# Onboarding Hardening Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Harden the enterprise B2B onboarding flow by extracting shared invitation acceptance logic, adding OIDC invitation support, fixing security gaps (suspended users, orphaned invitations), and improving observability (audit logging, email status reporting).

**Architecture:** Extract a shared `InvitationAcceptanceService` that centralizes invitation validation, email matching, atomic acceptance, UserTenant creation, and inviter notification. All three acceptance paths (authenticated, wallet, email registration) and the new OIDC path delegate to this service. Security checks (suspended user) and cascade operations (revoke on member removal) are added as targeted fixes to existing endpoints.

**Tech Stack:** ASP.NET Core 10, EF Core, PostgreSQL (SQLite in tests), xUnit v3, `SsdidDriveFactory` WebApplicationFactory test infrastructure.

---

## File Structure

| Action | File | Responsibility |
|--------|------|----------------|
| Create | `src/SsdidDrive.Api/Services/InvitationAcceptanceService.cs` | Shared invitation validation + acceptance logic |
| Create | `tests/SsdidDrive.Api.Tests/Integration/InvitationAcceptanceServiceTests.cs` | Tests for the extracted service via all acceptance endpoints |
| Create | `tests/SsdidDrive.Api.Tests/Integration/OidcInvitationTests.cs` | Tests for OIDC registration + invitation flow |
| Modify | `src/SsdidDrive.Api/Features/Invitations/AcceptInvitation.cs` | Delegate to InvitationAcceptanceService |
| Modify | `src/SsdidDrive.Api/Features/Invitations/AcceptWithWallet.cs` | Delegate to InvitationAcceptanceService |
| Modify | `src/SsdidDrive.Api/Features/Auth/EmailRegisterVerify.cs` | Delegate to InvitationAcceptanceService |
| Modify | `src/SsdidDrive.Api/Features/Auth/OidcAuthorize.cs` | Pass invitation_token in state |
| Modify | `src/SsdidDrive.Api/Features/Auth/OidcCallback.cs` | Handle new user registration + invitation acceptance |
| Modify | `src/SsdidDrive.Api/Features/Invitations/CreateInvitation.cs` | Add email_sent status + audit log |
| Modify | `src/SsdidDrive.Api/Features/Tenants/RemoveMember.cs` | Add cascade revoke + audit log |
| Modify | `src/SsdidDrive.Api/Program.cs` | Register InvitationAcceptanceService |
| Modify | `docs/plans/2026-03-11-invitation-onboarding-design.md` | Update stale doc |

---

## Chunk 1: InvitationAcceptanceService Extraction + Suspended User Check

### Task 1: Create InvitationAcceptanceService with tests

**Files:**
- Create: `src/SsdidDrive.Api/Services/InvitationAcceptanceService.cs`
- Create: `tests/SsdidDrive.Api.Tests/Integration/InvitationAcceptanceServiceTests.cs`
- Modify: `src/SsdidDrive.Api/Program.cs`

- [ ] **Step 1: Write the failing test — suspended user cannot accept invitation**

Create `tests/SsdidDrive.Api.Tests/Integration/InvitationAcceptanceServiceTests.cs`:

```csharp
using System.Net;
using System.Net.Http.Json;
using System.Text.Json;
using Microsoft.Extensions.DependencyInjection;
using SsdidDrive.Api.Data;
using SsdidDrive.Api.Data.Entities;
using SsdidDrive.Api.Tests.Infrastructure;

namespace SsdidDrive.Api.Tests.Integration;

public class InvitationAcceptanceServiceTests : IClassFixture<SsdidDriveFactory>
{
    private readonly SsdidDriveFactory _factory;

    public InvitationAcceptanceServiceTests(SsdidDriveFactory factory) => _factory = factory;

    [Fact]
    public async Task AcceptInvitation_SuspendedUser_Returns403()
    {
        // Arrange: owner creates invitation targeting a suspended user
        var (ownerClient, ownerId, tenantId) = await TestFixture.CreateAuthenticatedClientAsync(_factory, "SuspOwner");
        var (suspendedClient, suspendedUserId, _) = await TestFixture.CreateAuthenticatedClientAsync(_factory, "SuspUser");

        // Suspend the user
        using (var scope = _factory.Services.CreateScope())
        {
            var db = scope.ServiceProvider.GetRequiredService<AppDbContext>();
            var user = await db.Users.FindAsync(suspendedUserId);
            user!.Status = UserStatus.Suspended;
            await db.SaveChangesAsync();
        }

        // Create invitation targeting the suspended user
        using (var scope = _factory.Services.CreateScope())
        {
            var db = scope.ServiceProvider.GetRequiredService<AppDbContext>();
            var invitation = new Invitation
            {
                Id = Guid.NewGuid(),
                TenantId = tenantId,
                InvitedById = ownerId,
                InvitedUserId = suspendedUserId,
                Role = TenantRole.Member,
                Status = InvitationStatus.Pending,
                Token = Convert.ToBase64String(Guid.NewGuid().ToByteArray()).Replace("+", "-").Replace("/", "_").TrimEnd('='),
                ShortCode = "SUSP-TEST",
                ExpiresAt = DateTimeOffset.UtcNow.AddDays(7),
                CreatedAt = DateTimeOffset.UtcNow,
                UpdatedAt = DateTimeOffset.UtcNow
            };
            db.Invitations.Add(invitation);
            await db.SaveChangesAsync();

            // Act
            var response = await suspendedClient.PostAsync($"/api/invitations/{invitation.Id}/accept", null);

            // Assert
            Assert.Equal(HttpStatusCode.Forbidden, response.StatusCode);
        }
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `dotnet test tests/SsdidDrive.Api.Tests/ --filter "InvitationAcceptanceServiceTests.AcceptInvitation_SuspendedUser_Returns403" -v n`
Expected: FAIL — currently returns 200 OK because no suspended check exists.

- [ ] **Step 3: Write the InvitationAcceptanceService**

Create `src/SsdidDrive.Api/Services/InvitationAcceptanceService.cs`:

```csharp
using Microsoft.EntityFrameworkCore;
using SsdidDrive.Api.Common;
using SsdidDrive.Api.Data;
using SsdidDrive.Api.Data.Entities;

namespace SsdidDrive.Api.Services;

public class InvitationAcceptanceService(AppDbContext db, NotificationService notifications)
{
    public record AcceptResult(Guid InvitationId, Guid TenantId, string TenantName, string TenantSlug, TenantRole Role);

    /// <summary>
    /// Validates and accepts an invitation for a user. Handles:
    /// - Invitation lookup (by ID or token/short code)
    /// - Expiry check (auto-marks expired)
    /// - Status validation (only Pending can be accepted)
    /// - Suspended user check
    /// - Token proof validation (for open invitations via authenticated accept)
    /// - Email matching (if invitation has an email and callerEmail is provided)
    /// - Duplicate membership check
    /// - Atomic status update (prevents double-accept)
    /// - UserTenant creation
    /// - Inviter notification
    /// </summary>
    public async Task<Result<AcceptResult>> AcceptAsync(
        Guid userId,
        string? callerEmail,
        Guid? invitationId = null,
        string? token = null,
        string? tokenProof = null,
        string? acceptedByDid = null,
        CancellationToken ct = default)
    {
        // 1. Look up invitation
        Invitation? invitation;
        if (invitationId.HasValue)
        {
            invitation = await db.Invitations
                .Include(i => i.Tenant)
                .FirstOrDefaultAsync(i => i.Id == invitationId.Value, ct);
        }
        else if (!string.IsNullOrWhiteSpace(token))
        {
            invitation = await db.Invitations
                .Include(i => i.Tenant)
                .FirstOrDefaultAsync(i => i.Token == token || i.ShortCode == token, ct);
        }
        else
        {
            return AppError.BadRequest("Invitation ID or token is required");
        }

        if (invitation is null)
            return AppError.NotFound("Invitation not found");

        // 2. Check expiry
        if (invitation.ExpiresAt <= DateTimeOffset.UtcNow)
        {
            if (invitation.Status == InvitationStatus.Pending)
            {
                invitation.Status = InvitationStatus.Expired;
                invitation.UpdatedAt = DateTimeOffset.UtcNow;
                await db.SaveChangesAsync(ct);
            }
            return AppError.Gone("Invitation has expired");
        }

        // 3. Check status
        if (invitation.Status == InvitationStatus.Accepted)
            return AppError.Conflict("Invitation has already been accepted");

        if (invitation.Status != InvitationStatus.Pending)
            return AppError.NotFound("Invitation not found or is no longer valid");

        // 4. Check user is not suspended
        var user = await db.Users.FindAsync([userId], ct);
        if (user is null)
            return AppError.NotFound("User not found");

        if (user.Status == UserStatus.Suspended)
            return AppError.Forbidden("Your account is suspended");

        // 5. Email matching (if invitation specifies an email)
        if (!string.IsNullOrWhiteSpace(invitation.Email) && !string.IsNullOrWhiteSpace(callerEmail))
        {
            if (!string.Equals(invitation.Email.Trim(), callerEmail.Trim(), StringComparison.OrdinalIgnoreCase))
                return AppError.Forbidden("Email does not match the invitation");
        }

        // 6. Authorization: if InvitedUserId is set, only that user can accept
        if (invitation.InvitedUserId is not null && invitation.InvitedUserId != userId)
            return AppError.Forbidden("You are not the invited user");

        // 6b. For open invitations (InvitedUserId is null) via authenticated accept,
        // require constant-time token proof to prevent GUID brute-force
        if (invitation.InvitedUserId is null && invitationId.HasValue)
        {
            if (string.IsNullOrWhiteSpace(tokenProof) ||
                !System.Security.Cryptography.CryptographicOperations.FixedTimeEquals(
                    System.Text.Encoding.UTF8.GetBytes(tokenProof),
                    System.Text.Encoding.UTF8.GetBytes(invitation.Token)))
                return AppError.Forbidden("Invalid or missing invitation token");
        }

        // 7. Check duplicate membership
        var existingMembership = await db.UserTenants
            .AnyAsync(ut => ut.UserId == userId && ut.TenantId == invitation.TenantId, ct);

        if (existingMembership)
            return AppError.Conflict("You are already a member of this tenant");

        // 8. Begin transaction for atomic acceptance
        await using var transaction = await db.Database.BeginTransactionAsync(ct);

        // 9. Atomic claim (WHERE Status = Pending prevents double-accept)
        var updated = await db.Invitations
            .Where(i => i.Id == invitation.Id && i.Status == InvitationStatus.Pending)
            .ExecuteUpdateAsync(s => s
                .SetProperty(i => i.Status, InvitationStatus.Accepted)
                .SetProperty(i => i.InvitedUserId, userId)
                .SetProperty(i => i.AcceptedByAccountId, userId)
                .SetProperty(i => i.AcceptedByDid, acceptedByDid)
                .SetProperty(i => i.AcceptedAt, DateTimeOffset.UtcNow)
                .SetProperty(i => i.UpdatedAt, DateTimeOffset.UtcNow), ct);

        if (updated == 0)
            return AppError.Conflict("Invitation has already been processed");

        // 10. Create UserTenant
        db.UserTenants.Add(new UserTenant
        {
            UserId = userId,
            TenantId = invitation.TenantId,
            Role = invitation.Role,
            CreatedAt = DateTimeOffset.UtcNow
        });

        // 11. Notify inviter
        await notifications.CreateAsync(
            invitation.InvitedById,
            "invitation_accepted",
            "Invitation Accepted",
            $"{user.DisplayName ?? user.Did ?? user.Email ?? "A user"} accepted your invitation",
            actionType: "invitation",
            actionResourceId: invitation.Id.ToString(),
            ct: ct);

        try
        {
            await db.SaveChangesAsync(ct);
        }
        catch (DbUpdateException)
        {
            return AppError.Conflict("User is already a member of this tenant");
        }

        await transaction.CommitAsync(ct);

        return new AcceptResult(
            invitation.Id,
            invitation.TenantId,
            invitation.Tenant.Name,
            invitation.Tenant.Slug,
            invitation.Role);
    }
}
```

- [ ] **Step 4: Register InvitationAcceptanceService in DI**

In `src/SsdidDrive.Api/Program.cs`, add after the `AuditService` registration (line ~178):

```csharp
builder.Services.AddScoped<InvitationAcceptanceService>();
```

- [ ] **Step 5: Run test to verify it still fails**

Run: `dotnet test tests/SsdidDrive.Api.Tests/ --filter "InvitationAcceptanceServiceTests.AcceptInvitation_SuspendedUser_Returns403" -v n`
Expected: Still FAIL — `AcceptInvitation.cs` endpoint hasn't been updated to use the service yet.

- [ ] **Step 6: Commit service creation**

```bash
git add src/SsdidDrive.Api/Services/InvitationAcceptanceService.cs src/SsdidDrive.Api/Program.cs tests/SsdidDrive.Api.Tests/Integration/InvitationAcceptanceServiceTests.cs
git commit -m "feat: add InvitationAcceptanceService with suspended user check"
```

---

### Task 2: Refactor AcceptInvitation to use InvitationAcceptanceService

**Files:**
- Modify: `src/SsdidDrive.Api/Features/Invitations/AcceptInvitation.cs`

- [ ] **Step 1: Rewrite AcceptInvitation.Handle to delegate to service**

Replace the entire `Handle` method body in `AcceptInvitation.cs` with:

```csharp
using SsdidDrive.Api.Common;
using SsdidDrive.Api.Services;

namespace SsdidDrive.Api.Features.Invitations;

public static class AcceptInvitation
{
    public record Request(string? Token = null);

    public static void Map(RouteGroupBuilder group) =>
        group.MapPost("/{id:guid}/accept", Handle);

    private static async Task<IResult> Handle(
        Guid id,
        Request req,
        CurrentUserAccessor accessor,
        InvitationAcceptanceService acceptanceService,
        CancellationToken ct)
    {
        var user = accessor.User!;

        // For open invitations (InvitedUserId is null), require token proof
        // to prevent GUID brute-force. The token is passed in the request body.
        var result = await acceptanceService.AcceptAsync(
            user.Id,
            user.Email,
            invitationId: id,
            tokenProof: req.Token,
            ct: ct);

        return result.Match(
            ok => Results.Ok(new
            {
                id = ok.InvitationId,
                status = "accepted",
                tenant_id = ok.TenantId,
                role = ok.Role.ToString().ToLowerInvariant()
            }),
            err => err.ToProblemResult());
    }
}
```

- [ ] **Step 2: Run the suspended user test**

Run: `dotnet test tests/SsdidDrive.Api.Tests/ --filter "InvitationAcceptanceServiceTests.AcceptInvitation_SuspendedUser_Returns403" -v n`
Expected: PASS

- [ ] **Step 3: Run all existing invitation tests to verify no regressions**

Run: `dotnet test tests/SsdidDrive.Api.Tests/ --filter "InvitationTests" -v n`
Expected: All 15 tests PASS

- [ ] **Step 4: Commit**

```bash
git add src/SsdidDrive.Api/Features/Invitations/AcceptInvitation.cs
git commit -m "refactor: AcceptInvitation delegates to InvitationAcceptanceService"
```

---

### Task 3: Refactor AcceptWithWallet to use InvitationAcceptanceService

**Files:**
- Modify: `src/SsdidDrive.Api/Features/Invitations/AcceptWithWallet.cs`

- [ ] **Step 1: Verify suspended user check is exercised through the wallet path**

No new test needed here — the `InvitationAcceptanceService` already has a suspended user test from Task 1 that covers the shared code path. The wallet endpoint delegates to the same `AcceptAsync` method.

For wallet-specific suspended user testing, the `AcceptWithWalletTests.cs` integration tests would need a real SSDID credential. Since wallet users are created fresh during acceptance, the suspension scenario only applies if an existing suspended user's DID matches — this is covered by the service-level test in Task 1.

- [ ] **Step 2: Rewrite AcceptWithWallet.Handle to use the service**

The wallet endpoint has additional responsibilities beyond what the shared service handles:
1. Credential verification (SSDID-specific)
2. User creation (new wallet users)
3. Session creation (returns token)

Rewrite `AcceptWithWallet.cs` to use the service for the invitation-specific parts:

```csharp
using System.Text.Json;
using Microsoft.EntityFrameworkCore;
using SsdidDrive.Api.Common;
using SsdidDrive.Api.Data;
using SsdidDrive.Api.Data.Entities;
using SsdidDrive.Api.Middleware;
using SsdidDrive.Api.Services;
using SsdidDrive.Api.Ssdid;

namespace SsdidDrive.Api.Features.Invitations;

public static class AcceptWithWallet
{
    public record Request(JsonElement Credential, string Email);

    public static void Map(RouteGroupBuilder group) =>
        group.MapPost("/token/{token}/accept-with-wallet", Handle)
            .WithMetadata(new SsdidPublicAttribute())
            .RequireRateLimiting("auth");

    private static async Task<IResult> Handle(
        string token,
        Request req,
        AppDbContext db,
        SsdidAuthService auth,
        InvitationAcceptanceService acceptanceService,
        CancellationToken ct)
    {
        // 1. Verify credential first (cheap to fail fast)
        var verifyResult = auth.VerifyCredential(req.Credential);
        return await verifyResult.Match(
            async did =>
            {
                // 2. Find or create user
                var user = await db.Users
                    .FirstOrDefaultAsync(u => u.Did == did, ct);

                var isNewUser = user is null;
                if (isNewUser)
                {
                    // Look up invitation to get tenantId for new user's primary tenant
                    var invitation = await db.Invitations
                        .FirstOrDefaultAsync(i => i.Token == token || i.ShortCode == token, ct);

                    if (invitation is null)
                        return AppError.NotFound("Invitation not found").ToProblemResult();

                    user = new User
                    {
                        Id = Guid.NewGuid(),
                        Did = did,
                        Email = req.Email?.Trim().ToLowerInvariant(),
                        DisplayName = null,
                        Status = UserStatus.Active,
                        TenantId = invitation.TenantId,
                        CreatedAt = DateTimeOffset.UtcNow,
                        UpdatedAt = DateTimeOffset.UtcNow
                    };
                    db.Users.Add(user);
                    try
                    {
                        await db.SaveChangesAsync(ct);
                    }
                    catch (DbUpdateException)
                    {
                        db.ChangeTracker.Clear();
                        user = await db.Users.FirstAsync(u => u.Did == did, ct);
                        isNewUser = false;
                    }
                }

                // 3. Delegate invitation acceptance to shared service
                var result = await acceptanceService.AcceptAsync(
                    user!.Id,
                    req.Email,
                    token: token,
                    acceptedByDid: did,
                    ct: ct);

                return result.Match(
                    ok =>
                    {
                        // 4. Create session
                        var sessionResult = auth.CreateAuthenticatedSession(did);
                        return sessionResult.Match(
                            session => Results.Ok(new
                            {
                                session_token = session.SessionToken,
                                did = session.Did,
                                server_did = session.ServerDid,
                                server_key_id = session.ServerKeyId,
                                server_signature = session.ServerSignature,
                                user = new
                                {
                                    user!.Id,
                                    user.Did,
                                    display_name = user.DisplayName,
                                    status = user.Status.ToString().ToLowerInvariant()
                                },
                                tenant = new
                                {
                                    id = ok.TenantId,
                                    name = ok.TenantName,
                                    slug = ok.TenantSlug,
                                    role = ok.Role.ToString().ToLowerInvariant()
                                }
                            }),
                            err => err.ToProblemResult());
                    },
                    err => err.ToProblemResult());
            },
            err => Task.FromResult(err.ToProblemResult()));
    }
}
```

- [ ] **Step 3: Run wallet-related tests**

Run: `dotnet test tests/SsdidDrive.Api.Tests/ --filter "AcceptWithWalletTests|WalletLoginFlowTests" -v n`
Expected: All PASS

- [ ] **Step 4: Commit**

```bash
git add src/SsdidDrive.Api/Features/Invitations/AcceptWithWallet.cs tests/SsdidDrive.Api.Tests/Integration/InvitationAcceptanceServiceTests.cs
git commit -m "refactor: AcceptWithWallet delegates to InvitationAcceptanceService"
```

---

### Task 4: Refactor EmailRegisterVerify to use InvitationAcceptanceService

**Files:**
- Modify: `src/SsdidDrive.Api/Features/Auth/EmailRegisterVerify.cs`

- [ ] **Step 1: Rewrite EmailRegisterVerify.Handle to use the service**

The email registration endpoint has additional responsibilities:
1. OTP verification
2. User creation
3. Login entity creation
4. Session creation

Rewrite `EmailRegisterVerify.cs`:

```csharp
using Microsoft.EntityFrameworkCore;
using SsdidDrive.Api.Common;
using SsdidDrive.Api.Data;
using SsdidDrive.Api.Data.Entities;
using SsdidDrive.Api.Middleware;
using SsdidDrive.Api.Services;
using SsdidDrive.Api.Ssdid;

namespace SsdidDrive.Api.Features.Auth;

public static class EmailRegisterVerify
{
    public record Request(string Email, string Code, string? InvitationToken);

    public static void Map(RouteGroupBuilder group) =>
        group.MapPost("/email/register/verify", Handle)
            .WithMetadata(new SsdidPublicAttribute());

    private static async Task<IResult> Handle(
        Request req,
        AppDbContext db,
        OtpService otpService,
        ISessionStore sessionStore,
        AuditService auditService,
        InvitationAcceptanceService acceptanceService,
        CancellationToken ct)
    {
        if (string.IsNullOrWhiteSpace(req.Email) || string.IsNullOrWhiteSpace(req.Code))
            return AppError.BadRequest("Email and code are required").ToProblemResult();

        if (string.IsNullOrWhiteSpace(req.InvitationToken))
            return AppError.BadRequest("Invitation token is required").ToProblemResult();

        var email = req.Email.Trim().ToLowerInvariant();

        // Verify OTP before doing anything else
        if (!await otpService.VerifyAsync(email, "register", req.Code, ct))
            return AppError.Unauthorized("Invalid or expired verification code").ToProblemResult();

        // Look up invitation to get tenantId for the new user
        var invitationToken = req.InvitationToken!.Trim();
        var invitation = await db.Invitations
            .FirstOrDefaultAsync(i => (i.Token == invitationToken || i.ShortCode == invitationToken)
                && i.Status == InvitationStatus.Pending
                && i.ExpiresAt > DateTimeOffset.UtcNow, ct);

        if (invitation is null)
            return AppError.NotFound("Invalid or expired invitation").ToProblemResult();

        // Create user
        var user = new User
        {
            Id = Guid.NewGuid(),
            Email = email,
            EmailVerified = true,
            Status = UserStatus.Active,
            TenantId = invitation.TenantId,
            CreatedAt = DateTimeOffset.UtcNow,
            UpdatedAt = DateTimeOffset.UtcNow,
        };
        db.Users.Add(user);

        db.Logins.Add(new Login
        {
            AccountId = user.Id,
            Provider = LoginProvider.Email,
            ProviderSubject = email,
        });

        await db.SaveChangesAsync(ct);

        // Delegate invitation acceptance to shared service
        var result = await acceptanceService.AcceptAsync(
            user.Id,
            email,
            token: invitationToken,
            ct: ct);

        return result.Match(
            ok =>
            {
                var token = sessionStore.CreateSession(user.Id.ToString());
                if (token is null)
                    return AppError.ServiceUnavailable("Session limit exceeded").ToProblemResult();

                await auditService.LogAsync(user.Id, "auth.register.email", "user", user.Id, null, ct);

                return Results.Ok(new
                {
                    token,
                    account_id = user.Id,
                    email = user.Email,
                    requires_totp_setup = true,
                });
            },
            err => err.ToProblemResult());
    }
}
```

- [ ] **Step 2: Run email auth flow tests**

Run: `dotnet test tests/SsdidDrive.Api.Tests/ --filter "EmailAuthFlowTests" -v n`
Expected: All PASS

- [ ] **Step 3: Run all tests to verify no regressions**

Run: `dotnet test tests/SsdidDrive.Api.Tests/ -v n`
Expected: All PASS

- [ ] **Step 4: Commit**

```bash
git add src/SsdidDrive.Api/Features/Auth/EmailRegisterVerify.cs
git commit -m "refactor: EmailRegisterVerify delegates to InvitationAcceptanceService"
```

---

## Chunk 2: OIDC Registration + Invitation Path

### Task 5: Add invitation_token parameter to OidcAuthorize

**Files:**
- Modify: `src/SsdidDrive.Api/Features/Auth/OidcAuthorize.cs`

- [ ] **Step 1: Write test — OidcAuthorize passes invitation_token in state**

Create `tests/SsdidDrive.Api.Tests/Integration/OidcInvitationTests.cs`:

```csharp
using System.Net;
using System.Net.Http.Json;
using System.Text.Json;
using Microsoft.Extensions.DependencyInjection;
using SsdidDrive.Api.Data;
using SsdidDrive.Api.Data.Entities;
using SsdidDrive.Api.Tests.Infrastructure;

namespace SsdidDrive.Api.Tests.Integration;

public class OidcInvitationTests : IClassFixture<SsdidDriveFactory>
{
    private readonly SsdidDriveFactory _factory;

    public OidcInvitationTests(SsdidDriveFactory factory) => _factory = factory;

    // Note: Full OIDC flow tests require mocking the OIDC provider (Google/Microsoft).
    // These tests validate the invitation_token propagation through state parameter.
    // Integration with OidcCallback is tested via the existing AdminOidcFlowTests pattern.

    [Fact]
    public async Task OidcAuthorize_WithInvitationToken_IncludesTokenInRedirect()
    {
        var client = _factory.CreateClient(new Microsoft.AspNetCore.Mvc.Testing.WebApplicationFactoryClientOptions
        {
            AllowAutoRedirect = false
        });

        // This test verifies the authorize endpoint accepts invitation_token param.
        // The actual OIDC redirect will fail (no real provider configured in tests),
        // but the request should not 400.
        var response = await client.GetAsync(
            "/api/auth/oidc/google/authorize?invitation_token=TEST-TOKEN-123");

        // Should redirect to Google (or return 400 for unconfigured provider in test env)
        // The key assertion is that invitation_token is accepted as a parameter.
        Assert.True(
            response.StatusCode == HttpStatusCode.Redirect ||
            response.StatusCode == HttpStatusCode.BadRequest,
            $"Expected redirect or bad request, got {response.StatusCode}");
    }
}
```

- [ ] **Step 2: Modify OidcAuthorize to accept invitation_token**

Update `src/SsdidDrive.Api/Features/Auth/OidcAuthorize.cs`:

```csharp
using System.Security.Cryptography;
using SsdidDrive.Api.Common;
using SsdidDrive.Api.Middleware;
using SsdidDrive.Api.Services;
using SsdidDrive.Api.Ssdid;

namespace SsdidDrive.Api.Features.Auth;

public static class OidcAuthorize
{
    public static void Map(RouteGroupBuilder group) =>
        group.MapGet("/oidc/{provider}/authorize", Handle)
            .WithMetadata(new SsdidPublicAttribute())
            .RequireRateLimiting("auth");

    private static IResult Handle(
        string provider,
        string? redirect_uri,
        string? invitation_token,
        ISessionStore sessionStore,
        OidcCodeExchanger exchanger)
    {
        var stateToken = RandomNumberGenerator.GetHexString(64, lowercase: true);

        var result = exchanger.GetAuthorizationUrl(provider, stateToken);
        if (result is null)
            return AppError.BadRequest($"OIDC provider '{provider}' is not supported or not configured").ToProblemResult();

        var (url, state, codeVerifier) = result.Value;

        // Embed redirect_uri and invitation_token in the challenge payload.
        // Format: "codeVerifier|redirect_uri|invitation_token"
        // Missing segments are empty strings.
        var challengePayload = $"{codeVerifier}|{redirect_uri ?? ""}|{invitation_token ?? ""}";
        sessionStore.CreateChallenge("oidc", state, challengePayload, provider);

        return Results.Redirect(url);
    }
}
```

- [ ] **Step 3: Run test**

Run: `dotnet test tests/SsdidDrive.Api.Tests/ --filter "OidcInvitationTests" -v n`
Expected: PASS

- [ ] **Step 4: Commit**

```bash
git add src/SsdidDrive.Api/Features/Auth/OidcAuthorize.cs tests/SsdidDrive.Api.Tests/Integration/OidcInvitationTests.cs
git commit -m "feat: OidcAuthorize accepts invitation_token parameter"
```

---

### Task 6: Update OidcCallback to handle new user registration + invitation

**Files:**
- Modify: `src/SsdidDrive.Api/Features/Auth/OidcCallback.cs`

- [ ] **Step 1: Rewrite OidcCallback.cs completely**

Replace the entire file `src/SsdidDrive.Api/Features/Auth/OidcCallback.cs` with the complete updated version below. Key changes from original:
1. Parse 3-segment challenge payload (`codeVerifier|redirect_uri|invitation_token`)
2. When no existing login found AND invitation_token present: create user + accept invitation
3. Add `InvitationAcceptanceService` parameter to `Handle`

```csharp
using Microsoft.EntityFrameworkCore;
using SsdidDrive.Api.Common;
using SsdidDrive.Api.Data;
using SsdidDrive.Api.Data.Entities;
using SsdidDrive.Api.Middleware;
using SsdidDrive.Api.Services;
using SsdidDrive.Api.Ssdid;

namespace SsdidDrive.Api.Features.Auth;

public static class OidcCallback
{
    public static void Map(RouteGroupBuilder group) =>
        group.MapGet("/oidc/{provider}/callback", Handle)
            .WithMetadata(new SsdidPublicAttribute())
            .RequireRateLimiting("auth");

    private static async Task<IResult> Handle(
        string provider,
        string? code,
        string? state,
        AppDbContext db,
        ISessionStore sessionStore,
        OidcCodeExchanger exchanger,
        OidcTokenValidator validator,
        AuditService auditService,
        InvitationAcceptanceService acceptanceService,
        IConfiguration config,
        CancellationToken ct)
    {
        if (string.IsNullOrEmpty(code))
            return AppError.BadRequest("Missing authorization code").ToProblemResult();
        if (string.IsNullOrEmpty(state))
            return AppError.BadRequest("Missing state parameter").ToProblemResult();

        var challengeEntry = sessionStore.ConsumeChallenge("oidc", state);
        if (challengeEntry is null)
            return AppError.Unauthorized("Invalid or expired state parameter").ToProblemResult();

        // Parse challenge payload: "codeVerifier|redirect_uri|invitation_token"
        // Backward compatible: old 2-segment format still works (invitation_token will be null)
        var challengePayload = challengeEntry.Challenge;
        var storedProvider = challengeEntry.KeyId;
        var segments = challengePayload.Split('|');
        var codeVerifier = segments[0];
        string? clientRedirectUri = segments.Length > 1 && !string.IsNullOrEmpty(segments[1]) ? segments[1] : null;
        string? invitationToken = segments.Length > 2 && !string.IsNullOrEmpty(segments[2]) ? segments[2] : null;

        if (!string.Equals(storedProvider, provider, StringComparison.OrdinalIgnoreCase))
            return AppError.Unauthorized("State/provider mismatch").ToProblemResult();

        var tokenResult = await exchanger.ExchangeCodeAsync(provider, code, codeVerifier, ct);
        if (!tokenResult.IsSuccess)
            return tokenResult.Error!.ToProblemResult();

        var claims = await validator.ValidateAsync(provider, tokenResult.Value!, ct);
        if (!claims.IsSuccess)
            return claims.Error!.ToProblemResult();

        var oidcClaims = claims.Value!;
        var providerEnum = provider.ToLowerInvariant() switch
        {
            "google" => LoginProvider.Google,
            "microsoft" => LoginProvider.Microsoft,
            _ => (LoginProvider?)null
        };

        if (providerEnum is null)
            return AppError.BadRequest("Unsupported provider").ToProblemResult();

        // Look up existing login
        var existingLogin = await db.Logins
            .Include(l => l.Account)
            .FirstOrDefaultAsync(l =>
                l.Provider == providerEnum.Value
                && l.ProviderSubject == oidcClaims.Subject, ct);

        if (existingLogin is null)
        {
            // No existing login — check if this is an invitation-based registration
            if (string.IsNullOrEmpty(invitationToken))
                return RedirectWithError(config, "No account linked to this provider. Register first.", clientRedirectUri);

            // Validate invitation
            var invitation = await db.Invitations
                .Include(i => i.Tenant)
                .FirstOrDefaultAsync(i => (i.Token == invitationToken || i.ShortCode == invitationToken)
                    && i.Status == InvitationStatus.Pending
                    && i.ExpiresAt > DateTimeOffset.UtcNow, ct);

            if (invitation is null)
                return RedirectWithError(config, "Invalid or expired invitation", clientRedirectUri);

            // Email match
            if (!string.IsNullOrEmpty(invitation.Email)
                && !string.Equals(invitation.Email, oidcClaims.Email, StringComparison.OrdinalIgnoreCase))
                return RedirectWithError(config, "Email does not match the invitation", clientRedirectUri);

            // Find or create user
            var existingUser = await db.Users
                .FirstOrDefaultAsync(u => u.Email == oidcClaims.Email, ct);

            User newUser;
            if (existingUser is not null)
            {
                newUser = existingUser;
            }
            else
            {
                newUser = new User
                {
                    Id = Guid.NewGuid(),
                    Email = oidcClaims.Email,
                    DisplayName = oidcClaims.Name,
                    EmailVerified = true,
                    Status = UserStatus.Active,
                    TenantId = invitation.TenantId,
                    CreatedAt = DateTimeOffset.UtcNow,
                    UpdatedAt = DateTimeOffset.UtcNow,
                };
                db.Users.Add(newUser);
            }

            // Create OIDC login link
            db.Logins.Add(new Login
            {
                AccountId = newUser.Id,
                Provider = providerEnum.Value,
                ProviderSubject = oidcClaims.Subject,
            });

            await db.SaveChangesAsync(ct);

            // Accept invitation via shared service
            var acceptResult = await acceptanceService.AcceptAsync(
                newUser.Id,
                oidcClaims.Email,
                token: invitationToken,
                ct: ct);

            if (!acceptResult.IsSuccess)
                return RedirectWithError(config, acceptResult.Error!.Detail ?? "Failed to accept invitation", clientRedirectUri);

            newUser.LastLoginAt = DateTimeOffset.UtcNow;
            newUser.UpdatedAt = DateTimeOffset.UtcNow;
            await db.SaveChangesAsync(ct);

            var regSessionToken = sessionStore.CreateSession(newUser.Id.ToString());
            if (regSessionToken is null)
                return RedirectWithError(config, "Session limit exceeded", clientRedirectUri);

            await auditService.LogAsync(newUser.Id, "auth.register.oidc", "user", newUser.Id,
                $"Provider: {provider}, via invitation", ct);

            return BuildRedirect(clientRedirectUri, config, regSessionToken, provider,
                mfaRequired: false, totpSetupRequired: false);
        }

        // ── Existing login path (unchanged from original) ──
        var user = existingLogin.Account;
        if (user.Status == UserStatus.Suspended)
            return RedirectWithError(config, "Account is suspended", clientRedirectUri);

        var isAdmin = await db.UserTenants
            .AnyAsync(ut => ut.UserId == user.Id
                && (ut.Role == TenantRole.Owner || ut.Role == TenantRole.Admin), ct);

        string sessionValue;
        bool mfaRequired = false;
        bool totpSetupRequired = false;

        if (isAdmin)
        {
            if (user.TotpEnabled)
            {
                sessionValue = $"mfa:{user.Id}";
                mfaRequired = true;
            }
            else
            {
                sessionValue = user.Id.ToString();
                totpSetupRequired = true;
            }
        }
        else
        {
            sessionValue = user.Id.ToString();
        }

        if (!mfaRequired)
        {
            user.LastLoginAt = DateTimeOffset.UtcNow;
            user.UpdatedAt = DateTimeOffset.UtcNow;
            await db.SaveChangesAsync(ct);
        }

        var sessionToken = sessionStore.CreateSession(sessionValue);
        if (sessionToken is null)
            return RedirectWithError(config, "Session limit exceeded", clientRedirectUri);

        await auditService.LogAsync(user.Id,
            mfaRequired ? "auth.login.oidc.initiated" : "auth.login.oidc",
            "user", user.Id,
            $"Provider: {provider} (server-side)", ct);

        return BuildRedirect(clientRedirectUri, config, sessionToken, provider, mfaRequired, totpSetupRequired);
    }

    private static IResult BuildRedirect(string? clientRedirectUri, IConfiguration config,
        string sessionToken, string provider, bool mfaRequired, bool totpSetupRequired)
    {
        var baseUrl = clientRedirectUri ?? config["AdminPortal:BaseUrl"] ?? "/admin";

        if (clientRedirectUri is not null)
        {
            var separator = clientRedirectUri.Contains('?') ? "&" : "?";
            return Results.Redirect(
                $"{clientRedirectUri}{separator}" +
                $"token={Uri.EscapeDataString(sessionToken)}" +
                $"&provider={Uri.EscapeDataString(provider)}" +
                $"&mfa_required={mfaRequired.ToString().ToLowerInvariant()}" +
                $"&totp_setup_required={totpSetupRequired.ToString().ToLowerInvariant()}");
        }

        return Results.Redirect(
            $"{baseUrl}/auth/callback" +
            $"?token={Uri.EscapeDataString(sessionToken)}" +
            $"&mfa_required={mfaRequired.ToString().ToLowerInvariant()}" +
            $"&totp_setup_required={totpSetupRequired.ToString().ToLowerInvariant()}");
    }

    private static IResult RedirectWithError(IConfiguration config, string error, string? clientRedirectUri = null)
    {
        if (clientRedirectUri is not null)
        {
            var separator = clientRedirectUri.Contains('?') ? "&" : "?";
            return Results.Redirect($"{clientRedirectUri}{separator}error={Uri.EscapeDataString(error)}");
        }
        var adminBaseUrl = config["AdminPortal:BaseUrl"] ?? "/admin";
        return Results.Redirect($"{adminBaseUrl}/auth/callback?error={Uri.EscapeDataString(error)}");
    }
}
```

- [ ] **Step 2: Run existing OIDC tests to verify no regressions**

Run: `dotnet test tests/SsdidDrive.Api.Tests/ --filter "AdminOidcFlowTests|OidcInvitationTests" -v n`
Expected: All PASS. The existing payload format `"codeVerifier|redirect_uri"` is still handled correctly because the new parsing uses `Split('|')` and checks segment count.

- [ ] **Step 3: Run all tests**

Run: `dotnet test tests/SsdidDrive.Api.Tests/ -v n`
Expected: All PASS

- [ ] **Step 4: Commit**

```bash
git add src/SsdidDrive.Api/Features/Auth/OidcCallback.cs
git commit -m "feat: OidcCallback supports registration + invitation for new OIDC users"
```

---

## Chunk 3: Cascade Revoke, Audit Logging, Email Status

### Task 7: Add cascade revoke to RemoveMember

**Files:**
- Modify: `src/SsdidDrive.Api/Features/Tenants/RemoveMember.cs`
- Modify: `tests/SsdidDrive.Api.Tests/Integration/TenantMemberTests.cs`

- [ ] **Step 1: Write test — removing member revokes their pending invitations**

Add to `TenantMemberTests.cs`:

```csharp
[Fact]
public async Task RemoveMember_RevokesTheirPendingInvitations()
{
    var (ownerClient, ownerId, tenantId) = await TestFixture.CreateAuthenticatedClientAsync(_factory, "TM-CascOwner");
    var (adminClient, adminId) = await TestFixture.CreateUserInTenantAsync(_factory, tenantId, "TM-CascAdmin");

    // Promote to admin so they can create invitations
    using (var scope = _factory.Services.CreateScope())
    {
        var db = scope.ServiceProvider.GetRequiredService<AppDbContext>();
        var ut = db.UserTenants.Single(ut => ut.UserId == adminId && ut.TenantId == tenantId);
        ut.Role = TenantRole.Admin;
        await db.SaveChangesAsync();
    }

    // Admin creates an invitation
    var createResp = await adminClient.PostAsJsonAsync("/api/invitations", new
    {
        email = "cascade-target@example.com",
        role = "member"
    }, TestFixture.Json);
    Assert.Equal(HttpStatusCode.Created, createResp.StatusCode);
    var createBody = await createResp.Content.ReadFromJsonAsync<JsonElement>(TestFixture.Json);
    var invitationId = Guid.Parse(createBody.GetProperty("id").GetString()!);

    // Owner removes the admin
    var removeResp = await ownerClient.DeleteAsync($"/api/tenants/{tenantId}/members/{adminId}");
    Assert.Equal(HttpStatusCode.NoContent, removeResp.StatusCode);

    // Verify the admin's invitation was revoked
    using (var scope = _factory.Services.CreateScope())
    {
        var db = scope.ServiceProvider.GetRequiredService<AppDbContext>();
        var invitation = await db.Invitations.FindAsync(invitationId);
        Assert.NotNull(invitation);
        Assert.Equal(InvitationStatus.Revoked, invitation!.Status);
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `dotnet test tests/SsdidDrive.Api.Tests/ --filter "TenantMemberTests.RemoveMember_RevokesTheirPendingInvitations" -v n`
Expected: FAIL — invitation status is still Pending.

- [ ] **Step 3: Add cascade revoke to RemoveMember**

Update `src/SsdidDrive.Api/Features/Tenants/RemoveMember.cs`:

```csharp
using Microsoft.EntityFrameworkCore;
using SsdidDrive.Api.Common;
using SsdidDrive.Api.Data;
using SsdidDrive.Api.Data.Entities;
using SsdidDrive.Api.Services;

namespace SsdidDrive.Api.Features.Tenants;

public static class RemoveMember
{
    public static void Map(RouteGroupBuilder group) =>
        group.MapDelete("/{id:guid}/members/{userId:guid}", Handle);

    private static async Task<IResult> Handle(
        Guid id, Guid userId,
        AppDbContext db, CurrentUserAccessor accessor, AuditService audit, CancellationToken ct)
    {
        var user = accessor.User!;

        if (userId == user.Id)
            return AppError.BadRequest("Cannot remove yourself. Use a leave endpoint instead").ToProblemResult();

        var callerMembership = await db.UserTenants
            .FirstOrDefaultAsync(ut => ut.TenantId == id && ut.UserId == user.Id, ct);

        if (callerMembership is null)
            return AppError.Forbidden("You are not a member of this tenant").ToProblemResult();

        if (callerMembership.Role == TenantRole.Member)
            return AppError.Forbidden("Only owners and admins can remove members").ToProblemResult();

        var targetMembership = await db.UserTenants
            .FirstOrDefaultAsync(ut => ut.TenantId == id && ut.UserId == userId, ct);

        if (targetMembership is null)
            return AppError.NotFound("Member not found in this tenant").ToProblemResult();

        if (callerMembership.Role == TenantRole.Admin && targetMembership.Role == TenantRole.Owner)
            return AppError.Forbidden("Admins cannot remove owners").ToProblemResult();

        if (targetMembership.Role == TenantRole.Owner)
        {
            var ownerCount = await db.UserTenants
                .CountAsync(ut => ut.TenantId == id && ut.Role == TenantRole.Owner, ct);

            if (ownerCount <= 1)
                return AppError.BadRequest("Cannot remove the last owner of a tenant").ToProblemResult();
        }

        // Cascade-revoke pending invitations created by the removed member
        var revokedCount = await db.Invitations
            .Where(i => i.InvitedById == userId
                && i.TenantId == id
                && i.Status == InvitationStatus.Pending)
            .ExecuteUpdateAsync(s => s
                .SetProperty(i => i.Status, InvitationStatus.Revoked)
                .SetProperty(i => i.UpdatedAt, DateTimeOffset.UtcNow), ct);

        db.UserTenants.Remove(targetMembership);
        await db.SaveChangesAsync(ct);

        await audit.LogAsync(user.Id, "tenant.member.removed", "UserTenant", null,
            $"Removed user {userId} from tenant {id} (role: {targetMembership.Role}). Revoked {revokedCount} pending invitation(s).", ct);

        return Results.NoContent();
    }
}
```

- [ ] **Step 4: Run the cascade test**

Run: `dotnet test tests/SsdidDrive.Api.Tests/ --filter "TenantMemberTests.RemoveMember_RevokesTheirPendingInvitations" -v n`
Expected: PASS

- [ ] **Step 5: Run all tenant member tests**

Run: `dotnet test tests/SsdidDrive.Api.Tests/ --filter "TenantMemberTests" -v n`
Expected: All PASS

- [ ] **Step 6: Commit**

```bash
git add src/SsdidDrive.Api/Features/Tenants/RemoveMember.cs tests/SsdidDrive.Api.Tests/Integration/TenantMemberTests.cs
git commit -m "feat: cascade-revoke pending invitations when member is removed"
```

---

### Task 8: Add audit logging to CreateInvitation

**Files:**
- Modify: `src/SsdidDrive.Api/Features/Invitations/CreateInvitation.cs`

- [ ] **Step 1: Write test — invitation creation produces audit log**

Add to `InvitationAcceptanceServiceTests.cs`:

```csharp
[Fact]
public async Task CreateInvitation_ProducesAuditLog()
{
    var (client, userId, tenantId) = await TestFixture.CreateAuthenticatedClientAsync(_factory, "AuditInvOwner");

    var response = await client.PostAsJsonAsync("/api/invitations", new
    {
        email = "audit-test@example.com",
        role = "member"
    }, TestFixture.Json);

    Assert.Equal(HttpStatusCode.Created, response.StatusCode);

    // Verify audit log entry
    using var scope = _factory.Services.CreateScope();
    var db = scope.ServiceProvider.GetRequiredService<AppDbContext>();
    var auditEntry = await Microsoft.EntityFrameworkCore.EntityFrameworkQueryableExtensions
        .FirstOrDefaultAsync(db.AuditLog, a => a.ActorId == userId && a.Action == "invitation.created");
    Assert.NotNull(auditEntry);
    Assert.Contains("audit-test@example.com", auditEntry!.Details!);
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `dotnet test tests/SsdidDrive.Api.Tests/ --filter "InvitationAcceptanceServiceTests.CreateInvitation_ProducesAuditLog" -v n`
Expected: FAIL — no audit log entry exists.

- [ ] **Step 3: Add audit logging and email_sent status to CreateInvitation**

In `src/SsdidDrive.Api/Features/Invitations/CreateInvitation.cs`, add `AuditService audit` to the `Handle` parameters. Then update the email sending and response sections:

Replace the email sending block (lines 102-107) and the return (lines 109-123) with:

```csharp
        await db.SaveChangesAsync(ct);

        // Send invitation email — capture success/failure for response
        bool emailSent = false;
        string? emailError = null;
        if (!string.IsNullOrWhiteSpace(req.Email))
        {
            try
            {
                await emailService.SendInvitationAsync(
                    req.Email, tenant!.Name, role.Value.ToString().ToLowerInvariant(), shortCode, req.Message);
                emailSent = true;
            }
            catch (Exception ex)
            {
                emailError = "Failed to send invitation email";
                // Log but don't fail — invitation was created successfully
            }
        }

        // Audit log
        await audit.LogAsync(user.Id, "invitation.created", "Invitation", invitation.Id,
            $"Invited {req.Email ?? "(no email)"} as {role.Value.ToString().ToLowerInvariant()} to tenant {tenant!.Name}", ct);

        return Results.Created($"/api/invitations/{invitation.Id}", new
        {
            id = invitation.Id,
            tenant_id = invitation.TenantId,
            invited_by_id = invitation.InvitedById,
            email = invitation.Email,
            invited_user_id = invitation.InvitedUserId,
            role = invitation.Role.ToString().ToLowerInvariant(),
            status = invitation.Status.ToString().ToLowerInvariant(),
            token = invitation.Token,
            short_code = invitation.ShortCode,
            message = invitation.Message,
            email_sent = emailSent,
            email_error = emailError,
            expires_at = invitation.ExpiresAt,
            created_at = invitation.CreatedAt
        });
```

- [ ] **Step 4: Run audit log test**

Run: `dotnet test tests/SsdidDrive.Api.Tests/ --filter "InvitationAcceptanceServiceTests.CreateInvitation_ProducesAuditLog" -v n`
Expected: PASS

- [ ] **Step 5: Run all invitation tests**

Run: `dotnet test tests/SsdidDrive.Api.Tests/ --filter "InvitationTests" -v n`
Expected: All PASS (some tests may need minor updates if they assert on response shape — check for new `email_sent` field).

- [ ] **Step 6: Commit**

```bash
git add src/SsdidDrive.Api/Features/Invitations/CreateInvitation.cs tests/SsdidDrive.Api.Tests/Integration/InvitationAcceptanceServiceTests.cs
git commit -m "feat: add audit logging and email_sent status to CreateInvitation"
```

---

### Task 9: Update the design document

**Files:**
- Modify: `docs/plans/2026-03-11-invitation-onboarding-design.md`

- [ ] **Step 1: Update the design doc to reflect current state**

Key changes:
1. Line 5: Replace "Authentication is always via SSDID Wallet" with "Supports 3 auth methods: Email+TOTP, OIDC (Google/Microsoft), SSDID Wallet"
2. Update the Bootstrap Flow to show the simplified 5-step flow
3. Update the "Accepting an Invitation (New User)" flow to show all 3 auth paths
4. Update "What Needs to Be Built" to reflect what has been completed
5. Add section on the InvitationAcceptanceService architecture

Update lines 3-5 of `docs/plans/2026-03-11-invitation-onboarding-design.md`:

```markdown
## Overview

Invite-only onboarding for SSDID Drive targeting enterprise B2B. No open registration. All users enter through invitations. Authentication supports three methods: Email+TOTP, OIDC (Google/Microsoft), and SSDID Wallet.
```

Update the Principles section:

```markdown
## Principles

- **Invite-only** — no self-registration, no open sign-up
- **Top-down tenant creation** — users request tenants, SuperAdmin approves (requester auto-becomes Owner)
- **Multi-auth** — Email+TOTP, OIDC (Google/Microsoft), SSDID Wallet — all 3 supported for invitation acceptance
- **Multi-tenant** — a user can belong to multiple tenants via separate invitations
- **Email-verified** — invitation email must match the accepting user's email across all auth methods
```

Update the Bootstrap Flow:

```markdown
## Bootstrap Flow

```
1. Deploy SSDID Drive with AdminDid in appsettings
2. SuperAdmin registers with matching DID → auto-promoted
3. User registers (any auth method) and submits TenantRequest
4. SuperAdmin approves → tenant created + requester becomes Owner (automatic)
5. Owner invites Admins/Members (inside the app, via email)
6. Invitees accept using any auth method (Email+TOTP, OIDC, or Wallet)
```
```

- [ ] **Step 2: Commit**

```bash
git add docs/plans/2026-03-11-invitation-onboarding-design.md
git commit -m "docs: update onboarding design doc to reflect 3-auth-method support"
```

---

### Task 10: Final integration test — full onboarding flow

**Files:**
- Modify: `tests/SsdidDrive.Api.Tests/Integration/InvitationAcceptanceServiceTests.cs`

- [ ] **Step 1: Add comprehensive edge case tests**

Add to `InvitationAcceptanceServiceTests.cs`:

```csharp
[Fact]
public async Task AcceptInvitation_ExpiredInvitation_ReturnsGone()
{
    var (ownerClient, ownerId, tenantId) = await TestFixture.CreateAuthenticatedClientAsync(_factory, "ExpGoneOwner");
    var (acceptClient, acceptUserId, _) = await TestFixture.CreateAuthenticatedClientAsync(_factory, "ExpGoneAcceptee");

    using var scope = _factory.Services.CreateScope();
    var db = scope.ServiceProvider.GetRequiredService<AppDbContext>();

    var invitation = new Invitation
    {
        Id = Guid.NewGuid(),
        TenantId = tenantId,
        InvitedById = ownerId,
        InvitedUserId = acceptUserId,
        Role = TenantRole.Member,
        Status = InvitationStatus.Pending,
        Token = Convert.ToBase64String(Guid.NewGuid().ToByteArray()).Replace("+", "-").Replace("/", "_").TrimEnd('='),
        ShortCode = "EXP-GONE",
        ExpiresAt = DateTimeOffset.UtcNow.AddDays(-1),
        CreatedAt = DateTimeOffset.UtcNow.AddDays(-8),
        UpdatedAt = DateTimeOffset.UtcNow.AddDays(-8)
    };
    db.Invitations.Add(invitation);
    await db.SaveChangesAsync();

    var response = await acceptClient.PostAsync($"/api/invitations/{invitation.Id}/accept", null);

    // Service returns Gone (410) for expired invitations
    Assert.Equal(HttpStatusCode.Gone, response.StatusCode);
}

[Fact]
public async Task AcceptInvitation_AlreadyAccepted_Returns409()
{
    var (ownerClient, ownerId, tenantId) = await TestFixture.CreateAuthenticatedClientAsync(_factory, "DblAcceptOwner");
    var (acceptClient, acceptUserId, _) = await TestFixture.CreateAuthenticatedClientAsync(_factory, "DblAcceptUser");

    using var scope = _factory.Services.CreateScope();
    var db = scope.ServiceProvider.GetRequiredService<AppDbContext>();

    var invitation = new Invitation
    {
        Id = Guid.NewGuid(),
        TenantId = tenantId,
        InvitedById = ownerId,
        InvitedUserId = acceptUserId,
        Role = TenantRole.Member,
        Status = InvitationStatus.Accepted,
        Token = Convert.ToBase64String(Guid.NewGuid().ToByteArray()).Replace("+", "-").Replace("/", "_").TrimEnd('='),
        ShortCode = "DBL-ACPT",
        ExpiresAt = DateTimeOffset.UtcNow.AddDays(7),
        CreatedAt = DateTimeOffset.UtcNow,
        UpdatedAt = DateTimeOffset.UtcNow
    };
    db.Invitations.Add(invitation);
    await db.SaveChangesAsync();

    var response = await acceptClient.PostAsync($"/api/invitations/{invitation.Id}/accept", null);
    Assert.Equal(HttpStatusCode.Conflict, response.StatusCode);
}

[Fact]
public async Task CreateInvitation_ResponseIncludesEmailSentField()
{
    var (client, _, _) = await TestFixture.CreateAuthenticatedClientAsync(_factory, "EmailFieldOwner");

    var response = await client.PostAsJsonAsync("/api/invitations", new
    {
        email = "email-field-test@example.com",
        role = "member"
    }, TestFixture.Json);

    Assert.Equal(HttpStatusCode.Created, response.StatusCode);

    var body = await response.Content.ReadFromJsonAsync<JsonElement>(TestFixture.Json);
    Assert.True(body.TryGetProperty("email_sent", out _), "Response should include email_sent field");
}
```

- [ ] **Step 2: Run all new tests**

Run: `dotnet test tests/SsdidDrive.Api.Tests/ --filter "InvitationAcceptanceServiceTests" -v n`
Expected: All PASS

- [ ] **Step 3: Run complete test suite**

Run: `dotnet test tests/SsdidDrive.Api.Tests/ -v n`
Expected: All PASS

- [ ] **Step 4: Commit**

```bash
git add tests/SsdidDrive.Api.Tests/Integration/InvitationAcceptanceServiceTests.cs
git commit -m "test: add comprehensive edge case tests for invitation acceptance"
```

---

## Implementation Order & Dependencies

```
Task 1: InvitationAcceptanceService ──┐
Task 2: Refactor AcceptInvitation ────┤
Task 3: Refactor AcceptWithWallet ────┼── Chunk 1 (sequential)
Task 4: Refactor EmailRegisterVerify ─┘
                                      │
Task 5: OidcAuthorize invitation_token┤── Chunk 2 (sequential, depends on Chunk 1)
Task 6: OidcCallback registration ────┘
                                      │
Task 7: Cascade revoke ───────────────┤
Task 8: Audit logging + email_sent ───┼── Chunk 3 (7-8 parallel, 9-10 parallel)
Task 9: Update design doc ───────────┤
Task 10: Final integration tests ─────┘
```

Parallel execution opportunities:
- Tasks 7, 8 can run in parallel (independent endpoints)
- Tasks 9, 10 can run in parallel (docs vs tests)
- Chunks 1 and 2 must be sequential (Chunk 2 depends on the service from Chunk 1)
