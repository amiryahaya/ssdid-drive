# Backend API Integration Tests Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add integration tests for all SSDID Drive backend API endpoints using WebApplicationFactory with in-memory SQLite, covering the full HTTP pipeline (request → middleware → endpoint → DB → response).

**Architecture:** Use `WebApplicationFactory<Program>` to spin up the real ASP.NET pipeline with SQLite in-memory replacing PostgreSQL and a `MemoryStorageService` replacing disk storage. A shared `TestFixture` provides helper methods to register/authenticate users and seed data. Each test class covers one feature area.

**Tech Stack:** .NET 10, xUnit v3, WebApplicationFactory, SQLite in-memory, System.Text.Json

---

### Task 1: Add test infrastructure packages

**Files:**
- Modify: `tests/SsdidDrive.Api.Tests/SsdidDrive.Api.Tests.csproj`

**Step 1: Add required NuGet packages**

Add `Microsoft.AspNetCore.Mvc.Testing` and `Microsoft.EntityFrameworkCore.Sqlite` to the test project:

```xml
<PackageReference Include="Microsoft.AspNetCore.Mvc.Testing" Version="10.0.0" />
<PackageReference Include="Microsoft.EntityFrameworkCore.Sqlite" Version="10.0.3" />
```

Add them after the existing `xunit.v3` reference in the `<ItemGroup>`.

**Step 2: Verify packages restore**

Run: `dotnet restore tests/SsdidDrive.Api.Tests/`
Expected: Restore succeeds with no errors

**Step 3: Commit**

```bash
git add tests/SsdidDrive.Api.Tests/SsdidDrive.Api.Tests.csproj
git commit -m "chore(tests): add WebApplicationFactory and SQLite packages"
```

---

### Task 2: Create MemoryStorageService

**Files:**
- Create: `tests/SsdidDrive.Api.Tests/Infrastructure/MemoryStorageService.cs`

**Step 1: Write the failing test**

Create `tests/SsdidDrive.Api.Tests/Infrastructure/MemoryStorageServiceTests.cs`:

```csharp
using SsdidDrive.Api.Tests.Infrastructure;

namespace SsdidDrive.Api.Tests.Infrastructure;

public class MemoryStorageServiceTests
{
    private readonly MemoryStorageService _sut = new();

    [Fact]
    public async Task StoreAndRetrieve_Roundtrip()
    {
        var ct = TestContext.Current.CancellationToken;
        var content = "hello"u8.ToArray();
        using var stream = new MemoryStream(content);

        var path = await _sut.StoreAsync(Guid.NewGuid(), Guid.NewGuid(), Guid.NewGuid(), stream, ct);

        await using var retrieved = await _sut.RetrieveAsync(path, ct);
        using var ms = new MemoryStream();
        await retrieved.CopyToAsync(ms, ct);
        Assert.Equal(content, ms.ToArray());
    }

    [Fact]
    public async Task DeleteAsync_RemovesFile()
    {
        var ct = TestContext.Current.CancellationToken;
        using var stream = new MemoryStream("data"u8.ToArray());
        var path = await _sut.StoreAsync(Guid.NewGuid(), Guid.NewGuid(), Guid.NewGuid(), stream, ct);

        await _sut.DeleteAsync(path, ct);

        await Assert.ThrowsAsync<FileNotFoundException>(
            () => _sut.RetrieveAsync(path, ct));
    }
}
```

**Step 2: Run test to verify it fails**

Run: `dotnet test tests/SsdidDrive.Api.Tests/ --filter "MemoryStorageServiceTests" -v minimal`
Expected: FAIL — `MemoryStorageService` class does not exist

**Step 3: Write minimal implementation**

Create `tests/SsdidDrive.Api.Tests/Infrastructure/MemoryStorageService.cs`:

```csharp
using System.Collections.Concurrent;
using SsdidDrive.Api.Services;

namespace SsdidDrive.Api.Tests.Infrastructure;

public class MemoryStorageService : IStorageService
{
    private readonly ConcurrentDictionary<string, byte[]> _store = new();

    public Task<string> StoreAsync(Guid tenantId, Guid folderId, Guid fileId, Stream content, CancellationToken ct = default)
    {
        var path = Path.Combine(tenantId.ToString(), folderId.ToString(), fileId.ToString());
        using var ms = new MemoryStream();
        content.CopyTo(ms);
        _store[path] = ms.ToArray();
        return Task.FromResult(path);
    }

    public Task<Stream> RetrieveAsync(string storagePath, CancellationToken ct = default)
    {
        if (!_store.TryGetValue(storagePath, out var data))
            throw new FileNotFoundException($"Not found: {storagePath}");
        return Task.FromResult<Stream>(new MemoryStream(data));
    }

    public Task DeleteAsync(string storagePath, CancellationToken ct = default)
    {
        _store.TryRemove(storagePath, out _);
        return Task.CompletedTask;
    }
}
```

**Step 4: Run test to verify it passes**

Run: `dotnet test tests/SsdidDrive.Api.Tests/ --filter "MemoryStorageServiceTests" -v minimal`
Expected: 2 tests PASS

**Step 5: Commit**

```bash
git add tests/SsdidDrive.Api.Tests/Infrastructure/
git commit -m "test(infra): add MemoryStorageService for integration tests"
```

---

### Task 3: Create SsdidDriveFactory (WebApplicationFactory)

**Files:**
- Create: `tests/SsdidDrive.Api.Tests/Infrastructure/SsdidDriveFactory.cs`
- Create: `tests/SsdidDrive.Api.Tests/Infrastructure/TestFixture.cs`

**Step 1: Write the failing test**

Create `tests/SsdidDrive.Api.Tests/Infrastructure/FactoryTests.cs`:

```csharp
namespace SsdidDrive.Api.Tests.Infrastructure;

public class FactoryTests : IClassFixture<SsdidDriveFactory>
{
    private readonly HttpClient _client;

    public FactoryTests(SsdidDriveFactory factory) => _client = factory.CreateClient();

    [Fact]
    public async Task HealthEndpoint_ReturnsOk()
    {
        var response = await _client.GetAsync("/api/health");
        Assert.Equal(System.Net.HttpStatusCode.OK, response.StatusCode);
    }

    [Fact]
    public async Task ProtectedEndpoint_WithoutAuth_Returns401()
    {
        var response = await _client.GetAsync("/api/me");
        Assert.Equal(System.Net.HttpStatusCode.Unauthorized, response.StatusCode);
    }
}
```

**Step 2: Run test to verify it fails**

Run: `dotnet test tests/SsdidDrive.Api.Tests/ --filter "FactoryTests" -v minimal`
Expected: FAIL — `SsdidDriveFactory` does not exist

**Step 3: Write SsdidDriveFactory**

Create `tests/SsdidDrive.Api.Tests/Infrastructure/SsdidDriveFactory.cs`:

```csharp
using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Mvc.Testing;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.DependencyInjection;
using SsdidDrive.Api.Data;
using SsdidDrive.Api.Services;

namespace SsdidDrive.Api.Tests.Infrastructure;

public class SsdidDriveFactory : WebApplicationFactory<Program>
{
    protected override void ConfigureWebHost(IWebHostBuilder builder)
    {
        builder.UseEnvironment("Development");

        builder.ConfigureServices(services =>
        {
            // Remove the real PostgreSQL DbContext registration
            var descriptor = services.SingleOrDefault(
                d => d.ServiceType == typeof(DbContextOptions<AppDbContext>));
            if (descriptor != null) services.Remove(descriptor);

            // Remove any existing IStorageService registration
            var storageDescriptor = services.SingleOrDefault(
                d => d.ServiceType == typeof(IStorageService));
            if (storageDescriptor != null) services.Remove(storageDescriptor);

            // Add SQLite in-memory
            services.AddDbContext<AppDbContext>(options =>
                options.UseSqlite("DataSource=:memory:"));

            // Add MemoryStorageService
            services.AddSingleton<IStorageService, MemoryStorageService>();

            // Ensure DB is created
            var sp = services.BuildServiceProvider();
            using var scope = sp.CreateScope();
            var db = scope.ServiceProvider.GetRequiredService<AppDbContext>();
            db.Database.EnsureCreated();
        });
    }
}
```

**Step 4: Write TestFixture helper**

Create `tests/SsdidDrive.Api.Tests/Infrastructure/TestFixture.cs`:

```csharp
using System.Net.Http.Headers;
using System.Net.Http.Json;
using System.Text.Json;
using Microsoft.Extensions.DependencyInjection;
using SsdidDrive.Api.Data;
using SsdidDrive.Api.Data.Entities;
using SsdidDrive.Api.Ssdid;

namespace SsdidDrive.Api.Tests.Infrastructure;

public static class TestFixture
{
    private static readonly JsonSerializerOptions JsonOptions = new()
    {
        PropertyNamingPolicy = JsonNamingPolicy.SnakeCaseLower,
        PropertyNameCaseInsensitive = true
    };

    /// <summary>
    /// Seeds a user + tenant + session directly in the DB and SessionStore,
    /// bypassing the full SSDID register/authenticate flow.
    /// Returns an HttpClient with the Bearer token pre-configured.
    /// </summary>
    public static async Task<(HttpClient Client, Guid UserId, Guid TenantId)> CreateAuthenticatedClientAsync(
        SsdidDriveFactory factory,
        string? displayName = null,
        string? did = null)
    {
        did ??= $"did:ssdid:test-{Guid.NewGuid():N}";
        var sessionToken = Convert.ToBase64String(Guid.NewGuid().ToByteArray());

        using var scope = factory.Services.CreateScope();
        var db = scope.ServiceProvider.GetRequiredService<AppDbContext>();
        var sessionStore = scope.ServiceProvider.GetRequiredService<SessionStore>();

        var tenant = new Tenant
        {
            Name = "Test Tenant",
            Slug = $"test-{Guid.NewGuid():N}"[..32],
            CreatedAt = DateTimeOffset.UtcNow,
            UpdatedAt = DateTimeOffset.UtcNow
        };
        db.Tenants.Add(tenant);
        await db.SaveChangesAsync();

        var user = new User
        {
            Did = did,
            DisplayName = displayName ?? "Test User",
            Status = UserStatus.Active,
            TenantId = tenant.Id,
            CreatedAt = DateTimeOffset.UtcNow,
            UpdatedAt = DateTimeOffset.UtcNow
        };
        db.Users.Add(user);

        var userTenant = new UserTenant
        {
            UserId = user.Id,
            TenantId = tenant.Id,
            Role = TenantRole.Owner,
            CreatedAt = DateTimeOffset.UtcNow
        };
        db.UserTenants.Add(userTenant);
        await db.SaveChangesAsync();

        // Create session in the SessionStore
        sessionStore.CreateSessionDirect(did, sessionToken);

        var client = factory.CreateClient();
        client.DefaultRequestHeaders.Authorization = new AuthenticationHeaderValue("Bearer", sessionToken);

        return (client, user.Id, tenant.Id);
    }

    public static JsonSerializerOptions Json => JsonOptions;
}
```

**Important:** The `SessionStore` needs a `CreateSessionDirect(string did, string token)` method for tests. Add it to the production `SessionStore` class.

Modify `src/SsdidDrive.Api/Ssdid/SessionStore.cs` — add this method (it's internal, only visible to the test project via `InternalsVisibleTo`):

```csharp
internal void CreateSessionDirect(string did, string token)
{
    _sessions[token] = new SessionEntry(did, DateTimeOffset.UtcNow.Add(SessionTtl));
}
```

**Step 5: Run tests to verify they pass**

Run: `dotnet test tests/SsdidDrive.Api.Tests/ --filter "FactoryTests" -v minimal`
Expected: 2 tests PASS

**Step 6: Commit**

```bash
git add tests/SsdidDrive.Api.Tests/Infrastructure/ src/SsdidDrive.Api/Ssdid/SessionStore.cs
git commit -m "test(infra): add SsdidDriveFactory and TestFixture for integration tests"
```

---

### Task 4: Auth middleware integration tests

**Files:**
- Create: `tests/SsdidDrive.Api.Tests/Integration/AuthMiddlewareTests.cs`

**Step 1: Write the tests**

```csharp
using System.Net;
using System.Net.Http.Headers;
using System.Net.Http.Json;
using System.Text.Json;
using SsdidDrive.Api.Tests.Infrastructure;

namespace SsdidDrive.Api.Tests.Integration;

public class AuthMiddlewareTests : IClassFixture<SsdidDriveFactory>
{
    private readonly SsdidDriveFactory _factory;

    public AuthMiddlewareTests(SsdidDriveFactory factory) => _factory = factory;

    [Fact]
    public async Task ProtectedEndpoint_NoAuthHeader_Returns401()
    {
        var client = _factory.CreateClient();
        var response = await client.GetAsync("/api/me");
        Assert.Equal(HttpStatusCode.Unauthorized, response.StatusCode);
    }

    [Fact]
    public async Task ProtectedEndpoint_InvalidBearerFormat_Returns401()
    {
        var client = _factory.CreateClient();
        client.DefaultRequestHeaders.Authorization = new AuthenticationHeaderValue("Basic", "credentials");
        var response = await client.GetAsync("/api/me");
        Assert.Equal(HttpStatusCode.Unauthorized, response.StatusCode);
    }

    [Fact]
    public async Task ProtectedEndpoint_ExpiredSession_Returns401()
    {
        var client = _factory.CreateClient();
        client.DefaultRequestHeaders.Authorization = new AuthenticationHeaderValue("Bearer", "nonexistent-token");
        var response = await client.GetAsync("/api/me");
        Assert.Equal(HttpStatusCode.Unauthorized, response.StatusCode);
    }

    [Fact]
    public async Task ProtectedEndpoint_ValidSession_Returns200()
    {
        var (client, _, _) = await TestFixture.CreateAuthenticatedClientAsync(_factory);
        var response = await client.GetAsync("/api/me");
        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
    }

    [Fact]
    public async Task PublicEndpoint_ServerInfo_NoAuthRequired()
    {
        var client = _factory.CreateClient();
        var response = await client.GetAsync("/api/auth/ssdid/server-info");
        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
    }

    [Fact]
    public async Task ProblemDetails_HasCorrectContentType()
    {
        var client = _factory.CreateClient();
        var response = await client.GetAsync("/api/me");
        Assert.Equal("application/problem+json", response.Content.Headers.ContentType?.MediaType);
    }

    [Fact]
    public async Task Logout_InvalidatesSession()
    {
        var (client, _, _) = await TestFixture.CreateAuthenticatedClientAsync(_factory);

        // Verify session works
        var before = await client.GetAsync("/api/me");
        Assert.Equal(HttpStatusCode.OK, before.StatusCode);

        // Logout
        var logout = await client.PostAsync("/api/auth/ssdid/logout", null);
        Assert.Equal(HttpStatusCode.NoContent, logout.StatusCode);

        // Session should now be invalid
        var after = await client.GetAsync("/api/me");
        Assert.Equal(HttpStatusCode.Unauthorized, after.StatusCode);
    }
}
```

**Step 2: Run tests**

Run: `dotnet test tests/SsdidDrive.Api.Tests/ --filter "AuthMiddlewareTests" -v minimal`
Expected: All 7 tests PASS

**Step 3: Commit**

```bash
git add tests/SsdidDrive.Api.Tests/Integration/
git commit -m "test(api): add auth middleware integration tests"
```

---

### Task 5: Folder CRUD integration tests

**Files:**
- Create: `tests/SsdidDrive.Api.Tests/Integration/FolderTests.cs`

**Step 1: Write the tests**

```csharp
using System.Net;
using System.Net.Http.Json;
using System.Text.Json;
using SsdidDrive.Api.Tests.Infrastructure;

namespace SsdidDrive.Api.Tests.Integration;

public class FolderTests : IClassFixture<SsdidDriveFactory>
{
    private readonly SsdidDriveFactory _factory;

    public FolderTests(SsdidDriveFactory factory) => _factory = factory;

    private static object CreateFolderRequest(string name = "Test Folder") => new
    {
        name,
        encrypted_folder_key = Convert.ToBase64String(new byte[32]),
        kem_algorithm = "Kyber768"
    };

    [Fact]
    public async Task CreateFolder_ReturnsCreated()
    {
        var (client, userId, _) = await TestFixture.CreateAuthenticatedClientAsync(_factory);

        var response = await client.PostAsJsonAsync("/api/folders", CreateFolderRequest(), TestFixture.Json);

        Assert.Equal(HttpStatusCode.Created, response.StatusCode);

        var body = await response.Content.ReadFromJsonAsync<JsonElement>(TestFixture.Json);
        Assert.Equal("Test Folder", body.GetProperty("name").GetString());
        Assert.Equal("Kyber768", body.GetProperty("kem_algorithm").GetString());
        Assert.Equal(userId, Guid.Parse(body.GetProperty("owner_id").GetString()!));
    }

    [Fact]
    public async Task CreateFolder_EmptyName_Returns400()
    {
        var (client, _, _) = await TestFixture.CreateAuthenticatedClientAsync(_factory);
        var response = await client.PostAsJsonAsync("/api/folders", new
        {
            name = "",
            encrypted_folder_key = Convert.ToBase64String(new byte[32]),
            kem_algorithm = "Kyber768"
        }, TestFixture.Json);

        Assert.Equal(HttpStatusCode.BadRequest, response.StatusCode);
    }

    [Fact]
    public async Task CreateFolder_WithParent_Succeeds()
    {
        var (client, _, _) = await TestFixture.CreateAuthenticatedClientAsync(_factory);

        var parentResp = await client.PostAsJsonAsync("/api/folders", CreateFolderRequest("Parent"), TestFixture.Json);
        var parent = await parentResp.Content.ReadFromJsonAsync<JsonElement>(TestFixture.Json);
        var parentId = parent.GetProperty("id").GetString();

        var childResp = await client.PostAsJsonAsync("/api/folders", new
        {
            name = "Child",
            parent_folder_id = parentId,
            encrypted_folder_key = Convert.ToBase64String(new byte[32]),
            kem_algorithm = "Kyber768"
        }, TestFixture.Json);

        Assert.Equal(HttpStatusCode.Created, childResp.StatusCode);
        var child = await childResp.Content.ReadFromJsonAsync<JsonElement>(TestFixture.Json);
        Assert.Equal(parentId, child.GetProperty("parent_folder_id").GetString());
    }

    [Fact]
    public async Task CreateFolder_NonExistentParent_Returns404()
    {
        var (client, _, _) = await TestFixture.CreateAuthenticatedClientAsync(_factory);

        var response = await client.PostAsJsonAsync("/api/folders", new
        {
            name = "Orphan",
            parent_folder_id = Guid.NewGuid(),
            encrypted_folder_key = Convert.ToBase64String(new byte[32]),
            kem_algorithm = "Kyber768"
        }, TestFixture.Json);

        Assert.Equal(HttpStatusCode.NotFound, response.StatusCode);
    }

    [Fact]
    public async Task ListFolders_ReturnsOwnedFolders()
    {
        var (client, _, _) = await TestFixture.CreateAuthenticatedClientAsync(_factory);

        await client.PostAsJsonAsync("/api/folders", CreateFolderRequest("Folder A"), TestFixture.Json);
        await client.PostAsJsonAsync("/api/folders", CreateFolderRequest("Folder B"), TestFixture.Json);

        var response = await client.GetAsync("/api/folders");
        Assert.Equal(HttpStatusCode.OK, response.StatusCode);

        var folders = await response.Content.ReadFromJsonAsync<JsonElement[]>(TestFixture.Json);
        Assert.NotNull(folders);
        Assert.Equal(2, folders.Length);
    }

    [Fact]
    public async Task ListFolders_ExcludesOtherUserFolders()
    {
        var (client1, _, _) = await TestFixture.CreateAuthenticatedClientAsync(_factory, "User1");
        var (client2, _, _) = await TestFixture.CreateAuthenticatedClientAsync(_factory, "User2");

        await client1.PostAsJsonAsync("/api/folders", CreateFolderRequest("User1 Folder"), TestFixture.Json);

        var response = await client2.GetAsync("/api/folders");
        var folders = await response.Content.ReadFromJsonAsync<JsonElement[]>(TestFixture.Json);
        Assert.NotNull(folders);
        Assert.Empty(folders);
    }

    [Fact]
    public async Task GetFolder_ReturnsFolder()
    {
        var (client, _, _) = await TestFixture.CreateAuthenticatedClientAsync(_factory);

        var createResp = await client.PostAsJsonAsync("/api/folders", CreateFolderRequest(), TestFixture.Json);
        var created = await createResp.Content.ReadFromJsonAsync<JsonElement>(TestFixture.Json);
        var id = created.GetProperty("id").GetString();

        var response = await client.GetAsync($"/api/folders/{id}");
        Assert.Equal(HttpStatusCode.OK, response.StatusCode);

        var folder = await response.Content.ReadFromJsonAsync<JsonElement>(TestFixture.Json);
        Assert.Equal("Test Folder", folder.GetProperty("name").GetString());
        Assert.True(folder.TryGetProperty("encrypted_folder_key", out _));
    }

    [Fact]
    public async Task GetFolder_OtherUserFolder_Returns403Or404()
    {
        var (client1, _, _) = await TestFixture.CreateAuthenticatedClientAsync(_factory, "Owner");
        var (client2, _, _) = await TestFixture.CreateAuthenticatedClientAsync(_factory, "Outsider");

        var createResp = await client1.PostAsJsonAsync("/api/folders", CreateFolderRequest(), TestFixture.Json);
        var created = await createResp.Content.ReadFromJsonAsync<JsonElement>(TestFixture.Json);
        var id = created.GetProperty("id").GetString();

        var response = await client2.GetAsync($"/api/folders/{id}");
        Assert.True(
            response.StatusCode is HttpStatusCode.NotFound or HttpStatusCode.Forbidden,
            $"Expected 403 or 404, got {response.StatusCode}");
    }

    [Fact]
    public async Task DeleteFolder_ReturnsNoContent()
    {
        var (client, _, _) = await TestFixture.CreateAuthenticatedClientAsync(_factory);

        var createResp = await client.PostAsJsonAsync("/api/folders", CreateFolderRequest(), TestFixture.Json);
        var created = await createResp.Content.ReadFromJsonAsync<JsonElement>(TestFixture.Json);
        var id = created.GetProperty("id").GetString();

        var response = await client.DeleteAsync($"/api/folders/{id}");
        Assert.Equal(HttpStatusCode.NoContent, response.StatusCode);

        // Verify it's gone
        var getResp = await client.GetAsync($"/api/folders/{id}");
        Assert.Equal(HttpStatusCode.NotFound, getResp.StatusCode);
    }

    [Fact]
    public async Task DeleteFolder_NonOwner_Returns403()
    {
        var (client1, _, _) = await TestFixture.CreateAuthenticatedClientAsync(_factory, "Owner");
        var (client2, _, _) = await TestFixture.CreateAuthenticatedClientAsync(_factory, "NotOwner");

        var createResp = await client1.PostAsJsonAsync("/api/folders", CreateFolderRequest(), TestFixture.Json);
        var created = await createResp.Content.ReadFromJsonAsync<JsonElement>(TestFixture.Json);
        var id = created.GetProperty("id").GetString();

        var response = await client2.DeleteAsync($"/api/folders/{id}");
        Assert.True(
            response.StatusCode is HttpStatusCode.Forbidden or HttpStatusCode.NotFound,
            $"Expected 403 or 404, got {response.StatusCode}");
    }

    [Fact]
    public async Task DeleteFolder_CascadesSubFoldersAndFiles()
    {
        var (client, _, _) = await TestFixture.CreateAuthenticatedClientAsync(_factory);

        // Create parent
        var parentResp = await client.PostAsJsonAsync("/api/folders", CreateFolderRequest("Parent"), TestFixture.Json);
        var parent = await parentResp.Content.ReadFromJsonAsync<JsonElement>(TestFixture.Json);
        var parentId = parent.GetProperty("id").GetString();

        // Create child
        await client.PostAsJsonAsync("/api/folders", new
        {
            name = "Child",
            parent_folder_id = parentId,
            encrypted_folder_key = Convert.ToBase64String(new byte[32]),
            kem_algorithm = "Kyber768"
        }, TestFixture.Json);

        // Delete parent
        var deleteResp = await client.DeleteAsync($"/api/folders/{parentId}");
        Assert.Equal(HttpStatusCode.NoContent, deleteResp.StatusCode);

        // Verify child is also gone (list should be empty)
        var listResp = await client.GetAsync("/api/folders");
        var folders = await listResp.Content.ReadFromJsonAsync<JsonElement[]>(TestFixture.Json);
        Assert.NotNull(folders);
        Assert.Empty(folders);
    }

    [Fact]
    public async Task CreateFolder_WithoutAuth_Returns401()
    {
        var client = _factory.CreateClient();
        var response = await client.PostAsJsonAsync("/api/folders", CreateFolderRequest(), TestFixture.Json);
        Assert.Equal(HttpStatusCode.Unauthorized, response.StatusCode);
    }
}
```

**Step 2: Run tests**

Run: `dotnet test tests/SsdidDrive.Api.Tests/ --filter "FolderTests" -v minimal`
Expected: All 12 tests PASS

**Step 3: Commit**

```bash
git add tests/SsdidDrive.Api.Tests/Integration/FolderTests.cs
git commit -m "test(api): add folder CRUD integration tests"
```

---

### Task 6: File upload/download/delete integration tests

**Files:**
- Create: `tests/SsdidDrive.Api.Tests/Integration/FileTests.cs`

**Step 1: Write the tests**

```csharp
using System.Net;
using System.Net.Http.Headers;
using System.Net.Http.Json;
using System.Text;
using System.Text.Json;
using SsdidDrive.Api.Tests.Infrastructure;

namespace SsdidDrive.Api.Tests.Integration;

public class FileTests : IClassFixture<SsdidDriveFactory>
{
    private readonly SsdidDriveFactory _factory;

    public FileTests(SsdidDriveFactory factory) => _factory = factory;

    private static HttpContent CreateMultipartFile(string content = "encrypted-file-content", string fileName = "test.bin")
    {
        var fileContent = new ByteArrayContent(Encoding.UTF8.GetBytes(content));
        fileContent.Headers.ContentType = new MediaTypeHeaderValue("application/octet-stream");
        var form = new MultipartFormDataContent();
        form.Add(fileContent, "file", fileName);
        return form;
    }

    private async Task<string> CreateFolderAsync(HttpClient client)
    {
        var resp = await client.PostAsJsonAsync("/api/folders", new
        {
            name = "Test Folder",
            encrypted_folder_key = Convert.ToBase64String(new byte[32]),
            kem_algorithm = "Kyber768"
        }, TestFixture.Json);
        var body = await resp.Content.ReadFromJsonAsync<JsonElement>(TestFixture.Json);
        return body.GetProperty("id").GetString()!;
    }

    [Fact]
    public async Task UploadFile_ReturnsCreated()
    {
        var (client, _, _) = await TestFixture.CreateAuthenticatedClientAsync(_factory);
        var folderId = await CreateFolderAsync(client);

        var encKey = Convert.ToBase64String(new byte[32]);
        var nonce = Convert.ToBase64String(new byte[12]);
        var url = $"/api/folders/{folderId}/files?encrypted_file_key={encKey}&nonce={nonce}&encryption_algorithm=AES-256-GCM";

        var response = await client.PostAsync(url, CreateMultipartFile());
        Assert.Equal(HttpStatusCode.Created, response.StatusCode);

        var body = await response.Content.ReadFromJsonAsync<JsonElement>(TestFixture.Json);
        Assert.Equal("test.bin", body.GetProperty("name").GetString());
        Assert.Equal("AES-256-GCM", body.GetProperty("encryption_algorithm").GetString());
        Assert.True(body.GetProperty("size").GetInt64() > 0);
    }

    [Fact]
    public async Task UploadFile_NonExistentFolder_Returns404()
    {
        var (client, _, _) = await TestFixture.CreateAuthenticatedClientAsync(_factory);
        var url = $"/api/folders/{Guid.NewGuid()}/files?encrypted_file_key=abc&nonce=abc&encryption_algorithm=AES";

        var response = await client.PostAsync(url, CreateMultipartFile());
        Assert.Equal(HttpStatusCode.NotFound, response.StatusCode);
    }

    [Fact]
    public async Task ListFiles_ReturnsFilesInFolder()
    {
        var (client, _, _) = await TestFixture.CreateAuthenticatedClientAsync(_factory);
        var folderId = await CreateFolderAsync(client);

        var encKey = Convert.ToBase64String(new byte[32]);
        var nonce = Convert.ToBase64String(new byte[12]);
        var url = $"/api/folders/{folderId}/files?encrypted_file_key={encKey}&nonce={nonce}&encryption_algorithm=AES-256-GCM";
        await client.PostAsync(url, CreateMultipartFile("content1", "file1.bin"));
        await client.PostAsync(url, CreateMultipartFile("content2", "file2.bin"));

        var response = await client.GetAsync($"/api/folders/{folderId}/files");
        Assert.Equal(HttpStatusCode.OK, response.StatusCode);

        var files = await response.Content.ReadFromJsonAsync<JsonElement[]>(TestFixture.Json);
        Assert.NotNull(files);
        Assert.Equal(2, files.Length);
    }

    [Fact]
    public async Task DownloadFile_ReturnsFileContent()
    {
        var (client, _, _) = await TestFixture.CreateAuthenticatedClientAsync(_factory);
        var folderId = await CreateFolderAsync(client);

        var encKey = Convert.ToBase64String(new byte[32]);
        var nonce = Convert.ToBase64String(new byte[12]);
        var url = $"/api/folders/{folderId}/files?encrypted_file_key={encKey}&nonce={nonce}&encryption_algorithm=AES-256-GCM";
        var uploadResp = await client.PostAsync(url, CreateMultipartFile("my-encrypted-data"));
        var uploaded = await uploadResp.Content.ReadFromJsonAsync<JsonElement>(TestFixture.Json);
        var fileId = uploaded.GetProperty("id").GetString();

        var response = await client.GetAsync($"/api/files/{fileId}/download");
        Assert.Equal(HttpStatusCode.OK, response.StatusCode);

        var content = await response.Content.ReadAsStringAsync();
        Assert.Equal("my-encrypted-data", content);
    }

    [Fact]
    public async Task DownloadFile_OtherUser_Returns403Or404()
    {
        var (client1, _, _) = await TestFixture.CreateAuthenticatedClientAsync(_factory, "Uploader");
        var (client2, _, _) = await TestFixture.CreateAuthenticatedClientAsync(_factory, "Outsider");
        var folderId = await CreateFolderAsync(client1);

        var encKey = Convert.ToBase64String(new byte[32]);
        var nonce = Convert.ToBase64String(new byte[12]);
        var url = $"/api/folders/{folderId}/files?encrypted_file_key={encKey}&nonce={nonce}&encryption_algorithm=AES-256-GCM";
        var uploadResp = await client1.PostAsync(url, CreateMultipartFile());
        var uploaded = await uploadResp.Content.ReadFromJsonAsync<JsonElement>(TestFixture.Json);
        var fileId = uploaded.GetProperty("id").GetString();

        var response = await client2.GetAsync($"/api/files/{fileId}/download");
        Assert.True(
            response.StatusCode is HttpStatusCode.Forbidden or HttpStatusCode.NotFound,
            $"Expected 403 or 404, got {response.StatusCode}");
    }

    [Fact]
    public async Task DeleteFile_ReturnsNoContent()
    {
        var (client, _, _) = await TestFixture.CreateAuthenticatedClientAsync(_factory);
        var folderId = await CreateFolderAsync(client);

        var encKey = Convert.ToBase64String(new byte[32]);
        var nonce = Convert.ToBase64String(new byte[12]);
        var url = $"/api/folders/{folderId}/files?encrypted_file_key={encKey}&nonce={nonce}&encryption_algorithm=AES-256-GCM";
        var uploadResp = await client.PostAsync(url, CreateMultipartFile());
        var uploaded = await uploadResp.Content.ReadFromJsonAsync<JsonElement>(TestFixture.Json);
        var fileId = uploaded.GetProperty("id").GetString();

        var response = await client.DeleteAsync($"/api/files/{fileId}");
        Assert.Equal(HttpStatusCode.NoContent, response.StatusCode);

        var downloadResp = await client.GetAsync($"/api/files/{fileId}/download");
        Assert.Equal(HttpStatusCode.NotFound, downloadResp.StatusCode);
    }

    [Fact]
    public async Task DeleteFile_NonOwner_Returns403()
    {
        var (client1, _, _) = await TestFixture.CreateAuthenticatedClientAsync(_factory, "Uploader");
        var (client2, _, _) = await TestFixture.CreateAuthenticatedClientAsync(_factory, "NotOwner");
        var folderId = await CreateFolderAsync(client1);

        var encKey = Convert.ToBase64String(new byte[32]);
        var nonce = Convert.ToBase64String(new byte[12]);
        var url = $"/api/folders/{folderId}/files?encrypted_file_key={encKey}&nonce={nonce}&encryption_algorithm=AES-256-GCM";
        var uploadResp = await client1.PostAsync(url, CreateMultipartFile());
        var uploaded = await uploadResp.Content.ReadFromJsonAsync<JsonElement>(TestFixture.Json);
        var fileId = uploaded.GetProperty("id").GetString();

        var response = await client2.DeleteAsync($"/api/files/{fileId}");
        Assert.True(
            response.StatusCode is HttpStatusCode.Forbidden or HttpStatusCode.NotFound,
            $"Expected 403 or 404, got {response.StatusCode}");
    }

    [Fact]
    public async Task UploadFile_WithoutAuth_Returns401()
    {
        var client = _factory.CreateClient();
        var url = $"/api/folders/{Guid.NewGuid()}/files?encrypted_file_key=x&nonce=x&encryption_algorithm=AES";
        var response = await client.PostAsync(url, CreateMultipartFile());
        Assert.Equal(HttpStatusCode.Unauthorized, response.StatusCode);
    }
}
```

**Step 2: Run tests**

Run: `dotnet test tests/SsdidDrive.Api.Tests/ --filter "FileTests" -v minimal`
Expected: All 8 tests PASS

**Step 3: Commit**

```bash
git add tests/SsdidDrive.Api.Tests/Integration/FileTests.cs
git commit -m "test(api): add file upload/download/delete integration tests"
```

---

### Task 7: Share CRUD integration tests

**Files:**
- Create: `tests/SsdidDrive.Api.Tests/Integration/ShareTests.cs`

**Step 1: Write the tests**

```csharp
using System.Net;
using System.Net.Http.Json;
using System.Text;
using System.Text.Json;
using System.Net.Http.Headers;
using SsdidDrive.Api.Tests.Infrastructure;

namespace SsdidDrive.Api.Tests.Integration;

public class ShareTests : IClassFixture<SsdidDriveFactory>
{
    private readonly SsdidDriveFactory _factory;

    public ShareTests(SsdidDriveFactory factory) => _factory = factory;

    private async Task<string> CreateFolderAsync(HttpClient client)
    {
        var resp = await client.PostAsJsonAsync("/api/folders", new
        {
            name = "Shared Folder",
            encrypted_folder_key = Convert.ToBase64String(new byte[32]),
            kem_algorithm = "Kyber768"
        }, TestFixture.Json);
        var body = await resp.Content.ReadFromJsonAsync<JsonElement>(TestFixture.Json);
        return body.GetProperty("id").GetString()!;
    }

    [Fact]
    public async Task CreateShare_Folder_ReturnsCreated()
    {
        var (owner, ownerId, _) = await TestFixture.CreateAuthenticatedClientAsync(_factory, "Owner");
        var (_, recipientId, _) = await TestFixture.CreateAuthenticatedClientAsync(_factory, "Recipient");

        var folderId = await CreateFolderAsync(owner);

        var response = await owner.PostAsJsonAsync("/api/shares", new
        {
            resource_id = folderId,
            resource_type = "folder",
            shared_with_id = recipientId,
            permission = "read",
            encrypted_key = Convert.ToBase64String(new byte[64]),
            kem_algorithm = "Kyber768"
        }, TestFixture.Json);

        Assert.Equal(HttpStatusCode.Created, response.StatusCode);

        var share = await response.Content.ReadFromJsonAsync<JsonElement>(TestFixture.Json);
        Assert.Equal(folderId, share.GetProperty("resource_id").GetString());
        Assert.Equal("folder", share.GetProperty("resource_type").GetString());
        Assert.Equal("read", share.GetProperty("permission").GetString());
    }

    [Fact]
    public async Task CreateShare_SelfShare_Returns400()
    {
        var (owner, ownerId, _) = await TestFixture.CreateAuthenticatedClientAsync(_factory, "SelfSharer");
        var folderId = await CreateFolderAsync(owner);

        var response = await owner.PostAsJsonAsync("/api/shares", new
        {
            resource_id = folderId,
            resource_type = "folder",
            shared_with_id = ownerId,
            permission = "read",
            encrypted_key = Convert.ToBase64String(new byte[64])
        }, TestFixture.Json);

        Assert.Equal(HttpStatusCode.BadRequest, response.StatusCode);
    }

    [Fact]
    public async Task CreateShare_DuplicateShare_Returns409()
    {
        var (owner, _, _) = await TestFixture.CreateAuthenticatedClientAsync(_factory, "Owner");
        var (_, recipientId, _) = await TestFixture.CreateAuthenticatedClientAsync(_factory, "Recipient");
        var folderId = await CreateFolderAsync(owner);

        var shareReq = new
        {
            resource_id = folderId,
            resource_type = "folder",
            shared_with_id = recipientId,
            permission = "read",
            encrypted_key = Convert.ToBase64String(new byte[64])
        };

        var first = await owner.PostAsJsonAsync("/api/shares", shareReq, TestFixture.Json);
        Assert.Equal(HttpStatusCode.Created, first.StatusCode);

        var second = await owner.PostAsJsonAsync("/api/shares", shareReq, TestFixture.Json);
        Assert.Equal(HttpStatusCode.Conflict, second.StatusCode);
    }

    [Fact]
    public async Task CreateShare_NonOwner_Returns403()
    {
        var (owner, _, _) = await TestFixture.CreateAuthenticatedClientAsync(_factory, "Owner");
        var (notOwner, _, _) = await TestFixture.CreateAuthenticatedClientAsync(_factory, "NotOwner");
        var (_, recipientId, _) = await TestFixture.CreateAuthenticatedClientAsync(_factory, "Recipient");

        var folderId = await CreateFolderAsync(owner);

        var response = await notOwner.PostAsJsonAsync("/api/shares", new
        {
            resource_id = folderId,
            resource_type = "folder",
            shared_with_id = recipientId,
            permission = "read",
            encrypted_key = Convert.ToBase64String(new byte[64])
        }, TestFixture.Json);

        Assert.True(
            response.StatusCode is HttpStatusCode.Forbidden or HttpStatusCode.NotFound,
            $"Expected 403 or 404, got {response.StatusCode}");
    }

    [Fact]
    public async Task ListCreatedShares_ReturnsSharesICreated()
    {
        var (owner, _, _) = await TestFixture.CreateAuthenticatedClientAsync(_factory, "ShareOwner");
        var (_, recipientId, _) = await TestFixture.CreateAuthenticatedClientAsync(_factory, "ShareRecipient");
        var folderId = await CreateFolderAsync(owner);

        await owner.PostAsJsonAsync("/api/shares", new
        {
            resource_id = folderId,
            resource_type = "folder",
            shared_with_id = recipientId,
            permission = "read",
            encrypted_key = Convert.ToBase64String(new byte[64])
        }, TestFixture.Json);

        var response = await owner.GetAsync("/api/shares/created");
        Assert.Equal(HttpStatusCode.OK, response.StatusCode);

        var shares = await response.Content.ReadFromJsonAsync<JsonElement[]>(TestFixture.Json);
        Assert.NotNull(shares);
        Assert.Single(shares);
    }

    [Fact]
    public async Task ListReceivedShares_ReturnsSharesSharedWithMe()
    {
        var (owner, _, _) = await TestFixture.CreateAuthenticatedClientAsync(_factory, "Sharer");
        var (recipient, recipientId, _) = await TestFixture.CreateAuthenticatedClientAsync(_factory, "Receiver");
        var folderId = await CreateFolderAsync(owner);

        await owner.PostAsJsonAsync("/api/shares", new
        {
            resource_id = folderId,
            resource_type = "folder",
            shared_with_id = recipientId,
            permission = "read",
            encrypted_key = Convert.ToBase64String(new byte[64])
        }, TestFixture.Json);

        var response = await recipient.GetAsync("/api/shares/received");
        Assert.Equal(HttpStatusCode.OK, response.StatusCode);

        var shares = await response.Content.ReadFromJsonAsync<JsonElement[]>(TestFixture.Json);
        Assert.NotNull(shares);
        Assert.Single(shares);
        Assert.True(shares[0].TryGetProperty("encrypted_key", out _));
    }

    [Fact]
    public async Task RevokeShare_ReturnsNoContent()
    {
        var (owner, _, _) = await TestFixture.CreateAuthenticatedClientAsync(_factory, "Revoker");
        var (_, recipientId, _) = await TestFixture.CreateAuthenticatedClientAsync(_factory, "Revoked");
        var folderId = await CreateFolderAsync(owner);

        var createResp = await owner.PostAsJsonAsync("/api/shares", new
        {
            resource_id = folderId,
            resource_type = "folder",
            shared_with_id = recipientId,
            permission = "read",
            encrypted_key = Convert.ToBase64String(new byte[64])
        }, TestFixture.Json);
        var share = await createResp.Content.ReadFromJsonAsync<JsonElement>(TestFixture.Json);
        var shareId = share.GetProperty("id").GetString();

        var response = await owner.DeleteAsync($"/api/shares/{shareId}");
        Assert.Equal(HttpStatusCode.NoContent, response.StatusCode);

        // Verify it's gone from created list
        var listResp = await owner.GetAsync("/api/shares/created");
        var shares = await listResp.Content.ReadFromJsonAsync<JsonElement[]>(TestFixture.Json);
        Assert.NotNull(shares);
        Assert.Empty(shares);
    }

    [Fact]
    public async Task RevokeShare_NonSharer_Returns403()
    {
        var (owner, _, _) = await TestFixture.CreateAuthenticatedClientAsync(_factory, "ShareMaker");
        var (recipient, recipientId, _) = await TestFixture.CreateAuthenticatedClientAsync(_factory, "ShareTarget");
        var folderId = await CreateFolderAsync(owner);

        var createResp = await owner.PostAsJsonAsync("/api/shares", new
        {
            resource_id = folderId,
            resource_type = "folder",
            shared_with_id = recipientId,
            permission = "read",
            encrypted_key = Convert.ToBase64String(new byte[64])
        }, TestFixture.Json);
        var share = await createResp.Content.ReadFromJsonAsync<JsonElement>(TestFixture.Json);
        var shareId = share.GetProperty("id").GetString();

        // Recipient tries to revoke — not allowed
        var response = await recipient.DeleteAsync($"/api/shares/{shareId}");
        Assert.True(
            response.StatusCode is HttpStatusCode.Forbidden or HttpStatusCode.NotFound,
            $"Expected 403 or 404, got {response.StatusCode}");
    }

    [Fact]
    public async Task SharedFolder_RecipientCanListFiles()
    {
        var (owner, _, _) = await TestFixture.CreateAuthenticatedClientAsync(_factory, "FolderOwner");
        var (recipient, recipientId, _) = await TestFixture.CreateAuthenticatedClientAsync(_factory, "FolderViewer");
        var folderId = await CreateFolderAsync(owner);

        // Owner uploads a file
        var encKey = Convert.ToBase64String(new byte[32]);
        var nonce = Convert.ToBase64String(new byte[12]);
        var url = $"/api/folders/{folderId}/files?encrypted_file_key={encKey}&nonce={nonce}&encryption_algorithm=AES-256-GCM";
        await owner.PostAsync(url, new MultipartFormDataContent
        {
            { new ByteArrayContent("data"u8.ToArray()), "file", "shared-file.bin" }
        });

        // Owner shares folder with recipient
        await owner.PostAsJsonAsync("/api/shares", new
        {
            resource_id = folderId,
            resource_type = "folder",
            shared_with_id = recipientId,
            permission = "read",
            encrypted_key = Convert.ToBase64String(new byte[64])
        }, TestFixture.Json);

        // Recipient can list files in shared folder
        var response = await recipient.GetAsync($"/api/folders/{folderId}/files");
        Assert.Equal(HttpStatusCode.OK, response.StatusCode);

        var files = await response.Content.ReadFromJsonAsync<JsonElement[]>(TestFixture.Json);
        Assert.NotNull(files);
        Assert.Single(files);
    }

    [Fact]
    public async Task SharedFolder_RecipientCanDownloadFile()
    {
        var (owner, _, _) = await TestFixture.CreateAuthenticatedClientAsync(_factory, "DlOwner");
        var (recipient, recipientId, _) = await TestFixture.CreateAuthenticatedClientAsync(_factory, "DlRecipient");
        var folderId = await CreateFolderAsync(owner);

        // Upload file
        var encKey = Convert.ToBase64String(new byte[32]);
        var nonce = Convert.ToBase64String(new byte[12]);
        var url = $"/api/folders/{folderId}/files?encrypted_file_key={encKey}&nonce={nonce}&encryption_algorithm=AES-256-GCM";
        var uploadResp = await owner.PostAsync(url, new MultipartFormDataContent
        {
            { new ByteArrayContent("shared-data"u8.ToArray()), "file", "dl.bin" }
        });
        var file = await uploadResp.Content.ReadFromJsonAsync<JsonElement>(TestFixture.Json);
        var fileId = file.GetProperty("id").GetString();

        // Share folder
        await owner.PostAsJsonAsync("/api/shares", new
        {
            resource_id = folderId,
            resource_type = "folder",
            shared_with_id = recipientId,
            permission = "read",
            encrypted_key = Convert.ToBase64String(new byte[64])
        }, TestFixture.Json);

        // Recipient downloads
        var dlResp = await recipient.GetAsync($"/api/files/{fileId}/download");
        Assert.Equal(HttpStatusCode.OK, dlResp.StatusCode);
        var content = await dlResp.Content.ReadAsStringAsync();
        Assert.Equal("shared-data", content);
    }

    [Fact]
    public async Task RevokedShare_RecipientCannotAccessFolder()
    {
        var (owner, _, _) = await TestFixture.CreateAuthenticatedClientAsync(_factory, "RevokeOwner");
        var (recipient, recipientId, _) = await TestFixture.CreateAuthenticatedClientAsync(_factory, "RevokeTarget");
        var folderId = await CreateFolderAsync(owner);

        // Share
        var shareResp = await owner.PostAsJsonAsync("/api/shares", new
        {
            resource_id = folderId,
            resource_type = "folder",
            shared_with_id = recipientId,
            permission = "read",
            encrypted_key = Convert.ToBase64String(new byte[64])
        }, TestFixture.Json);
        var share = await shareResp.Content.ReadFromJsonAsync<JsonElement>(TestFixture.Json);
        var shareId = share.GetProperty("id").GetString();

        // Revoke
        await owner.DeleteAsync($"/api/shares/{shareId}");

        // Recipient can no longer access
        var folderResp = await recipient.GetAsync($"/api/folders/{folderId}");
        Assert.True(
            folderResp.StatusCode is HttpStatusCode.Forbidden or HttpStatusCode.NotFound,
            $"Expected 403 or 404 after revoke, got {folderResp.StatusCode}");
    }
}
```

**Step 2: Run tests**

Run: `dotnet test tests/SsdidDrive.Api.Tests/ --filter "ShareTests" -v minimal`
Expected: All 12 tests PASS

**Step 3: Commit**

```bash
git add tests/SsdidDrive.Api.Tests/Integration/ShareTests.cs
git commit -m "test(api): add share CRUD and access control integration tests"
```

---

### Task 8: User profile and keys integration tests

**Files:**
- Create: `tests/SsdidDrive.Api.Tests/Integration/UserTests.cs`

**Step 1: Write the tests**

```csharp
using System.Net;
using System.Net.Http.Json;
using System.Text.Json;
using SsdidDrive.Api.Tests.Infrastructure;

namespace SsdidDrive.Api.Tests.Integration;

public class UserTests : IClassFixture<SsdidDriveFactory>
{
    private readonly SsdidDriveFactory _factory;

    public UserTests(SsdidDriveFactory factory) => _factory = factory;

    [Fact]
    public async Task GetProfile_ReturnsCurrentUser()
    {
        var (client, userId, _) = await TestFixture.CreateAuthenticatedClientAsync(_factory, "ProfileUser");

        var response = await client.GetAsync("/api/me");
        Assert.Equal(HttpStatusCode.OK, response.StatusCode);

        var body = await response.Content.ReadFromJsonAsync<JsonElement>(TestFixture.Json);
        Assert.Equal("ProfileUser", body.GetProperty("display_name").GetString());
        Assert.Equal(userId.ToString(), body.GetProperty("id").GetString());
    }

    [Fact]
    public async Task UpdateProfile_ChangesDisplayName()
    {
        var (client, _, _) = await TestFixture.CreateAuthenticatedClientAsync(_factory, "OldName");

        var response = await client.PutAsJsonAsync("/api/me", new
        {
            display_name = "NewName"
        }, TestFixture.Json);
        Assert.Equal(HttpStatusCode.OK, response.StatusCode);

        // Verify change persisted
        var getResp = await client.GetAsync("/api/me");
        var body = await getResp.Content.ReadFromJsonAsync<JsonElement>(TestFixture.Json);
        Assert.Equal("NewName", body.GetProperty("display_name").GetString());
    }

    [Fact]
    public async Task UpdateKeys_StoresAndRetrieves()
    {
        var (client, _, _) = await TestFixture.CreateAuthenticatedClientAsync(_factory);

        var masterKey = Convert.ToBase64String(new byte[32]);
        var privateKeys = Convert.ToBase64String(new byte[128]);
        var salt = Convert.ToBase64String(new byte[16]);

        var updateResp = await client.PutAsJsonAsync("/api/me/keys", new
        {
            public_keys = "{\"kem\":\"test\"}",
            encrypted_master_key = masterKey,
            encrypted_private_keys = privateKeys,
            key_derivation_salt = salt
        }, TestFixture.Json);
        Assert.Equal(HttpStatusCode.OK, updateResp.StatusCode);

        var getResp = await client.GetAsync("/api/me/keys");
        Assert.Equal(HttpStatusCode.OK, getResp.StatusCode);

        var keys = await getResp.Content.ReadFromJsonAsync<JsonElement>(TestFixture.Json);
        Assert.Equal("{\"kem\":\"test\"}", keys.GetProperty("public_keys").GetString());
        Assert.Equal(masterKey, keys.GetProperty("encrypted_master_key").GetString());
    }

    [Fact]
    public async Task GetPublicKey_NoAuthRequired()
    {
        var (_, userId, _) = await TestFixture.CreateAuthenticatedClientAsync(_factory, "KeyHolder");

        var client = _factory.CreateClient(); // No auth
        var response = await client.GetAsync($"/api/users/{userId}/public-key");
        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
    }

    [Fact]
    public async Task GetPublicKey_NonExistentUser_Returns404()
    {
        var client = _factory.CreateClient();
        var response = await client.GetAsync($"/api/users/{Guid.NewGuid()}/public-key");
        Assert.Equal(HttpStatusCode.NotFound, response.StatusCode);
    }

    [Fact]
    public async Task ListTenantUsers_ReturnsUsersInSameTenant()
    {
        var (client, _, _) = await TestFixture.CreateAuthenticatedClientAsync(_factory, "TenantUser");

        var response = await client.GetAsync("/api/users");
        Assert.Equal(HttpStatusCode.OK, response.StatusCode);

        var users = await response.Content.ReadFromJsonAsync<JsonElement[]>(TestFixture.Json);
        Assert.NotNull(users);
        Assert.True(users.Length >= 1);
    }
}
```

**Step 2: Run tests**

Run: `dotnet test tests/SsdidDrive.Api.Tests/ --filter "UserTests" -v minimal`
Expected: All 6 tests PASS

**Step 3: Commit**

```bash
git add tests/SsdidDrive.Api.Tests/Integration/UserTests.cs
git commit -m "test(api): add user profile and keys integration tests"
```

---

### Task 9: End-to-end secure file sharing scenario test

**Files:**
- Create: `tests/SsdidDrive.Api.Tests/Integration/SecureFileSharingE2eTests.cs`

This test covers the full secure file sharing workflow: create folder → upload file → share with another user → recipient accesses → owner revokes → recipient loses access.

**Step 1: Write the test**

```csharp
using System.Net;
using System.Net.Http.Json;
using System.Text.Json;
using SsdidDrive.Api.Tests.Infrastructure;

namespace SsdidDrive.Api.Tests.Integration;

public class SecureFileSharingE2eTests : IClassFixture<SsdidDriveFactory>
{
    private readonly SsdidDriveFactory _factory;

    public SecureFileSharingE2eTests(SsdidDriveFactory factory) => _factory = factory;

    [Fact]
    public async Task FullSecureFileSharingWorkflow()
    {
        // ── Setup: Two users ──
        var (alice, aliceId, _) = await TestFixture.CreateAuthenticatedClientAsync(_factory, "Alice");
        var (bob, bobId, _) = await TestFixture.CreateAuthenticatedClientAsync(_factory, "Bob");

        // ── Step 1: Alice creates a folder with KEM-encrypted key ──
        var createFolderResp = await alice.PostAsJsonAsync("/api/folders", new
        {
            name = "Secret Documents",
            encrypted_folder_key = Convert.ToBase64String(new byte[32]),
            kem_algorithm = "Kyber768"
        }, TestFixture.Json);
        Assert.Equal(HttpStatusCode.Created, createFolderResp.StatusCode);
        var folder = await createFolderResp.Content.ReadFromJsonAsync<JsonElement>(TestFixture.Json);
        var folderId = folder.GetProperty("id").GetString()!;

        // ── Step 2: Alice uploads encrypted file ──
        var encKey = Convert.ToBase64String(new byte[32]);
        var nonce = Convert.ToBase64String(new byte[12]);
        var uploadUrl = $"/api/folders/{folderId}/files?encrypted_file_key={encKey}&nonce={nonce}&encryption_algorithm=AES-256-GCM";
        var uploadResp = await alice.PostAsync(uploadUrl, new MultipartFormDataContent
        {
            { new ByteArrayContent("top-secret-encrypted-content"u8.ToArray()), "file", "report.pdf" }
        });
        Assert.Equal(HttpStatusCode.Created, uploadResp.StatusCode);
        var file = await uploadResp.Content.ReadFromJsonAsync<JsonElement>(TestFixture.Json);
        var fileId = file.GetProperty("id").GetString()!;

        // ── Step 3: Bob cannot access Alice's folder or file ──
        var bobFolderResp = await bob.GetAsync($"/api/folders/{folderId}");
        Assert.True(bobFolderResp.StatusCode is HttpStatusCode.Forbidden or HttpStatusCode.NotFound);

        var bobDownloadResp = await bob.GetAsync($"/api/files/{fileId}/download");
        Assert.True(bobDownloadResp.StatusCode is HttpStatusCode.Forbidden or HttpStatusCode.NotFound);

        // ── Step 4: Alice shares folder with Bob (re-encapsulated key) ──
        var shareResp = await alice.PostAsJsonAsync("/api/shares", new
        {
            resource_id = folderId,
            resource_type = "folder",
            shared_with_id = bobId,
            permission = "read",
            encrypted_key = Convert.ToBase64String(new byte[64]),
            kem_algorithm = "Kyber768"
        }, TestFixture.Json);
        Assert.Equal(HttpStatusCode.Created, shareResp.StatusCode);
        var share = await shareResp.Content.ReadFromJsonAsync<JsonElement>(TestFixture.Json);
        var shareId = share.GetProperty("id").GetString()!;

        // ── Step 5: Bob can now see the share ──
        var bobSharesResp = await bob.GetAsync("/api/shares/received");
        var bobShares = await bobSharesResp.Content.ReadFromJsonAsync<JsonElement[]>(TestFixture.Json);
        Assert.NotNull(bobShares);
        Assert.Single(bobShares);
        Assert.True(bobShares[0].TryGetProperty("encrypted_key", out _));

        // ── Step 6: Bob can now access the folder and download the file ──
        var bobFolderResp2 = await bob.GetAsync($"/api/folders/{folderId}");
        Assert.Equal(HttpStatusCode.OK, bobFolderResp2.StatusCode);

        var bobFilesResp = await bob.GetAsync($"/api/folders/{folderId}/files");
        Assert.Equal(HttpStatusCode.OK, bobFilesResp.StatusCode);

        var bobDownloadResp2 = await bob.GetAsync($"/api/files/{fileId}/download");
        Assert.Equal(HttpStatusCode.OK, bobDownloadResp2.StatusCode);
        var content = await bobDownloadResp2.Content.ReadAsStringAsync();
        Assert.Equal("top-secret-encrypted-content", content);

        // ── Step 7: Alice revokes Bob's share ──
        var revokeResp = await alice.DeleteAsync($"/api/shares/{shareId}");
        Assert.Equal(HttpStatusCode.NoContent, revokeResp.StatusCode);

        // ── Step 8: Bob can no longer access ──
        var bobFolderResp3 = await bob.GetAsync($"/api/folders/{folderId}");
        Assert.True(bobFolderResp3.StatusCode is HttpStatusCode.Forbidden or HttpStatusCode.NotFound);

        var bobDownloadResp3 = await bob.GetAsync($"/api/files/{fileId}/download");
        Assert.True(bobDownloadResp3.StatusCode is HttpStatusCode.Forbidden or HttpStatusCode.NotFound);

        // ── Step 9: Alice can still access her own folder and file ──
        var aliceFolderResp = await alice.GetAsync($"/api/folders/{folderId}");
        Assert.Equal(HttpStatusCode.OK, aliceFolderResp.StatusCode);

        var aliceDownloadResp = await alice.GetAsync($"/api/files/{fileId}/download");
        Assert.Equal(HttpStatusCode.OK, aliceDownloadResp.StatusCode);
    }

    [Fact]
    public async Task WriteShareHolder_CanUploadToSharedFolder()
    {
        var (alice, _, _) = await TestFixture.CreateAuthenticatedClientAsync(_factory, "WriteShareAlice");
        var (bob, bobId, _) = await TestFixture.CreateAuthenticatedClientAsync(_factory, "WriteShareBob");

        // Alice creates folder
        var folderResp = await alice.PostAsJsonAsync("/api/folders", new
        {
            name = "Collaborative Folder",
            encrypted_folder_key = Convert.ToBase64String(new byte[32]),
            kem_algorithm = "Kyber768"
        }, TestFixture.Json);
        var folder = await folderResp.Content.ReadFromJsonAsync<JsonElement>(TestFixture.Json);
        var folderId = folder.GetProperty("id").GetString()!;

        // Alice shares folder with Bob (WRITE permission)
        await alice.PostAsJsonAsync("/api/shares", new
        {
            resource_id = folderId,
            resource_type = "folder",
            shared_with_id = bobId,
            permission = "write",
            encrypted_key = Convert.ToBase64String(new byte[64])
        }, TestFixture.Json);

        // Bob can upload to Alice's folder
        var encKey = Convert.ToBase64String(new byte[32]);
        var nonce = Convert.ToBase64String(new byte[12]);
        var url = $"/api/folders/{folderId}/files?encrypted_file_key={encKey}&nonce={nonce}&encryption_algorithm=AES-256-GCM";
        var uploadResp = await bob.PostAsync(url, new MultipartFormDataContent
        {
            { new ByteArrayContent("bob-contributed"u8.ToArray()), "file", "bob-file.txt" }
        });
        Assert.Equal(HttpStatusCode.Created, uploadResp.StatusCode);

        // Alice can see Bob's file
        var filesResp = await alice.GetAsync($"/api/folders/{folderId}/files");
        var files = await filesResp.Content.ReadFromJsonAsync<JsonElement[]>(TestFixture.Json);
        Assert.NotNull(files);
        Assert.Contains(files, f => f.GetProperty("name").GetString() == "bob-file.txt");
    }

    [Fact]
    public async Task ReadShareHolder_CannotUploadToSharedFolder()
    {
        var (alice, _, _) = await TestFixture.CreateAuthenticatedClientAsync(_factory, "ReadOnlyAlice");
        var (bob, bobId, _) = await TestFixture.CreateAuthenticatedClientAsync(_factory, "ReadOnlyBob");

        // Alice creates folder
        var folderResp = await alice.PostAsJsonAsync("/api/folders", new
        {
            name = "ReadOnly Folder",
            encrypted_folder_key = Convert.ToBase64String(new byte[32]),
            kem_algorithm = "Kyber768"
        }, TestFixture.Json);
        var folder = await folderResp.Content.ReadFromJsonAsync<JsonElement>(TestFixture.Json);
        var folderId = folder.GetProperty("id").GetString()!;

        // Share with READ only
        await alice.PostAsJsonAsync("/api/shares", new
        {
            resource_id = folderId,
            resource_type = "folder",
            shared_with_id = bobId,
            permission = "read",
            encrypted_key = Convert.ToBase64String(new byte[64])
        }, TestFixture.Json);

        // Bob tries to upload — should fail
        var encKey = Convert.ToBase64String(new byte[32]);
        var nonce = Convert.ToBase64String(new byte[12]);
        var url = $"/api/folders/{folderId}/files?encrypted_file_key={encKey}&nonce={nonce}&encryption_algorithm=AES-256-GCM";
        var uploadResp = await bob.PostAsync(url, new MultipartFormDataContent
        {
            { new ByteArrayContent("blocked"u8.ToArray()), "file", "blocked.txt" }
        });
        Assert.Equal(HttpStatusCode.Forbidden, uploadResp.StatusCode);
    }
}
```

**Step 2: Run tests**

Run: `dotnet test tests/SsdidDrive.Api.Tests/ --filter "SecureFileSharingE2eTests" -v minimal`
Expected: All 3 tests PASS

**Step 3: Commit**

```bash
git add tests/SsdidDrive.Api.Tests/Integration/SecureFileSharingE2eTests.cs
git commit -m "test(api): add end-to-end secure file sharing scenario tests"
```

---

### Task 10: Run full test suite and verify

**Step 1: Run all tests**

Run: `dotnet test tests/SsdidDrive.Api.Tests/ -v minimal`
Expected: All tests pass (existing unit tests + ~50 new integration tests)

**Step 2: Check test count**

Run: `dotnet test tests/SsdidDrive.Api.Tests/ -v minimal --list-tests 2>/dev/null | wc -l`
Expected: ~95+ tests total (46 existing + ~50 new)

**Step 3: Commit any remaining changes**

If any fixes were needed during the run, commit them:
```bash
git add -A tests/SsdidDrive.Api.Tests/
git commit -m "test(api): fix integration test issues from full suite run"
```
