using SsdidDrive.Api.Crypto;

namespace SsdidDrive.Api.Tests.Crypto;

public class AlgorithmRegistryTests
{
    #region Resolve

    [Theory]
    [InlineData("Ed25519VerificationKey2020", "Ed25519", null)]
    [InlineData("EcdsaSecp256r1VerificationKey2019", "Ecdsa", "P256")]
    [InlineData("EcdsaSecp384VerificationKey2019", "Ecdsa", "P384")]
    [InlineData("MlDsa44VerificationKey2024", "MlDsa", "MlDsa44")]
    [InlineData("MlDsa65VerificationKey2024", "MlDsa", "MlDsa65")]
    [InlineData("MlDsa87VerificationKey2024", "MlDsa", "MlDsa87")]
    [InlineData("SlhDsaSha2128sVerificationKey2024", "SlhDsa", "Sha2_128s")]
    [InlineData("SlhDsaSha2128fVerificationKey2024", "SlhDsa", "Sha2_128f")]
    [InlineData("SlhDsaSha2192sVerificationKey2024", "SlhDsa", "Sha2_192s")]
    [InlineData("SlhDsaSha2192fVerificationKey2024", "SlhDsa", "Sha2_192f")]
    [InlineData("SlhDsaSha2256sVerificationKey2024", "SlhDsa", "Sha2_256s")]
    [InlineData("SlhDsaSha2256fVerificationKey2024", "SlhDsa", "Sha2_256f")]
    [InlineData("SlhDsaShake128sVerificationKey2024", "SlhDsa", "Shake_128s")]
    [InlineData("SlhDsaShake128fVerificationKey2024", "SlhDsa", "Shake_128f")]
    [InlineData("SlhDsaShake192sVerificationKey2024", "SlhDsa", "Shake_192s")]
    [InlineData("SlhDsaShake192fVerificationKey2024", "SlhDsa", "Shake_192f")]
    [InlineData("SlhDsaShake256sVerificationKey2024", "SlhDsa", "Shake_256s")]
    [InlineData("SlhDsaShake256fVerificationKey2024", "SlhDsa", "Shake_256f")]
    [InlineData("KazSignVerificationKey2024", "KazSign", null)]
    public void Resolve_KnownVmType_ReturnsCorrectAlgorithmId(
        string vmType, string expectedFamily, string? expectedVariant)
    {
        var result = AlgorithmRegistry.Resolve(vmType);

        Assert.NotNull(result);
        Assert.Equal(expectedFamily, result.Family);
        Assert.Equal(expectedVariant, result.Variant);
    }

    [Theory]
    [InlineData("UnknownVerificationKey2024")]
    [InlineData("")]
    [InlineData("Ed25519VerificationKey2018")]
    [InlineData("RsaVerificationKey2018")]
    public void Resolve_UnknownVmType_ReturnsNull(string vmType)
    {
        var result = AlgorithmRegistry.Resolve(vmType);

        Assert.Null(result);
    }

    #endregion

    #region GetProofType

    [Theory]
    [InlineData("Ed25519VerificationKey2020", "Ed25519Signature2020")]
    [InlineData("EcdsaSecp256r1VerificationKey2019", "EcdsaSecp256r1Signature2019")]
    [InlineData("EcdsaSecp384VerificationKey2019", "EcdsaSecp384Signature2019")]
    [InlineData("MlDsa44VerificationKey2024", "MlDsa44Signature2024")]
    [InlineData("MlDsa65VerificationKey2024", "MlDsa65Signature2024")]
    [InlineData("MlDsa87VerificationKey2024", "MlDsa87Signature2024")]
    [InlineData("SlhDsaSha2128sVerificationKey2024", "SlhDsaSha2128sSignature2024")]
    [InlineData("SlhDsaSha2128fVerificationKey2024", "SlhDsaSha2128fSignature2024")]
    [InlineData("SlhDsaSha2192sVerificationKey2024", "SlhDsaSha2192sSignature2024")]
    [InlineData("SlhDsaSha2192fVerificationKey2024", "SlhDsaSha2192fSignature2024")]
    [InlineData("SlhDsaSha2256sVerificationKey2024", "SlhDsaSha2256sSignature2024")]
    [InlineData("SlhDsaSha2256fVerificationKey2024", "SlhDsaSha2256fSignature2024")]
    [InlineData("SlhDsaShake128sVerificationKey2024", "SlhDsaShake128sSignature2024")]
    [InlineData("SlhDsaShake128fVerificationKey2024", "SlhDsaShake128fSignature2024")]
    [InlineData("SlhDsaShake192sVerificationKey2024", "SlhDsaShake192sSignature2024")]
    [InlineData("SlhDsaShake192fVerificationKey2024", "SlhDsaShake192fSignature2024")]
    [InlineData("SlhDsaShake256sVerificationKey2024", "SlhDsaShake256sSignature2024")]
    [InlineData("SlhDsaShake256fVerificationKey2024", "SlhDsaShake256fSignature2024")]
    [InlineData("KazSignVerificationKey2024", "KazSignSignature2024")]
    public void GetProofType_KnownVmType_ReturnsCorrectProofType(
        string vmType, string expectedProofType)
    {
        var result = AlgorithmRegistry.GetProofType(vmType);

        Assert.Equal(expectedProofType, result);
    }

    [Theory]
    [InlineData("UnknownVerificationKey2024")]
    [InlineData("")]
    [InlineData("Ed25519VerificationKey2018")]
    [InlineData("RsaVerificationKey2018")]
    public void GetProofType_UnknownVmType_ReturnsNull(string vmType)
    {
        var result = AlgorithmRegistry.GetProofType(vmType);

        Assert.Null(result);
    }

    #endregion

    #region GetVmTypeFromProofType

    [Theory]
    [InlineData("Ed25519Signature2020", "Ed25519VerificationKey2020")]
    [InlineData("EcdsaSecp256r1Signature2019", "EcdsaSecp256r1VerificationKey2019")]
    [InlineData("EcdsaSecp384Signature2019", "EcdsaSecp384VerificationKey2019")]
    [InlineData("MlDsa44Signature2024", "MlDsa44VerificationKey2024")]
    [InlineData("MlDsa65Signature2024", "MlDsa65VerificationKey2024")]
    [InlineData("MlDsa87Signature2024", "MlDsa87VerificationKey2024")]
    [InlineData("SlhDsaSha2128sSignature2024", "SlhDsaSha2128sVerificationKey2024")]
    [InlineData("SlhDsaSha2128fSignature2024", "SlhDsaSha2128fVerificationKey2024")]
    [InlineData("SlhDsaSha2192sSignature2024", "SlhDsaSha2192sVerificationKey2024")]
    [InlineData("SlhDsaSha2192fSignature2024", "SlhDsaSha2192fVerificationKey2024")]
    [InlineData("SlhDsaSha2256sSignature2024", "SlhDsaSha2256sVerificationKey2024")]
    [InlineData("SlhDsaSha2256fSignature2024", "SlhDsaSha2256fVerificationKey2024")]
    [InlineData("SlhDsaShake128sSignature2024", "SlhDsaShake128sVerificationKey2024")]
    [InlineData("SlhDsaShake128fSignature2024", "SlhDsaShake128fVerificationKey2024")]
    [InlineData("SlhDsaShake192sSignature2024", "SlhDsaShake192sVerificationKey2024")]
    [InlineData("SlhDsaShake192fSignature2024", "SlhDsaShake192fVerificationKey2024")]
    [InlineData("SlhDsaShake256sSignature2024", "SlhDsaShake256sVerificationKey2024")]
    [InlineData("SlhDsaShake256fSignature2024", "SlhDsaShake256fVerificationKey2024")]
    [InlineData("KazSignSignature2024", "KazSignVerificationKey2024")]
    public void GetVmTypeFromProofType_KnownProofType_ReturnsCorrectVmType(
        string proofType, string expectedVmType)
    {
        var result = AlgorithmRegistry.GetVmTypeFromProofType(proofType);

        Assert.Equal(expectedVmType, result);
    }

    [Theory]
    [InlineData("UnknownSignature2024")]
    [InlineData("")]
    [InlineData("Ed25519Signature2018")]
    [InlineData("RsaSignature2018")]
    public void GetVmTypeFromProofType_UnknownProofType_ReturnsNull(string proofType)
    {
        var result = AlgorithmRegistry.GetVmTypeFromProofType(proofType);

        Assert.Null(result);
    }

    #endregion

    #region IsSupported

    [Theory]
    [InlineData("Ed25519VerificationKey2020")]
    [InlineData("EcdsaSecp256r1VerificationKey2019")]
    [InlineData("EcdsaSecp384VerificationKey2019")]
    [InlineData("MlDsa44VerificationKey2024")]
    [InlineData("MlDsa65VerificationKey2024")]
    [InlineData("MlDsa87VerificationKey2024")]
    [InlineData("SlhDsaSha2128sVerificationKey2024")]
    [InlineData("SlhDsaSha2128fVerificationKey2024")]
    [InlineData("SlhDsaSha2192sVerificationKey2024")]
    [InlineData("SlhDsaSha2192fVerificationKey2024")]
    [InlineData("SlhDsaSha2256sVerificationKey2024")]
    [InlineData("SlhDsaSha2256fVerificationKey2024")]
    [InlineData("SlhDsaShake128sVerificationKey2024")]
    [InlineData("SlhDsaShake128fVerificationKey2024")]
    [InlineData("SlhDsaShake192sVerificationKey2024")]
    [InlineData("SlhDsaShake192fVerificationKey2024")]
    [InlineData("SlhDsaShake256sVerificationKey2024")]
    [InlineData("SlhDsaShake256fVerificationKey2024")]
    [InlineData("KazSignVerificationKey2024")]
    public void IsSupported_KnownVmType_ReturnsTrue(string vmType)
    {
        Assert.True(AlgorithmRegistry.IsSupported(vmType));
    }

    [Theory]
    [InlineData("UnknownVerificationKey2024")]
    [InlineData("")]
    [InlineData("Ed25519VerificationKey2018")]
    [InlineData("RsaVerificationKey2018")]
    public void IsSupported_UnknownVmType_ReturnsFalse(string vmType)
    {
        Assert.False(AlgorithmRegistry.IsSupported(vmType));
    }

    #endregion

    #region Consistency checks

    [Fact]
    public void Resolve_And_GetProofType_CoverSameSetOfVmTypes()
    {
        // Every vmType that Resolve knows about should also have a proof type
        var allVmTypes = new[]
        {
            "Ed25519VerificationKey2020",
            "EcdsaSecp256r1VerificationKey2019",
            "EcdsaSecp384VerificationKey2019",
            "MlDsa44VerificationKey2024",
            "MlDsa65VerificationKey2024",
            "MlDsa87VerificationKey2024",
            "SlhDsaSha2128sVerificationKey2024",
            "SlhDsaSha2128fVerificationKey2024",
            "SlhDsaSha2192sVerificationKey2024",
            "SlhDsaSha2192fVerificationKey2024",
            "SlhDsaSha2256sVerificationKey2024",
            "SlhDsaSha2256fVerificationKey2024",
            "SlhDsaShake128sVerificationKey2024",
            "SlhDsaShake128fVerificationKey2024",
            "SlhDsaShake192sVerificationKey2024",
            "SlhDsaShake192fVerificationKey2024",
            "SlhDsaShake256sVerificationKey2024",
            "SlhDsaShake256fVerificationKey2024",
            "KazSignVerificationKey2024",
        };

        foreach (var vmType in allVmTypes)
        {
            Assert.NotNull(AlgorithmRegistry.Resolve(vmType));
            Assert.NotNull(AlgorithmRegistry.GetProofType(vmType));
            Assert.True(AlgorithmRegistry.IsSupported(vmType));
        }
    }

    [Fact]
    public void GetVmTypeFromProofType_RoundTrips_WithGetProofType()
    {
        var allVmTypes = new[]
        {
            "Ed25519VerificationKey2020",
            "EcdsaSecp256r1VerificationKey2019",
            "EcdsaSecp384VerificationKey2019",
            "MlDsa44VerificationKey2024",
            "MlDsa65VerificationKey2024",
            "MlDsa87VerificationKey2024",
            "SlhDsaSha2128sVerificationKey2024",
            "SlhDsaSha2128fVerificationKey2024",
            "SlhDsaSha2192sVerificationKey2024",
            "SlhDsaSha2192fVerificationKey2024",
            "SlhDsaSha2256sVerificationKey2024",
            "SlhDsaSha2256fVerificationKey2024",
            "SlhDsaShake128sVerificationKey2024",
            "SlhDsaShake128fVerificationKey2024",
            "SlhDsaShake192sVerificationKey2024",
            "SlhDsaShake192fVerificationKey2024",
            "SlhDsaShake256sVerificationKey2024",
            "SlhDsaShake256fVerificationKey2024",
            "KazSignVerificationKey2024",
        };

        foreach (var vmType in allVmTypes)
        {
            var proofType = AlgorithmRegistry.GetProofType(vmType);
            Assert.NotNull(proofType);

            var roundTripped = AlgorithmRegistry.GetVmTypeFromProofType(proofType);
            Assert.Equal(vmType, roundTripped);
        }
    }

    #endregion
}
