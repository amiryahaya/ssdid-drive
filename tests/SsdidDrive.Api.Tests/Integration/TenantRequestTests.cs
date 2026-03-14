using System.Net;
using System.Net.Http.Json;
using System.Text.Json;
using Microsoft.Extensions.DependencyInjection;
using SsdidDrive.Api.Data;
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

    [Fact]
    public async Task ListRequests_AsSuperAdmin_ReturnsPendingRequests()
    {
        var (userClient, userId, _) = await TestFixture.CreateAuthenticatedClientAsync(_factory);

        await userClient.PostAsJsonAsync("/api/tenant-requests", new
        {
            organization_name = "Admin List Test Corp"
        }, Json);

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

    [Fact]
    public async Task ApproveRequest_CreatesTenantAndAddsRequesterAsOwner()
    {
        var (userClient, userId, _) = await TestFixture.CreateAuthenticatedClientAsync(_factory);

        using (var scope = _factory.Services.CreateScope())
        {
            var db = scope.ServiceProvider.GetRequiredService<AppDbContext>();
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
            var db = scope.ServiceProvider.GetRequiredService<AppDbContext>();
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
}
