using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Mvc.Testing;
using Microsoft.Data.Sqlite;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;
using SsdidDrive.Api.Data;
using SsdidDrive.Api.Services;

namespace SsdidDrive.Api.Tests.Infrastructure;

public class SsdidDriveFactory : WebApplicationFactory<Program>
{
    // Keep the SQLite connection open so the in-memory DB survives across scopes.
    private readonly SqliteConnection _connection;

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

            // SQLite in-memory with shared connection
            services.AddDbContext<AppDbContext>(options =>
                options.UseSqlite(_connection));

            // Memory storage
            services.AddSingleton<IStorageService, MemoryStorageService>();
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
