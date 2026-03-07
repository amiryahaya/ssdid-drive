import Foundation
@testable import SecureSharing

/// Mock API client for testing network layer
final class MockAPIClient {

    // MARK: - Types

    typealias RequestHandler = (String, HTTPMethod, Any?) throws -> Data

    enum HTTPMethod: String {
        case get = "GET"
        case post = "POST"
        case put = "PUT"
        case patch = "PATCH"
        case delete = "DELETE"
    }

    enum MockAPIError: Error, LocalizedError {
        case notConfigured
        case httpError(statusCode: Int, message: String?)
        case networkError
        case timeout
        case decodingError

        var errorDescription: String? {
            switch self {
            case .notConfigured:
                return "Response not configured"
            case .httpError(let code, let message):
                return message ?? "HTTP error \(code)"
            case .networkError:
                return "Network error"
            case .timeout:
                return "Request timed out"
            case .decodingError:
                return "Failed to decode response"
            }
        }
    }

    // MARK: - Properties

    /// Map of endpoint to response data/error
    private var responses: [String: Result<Data, Error>] = [:]

    /// Custom handler for dynamic responses
    var requestHandler: RequestHandler?

    /// Track all requests made
    private(set) var requestHistory: [(endpoint: String, method: HTTPMethod, body: Data?)] = []

    /// Artificial delay for simulating network latency (in seconds)
    var artificialDelay: TimeInterval = 0

    /// Whether to fail all requests
    var shouldFailAllRequests = false
    var failAllRequestsError: Error = MockAPIError.networkError

    // MARK: - Configuration

    /// Set a successful JSON response for an endpoint
    func setResponse(_ jsonString: String, for endpoint: String) {
        guard let data = jsonString.data(using: .utf8) else { return }
        responses[endpoint] = .success(data)
    }

    /// Set response data for an endpoint
    func setResponse(_ data: Data, for endpoint: String) {
        responses[endpoint] = .success(data)
    }

    /// Set an error response for an endpoint
    func setError(_ error: Error, for endpoint: String) {
        responses[endpoint] = .failure(error)
    }

    /// Set a specific HTTP error for an endpoint
    func setHTTPError(statusCode: Int, message: String? = nil, for endpoint: String) {
        responses[endpoint] = .failure(MockAPIError.httpError(statusCode: statusCode, message: message))
    }

    /// Clear all configured responses
    func clearResponses() {
        responses.removeAll()
    }

    /// Clear request history
    func clearHistory() {
        requestHistory.removeAll()
    }

    /// Reset all state
    func reset() {
        responses.removeAll()
        requestHistory.removeAll()
        requestHandler = nil
        artificialDelay = 0
        shouldFailAllRequests = false
    }

    // MARK: - Request Methods

    /// Make a mock request and return decoded response
    func request<T: Decodable>(
        _ endpoint: String,
        method: HTTPMethod = .get,
        body: Encodable? = nil
    ) async throws -> T {
        // Track the request
        var bodyData: Data?
        if let body = body {
            bodyData = try? JSONEncoder().encode(AnyEncodable(body))
        }
        requestHistory.append((endpoint, method, bodyData))

        // Apply artificial delay
        if artificialDelay > 0 {
            try await Task.sleep(nanoseconds: UInt64(artificialDelay * 1_000_000_000))
        }

        // Check for global failure
        if shouldFailAllRequests {
            throw failAllRequestsError
        }

        // Try custom handler first
        if let handler = requestHandler {
            let data = try handler(endpoint, method, body)
            return try decode(data)
        }

        // Look up configured response
        guard let result = responses[endpoint] else {
            throw MockAPIError.notConfigured
        }

        switch result {
        case .success(let data):
            return try decode(data)
        case .failure(let error):
            throw error
        }
    }

    /// Make a mock request without expecting a response body
    func requestNoContent(
        _ endpoint: String,
        method: HTTPMethod = .get,
        body: Encodable? = nil
    ) async throws {
        // Track the request
        var bodyData: Data?
        if let body = body {
            bodyData = try? JSONEncoder().encode(AnyEncodable(body))
        }
        requestHistory.append((endpoint, method, bodyData))

        // Apply artificial delay
        if artificialDelay > 0 {
            try await Task.sleep(nanoseconds: UInt64(artificialDelay * 1_000_000_000))
        }

        // Check for global failure
        if shouldFailAllRequests {
            throw failAllRequestsError
        }

        // Check for configured error
        if let result = responses[endpoint], case .failure(let error) = result {
            throw error
        }
    }

    // MARK: - Helpers

    private func decode<T: Decodable>(_ data: Data) throws -> T {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw MockAPIError.decodingError
        }
    }

    // MARK: - Request History Helpers

    /// Get the number of requests made to a specific endpoint
    func requestCount(for endpoint: String) -> Int {
        requestHistory.filter { $0.endpoint == endpoint }.count
    }

    /// Get the last request made to a specific endpoint
    func lastRequest(for endpoint: String) -> (endpoint: String, method: HTTPMethod, body: Data?)? {
        requestHistory.last { $0.endpoint == endpoint }
    }

    /// Get the body of the last request to an endpoint as decoded object
    func lastRequestBody<T: Decodable>(for endpoint: String, as type: T.Type) -> T? {
        guard let request = lastRequest(for: endpoint),
              let bodyData = request.body else {
            return nil
        }
        return try? JSONDecoder().decode(type, from: bodyData)
    }

    /// Check if any request was made to an endpoint
    func wasEndpointCalled(_ endpoint: String) -> Bool {
        requestHistory.contains { $0.endpoint == endpoint }
    }
}

// MARK: - Type-Erased Encodable

private struct AnyEncodable: Encodable {
    private let _encode: (Encoder) throws -> Void

    init<T: Encodable>(_ value: T) {
        _encode = value.encode
    }

    func encode(to encoder: Encoder) throws {
        try _encode(encoder)
    }
}
