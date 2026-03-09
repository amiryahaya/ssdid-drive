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
}
