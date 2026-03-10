using System.Collections.Concurrent;
using System.Net;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;

namespace SsdidDrive.Api.Tests.Infrastructure;

/// <summary>
/// Mock HTTP handler that intercepts RegistryClient calls.
/// Supports both DID document registration (POST /api/did) and
/// challenge-response service registration (POST /api/register, /api/register/verify).
/// </summary>
public class MockRegistryDelegatingHandler : HttpMessageHandler
{
    private readonly ConcurrentDictionary<string, object> _documents = new();
    private readonly ConcurrentDictionary<string, string> _challenges = new();

    public void RegisterDid(string did, Dictionary<string, object> didDocument)
    {
        _documents[did] = new { did_document = didDocument };
    }

    protected override async Task<HttpResponseMessage> SendAsync(
        HttpRequestMessage request, CancellationToken ct)
    {
        var path = request.RequestUri?.AbsolutePath ?? "";

        // POST /api/did — DID document registration
        if (request.Method == HttpMethod.Post && path == "/api/did")
        {
            var body = await request.Content!.ReadAsStringAsync(ct);
            using var doc = JsonDocument.Parse(body);
            var root = doc.RootElement;

            if (root.TryGetProperty("did_document", out var didDoc) &&
                didDoc.TryGetProperty("id", out var idEl))
            {
                var did = idEl.GetString()!;
                _documents[did] = JsonSerializer.Deserialize<object>(root.GetRawText())!;
            }

            return new HttpResponseMessage(HttpStatusCode.Created)
            {
                Content = new StringContent(
                    JsonSerializer.Serialize(new { status = "created" }),
                    Encoding.UTF8, "application/json")
            };
        }

        // GET /api/did/:did — DID resolution
        if (request.Method == HttpMethod.Get && path.StartsWith("/api/did/"))
        {
            var encodedDid = path["/api/did/".Length..];
            var did = Uri.UnescapeDataString(encodedDid);

            if (_documents.TryGetValue(did, out var doc))
            {
                var json = JsonSerializer.Serialize(doc);
                return new HttpResponseMessage(HttpStatusCode.OK)
                {
                    Content = new StringContent(json, Encoding.UTF8, "application/json")
                };
            }

            return new HttpResponseMessage(HttpStatusCode.NotFound);
        }

        // POST /api/register — challenge request
        if (request.Method == HttpMethod.Post && path == "/api/register")
        {
            var body = await request.Content!.ReadAsStringAsync(ct);
            using var doc = JsonDocument.Parse(body);
            var root = doc.RootElement;

            var did = root.GetProperty("did").GetString()!;

            if (!_documents.ContainsKey(did))
            {
                return new HttpResponseMessage(HttpStatusCode.NotFound)
                {
                    Content = new StringContent(
                        JsonSerializer.Serialize(new { error = "Client DID not found in registry" }),
                        Encoding.UTF8, "application/json")
                };
            }

            var challenge = Convert.ToBase64String(RandomNumberGenerator.GetBytes(32))
                .Replace('+', '-').Replace('/', '_').TrimEnd('=');
            _challenges[did] = challenge;

            var response = new
            {
                challenge,
                server_did = "did:ssdid:mock-server",
                server_key_id = "did:ssdid:mock-server#key-1",
                server_signature = "umock-signature"
            };

            return new HttpResponseMessage(HttpStatusCode.OK)
            {
                Content = new StringContent(
                    JsonSerializer.Serialize(response),
                    Encoding.UTF8, "application/json")
            };
        }

        // POST /api/register/verify — challenge verification
        if (request.Method == HttpMethod.Post && path == "/api/register/verify")
        {
            var body = await request.Content!.ReadAsStringAsync(ct);
            using var doc = JsonDocument.Parse(body);
            var root = doc.RootElement;

            var did = root.GetProperty("did").GetString()!;

            if (!_challenges.TryRemove(did, out _))
            {
                return new HttpResponseMessage(HttpStatusCode.BadRequest)
                {
                    Content = new StringContent(
                        JsonSerializer.Serialize(new { error = "No pending challenge" }),
                        Encoding.UTF8, "application/json")
                };
            }

            // Mock: accept any signed challenge (we can't verify without the real crypto)
            var credential = new
            {
                status = "registered",
                credential = new
                {
                    type = new[] { "VerifiableCredential", "ServiceCredential" },
                    issuer = "did:ssdid:mock-server",
                    credentialSubject = new { id = did, service = "drive" }
                }
            };

            return new HttpResponseMessage(HttpStatusCode.Created)
            {
                Content = new StringContent(
                    JsonSerializer.Serialize(credential),
                    Encoding.UTF8, "application/json")
            };
        }

        return new HttpResponseMessage(HttpStatusCode.NotFound);
    }
}
