import Foundation
import FileProvider

/// Minimal URLSession-based HTTP client for the File Provider extension.
/// Reads auth token from the shared keychain. If missing or expired, throws `.notAuthenticated`.
/// No token refresh — if 401, throws `.notAuthenticated` so the system shows "Sign in required".
final class FPAPIClient {

    private let session: URLSession
    private let baseURL: String

    init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = FPConstants.httpTimeout
        config.timeoutIntervalForResource = 120
        self.session = URLSession(configuration: config)
        self.baseURL = FPConstants.baseURL
    }

    // MARK: - Folder Operations

    func listFolder(_ folderId: String?) async throws -> FPFolderContents {
        let path: String
        if let folderId {
            path = "/folders/\(folderId)/contents"
        } else {
            path = "/folders/root/contents"
        }
        return try await get(path)
    }

    func createFolder(name: String, parentId: String?, encryptedFolderKey: String? = nil, kemAlgorithm: String? = nil) async throws -> FPFolder {
        struct Body: Encodable {
            let name: String
            let parent_id: String?
            let encrypted_folder_key: String?
            let kem_algorithm: String?
        }
        let response: FPFolderResponse = try await post("/folders", body: Body(
            name: name,
            parent_id: parentId,
            encrypted_folder_key: encryptedFolderKey,
            kem_algorithm: kemAlgorithm
        ))
        return response.folder
    }

    func renameFolder(_ folderId: String, newName: String) async throws -> FPFolder {
        struct Body: Encodable { let name: String }
        let response: FPFolderResponse = try await put("/folders/\(folderId)", body: Body(name: newName))
        return response.folder
    }

    func deleteFolder(_ folderId: String) async throws {
        try await delete("/folders/\(folderId)")
    }

    // MARK: - File Operations

    func getFile(_ fileId: String) async throws -> FPFileItem {
        let response: FPFileResponse = try await get("/files/\(fileId)")
        return response.file
    }

    func getFolder(_ folderId: String) async throws -> FPFolder {
        let response: FPFolderResponse = try await get("/folders/\(folderId)")
        return response.folder
    }

    func downloadFile(_ fileId: String) async throws -> Data {
        let request = try makeRequest(path: "/files/\(fileId)/download", method: "GET")
        let (data, response) = try await session.data(for: request)
        try validateResponse(response)
        return data
    }

    /// Upload a file with optional encryption metadata.
    ///
    /// - Parameters:
    ///   - name: Display filename.
    ///   - fileData: File content (encrypted or plaintext).
    ///   - mimeType: MIME type of the original file.
    ///   - folderId: Parent folder ID (nil for root).
    ///   - encryptedFileKey: Base64-encoded wrapped file DEK (ciphertext + tag).
    ///   - nonce: Base64-encoded AES-GCM nonce for the file data.
    ///   - keyNonce: Base64-encoded AES-GCM nonce for the wrapped file key.
    ///   - algorithm: Encryption algorithm identifier (e.g. "aes-256-gcm").
    func uploadFile(
        name: String,
        data fileData: Data,
        mimeType: String,
        folderId: String?,
        encryptedFileKey: String? = nil,
        nonce: String? = nil,
        keyNonce: String? = nil,
        algorithm: String? = nil
    ) async throws -> FPFileItem {
        let token = try requireToken()
        let boundary = UUID().uuidString
        var request = URLRequest(url: URL(string: "\(baseURL)/files/upload")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var body = Data()
        // File field — sanitize filename for multipart header safety
        let safeName = name
            .replacingOccurrences(of: "\"", with: "_")
            .replacingOccurrences(of: "\r", with: "")
            .replacingOccurrences(of: "\n", with: "")
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"\(safeName)\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: \(mimeType)\r\n\r\n".data(using: .utf8)!)
        body.append(fileData)
        body.append("\r\n".data(using: .utf8)!)

        // Helper to append a multipart text field
        func appendField(_ fieldName: String, _ value: String) {
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"\(fieldName)\"\r\n\r\n".data(using: .utf8)!)
            body.append("\(value)\r\n".data(using: .utf8)!)
        }

        // Folder ID field
        if let folderId {
            appendField("folder_id", folderId)
        }

        // Encryption metadata fields
        if let encryptedFileKey {
            appendField("encrypted_file_key", encryptedFileKey)
        }
        if let nonce {
            appendField("nonce", nonce)
        }
        if let keyNonce {
            appendField("key_nonce", keyNonce)
        }
        if let algorithm {
            appendField("algorithm", algorithm)
        }

        body.append("--\(boundary)--\r\n".data(using: .utf8)!)
        request.httpBody = body

        let (responseData, response) = try await session.data(for: request)
        try validateResponse(response)
        let wrapper = try jsonDecoder.decode(FPFileResponse.self, from: responseData)
        return wrapper.file
    }

    func renameFile(_ fileId: String, newName: String) async throws -> FPFileItem {
        struct Body: Encodable { let name: String }
        let response: FPFileResponse = try await put("/files/\(fileId)", body: Body(name: newName))
        return response.file
    }

    func deleteFile(_ fileId: String) async throws {
        try await delete("/files/\(fileId)")
    }

    // MARK: - Private Networking

    private func get<T: Decodable>(_ path: String) async throws -> T {
        let request = try makeRequest(path: path, method: "GET")
        let (data, response) = try await session.data(for: request)
        try validateResponse(response)
        return try jsonDecoder.decode(T.self, from: data)
    }

    private func post<T: Decodable, B: Encodable>(_ path: String, body: B) async throws -> T {
        var request = try makeRequest(path: path, method: "POST")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)
        let (data, response) = try await session.data(for: request)
        try validateResponse(response)
        return try jsonDecoder.decode(T.self, from: data)
    }

    private func put<T: Decodable, B: Encodable>(_ path: String, body: B) async throws -> T {
        var request = try makeRequest(path: path, method: "PUT")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)
        let (data, response) = try await session.data(for: request)
        try validateResponse(response)
        return try jsonDecoder.decode(T.self, from: data)
    }

    private func delete(_ path: String) async throws {
        let request = try makeRequest(path: path, method: "DELETE")
        let (_, response) = try await session.data(for: request)
        try validateResponse(response)
    }

    private func makeRequest(path: String, method: String) throws -> URLRequest {
        let token = try requireToken()
        guard let url = URL(string: "\(baseURL)\(path)") else {
            throw NSFileProviderError(.noSuchItem)
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return request
    }

    private func requireToken() throws -> String {
        guard let token = FPKeychainReader.readAccessToken() else {
            throw NSFileProviderError(.notAuthenticated)
        }
        return token
    }

    private func validateResponse(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else {
            throw NSFileProviderError(.serverUnreachable)
        }
        switch http.statusCode {
        case 200...299:
            return
        case 401:
            throw NSFileProviderError(.notAuthenticated)
        case 404:
            throw NSFileProviderError(.noSuchItem)
        default:
            throw NSFileProviderError(.serverUnreachable)
        }
    }

    private lazy var jsonDecoder: JSONDecoder = {
        let decoder = JSONDecoder()
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let fallbackFormatter = ISO8601DateFormatter()
        fallbackFormatter.formatOptions = [.withInternetDateTime]
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let string = try container.decode(String.self)
            if let date = formatter.date(from: string) { return date }
            if let date = fallbackFormatter.date(from: string) { return date }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid date: \(string)")
        }
        return decoder
    }()
}

// MARK: - Response Wrappers

private struct FPFileResponse: Decodable {
    let file: FPFileItem
}

private struct FPFolderResponse: Decodable {
    let folder: FPFolder
}
