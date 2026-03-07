namespace SsdidDrive.Api.Services;

public class LocalStorageService : IStorageService
{
    private readonly string _basePath;

    public LocalStorageService(IWebHostEnvironment env)
    {
        _basePath = Path.Combine(env.ContentRootPath, "data", "files");
    }

    /// <summary>Test-only constructor that accepts an explicit base path.</summary>
    internal LocalStorageService(string basePath)
    {
        _basePath = basePath;
    }

    public async Task<string> StoreAsync(Guid tenantId, Guid folderId, Guid fileId, Stream content, CancellationToken ct)
    {
        var relativePath = Path.Combine(tenantId.ToString(), folderId.ToString(), fileId.ToString());
        var fullPath = Path.Combine(_basePath, relativePath);

        Directory.CreateDirectory(Path.GetDirectoryName(fullPath)!);

        await using var fs = new FileStream(fullPath, FileMode.Create, FileAccess.Write, FileShare.None);
        await content.CopyToAsync(fs, ct);

        return relativePath;
    }

    public Task<Stream> RetrieveAsync(string storagePath, CancellationToken ct)
    {
        var fullPath = Path.Combine(_basePath, storagePath);
        if (!File.Exists(fullPath))
            throw new FileNotFoundException("Stored file not found", fullPath);

        Stream fs = new FileStream(fullPath, FileMode.Open, FileAccess.Read, FileShare.Read);
        return Task.FromResult(fs);
    }

    public Task DeleteAsync(string storagePath, CancellationToken ct)
    {
        var fullPath = Path.Combine(_basePath, storagePath);
        if (File.Exists(fullPath))
            File.Delete(fullPath);

        return Task.CompletedTask;
    }
}
