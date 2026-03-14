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
using SsdidDrive.Api.Features.Activity;
using SsdidDrive.Api.Features.Admin;
using SsdidDrive.Api.Features.Recovery;
using SsdidDrive.Api.Features.Users;
using SsdidDrive.Api.Features.Account;
using SsdidDrive.Api.Features.ExtensionServices;
using SsdidDrive.Api.Features.TenantRequests;
using SsdidDrive.Api.Services;
using SsdidDrive.Api.Middleware;
using SsdidDrive.Api.Ssdid;
using SsdidDrive.Api.Crypto;
using SsdidDrive.Api.Crypto.Providers;
using SsdidDrive.Api.Health;
using Microsoft.Extensions.FileProviders;
using Serilog;
using Resend;
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
var sentryDsn = builder.Configuration["Sentry:Dsn"];
if (!string.IsNullOrEmpty(sentryDsn) && sentryDsn.Contains('@'))
{
    builder.WebHost.UseSentry(options =>
    {
        options.Dsn = sentryDsn;
        options.TracesSampleRate = builder.Configuration.GetValue("Sentry:TracesSampleRate", 0.2);
        options.SendDefaultPii = false;
        options.Environment = builder.Environment.EnvironmentName;
        options.Release = typeof(Program).Assembly.GetName().Version?.ToString() ?? "dev";
    });
}

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
    var identity = SsdidIdentity.LoadOrCreate(identityPath, algorithmType, factory);
    if (identity.AlgorithmMismatch)
    {
        var log = sp.GetRequiredService<ILoggerFactory>().CreateLogger("SsdidIdentity");
        log.LogWarning(
            "Loaded identity uses {Loaded} but configured Ssdid:Algorithm is {Configured}. " +
            "Delete {Path} to regenerate with the configured algorithm.",
            identity.AlgorithmType, algorithmType, identityPath);
    }
    return identity;
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

// ── OTP Store ──
if (!string.IsNullOrEmpty(redisConnection))
    builder.Services.AddSingleton<IOtpStore, RedisOtpStore>();
else
    builder.Services.AddSingleton<IOtpStore, InMemoryOtpStore>();

builder.Services.AddScoped<OtpService>();
builder.Services.AddSingleton<TotpService>();
builder.Services.AddSingleton<TotpEncryption>();
builder.Services.AddSingleton<OidcTokenValidator>();
builder.Services.AddHttpClient<OidcCodeExchanger>(client =>
{
    client.Timeout = TimeSpan.FromSeconds(15);
});
builder.Services.AddScoped<ExtensionServiceContext>();
builder.Services.AddSingleton<HmacReplayCache>();

builder.Services.AddHttpClient<RegistryClient>(client =>
{
    var registryUrl = builder.Configuration["Ssdid:RegistryUrl"] ?? "https://registry.ssdid.my";
    client.BaseAddress = new Uri(registryUrl);
    client.Timeout = TimeSpan.FromSeconds(10);
});

builder.Services.AddScoped<SsdidAuthService>();
builder.Services.AddScoped<NotificationService>();
builder.Services.AddScoped<AuditService>();
builder.Services.AddSingleton<FileActivityService>();
builder.Services.AddHostedService<FileActivityCleanupService>();

// ── Email (Resend) ──
var resendApiKey = builder.Configuration["Email:ApiKey"];
if (!string.IsNullOrEmpty(resendApiKey))
{
    builder.Services.AddOptions();
    builder.Services.AddHttpClient<ResendClient>();
    builder.Services.Configure<ResendClientOptions>(o => o.ApiToken = resendApiKey);
    builder.Services.AddTransient<IResend, ResendClient>();
    builder.Services.AddScoped<IEmailService, EmailService>();
}
else
{
    builder.Services.AddSingleton<IEmailService, NullEmailService>();
}
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

    // GET /api/recovery/share — partitioned by DID (query string), 5 req/DID/hour
    options.AddPolicy("recovery-share", httpContext =>
    {
        if (isTesting)
            return RateLimitPartition.GetNoLimiter("no-limit");

        var did = httpContext.Request.Query["did"].ToString();
        var key = string.IsNullOrEmpty(did) ? "anonymous" : did;
        return RateLimitPartition.GetFixedWindowLimiter(key, _ => new FixedWindowRateLimiterOptions
        {
            PermitLimit = 5,
            Window = TimeSpan.FromHours(1),
            QueueLimit = 0
        });
    });

    // POST /api/recovery/complete — partitioned by IP, 10 req/IP/hour
    options.AddPolicy("recovery-complete", httpContext =>
    {
        if (isTesting)
            return RateLimitPartition.GetNoLimiter("no-limit");

        var ip = httpContext.Connection.RemoteIpAddress?.ToString() ?? "unknown";
        return RateLimitPartition.GetFixedWindowLimiter(ip, _ => new FixedWindowRateLimiterOptions
        {
            PermitLimit = 10,
            Window = TimeSpan.FromHours(1),
            QueueLimit = 0
        });
    });

    // Email OTP send — 5 per IP per hour
    options.AddPolicy("auth-otp", httpContext =>
    {
        if (isTesting)
            return RateLimitPartition.GetNoLimiter("no-limit");

        var ip = httpContext.Connection.RemoteIpAddress?.ToString() ?? "unknown";
        return RateLimitPartition.GetFixedWindowLimiter(ip, _ => new FixedWindowRateLimiterOptions
        {
            PermitLimit = 5,
            Window = TimeSpan.FromHours(1),
            QueueLimit = 0
        });
    });

    // TOTP verify — 5 per IP per 15 minutes
    options.AddPolicy("auth-totp", httpContext =>
    {
        if (isTesting)
            return RateLimitPartition.GetNoLimiter("no-limit");

        var ip = httpContext.Connection.RemoteIpAddress?.ToString() ?? "unknown";
        return RateLimitPartition.GetFixedWindowLimiter(ip, _ => new FixedWindowRateLimiterOptions
        {
            PermitLimit = 5,
            Window = TimeSpan.FromMinutes(15),
            QueueLimit = 0
        });
    });

    // TOTP recovery — 3 per IP per hour
    options.AddPolicy("auth-recovery", httpContext =>
    {
        if (isTesting)
            return RateLimitPartition.GetNoLimiter("no-limit");

        var ip = httpContext.Connection.RemoteIpAddress?.ToString() ?? "unknown";
        return RateLimitPartition.GetFixedWindowLimiter(ip, _ => new FixedWindowRateLimiterOptions
        {
            PermitLimit = 3,
            Window = TimeSpan.FromHours(1),
            QueueLimit = 0
        });
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
app.UseForwardedHeaders(new ForwardedHeadersOptions
{
    ForwardedHeaders = Microsoft.AspNetCore.HttpOverrides.ForwardedHeaders.XForwardedFor
        | Microsoft.AspNetCore.HttpOverrides.ForwardedHeaders.XForwardedProto
        | Microsoft.AspNetCore.HttpOverrides.ForwardedHeaders.XForwardedHost
});
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

// HMAC middleware for extension service consumer-facing API routes.
// These routes use HMAC-SHA256 authentication instead of Bearer tokens.
app.UseWhen(
    context => context.Request.Path.StartsWithSegments("/api/ext"),
    branch => branch.UseMiddleware<HmacAuthMiddleware>());

// Auth middleware — endpoints marked [SsdidPublic] skip authentication.
// All /api endpoints go through the middleware; it checks endpoint metadata.
// Exclude /api/ext routes which use HMAC auth above.
app.UseWhen(
    context => context.Request.Path.StartsWithSegments("/api")
               && !context.Request.Path.StartsWithSegments("/api/ext"),
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
app.MapActivityFeature();
app.MapAccountFeature();
app.MapExtensionServiceFeature();
app.MapTenantRequestFeature();

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
