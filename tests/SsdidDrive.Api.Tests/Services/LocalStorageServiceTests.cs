using System.Text;
using SsdidDrive.Api.Services;

namespace SsdidDrive.Api.Tests.Services;

public class LocalStorageServiceTests : IDisposable
{
    private readonly string _tempDir;
    private readonly LocalStorageService _sut;

    public LocalStorageServiceTests()
    {
        _tempDir = Path.Combine(Path.GetTempPath(), "ssdid-storage-test-" + Guid.NewGuid());
        Directory.CreateDirectory(_tempDir);
        _sut = new LocalStorageService(_tempDir);
    }

    public void Dispose()
    {
        if (Directory.Exists(_tempDir))
            Directory.Delete(_tempDir, recursive: true);
    }

    [Fact]
    public async Task StoreAsync_WritesFileAndReturnsRelativePath()
    {
        var ct = TestContext.Current.CancellationToken;
        var tenantId = Guid.NewGuid();
        var folderId = Guid.NewGuid();
        var fileId = Guid.NewGuid();
        var content = "hello encrypted world"u8.ToArray();

        using var stream = new MemoryStream(content);
        var path = await _sut.StoreAsync(tenantId, folderId, fileId, stream, ct);

        Assert.Equal(Path.Combine(tenantId.ToString(), folderId.ToString(), fileId.ToString()), path);

        var fullPath = Path.Combine(_tempDir, path);
        Assert.True(File.Exists(fullPath));
        Assert.Equal(content, await File.ReadAllBytesAsync(fullPath, ct));
    }

    [Fact]
    public async Task RetrieveAsync_ReturnsStoredContent()
    {
        var ct = TestContext.Current.CancellationToken;
        var tenantId = Guid.NewGuid();
        var folderId = Guid.NewGuid();
        var fileId = Guid.NewGuid();
        var content = Encoding.UTF8.GetBytes("retrieve me");

        using var storeStream = new MemoryStream(content);
        var path = await _sut.StoreAsync(tenantId, folderId, fileId, storeStream, ct);

        await using var retrieved = await _sut.RetrieveAsync(path, ct);
        using var ms = new MemoryStream();
        await retrieved.CopyToAsync(ms, ct);

        Assert.Equal(content, ms.ToArray());
    }

    [Fact]
    public async Task RetrieveAsync_ThrowsFileNotFoundException_WhenMissing()
    {
        await Assert.ThrowsAsync<FileNotFoundException>(
            () => _sut.RetrieveAsync("nonexistent/path/file", TestContext.Current.CancellationToken));
    }

    [Fact]
    public async Task DeleteAsync_RemovesFile()
    {
        var ct = TestContext.Current.CancellationToken;
        var tenantId = Guid.NewGuid();
        var folderId = Guid.NewGuid();
        var fileId = Guid.NewGuid();

        using var stream = new MemoryStream("delete me"u8.ToArray());
        var path = await _sut.StoreAsync(tenantId, folderId, fileId, stream, ct);

        var fullPath = Path.Combine(_tempDir, path);
        Assert.True(File.Exists(fullPath));

        await _sut.DeleteAsync(path, ct);
        Assert.False(File.Exists(fullPath));
    }

    [Fact]
    public async Task DeleteAsync_DoesNotThrow_WhenFileAlreadyGone()
    {
        await _sut.DeleteAsync("missing/tenant/file", TestContext.Current.CancellationToken);
    }

    [Fact]
    public async Task StoreAsync_OverwritesExistingFile()
    {
        var ct = TestContext.Current.CancellationToken;
        var tenantId = Guid.NewGuid();
        var folderId = Guid.NewGuid();
        var fileId = Guid.NewGuid();

        using var stream1 = new MemoryStream("original"u8.ToArray());
        await _sut.StoreAsync(tenantId, folderId, fileId, stream1, ct);

        using var stream2 = new MemoryStream("overwritten"u8.ToArray());
        var path = await _sut.StoreAsync(tenantId, folderId, fileId, stream2, ct);

        await using var retrieved = await _sut.RetrieveAsync(path, ct);
        using var ms = new MemoryStream();
        await retrieved.CopyToAsync(ms, ct);
        Assert.Equal("overwritten", Encoding.UTF8.GetString(ms.ToArray()));
    }

    [Fact]
    public async Task RetrieveAsync_PathTraversal_ThrowsUnauthorizedAccess()
    {
        await Assert.ThrowsAsync<UnauthorizedAccessException>(
            () => _sut.RetrieveAsync("../../etc/passwd", TestContext.Current.CancellationToken));
    }

    [Fact]
    public async Task DeleteAsync_PathTraversal_ThrowsUnauthorizedAccess()
    {
        await Assert.ThrowsAsync<UnauthorizedAccessException>(
            () => _sut.DeleteAsync("../../etc/passwd", TestContext.Current.CancellationToken));
    }
}
