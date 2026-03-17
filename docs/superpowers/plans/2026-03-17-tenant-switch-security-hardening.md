# Tenant Switch Security Hardening — Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Treat tenant switching as a security boundary — issue new session tokens, revoke old ones, purge all local caches, and audit log every switch.

**Architecture:** Backend issues a new session token on switch and revokes the old one (eliminates cross-tenant token reuse). All clients purge local state (files, thumbnails, Spotlight, folder keys, notifications) to prevent data leakage between organizations. Upload-in-progress blocks switching.

**Tech Stack:** .NET 10 (backend), Swift/XCTest (iOS), Kotlin/JUnit (Android), React/Vitest (desktop)

---

## File Structure

### Backend (Chunk 1)
- Modify: `src/SsdidDrive.Api/Features/Users/SwitchTenant.cs` — Add token rotation + audit log
- Modify: `tests/SsdidDrive.Api.Tests/Integration/TenantMemberTests.cs` — Add switch tenant tests

### iOS Client (Chunk 2)
- Modify: `clients/ios/SsdidDrive/SsdidDrive/Data/Repository/TenantRepositoryImpl.swift` — Add cache purge on switch
- Modify: `clients/ios/SsdidDrive/SsdidDrive/Domain/Repository/TenantRepository.swift` — Add cache purge dependency
- Modify: `clients/ios/SsdidDrive/SsdidDrive/Core/DI/Container.swift` — Wire new dependencies to TenantRepository

### Android Client (Chunk 3)
- Modify: `clients/android/app/src/main/kotlin/my/ssdid/drive/data/repository/TenantRepositoryImpl.kt` — Add cache purge on switch

### Desktop Client (Chunk 4)
- Modify: `clients/desktop/src/stores/tenantStore.ts` — Add cache purge before reload

---

## Chunk 1: Backend — Token Rotation + Audit Logging

### Task 1: Backend — Issue new token and revoke old on tenant switch

**Files:**
- Modify: `src/SsdidDrive.Api/Features/Users/SwitchTenant.cs`
- Test: `tests/SsdidDrive.Api.Tests/Integration/TenantMemberTests.cs`

- [ ] **Step 1: Write the failing test — switch tenant returns new session token**

Add to `TenantMemberTests.cs`:

```csharp
[Fact]
public async Task SwitchTenant_ReturnsNewSessionToken()
{
    // Arrange: create user with two tenants
    var (client, userId) = await CreateAuthenticatedUser();
    var tenant2 = await CreateTenant("second-org");
    await AddUserToTenant(userId, tenant2.Id, TenantRole.Member);

    // Act: switch to second tenant
    var response = await client.PostAsync($"/api/me/switch-tenant/{tenant2.Id}", null);

    // Assert: response includes a new session_token
    response.EnsureSuccessStatusCode();
    var json = await response.Content.ReadFromJsonAsync<JsonElement>();
    Assert.True(json.TryGetProperty("session_token", out var tokenEl));
    Assert.False(string.IsNullOrEmpty(tokenEl.GetString()));
    Assert.Equal(tenant2.Id.ToString(), json.GetProperty("active_tenant_id").GetString());
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `dotnet test tests/SsdidDrive.Api.Tests/ --filter "SwitchTenant_ReturnsNewSessionToken" -v n`
Expected: FAIL — response does not contain `session_token`

- [ ] **Step 3: Write the failing test — old token is revoked after switch**

```csharp
[Fact]
public async Task SwitchTenant_RevokesOldToken()
{
    // Arrange
    var (client, userId) = await CreateAuthenticatedUser();
    var tenant2 = await CreateTenant("second-org");
    await AddUserToTenant(userId, tenant2.Id, TenantRole.Member);

    // Act: switch tenant — save old token, get new one
    var switchResponse = await client.PostAsync($"/api/me/switch-tenant/{tenant2.Id}", null);
    switchResponse.EnsureSuccessStatusCode();
    var json = await switchResponse.Content.ReadFromJsonAsync<JsonElement>();
    var newToken = json.GetProperty("session_token").GetString()!;

    // Assert: old token no longer works (client still uses old token)
    var filesResponse = await client.GetAsync("/api/files");
    Assert.Equal(HttpStatusCode.Unauthorized, filesResponse.StatusCode);

    // Assert: new token works
    client.DefaultRequestHeaders.Authorization =
        new System.Net.Http.Headers.AuthenticationHeaderValue("Bearer", newToken);
    var filesResponse2 = await client.GetAsync("/api/files");
    Assert.NotEqual(HttpStatusCode.Unauthorized, filesResponse2.StatusCode);
}
```

- [ ] **Step 4: Implement token rotation in SwitchTenant.cs**

Replace `SwitchTenant.cs` with:

```csharp
using Microsoft.EntityFrameworkCore;
using Ssdid.Sdk.Server.Session;
using SsdidDrive.Api.Common;
using SsdidDrive.Api.Data;
using SsdidDrive.Api.Services;

namespace SsdidDrive.Api.Features.Users;

public static class SwitchTenant
{
    public static void Map(RouteGroupBuilder group) =>
        group.MapPost("/me/switch-tenant/{tenantId:guid}", Handle);

    private static async Task<IResult> Handle(
        Guid tenantId,
        AppDbContext db,
        CurrentUserAccessor accessor,
        ISessionStore sessionStore,
        AuditService audit,
        CancellationToken ct)
    {
        var user = accessor.User!;
        var oldToken = accessor.SessionToken!;
        var oldTenantId = user.TenantId;

        var membership = await db.UserTenants
            .FirstOrDefaultAsync(ut => ut.UserId == user.Id && ut.TenantId == tenantId, ct);

        if (membership is null)
            return AppError.Forbidden("You are not a member of this tenant").ToProblemResult();

        // Update active tenant
        user.TenantId = tenantId;
        user.UpdatedAt = DateTimeOffset.UtcNow;
        await db.SaveChangesAsync(ct);

        // Issue new session token for the new tenant context
        var newToken = sessionStore.CreateSession(user.Id.ToString());
        if (newToken is null)
            return AppError.ServiceUnavailable("Session limit reached, try again later").ToProblemResult();

        // Revoke old session token (after new one is confirmed created)
        sessionStore.DeleteSession(oldToken);

        // Audit log
        await audit.LogAsync(
            user.Id,
            "tenant_switch",
            targetType: "tenant",
            targetId: tenantId,
            details: $"Switched from tenant {oldTenantId} to {tenantId}",
            ct: ct);

        return Results.Ok(new
        {
            active_tenant_id = tenantId,
            role = membership.Role.ToString().ToLowerInvariant(),
            session_token = newToken
        });
    }
}
```

Key design decisions:
- New token created BEFORE old token is revoked (prevents lockout if crash occurs between)
- Audit log captures both old and new tenant IDs for compliance tracing
- Session token returned in response so clients can save it atomically

- [ ] **Step 5: Run tests to verify they pass**

Run: `dotnet test tests/SsdidDrive.Api.Tests/ --filter "SwitchTenant" -v n`
Expected: PASS

- [ ] **Step 6: Write test — non-member cannot switch**

```csharp
[Fact]
public async Task SwitchTenant_NonMember_Returns403()
{
    var (client, _) = await CreateAuthenticatedUser();
    var tenant2 = await CreateTenant("other-org");
    // User is NOT added to tenant2

    var response = await client.PostAsync($"/api/me/switch-tenant/{tenant2.Id}", null);
    Assert.Equal(HttpStatusCode.Forbidden, response.StatusCode);
}
```

- [ ] **Step 7: Run all tests**

Run: `dotnet test tests/SsdidDrive.Api.Tests/ -v n`
Expected: ALL PASS

- [ ] **Step 8: Commit**

```bash
git add src/SsdidDrive.Api/Features/Users/SwitchTenant.cs tests/
git commit -m "feat: issue new session token on tenant switch + audit log

Security hardening: revoke old token, issue new one, and write audit
log entry on every tenant switch. Prevents cross-tenant session reuse."
```

---

## Chunk 2: iOS Client — Cache Purge on Tenant Switch

### Task 2: iOS — Purge all local caches on tenant switch

The iOS client already calls `switchTenant()` in `TenantRepositoryImpl`. We need to add cache purge calls after a successful switch.

**Files:**
- Modify: `clients/ios/SsdidDrive/SsdidDrive/Data/Repository/TenantRepositoryImpl.swift`
- Modify: `clients/ios/SsdidDrive/SsdidDrive/Core/DI/Container.swift` (inject dependencies)

- [ ] **Step 1: Add cache dependencies to TenantRepositoryImpl**

In `TenantRepositoryImpl.swift`, add properties for cache clearing:

```swift
private let thumbnailCache: ThumbnailCache
private let spotlightIndexer: SpotlightIndexer
private let fileRepository: FileRepository
```

Update `init`:

```swift
init(apiClient: APIClient, keychainManager: KeychainManager,
     thumbnailCache: ThumbnailCache, spotlightIndexer: SpotlightIndexer,
     fileRepository: FileRepository) {
    self.apiClient = apiClient
    self.keychainManager = keychainManager
    self.thumbnailCache = thumbnailCache
    self.spotlightIndexer = spotlightIndexer
    self.fileRepository = fileRepository
}
```

- [ ] **Step 2: Add cache purge after successful switch in switchTenant()**

After `try keychainManager.saveTokensWithTenantContext(...)` and before creating the new context, add:

```swift
// SECURITY: Purge all tenant-specific local data to prevent cross-org leakage
thumbnailCache.clearCache()
spotlightIndexer.clearAllIndexes()
try? fileRepository.clearDownloadCache()

// Clear shared keychain keys (File Provider extension)
keychainManager.clearSharedKemKeys()

// Notify File Provider to invalidate
// (FileProviderDomainManager will re-enumerate for new tenant)
```

- [ ] **Step 3: Update Container.swift to wire new dependencies**

In `Container.swift`, update the `TenantRepositoryImpl` initialization to pass the additional dependencies:

```swift
lazy var tenantRepository: TenantRepository = TenantRepositoryImpl(
    apiClient: apiClient,
    keychainManager: keychainManager,
    thumbnailCache: thumbnailCache,
    spotlightIndexer: spotlightIndexer,
    fileRepository: fileRepository
)
```

- [ ] **Step 4: Update the response model to read session_token**

Find the `TenantSwitchResponse` model and ensure it decodes `session_token` from the backend (in addition to `access_token` which may have been the old field name). The backend now returns `session_token` instead of `access_token`:

```swift
struct TenantSwitchData: Codable {
    let currentTenantId: String
    let role: String
    let sessionToken: String

    enum CodingKeys: String, CodingKey {
        case currentTenantId = "active_tenant_id"
        case role
        case sessionToken = "session_token"
    }

    var userRole: UserRole {
        UserRole(rawValue: role) ?? .member
    }
}
```

Update `saveTokensWithTenantContext` call to use `sessionToken`:

```swift
try keychainManager.saveTokensWithTenantContext(
    accessToken: response.data.sessionToken,
    refreshToken: "",  // session-based auth, no refresh token
    tenantId: response.data.currentTenantId,
    role: response.data.role
)
```

- [ ] **Step 5: Build and verify**

Build in Xcode. Verify no compile errors.

- [ ] **Step 6: Commit**

```bash
git add clients/ios/
git commit -m "feat(ios): purge all local caches on tenant switch

Clear thumbnail cache, Spotlight index, download cache, and shared
keychain KEM keys when switching organizations. Prevents cross-tenant
data leakage. Updates response model for new session_token field."
```

---

### Task 3: iOS — Block tenant switch during active upload

**Files:**
- Modify: `clients/ios/SsdidDrive/SsdidDrive/Presentation/Settings/TenantSwitcherView.swift`

- [ ] **Step 1: Add upload-in-progress check to TenantSwitcherView**

Before calling `switchTenant`, check if any upload is active. The exact mechanism depends on how the upload manager exposes state. Add a guard:

```swift
// In the switch action handler:
if uploadManager.hasActiveUploads {
    // Show alert
    showAlert(
        title: "Upload in Progress",
        message: "Please wait for the upload to complete or cancel it before switching organizations."
    )
    return
}
```

If `uploadManager` is not accessible from this view, inject it or check via a repository method.

- [ ] **Step 2: Commit**

```bash
git add clients/ios/
git commit -m "feat(ios): block tenant switch during active upload

Show alert when user tries to switch tenants while a file upload is
in progress. Prevents upload to wrong tenant."
```

---

## Chunk 3: Android Client — Cache Purge on Tenant Switch

### Task 4: Android — Purge all local caches on tenant switch

The Android client already clears `folderKeyManager.clearCache()` on switch. We need to add thumbnail cache, download cache, and notification clearing.

**Files:**
- Modify: `clients/android/app/src/main/kotlin/my/ssdid/drive/data/repository/TenantRepositoryImpl.kt`

- [ ] **Step 1: Add cache purge calls after successful switch**

In `switchTenant()`, after `folderKeyManager.clearCache()`, add:

```kotlin
// SECURITY: Purge all tenant-specific local data
folderKeyManager.clearCache()          // Already exists
thumbnailCache.evictAll()              // Add
downloadCache.clearAll()               // Add
notificationRepository.clearLocal()    // Add
```

Ensure these dependencies are injected via Hilt constructor.

- [ ] **Step 2: Update response model for session_token**

Update `TenantSwitchData` in `AuthDto.kt` to read `session_token` instead of `access_token`:

```kotlin
data class TenantSwitchData(
    @SerializedName("active_tenant_id") val currentTenantId: String,
    val role: String,
    @SerializedName("session_token") val sessionToken: String
)
```

Update the `saveTokensWithTenantContext` call to use `data.sessionToken`.

- [ ] **Step 3: Block switch during active upload**

In `TenantSwitcherViewModel`, check `uploadManager.hasActiveUploads` before calling `switchTenant`. Show a Snackbar/dialog if blocked.

- [ ] **Step 4: Run tests**

Run: `cd clients/android && ./gradlew test`
Expected: ALL PASS

- [ ] **Step 5: Commit**

```bash
git add clients/android/
git commit -m "feat(android): purge all local caches on tenant switch

Clear thumbnail cache, download cache, and notifications when switching
organizations. Block switch during active uploads. Update response
model for new session_token field."
```

---

## Chunk 4: Desktop Client — Cache Purge + Response Update

### Task 5: Desktop — Update tenant switch response handling

The desktop client already does `window.location.reload()` which clears all in-memory state. We just need to update the response model and ensure the Tauri backend handles the new `session_token` field.

**Files:**
- Modify: `clients/desktop/src/stores/tenantStore.ts`

- [ ] **Step 1: Update TenantSwitchResponse interface**

```typescript
interface TenantSwitchResponse {
  active_tenant_id: string;
  role: string;
  session_token: string;
}
```

- [ ] **Step 2: Update switchTenant to save new token**

```typescript
switchTenant: async (tenantId) => {
  set({ isSwitching: true, error: null });
  try {
    const response = await invoke<TenantSwitchResponse>('switch_tenant', { tenantId });

    // Save new session token
    const { setToken } = useAuthStore.getState();
    setToken(response.session_token);

    set({
      currentTenantId: tenantId,
      isSwitching: false,
    });

    // Full reload clears all in-memory state
    window.location.reload();
  } catch (error) {
    set({ isSwitching: false, error: String(error) });
  }
}
```

- [ ] **Step 3: Block switch during active upload**

Add a check before the `invoke` call:

```typescript
const { uploads } = useFileStore.getState();
if (uploads.some(u => u.status === 'uploading')) {
  set({ error: 'Please wait for uploads to complete before switching organizations.' });
  return;
}
```

- [ ] **Step 4: Run tests**

Run: `cd clients/desktop && npm test`
Expected: ALL PASS (may need to update `tenantStore.test.ts` to mock new response shape)

- [ ] **Step 5: Commit**

```bash
git add clients/desktop/
git commit -m "feat(desktop): update tenant switch for new session token + upload guard

Handle session_token from backend response. Block switch during active
uploads. Full page reload already clears all local state."
```

---

## Verification

After all tasks, run the full test suites:

```bash
# Backend
dotnet test tests/SsdidDrive.Api.Tests/ -v n

# iOS
xcodebuild test -scheme SsdidDrive

# Android
cd clients/android && ./gradlew test

# Desktop
cd clients/desktop && npm test
```

### Manual Test Checklist

- [ ] Switch tenant → old token returns 401
- [ ] Switch tenant → new token works for API calls
- [ ] Switch tenant → audit log entry created
- [ ] Switch tenant → thumbnails cleared (iOS/Android)
- [ ] Switch tenant → Spotlight results gone (iOS)
- [ ] Switch tenant → downloaded files inaccessible
- [ ] Switch tenant during upload → blocked with message
- [ ] Switch to non-member tenant → 403 error
- [ ] Kill app during switch → next launch recovers (iOS transaction markers)
- [ ] Rapid switch A→B→A → no stale data
