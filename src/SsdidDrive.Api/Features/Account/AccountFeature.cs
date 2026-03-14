namespace SsdidDrive.Api.Features.Account;

public static class AccountFeature
{
    public static void MapAccountFeature(this WebApplication app)
    {
        var account = app.MapGroup("/api/account").WithTags("Account");

        ListLogins.Map(account);
        LinkEmail.Map(account);
        LinkEmailVerify.Map(account);
        LinkOidc.Map(account);
        UnlinkLogin.Map(account);
    }
}
