# Invitation Acceptance Protocol Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement wallet-based invitation acceptance with double email verification, enabling unauthenticated users to accept Drive invitations via SSDID Wallet.

**Architecture:** Three-layer change — (1) Drive backend adds `accept-with-wallet` endpoint and modifies `GetInvitationByToken` to include inviter name, (2) SSDID Wallet adds `invite` deep link action with email comparison and acceptance screen, (3) Drive Android client updates `InviteAcceptViewModel` to use the new `ssdid://invite` wallet flow instead of the current register-based flow.

**Tech Stack:** C#/.NET 10 (backend), Kotlin/Jetpack Compose (Android wallet + Drive client), xUnit (backend tests), MockK (Android tests)

**Spec:** `docs/superpowers/specs/2026-03-13-invitation-acceptance-protocol-design.md`

---

## File Structure

### Backend (src/SsdidDrive.Api/)
| File | Action | Responsibility |
|------|--------|----------------|
| `Data/Entities/Invitation.cs` | Modify | Add `AcceptedByDid`, `AcceptedAt` fields |
| `Data/AppDbContext.cs` | Modify | Configure new columns |
| `Features/Invitations/AcceptWithWallet.cs` | Create | New public endpoint: verify credential + email match + create user + accept |
| `Features/Invitations/GetInvitationByToken.cs` | Modify | Add `.Include(i => i.InvitedBy)` and return `inviter_name` |
| `Features/Invitations/InvitationFeature.cs` | Modify | Register `AcceptWithWallet` endpoint |

### Backend Tests (tests/SsdidDrive.Api.Tests/)
| File | Action | Responsibility |
|------|--------|----------------|
| `Integration/AcceptWithWalletTests.cs` | Create | Integration tests for the new endpoint |

### Wallet (ssdid-wallet/android/app/src/main/java/my/ssdid/wallet/)
| File | Action | Responsibility |
|------|--------|----------------|
| `platform/deeplink/DeepLinkHandler.kt` | Modify | Add `invite` to VALID_ACTIONS, extract `callback_url` and `token` |
| `ui/navigation/Screen.kt` | Modify | Add `InviteAccept` screen route |
| `ui/navigation/NavGraph.kt` | Modify | Add composable for invite accept screen |
| `domain/transport/ServerApi.kt` | Modify | Add `getInvitationByToken` and `acceptWithWallet` API calls |
| `domain/transport/dto/InviteDto.kt` | Create | DTOs for invitation API |
| `feature/invite/InviteAcceptScreen.kt` | Create | UI: shows invitation details, Accept/Decline buttons |
| `feature/invite/InviteAcceptViewModel.kt` | Create | Logic: fetch invitation, compare email, call accept endpoint |

### Drive Android Client (clients/android/app/src/main/kotlin/my/ssdid/drive/)
| File | Action | Responsibility |
|------|--------|----------------|
| `presentation/auth/InviteAcceptViewModel.kt` | Modify | Change wallet launch from `ssdid://register` to `ssdid://invite` |
| `data/repository/AuthRepositoryImpl.kt` | Modify | Add `launchWalletInvite(token)` method |
| `domain/repository/AuthRepository.kt` | Modify | Add interface method |

---

## Chunk 1: Backend — Database Migration & Accept-With-Wallet Endpoint

### Task 1: Add `AcceptedByDid` and `AcceptedAt` to Invitation Entity

**Files:**
- Modify: `src/SsdidDrive.Api/Data/Entities/Invitation.cs`
- Modify: `src/SsdidDrive.Api/Data/AppDbContext.cs`

- [ ] **Step 1: Add fields to Invitation entity**

In `src/SsdidDrive.Api/Data/Entities/Invitation.cs`, add two new nullable fields after `UpdatedAt`:

```csharp
public string? AcceptedByDid { get; set; }             // DID of the user who accepted via wallet
public DateTimeOffset? AcceptedAt { get; set; }         // When the invitation was accepted
```

- [ ] **Step 2: Configure new columns in AppDbContext**

In `src/SsdidDrive.Api/Data/AppDbContext.cs`, inside the `modelBuilder.Entity<Invitation>()` block, add:

```csharp
e.Property(i => i.AcceptedByDid).HasMaxLength(256);
e.Property(i => i.AcceptedAt);
```

- [ ] **Step 3: Create EF Core migration**

Run:
```bash
dotnet ef migrations add AddInvitationAcceptanceFields --project src/SsdidDrive.Api
```

- [ ] **Step 4: Verify migration looks correct**

Check the generated migration file in `src/SsdidDrive.Api/Data/Migrations/` — it should add two nullable columns (`accepted_by_did` varchar(256) and `accepted_at` timestamptz) to the `invitations` table.

- [ ] **Step 5: Commit**

```bash
git add src/SsdidDrive.Api/Data/Entities/Invitation.cs src/SsdidDrive.Api/Data/AppDbContext.cs src/SsdidDrive.Api/Data/Migrations/
git commit -m "feat: add accepted_by_did and accepted_at fields to Invitation entity"
```

---

### Task 2: Modify GetInvitationByToken to include inviter name

**Files:**
- Modify: `src/SsdidDrive.Api/Features/Invitations/GetInvitationByToken.cs`

- [ ] **Step 1: Write failing test**

In `tests/SsdidDrive.Api.Tests/Integration/InvitationTests.cs`, add:

```csharp
[Fact]
public async Task GetInvitationByToken_IncludesInviterName()
{
    var (ownerClient, _, tenantId) = await TestFixture.CreateAuthenticatedClientAsync(_factory, "InviterNameOwner");

    var createResp = await ownerClient.PostAsJsonAsync("/api/invitations", new
    {
        email = "inviter-name-test@example.com",
        role = "member"
    }, TestFixture.Json);
    Assert.Equal(HttpStatusCode.Created, createResp.StatusCode);
    var createBody = await createResp.Content.ReadFromJsonAsync<JsonElement>(TestFixture.Json);
    var token = createBody.GetProperty("token").GetString()!;

    var anonClient = _factory.CreateClient();
    var response = await anonClient.GetAsync($"/api/invitations/token/{token}");
    Assert.Equal(HttpStatusCode.OK, response.StatusCode);

    var body = await response.Content.ReadFromJsonAsync<JsonElement>(TestFixture.Json);
    Assert.True(body.TryGetProperty("inviter_name", out var inviterName));
    Assert.Equal("InviterNameOwner", inviterName.GetString());
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `dotnet test tests/SsdidDrive.Api.Tests/ --filter "GetInvitationByToken_IncludesInviterName"`
Expected: FAIL — `inviter_name` property not found.

- [ ] **Step 3: Implement — add Include and inviter_name to response**

In `src/SsdidDrive.Api/Features/Invitations/GetInvitationByToken.cs`, modify the `Handle` method:

Change the query (line 26-31) to add `.Include(i => i.InvitedBy)`:
```csharp
var invitation = await db.Invitations
    .Include(i => i.Tenant)
    .Include(i => i.InvitedBy)
    .FirstOrDefaultAsync(i =>
        i.Token == token
        && i.Status == InvitationStatus.Pending
        && i.ExpiresAt > DateTimeOffset.UtcNow, ct);
```

Add `InviterName` to the response object (after line 41):
```csharp
InviterName = invitation.InvitedBy?.DisplayName,
```

- [ ] **Step 4: Run test to verify it passes**

Run: `dotnet test tests/SsdidDrive.Api.Tests/ --filter "GetInvitationByToken_IncludesInviterName"`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add src/SsdidDrive.Api/Features/Invitations/GetInvitationByToken.cs tests/SsdidDrive.Api.Tests/Integration/InvitationTests.cs
git commit -m "feat: include inviter_name in GetInvitationByToken response"
```

---

### Task 3: Create AcceptWithWallet endpoint

**Files:**
- Create: `src/SsdidDrive.Api/Features/Invitations/AcceptWithWallet.cs`
- Modify: `src/SsdidDrive.Api/Features/Invitations/InvitationFeature.cs`
- Create: `tests/SsdidDrive.Api.Tests/Integration/AcceptWithWalletTests.cs`

- [ ] **Step 1: Write failing integration tests**

Create `tests/SsdidDrive.Api.Tests/Integration/AcceptWithWalletTests.cs`:

```csharp
using System.Net;
using System.Net.Http.Json;
using System.Text.Json;
using Microsoft.Extensions.DependencyInjection;
using SsdidDrive.Api.Data;
using SsdidDrive.Api.Data.Entities;
using SsdidDrive.Api.Tests.Infrastructure;

namespace SsdidDrive.Api.Tests.Integration;

public class AcceptWithWalletTests : IClassFixture<SsdidDriveFactory>
{
    private readonly SsdidDriveFactory _factory;

    public AcceptWithWalletTests(SsdidDriveFactory factory) => _factory = factory;

    [Fact]
    public async Task AcceptWithWallet_ValidCredential_MatchingEmail_Returns200()
    {
        // Create a tenant with owner who will invite
        var (ownerClient, ownerId, tenantId) = await TestFixture.CreateAuthenticatedClientAsync(_factory, "WalletInvOwner");

        // Create invitation
        var createResp = await ownerClient.PostAsJsonAsync("/api/invitations", new
        {
            email = "wallet-accept@example.com",
            role = "member"
        }, TestFixture.Json);
        Assert.Equal(HttpStatusCode.Created, createResp.StatusCode);
        var createBody = await createResp.Content.ReadFromJsonAsync<JsonElement>(TestFixture.Json);
        var token = createBody.GetProperty("token").GetString()!;

        // Register a wallet identity and get credential
        var (walletIdentity, _) = TestFixture.CreateWalletIdentity();
        var credential = await TestFixture.RegisterWalletAsync(_factory, walletIdentity);

        // Accept with wallet — anonymous call (no Bearer token)
        var anonClient = _factory.CreateClient();
        var response = await anonClient.PostAsJsonAsync(
            $"/api/invitations/token/{token}/accept-with-wallet",
            new { credential, email = "wallet-accept@example.com" },
            TestFixture.Json);

        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        var body = await response.Content.ReadFromJsonAsync<JsonElement>(TestFixture.Json);
        Assert.False(string.IsNullOrEmpty(body.GetProperty("session_token").GetString()));
        Assert.Equal(walletIdentity.Did, body.GetProperty("did").GetString());
        Assert.True(body.TryGetProperty("tenant", out _));
    }

    [Fact]
    public async Task AcceptWithWallet_EmailMismatch_Returns403()
    {
        var (ownerClient, _, _) = await TestFixture.CreateAuthenticatedClientAsync(_factory, "WalletMismatchOwner");

        var createResp = await ownerClient.PostAsJsonAsync("/api/invitations", new
        {
            email = "invited@example.com",
            role = "member"
        }, TestFixture.Json);
        var createBody = await createResp.Content.ReadFromJsonAsync<JsonElement>(TestFixture.Json);
        var token = createBody.GetProperty("token").GetString()!;

        var (walletIdentity, _) = TestFixture.CreateWalletIdentity();
        var credential = await TestFixture.RegisterWalletAsync(_factory, walletIdentity);

        var anonClient = _factory.CreateClient();
        var response = await anonClient.PostAsJsonAsync(
            $"/api/invitations/token/{token}/accept-with-wallet",
            new { credential, email = "wrong-email@example.com" },
            TestFixture.Json);

        Assert.Equal(HttpStatusCode.Forbidden, response.StatusCode);
    }

    [Fact]
    public async Task AcceptWithWallet_ExpiredToken_Returns404()
    {
        var (_, ownerId, tenantId) = await TestFixture.CreateAuthenticatedClientAsync(_factory, "WalletExpiredOwner");

        // Insert expired invitation directly
        using var scope = _factory.Services.CreateScope();
        var db = scope.ServiceProvider.GetRequiredService<AppDbContext>();
        var invitation = new Invitation
        {
            Id = Guid.NewGuid(),
            TenantId = tenantId,
            InvitedById = ownerId,
            Email = "expired@example.com",
            Role = TenantRole.Member,
            Status = InvitationStatus.Pending,
            Token = Convert.ToBase64String(Guid.NewGuid().ToByteArray()).Replace("+", "-").Replace("/", "_").TrimEnd('='),
            ShortCode = $"EXP-{Guid.NewGuid():N}"[..8].ToUpper(),
            ExpiresAt = DateTimeOffset.UtcNow.AddDays(-1),
            CreatedAt = DateTimeOffset.UtcNow.AddDays(-8),
            UpdatedAt = DateTimeOffset.UtcNow.AddDays(-8)
        };
        db.Invitations.Add(invitation);
        await db.SaveChangesAsync();

        var (walletIdentity, _) = TestFixture.CreateWalletIdentity();
        var credential = await TestFixture.RegisterWalletAsync(_factory, walletIdentity);

        var anonClient = _factory.CreateClient();
        var response = await anonClient.PostAsJsonAsync(
            $"/api/invitations/token/{invitation.Token}/accept-with-wallet",
            new { credential, email = "expired@example.com" },
            TestFixture.Json);

        Assert.Equal(HttpStatusCode.NotFound, response.StatusCode);
    }

    [Fact]
    public async Task AcceptWithWallet_AlreadyAccepted_Returns409()
    {
        var (ownerClient, _, _) = await TestFixture.CreateAuthenticatedClientAsync(_factory, "WalletDoubleOwner");

        var createResp = await ownerClient.PostAsJsonAsync("/api/invitations", new
        {
            email = "double-accept@example.com",
            role = "member"
        }, TestFixture.Json);
        var createBody = await createResp.Content.ReadFromJsonAsync<JsonElement>(TestFixture.Json);
        var token = createBody.GetProperty("token").GetString()!;

        var (walletIdentity, _) = TestFixture.CreateWalletIdentity();
        var credential = await TestFixture.RegisterWalletAsync(_factory, walletIdentity);

        var anonClient = _factory.CreateClient();

        // First accept — should succeed
        var resp1 = await anonClient.PostAsJsonAsync(
            $"/api/invitations/token/{token}/accept-with-wallet",
            new { credential, email = "double-accept@example.com" },
            TestFixture.Json);
        Assert.Equal(HttpStatusCode.OK, resp1.StatusCode);

        // Second accept — should fail with 409 Conflict per spec
        var resp2 = await anonClient.PostAsJsonAsync(
            $"/api/invitations/token/{token}/accept-with-wallet",
            new { credential, email = "double-accept@example.com" },
            TestFixture.Json);
        Assert.Equal(HttpStatusCode.Conflict, resp2.StatusCode);
    }

    [Fact]
    public async Task AcceptWithWallet_InvalidCredential_Returns401()
    {
        var (ownerClient, _, _) = await TestFixture.CreateAuthenticatedClientAsync(_factory, "WalletBadCredOwner");

        var createResp = await ownerClient.PostAsJsonAsync("/api/invitations", new
        {
            email = "bad-cred@example.com",
            role = "member"
        }, TestFixture.Json);
        var createBody = await createResp.Content.ReadFromJsonAsync<JsonElement>(TestFixture.Json);
        var token = createBody.GetProperty("token").GetString()!;

        var anonClient = _factory.CreateClient();
        // Send a garbage credential
        var response = await anonClient.PostAsJsonAsync(
            $"/api/invitations/token/{token}/accept-with-wallet",
            new { credential = new { type = "fake" }, email = "bad-cred@example.com" },
            TestFixture.Json);
        Assert.Equal(HttpStatusCode.Unauthorized, response.StatusCode);
    }

    [Fact]
    public async Task AcceptWithWallet_CreatesNewUser_WhenDidNotInDb()
    {
        var (ownerClient, _, tenantId) = await TestFixture.CreateAuthenticatedClientAsync(_factory, "WalletNewUserOwner");

        var createResp = await ownerClient.PostAsJsonAsync("/api/invitations", new
        {
            email = "new-wallet-user@example.com",
            role = "member"
        }, TestFixture.Json);
        var createBody = await createResp.Content.ReadFromJsonAsync<JsonElement>(TestFixture.Json);
        var token = createBody.GetProperty("token").GetString()!;

        // Register wallet but do NOT create a Drive user for this DID
        var (walletIdentity, _) = TestFixture.CreateWalletIdentity();
        var credential = await TestFixture.RegisterWalletAsync(_factory, walletIdentity);

        var anonClient = _factory.CreateClient();
        var response = await anonClient.PostAsJsonAsync(
            $"/api/invitations/token/{token}/accept-with-wallet",
            new { credential, email = "new-wallet-user@example.com" },
            TestFixture.Json);

        Assert.Equal(HttpStatusCode.OK, response.StatusCode);

        // Verify user was created in DB
        using var scope = _factory.Services.CreateScope();
        var db = scope.ServiceProvider.GetRequiredService<AppDbContext>();
        var user = await Microsoft.EntityFrameworkCore.EntityFrameworkQueryableExtensions
            .FirstOrDefaultAsync(db.Users, u => u.Did == walletIdentity.Did);
        Assert.NotNull(user);

        // Verify UserTenant was created
        var ut = await Microsoft.EntityFrameworkCore.EntityFrameworkQueryableExtensions
            .FirstOrDefaultAsync(db.UserTenants, ut => ut.UserId == user.Id && ut.TenantId == tenantId);
        Assert.NotNull(ut);
        Assert.Equal(TenantRole.Member, ut.Role);

        // Verify AcceptedByDid and AcceptedAt are set on the invitation
        var inv = await Microsoft.EntityFrameworkCore.EntityFrameworkQueryableExtensions
            .FirstOrDefaultAsync(db.Invitations, i => i.Email == "new-wallet-user@example.com");
        Assert.NotNull(inv);
        Assert.Equal(walletIdentity.Did, inv!.AcceptedByDid);
        Assert.NotNull(inv.AcceptedAt);
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `dotnet test tests/SsdidDrive.Api.Tests/ --filter "AcceptWithWalletTests"`
Expected: FAIL — route not found (404 for all).

- [ ] **Step 3: Create AcceptWithWallet endpoint**

Create `src/SsdidDrive.Api/Features/Invitations/AcceptWithWallet.cs`:

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
        NotificationService notifications,
        CancellationToken ct)
    {
        // 1. Look up invitation by token (without status filter to distinguish 404 vs 409)
        var invitation = await db.Invitations
            .Include(i => i.Tenant)
            .Include(i => i.InvitedBy)
            .FirstOrDefaultAsync(i => i.Token == token, ct);

        if (invitation is null)
            return AppError.NotFound("Invitation not found").ToProblemResult();

        if (invitation.Status != InvitationStatus.Pending)
            return AppError.Conflict("Invitation has already been " + invitation.Status.ToString().ToLowerInvariant()).ToProblemResult();

        if (invitation.ExpiresAt <= DateTimeOffset.UtcNow)
        {
            invitation.Status = InvitationStatus.Expired;
            invitation.UpdatedAt = DateTimeOffset.UtcNow;
            await db.SaveChangesAsync(ct);
            return AppError.NotFound("Invitation has expired").ToProblemResult();
        }

        // 2. Verify credential
        var verifyResult = auth.VerifyCredential(req.Credential);
        return await verifyResult.Match(
            async did =>
            {
                // 3. Email match (case-insensitive)
                if (!string.Equals(req.Email?.Trim(), invitation.Email?.Trim(), StringComparison.OrdinalIgnoreCase))
                    return AppError.Forbidden("Email verification failed").ToProblemResult();

                // 4. Begin transaction for all DB changes (user creation + invitation update + UserTenant)
                await using var transaction = await db.Database.BeginTransactionAsync(ct);

                // 5. Find or create user
                var user = await db.Users
                    .FirstOrDefaultAsync(u => u.Did == did, ct);

                if (user is null)
                {
                    user = new User
                    {
                        Id = Guid.NewGuid(),
                        Did = did,
                        DisplayName = req.Email,
                        Status = UserStatus.Active,
                        TenantId = invitation.TenantId,
                        CreatedAt = DateTimeOffset.UtcNow,
                        UpdatedAt = DateTimeOffset.UtcNow
                    };
                    db.Users.Add(user);
                    await db.SaveChangesAsync(ct);
                }

                // 6. Check not already a member (direct DB query, not in-memory)
                var existingMembership = await db.UserTenants
                    .AnyAsync(ut => ut.UserId == user.Id && ut.TenantId == invitation.TenantId, ct);
                if (existingMembership)
                    return AppError.Conflict("User is already a member of this tenant").ToProblemResult();

                // 7. Accept invitation atomically
                var updated = await db.Invitations
                    .Where(i => i.Id == invitation.Id && i.Status == InvitationStatus.Pending)
                    .ExecuteUpdateAsync(s => s
                        .SetProperty(i => i.Status, InvitationStatus.Accepted)
                        .SetProperty(i => i.InvitedUserId, user.Id)
                        .SetProperty(i => i.AcceptedByDid, did)
                        .SetProperty(i => i.AcceptedAt, DateTimeOffset.UtcNow)
                        .SetProperty(i => i.UpdatedAt, DateTimeOffset.UtcNow), ct);

                if (updated == 0)
                    return AppError.Conflict("Invitation has already been processed").ToProblemResult();

                // 7. Create UserTenant
                db.UserTenants.Add(new UserTenant
                {
                    UserId = user.Id,
                    TenantId = invitation.TenantId,
                    Role = invitation.Role,
                    CreatedAt = DateTimeOffset.UtcNow
                });

                // 8. Notify inviter
                await notifications.CreateAsync(
                    invitation.InvitedById,
                    "invitation_accepted",
                    "Invitation Accepted",
                    $"{user.DisplayName ?? user.Did} accepted your invitation",
                    actionType: "invitation",
                    actionResourceId: invitation.Id.ToString(),
                    ct: ct);

                await db.SaveChangesAsync(ct);
                await transaction.CommitAsync(ct);

                // 9. Create session
                var sessionResult = auth.CreateAuthenticatedSession(did);
                return sessionResult.Match(
                    ok => Results.Ok(new
                    {
                        session_token = ok.SessionToken,
                        did = ok.Did,
                        server_did = ok.ServerDid,
                        server_key_id = ok.ServerKeyId,
                        server_signature = ok.ServerSignature,
                        user = new
                        {
                            user.Id,
                            user.Did,
                            display_name = user.DisplayName,
                            status = user.Status.ToString().ToLowerInvariant()
                        },
                        tenant = new
                        {
                            id = invitation.TenantId,
                            name = invitation.Tenant.Name,
                            slug = invitation.Tenant.Slug,
                            role = invitation.Role.ToString().ToLowerInvariant()
                        }
                    }),
                    err => err.ToProblemResult());
            },
            err => Task.FromResult(err.ToProblemResult()));
    }
}
```

- [ ] **Step 4: Register endpoint in InvitationFeature**

In `src/SsdidDrive.Api/Features/Invitations/InvitationFeature.cs`, add after `GetInvitationByToken.Map(group);`:

```csharp
AcceptWithWallet.Map(group);
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `dotnet test tests/SsdidDrive.Api.Tests/ --filter "AcceptWithWalletTests"`
Expected: All 5 tests PASS.

- [ ] **Step 6: Run full test suite to verify no regressions**

Run: `dotnet test tests/SsdidDrive.Api.Tests/`
Expected: All existing tests still pass.

- [ ] **Step 7: Commit**

```bash
git add src/SsdidDrive.Api/Features/Invitations/AcceptWithWallet.cs src/SsdidDrive.Api/Features/Invitations/InvitationFeature.cs tests/SsdidDrive.Api.Tests/Integration/AcceptWithWalletTests.cs
git commit -m "feat: add accept-with-wallet endpoint for invitation acceptance via SSDID Wallet"
```

---

## Chunk 2: SSDID Wallet — Deep Link Handler & Invite Accept Screen

### Task 4: Update wallet DeepLinkHandler for `invite` action

**Files:**
- Modify: `/Users/amirrudinyahaya/Workspace/ssdid-wallet/android/app/src/main/java/my/ssdid/wallet/platform/deeplink/DeepLinkHandler.kt`
- Modify: `/Users/amirrudinyahaya/Workspace/ssdid-wallet/android/app/src/main/java/my/ssdid/wallet/ui/navigation/Screen.kt`

- [ ] **Step 1: Add `invite` to VALID_ACTIONS and update parsing**

In `DeepLinkHandler.kt`:

1. Line 50 — add "invite" to VALID_ACTIONS:
```kotlin
private val VALID_ACTIONS = setOf("register", "authenticate", "sign", "credential-offer", "invite")
```

2. Add `token` field to `DeepLinkAction` data class (after `sessionId` on line 18):
```kotlin
val token: String = "",
```

3. Line 88-91 — extract `callback_url` for both `authenticate` and `invite`:
```kotlin
val callbackUrl = if (action in setOf("authenticate", "invite")) {
    val rawCallbackUrl = uri.getQueryParameter("callback_url") ?: ""
    if (isValidCallbackUrl(rawCallbackUrl)) rawCallbackUrl else ""
} else ""
```

4. After line 93, extract `token` parameter:
```kotlin
val token = uri.getQueryParameter("token") ?: ""
```

5. In the return statement (line 109-118), add `token = token`:
```kotlin
return DeepLinkAction(
    action = action,
    serverUrl = serverUrl,
    serverDid = uri.getQueryParameter("server_did") ?: "",
    sessionToken = uri.getQueryParameter("session_token") ?: "",
    callbackUrl = callbackUrl,
    sessionId = sessionId,
    token = token,
    requestedClaims = requestedClaims,
    acceptedAlgorithms = acceptedAlgorithms
)
```

6. Add `invite` case to `toNavRoute()` in `DeepLinkAction` (line 26-41):
```kotlin
"invite" -> Screen.InviteAccept.createRoute(serverUrl, token, callbackUrl)
```

- [ ] **Step 2: Add InviteAccept screen route**

In `Screen.kt`, add after the existing screen definitions:

```kotlin
object InviteAccept : Screen("invite_accept?serverUrl={serverUrl}&token={token}&callbackUrl={callbackUrl}") {
    fun createRoute(serverUrl: String, token: String, callbackUrl: String = "") =
        "invite_accept?serverUrl=${Uri.encode(serverUrl)}&token=${Uri.encode(token)}&callbackUrl=${Uri.encode(callbackUrl)}"
}
```

- [ ] **Step 3: Commit**

```bash
cd ~/Workspace/ssdid-wallet
git add android/app/src/main/java/my/ssdid/wallet/platform/deeplink/DeepLinkHandler.kt android/app/src/main/java/my/ssdid/wallet/ui/navigation/Screen.kt
git commit -m "feat: add invite deep link action to DeepLinkHandler"
```

---

### Task 5: Add wallet ServerApi methods for invitation

**Files:**
- Create: `/Users/amirrudinyahaya/Workspace/ssdid-wallet/android/app/src/main/java/my/ssdid/wallet/domain/transport/dto/InviteDto.kt`
- Modify: `/Users/amirrudinyahaya/Workspace/ssdid-wallet/android/app/src/main/java/my/ssdid/wallet/domain/transport/ServerApi.kt`

- [ ] **Step 1: Create invitation DTOs**

Create `InviteDto.kt`:

```kotlin
package my.ssdid.wallet.domain.transport.dto

import com.google.gson.annotations.SerializedName

data class InvitationDetailsResponse(
    val id: String,
    @SerializedName("tenant_id") val tenantId: String,
    @SerializedName("tenant_name") val tenantName: String,
    @SerializedName("inviter_name") val inviterName: String?,
    val email: String,
    val role: String,
    val status: String,
    val message: String?,
    @SerializedName("expires_at") val expiresAt: String
)

data class AcceptWithWalletRequest(
    val credential: kotlinx.serialization.json.JsonElement, // Raw JSON matching W3C VC format
    val email: String
)

data class AcceptWithWalletResponse(
    @SerializedName("session_token") val sessionToken: String,
    val did: String,
    @SerializedName("server_did") val serverDid: String,
    @SerializedName("server_key_id") val serverKeyId: String,
    @SerializedName("server_signature") val serverSignature: String
)
```

- [ ] **Step 2: Add API methods to ServerApi**

In `ServerApi.kt`, add:

```kotlin
@GET("api/invitations/token/{token}")
suspend fun getInvitationByToken(@Path("token") token: String): InvitationDetailsResponse

@POST("api/invitations/token/{token}/accept-with-wallet")
suspend fun acceptWithWallet(
    @Path("token") token: String,
    @Body request: AcceptWithWalletRequest
): AcceptWithWalletResponse
```

- [ ] **Step 3: Commit**

```bash
cd ~/Workspace/ssdid-wallet
git add android/app/src/main/java/my/ssdid/wallet/domain/transport/dto/InviteDto.kt android/app/src/main/java/my/ssdid/wallet/domain/transport/ServerApi.kt
git commit -m "feat: add invitation API methods to ServerApi"
```

---

### Task 6: Create wallet InviteAcceptViewModel and Screen

**Files:**
- Create: `/Users/amirrudinyahaya/Workspace/ssdid-wallet/android/app/src/main/java/my/ssdid/wallet/feature/invite/InviteAcceptViewModel.kt`
- Create: `/Users/amirrudinyahaya/Workspace/ssdid-wallet/android/app/src/main/java/my/ssdid/wallet/feature/invite/InviteAcceptScreen.kt`
- Modify: `/Users/amirrudinyahaya/Workspace/ssdid-wallet/android/app/src/main/java/my/ssdid/wallet/ui/navigation/NavGraph.kt`

- [ ] **Step 1: Create InviteAcceptViewModel**

Create `InviteAcceptViewModel.kt`:

```kotlin
package my.ssdid.wallet.feature.invite

import android.content.Intent
import android.net.Uri
import androidx.lifecycle.SavedStateHandle
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import dagger.hilt.android.lifecycle.HiltViewModel
import my.ssdid.wallet.domain.SsdidClient
import my.ssdid.wallet.domain.profile.ProfileManager
import my.ssdid.wallet.domain.transport.SsdidHttpClient
import my.ssdid.wallet.domain.transport.dto.AcceptWithWalletRequest
import my.ssdid.wallet.domain.transport.dto.InvitationDetailsResponse
import my.ssdid.wallet.domain.vault.Vault
import my.ssdid.wallet.platform.biometric.BiometricAuthenticator
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import javax.inject.Inject

data class InviteAcceptUiState(
    val isLoading: Boolean = true,
    val invitation: InvitationDetailsResponse? = null,
    val emailMatch: Boolean = false,
    val walletEmail: String = "",
    val error: String? = null,
    val isAccepting: Boolean = false,
    val acceptSuccess: Boolean = false,
    val sessionToken: String? = null,
    val callbackUrl: String = ""
)

@HiltViewModel
class InviteAcceptViewModel @Inject constructor(
    private val httpClient: SsdidHttpClient,
    private val vault: Vault,
    private val profileManager: ProfileManager,
    private val client: SsdidClient,
    private val biometricAuthenticator: BiometricAuthenticator,
    savedStateHandle: SavedStateHandle
) : ViewModel() {

    private val serverUrl: String = savedStateHandle["serverUrl"] ?: ""
    private val token: String = savedStateHandle["token"] ?: ""
    private val callbackUrl: String = savedStateHandle["callbackUrl"] ?: ""

    private val _uiState = MutableStateFlow(InviteAcceptUiState(callbackUrl = callbackUrl))
    val uiState: StateFlow<InviteAcceptUiState> = _uiState.asStateFlow()

    init {
        loadInvitation()
    }

    private fun loadInvitation() {
        viewModelScope.launch {
            _uiState.update { it.copy(isLoading = true, error = null) }
            try {
                val api = httpClient.serverApi(serverUrl)
                val invitation = api.getInvitationByToken(token)

                // Get wallet profile email
                val profileClaims = profileManager.getProfileClaims()
                val walletEmail = profileClaims?.get("email") ?: ""

                // Compare emails (case-insensitive)
                val emailMatch = walletEmail.isNotBlank() &&
                    walletEmail.trim().equals(invitation.email.trim(), ignoreCase = true)

                _uiState.update {
                    it.copy(
                        isLoading = false,
                        invitation = invitation,
                        emailMatch = emailMatch,
                        walletEmail = walletEmail,
                        error = if (!emailMatch) "This invitation was sent to a different email address" else null
                    )
                }
            } catch (e: Exception) {
                _uiState.update {
                    it.copy(isLoading = false, error = e.message ?: "Failed to load invitation")
                }
            }
        }
    }

    fun acceptInvitation() {
        viewModelScope.launch {
            _uiState.update { it.copy(isAccepting = true, error = null) }
            try {
                // Get credential from vault and serialize to JSON for backend
                val credentials = vault.listCredentials()
                val credential = credentials.firstOrNull()
                    ?: throw IllegalStateException("No credential found in wallet")
                val credentialJson = credential.toJsonElement() // Serialize to kotlinx.serialization JsonElement

                val walletEmail = _uiState.value.walletEmail

                val api = httpClient.serverApi(serverUrl)
                val response = api.acceptWithWallet(
                    token,
                    AcceptWithWalletRequest(
                        credential = credentialJson,
                        email = walletEmail
                    )
                )

                // Verify server signature (mutual auth) — same pattern as SsdidClient.authenticate()
                val serverSig = response.serverSignature
                val verified = client.verifier.verifyChallengeResponse(
                    response.serverDid,
                    response.serverKeyId,
                    response.sessionToken,
                    serverSig
                ).getOrThrow()
                if (!verified) throw SecurityException("Server signature verification failed")

                _uiState.update {
                    it.copy(
                        isAccepting = false,
                        acceptSuccess = true,
                        sessionToken = response.sessionToken
                    )
                }
            } catch (e: Exception) {
                _uiState.update {
                    it.copy(isAccepting = false, error = e.message ?: "Failed to accept invitation")
                }
            }
        }
    }

    fun buildCallbackUri(status: String? = null): Intent? {
        val state = _uiState.value
        if (callbackUrl.isBlank()) return null

        val uri = when {
            status == "cancelled" -> Uri.parse(callbackUrl).buildUpon()
                .appendQueryParameter("status", "cancelled")
                .build()
            state.acceptSuccess && state.sessionToken != null -> Uri.parse(callbackUrl).buildUpon()
                .appendQueryParameter("session_token", state.sessionToken)
                .appendQueryParameter("status", "success")
                .build()
            else -> Uri.parse(callbackUrl).buildUpon()
                .appendQueryParameter("status", "error")
                .appendQueryParameter("message", state.error ?: "Invitation acceptance failed")
                .build()
        }
        return Intent(Intent.ACTION_VIEW, uri)
    }

    fun buildDeclineCallbackUri(): Intent? = buildCallbackUri(status = "cancelled")
}
```

- [ ] **Step 2: Create InviteAcceptScreen**

Create `InviteAcceptScreen.kt`:

```kotlin
package my.ssdid.wallet.feature.invite

import android.content.Intent
import androidx.compose.foundation.layout.*
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Business
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.Email
import androidx.compose.material.icons.filled.Person
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.lifecycle.compose.collectAsStateWithLifecycle

@Composable
fun InviteAcceptScreen(
    viewModel: InviteAcceptViewModel = hiltViewModel()
) {
    val uiState by viewModel.uiState.collectAsStateWithLifecycle()
    val context = LocalContext.current

    // Auto-redirect on success
    LaunchedEffect(uiState.acceptSuccess) {
        if (uiState.acceptSuccess) {
            viewModel.buildCallbackUri()?.let { intent ->
                context.startActivity(intent)
            }
        }
    }

    Column(
        modifier = Modifier
            .fillMaxSize()
            .padding(24.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.Center
    ) {
        Text(
            text = "Invitation",
            style = MaterialTheme.typography.headlineMedium,
            color = MaterialTheme.colorScheme.primary
        )

        Spacer(modifier = Modifier.height(24.dp))

        when {
            uiState.isLoading -> {
                CircularProgressIndicator()
                Spacer(modifier = Modifier.height(16.dp))
                Text("Loading invitation details...")
            }

            uiState.acceptSuccess -> {
                Icon(
                    imageVector = Icons.Default.CheckCircle,
                    contentDescription = null,
                    tint = MaterialTheme.colorScheme.primary,
                    modifier = Modifier.size(64.dp)
                )
                Spacer(modifier = Modifier.height(16.dp))
                Text(
                    text = "Invitation accepted!",
                    style = MaterialTheme.typography.titleLarge
                )
                Spacer(modifier = Modifier.height(8.dp))
                Text(
                    text = "Returning to SSDID Drive...",
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
                // Manual return button if auto-redirect fails
                Spacer(modifier = Modifier.height(16.dp))
                OutlinedButton(onClick = {
                    viewModel.buildCallbackUri()?.let { context.startActivity(it) }
                }) {
                    Text("Return to SSDID Drive")
                }
            }

            uiState.invitation != null -> {
                val inv = uiState.invitation!!

                // Invitation details card
                Card(
                    modifier = Modifier.fillMaxWidth(),
                    colors = CardDefaults.cardColors(
                        containerColor = MaterialTheme.colorScheme.primaryContainer
                    )
                ) {
                    Column(modifier = Modifier.padding(16.dp)) {
                        // Tenant
                        Row(verticalAlignment = Alignment.CenterVertically) {
                            Icon(Icons.Default.Business, null)
                            Spacer(Modifier.width(12.dp))
                            Column {
                                Text("Organization", style = MaterialTheme.typography.labelSmall)
                                Text(inv.tenantName, style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold)
                            }
                        }

                        Spacer(Modifier.height(12.dp))

                        // Inviter
                        inv.inviterName?.let { name ->
                            Row(verticalAlignment = Alignment.CenterVertically) {
                                Icon(Icons.Default.Person, null)
                                Spacer(Modifier.width(12.dp))
                                Column {
                                    Text("Invited by", style = MaterialTheme.typography.labelSmall)
                                    Text(name, style = MaterialTheme.typography.bodyMedium)
                                }
                            }
                            Spacer(Modifier.height(12.dp))
                        }

                        // Invitation email
                        Row(verticalAlignment = Alignment.CenterVertically) {
                            Icon(Icons.Default.Email, null)
                            Spacer(Modifier.width(12.dp))
                            Column {
                                Text("Invited email", style = MaterialTheme.typography.labelSmall)
                                Text(inv.email, style = MaterialTheme.typography.bodyMedium)
                            }
                        }

                        Spacer(Modifier.height(8.dp))

                        // Role
                        Text(
                            "Role: ${inv.role}",
                            style = MaterialTheme.typography.labelMedium,
                            color = MaterialTheme.colorScheme.onPrimaryContainer.copy(alpha = 0.7f)
                        )

                        // Message
                        inv.message?.let { msg ->
                            Spacer(Modifier.height(12.dp))
                            HorizontalDivider()
                            Spacer(Modifier.height(8.dp))
                            Text("\"$msg\"", style = MaterialTheme.typography.bodyMedium,
                                fontStyle = androidx.compose.ui.text.font.FontStyle.Italic)
                        }
                    }
                }

                Spacer(modifier = Modifier.height(24.dp))

                // Error (email mismatch or other)
                uiState.error?.let { error ->
                    Text(
                        text = error,
                        color = MaterialTheme.colorScheme.error,
                        style = MaterialTheme.typography.bodyMedium,
                        textAlign = TextAlign.Center,
                        modifier = Modifier.fillMaxWidth()
                    )
                    Spacer(modifier = Modifier.height(16.dp))
                }

                // Accept button (only if email matches)
                if (uiState.emailMatch) {
                    Button(
                        onClick = { viewModel.acceptInvitation() },
                        enabled = !uiState.isAccepting,
                        modifier = Modifier.fillMaxWidth()
                    ) {
                        if (uiState.isAccepting) {
                            CircularProgressIndicator(
                                modifier = Modifier.size(20.dp),
                                color = MaterialTheme.colorScheme.onPrimary,
                                strokeWidth = 2.dp
                            )
                            Spacer(Modifier.width(8.dp))
                        }
                        Text("Accept Invitation")
                    }

                    Spacer(Modifier.height(8.dp))
                }

                // Decline button
                OutlinedButton(
                    onClick = {
                        viewModel.buildDeclineCallbackUri()?.let { context.startActivity(it) }
                    },
                    modifier = Modifier.fillMaxWidth()
                ) {
                    Text("Decline")
                }
            }

            else -> {
                // Error loading
                Text(
                    text = uiState.error ?: "Failed to load invitation",
                    color = MaterialTheme.colorScheme.error,
                    textAlign = TextAlign.Center
                )
            }
        }
    }
}
```

- [ ] **Step 3: Add composable to NavGraph**

In `NavGraph.kt`, add a composable block for the invite accept screen (alongside existing screen composable blocks):

```kotlin
composable(
    route = Screen.InviteAccept.route,
    arguments = listOf(
        navArgument("serverUrl") { type = NavType.StringType; defaultValue = "" },
        navArgument("token") { type = NavType.StringType; defaultValue = "" },
        navArgument("callbackUrl") { type = NavType.StringType; defaultValue = "" }
    )
) {
    InviteAcceptScreen()
}
```

Add the import: `import my.ssdid.wallet.feature.invite.InviteAcceptScreen`

- [ ] **Step 4: Build wallet to verify compilation**

Run:
```bash
cd ~/Workspace/ssdid-wallet/android && ./gradlew assembleDebug
```
Expected: BUILD SUCCESSFUL

- [ ] **Step 5: Commit**

```bash
cd ~/Workspace/ssdid-wallet
git add android/app/src/main/java/my/ssdid/wallet/feature/invite/ android/app/src/main/java/my/ssdid/wallet/ui/navigation/NavGraph.kt
git commit -m "feat: add invite acceptance screen with email verification"
```

---

## Chunk 3: Drive Android Client — Update Invitation Flow to Use Wallet

### Task 7: Update Drive Android invitation flow to use `ssdid://invite`

**Files:**
- Modify: `clients/android/app/src/main/kotlin/my/ssdid/drive/domain/repository/AuthRepository.kt`
- Modify: `clients/android/app/src/main/kotlin/my/ssdid/drive/data/repository/AuthRepositoryImpl.kt`
- Modify: `clients/android/app/src/main/kotlin/my/ssdid/drive/presentation/auth/InviteAcceptViewModel.kt`

- [ ] **Step 1: Add `launchWalletInvite` to AuthRepository interface**

In `clients/android/app/src/main/kotlin/my/ssdid/drive/domain/repository/AuthRepository.kt`, add:

```kotlin
suspend fun launchWalletInvite(token: String)
```

- [ ] **Step 2: Implement in AuthRepositoryImpl**

In `clients/android/app/src/main/kotlin/my/ssdid/drive/data/repository/AuthRepositoryImpl.kt`, add:

```kotlin
override suspend fun launchWalletInvite(token: String) {
    val serverUrl = BuildConfig.API_BASE_URL.removeSuffix("/api/").removeSuffix("/api")
    val walletUrl = "ssdid://invite" +
        "?server_url=${java.net.URLEncoder.encode(serverUrl, "UTF-8")}" +
        "&token=${java.net.URLEncoder.encode(token, "UTF-8")}" +
        "&callback_url=${java.net.URLEncoder.encode("ssdiddrive://invite/callback", "UTF-8")}"

    val intent = android.content.Intent(android.content.Intent.ACTION_VIEW, android.net.Uri.parse(walletUrl))
    intent.addFlags(android.content.Intent.FLAG_ACTIVITY_NEW_TASK)
    context.startActivity(intent)
}
```

- [ ] **Step 3: Update InviteAcceptViewModel to use invite flow**

In `clients/android/app/src/main/kotlin/my/ssdid/drive/presentation/auth/InviteAcceptViewModel.kt`, modify `acceptWithWallet()` (lines 131-148):

Replace the current implementation that creates a challenge and calls `launchWalletAuth` with:

```kotlin
fun acceptWithWallet() {
    viewModelScope.launch {
        _uiState.update { it.copy(isLoading = true, registrationError = null) }
        try {
            // Launch wallet with invite deep link — wallet handles email verification + authentication
            authRepository.launchWalletInvite(_uiState.value.token)
            _uiState.update { it.copy(isLoading = false, isWaitingForWallet = true) }
        } catch (e: Exception) {
            _uiState.update {
                it.copy(isLoading = false, registrationError = e.message)
            }
        }
    }
}
```

- [ ] **Step 4: Build Drive Android to verify compilation**

Run:
```bash
cd ~/Workspace/ssdid-drive/clients/android && ./gradlew assembleDebug
```
Expected: BUILD SUCCESSFUL

- [ ] **Step 5: Run Drive Android unit tests**

Run:
```bash
cd ~/Workspace/ssdid-drive/clients/android && ./gradlew test
```
Expected: All tests pass (update any test mocks that reference the old signature if needed).

- [ ] **Step 6: Commit**

```bash
cd ~/Workspace/ssdid-drive
git add clients/android/app/src/main/kotlin/my/ssdid/drive/domain/repository/AuthRepository.kt clients/android/app/src/main/kotlin/my/ssdid/drive/data/repository/AuthRepositoryImpl.kt clients/android/app/src/main/kotlin/my/ssdid/drive/presentation/auth/InviteAcceptViewModel.kt
git commit -m "feat: update Drive Android invitation flow to use ssdid://invite wallet protocol"
```

---

### Task 8: Handle invite callback deep link in Drive Android

**Files:**
- Modify: `clients/android/app/src/main/kotlin/my/ssdid/drive/util/DeepLinkHandler.kt`

**Critical issue:** The current `parseCustomScheme()` handles `ssdiddrive://invite/{token}` by taking the first path segment as a token. When the wallet calls back with `ssdiddrive://invite/callback?session_token=...`, this would parse `"callback"` as the invitation token — a bug. We must distinguish between the invitation link and the wallet callback.

- [ ] **Step 1: Update DeepLinkHandler to handle invite callback**

In `clients/android/app/src/main/kotlin/my/ssdid/drive/util/DeepLinkHandler.kt`, modify the `"invite"` case in `parseCustomScheme()` (lines 72-75):

Replace:
```kotlin
"invite" -> {
    val token = pathSegments.firstOrNull() ?: uri.lastPathSegment
    token?.let { DeepLinkAction.AcceptInvitation(it) }
}
```

With:
```kotlin
"invite" -> {
    val segment = pathSegments.firstOrNull()
    if (segment == "callback") {
        // ssdiddrive://invite/callback?session_token=...&status=...
        val sessionToken = uri.getQueryParameter("session_token")
        val status = uri.getQueryParameter("status") ?: ""
        if (status == "success" && sessionToken != null) {
            DeepLinkAction.WalletInviteCallback(sessionToken)
        } else {
            val errorMessage = uri.getQueryParameter("message") ?: "Invitation failed"
            DeepLinkAction.WalletInviteError(errorMessage)
        }
    } else {
        // ssdiddrive://invite/{token} — open invitation acceptance screen
        val token = segment ?: uri.lastPathSegment
        token?.let { DeepLinkAction.AcceptInvitation(it) }
    }
}
```

- [ ] **Step 2: Add new DeepLinkAction types**

In the same file, add to the `DeepLinkAction` sealed class:

```kotlin
/**
 * Handle SSDID Wallet invitation callback with session token.
 */
data class WalletInviteCallback(val sessionToken: String) : DeepLinkAction()

/**
 * Handle SSDID Wallet invitation callback with error.
 */
data class WalletInviteError(val message: String) : DeepLinkAction()
```

- [ ] **Step 3: Handle new actions in MainActivity/NavGraph**

In the activity or navigation handler that processes `DeepLinkAction`, add handling for `WalletInviteCallback`:

```kotlin
is DeepLinkAction.WalletInviteCallback -> {
    WalletCallbackHolder.set(action.sessionToken)
    // Navigate to InviteAcceptScreen which will consume the token
}
is DeepLinkAction.WalletInviteError -> {
    // Show error or navigate to InviteAcceptScreen with error state
}
```

- [ ] **Step 4: Build and verify**

Run:
```bash
cd ~/Workspace/ssdid-drive/clients/android && ./gradlew assembleDebug
```

- [ ] **Step 5: Test the full flow on device**

1. Launch Drive app → tap invitation link
2. Drive opens wallet via `ssdid://invite?...`
3. Wallet shows invitation details with email check
4. If email matches, tap "Accept Invitation"
5. Wallet calls backend, gets session token, calls back to Drive
6. Drive receives session token via `WalletCallbackHolder`, navigates to main screen

- [ ] **Step 6: Commit**

```bash
cd ~/Workspace/ssdid-drive
git add clients/android/app/src/main/kotlin/my/ssdid/drive/util/DeepLinkHandler.kt
git commit -m "feat: handle ssdiddrive://invite/callback deep link for wallet invitation flow"
```

---

## Summary

| Task | Component | Description |
|------|-----------|-------------|
| 1 | Backend DB | Add `AcceptedByDid` and `AcceptedAt` to Invitation entity + migration |
| 2 | Backend API | Add `inviter_name` to GetInvitationByToken response |
| 3 | Backend API | Create `AcceptWithWallet` endpoint with credential verification + email match |
| 4 | Wallet | Update DeepLinkHandler for `invite` action + Screen route |
| 5 | Wallet | Add ServerApi methods for invitation endpoints |
| 6 | Wallet | Create InviteAcceptViewModel + InviteAcceptScreen |
| 7 | Drive Android | Update InviteAcceptViewModel to use `ssdid://invite` flow |
| 8 | Drive Android | Verify invite callback deep link routing |
