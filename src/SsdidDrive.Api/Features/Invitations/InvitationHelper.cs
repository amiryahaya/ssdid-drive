using Microsoft.EntityFrameworkCore;
using SsdidDrive.Api.Data;

namespace SsdidDrive.Api.Features.Invitations;

public static class InvitationHelper
{
    public static async Task<string> GenerateShortCode(AppDbContext db, string tenantSlug, CancellationToken ct)
    {
        const string chars = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789";
        var prefix = tenantSlug.Split('-')[0].ToUpperInvariant();
        if (prefix.Length > 6) prefix = prefix[..6];

        for (var attempt = 0; attempt < 10; attempt++)
        {
            var suffix = new string(Enumerable.Range(0, 4)
                .Select(_ => chars[System.Security.Cryptography.RandomNumberGenerator.GetInt32(chars.Length)])
                .ToArray());
            var code = $"{prefix}-{suffix}";
            if (!await db.Invitations.AnyAsync(i => i.ShortCode == code, ct))
                return code;
        }

        for (var fallbackAttempt = 0; fallbackAttempt < 5; fallbackAttempt++)
        {
            var fallbackSuffix = new string(Enumerable.Range(0, 6)
                .Select(_ => chars[System.Security.Cryptography.RandomNumberGenerator.GetInt32(chars.Length)])
                .ToArray());
            var fallbackCode = $"{prefix}-{fallbackSuffix}";
            if (!await db.Invitations.AnyAsync(i => i.ShortCode == fallbackCode, ct))
                return fallbackCode;
        }

        throw new InvalidOperationException("Short code space exhausted for this tenant; please retry");
    }

    public static string GenerateToken()
    {
        return Convert.ToBase64String(System.Security.Cryptography.RandomNumberGenerator.GetBytes(32))
            .Replace("+", "-").Replace("/", "_").TrimEnd('=');
    }
}
