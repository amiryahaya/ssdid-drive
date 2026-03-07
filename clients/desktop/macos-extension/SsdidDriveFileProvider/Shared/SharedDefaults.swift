import Foundation

/// Helper class for sharing data between the main app and extension via App Groups
class SharedDefaults {

    // MARK: - Constants

    private let appGroupId = "group.my.ssdid.drive.desktop"

    private enum Keys {
        static let apiBaseUrl = "api_base_url"
        static let fileMetadataCache = "file_metadata_cache"
        static let lastSyncTime = "last_sync_time"
        static let pendingCryptoRequests = "pending_crypto_requests"
        static let cryptoResponses = "crypto_responses"
        static let userInfo = "user_info"
    }

    // MARK: - Properties

    private let defaults: UserDefaults?

    // MARK: - Initialization

    init() {
        self.defaults = UserDefaults(suiteName: appGroupId)
    }

    // MARK: - API Configuration

    /// Get the API base URL
    var apiBaseUrl: String {
        defaults?.string(forKey: Keys.apiBaseUrl) ?? "https://api.ssdid.my"
    }

    /// Set the API base URL
    func setApiBaseUrl(_ url: String) {
        defaults?.set(url, forKey: Keys.apiBaseUrl)
    }

    // MARK: - User Info

    /// Get current user info
    func getUserInfo() -> UserInfo? {
        guard let data = defaults?.data(forKey: Keys.userInfo),
              let info = try? JSONDecoder().decode(UserInfo.self, from: data) else {
            return nil
        }
        return info
    }

    /// Set current user info
    func setUserInfo(_ info: UserInfo) {
        guard let data = try? JSONEncoder().encode(info) else {
            return
        }
        defaults?.set(data, forKey: Keys.userInfo)
    }

    /// Clear user info (on logout)
    func clearUserInfo() {
        defaults?.removeObject(forKey: Keys.userInfo)
    }

    // MARK: - File Metadata Cache

    /// Get cached file metadata
    func getCachedFileMetadata(fileId: String) -> FileProviderItem? {
        guard let cache = defaults?.dictionary(forKey: Keys.fileMetadataCache),
              let data = cache[fileId] as? Data else {
            return nil
        }
        return FileProviderItem.from(cachedData: data)
    }

    /// Cache file metadata
    func cacheFileMetadata(_ item: FileProviderItem) {
        var cache = defaults?.dictionary(forKey: Keys.fileMetadataCache) ?? [:]

        if let data = item.toCacheData() {
            cache[item.id] = data
        }

        defaults?.set(cache, forKey: Keys.fileMetadataCache)
    }

    /// Cache multiple file metadata items
    func cacheFileMetadata(_ items: [FileProviderItem]) {
        var cache = defaults?.dictionary(forKey: Keys.fileMetadataCache) ?? [:]

        for item in items {
            if let data = item.toCacheData() {
                cache[item.id] = data
            }
        }

        defaults?.set(cache, forKey: Keys.fileMetadataCache)
    }

    /// Remove cached file metadata
    func removeCachedFileMetadata(fileId: String) {
        var cache = defaults?.dictionary(forKey: Keys.fileMetadataCache) ?? [:]
        cache.removeValue(forKey: fileId)
        defaults?.set(cache, forKey: Keys.fileMetadataCache)
    }

    /// Clear all cached file metadata
    func clearFileMetadataCache() {
        defaults?.removeObject(forKey: Keys.fileMetadataCache)
    }

    // MARK: - Sync Time

    /// Get the last sync time
    var lastSyncTime: Date? {
        defaults?.object(forKey: Keys.lastSyncTime) as? Date
    }

    /// Update the last sync time
    func updateLastSyncTime() {
        defaults?.set(Date(), forKey: Keys.lastSyncTime)
    }

    // MARK: - Crypto IPC

    /// Write a crypto request for the main app to process
    func writeCryptoRequest(_ request: CryptoRequest) throws {
        var requests = getPendingCryptoRequests()
        requests[request.id] = request

        let data = try JSONEncoder().encode(requests)
        defaults?.set(data, forKey: Keys.pendingCryptoRequests)
    }

    /// Get all pending crypto requests
    func getPendingCryptoRequests() -> [String: CryptoRequest] {
        guard let data = defaults?.data(forKey: Keys.pendingCryptoRequests),
              let requests = try? JSONDecoder().decode([String: CryptoRequest].self, from: data) else {
            return [:]
        }
        return requests
    }

    /// Clear a specific crypto request
    func clearCryptoRequest(requestId: String) {
        var requests = getPendingCryptoRequests()
        requests.removeValue(forKey: requestId)

        if let data = try? JSONEncoder().encode(requests) {
            defaults?.set(data, forKey: Keys.pendingCryptoRequests)
        }
    }

    /// Write a crypto response (called by main app)
    func writeCryptoResponse(_ response: CryptoResponse) throws {
        var responses = getAllCryptoResponses()
        responses[response.requestId] = response

        let data = try JSONEncoder().encode(responses)
        defaults?.set(data, forKey: Keys.cryptoResponses)
    }

    /// Read a crypto response
    func readCryptoResponse(requestId: String) -> CryptoResponse? {
        let responses = getAllCryptoResponses()
        return responses[requestId]
    }

    /// Get all crypto responses
    private func getAllCryptoResponses() -> [String: CryptoResponse] {
        guard let data = defaults?.data(forKey: Keys.cryptoResponses),
              let responses = try? JSONDecoder().decode([String: CryptoResponse].self, from: data) else {
            return [:]
        }
        return responses
    }

    /// Clear a specific crypto response
    func clearCryptoResponse(requestId: String) {
        var responses = getAllCryptoResponses()
        responses.removeValue(forKey: requestId)

        if let data = try? JSONEncoder().encode(responses) {
            defaults?.set(data, forKey: Keys.cryptoResponses)
        }
    }

    // MARK: - Clear All

    /// Clear all shared data (on logout)
    func clearAll() {
        clearFileMetadataCache()
        clearUserInfo()
        defaults?.removeObject(forKey: Keys.lastSyncTime)
        defaults?.removeObject(forKey: Keys.pendingCryptoRequests)
        defaults?.removeObject(forKey: Keys.cryptoResponses)
    }
}

// MARK: - User Info Model

struct UserInfo: Codable {
    let id: String
    let email: String
    let name: String
    let storageUsed: Int64
    let storageLimit: Int64
}
