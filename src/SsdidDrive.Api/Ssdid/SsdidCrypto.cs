using System.Security.Cryptography;
using System.Text;
using System.Text.Encodings.Web;
using System.Text.Json;
using Org.BouncyCastle.Crypto.Digests;

namespace SsdidDrive.Api.Ssdid;

/// <summary>
/// Encoding utilities for SSDID: Base64url, multibase, challenge generation,
/// canonical JSON, SHA3-256, and W3C Data Integrity signing payload.
/// </summary>
public static class SsdidCrypto
{
    public const string DefaultRegistryUrl = "https://registry.ssdid.my";

    public static string GenerateChallenge()
    {
        var bytes = RandomNumberGenerator.GetBytes(32);
        return Base64UrlEncode(bytes);
    }

    public static string Base64UrlEncode(byte[] data)
    {
        return Convert.ToBase64String(data)
            .Replace('+', '-')
            .Replace('/', '_')
            .TrimEnd('=');
    }

    public static byte[] Base64UrlDecode(string input)
    {
        var s = input.Replace('-', '+').Replace('_', '/');
        switch (s.Length % 4)
        {
            case 2: s += "=="; break;
            case 3: s += "="; break;
        }
        return Convert.FromBase64String(s);
    }

    public static string MultibaseEncode(byte[] data) => "u" + Base64UrlEncode(data);

    public static byte[] MultibaseDecode(string multibase)
    {
        if (string.IsNullOrEmpty(multibase) || multibase[0] != 'u')
            throw new ArgumentException("Invalid multibase encoding (expected 'u' prefix)");

        return Base64UrlDecode(multibase[1..]);
    }

    // ── Canonical JSON (sorted keys, no whitespace) ──

    /// <summary>
    /// Produces canonical JSON: keys sorted alphabetically, no whitespace.
    /// Matches the SSDID registry's SsdidCore.Crypto.canonical_json/1.
    /// </summary>
    /// <summary>
    /// JSON serializer options that match Elixir Jason.encode! behavior:
    /// no escaping of +, /, etc. — only mandatory escapes (" and \).
    /// </summary>
    private static readonly JsonSerializerOptions RelaxedJson = new()
    {
        Encoder = JavaScriptEncoder.UnsafeRelaxedJsonEscaping
    };

    public static string CanonicalJson(object obj)
    {
        var json = JsonSerializer.Serialize(obj, RelaxedJson);
        using var doc = JsonDocument.Parse(json);
        return CanonicalizeElement(doc.RootElement);
    }

    private static string CanonicalizeElement(JsonElement element)
    {
        switch (element.ValueKind)
        {
            case JsonValueKind.Object:
                var properties = element.EnumerateObject()
                    .OrderBy(p => p.Name, StringComparer.Ordinal)
                    .Select(p => $"{JsonSerializer.Serialize(p.Name, RelaxedJson)}:{CanonicalizeElement(p.Value)}");
                return "{" + string.Join(",", properties) + "}";

            case JsonValueKind.Array:
                var items = element.EnumerateArray()
                    .Select(CanonicalizeElement);
                return "[" + string.Join(",", items) + "]";

            default:
                // GetRawText() preserves the original encoding from Parse,
                // but we re-parsed from RelaxedJson output so + stays literal
                return element.GetRawText();
        }
    }

    // ── SHA3-256 ──

    /// <summary>
    /// Computes SHA3-256 hash using BouncyCastle.
    /// Matches the SSDID registry's SsdidCore.Crypto.sha3_256/1.
    /// </summary>
    public static byte[] Sha3_256(byte[] data)
    {
        var digest = new Sha3Digest(256);
        digest.BlockUpdate(data, 0, data.Length);
        var result = new byte[digest.GetDigestSize()];
        digest.DoFinal(result, 0);
        return result;
    }

    // ── W3C Data Integrity signing payload ──

    /// <summary>
    /// Builds the W3C Data Integrity signing payload:
    ///   SHA3-256(canonical_json(proof_options)) + SHA3-256(canonical_json(document))
    /// Matches the SSDID registry's SsdidCore.Proof.signing_payload/2.
    /// </summary>
    public static byte[] W3cSigningPayload(object document, object proofOptions)
    {
        var docHash = Sha3_256(Encoding.UTF8.GetBytes(CanonicalJson(document)));
        var optionsHash = Sha3_256(Encoding.UTF8.GetBytes(CanonicalJson(proofOptions)));

        // W3C Data Integrity: options hash first, then document hash
        var payload = new byte[optionsHash.Length + docHash.Length];
        Buffer.BlockCopy(optionsHash, 0, payload, 0, optionsHash.Length);
        Buffer.BlockCopy(docHash, 0, payload, optionsHash.Length, docHash.Length);
        return payload;
    }
}
