# Backend Auth Core Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add email+TOTP and OIDC authentication alongside existing SSDID auth, with account linking support.

**Architecture:** New auth endpoints create sessions using Account.Id (UUID) instead of DID. Middleware detects session type by format (UUID vs `did:*` string) for backward compatibility. New Login entity tracks linked auth methods. OTP stored in Redis/in-memory with TTL. TOTP via OtpNet (RFC 6238).

**Tech Stack:** .NET 10, EF Core + PostgreSQL, OtpNet, QRCoder, Microsoft.IdentityModel (JWT validation), Resend (email)

**Spec:** `docs/superpowers/specs/2026-03-14-auth-migration-design.md`

**Scope:** Spec Phases 1-3 + Phase 5 (backend auth core only). The following are separate plans:
- **Plan 2:** Extension services, HMAC middleware, tenant requests (Phase 4)
- **Plan 3:** Admin portal server-side OIDC authorize/callback endpoints (Phase 6)
- **Plan 7:** SSDID removal + final DB migrations — Account rename, DID column drop (Phases 10-11)

---

## File Structure

### New Files

```
src/SsdidDrive.Api/Data/Entities/Login.cs              — Login entity + LoginProvider enum
src/SsdidDrive.Api/Services/OtpService.cs               — OTP generation, storage (Redis/in-memory), verification
src/SsdidDrive.Api/Services/TotpService.cs              — TOTP secret generation, QR URI, code verification, backup codes
src/SsdidDrive.Api/Services/TotpEncryption.cs           — AES-GCM encryption for TOTP secrets and backup codes at rest
src/SsdidDrive.Api/Services/OidcTokenValidator.cs       — Google/Microsoft ID token validation (cached OIDC discovery)
src/SsdidDrive.Api/Features/Auth/EmailRegister.cs       — POST /api/auth/email/register
src/SsdidDrive.Api/Features/Auth/EmailRegisterVerify.cs — POST /api/auth/email/register/verify
src/SsdidDrive.Api/Features/Auth/EmailLogin.cs          — POST /api/auth/email/login
src/SsdidDrive.Api/Features/Auth/TotpSetup.cs           — POST /api/auth/totp/setup
src/SsdidDrive.Api/Features/Auth/TotpSetupConfirm.cs    — POST /api/auth/totp/setup/confirm
src/SsdidDrive.Api/Features/Auth/TotpVerify.cs          — POST /api/auth/totp/verify
src/SsdidDrive.Api/Features/Auth/TotpRecovery.cs        — POST /api/auth/totp/recovery
src/SsdidDrive.Api/Features/Auth/TotpRecoveryVerify.cs  — POST /api/auth/totp/recovery/verify
src/SsdidDrive.Api/Features/Auth/OidcVerify.cs          — POST /api/auth/oidc/verify
src/SsdidDrive.Api/Features/Account/AccountFeature.cs   — Route group for /api/account
src/SsdidDrive.Api/Features/Account/ListLogins.cs       — GET /api/account/logins
src/SsdidDrive.Api/Features/Account/LinkEmail.cs        — POST /api/account/logins/email
src/SsdidDrive.Api/Features/Account/LinkEmailVerify.cs  — POST /api/account/logins/email/verify
src/SsdidDrive.Api/Features/Account/LinkOidc.cs         — POST /api/account/logins/oidc
src/SsdidDrive.Api/Features/Account/UnlinkLogin.cs      — DELETE /api/account/logins/{id}
tests/SsdidDrive.Api.Tests/Unit/OtpServiceTests.cs
tests/SsdidDrive.Api.Tests/Unit/TotpServiceTests.cs
tests/SsdidDrive.Api.Tests/Integration/EmailAuthFlowTests.cs
tests/SsdidDrive.Api.Tests/Integration/LoginLinkingTests.cs
tests/SsdidDrive.Api.Tests/Integration/TotpRecoveryTests.cs
```

### Modified Files

```
src/SsdidDrive.Api/Data/Entities/User.cs                — Add TotpSecret, TotpEnabled, BackupCodes, EmailVerified
src/SsdidDrive.Api/Data/AppDbContext.cs                  — Add Login DbSet + configuration
src/SsdidDrive.Api/Features/Auth/AuthFeature.cs          — Map new auth endpoints
src/SsdidDrive.Api/Middleware/SsdidAuthMiddleware.cs      — Dual-mode: UUID lookup + DID lookup + MfaPending
src/SsdidDrive.Api/Common/CurrentUserAccessor.cs         — Add MfaPending property
src/SsdidDrive.Api/Program.cs                            — Register new services, map AccountFeature
src/SsdidDrive.Api/SsdidDrive.Api.csproj                 — Add OtpNet, QRCoder NuGet packages
```

---

## Chunk 1: Data Model + Infrastructure Services

### Task 1: Login Entity + User Columns + EF Migration

**Files:**
- Create: `src/SsdidDrive.Api/Data/Entities/Login.cs`
- Modify: `src/SsdidDrive.Api/Data/Entities/User.cs`
- Modify: `src/SsdidDrive.Api/Data/AppDbContext.cs`

- [ ] **Step 1: Add NuGet packages**

```bash
cd /Users/amirrudinyahaya/Workspace/ssdid-drive/.claude/worktrees/file-activity-logs
dotnet add src/SsdidDrive.Api/SsdidDrive.Api.csproj package OtpNet
dotnet add src/SsdidDrive.Api/SsdidDrive.Api.csproj package QRCoder
```

- [ ] **Step 2: Create Login entity**

Create `src/SsdidDrive.Api/Data/Entities/Login.cs`:

```csharp
namespace SsdidDrive.Api.Data.Entities;

public enum LoginProvider { Email, Google, Microsoft }

public class Login
{
    public Guid Id { get; set; }
    public Guid AccountId { get; set; }
    public LoginProvider Provider { get; set; }
    public string ProviderSubject { get; set; } = default!;
    public DateTimeOffset CreatedAt { get; set; }
    public DateTimeOffset LinkedAt { get; set; }

    public User Account { get; set; } = null!;
}
```

- [ ] **Step 3: Add TOTP columns to User**

Modify `src/SsdidDrive.Api/Data/Entities/User.cs` — add after `HasRecoverySetup`:

```csharp
// Auth: TOTP
public string? TotpSecret { get; set; }
public bool TotpEnabled { get; set; }
public string? BackupCodes { get; set; } // Encrypted JSON array
public bool EmailVerified { get; set; }

// Linked logins
public ICollection<Login> Logins { get; set; } = [];
```

- [ ] **Step 4: Configure Login entity in AppDbContext**

Modify `src/SsdidDrive.Api/Data/AppDbContext.cs` — add `DbSet`:

```csharp
public DbSet<Login> Logins => Set<Login>();
```

Add configuration in `OnModelCreating` (follow existing patterns — lowercase snake_case table, gen_random_uuid PK, enum conversion):

```csharp
modelBuilder.Entity<Login>(e =>
{
    e.ToTable("logins");
    e.Property(x => x.Id).HasDefaultValueSql("gen_random_uuid()");
    e.Property(x => x.Provider)
        .HasConversion(
            v => v.ToString().ToLowerInvariant(),
            v => Enum.Parse<LoginProvider>(v, true));
    e.Property(x => x.CreatedAt).HasDefaultValueSql("now()");
    e.Property(x => x.LinkedAt).HasDefaultValueSql("now()");

    e.HasIndex(x => new { x.Provider, x.ProviderSubject }).IsUnique();
    e.HasIndex(x => x.AccountId);

    e.HasOne(x => x.Account)
        .WithMany(u => u.Logins)
        .HasForeignKey(x => x.AccountId)
        .OnDelete(DeleteBehavior.Cascade);
});
```

- [ ] **Step 5: Create EF migration**

```bash
dotnet ef migrations add AddLoginEntityAndTotpColumns --project src/SsdidDrive.Api
```

Verify the migration file was created under `src/SsdidDrive.Api/Data/Migrations/`.

- [ ] **Step 6: Verify build**

```bash
dotnet build src/SsdidDrive.Api
```

Expected: Build succeeded.

- [ ] **Step 7: Commit**

```bash
git add src/SsdidDrive.Api/Data/Entities/Login.cs \
  src/SsdidDrive.Api/Data/Entities/User.cs \
  src/SsdidDrive.Api/Data/AppDbContext.cs \
  src/SsdidDrive.Api/SsdidDrive.Api.csproj \
  src/SsdidDrive.Api/Data/Migrations/
git commit -m "feat: add Login entity and TOTP columns to User"
```

---

### Task 2: OTP Service

Handles email OTP generation, storage (Redis or in-memory), and verification with attempt counting.

**Files:**
- Create: `src/SsdidDrive.Api/Services/OtpService.cs`
- Create: `tests/SsdidDrive.Api.Tests/Unit/OtpServiceTests.cs`
- Modify: `src/SsdidDrive.Api/Program.cs`

- [ ] **Step 1: Write failing tests**

Create `tests/SsdidDrive.Api.Tests/Unit/OtpServiceTests.cs`:

```csharp
using SsdidDrive.Api.Services;

namespace SsdidDrive.Api.Tests.Unit;

public class OtpServiceTests
{
    private readonly OtpService _sut = new(new FakeOtpStore());

    [Fact]
    public async Task GenerateAndVerify_ValidCode_ReturnsTrue()
    {
        var code = await _sut.GenerateAsync("test@example.com", "register");
        Assert.Equal(6, code.Length);
        Assert.True(code.All(char.IsDigit));

        var result = await _sut.VerifyAsync("test@example.com", "register", code);
        Assert.True(result);
    }

    [Fact]
    public async Task Verify_WrongCode_ReturnsFalse()
    {
        await _sut.GenerateAsync("test@example.com", "register");
        var result = await _sut.VerifyAsync("test@example.com", "register", "000000");
        Assert.False(result);
    }

    [Fact]
    public async Task Verify_CodeConsumedAfterSuccess_ReturnsFalse()
    {
        var code = await _sut.GenerateAsync("test@example.com", "register");
        await _sut.VerifyAsync("test@example.com", "register", code);

        var result = await _sut.VerifyAsync("test@example.com", "register", code);
        Assert.False(result);
    }

    [Fact]
    public async Task Verify_ExceedsMaxAttempts_ReturnsFalse()
    {
        var code = await _sut.GenerateAsync("test@example.com", "register");

        for (int i = 0; i < 5; i++)
            await _sut.VerifyAsync("test@example.com", "register", "000000");

        // Even correct code should fail after 5 wrong attempts
        var result = await _sut.VerifyAsync("test@example.com", "register", code);
        Assert.False(result);
    }

    [Fact]
    public async Task Verify_NoCodeGenerated_ReturnsFalse()
    {
        var result = await _sut.VerifyAsync("unknown@example.com", "register", "123456");
        Assert.False(result);
    }
}

/// <summary>In-memory OTP store for unit tests.</summary>
internal class FakeOtpStore : IOtpStore
{
    private readonly Dictionary<string, OtpEntry> _store = new();

    public Task StoreAsync(string key, OtpEntry entry, TimeSpan ttl, CancellationToken ct = default)
    {
        _store[key] = entry;
        return Task.CompletedTask;
    }

    public Task<OtpEntry?> GetAsync(string key, CancellationToken ct = default)
    {
        _store.TryGetValue(key, out var entry);
        return Task.FromResult(entry);
    }

    public Task DeleteAsync(string key, CancellationToken ct = default)
    {
        _store.Remove(key);
        return Task.CompletedTask;
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
dotnet test tests/SsdidDrive.Api.Tests --filter "OtpServiceTests" -v n
```

Expected: FAIL — `OtpService`, `IOtpStore`, `OtpEntry` do not exist.

- [ ] **Step 3: Implement OtpService**

Create `src/SsdidDrive.Api/Services/OtpService.cs`:

```csharp
using System.Security.Cryptography;

namespace SsdidDrive.Api.Services;

public record OtpEntry(string Code, DateTimeOffset ExpiresAt, int Attempts);

public interface IOtpStore
{
    Task StoreAsync(string key, OtpEntry entry, TimeSpan ttl, CancellationToken ct = default);
    Task<OtpEntry?> GetAsync(string key, CancellationToken ct = default);
    Task DeleteAsync(string key, CancellationToken ct = default);
}

public class OtpService(IOtpStore store)
{
    private const int CodeLength = 6;
    private const int MaxAttempts = 5;
    private static readonly TimeSpan Ttl = TimeSpan.FromMinutes(10);

    public async Task<string> GenerateAsync(string email, string purpose, CancellationToken ct = default)
    {
        var code = RandomNumberGenerator.GetInt32(0, 1_000_000).ToString("D6");
        var key = BuildKey(email, purpose);
        var entry = new OtpEntry(code, DateTimeOffset.UtcNow.Add(Ttl), 0);
        await store.StoreAsync(key, entry, Ttl, ct);
        return code;
    }

    public async Task<bool> VerifyAsync(string email, string purpose, string code, CancellationToken ct = default)
    {
        var key = BuildKey(email, purpose);
        var entry = await store.GetAsync(key, ct);

        if (entry is null || entry.ExpiresAt < DateTimeOffset.UtcNow)
            return false;

        if (entry.Attempts >= MaxAttempts)
        {
            await store.DeleteAsync(key, ct);
            return false;
        }

        if (entry.Code != code)
        {
            var updated = entry with { Attempts = entry.Attempts + 1 };
            await store.StoreAsync(key, updated, entry.ExpiresAt - DateTimeOffset.UtcNow, ct);
            return false;
        }

        await store.DeleteAsync(key, ct);
        return true;
    }

    private static string BuildKey(string email, string purpose) =>
        $"ssdid:otp:{email.ToLowerInvariant()}:{purpose}";
}

/// <summary>In-memory OTP store. Used when Redis is not configured.</summary>
public class InMemoryOtpStore : IOtpStore
{
    private readonly System.Collections.Concurrent.ConcurrentDictionary<string, OtpEntry> _store = new();

    public Task StoreAsync(string key, OtpEntry entry, TimeSpan ttl, CancellationToken ct = default)
    {
        _store[key] = entry;
        return Task.CompletedTask;
    }

    public Task<OtpEntry?> GetAsync(string key, CancellationToken ct = default)
    {
        _store.TryGetValue(key, out var entry);
        if (entry is not null && entry.ExpiresAt < DateTimeOffset.UtcNow)
        {
            _store.TryRemove(key, out _);
            return Task.FromResult<OtpEntry?>(null);
        }
        return Task.FromResult(entry);
    }

    public Task DeleteAsync(string key, CancellationToken ct = default)
    {
        _store.TryRemove(key, out _);
        return Task.CompletedTask;
    }
}

/// <summary>Redis-backed OTP store using IDistributedCache.</summary>
public class RedisOtpStore(Microsoft.Extensions.Caching.Distributed.IDistributedCache cache) : IOtpStore
{
    public async Task StoreAsync(string key, OtpEntry entry, TimeSpan ttl, CancellationToken ct = default)
    {
        var json = System.Text.Json.JsonSerializer.Serialize(entry);
        await cache.SetStringAsync(key, json, new Microsoft.Extensions.Caching.Distributed.DistributedCacheEntryOptions
        {
            AbsoluteExpirationRelativeToNow = ttl
        }, ct);
    }

    public async Task<OtpEntry?> GetAsync(string key, CancellationToken ct = default)
    {
        var json = await cache.GetStringAsync(key, ct);
        return json is null ? null : System.Text.Json.JsonSerializer.Deserialize<OtpEntry>(json);
    }

    public async Task DeleteAsync(string key, CancellationToken ct = default)
    {
        await cache.RemoveAsync(key, ct);
    }
}
```

- [ ] **Step 4: Register OtpService in Program.cs**

Add after the session store setup block in `Program.cs`:

```csharp
// ── OTP Store ──
if (!string.IsNullOrEmpty(redisConnection))
    builder.Services.AddSingleton<IOtpStore, RedisOtpStore>();
else
    builder.Services.AddSingleton<IOtpStore, InMemoryOtpStore>();

builder.Services.AddScoped<OtpService>();
```

- [ ] **Step 5: Run tests to verify they pass**

```bash
dotnet test tests/SsdidDrive.Api.Tests --filter "OtpServiceTests" -v n
```

Expected: All 5 tests PASS.

- [ ] **Step 6: Commit**

```bash
git add src/SsdidDrive.Api/Services/OtpService.cs \
  src/SsdidDrive.Api/Program.cs \
  tests/SsdidDrive.Api.Tests/Unit/OtpServiceTests.cs
git commit -m "feat: add OTP service with Redis and in-memory backends"
```

---

### Task 3: TOTP Service

Handles TOTP secret generation, otpauth URI building, code verification (+/- 1 time step), and backup code generation/verification.

**Files:**
- Create: `src/SsdidDrive.Api/Services/TotpService.cs`
- Create: `tests/SsdidDrive.Api.Tests/Unit/TotpServiceTests.cs`
- Modify: `src/SsdidDrive.Api/Program.cs`

- [ ] **Step 1: Write failing tests**

Create `tests/SsdidDrive.Api.Tests/Unit/TotpServiceTests.cs`:

```csharp
using OtpNet;
using SsdidDrive.Api.Services;

namespace SsdidDrive.Api.Tests.Unit;

public class TotpServiceTests
{
    private readonly TotpService _sut = new();

    [Fact]
    public void GenerateSecret_Returns32ByteBase32String()
    {
        var secret = _sut.GenerateSecret();
        var decoded = Base32Encoding.ToBytes(secret);
        Assert.Equal(20, decoded.Length); // 160-bit secret per RFC 4226
    }

    [Fact]
    public void GenerateOtpAuthUri_ReturnsValidUri()
    {
        var secret = _sut.GenerateSecret();
        var uri = _sut.GenerateOtpAuthUri(secret, "test@example.com");

        Assert.StartsWith("otpauth://totp/SSDID%20Drive:test%40example.com", uri);
        Assert.Contains($"secret={secret}", uri);
        Assert.Contains("issuer=SSDID%20Drive", uri);
    }

    [Fact]
    public void VerifyCode_CurrentCode_ReturnsTrue()
    {
        var secret = _sut.GenerateSecret();
        var totp = new Totp(Base32Encoding.ToBytes(secret));
        var code = totp.ComputeTotp();

        Assert.True(_sut.VerifyCode(secret, code));
    }

    [Fact]
    public void VerifyCode_WrongCode_ReturnsFalse()
    {
        var secret = _sut.GenerateSecret();
        Assert.False(_sut.VerifyCode(secret, "000000"));
    }

    [Fact]
    public void GenerateBackupCodes_Returns10UniqueCodes()
    {
        var codes = _sut.GenerateBackupCodes();
        Assert.Equal(10, codes.Count);
        Assert.Equal(10, codes.Distinct().Count());
        Assert.All(codes, c =>
        {
            Assert.Equal(8, c.Length);
            Assert.True(c.All(char.IsLetterOrDigit));
        });
    }

    [Fact]
    public void VerifyBackupCode_ValidCode_ReturnsTrueAndRemovesCode()
    {
        var codes = _sut.GenerateBackupCodes();
        var codeToUse = codes[0];
        var codesJson = System.Text.Json.JsonSerializer.Serialize(codes);

        var (valid, remainingJson) = _sut.VerifyBackupCode(codesJson, codeToUse);

        Assert.True(valid);
        var remaining = System.Text.Json.JsonSerializer.Deserialize<List<string>>(remainingJson!);
        Assert.Equal(9, remaining!.Count);
        Assert.DoesNotContain(codeToUse, remaining);
    }

    [Fact]
    public void VerifyBackupCode_InvalidCode_ReturnsFalse()
    {
        var codes = _sut.GenerateBackupCodes();
        var codesJson = System.Text.Json.JsonSerializer.Serialize(codes);

        var (valid, _) = _sut.VerifyBackupCode(codesJson, "INVALID1");

        Assert.False(valid);
    }

    [Fact]
    public void VerifyBackupCode_CaseInsensitive()
    {
        var codes = _sut.GenerateBackupCodes();
        var codeToUse = codes[0].ToLowerInvariant();
        var codesJson = System.Text.Json.JsonSerializer.Serialize(codes);

        var (valid, _) = _sut.VerifyBackupCode(codesJson, codeToUse);

        Assert.True(valid);
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
dotnet test tests/SsdidDrive.Api.Tests --filter "TotpServiceTests" -v n
```

Expected: FAIL — `TotpService` does not exist.

- [ ] **Step 3: Implement TotpService**

Create `src/SsdidDrive.Api/Services/TotpService.cs`:

```csharp
using System.Security.Cryptography;
using System.Text.Json;
using OtpNet;

namespace SsdidDrive.Api.Services;

public class TotpService
{
    private const string Issuer = "SSDID Drive";
    private const int SecretLength = 20; // 160-bit per RFC 4226
    private const int BackupCodeCount = 10;
    private const int BackupCodeLength = 8;

    public string GenerateSecret()
    {
        var secret = new byte[SecretLength];
        RandomNumberGenerator.Fill(secret);
        return Base32Encoding.ToString(secret);
    }

    public string GenerateOtpAuthUri(string base32Secret, string email)
    {
        var label = Uri.EscapeDataString($"{Issuer}:{email}");
        var issuerParam = Uri.EscapeDataString(Issuer);
        return $"otpauth://totp/{label}?secret={base32Secret}&issuer={issuerParam}&algorithm=SHA1&digits=6&period=30";
    }

    public bool VerifyCode(string base32Secret, string code)
    {
        var secretBytes = Base32Encoding.ToBytes(base32Secret);
        var totp = new Totp(secretBytes);
        return totp.VerifyTotp(code, out _, new VerificationWindow(previous: 1, future: 1));
    }

    public List<string> GenerateBackupCodes()
    {
        const string chars = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"; // No I, O, 0, 1 to avoid confusion
        var codes = new List<string>(BackupCodeCount);

        for (int i = 0; i < BackupCodeCount; i++)
        {
            var code = new char[BackupCodeLength];
            for (int j = 0; j < BackupCodeLength; j++)
                code[j] = chars[RandomNumberGenerator.GetInt32(chars.Length)];
            codes.Add(new string(code));
        }

        return codes;
    }

    public (bool Valid, string? RemainingCodesJson) VerifyBackupCode(string codesJson, string code)
    {
        var codes = JsonSerializer.Deserialize<List<string>>(codesJson);
        if (codes is null) return (false, null);

        var match = codes.FirstOrDefault(c =>
            string.Equals(c, code, StringComparison.OrdinalIgnoreCase));

        if (match is null) return (false, null);

        codes.Remove(match);
        return (true, JsonSerializer.Serialize(codes));
    }
}
```

- [ ] **Step 4: Register TotpService in Program.cs**

Add after OTP store registration:

```csharp
builder.Services.AddSingleton<TotpService>();
```

- [ ] **Step 5: Run tests to verify they pass**

```bash
dotnet test tests/SsdidDrive.Api.Tests --filter "TotpServiceTests" -v n
```

Expected: All 8 tests PASS.

- [ ] **Step 6: Commit**

```bash
git add src/SsdidDrive.Api/Services/TotpService.cs \
  src/SsdidDrive.Api/Program.cs \
  tests/SsdidDrive.Api.Tests/Unit/TotpServiceTests.cs
git commit -m "feat: add TOTP service with backup code support"
```

---

### Task 4: Session Store Dual-Mode + Middleware Update

Update middleware to handle both DID-based sessions (existing) and Account.Id-based sessions (new auth). Add MfaPending support.

**Files:**
- Modify: `src/SsdidDrive.Api/Common/CurrentUserAccessor.cs`
- Modify: `src/SsdidDrive.Api/Middleware/SsdidAuthMiddleware.cs`

- [ ] **Step 1: Add MfaPending to CurrentUserAccessor**

Modify `src/SsdidDrive.Api/Common/CurrentUserAccessor.cs` — add property:

```csharp
public bool MfaPending { get; set; }
```

- [ ] **Step 2: Update SsdidAuthMiddleware for dual-mode**

Modify `src/SsdidDrive.Api/Middleware/SsdidAuthMiddleware.cs`. Replace the session→user lookup section. After extracting the token and calling `sessionStore.GetSession(token)`:

```csharp
var sessionValue = sessionStore.GetSession(token);
if (sessionValue is null)
{
    await WriteProblem(context, 401, "Invalid or expired session");
    return;
}

// Detect session type and resolve user
User? user;
bool mfaPending = false;

var effectiveValue = sessionValue;
if (sessionValue.StartsWith("mfa:", StringComparison.Ordinal))
{
    mfaPending = true;
    effectiveValue = sessionValue[4..];
}

if (Guid.TryParse(effectiveValue, out var accountId))
{
    // New auth: session value is Account.Id (UUID)
    user = await db.Users.AsNoTracking().FirstOrDefaultAsync(u => u.Id == accountId);
}
else
{
    // Legacy SSDID auth: session value is DID
    user = await db.Users.AsNoTracking().FirstOrDefaultAsync(u => u.Did == sessionValue);
}

if (user is null)
{
    await WriteProblem(context, 401, "No account found for this session");
    return;
}

if (user.Status == UserStatus.Suspended)
{
    await WriteProblem(context, 403, "Account is suspended");
    return;
}

// If MFA pending, only allow TOTP verify endpoint
if (mfaPending)
{
    var path = context.Request.Path.Value ?? "";
    if (!path.Equals("/api/auth/totp/verify", StringComparison.OrdinalIgnoreCase))
    {
        await WriteProblem(context, 403, "MFA verification required");
        return;
    }
}

accessor.UserId = user.Id;
accessor.Did = user.Did;
accessor.User = user;
accessor.SessionToken = token;
accessor.SystemRole = user.SystemRole;
accessor.MfaPending = mfaPending;
```

- [ ] **Step 3: Verify build**

```bash
dotnet build src/SsdidDrive.Api
```

Expected: Build succeeded.

- [ ] **Step 4: Commit**

```bash
git add src/SsdidDrive.Api/Common/CurrentUserAccessor.cs \
  src/SsdidDrive.Api/Middleware/SsdidAuthMiddleware.cs
git commit -m "feat: dual-mode auth middleware (DID + Account.Id sessions)"
```

---

## Chunk 2: Auth Endpoints

### Task 5: Email Registration Endpoints

POST /api/auth/email/register and POST /api/auth/email/register/verify

**Files:**
- Create: `src/SsdidDrive.Api/Features/Auth/EmailRegister.cs`
- Create: `src/SsdidDrive.Api/Features/Auth/EmailRegisterVerify.cs`
- Modify: `src/SsdidDrive.Api/Features/Auth/AuthFeature.cs`
- Create: `tests/SsdidDrive.Api.Tests/Integration/EmailAuthFlowTests.cs`

- [ ] **Step 1: Write integration test for email registration**

Create `tests/SsdidDrive.Api.Tests/Integration/EmailAuthFlowTests.cs`:

```csharp
using System.Net;
using System.Net.Http.Json;
using System.Text.Json;

namespace SsdidDrive.Api.Tests.Integration;

public class EmailAuthFlowTests : IClassFixture<SsdidDriveFactory>
{
    private readonly HttpClient _client;
    private static readonly JsonSerializerOptions SnakeJson = new()
    {
        PropertyNamingPolicy = JsonNamingPolicy.SnakeCaseLower
    };

    public EmailAuthFlowTests(SsdidDriveFactory factory)
    {
        _client = factory.CreateClient();
    }

    [Fact]
    public async Task Register_WithoutInvitation_Returns400()
    {
        var resp = await _client.PostAsJsonAsync("/api/auth/email/register",
            new { email = "test@example.com" }, SnakeJson);

        Assert.Equal(HttpStatusCode.BadRequest, resp.StatusCode);
    }

    [Fact]
    public async Task Register_WithInvalidInvitation_Returns404()
    {
        var resp = await _client.PostAsJsonAsync("/api/auth/email/register",
            new { email = "test@example.com", invitation_token = "invalid-token" }, SnakeJson);

        Assert.Equal(HttpStatusCode.NotFound, resp.StatusCode);
    }

    [Fact]
    public async Task RegisterVerify_WithWrongCode_Returns401()
    {
        var resp = await _client.PostAsJsonAsync("/api/auth/email/register/verify",
            new { email = "test@example.com", code = "000000", invitation_token = "invalid" }, SnakeJson);

        // Should fail on invitation validation or code verification
        Assert.True(resp.StatusCode == HttpStatusCode.NotFound
            || resp.StatusCode == HttpStatusCode.Unauthorized);
    }
}
```

**Note:** Full flow integration tests (with real invitation creation → OTP → verify) will be added after all auth endpoints are in place. These tests verify basic validation.

- [ ] **Step 2: Run tests to verify they fail**

```bash
dotnet test tests/SsdidDrive.Api.Tests --filter "EmailAuthFlowTests" -v n
```

Expected: FAIL — endpoints don't exist yet (404, not the expected status codes).

- [ ] **Step 3: Implement EmailRegister endpoint**

Create `src/SsdidDrive.Api/Features/Auth/EmailRegister.cs`:

```csharp
using Microsoft.EntityFrameworkCore;
using SsdidDrive.Api.Common;
using SsdidDrive.Api.Data;
using SsdidDrive.Api.Data.Entities;
using SsdidDrive.Api.Services;

namespace SsdidDrive.Api.Features.Auth;

public static class EmailRegister
{
    public record Request(string Email, string? InvitationToken);

    public static void Map(RouteGroupBuilder group) =>
        group.MapPost("/email/register", Handle)
            .WithMetadata(new SsdidPublicAttribute());

    private static async Task<IResult> Handle(
        Request req,
        AppDbContext db,
        OtpService otpService,
        IEmailService emailService,
        ILogger<EmailRegister> logger,
        CancellationToken ct)
    {
        if (string.IsNullOrWhiteSpace(req.Email))
            return AppError.BadRequest("Email is required").ToProblemResult();

        if (string.IsNullOrWhiteSpace(req.InvitationToken))
            return AppError.BadRequest("Invitation token is required").ToProblemResult();

        var email = req.Email.Trim().ToLowerInvariant();

        // Validate invitation
        var invitation = await db.Invitations
            .FirstOrDefaultAsync(i => i.Token == req.InvitationToken
                && i.Status == InvitationStatus.Pending
                && i.ExpiresAt > DateTimeOffset.UtcNow, ct);

        if (invitation is null)
            return AppError.NotFound("Invalid or expired invitation").ToProblemResult();

        // Check if account already exists with this email
        var existingUser = await db.Users
            .FirstOrDefaultAsync(u => u.Email == email, ct);

        if (existingUser is not null)
            return AppError.Conflict("An account with this email already exists").ToProblemResult();

        // Generate and send OTP
        var code = await otpService.GenerateAsync(email, "register", ct);

        try
        {
            await emailService.SendOtpAsync(email, code, ct);
        }
        catch (Exception ex)
        {
            logger.LogError(ex, "Failed to send OTP email to {Email}", email);
            return AppError.ServiceUnavailable("Failed to send verification email").ToProblemResult();
        }

        return Results.Ok(new { message = "Verification code sent to your email" });
    }
}
```

- [ ] **Step 4: Implement EmailRegisterVerify endpoint**

Create `src/SsdidDrive.Api/Features/Auth/EmailRegisterVerify.cs`:

```csharp
using Microsoft.EntityFrameworkCore;
using SsdidDrive.Api.Common;
using SsdidDrive.Api.Data;
using SsdidDrive.Api.Data.Entities;
using SsdidDrive.Api.Services;

namespace SsdidDrive.Api.Features.Auth;

public static class EmailRegisterVerify
{
    public record Request(string Email, string Code, string? InvitationToken);

    public static void Map(RouteGroupBuilder group) =>
        group.MapPost("/email/register/verify", Handle)
            .WithMetadata(new SsdidPublicAttribute());

    private static async Task<IResult> Handle(
        Request req,
        AppDbContext db,
        OtpService otpService,
        ISessionStore sessionStore,
        AuditService auditService,
        CancellationToken ct)
    {
        if (string.IsNullOrWhiteSpace(req.Email) || string.IsNullOrWhiteSpace(req.Code))
            return AppError.BadRequest("Email and code are required").ToProblemResult();

        if (string.IsNullOrWhiteSpace(req.InvitationToken))
            return AppError.BadRequest("Invitation token is required").ToProblemResult();

        var email = req.Email.Trim().ToLowerInvariant();

        // Validate invitation
        var invitation = await db.Invitations
            .FirstOrDefaultAsync(i => i.Token == req.InvitationToken
                && i.Status == InvitationStatus.Pending
                && i.ExpiresAt > DateTimeOffset.UtcNow, ct);

        if (invitation is null)
            return AppError.NotFound("Invalid or expired invitation").ToProblemResult();

        // Verify OTP
        if (!await otpService.VerifyAsync(email, "register", req.Code, ct))
            return AppError.Unauthorized("Invalid or expired verification code").ToProblemResult();

        // Create account
        var user = new User
        {
            Email = email,
            EmailVerified = true,
            Status = UserStatus.Active,
            TenantId = invitation.TenantId,
            CreatedAt = DateTimeOffset.UtcNow,
            UpdatedAt = DateTimeOffset.UtcNow,
        };
        db.Users.Add(user);

        // Create login
        var login = new Login
        {
            AccountId = user.Id,
            Provider = LoginProvider.Email,
            ProviderSubject = email,
        };
        db.Logins.Add(login);

        // Accept invitation
        invitation.Status = InvitationStatus.Accepted;
        invitation.InvitedUserId = user.Id;
        invitation.AcceptedAt = DateTimeOffset.UtcNow;

        // Add to tenant
        db.UserTenants.Add(new UserTenant
        {
            UserId = user.Id,
            TenantId = invitation.TenantId,
            Role = invitation.Role,
        });

        await db.SaveChangesAsync(ct);

        // Create session (store Account.Id, not DID)
        var token = sessionStore.CreateSession(user.Id.ToString());
        if (token is null)
            return AppError.ServiceUnavailable("Session limit exceeded").ToProblemResult();

        await auditService.LogAsync(user.Id, "auth.register.email", "user", user.Id, null, ct);

        return Results.Ok(new
        {
            token,
            account_id = user.Id,
            email = user.Email,
            requires_totp_setup = true,
        });
    }
}
```

- [ ] **Step 5: Add IEmailService.SendOtpAsync if not exists**

Check if `IEmailService` already has a `SendOtpAsync` method. If not, add to `src/SsdidDrive.Api/Services/IEmailService.cs`:

```csharp
Task SendOtpAsync(string email, string code, CancellationToken ct = default);
```

And implement in `EmailService` and `NullEmailService` (which just logs).

- [ ] **Step 6: Map endpoints in AuthFeature.cs**

Modify `src/SsdidDrive.Api/Features/Auth/AuthFeature.cs` — add inside the `MapAuthFeature` method:

```csharp
EmailRegister.Map(auth);
EmailRegisterVerify.Map(auth);
```

- [ ] **Step 7: Run tests to verify they pass**

```bash
dotnet test tests/SsdidDrive.Api.Tests --filter "EmailAuthFlowTests" -v n
```

Expected: All 3 tests PASS.

- [ ] **Step 8: Commit**

```bash
git add src/SsdidDrive.Api/Features/Auth/EmailRegister.cs \
  src/SsdidDrive.Api/Features/Auth/EmailRegisterVerify.cs \
  src/SsdidDrive.Api/Features/Auth/AuthFeature.cs \
  tests/SsdidDrive.Api.Tests/Integration/EmailAuthFlowTests.cs
git commit -m "feat: add email registration endpoints with invitation validation"
```

---

### Task 6: TOTP Setup + Confirm Endpoints

POST /api/auth/totp/setup and POST /api/auth/totp/setup/confirm. These are authenticated — called after registration to complete TOTP setup.

**Files:**
- Create: `src/SsdidDrive.Api/Features/Auth/TotpSetup.cs`
- Create: `src/SsdidDrive.Api/Features/Auth/TotpSetupConfirm.cs`
- Modify: `src/SsdidDrive.Api/Features/Auth/AuthFeature.cs`

- [ ] **Step 1: Implement TotpSetup endpoint**

Create `src/SsdidDrive.Api/Features/Auth/TotpSetup.cs`:

```csharp
using Microsoft.EntityFrameworkCore;
using SsdidDrive.Api.Common;
using SsdidDrive.Api.Data;
using SsdidDrive.Api.Services;

namespace SsdidDrive.Api.Features.Auth;

public static class TotpSetup
{
    public static void Map(RouteGroupBuilder group) =>
        group.MapPost("/totp/setup", Handle);

    private static async Task<IResult> Handle(
        CurrentUserAccessor accessor,
        AppDbContext db,
        TotpService totpService,
        CancellationToken ct)
    {
        var user = await db.Users.FirstOrDefaultAsync(u => u.Id == accessor.UserId, ct);
        if (user is null)
            return AppError.NotFound("Account not found").ToProblemResult();

        if (user.TotpEnabled)
            return AppError.Conflict("TOTP is already enabled").ToProblemResult();

        var secret = totpService.GenerateSecret();
        var uri = totpService.GenerateOtpAuthUri(secret, user.Email ?? "unknown");

        // Store secret (not yet enabled until confirmed)
        user.TotpSecret = secret;
        user.UpdatedAt = DateTimeOffset.UtcNow;
        await db.SaveChangesAsync(ct);

        return Results.Ok(new
        {
            secret,
            otpauth_uri = uri,
        });
    }
}
```

- [ ] **Step 2: Implement TotpSetupConfirm endpoint**

Create `src/SsdidDrive.Api/Features/Auth/TotpSetupConfirm.cs`:

```csharp
using Microsoft.EntityFrameworkCore;
using SsdidDrive.Api.Common;
using SsdidDrive.Api.Data;
using SsdidDrive.Api.Services;

namespace SsdidDrive.Api.Features.Auth;

public static class TotpSetupConfirm
{
    public record Request(string Code);

    public static void Map(RouteGroupBuilder group) =>
        group.MapPost("/totp/setup/confirm", Handle);

    private static async Task<IResult> Handle(
        Request req,
        CurrentUserAccessor accessor,
        AppDbContext db,
        TotpService totpService,
        AuditService auditService,
        CancellationToken ct)
    {
        if (string.IsNullOrWhiteSpace(req.Code))
            return AppError.BadRequest("TOTP code is required").ToProblemResult();

        var user = await db.Users.FirstOrDefaultAsync(u => u.Id == accessor.UserId, ct);
        if (user is null)
            return AppError.NotFound("Account not found").ToProblemResult();

        if (string.IsNullOrEmpty(user.TotpSecret))
            return AppError.BadRequest("Call /totp/setup first").ToProblemResult();

        if (user.TotpEnabled)
            return AppError.Conflict("TOTP is already enabled").ToProblemResult();

        if (!totpService.VerifyCode(user.TotpSecret, req.Code))
            return AppError.Unauthorized("Invalid TOTP code").ToProblemResult();

        var backupCodes = totpService.GenerateBackupCodes();

        user.TotpEnabled = true;
        user.BackupCodes = System.Text.Json.JsonSerializer.Serialize(backupCodes);
        user.UpdatedAt = DateTimeOffset.UtcNow;
        await db.SaveChangesAsync(ct);

        await auditService.LogAsync(accessor.UserId, "auth.totp.setup", "user", accessor.UserId, null, ct);

        return Results.Ok(new
        {
            totp_enabled = true,
            backup_codes = backupCodes,
        });
    }
}
```

- [ ] **Step 3: Map endpoints in AuthFeature.cs**

Add:

```csharp
TotpSetup.Map(auth);
TotpSetupConfirm.Map(auth);
```

- [ ] **Step 4: Build and verify**

```bash
dotnet build src/SsdidDrive.Api
```

- [ ] **Step 5: Commit**

```bash
git add src/SsdidDrive.Api/Features/Auth/TotpSetup.cs \
  src/SsdidDrive.Api/Features/Auth/TotpSetupConfirm.cs \
  src/SsdidDrive.Api/Features/Auth/AuthFeature.cs
git commit -m "feat: add TOTP setup and confirm endpoints"
```

---

### Task 7: Email Login + TOTP Verify Endpoints

POST /api/auth/email/login and POST /api/auth/totp/verify

**Files:**
- Create: `src/SsdidDrive.Api/Features/Auth/EmailLogin.cs`
- Create: `src/SsdidDrive.Api/Features/Auth/TotpVerify.cs`
- Modify: `src/SsdidDrive.Api/Features/Auth/AuthFeature.cs`

- [ ] **Step 1: Implement EmailLogin endpoint**

Create `src/SsdidDrive.Api/Features/Auth/EmailLogin.cs`:

```csharp
using Microsoft.EntityFrameworkCore;
using SsdidDrive.Api.Common;
using SsdidDrive.Api.Data;
using SsdidDrive.Api.Data.Entities;

namespace SsdidDrive.Api.Features.Auth;

public static class EmailLogin
{
    public record Request(string Email);

    public static void Map(RouteGroupBuilder group) =>
        group.MapPost("/email/login", Handle)
            .WithMetadata(new SsdidPublicAttribute());

    private static async Task<IResult> Handle(
        Request req,
        AppDbContext db,
        CancellationToken ct)
    {
        if (string.IsNullOrWhiteSpace(req.Email))
            return AppError.BadRequest("Email is required").ToProblemResult();

        var email = req.Email.Trim().ToLowerInvariant();

        var user = await db.Users
            .AsNoTracking()
            .FirstOrDefaultAsync(u => u.Email == email && u.Status == UserStatus.Active, ct);

        if (user is null)
            return AppError.NotFound("No account with this email").ToProblemResult();

        if (!user.TotpEnabled)
            return AppError.BadRequest("TOTP is not set up for this account").ToProblemResult();

        return Results.Ok(new { requires_totp = true, email });
    }
}
```

- [ ] **Step 2: Implement TotpVerify endpoint**

Create `src/SsdidDrive.Api/Features/Auth/TotpVerify.cs`:

```csharp
using Microsoft.EntityFrameworkCore;
using SsdidDrive.Api.Common;
using SsdidDrive.Api.Data;
using SsdidDrive.Api.Data.Entities;
using SsdidDrive.Api.Services;

namespace SsdidDrive.Api.Features.Auth;

public static class TotpVerify
{
    public record Request(string Email, string Code);

    public static void Map(RouteGroupBuilder group) =>
        group.MapPost("/totp/verify", Handle)
            .WithMetadata(new SsdidPublicAttribute());

    private static async Task<IResult> Handle(
        Request req,
        AppDbContext db,
        TotpService totpService,
        ISessionStore sessionStore,
        AuditService auditService,
        CancellationToken ct)
    {
        if (string.IsNullOrWhiteSpace(req.Email) || string.IsNullOrWhiteSpace(req.Code))
            return AppError.BadRequest("Email and code are required").ToProblemResult();

        var email = req.Email.Trim().ToLowerInvariant();

        var user = await db.Users
            .FirstOrDefaultAsync(u => u.Email == email && u.Status == UserStatus.Active, ct);

        if (user is null)
            return AppError.Unauthorized("Invalid credentials").ToProblemResult();

        if (!user.TotpEnabled || string.IsNullOrEmpty(user.TotpSecret))
            return AppError.BadRequest("TOTP is not set up for this account").ToProblemResult();

        // Try TOTP code first
        bool valid = totpService.VerifyCode(user.TotpSecret, req.Code);

        // If TOTP failed, try backup code
        string? updatedBackupCodes = null;
        if (!valid && !string.IsNullOrEmpty(user.BackupCodes))
        {
            var (backupValid, remaining) = totpService.VerifyBackupCode(user.BackupCodes, req.Code);
            if (backupValid)
            {
                valid = true;
                updatedBackupCodes = remaining;
            }
        }

        if (!valid)
        {
            await auditService.LogAsync(Guid.Empty, "auth.login.failed", "user", user.Id,
                $"Failed TOTP for {email}", ct);
            return AppError.Unauthorized("Invalid TOTP code").ToProblemResult();
        }

        // Consume backup code if used
        if (updatedBackupCodes is not null)
        {
            user.BackupCodes = updatedBackupCodes;
        }

        user.LastLoginAt = DateTimeOffset.UtcNow;
        user.UpdatedAt = DateTimeOffset.UtcNow;
        await db.SaveChangesAsync(ct);

        var token = sessionStore.CreateSession(user.Id.ToString());
        if (token is null)
            return AppError.ServiceUnavailable("Session limit exceeded").ToProblemResult();

        await auditService.LogAsync(user.Id, "auth.login.email", "user", user.Id, null, ct);

        return Results.Ok(new
        {
            token,
            account_id = user.Id,
            email = user.Email,
            display_name = user.DisplayName,
        });
    }
}
```

- [ ] **Step 3: Map endpoints in AuthFeature.cs**

Add:

```csharp
EmailLogin.Map(auth);
TotpVerify.Map(auth);
```

- [ ] **Step 4: Build and verify**

```bash
dotnet build src/SsdidDrive.Api
```

- [ ] **Step 5: Commit**

```bash
git add src/SsdidDrive.Api/Features/Auth/EmailLogin.cs \
  src/SsdidDrive.Api/Features/Auth/TotpVerify.cs \
  src/SsdidDrive.Api/Features/Auth/AuthFeature.cs
git commit -m "feat: add email login and TOTP verify endpoints"
```

---

### Task 8: OIDC Token Validation + Verify Endpoint

POST /api/auth/oidc/verify — validates Google/Microsoft ID tokens from native SDKs.

**Files:**
- Create: `src/SsdidDrive.Api/Services/OidcTokenValidator.cs`
- Create: `src/SsdidDrive.Api/Features/Auth/OidcVerify.cs`
- Modify: `src/SsdidDrive.Api/Features/Auth/AuthFeature.cs`
- Modify: `src/SsdidDrive.Api/Program.cs`

- [ ] **Step 1: Implement OidcTokenValidator**

Create `src/SsdidDrive.Api/Services/OidcTokenValidator.cs`:

```csharp
using System.IdentityModel.Tokens.Jwt;
using Microsoft.IdentityModel.Protocols;
using Microsoft.IdentityModel.Protocols.OpenIdConnect;
using Microsoft.IdentityModel.Tokens;

namespace SsdidDrive.Api.Services;

public record OidcClaims(string Subject, string Email, string? Name);

public class OidcTokenValidator
{
    private readonly Dictionary<string, ProviderConfig> _providers;
    private readonly ILogger<OidcTokenValidator> _logger;

    public OidcTokenValidator(IConfiguration config, ILogger<OidcTokenValidator> logger)
    {
        _logger = logger;
        _providers = new(StringComparer.OrdinalIgnoreCase)
        {
            ["google"] = new(
                "https://accounts.google.com/.well-known/openid-configuration",
                config["Oidc:Google:ClientId"] ?? ""),
            ["microsoft"] = new(
                "https://login.microsoftonline.com/common/v2.0/.well-known/openid-configuration",
                config["Oidc:Microsoft:ClientId"] ?? ""),
        };
    }

    public async Task<Result<OidcClaims>> ValidateAsync(string provider, string idToken, CancellationToken ct = default)
    {
        if (!_providers.TryGetValue(provider, out var config))
            return AppError.BadRequest($"Unsupported OIDC provider: {provider}");

        if (string.IsNullOrEmpty(config.ClientId))
            return AppError.ServiceUnavailable($"OIDC provider '{provider}' is not configured");

        try
        {
            var configManager = new ConfigurationManager<OpenIdConnectConfiguration>(
                config.MetadataUrl,
                new OpenIdConnectConfigurationRetriever(),
                new HttpDocumentRetriever());

            var oidcConfig = await configManager.GetConfigurationAsync(ct);

            var validationParams = new TokenValidationParameters
            {
                ValidIssuer = oidcConfig.Issuer,
                ValidAudience = config.ClientId,
                IssuerSigningKeys = oidcConfig.SigningKeys,
                ValidateIssuer = true,
                ValidateAudience = true,
                ValidateLifetime = true,
                ValidateIssuerSigningKey = true,
                ClockSkew = TimeSpan.FromMinutes(2),
            };

            // Microsoft tokens may have multiple valid issuers
            if (provider.Equals("microsoft", StringComparison.OrdinalIgnoreCase))
            {
                validationParams.ValidIssuers = [
                    oidcConfig.Issuer,
                    "https://login.microsoftonline.com/{tenantid}/v2.0"
                ];
                validationParams.ValidateIssuer = false; // Microsoft uses tenant-specific issuers
            }

            var handler = new JwtSecurityTokenHandler();
            var principal = handler.ValidateToken(idToken, validationParams, out var validatedToken);

            var sub = principal.FindFirst("sub")?.Value
                ?? principal.FindFirst(System.Security.Claims.ClaimTypes.NameIdentifier)?.Value;
            var email = principal.FindFirst("email")?.Value
                ?? principal.FindFirst(System.Security.Claims.ClaimTypes.Email)?.Value;
            var name = principal.FindFirst("name")?.Value
                ?? principal.FindFirst(System.Security.Claims.ClaimTypes.Name)?.Value;

            if (string.IsNullOrEmpty(sub) || string.IsNullOrEmpty(email))
                return AppError.BadRequest("ID token missing required claims (sub, email)");

            return new OidcClaims(sub, email.ToLowerInvariant(), name);
        }
        catch (SecurityTokenException ex)
        {
            _logger.LogWarning(ex, "OIDC token validation failed for provider {Provider}", provider);
            return AppError.Unauthorized("Invalid ID token");
        }
    }

    private record ProviderConfig(string MetadataUrl, string ClientId);
}
```

- [ ] **Step 2: Implement OidcVerify endpoint**

Create `src/SsdidDrive.Api/Features/Auth/OidcVerify.cs`:

```csharp
using Microsoft.EntityFrameworkCore;
using SsdidDrive.Api.Common;
using SsdidDrive.Api.Data;
using SsdidDrive.Api.Data.Entities;
using SsdidDrive.Api.Services;

namespace SsdidDrive.Api.Features.Auth;

public static class OidcVerify
{
    public record Request(string Provider, string IdToken, string? InvitationToken);

    public static void Map(RouteGroupBuilder group) =>
        group.MapPost("/oidc/verify", Handle)
            .WithMetadata(new SsdidPublicAttribute());

    private static async Task<IResult> Handle(
        Request req,
        AppDbContext db,
        OidcTokenValidator validator,
        ISessionStore sessionStore,
        AuditService auditService,
        CancellationToken ct)
    {
        if (string.IsNullOrWhiteSpace(req.Provider) || string.IsNullOrWhiteSpace(req.IdToken))
            return AppError.BadRequest("Provider and id_token are required").ToProblemResult();

        // Validate ID token
        var claims = await validator.ValidateAsync(req.Provider, req.IdToken, ct);
        if (!claims.IsSuccess)
            return claims.Error!.ToProblemResult();

        var oidcClaims = claims.Value!;
        var providerEnum = req.Provider.ToLowerInvariant() switch
        {
            "google" => LoginProvider.Google,
            "microsoft" => LoginProvider.Microsoft,
            _ => (LoginProvider?)null,
        };

        if (providerEnum is null)
            return AppError.BadRequest("Unsupported provider").ToProblemResult();

        // Look up existing login
        var existingLogin = await db.Logins
            .Include(l => l.Account)
            .FirstOrDefaultAsync(l =>
                l.Provider == providerEnum.Value
                && l.ProviderSubject == oidcClaims.Subject, ct);

        if (existingLogin is not null)
        {
            // Existing account — login
            var user = existingLogin.Account;
            if (user.Status == UserStatus.Suspended)
                return AppError.Forbidden("Account is suspended").ToProblemResult();

            user.LastLoginAt = DateTimeOffset.UtcNow;
            user.UpdatedAt = DateTimeOffset.UtcNow;
            await db.SaveChangesAsync(ct);

            // Check if admin requiring TOTP
            var userTenant = await db.UserTenants
                .FirstOrDefaultAsync(ut => ut.UserId == user.Id, ct);

            bool needsMfa = user.TotpEnabled
                && userTenant is not null
                && (userTenant.Role == TenantRole.Owner || userTenant.Role == TenantRole.Admin);

            var sessionValue = needsMfa ? $"mfa:{user.Id}" : user.Id.ToString();
            var token = sessionStore.CreateSession(sessionValue);
            if (token is null)
                return AppError.ServiceUnavailable("Session limit exceeded").ToProblemResult();

            await auditService.LogAsync(user.Id, "auth.login.oidc", "user", user.Id,
                $"Provider: {req.Provider}", ct);

            return Results.Ok(new
            {
                token,
                account_id = user.Id,
                email = user.Email,
                display_name = user.DisplayName,
                mfa_required = needsMfa,
            });
        }

        // No existing login — need invitation for registration
        if (string.IsNullOrWhiteSpace(req.InvitationToken))
            return AppError.NotFound("No account linked to this provider. Register first or link in Settings.").ToProblemResult();

        // Validate invitation
        var invitation = await db.Invitations
            .FirstOrDefaultAsync(i => i.Token == req.InvitationToken
                && i.Status == InvitationStatus.Pending
                && i.ExpiresAt > DateTimeOffset.UtcNow, ct);

        if (invitation is null)
            return AppError.NotFound("Invalid or expired invitation").ToProblemResult();

        // Create new account
        var newUser = new User
        {
            Email = oidcClaims.Email,
            DisplayName = oidcClaims.Name,
            EmailVerified = true, // OIDC provider verified the email
            Status = UserStatus.Active,
            TenantId = invitation.TenantId,
            CreatedAt = DateTimeOffset.UtcNow,
            UpdatedAt = DateTimeOffset.UtcNow,
        };
        db.Users.Add(newUser);

        // Create login
        db.Logins.Add(new Login
        {
            AccountId = newUser.Id,
            Provider = providerEnum.Value,
            ProviderSubject = oidcClaims.Subject,
        });

        // Accept invitation
        invitation.Status = InvitationStatus.Accepted;
        invitation.InvitedUserId = newUser.Id;
        invitation.AcceptedAt = DateTimeOffset.UtcNow;

        db.UserTenants.Add(new UserTenant
        {
            UserId = newUser.Id,
            TenantId = invitation.TenantId,
            Role = invitation.Role,
        });

        await db.SaveChangesAsync(ct);

        var newToken = sessionStore.CreateSession(newUser.Id.ToString());
        if (newToken is null)
            return AppError.ServiceUnavailable("Session limit exceeded").ToProblemResult();

        await auditService.LogAsync(newUser.Id, "auth.register.oidc", "user", newUser.Id,
            $"Provider: {req.Provider}", ct);

        return Results.Ok(new
        {
            token = newToken,
            account_id = newUser.Id,
            email = newUser.Email,
            display_name = newUser.DisplayName,
            is_new_account = true,
        });
    }
}
```

- [ ] **Step 3: Register services and map endpoint**

In `Program.cs`, add:

```csharp
builder.Services.AddSingleton<OidcTokenValidator>();
```

In `AuthFeature.cs`, add:

```csharp
OidcVerify.Map(auth);
```

- [ ] **Step 4: Build and verify**

```bash
dotnet build src/SsdidDrive.Api
```

- [ ] **Step 5: Commit**

```bash
git add src/SsdidDrive.Api/Services/OidcTokenValidator.cs \
  src/SsdidDrive.Api/Features/Auth/OidcVerify.cs \
  src/SsdidDrive.Api/Features/Auth/AuthFeature.cs \
  src/SsdidDrive.Api/Program.cs
git commit -m "feat: add OIDC token validation and verify endpoint"
```

---

## Chunk 3: Account Linking + Recovery

### Task 9: Account Feature — Link Logins Endpoints

**Files:**
- Create: `src/SsdidDrive.Api/Features/Account/AccountFeature.cs`
- Create: `src/SsdidDrive.Api/Features/Account/ListLogins.cs`
- Create: `src/SsdidDrive.Api/Features/Account/LinkEmail.cs`
- Create: `src/SsdidDrive.Api/Features/Account/LinkEmailVerify.cs`
- Create: `src/SsdidDrive.Api/Features/Account/LinkOidc.cs`
- Create: `src/SsdidDrive.Api/Features/Account/UnlinkLogin.cs`
- Modify: `src/SsdidDrive.Api/Program.cs`
- Create: `tests/SsdidDrive.Api.Tests/Integration/LoginLinkingTests.cs`

- [ ] **Step 1: Create AccountFeature route group**

Create `src/SsdidDrive.Api/Features/Account/AccountFeature.cs`:

```csharp
namespace SsdidDrive.Api.Features.Account;

public static class AccountFeature
{
    public static void MapAccountFeature(this WebApplication app)
    {
        var account = app.MapGroup("/api/account").WithTags("Account");

        ListLogins.Map(account);
        LinkEmail.Map(account);
        LinkEmailVerify.Map(account);
        LinkOidc.Map(account);
        UnlinkLogin.Map(account);
    }
}
```

- [ ] **Step 2: Implement ListLogins**

Create `src/SsdidDrive.Api/Features/Account/ListLogins.cs`:

```csharp
using Microsoft.EntityFrameworkCore;
using SsdidDrive.Api.Common;
using SsdidDrive.Api.Data;

namespace SsdidDrive.Api.Features.Account;

public static class ListLogins
{
    public static void Map(RouteGroupBuilder group) =>
        group.MapGet("/logins", Handle);

    private static async Task<IResult> Handle(
        CurrentUserAccessor accessor,
        AppDbContext db,
        CancellationToken ct)
    {
        var logins = await db.Logins
            .AsNoTracking()
            .Where(l => l.AccountId == accessor.UserId)
            .OrderBy(l => l.CreatedAt)
            .Select(l => new
            {
                id = l.Id,
                provider = l.Provider.ToString().ToLowerInvariant(),
                provider_subject = l.ProviderSubject,
                linked_at = l.LinkedAt,
            })
            .ToListAsync(ct);

        return Results.Ok(new { logins });
    }
}
```

- [ ] **Step 3: Implement LinkEmail**

Create `src/SsdidDrive.Api/Features/Account/LinkEmail.cs`:

```csharp
using Microsoft.EntityFrameworkCore;
using SsdidDrive.Api.Common;
using SsdidDrive.Api.Data;
using SsdidDrive.Api.Data.Entities;
using SsdidDrive.Api.Services;

namespace SsdidDrive.Api.Features.Account;

public static class LinkEmail
{
    public record Request(string Email);

    public static void Map(RouteGroupBuilder group) =>
        group.MapPost("/logins/email", Handle);

    private static async Task<IResult> Handle(
        Request req,
        CurrentUserAccessor accessor,
        AppDbContext db,
        OtpService otpService,
        IEmailService emailService,
        ILogger<LinkEmail> logger,
        CancellationToken ct)
    {
        if (string.IsNullOrWhiteSpace(req.Email))
            return AppError.BadRequest("Email is required").ToProblemResult();

        var email = req.Email.Trim().ToLowerInvariant();

        // Check if email is already linked to another account
        var existing = await db.Logins
            .AnyAsync(l => l.Provider == LoginProvider.Email
                && l.ProviderSubject == email
                && l.AccountId != accessor.UserId, ct);

        if (existing)
            return AppError.Conflict("This email is already linked to another account").ToProblemResult();

        // Check if already linked to this account
        var alreadyLinked = await db.Logins
            .AnyAsync(l => l.Provider == LoginProvider.Email
                && l.AccountId == accessor.UserId, ct);

        if (alreadyLinked)
            return AppError.Conflict("An email login is already linked to this account").ToProblemResult();

        var code = await otpService.GenerateAsync(email, "link", ct);

        try
        {
            await emailService.SendOtpAsync(email, code, ct);
        }
        catch (Exception ex)
        {
            logger.LogError(ex, "Failed to send link OTP to {Email}", email);
            return AppError.ServiceUnavailable("Failed to send verification email").ToProblemResult();
        }

        return Results.Ok(new { message = "Verification code sent" });
    }
}
```

- [ ] **Step 4: Implement LinkEmailVerify**

Create `src/SsdidDrive.Api/Features/Account/LinkEmailVerify.cs`:

```csharp
using Microsoft.EntityFrameworkCore;
using SsdidDrive.Api.Common;
using SsdidDrive.Api.Data;
using SsdidDrive.Api.Data.Entities;
using SsdidDrive.Api.Services;

namespace SsdidDrive.Api.Features.Account;

public static class LinkEmailVerify
{
    public record Request(string Email, string Code);

    public static void Map(RouteGroupBuilder group) =>
        group.MapPost("/logins/email/verify", Handle);

    private static async Task<IResult> Handle(
        Request req,
        CurrentUserAccessor accessor,
        AppDbContext db,
        OtpService otpService,
        AuditService auditService,
        CancellationToken ct)
    {
        if (string.IsNullOrWhiteSpace(req.Email) || string.IsNullOrWhiteSpace(req.Code))
            return AppError.BadRequest("Email and code are required").ToProblemResult();

        var email = req.Email.Trim().ToLowerInvariant();

        if (!await otpService.VerifyAsync(email, "link", req.Code, ct))
            return AppError.Unauthorized("Invalid or expired verification code").ToProblemResult();

        // Create the email login
        db.Logins.Add(new Login
        {
            AccountId = accessor.UserId,
            Provider = LoginProvider.Email,
            ProviderSubject = email,
        });

        // Update account email and verification
        var user = await db.Users.FirstOrDefaultAsync(u => u.Id == accessor.UserId, ct);
        if (user is not null)
        {
            user.Email = email;
            user.EmailVerified = true;
            user.UpdatedAt = DateTimeOffset.UtcNow;
        }

        await db.SaveChangesAsync(ct);

        await auditService.LogAsync(accessor.UserId, "auth.login.linked", "login", null,
            "Provider: email", ct);

        // After linking email, user needs to set up TOTP
        return Results.Ok(new
        {
            linked = true,
            requires_totp_setup = user is not null && !user.TotpEnabled,
        });
    }
}
```

- [ ] **Step 5: Implement LinkOidc**

Create `src/SsdidDrive.Api/Features/Account/LinkOidc.cs`:

```csharp
using Microsoft.EntityFrameworkCore;
using SsdidDrive.Api.Common;
using SsdidDrive.Api.Data;
using SsdidDrive.Api.Data.Entities;
using SsdidDrive.Api.Services;

namespace SsdidDrive.Api.Features.Account;

public static class LinkOidc
{
    public record Request(string Provider, string IdToken);

    public static void Map(RouteGroupBuilder group) =>
        group.MapPost("/logins/oidc", Handle);

    private static async Task<IResult> Handle(
        Request req,
        CurrentUserAccessor accessor,
        AppDbContext db,
        OidcTokenValidator validator,
        AuditService auditService,
        CancellationToken ct)
    {
        if (string.IsNullOrWhiteSpace(req.Provider) || string.IsNullOrWhiteSpace(req.IdToken))
            return AppError.BadRequest("Provider and id_token are required").ToProblemResult();

        var claims = await validator.ValidateAsync(req.Provider, req.IdToken, ct);
        if (!claims.IsSuccess)
            return claims.Error!.ToProblemResult();

        var oidcClaims = claims.Value!;
        var providerEnum = req.Provider.ToLowerInvariant() switch
        {
            "google" => LoginProvider.Google,
            "microsoft" => LoginProvider.Microsoft,
            _ => (LoginProvider?)null,
        };

        if (providerEnum is null)
            return AppError.BadRequest("Unsupported provider").ToProblemResult();

        // Check if already linked to another account
        var existing = await db.Logins
            .AnyAsync(l => l.Provider == providerEnum.Value
                && l.ProviderSubject == oidcClaims.Subject, ct);

        if (existing)
            return AppError.Conflict($"This {req.Provider} account is already linked to another account").ToProblemResult();

        db.Logins.Add(new Login
        {
            AccountId = accessor.UserId,
            Provider = providerEnum.Value,
            ProviderSubject = oidcClaims.Subject,
        });
        await db.SaveChangesAsync(ct);

        await auditService.LogAsync(accessor.UserId, "auth.login.linked", "login", null,
            $"Provider: {req.Provider}", ct);

        return Results.Ok(new { linked = true, provider = req.Provider });
    }
}
```

- [ ] **Step 6: Implement UnlinkLogin**

Create `src/SsdidDrive.Api/Features/Account/UnlinkLogin.cs`:

```csharp
using Microsoft.EntityFrameworkCore;
using SsdidDrive.Api.Common;
using SsdidDrive.Api.Data;
using SsdidDrive.Api.Services;

namespace SsdidDrive.Api.Features.Account;

public static class UnlinkLogin
{
    public static void Map(RouteGroupBuilder group) =>
        group.MapDelete("/logins/{id:guid}", Handle);

    private static async Task<IResult> Handle(
        Guid id,
        CurrentUserAccessor accessor,
        AppDbContext db,
        AuditService auditService,
        CancellationToken ct)
    {
        var login = await db.Logins
            .FirstOrDefaultAsync(l => l.Id == id && l.AccountId == accessor.UserId, ct);

        if (login is null)
            return AppError.NotFound("Login not found").ToProblemResult();

        // Must keep at least one login method
        var loginCount = await db.Logins
            .CountAsync(l => l.AccountId == accessor.UserId, ct);

        if (loginCount <= 1)
            return AppError.BadRequest("Cannot remove your only login method").ToProblemResult();

        var provider = login.Provider.ToString().ToLowerInvariant();
        db.Logins.Remove(login);
        await db.SaveChangesAsync(ct);

        await auditService.LogAsync(accessor.UserId, "auth.login.unlinked", "login", id,
            $"Provider: {provider}", ct);

        return Results.Ok(new { unlinked = true });
    }
}
```

- [ ] **Step 7: Register AccountFeature in Program.cs**

Add after `app.MapActivityFeature();`:

```csharp
app.MapAccountFeature();
```

Add the using:

```csharp
using SsdidDrive.Api.Features.Account;
```

- [ ] **Step 8: Build and verify**

```bash
dotnet build src/SsdidDrive.Api
```

- [ ] **Step 9: Commit**

```bash
git add src/SsdidDrive.Api/Features/Account/ \
  src/SsdidDrive.Api/Program.cs
git commit -m "feat: add account login linking endpoints"
```

---

### Task 10: TOTP Recovery Endpoints

POST /api/auth/totp/recovery and POST /api/auth/totp/recovery/verify

**Files:**
- Create: `src/SsdidDrive.Api/Features/Auth/TotpRecovery.cs`
- Create: `src/SsdidDrive.Api/Features/Auth/TotpRecoveryVerify.cs`
- Modify: `src/SsdidDrive.Api/Features/Auth/AuthFeature.cs`

- [ ] **Step 1: Implement TotpRecovery endpoint**

Create `src/SsdidDrive.Api/Features/Auth/TotpRecovery.cs`:

```csharp
using Microsoft.EntityFrameworkCore;
using SsdidDrive.Api.Common;
using SsdidDrive.Api.Data;
using SsdidDrive.Api.Data.Entities;
using SsdidDrive.Api.Services;

namespace SsdidDrive.Api.Features.Auth;

public static class TotpRecovery
{
    public record Request(string Email);

    public static void Map(RouteGroupBuilder group) =>
        group.MapPost("/totp/recovery", Handle)
            .WithMetadata(new SsdidPublicAttribute());

    private static async Task<IResult> Handle(
        Request req,
        AppDbContext db,
        OtpService otpService,
        IEmailService emailService,
        ILogger<TotpRecovery> logger,
        CancellationToken ct)
    {
        if (string.IsNullOrWhiteSpace(req.Email))
            return AppError.BadRequest("Email is required").ToProblemResult();

        var email = req.Email.Trim().ToLowerInvariant();

        var user = await db.Users
            .AsNoTracking()
            .FirstOrDefaultAsync(u => u.Email == email && u.Status == UserStatus.Active, ct);

        if (user is null)
            return AppError.NotFound("No account with this email").ToProblemResult();

        if (!user.TotpEnabled)
            return AppError.BadRequest("TOTP is not enabled for this account").ToProblemResult();

        var code = await otpService.GenerateAsync(email, "recovery", ct);

        try
        {
            await emailService.SendOtpAsync(email, code, ct);
        }
        catch (Exception ex)
        {
            logger.LogError(ex, "Failed to send recovery OTP to {Email}", email);
            return AppError.ServiceUnavailable("Failed to send verification email").ToProblemResult();
        }

        return Results.Ok(new { message = "Recovery code sent to your email" });
    }
}
```

- [ ] **Step 2: Implement TotpRecoveryVerify endpoint**

Create `src/SsdidDrive.Api/Features/Auth/TotpRecoveryVerify.cs`:

```csharp
using Microsoft.EntityFrameworkCore;
using SsdidDrive.Api.Common;
using SsdidDrive.Api.Data;
using SsdidDrive.Api.Data.Entities;
using SsdidDrive.Api.Services;

namespace SsdidDrive.Api.Features.Auth;

public static class TotpRecoveryVerify
{
    public record Request(string Email, string Code);

    public static void Map(RouteGroupBuilder group) =>
        group.MapPost("/totp/recovery/verify", Handle)
            .WithMetadata(new SsdidPublicAttribute());

    private static async Task<IResult> Handle(
        Request req,
        AppDbContext db,
        OtpService otpService,
        ISessionStore sessionStore,
        AuditService auditService,
        CancellationToken ct)
    {
        if (string.IsNullOrWhiteSpace(req.Email) || string.IsNullOrWhiteSpace(req.Code))
            return AppError.BadRequest("Email and code are required").ToProblemResult();

        var email = req.Email.Trim().ToLowerInvariant();

        if (!await otpService.VerifyAsync(email, "recovery", req.Code, ct))
            return AppError.Unauthorized("Invalid or expired recovery code").ToProblemResult();

        var user = await db.Users
            .FirstOrDefaultAsync(u => u.Email == email && u.Status == UserStatus.Active, ct);

        if (user is null)
            return AppError.NotFound("Account not found").ToProblemResult();

        // Disable old TOTP and invalidate backup codes
        user.TotpEnabled = false;
        user.TotpSecret = null;
        user.BackupCodes = null;
        user.UpdatedAt = DateTimeOffset.UtcNow;
        await db.SaveChangesAsync(ct);

        // Revoke all existing sessions for this account
        sessionStore.InvalidateSessionsForDid(user.Id.ToString());
        // Also invalidate DID-based sessions if they exist
        if (!string.IsNullOrEmpty(user.Did))
            sessionStore.InvalidateSessionsForDid(user.Did);

        await auditService.LogAsync(user.Id, "auth.totp.reset", "user", user.Id, null, ct);
        await auditService.LogAsync(user.Id, "auth.sessions.revoked", "user", user.Id,
            "TOTP recovery", ct);

        // Create new session so user can set up TOTP again
        var token = sessionStore.CreateSession(user.Id.ToString());
        if (token is null)
            return AppError.ServiceUnavailable("Session limit exceeded").ToProblemResult();

        return Results.Ok(new
        {
            token,
            account_id = user.Id,
            totp_disabled = true,
            requires_totp_setup = true,
        });
    }
}
```

- [ ] **Step 3: Map endpoints in AuthFeature.cs**

Add:

```csharp
TotpRecovery.Map(auth);
TotpRecoveryVerify.Map(auth);
```

- [ ] **Step 4: Build and verify**

```bash
dotnet build src/SsdidDrive.Api
```

- [ ] **Step 5: Commit**

```bash
git add src/SsdidDrive.Api/Features/Auth/TotpRecovery.cs \
  src/SsdidDrive.Api/Features/Auth/TotpRecoveryVerify.cs \
  src/SsdidDrive.Api/Features/Auth/AuthFeature.cs
git commit -m "feat: add TOTP recovery endpoints with session revocation"
```

---

## Chunk 4: Rate Limiting + Full Integration Tests

### Task 11: Rate Limiting for Auth Endpoints

**Files:**
- Modify: `src/SsdidDrive.Api/Program.cs`
- Modify: `src/SsdidDrive.Api/Features/Auth/AuthFeature.cs`

- [ ] **Step 1: Add rate limiting policies in Program.cs**

Add inside the `AddRateLimiter` block:

```csharp
// Email OTP send — 5 per email per hour
options.AddPolicy("auth-otp", httpContext =>
{
    if (isTesting)
        return RateLimitPartition.GetNoLimiter("no-limit");

    var email = "unknown";
    if (httpContext.Request.HasJsonContentType())
    {
        // Can't easily read body here; partition by IP instead
        email = httpContext.Connection.RemoteIpAddress?.ToString() ?? "unknown";
    }
    return RateLimitPartition.GetFixedWindowLimiter(email, _ => new FixedWindowRateLimiterOptions
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

// TOTP recovery — 3 per email/IP per hour
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
```

- [ ] **Step 2: Apply rate limiting to endpoints**

In the endpoint `Map` methods, add `.RequireRateLimiting("policy")`:

- `EmailRegister.cs`: `.RequireRateLimiting("auth-otp")`
- `EmailLogin.cs`: `.RequireRateLimiting("auth")`
- `TotpVerify.cs`: `.RequireRateLimiting("auth-totp")`
- `TotpRecovery.cs`: `.RequireRateLimiting("auth-recovery")`
- `TotpRecoveryVerify.cs`: `.RequireRateLimiting("auth-recovery")`
- `OidcVerify.cs`: `.RequireRateLimiting("auth")`

- [ ] **Step 3: Build and verify**

```bash
dotnet build src/SsdidDrive.Api
```

- [ ] **Step 4: Commit**

```bash
git add src/SsdidDrive.Api/Program.cs \
  src/SsdidDrive.Api/Features/Auth/
git commit -m "feat: add rate limiting for auth endpoints"
```

---

### Task 12: IEmailService.SendOtpAsync

Ensure the email service can send OTP codes. Add `SendOtpAsync` to the existing `IEmailService` interface.

**Files:**
- Modify: `src/SsdidDrive.Api/Services/IEmailService.cs` (or wherever IEmailService is defined)

- [ ] **Step 1: Find and read the IEmailService interface**

```bash
grep -rn "interface IEmailService" src/SsdidDrive.Api/
```

- [ ] **Step 2: Add SendOtpAsync method**

Add to `IEmailService`:

```csharp
Task SendOtpAsync(string toEmail, string code, CancellationToken ct = default);
```

Implement in `EmailService` (Resend-backed):

```csharp
public async Task SendOtpAsync(string toEmail, string code, CancellationToken ct = default)
{
    var message = new EmailMessage
    {
        From = _fromAddress,
        To = toEmail,
        Subject = "SSDID Drive - Verification Code",
        HtmlBody = $"<p>Your verification code is: <strong>{code}</strong></p><p>This code expires in 10 minutes.</p>",
    };
    await _resend.EmailSendAsync(message, ct);
}
```

Implement in `NullEmailService` (development fallback):

```csharp
public Task SendOtpAsync(string toEmail, string code, CancellationToken ct = default)
{
    _logger.LogInformation("OTP for {Email}: {Code}", toEmail, code);
    return Task.CompletedTask;
}
```

- [ ] **Step 3: Build and verify**

```bash
dotnet build src/SsdidDrive.Api
```

- [ ] **Step 4: Commit**

```bash
git add src/SsdidDrive.Api/Services/
git commit -m "feat: add SendOtpAsync to email service"
```

---

### Task 13: Full Integration Tests

End-to-end tests covering the complete registration and login flows.

**Files:**
- Modify: `tests/SsdidDrive.Api.Tests/Integration/EmailAuthFlowTests.cs`
- Create: `tests/SsdidDrive.Api.Tests/Integration/TotpRecoveryTests.cs`

- [ ] **Step 1: Add full registration + login flow test**

Add to `EmailAuthFlowTests.cs`. This test needs a helper to create an invitation first:

```csharp
[Fact]
public async Task FullFlow_Register_SetupTotp_Login()
{
    // 1. Create a tenant and invitation (setup)
    // Use direct DB seeding via factory or admin endpoints
    // This will depend on existing test infrastructure

    // 2. Register: POST /api/auth/email/register
    // 3. Verify OTP: POST /api/auth/email/register/verify
    //    (In tests, read OTP from NullEmailService logs or mock OtpService)
    // 4. Setup TOTP: POST /api/auth/totp/setup
    // 5. Confirm TOTP: POST /api/auth/totp/setup/confirm
    // 6. Logout
    // 7. Login: POST /api/auth/email/login
    // 8. Verify TOTP: POST /api/auth/totp/verify
    // 9. Assert: valid session token returned
}
```

**Note:** Full integration test implementation depends on test factory infrastructure (how to seed invitations, how to intercept OTP codes in tests). The implementer should:
1. Check `SsdidDriveFactory` for DB seeding patterns
2. Use `NullEmailService` in test environment (OTP codes logged)
3. Use a test-specific `IOtpStore` that allows retrieving the generated code
4. Generate valid TOTP codes using OtpNet directly with the secret returned from `/totp/setup`

- [ ] **Step 2: Run all tests**

```bash
dotnet test tests/SsdidDrive.Api.Tests -v n
```

Expected: All tests PASS (existing + new).

- [ ] **Step 3: Commit**

```bash
git add tests/SsdidDrive.Api.Tests/
git commit -m "test: add auth flow integration tests"
```

---

---

## Chunk 5: Review Fixes — Encryption, Migrations, Tests, Session Store

### Task 14: TOTP Encryption at Rest

The spec requires TotpSecret and BackupCodes to be encrypted at rest. Use AES-256-GCM with a server-held key from configuration.

**Files:**
- Create: `src/SsdidDrive.Api/Services/TotpEncryption.cs`
- Modify: `src/SsdidDrive.Api/Program.cs`

- [ ] **Step 1: Implement TotpEncryption service**

Create `src/SsdidDrive.Api/Services/TotpEncryption.cs`:

```csharp
using System.Security.Cryptography;

namespace SsdidDrive.Api.Services;

public class TotpEncryption
{
    private readonly byte[] _key;

    public TotpEncryption(IConfiguration config)
    {
        var keyBase64 = config["Auth:TotpEncryptionKey"];
        if (string.IsNullOrEmpty(keyBase64))
        {
            // Generate a key for development — log warning
            _key = RandomNumberGenerator.GetBytes(32);
        }
        else
        {
            _key = Convert.FromBase64String(keyBase64);
        }

        if (_key.Length != 32)
            throw new ArgumentException("Auth:TotpEncryptionKey must be 32 bytes (base64-encoded)");
    }

    public string Encrypt(string plaintext)
    {
        var nonce = RandomNumberGenerator.GetBytes(12);
        var plaintextBytes = System.Text.Encoding.UTF8.GetBytes(plaintext);
        var ciphertext = new byte[plaintextBytes.Length];
        var tag = new byte[16];

        using var aes = new AesGcm(_key, 16);
        aes.Encrypt(nonce, plaintextBytes, ciphertext, tag);

        // Format: base64(nonce + ciphertext + tag)
        var combined = new byte[nonce.Length + ciphertext.Length + tag.Length];
        Buffer.BlockCopy(nonce, 0, combined, 0, nonce.Length);
        Buffer.BlockCopy(ciphertext, 0, combined, nonce.Length, ciphertext.Length);
        Buffer.BlockCopy(tag, 0, combined, nonce.Length + ciphertext.Length, tag.Length);

        return Convert.ToBase64String(combined);
    }

    public string Decrypt(string encrypted)
    {
        var combined = Convert.FromBase64String(encrypted);

        var nonce = combined[..12];
        var tag = combined[^16..];
        var ciphertext = combined[12..^16];
        var plaintext = new byte[ciphertext.Length];

        using var aes = new AesGcm(_key, 16);
        aes.Decrypt(nonce, ciphertext, tag, plaintext);

        return System.Text.Encoding.UTF8.GetString(plaintext);
    }
}
```

- [ ] **Step 2: Register in Program.cs**

```csharp
builder.Services.AddSingleton<TotpEncryption>();
```

- [ ] **Step 3: Add config key to appsettings.Development.json**

```json
{
  "Auth": {
    "TotpEncryptionKey": ""
  }
}
```

Empty string = auto-generated dev key (logged as warning).

- [ ] **Step 4: Update all endpoints that read/write TotpSecret and BackupCodes**

In `TotpSetup.cs` — encrypt before saving:

```csharp
user.TotpSecret = totpEncryption.Encrypt(secret);
```

Return the plaintext `secret` to the client (not the encrypted version).

In `TotpSetupConfirm.cs` — decrypt before verifying:

```csharp
var decryptedSecret = totpEncryption.Decrypt(user.TotpSecret);
if (!totpService.VerifyCode(decryptedSecret, req.Code))
    return AppError.Unauthorized("Invalid TOTP code").ToProblemResult();
// Encrypt backup codes before saving
user.BackupCodes = totpEncryption.Encrypt(JsonSerializer.Serialize(backupCodes));
```

In `TotpVerify.cs` — decrypt secret and backup codes:

```csharp
var decryptedSecret = totpEncryption.Decrypt(user.TotpSecret);
bool valid = totpService.VerifyCode(decryptedSecret, req.Code);

if (!valid && !string.IsNullOrEmpty(user.BackupCodes))
{
    var decryptedCodes = totpEncryption.Decrypt(user.BackupCodes);
    var (backupValid, remaining) = totpService.VerifyBackupCode(decryptedCodes, req.Code);
    if (backupValid)
    {
        valid = true;
        user.BackupCodes = totpEncryption.Encrypt(remaining!);
    }
}
```

Apply same pattern to `TotpRecoveryVerify.cs` and `LinkEmailVerify.cs`.

- [ ] **Step 5: Add TotpEncryption as dependency to all affected endpoints**

Add `TotpEncryption totpEncryption` parameter to Handle methods of: `TotpSetup`, `TotpSetupConfirm`, `TotpVerify`, `TotpRecoveryVerify`.

- [ ] **Step 6: Commit**

```bash
git add src/SsdidDrive.Api/Services/TotpEncryption.cs \
  src/SsdidDrive.Api/Program.cs \
  src/SsdidDrive.Api/Features/Auth/
git commit -m "security: encrypt TOTP secrets and backup codes at rest with AES-256-GCM"
```

---

### Task 15: Database Migration — Make Email Required + DID Nullable

Covers spec DB migration phases 3-5. Phase 6-7 (Account rename, Device FK rename) are in Plan 7.

**Files:**
- Modify: `src/SsdidDrive.Api/Data/AppDbContext.cs`
- Modify: `src/SsdidDrive.Api/Data/Entities/Invitation.cs`

- [ ] **Step 1: Configure Email as required + unique in AppDbContext**

In the User entity configuration:

```csharp
e.HasIndex(x => x.Email).IsUnique().HasFilter("\"Email\" IS NOT NULL");
```

Note: Cannot make Email `NOT NULL` yet — existing users may have null emails. The unique filtered index allows the new auth to work while preserving backward compatibility. Making it truly required happens in Plan 7 after data migration.

- [ ] **Step 2: Make DID nullable in User entity**

Modify `src/SsdidDrive.Api/Data/Entities/User.cs`:

```csharp
public string? Did { get; set; }  // Was: string Did = default!;
```

- [ ] **Step 3: Add AcceptedByAccountId to Invitation**

Modify `src/SsdidDrive.Api/Data/Entities/Invitation.cs` — add alongside `AcceptedByDid`:

```csharp
public Guid? AcceptedByAccountId { get; set; }
```

- [ ] **Step 4: Update middleware to handle null DID**

In `SsdidAuthMiddleware.cs`, the `accessor.Did` assignment needs null handling:

```csharp
accessor.Did = user.Did ?? "";
```

- [ ] **Step 5: Create EF migration**

```bash
dotnet ef migrations add MakeDidNullableAddEmailIndex --project src/SsdidDrive.Api
```

- [ ] **Step 6: Commit**

```bash
git add src/SsdidDrive.Api/Data/ \
  src/SsdidDrive.Api/Middleware/
git commit -m "feat: make DID nullable, add unique email index, add AcceptedByAccountId"
```

---

### Task 16: Session Store Compatibility for UUID-Based Sessions

Verify and fix `InvalidateSessionsForDid` to work with Account.Id-based sessions.

**Files:**
- Modify: `src/SsdidDrive.Api/Ssdid/SessionStore.cs`
- Modify: `src/SsdidDrive.Api/Ssdid/RedisSessionStore.cs`

- [ ] **Step 1: Review SessionStore.InvalidateSessionsForDid**

Read the method. It scans all sessions and removes those matching the given value. Since it does a value-match (not key-match), it already works for UUID strings — the method name is misleading but the implementation is generic. Verify by reading the code.

If the implementation filters by `entry.Value == did` or similar string match, it will work for UUID strings too. Document this.

- [ ] **Step 2: Review RedisSessionStore.InvalidateSessionsForDid**

Read the method. It likely uses `SCAN` to find session keys and checks values. Same logic — value matching works for UUIDs.

If the method uses a DID-specific key prefix or index, it needs updating. Otherwise, just add a comment documenting the dual use.

- [ ] **Step 3: Add alias method for clarity (optional)**

If desired, add `InvalidateSessionsForAccount(Guid accountId)` that calls `InvalidateSessionsForDid(accountId.ToString())`. This makes calling code clearer without changing internals.

- [ ] **Step 4: Commit**

```bash
git add src/SsdidDrive.Api/Ssdid/
git commit -m "fix: verify session store works with UUID-based sessions"
```

---

### Task 17: OidcTokenValidator — Cache OIDC Discovery Documents

Fix: current implementation creates a new ConfigurationManager per request.

**Files:**
- Modify: `src/SsdidDrive.Api/Services/OidcTokenValidator.cs`

- [ ] **Step 1: Cache ConfigurationManagers per provider**

Replace the per-request instantiation with cached instances:

```csharp
public class OidcTokenValidator
{
    private readonly Dictionary<string, ProviderConfig> _providers;
    private readonly ConcurrentDictionary<string, ConfigurationManager<OpenIdConnectConfiguration>> _configManagers = new();
    private readonly ILogger<OidcTokenValidator> _logger;

    // ... constructor same as before ...

    public async Task<Result<OidcClaims>> ValidateAsync(string provider, string idToken, CancellationToken ct = default)
    {
        if (!_providers.TryGetValue(provider, out var config))
            return AppError.BadRequest($"Unsupported OIDC provider: {provider}");

        if (string.IsNullOrEmpty(config.ClientId))
            return AppError.ServiceUnavailable($"OIDC provider '{provider}' is not configured");

        try
        {
            var configManager = _configManagers.GetOrAdd(provider, _ =>
                new ConfigurationManager<OpenIdConnectConfiguration>(
                    config.MetadataUrl,
                    new OpenIdConnectConfigurationRetriever(),
                    new HttpDocumentRetriever()));

            var oidcConfig = await configManager.GetConfigurationAsync(ct);
            // ... rest of validation same as before ...
        }
    }
}
```

- [ ] **Step 2: Commit**

```bash
git add src/SsdidDrive.Api/Services/OidcTokenValidator.cs
git commit -m "perf: cache OIDC discovery documents per provider"
```

---

### Task 18: Add OIDC NuGet Packages + Configuration

**Files:**
- Modify: `src/SsdidDrive.Api/SsdidDrive.Api.csproj`
- Modify: `src/SsdidDrive.Api/appsettings.json`
- Modify: `src/SsdidDrive.Api/appsettings.Development.json`

- [ ] **Step 1: Add NuGet packages**

```bash
dotnet add src/SsdidDrive.Api/SsdidDrive.Api.csproj package Microsoft.IdentityModel.Protocols.OpenIdConnect
dotnet add src/SsdidDrive.Api/SsdidDrive.Api.csproj package System.IdentityModel.Tokens.Jwt
```

- [ ] **Step 2: Add OIDC configuration to appsettings.json**

```json
{
  "Oidc": {
    "Google": {
      "ClientId": ""
    },
    "Microsoft": {
      "ClientId": ""
    }
  },
  "Auth": {
    "TotpEncryptionKey": ""
  }
}
```

- [ ] **Step 3: Commit**

```bash
git add src/SsdidDrive.Api/SsdidDrive.Api.csproj \
  src/SsdidDrive.Api/appsettings*.json
git commit -m "chore: add OIDC packages and auth configuration"
```

---

### Task 19: Missing Tests — TOTP Setup, Login, OIDC

Fix TDD gaps in Tasks 6, 7, 8.

**Files:**
- Modify: `tests/SsdidDrive.Api.Tests/Integration/EmailAuthFlowTests.cs`

- [ ] **Step 1: Add TOTP setup integration tests**

Add to `EmailAuthFlowTests.cs`:

```csharp
[Fact]
public async Task TotpSetup_WithoutAuth_Returns401()
{
    var resp = await _client.PostAsync("/api/auth/totp/setup", null);
    Assert.Equal(HttpStatusCode.Unauthorized, resp.StatusCode);
}

[Fact]
public async Task TotpSetupConfirm_WithoutAuth_Returns401()
{
    var resp = await _client.PostAsJsonAsync("/api/auth/totp/setup/confirm",
        new { code = "123456" }, SnakeJson);
    Assert.Equal(HttpStatusCode.Unauthorized, resp.StatusCode);
}

[Fact]
public async Task TotpSetupConfirm_WithWrongCode_Returns401()
{
    // Setup: create authenticated session, call /totp/setup, then confirm with wrong code
    // This test requires a seeded user with a valid session token
    // Implementation depends on test factory — seed user + create session in test setup
}
```

- [ ] **Step 2: Add email login + TOTP verify tests**

```csharp
[Fact]
public async Task EmailLogin_UnknownEmail_Returns404()
{
    var resp = await _client.PostAsJsonAsync("/api/auth/email/login",
        new { email = "nonexistent@example.com" }, SnakeJson);
    Assert.Equal(HttpStatusCode.NotFound, resp.StatusCode);
}

[Fact]
public async Task TotpVerify_WrongCode_Returns401()
{
    var resp = await _client.PostAsJsonAsync("/api/auth/totp/verify",
        new { email = "test@example.com", code = "000000" }, SnakeJson);
    // Either 401 (wrong code) or 404 (no account) — both are valid for unknown email
    Assert.True(resp.StatusCode == HttpStatusCode.Unauthorized
        || resp.StatusCode == HttpStatusCode.NotFound);
}
```

- [ ] **Step 3: Add OIDC verify tests**

```csharp
[Fact]
public async Task OidcVerify_MissingProvider_Returns400()
{
    var resp = await _client.PostAsJsonAsync("/api/auth/oidc/verify",
        new { provider = "", id_token = "fake" }, SnakeJson);
    Assert.Equal(HttpStatusCode.BadRequest, resp.StatusCode);
}

[Fact]
public async Task OidcVerify_InvalidToken_Returns401()
{
    var resp = await _client.PostAsJsonAsync("/api/auth/oidc/verify",
        new { provider = "google", id_token = "not.a.valid.jwt" }, SnakeJson);
    // Either 401 (invalid token) or 503 (provider not configured)
    Assert.True(resp.StatusCode == HttpStatusCode.Unauthorized
        || resp.StatusCode == HttpStatusCode.ServiceUnavailable);
}

[Fact]
public async Task OidcVerify_NoAccount_NoInvitation_Returns404()
{
    // With a valid-looking but unlinked token, should get 404
    // Full test requires mocking OidcTokenValidator — implementation detail
}
```

- [ ] **Step 4: Run all tests**

```bash
dotnet test tests/SsdidDrive.Api.Tests -v n
```

- [ ] **Step 5: Commit**

```bash
git add tests/SsdidDrive.Api.Tests/
git commit -m "test: add missing integration tests for TOTP, login, and OIDC endpoints"
```

---

### Task 20: Fix OidcVerify MFA Gate — Enforce TOTP for All Admins

The current implementation only gates admins who already have TOTP enabled. Admins without TOTP should be prompted to set it up.

**Files:**
- Modify: `src/SsdidDrive.Api/Features/Auth/OidcVerify.cs`

- [ ] **Step 1: Update MFA gate logic**

In `OidcVerify.cs`, replace the MFA check section:

```csharp
// Check if user is admin/owner in any tenant
var isAdmin = await db.UserTenants
    .AnyAsync(ut => ut.UserId == user.Id
        && (ut.Role == TenantRole.Owner || ut.Role == TenantRole.Admin), ct);

string sessionValue;
bool mfaRequired = false;
bool totpSetupRequired = false;

if (isAdmin)
{
    if (user.TotpEnabled)
    {
        // Admin with TOTP — require MFA verification
        sessionValue = $"mfa:{user.Id}";
        mfaRequired = true;
    }
    else
    {
        // Admin without TOTP — require TOTP setup
        sessionValue = user.Id.ToString(); // Full session so they can call /totp/setup
        totpSetupRequired = true;
    }
}
else
{
    sessionValue = user.Id.ToString();
}

var token = sessionStore.CreateSession(sessionValue);

return Results.Ok(new
{
    token,
    account_id = user.Id,
    email = user.Email,
    display_name = user.DisplayName,
    mfa_required = mfaRequired,
    totp_setup_required = totpSetupRequired,
});
```

- [ ] **Step 2: Commit**

```bash
git add src/SsdidDrive.Api/Features/Auth/OidcVerify.cs
git commit -m "fix: enforce TOTP setup for admin OIDC users without TOTP"
```

---

### Task 21: Reorder — IEmailService.SendOtpAsync (Move Before Task 5)

Task 12 (IEmailService.SendOtpAsync) is a dependency of Tasks 5, 9, and 10. The implementer MUST complete Task 12 before starting Task 5. The dependency table below reflects this.

---

## Summary

| Task | Description | Dependencies |
|------|-------------|-------------|
| 1 | Login entity + User TOTP columns + migration | None |
| 2 | OTP service (generate, store, verify) | None |
| 3 | TOTP service (OtpNet, backup codes) | NuGet: OtpNet |
| 4 | Session dual-mode middleware (UUID + DID) | None |
| 12 | IEmailService.SendOtpAsync | None |
| 14 | TOTP encryption at rest (AES-256-GCM) | None |
| 15 | DB migration: DID nullable + email index + AcceptedByAccountId | Task 1 |
| 16 | Session store UUID compatibility verification | Task 4 |
| 17 | OidcTokenValidator — cache discovery documents | None |
| 18 | OIDC NuGet packages + configuration | None |
| 5 | Email registration endpoints | Tasks 1, 2, 12 |
| 6 | TOTP setup + confirm endpoints | Tasks 1, 3, 14 |
| 7 | Email login + TOTP verify endpoints | Tasks 1, 3, 4, 14 |
| 8 | OIDC token validator + verify endpoint | Tasks 1, 4, 17, 18 |
| 20 | Fix OIDC MFA gate for admins | Task 8 |
| 9 | Account link logins endpoints | Tasks 1, 2, 3, 8, 14 |
| 10 | TOTP recovery endpoints | Tasks 1, 2, 3, 4, 14 |
| 11 | Rate limiting for auth endpoints | Tasks 5-10 |
| 19 | Missing integration tests | Tasks 5-10 |
| 13 | Full end-to-end integration tests | All above |

**Parallel-safe batches:**
- **Batch 1** (all independent): Tasks 1, 2, 3, 4, 12, 14, 17, 18
- **Batch 2** (depend on Batch 1): Tasks 5, 6, 7, 8, 15, 16
- **Batch 3** (depend on Batch 2): Tasks 9, 10, 20
- **Batch 4** (depend on all): Tasks 11, 19, 13
