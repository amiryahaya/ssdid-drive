namespace SsdidDrive.Api.Features.Folders;

public static class FolderFeature
{
    public static void MapFolderFeature(this IEndpointRouteBuilder routes)
    {
        var group = routes.MapGroup("/api/folders").WithTags("Folders");

        CreateFolder.Map(group);
        ListFolders.Map(group);
        GetRootFolder.Map(group);
        GetRootFolderContents.Map(group);
        GetFolder.Map(group);
        RenameFolder.Map(group);
        DeleteFolder.Map(group);
        GetFolderKey.Map(group);
        RotateFolderKey.Map(group);
    }
}
