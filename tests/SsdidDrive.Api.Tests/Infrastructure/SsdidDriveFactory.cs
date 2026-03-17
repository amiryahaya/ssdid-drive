using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Mvc.Testing;
using Microsoft.Data.Sqlite;
using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Diagnostics;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;
using SsdidDrive.Api.Data;
using SsdidDrive.Api.Services;

namespace SsdidDrive.Api.Tests.Infrastructure;

public class SsdidDriveFactory : WebApplicationFactory<Program>
{
    // Keep the SQLite connection open so the in-memory DB survives across scopes.
    private readonly SqliteConnection _connection;

    /// <summary>
    /// Mock registry handler shared by all tests using this factory.
    /// Register DIDs here before calling RegisterWalletAsync.
    /// </summary>
    public MockRegistryDelegatingHandler MockRegistryHandler { get; } = new();

    /// <summary>
    /// Set to false in subclasses that need the real registry (e.g. RealRegistryFactory).
    /// </summary>
    protected virtual bool UseMockRegistry => true;

    public SsdidDriveFactory()
    {
        _connection = new SqliteConnection("DataSource=:memory:");
        _connection.Open();

        // Register PostgreSQL "now()" so HasDefaultValueSql("now()") works on SQLite.
        _connection.CreateFunction("now", () => DateTimeOffset.UtcNow.ToString("o"));
        // Map gen_random_uuid() → randomblob(16) via a SQLite alias.
        _connection.CreateFunction("gen_random_uuid", () => Guid.NewGuid());
    }

    protected override void ConfigureWebHost(IWebHostBuilder builder)
    {
        // Use "Testing" to skip the auto-migrate block in Program.cs
        // (which runs MigrateAsync only in Development and would fail with SQLite).
        builder.UseEnvironment("Testing");

        builder.ConfigureServices(services =>
        {
            // Remove all EF Core / DbContext registrations added by the app
            var efDescriptors = services.Where(d =>
                d.ServiceType == typeof(DbContextOptions<AppDbContext>) ||
                d.ServiceType == typeof(DbContextOptions) ||
                d.ServiceType == typeof(AppDbContext) ||
                d.ServiceType.FullName?.Contains("EntityFrameworkCore") == true ||
                d.ImplementationType?.FullName?.Contains("Npgsql") == true ||
                d.ServiceType.FullName?.Contains("Npgsql") == true)
                .ToList();
            foreach (var d in efDescriptors) services.Remove(d);

            // Remove real storage
            var storageDescriptor = services.SingleOrDefault(
                d => d.ServiceType == typeof(IStorageService));
            if (storageDescriptor != null) services.Remove(storageDescriptor);

            // SQLite in-memory with shared connection.
            // Replace the internal IModelCustomizer to apply DateTimeOffset → TEXT conversion
            // so SQLite can handle ORDER BY and WHERE on DateTimeOffset columns.
            services.AddDbContext<AppDbContext>(options =>
            {
                options.UseSqlite(_connection);
                options.ReplaceService<Microsoft.EntityFrameworkCore.Infrastructure.IModelCustomizer,
                    SqliteDateTimeOffsetModelCustomizer>();
            });

            // Memory storage
            services.AddSingleton<IStorageService, MemoryStorageService>();

            // Mock registry for DID resolution (subclasses can override)
            if (UseMockRegistry)
            {
                services.AddHttpClient<global::Ssdid.Sdk.Server.Registry.RegistryClient>()
                    .ConfigurePrimaryHttpMessageHandler(() => MockRegistryHandler);
            }
        });
    }

    protected override IHost CreateHost(IHostBuilder builder)
    {
        var host = base.CreateHost(builder);

        // Create the DB schema using the real DI container (no BuildServiceProvider needed)
        using var scope = host.Services.CreateScope();
        var db = scope.ServiceProvider.GetRequiredService<AppDbContext>();
        db.Database.EnsureCreated();

        return host;
    }

    protected override void Dispose(bool disposing)
    {
        base.Dispose(disposing);
        if (disposing)
            _connection.Dispose();
    }
}

/// <summary>
/// Model customizer that converts all DateTimeOffset properties to TEXT (ISO 8601 string)
/// for SQLite, enabling ORDER BY and WHERE comparisons that the SQLite provider normally blocks.
/// </summary>
internal class SqliteDateTimeOffsetModelCustomizer
    : Microsoft.EntityFrameworkCore.Infrastructure.RelationalModelCustomizer
{
    public SqliteDateTimeOffsetModelCustomizer(
        Microsoft.EntityFrameworkCore.Infrastructure.ModelCustomizerDependencies dependencies)
        : base(dependencies) { }

    public override void Customize(Microsoft.EntityFrameworkCore.ModelBuilder modelBuilder, DbContext context)
    {
        base.Customize(modelBuilder, context);

        // Convert all DateTimeOffset and DateTimeOffset? properties to string for SQLite compat
        foreach (var entityType in modelBuilder.Model.GetEntityTypes())
        {
            foreach (var property in entityType.GetProperties())
            {
                if (property.ClrType == typeof(DateTimeOffset))
                {
                    property.SetValueConverter(
                        new Microsoft.EntityFrameworkCore.Storage.ValueConversion.ValueConverter<DateTimeOffset, string>(
                            v => v.ToString("o"),
                            v => DateTimeOffset.Parse(v)));
                    property.SetColumnType("TEXT");
                }
                else if (property.ClrType == typeof(DateTimeOffset?))
                {
                    property.SetValueConverter(
                        new Microsoft.EntityFrameworkCore.Storage.ValueConversion.ValueConverter<DateTimeOffset?, string?>(
                            v => v.HasValue ? v.Value.ToString("o") : null,
                            v => v != null ? DateTimeOffset.Parse(v) : null));
                    property.SetColumnType("TEXT");
                }
            }
        }
    }
}
