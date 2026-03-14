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
