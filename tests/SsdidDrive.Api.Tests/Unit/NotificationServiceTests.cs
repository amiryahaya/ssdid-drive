using System.Net;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Logging.Abstractions;
using Microsoft.Extensions.Options;
using SsdidDrive.Api.Data;
using SsdidDrive.Api.Data.Entities;
using SsdidDrive.Api.Services;

namespace SsdidDrive.Api.Tests.Unit;

public class NotificationServiceTests : IDisposable
{
    private readonly AppDbContext _db;
    private readonly TrackingPushHandler _pushHandler;
    private readonly PushService _pushService;
    private readonly NotificationService _sut;
    private readonly Guid _userId;

    public NotificationServiceTests()
    {
        var options = new DbContextOptionsBuilder<AppDbContext>()
            .UseSqlite("DataSource=:memory:")
            .Options;

        _db = new AppDbContext(options);
        _db.Database.OpenConnection();
        _db.Database.EnsureCreated();

        // Seed a user for FK constraints
        _userId = Guid.NewGuid();
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
            Id = _userId,
            Did = $"did:ssdid:test-{Guid.NewGuid():N}",
            DisplayName = "Test User",
            Status = UserStatus.Active,
            TenantId = tenant.Id,
            CreatedAt = DateTimeOffset.UtcNow,
            UpdatedAt = DateTimeOffset.UtcNow
        });
        _db.SaveChanges();

        // PushService with tracking handler — enabled so we can verify push calls
        _pushHandler = new TrackingPushHandler();
        var httpClient = new HttpClient(_pushHandler);
        var pushOptions = Options.Create(new OneSignalOptions { AppId = "app", ApiKey = "key" });
        _pushService = new PushService(httpClient, pushOptions, NullLogger<PushService>.Instance);

        _sut = new NotificationService(_db, _pushService);
    }

    // ── 1. CreateAsync adds notification to DbContext ────────────────────

    [Fact]
    public async Task CreateAsync_AddsNotificationToDbContext()
    {
        await _sut.CreateAsync(_userId, "test", "Title", "Message");
        await _db.SaveChangesAsync();

        var notification = await _db.Notifications.FirstOrDefaultAsync(n => n.UserId == _userId);
        Assert.NotNull(notification);
        Assert.Equal("test", notification!.Type);
        Assert.Equal("Title", notification.Title);
        Assert.Equal("Message", notification.Message);
        Assert.False(notification.IsRead);
    }

    // ── 2. CreateAsync triggers push when skipPush is false ──────────────

    [Fact]
    public async Task CreateAsync_TriggersPushWhenSkipPushFalse()
    {
        await _sut.CreateAsync(_userId, "test", "PushTitle", "PushMsg", skipPush: false);

        // Give fire-and-forget a moment to execute
        await Task.Delay(100);

        Assert.True(_pushHandler.CallCount >= 1, "Expected at least one push HTTP call");
    }

    // ── 3. CreateAsync skips push when skipPush is true ──────────────────

    [Fact]
    public async Task CreateAsync_SkipsPushWhenSkipPushTrue()
    {
        await _sut.CreateAsync(_userId, "test", "NoPush", "NoPushMsg", skipPush: true);

        // Give any potential fire-and-forget a moment
        await Task.Delay(100);

        Assert.Equal(0, _pushHandler.CallCount);
    }

    public void Dispose()
    {
        _db.Database.CloseConnection();
        _db.Dispose();
    }

    private class TrackingPushHandler : HttpMessageHandler
    {
        private int _callCount;
        public int CallCount => _callCount;

        protected override Task<HttpResponseMessage> SendAsync(
            HttpRequestMessage request, CancellationToken cancellationToken)
        {
            Interlocked.Increment(ref _callCount);
            return Task.FromResult(new HttpResponseMessage(HttpStatusCode.OK)
            {
                Content = new StringContent("{}")
            });
        }
    }
}
