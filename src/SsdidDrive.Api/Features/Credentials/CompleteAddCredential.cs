using SsdidDrive.Api.Common;
using SsdidDrive.Api.Data;
using SsdidDrive.Api.Data.Entities;

namespace SsdidDrive.Api.Features.Credentials;

public static class CompleteAddCredential
{
    private record Request(string CredentialId, string PublicKey, string? Name);

    public static void Map(RouteGroupBuilder group) =>
        group.MapPost("/webauthn/complete", Handle);

    private static async Task<IResult> Handle(Request request, AppDbContext db, CurrentUserAccessor accessor, CancellationToken ct)
    {
        var user = accessor.User!;

        if (string.IsNullOrWhiteSpace(request.CredentialId))
            return AppError.BadRequest("credential_id is required").ToProblemResult();

        if (string.IsNullOrWhiteSpace(request.PublicKey))
            return AppError.BadRequest("public_key is required").ToProblemResult();

        // For MVP, verify that a challenge was issued (don't do full attestation)
        if (!BeginAddCredential.PendingChallenges.TryRemove(user.Id, out var pending))
            return AppError.BadRequest("No pending WebAuthn challenge. Call begin first.").ToProblemResult();

        var elapsed = DateTimeOffset.UtcNow - pending.CreatedAt;
        if (elapsed > TimeSpan.FromMinutes(5))
            return AppError.BadRequest("WebAuthn challenge expired").ToProblemResult();

        byte[] publicKeyBytes;
        try
        {
            publicKeyBytes = Convert.FromBase64String(request.PublicKey);
        }
        catch (FormatException)
        {
            return AppError.BadRequest("Invalid public_key encoding").ToProblemResult();
        }

        var credential = new WebAuthnCredential
        {
            Id = Guid.NewGuid(),
            UserId = user.Id,
            CredentialId = request.CredentialId,
            PublicKey = publicKeyBytes,
            Name = request.Name,
            SignCount = 0,
            CreatedAt = DateTimeOffset.UtcNow
        };

        db.WebAuthnCredentials.Add(credential);
        await db.SaveChangesAsync(ct);

        return Results.Created($"/api/credentials/{credential.Id}", new
        {
            credential.Id,
            credential.CredentialId,
            credential.Name,
            credential.LastUsedAt,
            credential.CreatedAt
        });
    }
}
