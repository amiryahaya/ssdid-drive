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
