using System.Collections.Concurrent;
using System.Net;
using System.Text;
using System.Text.Json;

namespace SsdidDrive.Api.Tests.Infrastructure;

/// <summary>
/// Mock HTTP handler that intercepts RegistryClient calls.
/// </summary>
public class MockRegistryDelegatingHandler : HttpMessageHandler
{
    private readonly ConcurrentDictionary<string, object> _documents = new();

    public void RegisterDid(string did, Dictionary<string, object> didDocument)
    {
        _documents[did] = new { did_document = didDocument };
    }

    protected override Task<HttpResponseMessage> SendAsync(
        HttpRequestMessage request, CancellationToken ct)
    {
        var path = request.RequestUri?.AbsolutePath ?? "";

        if (request.Method == HttpMethod.Post && path == "/api/did")
        {
            return Task.FromResult(new HttpResponseMessage(HttpStatusCode.Created)
            {
                Content = new StringContent("{}", Encoding.UTF8, "application/json")
            });
        }

        if (request.Method == HttpMethod.Get && path.StartsWith("/api/did/"))
        {
            var encodedDid = path["/api/did/".Length..];
            var did = Uri.UnescapeDataString(encodedDid);

            if (_documents.TryGetValue(did, out var doc))
            {
                var json = JsonSerializer.Serialize(doc);
                return Task.FromResult(new HttpResponseMessage(HttpStatusCode.OK)
                {
                    Content = new StringContent(json, Encoding.UTF8, "application/json")
                });
            }

            return Task.FromResult(new HttpResponseMessage(HttpStatusCode.NotFound));
        }

        return Task.FromResult(new HttpResponseMessage(HttpStatusCode.NotFound));
    }
}
