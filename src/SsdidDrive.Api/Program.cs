using System.Text.Json;
using System.Threading.RateLimiting;
using Microsoft.AspNetCore.RateLimiting;
using Microsoft.EntityFrameworkCore;
using SsdidDrive.Api.Common;
using SsdidDrive.Api.Data;
using SsdidDrive.Api.Features.Auth;
using SsdidDrive.Api.Features.Files;
using SsdidDrive.Api.Features.Folders;
using SsdidDrive.Api.Features.Health;
using SsdidDrive.Api.Features.Devices;
using SsdidDrive.Api.Features.Invitations;
using SsdidDrive.Api.Features.Shares;
using SsdidDrive.Api.Features.Tenants;
using SsdidDrive.Api.Features.Notifications;
using SsdidDrive.Api.Features.Users;
using SsdidDrive.Api.Services;
using SsdidDrive.Api.Middleware;
using SsdidDrive.Api.Ssdid;
using SsdidDrive.Api.Crypto;
using SsdidDrive.Api.Crypto.Providers;

var builder = WebApplication.CreateBuilder(args);

// ── Problem Details + Global Exception Handler ──
builder.Services.AddProblemDetails();
builder.Services.AddExceptionHandler<GlobalExceptionHandler>();

// ── JSON snake_case serialization ──
builder.Services.ConfigureHttpJsonOptions(options =>
{
    options.SerializerOptions.PropertyNamingPolicy = JsonNamingPolicy.SnakeCaseLower;
});

// ── Database ──
builder.Services.AddDbContext<AppDbContext>(options =>
    options.UseNpgsql(builder.Configuration.GetConnectionString("Default")));

// ── Scoped services ──
builder.Services.AddScoped<CurrentUserAccessor>();

// ── Storage ──
builder.Services.AddSingleton<IStorageService, LocalStorageService>();

// ── Crypto Providers ──
builder.Services.AddSingleton<ICryptoProvider, Ed25519Provider>();
builder.Services.AddSingleton<ICryptoProvider, EcdsaProvider>();
builder.Services.AddSingleton<ICryptoProvider, MlDsaProvider>();
builder.Services.AddSingleton<ICryptoProvider, SlhDsaProvider>();
builder.Services.AddSingleton<ICryptoProvider, KazSignProvider>();
builder.Services.AddSingleton<CryptoProviderFactory>();

// ── SSDID Services ──
builder.Services.AddSingleton<SsdidIdentity>(sp =>
{
    var factory = sp.GetRequiredService<CryptoProviderFactory>();
    var identityPath = builder.Configuration["Ssdid:IdentityPath"]
        ?? Path.Combine(builder.Environment.ContentRootPath, "data", "server-identity.json");
    var algorithmType = builder.Configuration["Ssdid:Algorithm"] ?? "KazSignVerificationKey2024";
    return SsdidIdentity.LoadOrCreate(identityPath, algorithmType, factory);
});

// ── Session Store (Redis or in-memory) ──
var redisConnection = builder.Configuration.GetConnectionString("Redis");
if (!string.IsNullOrEmpty(redisConnection))
{
    builder.Services.AddStackExchangeRedisCache(options =>
    {
        options.Configuration = redisConnection;
        options.InstanceName = "ssdid:";
    });
    builder.Services.AddSingleton<StackExchange.Redis.IConnectionMultiplexer>(sp =>
        StackExchange.Redis.ConnectionMultiplexer.Connect(redisConnection));
    builder.Services.AddSingleton<RedisSessionStore>();
    builder.Services.AddSingleton<ISessionStore>(sp => sp.GetRequiredService<RedisSessionStore>());
    builder.Services.AddSingleton<ISseNotificationBus>(sp => sp.GetRequiredService<RedisSessionStore>());
}
else
{
    builder.Services.AddSingleton<SessionStore>();
    builder.Services.AddSingleton<ISessionStore>(sp => sp.GetRequiredService<SessionStore>());
    builder.Services.AddSingleton<ISseNotificationBus>(sp => sp.GetRequiredService<SessionStore>());
    builder.Services.AddHostedService(sp => sp.GetRequiredService<SessionStore>());
}

builder.Services.AddHttpClient<RegistryClient>(client =>
{
    var registryUrl = builder.Configuration["Ssdid:RegistryUrl"] ?? "https://registry.ssdid.my";
    client.BaseAddress = new Uri(registryUrl);
    client.Timeout = TimeSpan.FromSeconds(10);
});

builder.Services.AddScoped<SsdidAuthService>();
builder.Services.AddScoped<NotificationService>();
builder.Services.AddHostedService<ServerRegistrationService>();

// ── Rate Limiting ──
builder.Services.AddRateLimiter(options =>
{
    options.RejectionStatusCode = 429;
    var isTesting = builder.Environment.EnvironmentName == "Testing";
    options.AddFixedWindowLimiter("auth", limiter =>
    {
        limiter.PermitLimit = isTesting ? 10_000 : 20;
        limiter.Window = TimeSpan.FromMinutes(1);
        limiter.QueueLimit = 0;
    });
});

// ── OpenAPI ──
builder.Services.AddOpenApi();

// ── CORS ──
builder.Services.AddCors(options =>
{
    options.AddDefaultPolicy(policy =>
    {
        var origins = builder.Configuration.GetSection("Cors:Origins").Get<string[]>()
            ?? ["http://localhost:3000", "http://localhost:5173"];
        policy.WithOrigins(origins)
            .AllowAnyHeader()
            .AllowAnyMethod()
            .AllowCredentials();
    });
});

var app = builder.Build();

// ── Startup warnings ──
if (!app.Environment.IsDevelopment())
{
    var keyPath = app.Configuration["Ssdid:IdentityPath"]
        ?? Path.Combine(app.Environment.ContentRootPath, "data", "server-identity.json");
    if (File.Exists(keyPath))
        app.Logger.LogWarning(
            "Server identity private key is stored in plaintext at {Path}. " +
            "Consider using a key vault or HSM for production.", keyPath);

    if (string.IsNullOrEmpty(app.Configuration.GetConnectionString("Redis")))
        app.Logger.LogWarning(
            "SessionStore is in-memory only (single-instance). " +
            "Set ConnectionStrings:Redis for horizontal scaling.");
}

// ── Pipeline ──
app.UseExceptionHandler();
app.UseStatusCodePages();

if (app.Environment.IsDevelopment())
{
    app.MapOpenApi();
}

app.UseCors();
app.UseRateLimiter();

// Auth middleware — endpoints marked [SsdidPublic] skip authentication.
// All /api endpoints go through the middleware; it checks endpoint metadata.
app.UseWhen(
    context => context.Request.Path.StartsWithSegments("/api"),
    branch => branch.UseMiddleware<SsdidAuthMiddleware>());

// ── Features ──
app.MapHealthFeature();
app.MapAuthFeature();
app.MapUserFeature();
app.MapFolderFeature();
app.MapFileFeature();
app.MapShareFeature();
app.MapDeviceFeature();
app.MapInvitationFeature();
app.MapTenantFeature();
app.MapNotificationFeature();

// ── Auto-migrate (guarded) ──
if (app.Environment.IsDevelopment() ||
    string.Equals(Environment.GetEnvironmentVariable("ENABLE_AUTO_MIGRATE"), "true", StringComparison.OrdinalIgnoreCase))
{
    using var scope = app.Services.CreateScope();
    var db = scope.ServiceProvider.GetRequiredService<AppDbContext>();
    await db.Database.MigrateAsync();
}

app.Run();
