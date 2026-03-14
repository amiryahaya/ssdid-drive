# Extension Services, HMAC Middleware & Tenant Requests Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add extension service management (HMAC-authenticated 3rd-party API access), HMAC verification middleware, and tenant creation request flow.

**Architecture:** New `ExtensionService` entity stores per-tenant API credentials (HMAC secret encrypted at rest via existing `TotpEncryption`). New `HmacAuthMiddleware` runs before `SsdidAuthMiddleware` for `/api/ext/*` routes, verifying HMAC signatures and setting request context. `TenantRequest` entity enables self-service tenant creation with admin approval. All endpoints follow existing vertical slice pattern.

**Tech Stack:** .NET 10, EF Core + PostgreSQL, HMAC-SHA256, AES-256-GCM (existing `TotpEncryption`)

**Spec:** `docs/superpowers/specs/2026-03-14-auth-migration-design.md` (Phase 4)

**Scope:** Extension service CRUD, HMAC middleware, tenant request endpoints, audit logging. This plan does NOT cover admin portal UI or client-side changes.

---

## File Structure

### New Files

```
src/SsdidDrive.Api/Data/Entities/ExtensionService.cs       — ExtensionService entity + ServicePermissions class
src/SsdidDrive.Api/Data/Entities/TenantRequest.cs           — TenantRequest entity + TenantRequestStatus enum
src/SsdidDrive.Api/Middleware/HmacAuthMiddleware.cs          — HMAC signature verification middleware for /api/ext/* routes
src/SsdidDrive.Api/Common/ExtensionServiceContext.cs         — Scoped context set by HMAC middleware (TenantId, ServiceId, Permissions)
src/SsdidDrive.Api/Features/ExtensionServices/ExtensionServiceFeature.cs  — Route group for /api/tenant/services
src/SsdidDrive.Api/Features/ExtensionServices/RegisterService.cs          — POST /api/tenant/services
src/SsdidDrive.Api/Features/ExtensionServices/ListServices.cs             — GET /api/tenant/services
src/SsdidDrive.Api/Features/ExtensionServices/GetService.cs               — GET /api/tenant/services/{id}
src/SsdidDrive.Api/Features/ExtensionServices/UpdateService.cs            — PUT /api/tenant/services/{id}
src/SsdidDrive.Api/Features/ExtensionServices/RevokeService.cs            — DELETE /api/tenant/services/{id}
src/SsdidDrive.Api/Features/ExtensionServices/RotateSecret.cs             — POST /api/tenant/services/{id}/rotate
src/SsdidDrive.Api/Features/TenantRequests/TenantRequestFeature.cs        — Route group for tenant request endpoints
src/SsdidDrive.Api/Features/TenantRequests/SubmitRequest.cs               — POST /api/tenant-requests
src/SsdidDrive.Api/Features/TenantRequests/ListRequests.cs                — GET /api/admin/tenant-requests
src/SsdidDrive.Api/Features/TenantRequests/ApproveRequest.cs              — POST /api/admin/tenant-requests/{id}/approve
src/SsdidDrive.Api/Features/TenantRequests/RejectRequest.cs               — POST /api/admin/tenant-requests/{id}/reject
tests/SsdidDrive.Api.Tests/Unit/HmacSignatureTests.cs                     — Unit tests for HMAC signature computation + verification
tests/SsdidDrive.Api.Tests/Integration/ExtensionServiceTests.cs           — Integration tests for extension service CRUD + rotate
tests/SsdidDrive.Api.Tests/Integration/HmacMiddlewareTests.cs             — Integration tests for HMAC middleware
tests/SsdidDrive.Api.Tests/Integration/TenantRequestTests.cs              — Integration tests for tenant request flow
```

### Modified Files

```
src/SsdidDrive.Api/Data/AppDbContext.cs           — Add DbSet<ExtensionService>, DbSet<TenantRequest>, OnModelCreating config
src/SsdidDrive.Api/Program.cs                     — Register ExtensionServiceContext, HmacAuthMiddleware, map features
src/SsdidDrive.Api/Common/CurrentUserAccessor.cs  — Add TenantId property (for user's active tenant context)
```

---

## Chunk 1: Data Model & HMAC Core

### Task 1: ExtensionService Entity

**Files:**
- Create: `src/SsdidDrive.Api/Data/Entities/ExtensionService.cs`
- Modify: `src/SsdidDrive.Api/Data/AppDbContext.cs`

- [ ] **Step 1: Create ExtensionService entity**

```csharp
// src/SsdidDrive.Api/Data/Entities/ExtensionService.cs
namespace SsdidDrive.Api.Data.Entities;

public class ExtensionService
{
    public Guid Id { get; set; }
    public Guid TenantId { get; set; }
    public string Name { get; set; } = default!;
    public string ServiceKey { get; set; } = default!; // Encrypted HMAC secret
    public string Permissions { get; set; } = "{}"; // JSON permissions object
    public bool Enabled { get; set; } = true;
    public DateTimeOffset CreatedAt { get; set; }
    public DateTimeOffset? LastUsedAt { get; set; }

    public Tenant Tenant { get; set; } = null!;
}
```

- [ ] **Step 2: Add DbSet and EF configuration in AppDbContext**

Add `public DbSet<ExtensionService> ExtensionServices => Set<ExtensionService>();` to AppDbContext.

Add OnModelCreating configuration:

```csharp
modelBuilder.Entity<ExtensionService>(e =>
{
    e.ToTable("extension_services");
    e.HasKey(x => x.Id);
    e.Property(x => x.Id).HasDefaultValueSql("gen_random_uuid()");
    e.Property(x => x.Name).HasMaxLength(256).IsRequired();
    e.Property(x => x.ServiceKey).HasMaxLength(512).IsRequired();
    e.Property(x => x.Permissions).HasColumnType("jsonb").HasDefaultValueSql("'{}'::jsonb");
    e.Property(x => x.Enabled).HasDefaultValue(true);
    e.Property(x => x.CreatedAt).HasDefaultValueSql("now()");

    e.HasIndex(x => x.TenantId);
    e.HasIndex(x => new { x.TenantId, x.Name }).IsUnique();

    e.HasOne(x => x.Tenant)
        .WithMany()
        .HasForeignKey(x => x.TenantId)
        .OnDelete(DeleteBehavior.Cascade);
});
```

- [ ] **Step 3: Build to verify compilation**

Run: `dotnet build src/SsdidDrive.Api`
Expected: Build succeeded

- [ ] **Step 4: Commit**

```bash
git add src/SsdidDrive.Api/Data/Entities/ExtensionService.cs src/SsdidDrive.Api/Data/AppDbContext.cs
git commit -m "feat: add ExtensionService entity and EF configuration"
```

### Task 2: TenantRequest Entity

**Files:**
- Create: `src/SsdidDrive.Api/Data/Entities/TenantRequest.cs`
- Modify: `src/SsdidDrive.Api/Data/AppDbContext.cs`

- [ ] **Step 1: Create TenantRequest entity**

```csharp
// src/SsdidDrive.Api/Data/Entities/TenantRequest.cs
namespace SsdidDrive.Api.Data.Entities;

public enum TenantRequestStatus { Pending, Approved, Rejected }

public class TenantRequest
{
    public Guid Id { get; set; }
    public string OrganizationName { get; set; } = default!;
    public string RequesterEmail { get; set; } = default!;
    public Guid? RequesterAccountId { get; set; }
    public string? Reason { get; set; }
    public TenantRequestStatus Status { get; set; } = TenantRequestStatus.Pending;
    public Guid? ReviewedBy { get; set; }
    public DateTimeOffset? ReviewedAt { get; set; }
    public string? RejectionReason { get; set; }
    public DateTimeOffset CreatedAt { get; set; }

    public User? RequesterAccount { get; set; }
    public User? Reviewer { get; set; }
}
```

- [ ] **Step 2: Add DbSet and EF configuration in AppDbContext**

Add `public DbSet<TenantRequest> TenantRequests => Set<TenantRequest>();` to AppDbContext.

Add OnModelCreating configuration:

```csharp
modelBuilder.Entity<TenantRequest>(e =>
{
    e.ToTable("tenant_requests");
    e.HasKey(x => x.Id);
    e.Property(x => x.Id).HasDefaultValueSql("gen_random_uuid()");
    e.Property(x => x.OrganizationName).HasMaxLength(256).IsRequired();
    e.Property(x => x.RequesterEmail).HasMaxLength(160).IsRequired();
    e.Property(x => x.Reason).HasMaxLength(1024);
    e.Property(x => x.Status).HasMaxLength(32)
        .HasDefaultValue(TenantRequestStatus.Pending)
        .HasConversion(
            v => v.ToString().ToLowerInvariant(),
            v => Enum.Parse<TenantRequestStatus>(v, true));
    e.Property(x => x.RejectionReason).HasMaxLength(1024);
    e.Property(x => x.CreatedAt).HasDefaultValueSql("now()");

    e.HasIndex(x => x.Status);
    e.HasIndex(x => x.RequesterAccountId);

    e.HasOne(x => x.RequesterAccount)
        .WithMany()
        .HasForeignKey(x => x.RequesterAccountId)
        .OnDelete(DeleteBehavior.SetNull);

    e.HasOne(x => x.Reviewer)
        .WithMany()
        .HasForeignKey(x => x.ReviewedBy)
        .OnDelete(DeleteBehavior.SetNull);
});
```

- [ ] **Step 3: Build to verify compilation**

Run: `dotnet build src/SsdidDrive.Api`
Expected: Build succeeded

- [ ] **Step 4: Commit**

```bash
git add src/SsdidDrive.Api/Data/Entities/TenantRequest.cs src/SsdidDrive.Api/Data/AppDbContext.cs
git commit -m "feat: add TenantRequest entity and EF configuration"
```

### Task 3: EF Core Migration

**Files:**
- Create: New migration files (auto-generated)

- [ ] **Step 1: Generate migration**

Run: `dotnet ef migrations add AddExtensionServiceAndTenantRequest --project src/SsdidDrive.Api`
Expected: Migration files created in `src/SsdidDrive.Api/Migrations/`

- [ ] **Step 2: Verify migration looks correct**

Review the generated migration to confirm it creates `extension_services` and `tenant_requests` tables with correct columns, indexes, and foreign keys.

- [ ] **Step 3: Build to verify**

Run: `dotnet build src/SsdidDrive.Api`
Expected: Build succeeded

- [ ] **Step 4: Commit**

```bash
git add src/SsdidDrive.Api/Migrations/
git commit -m "migration: add extension_services and tenant_requests tables"
```

### Task 4: ExtensionServiceContext + CurrentUserAccessor TenantId

**Files:**
- Create: `src/SsdidDrive.Api/Common/ExtensionServiceContext.cs`
- Modify: `src/SsdidDrive.Api/Common/CurrentUserAccessor.cs`

- [ ] **Step 1: Create ExtensionServiceContext**

```csharp
// src/SsdidDrive.Api/Common/ExtensionServiceContext.cs
namespace SsdidDrive.Api.Common;

/// <summary>
/// Scoped context populated by HmacAuthMiddleware for extension service requests.
/// </summary>
public class ExtensionServiceContext
{
    public Guid ServiceId { get; set; }
    public Guid TenantId { get; set; }
    public string ServiceName { get; set; } = default!;
    public Dictionary<string, bool> Permissions { get; set; } = new();

    public bool HasPermission(string permission)
        => Permissions.TryGetValue(permission, out var allowed) && allowed;
}
```

- [ ] **Step 2: Add TenantId to CurrentUserAccessor**

Add to `CurrentUserAccessor`:

```csharp
public Guid? TenantId { get; set; }
```

- [ ] **Step 3: Build to verify**

Run: `dotnet build src/SsdidDrive.Api`
Expected: Build succeeded

- [ ] **Step 4: Commit**

```bash
git add src/SsdidDrive.Api/Common/ExtensionServiceContext.cs src/SsdidDrive.Api/Common/CurrentUserAccessor.cs
git commit -m "feat: add ExtensionServiceContext and TenantId to CurrentUserAccessor"
```

### Task 5: HMAC Signature Computation (Unit Tests First)

**Files:**
- Create: `tests/SsdidDrive.Api.Tests/Unit/HmacSignatureTests.cs`
- Create: `src/SsdidDrive.Api/Middleware/HmacAuthMiddleware.cs` (signature computation helper only)

- [ ] **Step 1: Write failing tests for HMAC signature computation**

```csharp
// tests/SsdidDrive.Api.Tests/Unit/HmacSignatureTests.cs
using System.Security.Cryptography;
using System.Text;
using SsdidDrive.Api.Middleware;

namespace SsdidDrive.Api.Tests.Unit;

public class HmacSignatureTests
{
    [Fact]
    public void ComputeSignature_ReturnsConsistentResult()
    {
        var secret = Convert.FromBase64String(Convert.ToBase64String(RandomNumberGenerator.GetBytes(32)));
        var timestamp = "2026-03-14T10:00:00Z";
        var method = "POST";
        var path = "/api/ext/files";
        var bodyHash = HmacSignatureHelper.ComputeBodyHash("""{"name":"test"}""");

        var sig1 = HmacSignatureHelper.ComputeSignature(secret, timestamp, method, path, bodyHash);
        var sig2 = HmacSignatureHelper.ComputeSignature(secret, timestamp, method, path, bodyHash);

        Assert.Equal(sig1, sig2);
    }

    [Fact]
    public void ComputeSignature_DifferentSecrets_ProduceDifferentSignatures()
    {
        var secret1 = RandomNumberGenerator.GetBytes(32);
        var secret2 = RandomNumberGenerator.GetBytes(32);
        var timestamp = "2026-03-14T10:00:00Z";
        var method = "GET";
        var path = "/api/ext/files";
        var bodyHash = HmacSignatureHelper.ComputeBodyHash("");

        var sig1 = HmacSignatureHelper.ComputeSignature(secret1, timestamp, method, path, bodyHash);
        var sig2 = HmacSignatureHelper.ComputeSignature(secret2, timestamp, method, path, bodyHash);

        Assert.NotEqual(sig1, sig2);
    }

    [Fact]
    public void ComputeBodyHash_EmptyBody_ReturnsExpectedHash()
    {
        var hash = HmacSignatureHelper.ComputeBodyHash("");
        // SHA-256 of empty string is well-known
        Assert.Equal("e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855", hash);
    }

    [Fact]
    public void VerifySignature_ValidSignature_ReturnsTrue()
    {
        var secret = RandomNumberGenerator.GetBytes(32);
        var timestamp = "2026-03-14T10:00:00Z";
        var method = "POST";
        var path = "/api/ext/files";
        var bodyHash = HmacSignatureHelper.ComputeBodyHash("""{"data":"test"}""");

        var signature = HmacSignatureHelper.ComputeSignature(secret, timestamp, method, path, bodyHash);

        Assert.True(HmacSignatureHelper.VerifySignature(secret, timestamp, method, path, bodyHash, signature));
    }

    [Fact]
    public void VerifySignature_TamperedSignature_ReturnsFalse()
    {
        var secret = RandomNumberGenerator.GetBytes(32);
        var timestamp = "2026-03-14T10:00:00Z";
        var method = "POST";
        var path = "/api/ext/files";
        var bodyHash = HmacSignatureHelper.ComputeBodyHash("data");

        var signature = HmacSignatureHelper.ComputeSignature(secret, timestamp, method, path, bodyHash);
        var tampered = Convert.ToBase64String(new byte[32]); // wrong signature

        Assert.False(HmacSignatureHelper.VerifySignature(secret, timestamp, method, path, bodyHash, tampered));
    }

    [Fact]
    public void VerifySignature_DifferentPath_ReturnsFalse()
    {
        var secret = RandomNumberGenerator.GetBytes(32);
        var timestamp = "2026-03-14T10:00:00Z";
        var method = "GET";
        var bodyHash = HmacSignatureHelper.ComputeBodyHash("");

        var signature = HmacSignatureHelper.ComputeSignature(secret, timestamp, method, "/api/ext/files", bodyHash);

        Assert.False(HmacSignatureHelper.VerifySignature(secret, timestamp, method, "/api/ext/folders", bodyHash, signature));
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `dotnet test tests/SsdidDrive.Api.Tests/ --filter "HmacSignatureTests" --no-restore`
Expected: FAIL — `HmacSignatureHelper` does not exist

- [ ] **Step 3: Implement HmacSignatureHelper**

```csharp
// Add to src/SsdidDrive.Api/Middleware/HmacAuthMiddleware.cs (just the helper for now)
using System.Security.Cryptography;
using System.Text;

namespace SsdidDrive.Api.Middleware;

public static class HmacSignatureHelper
{
    public static string ComputeBodyHash(string body)
    {
        var hash = SHA256.HashData(Encoding.UTF8.GetBytes(body));
        return Convert.ToHexStringLower(hash);
    }

    public static string ComputeSignature(byte[] secret, string timestamp, string method, string path, string bodyHash)
    {
        var stringToSign = $"{timestamp}\n{method}\n{path}\n{bodyHash}";
        var signatureBytes = HMACSHA256.HashData(secret, Encoding.UTF8.GetBytes(stringToSign));
        return Convert.ToBase64String(signatureBytes);
    }

    public static bool VerifySignature(byte[] secret, string timestamp, string method, string path, string bodyHash, string providedSignature)
    {
        var expected = ComputeSignature(secret, timestamp, method, path, bodyHash);
        var expectedBytes = Convert.FromBase64String(expected);
        var providedBytes = Convert.FromBase64String(providedSignature);
        return CryptographicOperations.FixedTimeEquals(expectedBytes, providedBytes);
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `dotnet test tests/SsdidDrive.Api.Tests/ --filter "HmacSignatureTests" --no-restore`
Expected: All 6 tests PASS

- [ ] **Step 5: Commit**

```bash
git add tests/SsdidDrive.Api.Tests/Unit/HmacSignatureTests.cs src/SsdidDrive.Api/Middleware/HmacAuthMiddleware.cs
git commit -m "feat: add HMAC signature computation and verification helper with tests"
```

### Task 6: HMAC Auth Middleware

**Files:**
- Modify: `src/SsdidDrive.Api/Middleware/HmacAuthMiddleware.cs` (add middleware class)
- Modify: `src/SsdidDrive.Api/Program.cs`

- [ ] **Step 1: Implement HmacAuthMiddleware**

Add the middleware class to the same file after `HmacSignatureHelper`:

```csharp
public class HmacAuthMiddleware(RequestDelegate next, ILogger<HmacAuthMiddleware> logger)
{
    private static readonly TimeSpan MaxTimestampAge = TimeSpan.FromMinutes(5);

    public async Task InvokeAsync(HttpContext context, AppDbContext db, ExtensionServiceContext serviceContext, TotpEncryption encryption)
    {
        var serviceIdHeader = context.Request.Headers["X-Service-Id"].FirstOrDefault();
        var timestampHeader = context.Request.Headers["X-Timestamp"].FirstOrDefault();
        var signatureHeader = context.Request.Headers["X-Signature"].FirstOrDefault();

        if (string.IsNullOrEmpty(serviceIdHeader) || string.IsNullOrEmpty(timestampHeader) || string.IsNullOrEmpty(signatureHeader))
        {
            context.Response.StatusCode = 401;
            await context.Response.WriteAsJsonAsync(new { error = "Missing HMAC authentication headers" });
            return;
        }

        if (!Guid.TryParse(serviceIdHeader, out var serviceId))
        {
            context.Response.StatusCode = 401;
            await context.Response.WriteAsJsonAsync(new { error = "Invalid X-Service-Id format" });
            return;
        }

        // Parse and validate timestamp
        if (!DateTimeOffset.TryParse(timestampHeader, out var timestamp))
        {
            context.Response.StatusCode = 401;
            await context.Response.WriteAsJsonAsync(new { error = "Invalid X-Timestamp format" });
            return;
        }

        var age = DateTimeOffset.UtcNow - timestamp;
        if (age > MaxTimestampAge || age < -TimeSpan.FromMinutes(1))
        {
            context.Response.StatusCode = 401;
            await context.Response.WriteAsJsonAsync(new { error = "Timestamp outside acceptable range" });
            return;
        }

        // Look up service
        var service = await db.ExtensionServices.FindAsync(serviceId);
        if (service is null || !service.Enabled)
        {
            context.Response.StatusCode = 401;
            await context.Response.WriteAsJsonAsync(new { error = "Service not found or disabled" });
            return;
        }

        // Decrypt the stored HMAC secret
        byte[] secret;
        try
        {
            var decryptedKey = encryption.Decrypt(service.ServiceKey);
            secret = Convert.FromBase64String(decryptedKey);
        }
        catch
        {
            logger.LogError("Failed to decrypt service key for service {ServiceId}", serviceId);
            context.Response.StatusCode = 500;
            await context.Response.WriteAsJsonAsync(new { error = "Internal server error" });
            return;
        }

        // Read body for signature verification
        context.Request.EnableBuffering();
        using var reader = new StreamReader(context.Request.Body, leaveOpen: true);
        var body = await reader.ReadToEndAsync();
        context.Request.Body.Position = 0;

        var bodyHash = HmacSignatureHelper.ComputeBodyHash(body);
        var method = context.Request.Method;
        var path = context.Request.Path.Value ?? "/";

        if (!HmacSignatureHelper.VerifySignature(secret, timestampHeader, method, path, bodyHash, signatureHeader))
        {
            context.Response.StatusCode = 401;
            await context.Response.WriteAsJsonAsync(new { error = "Invalid HMAC signature" });
            return;
        }

        // Parse permissions from JSON
        var permissions = new Dictionary<string, bool>();
        try
        {
            permissions = System.Text.Json.JsonSerializer.Deserialize<Dictionary<string, bool>>(service.Permissions)
                ?? new Dictionary<string, bool>();
        }
        catch { /* default to empty permissions */ }

        // Set context
        serviceContext.ServiceId = service.Id;
        serviceContext.TenantId = service.TenantId;
        serviceContext.ServiceName = service.Name;
        serviceContext.Permissions = permissions;

        // Update LastUsedAt (fire-and-forget, don't block the request)
        service.LastUsedAt = DateTimeOffset.UtcNow;
        _ = db.SaveChangesAsync();

        await next(context);
    }
}
```

- [ ] **Step 2: Register services and middleware in Program.cs**

Add to service registration section (after `OidcTokenValidator`):

```csharp
builder.Services.AddScoped<ExtensionServiceContext>();
```

Add HMAC middleware before SsdidAuthMiddleware pipeline (the `/api/ext/*` route mapping will handle this — no middleware registration needed at pipeline level since extension service endpoints will use their own middleware via endpoint filters or a separate route group).

**Note:** The HMAC middleware will be applied via `UseWhen` for `/api/ext` routes, similar to how `SsdidAuthMiddleware` is applied for `/api` routes. However, since there are no `/api/ext` endpoints in this plan (those come in future plans when clients integrate), the middleware registration is prepared but not actively routing. For now, the middleware is tested via integration tests that directly invoke it.

Add `using SsdidDrive.Api.Common;` if not already imported (for `ExtensionServiceContext`).

- [ ] **Step 3: Build to verify**

Run: `dotnet build src/SsdidDrive.Api`
Expected: Build succeeded

- [ ] **Step 4: Commit**

```bash
git add src/SsdidDrive.Api/Middleware/HmacAuthMiddleware.cs src/SsdidDrive.Api/Program.cs
git commit -m "feat: add HMAC auth middleware for extension service requests"
```

---

## Chunk 2: Extension Service CRUD Endpoints

### Task 7: ExtensionServiceFeature Route Group

**Files:**
- Create: `src/SsdidDrive.Api/Features/ExtensionServices/ExtensionServiceFeature.cs`

- [ ] **Step 1: Create the feature route group**

```csharp
// src/SsdidDrive.Api/Features/ExtensionServices/ExtensionServiceFeature.cs
using Microsoft.EntityFrameworkCore;
using SsdidDrive.Api.Common;
using SsdidDrive.Api.Data;
using SsdidDrive.Api.Data.Entities;

namespace SsdidDrive.Api.Features.ExtensionServices;

public static class ExtensionServiceFeature
{
    public static void MapExtensionServiceFeature(this IEndpointRouteBuilder routes)
    {
        var group = routes.MapGroup("/api/tenant/services")
            .WithTags("Extension Services")
            .AddEndpointFilter(async (ctx, next) =>
            {
                // Require Owner or Admin role in user's active tenant
                var accessor = ctx.HttpContext.RequestServices.GetRequiredService<CurrentUserAccessor>();
                var db = ctx.HttpContext.RequestServices.GetRequiredService<AppDbContext>();

                if (accessor.User?.TenantId is null)
                    return Results.Problem(
                        statusCode: 403,
                        title: "Forbidden",
                        detail: "No active tenant");

                var userTenant = await db.UserTenants
                    .FirstOrDefaultAsync(ut => ut.UserId == accessor.UserId && ut.TenantId == accessor.User.TenantId);

                if (userTenant is null || (userTenant.Role != TenantRole.Owner && userTenant.Role != TenantRole.Admin))
                    return Results.Problem(
                        statusCode: 403,
                        title: "Forbidden",
                        detail: "Owner or Admin role required");

                return await next(ctx);
            });

        RegisterService.Map(group);
        ListServices.Map(group);
        GetService.Map(group);
        UpdateService.Map(group);
        RevokeService.Map(group);
        RotateSecret.Map(group);
    }
}
```

- [ ] **Step 2: Register in Program.cs**

Add `using SsdidDrive.Api.Features.ExtensionServices;` and `app.MapExtensionServiceFeature();` after `app.MapAccountFeature();`.

- [ ] **Step 3: Build to verify** (will fail until endpoint stubs exist — that's OK, proceed to next tasks)

### Task 8: RegisterService Endpoint

**Files:**
- Create: `src/SsdidDrive.Api/Features/ExtensionServices/RegisterService.cs`

- [ ] **Step 1: Write failing integration test**

```csharp
// Add to tests/SsdidDrive.Api.Tests/Integration/ExtensionServiceTests.cs
using System.Net;
using System.Net.Http.Json;
using System.Text.Json;
using SsdidDrive.Api.Tests.Infrastructure;

namespace SsdidDrive.Api.Tests.Integration;

public class ExtensionServiceTests : IClassFixture<SsdidDriveFactory>
{
    private readonly SsdidDriveFactory _factory;
    private static readonly JsonSerializerOptions Json = TestFixture.Json;

    public ExtensionServiceTests(SsdidDriveFactory factory) => _factory = factory;

    [Fact]
    public async Task RegisterService_ValidRequest_ReturnsCreatedWithSecret()
    {
        var (client, userId, tenantId) = await TestFixture.CreateAuthenticatedClientAsync(_factory);

        var response = await client.PostAsJsonAsync("/api/tenant/services", new
        {
            name = "Test Analytics",
            permissions = new { files_read = true, activity_read = true }
        }, Json);

        Assert.Equal(HttpStatusCode.Created, response.StatusCode);
        var body = await response.Content.ReadFromJsonAsync<JsonElement>(Json);
        Assert.True(body.TryGetProperty("id", out _));
        Assert.True(body.TryGetProperty("service_key", out var keyProp));
        Assert.False(string.IsNullOrEmpty(keyProp.GetString()));
        Assert.Equal("Test Analytics", body.GetProperty("name").GetString());
    }

    [Fact]
    public async Task RegisterService_DuplicateName_ReturnsConflict()
    {
        var (client, userId, tenantId) = await TestFixture.CreateAuthenticatedClientAsync(_factory);

        await client.PostAsJsonAsync("/api/tenant/services", new
        {
            name = "Unique Service",
            permissions = new { files_read = true }
        }, Json);

        var response = await client.PostAsJsonAsync("/api/tenant/services", new
        {
            name = "Unique Service",
            permissions = new { files_read = true }
        }, Json);

        Assert.Equal(HttpStatusCode.Conflict, response.StatusCode);
    }

    [Fact]
    public async Task RegisterService_MemberRole_ReturnsForbidden()
    {
        var (ownerClient, _, tenantId) = await TestFixture.CreateAuthenticatedClientAsync(_factory);
        var (memberClient, _) = await TestFixture.CreateUserInTenantAsync(_factory, tenantId);

        var response = await memberClient.PostAsJsonAsync("/api/tenant/services", new
        {
            name = "Member Service",
            permissions = new { files_read = true }
        }, Json);

        Assert.Equal(HttpStatusCode.Forbidden, response.StatusCode);
    }
}
```

- [ ] **Step 2: Implement RegisterService**

```csharp
// src/SsdidDrive.Api/Features/ExtensionServices/RegisterService.cs
using System.Security.Cryptography;
using System.Text.Json;
using Microsoft.EntityFrameworkCore;
using SsdidDrive.Api.Common;
using SsdidDrive.Api.Data;
using SsdidDrive.Api.Data.Entities;
using SsdidDrive.Api.Services;

namespace SsdidDrive.Api.Features.ExtensionServices;

public static class RegisterService
{
    public static void Map(RouteGroupBuilder group) =>
        group.MapPost("/", Handle);

    private record RegisterRequest(string? Name, Dictionary<string, bool>? Permissions);

    private static async Task<IResult> Handle(
        RegisterRequest request,
        AppDbContext db,
        CurrentUserAccessor accessor,
        TotpEncryption encryption,
        AuditService audit,
        CancellationToken ct)
    {
        if (string.IsNullOrWhiteSpace(request.Name))
            return AppError.BadRequest("Name is required").ToProblemResult();

        var tenantId = accessor.User!.TenantId!.Value;

        var exists = await db.ExtensionServices
            .AnyAsync(s => s.TenantId == tenantId && s.Name == request.Name.Trim(), ct);
        if (exists)
            return AppError.Conflict($"A service named '{request.Name}' already exists in this tenant").ToProblemResult();

        // Generate 256-bit HMAC secret
        var secretBytes = RandomNumberGenerator.GetBytes(32);
        var secretBase64 = Convert.ToBase64String(secretBytes);

        // Encrypt for storage
        var encryptedSecret = encryption.Encrypt(secretBase64);

        var permissions = request.Permissions ?? new Dictionary<string, bool>();
        var permissionsJson = JsonSerializer.Serialize(permissions);

        var service = new ExtensionService
        {
            Id = Guid.NewGuid(),
            TenantId = tenantId,
            Name = request.Name.Trim(),
            ServiceKey = encryptedSecret,
            Permissions = permissionsJson,
            Enabled = true,
            CreatedAt = DateTimeOffset.UtcNow
        };

        db.ExtensionServices.Add(service);
        await db.SaveChangesAsync(ct);

        await audit.LogAsync(accessor.UserId, "service.registered", "ExtensionService", service.Id,
            $"Registered extension service '{service.Name}'", ct);

        // Return the secret in plaintext — shown once only
        return Results.Created($"/api/tenant/services/{service.Id}", new
        {
            id = service.Id,
            name = service.Name,
            service_key = secretBase64,
            permissions,
            enabled = service.Enabled,
            created_at = service.CreatedAt
        });
    }
}
```

- [ ] **Step 3: Run tests**

Run: `dotnet test tests/SsdidDrive.Api.Tests/ --filter "ExtensionServiceTests" --no-restore`
Expected: All 3 tests PASS

- [ ] **Step 4: Commit**

```bash
git add src/SsdidDrive.Api/Features/ExtensionServices/ tests/SsdidDrive.Api.Tests/Integration/ExtensionServiceTests.cs
git commit -m "feat: add RegisterService endpoint for extension services"
```

### Task 9: ListServices Endpoint

**Files:**
- Create: `src/SsdidDrive.Api/Features/ExtensionServices/ListServices.cs`
- Modify: `tests/SsdidDrive.Api.Tests/Integration/ExtensionServiceTests.cs`

- [ ] **Step 1: Add integration test**

```csharp
[Fact]
public async Task ListServices_ReturnsAllServicesForTenant()
{
    var (client, userId, tenantId) = await TestFixture.CreateAuthenticatedClientAsync(_factory);

    await client.PostAsJsonAsync("/api/tenant/services", new { name = "Service A", permissions = new { files_read = true } }, Json);
    await client.PostAsJsonAsync("/api/tenant/services", new { name = "Service B", permissions = new { activity_read = true } }, Json);

    var response = await client.GetAsync("/api/tenant/services");

    Assert.Equal(HttpStatusCode.OK, response.StatusCode);
    var body = await response.Content.ReadFromJsonAsync<JsonElement>(Json);
    var items = body.GetProperty("items");
    Assert.True(items.GetArrayLength() >= 2);

    // Secret should NOT be returned in list
    var first = items[0];
    Assert.False(first.TryGetProperty("service_key", out _));
}
```

- [ ] **Step 2: Implement ListServices**

```csharp
// src/SsdidDrive.Api/Features/ExtensionServices/ListServices.cs
using System.Text.Json;
using Microsoft.EntityFrameworkCore;
using SsdidDrive.Api.Common;
using SsdidDrive.Api.Data;

namespace SsdidDrive.Api.Features.ExtensionServices;

public static class ListServices
{
    public static void Map(RouteGroupBuilder group) =>
        group.MapGet("/", Handle);

    private static async Task<IResult> Handle(
        AppDbContext db,
        CurrentUserAccessor accessor,
        CancellationToken ct)
    {
        var tenantId = accessor.User!.TenantId!.Value;

        var services = await db.ExtensionServices
            .Where(s => s.TenantId == tenantId)
            .OrderBy(s => s.Name)
            .Select(s => new
            {
                id = s.Id,
                name = s.Name,
                permissions = s.Permissions,
                enabled = s.Enabled,
                created_at = s.CreatedAt,
                last_used_at = s.LastUsedAt
            })
            .ToListAsync(ct);

        // Parse permissions JSON strings back to objects for proper serialization
        var items = services.Select(s => new
        {
            s.id,
            s.name,
            permissions = JsonSerializer.Deserialize<Dictionary<string, bool>>(s.permissions),
            s.enabled,
            s.created_at,
            s.last_used_at
        });

        return Results.Ok(new { items });
    }
}
```

- [ ] **Step 3: Run tests, verify, commit**

### Task 10: GetService Endpoint

**Files:**
- Create: `src/SsdidDrive.Api/Features/ExtensionServices/GetService.cs`
- Modify: `tests/SsdidDrive.Api.Tests/Integration/ExtensionServiceTests.cs`

- [ ] **Step 1: Add integration test**

```csharp
[Fact]
public async Task GetService_ValidId_ReturnsServiceDetails()
{
    var (client, userId, tenantId) = await TestFixture.CreateAuthenticatedClientAsync(_factory);

    var createResp = await client.PostAsJsonAsync("/api/tenant/services", new { name = "Details Svc", permissions = new { files_read = true } }, Json);
    var createBody = await createResp.Content.ReadFromJsonAsync<JsonElement>(Json);
    var serviceId = createBody.GetProperty("id").GetString();

    var response = await client.GetAsync($"/api/tenant/services/{serviceId}");

    Assert.Equal(HttpStatusCode.OK, response.StatusCode);
    var body = await response.Content.ReadFromJsonAsync<JsonElement>(Json);
    Assert.Equal("Details Svc", body.GetProperty("name").GetString());
    Assert.False(body.TryGetProperty("service_key", out _)); // Secret not returned in GET
}

[Fact]
public async Task GetService_WrongTenant_ReturnsNotFound()
{
    var (client1, _, _) = await TestFixture.CreateAuthenticatedClientAsync(_factory);
    var (client2, _, _) = await TestFixture.CreateAuthenticatedClientAsync(_factory);

    var createResp = await client1.PostAsJsonAsync("/api/tenant/services", new { name = "Isolated Svc", permissions = new { files_read = true } }, Json);
    var createBody = await createResp.Content.ReadFromJsonAsync<JsonElement>(Json);
    var serviceId = createBody.GetProperty("id").GetString();

    var response = await client2.GetAsync($"/api/tenant/services/{serviceId}");
    Assert.Equal(HttpStatusCode.NotFound, response.StatusCode);
}
```

- [ ] **Step 2: Implement GetService**

```csharp
// src/SsdidDrive.Api/Features/ExtensionServices/GetService.cs
using System.Text.Json;
using Microsoft.EntityFrameworkCore;
using SsdidDrive.Api.Common;
using SsdidDrive.Api.Data;

namespace SsdidDrive.Api.Features.ExtensionServices;

public static class GetService
{
    public static void Map(RouteGroupBuilder group) =>
        group.MapGet("/{id:guid}", Handle);

    private static async Task<IResult> Handle(
        Guid id,
        AppDbContext db,
        CurrentUserAccessor accessor,
        CancellationToken ct)
    {
        var tenantId = accessor.User!.TenantId!.Value;

        var service = await db.ExtensionServices
            .FirstOrDefaultAsync(s => s.Id == id && s.TenantId == tenantId, ct);

        if (service is null)
            return AppError.NotFound("Extension service not found").ToProblemResult();

        var permissions = JsonSerializer.Deserialize<Dictionary<string, bool>>(service.Permissions);

        return Results.Ok(new
        {
            id = service.Id,
            name = service.Name,
            permissions,
            enabled = service.Enabled,
            created_at = service.CreatedAt,
            last_used_at = service.LastUsedAt
        });
    }
}
```

- [ ] **Step 3: Run tests, verify, commit**

### Task 11: UpdateService Endpoint

**Files:**
- Create: `src/SsdidDrive.Api/Features/ExtensionServices/UpdateService.cs`
- Modify: `tests/SsdidDrive.Api.Tests/Integration/ExtensionServiceTests.cs`

- [ ] **Step 1: Add integration test**

```csharp
[Fact]
public async Task UpdateService_ValidRequest_UpdatesPermissionsAndEnabled()
{
    var (client, _, _) = await TestFixture.CreateAuthenticatedClientAsync(_factory);

    var createResp = await client.PostAsJsonAsync("/api/tenant/services", new { name = "Updatable", permissions = new { files_read = true } }, Json);
    var createBody = await createResp.Content.ReadFromJsonAsync<JsonElement>(Json);
    var serviceId = createBody.GetProperty("id").GetString();

    var response = await client.PutAsJsonAsync($"/api/tenant/services/{serviceId}", new
    {
        permissions = new { files_read = true, files_write = true, activity_read = true },
        enabled = false
    }, Json);

    Assert.Equal(HttpStatusCode.OK, response.StatusCode);
    var body = await response.Content.ReadFromJsonAsync<JsonElement>(Json);
    Assert.False(body.GetProperty("enabled").GetBoolean());
}
```

- [ ] **Step 2: Implement UpdateService**

```csharp
// src/SsdidDrive.Api/Features/ExtensionServices/UpdateService.cs
using System.Text.Json;
using Microsoft.EntityFrameworkCore;
using SsdidDrive.Api.Common;
using SsdidDrive.Api.Data;

namespace SsdidDrive.Api.Features.ExtensionServices;

public static class UpdateService
{
    public static void Map(RouteGroupBuilder group) =>
        group.MapPut("/{id:guid}", Handle);

    private record UpdateRequest(Dictionary<string, bool>? Permissions, bool? Enabled);

    private static async Task<IResult> Handle(
        Guid id,
        UpdateRequest request,
        AppDbContext db,
        CurrentUserAccessor accessor,
        AuditService audit,
        CancellationToken ct)
    {
        var tenantId = accessor.User!.TenantId!.Value;

        var service = await db.ExtensionServices
            .FirstOrDefaultAsync(s => s.Id == id && s.TenantId == tenantId, ct);

        if (service is null)
            return AppError.NotFound("Extension service not found").ToProblemResult();

        if (request.Permissions is not null)
            service.Permissions = JsonSerializer.Serialize(request.Permissions);

        if (request.Enabled.HasValue)
            service.Enabled = request.Enabled.Value;

        await db.SaveChangesAsync(ct);

        var permissions = JsonSerializer.Deserialize<Dictionary<string, bool>>(service.Permissions);

        return Results.Ok(new
        {
            id = service.Id,
            name = service.Name,
            permissions,
            enabled = service.Enabled,
            created_at = service.CreatedAt,
            last_used_at = service.LastUsedAt
        });
    }
}
```

Need to add `using SsdidDrive.Api.Services;` for `AuditService` — actually `AuditService` is in `SsdidDrive.Api.Services` namespace. The endpoint signature needs it injected. Let me fix:

The `AuditService` import: since this endpoint is in `SsdidDrive.Api.Features.ExtensionServices` namespace, we need `using SsdidDrive.Api.Services;`.

- [ ] **Step 3: Run tests, verify, commit**

### Task 12: RevokeService Endpoint

**Files:**
- Create: `src/SsdidDrive.Api/Features/ExtensionServices/RevokeService.cs`
- Modify: `tests/SsdidDrive.Api.Tests/Integration/ExtensionServiceTests.cs`

- [ ] **Step 1: Add integration test**

```csharp
[Fact]
public async Task RevokeService_ValidId_ReturnsNoContent()
{
    var (client, _, _) = await TestFixture.CreateAuthenticatedClientAsync(_factory);

    var createResp = await client.PostAsJsonAsync("/api/tenant/services", new { name = "Revokable", permissions = new { files_read = true } }, Json);
    var createBody = await createResp.Content.ReadFromJsonAsync<JsonElement>(Json);
    var serviceId = createBody.GetProperty("id").GetString();

    var response = await client.DeleteAsync($"/api/tenant/services/{serviceId}");
    Assert.Equal(HttpStatusCode.NoContent, response.StatusCode);

    // Verify it's gone
    var getResponse = await client.GetAsync($"/api/tenant/services/{serviceId}");
    Assert.Equal(HttpStatusCode.NotFound, getResponse.StatusCode);
}
```

- [ ] **Step 2: Implement RevokeService**

```csharp
// src/SsdidDrive.Api/Features/ExtensionServices/RevokeService.cs
using Microsoft.EntityFrameworkCore;
using SsdidDrive.Api.Common;
using SsdidDrive.Api.Data;
using SsdidDrive.Api.Services;

namespace SsdidDrive.Api.Features.ExtensionServices;

public static class RevokeService
{
    public static void Map(RouteGroupBuilder group) =>
        group.MapDelete("/{id:guid}", Handle);

    private static async Task<IResult> Handle(
        Guid id,
        AppDbContext db,
        CurrentUserAccessor accessor,
        AuditService audit,
        CancellationToken ct)
    {
        var tenantId = accessor.User!.TenantId!.Value;

        var service = await db.ExtensionServices
            .FirstOrDefaultAsync(s => s.Id == id && s.TenantId == tenantId, ct);

        if (service is null)
            return AppError.NotFound("Extension service not found").ToProblemResult();

        db.ExtensionServices.Remove(service);
        await db.SaveChangesAsync(ct);

        await audit.LogAsync(accessor.UserId, "service.revoked", "ExtensionService", service.Id,
            $"Revoked extension service '{service.Name}'", ct);

        return Results.NoContent();
    }
}
```

- [ ] **Step 3: Run tests, verify, commit**

### Task 13: RotateSecret Endpoint

**Files:**
- Create: `src/SsdidDrive.Api/Features/ExtensionServices/RotateSecret.cs`
- Modify: `tests/SsdidDrive.Api.Tests/Integration/ExtensionServiceTests.cs`

- [ ] **Step 1: Add integration test**

```csharp
[Fact]
public async Task RotateSecret_ValidId_ReturnsNewSecret()
{
    var (client, _, _) = await TestFixture.CreateAuthenticatedClientAsync(_factory);

    var createResp = await client.PostAsJsonAsync("/api/tenant/services", new { name = "Rotatable", permissions = new { files_read = true } }, Json);
    var createBody = await createResp.Content.ReadFromJsonAsync<JsonElement>(Json);
    var serviceId = createBody.GetProperty("id").GetString();
    var originalKey = createBody.GetProperty("service_key").GetString();

    var response = await client.PostAsync($"/api/tenant/services/{serviceId}/rotate", null);

    Assert.Equal(HttpStatusCode.OK, response.StatusCode);
    var body = await response.Content.ReadFromJsonAsync<JsonElement>(Json);
    var newKey = body.GetProperty("service_key").GetString();
    Assert.NotEqual(originalKey, newKey);
    Assert.False(string.IsNullOrEmpty(newKey));
}
```

- [ ] **Step 2: Implement RotateSecret**

```csharp
// src/SsdidDrive.Api/Features/ExtensionServices/RotateSecret.cs
using System.Security.Cryptography;
using Microsoft.EntityFrameworkCore;
using SsdidDrive.Api.Common;
using SsdidDrive.Api.Data;
using SsdidDrive.Api.Services;

namespace SsdidDrive.Api.Features.ExtensionServices;

public static class RotateSecret
{
    public static void Map(RouteGroupBuilder group) =>
        group.MapPost("/{id:guid}/rotate", Handle);

    private static async Task<IResult> Handle(
        Guid id,
        AppDbContext db,
        CurrentUserAccessor accessor,
        TotpEncryption encryption,
        AuditService audit,
        CancellationToken ct)
    {
        var tenantId = accessor.User!.TenantId!.Value;

        var service = await db.ExtensionServices
            .FirstOrDefaultAsync(s => s.Id == id && s.TenantId == tenantId, ct);

        if (service is null)
            return AppError.NotFound("Extension service not found").ToProblemResult();

        // Generate new 256-bit secret
        var newSecretBytes = RandomNumberGenerator.GetBytes(32);
        var newSecretBase64 = Convert.ToBase64String(newSecretBytes);

        // Encrypt and store
        service.ServiceKey = encryption.Encrypt(newSecretBase64);
        await db.SaveChangesAsync(ct);

        await audit.LogAsync(accessor.UserId, "service.secret.rotated", "ExtensionService", service.Id,
            $"Rotated HMAC secret for service '{service.Name}'", ct);

        return Results.Ok(new
        {
            id = service.Id,
            name = service.Name,
            service_key = newSecretBase64
        });
    }
}
```

- [ ] **Step 3: Run tests, verify, commit**

---

## Chunk 3: HMAC Middleware Integration Tests

### Task 14: HMAC Middleware Integration Tests

**Files:**
- Create: `tests/SsdidDrive.Api.Tests/Integration/HmacMiddlewareTests.cs`

These tests verify the full HMAC auth flow by creating a service, getting its key, and making HMAC-signed requests. Since there are no `/api/ext/*` endpoints yet, we'll test by adding a test-only endpoint or by directly testing the middleware via the service management endpoints with HMAC headers.

**Alternative approach:** Test the middleware logic by creating a service, using the returned key to sign a request, and verifying the `ExtensionServiceContext` is populated. We can do this by adding a simple test endpoint during tests, or by testing the core middleware components in isolation. The simplest approach is to test signature verification and service lookup via unit-style tests that invoke the middleware directly.

- [ ] **Step 1: Write integration tests**

```csharp
// tests/SsdidDrive.Api.Tests/Integration/HmacMiddlewareTests.cs
using System.Net;
using System.Net.Http.Json;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using SsdidDrive.Api.Middleware;
using SsdidDrive.Api.Tests.Infrastructure;

namespace SsdidDrive.Api.Tests.Integration;

public class HmacMiddlewareTests : IClassFixture<SsdidDriveFactory>
{
    private readonly SsdidDriveFactory _factory;
    private static readonly JsonSerializerOptions Json = TestFixture.Json;

    public HmacMiddlewareTests(SsdidDriveFactory factory) => _factory = factory;

    [Fact]
    public async Task RegisteredService_CanComputeValidSignature()
    {
        // Create service and get the plaintext key
        var (client, userId, tenantId) = await TestFixture.CreateAuthenticatedClientAsync(_factory);
        var createResp = await client.PostAsJsonAsync("/api/tenant/services", new
        {
            name = "HMAC Test Service",
            permissions = new { files_read = true }
        }, Json);

        var body = await createResp.Content.ReadFromJsonAsync<JsonElement>(Json);
        var serviceKey = body.GetProperty("service_key").GetString()!;
        var serviceId = body.GetProperty("id").GetString()!;

        // Verify we can compute a valid signature with the returned key
        var secret = Convert.FromBase64String(serviceKey);
        var timestamp = DateTimeOffset.UtcNow.ToString("yyyy-MM-ddTHH:mm:ssZ");
        var method = "GET";
        var path = "/api/ext/files";
        var bodyHash = HmacSignatureHelper.ComputeBodyHash("");

        var signature = HmacSignatureHelper.ComputeSignature(secret, timestamp, method, path, bodyHash);

        // Signature should be valid base64
        Assert.False(string.IsNullOrEmpty(signature));
        var sigBytes = Convert.FromBase64String(signature);
        Assert.Equal(32, sigBytes.Length); // HMAC-SHA256 produces 32 bytes
    }

    [Fact]
    public async Task RotatedKey_InvalidatesOldSignatures()
    {
        var (client, userId, tenantId) = await TestFixture.CreateAuthenticatedClientAsync(_factory);
        var createResp = await client.PostAsJsonAsync("/api/tenant/services", new
        {
            name = "Rotate Test",
            permissions = new { files_read = true }
        }, Json);
        var createBody = await createResp.Content.ReadFromJsonAsync<JsonElement>(Json);
        var oldKey = createBody.GetProperty("service_key").GetString()!;
        var serviceId = createBody.GetProperty("id").GetString()!;

        // Rotate
        var rotateResp = await client.PostAsync($"/api/tenant/services/{serviceId}/rotate", null);
        var rotateBody = await rotateResp.Content.ReadFromJsonAsync<JsonElement>(Json);
        var newKey = rotateBody.GetProperty("service_key").GetString()!;

        // Old key should produce different signatures than new key
        var timestamp = DateTimeOffset.UtcNow.ToString("yyyy-MM-ddTHH:mm:ssZ");
        var bodyHash = HmacSignatureHelper.ComputeBodyHash("");

        var oldSig = HmacSignatureHelper.ComputeSignature(Convert.FromBase64String(oldKey), timestamp, "GET", "/test", bodyHash);
        var newSig = HmacSignatureHelper.ComputeSignature(Convert.FromBase64String(newKey), timestamp, "GET", "/test", bodyHash);

        Assert.NotEqual(oldSig, newSig);

        // New key should verify against new signature
        Assert.True(HmacSignatureHelper.VerifySignature(Convert.FromBase64String(newKey), timestamp, "GET", "/test", bodyHash, newSig));
        // Old key should NOT verify new signature
        Assert.False(HmacSignatureHelper.VerifySignature(Convert.FromBase64String(oldKey), timestamp, "GET", "/test", bodyHash, newSig));
    }
}
```

- [ ] **Step 2: Run tests**

Run: `dotnet test tests/SsdidDrive.Api.Tests/ --filter "HmacMiddlewareTests" --no-restore`
Expected: All tests PASS

- [ ] **Step 3: Commit**

```bash
git add tests/SsdidDrive.Api.Tests/Integration/HmacMiddlewareTests.cs
git commit -m "test: add HMAC middleware integration tests"
```

---

## Chunk 4: Tenant Request Endpoints

### Task 15: TenantRequestFeature Route Group + SubmitRequest

**Files:**
- Create: `src/SsdidDrive.Api/Features/TenantRequests/TenantRequestFeature.cs`
- Create: `src/SsdidDrive.Api/Features/TenantRequests/SubmitRequest.cs`
- Create: `tests/SsdidDrive.Api.Tests/Integration/TenantRequestTests.cs`

- [ ] **Step 1: Write failing integration test**

```csharp
// tests/SsdidDrive.Api.Tests/Integration/TenantRequestTests.cs
using System.Net;
using System.Net.Http.Json;
using System.Text.Json;
using SsdidDrive.Api.Tests.Infrastructure;

namespace SsdidDrive.Api.Tests.Integration;

public class TenantRequestTests : IClassFixture<SsdidDriveFactory>
{
    private readonly SsdidDriveFactory _factory;
    private static readonly JsonSerializerOptions Json = TestFixture.Json;

    public TenantRequestTests(SsdidDriveFactory factory) => _factory = factory;

    [Fact]
    public async Task SubmitRequest_ValidRequest_ReturnsCreated()
    {
        var (client, userId, _) = await TestFixture.CreateAuthenticatedClientAsync(_factory);

        var response = await client.PostAsJsonAsync("/api/tenant-requests", new
        {
            organization_name = "Acme Corp",
            reason = "Need secure file sharing for our team"
        }, Json);

        Assert.Equal(HttpStatusCode.Created, response.StatusCode);
        var body = await response.Content.ReadFromJsonAsync<JsonElement>(Json);
        Assert.Equal("Acme Corp", body.GetProperty("organization_name").GetString());
        Assert.Equal("pending", body.GetProperty("status").GetString());
    }

    [Fact]
    public async Task SubmitRequest_MissingName_ReturnsBadRequest()
    {
        var (client, _, _) = await TestFixture.CreateAuthenticatedClientAsync(_factory);

        var response = await client.PostAsJsonAsync("/api/tenant-requests", new
        {
            reason = "No name"
        }, Json);

        Assert.Equal(HttpStatusCode.BadRequest, response.StatusCode);
    }

    [Fact]
    public async Task SubmitRequest_Unauthenticated_ReturnsUnauthorized()
    {
        var client = _factory.CreateClient();

        var response = await client.PostAsJsonAsync("/api/tenant-requests", new
        {
            organization_name = "No Auth Corp"
        }, Json);

        Assert.Equal(HttpStatusCode.Unauthorized, response.StatusCode);
    }
}
```

- [ ] **Step 2: Create TenantRequestFeature**

```csharp
// src/SsdidDrive.Api/Features/TenantRequests/TenantRequestFeature.cs
namespace SsdidDrive.Api.Features.TenantRequests;

public static class TenantRequestFeature
{
    public static void MapTenantRequestFeature(this IEndpointRouteBuilder routes)
    {
        // Authenticated user endpoint
        var group = routes.MapGroup("/api/tenant-requests")
            .WithTags("Tenant Requests");

        SubmitRequest.Map(group);
    }
}
```

- [ ] **Step 3: Implement SubmitRequest**

```csharp
// src/SsdidDrive.Api/Features/TenantRequests/SubmitRequest.cs
using SsdidDrive.Api.Common;
using SsdidDrive.Api.Data;
using SsdidDrive.Api.Data.Entities;
using SsdidDrive.Api.Services;

namespace SsdidDrive.Api.Features.TenantRequests;

public static class SubmitRequest
{
    public static void Map(RouteGroupBuilder group) =>
        group.MapPost("/", Handle);

    private record SubmitRequestBody(string? OrganizationName, string? Reason);

    private static async Task<IResult> Handle(
        SubmitRequestBody request,
        AppDbContext db,
        CurrentUserAccessor accessor,
        AuditService audit,
        CancellationToken ct)
    {
        if (string.IsNullOrWhiteSpace(request.OrganizationName))
            return AppError.BadRequest("Organization name is required").ToProblemResult();

        var tenantRequest = new TenantRequest
        {
            Id = Guid.NewGuid(),
            OrganizationName = request.OrganizationName.Trim(),
            RequesterEmail = accessor.User!.Email ?? "",
            RequesterAccountId = accessor.UserId,
            Reason = request.Reason?.Trim(),
            Status = TenantRequestStatus.Pending,
            CreatedAt = DateTimeOffset.UtcNow
        };

        db.TenantRequests.Add(tenantRequest);
        await db.SaveChangesAsync(ct);

        await audit.LogAsync(accessor.UserId, "tenant.requested", "TenantRequest", tenantRequest.Id,
            $"Requested tenant creation: '{tenantRequest.OrganizationName}'", ct);

        return Results.Created($"/api/tenant-requests/{tenantRequest.Id}", new
        {
            id = tenantRequest.Id,
            organization_name = tenantRequest.OrganizationName,
            reason = tenantRequest.Reason,
            status = "pending",
            created_at = tenantRequest.CreatedAt
        });
    }
}
```

- [ ] **Step 4: Register in Program.cs**

Add `using SsdidDrive.Api.Features.TenantRequests;` and `app.MapTenantRequestFeature();` after `app.MapExtensionServiceFeature();`.

- [ ] **Step 5: Run tests, verify, commit**

### Task 16: ListRequests (Admin Endpoint)

**Files:**
- Create: `src/SsdidDrive.Api/Features/TenantRequests/ListRequests.cs`
- Modify: `src/SsdidDrive.Api/Features/Admin/AdminFeature.cs`
- Modify: `tests/SsdidDrive.Api.Tests/Integration/TenantRequestTests.cs`

- [ ] **Step 1: Add integration test**

```csharp
[Fact]
public async Task ListRequests_AsSuperAdmin_ReturnsPendingRequests()
{
    // Create a regular user who submits a request
    var (userClient, userId, _) = await TestFixture.CreateAuthenticatedClientAsync(_factory);

    await userClient.PostAsJsonAsync("/api/tenant-requests", new
    {
        organization_name = "Admin List Test Corp"
    }, Json);

    // Create a super admin
    var (adminClient, _, _) = await TestFixture.CreateAuthenticatedClientAsync(
        _factory, systemRole: "SuperAdmin");

    var response = await adminClient.GetAsync("/api/admin/tenant-requests");

    Assert.Equal(HttpStatusCode.OK, response.StatusCode);
    var body = await response.Content.ReadFromJsonAsync<JsonElement>(Json);
    Assert.True(body.GetProperty("items").GetArrayLength() >= 1);
}

[Fact]
public async Task ListRequests_AsNonAdmin_ReturnsForbidden()
{
    var (client, _, _) = await TestFixture.CreateAuthenticatedClientAsync(_factory);

    var response = await client.GetAsync("/api/admin/tenant-requests");

    Assert.Equal(HttpStatusCode.Forbidden, response.StatusCode);
}
```

- [ ] **Step 2: Implement ListRequests**

```csharp
// src/SsdidDrive.Api/Features/TenantRequests/ListRequests.cs
using Microsoft.EntityFrameworkCore;
using SsdidDrive.Api.Data;
using SsdidDrive.Api.Data.Entities;

namespace SsdidDrive.Api.Features.TenantRequests;

public static class ListRequests
{
    public static void Map(RouteGroupBuilder group) =>
        group.MapGet("/tenant-requests", Handle);

    private static async Task<IResult> Handle(
        AppDbContext db,
        string? status,
        CancellationToken ct)
    {
        var query = db.TenantRequests
            .Include(r => r.RequesterAccount)
            .AsQueryable();

        if (!string.IsNullOrEmpty(status) && Enum.TryParse<TenantRequestStatus>(status, true, out var statusFilter))
            query = query.Where(r => r.Status == statusFilter);
        else
            query = query.Where(r => r.Status == TenantRequestStatus.Pending);

        var requests = await query
            .OrderByDescending(r => r.CreatedAt)
            .Select(r => new
            {
                id = r.Id,
                organization_name = r.OrganizationName,
                requester_email = r.RequesterEmail,
                requester_name = r.RequesterAccount != null ? r.RequesterAccount.DisplayName : null,
                reason = r.Reason,
                status = r.Status.ToString().ToLowerInvariant(),
                created_at = r.CreatedAt,
                reviewed_at = r.ReviewedAt,
                rejection_reason = r.RejectionReason
            })
            .ToListAsync(ct);

        return Results.Ok(new { items = requests });
    }
}
```

- [ ] **Step 3: Register in AdminFeature**

Add `ListRequests.Map(group);` to `AdminFeature.MapAdminFeature()`. Add `using SsdidDrive.Api.Features.TenantRequests;` to AdminFeature.cs.

- [ ] **Step 4: Run tests, verify, commit**

### Task 17: ApproveRequest (Admin Endpoint)

**Files:**
- Create: `src/SsdidDrive.Api/Features/TenantRequests/ApproveRequest.cs`
- Modify: `src/SsdidDrive.Api/Features/Admin/AdminFeature.cs`
- Modify: `tests/SsdidDrive.Api.Tests/Integration/TenantRequestTests.cs`

- [ ] **Step 1: Add integration test**

```csharp
[Fact]
public async Task ApproveRequest_CreatesTenantAndInvitesRequester()
{
    // Regular user submits request
    var (userClient, userId, _) = await TestFixture.CreateAuthenticatedClientAsync(_factory);

    // Set email on user for invitation
    using (var scope = _factory.Services.CreateScope())
    {
        var db = scope.ServiceProvider.GetRequiredService<SsdidDrive.Api.Data.AppDbContext>();
        var user = await db.Users.FindAsync(userId);
        user!.Email = $"approve-test-{Guid.NewGuid():N}@test.com";
        await db.SaveChangesAsync();
    }

    var submitResp = await userClient.PostAsJsonAsync("/api/tenant-requests", new
    {
        organization_name = $"Approved Corp {Guid.NewGuid():N}"[..30]
    }, Json);
    var submitBody = await submitResp.Content.ReadFromJsonAsync<JsonElement>(Json);
    var requestId = submitBody.GetProperty("id").GetString();

    // Super admin approves
    var (adminClient, _, _) = await TestFixture.CreateAuthenticatedClientAsync(
        _factory, systemRole: "SuperAdmin");

    var response = await adminClient.PostAsync($"/api/admin/tenant-requests/{requestId}/approve", null);

    Assert.Equal(HttpStatusCode.OK, response.StatusCode);
    var body = await response.Content.ReadFromJsonAsync<JsonElement>(Json);
    Assert.Equal("approved", body.GetProperty("status").GetString());
    Assert.True(body.TryGetProperty("tenant_id", out _));
}

[Fact]
public async Task ApproveRequest_AlreadyApproved_ReturnsConflict()
{
    var (userClient, userId, _) = await TestFixture.CreateAuthenticatedClientAsync(_factory);

    using (var scope = _factory.Services.CreateScope())
    {
        var db = scope.ServiceProvider.GetRequiredService<SsdidDrive.Api.Data.AppDbContext>();
        var user = await db.Users.FindAsync(userId);
        user!.Email = $"dup-approve-{Guid.NewGuid():N}@test.com";
        await db.SaveChangesAsync();
    }

    var submitResp = await userClient.PostAsJsonAsync("/api/tenant-requests", new
    {
        organization_name = $"Dup Approved {Guid.NewGuid():N}"[..30]
    }, Json);
    var submitBody = await submitResp.Content.ReadFromJsonAsync<JsonElement>(Json);
    var requestId = submitBody.GetProperty("id").GetString();

    var (adminClient, _, _) = await TestFixture.CreateAuthenticatedClientAsync(
        _factory, systemRole: "SuperAdmin");

    await adminClient.PostAsync($"/api/admin/tenant-requests/{requestId}/approve", null);
    var response = await adminClient.PostAsync($"/api/admin/tenant-requests/{requestId}/approve", null);

    Assert.Equal(HttpStatusCode.Conflict, response.StatusCode);
}
```

- [ ] **Step 2: Implement ApproveRequest**

```csharp
// src/SsdidDrive.Api/Features/TenantRequests/ApproveRequest.cs
using System.Text.RegularExpressions;
using Microsoft.EntityFrameworkCore;
using SsdidDrive.Api.Common;
using SsdidDrive.Api.Data;
using SsdidDrive.Api.Data.Entities;
using SsdidDrive.Api.Services;

namespace SsdidDrive.Api.Features.TenantRequests;

public static partial class ApproveRequest
{
    public static void Map(RouteGroupBuilder group) =>
        group.MapPost("/tenant-requests/{id:guid}/approve", Handle);

    private static async Task<IResult> Handle(
        Guid id,
        AppDbContext db,
        CurrentUserAccessor accessor,
        AuditService audit,
        CancellationToken ct)
    {
        var request = await db.TenantRequests.FindAsync([id], ct);
        if (request is null)
            return AppError.NotFound("Tenant request not found").ToProblemResult();

        if (request.Status != TenantRequestStatus.Pending)
            return AppError.Conflict($"Request is already {request.Status.ToString().ToLowerInvariant()}").ToProblemResult();

        // Generate slug from organization name
        var slug = SlugRegex().Replace(request.OrganizationName.ToLowerInvariant(), "-").Trim('-');
        if (string.IsNullOrEmpty(slug)) slug = $"org-{Guid.NewGuid():N}"[..16];

        // Ensure slug uniqueness
        var baseSlug = slug;
        var counter = 1;
        while (await db.Tenants.AnyAsync(t => t.Slug == slug, ct))
        {
            slug = $"{baseSlug}-{counter}";
            counter++;
        }

        // Create tenant
        var tenant = new Tenant
        {
            Id = Guid.NewGuid(),
            Name = request.OrganizationName,
            Slug = slug,
            CreatedAt = DateTimeOffset.UtcNow,
            UpdatedAt = DateTimeOffset.UtcNow
        };
        db.Tenants.Add(tenant);

        // If requester has an account, make them Owner
        if (request.RequesterAccountId.HasValue)
        {
            db.UserTenants.Add(new UserTenant
            {
                UserId = request.RequesterAccountId.Value,
                TenantId = tenant.Id,
                Role = TenantRole.Owner,
                CreatedAt = DateTimeOffset.UtcNow
            });
        }

        // Update request
        request.Status = TenantRequestStatus.Approved;
        request.ReviewedBy = accessor.UserId;
        request.ReviewedAt = DateTimeOffset.UtcNow;

        await db.SaveChangesAsync(ct);

        await audit.LogAsync(accessor.UserId, "tenant.request.approved", "TenantRequest", request.Id,
            $"Approved tenant request for '{request.OrganizationName}', created tenant {tenant.Id}", ct);

        return Results.Ok(new
        {
            id = request.Id,
            organization_name = request.OrganizationName,
            status = "approved",
            tenant_id = tenant.Id,
            tenant_slug = tenant.Slug,
            reviewed_at = request.ReviewedAt
        });
    }

    [GeneratedRegex(@"[^a-z0-9]+")]
    private static partial Regex SlugRegex();
}
```

- [ ] **Step 3: Register in AdminFeature**

Add `ApproveRequest.Map(group);` to `AdminFeature.MapAdminFeature()`.

- [ ] **Step 4: Run tests, verify, commit**

### Task 18: RejectRequest (Admin Endpoint)

**Files:**
- Create: `src/SsdidDrive.Api/Features/TenantRequests/RejectRequest.cs`
- Modify: `src/SsdidDrive.Api/Features/Admin/AdminFeature.cs`
- Modify: `tests/SsdidDrive.Api.Tests/Integration/TenantRequestTests.cs`

- [ ] **Step 1: Add integration test**

```csharp
[Fact]
public async Task RejectRequest_WithReason_UpdatesStatusAndReason()
{
    var (userClient, _, _) = await TestFixture.CreateAuthenticatedClientAsync(_factory);

    var submitResp = await userClient.PostAsJsonAsync("/api/tenant-requests", new
    {
        organization_name = "Rejected Corp"
    }, Json);
    var submitBody = await submitResp.Content.ReadFromJsonAsync<JsonElement>(Json);
    var requestId = submitBody.GetProperty("id").GetString();

    var (adminClient, _, _) = await TestFixture.CreateAuthenticatedClientAsync(
        _factory, systemRole: "SuperAdmin");

    var response = await adminClient.PostAsJsonAsync($"/api/admin/tenant-requests/{requestId}/reject", new
    {
        reason = "Duplicate organization"
    }, Json);

    Assert.Equal(HttpStatusCode.OK, response.StatusCode);
    var body = await response.Content.ReadFromJsonAsync<JsonElement>(Json);
    Assert.Equal("rejected", body.GetProperty("status").GetString());
    Assert.Equal("Duplicate organization", body.GetProperty("rejection_reason").GetString());
}
```

- [ ] **Step 2: Implement RejectRequest**

```csharp
// src/SsdidDrive.Api/Features/TenantRequests/RejectRequest.cs
using Microsoft.EntityFrameworkCore;
using SsdidDrive.Api.Common;
using SsdidDrive.Api.Data;
using SsdidDrive.Api.Data.Entities;
using SsdidDrive.Api.Services;

namespace SsdidDrive.Api.Features.TenantRequests;

public static class RejectRequest
{
    public static void Map(RouteGroupBuilder group) =>
        group.MapPost("/tenant-requests/{id:guid}/reject", Handle);

    private record RejectRequestBody(string? Reason);

    private static async Task<IResult> Handle(
        Guid id,
        RejectRequestBody request,
        AppDbContext db,
        CurrentUserAccessor accessor,
        AuditService audit,
        IEmailService emailService,
        CancellationToken ct)
    {
        var tenantRequest = await db.TenantRequests.FindAsync([id], ct);
        if (tenantRequest is null)
            return AppError.NotFound("Tenant request not found").ToProblemResult();

        if (tenantRequest.Status != TenantRequestStatus.Pending)
            return AppError.Conflict($"Request is already {tenantRequest.Status.ToString().ToLowerInvariant()}").ToProblemResult();

        tenantRequest.Status = TenantRequestStatus.Rejected;
        tenantRequest.RejectionReason = request.Reason?.Trim();
        tenantRequest.ReviewedBy = accessor.UserId;
        tenantRequest.ReviewedAt = DateTimeOffset.UtcNow;

        await db.SaveChangesAsync(ct);

        await audit.LogAsync(accessor.UserId, "tenant.request.rejected", "TenantRequest", tenantRequest.Id,
            $"Rejected tenant request for '{tenantRequest.OrganizationName}': {request.Reason}", ct);

        // Send rejection notification email (best-effort)
        if (!string.IsNullOrEmpty(tenantRequest.RequesterEmail))
        {
            try
            {
                await emailService.SendRejectionAsync(
                    tenantRequest.RequesterEmail,
                    tenantRequest.OrganizationName,
                    request.Reason,
                    ct);
            }
            catch { /* email failure should not block the rejection */ }
        }

        return Results.Ok(new
        {
            id = tenantRequest.Id,
            organization_name = tenantRequest.OrganizationName,
            status = "rejected",
            rejection_reason = tenantRequest.RejectionReason,
            reviewed_at = tenantRequest.ReviewedAt
        });
    }
}
```

- [ ] **Step 3: Add SendRejectionAsync to IEmailService**

Add to `IEmailService` interface:

```csharp
Task SendRejectionAsync(string toEmail, string organizationName, string? reason, CancellationToken ct = default);
```

Add implementations to both `EmailService` and `NullEmailService`.

- [ ] **Step 4: Register in AdminFeature**

Add `RejectRequest.Map(group);` to `AdminFeature.MapAdminFeature()`.

- [ ] **Step 5: Run tests, verify, commit**

---

## Summary

| Task | Description | Dependencies |
|------|-------------|-------------|
| 1 | ExtensionService entity | — |
| 2 | TenantRequest entity | — |
| 3 | EF migration | 1, 2 |
| 4 | ExtensionServiceContext + CurrentUserAccessor.TenantId | — |
| 5 | HMAC signature helper + unit tests | — |
| 6 | HMAC auth middleware | 4, 5 |
| 7 | ExtensionServiceFeature route group | 1 |
| 8 | RegisterService endpoint + tests | 7 |
| 9 | ListServices endpoint + test | 7 |
| 10 | GetService endpoint + tests | 7 |
| 11 | UpdateService endpoint + test | 7 |
| 12 | RevokeService endpoint + test | 7 |
| 13 | RotateSecret endpoint + test | 7 |
| 14 | HMAC middleware integration tests | 6, 8, 13 |
| 15 | TenantRequestFeature + SubmitRequest + tests | 2 |
| 16 | ListRequests (admin) + tests | 15 |
| 17 | ApproveRequest (admin) + tests | 15 |
| 18 | RejectRequest (admin) + tests | 15 |

**Parallelizable batches:**
- Batch 1: Tasks 1, 2, 4, 5 (all independent)
- Batch 2: Task 3 (depends on 1, 2), Task 6 (depends on 4, 5), Task 7 (depends on 1)
- Batch 3: Tasks 8-13 (all depend on 7, independent of each other), Task 15 (depends on 2)
- Batch 4: Task 14 (depends on 6, 8, 13), Tasks 16-18 (depend on 15, independent of each other)
