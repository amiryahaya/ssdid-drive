using SsdidDrive.Api.Crypto;

namespace SsdidDrive.Api.Ssdid;

public class ServerRegistrationService(
    IServiceProvider services,
    SsdidIdentity identity,
    IHostApplicationLifetime lifetime,
    ILogger<ServerRegistrationService> logger) : IHostedService
{
    private CancellationTokenSource? _cts;
    private const int MaxRetries = 3;
    private static readonly TimeSpan RetryDelay = TimeSpan.FromSeconds(10);

    public Task StartAsync(CancellationToken ct)
    {
        _cts = CancellationTokenSource.CreateLinkedTokenSource(ct);
        lifetime.ApplicationStarted.Register(() => _ = RegisterWithRetryAsync(_cts.Token));
        return Task.CompletedTask;
    }

    public Task StopAsync(CancellationToken ct)
    {
        _cts?.Cancel();
        _cts?.Dispose();
        return Task.CompletedTask;
    }

    private async Task RegisterWithRetryAsync(CancellationToken ct)
    {
        for (var attempt = 1; attempt <= MaxRetries; attempt++)
        {
            try
            {
                using var scope = services.CreateScope();
                var registry = scope.ServiceProvider.GetRequiredService<RegistryClient>();

                // Step 1: Register DID Document via W3C Data Integrity proof
                var didRegistered = await RegisterDidDocument(registry);
                if (!didRegistered)
                {
                    logger.LogWarning(
                        "DID document registration failed (attempt {Attempt}/{Max})",
                        attempt, MaxRetries);

                    if (attempt < MaxRetries)
                        await Task.Delay(RetryDelay * attempt, ct);
                    continue;
                }

                // Step 2: Challenge-response service registration
                var serviceRegistered = await RegisterWithChallenge(registry);
                if (serviceRegistered)
                {
                    logger.LogInformation("Server DID registered and verified: {Did}", identity.Did);
                    return;
                }

                logger.LogWarning(
                    "Service registration failed (attempt {Attempt}/{Max})",
                    attempt, MaxRetries);
            }
            catch (Exception ex) when (ex is not OperationCanceledException)
            {
                logger.LogWarning(ex,
                    "Could not register server DID (attempt {Attempt}/{Max})",
                    attempt, MaxRetries);
            }

            if (attempt < MaxRetries)
                await Task.Delay(RetryDelay * attempt, ct);
        }

        logger.LogError("Server DID registration failed after {Max} attempts", MaxRetries);
    }

    /// <summary>
    /// Register the server's DID Document with the registry (POST /api/did).
    /// </summary>
    private async Task<bool> RegisterDidDocument(RegistryClient registry)
    {
        var didDoc = identity.BuildDidDocument();

        var proofType = CryptoProviderFactory.GetProofType(identity.AlgorithmType);
        var proofOptions = new Dictionary<string, object>
        {
            ["type"] = proofType,
            ["created"] = DateTimeOffset.UtcNow.ToString("o"),
            ["verificationMethod"] = identity.KeyId,
            ["proofPurpose"] = "assertionMethod"
        };

        var payload = SsdidCrypto.W3cSigningPayload(didDoc, proofOptions);
        var proofBytes = identity.SignRaw(payload);
        proofOptions["proofValue"] = SsdidCrypto.MultibaseEncode(proofBytes);

        var (success, error) = await registry.RegisterDidDocument(didDoc, proofOptions);

        if (!success)
            logger.LogWarning("DID document registration error: {Error}", error);

        return success;
    }

    /// <summary>
    /// Challenge-response service registration (POST /api/register + /api/register/verify).
    /// </summary>
    private async Task<bool> RegisterWithChallenge(RegistryClient registry)
    {
        // Step 1: Request challenge
        var challengeResp = await registry.RequestRegistrationChallenge(identity.Did, identity.KeyId);
        if (challengeResp is null)
            return false;

        logger.LogDebug("Received registration challenge from {ServerDid}", challengeResp.ServerDid);

        // Step 2: Sign the challenge
        var signedChallenge = identity.SignChallenge(challengeResp.Challenge);

        // Step 3: Verify with the signed challenge
        var verifyResp = await registry.VerifyRegistration(identity.Did, identity.KeyId, signedChallenge);
        if (verifyResp is null)
            return false;

        logger.LogInformation("Service registration verified: {Status}", verifyResp.Status);
        return true;
    }
}
