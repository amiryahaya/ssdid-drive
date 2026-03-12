import Foundation

/// Service for SSDID wallet-based authentication.
/// Communicates with the server's SSDID auth endpoints to retrieve server identity
/// and facilitate QR-code / deep-link authentication flows.
final class SsdidAuthService {

    // MARK: - Singleton

    static let shared = SsdidAuthService()

    // MARK: - Properties

    let baseURL: String

    // MARK: - Types

    struct ServerInfo: Codable {
        let serverDid: String
        let serverKeyId: String
        let serviceName: String
        let registryUrl: String

        enum CodingKeys: String, CodingKey {
            case serverDid = "server_did"
            case serverKeyId = "server_key_id"
            case serviceName = "service_name"
            case registryUrl = "registry_url"
        }
    }

    // MARK: - Initialization

    private init() {
        baseURL = ProcessInfo.processInfo.environment["API_URL"]
            ?? "https://drive.ssdid.my"
    }

    // MARK: - Endpoints

    /// Fetch server identity information needed to build the QR challenge payload.
    func getServerInfo() async throws -> ServerInfo {
        guard let url = URL(string: "\(baseURL)/api/auth/ssdid/server-info") else {
            throw URLError(.badURL)
        }

        let (data, response) = try await URLSession.shared.data(from: url)

        if let httpResponse = response as? HTTPURLResponse,
           !(200...299).contains(httpResponse.statusCode) {
            throw URLError(.badServerResponse)
        }

        return try JSONDecoder().decode(ServerInfo.self, from: data)
    }
}
