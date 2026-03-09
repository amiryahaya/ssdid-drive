namespace SsdidDrive.Api.Features.Files;

public static class FileFeature
{
    public static void MapFileFeature(this IEndpointRouteBuilder routes)
    {
        var group = routes.MapGroup("/api").WithTags("Files");

        UploadFile.Map(group);
        ListFiles.Map(group);
        DownloadFile.Map(group);
        DeleteFile.Map(group);
        RenameFile.Map(group);
    }
}
