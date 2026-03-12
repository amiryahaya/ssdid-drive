# Admin Portal — Invite User to Tenant — Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Enable SuperAdmins to invite users as tenant Owner or Admin from the admin portal's TenantDetailPage.

**Architecture:** Three backend endpoints (create/list/revoke invitations) under `/api/admin/tenants/{tenantId}/invitations`, protected by existing SuperAdmin filter. Frontend adds an InviteUserDialog component, invitation state to adminStore, and a pending invitations section on TenantDetailPage. Reuses existing `Invitation` entity and `GenerateShortCode` logic (extracted to shared helper).

**Tech Stack:** ASP.NET Core 10 Minimal APIs, EF Core + PostgreSQL, React 19 + Zustand + Tailwind CSS

---

## File Structure

**Backend — New files:**
- `src/SsdidDrive.Api/Features/Admin/CreateAdminInvitation.cs` — POST endpoint
- `src/SsdidDrive.Api/Features/Admin/ListAdminInvitations.cs` — GET endpoint
- `src/SsdidDrive.Api/Features/Admin/RevokeAdminInvitation.cs` — DELETE endpoint
- `src/SsdidDrive.Api/Features/Invitations/InvitationHelper.cs` — Extracted shared `GenerateShortCode` logic

**Backend — Modified files:**
- `src/SsdidDrive.Api/Features/Admin/AdminFeature.cs` — Register new endpoints
- `src/SsdidDrive.Api/Features/Invitations/CreateInvitation.cs` — Use shared `InvitationHelper.GenerateShortCode`

**Frontend — New files:**
- `clients/admin/src/components/InviteUserDialog.tsx` — Invite dialog with form + success state

**Frontend — Modified files:**
- `clients/admin/src/stores/adminStore.ts` — Add invitation state and actions
- `clients/admin/src/pages/TenantDetailPage.tsx` — Add invite button + pending invitations section

**Tests:**
- `tests/SsdidDrive.Api.Tests/Integration/AdminInvitationTests.cs` — All backend tests

---

## Chunk 1: Backend

### Task 1: Extract shared GenerateShortCode helper

**Files:**
- Create: `src/SsdidDrive.Api/Features/Invitations/InvitationHelper.cs`
- Modify: `src/SsdidDrive.Api/Features/Invitations/CreateInvitation.cs:129-160`

- [ ] **Step 1: Create InvitationHelper with extracted GenerateShortCode**

```csharp
// src/SsdidDrive.Api/Features/Invitations/InvitationHelper.cs
using Microsoft.EntityFrameworkCore;
using SsdidDrive.Api.Data;

namespace SsdidDrive.Api.Features.Invitations;

public static class InvitationHelper
{
    public static async Task<string> GenerateShortCode(AppDbContext db, string tenantSlug, CancellationToken ct)
    {
        const string chars = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"; // No 0/O/1/I to avoid confusion
        var prefix = tenantSlug.Split('-')[0].ToUpperInvariant();
        if (prefix.Length > 6) prefix = prefix[..6];

        for (var attempt = 0; attempt < 10; attempt++)
        {
            var suffix = new string(Enumerable.Range(0, 4)
                .Select(_ => chars[System.Security.Cryptography.RandomNumberGenerator.GetInt32(chars.Length)])
                .ToArray());

            var code = $"{prefix}-{suffix}";

            if (!await db.Invitations.AnyAsync(i => i.ShortCode == code, ct))
                return code;
        }

        // Fallback: longer suffix
        for (var fallbackAttempt = 0; fallbackAttempt < 5; fallbackAttempt++)
        {
            var fallbackSuffix = new string(Enumerable.Range(0, 6)
                .Select(_ => chars[System.Security.Cryptography.RandomNumberGenerator.GetInt32(chars.Length)])
                .ToArray());

            var fallbackCode = $"{prefix}-{fallbackSuffix}";
            if (!await db.Invitations.AnyAsync(i => i.ShortCode == fallbackCode, ct))
                return fallbackCode;
        }

        throw new InvalidOperationException("Short code space exhausted for this tenant; please retry");
    }

    public static string GenerateToken()
    {
        return Convert.ToBase64String(System.Security.Cryptography.RandomNumberGenerator.GetBytes(32))
            .Replace("+", "-").Replace("/", "_").TrimEnd('=');
    }
}
```

- [ ] **Step 2: Update CreateInvitation.cs to use InvitationHelper**

In `src/SsdidDrive.Api/Features/Invitations/CreateInvitation.cs`, replace lines 54-56:
```csharp
// Before:
var token = Convert.ToBase64String(System.Security.Cryptography.RandomNumberGenerator.GetBytes(32))
    .Replace("+", "-").Replace("/", "_").TrimEnd('=');
```
With:
```csharp
var token = InvitationHelper.GenerateToken();
```

Replace line 60:
```csharp
// Before:
var shortCode = await GenerateShortCode(db, tenant!.Slug, ct);
```
With:
```csharp
var shortCode = await InvitationHelper.GenerateShortCode(db, tenant!.Slug, ct);
```

Delete the private `GenerateShortCode` method (lines 129-160) from `CreateInvitation.cs`.

- [ ] **Step 3: Verify existing tests still pass**

Run: `dotnet test tests/SsdidDrive.Api.Tests/ --filter "FullyQualifiedName~InvitationTests" -v minimal`
Expected: All existing invitation tests PASS (the refactor is behavior-preserving).

- [ ] **Step 4: Commit**

```bash
git add src/SsdidDrive.Api/Features/Invitations/InvitationHelper.cs src/SsdidDrive.Api/Features/Invitations/CreateInvitation.cs
git commit -m "refactor: extract shared InvitationHelper for GenerateShortCode and GenerateToken"
```

---

### Task 2: Create admin invitation endpoint — tests first

**Files:**
- Create: `tests/SsdidDrive.Api.Tests/Integration/AdminInvitationTests.cs`

- [ ] **Step 1: Write failing tests for CreateAdminInvitation**

```csharp
// tests/SsdidDrive.Api.Tests/Integration/AdminInvitationTests.cs
using System.Net;
using System.Net.Http.Json;
using System.Text.Json;
using SsdidDrive.Api.Tests.Infrastructure;

namespace SsdidDrive.Api.Tests.Integration;

public class AdminInvitationTests : IClassFixture<SsdidDriveFactory>
{
    private readonly SsdidDriveFactory _factory;
    public AdminInvitationTests(SsdidDriveFactory factory) => _factory = factory;

    private async Task<(HttpClient Client, Guid TenantId)> CreateAdminWithTenant(string name = "InvAdmin")
    {
        var (client, _, _) = await TestFixture.CreateAuthenticatedClientAsync(_factory, name, systemRole: "SuperAdmin");
        var slug = $"inv-{Guid.NewGuid():N}"[..20];
        var createResp = await client.PostAsJsonAsync("/api/admin/tenants",
            new { name = "InviteTenant", slug }, TestFixture.Json);
        createResp.EnsureSuccessStatusCode();
        var tenant = await createResp.Content.ReadFromJsonAsync<JsonElement>(TestFixture.Json);
        return (client, tenant.GetProperty("id").GetGuid());
    }

    [Fact]
    public async Task CreateInvitation_Owner_ReturnsCreated()
    {
        var (client, tenantId) = await CreateAdminWithTenant("OwnerInvAdmin");
        var response = await client.PostAsJsonAsync(
            $"/api/admin/tenants/{tenantId}/invitations",
            new { email = "owner@test.com", role = "owner" }, TestFixture.Json);

        Assert.Equal(HttpStatusCode.Created, response.StatusCode);

        var body = await response.Content.ReadFromJsonAsync<JsonElement>(TestFixture.Json);
        Assert.Equal("owner", body.GetProperty("role").GetString());
        Assert.Equal("owner@test.com", body.GetProperty("email").GetString());
        Assert.Equal("pending", body.GetProperty("status").GetString());
        Assert.True(body.TryGetProperty("short_code", out var code));
        Assert.False(string.IsNullOrEmpty(code.GetString()));
    }

    [Fact]
    public async Task CreateInvitation_Admin_ReturnsCreated()
    {
        var (client, tenantId) = await CreateAdminWithTenant("AdminInvAdmin");
        var response = await client.PostAsJsonAsync(
            $"/api/admin/tenants/{tenantId}/invitations",
            new { email = "admin@test.com", role = "admin" }, TestFixture.Json);

        Assert.Equal(HttpStatusCode.Created, response.StatusCode);

        var body = await response.Content.ReadFromJsonAsync<JsonElement>(TestFixture.Json);
        Assert.Equal("admin", body.GetProperty("role").GetString());
    }

    [Fact]
    public async Task CreateInvitation_MemberRole_Returns400()
    {
        var (client, tenantId) = await CreateAdminWithTenant("MemberRoleAdmin");
        var response = await client.PostAsJsonAsync(
            $"/api/admin/tenants/{tenantId}/invitations",
            new { email = "member@test.com", role = "member" }, TestFixture.Json);

        Assert.Equal(HttpStatusCode.BadRequest, response.StatusCode);
    }

    [Fact]
    public async Task CreateInvitation_NonSuperAdmin_Returns403()
    {
        var (regularClient, _, tenantId) = await TestFixture.CreateAuthenticatedClientAsync(_factory, "RegularInvUser");
        var response = await regularClient.PostAsJsonAsync(
            $"/api/admin/tenants/{tenantId}/invitations",
            new { email = "test@test.com", role = "owner" }, TestFixture.Json);

        Assert.Equal(HttpStatusCode.Forbidden, response.StatusCode);
    }

    [Fact]
    public async Task CreateInvitation_TenantNotFound_Returns404()
    {
        var (client, _, _) = await TestFixture.CreateAuthenticatedClientAsync(_factory, "NotFoundInvAdmin", systemRole: "SuperAdmin");
        var response = await client.PostAsJsonAsync(
            $"/api/admin/tenants/{Guid.NewGuid()}/invitations",
            new { email = "test@test.com", role = "owner" }, TestFixture.Json);

        Assert.Equal(HttpStatusCode.NotFound, response.StatusCode);
    }

    [Fact]
    public async Task CreateInvitation_MissingEmail_Returns400()
    {
        var (client, tenantId) = await CreateAdminWithTenant("NoEmailAdmin");
        var response = await client.PostAsJsonAsync(
            $"/api/admin/tenants/{tenantId}/invitations",
            new { role = "owner" }, TestFixture.Json);

        Assert.Equal(HttpStatusCode.BadRequest, response.StatusCode);
    }

    [Fact]
    public async Task CreateInvitation_InvalidEmail_Returns400()
    {
        var (client, tenantId) = await CreateAdminWithTenant("BadEmailAdmin");
        var response = await client.PostAsJsonAsync(
            $"/api/admin/tenants/{tenantId}/invitations",
            new { email = "not-an-email", role = "owner" }, TestFixture.Json);

        Assert.Equal(HttpStatusCode.BadRequest, response.StatusCode);
    }

    [Fact]
    public async Task CreateInvitation_DuplicatePending_Returns409()
    {
        var (client, tenantId) = await CreateAdminWithTenant("DupInvAdmin");
        var email = $"dup-{Guid.NewGuid():N}@test.com";

        var first = await client.PostAsJsonAsync(
            $"/api/admin/tenants/{tenantId}/invitations",
            new { email, role = "owner" }, TestFixture.Json);
        Assert.Equal(HttpStatusCode.Created, first.StatusCode);

        var second = await client.PostAsJsonAsync(
            $"/api/admin/tenants/{tenantId}/invitations",
            new { email, role = "owner" }, TestFixture.Json);
        Assert.Equal(HttpStatusCode.Conflict, second.StatusCode);
    }

    [Fact]
    public async Task CreateInvitation_ExistingMember_Returns409()
    {
        // CreateAuthenticatedClientAsync creates a user who is Owner of their own tenant
        var (adminClient, _, _) = await TestFixture.CreateAuthenticatedClientAsync(_factory, "ExistMemberAdmin", systemRole: "SuperAdmin");
        // Create a user with known email in a specific tenant
        var (_, targetUserId, targetTenantId) = await TestFixture.CreateAuthenticatedClientAsync(_factory, "ExistingMember");

        // The user is already a member of targetTenantId — try to invite them to it
        // First we need to know the user's email. TestFixture doesn't set email, so we set it manually.
        using var scope = _factory.Services.CreateScope();
        var db = scope.ServiceProvider.GetRequiredService<SsdidDrive.Api.Data.AppDbContext>();
        var user = await db.Users.FindAsync(targetUserId);
        user!.Email = "existing@test.com";
        await db.SaveChangesAsync();

        var response = await adminClient.PostAsJsonAsync(
            $"/api/admin/tenants/{targetTenantId}/invitations",
            new { email = "existing@test.com", role = "owner" }, TestFixture.Json);

        Assert.Equal(HttpStatusCode.Conflict, response.StatusCode);
    }

    [Fact]
    public async Task AcceptInvitation_OwnerRole_AddsUserAsOwner()
    {
        var (adminClient, tenantId) = await CreateAdminWithTenant("AcceptOwnerAdmin");

        // Create an Owner invitation via admin endpoint
        var createResp = await adminClient.PostAsJsonAsync(
            $"/api/admin/tenants/{tenantId}/invitations",
            new { email = "newowner@test.com", role = "owner" }, TestFixture.Json);
        createResp.EnsureSuccessStatusCode();
        var created = await createResp.Content.ReadFromJsonAsync<JsonElement>(TestFixture.Json);
        var invitationId = created.GetProperty("id").GetGuid();
        var token = created.GetProperty("short_code").GetString(); // not the token, get it from DB

        // Get the actual token from the DB
        using var scope = _factory.Services.CreateScope();
        var db = scope.ServiceProvider.GetRequiredService<SsdidDrive.Api.Data.AppDbContext>();
        var invitation = await db.Invitations.FindAsync(invitationId);
        var invToken = invitation!.Token;

        // Create a new user (not in this tenant) to accept the invitation
        var (acceptingClient, acceptingUserId, _) = await TestFixture.CreateAuthenticatedClientAsync(_factory, "NewOwner");

        // Accept the invitation (uses the regular invitation endpoint, not admin)
        var acceptResp = await acceptingClient.PostAsJsonAsync(
            $"/api/invitations/{invitationId}/accept",
            new { token = invToken }, TestFixture.Json);
        Assert.Equal(HttpStatusCode.OK, acceptResp.StatusCode);

        var acceptBody = await acceptResp.Content.ReadFromJsonAsync<JsonElement>(TestFixture.Json);
        Assert.Equal("owner", acceptBody.GetProperty("role").GetString());

        // Verify the user is now an Owner of the tenant
        using var scope2 = _factory.Services.CreateScope();
        var db2 = scope2.ServiceProvider.GetRequiredService<SsdidDrive.Api.Data.AppDbContext>();
        var membership = await db2.UserTenants
            .FirstOrDefaultAsync(ut => ut.UserId == acceptingUserId && ut.TenantId == tenantId);
        Assert.NotNull(membership);
        Assert.Equal(SsdidDrive.Api.Data.Entities.TenantRole.Owner, membership.Role);
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `dotnet test tests/SsdidDrive.Api.Tests/ --filter "FullyQualifiedName~AdminInvitationTests" -v minimal`
Expected: All tests FAIL (endpoints don't exist yet).

- [ ] **Step 3: Commit failing tests**

```bash
git add tests/SsdidDrive.Api.Tests/Integration/AdminInvitationTests.cs
git commit -m "test: add failing tests for admin invitation creation"
```

---

### Task 3: Implement CreateAdminInvitation endpoint

**Files:**
- Create: `src/SsdidDrive.Api/Features/Admin/CreateAdminInvitation.cs`
- Modify: `src/SsdidDrive.Api/Features/Admin/AdminFeature.cs:23-31`

- [ ] **Step 1: Create CreateAdminInvitation.cs**

```csharp
// src/SsdidDrive.Api/Features/Admin/CreateAdminInvitation.cs
using System.Net.Mail;
using Microsoft.EntityFrameworkCore;
using SsdidDrive.Api.Common;
using SsdidDrive.Api.Data;
using SsdidDrive.Api.Data.Entities;
using SsdidDrive.Api.Features.Invitations;
using SsdidDrive.Api.Services;

namespace SsdidDrive.Api.Features.Admin;

public static class CreateAdminInvitation
{
    public record Request(string? Email, string? Role, string? Message);

    public static void Map(RouteGroupBuilder group) =>
        group.MapPost("/tenants/{tenantId:guid}/invitations", Handle);

    private static async Task<IResult> Handle(
        Guid tenantId, Request req, AppDbContext db,
        CurrentUserAccessor accessor, NotificationService notifications,
        EmailService? emailService, AuditService audit, CancellationToken ct)
    {
        // Validate email is provided and valid
        if (string.IsNullOrWhiteSpace(req.Email))
            return AppError.BadRequest("Email is required").ToProblemResult();

        if (!MailAddress.TryCreate(req.Email, out _))
            return AppError.BadRequest("Invalid email address format").ToProblemResult();

        if (req.Message is { Length: > 500 })
            return AppError.BadRequest("Message must be 500 characters or fewer").ToProblemResult();

        // Validate role: only owner or admin
        var role = req.Role?.ToLowerInvariant() switch
        {
            "owner" => TenantRole.Owner,
            "admin" => TenantRole.Admin,
            _ => (TenantRole?)null
        };

        if (role is null)
            return AppError.BadRequest("Role must be 'owner' or 'admin'").ToProblemResult();

        // Validate tenant exists
        var tenant = await db.Tenants.FirstOrDefaultAsync(t => t.Id == tenantId, ct);
        if (tenant is null)
            return AppError.NotFound("Tenant not found").ToProblemResult();

        // Check for existing member by email
        var existingMember = await db.Users
            .Where(u => u.Email == req.Email)
            .Join(db.UserTenants.Where(ut => ut.TenantId == tenantId),
                u => u.Id, ut => ut.UserId, (u, ut) => u)
            .AnyAsync(ct);

        if (existingMember)
            return AppError.Conflict("This user is already a member of the tenant").ToProblemResult();

        // Check for duplicate pending invitation
        var duplicatePending = await db.Invitations
            .AnyAsync(i => i.TenantId == tenantId
                && i.Email == req.Email
                && i.Status == InvitationStatus.Pending, ct);

        if (duplicatePending)
            return AppError.Conflict("A pending invitation already exists for this email").ToProblemResult();

        var now = DateTimeOffset.UtcNow;
        var token = InvitationHelper.GenerateToken();
        var shortCode = await InvitationHelper.GenerateShortCode(db, tenant.Slug, ct);

        // Resolve email to existing user
        Guid? invitedUserId = null;
        var invitedUser = await db.Users.FirstOrDefaultAsync(u => u.Email == req.Email, ct);
        invitedUserId = invitedUser?.Id;

        var user = accessor.User!;

        var invitation = new Invitation
        {
            Id = Guid.NewGuid(),
            TenantId = tenantId,
            InvitedById = user.Id,
            InvitedUserId = invitedUserId,
            Email = req.Email,
            Role = role.Value,
            Status = InvitationStatus.Pending,
            Token = token,
            ShortCode = shortCode,
            Message = req.Message,
            ExpiresAt = now.AddDays(7),
            CreatedAt = now,
            UpdatedAt = now
        };

        db.Invitations.Add(invitation);

        if (invitedUserId is not null)
        {
            await notifications.CreateAsync(
                invitedUserId.Value,
                "invitation_received",
                "New Invitation",
                $"You've been invited to join {tenant.Name} as {role.Value.ToString().ToLowerInvariant()}",
                actionType: "invitation",
                actionResourceId: invitation.Id.ToString(),
                ct: ct);
        }

        await db.SaveChangesAsync(ct);

        await audit.LogAsync(user.Id, "invitation.created",
            "Invitation", invitation.Id,
            $"Invited {req.Email} as {role.Value.ToString().ToLowerInvariant()} to tenant {tenant.Name}", ct);

        // Send email (fire-and-forget)
        if (emailService is not null)
        {
            var email = req.Email;
            var tenantName = tenant.Name;
            var roleName = role.Value.ToString().ToLowerInvariant();
            var msg = req.Message;
            _ = Task.Run(() => emailService.SendInvitationAsync(email, tenantName, roleName, shortCode, msg));
        }

        return Results.Created($"/api/admin/tenants/{tenantId}/invitations/{invitation.Id}", new
        {
            id = invitation.Id,
            tenant_id = invitation.TenantId,
            invited_by_id = invitation.InvitedById,
            email = invitation.Email,
            invited_user_id = invitation.InvitedUserId,
            role = invitation.Role.ToString().ToLowerInvariant(),
            status = invitation.Status.ToString().ToLowerInvariant(),
            short_code = invitation.ShortCode,
            message = invitation.Message,
            expires_at = invitation.ExpiresAt,
            created_at = invitation.CreatedAt
        });
    }
}
```

- [ ] **Step 2: Register in AdminFeature.cs**

In `src/SsdidDrive.Api/Features/Admin/AdminFeature.cs`, add after line 31 (`ListAuditLog.Map(group);`):
```csharp
        CreateAdminInvitation.Map(group);
```

- [ ] **Step 3: Run creation tests to verify they pass**

Run: `dotnet test tests/SsdidDrive.Api.Tests/ --filter "FullyQualifiedName~AdminInvitationTests" -v minimal`
Expected: All creation tests PASS.

- [ ] **Step 4: Commit**

```bash
git add src/SsdidDrive.Api/Features/Admin/CreateAdminInvitation.cs src/SsdidDrive.Api/Features/Admin/AdminFeature.cs
git commit -m "feat: add admin endpoint for creating tenant invitations (owner/admin)"
```

---

### Task 4: List and Revoke admin invitation endpoints — tests first

**Files:**
- Modify: `tests/SsdidDrive.Api.Tests/Integration/AdminInvitationTests.cs`

- [ ] **Step 1: Add failing tests for List and Revoke**

Append to `AdminInvitationTests.cs`:

```csharp
    [Fact]
    public async Task ListInvitations_ReturnsInvitationsForTenant()
    {
        var (client, tenantId) = await CreateAdminWithTenant("ListInvAdmin");
        // Create two invitations
        await client.PostAsJsonAsync(
            $"/api/admin/tenants/{tenantId}/invitations",
            new { email = "list1@test.com", role = "owner" }, TestFixture.Json);
        await client.PostAsJsonAsync(
            $"/api/admin/tenants/{tenantId}/invitations",
            new { email = "list2@test.com", role = "admin" }, TestFixture.Json);

        var response = await client.GetAsync($"/api/admin/tenants/{tenantId}/invitations");
        Assert.Equal(HttpStatusCode.OK, response.StatusCode);

        var body = await response.Content.ReadFromJsonAsync<JsonElement>(TestFixture.Json);
        Assert.True(body.TryGetProperty("items", out var items));
        Assert.Equal(2, items.GetArrayLength());
        Assert.True(body.TryGetProperty("total", out var total));
        Assert.Equal(2, total.GetInt32());
    }

    [Fact]
    public async Task ListInvitations_TenantNotFound_Returns404()
    {
        var (client, _, _) = await TestFixture.CreateAuthenticatedClientAsync(_factory, "ListNotFoundAdmin", systemRole: "SuperAdmin");
        var response = await client.GetAsync($"/api/admin/tenants/{Guid.NewGuid()}/invitations");
        Assert.Equal(HttpStatusCode.NotFound, response.StatusCode);
    }

    [Fact]
    public async Task RevokeInvitation_PendingInvitation_ReturnsNoContent()
    {
        var (client, tenantId) = await CreateAdminWithTenant("RevokeInvAdmin");
        var createResp = await client.PostAsJsonAsync(
            $"/api/admin/tenants/{tenantId}/invitations",
            new { email = "revoke@test.com", role = "owner" }, TestFixture.Json);
        var created = await createResp.Content.ReadFromJsonAsync<JsonElement>(TestFixture.Json);
        var invitationId = created.GetProperty("id").GetGuid();

        var response = await client.DeleteAsync($"/api/admin/tenants/{tenantId}/invitations/{invitationId}");
        Assert.Equal(HttpStatusCode.NoContent, response.StatusCode);

        // Verify it's revoked in the list
        var listResp = await client.GetAsync($"/api/admin/tenants/{tenantId}/invitations");
        var listBody = await listResp.Content.ReadFromJsonAsync<JsonElement>(TestFixture.Json);
        var items = listBody.GetProperty("items");
        var inv = items.EnumerateArray().First();
        Assert.Equal("revoked", inv.GetProperty("status").GetString());
    }

    [Fact]
    public async Task RevokeInvitation_NotFound_Returns404()
    {
        var (client, tenantId) = await CreateAdminWithTenant("RevokeNotFoundAdmin");
        var response = await client.DeleteAsync($"/api/admin/tenants/{tenantId}/invitations/{Guid.NewGuid()}");
        Assert.Equal(HttpStatusCode.NotFound, response.StatusCode);
    }

    [Fact]
    public async Task RevokeInvitation_AlreadyAccepted_Returns400()
    {
        var (client, tenantId) = await CreateAdminWithTenant("RevokeAcceptedAdmin");
        var createResp = await client.PostAsJsonAsync(
            $"/api/admin/tenants/{tenantId}/invitations",
            new { email = "accepted@test.com", role = "admin" }, TestFixture.Json);
        var created = await createResp.Content.ReadFromJsonAsync<JsonElement>(TestFixture.Json);
        var invitationId = created.GetProperty("id").GetGuid();

        // Manually set status to Accepted via DB
        using var scope = _factory.Services.CreateScope();
        var db = scope.ServiceProvider.GetRequiredService<SsdidDrive.Api.Data.AppDbContext>();
        var invitation = await db.Invitations.FindAsync(invitationId);
        invitation!.Status = SsdidDrive.Api.Data.Entities.InvitationStatus.Accepted;
        await db.SaveChangesAsync();

        var response = await client.DeleteAsync($"/api/admin/tenants/{tenantId}/invitations/{invitationId}");
        Assert.Equal(HttpStatusCode.BadRequest, response.StatusCode);
    }
```

- [ ] **Step 2: Run tests to verify new ones fail**

Run: `dotnet test tests/SsdidDrive.Api.Tests/ --filter "FullyQualifiedName~AdminInvitationTests" -v minimal`
Expected: New list/revoke tests FAIL, creation tests still PASS.

- [ ] **Step 3: Commit failing tests**

```bash
git add tests/SsdidDrive.Api.Tests/Integration/AdminInvitationTests.cs
git commit -m "test: add failing tests for list and revoke admin invitations"
```

---

### Task 5: Implement List and Revoke endpoints

**Files:**
- Create: `src/SsdidDrive.Api/Features/Admin/ListAdminInvitations.cs`
- Create: `src/SsdidDrive.Api/Features/Admin/RevokeAdminInvitation.cs`
- Modify: `src/SsdidDrive.Api/Features/Admin/AdminFeature.cs`

- [ ] **Step 1: Create ListAdminInvitations.cs**

```csharp
// src/SsdidDrive.Api/Features/Admin/ListAdminInvitations.cs
using Microsoft.EntityFrameworkCore;
using SsdidDrive.Api.Common;
using SsdidDrive.Api.Data;

namespace SsdidDrive.Api.Features.Admin;

public static class ListAdminInvitations
{
    public static void Map(RouteGroupBuilder group) =>
        group.MapGet("/tenants/{tenantId:guid}/invitations", Handle);

    private static async Task<IResult> Handle(
        Guid tenantId, [AsParameters] PaginationParams pagination,
        AppDbContext db, CancellationToken ct)
    {
        var tenantExists = await db.Tenants.AnyAsync(t => t.Id == tenantId, ct);
        if (!tenantExists)
            return AppError.NotFound("Tenant not found").ToProblemResult();

        var query = db.Invitations
            .Where(i => i.TenantId == tenantId)
            .OrderByDescending(i => i.CreatedAt);

        var total = await query.CountAsync(ct);

        var items = await query
            .Skip(pagination.Skip)
            .Take(pagination.Take)
            .Select(i => new
            {
                id = i.Id,
                tenant_id = i.TenantId,
                invited_by_id = i.InvitedById,
                email = i.Email,
                invited_user_id = i.InvitedUserId,
                role = i.Role.ToString().ToLowerInvariant(),
                status = i.Status.ToString().ToLowerInvariant(),
                short_code = i.ShortCode,
                message = i.Message,
                expires_at = i.ExpiresAt,
                created_at = i.CreatedAt
            })
            .ToListAsync(ct);

        return Results.Ok(new
        {
            items,
            total,
            page = pagination.NormalizedPage,
            page_size = pagination.Take
        });
    }
}
```

- [ ] **Step 2: Create RevokeAdminInvitation.cs**

```csharp
// src/SsdidDrive.Api/Features/Admin/RevokeAdminInvitation.cs
using Microsoft.EntityFrameworkCore;
using SsdidDrive.Api.Common;
using SsdidDrive.Api.Data;
using SsdidDrive.Api.Data.Entities;
using SsdidDrive.Api.Services;

namespace SsdidDrive.Api.Features.Admin;

public static class RevokeAdminInvitation
{
    public static void Map(RouteGroupBuilder group) =>
        group.MapDelete("/tenants/{tenantId:guid}/invitations/{id:guid}", Handle);

    private static async Task<IResult> Handle(
        Guid tenantId, Guid id, AppDbContext db,
        CurrentUserAccessor accessor, AuditService audit, CancellationToken ct)
    {
        var invitation = await db.Invitations
            .FirstOrDefaultAsync(i => i.Id == id && i.TenantId == tenantId, ct);

        if (invitation is null)
            return AppError.NotFound("Invitation not found").ToProblemResult();

        if (invitation.Status != InvitationStatus.Pending)
            return AppError.BadRequest("Only pending invitations can be revoked").ToProblemResult();

        invitation.Status = InvitationStatus.Revoked;
        invitation.UpdatedAt = DateTimeOffset.UtcNow;
        await db.SaveChangesAsync(ct);

        await audit.LogAsync(accessor.User!.Id, "invitation.revoked",
            "Invitation", invitation.Id,
            $"Revoked invitation for {invitation.Email} to tenant {tenantId}", ct);

        return Results.NoContent();
    }
}
```

- [ ] **Step 3: Register both in AdminFeature.cs**

In `src/SsdidDrive.Api/Features/Admin/AdminFeature.cs`, add after `CreateAdminInvitation.Map(group);`:
```csharp
        ListAdminInvitations.Map(group);
        RevokeAdminInvitation.Map(group);
```

- [ ] **Step 4: Run all admin invitation tests**

Run: `dotnet test tests/SsdidDrive.Api.Tests/ --filter "FullyQualifiedName~AdminInvitationTests" -v minimal`
Expected: All tests PASS.

- [ ] **Step 5: Run full test suite to check for regressions**

Run: `dotnet test tests/SsdidDrive.Api.Tests/ -v minimal`
Expected: All tests PASS.

- [ ] **Step 6: Commit**

```bash
git add src/SsdidDrive.Api/Features/Admin/ListAdminInvitations.cs src/SsdidDrive.Api/Features/Admin/RevokeAdminInvitation.cs src/SsdidDrive.Api/Features/Admin/AdminFeature.cs
git commit -m "feat: add list and revoke endpoints for admin tenant invitations"
```

---

## Chunk 2: Frontend

### Task 6: Add invitation state to adminStore

**Files:**
- Modify: `clients/admin/src/stores/adminStore.ts`

- [ ] **Step 1: Add AdminInvitation interface and state**

In `clients/admin/src/stores/adminStore.ts`, add after the `TenantMember` interface (line 32):

```typescript
export interface AdminInvitation {
  id: string
  tenant_id: string
  invited_by_id: string
  email: string | null
  invited_user_id: string | null
  role: string
  status: string
  short_code: string
  message: string | null
  expires_at: string
  created_at: string
}

interface AdminInvitationsResponse {
  items: AdminInvitation[]
  total: number
  page: number
  page_size: number
}
```

- [ ] **Step 2: Add invitation state and methods to AdminState interface**

Add to the `AdminState` interface (after `fetchTenantMembers`, around line 87):

```typescript
  tenantInvitations: AdminInvitation[]
  tenantInvitationsTotal: number
  tenantInvitationsLoading: boolean
  fetchTenantInvitations: (tenantId: string, page?: number, pageSize?: number) => Promise<void>
  createAdminInvitation: (tenantId: string, email: string, role: string, message?: string) => Promise<AdminInvitation>
  revokeAdminInvitation: (tenantId: string, invitationId: string) => Promise<void>
```

- [ ] **Step 3: Add implementation to the store**

Add after `fetchTenantMembers` implementation (after line 181):

```typescript
  tenantInvitations: [],
  tenantInvitationsTotal: 0,
  tenantInvitationsLoading: false,

  fetchTenantInvitations: async (tenantId: string, page = 1, pageSize = 20) => {
    set({ tenantInvitationsLoading: true })
    try {
      const res = await api.get<AdminInvitationsResponse>(
        `/api/admin/tenants/${tenantId}/invitations?page=${page}&page_size=${pageSize}`)
      set({ tenantInvitations: res.items, tenantInvitationsTotal: res.total })
    } catch (err) {
      set({ tenantInvitations: [], tenantInvitationsTotal: 0 })
      throw err
    } finally {
      set({ tenantInvitationsLoading: false })
    }
  },

  createAdminInvitation: async (tenantId: string, email: string, role: string, message?: string) => {
    const body: Record<string, string> = { email, role }
    if (message) body.message = message
    return api.post<AdminInvitation>(`/api/admin/tenants/${tenantId}/invitations`, body)
  },

  revokeAdminInvitation: async (tenantId: string, invitationId: string) => {
    await api.delete(`/api/admin/tenants/${tenantId}/invitations/${invitationId}`)
    set({
      tenantInvitations: get().tenantInvitations.map((inv) =>
        inv.id === invitationId ? { ...inv, status: 'revoked' } : inv
      ),
    })
  },
```

- [ ] **Step 4: Commit**

```bash
git add clients/admin/src/stores/adminStore.ts
git commit -m "feat: add invitation state and actions to admin store"
```

---

### Task 7: Create InviteUserDialog component

**Files:**
- Create: `clients/admin/src/components/InviteUserDialog.tsx`

- [ ] **Step 1: Create InviteUserDialog.tsx**

```tsx
// clients/admin/src/components/InviteUserDialog.tsx
import { useState, useEffect } from 'react'
import { useAdminStore } from '../stores/adminStore'
import type { AdminInvitation } from '../stores/adminStore'

interface InviteUserDialogProps {
  open: boolean
  onClose: () => void
  tenantId: string
  tenantName: string
  onInvited: () => void
}

export default function InviteUserDialog({
  open,
  onClose,
  tenantId,
  tenantName,
  onInvited,
}: InviteUserDialogProps) {
  const createAdminInvitation = useAdminStore((s) => s.createAdminInvitation)

  const [email, setEmail] = useState('')
  const [role, setRole] = useState<'owner' | 'admin'>('owner')
  const [message, setMessage] = useState('')
  const [submitting, setSubmitting] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const [success, setSuccess] = useState<AdminInvitation | null>(null)
  const [copied, setCopied] = useState(false)

  useEffect(() => {
    if (open) {
      setEmail('')
      setRole('owner')
      setMessage('')
      setSubmitting(false)
      setError(null)
      setSuccess(null)
      setCopied(false)
    }
  }, [open])

  useEffect(() => {
    if (!open) return
    const handleKeyDown = (e: KeyboardEvent) => {
      if (e.key === 'Escape' && !submitting) onClose()
    }
    document.addEventListener('keydown', handleKeyDown)
    return () => document.removeEventListener('keydown', handleKeyDown)
  }, [open, submitting, onClose])

  if (!open) return null

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault()
    if (!email.trim()) return

    setSubmitting(true)
    setError(null)
    try {
      const invitation = await createAdminInvitation(
        tenantId, email.trim(), role, message.trim() || undefined)
      setSuccess(invitation)
      onInvited()
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Failed to create invitation')
    } finally {
      setSubmitting(false)
    }
  }

  const handleCopy = async () => {
    if (!success) return
    await navigator.clipboard.writeText(success.short_code)
    setCopied(true)
    setTimeout(() => setCopied(false), 2000)
  }

  return (
    <div
      className="fixed inset-0 z-50 flex items-center justify-center bg-black/40 backdrop-blur-sm"
      role="dialog"
      aria-modal="true"
      aria-labelledby="invite-user-title"
      onClick={() => !submitting && onClose()}
    >
      <div
        className="bg-white rounded-xl shadow-xl w-full max-w-md p-6"
        onClick={(e) => e.stopPropagation()}
      >
        {success ? (
          <div className="text-center">
            <div className="w-12 h-12 bg-green-100 rounded-full flex items-center justify-center mx-auto mb-4">
              <svg className="w-6 h-6 text-green-600" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M5 13l4 4L19 7" />
              </svg>
            </div>
            <h3 className="text-lg font-semibold mb-1">Invitation Sent!</h3>
            <p className="text-gray-500 text-sm mb-5">Share this code with the invited user</p>

            <div className="bg-gray-50 border border-gray-200 rounded-lg p-4 mb-2 flex items-center justify-center gap-3">
              <span className="font-mono text-2xl font-bold tracking-wider">
                {success.short_code}
              </span>
              <button
                onClick={handleCopy}
                className="px-3 py-1 border border-gray-300 rounded-md text-xs text-gray-700 hover:bg-gray-100"
              >
                {copied ? 'Copied!' : 'Copy'}
              </button>
            </div>
            <p className="text-gray-400 text-xs mb-5">Expires in 7 days</p>

            <button
              onClick={onClose}
              className="px-6 py-2 border border-gray-300 rounded-lg text-sm text-gray-700 hover:bg-gray-50"
            >
              Close
            </button>
          </div>
        ) : (
          <>
            <h3 id="invite-user-title" className="text-lg font-semibold mb-1">
              Invite User
            </h3>
            <p className="text-gray-500 text-sm mb-5">
              Invite a user to <strong>{tenantName}</strong>
            </p>

            {error && (
              <div className="bg-red-50 border border-red-200 text-red-700 rounded-lg p-3 mb-4 text-sm">
                {error}
              </div>
            )}

            <form onSubmit={handleSubmit} className="space-y-4">
              <div>
                <label htmlFor="invite-email" className="block text-sm font-medium text-gray-700 mb-1">
                  Email
                </label>
                <input
                  id="invite-email"
                  type="email"
                  value={email}
                  onChange={(e) => setEmail(e.target.value)}
                  placeholder="user@example.com"
                  className="w-full border border-gray-300 rounded-lg px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-blue-500 focus:border-transparent"
                  required
                  autoFocus
                />
              </div>

              <div>
                <label className="block text-sm font-medium text-gray-700 mb-1">Role</label>
                <div className="flex gap-2">
                  <button
                    type="button"
                    onClick={() => setRole('owner')}
                    className={`flex-1 p-3 rounded-lg border-2 text-center transition-colors ${
                      role === 'owner'
                        ? 'border-blue-600 bg-blue-50'
                        : 'border-gray-200 bg-white hover:border-gray-300'
                    }`}
                  >
                    <div className={`font-semibold text-sm ${role === 'owner' ? 'text-blue-700' : 'text-gray-700'}`}>
                      Owner
                    </div>
                    <div className="text-xs text-gray-500 mt-0.5">Full tenant control</div>
                  </button>
                  <button
                    type="button"
                    onClick={() => setRole('admin')}
                    className={`flex-1 p-3 rounded-lg border-2 text-center transition-colors ${
                      role === 'admin'
                        ? 'border-blue-600 bg-blue-50'
                        : 'border-gray-200 bg-white hover:border-gray-300'
                    }`}
                  >
                    <div className={`font-semibold text-sm ${role === 'admin' ? 'text-blue-700' : 'text-gray-700'}`}>
                      Admin
                    </div>
                    <div className="text-xs text-gray-500 mt-0.5">Manage members</div>
                  </button>
                </div>
              </div>

              <div>
                <label htmlFor="invite-message" className="block text-sm font-medium text-gray-700 mb-1">
                  Message <span className="font-normal text-gray-400">(optional)</span>
                </label>
                <textarea
                  id="invite-message"
                  value={message}
                  onChange={(e) => setMessage(e.target.value)}
                  placeholder="Personal message to include with the invitation..."
                  maxLength={500}
                  rows={2}
                  className="w-full border border-gray-300 rounded-lg px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-blue-500 focus:border-transparent resize-vertical"
                />
              </div>

              <div className="flex justify-end gap-3 pt-2">
                <button
                  type="button"
                  onClick={onClose}
                  disabled={submitting}
                  className="px-4 py-2 text-sm text-gray-700 border border-gray-300 rounded-lg hover:bg-gray-50 disabled:opacity-50"
                >
                  Cancel
                </button>
                <button
                  type="submit"
                  disabled={submitting || !email.trim()}
                  className="px-4 py-2 text-sm text-white bg-blue-600 rounded-lg hover:bg-blue-700 disabled:opacity-50 disabled:cursor-not-allowed"
                >
                  {submitting ? 'Sending...' : 'Send Invitation'}
                </button>
              </div>
            </form>
          </>
        )}
      </div>
    </div>
  )
}
```

- [ ] **Step 2: Commit**

```bash
git add clients/admin/src/components/InviteUserDialog.tsx
git commit -m "feat: add InviteUserDialog component for admin portal"
```

---

### Task 8: Update TenantDetailPage with invite button and pending invitations

**Files:**
- Modify: `clients/admin/src/pages/TenantDetailPage.tsx`

- [ ] **Step 1: Add imports and invitation state**

At the top of `TenantDetailPage.tsx`, update the import from adminStore to include `AdminInvitation`:
```typescript
import type { Column } from '../components/DataTable'
import { useAdminStore } from '../stores/adminStore'
import type { Tenant, TenantMember, AdminInvitation } from '../stores/adminStore'
```

Add import for InviteUserDialog:
```typescript
import InviteUserDialog from '../components/InviteUserDialog'
```

Add import for `formatDate` (already imported) — no change needed.

- [ ] **Step 2: Add invitation state and effects to the component**

Inside the `TenantDetailPage` component function, after the existing state/effects (after line 56), add:

```typescript
  const {
    tenantInvitations,
    tenantInvitationsLoading,
    fetchTenantInvitations,
    revokeAdminInvitation,
  } = useAdminStore()

  const [inviteOpen, setInviteOpen] = useState(false)
  const [revoking, setRevoking] = useState<string | null>(null)
  const [invError, setInvError] = useState<string | null>(null)
```

Update the destructuring at the top of the component to pull these from the store (merge with existing destructuring).

Add an effect to fetch invitations:
```typescript
  useEffect(() => {
    if (!id) return
    fetchTenantInvitations(id).catch(() => {})
  }, [id, fetchTenantInvitations])
```

Add a revoke handler:
```typescript
  const handleRevoke = async (invitationId: string) => {
    if (!id) return
    if (!confirm('Are you sure you want to revoke this invitation?')) return
    setRevoking(invitationId)
    setInvError(null)
    try {
      await revokeAdminInvitation(id, invitationId)
      await fetchTenantInvitations(id)
    } catch (err) {
      setInvError(err instanceof Error ? err.message : 'Failed to revoke invitation')
    } finally {
      setRevoking(null)
    }
  }
```

- [ ] **Step 3: Add invite button next to Members heading**

Replace the Members heading (line 148):
```tsx
      <h3 className="text-lg font-semibold mb-3">Members</h3>
```
With:
```tsx
      <div className="flex items-center justify-between mb-3">
        <h3 className="text-lg font-semibold">Members</h3>
        <button
          onClick={() => setInviteOpen(true)}
          className="flex items-center gap-1.5 px-4 py-2 text-sm text-white bg-blue-600 rounded-lg hover:bg-blue-700"
        >
          <span className="text-base leading-none">+</span> Invite User
        </button>
      </div>
```

- [ ] **Step 4: Add pending invitations section after the members DataTable**

After the closing `/>` of the DataTable (line 154), add:

```tsx
      {/* Pending Invitations */}
      <div className="mt-8">
        <h3 className="text-lg font-semibold mb-3">Pending Invitations</h3>

        {invError && (
          <div className="bg-red-50 border border-red-200 text-red-700 rounded-lg p-3 mb-4 text-sm">
            {invError}
          </div>
        )}

        {tenantInvitationsLoading ? (
          <div className="bg-white rounded-lg shadow p-6 animate-pulse">
            <div className="h-4 bg-gray-200 rounded w-1/3 mb-4" />
            <div className="h-4 bg-gray-200 rounded w-full mb-2" />
            <div className="h-4 bg-gray-200 rounded w-2/3" />
          </div>
        ) : tenantInvitations.length === 0 ? (
          <div className="bg-white rounded-lg shadow p-6 text-center text-gray-500 text-sm">
            No invitations for this tenant.
          </div>
        ) : (
          <div className="bg-white rounded-lg shadow overflow-hidden">
            <table className="w-full text-sm">
              <thead>
                <tr className="border-b border-gray-200">
                  <th className="text-left px-4 py-3 text-gray-500 font-medium">Email</th>
                  <th className="text-left px-4 py-3 text-gray-500 font-medium">Role</th>
                  <th className="text-left px-4 py-3 text-gray-500 font-medium">Code</th>
                  <th className="text-left px-4 py-3 text-gray-500 font-medium">Status</th>
                  <th className="text-left px-4 py-3 text-gray-500 font-medium">Sent</th>
                  <th className="text-left px-4 py-3 text-gray-500 font-medium">Expires</th>
                  <th className="text-right px-4 py-3 text-gray-500 font-medium"></th>
                </tr>
              </thead>
              <tbody>
                {tenantInvitations.map((inv) => (
                  <tr key={inv.id} className="border-b border-gray-100 last:border-0">
                    <td className="px-4 py-3">{inv.email || '\u2014'}</td>
                    <td className="px-4 py-3">
                      <RoleBadge role={inv.role} />
                    </td>
                    <td className="px-4 py-3 font-mono text-xs">{inv.short_code}</td>
                    <td className="px-4 py-3">
                      <span className={`inline-block px-2 py-0.5 rounded-full text-xs font-medium capitalize ${
                        inv.status === 'pending' ? 'bg-yellow-100 text-yellow-800' :
                        inv.status === 'accepted' ? 'bg-green-100 text-green-800' :
                        inv.status === 'revoked' ? 'bg-red-100 text-red-800' :
                        'bg-gray-100 text-gray-700'
                      }`}>
                        {inv.status}
                      </span>
                    </td>
                    <td className="px-4 py-3">{formatDate(inv.created_at)}</td>
                    <td className="px-4 py-3">{formatDate(inv.expires_at)}</td>
                    <td className="px-4 py-3 text-right">
                      {inv.status === 'pending' && (
                        <button
                          onClick={() => handleRevoke(inv.id)}
                          disabled={revoking === inv.id}
                          className="px-3 py-1 text-xs border border-red-300 text-red-600 rounded-md hover:bg-red-50 disabled:opacity-50"
                        >
                          {revoking === inv.id ? 'Revoking...' : 'Revoke'}
                        </button>
                      )}
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </div>

      {/* Invite Dialog */}
      {tenant && (
        <InviteUserDialog
          open={inviteOpen}
          onClose={() => setInviteOpen(false)}
          tenantId={id!}
          tenantName={tenant.name}
          onInvited={() => fetchTenantInvitations(id!)}
        />
      )}
```

- [ ] **Step 5: Verify admin portal builds**

Run: `cd clients/admin && npx tsc --noEmit`
Expected: No type errors.

- [ ] **Step 6: Commit**

```bash
git add clients/admin/src/pages/TenantDetailPage.tsx
git commit -m "feat: add invite button and pending invitations to TenantDetailPage"
```

---

### Task 9: Set up vitest and add frontend tests for admin portal

**Files:**
- Modify: `clients/admin/package.json`
- Modify: `clients/admin/vite.config.ts`
- Create: `clients/admin/src/components/__tests__/InviteUserDialog.test.tsx`
- Create: `clients/admin/src/pages/__tests__/TenantDetailPage.test.tsx`
- Create: `clients/admin/src/test-setup.ts`

- [ ] **Step 1: Install vitest and testing-library dependencies**

Run: `cd clients/admin && npm install -D vitest @testing-library/react @testing-library/jest-dom @testing-library/user-event jsdom`

- [ ] **Step 2: Add test config to vite.config.ts**

In `clients/admin/vite.config.ts`, add the test configuration:

```typescript
import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'
import tailwindcss from '@tailwindcss/vite'

export default defineConfig({
  plugins: [react(), tailwindcss()],
  base: '/admin/',
  build: {
    outDir: '../../src/SsdidDrive.Api/wwwroot/admin',
    emptyOutDir: true,
  },
  server: {
    port: 5174,
    proxy: {
      '/api': {
        target: 'http://localhost:5139',
        changeOrigin: true,
      },
    },
  },
  test: {
    environment: 'jsdom',
    setupFiles: ['./src/test-setup.ts'],
    globals: true,
  },
})
```

- [ ] **Step 3: Create test setup file**

```typescript
// clients/admin/src/test-setup.ts
import '@testing-library/jest-dom/vitest'
```

- [ ] **Step 4: Add test script to package.json**

In `clients/admin/package.json`, add to scripts:
```json
"test": "vitest run",
"test:watch": "vitest"
```

- [ ] **Step 5: Write InviteUserDialog tests**

```tsx
// clients/admin/src/components/__tests__/InviteUserDialog.test.tsx
import { describe, it, expect, vi, beforeEach } from 'vitest'
import { render, screen, fireEvent, waitFor } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import InviteUserDialog from '../InviteUserDialog'
import { useAdminStore } from '../../stores/adminStore'

// Mock the store
vi.mock('../../stores/adminStore', () => ({
  useAdminStore: vi.fn(),
}))

const mockCreateAdminInvitation = vi.fn()

beforeEach(() => {
  vi.clearAllMocks()
  ;(useAdminStore as unknown as ReturnType<typeof vi.fn>).mockImplementation(
    (selector: (s: unknown) => unknown) =>
      selector({ createAdminInvitation: mockCreateAdminInvitation })
  )
})

describe('InviteUserDialog', () => {
  const defaultProps = {
    open: true,
    onClose: vi.fn(),
    tenantId: 'tenant-123',
    tenantName: 'Acme Corp',
    onInvited: vi.fn(),
  }

  it('renders email, role toggle, and message fields', () => {
    render(<InviteUserDialog {...defaultProps} />)
    expect(screen.getByLabelText('Email')).toBeInTheDocument()
    expect(screen.getByText('Owner')).toBeInTheDocument()
    expect(screen.getByText('Admin')).toBeInTheDocument()
    expect(screen.getByLabelText(/Message/)).toBeInTheDocument()
  })

  it('does not render when closed', () => {
    render(<InviteUserDialog {...defaultProps} open={false} />)
    expect(screen.queryByText('Invite User')).not.toBeInTheDocument()
  })

  it('defaults to Owner role', () => {
    render(<InviteUserDialog {...defaultProps} />)
    const ownerBtn = screen.getByText('Owner').closest('button')!
    expect(ownerBtn.className).toContain('border-blue-600')
  })

  it('toggles between Owner and Admin roles', async () => {
    const user = userEvent.setup()
    render(<InviteUserDialog {...defaultProps} />)

    const adminBtn = screen.getByText('Admin').closest('button')!
    await user.click(adminBtn)
    expect(adminBtn.className).toContain('border-blue-600')

    const ownerBtn = screen.getByText('Owner').closest('button')!
    expect(ownerBtn.className).not.toContain('border-blue-600')
  })

  it('calls createAdminInvitation with correct params on submit', async () => {
    const user = userEvent.setup()
    mockCreateAdminInvitation.mockResolvedValue({
      id: 'inv-1',
      short_code: 'ACME-X7K2',
      status: 'pending',
    })

    render(<InviteUserDialog {...defaultProps} />)

    await user.type(screen.getByLabelText('Email'), 'test@example.com')
    await user.click(screen.getByText('Send Invitation'))

    await waitFor(() => {
      expect(mockCreateAdminInvitation).toHaveBeenCalledWith(
        'tenant-123', 'test@example.com', 'owner', undefined
      )
    })
  })

  it('shows success state with invite code after creation', async () => {
    const user = userEvent.setup()
    mockCreateAdminInvitation.mockResolvedValue({
      id: 'inv-1',
      short_code: 'ACME-X7K2',
      status: 'pending',
    })

    render(<InviteUserDialog {...defaultProps} />)

    await user.type(screen.getByLabelText('Email'), 'test@example.com')
    await user.click(screen.getByText('Send Invitation'))

    await waitFor(() => {
      expect(screen.getByText('Invitation Sent!')).toBeInTheDocument()
      expect(screen.getByText('ACME-X7K2')).toBeInTheDocument()
      expect(screen.getByText('Copy')).toBeInTheDocument()
    })
  })

  it('shows error on failure', async () => {
    const user = userEvent.setup()
    mockCreateAdminInvitation.mockRejectedValue(new Error('Email already invited'))

    render(<InviteUserDialog {...defaultProps} />)

    await user.type(screen.getByLabelText('Email'), 'dup@example.com')
    await user.click(screen.getByText('Send Invitation'))

    await waitFor(() => {
      expect(screen.getByText('Email already invited')).toBeInTheDocument()
    })
  })
})
```

- [ ] **Step 6: Write TenantDetailPage invitation tests**

```tsx
// clients/admin/src/pages/__tests__/TenantDetailPage.test.tsx
import { describe, it, expect, vi, beforeEach } from 'vitest'
import { render, screen, waitFor } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { MemoryRouter, Route, Routes } from 'react-router-dom'
import TenantDetailPage from '../TenantDetailPage'
import { useAdminStore } from '../../stores/adminStore'

vi.mock('../../stores/adminStore', () => ({
  useAdminStore: vi.fn(),
}))

const mockStore = {
  tenants: [{ id: 't1', name: 'Acme', slug: 'acme', disabled: false, storage_quota_bytes: null, user_count: 2, created_at: '2026-03-01T00:00:00Z' }],
  tenantMembers: [
    { user_id: 'u1', did: 'did:ssdid:abc', display_name: 'John', email: 'john@acme.com', role: 'Owner' },
  ],
  tenantMembersLoading: false,
  tenantInvitations: [],
  tenantInvitationsLoading: false,
  tenantInvitationsTotal: 0,
  fetchTenantById: vi.fn(),
  fetchTenantMembers: vi.fn().mockResolvedValue(undefined),
  fetchTenantInvitations: vi.fn().mockResolvedValue(undefined),
  revokeAdminInvitation: vi.fn().mockResolvedValue(undefined),
  createAdminInvitation: vi.fn(),
}

beforeEach(() => {
  vi.clearAllMocks()
  ;(useAdminStore as unknown as ReturnType<typeof vi.fn>).mockImplementation(
    (selector: (s: unknown) => unknown) => selector(mockStore)
  )
})

function renderPage() {
  return render(
    <MemoryRouter initialEntries={['/tenants/t1']}>
      <Routes>
        <Route path="/tenants/:id" element={<TenantDetailPage />} />
      </Routes>
    </MemoryRouter>
  )
}

describe('TenantDetailPage — Invitations', () => {
  it('shows Invite User button', () => {
    renderPage()
    expect(screen.getByText('Invite User')).toBeInTheDocument()
  })

  it('shows empty state when no invitations', () => {
    renderPage()
    expect(screen.getByText('No invitations for this tenant.')).toBeInTheDocument()
  })

  it('renders pending invitations table', () => {
    mockStore.tenantInvitations = [
      { id: 'i1', tenant_id: 't1', invited_by_id: 'u1', email: 'new@acme.com', invited_user_id: null, role: 'owner', status: 'pending', short_code: 'ACME-X7K2', message: null, expires_at: '2026-03-19T00:00:00Z', created_at: '2026-03-12T00:00:00Z' },
    ]

    renderPage()
    expect(screen.getByText('new@acme.com')).toBeInTheDocument()
    expect(screen.getByText('ACME-X7K2')).toBeInTheDocument()
    expect(screen.getByText('Revoke')).toBeInTheDocument()
  })

  it('opens invite dialog on button click', async () => {
    const user = userEvent.setup()
    mockStore.tenantInvitations = []

    renderPage()
    await user.click(screen.getByText('Invite User'))

    await waitFor(() => {
      expect(screen.getByText(/Invite a user to/)).toBeInTheDocument()
    })
  })

  it('shows revoke button only for pending invitations', () => {
    mockStore.tenantInvitations = [
      { id: 'i1', tenant_id: 't1', invited_by_id: 'u1', email: 'a@b.com', invited_user_id: null, role: 'admin', status: 'accepted', short_code: 'ACME-1234', message: null, expires_at: '2026-03-19T00:00:00Z', created_at: '2026-03-12T00:00:00Z' },
    ]

    renderPage()
    expect(screen.queryByText('Revoke')).not.toBeInTheDocument()
  })
})
```

- [ ] **Step 7: Run frontend tests**

Run: `cd clients/admin && npm test`
Expected: All tests PASS.

- [ ] **Step 8: Commit**

```bash
git add clients/admin/package.json clients/admin/vite.config.ts clients/admin/src/test-setup.ts clients/admin/src/components/__tests__/InviteUserDialog.test.tsx clients/admin/src/pages/__tests__/TenantDetailPage.test.tsx
git commit -m "test: add vitest setup and frontend tests for admin invite UI"
```

---

### Task 10: Add role matrix documentation

**Files:**
- Create: `docs/role-matrix.md`

- [ ] **Step 1: Create role-matrix.md**

Copy the role matrix from the spec into a standalone document at `docs/role-matrix.md`:

```markdown
# SSDID Drive — Role Matrix

## System Roles

| Role | Scope | Description |
|------|-------|-------------|
| SuperAdmin | Platform | Full platform administration |

## Tenant Roles

| Role | Scope | Description |
|------|-------|-------------|
| Owner | Tenant | Full tenant control |
| Admin | Tenant | Member management (limited) |
| Member | Tenant | Standard access |

## Permission Matrix

| Action | SuperAdmin | Owner | Admin | Member |
|---|---|---|---|---|
| **Platform** | | | | |
| Create tenant | Yes | - | - | - |
| Edit/disable tenant | Yes | - | - | - |
| View all users | Yes | - | - | - |
| Suspend/activate user | Yes | - | - | - |
| Assign SuperAdmin role | Yes | - | - | - |
| View audit log | Yes | - | - | - |
| **Tenant Invitations** | | | | |
| Invite Owner | Yes | - | - | - |
| Invite Admin | Yes | Yes | - | - |
| Invite Member | - | Yes | Yes | - |
| Revoke own invitation | Yes | Yes | Yes | - |
| **Tenant Members** | | | | |
| View members | Yes | Yes | Yes | Yes |
| Change role to Owner | - | Yes | - | - |
| Change role to Admin | - | Yes | - | - |
| Change role to Member | - | Yes | Yes* | - |
| Remove member | - | Yes | Yes* | - |

*Admin can only manage Members, not other Admins or Owners. SuperAdmin does not invite Members — that's the responsibility of tenant Owners/Admins via the desktop client.
```

- [ ] **Step 2: Commit**

```bash
git add docs/role-matrix.md
git commit -m "docs: add role matrix for system and tenant permissions"
```

---

### Task 11: Final verification

- [ ] **Step 1: Run full backend test suite**

Run: `dotnet test tests/SsdidDrive.Api.Tests/ -v minimal`
Expected: All tests PASS.

- [ ] **Step 2: Verify admin portal compiles**

Run: `cd clients/admin && npx tsc --noEmit`
Expected: No type errors.

- [ ] **Step 3: Verify admin portal builds for production**

Run: `cd clients/admin && npm run build`
Expected: Build succeeds.
