using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.Logging.Abstractions;
using SsdidDrive.Api.Services;

namespace SsdidDrive.Api.Tests.Unit;

public class TotpEncryptionTests
{
    private TotpEncryption CreateSut(string? key = null)
    {
        var config = new ConfigurationBuilder()
            .AddInMemoryCollection(new Dictionary<string, string?>
            {
                ["Auth:TotpEncryptionKey"] = key ?? Convert.ToBase64String(new byte[32])
            })
            .Build();
        return new TotpEncryption(config, NullLogger<TotpEncryption>.Instance);
    }

    [Fact]
    public void RoundTrip_PreservesPlaintext()
    {
        var sut = CreateSut();
        var plaintext = "JBSWY3DPEHPK3PXP";

        var encrypted = sut.Encrypt(plaintext);
        var decrypted = sut.Decrypt(encrypted);

        Assert.Equal(plaintext, decrypted);
    }

    [Fact]
    public void Encrypt_ProducesDifferentOutputEachTime()
    {
        var sut = CreateSut();
        var plaintext = "JBSWY3DPEHPK3PXP";

        var enc1 = sut.Encrypt(plaintext);
        var enc2 = sut.Encrypt(plaintext);

        Assert.NotEqual(enc1, enc2); // Different nonces
    }

    [Fact]
    public void Decrypt_WithWrongKey_Throws()
    {
        var sut1 = CreateSut(Convert.ToBase64String(new byte[32]));
        var sut2 = CreateSut(Convert.ToBase64String(System.Security.Cryptography.RandomNumberGenerator.GetBytes(32)));

        var encrypted = sut1.Encrypt("secret");

        Assert.ThrowsAny<Exception>(() => sut2.Decrypt(encrypted));
    }

    [Fact]
    public void Constructor_WithEmptyKey_GeneratesDevKey()
    {
        var config = new ConfigurationBuilder()
            .AddInMemoryCollection(new Dictionary<string, string?>
            {
                ["Auth:TotpEncryptionKey"] = ""
            })
            .Build();

        var sut = new TotpEncryption(config, NullLogger<TotpEncryption>.Instance);
        var plaintext = "test-secret";

        // Should work with auto-generated key
        var encrypted = sut.Encrypt(plaintext);
        var decrypted = sut.Decrypt(encrypted);
        Assert.Equal(plaintext, decrypted);
    }
}
