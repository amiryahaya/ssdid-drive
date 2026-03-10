using System.Text.Json;

namespace SsdidDrive.Api.Ssdid;

/// <summary>
/// HTTP client for the SSDID Registry.
/// Resolves DIDs to DID Documents, registers DID Documents,
/// and performs challenge-response service registration.
/// </summary>
public class RegistryClient(HttpClient httpClient, ILogger<RegistryClient> logger)
{
    /// <summary>
    /// Resolve a DID to its DID Document from the registry.
    /// </summary>
    public async Task<JsonElement?> ResolveDid(string did)
    {
        try
        {
            // URL-encode the DID (colons in did:ssdid:xxx)
            var encodedDid = Uri.EscapeDataString(did);
            var response = await httpClient.GetAsync($"/api/did/{encodedDid}");

            if (!response.IsSuccessStatusCode)
            {
                logger.LogWarning("Failed to resolve DID {Did}: {Status}", did, response.StatusCode);
                return null;
            }

            var json = await response.Content.ReadAsStringAsync();
            using var doc = JsonDocument.Parse(json);
            return doc.RootElement.Clone();
        }
        catch (Exception ex)
        {
            logger.LogError(ex, "Error resolving DID {Did}", did);
            return null;
        }
    }

    /// <summary>
    /// Extract a public key from a DID Document by key ID.
    /// Returns the raw public key bytes.
    /// </summary>
    public static (byte[] PublicKey, string AlgorithmType)? ExtractPublicKey(JsonElement didDocument, string keyId)
    {
        if (!didDocument.TryGetProperty("did_document", out var doc))
            doc = didDocument;

        if (!doc.TryGetProperty("verificationMethod", out var methods))
            return null;

        foreach (var method in methods.EnumerateArray())
        {
            if (!method.TryGetProperty("id", out var idEl) || idEl.GetString() != keyId)
                continue;

            if (!method.TryGetProperty("publicKeyMultibase", out var multibaseEl))
                return null;
            var multibase = multibaseEl.GetString();
            if (multibase is null) return null;

            if (!method.TryGetProperty("type", out var typeEl))
                return null;
            var vmType = typeEl.GetString();
            if (vmType is null) return null;

            return (SsdidCrypto.MultibaseDecode(multibase), vmType);
        }

        return null;
    }

    // ── DID Document Registration (POST /api/did) ──

    /// <summary>
    /// Register a DID Document with the registry via W3C Data Integrity proof.
    /// </summary>
    public async Task<(bool Success, string? Error)> RegisterDidDocument(object didDocument, object proof)
    {
        try
        {
            var payload = new { did_document = didDocument, proof };
            var response = await httpClient.PostAsJsonAsync("/api/did", payload);

            if (response.IsSuccessStatusCode)
            {
                logger.LogInformation("DID document registered with registry");
                return (true, null);
            }

            var body = await response.Content.ReadAsStringAsync();
            logger.LogWarning("Failed to register DID document: {Status} {Body}",
                response.StatusCode, body);
            return (false, $"{response.StatusCode}: {body}");
        }
        catch (Exception ex)
        {
            logger.LogError(ex, "Error registering DID document with registry");
            return (false, ex.Message);
        }
    }

    // ── Challenge-Response Service Registration (POST /api/register) ──

    /// <summary>
    /// Step 1: Request a challenge for service registration.
    /// </summary>
    public async Task<RegistrationChallengeResponse?> RequestRegistrationChallenge(string did, string keyId)
    {
        try
        {
            var payload = new { did, key_id = keyId };
            var response = await httpClient.PostAsJsonAsync("/api/register", payload);

            if (!response.IsSuccessStatusCode)
            {
                var body = await response.Content.ReadAsStringAsync();
                logger.LogWarning("Registration challenge request failed: {Status} {Body}",
                    response.StatusCode, body);
                return null;
            }

            var json = await response.Content.ReadAsStringAsync();
            using var doc = JsonDocument.Parse(json);
            var root = doc.RootElement;

            return new RegistrationChallengeResponse(
                Challenge: root.GetProperty("challenge").GetString()!,
                ServerDid: root.GetProperty("server_did").GetString()!,
                ServerKeyId: root.GetProperty("server_key_id").GetString()!,
                ServerSignature: root.GetProperty("server_signature").GetString()!
            );
        }
        catch (Exception ex)
        {
            logger.LogError(ex, "Error requesting registration challenge");
            return null;
        }
    }

    /// <summary>
    /// Step 2: Verify the signed challenge to complete service registration.
    /// </summary>
    public async Task<RegistrationVerifyResponse?> VerifyRegistration(string did, string keyId, string signedChallenge)
    {
        try
        {
            var payload = new { did, key_id = keyId, signed_challenge = signedChallenge };
            var response = await httpClient.PostAsJsonAsync("/api/register/verify", payload);

            if (!response.IsSuccessStatusCode)
            {
                var body = await response.Content.ReadAsStringAsync();
                logger.LogWarning("Registration verification failed: {Status} {Body}",
                    response.StatusCode, body);
                return null;
            }

            var json = await response.Content.ReadAsStringAsync();
            using var doc = JsonDocument.Parse(json);
            var root = doc.RootElement.Clone();

            return new RegistrationVerifyResponse(
                Status: root.GetProperty("status").GetString()!,
                Credential: root.GetProperty("credential")
            );
        }
        catch (Exception ex)
        {
            logger.LogError(ex, "Error verifying registration");
            return null;
        }
    }
}

public record RegistrationChallengeResponse(
    string Challenge,
    string ServerDid,
    string ServerKeyId,
    string ServerSignature);

public record RegistrationVerifyResponse(
    string Status,
    JsonElement Credential);
