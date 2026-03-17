using System.Net;
using System.Net.Http.Json;
using System.Text.Json;
using Microsoft.Extensions.DependencyInjection;
using SsdidDrive.Api.Data;
using SsdidDrive.Api.Data.Entities;
using SsdidDrive.Api.Tests.Infrastructure;

namespace SsdidDrive.Api.Tests.Integration;

public class NotificationTests : IClassFixture<SsdidDriveFactory>
{
    private readonly SsdidDriveFactory _factory;

    public NotificationTests(SsdidDriveFactory factory) => _factory = factory;

    private async Task<Guid> CreateNotificationAsync(
        SsdidDriveFactory factory, Guid userId,
        string type = "test", string title = "Test", string message = "Test message",
        bool isRead = false)
    {
        using var scope = factory.Services.CreateScope();
        var db = scope.ServiceProvider.GetRequiredService<AppDbContext>();
        var notification = new Notification
        {
            Id = Guid.NewGuid(),
            UserId = userId,
            Type = type,
            Title = title,
            Message = message,
            IsRead = isRead,
            CreatedAt = DateTimeOffset.UtcNow
        };
        db.Notifications.Add(notification);
        await db.SaveChangesAsync();
        return notification.Id;
    }

    // ── 1. List notifications → 200 ─────────────────────────────────────

    [Fact]
    public async Task ListNotifications_ReturnsSeededNotifications()
    {
        var (client, userId, _) = await TestFixture.CreateAuthenticatedClientAsync(_factory, "NotifList");

        await CreateNotificationAsync(_factory, userId, title: "Notif 1");
        await CreateNotificationAsync(_factory, userId, title: "Notif 2");

        var response = await client.GetAsync("/api/notifications");
        Assert.Equal(HttpStatusCode.OK, response.StatusCode);

        var body = await response.Content.ReadFromJsonAsync<JsonElement>(TestFixture.Json);
        var items = body.GetProperty("items");
        Assert.True(items.GetArrayLength() >= 2);
    }

    // ── 2. List with unread_only filter → only unread ────────────────────

    [Fact]
    public async Task ListNotifications_UnreadOnly_FiltersCorrectly()
    {
        var (client, userId, _) = await TestFixture.CreateAuthenticatedClientAsync(_factory, "NotifUnread");

        await CreateNotificationAsync(_factory, userId, title: "Unread 1", isRead: false);
        await CreateNotificationAsync(_factory, userId, title: "Read 1", isRead: true);
        await CreateNotificationAsync(_factory, userId, title: "Unread 2", isRead: false);

        var response = await client.GetAsync("/api/notifications?unread_only=true");
        Assert.Equal(HttpStatusCode.OK, response.StatusCode);

        var body = await response.Content.ReadFromJsonAsync<JsonElement>(TestFixture.Json);
        var items = body.GetProperty("items");
        // Should have exactly 2 unread notifications
        Assert.Equal(2, items.GetArrayLength());

        for (int i = 0; i < items.GetArrayLength(); i++)
        {
            Assert.False(items[i].GetProperty("is_read").GetBoolean());
        }
    }

    // ── 3. Get unread count → correct count ──────────────────────────────

    [Fact]
    public async Task GetUnreadCount_ReturnsCorrectCount()
    {
        var (client, userId, _) = await TestFixture.CreateAuthenticatedClientAsync(_factory, "NotifCount");

        await CreateNotificationAsync(_factory, userId, isRead: false);
        await CreateNotificationAsync(_factory, userId, isRead: false);
        await CreateNotificationAsync(_factory, userId, isRead: true);

        var response = await client.GetAsync("/api/notifications/unread-count");
        Assert.Equal(HttpStatusCode.OK, response.StatusCode);

        var body = await response.Content.ReadFromJsonAsync<JsonElement>(TestFixture.Json);
        Assert.Equal(2, body.GetProperty("count").GetInt32());
    }

    // ── 4. Mark as read → 200 ────────────────────────────────────────────

    [Fact]
    public async Task MarkAsRead_ReturnsOk()
    {
        var (client, userId, _) = await TestFixture.CreateAuthenticatedClientAsync(_factory, "NotifMarkRead");

        var notifId = await CreateNotificationAsync(_factory, userId);

        var response = await client.PatchAsync($"/api/notifications/{notifId}/read", null);
        Assert.Equal(HttpStatusCode.OK, response.StatusCode);

        // Verify it's now read
        var listResp = await client.GetAsync("/api/notifications?unread_only=true");
        var body = await listResp.Content.ReadFromJsonAsync<JsonElement>(TestFixture.Json);
        var items = body.GetProperty("items");
        var ids = Enumerable.Range(0, items.GetArrayLength())
            .Select(i => items[i].GetProperty("id").GetGuid())
            .ToList();
        Assert.DoesNotContain(notifId, ids);
    }

    // ── 5. Mark as read non-owner → 404 ──────────────────────────────────

    [Fact]
    public async Task MarkAsRead_NonOwner_ReturnsNotFound()
    {
        var (client1, userId1, tenantId) = await TestFixture.CreateAuthenticatedClientAsync(_factory, "NotifOwner");
        var (client2, _) = await TestFixture.CreateUserInTenantAsync(_factory, tenantId, "NotifNonOwner");

        var notifId = await CreateNotificationAsync(_factory, userId1);

        var response = await client2.PatchAsync($"/api/notifications/{notifId}/read", null);
        Assert.Equal(HttpStatusCode.NotFound, response.StatusCode);
    }

    // ── 6. Mark all as read → 200, count returned ────────────────────────

    [Fact]
    public async Task MarkAllAsRead_ReturnsCount()
    {
        var (client, userId, _) = await TestFixture.CreateAuthenticatedClientAsync(_factory, "NotifMarkAll");

        await CreateNotificationAsync(_factory, userId, isRead: false);
        await CreateNotificationAsync(_factory, userId, isRead: false);
        await CreateNotificationAsync(_factory, userId, isRead: false);
        await CreateNotificationAsync(_factory, userId, isRead: true);

        var response = await client.PatchAsync("/api/notifications/read-all", null);
        Assert.Equal(HttpStatusCode.OK, response.StatusCode);

        var body = await response.Content.ReadFromJsonAsync<JsonElement>(TestFixture.Json);
        Assert.Equal(3, body.GetProperty("count").GetInt32());

        // Verify all are read now
        var countResp = await client.GetAsync("/api/notifications/unread-count");
        var countBody = await countResp.Content.ReadFromJsonAsync<JsonElement>(TestFixture.Json);
        Assert.Equal(0, countBody.GetProperty("count").GetInt32());
    }

    // ── 7. Delete notification → 204 ─────────────────────────────────────

    [Fact]
    public async Task DeleteNotification_ReturnsNoContent()
    {
        var (client, userId, _) = await TestFixture.CreateAuthenticatedClientAsync(_factory, "NotifDelete");

        var notifId = await CreateNotificationAsync(_factory, userId);

        var response = await client.DeleteAsync($"/api/notifications/{notifId}");
        Assert.Equal(HttpStatusCode.NoContent, response.StatusCode);

        // Verify it's gone
        var listResp = await client.GetAsync("/api/notifications");
        var body = await listResp.Content.ReadFromJsonAsync<JsonElement>(TestFixture.Json);
        var items = body.GetProperty("items");
        var ids = Enumerable.Range(0, items.GetArrayLength())
            .Select(i => items[i].GetProperty("id").GetGuid())
            .ToList();
        Assert.DoesNotContain(notifId, ids);
    }

    // ── 8. Delete notification as non-owner → 404 ────────────────────────

    [Fact]
    public async Task DeleteNotification_NonOwner_ReturnsNotFound()
    {
        var (client1, userId1, tenantId) = await TestFixture.CreateAuthenticatedClientAsync(_factory, "NotifDelOwner");
        var (client2, _) = await TestFixture.CreateUserInTenantAsync(_factory, tenantId, "NotifDelNonOwner");

        var notifId = await CreateNotificationAsync(_factory, userId1);

        var response = await client2.DeleteAsync($"/api/notifications/{notifId}");
        Assert.Equal(HttpStatusCode.NotFound, response.StatusCode);
    }

    // ── 9. Notifications ordered by created_at desc ──────────────────────

    [Fact]
    public async Task ListNotifications_OrderedByCreatedAtDesc()
    {
        var (client, userId, _) = await TestFixture.CreateAuthenticatedClientAsync(_factory, "NotifOrder");

        // Create with explicit timestamps to ensure ordering
        using (var scope = _factory.Services.CreateScope())
        {
            var db = scope.ServiceProvider.GetRequiredService<AppDbContext>();
            db.Notifications.AddRange(
                new Notification
                {
                    Id = Guid.NewGuid(), UserId = userId, Type = "test",
                    Title = "Older", Message = "msg",
                    CreatedAt = DateTimeOffset.UtcNow.AddMinutes(-10)
                },
                new Notification
                {
                    Id = Guid.NewGuid(), UserId = userId, Type = "test",
                    Title = "Newer", Message = "msg",
                    CreatedAt = DateTimeOffset.UtcNow.AddMinutes(-1)
                }
            );
            await db.SaveChangesAsync();
        }

        var response = await client.GetAsync("/api/notifications");
        var body = await response.Content.ReadFromJsonAsync<JsonElement>(TestFixture.Json);
        var items = body.GetProperty("items");

        Assert.True(items.GetArrayLength() >= 2);
        // First should be "Newer"
        var titles = Enumerable.Range(0, items.GetArrayLength())
            .Select(i => items[i].GetProperty("title").GetString())
            .ToList();
        var newerIdx = titles.IndexOf("Newer");
        var olderIdx = titles.IndexOf("Older");
        Assert.True(newerIdx < olderIdx, "Newer notification should come before older one");
    }

    // ── 10. Notifications are isolated per user ───────────────────────────

    [Fact]
    public async Task ListNotifications_DoesNotReturnOtherUsersNotifications()
    {
        var (clientA, userAId, tenantId) = await TestFixture.CreateAuthenticatedClientAsync(_factory, "NotifIsoA");
        var (clientB, userBId) = await TestFixture.CreateUserInTenantAsync(_factory, tenantId, "NotifIsoB");

        var uniqueTitle = $"OnlyForA-{Guid.NewGuid():N}";
        await CreateNotificationAsync(_factory, userAId, title: uniqueTitle);
        await CreateNotificationAsync(_factory, userBId, title: "OnlyForB");

        // User A's list should contain their notification but not user B's
        var responseA = await clientA.GetAsync("/api/notifications");
        Assert.Equal(HttpStatusCode.OK, responseA.StatusCode);

        var bodyA = await responseA.Content.ReadFromJsonAsync<JsonElement>(TestFixture.Json);
        var itemsA = bodyA.GetProperty("items");
        var titlesA = Enumerable.Range(0, itemsA.GetArrayLength())
            .Select(i => itemsA[i].GetProperty("title").GetString())
            .ToList();

        Assert.Contains(uniqueTitle, titlesA);
        Assert.DoesNotContain("OnlyForB", titlesA);

        // User B's list should not contain User A's notification
        var responseB = await clientB.GetAsync("/api/notifications");
        var bodyB = await responseB.Content.ReadFromJsonAsync<JsonElement>(TestFixture.Json);
        var itemsB = bodyB.GetProperty("items");
        var titlesB = Enumerable.Range(0, itemsB.GetArrayLength())
            .Select(i => itemsB[i].GetProperty("title").GetString())
            .ToList();

        Assert.DoesNotContain(uniqueTitle, titlesB);
    }

    // ── 11. MarkAsRead sets is_read field to true ─────────────────────────

    [Fact]
    public async Task MarkAsRead_SetsIsReadTrue()
    {
        var (client, userId, _) = await TestFixture.CreateAuthenticatedClientAsync(_factory, "NotifMarkReadField");

        var notifId = await CreateNotificationAsync(_factory, userId, isRead: false);

        var response = await client.PatchAsync($"/api/notifications/{notifId}/read", null);
        Assert.Equal(HttpStatusCode.OK, response.StatusCode);

        var body = await response.Content.ReadFromJsonAsync<JsonElement>(TestFixture.Json);
        Assert.Equal(notifId, body.GetProperty("id").GetGuid());
        Assert.True(body.GetProperty("is_read").GetBoolean());
    }

    // ── 12. GetUnreadCount returns count=3 for 3 unread ──────────────────

    [Fact]
    public async Task GetUnreadCount_ReturnsThreeForThreeUnread()
    {
        var (client, userId, _) = await TestFixture.CreateAuthenticatedClientAsync(_factory, "NotifCount3");

        await CreateNotificationAsync(_factory, userId, title: "U1", isRead: false);
        await CreateNotificationAsync(_factory, userId, title: "U2", isRead: false);
        await CreateNotificationAsync(_factory, userId, title: "U3", isRead: false);

        var response = await client.GetAsync("/api/notifications/unread-count");
        Assert.Equal(HttpStatusCode.OK, response.StatusCode);

        var body = await response.Content.ReadFromJsonAsync<JsonElement>(TestFixture.Json);
        Assert.Equal(3, body.GetProperty("count").GetInt32());
    }

    // ── 13. E2E: ShareFile_CreatesNotificationForRecipient ───────────────

    [Fact]
    public async Task ShareFile_CreatesNotificationForRecipient()
    {
        var (clientA, _, tenantId) = await TestFixture.CreateAuthenticatedClientAsync(_factory, "E2EShareNotifA");
        var (clientB, userBId) = await TestFixture.CreateUserInTenantAsync(_factory, tenantId, "E2EShareNotifB");

        var folderId = await TestFixture.CreateFolderAsync(clientA, "E2E Notify Folder");

        var (status, shareBody) = await TestFixture.CreateShareAsync(clientA, folderId, userBId);
        Assert.Equal(HttpStatusCode.Created, status);
        var shareId = shareBody.GetProperty("id").GetString()!;

        // User B should have a share_created notification
        var notifResp = await clientB.GetAsync("/api/notifications");
        Assert.Equal(HttpStatusCode.OK, notifResp.StatusCode);

        var notifBody = await notifResp.Content.ReadFromJsonAsync<JsonElement>(TestFixture.Json);
        var items = notifBody.GetProperty("items");

        var shareNotif = Enumerable.Range(0, items.GetArrayLength())
            .Select(i => items[i])
            .FirstOrDefault(n => n.GetProperty("type").GetString() == "share_created");

        Assert.NotEqual(default, shareNotif);
        Assert.Equal("New Share", shareNotif.GetProperty("title").GetString());
        Assert.Equal(shareId, shareNotif.GetProperty("action_resource_id").GetString());
    }

    // ── 14. E2E: ShareFile_NotificationAppearsInUnreadCount ──────────────

    [Fact]
    public async Task ShareFile_NotificationAppearsInUnreadCount()
    {
        var (clientA, _, tenantId) = await TestFixture.CreateAuthenticatedClientAsync(_factory, "E2ECountA");
        var (clientB, userBId) = await TestFixture.CreateUserInTenantAsync(_factory, tenantId, "E2ECountB");

        // Baseline: check current unread count for User B
        var beforeResp = await clientB.GetAsync("/api/notifications/unread-count");
        var beforeBody = await beforeResp.Content.ReadFromJsonAsync<JsonElement>(TestFixture.Json);
        var countBefore = beforeBody.GetProperty("count").GetInt32();

        var folderId = await TestFixture.CreateFolderAsync(clientA, "E2E Count Folder");
        var (status, _) = await TestFixture.CreateShareAsync(clientA, folderId, userBId);
        Assert.Equal(HttpStatusCode.Created, status);

        // After share: unread count should have increased by 1
        var afterResp = await clientB.GetAsync("/api/notifications/unread-count");
        Assert.Equal(HttpStatusCode.OK, afterResp.StatusCode);

        var afterBody = await afterResp.Content.ReadFromJsonAsync<JsonElement>(TestFixture.Json);
        var countAfter = afterBody.GetProperty("count").GetInt32();

        Assert.Equal(countBefore + 1, countAfter);
    }

    // ── 15. E2E: MarkAsRead_DecreasesUnreadCount ─────────────────────────

    [Fact]
    public async Task MarkAsRead_DecreasesUnreadCount()
    {
        var (clientA, _, tenantId) = await TestFixture.CreateAuthenticatedClientAsync(_factory, "E2EMarkCountA");
        var (clientB, userBId) = await TestFixture.CreateUserInTenantAsync(_factory, tenantId, "E2EMarkCountB");

        var folderId = await TestFixture.CreateFolderAsync(clientA, "E2E Mark Count Folder");
        var (status, _) = await TestFixture.CreateShareAsync(clientA, folderId, userBId);
        Assert.Equal(HttpStatusCode.Created, status);

        // Get unread count and find the share_created notification
        var countResp = await clientB.GetAsync("/api/notifications/unread-count");
        var countBody = await countResp.Content.ReadFromJsonAsync<JsonElement>(TestFixture.Json);
        var countBefore = countBody.GetProperty("count").GetInt32();
        Assert.True(countBefore >= 1);

        var notifResp = await clientB.GetAsync("/api/notifications?unread_only=true");
        var notifBody = await notifResp.Content.ReadFromJsonAsync<JsonElement>(TestFixture.Json);
        var items = notifBody.GetProperty("items");

        var shareNotif = Enumerable.Range(0, items.GetArrayLength())
            .Select(i => items[i])
            .First(n => n.GetProperty("type").GetString() == "share_created");

        var notifId = shareNotif.GetProperty("id").GetGuid();

        // Mark that notification as read
        var markResp = await clientB.PatchAsync($"/api/notifications/{notifId}/read", null);
        Assert.Equal(HttpStatusCode.OK, markResp.StatusCode);

        // Unread count should decrease by 1
        var countAfterResp = await clientB.GetAsync("/api/notifications/unread-count");
        var countAfterBody = await countAfterResp.Content.ReadFromJsonAsync<JsonElement>(TestFixture.Json);
        Assert.Equal(countBefore - 1, countAfterBody.GetProperty("count").GetInt32());
    }
}
