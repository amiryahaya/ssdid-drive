using System.Net;
using System.Net.Http.Json;
using System.Text.Json;
using SsdidDrive.Api.Tests.Infrastructure;

namespace SsdidDrive.Api.Tests.Integration;

public class PaginationTests : IClassFixture<SsdidDriveFactory>
{
    private readonly SsdidDriveFactory _factory;

    public PaginationTests(SsdidDriveFactory factory) => _factory = factory;

    // ── Folders ────────────────────────────────────────────────────────

    [Fact]
    public async Task ListFolders_WithPagination_ReturnsPagedResponse()
    {
        var (client, _, _) = await TestFixture.CreateAuthenticatedClientAsync(_factory);

        await TestFixture.CreateFolderAsync(client, "PagFolder A");
        await TestFixture.CreateFolderAsync(client, "PagFolder B");
        await TestFixture.CreateFolderAsync(client, "PagFolder C");

        var response = await client.GetAsync("/api/folders?page=1&pageSize=2");
        Assert.Equal(HttpStatusCode.OK, response.StatusCode);

        var body = await response.Content.ReadFromJsonAsync<JsonElement>(TestFixture.Json);
        var items = body.GetProperty("items");
        var total = body.GetProperty("total").GetInt32();

        Assert.Equal(2, items.GetArrayLength());
        Assert.Equal(3, total);
        Assert.Equal(1, body.GetProperty("page").GetInt32());
        Assert.Equal(2, body.GetProperty("page_size").GetInt32());
        Assert.Equal(2, body.GetProperty("total_pages").GetInt32());
    }

    [Fact]
    public async Task ListFolders_SecondPage_ReturnsRemainingItems()
    {
        var (client, _, _) = await TestFixture.CreateAuthenticatedClientAsync(_factory);

        await TestFixture.CreateFolderAsync(client, "Pag2Folder A");
        await TestFixture.CreateFolderAsync(client, "Pag2Folder B");
        await TestFixture.CreateFolderAsync(client, "Pag2Folder C");

        var response = await client.GetAsync("/api/folders?page=2&pageSize=2");
        Assert.Equal(HttpStatusCode.OK, response.StatusCode);

        var body = await response.Content.ReadFromJsonAsync<JsonElement>(TestFixture.Json);
        var items = body.GetProperty("items");

        Assert.Equal(1, items.GetArrayLength());
        Assert.Equal(3, body.GetProperty("total").GetInt32());
        Assert.Equal(2, body.GetProperty("page").GetInt32());
    }

    [Fact]
    public async Task ListFolders_WithSearch_FiltersResults()
    {
        var (client, _, _) = await TestFixture.CreateAuthenticatedClientAsync(_factory);

        await TestFixture.CreateFolderAsync(client, "SearchHit Alpha");
        await TestFixture.CreateFolderAsync(client, "SearchHit Beta");
        await TestFixture.CreateFolderAsync(client, "NoMatch Gamma");

        var response = await client.GetAsync("/api/folders?search=SearchHit");
        Assert.Equal(HttpStatusCode.OK, response.StatusCode);

        var body = await response.Content.ReadFromJsonAsync<JsonElement>(TestFixture.Json);
        var items = body.GetProperty("items");

        Assert.Equal(2, items.GetArrayLength());
        Assert.Equal(2, body.GetProperty("total").GetInt32());
    }

    [Fact]
    public async Task ListFolders_DefaultPagination_ReturnsAllItems()
    {
        var (client, _, _) = await TestFixture.CreateAuthenticatedClientAsync(_factory);

        await TestFixture.CreateFolderAsync(client, "DefFolder A");
        await TestFixture.CreateFolderAsync(client, "DefFolder B");

        var response = await client.GetAsync("/api/folders");
        Assert.Equal(HttpStatusCode.OK, response.StatusCode);

        var body = await response.Content.ReadFromJsonAsync<JsonElement>(TestFixture.Json);
        var items = body.GetProperty("items");

        Assert.True(items.GetArrayLength() >= 2);
        Assert.Equal(50, body.GetProperty("page_size").GetInt32());
        Assert.Equal(1, body.GetProperty("page").GetInt32());
    }

    // ── Files ──────────────────────────────────────────────────────────

    [Fact]
    public async Task ListFiles_WithPagination_ReturnsPagedResponse()
    {
        var (client, _, _) = await TestFixture.CreateAuthenticatedClientAsync(_factory);
        var folderId = await TestFixture.CreateFolderAsync(client, "PagFileFolder");

        await TestFixture.UploadFileAsync(client, folderId, "pagfile1.bin");
        await TestFixture.UploadFileAsync(client, folderId, "pagfile2.bin");
        await TestFixture.UploadFileAsync(client, folderId, "pagfile3.bin");

        var response = await client.GetAsync($"/api/folders/{folderId}/files?page=1&pageSize=2");
        Assert.Equal(HttpStatusCode.OK, response.StatusCode);

        var body = await response.Content.ReadFromJsonAsync<JsonElement>(TestFixture.Json);
        var items = body.GetProperty("items");

        Assert.Equal(2, items.GetArrayLength());
        Assert.Equal(3, body.GetProperty("total").GetInt32());
    }

    [Fact]
    public async Task ListFiles_WithSearch_FiltersResults()
    {
        var (client, _, _) = await TestFixture.CreateAuthenticatedClientAsync(_factory);
        var folderId = await TestFixture.CreateFolderAsync(client, "SearchFileFolder");

        await TestFixture.UploadFileAsync(client, folderId, "report-q1.bin");
        await TestFixture.UploadFileAsync(client, folderId, "report-q2.bin");
        await TestFixture.UploadFileAsync(client, folderId, "invoice.bin");

        var response = await client.GetAsync($"/api/folders/{folderId}/files?search=report");
        Assert.Equal(HttpStatusCode.OK, response.StatusCode);

        var body = await response.Content.ReadFromJsonAsync<JsonElement>(TestFixture.Json);
        var items = body.GetProperty("items");

        Assert.Equal(2, items.GetArrayLength());
        Assert.Equal(2, body.GetProperty("total").GetInt32());
    }

    // ── Shares ─────────────────────────────────────────────────────────

    [Fact]
    public async Task ListCreatedShares_WithPagination_ReturnsPagedResponse()
    {
        var (client1, _, tenantId) = await TestFixture.CreateAuthenticatedClientAsync(_factory, "PagShareOwner");
        var (_, userId2) = await TestFixture.CreateUserInTenantAsync(_factory, tenantId, "PagShareRecip1");
        var (_, userId3) = await TestFixture.CreateUserInTenantAsync(_factory, tenantId, "PagShareRecip2");
        var (_, userId4) = await TestFixture.CreateUserInTenantAsync(_factory, tenantId, "PagShareRecip3");

        var folderId = await TestFixture.CreateFolderAsync(client1, "PagShareFolder");

        await TestFixture.CreateShareAsync(client1, folderId, userId2);
        await TestFixture.CreateShareAsync(client1, folderId, userId3);
        await TestFixture.CreateShareAsync(client1, folderId, userId4);

        var response = await client1.GetAsync("/api/shares/created?page=1&pageSize=2");
        Assert.Equal(HttpStatusCode.OK, response.StatusCode);

        var body = await response.Content.ReadFromJsonAsync<JsonElement>(TestFixture.Json);
        var items = body.GetProperty("items");

        Assert.Equal(2, items.GetArrayLength());
        Assert.Equal(3, body.GetProperty("total").GetInt32());
    }

    [Fact]
    public async Task ListReceivedShares_WithPagination_ReturnsPagedResponse()
    {
        var (client1, _, tenantId) = await TestFixture.CreateAuthenticatedClientAsync(_factory, "PagRecvOwner");
        var (client2, userId2) = await TestFixture.CreateUserInTenantAsync(_factory, tenantId, "PagRecvRecipient");

        var folder1 = await TestFixture.CreateFolderAsync(client1, "PagRecv1");
        var folder2 = await TestFixture.CreateFolderAsync(client1, "PagRecv2");
        var folder3 = await TestFixture.CreateFolderAsync(client1, "PagRecv3");

        await TestFixture.CreateShareAsync(client1, folder1, userId2);
        await TestFixture.CreateShareAsync(client1, folder2, userId2);
        await TestFixture.CreateShareAsync(client1, folder3, userId2);

        var response = await client2.GetAsync("/api/shares/received?page=1&pageSize=2");
        Assert.Equal(HttpStatusCode.OK, response.StatusCode);

        var body = await response.Content.ReadFromJsonAsync<JsonElement>(TestFixture.Json);
        var items = body.GetProperty("items");

        Assert.Equal(2, items.GetArrayLength());
        Assert.Equal(3, body.GetProperty("total").GetInt32());
    }
}
