using System.Collections.Concurrent;
using SsdidDrive.Api.Services;

namespace SsdidDrive.Api.Tests.Infrastructure;

public class MemoryStorageService : IStorageService
{
    private readonly ConcurrentDictionary<string, byte[]> _store = new();

    public async Task<string> StoreAsync(Guid tenantId, Guid folderId, Guid fileId, Stream content, CancellationToken ct)
    {
        var path = Path.Combine(tenantId.ToString(), folderId.ToString(), fileId.ToString());
        using var ms = new MemoryStream();
        await content.CopyToAsync(ms, ct);
        _store[path] = ms.ToArray();
        return path;
    }

    public Task<Stream> RetrieveAsync(string storagePath, CancellationToken ct)
    {
        if (!_store.TryGetValue(storagePath, out var data))
            throw new FileNotFoundException($"Not found: {storagePath}");
        return Task.FromResult<Stream>(new MemoryStream(data));
    }

    public Task DeleteAsync(string storagePath, CancellationToken ct)
    {
        _store.TryRemove(storagePath, out _);
        return Task.CompletedTask;
    }
}
