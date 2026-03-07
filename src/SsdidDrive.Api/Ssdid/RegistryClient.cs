using System.Text.Json;

namespace SsdidDrive.Api.Ssdid;

/// <summary>
/// HTTP client for the SSDID Registry.
/// Resolves DIDs to DID Documents and retrieves public keys.
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
            var id = method.GetProperty("id").GetString();
            if (id != keyId) continue;

            var multibase = method.GetProperty("publicKeyMultibase").GetString();
            if (multibase is null) return null;

            var vmType = method.GetProperty("type").GetString();
            if (vmType is null) return null;

            return (SsdidCrypto.MultibaseDecode(multibase), vmType);
        }

        return null;
    }

    /// <summary>
    /// Register a DID Document with the registry.
    /// </summary>
    public async Task<bool> RegisterDid(object didDocument, object proof)
    {
        try
        {
            var payload = new { did_document = didDocument, proof };
            var response = await httpClient.PostAsJsonAsync("/api/did", payload);

            if (response.IsSuccessStatusCode)
            {
                logger.LogInformation("DID registered with registry");
                return true;
            }

            logger.LogWarning("Failed to register DID: {Status}", response.StatusCode);
            return false;
        }
        catch (Exception ex)
        {
            logger.LogError(ex, "Error registering DID with registry");
            return false;
        }
    }
}
