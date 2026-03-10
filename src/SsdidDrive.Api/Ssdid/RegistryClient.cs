using System.Text.Json;

namespace SsdidDrive.Api.Ssdid;

/// <summary>
/// HTTP client for the SSDID Registry.
/// The registry is a DID Document store — it handles CRUD only.
/// Challenge-response authentication happens directly between clients and this server.
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

            // 409 Conflict = DID already exists — treat as success for idempotent startup.
            // If the server key was rotated, the registry still has the old public key.
            // Use PUT /api/did/:did to update if key material changed.
            if (response.StatusCode == System.Net.HttpStatusCode.Conflict)
            {
                logger.LogWarning(
                    "DID already registered (409 Conflict). If the server key was rotated, " +
                    "the registry may have a stale public key — resolve and verify manually.");
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

}
