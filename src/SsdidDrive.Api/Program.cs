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
using SsdidDrive.Api.Features.Credentials;
using SsdidDrive.Api.Features.Admin;
using SsdidDrive.Api.Features.Recovery;
using SsdidDrive.Api.Features.Users;
using SsdidDrive.Api.Services;
using SsdidDrive.Api.Middleware;
using SsdidDrive.Api.Ssdid;
using SsdidDrive.Api.Crypto;
using SsdidDrive.Api.Crypto.Providers;
using SsdidDrive.Api.Health;
using Microsoft.Extensions.FileProviders;
using Serilog;
using StackExchange.Redis;

var builder = WebApplication.CreateBuilder(args);

// ── Serilog ──
builder.Host.UseSerilog((context, services, configuration) => configuration
    .ReadFrom.Configuration(context.Configuration)
    .ReadFrom.Services(services)
    .Enrich.FromLogContext()
    .Enrich.WithProperty("Application", "SsdidDrive.Api")
    .WriteTo.Console()
    .WriteTo.File(
        path: Path.Combine(builder.Environment.ContentRootPath, "logs", "ssdid-drive-.log"),
        rollingInterval: RollingInterval.Day,
        retainedFileCountLimit: 7,
        fileSizeLimitBytes: 50 * 1024 * 1024,
        rollOnFileSizeLimit: true,
        outputTemplate: "{Timestamp:yyyy-MM-dd HH:mm:ss.fff zzz} [{Level:u3}] {SourceContext} {Message:lj}{NewLine}{Exception}"));

// ── Sentry ──
builder.WebHost.UseSentry(options =>
{
    options.Dsn = builder.Configuration["Sentry:Dsn"];
    options.TracesSampleRate = builder.Configuration.GetValue("Sentry:TracesSampleRate", 0.2);
    options.SendDefaultPii = false;
    options.Environment = builder.Environment.EnvironmentName;
    options.Release = typeof(Program).Assembly.GetName().Version?.ToString() ?? "dev";
});

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

// ── Session Store Options ──
builder.Services.Configure<SessionStoreOptions>(
    builder.Configuration.GetSection(SessionStoreOptions.SectionName));

// ── Session Store (Redis or in-memory) ──
var redisConnection = builder.Configuration.GetConnectionString("Redis");
if (!string.IsNullOrEmpty(redisConnection))
{
    var redisOptions = ConfigurationOptions.Parse(redisConnection);
    redisOptions.AbortOnConnectFail = false;
    redisOptions.ConnectRetry = 3;
    redisOptions.ReconnectRetryPolicy = new ExponentialRetry(5000);

    // InstanceName must be empty: RedisSessionStore already namespaces all keys
    // with "ssdid:session:" and "ssdid:challenge:" prefixes. Setting InstanceName
    // here would cause IDistributedCache to prepend an additional "ssdid:" prefix,
    // producing keys like "ssdid:ssdid:session:{token}" that server.Keys() and
    // direct db.StringGet() calls would never match.
    builder.Services.AddStackExchangeRedisCache(options =>
    {
        options.Configuration = redisConnection;
        options.InstanceName = "";
    });
    builder.Services.AddSingleton<IConnectionMultiplexer>(sp =>
        ConnectionMultiplexer.Connect(redisOptions));
    builder.Services.AddSingleton<RedisSessionStore>();
    builder.Services.AddSingleton<ISessionStore>(sp => sp.GetRequiredService<RedisSessionStore>());
    builder.Services.AddSingleton<ISseNotificationBus>(sp => sp.GetRequiredService<RedisSessionStore>());
    builder.Services.AddHealthChecks().AddCheck<RedisHealthCheck>("redis");
}
else
{
    builder.Services.AddSingleton<SessionStore>();
    builder.Services.AddSingleton<ISessionStore>(sp => sp.GetRequiredService<SessionStore>());
    builder.Services.AddSingleton<ISseNotificationBus>(sp => sp.GetRequiredService<SessionStore>());
    builder.Services.AddHostedService(sp => sp.GetRequiredService<SessionStore>());
    builder.Services.AddHealthChecks();
}

builder.Services.AddHttpClient<RegistryClient>(client =>
{
    var registryUrl = builder.Configuration["Ssdid:RegistryUrl"] ?? "https://registry.ssdid.my";
    client.BaseAddress = new Uri(registryUrl);
    client.Timeout = TimeSpan.FromSeconds(10);
});

builder.Services.AddScoped<SsdidAuthService>();
builder.Services.AddScoped<NotificationService>();
builder.Services.AddScoped<AuditService>();
builder.Services.AddSingleton<WebAuthnChallengeStore>();
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
    var startupLogger = app.Services.GetRequiredService<ILogger<Program>>();

    var keyPath = app.Configuration["Ssdid:IdentityPath"]
        ?? Path.Combine(app.Environment.ContentRootPath, "data", "server-identity.json");
    if (File.Exists(keyPath))
        startupLogger.LogWarning(
            "Server identity private key is stored in plaintext at {Path}. " +
            "Consider using a key vault or HSM for production.", keyPath);

    if (string.IsNullOrEmpty(app.Configuration.GetConnectionString("Redis")))
        startupLogger.LogWarning(
            "SessionStore is in-memory only (single-instance). " +
            "Set ConnectionStrings:Redis for horizontal scaling.");

    if (string.IsNullOrEmpty(app.Configuration["Sentry:Dsn"]))
        startupLogger.LogWarning(
            "Sentry DSN is not configured. Error tracking is disabled. " +
            "Set Sentry:Dsn to enable production error reporting.");
}

// ── Pipeline ──
app.UseExceptionHandler();
app.UseStatusCodePages();
app.UseSerilogRequestLogging(options =>
{
    options.GetLevel = (httpContext, elapsed, ex) =>
        httpContext.Request.Path.StartsWithSegments("/health")
            ? Serilog.Events.LogEventLevel.Verbose
            : Serilog.Events.LogEventLevel.Information;
});

if (app.Environment.IsDevelopment())
{
    app.MapOpenApi();
}

app.UseCors();
app.UseRateLimiter();
app.MapHealthChecks("/health/redis");

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
app.MapRecoveryFeature();
app.MapCredentialFeature();
app.MapAdminFeature();

// ── Serve admin SPA ──
var adminPath = Path.Combine(app.Environment.ContentRootPath, "wwwroot", "admin");
if (Directory.Exists(adminPath))
{
    app.UseStaticFiles(new StaticFileOptions
    {
        FileProvider = new PhysicalFileProvider(adminPath),
        RequestPath = "/admin"
    });
    app.MapFallbackToFile("/admin/{**path}", "admin/index.html");
}

// ── Auto-migrate (guarded) ──
if (app.Environment.IsDevelopment() ||
    string.Equals(Environment.GetEnvironmentVariable("ENABLE_AUTO_MIGRATE"), "true", StringComparison.OrdinalIgnoreCase))
{
    using var scope = app.Services.CreateScope();
    var db = scope.ServiceProvider.GetRequiredService<AppDbContext>();
    await db.Database.MigrateAsync();
}

app.Run();
