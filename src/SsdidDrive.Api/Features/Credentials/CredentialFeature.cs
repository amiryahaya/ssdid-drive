namespace SsdidDrive.Api.Features.Credentials;

public static class CredentialFeature
{
    public static void MapCredentialFeature(this IEndpointRouteBuilder routes)
    {
        var group = routes.MapGroup("/api/credentials").WithTags("Credentials");

        ListCredentials.Map(group);
        RenameCredential.Map(group);
        DeleteCredential.Map(group);
        BeginAddCredential.Map(group);
        CompleteAddCredential.Map(group);
    }
}
