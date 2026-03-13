import Foundation

/// Implementation of ActivityRepository using the API client
final class ActivityRepositoryImpl: ActivityRepository {

    // MARK: - Properties

    private let apiClient: APIClient

    // MARK: - Initialization

    init(apiClient: APIClient) {
        self.apiClient = apiClient
    }

    // MARK: - ActivityRepository

    func getActivity(page: Int, pageSize: Int, eventType: String?) async throws -> ActivityResponse {
        var queryItems = [
            URLQueryItem(name: "page", value: "\(page)"),
            URLQueryItem(name: "page_size", value: "\(pageSize)")
        ]

        if let eventType = eventType {
            queryItems.append(URLQueryItem(name: "event_type", value: eventType))
        }

        return try await apiClient.request(
            "/api/activity",
            method: .get,
            body: nil,
            queryItems: queryItems,
            requiresAuth: true
        )
    }

    func getResourceActivity(resourceId: String, page: Int, pageSize: Int) async throws -> ActivityResponse {
        guard UUID(uuidString: resourceId) != nil else {
            throw APIClient.APIError.invalidURL
        }

        let queryItems = [
            URLQueryItem(name: "page", value: "\(page)"),
            URLQueryItem(name: "page_size", value: "\(pageSize)")
        ]

        return try await apiClient.request(
            "/api/activity/resource/\(resourceId)",
            method: .get,
            body: nil,
            queryItems: queryItems,
            requiresAuth: true
        )
    }
}
