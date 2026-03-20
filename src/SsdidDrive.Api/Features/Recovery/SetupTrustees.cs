using SsdidDrive.Api.Common;
using SsdidDrive.Api.Data;
using SsdidDrive.Api.Data.Entities;
using Microsoft.EntityFrameworkCore;

namespace SsdidDrive.Api.Features.Recovery;

public static class SetupTrustees
{
    public record ShareEntry(Guid TrusteeUserId, string EncryptedShare, int ShareIndex);
    public record Request(int Threshold, List<ShareEntry> Shares);

    public static void Map(RouteGroupBuilder group) =>
        group.MapPost("/trustees/setup", Handle);

    private static async Task<IResult> Handle(
        Request req,
        AppDbContext db,
        CurrentUserAccessor accessor,
        CancellationToken ct)
    {
        var user = accessor.User!;

        if (req.Threshold < 2)
            return AppError.BadRequest("threshold must be at least 2").ToProblemResult();
        if (req.Shares is null || req.Shares.Count == 0)
            return AppError.BadRequest("shares are required").ToProblemResult();
        if (req.Threshold > req.Shares.Count)
            return AppError.BadRequest("threshold cannot exceed the number of shares").ToProblemResult();

        // Validate all trustees exist and are in user's tenant
        var trusteeUserIds = req.Shares.Select(s => s.TrusteeUserId).Distinct().ToList();
        if (trusteeUserIds.Count != req.Shares.Count)
            return AppError.BadRequest("duplicate trustee_user_id in shares").ToProblemResult();
        if (trusteeUserIds.Contains(user.Id))
            return AppError.BadRequest("cannot designate yourself as a trustee").ToProblemResult();

        List<Guid> validTrusteeIds;
        if (user.TenantId is not null)
        {
            // Trustees must be in the same tenant
            validTrusteeIds = await db.UserTenants
                .Where(ut => ut.TenantId == user.TenantId && trusteeUserIds.Contains(ut.UserId))
                .Select(ut => ut.UserId)
                .ToListAsync(ct);
        }
        else
        {
            // No tenant — just check users exist
            validTrusteeIds = await db.Users
                .Where(u => trusteeUserIds.Contains(u.Id))
                .Select(u => u.Id)
                .ToListAsync(ct);
        }

        if (validTrusteeIds.Count != trusteeUserIds.Count)
        {
            var missing = trusteeUserIds.Except(validTrusteeIds).ToList();
            return AppError.BadRequest($"trustees not found or not in your tenant: {string.Join(", ", missing)}").ToProblemResult();
        }

        // Get or validate recovery setup
        var setup = await db.RecoverySetups
            .Include(rs => rs.Trustees)
            .FirstOrDefaultAsync(rs => rs.UserId == user.Id && rs.IsActive, ct);
        if (setup is null)
            return AppError.NotFound("No active recovery setup found. Set up recovery first.").ToProblemResult();

        // Remove existing trustees (re-setup)
        if (setup.Trustees.Count > 0)
            db.RecoveryTrustees.RemoveRange(setup.Trustees);

        // Update threshold
        setup.Threshold = req.Threshold;

        // Create new trustees
        foreach (var share in req.Shares)
        {
            byte[] encryptedShare;
            try
            {
                encryptedShare = Convert.FromBase64String(share.EncryptedShare);
            }
            catch (FormatException)
            {
                return AppError.BadRequest($"encrypted_share for trustee {share.TrusteeUserId} must be valid base64").ToProblemResult();
            }

            db.RecoveryTrustees.Add(new RecoveryTrustee
            {
                RecoverySetupId = setup.Id,
                TrusteeUserId = share.TrusteeUserId,
                EncryptedShare = encryptedShare,
                ShareIndex = share.ShareIndex,
                CreatedAt = DateTimeOffset.UtcNow
            });
        }

        await db.SaveChangesAsync(ct);

        return Results.Ok(new
        {
            trustee_count = req.Shares.Count,
            threshold = req.Threshold
        });
    }
}
