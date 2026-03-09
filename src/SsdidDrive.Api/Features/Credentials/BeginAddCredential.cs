using System.Collections.Concurrent;
using System.Security.Cryptography;
using SsdidDrive.Api.Common;

namespace SsdidDrive.Api.Features.Credentials;

public static class BeginAddCredential
{
    // In-memory challenge store with TTL for MVP.
    // Key: userId, Value: (challenge, createdAt)
    // TODO: Move to ISessionStore for horizontal scaling — this static store only works on a single instance.
    internal static readonly ConcurrentDictionary<Guid, (string Challenge, DateTimeOffset CreatedAt)> PendingChallenges = new();
    private static readonly TimeSpan ChallengeTtl = TimeSpan.FromMinutes(5);

    public static void Map(RouteGroupBuilder group) =>
        group.MapPost("/webauthn/begin", Handle);

    private static IResult Handle(CurrentUserAccessor accessor)
    {
        var user = accessor.User!;

        // Generate a random challenge
        var challengeBytes = RandomNumberGenerator.GetBytes(32);
        var challenge = Convert.ToBase64String(challengeBytes);

        // Store challenge for verification in CompleteAddCredential
        PendingChallenges[user.Id] = (challenge, DateTimeOffset.UtcNow);

        // Clean up expired challenges opportunistically
        CleanupExpired();

        return Results.Ok(new
        {
            challenge,
            rp = new { name = "SSDID Drive", id = "drive.ssdid.my" },
            user = new
            {
                id = Convert.ToBase64String(user.Id.ToByteArray()),
                name = user.Did,
                display_name = user.DisplayName ?? user.Did
            },
            pub_key_cred_params = new[] { new { type = "public-key", alg = -7 } },
            timeout = 60000,
            attestation = "none",
            authenticator_selection = new { user_verification = "preferred" }
        });
    }

    private static void CleanupExpired()
    {
        var now = DateTimeOffset.UtcNow;
        foreach (var (key, entry) in PendingChallenges)
        {
            if (now - entry.CreatedAt > ChallengeTtl)
                PendingChallenges.TryRemove(key, out _);
        }
    }
}
