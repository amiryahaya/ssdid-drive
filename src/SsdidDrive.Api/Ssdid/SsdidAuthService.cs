using System.Text;
using System.Text.Json;
using SsdidDrive.Api.Common;
using SsdidDrive.Api.Crypto;

namespace SsdidDrive.Api.Ssdid;

public record RegisterResponse(string Challenge, string ServerDid, string ServerKeyId, string ServerSignature);
public record VerifyResponse(JsonElement Credential, string Did);
public record AuthenticateResponse(string SessionToken, string Did, string ServerDid, string ServerKeyId, string ServerSignature);

public class SsdidAuthService
{
    private readonly SsdidIdentity _identity;
    private readonly ISessionStore _sessionStore;
    private readonly RegistryClient _registryClient;
    private readonly CryptoProviderFactory _cryptoFactory;
    private readonly ILogger<SsdidAuthService> _logger;
    private readonly IReadOnlyDictionary<string, (byte[] PublicKey, string AlgorithmType, string KeyId)> _trustedKeys;

    private static readonly JsonSerializerOptions VcSerializerOptions = new() { WriteIndented = false };

    public SsdidAuthService(
        SsdidIdentity identity,
        ISessionStore sessionStore,
        RegistryClient registryClient,
        CryptoProviderFactory cryptoFactory,
        IConfiguration config,
        ILogger<SsdidAuthService> logger)
    {
        _identity = identity;
        _sessionStore = sessionStore;
        _registryClient = registryClient;
        _cryptoFactory = cryptoFactory;
        _logger = logger;
        _trustedKeys = BuildTrustedKeys(identity, config);
    }

    private static IReadOnlyDictionary<string, (byte[] PublicKey, string AlgorithmType, string KeyId)> BuildTrustedKeys(
        SsdidIdentity identity, IConfiguration config)
    {
        var keys = new Dictionary<string, (byte[] PublicKey, string AlgorithmType, string KeyId)>
        {
            [identity.Did] = (identity.PublicKey, identity.AlgorithmType, identity.KeyId)
        };
        var previous = config.GetSection("Ssdid:PreviousIdentities").GetChildren();
        foreach (var entry in previous)
        {
            var did = entry["Did"];
            var pubKey = entry["PublicKey"];
            var algType = entry["AlgorithmType"] ?? "Ed25519VerificationKey2020";
            var keyId = entry["KeyId"] ?? $"{did}#key-1";
            if (did is not null && pubKey is not null)
                keys[did] = (SsdidCrypto.Base64UrlDecode(pubKey), algType, keyId);
        }
        return keys.AsReadOnly();
    }

    public async Task<Result<RegisterResponse>> HandleRegister(string clientDid, string clientKeyId)
    {
        var didDoc = await _registryClient.ResolveDid(clientDid);
        if (didDoc is null)
        {
            _logger.LogWarning("Registration failed: DID not found {Did}", clientDid);
            return AppError.NotFound("DID not found in registry");
        }

        var challenge = SsdidCrypto.GenerateChallenge();
        var serverSignature = _identity.SignChallenge(challenge);
        _sessionStore.CreateChallenge(clientDid, "registration", challenge, clientKeyId);

        return new RegisterResponse(challenge, _identity.Did, _identity.KeyId, serverSignature);
    }

    public async Task<Result<VerifyResponse>> HandleVerifyResponse(string clientDid, string clientKeyId, string signedChallenge)
    {
        var entry = _sessionStore.ConsumeChallenge(clientDid, "registration");
        if (entry is null)
        {
            _logger.LogWarning("Verify failed: no challenge found for {Did}", clientDid);
            return AppError.Unauthorized("No pending challenge found or challenge expired");
        }

        if (entry.KeyId != clientKeyId)
        {
            _logger.LogWarning("Verify failed: key ID mismatch for {Did}", clientDid);
            return AppError.Unauthorized("Key ID does not match the pending challenge");
        }

        var didDoc = await _registryClient.ResolveDid(clientDid);
        if (didDoc is null)
            return AppError.NotFound("DID not found in registry");

        var extracted = RegistryClient.ExtractPublicKey(didDoc.Value, clientKeyId);
        if (extracted is null)
        {
            _logger.LogWarning("Verify failed: public key not found for {KeyId}", clientKeyId);
            return AppError.NotFound("Public key not found in DID Document");
        }

        var (publicKey, algorithmType) = extracted.Value;
        var signatureBytes = SsdidCrypto.MultibaseDecode(signedChallenge);
        var challengeBytes = Encoding.UTF8.GetBytes(entry.Challenge);

        if (!_cryptoFactory.Verify(algorithmType, challengeBytes, signatureBytes, publicKey))
        {
            _logger.LogWarning("Verify failed: invalid signature for {Did}", clientDid);
            return AppError.Unauthorized("Signature verification failed");
        }

        var credential = IssueCredential(clientDid);
        _logger.LogInformation("Registration verified for {Did}", clientDid);

        return new VerifyResponse(credential, clientDid);
    }

    public Result<string> VerifyCredential(JsonElement credential)
    {
        if (!VerifyCredentialOffline(credential))
        {
            _logger.LogWarning("Authentication failed: invalid credential");
            return AppError.Unauthorized("Invalid or expired credential");
        }

        var subjectDid = credential
            .GetProperty("credentialSubject")
            .GetProperty("id")
            .GetString();

        if (subjectDid is null)
            return AppError.Unauthorized("Credential missing subject DID");

        return subjectDid;
    }

    public Result<AuthenticateResponse> CreateAuthenticatedSession(string did)
    {
        var sessionToken = _sessionStore.CreateSession(did);
        if (sessionToken is null)
        {
            _logger.LogWarning("Authentication failed: session limit reached");
            return AppError.ServiceUnavailable("Session limit reached, try again later");
        }

        var serverSignature = _identity.SignChallenge(sessionToken);
        _logger.LogInformation("Authenticated {Did}", did);

        return new AuthenticateResponse(sessionToken, did, _identity.Did, _identity.KeyId, serverSignature);
    }

    public void RevokeSession(string token) => _sessionStore.DeleteSession(token);

    private static string BuildSigningInput(
        string vcId, string issuer, string issuanceDate,
        string expirationDate, string subjectDid, string service)
    {
        static string Lp(string s) => $"{s.Length}:{s}";
        return $"{Lp(vcId)};{Lp(issuer)};{Lp(issuanceDate)};{Lp(expirationDate)};{Lp(subjectDid)};{Lp(service)}";
    }

    private JsonElement IssueCredential(string subjectDid)
    {
        var now = DateTimeOffset.UtcNow;
        var vcId = $"urn:uuid:{Guid.NewGuid()}";
        var issuanceDate = now.ToString("o");
        var expirationDate = now.AddDays(30).ToString("o");

        var signingInput = BuildSigningInput(
            vcId, _identity.Did, issuanceDate, expirationDate, subjectDid, "drive");
        var proofBytes = _cryptoFactory.Sign(
            _identity.AlgorithmType,
            Encoding.UTF8.GetBytes(signingInput),
            _identity.PrivateKey);

        var proofType = CryptoProviderFactory.GetProofType(_identity.AlgorithmType);

        var vc = new
        {
            @context = new[] { "https://www.w3.org/2018/credentials/v1" },
            id = vcId,
            type = new[] { "VerifiableCredential", "SsdidRegistrationCredential" },
            issuer = _identity.Did,
            issuanceDate,
            expirationDate,
            credentialSubject = new
            {
                id = subjectDid,
                service = "drive",
                registeredAt = issuanceDate
            },
            proof = new
            {
                type = proofType,
                created = now.ToString("o"),
                verificationMethod = _identity.KeyId,
                proofPurpose = "assertionMethod",
                proofValue = SsdidCrypto.MultibaseEncode(proofBytes)
            }
        };

        return JsonSerializer.SerializeToElement(vc, VcSerializerOptions);
    }

    private bool VerifyCredentialOffline(JsonElement credential)
    {
        try
        {
            var issuer = credential.GetProperty("issuer").GetString();
            if (issuer is null || !_trustedKeys.TryGetValue(issuer, out var trustedKey))
            {
                _logger.LogWarning("VC verification failed: untrusted issuer {Issuer}", issuer);
                return false;
            }

            // Validate VC type includes SsdidRegistrationCredential
            if (!credential.TryGetProperty("type", out var typeArr) ||
                typeArr.ValueKind != JsonValueKind.Array)
            {
                _logger.LogWarning("VC verification failed: missing or invalid type array");
                return false;
            }

            var hasCredentialType = false;
            foreach (var t in typeArr.EnumerateArray())
            {
                if (t.GetString() == "SsdidRegistrationCredential")
                {
                    hasCredentialType = true;
                    break;
                }
            }

            if (!hasCredentialType)
            {
                _logger.LogWarning("VC verification failed: missing SsdidRegistrationCredential type");
                return false;
            }

            if (!credential.TryGetProperty("id", out var idEl) ||
                !credential.TryGetProperty("issuanceDate", out var issuanceDateEl) ||
                !credential.TryGetProperty("expirationDate", out var expirationDateEl) ||
                !credential.TryGetProperty("credentialSubject", out var subject) ||
                !subject.TryGetProperty("id", out var subjectDidEl) ||
                !subject.TryGetProperty("service", out var serviceEl) ||
                !credential.TryGetProperty("proof", out var proof) ||
                !proof.TryGetProperty("proofValue", out var proofValueEl))
            {
                _logger.LogWarning("VC verification failed: missing required properties");
                return false;
            }

            // Validate proof.proofPurpose
            if (!proof.TryGetProperty("proofPurpose", out var proofPurposeEl) ||
                proofPurposeEl.GetString() != "assertionMethod")
            {
                _logger.LogWarning("VC verification failed: invalid or missing proofPurpose");
                return false;
            }

            // Validate proof.verificationMethod matches trusted key
            if (!proof.TryGetProperty("verificationMethod", out var vmEl) ||
                vmEl.GetString() != trustedKey.KeyId)
            {
                _logger.LogWarning("VC verification failed: verificationMethod mismatch");
                return false;
            }

            var vcId = idEl.GetString();
            var issuanceDate = issuanceDateEl.GetString();
            var expirationDate = expirationDateEl.GetString();
            var subjectDid = subjectDidEl.GetString();
            var service = serviceEl.GetString();
            var proofValue = proofValueEl.GetString();

            if (vcId is null || issuanceDate is null || expirationDate is null ||
                subjectDid is null || service is null || proofValue is null)
            {
                _logger.LogWarning("VC verification failed: null property values");
                return false;
            }

            if (!DateTimeOffset.TryParse(expirationDate, null,
                    System.Globalization.DateTimeStyles.RoundtripKind, out var exp))
            {
                _logger.LogWarning("VC verification failed: unparseable expirationDate");
                return false;
            }

            if (exp < DateTimeOffset.UtcNow) return false;

            var signingInput = BuildSigningInput(vcId, issuer, issuanceDate, expirationDate, subjectDid, service);
            var sigBytes = SsdidCrypto.MultibaseDecode(proofValue);
            var msgBytes = Encoding.UTF8.GetBytes(signingInput);

            return _cryptoFactory.Verify(trustedKey.AlgorithmType, msgBytes, sigBytes, trustedKey.PublicKey);
        }
        catch (Exception ex) when (ex is FormatException or ArgumentException or KeyNotFoundException)
        {
            _logger.LogWarning(ex, "VC verification failed: invalid date or encoding format");
            return false;
        }
    }
}
