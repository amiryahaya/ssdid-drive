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
using SsdidDrive.Api.Features.Shares;
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
#pragma warning disable ASP0000 // CryptoProviderFactory needed before DI container is built
var cryptoFactory = builder.Services.BuildServiceProvider().GetRequiredService<CryptoProviderFactory>();
#pragma warning restore ASP0000
var identityPath = builder.Configuration["Ssdid:IdentityPath"]
    ?? Path.Combine(builder.Environment.ContentRootPath, "data", "server-identity.json");
var algorithmType = builder.Configuration["Ssdid:Algorithm"] ?? "KazSignVerificationKey2024";
var identity = SsdidIdentity.LoadOrCreate(identityPath, algorithmType, cryptoFactory);
builder.Services.AddSingleton(identity);

var sessionStore = new SessionStore();
builder.Services.AddSingleton(sessionStore);
builder.Services.AddHostedService(sp => sp.GetRequiredService<SessionStore>());

builder.Services.AddHttpClient<RegistryClient>(client =>
{
    var registryUrl = builder.Configuration["Ssdid:RegistryUrl"] ?? "https://registry.ssdid.my";
    client.BaseAddress = new Uri(registryUrl);
    client.Timeout = TimeSpan.FromSeconds(10);
});

builder.Services.AddScoped<SsdidAuthService>();
builder.Services.AddHostedService<ServerRegistrationService>();

// ── Rate Limiting ──
builder.Services.AddRateLimiter(options =>
{
    options.RejectionStatusCode = 429;
    options.AddFixedWindowLimiter("auth", limiter =>
    {
        limiter.PermitLimit = 20;
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

// ── Pipeline ──
app.UseExceptionHandler();
app.UseStatusCodePages();

if (app.Environment.IsDevelopment())
{
    app.MapOpenApi();
}

app.UseCors();
app.UseRateLimiter();

// Auth middleware — whitelist of public paths that skip authentication
app.UseWhen(
    context =>
    {
        var path = context.Request.Path;
        if (!path.StartsWithSegments("/api")) return false;

        // Public auth endpoints (no session required)
        if (path.StartsWithSegments("/api/auth/ssdid/server-info")) return false;
        if (path.StartsWithSegments("/api/auth/ssdid/register")) return false;
        if (path.StartsWithSegments("/api/auth/ssdid/authenticate")) return false;
        if (path.StartsWithSegments("/api/auth/ssdid/events")) return false;

        return true;
    },
    branch => branch.UseMiddleware<SsdidAuthMiddleware>());

// ── Features ──
app.MapHealthFeature();
app.MapAuthFeature();
app.MapUserFeature();
app.MapFolderFeature();
app.MapFileFeature();
app.MapShareFeature();

// ── Auto-migrate (guarded) ──
if (app.Environment.IsDevelopment() ||
    string.Equals(Environment.GetEnvironmentVariable("ENABLE_AUTO_MIGRATE"), "true", StringComparison.OrdinalIgnoreCase))
{
    using var scope = app.Services.CreateScope();
    var db = scope.ServiceProvider.GetRequiredService<AppDbContext>();
    await db.Database.MigrateAsync();
}

app.Run();
