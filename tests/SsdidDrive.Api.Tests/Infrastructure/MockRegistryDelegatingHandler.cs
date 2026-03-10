using System.Collections.Concurrent;
using System.Net;
using System.Text;
using System.Text.Json;

namespace SsdidDrive.Api.Tests.Infrastructure;

/// <summary>
/// Mock HTTP handler that intercepts RegistryClient calls.
/// Supports DID document registration (POST /api/did) and resolution (GET /api/did/:did).
/// </summary>
public class MockRegistryDelegatingHandler : HttpMessageHandler
{
    private readonly ConcurrentDictionary<string, object> _documents = new();

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

            if (!root.TryGetProperty("did_document", out var didDoc) ||
                !didDoc.TryGetProperty("id", out var idEl))
            {
                return new HttpResponseMessage(HttpStatusCode.BadRequest)
                {
                    Content = new StringContent(
                        JsonSerializer.Serialize(new { error = "Missing did_document.id" }),
                        Encoding.UTF8, "application/json")
                };
            }

            var did = idEl.GetString()!;

            // Return 409 if DID already exists (matches real registry behavior)
            if (_documents.ContainsKey(did))
            {
                return new HttpResponseMessage(HttpStatusCode.Conflict)
                {
                    Content = new StringContent(
                        JsonSerializer.Serialize(new { error = "DID already exists" }),
                        Encoding.UTF8, "application/json")
                };
            }

            _documents[did] = JsonSerializer.Deserialize<object>(root.GetRawText())!;

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

        return new HttpResponseMessage(HttpStatusCode.NotFound);
    }
}
