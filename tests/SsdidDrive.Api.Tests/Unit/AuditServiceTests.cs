using Microsoft.EntityFrameworkCore;
using SsdidDrive.Api.Data;
using SsdidDrive.Api.Data.Entities;
using SsdidDrive.Api.Services;

namespace SsdidDrive.Api.Tests.Unit;

public class AuditServiceTests : IDisposable
{
    private readonly AppDbContext _db;
    private readonly AuditService _sut;
    private readonly Guid _actorId;

    public AuditServiceTests()
    {
        var options = new DbContextOptionsBuilder<AppDbContext>()
            .UseSqlite("DataSource=:memory:")
            .Options;

        _db = new AppDbContext(options);
        _db.Database.OpenConnection();
        _db.Database.EnsureCreated();

        // Seed a user for FK constraints
        _actorId = Guid.NewGuid();
        var tenant = new Tenant
        {
            Id = Guid.NewGuid(),
            Name = "Test",
            Slug = $"test-{Guid.NewGuid():N}"[..32],
            CreatedAt = DateTimeOffset.UtcNow,
            UpdatedAt = DateTimeOffset.UtcNow
        };
        _db.Tenants.Add(tenant);
        _db.Users.Add(new User
        {
            Id = _actorId,
            Did = $"did:ssdid:test-{Guid.NewGuid():N}",
            DisplayName = "Audit Actor",
            Status = UserStatus.Active,
            TenantId = tenant.Id,
            CreatedAt = DateTimeOffset.UtcNow,
            UpdatedAt = DateTimeOffset.UtcNow
        });
        _db.SaveChanges();

        _sut = new AuditService(_db);
    }

    // ── 1. LogAsync persists entry with all fields ──────────────────────

    [Fact]
    public async Task LogAsync_PersistsEntryWithAllFields()
    {
        var targetId = Guid.NewGuid();
        await _sut.LogAsync(
            _actorId, "user.suspended",
            targetType: "user", targetId: targetId,
            details: "Suspended for policy violation");

        var entry = await _db.AuditLog.FirstOrDefaultAsync(a => a.ActorId == _actorId);
        Assert.NotNull(entry);
        Assert.Equal("user.suspended", entry!.Action);
        Assert.Equal("user", entry.TargetType);
        Assert.Equal(targetId, entry.TargetId);
        Assert.Equal("Suspended for policy violation", entry.Details);
        Assert.True(entry.CreatedAt <= DateTimeOffset.UtcNow);
        Assert.NotEqual(Guid.Empty, entry.Id);
    }

    // ── 2. LogAsync with null optional fields persists correctly ─────────

    [Fact]
    public async Task LogAsync_NullOptionalFields_Persists()
    {
        await _sut.LogAsync(_actorId, "session.created");

        var entry = await _db.AuditLog.FirstOrDefaultAsync(
            a => a.ActorId == _actorId && a.Action == "session.created");
        Assert.NotNull(entry);
        Assert.Null(entry!.TargetType);
        Assert.Null(entry.TargetId);
        Assert.Null(entry.Details);
    }

    public void Dispose()
    {
        _db.Database.CloseConnection();
        _db.Dispose();
    }
}
