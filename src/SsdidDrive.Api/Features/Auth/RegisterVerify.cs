using Microsoft.EntityFrameworkCore;
using SsdidDrive.Api.Common;
using SsdidDrive.Api.Data;
using SsdidDrive.Api.Data.Entities;
using SsdidDrive.Api.Middleware;
using SsdidDrive.Api.Ssdid;

namespace SsdidDrive.Api.Features.Auth;

public static class RegisterVerify
{
    public record Request(string Did, string KeyId, string SignedChallenge, Dictionary<string, string>? SharedClaims = null);

    public static void Map(RouteGroupBuilder group) =>
        group.MapPost("/register/verify", Handle)
            .WithMetadata(new SsdidPublicAttribute());

    private static async Task<IResult> Handle(Request req, SsdidAuthService auth, AppDbContext db, IConfiguration config)
    {
        if (string.IsNullOrWhiteSpace(req.Did) || !req.Did.StartsWith("did:ssdid:") || req.Did.Length > 256)
            return AppError.BadRequest("Invalid DID format").ToProblemResult();
        if (string.IsNullOrWhiteSpace(req.KeyId) || req.KeyId.Length > 512)
            return AppError.BadRequest("Invalid KeyId").ToProblemResult();
        // PQC signatures are large: ML-DSA-44 ~3.2K, SLH-DSA-SHA2-256f ~66K base64 chars
        if (string.IsNullOrWhiteSpace(req.SignedChallenge) || req.SignedChallenge.Length > 100_000)
            return AppError.BadRequest("Invalid SignedChallenge").ToProblemResult();

        var result = await auth.HandleVerifyResponse(req.Did, req.KeyId, req.SignedChallenge);
        return await result.Match(
            async ok =>
            {
                var adminDid = config["Ssdid:AdminDid"];
                var user = await ProvisionUser(db, req.Did, req.SharedClaims, adminDid);
                return Results.Created($"/api/users/{user.Id}", ok);
            },
            err => Task.FromResult(err.ToProblemResult()));
    }

    private static async Task<User> ProvisionUser(AppDbContext db, string did, Dictionary<string, string>? claims, string? adminDid)
    {
        var user = await db.Users.FirstOrDefaultAsync(u => u.Did == did);
        if (user is not null)
        {
            // Update claims on re-registration (wallet may have updated profile)
            ApplyClaims(user, claims);
            await db.SaveChangesAsync();
            return user;
        }

        await using var tx = await db.Database.BeginTransactionAsync();
        try
        {
            var tenant = new Tenant
            {
                Id = Guid.NewGuid(),
                Name = "Personal",
                Slug = $"personal-{Guid.NewGuid():N}"
            };
            db.Tenants.Add(tenant);

            user = new User
            {
                Id = Guid.NewGuid(),
                Did = did,
                TenantId = tenant.Id,
                SystemRole = !string.IsNullOrEmpty(adminDid) && did == adminDid
                    ? SystemRole.SuperAdmin : null
            };
            ApplyClaims(user, claims);
            db.Users.Add(user);

            db.UserTenants.Add(new UserTenant
            {
                UserId = user.Id,
                TenantId = tenant.Id,
                Role = TenantRole.Owner
            });

            await db.SaveChangesAsync();
            await tx.CommitAsync();
            return user;
        }
        catch (DbUpdateException)
        {
            await tx.RollbackAsync();
            db.ChangeTracker.Clear();
            var existing = await db.Users.FirstOrDefaultAsync(u => u.Did == did);
            return existing ?? throw new InvalidOperationException(
                $"User provisioning failed for DID {did}: concurrent insert expected but user not found");
        }
    }

    private static void ApplyClaims(User user, Dictionary<string, string>? claims)
    {
        if (claims is null || claims.Count == 0) return;

        if (claims.TryGetValue("name", out var name) && !string.IsNullOrWhiteSpace(name))
            user.DisplayName = name.Trim()[..Math.Min(name.Trim().Length, 200)];

        if (claims.TryGetValue("email", out var email) && !string.IsNullOrWhiteSpace(email))
            user.Email = email.Trim()[..Math.Min(email.Trim().Length, 320)];
    }
}
