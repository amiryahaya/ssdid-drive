using Microsoft.EntityFrameworkCore;
using SsdidDrive.Api.Common;
using SsdidDrive.Api.Data;
using SsdidDrive.Api.Data.Entities;

namespace SsdidDrive.Api.Features.Devices;

public static class EnrollDevice
{
    private static readonly HashSet<string> ValidPlatforms = ["android", "ios", "macos", "windows", "linux"];

    public record Request(string DeviceFingerprint, string Platform, string? DeviceName, string? DeviceInfo, string KeyAlgorithm, string? PublicKey);

    public static void Map(RouteGroupBuilder group) =>
        group.MapPost("/", Handle);

    private static async Task<IResult> Handle(Request req, AppDbContext db, CurrentUserAccessor accessor, CancellationToken ct)
    {
        var user = accessor.User!;

        if (string.IsNullOrWhiteSpace(req.DeviceFingerprint))
            return AppError.BadRequest("Device fingerprint is required").ToProblemResult();

        if (string.IsNullOrWhiteSpace(req.Platform) || !ValidPlatforms.Contains(req.Platform))
            return AppError.BadRequest("Platform is required and must be one of: android, ios, macos, windows, linux").ToProblemResult();

        if (string.IsNullOrWhiteSpace(req.KeyAlgorithm))
            return AppError.BadRequest("Key algorithm is required").ToProblemResult();

        var exists = await db.Devices.AnyAsync(
            d => d.UserId == user.Id && d.DeviceFingerprint == req.DeviceFingerprint, ct);

        if (exists)
            return AppError.Conflict("A device with this fingerprint is already enrolled").ToProblemResult();

        var now = DateTimeOffset.UtcNow;
        var device = new Device
        {
            UserId = user.Id,
            DeviceFingerprint = req.DeviceFingerprint,
            Platform = req.Platform,
            DeviceName = req.DeviceName,
            DeviceInfo = req.DeviceInfo,
            KeyAlgorithm = req.KeyAlgorithm,
            PublicKey = string.IsNullOrEmpty(req.PublicKey) ? null : Convert.FromBase64String(req.PublicKey),
            Status = DeviceStatus.Active,
            CreatedAt = now,
            UpdatedAt = now
        };

        db.Devices.Add(device);
        await db.SaveChangesAsync(ct);

        return Results.Created($"/api/devices/{device.Id}", new
        {
            device.Id,
            device.UserId,
            device.DeviceFingerprint,
            device.DeviceName,
            device.Platform,
            device.DeviceInfo,
            Status = device.Status.ToString(),
            device.KeyAlgorithm,
            PublicKey = device.PublicKey is not null ? Convert.ToBase64String(device.PublicKey) : null,
            device.LastUsedAt,
            device.CreatedAt,
            device.UpdatedAt
        });
    }
}
