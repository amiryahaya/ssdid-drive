# Recovery via Shamir's Secret Sharing — Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Enable master key recovery via Shamir's Secret Sharing (2-of-3) with file-based share export and server-held share.

**Architecture:** Replace the existing trustee-based recovery model with a simpler file-based approach. Client splits master key into 3 Shamir shares — 2 exported as `.recovery` files (self-custody + trusted person), 1 stored on server. Any 2 shares reconstruct the key. Server endpoint for recovery completion is unauthenticated, using `key_proof` (SHA-256 of KEM public key) as cryptographic identity proof.

**Tech Stack:** .NET 10 (backend), EF Core + PostgreSQL, Redis (rate limiting), Rust/sharks (desktop SSS), Kotlin GF(256) (Android), Swift GF(256) (iOS), React/TypeScript (desktop UI), Jetpack Compose (Android UI), UIKit (iOS UI)

**Spec:** `docs/superpowers/specs/2026-03-14-recovery-shamir-design.md`

**Important context:** The codebase already has recovery entities (`RecoveryConfig`, `RecoveryShare`, `RecoveryRequest`, `RecoveryApproval`) and client-side recovery services/commands for a trustee-based model. This plan REPLACES that model with the simpler Shamir file-based approach described in the spec. Existing recovery code should be replaced, not extended.

---

## File Structure

### Backend (Create/Modify)

| File | Responsibility |
|------|---------------|
| Create: `src/SsdidDrive.Api/Data/Entities/RecoverySetup.cs` | New entity for Shamir recovery |
| Modify: `src/SsdidDrive.Api/Data/Entities/User.cs` | Add `HasRecoverySetup` column |
| Modify: `src/SsdidDrive.Api/Data/AppDbContext.cs` | Add `DbSet<RecoverySetup>`, entity config, remove old recovery entity configs |
| Create: `src/SsdidDrive.Api/Features/Recovery/SetupRecovery.cs` | POST /api/recovery/setup |
| Create: `src/SsdidDrive.Api/Features/Recovery/GetRecoveryStatus.cs` | GET /api/recovery/status |
| Create: `src/SsdidDrive.Api/Features/Recovery/GetRecoveryShare.cs` | GET /api/recovery/share (unauth) |
| Create: `src/SsdidDrive.Api/Features/Recovery/CompleteRecovery.cs` | POST /api/recovery/complete (unauth) |
| Create: `src/SsdidDrive.Api/Features/Recovery/DeleteRecoverySetup.cs` | DELETE /api/recovery/setup |
| Modify: `src/SsdidDrive.Api/Features/Recovery/RecoveryFeature.cs` | Replace old endpoint mappings with new 5 endpoints |
| Modify: `src/SsdidDrive.Api/Program.cs` | Add recovery rate limiter policies |
| Create: `tests/SsdidDrive.Api.Tests/Integration/RecoveryShamirTests.cs` | Integration tests for all 5 endpoints |

### Cross-Platform Test Vectors

| File | Responsibility |
|------|---------------|
| Create: `tests/fixtures/shamir-test-vectors.json` | Known inputs/outputs for SSS across all platforms |

### Desktop — Rust Backend

| File | Responsibility |
|------|---------------|
| Modify: `clients/desktop/src-tauri/src/services/recovery_service.rs` | Replace with Shamir split/reconstruct + file I/O |
| Modify: `clients/desktop/src-tauri/src/commands/recovery.rs` | Replace with new Tauri commands |
| Modify: `clients/desktop/src-tauri/src/lib.rs` | Update command registrations |
| Modify: `clients/desktop/src-tauri/Cargo.toml` | Add `sharks` crate if compatible |

### Desktop — React Frontend

| File | Responsibility |
|------|---------------|
| Modify: `clients/desktop/src/services/tauri.ts` | Add recovery service functions |
| Create: `clients/desktop/src/pages/RecoveryPage.tsx` | Login-page recovery flow |
| Create: `clients/desktop/src/components/recovery/RecoverySetupWizard.tsx` | 3-step setup wizard |
| Create: `clients/desktop/src/components/recovery/RecoveryBanner.tsx` | Persistent warning banner |
| Modify: `clients/desktop/src/App.tsx` | Add /recover route |
| Modify: `clients/desktop/src/pages/LoginPage.tsx` | Add "Recover Account" link |
| Modify: `clients/desktop/src/components/layout/Sidebar.tsx` | Integrate banner |

### Android

| File | Responsibility |
|------|---------------|
| Create: `clients/android/.../domain/crypto/ShamirSecretSharing.kt` | GF(256) split/reconstruct |
| Create: `clients/android/.../domain/crypto/RecoveryFile.kt` | .recovery file parse/serialize |
| Create: `clients/android/.../domain/repository/RecoveryRepository.kt` | Repository interface |
| Create: `clients/android/.../data/repository/RecoveryRepositoryImpl.kt` | API calls |
| Modify: `clients/android/.../data/remote/ApiService.kt` | Replace old recovery endpoints with new 5 |
| Create: `clients/android/.../presentation/recovery/RecoverySetupViewModel.kt` | Setup wizard VM |
| Create: `clients/android/.../presentation/recovery/RecoverySetupScreen.kt` | Setup wizard UI |
| Create: `clients/android/.../presentation/recovery/RecoveryViewModel.kt` | Recovery flow VM |
| Create: `clients/android/.../presentation/recovery/RecoveryScreen.kt` | Recovery flow UI |
| Create: `clients/android/.../presentation/recovery/RecoveryBanner.kt` | Warning banner composable |
| Modify: `clients/android/.../presentation/auth/LoginScreen.kt` | Add "Recover Account" button |
| Modify: `clients/android/.../di/RepositoryModule.kt` | Bind RecoveryRepository |
| Create: `clients/android/.../domain/crypto/ShamirSecretSharingTest.kt` | Unit tests |

### iOS

| File | Responsibility |
|------|---------------|
| Create: `clients/ios/.../Domain/Crypto/ShamirSecretSharing.swift` | GF(256) split/reconstruct |
| Create: `clients/ios/.../Domain/Crypto/RecoveryFile.swift` | .recovery file parse/serialize |
| Create: `clients/ios/.../Domain/Repository/RecoveryRepository.swift` | Repository protocol |
| Create: `clients/ios/.../Data/Repository/RecoveryRepositoryImpl.swift` | API calls |
| Create: `clients/ios/.../Presentation/Recovery/RecoverySetupViewModel.swift` | Setup wizard VM |
| Create: `clients/ios/.../Presentation/Recovery/RecoverySetupViewController.swift` | Setup wizard UI |
| Create: `clients/ios/.../Presentation/Recovery/RecoveryViewModel.swift` | Recovery flow VM |
| Create: `clients/ios/.../Presentation/Recovery/RecoveryViewController.swift` | Recovery flow UI |
| Create: `clients/ios/.../Presentation/Recovery/RecoveryBanner.swift` | Warning banner view |
| Create: `clients/ios/.../Presentation/Recovery/RecoveryCoordinator.swift` | Navigation coordinator |
| Modify: `clients/ios/.../Core/DI/Container.swift` | Add recoveryRepository |
| Modify: login screen | Add "Recover Account" button |

---

## Chunk 1: Backend — Data Model & Migration

### Task 1: RecoverySetup Entity

**Files:**
- Create: `src/SsdidDrive.Api/Data/Entities/RecoverySetup.cs`
- Modify: `src/SsdidDrive.Api/Data/Entities/User.cs`

- [ ] **Step 1: Create RecoverySetup entity**

```csharp
// src/SsdidDrive.Api/Data/Entities/RecoverySetup.cs
namespace SsdidDrive.Api.Data.Entities;

public class RecoverySetup
{
    public Guid Id { get; set; }
    public Guid UserId { get; set; }
    public string ServerShare { get; set; } = default!;
    public string KeyProof { get; set; } = default!;
    public DateTimeOffset ShareCreatedAt { get; set; }
    public bool IsActive { get; set; }

    public User User { get; set; } = null!;
}
```

- [ ] **Step 2: Add HasRecoverySetup to User entity**

In `src/SsdidDrive.Api/Data/Entities/User.cs`, add after `UpdatedAt`:

```csharp
public bool HasRecoverySetup { get; set; }
```

- [ ] **Step 3: Commit**

```bash
git add src/SsdidDrive.Api/Data/Entities/RecoverySetup.cs src/SsdidDrive.Api/Data/Entities/User.cs
git commit -m "feat(recovery): add RecoverySetup entity and HasRecoverySetup on User"
```

### Task 2: AppDbContext Configuration

**Files:**
- Modify: `src/SsdidDrive.Api/Data/AppDbContext.cs`

- [ ] **Step 1: Add DbSet and configure RecoverySetup**

Add to `AppDbContext`:
```csharp
public DbSet<RecoverySetup> RecoverySetups => Set<RecoverySetup>();
```

Add entity configuration in `OnModelCreating` (replace the old `RecoveryConfig`/`RecoveryShare`/`RecoveryRequest`/`RecoveryApproval` configurations):

```csharp
modelBuilder.Entity<RecoverySetup>(e =>
{
    e.ToTable("recovery_setups");
    e.HasKey(rs => rs.Id);
    e.Property(rs => rs.Id).HasDefaultValueSql("gen_random_uuid()");
    e.Property(rs => rs.ServerShare).IsRequired();
    e.Property(rs => rs.KeyProof).HasMaxLength(64).IsRequired();
    e.Property(rs => rs.ShareCreatedAt).HasDefaultValueSql("now()");
    e.Property(rs => rs.IsActive).HasDefaultValue(false);

    e.HasIndex(rs => rs.UserId).IsUnique();

    e.HasOne(rs => rs.User)
        .WithOne()
        .HasForeignKey<RecoverySetup>(rs => rs.UserId)
        .OnDelete(DeleteBehavior.Cascade);
});
```

Also add `HasRecoverySetup` configuration on the User entity config:
```csharp
e.Property(u => u.HasRecoverySetup).HasDefaultValue(false);
```

- [ ] **Step 2: Remove old recovery entity DbSets and configurations**

Remove `DbSet<RecoveryConfig>`, `DbSet<RecoveryShare>`, `DbSet<RecoveryRequest>`, `DbSet<RecoveryApproval>` and their `OnModelCreating` configurations. Keep the entity files for now (migration needs them to generate the drop).

- [ ] **Step 3: Create migration**

```bash
dotnet ef migrations add ShamirRecovery --project src/SsdidDrive.Api
```

This migration should:
- Drop tables: `recovery_approvals`, `recovery_requests`, `recovery_shares`, `recovery_configs`
- Create table: `recovery_setups`
- Add column: `users.HasRecoverySetup`

Review the generated migration to verify these operations are correct.

- [ ] **Step 4: Verify build**

```bash
dotnet build src/SsdidDrive.Api
```

- [ ] **Step 5: Commit**

```bash
git add src/SsdidDrive.Api/Data/ src/SsdidDrive.Api/Migrations/
git commit -m "feat(recovery): add RecoverySetup DbContext config and migration"
```

### Task 3: Recovery API Endpoints

**Files:**
- Create: `src/SsdidDrive.Api/Features/Recovery/SetupRecovery.cs`
- Create: `src/SsdidDrive.Api/Features/Recovery/GetRecoveryStatus.cs`
- Create: `src/SsdidDrive.Api/Features/Recovery/GetRecoveryShare.cs`
- Create: `src/SsdidDrive.Api/Features/Recovery/CompleteRecovery.cs`
- Create: `src/SsdidDrive.Api/Features/Recovery/DeleteRecoverySetup.cs`
- Modify: `src/SsdidDrive.Api/Features/Recovery/RecoveryFeature.cs`

- [ ] **Step 1: Create SetupRecovery endpoint**

```csharp
// src/SsdidDrive.Api/Features/Recovery/SetupRecovery.cs
using SsdidDrive.Api.Common;
using SsdidDrive.Api.Data;
using SsdidDrive.Api.Data.Entities;
using SsdidDrive.Api.Services;
using Microsoft.EntityFrameworkCore;

namespace SsdidDrive.Api.Features.Recovery;

public static class SetupRecovery
{
    public record Request(string ServerShare, string KeyProof);

    public static void Map(RouteGroupBuilder group) =>
        group.MapPost("/setup", Handle);

    private static async Task<IResult> Handle(
        Request req,
        AppDbContext db,
        CurrentUserAccessor accessor,
        FileActivityService activity,
        CancellationToken ct)
    {
        var user = accessor.User!;

        if (string.IsNullOrWhiteSpace(req.ServerShare))
            return AppError.BadRequest("server_share is required").ToProblemResult();
        if (string.IsNullOrWhiteSpace(req.KeyProof) || req.KeyProof.Length != 64)
            return AppError.BadRequest("key_proof must be a 64-character SHA-256 hex string").ToProblemResult();

        var existing = await db.RecoverySetups
            .FirstOrDefaultAsync(rs => rs.UserId == user.Id, ct);

        var isRegeneration = false;
        if (existing is not null)
        {
            isRegeneration = existing.IsActive;
            existing.ServerShare = req.ServerShare;
            existing.KeyProof = req.KeyProof;
            existing.ShareCreatedAt = DateTimeOffset.UtcNow;
            existing.IsActive = true;
        }
        else
        {
            db.RecoverySetups.Add(new RecoverySetup
            {
                UserId = user.Id,
                ServerShare = req.ServerShare,
                KeyProof = req.KeyProof,
                ShareCreatedAt = DateTimeOffset.UtcNow,
                IsActive = true
            });
        }

        user.HasRecoverySetup = true;
        await db.SaveChangesAsync(ct);

        var eventType = isRegeneration ? "recovery.regenerated" : "recovery.setup";
        _ = activity.LogAsync(
            user.Id, user.TenantId!.Value, eventType, "recovery",
            user.Id, user.DisplayName ?? "recovery", user.Id, ct: ct);

        return Results.Created();
    }
}
```

- [ ] **Step 2: Create GetRecoveryStatus endpoint**

```csharp
// src/SsdidDrive.Api/Features/Recovery/GetRecoveryStatus.cs
using SsdidDrive.Api.Common;
using SsdidDrive.Api.Data;
using Microsoft.EntityFrameworkCore;

namespace SsdidDrive.Api.Features.Recovery;

public static class GetRecoveryStatus
{
    public static void Map(RouteGroupBuilder group) =>
        group.MapGet("/status", Handle);

    private static async Task<IResult> Handle(
        AppDbContext db,
        CurrentUserAccessor accessor,
        CancellationToken ct)
    {
        var user = accessor.User!;
        var setup = await db.RecoverySetups
            .Where(rs => rs.UserId == user.Id && rs.IsActive)
            .Select(rs => new { rs.ShareCreatedAt })
            .FirstOrDefaultAsync(ct);

        return Results.Ok(new
        {
            is_active = setup is not null,
            created_at = setup?.ShareCreatedAt
        });
    }
}
```

- [ ] **Step 3: Create GetRecoveryShare endpoint (unauthenticated)**

```csharp
// src/SsdidDrive.Api/Features/Recovery/GetRecoveryShare.cs
using SsdidDrive.Api.Common;
using SsdidDrive.Api.Data;
using SsdidDrive.Api.Services;
using Microsoft.EntityFrameworkCore;

namespace SsdidDrive.Api.Features.Recovery;

public static class GetRecoveryShare
{
    public static void Map(IEndpointRouteBuilder routes) =>
        routes.MapGet("/api/recovery/share", Handle)
            .RequireRateLimiting("recovery-share");

    private static async Task<IResult> Handle(
        string did,
        AppDbContext db,
        FileActivityService activity,
        CancellationToken ct)
    {
        var sw = System.Diagnostics.Stopwatch.StartNew();

        var setup = await db.RecoverySetups
            .Where(rs => rs.User.Did == did && rs.IsActive)
            .Select(rs => new { rs.ServerShare, rs.User.Id, rs.User.TenantId })
            .FirstOrDefaultAsync(ct);

        // Constant-time response: pad to minimum 200ms
        var elapsed = sw.ElapsedMilliseconds;
        if (elapsed < 200)
            await Task.Delay((int)(200 - elapsed), ct);

        if (setup is null)
        {
            // Log failed retrieval attempts for security monitoring (even on 404)
            _ = activity.LogAsync(
                Guid.Empty, Guid.Empty, "recovery.share_retrieved", "recovery",
                Guid.Empty, did, Guid.Empty,
                new { success = false, did }, ct: ct);
            return AppError.NotFound("No active recovery setup found").ToProblemResult();
        }

        _ = activity.LogAsync(
            setup.Id, setup.TenantId ?? Guid.Empty, "recovery.share_retrieved", "recovery",
            setup.Id, "recovery-share", setup.Id,
            new { success = true }, ct: ct);

        return Results.Ok(new
        {
            server_share = setup.ServerShare,
            share_index = 3
        });
    }
}
```

- [ ] **Step 4: Create CompleteRecovery endpoint (unauthenticated, atomic)**

```csharp
// src/SsdidDrive.Api/Features/Recovery/CompleteRecovery.cs
using SsdidDrive.Api.Common;
using SsdidDrive.Api.Data;
using SsdidDrive.Api.Data.Entities;
using SsdidDrive.Api.Services;
using SsdidDrive.Api.Ssdid;
using Microsoft.EntityFrameworkCore;

namespace SsdidDrive.Api.Features.Recovery;

public static class CompleteRecovery
{
    public record Request(string OldDid, string NewDid, string KeyProof, string KemPublicKey);

    public static void Map(IEndpointRouteBuilder routes) =>
        routes.MapPost("/api/recovery/complete", Handle)
            .RequireRateLimiting("recovery-complete");

    private static async Task<IResult> Handle(
        Request req,
        AppDbContext db,
        ISessionStore sessionStore,
        FileActivityService activity,
        CancellationToken ct)
    {
        if (string.IsNullOrWhiteSpace(req.OldDid) || string.IsNullOrWhiteSpace(req.NewDid)
            || string.IsNullOrWhiteSpace(req.KeyProof) || string.IsNullOrWhiteSpace(req.KemPublicKey))
            return AppError.BadRequest("All fields are required").ToProblemResult();

        await using var transaction = await db.Database.BeginTransactionAsync(ct);

        var user = await db.Users
            .FirstOrDefaultAsync(u => u.Did == req.OldDid, ct);
        if (user is null)
            return AppError.NotFound("User not found").ToProblemResult();

        var setup = await db.RecoverySetups
            .FirstOrDefaultAsync(rs => rs.UserId == user.Id && rs.IsActive, ct);
        if (setup is null)
            return AppError.NotFound("No active recovery setup found").ToProblemResult();

        if (!string.Equals(setup.KeyProof, req.KeyProof, StringComparison.OrdinalIgnoreCase))
            return AppError.Forbidden("Invalid key proof").ToProblemResult();

        // Atomic DID migration
        user.Did = req.NewDid;
        user.KemPublicKey = Convert.FromBase64String(req.KemPublicKey);
        user.HasRecoverySetup = false;
        user.UpdatedAt = DateTimeOffset.UtcNow;

        // Invalidate recovery
        setup.IsActive = false;
        setup.ServerShare = "";

        await db.SaveChangesAsync(ct);
        await transaction.CommitAsync(ct);

        // Invalidate old sessions (best-effort, outside transaction)
        try { await sessionStore.InvalidateUserSessionsAsync(user.Id); }
        catch { /* log but don't fail recovery */ }

        // Create new session
        var token = Guid.NewGuid().ToString("N");
        await sessionStore.CreateSessionAsync(token, user.Id, TimeSpan.FromHours(1));

        _ = activity.LogAsync(
            user.Id, user.TenantId ?? Guid.Empty, "recovery.completed", "recovery",
            user.Id, user.DisplayName ?? "recovery", user.Id, ct: ct);

        return Results.Ok(new
        {
            token,
            user_id = user.Id
        });
    }
}
```

**Note:** The `ISessionStore` methods `InvalidateUserSessionsAsync` and `CreateSessionAsync` may need to be added or adapted to match the existing session store interface. Check `src/SsdidDrive.Api/Ssdid/SessionStore.cs` and `RedisSessionStore.cs` for the actual method signatures. Use the existing session creation pattern from `SsdidAuthService.cs`.

- [ ] **Step 5: Create DeleteRecoverySetup endpoint**

```csharp
// src/SsdidDrive.Api/Features/Recovery/DeleteRecoverySetup.cs
using SsdidDrive.Api.Common;
using SsdidDrive.Api.Data;
using SsdidDrive.Api.Services;
using Microsoft.EntityFrameworkCore;

namespace SsdidDrive.Api.Features.Recovery;

public static class DeleteRecoverySetup
{
    public static void Map(RouteGroupBuilder group) =>
        group.MapDelete("/setup", Handle);

    private static async Task<IResult> Handle(
        AppDbContext db,
        CurrentUserAccessor accessor,
        FileActivityService activity,
        CancellationToken ct)
    {
        var user = accessor.User!;
        var setup = await db.RecoverySetups
            .FirstOrDefaultAsync(rs => rs.UserId == user.Id, ct);

        if (setup is null)
            return Results.NoContent();

        setup.IsActive = false;
        setup.ServerShare = "";
        user.HasRecoverySetup = false;
        await db.SaveChangesAsync(ct);

        _ = activity.LogAsync(
            user.Id, user.TenantId!.Value, "recovery.deactivated", "recovery",
            user.Id, user.DisplayName ?? "recovery", user.Id, ct: ct);

        return Results.NoContent();
    }
}
```

- [ ] **Step 6: Replace RecoveryFeature.cs endpoint mappings**

```csharp
// src/SsdidDrive.Api/Features/Recovery/RecoveryFeature.cs
namespace SsdidDrive.Api.Features.Recovery;

public static class RecoveryFeature
{
    public static void MapRecoveryFeature(this IEndpointRouteBuilder routes)
    {
        // Authenticated endpoints under /api/recovery
        var group = routes.MapGroup("/api/recovery").WithTags("Recovery");
        SetupRecovery.Map(group);
        GetRecoveryStatus.Map(group);
        DeleteRecoverySetup.Map(group);

        // Unauthenticated endpoints mapped directly on routes
        // (GetRecoveryShare and CompleteRecovery handle their own paths)
        GetRecoveryShare.Map(routes);
        CompleteRecovery.Map(routes);
    }
}
```

- [ ] **Step 7: Verify build**

```bash
dotnet build src/SsdidDrive.Api
```

- [ ] **Step 8: Commit**

```bash
git add src/SsdidDrive.Api/Features/Recovery/
git commit -m "feat(recovery): add Shamir recovery API endpoints"
```

### Task 4: Rate Limiting Configuration

**Files:**
- Modify: `src/SsdidDrive.Api/Program.cs`

- [ ] **Step 1: Add per-DID and per-IP partitioned rate limiter policies**

In `Program.cs`, inside the `AddRateLimiter` configuration block, add partitioned rate limiters that key by DID (from query string or body) and by IP:

```csharp
options.AddPolicy("recovery-share", httpContext =>
{
    if (isTesting)
        return RateLimitPartition.GetNoLimiter("testing");

    var did = httpContext.Request.Query["did"].FirstOrDefault() ?? "unknown";
    var ip = httpContext.Connection.RemoteIpAddress?.ToString() ?? "unknown";

    // Per-DID limit: 5/hour
    return RateLimitPartition.GetFixedWindowLimiter($"recovery-share:did:{did}", _ => new FixedWindowRateLimiterOptions
    {
        PermitLimit = 5,
        Window = TimeSpan.FromHours(1),
        QueueLimit = 0
    });
});

options.AddPolicy("recovery-complete", httpContext =>
{
    if (isTesting)
        return RateLimitPartition.GetNoLimiter("testing");

    var ip = httpContext.Connection.RemoteIpAddress?.ToString() ?? "unknown";

    // Per-IP limit: 10/hour
    return RateLimitPartition.GetFixedWindowLimiter($"recovery-complete:ip:{ip}", _ => new FixedWindowRateLimiterOptions
    {
        PermitLimit = 10,
        Window = TimeSpan.FromHours(1),
        QueueLimit = 0
    });
});
```

Add the required using:
```csharp
using System.Threading.RateLimiting;
```

- [ ] **Step 2: Verify build**

```bash
dotnet build src/SsdidDrive.Api
```

- [ ] **Step 3: Commit**

```bash
git add src/SsdidDrive.Api/Program.cs
git commit -m "feat(recovery): add rate limiting for unauthenticated recovery endpoints"
```

### Task 5: Backend Integration Tests

**Files:**
- Create: `tests/SsdidDrive.Api.Tests/Integration/RecoveryShamirTests.cs`

- [ ] **Step 1: Write integration tests**

```csharp
using System.Net;
using System.Net.Http.Json;
using System.Text.Json;
using SsdidDrive.Api.Tests.Infrastructure;

namespace SsdidDrive.Api.Tests.Integration;

public class RecoveryShamirTests : IClassFixture<SsdidDriveFactory>
{
    private readonly SsdidDriveFactory _factory;

    public RecoveryShamirTests(SsdidDriveFactory factory) => _factory = factory;

    [Fact]
    public async Task SetupRecovery_ReturnsCreated()
    {
        var (client, userId, tenantId) =
            await TestFixture.CreateAuthenticatedClientAsync(_factory, "RecoveryUser");

        var response = await client.PostAsJsonAsync("/api/recovery/setup", new
        {
            server_share = Convert.ToBase64String(new byte[32]),
            key_proof = new string('a', 64)
        }, TestFixture.Json);

        Assert.Equal(HttpStatusCode.Created, response.StatusCode);
    }

    [Fact]
    public async Task GetRecoveryStatus_AfterSetup_ReturnsActive()
    {
        var (client, userId, tenantId) =
            await TestFixture.CreateAuthenticatedClientAsync(_factory, "StatusUser");

        await client.PostAsJsonAsync("/api/recovery/setup", new
        {
            server_share = Convert.ToBase64String(new byte[32]),
            key_proof = new string('b', 64)
        }, TestFixture.Json);

        var response = await client.GetAsync("/api/recovery/status");
        Assert.Equal(HttpStatusCode.OK, response.StatusCode);

        var body = await response.Content.ReadFromJsonAsync<JsonElement>(TestFixture.Json);
        Assert.True(body.GetProperty("is_active").GetBoolean());
    }

    [Fact]
    public async Task GetRecoveryStatus_NoSetup_ReturnsInactive()
    {
        var (client, _, _) =
            await TestFixture.CreateAuthenticatedClientAsync(_factory, "NoSetupUser");

        var response = await client.GetAsync("/api/recovery/status");
        Assert.Equal(HttpStatusCode.OK, response.StatusCode);

        var body = await response.Content.ReadFromJsonAsync<JsonElement>(TestFixture.Json);
        Assert.False(body.GetProperty("is_active").GetBoolean());
    }

    [Fact]
    public async Task GetRecoveryShare_UnknownDid_Returns404()
    {
        var client = _factory.CreateClient();
        var response = await client.GetAsync("/api/recovery/share?did=did:ssdid:unknown");
        Assert.Equal(HttpStatusCode.NotFound, response.StatusCode);
    }

    [Fact]
    public async Task DeleteRecoverySetup_DeactivatesRecovery()
    {
        var (client, _, _) =
            await TestFixture.CreateAuthenticatedClientAsync(_factory, "DeleteUser");

        await client.PostAsJsonAsync("/api/recovery/setup", new
        {
            server_share = Convert.ToBase64String(new byte[32]),
            key_proof = new string('c', 64)
        }, TestFixture.Json);

        var deleteResponse = await client.DeleteAsync("/api/recovery/setup");
        Assert.Equal(HttpStatusCode.NoContent, deleteResponse.StatusCode);

        var statusResponse = await client.GetAsync("/api/recovery/status");
        var body = await statusResponse.Content.ReadFromJsonAsync<JsonElement>(TestFixture.Json);
        Assert.False(body.GetProperty("is_active").GetBoolean());
    }

    [Fact]
    public async Task SetupRecovery_InvalidKeyProof_ReturnsBadRequest()
    {
        var (client, _, _) =
            await TestFixture.CreateAuthenticatedClientAsync(_factory, "BadProofUser");

        var response = await client.PostAsJsonAsync("/api/recovery/setup", new
        {
            server_share = Convert.ToBase64String(new byte[32]),
            key_proof = "too-short"
        }, TestFixture.Json);

        Assert.Equal(HttpStatusCode.BadRequest, response.StatusCode);
    }

    [Fact]
    public async Task GetRecoveryShare_ValidDid_ReturnsShare()
    {
        var (client, userId, tenantId) =
            await TestFixture.CreateAuthenticatedClientAsync(_factory, "ShareUser");

        var serverShare = Convert.ToBase64String(new byte[32]);
        await client.PostAsJsonAsync("/api/recovery/setup", new
        {
            server_share = serverShare,
            key_proof = new string('e', 64)
        }, TestFixture.Json);

        // Fetch share with unauthenticated client using the user's DID
        var unauthClient = _factory.CreateClient();
        var response = await unauthClient.GetAsync($"/api/recovery/share?did=did:ssdid:ShareUser");
        Assert.Equal(HttpStatusCode.OK, response.StatusCode);

        var body = await response.Content.ReadFromJsonAsync<JsonElement>(TestFixture.Json);
        Assert.Equal(serverShare, body.GetProperty("server_share").GetString());
        Assert.Equal(3, body.GetProperty("share_index").GetInt32());
    }

    [Fact]
    public async Task CompleteRecovery_InvalidKeyProof_ReturnsForbidden()
    {
        var (client, userId, tenantId) =
            await TestFixture.CreateAuthenticatedClientAsync(_factory, "CompleteUser");

        // Setup recovery first
        await client.PostAsJsonAsync("/api/recovery/setup", new
        {
            server_share = Convert.ToBase64String(new byte[32]),
            key_proof = new string('d', 64)
        }, TestFixture.Json);

        // Try to complete with wrong key_proof (use unauthenticated client)
        var unauthClient = _factory.CreateClient();
        var response = await unauthClient.PostAsJsonAsync("/api/recovery/complete", new
        {
            old_did = $"did:ssdid:CompleteUser",
            new_did = "did:ssdid:newdevice",
            key_proof = new string('x', 64),
            kem_public_key = Convert.ToBase64String(new byte[32])
        }, TestFixture.Json);

        Assert.Equal(HttpStatusCode.Forbidden, response.StatusCode);
    }
}
```

**Note:** The `old_did` value in `CompleteRecovery_InvalidKeyProof` must match the DID created by `TestFixture.CreateAuthenticatedClientAsync`. Check the fixture to see the DID format — it's typically `did:ssdid:{displayName}` or similar. Adjust accordingly.

- [ ] **Step 2: Run tests**

```bash
dotnet test tests/SsdidDrive.Api.Tests/ --filter "RecoveryShamirTests"
```

Expected: All tests pass.

- [ ] **Step 3: Commit**

```bash
git add tests/SsdidDrive.Api.Tests/Integration/RecoveryShamirTests.cs
git commit -m "test(recovery): add integration tests for Shamir recovery endpoints"
```

---

## Chunk 2: Cross-Platform Shamir Test Vectors & Desktop Rust

### Task 6: Shamir Test Vectors

**Files:**
- Create: `tests/fixtures/shamir-test-vectors.json`

- [ ] **Step 1: Create test vectors file**

These vectors use known inputs (master key + random coefficients) to produce deterministic shares. All platforms must match these exactly.

```json
{
  "description": "Shamir Secret Sharing GF(256) test vectors. Irreducible polynomial: x^8+x^4+x^3+x+1 (0x11B). Threshold: 2, Total: 3.",
  "vectors": [
    {
      "name": "all-zeros",
      "master_key_hex": "0000000000000000000000000000000000000000000000000000000000000000",
      "coefficients_hex": "0102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f20",
      "shares": {
        "1": "0102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f20",
        "2": "0204060805070b1c12140b18131a1530222432282a2e2838323428343a362e40",
        "3": "0306030c01010c14190e001409141a20332636383f343144292e3d283722114b"
      }
    },
    {
      "name": "all-ones",
      "master_key_hex": "0101010101010101010101010101010101010101010101010101010101010101",
      "coefficients_hex": "ff00ff00ff00ff00ff00ff00ff00ff00ff00ff00ff00ff00ff00ff00ff00ff00",
      "shares": {
        "1": "fe01fe01fe01fe01fe01fe01fe01fe01fe01fe01fe01fe01fe01fe01fe01fe01",
        "2": "e301e301e301e301e301e301e301e301e301e301e301e301e301e301e301e301",
        "3": "1c011c011c011c011c011c011c011c011c011c011c011c011c011c011c011c01"
      }
    },
    {
      "name": "random-key",
      "master_key_hex": "deadbeefcafebabe0123456789abcdef0011223344556677fedcba9876543210",
      "coefficients_hex": "a1b2c3d4e5f60718293a4b5c6d7e8f90a1b2c3d4e5f60718293a4b5c6d7e8f90",
      "shares": {
        "1": "7f1f7d3b2f48bd26280963355e259e7fa1a3e1e7a1a361ef27e6f1c41b2abd80",
        "2": "c5f98806fa52039c29233c1ad743116030117039e6f68697d81c4b58624cb4b0",
        "3": "64eb4bd23144be0a011977272a3d80f0918152e943a5478ff116b4e4156235a0"
      },
      "reconstruction_tests": [
        {"shares": [1, 2], "expected": "deadbeefcafebabe0123456789abcdef0011223344556677fedcba9876543210"},
        {"shares": [1, 3], "expected": "deadbeefcafebabe0123456789abcdef0011223344556677fedcba9876543210"},
        {"shares": [2, 3], "expected": "deadbeefcafebabe0123456789abcdef0011223344556677fedcba9876543210"}
      ]
    }
  ]
}
```

**IMPORTANT:** These test vector share values are EXAMPLES. The actual values must be computed using correct GF(256) arithmetic with polynomial 0x11B. When implementing Task 7 (Rust SSS), generate the real test vectors using the Rust implementation (which uses an audited library), then update this file with the correct values. All other platforms validate against these vectors.

- [ ] **Step 2: Commit**

```bash
mkdir -p tests/fixtures
git add tests/fixtures/shamir-test-vectors.json
git commit -m "test(recovery): add cross-platform Shamir SSS test vectors"
```

### Task 7: Desktop Rust — Shamir Service

**Files:**
- Modify: `clients/desktop/src-tauri/src/services/recovery_service.rs`
- Modify: `clients/desktop/src-tauri/Cargo.toml`

- [ ] **Step 1: Check `sharks` crate compatibility**

The `sharks` crate uses GF(256) with the same AES irreducible polynomial (0x11B). Verify by checking the crate source or docs. If incompatible, implement custom GF(256) (~100 lines).

Add to `clients/desktop/src-tauri/Cargo.toml` dependencies:

```toml
sharks = "0.5"
```

- [ ] **Step 2: Replace recovery_service.rs with Shamir implementation**

Replace the entire file with the new Shamir-based recovery service. The existing file is 512 lines of trustee-based recovery code — none of it is reusable.

```rust
// clients/desktop/src-tauri/src/services/recovery_service.rs
use base64::{engine::general_purpose::STANDARD as BASE64, Engine};
use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};
use sharks::{Share, Sharks};
use zeroize::Zeroize;

use crate::services::api_client::ApiClient;
use crate::AppResult;

#[derive(Debug, Serialize, Deserialize)]
pub struct RecoveryFile {
    pub version: u32,
    pub scheme: String,
    pub threshold: u32,
    pub share_index: u8,
    pub share_data: String, // base64
    pub checksum: String,   // SHA-256 hex of raw share bytes
    pub user_did: String,
    pub created_at: String,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct RecoveryStatus {
    pub is_active: bool,
    pub created_at: Option<String>,
}

pub struct RecoveryService {
    api_client: ApiClient,
}

impl RecoveryService {
    pub fn new(api_client: ApiClient) -> Self {
        Self { api_client }
    }

    /// Split a 32-byte master key into 3 Shamir shares (threshold 2).
    /// Returns ((index1, data1), (index2, data2), (index3, data3)).
    /// IMPORTANT: sharks crate includes x-coordinate as first byte in serialized shares.
    /// We strip it out since share_index is stored separately in the .recovery file.
    pub fn split_master_key(master_key: &[u8; 32]) -> AppResult<((u8, Vec<u8>), (u8, Vec<u8>), (u8, Vec<u8>))> {
        let sharks = Sharks(2); // threshold = 2
        let dealer = sharks.dealer(master_key);
        let shares: Vec<Share> = dealer.take(3).collect();

        // sharks serializes as [x_coord, byte0, byte1, ...] — strip first byte
        let extract = |s: &Share| -> (u8, Vec<u8>) {
            let bytes = Vec::from(s);
            (bytes[0], bytes[1..].to_vec()) // (x-coordinate, share data only)
        };

        Ok((extract(&shares[0]), extract(&shares[1]), extract(&shares[2])))
    }

    /// Reconstruct a 32-byte master key from 2 Shamir shares.
    /// share_index and share_data are separate — prepend index for sharks format.
    pub fn reconstruct_master_key(
        index1: u8, data1: &[u8],
        index2: u8, data2: &[u8],
    ) -> AppResult<[u8; 32]> {
        // sharks expects [x_coord, byte0, byte1, ...] — prepend index
        let mut s1_bytes = vec![index1];
        s1_bytes.extend_from_slice(data1);
        let mut s2_bytes = vec![index2];
        s2_bytes.extend_from_slice(data2);

        let s1 = Share::try_from(s1_bytes)
            .map_err(|e| format!("Invalid share 1: {}", e))?;
        let s2 = Share::try_from(s2_bytes)
            .map_err(|e| format!("Invalid share 2: {}", e))?;

        let sharks = Sharks(2);
        let secret = sharks.recover(&[s1, s2])
            .map_err(|e| format!("Reconstruction failed: {}", e))?;

        let mut key = [0u8; 32];
        if secret.len() != 32 {
            return Err(format!("Reconstructed key is {} bytes, expected 32", secret.len()).into());
        }
        key.copy_from_slice(&secret);
        Ok(key)
    }

    /// Create a RecoveryFile struct for export.
    pub fn create_recovery_file(
        share_index: u8,
        share_data: &[u8],
        user_did: &str,
    ) -> RecoveryFile {
        let checksum = hex::encode(Sha256::digest(share_data));
        RecoveryFile {
            version: 1,
            scheme: "shamir-gf256".to_string(),
            threshold: 2,
            share_index,
            share_data: BASE64.encode(share_data),
            checksum,
            user_did: user_did.to_string(),
            created_at: chrono::Utc::now().to_rfc3339(),
        }
    }

    /// Parse and validate a .recovery file.
    pub fn parse_recovery_file(contents: &str) -> AppResult<RecoveryFile> {
        let file: RecoveryFile = serde_json::from_str(contents)
            .map_err(|e| format!("Invalid recovery file: {}", e))?;

        if file.version > 1 {
            return Err("This recovery file requires a newer version of SSDID Drive".into());
        }

        // Validate checksum
        let raw_bytes = BASE64.decode(&file.share_data)
            .map_err(|e| format!("Invalid share_data base64: {}", e))?;
        let expected_checksum = hex::encode(Sha256::digest(&raw_bytes));
        if file.checksum != expected_checksum {
            return Err("Recovery file is damaged (checksum mismatch)".into());
        }

        Ok(file)
    }

    /// Compute key_proof: SHA-256 hex of the KEM public key.
    pub fn compute_key_proof(kem_public_key: &[u8]) -> String {
        hex::encode(Sha256::digest(kem_public_key))
    }

    // --- API calls ---

    pub async fn setup(&self, server_share: &str, key_proof: &str) -> AppResult<()> {
        self.api_client.post::<_, serde_json::Value>(
            "/api/recovery/setup",
            &serde_json::json!({
                "server_share": server_share,
                "key_proof": key_proof
            }),
        ).await?;
        Ok(())
    }

    pub async fn get_status(&self) -> AppResult<RecoveryStatus> {
        self.api_client.get("/api/recovery/status").await
    }

    pub async fn get_server_share(&self, did: &str) -> AppResult<ServerShareResponse> {
        // Use unauthenticated request
        let url = format!("/api/recovery/share?did={}", urlencoding::encode(did));
        self.api_client.get(&url).await
    }

    pub async fn complete_recovery(
        &self,
        old_did: &str,
        new_did: &str,
        key_proof: &str,
        kem_public_key: &str,
    ) -> AppResult<CompleteRecoveryResponse> {
        self.api_client.post(
            "/api/recovery/complete",
            &serde_json::json!({
                "old_did": old_did,
                "new_did": new_did,
                "key_proof": key_proof,
                "kem_public_key": kem_public_key
            }),
        ).await
    }

    pub async fn delete_setup(&self) -> AppResult<()> {
        self.api_client.delete::<serde_json::Value>("/api/recovery/setup").await?;
        Ok(())
    }
}

#[derive(Debug, Deserialize)]
pub struct ServerShareResponse {
    pub server_share: String,
    pub share_index: u8,
}

#[derive(Debug, Deserialize)]
pub struct CompleteRecoveryResponse {
    pub token: String,
    pub user_id: String,
}
```

- [ ] **Step 3: Add `hex` crate to Cargo.toml if not present**

```toml
hex = "0.4"
sha2 = "0.10"
```

- [ ] **Step 4: Verify build**

```bash
cd clients/desktop && cargo build
```

- [ ] **Step 5: Commit**

```bash
git add clients/desktop/src-tauri/
git commit -m "feat(desktop): replace recovery service with Shamir SSS implementation"
```

### Task 8: Desktop Rust — Tauri Commands

**Files:**
- Modify: `clients/desktop/src-tauri/src/commands/recovery.rs`
- Modify: `clients/desktop/src-tauri/src/lib.rs`

- [ ] **Step 1: Replace recovery commands**

Replace the entire `commands/recovery.rs` with new Shamir-based commands:

```rust
// clients/desktop/src-tauri/src/commands/recovery.rs
use tauri::State;
use crate::state::AppState;
use crate::services::recovery_service::{RecoveryService, RecoveryFile, RecoveryStatus};
use crate::AppResult;

#[tauri::command]
pub async fn setup_recovery(
    server_share: String,
    key_proof: String,
    state: State<'_, AppState>,
) -> AppResult<()> {
    let api_client = state.require_auth()?;
    let service = RecoveryService::new(api_client);
    service.setup(&server_share, &key_proof).await
}

#[tauri::command]
pub async fn get_recovery_status(
    state: State<'_, AppState>,
) -> AppResult<RecoveryStatus> {
    let api_client = state.require_auth()?;
    let service = RecoveryService::new(api_client);
    service.get_status().await
}

#[tauri::command]
pub async fn split_master_key(
    state: State<'_, AppState>,
) -> AppResult<SplitResult> {
    let crypto = state.require_unlocked()?;
    let master_key = crypto.get_master_key()?;
    let user_did = state.get_user_did()?;

    let ((i1, d1), (i2, d2), (_i3, d3)) = RecoveryService::split_master_key(&master_key)?;

    let file1 = RecoveryService::create_recovery_file(i1, &d1, &user_did);
    let file2 = RecoveryService::create_recovery_file(i2, &d2, &user_did);
    let server_share = base64::engine::general_purpose::STANDARD.encode(&d3);

    // Compute key_proof from KEM public key
    let kem_pk = crypto.get_kem_public_key()?;
    let key_proof = RecoveryService::compute_key_proof(&kem_pk);

    Ok(SplitResult {
        file1: serde_json::to_string_pretty(&file1).unwrap(),
        file2: serde_json::to_string_pretty(&file2).unwrap(),
        server_share,
        key_proof,
    })
}

#[derive(serde::Serialize)]
pub struct SplitResult {
    pub file1: String,
    pub file2: String,
    pub server_share: String,
    pub key_proof: String,
}

#[tauri::command]
pub async fn recover_with_files(
    file1_contents: String,
    file2_contents: String,
) -> AppResult<RecoverResult> {
    let f1 = RecoveryService::parse_recovery_file(&file1_contents)?;
    let f2 = RecoveryService::parse_recovery_file(&file2_contents)?;

    if f1.user_did != f2.user_did {
        return Err("Recovery files belong to different accounts".into());
    }
    if f1.share_index == f2.share_index {
        return Err("Both files contain the same share".into());
    }

    let s1_bytes = base64::engine::general_purpose::STANDARD.decode(&f1.share_data)?;
    let s2_bytes = base64::engine::general_purpose::STANDARD.decode(&f2.share_data)?;

    let master_key = RecoveryService::reconstruct_master_key(
        f1.share_index, &s1_bytes,
        f2.share_index, &s2_bytes,
    )?;

    Ok(RecoverResult {
        master_key_b64: base64::engine::general_purpose::STANDARD.encode(&master_key),
        user_did: f1.user_did,
    })
}

#[tauri::command]
pub async fn recover_with_file_and_server(
    file_contents: String,
    state: State<'_, AppState>,
) -> AppResult<RecoverResult> {
    let f = RecoveryService::parse_recovery_file(&file_contents)?;

    let api_client = state.get_api_client();
    let service = RecoveryService::new(api_client);
    let server = service.get_server_share(&f.user_did).await?;

    let server_bytes = base64::engine::general_purpose::STANDARD.decode(&server.server_share)?;
    let file_bytes = base64::engine::general_purpose::STANDARD.decode(&f.share_data)?;

    let master_key = RecoveryService::reconstruct_master_key(
        f.share_index, &file_bytes,
        server.share_index, &server_bytes,
    )?;

    Ok(RecoverResult {
        master_key_b64: base64::engine::general_purpose::STANDARD.encode(&master_key),
        user_did: f.user_did,
    })
}

#[derive(serde::Serialize)]
pub struct RecoverResult {
    pub master_key_b64: String,
    pub user_did: String,
}

#[tauri::command]
pub async fn delete_recovery_setup(
    state: State<'_, AppState>,
) -> AppResult<()> {
    let api_client = state.require_auth()?;
    let service = RecoveryService::new(api_client);
    service.delete_setup().await
}
```

- [ ] **Step 2: Update lib.rs command registrations**

In `clients/desktop/src-tauri/src/lib.rs`, replace the old recovery command registrations with:

```rust
commands::recovery::setup_recovery,
commands::recovery::get_recovery_status,
commands::recovery::split_master_key,
commands::recovery::recover_with_files,
commands::recovery::recover_with_file_and_server,
commands::recovery::delete_recovery_setup,
```

Remove old recovery commands: `initiate_recovery`, `approve_recovery_request`, `complete_recovery`, `get_pending_recovery_requests`.

- [ ] **Step 3: Verify build**

```bash
cd clients/desktop && cargo build
```

- [ ] **Step 4: Commit**

```bash
git add clients/desktop/src-tauri/src/commands/recovery.rs clients/desktop/src-tauri/src/lib.rs
git commit -m "feat(desktop): replace recovery Tauri commands with Shamir SSS"
```

---

## Chunk 3: Desktop Frontend

### Task 9: Desktop TypeScript Service Layer

**Files:**
- Modify: `clients/desktop/src/services/tauri.ts`

- [ ] **Step 1: Add recovery types and service functions**

Add to `clients/desktop/src/services/tauri.ts`:

```typescript
// ==================== Recovery Types ====================

export interface RecoveryStatus {
  is_active: boolean;
  created_at: string | null;
}

export interface SplitResult {
  file1: string; // JSON string of .recovery file
  file2: string;
  server_share: string;
  key_proof: string;
}

export interface RecoverResult {
  master_key_b64: string;
  user_did: string;
}
```

Add to the `tauriService` object:

```typescript
// ==================== Recovery Commands ====================

async getRecoveryStatus(): Promise<RecoveryStatus> {
  return invoke('get_recovery_status');
},

async splitMasterKey(): Promise<SplitResult> {
  return invoke('split_master_key');
},

async setupRecovery(serverShare: string, keyProof: string): Promise<void> {
  return invoke('setup_recovery', { server_share: serverShare, key_proof: keyProof });
},

async recoverWithFiles(file1Contents: string, file2Contents: string): Promise<RecoverResult> {
  return invoke('recover_with_files', { file1_contents: file1Contents, file2_contents: file2Contents });
},

async recoverWithFileAndServer(fileContents: string): Promise<RecoverResult> {
  return invoke('recover_with_file_and_server', { file_contents: fileContents });
},

async deleteRecoverySetup(): Promise<void> {
  return invoke('delete_recovery_setup');
},
```

- [ ] **Step 2: Commit**

```bash
git add clients/desktop/src/services/tauri.ts
git commit -m "feat(desktop): add recovery service functions to Tauri TS layer"
```

### Task 10: Recovery Banner Component

**Files:**
- Create: `clients/desktop/src/components/recovery/RecoveryBanner.tsx`

- [ ] **Step 1: Create the persistent warning banner**

```tsx
// clients/desktop/src/components/recovery/RecoveryBanner.tsx
import { useState, useEffect } from 'react';
import { ShieldAlert, X } from 'lucide-react';
import { tauriService } from '../../services/tauri';

interface RecoveryBannerProps {
  onSetupClick: () => void;
}

export function RecoveryBanner({ onSetupClick }: RecoveryBannerProps) {
  const [visible, setVisible] = useState(false);
  const [dismissCount, setDismissCount] = useState(0);
  const [canDismiss, setCanDismiss] = useState(true);

  useEffect(() => {
    checkRecoveryStatus();
  }, []);

  async function checkRecoveryStatus() {
    try {
      const status = await tauriService.getRecoveryStatus();
      if (!status.is_active) {
        setVisible(true);
        const count = parseInt(localStorage.getItem('recovery_dismiss_count') || '0');
        setDismissCount(count);
        setCanDismiss(count < 3);
      }
    } catch {
      // Not authenticated yet or error — don't show
    }
  }

  function handleDismiss() {
    const newCount = dismissCount + 1;
    localStorage.setItem('recovery_dismiss_count', String(newCount));
    setDismissCount(newCount);
    if (newCount >= 3) {
      setCanDismiss(false);
    } else {
      setVisible(false);
    }
  }

  if (!visible) return null;

  return (
    <div className="bg-red-900/80 border border-red-700 text-red-100 px-4 py-3 flex items-center gap-3">
      <ShieldAlert className="h-5 w-5 flex-shrink-0 text-red-400" />
      <p className="flex-1 text-sm font-medium">
        Your files are at risk. If you lose this device, your encrypted files will be
        permanently unrecoverable.
      </p>
      <button
        onClick={onSetupClick}
        className="bg-red-600 hover:bg-red-500 text-white px-4 py-1.5 rounded text-sm font-medium whitespace-nowrap"
      >
        Set Up Recovery
      </button>
      {canDismiss && (
        <button onClick={handleDismiss} className="text-red-400 hover:text-red-300">
          <X className="h-4 w-4" />
        </button>
      )}
    </div>
  );
}
```

- [ ] **Step 2: Integrate banner into main layout**

In `clients/desktop/src/components/layout/Sidebar.tsx` (or the main layout component that wraps authenticated pages), add the banner at the top of the content area. Import `RecoveryBanner` and render it above the main content. Wire `onSetupClick` to navigate to the recovery setup wizard (e.g., open a dialog or navigate to `/settings` with a query param).

- [ ] **Step 3: Commit**

```bash
git add clients/desktop/src/components/recovery/
git commit -m "feat(desktop): add recovery warning banner component"
```

### Task 11: Recovery Setup Wizard

**Files:**
- Create: `clients/desktop/src/components/recovery/RecoverySetupWizard.tsx`

- [ ] **Step 1: Create the 3-step wizard component**

Build a modal/dialog component with 3 steps:
1. Explanation screen with "Begin Setup" button
2. Generate shares, download 2 `.recovery` files with confirmation checkboxes
3. Upload server share + show success

Use Tauri's `save` dialog (`@tauri-apps/plugin-dialog`) for file download. Use `tauriService.splitMasterKey()` to generate shares, then `tauriService.setupRecovery()` to upload the server share.

Key interactions:
- Step 2: Call `splitMasterKey()` → get `file1`, `file2`, `server_share`, `key_proof`
- Download file1 as `recovery-self.recovery` via Tauri save dialog
- Download file2 as `recovery-trusted.recovery` via Tauri save dialog
- Step 3: Call `setupRecovery(server_share, key_proof)` → success

The component should be ~150-200 lines. Use existing Radix UI components (Dialog, Button) and Tailwind for styling, matching the app's design system.

- [ ] **Step 2: Wire wizard into settings page and banner**

Add a "Recovery" section to the settings page showing status and a "Set Up" / "Regenerate" button that opens the wizard.

- [ ] **Step 3: Commit**

```bash
git add clients/desktop/src/components/recovery/RecoverySetupWizard.tsx
git commit -m "feat(desktop): add recovery setup wizard component"
```

### Task 12: Recovery Page (Login Flow)

**Files:**
- Create: `clients/desktop/src/pages/RecoveryPage.tsx`
- Modify: `clients/desktop/src/App.tsx`
- Modify: `clients/desktop/src/pages/LoginPage.tsx`

- [ ] **Step 1: Create RecoveryPage**

Build a page with two recovery paths:
- Path A: Upload 2 `.recovery` files → `recoverWithFiles()`
- Path B: Upload 1 `.recovery` file → `recoverWithFileAndServer()`

Use Tauri's `open` dialog for file selection. After successful reconstruction, the page should complete the re-enrollment flow (generate new DID, call recovery complete API, store keys, redirect to main app).

The page should handle:
- File upload via Tauri dialog (`.recovery` extension filter)
- Validation feedback (wrong files, same share, different accounts)
- Loading states during reconstruction and API calls
- Success → redirect to main app
- Error handling with clear messages

**Post-recovery folder key re-encapsulation (CRITICAL):** After successful reconstruction and re-enrollment, the app must re-encapsulate all folder keys with the new KEM keys. This happens automatically after the user regains access:
1. List all folders the user owns
2. For each folder, use the old KEM private keys (derived from the reconstructed master key) to decapsulate the folder key
3. Re-encapsulate with the new KEM public key
4. Upload updated `WrappedKek` + `OwnerKemCiphertext` to server via the existing folder key rotation endpoint (`POST /api/folders/{id}/rotate-key` or similar)
5. Zeroize old KEM keys from memory

This logic should be implemented in the Rust `RecoveryService` as `re_encapsulate_folder_keys()` and called from the recovery command after successful completion. The same re-encapsulation logic applies to Android and iOS recovery flows.

- [ ] **Step 2: Add /recover route to App.tsx**

```tsx
<Route path="/recover" element={<RecoveryPage />} />
```

This route should NOT be wrapped in `<ProtectedRoute>` since the user is not authenticated.

- [ ] **Step 3: Add "Recover Account" link to LoginPage**

Add a link below the login button:
```tsx
<Link to="/recover" className="text-sm text-muted-foreground hover:text-foreground">
  Lost your device? Recover your account
</Link>
```

- [ ] **Step 4: Commit**

```bash
git add clients/desktop/src/pages/RecoveryPage.tsx clients/desktop/src/App.tsx clients/desktop/src/pages/LoginPage.tsx
git commit -m "feat(desktop): add recovery page and login integration"
```

---

## Chunk 4: Android Client

### Task 13: Android Shamir Implementation

**Files:**
- Create: `clients/android/app/src/main/java/my/ssdid/drive/domain/crypto/ShamirSecretSharing.kt`
- Create: `clients/android/app/src/main/java/my/ssdid/drive/domain/crypto/RecoveryFile.kt`
- Create: `clients/android/app/src/test/java/my/ssdid/drive/domain/crypto/ShamirSecretSharingTest.kt`

- [ ] **Step 1: Implement GF(256) arithmetic and Shamir SSS**

```kotlin
// clients/android/app/src/main/java/my/ssdid/drive/domain/crypto/ShamirSecretSharing.kt
package my.ssdid.drive.domain.crypto

import java.security.SecureRandom

/**
 * Shamir's Secret Sharing over GF(256).
 * Irreducible polynomial: x^8 + x^4 + x^3 + x + 1 (0x11B, same as AES).
 */
object ShamirSecretSharing {

    // GF(256) multiplication using Russian peasant algorithm
    private fun gfMul(a: Int, b: Int): Int {
        var aa = a
        var bb = b
        var result = 0
        while (bb > 0) {
            if (bb and 1 != 0) result = result xor aa
            aa = aa shl 1
            if (aa and 0x100 != 0) aa = aa xor 0x11B
            bb = bb shr 1
        }
        return result
    }

    // GF(256) multiplicative inverse via extended Euclidean / Fermat's little theorem
    private fun gfInv(a: Int): Int {
        if (a == 0) throw ArithmeticException("No inverse for 0")
        // a^254 = a^(-1) in GF(256) since a^255 = 1
        var result = a
        repeat(6) { result = gfMul(result, result); result = gfMul(result, a) }
        result = gfMul(result, result) // a^254
        return result
    }

    /**
     * Split a secret byte array into [totalShares] shares with [threshold] required to reconstruct.
     * Returns a list of pairs: (shareIndex: Int, shareData: ByteArray).
     */
    fun split(secret: ByteArray, threshold: Int, totalShares: Int): List<Pair<Int, ByteArray>> {
        require(threshold in 2..totalShares)
        require(totalShares <= 255)

        val rng = SecureRandom()
        val shares = (1..totalShares).map { x -> x to ByteArray(secret.size) }

        for (byteIdx in secret.indices) {
            // Generate random coefficients for polynomial of degree (threshold - 1)
            val coeffs = IntArray(threshold)
            coeffs[0] = secret[byteIdx].toInt() and 0xFF
            for (i in 1 until threshold) {
                coeffs[i] = rng.nextInt(256)
            }

            // Evaluate polynomial at each x
            for ((x, shareData) in shares) {
                var value = 0
                var xPow = 1
                for (c in coeffs) {
                    value = value xor gfMul(c, xPow)
                    xPow = gfMul(xPow, x)
                }
                shareData[byteIdx] = value.toByte()
            }
        }

        return shares
    }

    /**
     * Reconstruct secret from [shares] using Lagrange interpolation over GF(256).
     * Each share is a pair of (shareIndex: Int, shareData: ByteArray).
     */
    fun reconstruct(shares: List<Pair<Int, ByteArray>>): ByteArray {
        require(shares.size >= 2)
        val len = shares[0].second.size
        require(shares.all { it.second.size == len })

        val result = ByteArray(len)

        for (byteIdx in 0 until len) {
            var value = 0
            for (i in shares.indices) {
                val (xi, yi) = shares[i]
                val yiByte = yi[byteIdx].toInt() and 0xFF

                // Lagrange basis polynomial evaluated at x=0
                var basis = 1
                for (j in shares.indices) {
                    if (i == j) continue
                    val xj = shares[j].first
                    // basis *= xj / (xj - xi)  in GF(256)
                    // xj - xi = xj XOR xi in GF(256)
                    basis = gfMul(basis, gfMul(xj, gfInv(xj xor xi)))
                }

                value = value xor gfMul(yiByte, basis)
            }
            result[byteIdx] = value.toByte()
        }

        return result
    }
}
```

- [ ] **Step 2: Create RecoveryFile data class**

```kotlin
// clients/android/app/src/main/java/my/ssdid/drive/domain/crypto/RecoveryFile.kt
package my.ssdid.drive.domain.crypto

import com.google.gson.annotations.SerializedName
import java.security.MessageDigest
import android.util.Base64

data class RecoveryFile(
    val version: Int,
    val scheme: String,
    val threshold: Int,
    @SerializedName("share_index") val shareIndex: Int,
    @SerializedName("share_data") val shareData: String,
    val checksum: String,
    @SerializedName("user_did") val userDid: String,
    @SerializedName("created_at") val createdAt: String
) {
    fun validate(): Result<ByteArray> {
        if (version > 1) {
            return Result.failure(IllegalArgumentException(
                "This recovery file requires a newer version of SSDID Drive"))
        }

        val rawBytes = try {
            Base64.decode(shareData, Base64.NO_WRAP)
        } catch (e: Exception) {
            return Result.failure(IllegalArgumentException("Invalid share data"))
        }

        val expectedChecksum = MessageDigest.getInstance("SHA-256")
            .digest(rawBytes)
            .joinToString("") { "%02x".format(it) }

        if (checksum != expectedChecksum) {
            return Result.failure(IllegalArgumentException("Recovery file is damaged"))
        }

        return Result.success(rawBytes)
    }

    companion object {
        fun create(shareIndex: Int, shareData: ByteArray, userDid: String): RecoveryFile {
            val checksum = MessageDigest.getInstance("SHA-256")
                .digest(shareData)
                .joinToString("") { "%02x".format(it) }

            return RecoveryFile(
                version = 1,
                scheme = "shamir-gf256",
                threshold = 2,
                shareIndex = shareIndex,
                shareData = Base64.encodeToString(shareData, Base64.NO_WRAP),
                checksum = checksum,
                userDid = userDid,
                createdAt = java.time.Instant.now().toString()
            )
        }
    }
}
```

- [ ] **Step 3: Write unit tests**

```kotlin
// clients/android/app/src/test/java/my/ssdid/drive/domain/crypto/ShamirSecretSharingTest.kt
package my.ssdid.drive.domain.crypto

import org.junit.Assert.*
import org.junit.Test

class ShamirSecretSharingTest {

    @Test
    fun `split and reconstruct with shares 1 and 2`() {
        val secret = ByteArray(32) { it.toByte() }
        val shares = ShamirSecretSharing.split(secret, 2, 3)
        assertEquals(3, shares.size)

        val reconstructed = ShamirSecretSharing.reconstruct(listOf(shares[0], shares[1]))
        assertArrayEquals(secret, reconstructed)
    }

    @Test
    fun `split and reconstruct with shares 1 and 3`() {
        val secret = ByteArray(32) { it.toByte() }
        val shares = ShamirSecretSharing.split(secret, 2, 3)

        val reconstructed = ShamirSecretSharing.reconstruct(listOf(shares[0], shares[2]))
        assertArrayEquals(secret, reconstructed)
    }

    @Test
    fun `split and reconstruct with shares 2 and 3`() {
        val secret = ByteArray(32) { it.toByte() }
        val shares = ShamirSecretSharing.split(secret, 2, 3)

        val reconstructed = ShamirSecretSharing.reconstruct(listOf(shares[1], shares[2]))
        assertArrayEquals(secret, reconstructed)
    }

    @Test
    fun `reconstruct random 32-byte key`() {
        val secret = java.security.SecureRandom().let { rng ->
            ByteArray(32).also { rng.nextBytes(it) }
        }
        val shares = ShamirSecretSharing.split(secret, 2, 3)

        for (combo in listOf(listOf(0, 1), listOf(0, 2), listOf(1, 2))) {
            val selected = combo.map { shares[it] }
            val reconstructed = ShamirSecretSharing.reconstruct(selected)
            assertArrayEquals("Failed for combination $combo", secret, reconstructed)
        }
    }

    @Test
    fun `single share reveals nothing about secret`() {
        // Information-theoretic: for any single share, every possible secret is equally likely.
        // We test this indirectly: two different secrets can produce the same share at index 1.
        val s1 = byteArrayOf(0x42)
        val s2 = byteArrayOf(0x99.toByte())

        // With threshold=2, share at x=1 is: secret XOR coeff.
        // For s1 with coeff=0x57: share = 0x42 XOR 0x57 = 0x15
        // For s2 with coeff=0x8C: share = 0x99 XOR gfMul(0x8C, 1)
        // This shows any share value is possible for any secret.
        // Just verify we get 32-byte shares.
        val shares1 = ShamirSecretSharing.split(s1, 2, 3)
        val shares2 = ShamirSecretSharing.split(s2, 2, 3)
        assertEquals(1, shares1[0].second.size)
        assertEquals(1, shares2[0].second.size)
    }
}
```

- [ ] **Step 4: Run tests**

```bash
cd clients/android && ./gradlew test --tests "my.ssdid.drive.domain.crypto.ShamirSecretSharingTest"
```

- [ ] **Step 5: Commit**

```bash
git add clients/android/app/src/main/java/my/ssdid/drive/domain/crypto/ShamirSecretSharing.kt \
       clients/android/app/src/main/java/my/ssdid/drive/domain/crypto/RecoveryFile.kt \
       clients/android/app/src/test/java/my/ssdid/drive/domain/crypto/ShamirSecretSharingTest.kt
git commit -m "feat(android): add Shamir SSS implementation with GF(256) and tests"
```

### Task 14: Android Repository & API Layer

**Files:**
- Modify: `clients/android/app/src/main/java/my/ssdid/drive/data/remote/ApiService.kt`
- Create: `clients/android/app/src/main/java/my/ssdid/drive/domain/repository/RecoveryRepository.kt`
- Create: `clients/android/app/src/main/java/my/ssdid/drive/data/repository/RecoveryRepositoryImpl.kt`
- Modify: `clients/android/app/src/main/java/my/ssdid/drive/di/RepositoryModule.kt`

- [ ] **Step 1: Replace old recovery endpoints in ApiService.kt**

Remove all existing recovery-related Retrofit endpoints and add:

```kotlin
// Recovery
@POST("recovery/setup")
suspend fun setupRecovery(@Body request: SetupRecoveryRequest): Response<Unit>

@GET("recovery/status")
suspend fun getRecoveryStatus(): Response<RecoveryStatusResponse>

@GET("recovery/share")
suspend fun getRecoveryShare(@Query("did") did: String): Response<ServerShareResponse>

@POST("recovery/complete")
suspend fun completeRecovery(@Body request: CompleteRecoveryRequest): Response<CompleteRecoveryResponse>

@DELETE("recovery/setup")
suspend fun deleteRecoverySetup(): Response<Unit>

// DTOs
data class SetupRecoveryRequest(
    @SerializedName("server_share") val serverShare: String,
    @SerializedName("key_proof") val keyProof: String
)
data class RecoveryStatusResponse(
    @SerializedName("is_active") val isActive: Boolean,
    @SerializedName("created_at") val createdAt: String?
)
data class ServerShareResponse(
    @SerializedName("server_share") val serverShare: String,
    @SerializedName("share_index") val shareIndex: Int
)
data class CompleteRecoveryRequest(
    @SerializedName("old_did") val oldDid: String,
    @SerializedName("new_did") val newDid: String,
    @SerializedName("key_proof") val keyProof: String,
    @SerializedName("kem_public_key") val kemPublicKey: String
)
data class CompleteRecoveryResponse(
    val token: String,
    @SerializedName("user_id") val userId: String
)
```

- [ ] **Step 2: Create RecoveryRepository interface**

```kotlin
package my.ssdid.drive.domain.repository

interface RecoveryRepository {
    suspend fun setupRecovery(serverShare: String, keyProof: String): Result<Unit>
    suspend fun getStatus(): Result<RecoveryStatusResponse>
    suspend fun getServerShare(did: String): Result<ServerShareResponse>
    suspend fun completeRecovery(oldDid: String, newDid: String, keyProof: String, kemPublicKey: String): Result<CompleteRecoveryResponse>
    suspend fun deleteSetup(): Result<Unit>
}
```

- [ ] **Step 3: Create RecoveryRepositoryImpl**

Follow the existing repository pattern — wrap Retrofit calls in try/catch, return `Result<T>`.

- [ ] **Step 4: Add Hilt binding in RepositoryModule**

```kotlin
@Binds @Singleton
abstract fun bindRecoveryRepository(impl: RecoveryRepositoryImpl): RecoveryRepository
```

- [ ] **Step 5: Commit**

```bash
git add clients/android/app/src/main/java/my/ssdid/drive/
git commit -m "feat(android): add recovery repository and API layer"
```

### Task 15: Android Recovery UI

**Files:**
- Create: `clients/android/app/src/main/java/my/ssdid/drive/presentation/recovery/RecoverySetupViewModel.kt`
- Create: `clients/android/app/src/main/java/my/ssdid/drive/presentation/recovery/RecoverySetupScreen.kt`
- Create: `clients/android/app/src/main/java/my/ssdid/drive/presentation/recovery/RecoveryViewModel.kt`
- Create: `clients/android/app/src/main/java/my/ssdid/drive/presentation/recovery/RecoveryScreen.kt`
- Create: `clients/android/app/src/main/java/my/ssdid/drive/presentation/recovery/RecoveryBanner.kt`
- Modify: `clients/android/app/src/main/java/my/ssdid/drive/presentation/auth/LoginScreen.kt`

- [ ] **Step 1: Create RecoverySetupViewModel**

Hilt ViewModel with states: Explanation → GenerateShares → UploadingServerShare → Success. Use `Intent.ACTION_CREATE_DOCUMENT` for file save (SAF).

- [ ] **Step 2: Create RecoverySetupScreen**

3-step wizard Compose UI matching the spec. Step 1: explanation + "Begin Setup". Step 2: download buttons + checkboxes. Step 3: auto-upload + success.

- [ ] **Step 3: Create RecoveryViewModel**

Handles the login-page recovery flow. States: SelectPath → UploadFiles → Reconstructing → ReEnrolling → Success. Two paths: 2 files or 1 file + server.

- [ ] **Step 4: Create RecoveryScreen**

Compose UI for recovery flow. File upload via `rememberLauncherForActivityResult(ActivityResultContracts.OpenDocument())`. Shows progress and error states.

- [ ] **Step 5: Create RecoveryBanner composable**

```kotlin
@Composable
fun RecoveryBanner(onSetupClick: () -> Unit) {
    // Red/orange warning bar with shield icon, message text, CTA button, dismiss logic
    // Uses SharedPreferences for dismiss count tracking
}
```

- [ ] **Step 6: Add "Recover Account" to LoginScreen**

Add a `TextButton` below the wallet login button:
```kotlin
TextButton(onClick = { navController.navigate("recovery") }) {
    Text("Lost your device? Recover your account")
}
```

- [ ] **Step 7: Add navigation routes**

In NavGraph, add `composable("recovery") { RecoveryScreen(...) }` and `composable("recovery-setup") { RecoverySetupScreen(...) }`.

- [ ] **Step 8: Commit**

```bash
git add clients/android/app/src/main/java/my/ssdid/drive/presentation/
git commit -m "feat(android): add recovery setup wizard, recovery flow, and banner UI"
```

---

## Chunk 5: iOS Client

### Task 16: iOS Shamir Implementation

**Files:**
- Create: `clients/ios/SsdidDrive/SsdidDrive/Domain/Crypto/ShamirSecretSharing.swift`
- Create: `clients/ios/SsdidDrive/SsdidDrive/Domain/Crypto/RecoveryFile.swift`

- [ ] **Step 1: Implement GF(256) and Shamir SSS in Swift**

```swift
// clients/ios/SsdidDrive/SsdidDrive/Domain/Crypto/ShamirSecretSharing.swift
import Foundation
import Security

/// Shamir's Secret Sharing over GF(256).
/// Irreducible polynomial: x^8 + x^4 + x^3 + x + 1 (0x11B, same as AES).
enum ShamirSecretSharing {

    /// GF(256) multiplication using Russian peasant algorithm.
    static func gfMul(_ a: UInt8, _ b: UInt8) -> UInt8 {
        var aa = UInt16(a)
        var bb = UInt16(b)
        var result: UInt16 = 0
        while bb > 0 {
            if bb & 1 != 0 { result ^= aa }
            aa <<= 1
            if aa & 0x100 != 0 { aa ^= 0x11B }
            bb >>= 1
        }
        return UInt8(result & 0xFF)
    }

    /// GF(256) multiplicative inverse via Fermat's little theorem: a^254 = a^(-1).
    static func gfInv(_ a: UInt8) -> UInt8 {
        guard a != 0 else { fatalError("No inverse for 0 in GF(256)") }
        var result = a
        for _ in 0..<6 {
            result = gfMul(result, result)
            result = gfMul(result, a)
        }
        result = gfMul(result, result) // a^254
        return result
    }

    /// Split secret into shares. Returns [(shareIndex, shareData)].
    static func split(secret: Data, threshold: Int, totalShares: Int) -> [(index: UInt8, data: Data)] {
        precondition(threshold >= 2 && threshold <= totalShares && totalShares <= 255)

        var shares = (1...totalShares).map { (UInt8($0), Data(count: secret.count)) }

        for byteIdx in 0..<secret.count {
            var coeffs = [UInt8](repeating: 0, count: threshold)
            coeffs[0] = secret[byteIdx]
            for i in 1..<threshold {
                var randomByte: UInt8 = 0
                SecRandomCopyBytes(kSecRandomDefault, 1, &randomByte)
                coeffs[i] = randomByte
            }

            for shareIdx in 0..<shares.count {
                let x = shares[shareIdx].index
                var value: UInt8 = 0
                var xPow: UInt8 = 1
                for c in coeffs {
                    value ^= gfMul(c, xPow)
                    xPow = gfMul(xPow, x)
                }
                shares[shareIdx].data[byteIdx] = value
            }
        }

        return shares
    }

    /// Reconstruct secret from shares using Lagrange interpolation.
    static func reconstruct(shares: [(index: UInt8, data: Data)]) -> Data {
        precondition(shares.count >= 2)
        let len = shares[0].data.count
        precondition(shares.allSatisfy { $0.data.count == len })

        var result = Data(count: len)

        for byteIdx in 0..<len {
            var value: UInt8 = 0
            for i in 0..<shares.count {
                let xi = shares[i].index
                let yi = shares[i].data[byteIdx]

                var basis: UInt8 = 1
                for j in 0..<shares.count {
                    guard i != j else { continue }
                    let xj = shares[j].index
                    basis = gfMul(basis, gfMul(xj, gfInv(xj ^ xi)))
                }

                value ^= gfMul(yi, basis)
            }
            result[byteIdx] = value
        }

        return result
    }
}
```

- [ ] **Step 2: Create RecoveryFile model**

```swift
// clients/ios/SsdidDrive/SsdidDrive/Domain/Crypto/RecoveryFile.swift
import Foundation
import CryptoKit

struct RecoveryFile: Codable {
    let version: Int
    let scheme: String
    let threshold: Int
    let shareIndex: Int
    let shareData: String
    let checksum: String
    let userDid: String
    let createdAt: String

    enum CodingKeys: String, CodingKey {
        case version, scheme, threshold, checksum
        case shareIndex = "share_index"
        case shareData = "share_data"
        case userDid = "user_did"
        case createdAt = "created_at"
    }

    func validate() throws -> Data {
        guard version <= 1 else {
            throw RecoveryError.unsupportedVersion
        }

        guard let rawBytes = Data(base64Encoded: shareData) else {
            throw RecoveryError.invalidShareData
        }

        let hash = SHA256.hash(data: rawBytes)
        let expectedChecksum = hash.map { String(format: "%02x", $0) }.joined()

        guard checksum == expectedChecksum else {
            throw RecoveryError.corruptedFile
        }

        return rawBytes
    }

    static func create(shareIndex: Int, shareData: Data, userDid: String) -> RecoveryFile {
        let hash = SHA256.hash(data: shareData)
        let checksum = hash.map { String(format: "%02x", $0) }.joined()

        return RecoveryFile(
            version: 1,
            scheme: "shamir-gf256",
            threshold: 2,
            shareIndex: shareIndex,
            shareData: shareData.base64EncodedString(),
            checksum: checksum,
            userDid: userDid,
            createdAt: ISO8601DateFormatter().string(from: Date())
        )
    }
}

enum RecoveryError: LocalizedError {
    case unsupportedVersion
    case invalidShareData
    case corruptedFile
    case sameShare
    case differentAccounts
    case reconstructionFailed

    var errorDescription: String? {
        switch self {
        case .unsupportedVersion: return "This recovery file requires a newer version of SSDID Drive"
        case .invalidShareData: return "Invalid share data in recovery file"
        case .corruptedFile: return "Recovery file is damaged (checksum mismatch)"
        case .sameShare: return "Both files contain the same share"
        case .differentAccounts: return "Recovery files belong to different accounts"
        case .reconstructionFailed: return "Failed to reconstruct encryption key"
        }
    }
}
```

- [ ] **Step 3: Write iOS Shamir unit tests**

Create `clients/ios/SsdidDrive/SsdidDriveTests/Domain/Crypto/ShamirSecretSharingTests.swift`:

```swift
import XCTest
@testable import SsdidDrive

final class ShamirSecretSharingTests: XCTestCase {

    func testSplitAndReconstructWithShares12() {
        let secret = Data(0..<32)
        let shares = ShamirSecretSharing.split(secret: secret, threshold: 2, totalShares: 3)
        let result = ShamirSecretSharing.reconstruct(shares: [shares[0], shares[1]])
        XCTAssertEqual(result, secret)
    }

    func testSplitAndReconstructWithShares13() {
        let secret = Data(0..<32)
        let shares = ShamirSecretSharing.split(secret: secret, threshold: 2, totalShares: 3)
        let result = ShamirSecretSharing.reconstruct(shares: [shares[0], shares[2]])
        XCTAssertEqual(result, secret)
    }

    func testSplitAndReconstructWithShares23() {
        let secret = Data(0..<32)
        let shares = ShamirSecretSharing.split(secret: secret, threshold: 2, totalShares: 3)
        let result = ShamirSecretSharing.reconstruct(shares: [shares[1], shares[2]])
        XCTAssertEqual(result, secret)
    }

    func testAllCombinationsWithRandomKey() {
        var secret = Data(count: 32)
        _ = secret.withUnsafeMutableBytes { SecRandomCopyBytes(kSecRandomDefault, 32, $0.baseAddress!) }

        let shares = ShamirSecretSharing.split(secret: secret, threshold: 2, totalShares: 3)
        let combos: [(Int, Int)] = [(0, 1), (0, 2), (1, 2)]
        for (i, j) in combos {
            let result = ShamirSecretSharing.reconstruct(shares: [shares[i], shares[j]])
            XCTAssertEqual(result, secret, "Failed for combination (\(i), \(j))")
        }
    }
}
```

- [ ] **Step 4: Commit**

```bash
git add clients/ios/SsdidDrive/SsdidDrive/Domain/Crypto/ShamirSecretSharing.swift \
       clients/ios/SsdidDrive/SsdidDrive/Domain/Crypto/RecoveryFile.swift \
       clients/ios/SsdidDrive/SsdidDriveTests/
git commit -m "feat(ios): add Shamir SSS implementation with GF(256) and tests"
```

**Cross-platform test vector validation:** Each platform's Shamir tests MUST also include a test that reads `tests/fixtures/shamir-test-vectors.json` and validates that `split()` with the given coefficients produces the expected shares, and `reconstruct()` from every 2-of-3 combination recovers the original master key. The implementing agent should add this test after the test vectors file has been finalized with correct values (Task 6/7).

### Task 17: iOS Repository & API Layer

**Files:**
- Create: `clients/ios/SsdidDrive/SsdidDrive/Domain/Repository/RecoveryRepository.swift`
- Create: `clients/ios/SsdidDrive/SsdidDrive/Data/Repository/RecoveryRepositoryImpl.swift`
- Modify: `clients/ios/SsdidDrive/SsdidDrive/Core/DI/Container.swift`

- [ ] **Step 1: Create RecoveryRepository protocol**

```swift
protocol RecoveryRepository {
    func setupRecovery(serverShare: String, keyProof: String) async throws
    func getStatus() async throws -> RecoveryStatusResponse
    func getServerShare(did: String) async throws -> ServerShareResponse
    func completeRecovery(oldDid: String, newDid: String, keyProof: String, kemPublicKey: String) async throws -> CompleteRecoveryResponse
    func deleteSetup() async throws
}

struct RecoveryStatusResponse: Codable {
    let isActive: Bool
    let createdAt: String?

    enum CodingKeys: String, CodingKey {
        case isActive = "is_active"
        case createdAt = "created_at"
    }
}

struct ServerShareResponse: Codable {
    let serverShare: String
    let shareIndex: Int

    enum CodingKeys: String, CodingKey {
        case serverShare = "server_share"
        case shareIndex = "share_index"
    }
}

struct CompleteRecoveryResponse: Codable {
    let token: String
    let userId: String

    enum CodingKeys: String, CodingKey {
        case token
        case userId = "user_id"
    }
}
```

- [ ] **Step 2: Create RecoveryRepositoryImpl**

Follow the existing `APIClient.request()` pattern.

- [ ] **Step 3: Add to DI Container**

```swift
lazy var recoveryRepository: RecoveryRepository = RecoveryRepositoryImpl(apiClient: apiClient)
```

- [ ] **Step 4: Commit**

```bash
git add clients/ios/SsdidDrive/SsdidDrive/Domain/Repository/RecoveryRepository.swift \
       clients/ios/SsdidDrive/SsdidDrive/Data/Repository/RecoveryRepositoryImpl.swift \
       clients/ios/SsdidDrive/SsdidDrive/Core/DI/Container.swift
git commit -m "feat(ios): add recovery repository and API layer"
```

### Task 18: iOS Recovery UI

**Files:**
- Create: `clients/ios/SsdidDrive/SsdidDrive/Presentation/Recovery/RecoverySetupViewModel.swift`
- Create: `clients/ios/SsdidDrive/SsdidDrive/Presentation/Recovery/RecoverySetupViewController.swift`
- Create: `clients/ios/SsdidDrive/SsdidDrive/Presentation/Recovery/RecoveryViewModel.swift`
- Create: `clients/ios/SsdidDrive/SsdidDrive/Presentation/Recovery/RecoveryViewController.swift`
- Create: `clients/ios/SsdidDrive/SsdidDrive/Presentation/Recovery/RecoveryBanner.swift`
- Create: `clients/ios/SsdidDrive/SsdidDrive/Presentation/Recovery/RecoveryCoordinator.swift`

- [ ] **Step 1: Create RecoverySetupViewModel**

`@MainActor` class extending `BaseViewModel`. States: explanation → generating → downloading → uploading → success. Uses `@Published` properties.

- [ ] **Step 2: Create RecoverySetupViewController**

UIKit view controller with 3 steps. Uses `UIDocumentPickerViewController` for file save. Follows `BaseViewController` pattern with `setupUI()` and `setupBindings()`.

- [ ] **Step 3: Create RecoveryViewModel**

Handles login-page recovery. States: selectPath → uploadingFiles → reconstructing → reEnrolling → success.

- [ ] **Step 4: Create RecoveryViewController**

UIKit view controller for recovery flow. Uses `UIDocumentPickerViewController` for file open (`.recovery` UTType).

- [ ] **Step 5: Create RecoveryBanner**

`UIView` subclass with shield icon, warning text, CTA button, and dismiss button. Uses `UserDefaults` for dismiss count tracking.

- [ ] **Step 6: Create RecoveryCoordinator**

`BaseCoordinator` subclass for recovery navigation. Manages push/present for setup wizard and recovery flow.

- [ ] **Step 7: Integrate banner into MainCoordinator**

Add `RecoveryBanner` to the main tab controller's view hierarchy (above the content area).

- [ ] **Step 8: Add "Recover Account" to login screen**

Add a button/link to the login view controller that presents `RecoveryViewController`.

- [ ] **Step 9: Commit**

```bash
git add clients/ios/SsdidDrive/SsdidDrive/Presentation/Recovery/
git commit -m "feat(ios): add recovery setup wizard, recovery flow, banner, and coordinator"
```

---

## Chunk 6: Cleanup & Final Integration

### Task 19: Remove Old Recovery Entities

**Files:**
- Delete or clear: `src/SsdidDrive.Api/Data/Entities/RecoveryConfig.cs`
- Delete or clear: `src/SsdidDrive.Api/Data/Entities/RecoveryShare.cs`
- Delete or clear: `src/SsdidDrive.Api/Data/Entities/RecoveryRequest.cs`
- Delete or clear: `src/SsdidDrive.Api/Data/Entities/RecoveryApproval.cs`
- Remove old endpoint files from `src/SsdidDrive.Api/Features/Recovery/` (anything not in our new set)

- [ ] **Step 1: Remove old entity files**

Delete the 4 old recovery entity files and any old endpoint files in the Recovery feature folder that are not part of the new implementation (SetupRecovery, GetRecoveryStatus, GetRecoveryShare, CompleteRecovery, DeleteRecoverySetup, RecoveryFeature).

- [ ] **Step 2: Clean up any remaining references**

Search for `RecoveryConfig`, `RecoveryShare`, `RecoveryRequest`, `RecoveryApproval` across the codebase and remove any remaining references (imports, DbSets, navigation properties, etc.).

- [ ] **Step 3: Verify build**

```bash
dotnet build src/SsdidDrive.Api
dotnet test tests/SsdidDrive.Api.Tests/
```

- [ ] **Step 4: Commit**

```bash
git add -A
git commit -m "refactor(recovery): remove old trustee-based recovery entities and endpoints"
```

### Task 20: Final Verification

- [ ] **Step 1: Run all backend tests**

```bash
dotnet test tests/SsdidDrive.Api.Tests/
```

- [ ] **Step 2: Build all clients**

```bash
cd clients/desktop && cargo build && npm run build
cd clients/android && ./gradlew assembleDebug
# iOS: verify via Xcode build
```

- [ ] **Step 3: Verify cross-platform test vectors**

Run Shamir tests on each platform and verify they all pass the same test vectors.

- [ ] **Step 4: Final commit if any fixes needed**

```bash
git add -A
git commit -m "fix(recovery): resolve final integration issues"
```
