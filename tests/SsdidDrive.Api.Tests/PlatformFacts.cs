using System.Security.Cryptography;
using SsdidDrive.Api.Crypto.Providers;

namespace SsdidDrive.Api.Tests;

/// <summary>
/// Skip helpers for platform-dependent crypto tests.
/// Tests call SkipIfUnsupported() at the start — throws Xunit.SkipException
/// on unsupported platforms so xUnit marks them as skipped (not failed).
/// </summary>
public static class PlatformFacts
{
    private static readonly Lazy<bool> MlDsaSupported = new(() =>
    {
        try
        {
            using var _ = MLDsa.GenerateKey(MLDsaAlgorithm.MLDsa44);
            return true;
        }
        catch (PlatformNotSupportedException)
        {
            return false;
        }
    });

    private static readonly Lazy<bool> SlhDsaSupported = new(() =>
    {
        try
        {
            using var _ = SlhDsa.GenerateKey(SlhDsaAlgorithm.SlhDsaSha2_128f);
            return true;
        }
        catch (PlatformNotSupportedException)
        {
            return false;
        }
    });

    private static readonly Lazy<bool> KazSignSupported = new(() =>
    {
        try
        {
            using var provider = new KazSignProvider();
            provider.GenerateKeyPair(null);
            return true;
        }
        catch (DllNotFoundException)
        {
            return false;
        }
    });

    public static void SkipIfMlDsaUnsupported()
    {
        if (!MlDsaSupported.Value)
            Assert.Skip("ML-DSA not supported on this platform");
    }

    public static void SkipIfSlhDsaUnsupported()
    {
        if (!SlhDsaSupported.Value)
            Assert.Skip("SLH-DSA not supported on this platform");
    }

    public static void SkipIfKazSignUnsupported()
    {
        if (!KazSignSupported.Value)
            Assert.Skip("libkazsign native library not available");
    }
}
