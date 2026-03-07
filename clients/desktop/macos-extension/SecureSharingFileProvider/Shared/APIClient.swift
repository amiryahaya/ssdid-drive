import Foundation
import os.log

/// HTTP client for communicating with the SecureSharing backend API
class APIClient {

    // MARK: - Properties

    private let session: URLSession
    private let sharedDefaults: SharedDefaults
    private let logger = Logger(subsystem: "com.securesharing.fileprovider", category: "APIClient")

    private var baseURL: URL {
        URL(string: sharedDefaults.apiBaseUrl)!
    }

    // MARK: - Initialization

    init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 300
        self.session = URLSession(configuration: config)
        self.sharedDefaults = SharedDefaults()
    }

    // MARK: - File Operations

    /// Fetch file metadata by ID
    func fetchFileMetadata(fileId: String, authToken: String) async throws -> FileProviderItem {
        let url = baseURL.appendingPathComponent("/api/files/\(fileId)")

        var request = URLRequest(url: url)
        request.setValue("Bearer \(authToken)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await session.data(for: request)

        try validateResponse(response)

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let item = FileProviderItem.from(apiResponse: json) else {
            throw APIError.invalidResponse
        }

        // Cache the metadata
        sharedDefaults.cacheFileMetadata(item)

        return item
    }

    /// List files in a folder
    func listFiles(folderId: String, page: Int, authToken: String) async throws -> ([FileProviderItem], Bool) {
        var components = URLComponents(url: baseURL.appendingPathComponent("/api/files"), resolvingAgainstBaseURL: true)!
        components.queryItems = [
            URLQueryItem(name: "parent_id", value: folderId == "root" ? nil : folderId),
            URLQueryItem(name: "page", value: String(page)),
            URLQueryItem(name: "limit", value: "50")
        ]

        var request = URLRequest(url: components.url!)
        request.setValue("Bearer \(authToken)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await session.data(for: request)

        try validateResponse(response)

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let filesArray = json["files"] as? [[String: Any]] else {
            throw APIError.invalidResponse
        }

        let items = filesArray.compactMap { FileProviderItem.from(apiResponse: $0) }
        let hasMore = json["has_more"] as? Bool ?? false

        // Cache all items
        sharedDefaults.cacheFileMetadata(items)

        return (items, hasMore)
    }

    /// Download file content
    func downloadFile(fileId: String, to destinationURL: URL, authToken: String, progress: @escaping (Double) -> Void) async throws {
        let url = baseURL.appendingPathComponent("/api/files/\(fileId)/download")

        var request = URLRequest(url: url)
        request.setValue("Bearer \(authToken)", forHTTPHeaderField: "Authorization")

        let (localURL, response) = try await session.download(for: request)

        try validateResponse(response)

        // Move downloaded file to destination
        try FileManager.default.moveItem(at: localURL, to: destinationURL)

        progress(1.0)
    }

    /// Upload a file
    func uploadFile(name: String, parentId: String, contentURL: URL, authToken: String, progress: @escaping (Double) -> Void) async throws -> FileProviderItem {
        let url = baseURL.appendingPathComponent("/api/files/upload")

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(authToken)", forHTTPHeaderField: "Authorization")

        // Create multipart form data
        let boundary = UUID().uuidString
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var body = Data()

        // Add parent_id field
        if parentId != "root" {
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"parent_id\"\r\n\r\n".data(using: .utf8)!)
            body.append("\(parentId)\r\n".data(using: .utf8)!)
        }

        // Add file
        let fileData = try Data(contentsOf: contentURL)
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"\(name)\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: application/octet-stream\r\n\r\n".data(using: .utf8)!)
        body.append(fileData)
        body.append("\r\n".data(using: .utf8)!)

        body.append("--\(boundary)--\r\n".data(using: .utf8)!)

        request.httpBody = body

        let (data, response) = try await session.data(for: request)

        try validateResponse(response)

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let item = FileProviderItem.from(apiResponse: json) else {
            throw APIError.invalidResponse
        }

        progress(1.0)

        return item
    }

    /// Create a folder
    func createFolder(name: String, parentId: String, authToken: String) async throws -> FileProviderItem {
        let url = baseURL.appendingPathComponent("/api/folders")

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(authToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "name": name,
            "parent_id": parentId == "root" ? NSNull() : parentId
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)

        try validateResponse(response)

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let item = FileProviderItem.from(apiResponse: json) else {
            throw APIError.invalidResponse
        }

        return item
    }

    /// Rename a file or folder
    func renameFile(fileId: String, newName: String, authToken: String) async throws -> FileProviderItem {
        let url = baseURL.appendingPathComponent("/api/files/\(fileId)")

        var request = URLRequest(url: url)
        request.httpMethod = "PATCH"
        request.setValue("Bearer \(authToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = ["name": newName]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)

        try validateResponse(response)

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let item = FileProviderItem.from(apiResponse: json) else {
            throw APIError.invalidResponse
        }

        // Update cache
        sharedDefaults.cacheFileMetadata(item)

        return item
    }

    /// Move a file or folder
    func moveFile(fileId: String, newParentId: String, authToken: String) async throws -> FileProviderItem {
        let url = baseURL.appendingPathComponent("/api/files/\(fileId)/move")

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(authToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = ["parent_id": newParentId == "root" ? NSNull() : newParentId]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)

        try validateResponse(response)

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let item = FileProviderItem.from(apiResponse: json) else {
            throw APIError.invalidResponse
        }

        // Update cache
        sharedDefaults.cacheFileMetadata(item)

        return item
    }

    /// Update file content
    func updateFileContent(fileId: String, contentURL: URL, authToken: String, progress: @escaping (Double) -> Void) async throws -> FileProviderItem {
        let url = baseURL.appendingPathComponent("/api/files/\(fileId)/content")

        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue("Bearer \(authToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")

        let fileData = try Data(contentsOf: contentURL)
        request.httpBody = fileData

        let (data, response) = try await session.data(for: request)

        try validateResponse(response)

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let item = FileProviderItem.from(apiResponse: json) else {
            throw APIError.invalidResponse
        }

        progress(1.0)

        // Update cache
        sharedDefaults.cacheFileMetadata(item)

        return item
    }

    /// Delete a file or folder
    func deleteFile(fileId: String, authToken: String) async throws {
        let url = baseURL.appendingPathComponent("/api/files/\(fileId)")

        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.setValue("Bearer \(authToken)", forHTTPHeaderField: "Authorization")

        let (_, response) = try await session.data(for: request)

        try validateResponse(response)

        // Remove from cache
        sharedDefaults.removeCachedFileMetadata(fileId: fileId)
    }

    /// Get changes since a timestamp
    func getChanges(since: Date, authToken: String) async throws -> FileChangesResponse {
        var components = URLComponents(url: baseURL.appendingPathComponent("/api/files/changes"), resolvingAgainstBaseURL: true)!
        components.queryItems = [
            URLQueryItem(name: "since", value: ISO8601DateFormatter().string(from: since))
        ]

        var request = URLRequest(url: components.url!)
        request.setValue("Bearer \(authToken)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await session.data(for: request)

        try validateResponse(response)

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw APIError.invalidResponse
        }

        let updatedArray = json["updated"] as? [[String: Any]] ?? []
        let deletedArray = json["deleted"] as? [String] ?? []

        let updatedItems = updatedArray.compactMap { FileProviderItem.from(apiResponse: $0) }

        // Update cache with new items
        sharedDefaults.cacheFileMetadata(updatedItems)

        // Remove deleted items from cache
        for fileId in deletedArray {
            sharedDefaults.removeCachedFileMetadata(fileId: fileId)
        }

        return FileChangesResponse(
            updatedItems: updatedItems,
            deletedItemIds: deletedArray
        )
    }

    /// Get recent files
    func getRecentFiles(authToken: String) async throws -> [FileProviderItem] {
        let url = baseURL.appendingPathComponent("/api/files/recent")

        var request = URLRequest(url: url)
        request.setValue("Bearer \(authToken)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await session.data(for: request)

        try validateResponse(response)

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let filesArray = json["files"] as? [[String: Any]] else {
            throw APIError.invalidResponse
        }

        return filesArray.compactMap { FileProviderItem.from(apiResponse: $0) }
    }

    /// Get trashed files
    func getTrashedFiles(authToken: String) async throws -> [FileProviderItem] {
        let url = baseURL.appendingPathComponent("/api/files/trash")

        var request = URLRequest(url: url)
        request.setValue("Bearer \(authToken)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await session.data(for: request)

        try validateResponse(response)

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let filesArray = json["files"] as? [[String: Any]] else {
            throw APIError.invalidResponse
        }

        return filesArray.compactMap { FileProviderItem.from(apiResponse: $0) }
    }

    // MARK: - Private Methods

    private func validateResponse(_ response: URLResponse) throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }

        switch httpResponse.statusCode {
        case 200...299:
            return
        case 401:
            throw APIError.unauthorized
        case 403:
            throw APIError.forbidden
        case 404:
            throw APIError.notFound
        case 429:
            throw APIError.rateLimited
        case 500...599:
            throw APIError.serverError
        default:
            throw APIError.unknown(httpResponse.statusCode)
        }
    }
}

// MARK: - API Errors

enum APIError: Error, LocalizedError {
    case invalidResponse
    case unauthorized
    case forbidden
    case notFound
    case rateLimited
    case serverError
    case unknown(Int)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Invalid response from server"
        case .unauthorized:
            return "Authentication required"
        case .forbidden:
            return "Access denied"
        case .notFound:
            return "Resource not found"
        case .rateLimited:
            return "Too many requests"
        case .serverError:
            return "Server error"
        case .unknown(let code):
            return "Unknown error (status code: \(code))"
        }
    }
}
