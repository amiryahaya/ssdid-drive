import Foundation

/// Represents a registered device
struct Device: Codable, Identifiable, Equatable, Hashable {
    let id: String
    let name: String
    let platform: String
    let publicKey: Data
    let userId: String
    let isRevoked: Bool
    let lastActiveAt: Date?
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case platform
        case publicKey = "public_key"
        case userId = "user_id"
        case isRevoked = "is_revoked"
        case lastActiveAt = "last_active_at"
        case createdAt = "created_at"
    }

    /// Icon name for the platform
    var platformIcon: String {
        switch platform.lowercased() {
        case "ios": return "iphone"
        case "android": return "flipphone"
        case "web": return "globe"
        case "macos": return "laptopcomputer"
        case "windows": return "pc"
        default: return "desktopcomputer"
        }
    }

    /// Is this the current device
    func isCurrent(deviceId: String?) -> Bool {
        id == deviceId
    }
}

/// Device enrollment request
struct DeviceEnrollRequest: Codable {
    let name: String
    let platform: String
    let publicKey: Data

    enum CodingKeys: String, CodingKey {
        case name
        case platform
        case publicKey = "public_key"
    }
}

/// Device enrollment response
struct DeviceEnrollResponse: Codable {
    let device: Device
}
