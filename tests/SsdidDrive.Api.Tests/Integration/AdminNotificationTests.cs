using System.Net;
using System.Net.Http.Json;
using System.Text.Json;
using Microsoft.Extensions.DependencyInjection;
using SsdidDrive.Api.Data;
using SsdidDrive.Api.Tests.Infrastructure;

namespace SsdidDrive.Api.Tests.Integration;

public class AdminNotificationTests : IClassFixture<SsdidDriveFactory>
{
    private readonly SsdidDriveFactory _factory;

    public AdminNotificationTests(SsdidDriveFactory factory) => _factory = factory;

    // ── 1. User scope → returns recipient count ─────────────────────────

    [Fact]
    public async Task SendNotification_UserScope_ReturnsRecipientCount()
    {
        var (adminClient, _, _) = await TestFixture.CreateAuthenticatedClientAsync(_factory, "NotifAdmin1", systemRole: "SuperAdmin");
        var (_, targetId, _) = await TestFixture.CreateAuthenticatedClientAsync(_factory, "NotifTarget1");

        var response = await adminClient.PostAsJsonAsync("/api/admin/notifications", new
        {
            scope = "user",
            target_id = targetId,
            title = "Test Notification",
            message = "This is a test notification"
        }, TestFixture.Json);

        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        var body = await response.Content.ReadFromJsonAsync<JsonElement>(TestFixture.Json);
        Assert.Equal(1, body.GetProperty("recipients").GetInt32());
    }

    // ── 2. User scope, target not found → 404 ───────────────────────────

    [Fact]
    public async Task SendNotification_UserScope_TargetNotFound_Returns404()
    {
        var (adminClient, _, _) = await TestFixture.CreateAuthenticatedClientAsync(_factory, "NotifAdmin2", systemRole: "SuperAdmin");

        var response = await adminClient.PostAsJsonAsync("/api/admin/notifications", new
        {
            scope = "user",
            target_id = Guid.NewGuid(),
            title = "Test",
            message = "Test"
        }, TestFixture.Json);

        Assert.Equal(HttpStatusCode.NotFound, response.StatusCode);
    }

    // ── 3. Tenant scope → sends to all members ──────────────────────────

    [Fact]
    public async Task SendNotification_TenantScope_SendsToAllMembers()
    {
        var (adminClient, _, _) = await TestFixture.CreateAuthenticatedClientAsync(_factory, "NotifTenantAdmin", systemRole: "SuperAdmin");
        // Create a tenant with members
        var (_, _, tenantId) = await TestFixture.CreateAuthenticatedClientAsync(_factory, "TenantMember1");
        await TestFixture.CreateUserInTenantAsync(_factory, tenantId, "TenantMember2");

        var response = await adminClient.PostAsJsonAsync("/api/admin/notifications", new
        {
            scope = "tenant",
            target_id = tenantId,
            title = "Tenant Announcement",
            message = "Hello tenant members"
        }, TestFixture.Json);

        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        var body = await response.Content.ReadFromJsonAsync<JsonElement>(TestFixture.Json);
        // Tenant has at least 2 members (owner + member added)
        Assert.True(body.GetProperty("recipients").GetInt32() >= 2);
    }

    // ── 4. Broadcast scope → sends to all active users ──────────────────

    [Fact]
    public async Task SendNotification_BroadcastScope_SendsToAllActiveUsers()
    {
        var (adminClient, _, _) = await TestFixture.CreateAuthenticatedClientAsync(_factory, "BroadcastAdmin", systemRole: "SuperAdmin");

        var response = await adminClient.PostAsJsonAsync("/api/admin/notifications", new
        {
            scope = "broadcast",
            title = "System Broadcast",
            message = "Important system announcement"
        }, TestFixture.Json);

        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        var body = await response.Content.ReadFromJsonAsync<JsonElement>(TestFixture.Json);
        Assert.True(body.GetProperty("recipients").GetInt32() >= 1);
    }

    // ── 5. Invalid scope → 400 ──────────────────────────────────────────

    [Fact]
    public async Task SendNotification_InvalidScope_Returns400()
    {
        var (adminClient, _, _) = await TestFixture.CreateAuthenticatedClientAsync(_factory, "NotifInvalidScope", systemRole: "SuperAdmin");

        var response = await adminClient.PostAsJsonAsync("/api/admin/notifications", new
        {
            scope = "invalid_scope",
            title = "Test",
            message = "Test"
        }, TestFixture.Json);

        Assert.Equal(HttpStatusCode.BadRequest, response.StatusCode);
    }

    // ── 6. Missing title → 400 ──────────────────────────────────────────

    [Fact]
    public async Task SendNotification_MissingTitle_Returns400()
    {
        var (adminClient, _, _) = await TestFixture.CreateAuthenticatedClientAsync(_factory, "NotifNoTitle", systemRole: "SuperAdmin");
        var (_, targetId, _) = await TestFixture.CreateAuthenticatedClientAsync(_factory, "NotifNoTitleTarget");

        var response = await adminClient.PostAsJsonAsync("/api/admin/notifications", new
        {
            scope = "user",
            target_id = targetId,
            title = "",
            message = "Message body"
        }, TestFixture.Json);

        Assert.Equal(HttpStatusCode.BadRequest, response.StatusCode);
    }

    // ── 7. Null/empty scope → 400 ───────────────────────────────────────

    [Fact]
    public async Task SendNotification_NullScope_Returns400()
    {
        var (adminClient, _, _) = await TestFixture.CreateAuthenticatedClientAsync(_factory, "NotifNullScope", systemRole: "SuperAdmin");

        var response = await adminClient.PostAsJsonAsync("/api/admin/notifications", new
        {
            scope = "",
            title = "Test",
            message = "Test"
        }, TestFixture.Json);

        Assert.Equal(HttpStatusCode.BadRequest, response.StatusCode);
    }

    // ── 8. Writes to notification log ───────────────────────────────────

    [Fact]
    public async Task SendNotification_WritesToNotificationLog()
    {
        var (adminClient, _, _) = await TestFixture.CreateAuthenticatedClientAsync(_factory, "NotifLogAdmin", systemRole: "SuperAdmin");
        var (_, targetId, _) = await TestFixture.CreateAuthenticatedClientAsync(_factory, "NotifLogTarget");

        var uniqueTitle = $"LogTest-{Guid.NewGuid():N}";
        await adminClient.PostAsJsonAsync("/api/admin/notifications", new
        {
            scope = "user",
            target_id = targetId,
            title = uniqueTitle,
            message = "Check the log"
        }, TestFixture.Json);

        // Verify via the notification log endpoint
        var logResponse = await adminClient.GetAsync("/api/admin/notifications");
        Assert.Equal(HttpStatusCode.OK, logResponse.StatusCode);

        var logBody = await logResponse.Content.ReadFromJsonAsync<JsonElement>(TestFixture.Json);
        var items = logBody.GetProperty("items");
        Assert.True(items.GetArrayLength() >= 1);

        // Find the log entry by unique title
        var found = false;
        foreach (var item in items.EnumerateArray())
        {
            if (item.GetProperty("title").GetString() == uniqueTitle)
            {
                found = true;
                Assert.Equal("user", item.GetProperty("scope").GetString());
                Assert.Equal(1, item.GetProperty("recipient_count").GetInt32());
                break;
            }
        }
        Assert.True(found, $"Expected notification log entry with title '{uniqueTitle}'");
    }

    // ── 9. ListNotificationLog returns paged results ────────────────────

    [Fact]
    public async Task ListNotificationLog_ReturnsPagedResults()
    {
        var (adminClient, _, _) = await TestFixture.CreateAuthenticatedClientAsync(_factory, "NotifLogListAdmin", systemRole: "SuperAdmin");
        var (_, targetId, _) = await TestFixture.CreateAuthenticatedClientAsync(_factory, "NotifLogListTarget");

        // Send a notification to populate the log
        await adminClient.PostAsJsonAsync("/api/admin/notifications", new
        {
            scope = "user",
            target_id = targetId,
            title = "Paged Test",
            message = "Page test"
        }, TestFixture.Json);

        var response = await adminClient.GetAsync("/api/admin/notifications?page=1&page_size=5");
        Assert.Equal(HttpStatusCode.OK, response.StatusCode);

        var body = await response.Content.ReadFromJsonAsync<JsonElement>(TestFixture.Json);
        Assert.True(body.TryGetProperty("items", out var items));
        Assert.True(body.TryGetProperty("total", out _));
        Assert.True(items.GetArrayLength() >= 1);
    }

    // ── 10. Non-admin → 403 ─────────────────────────────────────────────

    [Fact]
    public async Task SendNotification_NonAdmin_Returns403()
    {
        var (client, _, _) = await TestFixture.CreateAuthenticatedClientAsync(_factory, "NotifNonAdmin");

        var response = await client.PostAsJsonAsync("/api/admin/notifications", new
        {
            scope = "broadcast",
            title = "Unauthorized",
            message = "Should not work"
        }, TestFixture.Json);

        Assert.Equal(HttpStatusCode.Forbidden, response.StatusCode);
    }
}
