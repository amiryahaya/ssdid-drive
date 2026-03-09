# Backend MVP Features Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Implement all high and medium priority backend API features needed for MVP: folder/file rename, share accept/reject, device enrollment, tenant invitations, notifications, account recovery, search/pagination, and WebAuthn/passkeys.

**Architecture:** Vertical slice (feature-based) Minimal API endpoints. Each feature gets a folder under `Features/`, entity classes under `Data/Entities/`, and EF Core migrations. All endpoints use snake_case JSON, RFC 7807 errors via `AppError`, and `CurrentUserAccessor` for auth.

**Tech Stack:** ASP.NET Core 10, EF Core + PostgreSQL, xUnit 3, in-memory SQLite for tests.

---

## Phase 1: Quick Wins (High Priority, Low Complexity)

### Task 1: Folder Rename Endpoint

**Files:**
- Create: `src/SsdidDrive.Api/Features/Folders/RenameFolder.cs`
- Test: `tests/SsdidDrive.Api.Tests/Features/Folders/RenameFolderTests.cs`

**Step 1: Write the failing test**

```csharp
// tests/SsdidDrive.Api.Tests/Features/Folders/RenameFolderTests.cs
using System.Net;
using System.Text.Json;
using SsdidDrive.Api.Tests.Infrastructure;

namespace SsdidDrive.Api.Tests.Features.Folders;

public class RenameFolderTests : IClassFixture<SsdidDriveFactory>
{
    private readonly SsdidDriveFactory _factory;
    public RenameFolderTests(SsdidDriveFactory factory) => _factory = factory;

    [Fact]
    public async Task RenameFolder_ValidName_ReturnsOk()
    {
        var (client, _, _) = await TestFixture.CreateAuthenticatedClientAsync(_factory);
        var folderId = await TestFixture.CreateFolderAsync(client, "Original Name");

        var response = await client.PatchAsJsonAsync($"/api/folders/{folderId}",
            new { name = "Renamed Folder" });

        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        var body = await response.Content.ReadFromJsonAsync<JsonElement>(TestFixture.Json);
        Assert.Equal("Renamed Folder", body.GetProperty("name").GetString());
    }

    [Fact]
    public async Task RenameFolder_NotOwner_ReturnsForbidden()
    {
        var (client1, _, tenantId) = await TestFixture.CreateAuthenticatedClientAsync(_factory, "Owner");
        var (client2, _) = await TestFixture.CreateUserInTenantAsync(_factory, tenantId, "Other");
        var folderId = await TestFixture.CreateFolderAsync(client1, "Owner's Folder");

        var response = await client2.PatchAsJsonAsync($"/api/folders/{folderId}",
            new { name = "Hijacked" });

        Assert.Equal(HttpStatusCode.Forbidden, response.StatusCode);
    }

    [Fact]
    public async Task RenameFolder_EmptyName_ReturnsBadRequest()
    {
        var (client, _, _) = await TestFixture.CreateAuthenticatedClientAsync(_factory);
        var folderId = await TestFixture.CreateFolderAsync(client, "Test");

        var response = await client.PatchAsJsonAsync($"/api/folders/{folderId}",
            new { name = "" });

        Assert.Equal(HttpStatusCode.BadRequest, response.StatusCode);
    }
}
```

**Step 2: Run tests to verify they fail**

Run: `dotnet test tests/SsdidDrive.Api.Tests/ --filter "RenameFolderTests"`
Expected: FAIL — 404 (endpoint doesn't exist)

**Step 3: Implement endpoint**

```csharp
// src/SsdidDrive.Api/Features/Folders/RenameFolder.cs
using Microsoft.EntityFrameworkCore;
using SsdidDrive.Api.Common;
using SsdidDrive.Api.Data;

namespace SsdidDrive.Api.Features.Folders;

public static class RenameFolder
{
    public record Request(string Name);

    public static void Map(RouteGroupBuilder group) =>
        group.MapPatch("/{id:guid}", Handle);

    private static async Task<IResult> Handle(
        Guid id, Request req, AppDbContext db,
        CurrentUserAccessor accessor, CancellationToken ct)
    {
        if (string.IsNullOrWhiteSpace(req.Name))
            return AppError.BadRequest("Name is required").ToProblemResult();

        var folder = await db.Folders.FirstOrDefaultAsync(f => f.Id == id, ct);
        if (folder is null)
            return AppError.NotFound("Folder not found").ToProblemResult();

        if (folder.OwnerId != accessor.User!.Id)
            return AppError.Forbidden("Only the owner can rename a folder").ToProblemResult();

        folder.Name = req.Name.Trim();
        folder.UpdatedAt = DateTimeOffset.UtcNow;
        await db.SaveChangesAsync(ct);

        return Results.Ok(new
        {
            folder.Id,
            folder.Name,
            folder.ParentFolderId,
            folder.OwnerId,
            folder.CreatedAt,
            folder.UpdatedAt
        });
    }
}
```

**Step 4: Register in FolderFeature.cs**

Add `RenameFolder.Map(group);` to `src/SsdidDrive.Api/Features/Folders/FolderFeature.cs`.

**Step 5: Run tests and verify they pass**

Run: `dotnet test tests/SsdidDrive.Api.Tests/ --filter "RenameFolderTests"`
Expected: PASS

**Step 6: Commit**

```bash
git add src/SsdidDrive.Api/Features/Folders/RenameFolder.cs \
        src/SsdidDrive.Api/Features/Folders/FolderFeature.cs \
        tests/SsdidDrive.Api.Tests/Features/Folders/RenameFolderTests.cs
git commit -m "feat(api): add PATCH /api/folders/{id} for rename"
```

---

### Task 2: File Rename Endpoint

**Files:**
- Create: `src/SsdidDrive.Api/Features/Files/RenameFile.cs`
- Test: `tests/SsdidDrive.Api.Tests/Features/Files/RenameFileTests.cs`

Same pattern as Task 1 but for `PATCH /api/files/{id:guid}`.

**Step 1: Write the failing test**

```csharp
// tests/SsdidDrive.Api.Tests/Features/Files/RenameFileTests.cs
using System.Net;
using System.Text.Json;
using SsdidDrive.Api.Tests.Infrastructure;

namespace SsdidDrive.Api.Tests.Features.Files;

public class RenameFileTests : IClassFixture<SsdidDriveFactory>
{
    private readonly SsdidDriveFactory _factory;
    public RenameFileTests(SsdidDriveFactory factory) => _factory = factory;

    [Fact]
    public async Task RenameFile_ValidName_ReturnsOk()
    {
        var (client, _, _) = await TestFixture.CreateAuthenticatedClientAsync(_factory);
        var folderId = await TestFixture.CreateFolderAsync(client, "Folder");
        var fileId = await TestFixture.UploadFileAsync(client, folderId, "original.txt", "content");

        var response = await client.PatchAsJsonAsync($"/api/files/{fileId}",
            new { name = "renamed.txt" });

        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        var body = await response.Content.ReadFromJsonAsync<JsonElement>(TestFixture.Json);
        Assert.Equal("renamed.txt", body.GetProperty("name").GetString());
    }

    [Fact]
    public async Task RenameFile_NotUploader_ReturnsForbidden()
    {
        var (client1, _, tenantId) = await TestFixture.CreateAuthenticatedClientAsync(_factory, "Uploader");
        var (client2, _) = await TestFixture.CreateUserInTenantAsync(_factory, tenantId, "Other");
        var folderId = await TestFixture.CreateFolderAsync(client1, "Folder");
        var fileId = await TestFixture.UploadFileAsync(client1, folderId, "test.txt", "data");

        var response = await client2.PatchAsJsonAsync($"/api/files/{fileId}",
            new { name = "hijacked.txt" });

        Assert.Equal(HttpStatusCode.Forbidden, response.StatusCode);
    }
}
```

**Step 2–6:** Same cycle as Task 1.

```csharp
// src/SsdidDrive.Api/Features/Files/RenameFile.cs
using Microsoft.EntityFrameworkCore;
using SsdidDrive.Api.Common;
using SsdidDrive.Api.Data;

namespace SsdidDrive.Api.Features.Files;

public static class RenameFile
{
    public record Request(string Name);

    public static void Map(RouteGroupBuilder group) =>
        group.MapPatch("/{id:guid}", Handle);

    private static async Task<IResult> Handle(
        Guid id, Request req, AppDbContext db,
        CurrentUserAccessor accessor, CancellationToken ct)
    {
        if (string.IsNullOrWhiteSpace(req.Name))
            return AppError.BadRequest("Name is required").ToProblemResult();

        var file = await db.Files.FirstOrDefaultAsync(f => f.Id == id, ct);
        if (file is null)
            return AppError.NotFound("File not found").ToProblemResult();

        if (file.UploadedById != accessor.User!.Id)
            return AppError.Forbidden("Only the uploader can rename a file").ToProblemResult();

        file.Name = req.Name.Trim();
        file.UpdatedAt = DateTimeOffset.UtcNow;
        await db.SaveChangesAsync(ct);

        return Results.Ok(new
        {
            file.Id,
            file.Name,
            file.ContentType,
            file.Size,
            file.FolderId,
            file.CreatedAt,
            file.UpdatedAt
        });
    }
}
```

Register `RenameFile.Map(group);` in `FileFeature.cs`.

```bash
git commit -m "feat(api): add PATCH /api/files/{id} for rename"
```

---

### Task 3: Share Details, Accept, Update Permission, Set Expiry

**Files:**
- Create: `src/SsdidDrive.Api/Features/Shares/GetShare.cs`
- Create: `src/SsdidDrive.Api/Features/Shares/UpdateSharePermission.cs`
- Create: `src/SsdidDrive.Api/Features/Shares/SetShareExpiry.cs`
- Modify: `src/SsdidDrive.Api/Features/Shares/ShareFeature.cs`
- Test: `tests/SsdidDrive.Api.Tests/Features/Shares/ShareManagementTests.cs`

**Endpoints:**
- `GET /api/shares/{id:guid}` — Get share details (owner or recipient)
- `PATCH /api/shares/{id:guid}/permission` — Update permission (owner only)
- `PATCH /api/shares/{id:guid}/expiry` — Set/remove expiry (owner only)

**Step 1: Write failing tests**

```csharp
// tests/SsdidDrive.Api.Tests/Features/Shares/ShareManagementTests.cs
namespace SsdidDrive.Api.Tests.Features.Shares;

public class ShareManagementTests : IClassFixture<SsdidDriveFactory>
{
    private readonly SsdidDriveFactory _factory;
    public ShareManagementTests(SsdidDriveFactory factory) => _factory = factory;

    [Fact]
    public async Task GetShare_AsOwner_ReturnsDetails()
    {
        var (client1, _, tenantId) = await TestFixture.CreateAuthenticatedClientAsync(_factory, "Owner");
        var (client2, userId2) = await TestFixture.CreateUserInTenantAsync(_factory, tenantId, "Recipient");
        var folderId = await TestFixture.CreateFolderAsync(client1, "Shared Folder");
        var (status, shareBody) = await TestFixture.CreateShareAsync(client1, folderId, userId2);
        var shareId = shareBody.GetProperty("id").GetGuid();

        var response = await client1.GetAsync($"/api/shares/{shareId}");

        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        var body = await response.Content.ReadFromJsonAsync<JsonElement>(TestFixture.Json);
        Assert.Equal("read", body.GetProperty("permission").GetString());
    }

    [Fact]
    public async Task UpdatePermission_AsOwner_ReturnsOk()
    {
        // Setup share, then PATCH permission to "write"
        // Assert 200 and permission changed
    }

    [Fact]
    public async Task SetExpiry_AsOwner_ReturnsOk()
    {
        // Setup share, then PATCH expiry
        // Assert 200 and expires_at set
    }

    [Fact]
    public async Task UpdatePermission_AsRecipient_ReturnsForbidden()
    {
        // Only the share owner can update permission
    }
}
```

**Step 2–6:** Implement each endpoint following the static class pattern. Register in `ShareFeature.cs`.

```bash
git commit -m "feat(api): add share details, permission update, and expiry endpoints"
```

---

## Phase 2: Device Enrollment (High Priority)

### Task 4: Device Entity + Migration

**Files:**
- Create: `src/SsdidDrive.Api/Data/Entities/Device.cs`
- Modify: `src/SsdidDrive.Api/Data/AppDbContext.cs`
- Migration: `dotnet ef migrations add AddDevices --project src/SsdidDrive.Api`

**Entity:**

```csharp
// src/SsdidDrive.Api/Data/Entities/Device.cs
namespace SsdidDrive.Api.Data.Entities;

public class Device
{
    public Guid Id { get; set; }
    public Guid UserId { get; set; }
    public string DeviceFingerprint { get; set; } = default!;
    public string? DeviceName { get; set; }
    public string Platform { get; set; } = default!;         // "android", "ios", "macos", "windows", "linux"
    public string? DeviceInfo { get; set; }                   // JSON (model, OS version, app version)
    public DeviceStatus Status { get; set; } = DeviceStatus.Active;
    public string KeyAlgorithm { get; set; } = default!;     // "kaz_sign", "ml_dsa"
    public byte[]? PublicKey { get; set; }                    // Device signing public key
    public DateTimeOffset? LastUsedAt { get; set; }
    public DateTimeOffset CreatedAt { get; set; }
    public DateTimeOffset UpdatedAt { get; set; }

    public User User { get; set; } = null!;
}

public enum DeviceStatus { Active, Suspended, Revoked }
```

**DbContext additions:**
- `public DbSet<Device> Devices => Set<Device>();`
- Table: `devices`, indexes on `(UserId, DeviceFingerprint)` unique, `UserId`
- Enum stored as lowercase string
- FK: `UserId` → User (Cascade)

```bash
dotnet ef migrations add AddDevices --project src/SsdidDrive.Api
git commit -m "feat(api): add Device entity and migration"
```

---

### Task 5: Device Enrollment Endpoints

**Files:**
- Create: `src/SsdidDrive.Api/Features/Devices/DeviceFeature.cs`
- Create: `src/SsdidDrive.Api/Features/Devices/EnrollDevice.cs`
- Create: `src/SsdidDrive.Api/Features/Devices/ListDevices.cs`
- Create: `src/SsdidDrive.Api/Features/Devices/UpdateDevice.cs`
- Create: `src/SsdidDrive.Api/Features/Devices/RevokeDevice.cs`
- Create: `src/SsdidDrive.Api/Features/Devices/GetCurrentDevice.cs`
- Modify: `src/SsdidDrive.Api/Program.cs` — add `app.MapDeviceFeature()`
- Test: `tests/SsdidDrive.Api.Tests/Features/Devices/DeviceTests.cs`

**Endpoints:**
- `POST /api/devices` — Enroll new device (fingerprint, platform, public key)
- `GET /api/devices` — List user's devices
- `GET /api/devices/current` — Get current device enrollment
- `PATCH /api/devices/{id:guid}` — Update device name
- `DELETE /api/devices/{id:guid}` — Revoke device

```bash
git commit -m "feat(api): add device enrollment CRUD endpoints"
```

---

## Phase 3: Tenant Invitations & Roles (High Priority)

### Task 6: Invitation Entity + Migration

**Files:**
- Create: `src/SsdidDrive.Api/Data/Entities/Invitation.cs`
- Modify: `src/SsdidDrive.Api/Data/AppDbContext.cs`
- Migration: `dotnet ef migrations add AddInvitations --project src/SsdidDrive.Api`

**Entity:**

```csharp
public class Invitation
{
    public Guid Id { get; set; }
    public Guid TenantId { get; set; }
    public Guid InvitedById { get; set; }
    public string? Email { get; set; }                        // Invited email (may not have account yet)
    public Guid? InvitedUserId { get; set; }                  // Set if user already exists
    public TenantRole Role { get; set; } = TenantRole.Member;
    public InvitationStatus Status { get; set; } = InvitationStatus.Pending;
    public string Token { get; set; } = default!;             // Deep link token
    public string? Message { get; set; }                      // Optional invite message
    public DateTimeOffset ExpiresAt { get; set; }
    public DateTimeOffset CreatedAt { get; set; }
    public DateTimeOffset UpdatedAt { get; set; }

    public Tenant Tenant { get; set; } = null!;
    public User InvitedBy { get; set; } = null!;
    public User? InvitedUser { get; set; }
}

public enum InvitationStatus { Pending, Accepted, Declined, Expired, Revoked }
```

```bash
git commit -m "feat(api): add Invitation entity and migration"
```

---

### Task 7: Invitation Endpoints

**Files:**
- Create: `src/SsdidDrive.Api/Features/Invitations/InvitationFeature.cs`
- Create: `src/SsdidDrive.Api/Features/Invitations/CreateInvitation.cs`
- Create: `src/SsdidDrive.Api/Features/Invitations/ListInvitations.cs`
- Create: `src/SsdidDrive.Api/Features/Invitations/AcceptInvitation.cs`
- Create: `src/SsdidDrive.Api/Features/Invitations/DeclineInvitation.cs`
- Create: `src/SsdidDrive.Api/Features/Invitations/RevokeInvitation.cs`
- Create: `src/SsdidDrive.Api/Features/Invitations/GetInvitationByToken.cs`
- Modify: `src/SsdidDrive.Api/Program.cs`
- Test: `tests/SsdidDrive.Api.Tests/Features/Invitations/InvitationTests.cs`

**Endpoints:**
- `POST /api/invitations` — Create invitation (Admin/Owner only)
- `GET /api/invitations` — List pending invitations for current user
- `GET /api/invitations/sent` — List invitations sent by current user
- `GET /api/invitations/token/{token}` — Validate invitation token (public, for deep links)
- `POST /api/invitations/{id:guid}/accept` — Accept invitation
- `POST /api/invitations/{id:guid}/decline` — Decline invitation
- `DELETE /api/invitations/{id:guid}` — Revoke invitation (creator only)

**Key logic:**
- Creating invitation requires Admin or Owner role in the tenant (`UserTenant.Role`)
- Accepting adds a `UserTenant` row with the invited role
- Token-based lookup is public (unauthenticated) for deep link validation
- Invitations expire (default 7 days)

```bash
git commit -m "feat(api): add tenant invitation endpoints"
```

---

### Task 8: Tenant Member Management

**Files:**
- Create: `src/SsdidDrive.Api/Features/Tenants/TenantFeature.cs`
- Create: `src/SsdidDrive.Api/Features/Tenants/ListMembers.cs`
- Create: `src/SsdidDrive.Api/Features/Tenants/UpdateMemberRole.cs`
- Create: `src/SsdidDrive.Api/Features/Tenants/RemoveMember.cs`
- Modify: `src/SsdidDrive.Api/Program.cs`
- Test: `tests/SsdidDrive.Api.Tests/Features/Tenants/TenantMemberTests.cs`

**Endpoints:**
- `GET /api/tenants/{id:guid}/members` — List tenant members with roles
- `PATCH /api/tenants/{id:guid}/members/{userId:guid}` — Update member role (Owner only)
- `DELETE /api/tenants/{id:guid}/members/{userId:guid}` — Remove member (Admin/Owner)

```bash
git commit -m "feat(api): add tenant member management endpoints"
```

---

## Phase 4: Notifications (Medium Priority)

### Task 9: Notification Entity + Migration

**Files:**
- Create: `src/SsdidDrive.Api/Data/Entities/Notification.cs`
- Modify: `src/SsdidDrive.Api/Data/AppDbContext.cs`
- Migration: `dotnet ef migrations add AddNotifications --project src/SsdidDrive.Api`

**Entity:**

```csharp
public class Notification
{
    public Guid Id { get; set; }
    public Guid UserId { get; set; }
    public string Type { get; set; } = default!;              // "share_received", "share_revoked", etc.
    public string Title { get; set; } = default!;
    public string Message { get; set; } = default!;
    public bool IsRead { get; set; }
    public string? ActionType { get; set; }                   // "open_share", "open_file", etc.
    public string? ActionResourceId { get; set; }             // ID of related resource
    public DateTimeOffset CreatedAt { get; set; }

    public User User { get; set; } = null!;
}
```

Table: `notifications`, indexes on `(UserId, IsRead)`, `(UserId, CreatedAt DESC)`.

```bash
git commit -m "feat(api): add Notification entity and migration"
```

---

### Task 10: Notification Endpoints

**Files:**
- Create: `src/SsdidDrive.Api/Features/Notifications/NotificationFeature.cs`
- Create: `src/SsdidDrive.Api/Features/Notifications/ListNotifications.cs`
- Create: `src/SsdidDrive.Api/Features/Notifications/GetUnreadCount.cs`
- Create: `src/SsdidDrive.Api/Features/Notifications/MarkAsRead.cs`
- Create: `src/SsdidDrive.Api/Features/Notifications/MarkAllAsRead.cs`
- Create: `src/SsdidDrive.Api/Features/Notifications/DeleteNotification.cs`
- Modify: `src/SsdidDrive.Api/Program.cs`
- Test: `tests/SsdidDrive.Api.Tests/Features/Notifications/NotificationTests.cs`

**Endpoints:**
- `GET /api/notifications` — List notifications (paginated, optional `?unread_only=true`)
- `GET /api/notifications/unread-count` — Get unread count
- `POST /api/notifications/{id:guid}/read` — Mark as read
- `POST /api/notifications/read-all` — Mark all as read
- `DELETE /api/notifications/{id:guid}` — Delete notification

**Helper service:** Create `NotificationService` to emit notifications from other features (e.g., when a share is created, notify the recipient).

```bash
git commit -m "feat(api): add notification endpoints and service"
```

---

## Phase 5: Search & Pagination (Medium Priority)

### Task 11: Add Pagination to List Endpoints

**Files:**
- Create: `src/SsdidDrive.Api/Common/PaginationParams.cs`
- Modify: `src/SsdidDrive.Api/Features/Folders/ListFolders.cs`
- Modify: `src/SsdidDrive.Api/Features/Files/ListFiles.cs` (or equivalent in upload endpoint)
- Modify: `src/SsdidDrive.Api/Features/Shares/ListCreatedShares.cs`
- Modify: `src/SsdidDrive.Api/Features/Shares/ListReceivedShares.cs`
- Test: `tests/SsdidDrive.Api.Tests/Features/PaginationTests.cs`

**Common pagination helper:**

```csharp
// src/SsdidDrive.Api/Common/PaginationParams.cs
public record PaginationParams(int Page = 1, int PageSize = 50, string? Search = null)
{
    public int Skip => (Math.Max(1, Page) - 1) * Math.Clamp(PageSize, 1, 100);
    public int Take => Math.Clamp(PageSize, 1, 100);
}

public record PagedResponse<T>(IReadOnlyList<T> Items, int Total, int Page, int PageSize)
{
    public int TotalPages => (int)Math.Ceiling((double)Total / PageSize);
}
```

**Query params:** `?page=1&page_size=50&search=report`

- Folders: search by name
- Files: search by name, filter by content_type
- Shares: no search, just pagination

```bash
git commit -m "feat(api): add pagination and search to list endpoints"
```

---

## Phase 6: Account Recovery (Medium Priority)

### Task 12: Recovery Entities + Migration

**Files:**
- Create: `src/SsdidDrive.Api/Data/Entities/RecoveryConfig.cs`
- Create: `src/SsdidDrive.Api/Data/Entities/RecoveryShare.cs`
- Create: `src/SsdidDrive.Api/Data/Entities/RecoveryRequest.cs`
- Modify: `src/SsdidDrive.Api/Data/AppDbContext.cs`
- Migration: `dotnet ef migrations add AddRecovery --project src/SsdidDrive.Api`

**Entities:**

```csharp
public class RecoveryConfig
{
    public Guid Id { get; set; }
    public Guid UserId { get; set; }
    public int Threshold { get; set; }          // Min shares needed (k)
    public int TotalShares { get; set; }        // Total shares (n)
    public bool IsActive { get; set; }
    public DateTimeOffset CreatedAt { get; set; }
    public User User { get; set; } = null!;
    public ICollection<RecoveryShare> Shares { get; set; } = [];
}

public class RecoveryShare
{
    public Guid Id { get; set; }
    public Guid RecoveryConfigId { get; set; }
    public Guid TrusteeId { get; set; }         // User who holds this share
    public byte[] EncryptedShare { get; set; } = default!;
    public RecoveryShareStatus Status { get; set; } = RecoveryShareStatus.Pending;
    public DateTimeOffset CreatedAt { get; set; }
    public RecoveryConfig Config { get; set; } = null!;
    public User Trustee { get; set; } = null!;
}

public enum RecoveryShareStatus { Pending, Accepted, Rejected }

public class RecoveryRequest
{
    public Guid Id { get; set; }
    public Guid RequesterId { get; set; }
    public Guid RecoveryConfigId { get; set; }
    public RecoveryRequestStatus Status { get; set; } = RecoveryRequestStatus.Pending;
    public int ApprovalsReceived { get; set; }
    public DateTimeOffset CreatedAt { get; set; }
    public DateTimeOffset? CompletedAt { get; set; }
    public User Requester { get; set; } = null!;
    public RecoveryConfig Config { get; set; } = null!;
}

public enum RecoveryRequestStatus { Pending, Approved, Completed, Rejected, Expired }
```

```bash
git commit -m "feat(api): add recovery entities (config, shares, requests)"
```

---

### Task 13: Recovery Endpoints

**Files:**
- Create: `src/SsdidDrive.Api/Features/Recovery/RecoveryFeature.cs`
- Create: `src/SsdidDrive.Api/Features/Recovery/SetupRecovery.cs`
- Create: `src/SsdidDrive.Api/Features/Recovery/CreateRecoveryShare.cs`
- Create: `src/SsdidDrive.Api/Features/Recovery/ListTrusteeShares.cs`
- Create: `src/SsdidDrive.Api/Features/Recovery/AcceptRecoveryShare.cs`
- Create: `src/SsdidDrive.Api/Features/Recovery/InitiateRecovery.cs`
- Create: `src/SsdidDrive.Api/Features/Recovery/ApproveRecovery.cs`
- Create: `src/SsdidDrive.Api/Features/Recovery/GetRecoveryStatus.cs`
- Modify: `src/SsdidDrive.Api/Program.cs`
- Test: `tests/SsdidDrive.Api.Tests/Features/Recovery/RecoveryTests.cs`

**Endpoints:**
- `POST /api/recovery/setup` — Configure recovery (threshold, total shares)
- `POST /api/recovery/shares` — Distribute encrypted share to trustee
- `GET /api/recovery/shares` — List shares held as trustee
- `POST /api/recovery/shares/{id:guid}/accept` — Accept a recovery share
- `POST /api/recovery/shares/{id:guid}/reject` — Reject a recovery share
- `POST /api/recovery/requests` — Initiate account recovery
- `POST /api/recovery/requests/{id:guid}/approve` — Approve recovery (trustee submits share)
- `GET /api/recovery/requests/{id:guid}` — Get recovery request status
- `GET /api/recovery/status` — Get current user's recovery config status

```bash
git commit -m "feat(api): add account recovery endpoints (Shamir)"
```

---

## Phase 7: WebAuthn / Passkeys (Medium Priority)

### Task 14: WebAuthn Credential Entity + Migration

**Files:**
- Create: `src/SsdidDrive.Api/Data/Entities/WebAuthnCredential.cs`
- Modify: `src/SsdidDrive.Api/Data/AppDbContext.cs`
- Migration: `dotnet ef migrations add AddWebAuthnCredentials --project src/SsdidDrive.Api`

**Entity:**

```csharp
public class WebAuthnCredential
{
    public Guid Id { get; set; }
    public Guid UserId { get; set; }
    public string CredentialId { get; set; } = default!;      // Base64url-encoded
    public byte[] PublicKey { get; set; } = default!;
    public string? Name { get; set; }                          // User-given name
    public long SignCount { get; set; }
    public DateTimeOffset? LastUsedAt { get; set; }
    public DateTimeOffset CreatedAt { get; set; }
    public User User { get; set; } = null!;
}
```

```bash
git commit -m "feat(api): add WebAuthnCredential entity and migration"
```

---

### Task 15: WebAuthn Endpoints

**Files:**
- Create: `src/SsdidDrive.Api/Features/Credentials/CredentialFeature.cs`
- Create: `src/SsdidDrive.Api/Features/Credentials/ListCredentials.cs`
- Create: `src/SsdidDrive.Api/Features/Credentials/RenameCredential.cs`
- Create: `src/SsdidDrive.Api/Features/Credentials/DeleteCredential.cs`
- Create: `src/SsdidDrive.Api/Features/Credentials/BeginAddCredential.cs`
- Create: `src/SsdidDrive.Api/Features/Credentials/CompleteAddCredential.cs`
- Modify: `src/SsdidDrive.Api/Program.cs`
- Test: `tests/SsdidDrive.Api.Tests/Features/Credentials/CredentialTests.cs`

**Endpoints:**
- `GET /api/credentials` — List user's credentials (passkeys + OIDC)
- `PATCH /api/credentials/{id:guid}` — Rename credential
- `DELETE /api/credentials/{id:guid}` — Delete credential (must keep at least 1)
- `POST /api/credentials/webauthn/begin` — Begin WebAuthn registration (returns challenge + options)
- `POST /api/credentials/webauthn/complete` — Complete WebAuthn registration (stores credential)

**Note:** WebAuthn server-side validation requires a FIDO2 library. Consider `Fido2.Models` NuGet package or implement minimal attestation verification.

```bash
git commit -m "feat(api): add WebAuthn credential management endpoints"
```

---

## Summary

| Phase | Tasks | Features |
|-------|-------|----------|
| 1 | 1–3 | Folder/file rename, share management |
| 2 | 4–5 | Device enrollment |
| 3 | 6–8 | Tenant invitations & member management |
| 4 | 9–10 | Notifications |
| 5 | 11 | Pagination & search |
| 6 | 12–13 | Account recovery (Shamir) |
| 7 | 14–15 | WebAuthn/passkeys |

**Total: 15 tasks across 7 phases.**

Each task follows TDD: write failing test → implement → verify → commit.
