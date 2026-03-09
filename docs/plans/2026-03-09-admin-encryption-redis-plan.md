# Admin Portal, File Encryption & Redis Hardening — Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add system superadmin portal (React SPA + backend endpoints), wire end-to-end file encryption across all client platforms, and harden Redis-backed distributed sessions with integration tests.

**Architecture:** Three phases — Phase 1 (Backend: admin endpoints + encryption APIs + Redis hardening), Phase 2 (Admin React SPA), Phase 3 (Client-side crypto wiring for Desktop/Android/iOS). Each phase is independently testable.

**Tech Stack:** ASP.NET Core 10, EF Core + PostgreSQL, React + Vite + TypeScript + Tailwind + Zustand, Rust (Tauri desktop crypto), Kotlin (Android crypto), Swift (iOS crypto), Testcontainers for Redis integration tests.

---

## Phase 1: Backend — Admin, Encryption APIs, Redis Hardening

### Task 1: Add SystemRole to User entity

**Files:**
- Modify: `src/SsdidDrive.Api/Data/Entities/User.cs:3-11`
- Create: `src/SsdidDrive.Api/Data/Entities/SystemRole.cs`
- Modify: `src/SsdidDrive.Api/Data/AppDbContext.cs` (add enum conversion)
- Test: `tests/SsdidDrive.Api.Tests/Integration/AdminTests.cs`

**Step 1: Write the failing test**

```csharp
// tests/SsdidDrive.Api.Tests/Integration/AdminTests.cs
using System.Net;
using System.Net.Http.Json;
using System.Text.Json;
using SsdidDrive.Api.Tests.Infrastructure;

namespace SsdidDrive.Api.Tests.Integration;

public class AdminTests : IClassFixture<SsdidDriveFactory>
{
    private readonly SsdidDriveFactory _factory;
    public AdminTests(SsdidDriveFactory factory) => _factory = factory;

    [Fact]
    public async Task AdminStats_NonAdmin_Returns403()
    {
        var (client, _, _) = await TestFixture.CreateAuthenticatedClientAsync(_factory, "RegularUser");
        var response = await client.GetAsync("/api/admin/stats");
        Assert.Equal(HttpStatusCode.Forbidden, response.StatusCode);
    }
}
```

**Step 2: Run test to verify it fails**

Run: `dotnet test tests/SsdidDrive.Api.Tests/ --filter "FullyQualifiedName~AdminTests.AdminStats_NonAdmin_Returns403"`
Expected: FAIL (404 — endpoint doesn't exist yet)

**Step 3: Create SystemRole enum and add to User**

```csharp
// src/SsdidDrive.Api/Data/Entities/SystemRole.cs
namespace SsdidDrive.Api.Data.Entities;

public enum SystemRole { SuperAdmin }
```

Add to `User.cs` after line 11:
```csharp
public SystemRole? SystemRole { get; set; }
```

Add to `AppDbContext.cs` in `OnModelCreating`, in the User entity config:
```csharp
entity.Property(e => e.SystemRole)
    .HasConversion<string>()
    .HasMaxLength(20);
```

**Step 4: Create migration**

Run: `dotnet ef migrations add AddSystemRole --project src/SsdidDrive.Api`

**Step 5: Commit**

```bash
git add src/SsdidDrive.Api/Data/Entities/SystemRole.cs src/SsdidDrive.Api/Data/Entities/User.cs src/SsdidDrive.Api/Data/AppDbContext.cs src/SsdidDrive.Api/Migrations/ tests/SsdidDrive.Api.Tests/Integration/AdminTests.cs
git commit -m "feat: add SystemRole to User entity"
```

---

### Task 2: Admin authorization middleware and stats endpoint

**Files:**
- Create: `src/SsdidDrive.Api/Features/Admin/AdminFeature.cs`
- Create: `src/SsdidDrive.Api/Features/Admin/GetStats.cs`
- Modify: `src/SsdidDrive.Api/Program.cs:178` (add MapAdminFeature)
- Modify: `src/SsdidDrive.Api/Common/CurrentUserAccessor.cs` (add SystemRole)
- Modify: `src/SsdidDrive.Api/Middleware/SsdidAuthMiddleware.cs:57-59` (populate SystemRole)
- Test: `tests/SsdidDrive.Api.Tests/Integration/AdminTests.cs`

**Step 1: Write the failing test**

Add to `AdminTests.cs`:
```csharp
[Fact]
public async Task AdminStats_SuperAdmin_ReturnsStats()
{
    var (client, _, _) = await TestFixture.CreateAuthenticatedClientAsync(_factory, "AdminUser", systemRole: "SuperAdmin");
    var response = await client.GetAsync("/api/admin/stats");
    Assert.Equal(HttpStatusCode.OK, response.StatusCode);

    var body = await response.Content.ReadFromJsonAsync<JsonElement>(TestFixture.Json);
    Assert.True(body.TryGetProperty("user_count", out _));
    Assert.True(body.TryGetProperty("tenant_count", out _));
    Assert.True(body.TryGetProperty("active_session_count", out _));
    Assert.True(body.TryGetProperty("total_storage_bytes", out _));
}
```

Update `TestFixture.CreateAuthenticatedClientAsync` to accept optional `systemRole` parameter. When provided, set `User.SystemRole` in the DB after creation.

**Step 2: Run test to verify it fails**

Run: `dotnet test tests/SsdidDrive.Api.Tests/ --filter "FullyQualifiedName~AdminTests.AdminStats_SuperAdmin_ReturnsStats"`
Expected: FAIL (compilation error — systemRole parameter doesn't exist)

**Step 3: Implement**

Add `SystemRole` to `CurrentUserAccessor`:
```csharp
public SystemRole? SystemRole { get; set; }
```

In `SsdidAuthMiddleware.cs` after line 59, add:
```csharp
accessor.SystemRole = user.SystemRole;
```

Create `AdminFeature.cs`:
```csharp
using SsdidDrive.Api.Common;

namespace SsdidDrive.Api.Features.Admin;

public static class AdminFeature
{
    public static void MapAdminFeature(this IEndpointRouteBuilder routes)
    {
        var group = routes.MapGroup("/api/admin")
            .WithTags("Admin")
            .AddEndpointFilter(async (ctx, next) =>
            {
                var accessor = ctx.HttpContext.RequestServices.GetRequiredService<CurrentUserAccessor>();
                if (accessor.SystemRole != Data.Entities.SystemRole.SuperAdmin)
                    return Results.Problem(
                        statusCode: 403,
                        title: "Forbidden",
                        detail: "System administrator access required");
                return await next(ctx);
            });

        GetStats.Map(group);
    }
}
```

Create `GetStats.cs`:
```csharp
using Microsoft.EntityFrameworkCore;
using SsdidDrive.Api.Data;
using SsdidDrive.Api.Ssdid;

namespace SsdidDrive.Api.Features.Admin;

public static class GetStats
{
    public static void Map(RouteGroupBuilder group) =>
        group.MapGet("/stats", Handle);

    private static async Task<IResult> Handle(AppDbContext db, CancellationToken ct)
    {
        var userCount = await db.Users.CountAsync(ct);
        var tenantCount = await db.Tenants.CountAsync(ct);
        var fileCount = await db.Files.CountAsync(ct);
        var totalStorageBytes = await db.Files.SumAsync(f => f.Size, ct);

        return Results.Ok(new
        {
            user_count = userCount,
            tenant_count = tenantCount,
            file_count = fileCount,
            total_storage_bytes = totalStorageBytes,
            active_session_count = 0 // placeholder — will wire to ISessionStore later
        });
    }
}
```

Add to `Program.cs` after line 178:
```csharp
app.MapAdminFeature();
```

Add the `using` for `SsdidDrive.Api.Features.Admin;` at the top of `Program.cs`.

Update `TestFixture.CreateAuthenticatedClientAsync` to support `systemRole`:
```csharp
// After creating the user in DB, if systemRole is provided:
if (systemRole is not null)
{
    user.SystemRole = Enum.Parse<SystemRole>(systemRole);
    await db.SaveChangesAsync();
}
```

**Step 4: Run tests**

Run: `dotnet test tests/SsdidDrive.Api.Tests/ --filter "FullyQualifiedName~AdminTests"`
Expected: PASS (both tests)

**Step 5: Commit**

```bash
git add src/SsdidDrive.Api/Features/Admin/ src/SsdidDrive.Api/Program.cs src/SsdidDrive.Api/Common/CurrentUserAccessor.cs src/SsdidDrive.Api/Middleware/SsdidAuthMiddleware.cs tests/SsdidDrive.Api.Tests/
git commit -m "feat(api): add admin authorization and stats endpoint"
```

---

### Task 3: Admin user management endpoints

**Files:**
- Create: `src/SsdidDrive.Api/Features/Admin/ListUsers.cs`
- Create: `src/SsdidDrive.Api/Features/Admin/UpdateUser.cs`
- Modify: `src/SsdidDrive.Api/Features/Admin/AdminFeature.cs`
- Test: `tests/SsdidDrive.Api.Tests/Integration/AdminTests.cs`

**Step 1: Write failing tests**

Add to `AdminTests.cs`:
```csharp
[Fact]
public async Task AdminListUsers_ReturnsAllUsers()
{
    var (client, _, _) = await TestFixture.CreateAuthenticatedClientAsync(_factory, "AdminLister", systemRole: "SuperAdmin");
    var response = await client.GetAsync("/api/admin/users");
    Assert.Equal(HttpStatusCode.OK, response.StatusCode);

    var body = await response.Content.ReadFromJsonAsync<JsonElement>(TestFixture.Json);
    Assert.True(body.TryGetProperty("items", out var items));
    Assert.True(items.GetArrayLength() >= 1);
}

[Fact]
public async Task AdminSuspendUser_ChangesStatus()
{
    var (adminClient, _, _) = await TestFixture.CreateAuthenticatedClientAsync(_factory, "SuspendAdmin", systemRole: "SuperAdmin");
    var (_, targetId, _) = await TestFixture.CreateAuthenticatedClientAsync(_factory, "TargetUser");

    var response = await adminClient.PatchAsJsonAsync($"/api/admin/users/{targetId}",
        new { status = "suspended" }, TestFixture.Json);
    Assert.Equal(HttpStatusCode.OK, response.StatusCode);

    var body = await response.Content.ReadFromJsonAsync<JsonElement>(TestFixture.Json);
    Assert.Equal("suspended", body.GetProperty("status").GetString());
}
```

**Step 2: Run to verify failure**

Run: `dotnet test tests/SsdidDrive.Api.Tests/ --filter "FullyQualifiedName~AdminTests.AdminListUsers"`
Expected: FAIL (404)

**Step 3: Implement**

Create `ListUsers.cs`:
```csharp
using Microsoft.EntityFrameworkCore;
using SsdidDrive.Api.Common;
using SsdidDrive.Api.Data;

namespace SsdidDrive.Api.Features.Admin;

public static class ListUsers
{
    public static void Map(RouteGroupBuilder group) =>
        group.MapGet("/users", Handle);

    private static async Task<IResult> Handle(
        AppDbContext db,
        [AsParameters] PaginationParams pagination,
        string? search,
        CancellationToken ct)
    {
        var query = db.Users.AsNoTracking().AsQueryable();

        if (!string.IsNullOrWhiteSpace(search))
            query = query.Where(u =>
                (u.DisplayName != null && u.DisplayName.Contains(search)) ||
                u.Did.Contains(search) ||
                (u.Email != null && u.Email.Contains(search)));

        var total = await query.CountAsync(ct);
        var items = await query
            .OrderByDescending(u => u.CreatedAt)
            .Skip(pagination.Offset)
            .Take(pagination.Limit)
            .Select(u => new
            {
                u.Id, u.Did, u.DisplayName, u.Email,
                Status = u.Status.ToString().ToLowerInvariant(),
                SystemRole = u.SystemRole != null ? u.SystemRole.ToString() : null,
                u.TenantId, u.LastLoginAt, u.CreatedAt
            })
            .ToListAsync(ct);

        return Results.Ok(new { items, total, pagination.Offset, pagination.Limit });
    }
}
```

Create `UpdateUser.cs`:
```csharp
using SsdidDrive.Api.Common;
using SsdidDrive.Api.Data;
using SsdidDrive.Api.Data.Entities;

namespace SsdidDrive.Api.Features.Admin;

public static class UpdateUser
{
    public record Request(string? Status, string? SystemRole);

    public static void Map(RouteGroupBuilder group) =>
        group.MapPatch("/users/{id:guid}", Handle);

    private static async Task<IResult> Handle(
        Guid id, Request req, AppDbContext db, CurrentUserAccessor accessor, CancellationToken ct)
    {
        var user = await db.Users.FindAsync([id], ct);
        if (user is null)
            return AppError.NotFound("User not found").ToProblemResult();

        // Prevent self-demotion
        if (id == accessor.UserId && req.Status == "suspended")
            return AppError.BadRequest("Cannot suspend yourself").ToProblemResult();

        if (req.Status is not null)
        {
            if (!Enum.TryParse<UserStatus>(req.Status, ignoreCase: true, out var status))
                return AppError.BadRequest("Status must be 'active' or 'suspended'").ToProblemResult();
            user.Status = status;
        }

        if (req.SystemRole is not null)
        {
            if (req.SystemRole == "")
                user.SystemRole = null;
            else if (!Enum.TryParse<SystemRole>(req.SystemRole, ignoreCase: true, out var role))
                return AppError.BadRequest("SystemRole must be 'SuperAdmin' or empty").ToProblemResult();
            else
                user.SystemRole = role;
        }

        user.UpdatedAt = DateTimeOffset.UtcNow;
        await db.SaveChangesAsync(ct);

        return Results.Ok(new
        {
            user.Id, user.Did, user.DisplayName, user.Email,
            Status = user.Status.ToString().ToLowerInvariant(),
            SystemRole = user.SystemRole?.ToString(),
            user.TenantId, user.LastLoginAt, user.CreatedAt, user.UpdatedAt
        });
    }
}
```

Add to `AdminFeature.cs`:
```csharp
ListUsers.Map(group);
UpdateUser.Map(group);
```

**Step 4: Run tests**

Run: `dotnet test tests/SsdidDrive.Api.Tests/ --filter "FullyQualifiedName~AdminTests"`
Expected: PASS

**Step 5: Commit**

```bash
git add src/SsdidDrive.Api/Features/Admin/ tests/SsdidDrive.Api.Tests/Integration/AdminTests.cs
git commit -m "feat(api): add admin user management endpoints"
```

---

### Task 4: Admin tenant management endpoints

**Files:**
- Create: `src/SsdidDrive.Api/Features/Admin/ListTenants.cs`
- Create: `src/SsdidDrive.Api/Features/Admin/CreateTenant.cs`
- Create: `src/SsdidDrive.Api/Features/Admin/UpdateTenant.cs`
- Create: `src/SsdidDrive.Api/Features/Admin/GetTenantMembers.cs`
- Modify: `src/SsdidDrive.Api/Features/Admin/AdminFeature.cs`
- Modify: `src/SsdidDrive.Api/Data/Entities/Tenant.cs` (add Disabled, StorageQuotaBytes)
- Test: `tests/SsdidDrive.Api.Tests/Integration/AdminTests.cs`

**Step 1: Write failing tests**

Add to `AdminTests.cs`:
```csharp
[Fact]
public async Task AdminCreateTenant_CreatesAndLists()
{
    var (client, _, _) = await TestFixture.CreateAuthenticatedClientAsync(_factory, "TenantAdmin", systemRole: "SuperAdmin");

    var createResponse = await client.PostAsJsonAsync("/api/admin/tenants",
        new { name = "TestCorp", slug = "testcorp-" + Guid.NewGuid().ToString("N")[..8] }, TestFixture.Json);
    Assert.Equal(HttpStatusCode.Created, createResponse.StatusCode);

    var listResponse = await client.GetAsync("/api/admin/tenants");
    Assert.Equal(HttpStatusCode.OK, listResponse.StatusCode);
    var body = await listResponse.Content.ReadFromJsonAsync<JsonElement>(TestFixture.Json);
    Assert.True(body.GetProperty("items").GetArrayLength() >= 1);
}

[Fact]
public async Task AdminUpdateTenant_DisablesTenant()
{
    var (client, _, _) = await TestFixture.CreateAuthenticatedClientAsync(_factory, "DisableAdmin", systemRole: "SuperAdmin");

    var createResponse = await client.PostAsJsonAsync("/api/admin/tenants",
        new { name = "ToDisable", slug = "disable-" + Guid.NewGuid().ToString("N")[..8] }, TestFixture.Json);
    var created = await createResponse.Content.ReadFromJsonAsync<JsonElement>(TestFixture.Json);
    var tenantId = created.GetProperty("id").GetGuid();

    var patchResponse = await client.PatchAsJsonAsync($"/api/admin/tenants/{tenantId}",
        new { disabled = true }, TestFixture.Json);
    Assert.Equal(HttpStatusCode.OK, patchResponse.StatusCode);

    var body = await patchResponse.Content.ReadFromJsonAsync<JsonElement>(TestFixture.Json);
    Assert.True(body.GetProperty("disabled").GetBoolean());
}
```

**Step 2: Run to verify failure**

Run: `dotnet test tests/SsdidDrive.Api.Tests/ --filter "FullyQualifiedName~AdminTests.AdminCreateTenant"`
Expected: FAIL

**Step 3: Implement**

Add to `Tenant.cs`:
```csharp
public bool Disabled { get; set; }
public long? StorageQuotaBytes { get; set; }
```

Create migration: `dotnet ef migrations add AddTenantQuotaAndDisabled --project src/SsdidDrive.Api`

Create `ListTenants.cs`, `CreateTenant.cs`, `UpdateTenant.cs`, `GetTenantMembers.cs` following the same vertical-slice pattern as existing endpoints. Wire into `AdminFeature.cs`.

**Step 4: Run tests**

Run: `dotnet test tests/SsdidDrive.Api.Tests/ --filter "FullyQualifiedName~AdminTests"`
Expected: PASS

**Step 5: Commit**

```bash
git add src/SsdidDrive.Api/Features/Admin/ src/SsdidDrive.Api/Data/Entities/Tenant.cs src/SsdidDrive.Api/Migrations/ tests/SsdidDrive.Api.Tests/Integration/AdminTests.cs
git commit -m "feat(api): add admin tenant management endpoints"
```

---

### Task 5: Admin audit log

**Files:**
- Create: `src/SsdidDrive.Api/Data/Entities/AuditLogEntry.cs`
- Create: `src/SsdidDrive.Api/Services/AuditService.cs`
- Create: `src/SsdidDrive.Api/Features/Admin/ListAuditLog.cs`
- Modify: `src/SsdidDrive.Api/Data/AppDbContext.cs` (add DbSet)
- Modify: `src/SsdidDrive.Api/Features/Admin/AdminFeature.cs`
- Modify: `src/SsdidDrive.Api/Features/Admin/UpdateUser.cs` (log action)
- Modify: `src/SsdidDrive.Api/Features/Admin/UpdateTenant.cs` (log action)
- Modify: `src/SsdidDrive.Api/Program.cs` (register AuditService)
- Test: `tests/SsdidDrive.Api.Tests/Integration/AdminTests.cs`

**Step 1: Write failing test**

```csharp
[Fact]
public async Task AdminAuditLog_RecordsActions()
{
    var (client, _, _) = await TestFixture.CreateAuthenticatedClientAsync(_factory, "AuditAdmin", systemRole: "SuperAdmin");
    var (_, targetId, _) = await TestFixture.CreateAuthenticatedClientAsync(_factory, "AuditTarget");

    // Suspend a user (should create audit entry)
    await client.PatchAsJsonAsync($"/api/admin/users/{targetId}",
        new { status = "suspended" }, TestFixture.Json);

    var response = await client.GetAsync("/api/admin/audit-log");
    Assert.Equal(HttpStatusCode.OK, response.StatusCode);

    var body = await response.Content.ReadFromJsonAsync<JsonElement>(TestFixture.Json);
    Assert.True(body.GetProperty("items").GetArrayLength() >= 1);
}
```

**Step 2: Implement**

```csharp
// src/SsdidDrive.Api/Data/Entities/AuditLogEntry.cs
namespace SsdidDrive.Api.Data.Entities;

public class AuditLogEntry
{
    public Guid Id { get; set; }
    public Guid ActorId { get; set; }
    public string Action { get; set; } = string.Empty; // e.g. "user.suspended", "tenant.created"
    public string? TargetType { get; set; } // "user", "tenant"
    public Guid? TargetId { get; set; }
    public string? Details { get; set; } // JSON
    public DateTimeOffset CreatedAt { get; set; }

    public User Actor { get; set; } = null!;
}
```

```csharp
// src/SsdidDrive.Api/Services/AuditService.cs
using SsdidDrive.Api.Data;
using SsdidDrive.Api.Data.Entities;

namespace SsdidDrive.Api.Services;

public class AuditService(AppDbContext db)
{
    public async Task LogAsync(Guid actorId, string action, string? targetType = null, Guid? targetId = null, string? details = null, CancellationToken ct = default)
    {
        db.AuditLog.Add(new AuditLogEntry
        {
            Id = Guid.NewGuid(),
            ActorId = actorId,
            Action = action,
            TargetType = targetType,
            TargetId = targetId,
            Details = details,
            CreatedAt = DateTimeOffset.UtcNow
        });
        await db.SaveChangesAsync(ct);
    }
}
```

Wire `AuditService` as scoped in `Program.cs`. Add `LogAsync` calls into `UpdateUser.cs` and `UpdateTenant.cs`. Create `ListAuditLog.cs` (paginated, descending by date).

**Step 3: Run tests, commit**

```bash
git commit -m "feat(api): add admin audit log"
```

---

### Task 6: KEM public key endpoints

**Files:**
- Create: `src/SsdidDrive.Api/Features/Users/PublishKemKey.cs`
- Create: `src/SsdidDrive.Api/Features/Users/GetKemPublicKey.cs`
- Modify: `src/SsdidDrive.Api/Features/Users/UserFeature.cs`
- Modify: `src/SsdidDrive.Api/Data/Entities/User.cs` (add KemPublicKey)
- Test: `tests/SsdidDrive.Api.Tests/Integration/UserTests.cs`

**Step 1: Write failing test**

Add to `UserTests.cs`:
```csharp
[Fact]
public async Task PublishAndGetKemKey_RoundTrips()
{
    var (client1, userId1, _) = await TestFixture.CreateAuthenticatedClientAsync(_factory, "KemPublisher");
    var kemPk = Convert.ToBase64String(new byte[800]); // ML-KEM-768 public key

    var publishResponse = await client1.PatchAsJsonAsync("/api/me/keys/kem",
        new { kem_public_key = kemPk, kem_algorithm = "ML-KEM-768" }, TestFixture.Json);
    Assert.Equal(HttpStatusCode.OK, publishResponse.StatusCode);

    // Another user can fetch it
    var (client2, _, _) = await TestFixture.CreateAuthenticatedClientAsync(_factory, "KemConsumer");
    var getResponse = await client2.GetAsync($"/api/users/{userId1}/kem-public-key");
    Assert.Equal(HttpStatusCode.OK, getResponse.StatusCode);

    var body = await getResponse.Content.ReadFromJsonAsync<JsonElement>(TestFixture.Json);
    Assert.Equal(kemPk, body.GetProperty("kem_public_key").GetString());
    Assert.Equal("ML-KEM-768", body.GetProperty("kem_algorithm").GetString());
}
```

**Step 2: Implement**

Add to `User.cs`:
```csharp
public byte[]? KemPublicKey { get; set; }
public string? KemAlgorithm { get; set; }
```

Create migration. Create `PublishKemKey.cs` (PATCH `/me/keys/kem`) and `GetKemPublicKey.cs` (GET `/users/{id}/kem-public-key`). Wire into `UserFeature.cs`.

**Step 3: Run tests, commit**

```bash
git commit -m "feat(api): add KEM public key publish and fetch endpoints"
```

---

### Task 7: Folder key distribution endpoint

**Files:**
- Create: `src/SsdidDrive.Api/Features/Folders/GetFolderKey.cs`
- Create: `src/SsdidDrive.Api/Features/Folders/RotateFolderKey.cs`
- Modify: `src/SsdidDrive.Api/Features/Folders/FolderFeature.cs`
- Modify: `src/SsdidDrive.Api/Data/Entities/Folder.cs` (add FolderKeyVersion)
- Test: `tests/SsdidDrive.Api.Tests/Integration/FolderTests.cs`

**Step 1: Write failing test**

Add to `FolderTests.cs`:
```csharp
[Fact]
public async Task GetFolderKey_Owner_ReturnsEncryptedKey()
{
    var (client, _, _) = await TestFixture.CreateAuthenticatedClientAsync(_factory, "FolderKeyUser");
    var encKey = Convert.ToBase64String(new byte[32]);

    var createResponse = await client.PostAsJsonAsync("/api/folders",
        new { name = "KeyFolder", encrypted_folder_key = encKey, kem_algorithm = "ML-KEM-768" }, TestFixture.Json);
    var created = await createResponse.Content.ReadFromJsonAsync<JsonElement>(TestFixture.Json);
    var folderId = created.GetProperty("id").GetGuid();

    var keyResponse = await client.GetAsync($"/api/folders/{folderId}/key");
    Assert.Equal(HttpStatusCode.OK, keyResponse.StatusCode);

    var body = await keyResponse.Content.ReadFromJsonAsync<JsonElement>(TestFixture.Json);
    Assert.Equal(encKey, body.GetProperty("encrypted_folder_key").GetString());
}
```

**Step 2: Implement**

`GetFolderKey.cs`: Returns the folder's `EncryptedFolderKey` if caller is the owner, or the share's `EncryptedKey` if caller has a share.

`RotateFolderKey.cs`: POST `/folders/{id}/rotate-key` — accepts new `EncryptedFolderKey` + array of `{ user_id, encrypted_key }` for all members. Updates the folder key and creates/updates share keys. Increments `FolderKeyVersion`.

**Step 3: Run tests, commit**

```bash
git commit -m "feat(api): add folder key retrieval and rotation endpoints"
```

---

### Task 8: Redis health check and connection resilience

**Files:**
- Create: `src/SsdidDrive.Api/Health/RedisHealthCheck.cs`
- Modify: `src/SsdidDrive.Api/Program.cs:66-86` (add resilience config, health check)
- Test: `tests/SsdidDrive.Api.Tests/Integration/RedisSessionStoreTests.cs`

**Step 1: Write failing test**

```csharp
// tests/SsdidDrive.Api.Tests/Integration/RedisSessionStoreTests.cs
using SsdidDrive.Api.Ssdid;

namespace SsdidDrive.Api.Tests.Integration;

public class RedisSessionStoreTests
{
    [Fact]
    public void CreateAndGetSession_RoundTrips()
    {
        // This test will use Testcontainers in a later step.
        // For now, test the in-memory store as a baseline.
        var store = new SessionStore(
            Microsoft.Extensions.Logging.Abstractions.NullLogger<SessionStore>.Instance,
            TimeProvider.System);

        store.CreateChallenge("did:test:123", "register", "challenge123", "key1");
        var entry = store.ConsumeChallenge("did:test:123", "register");
        Assert.NotNull(entry);
        Assert.Equal("challenge123", entry.Value.Challenge);

        // Second consume should return null (already consumed)
        var entry2 = store.ConsumeChallenge("did:test:123", "register");
        Assert.Null(entry2);
    }
}
```

**Step 2: Implement health check**

```csharp
// src/SsdidDrive.Api/Health/RedisHealthCheck.cs
using Microsoft.Extensions.Diagnostics.HealthChecks;
using StackExchange.Redis;

namespace SsdidDrive.Api.Health;

public class RedisHealthCheck(IConnectionMultiplexer redis) : IHealthCheck
{
    public async Task<HealthCheckResult> CheckHealthAsync(HealthCheckContext context, CancellationToken ct = default)
    {
        try
        {
            var db = redis.GetDatabase();
            var latency = await db.PingAsync();
            return HealthCheckResult.Healthy($"Redis ping: {latency.TotalMilliseconds:F1}ms");
        }
        catch (Exception ex)
        {
            return HealthCheckResult.Unhealthy("Redis unreachable", ex);
        }
    }
}
```

In `Program.cs`, within the Redis config block, add:
```csharp
builder.Services.AddHealthChecks().AddCheck<RedisHealthCheck>("redis");
```

Update Redis connection to use resilient options:
```csharp
var redisOptions = ConfigurationOptions.Parse(redisConnection);
redisOptions.AbortOnConnectFail = false;
redisOptions.ConnectRetry = 3;
redisOptions.ReconnectRetryPolicy = new ExponentialRetry(5000);
builder.Services.AddSingleton<IConnectionMultiplexer>(sp =>
    ConnectionMultiplexer.Connect(redisOptions));
```

Add health endpoint mapping:
```csharp
app.MapHealthChecks("/health/redis");
```

**Step 3: Run tests, commit**

```bash
git commit -m "feat: add Redis health check and connection resilience"
```

---

### Task 9: Redis integration tests with Testcontainers

**Files:**
- Modify: `tests/SsdidDrive.Api.Tests/SsdidDrive.Api.Tests.csproj` (add Testcontainers.Redis)
- Modify: `tests/SsdidDrive.Api.Tests/Integration/RedisSessionStoreTests.cs`

**Step 1: Add Testcontainers package**

Run: `dotnet add tests/SsdidDrive.Api.Tests/ package Testcontainers.Redis`

**Step 2: Write Redis integration tests**

```csharp
using Microsoft.Extensions.Caching.Distributed;
using Microsoft.Extensions.Caching.StackExchangeRedis;
using Microsoft.Extensions.Logging.Abstractions;
using Microsoft.Extensions.Options;
using SsdidDrive.Api.Ssdid;
using StackExchange.Redis;
using Testcontainers.Redis;

namespace SsdidDrive.Api.Tests.Integration;

public class RedisSessionStoreIntegrationTests : IAsyncLifetime
{
    private readonly RedisContainer _redis = new RedisBuilder()
        .WithImage("redis:7-alpine")
        .Build();

    private RedisSessionStore _store = null!;
    private IConnectionMultiplexer _mux = null!;

    public async Task InitializeAsync()
    {
        await _redis.StartAsync();
        _mux = await ConnectionMultiplexer.ConnectAsync(_redis.GetConnectionString());
        var cache = new RedisCache(Options.Create(new RedisCacheOptions
        {
            Configuration = _redis.GetConnectionString(),
            InstanceName = "test:"
        }));
        _store = new RedisSessionStore(cache, _mux, NullLogger<RedisSessionStore>.Instance);
    }

    public async Task DisposeAsync()
    {
        _mux.Dispose();
        await _redis.DisposeAsync();
    }

    [Fact]
    public void Challenge_CreateAndConsume_Works()
    {
        _store.CreateChallenge("did:test:redis", "register", "ch123", "key1");
        var entry = _store.ConsumeChallenge("did:test:redis", "register");
        Assert.NotNull(entry);
        Assert.Equal("ch123", entry.Value.Challenge);
    }

    [Fact]
    public void Challenge_DoubleConsume_ReturnsNull()
    {
        _store.CreateChallenge("did:test:double", "register", "ch456", "key2");
        _store.ConsumeChallenge("did:test:double", "register");
        var second = _store.ConsumeChallenge("did:test:double", "register");
        Assert.Null(second);
    }

    [Fact]
    public void Session_CreateGetDelete_Works()
    {
        var token = _store.CreateSession("did:test:session");
        Assert.NotNull(token);

        var did = _store.GetSession(token);
        Assert.Equal("did:test:session", did);

        _store.DeleteSession(token);
        var gone = _store.GetSession(token);
        Assert.Null(gone);
    }

    [Fact]
    public async Task PubSub_NotifyAndWait_Works()
    {
        var challengeId = Guid.NewGuid().ToString();
        var waitTask = _store.WaitForCompletion(challengeId, new CancellationTokenSource(5000).Token);

        // Small delay to let subscriber connect
        await Task.Delay(100);
        var published = _store.NotifyCompletion(challengeId, "session-token-123");
        Assert.True(published);

        var result = await waitTask;
        Assert.Equal("session-token-123", result);
    }
}
```

**Step 3: Run tests**

Run: `dotnet test tests/SsdidDrive.Api.Tests/ --filter "FullyQualifiedName~RedisSessionStore"`
Expected: PASS (requires Docker running)

**Step 4: Commit**

```bash
git add tests/SsdidDrive.Api.Tests/
git commit -m "test: add Redis integration tests with Testcontainers"
```

---

### Task 10: Admin session metrics endpoint

**Files:**
- Create: `src/SsdidDrive.Api/Features/Admin/GetSessions.cs`
- Modify: `src/SsdidDrive.Api/Ssdid/ISessionStore.cs` (add GetActiveSessionCount)
- Modify: `src/SsdidDrive.Api/Ssdid/SessionStore.cs` (implement count)
- Modify: `src/SsdidDrive.Api/Ssdid/RedisSessionStore.cs` (implement count)
- Modify: `src/SsdidDrive.Api/Features/Admin/AdminFeature.cs`
- Modify: `src/SsdidDrive.Api/Features/Admin/GetStats.cs` (wire real session count)
- Test: `tests/SsdidDrive.Api.Tests/Integration/AdminTests.cs`

**Step 1: Write failing test**

```csharp
[Fact]
public async Task AdminSessions_ReturnsSessionCount()
{
    var (client, _, _) = await TestFixture.CreateAuthenticatedClientAsync(_factory, "SessionAdmin", systemRole: "SuperAdmin");
    var response = await client.GetAsync("/api/admin/sessions");
    Assert.Equal(HttpStatusCode.OK, response.StatusCode);

    var body = await response.Content.ReadFromJsonAsync<JsonElement>(TestFixture.Json);
    Assert.True(body.TryGetProperty("active_sessions", out _));
    Assert.True(body.TryGetProperty("active_challenges", out _));
}
```

**Step 2: Implement**

Add to `ISessionStore`:
```csharp
int GetActiveSessionCount();
int GetActiveChallengeCount();
```

Implement in `SessionStore` (count ConcurrentDictionary entries) and `RedisSessionStore` (use Redis SCAN or maintain a counter — simplest is `DBSIZE` approximation or maintain an atomic counter).

**Step 3: Run tests, commit**

```bash
git commit -m "feat(api): add admin session metrics endpoint"
```

---

## Phase 2: Admin React SPA

### Task 11: Scaffold React admin app

**Files:**
- Create: `clients/admin/package.json`
- Create: `clients/admin/vite.config.ts`
- Create: `clients/admin/tsconfig.json`
- Create: `clients/admin/index.html`
- Create: `clients/admin/src/main.tsx`
- Create: `clients/admin/src/App.tsx`
- Create: `clients/admin/tailwind.config.js`
- Create: `clients/admin/postcss.config.js`
- Create: `clients/admin/src/index.css`

**Step 1: Scaffold**

```bash
cd clients/admin
npm create vite@latest . -- --template react-ts
npm install
npm install tailwindcss @tailwindcss/vite zustand react-router-dom
```

**Step 2: Configure**

Set `vite.config.ts` with base path `/admin/` and API proxy to `http://localhost:5139`.

**Step 3: Verify build**

Run: `cd clients/admin && npm run build`
Expected: Build succeeds

**Step 4: Commit**

```bash
git commit -m "feat(admin): scaffold React admin SPA"
```

---

### Task 12: Auth store and login page

**Files:**
- Create: `clients/admin/src/stores/authStore.ts`
- Create: `clients/admin/src/pages/LoginPage.tsx`
- Create: `clients/admin/src/services/api.ts`

Implement Zustand auth store with `login()` (calls SSDID auth flow), `logout()`, `isAuthenticated`, `user` state. Login page with QR code / DID input for SSDID authentication. API service using fetch with Bearer token from store.

**Commit:** `feat(admin): add auth store and login page`

---

### Task 13: Dashboard page

**Files:**
- Create: `clients/admin/src/pages/DashboardPage.tsx`
- Create: `clients/admin/src/components/StatsCard.tsx`

Dashboard calls `GET /api/admin/stats` and `GET /api/admin/sessions`. Displays stats cards: user count, tenant count, file count, storage used, active sessions.

**Commit:** `feat(admin): add dashboard page with stats cards`

---

### Task 14: Users management page

**Files:**
- Create: `clients/admin/src/pages/UsersPage.tsx`
- Create: `clients/admin/src/components/DataTable.tsx` (reusable)
- Create: `clients/admin/src/stores/adminStore.ts`

Table with pagination, search. Suspend/activate toggle button per user. Uses `GET /api/admin/users` and `PATCH /api/admin/users/{id}`.

**Commit:** `feat(admin): add users management page`

---

### Task 15: Tenants management page

**Files:**
- Create: `clients/admin/src/pages/TenantsPage.tsx`
- Create: `clients/admin/src/pages/TenantDetailPage.tsx`
- Create: `clients/admin/src/components/CreateTenantDialog.tsx`

Table of tenants with create, edit, disable. Detail page shows members and storage usage.

**Commit:** `feat(admin): add tenants management page`

---

### Task 16: Audit log page

**Files:**
- Create: `clients/admin/src/pages/AuditLogPage.tsx`

Paginated table of audit entries from `GET /api/admin/audit-log`. Shows actor, action, target, timestamp.

**Commit:** `feat(admin): add audit log page`

---

### Task 17: Serve admin SPA from ASP.NET Core

**Files:**
- Modify: `src/SsdidDrive.Api/Program.cs` (add static files for /admin/)

Add to `Program.cs` before `app.Run()`:
```csharp
// Serve admin SPA
app.UseStaticFiles(new StaticFileOptions
{
    FileProvider = new PhysicalFileProvider(Path.Combine(app.Environment.ContentRootPath, "wwwroot", "admin")),
    RequestPath = "/admin"
});
app.MapFallbackToFile("/admin/{**path}", "admin/index.html");
```

Build admin: `cd clients/admin && npm run build` → output to `src/SsdidDrive.Api/wwwroot/admin/`.

**Commit:** `feat: serve admin SPA from ASP.NET Core`

---

## Phase 3: Client-Side Crypto

### Task 18: Desktop (Rust/Tauri) — crypto commands

**Files:**
- Modify: `clients/desktop/src-tauri/src/commands/crypto.rs`
- Modify: `clients/desktop/src-tauri/src/services/crypto_service.rs`
- Modify: `clients/desktop/native/securesharing-crypto/src/lib.rs`

Wire Tauri commands:
- `generate_kem_keypair(algorithm)` → returns `(public_key, encrypted_private_key)`
- `encrypt_file(file_path, folder_key)` → returns `(ciphertext_path, encrypted_file_key, nonce)`
- `decrypt_file(ciphertext_path, folder_key, file_id, nonce)` → returns `plaintext_path`
- `encapsulate_folder_key(folder_key, recipient_kem_pk)` → returns `encrypted_key`
- `decapsulate_folder_key(encrypted_key, kem_sk)` → returns `folder_key`
- `derive_file_key(folder_key, file_id)` → returns `file_key` (HKDF)

**Commit:** `feat(desktop): wire crypto commands for file encryption`

---

### Task 19: Desktop — encrypt-before-upload flow

**Files:**
- Modify: `clients/desktop/src/stores/fileStore.ts`
- Modify: `clients/desktop/src/components/files/DropZoneOverlay.tsx`
- Modify: `clients/desktop/src/services/tauri.ts`

Before `uploadFile()`:
1. Get folder key (decrypt from stored encrypted folder key using user's KEM SK)
2. Derive file key via HKDF(folder_key, new_file_id)
3. Encrypt file content with AES-256-GCM using file key
4. Upload ciphertext + base64(encrypted_file_key) + base64(nonce) + algorithm

**Commit:** `feat(desktop): encrypt files before upload`

---

### Task 20: Desktop — decrypt-after-download flow

**Files:**
- Modify: `clients/desktop/src/stores/fileStore.ts`
- Modify: `clients/desktop/src/services/tauri.ts`

`downloadFile()`:
1. Download ciphertext from server
2. Get folder key (decrypt via KEM)
3. Derive file key via HKDF(folder_key, file_id)
4. Decrypt with AES-256-GCM using nonce from metadata
5. Write plaintext to user-chosen path

**Commit:** `feat(desktop): decrypt files after download`

---

### Task 21: Android — crypto wiring

**Files:**
- Modify: `clients/android/app/src/main/kotlin/com/securesharing/crypto/CryptoManager.kt`
- Modify: `clients/android/app/src/main/kotlin/com/securesharing/crypto/FileEncryptor.kt`
- Modify: `clients/android/app/src/main/kotlin/com/securesharing/crypto/FileDecryptor.kt`
- Modify: `clients/android/app/src/main/kotlin/com/securesharing/crypto/KeyEncapsulation.kt`
- Modify: `clients/android/app/src/main/kotlin/com/securesharing/crypto/FolderKeyManager.kt`

Implement:
- `KeyEncapsulation.encapsulate(folderKey, recipientPk)` using `kazkem-release.aar`
- `KeyEncapsulation.decapsulate(encryptedKey, sk)` using `kazkem-release.aar`
- `FileEncryptor.encrypt(inputStream, folderKey, fileId)` → AES-256-GCM + HKDF
- `FileDecryptor.decrypt(inputStream, folderKey, fileId, nonce)` → plaintext stream
- `FolderKeyManager.generateFolderKey()` → random 256-bit key
- `FolderKeyManager.deriveFolderKey(folderKey, fileId)` → HKDF-SHA3-256

**Commit:** `feat(android): implement crypto for file encryption`

---

### Task 22: Android — integrate crypto into upload/download

**Files:**
- Modify: `clients/android/app/src/main/kotlin/com/securesharing/data/repository/FileRepositoryImpl.kt`

Wire `FileEncryptor` into upload flow and `FileDecryptor` into download flow, matching the desktop pattern.

**Commit:** `feat(android): wire encrypt/decrypt into file upload/download`

---

### Task 23: iOS — crypto wiring

**Files:**
- Modify: `clients/ios/SsdidDrive/FileProviderCore/FPEncryptor.swift`
- Modify: `clients/ios/SsdidDrive/FileProviderCore/FPDecryptor.swift`
- Modify: `clients/ios/SsdidDrive/FileProviderCore/FPKeychainReader.swift`

Implement using `KazKemNative.xcframework`:
- `FPEncryptor.encrypt(data, folderKey, fileId)` → `(ciphertext, nonce)`
- `FPDecryptor.decrypt(ciphertext, folderKey, fileId, nonce)` → plaintext
- `FPKeychainReader.getKemKeyPair()` → read from Keychain
- KEM encapsulate/decapsulate for folder key sharing

**Commit:** `feat(ios): implement crypto for file encryption`

---

### Task 24: iOS — integrate crypto into FileProvider

**Files:**
- Modify: `clients/ios/SsdidDrive/FileProviderExtension/FileProviderExtension.swift`

Wire encryption into FileProvider's `importDocument` and `fetchContents` methods.

**Commit:** `feat(ios): wire encrypt/decrypt into FileProvider`

---

## Summary

| Phase | Tasks | Description |
|-------|-------|-------------|
| 1 | 1-10 | Backend: admin endpoints, encryption APIs, Redis hardening |
| 2 | 11-17 | Admin React SPA |
| 3 | 18-24 | Client-side crypto (Desktop, Android, iOS) |

Total: 24 tasks across 3 phases.
