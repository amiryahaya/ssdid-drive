using SsdidDrive.Api.Crypto.Providers;

namespace SsdidDrive.Api.Tests;

/// <summary>
/// Skip helpers for platform-dependent crypto tests.
/// ML-DSA and SLH-DSA now use BouncyCastle (cross-platform, always available).
/// KAZ-Sign depends on a native library that may not be available.
/// </summary>
public static class PlatformFacts
{
    private static readonly Lazy<bool> KazSignSupported = new(() =>
    {
        try
        {
            using var provider = new KazSignProvider();
            var (pub, priv) = provider.GenerateKeyPair(null);
            // Also verify signing works (not just keygen)
            var sig = provider.Sign("test"u8.ToArray(), priv, null);
            return provider.Verify("test"u8.ToArray(), sig, pub, null);
        }
        catch
        {
            return false;
        }
    });

    public static void SkipIfMlDsaUnsupported()
    {
        // BouncyCastle ML-DSA is always available — no skip needed
    }

    public static void SkipIfSlhDsaUnsupported()
    {
        // BouncyCastle SLH-DSA is always available — no skip needed
    }

    public static void SkipIfKazSignUnsupported()
    {
        if (!KazSignSupported.Value)
            Assert.Skip("libkazsign native library not available or not functional");
    }
}
