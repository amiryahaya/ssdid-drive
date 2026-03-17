# Push Notifications + Admin Broadcast — Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Enable server-side push notifications via OneSignal for all notification events (shares, invites, etc.), and add admin portal capability to send notifications to specific users, organizations, or broadcast to all.

**Architecture:** Backend integrates with OneSignal REST API to send pushes whenever in-app notifications are created. A new `PushService` wraps the OneSignal API. Admin gets new endpoints + UI for composing and sending targeted or broadcast notifications. A `NotificationLog` entity tracks all sent messages for audit.

**Tech Stack:** .NET 10 (backend), OneSignal REST API v1, React/TypeScript (admin portal)

---

## File Structure

### Chunk 1: Backend Push Infrastructure
- Add field: `Data/Entities/Device.cs` — `PushPlayerId` column
- Create migration: `dotnet ef migrations add AddDevicePushPlayerId`
- Create: `Services/PushService.cs` — OneSignal REST API client
- Modify: `Services/NotificationService.cs` — call PushService after creating in-app notification
- Modify: `appsettings.json` — add `OneSignal:AppId` + `OneSignal:ApiKey`
- Modify: `Program.cs` — register PushService in DI

### Chunk 2: Push Registration Endpoints
- Create: `Features/Devices/RegisterPush.cs` — `POST /api/devices/{id}/push`
- Create: `Features/Devices/UnregisterPush.cs` — `DELETE /api/devices/{id}/push`

### Chunk 3: Admin Notification Endpoints + Log Entity
- Create: `Data/Entities/NotificationLog.cs` — sent message log entity
- Create migration: `dotnet ef migrations add AddNotificationLog`
- Modify: `Data/AppDbContext.cs` — add `NotificationLogs` DbSet
- Create: `Features/Admin/SendNotification.cs` — `POST /api/admin/notifications`
- Create: `Features/Admin/ListNotificationLog.cs` — `GET /api/admin/notifications`

### Chunk 4: Admin Portal UI
- Modify: `clients/admin/src/stores/adminStore.ts` — add notification actions
- Create: `clients/admin/src/pages/NotificationsPage.tsx` — compose + send + log
- Create: `clients/admin/src/components/SendNotificationDialog.tsx` — compose dialog
- Modify: `clients/admin/src/components/Sidebar.tsx` — add Notifications nav link
- Modify: `clients/admin/src/App.tsx` — add route

---

## Chunk 1: Backend Push Infrastructure

### Task 1: Add PushPlayerId to Device entity + migration

**Files:**
- Modify: `src/SsdidDrive.Api/Data/Entities/Device.cs`

- [ ] **Step 1: Add PushPlayerId field to Device entity**

```csharp
// Add to Device.cs:
public string? PushPlayerId { get; set; }
```

- [ ] **Step 2: Create EF migration**

Run: `dotnet ef migrations add AddDevicePushPlayerId --project src/SsdidDrive.Api`

- [ ] **Step 3: Commit**

```bash
git add src/SsdidDrive.Api/Data/ src/SsdidDrive.Api/Migrations/
git commit -m "feat: add PushPlayerId column to Device entity"
```

---

### Task 2: Create PushService (OneSignal REST API client)

**Files:**
- Create: `src/SsdidDrive.Api/Services/PushService.cs`
- Modify: `src/SsdidDrive.Api/appsettings.json`
- Modify: `src/SsdidDrive.Api/Program.cs`

- [ ] **Step 1: Add OneSignal config to appsettings.json**

```json
"OneSignal": {
  "AppId": "",
  "ApiKey": ""
}
```

- [ ] **Step 2: Create PushService**

```csharp
using System.Text.Json;
using Microsoft.Extensions.Options;

namespace SsdidDrive.Api.Services;

public class OneSignalOptions
{
    public string AppId { get; set; } = string.Empty;
    public string ApiKey { get; set; } = string.Empty;
}

public class PushService
{
    private readonly HttpClient _httpClient;
    private readonly OneSignalOptions _options;
    private readonly ILogger<PushService> _logger;
    private bool _enabled;

    public PushService(HttpClient httpClient, IOptions<OneSignalOptions> options, ILogger<PushService> logger)
    {
        _httpClient = httpClient;
        _options = options.Value;
        _logger = logger;
        _enabled = !string.IsNullOrEmpty(_options.AppId) && !string.IsNullOrEmpty(_options.ApiKey);

        if (_enabled)
        {
            _httpClient.BaseAddress = new Uri("https://api.onesignal.com/");
            _httpClient.DefaultRequestHeaders.Add("Authorization", $"Key {_options.ApiKey}");
        }
    }

    /// Send push notification to specific users by their external user IDs (our User.Id).
    public async Task SendToUsersAsync(
        IReadOnlyList<string> externalUserIds,
        string title,
        string message,
        string? actionType = null,
        string? resourceId = null,
        CancellationToken ct = default)
    {
        if (!_enabled || externalUserIds.Count == 0) return;

        var payload = new
        {
            app_id = _options.AppId,
            include_aliases = new { external_id = externalUserIds },
            target_channel = "push",
            headings = new { en = title },
            contents = new { en = message },
            data = new Dictionary<string, string?>
            {
                ["action_type"] = actionType,
                ["resource_id"] = resourceId
            }
        };

        try
        {
            var response = await _httpClient.PostAsJsonAsync("notifications", payload, ct);
            if (!response.IsSuccessStatusCode)
            {
                var body = await response.Content.ReadAsStringAsync(ct);
                _logger.LogWarning("OneSignal push failed ({Status}): {Body}",
                    response.StatusCode, body);
            }
        }
        catch (Exception ex)
        {
            // Push failure should never block the main operation
            _logger.LogError(ex, "Failed to send push notification via OneSignal");
        }
    }

    /// Send push to all subscribed users (broadcast).
    public async Task BroadcastAsync(
        string title,
        string message,
        string? actionType = null,
        string? resourceId = null,
        CancellationToken ct = default)
    {
        if (!_enabled) return;

        var payload = new
        {
            app_id = _options.AppId,
            included_segments = new[] { "Subscribed Users" },
            headings = new { en = title },
            contents = new { en = message },
            data = new Dictionary<string, string?>
            {
                ["action_type"] = actionType,
                ["resource_id"] = resourceId
            }
        };

        try
        {
            var response = await _httpClient.PostAsJsonAsync("notifications", payload, ct);
            if (!response.IsSuccessStatusCode)
            {
                var body = await response.Content.ReadAsStringAsync(ct);
                _logger.LogWarning("OneSignal broadcast failed ({Status}): {Body}",
                    response.StatusCode, body);
            }
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Failed to broadcast push notification via OneSignal");
        }
    }
}
```

- [ ] **Step 3: Register in Program.cs**

```csharp
builder.Services.Configure<OneSignalOptions>(builder.Configuration.GetSection("OneSignal"));
builder.Services.AddHttpClient<PushService>();
```

- [ ] **Step 4: Commit**

```bash
git add src/SsdidDrive.Api/Services/PushService.cs src/SsdidDrive.Api/appsettings.json src/SsdidDrive.Api/Program.cs
git commit -m "feat: add PushService for OneSignal REST API integration"
```

---

### Task 3: Integrate PushService into NotificationService

**Files:**
- Modify: `src/SsdidDrive.Api/Services/NotificationService.cs`

- [ ] **Step 1: Add PushService dependency and fire push after creating in-app notification**

Update `NotificationService` to accept `PushService` and call it after creating the notification:

```csharp
public class NotificationService(AppDbContext db, PushService pushService)
{
    public async Task CreateAsync(
        Guid userId, string type, string title, string message,
        string? actionType = null, string? actionResourceId = null,
        CancellationToken ct = default)
    {
        // Existing: create in-app notification
        db.Notifications.Add(new Notification
        {
            Id = Guid.NewGuid(),
            UserId = userId,
            Type = type,
            Title = title,
            Message = message,
            ActionType = actionType,
            ActionResourceId = actionResourceId,
            CreatedAt = DateTimeOffset.UtcNow
        });
        // Note: caller saves changes

        // NEW: fire push notification (fire-and-forget, non-blocking)
        _ = pushService.SendToUsersAsync(
            [userId.ToString()], title, message, actionType, actionResourceId, ct);
    }
}
```

Key design: push is fire-and-forget. If OneSignal is down, the in-app notification still works.

- [ ] **Step 2: Commit**

```bash
git add src/SsdidDrive.Api/Services/NotificationService.cs
git commit -m "feat: send push notification via OneSignal when creating in-app notifications"
```

---

## Chunk 2: Push Registration Endpoints

### Task 4: Create push registration/unregistration endpoints

These endpoints let clients register their OneSignal player ID with a device enrollment.

**Files:**
- Create: `src/SsdidDrive.Api/Features/Devices/RegisterPush.cs`
- Create: `src/SsdidDrive.Api/Features/Devices/UnregisterPush.cs`
- Modify: `src/SsdidDrive.Api/Features/Devices/DeviceFeature.cs` — map new endpoints

- [ ] **Step 1: Read DeviceFeature.cs to understand existing endpoint mapping pattern**

- [ ] **Step 2: Create RegisterPush.cs**

```csharp
using Microsoft.EntityFrameworkCore;
using SsdidDrive.Api.Common;
using SsdidDrive.Api.Data;

namespace SsdidDrive.Api.Features.Devices;

public static class RegisterPush
{
    public record Request(string PlayerId);

    public static void Map(RouteGroupBuilder group) =>
        group.MapPost("/{deviceId:guid}/push", Handle);

    private static async Task<IResult> Handle(
        Guid deviceId, Request req,
        AppDbContext db, CurrentUserAccessor accessor, CancellationToken ct)
    {
        var device = await db.Devices
            .FirstOrDefaultAsync(d => d.Id == deviceId && d.UserId == accessor.UserId, ct);

        if (device is null)
            return AppError.NotFound("Device not found").ToProblemResult();

        if (string.IsNullOrWhiteSpace(req.PlayerId))
            return AppError.Validation("player_id is required").ToProblemResult();

        device.PushPlayerId = req.PlayerId.Trim();
        await db.SaveChangesAsync(ct);

        return Results.NoContent();
    }
}
```

- [ ] **Step 3: Create UnregisterPush.cs**

```csharp
using Microsoft.EntityFrameworkCore;
using SsdidDrive.Api.Common;
using SsdidDrive.Api.Data;

namespace SsdidDrive.Api.Features.Devices;

public static class UnregisterPush
{
    public static void Map(RouteGroupBuilder group) =>
        group.MapDelete("/{deviceId:guid}/push", Handle);

    private static async Task<IResult> Handle(
        Guid deviceId,
        AppDbContext db, CurrentUserAccessor accessor, CancellationToken ct)
    {
        var device = await db.Devices
            .FirstOrDefaultAsync(d => d.Id == deviceId && d.UserId == accessor.UserId, ct);

        if (device is null)
            return AppError.NotFound("Device not found").ToProblemResult();

        device.PushPlayerId = null;
        await db.SaveChangesAsync(ct);

        return Results.NoContent();
    }
}
```

- [ ] **Step 4: Map endpoints in DeviceFeature.cs**

Add to the Map method:
```csharp
RegisterPush.Map(group);
UnregisterPush.Map(group);
```

- [ ] **Step 5: Commit**

```bash
git add src/SsdidDrive.Api/Features/Devices/
git commit -m "feat: add push player ID registration/unregistration endpoints"
```

---

## Chunk 3: Admin Notification Endpoints + Log

### Task 5: Create NotificationLog entity + admin send endpoint

**Files:**
- Create: `src/SsdidDrive.Api/Data/Entities/NotificationLog.cs`
- Modify: `src/SsdidDrive.Api/Data/AppDbContext.cs`
- Create: `src/SsdidDrive.Api/Features/Admin/SendNotification.cs`
- Create: `src/SsdidDrive.Api/Features/Admin/ListNotificationLog.cs`

- [ ] **Step 1: Create NotificationLog entity**

```csharp
namespace SsdidDrive.Api.Data.Entities;

public class NotificationLog
{
    public Guid Id { get; set; }
    public Guid SentById { get; set; }           // Admin who sent it
    public string Scope { get; set; } = string.Empty;  // "user", "tenant", "broadcast"
    public Guid? TargetId { get; set; }          // User ID or Tenant ID (null for broadcast)
    public string Title { get; set; } = string.Empty;
    public string Message { get; set; } = string.Empty;
    public int RecipientCount { get; set; }
    public DateTimeOffset CreatedAt { get; set; }

    public User SentBy { get; set; } = null!;
}
```

- [ ] **Step 2: Add DbSet to AppDbContext**

```csharp
public DbSet<NotificationLog> NotificationLogs => Set<NotificationLog>();
```

- [ ] **Step 3: Create migration**

Run: `dotnet ef migrations add AddNotificationLog --project src/SsdidDrive.Api`

- [ ] **Step 4: Create SendNotification.cs**

```csharp
using Microsoft.EntityFrameworkCore;
using SsdidDrive.Api.Common;
using SsdidDrive.Api.Data;
using SsdidDrive.Api.Data.Entities;
using SsdidDrive.Api.Services;

namespace SsdidDrive.Api.Features.Admin;

public static class SendNotification
{
    public record Request(string Scope, Guid? TargetId, string Title, string Message);

    public static void Map(RouteGroupBuilder group) =>
        group.MapPost("/notifications", Handle);

    private static async Task<IResult> Handle(
        Request req,
        AppDbContext db,
        CurrentUserAccessor accessor,
        NotificationService notificationService,
        PushService pushService,
        AuditService audit,
        CancellationToken ct)
    {
        if (string.IsNullOrWhiteSpace(req.Title) || string.IsNullOrWhiteSpace(req.Message))
            return AppError.Validation("Title and message are required").ToProblemResult();

        var adminId = accessor.UserId;
        List<Guid> recipientIds;

        switch (req.Scope.ToLowerInvariant())
        {
            case "user":
                if (req.TargetId is null)
                    return AppError.Validation("target_id is required for user scope").ToProblemResult();
                var userExists = await db.Users.AnyAsync(u => u.Id == req.TargetId, ct);
                if (!userExists)
                    return AppError.NotFound("User not found").ToProblemResult();
                recipientIds = [req.TargetId.Value];
                break;

            case "tenant":
                if (req.TargetId is null)
                    return AppError.Validation("target_id is required for tenant scope").ToProblemResult();
                recipientIds = await db.UserTenants
                    .Where(ut => ut.TenantId == req.TargetId)
                    .Select(ut => ut.UserId)
                    .ToListAsync(ct);
                if (recipientIds.Count == 0)
                    return AppError.NotFound("Tenant has no members").ToProblemResult();
                break;

            case "broadcast":
                recipientIds = await db.Users
                    .Where(u => u.Status == UserStatus.Active)
                    .Select(u => u.Id)
                    .ToListAsync(ct);
                break;

            default:
                return AppError.Validation("Scope must be 'user', 'tenant', or 'broadcast'").ToProblemResult();
        }

        // Create in-app notifications for all recipients
        foreach (var userId in recipientIds)
        {
            await notificationService.CreateAsync(
                userId, "admin_announcement", req.Title, req.Message, ct: ct);
        }

        // Log the sent message
        db.NotificationLogs.Add(new NotificationLog
        {
            Id = Guid.NewGuid(),
            SentById = adminId,
            Scope = req.Scope.ToLowerInvariant(),
            TargetId = req.TargetId,
            Title = req.Title,
            Message = req.Message,
            RecipientCount = recipientIds.Count,
            CreatedAt = DateTimeOffset.UtcNow
        });

        await db.SaveChangesAsync(ct);

        // Send push notifications (fire-and-forget)
        if (req.Scope == "broadcast")
        {
            _ = pushService.BroadcastAsync(req.Title, req.Message, ct: ct);
        }
        else
        {
            _ = pushService.SendToUsersAsync(
                recipientIds.Select(id => id.ToString()).ToList(),
                req.Title, req.Message, ct: ct);
        }

        // Audit log
        await audit.LogAsync(adminId, "admin_notification_sent",
            details: $"Scope: {req.Scope}, recipients: {recipientIds.Count}, title: {req.Title}",
            ct: ct);

        return Results.Ok(new { recipients = recipientIds.Count });
    }
}
```

- [ ] **Step 5: Create ListNotificationLog.cs**

```csharp
using Microsoft.EntityFrameworkCore;
using SsdidDrive.Api.Common;
using SsdidDrive.Api.Data;

namespace SsdidDrive.Api.Features.Admin;

public static class ListNotificationLog
{
    public static void Map(RouteGroupBuilder group) =>
        group.MapGet("/notifications", Handle);

    private static async Task<IResult> Handle(
        AppDbContext db,
        int page = 1, int pageSize = 20,
        CancellationToken ct = default)
    {
        var pagination = new PaginationParams(page, pageSize);

        var total = await db.NotificationLogs.CountAsync(ct);

        var items = await db.NotificationLogs
            .OrderByDescending(n => n.CreatedAt)
            .Skip(pagination.Skip)
            .Take(pagination.Take)
            .Include(n => n.SentBy)
            .Select(n => new
            {
                n.Id,
                n.Scope,
                n.TargetId,
                n.Title,
                n.Message,
                n.RecipientCount,
                n.CreatedAt,
                SentByName = n.SentBy.DisplayName ?? n.SentBy.Did
            })
            .ToListAsync(ct);

        return Results.Ok(new PagedResponse<object>(items, total, pagination.NormalizedPage, pagination.Take));
    }
}
```

- [ ] **Step 6: Map endpoints in AdminFeature.cs**

Add:
```csharp
SendNotification.Map(group);
ListNotificationLog.Map(group);
```

- [ ] **Step 7: Commit**

```bash
git add src/SsdidDrive.Api/Data/ src/SsdidDrive.Api/Features/Admin/ src/SsdidDrive.Api/Migrations/
git commit -m "feat: admin notification sending with user/tenant/broadcast scope + message log"
```

---

## Chunk 4: Admin Portal UI

### Task 6: Admin portal notifications page

**Files:**
- Create: `clients/admin/src/pages/NotificationsPage.tsx`
- Create: `clients/admin/src/components/SendNotificationDialog.tsx`
- Modify: `clients/admin/src/stores/adminStore.ts`
- Modify: `clients/admin/src/components/Sidebar.tsx`
- Modify: `clients/admin/src/App.tsx`

- [ ] **Step 1: Add notification actions to adminStore.ts**

```typescript
// Types
interface NotificationLog {
  id: string
  scope: string
  target_id: string | null
  title: string
  message: string
  recipient_count: number
  created_at: string
  sent_by_name: string
}

// State
notificationLogs: NotificationLog[]
notificationLogsLoading: boolean

// Actions
sendNotification: (scope: string, targetId: string | null, title: string, message: string) => Promise<{ recipients: number }>
fetchNotificationLogs: (page: number, pageSize: number) => Promise<void>
```

- [ ] **Step 2: Create SendNotificationDialog.tsx**

Dialog with:
- Scope selector: "Specific User" | "Organization" | "Broadcast to All"
- Target field: user search (when user scope) or tenant selector (when tenant scope)
- Title input
- Message textarea
- Send button with confirmation
- Success message showing recipient count

- [ ] **Step 3: Create NotificationsPage.tsx**

Page with:
- "Send Notification" button (opens dialog)
- Table showing notification log: date, sender, scope, title, message preview, recipient count
- Pagination
- Scope badge (user/tenant/broadcast) with color coding

- [ ] **Step 4: Add navigation link in Sidebar.tsx**

Add "Notifications" link with bell icon between "Audit Log" and any existing items.

- [ ] **Step 5: Add route in App.tsx**

```tsx
<Route path="/notifications" element={<NotificationsPage />} />
```

- [ ] **Step 6: Run tests**

Run: `cd clients/admin && npm test`

- [ ] **Step 7: Commit**

```bash
git add clients/admin/
git commit -m "feat(admin): notification sending UI with user/tenant/broadcast scope + message log"
```

---

## Verification

After all tasks:

```bash
# Backend build
dotnet build src/SsdidDrive.Api

# Backend tests
dotnet test tests/SsdidDrive.Api.Tests/ -v n

# Admin portal tests
cd clients/admin && npm test
```

### Manual Test Checklist

- [ ] Configure OneSignal App ID + API Key in appsettings/env
- [ ] Share a file → recipient gets push notification
- [ ] Create invitation → invitee gets push notification
- [ ] Admin sends to specific user → user gets in-app + push
- [ ] Admin sends to organization → all members get notification
- [ ] Admin broadcasts → all active users get notification
- [ ] Notification log shows all sent messages with sender, scope, count
- [ ] Push failure does NOT block in-app notification creation
- [ ] OneSignal not configured → push silently skipped, in-app still works
