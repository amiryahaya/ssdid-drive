namespace SsdidDrive.Api.Services;

public interface IStorageService
{
    Task<string> StoreAsync(Guid tenantId, Guid folderId, Guid fileId, Stream content, CancellationToken ct);
    Task<Stream> RetrieveAsync(string storagePath, CancellationToken ct);
    Task DeleteAsync(string storagePath, CancellationToken ct);
}
