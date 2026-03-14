using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Design;

namespace SsdidDrive.Api.Data;

/// <summary>
/// Design-time factory used by <c>dotnet ef migrations</c> so that the CLI
/// can instantiate AppDbContext without bootstrapping the full application
/// (which requires native libraries such as libkazsign).
/// </summary>
public class DesignTimeDbContextFactory : IDesignTimeDbContextFactory<AppDbContext>
{
    public AppDbContext CreateDbContext(string[] args)
    {
        var optionsBuilder = new DbContextOptionsBuilder<AppDbContext>();
        // The connection string only needs to be syntactically valid;
        // EF uses it to determine the provider but does not connect during migration scaffolding.
        optionsBuilder.UseNpgsql("Host=localhost;Database=ssdid_drive;Username=ssdid_drive;Password=ssdid_drive");
        return new AppDbContext(optionsBuilder.Options);
    }
}
