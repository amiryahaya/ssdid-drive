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
    public DbSet<Device> Devices => Set<Device>();
    public DbSet<Invitation> Invitations => Set<Invitation>();
    public DbSet<Notification> Notifications => Set<Notification>();
    public DbSet<RecoveryConfig> RecoveryConfigs => Set<RecoveryConfig>();
    public DbSet<RecoveryShare> RecoveryShares => Set<RecoveryShare>();
    public DbSet<RecoveryRequest> RecoveryRequests => Set<RecoveryRequest>();
    public DbSet<RecoveryApproval> RecoveryApprovals => Set<RecoveryApproval>();
    public DbSet<WebAuthnCredential> WebAuthnCredentials => Set<WebAuthnCredential>();
    public DbSet<AuditLogEntry> AuditLog => Set<AuditLogEntry>();

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
            e.Property(u => u.SystemRole)
                .HasConversion<string>()
                .HasMaxLength(20);
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
            e.Property(t => t.Disabled).HasDefaultValue(false);
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
        modelBuilder.Entity<Device>(e =>
        {
            e.ToTable("devices");
            e.HasKey(d => d.Id);
            e.Property(d => d.Id).HasDefaultValueSql("gen_random_uuid()");
            e.Property(d => d.DeviceFingerprint).HasMaxLength(256).IsRequired();
            e.Property(d => d.DeviceName).HasMaxLength(256);
            e.Property(d => d.Platform).HasMaxLength(32).IsRequired();
            e.Property(d => d.DeviceInfo).HasMaxLength(4096);
            e.Property(d => d.KeyAlgorithm).HasMaxLength(64).IsRequired();
            e.Property(d => d.Status).HasMaxLength(32)
                .HasDefaultValue(DeviceStatus.Active)
                .HasConversion(
                    v => v.ToString().ToLowerInvariant(),
                    v => Enum.Parse<DeviceStatus>(v, true));
            e.Property(d => d.CreatedAt).HasDefaultValueSql("now()");
            e.Property(d => d.UpdatedAt).HasDefaultValueSql("now()");

            e.HasIndex(d => new { d.UserId, d.DeviceFingerprint }).IsUnique();
            e.HasIndex(d => d.UserId);

            e.HasOne(d => d.User)
                .WithMany()
                .HasForeignKey(d => d.UserId)
                .OnDelete(DeleteBehavior.Cascade);
        });

        modelBuilder.Entity<Invitation>(e =>
        {
            e.ToTable("invitations");
            e.HasKey(i => i.Id);
            e.Property(i => i.Id).HasDefaultValueSql("gen_random_uuid()");
            e.Property(i => i.Email).HasMaxLength(160);
            e.Property(i => i.Token).HasMaxLength(256).IsRequired();
            e.Property(i => i.ShortCode).HasMaxLength(16).IsRequired();
            e.Property(i => i.Message).HasMaxLength(1024);
            e.Property(i => i.Role).HasMaxLength(32)
                .HasDefaultValue(TenantRole.Member)
                .HasConversion(
                    v => v.ToString().ToLowerInvariant(),
                    v => Enum.Parse<TenantRole>(v, true));
            e.Property(i => i.Status).HasMaxLength(32)
                .HasDefaultValue(InvitationStatus.Pending)
                .HasConversion(
                    v => v.ToString().ToLowerInvariant(),
                    v => Enum.Parse<InvitationStatus>(v, true));
            e.Property(i => i.CreatedAt).HasDefaultValueSql("now()");
            e.Property(i => i.UpdatedAt).HasDefaultValueSql("now()");

            e.HasIndex(i => i.Token).IsUnique();
            e.HasIndex(i => i.ShortCode).IsUnique();
            e.HasIndex(i => new { i.TenantId, i.Status });
            e.HasIndex(i => i.InvitedUserId);
            e.HasIndex(i => new { i.TenantId, i.Email })
                .IsUnique()
                .HasFilter("\"Status\" = 'pending'")
                .HasDatabaseName("ix_invitations_pending_email_tenant");

            e.HasOne(i => i.Tenant)
                .WithMany()
                .HasForeignKey(i => i.TenantId)
                .OnDelete(DeleteBehavior.Cascade);

            e.HasOne(i => i.InvitedBy)
                .WithMany()
                .HasForeignKey(i => i.InvitedById)
                .OnDelete(DeleteBehavior.Cascade);

            e.HasOne(i => i.InvitedUser)
                .WithMany()
                .HasForeignKey(i => i.InvitedUserId)
                .OnDelete(DeleteBehavior.SetNull);
        });

        modelBuilder.Entity<Notification>(e =>
        {
            e.ToTable("notifications");
            e.HasKey(n => n.Id);
            e.Property(n => n.Id).HasDefaultValueSql("gen_random_uuid()");
            e.Property(n => n.Type).HasMaxLength(64).IsRequired();
            e.Property(n => n.Title).HasMaxLength(256).IsRequired();
            e.Property(n => n.Message).HasMaxLength(1024).IsRequired();
            e.Property(n => n.IsRead).HasDefaultValue(false);
            e.Property(n => n.ActionType).HasMaxLength(64);
            e.Property(n => n.ActionResourceId).HasMaxLength(256);
            e.Property(n => n.CreatedAt).HasDefaultValueSql("now()");

            e.HasIndex(n => new { n.UserId, n.IsRead });
            e.HasIndex(n => new { n.UserId, n.CreatedAt });

            e.HasOne(n => n.User)
                .WithMany()
                .HasForeignKey(n => n.UserId)
                .OnDelete(DeleteBehavior.Cascade);
        });

        modelBuilder.Entity<RecoveryConfig>(e =>
        {
            e.ToTable("recovery_configs");
            e.HasKey(rc => rc.Id);
            e.Property(rc => rc.Id).HasDefaultValueSql("gen_random_uuid()");
            e.Property(rc => rc.IsActive).HasDefaultValue(false);
            e.Property(rc => rc.CreatedAt).HasDefaultValueSql("now()");

            e.HasIndex(rc => rc.UserId);

            e.HasOne(rc => rc.User)
                .WithMany()
                .HasForeignKey(rc => rc.UserId)
                .OnDelete(DeleteBehavior.Cascade);
        });

        modelBuilder.Entity<RecoveryShare>(e =>
        {
            e.ToTable("recovery_shares");
            e.HasKey(rs => rs.Id);
            e.Property(rs => rs.Id).HasDefaultValueSql("gen_random_uuid()");
            e.Property(rs => rs.Status).HasMaxLength(32)
                .HasDefaultValue(RecoveryShareStatus.Pending)
                .HasConversion(
                    v => v.ToString().ToLowerInvariant(),
                    v => Enum.Parse<RecoveryShareStatus>(v, true));
            e.Property(rs => rs.CreatedAt).HasDefaultValueSql("now()");

            e.HasIndex(rs => rs.RecoveryConfigId);
            e.HasIndex(rs => rs.TrusteeId);
            e.HasIndex(rs => new { rs.RecoveryConfigId, rs.TrusteeId }).IsUnique();

            e.HasOne(rs => rs.Config)
                .WithMany(rc => rc.Shares)
                .HasForeignKey(rs => rs.RecoveryConfigId)
                .OnDelete(DeleteBehavior.Cascade);

            e.HasOne(rs => rs.Trustee)
                .WithMany()
                .HasForeignKey(rs => rs.TrusteeId)
                .OnDelete(DeleteBehavior.Cascade);
        });

        modelBuilder.Entity<RecoveryRequest>(e =>
        {
            e.ToTable("recovery_requests");
            e.HasKey(rr => rr.Id);
            e.Property(rr => rr.Id).HasDefaultValueSql("gen_random_uuid()");
            e.Property(rr => rr.Status).HasMaxLength(32)
                .HasDefaultValue(RecoveryRequestStatus.Pending)
                .HasConversion(
                    v => v.ToString().ToLowerInvariant(),
                    v => Enum.Parse<RecoveryRequestStatus>(v, true));
            e.Property(rr => rr.ApprovalsReceived).HasDefaultValue(0);
            e.Property(rr => rr.CreatedAt).HasDefaultValueSql("now()");

            e.HasIndex(rr => rr.RequesterId);
            e.HasIndex(rr => rr.RecoveryConfigId);

            e.HasOne(rr => rr.Requester)
                .WithMany()
                .HasForeignKey(rr => rr.RequesterId)
                .OnDelete(DeleteBehavior.Cascade);

            e.HasOne(rr => rr.Config)
                .WithMany()
                .HasForeignKey(rr => rr.RecoveryConfigId)
                .OnDelete(DeleteBehavior.Cascade);
        });

        modelBuilder.Entity<RecoveryApproval>(e =>
        {
            e.ToTable("recovery_approvals");
            e.HasKey(ra => ra.Id);
            e.Property(ra => ra.Id).HasDefaultValueSql("gen_random_uuid()");
            e.Property(ra => ra.ApprovedAt).HasDefaultValueSql("now()");

            e.HasIndex(ra => new { ra.RecoveryRequestId, ra.TrusteeId }).IsUnique();

            e.HasOne(ra => ra.RecoveryRequest)
                .WithMany(rr => rr.Approvals)
                .HasForeignKey(ra => ra.RecoveryRequestId)
                .OnDelete(DeleteBehavior.Cascade);

            e.HasOne(ra => ra.Trustee)
                .WithMany()
                .HasForeignKey(ra => ra.TrusteeId)
                .OnDelete(DeleteBehavior.Cascade);
        });

        modelBuilder.Entity<WebAuthnCredential>(e =>
        {
            e.ToTable("webauthn_credentials");
            e.HasKey(w => w.Id);
            e.Property(w => w.Id).HasDefaultValueSql("gen_random_uuid()");
            e.Property(w => w.CredentialId).HasMaxLength(512).IsRequired();
            e.Property(w => w.PublicKey).IsRequired();
            e.Property(w => w.Name).HasMaxLength(256);
            e.Property(w => w.CreatedAt).HasDefaultValueSql("now()");

            e.HasIndex(w => w.CredentialId).IsUnique();
            e.HasIndex(w => w.UserId);

            e.HasOne(w => w.User)
                .WithMany()
                .HasForeignKey(w => w.UserId)
                .OnDelete(DeleteBehavior.Cascade);
        });

        modelBuilder.Entity<AuditLogEntry>(e =>
        {
            e.ToTable("audit_log");
            e.HasKey(a => a.Id);
            e.Property(a => a.Id).HasDefaultValueSql("gen_random_uuid()");
            e.Property(a => a.Action).HasMaxLength(128).IsRequired();
            e.Property(a => a.TargetType).HasMaxLength(64);
            e.Property(a => a.Details).HasMaxLength(4096);
            e.Property(a => a.CreatedAt).HasDefaultValueSql("now()");

            e.HasIndex(a => a.CreatedAt).IsDescending();

            e.HasOne(a => a.Actor)
                .WithMany()
                .HasForeignKey(a => a.ActorId)
                .OnDelete(DeleteBehavior.Cascade);
        });
    }
}
