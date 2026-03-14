using Microsoft.EntityFrameworkCore;
using SsdidDrive.Api.Common;
using SsdidDrive.Api.Data;
using SsdidDrive.Api.Data.Entities;
using SsdidDrive.Api.Services;

namespace SsdidDrive.Api.Features.Account;

public static class LinkOidc
{
    public record Request(string Provider, string IdToken);

    public static void Map(RouteGroupBuilder group) =>
        group.MapPost("/logins/oidc", Handle);

    private static async Task<IResult> Handle(
        Request req,
        CurrentUserAccessor accessor,
        AppDbContext db,
        OidcTokenValidator validator,
        AuditService auditService,
        CancellationToken ct)
    {
        if (string.IsNullOrWhiteSpace(req.Provider) || string.IsNullOrWhiteSpace(req.IdToken))
            return AppError.BadRequest("Provider and id_token are required").ToProblemResult();

        var claims = await validator.ValidateAsync(req.Provider, req.IdToken, ct);
        if (!claims.IsSuccess)
            return claims.Error!.ToProblemResult();

        var oidcClaims = claims.Value!;
        var providerEnum = req.Provider.ToLowerInvariant() switch
        {
            "google" => LoginProvider.Google,
            "microsoft" => LoginProvider.Microsoft,
            _ => (LoginProvider?)null,
        };

        if (providerEnum is null)
            return AppError.BadRequest("Unsupported provider").ToProblemResult();

        var existing = await db.Logins
            .AnyAsync(l => l.Provider == providerEnum.Value
                && l.ProviderSubject == oidcClaims.Subject, ct);

        if (existing)
            return AppError.Conflict($"This {req.Provider} account is already linked to another account").ToProblemResult();

        db.Logins.Add(new Login
        {
            AccountId = accessor.UserId,
            Provider = providerEnum.Value,
            ProviderSubject = oidcClaims.Subject,
        });
        await db.SaveChangesAsync(ct);

        await auditService.LogAsync(accessor.UserId, "auth.login.linked", "login", null,
            $"Provider: {req.Provider}", ct);

        return Results.Ok(new { linked = true, provider = req.Provider });
    }
}
