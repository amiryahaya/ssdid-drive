using SsdidDrive.Api.Common;

namespace SsdidDrive.Api.Features.Users;

public static class GetKeys
{
    public static void Map(RouteGroupBuilder group) =>
        group.MapGet("/me/keys", Handle);

    private static IResult Handle(CurrentUserAccessor accessor)
    {
        var user = accessor.User!;
        return Results.Ok(new
        {
            user.PublicKeys,
            encrypted_master_key = user.EncryptedMasterKey is not null
                ? Convert.ToBase64String(user.EncryptedMasterKey) : null,
            encrypted_private_keys = user.EncryptedPrivateKeys is not null
                ? Convert.ToBase64String(user.EncryptedPrivateKeys) : null,
            key_derivation_salt = user.KeyDerivationSalt is not null
                ? Convert.ToBase64String(user.KeyDerivationSalt) : null
        });
    }
}
