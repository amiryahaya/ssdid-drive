using Microsoft.EntityFrameworkCore;
using SsdidDrive.Api.Common;
using SsdidDrive.Api.Data;
using SsdidDrive.Api.Data.Entities;

namespace SsdidDrive.Api.Features.Invitations;

public static class ListInvitations
{
    public static void Map(RouteGroupBuilder group)
    {
        group.MapGet("/", HandleReceived);
        group.MapGet("/sent", HandleSent);
    }

    private static async Task<IResult> HandleReceived(
        AppDbContext db,
        CurrentUserAccessor accessor,
        [AsParameters] PaginationParams pagination,
        CancellationToken ct)
    {
        var user = accessor.User!;

        // Match by InvitedUserId, or by email when InvitedUserId is null (unresolved at invite time)
        var query = db.Invitations
            .Where(i => i.Status == InvitationStatus.Pending
                && (i.InvitedUserId == user.Id
                    || (i.InvitedUserId == null && user.Email != null && i.Email == user.Email)));

        var total = await query.CountAsync(ct);

        var items = await query
            .OrderByDescending(i => i.CreatedAt)
            .Skip(pagination.Skip)
            .Take(pagination.Take)
            .ToListAsync(ct);
        var invitations = items.Select(ToDto).ToList();

        return Results.Ok(new PagedResponse<object>(invitations, total, pagination.NormalizedPage, pagination.Take));
    }

    private static async Task<IResult> HandleSent(
        AppDbContext db,
        CurrentUserAccessor accessor,
        [AsParameters] PaginationParams pagination,
        CancellationToken ct)
    {
        var user = accessor.User!;

        var query = db.Invitations.Where(i => i.InvitedById == user.Id);

        var total = await query.CountAsync(ct);

        var items = await query
            .OrderByDescending(i => i.CreatedAt)
            .Skip(pagination.Skip)
            .Take(pagination.Take)
            .ToListAsync(ct);
        var invitations = items.Select(ToDto).ToList();

        return Results.Ok(new PagedResponse<object>(invitations, total, pagination.NormalizedPage, pagination.Take));
    }

    private static object ToDto(Invitation i) => new
    {
        i.Id,
        i.TenantId,
        i.InvitedById,
        i.Email,
        i.InvitedUserId,
        Role = i.Role.ToString().ToLowerInvariant(),
        Status = i.Status.ToString().ToLowerInvariant(),
        i.ShortCode,
        i.Message,
        i.ExpiresAt,
        i.CreatedAt
    };
}
