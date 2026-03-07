using Microsoft.EntityFrameworkCore;
using SsdidDrive.Api.Data.Entities;

namespace SsdidDrive.Api.Data;

public class AppDbContext(DbContextOptions<AppDbContext> options) : DbContext(options)
{
    public DbSet<User> Users => Set<User>();
    public DbSet<Tenant> Tenants => Set<Tenant>();
    public DbSet<UserTenant> UserTenants => Set<UserTenant>();
    public DbSet<Folder> Folders => Set<Folder>();
    public DbSet<FileItem> Files => Set<FileItem>();
    public DbSet<Share> Shares => Set<Share>();

    protected override void OnModelCreating(ModelBuilder modelBuilder)
    {
        modelBuilder.Entity<User>(e =>
        {
            e.ToTable("users");
            e.HasKey(u => u.Id);
            e.Property(u => u.Id).HasDefaultValueSql("gen_random_uuid()");
            e.Property(u => u.Did).HasMaxLength(256).IsRequired();
            e.Property(u => u.DisplayName).HasMaxLength(256);
            e.Property(u => u.Email).HasMaxLength(160);
            e.Property(u => u.Status).HasMaxLength(32)
                .HasDefaultValue(UserStatus.Active)
                .HasConversion(
                    v => v.ToString().ToLowerInvariant(),
                    v => Enum.Parse<UserStatus>(v, true));
            e.Property(u => u.PublicKeys).HasColumnType("jsonb");
            e.Property(u => u.CreatedAt).HasDefaultValueSql("now()");
            e.Property(u => u.UpdatedAt).HasDefaultValueSql("now()");

            e.HasIndex(u => u.Did).IsUnique();
            e.HasIndex(u => u.Status);

            e.HasOne(u => u.Tenant)
                .WithMany(t => t.Users)
                .HasForeignKey(u => u.TenantId)
                .OnDelete(DeleteBehavior.SetNull);
        });

        modelBuilder.Entity<Tenant>(e =>
        {
            e.ToTable("tenants");
            e.HasKey(t => t.Id);
            e.Property(t => t.Id).HasDefaultValueSql("gen_random_uuid()");
            e.Property(t => t.Name).HasMaxLength(256).IsRequired();
            e.Property(t => t.Slug).HasMaxLength(256).IsRequired();
            e.Property(t => t.CreatedAt).HasDefaultValueSql("now()");
            e.Property(t => t.UpdatedAt).HasDefaultValueSql("now()");

            e.HasIndex(t => t.Slug).IsUnique();
        });

        modelBuilder.Entity<UserTenant>(e =>
        {
            e.ToTable("user_tenants");
            e.HasKey(ut => new { ut.UserId, ut.TenantId });
            e.Property(ut => ut.Role).HasMaxLength(32)
                .HasDefaultValue(TenantRole.Member)
                .HasConversion(
                    v => v.ToString().ToLowerInvariant(),
                    v => Enum.Parse<TenantRole>(v, true));
            e.Property(ut => ut.CreatedAt).HasDefaultValueSql("now()");

            e.HasOne(ut => ut.User).WithMany(u => u.UserTenants).HasForeignKey(ut => ut.UserId);
            e.HasOne(ut => ut.Tenant).WithMany(t => t.UserTenants).HasForeignKey(ut => ut.TenantId);
        });

        modelBuilder.Entity<Folder>(e =>
        {
            e.ToTable("folders");
            e.HasKey(f => f.Id);
            e.Property(f => f.Id).HasDefaultValueSql("gen_random_uuid()");
            e.Property(f => f.Name).HasMaxLength(512).IsRequired();
            e.Property(f => f.KemAlgorithm).HasMaxLength(64);
            e.Property(f => f.CreatedAt).HasDefaultValueSql("now()");
            e.Property(f => f.UpdatedAt).HasDefaultValueSql("now()");

            e.HasIndex(f => new { f.TenantId, f.ParentFolderId });
            e.HasIndex(f => f.OwnerId);

            e.HasOne(f => f.ParentFolder)
                .WithMany(f => f.SubFolders)
                .HasForeignKey(f => f.ParentFolderId)
                .OnDelete(DeleteBehavior.Restrict);

            e.HasOne(f => f.Owner)
                .WithMany()
                .HasForeignKey(f => f.OwnerId)
                .OnDelete(DeleteBehavior.Cascade);

            e.HasOne(f => f.Tenant)
                .WithMany()
                .HasForeignKey(f => f.TenantId)
                .OnDelete(DeleteBehavior.Cascade);
        });

        modelBuilder.Entity<FileItem>(e =>
        {
            e.ToTable("files");
            e.HasKey(f => f.Id);
            e.Property(f => f.Id).HasDefaultValueSql("gen_random_uuid()");
            e.Property(f => f.Name).HasMaxLength(512).IsRequired();
            e.Property(f => f.ContentType).HasMaxLength(256).IsRequired();
            e.Property(f => f.StoragePath).HasMaxLength(1024).IsRequired();
            e.Property(f => f.EncryptionAlgorithm).HasMaxLength(64);
            e.Property(f => f.CreatedAt).HasDefaultValueSql("now()");
            e.Property(f => f.UpdatedAt).HasDefaultValueSql("now()");

            e.HasIndex(f => f.FolderId);

            e.HasOne(f => f.Folder)
                .WithMany(d => d.Files)
                .HasForeignKey(f => f.FolderId)
                .OnDelete(DeleteBehavior.Cascade);

            e.HasOne(f => f.UploadedBy)
                .WithMany()
                .HasForeignKey(f => f.UploadedById)
                .OnDelete(DeleteBehavior.Cascade);
        });

        modelBuilder.Entity<Share>(e =>
        {
            e.ToTable("shares");
            e.HasKey(s => s.Id);
            e.Property(s => s.Id).HasDefaultValueSql("gen_random_uuid()");
            e.Property(s => s.ResourceType).HasMaxLength(32).IsRequired();
            e.Property(s => s.Permission).HasMaxLength(32).HasDefaultValue("read");
            e.Property(s => s.KemAlgorithm).HasMaxLength(64);
            e.Property(s => s.CreatedAt).HasDefaultValueSql("now()");

            e.HasIndex(s => new { s.ResourceId, s.ResourceType });
            e.HasIndex(s => s.SharedWithId);

            e.HasOne(s => s.SharedBy)
                .WithMany()
                .HasForeignKey(s => s.SharedById)
                .OnDelete(DeleteBehavior.Cascade);

            e.HasOne(s => s.SharedWith)
                .WithMany()
                .HasForeignKey(s => s.SharedWithId)
                .OnDelete(DeleteBehavior.Cascade);
        });
    }
}
