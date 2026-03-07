import Foundation

/// Application-wide constants
enum Constants {

    // MARK: - API Configuration

    enum API {
        #if DEBUG
        static let baseURL = "https://api-dev.ssdid-drive.app"
        #else
        static let baseURL = "https://api.ssdid-drive.app"
        #endif

        static let apiVersion = "v1"
        static let timeout: TimeInterval = 30

        static var fullBaseURL: String {
            "\(baseURL)/\(apiVersion)"
        }

        /// PII Service URL (separate microservice for PII detection)
        #if DEBUG
        static let piiServiceURL = "http://localhost:4001/api/v1"
        #else
        static let piiServiceURL = "https://pii.ssdid-drive.app/api/v1"
        #endif

        // Endpoints
        enum Endpoints {
            // Auth
            static let login = "/auth/login"
            static let register = "/auth/register"
            static let refreshToken = "/auth/refresh"
            static let logout = "/auth/logout"
            static let me = "/auth/me"

            // Devices
            static let devices = "/devices"
            static let enrollDevice = "/devices/enroll"
            static let revokeDevice = "/devices/{id}/revoke"

            // Files
            static let files = "/files"
            static let fileById = "/files/{id}"
            static let downloadFile = "/files/{id}/download"
            static let uploadFile = "/files/upload"

            // Folders
            static let folders = "/folders"
            static let folderById = "/folders/{id}"
            static let folderContents = "/folders/{id}/contents"

            // Shares
            static let shareFile = "/shares/file"
            static let shareFolder = "/shares/folder"
            static let shareById = "/shares/{id}"
            static let receivedShares = "/shares/received"
            static let createdShares = "/shares/created"
            static let sharePermission = "/shares/{id}/permission"
            static let shareExpiry = "/shares/{id}/expiry"
            static let shareInvitations = "/shares/invitations"

            // Recovery
            static let recoveryConfig = "/recovery/config"
            static let setupRecovery = "/recovery/setup"
            static let recoveryShares = "/recovery/shares"
            static let pendingRequests = "/recovery/requests/pending"
            static let initiateRecovery = "/recovery/initiate"
            static let approveRecovery = "/recovery/requests/{id}/approve"
            static let rejectRecovery = "/recovery/requests/{id}/reject"

            // WebAuthn
            static let webauthnRegisterBegin = "/auth/webauthn/register/begin"
            static let webauthnRegisterComplete = "/auth/webauthn/register/complete"
            static let webauthnLoginBegin = "/auth/webauthn/login/begin"
            static let webauthnLoginComplete = "/auth/webauthn/login/complete"
            static let webauthnCredentialBegin = "/auth/webauthn/credentials/begin"
            static let webauthnCredentialComplete = "/auth/webauthn/credentials/complete"

            // OIDC
            static let oidcAuthorize = "/auth/oidc/authorize"
            static let oidcCallback = "/auth/oidc/callback"
            static let oidcRegister = "/auth/oidc/register"

            // Providers & Credentials
            static let authProviders = "/auth/providers"
            static let authCredentials = "/auth/credentials"

            // Users
            static let searchUsers = "/users/search"
            static let userById = "/users/{id}"

            // Invitation Token (Public - Unauthenticated)
            static let inviteInfo = "/invite/{token}"
            static let acceptInvite = "/invite/{token}/accept"

            // Tenants
            static let tenants = "/tenants"
            static let switchTenant = "/tenant/switch"
            static let tenantConfig = "/tenant/config"
            static let leaveTenant = "/tenants/{id}/leave"
        }

        // Headers
        enum Headers {
            static let authorization = "Authorization"
            static let contentType = "Content-Type"
            static let accept = "Accept"
            static let tenantId = "X-Tenant-ID"
            static let deviceId = "X-Device-ID"
            static let deviceSignature = "X-Device-Signature"
            static let timestamp = "X-Timestamp"
        }

        /// SSL Certificate Pinning - SHA-256 hashes of server public keys (base64 encoded)
        ///
        /// To generate certificate hash for your production server, run:
        /// ```
        /// echo | openssl s_client -connect YOUR_DOMAIN:443 2>/dev/null | \
        ///   openssl x509 -pubkey -noout | \
        ///   openssl pkey -pubin -outform der | \
        ///   openssl dgst -sha256 -binary | base64
        /// ```
        ///
        /// Example for api.ssdid-drive.app:
        /// ```
        /// echo | openssl s_client -connect api.ssdid-drive.app:443 2>/dev/null | \
        ///   openssl x509 -pubkey -noout | \
        ///   openssl pkey -pubin -outform der | \
        ///   openssl dgst -sha256 -binary | base64
        /// ```
        ///
        /// IMPORTANT: Always include at least 2 hashes (primary + backup) for certificate rotation.
        /// Empty array disables pinning (NOT RECOMMENDED for production).
        ///
        #if DEBUG
        /// Pinning disabled in debug builds for localhost development
        static let pinnedCertificateHashes: [String] = []
        #else
        /// SECURITY: SSL pinning certificate hashes for production
        /// CRITICAL: Replace these placeholder hashes with actual production certificate hashes before App Store release!
        ///
        /// The app will fail to start in production if these remain as placeholders.
        /// Generate hashes using the openssl command documented above.
        static let pinnedCertificateHashes: [String] = [
            // Primary certificate hash (leaf certificate)
            // TODO: Replace with actual hash before release
            "REPLACE_WITH_PRIMARY_CERTIFICATE_HASH_BASE64",

            // Backup certificate hash (intermediate CA or next certificate for rotation)
            // TODO: Replace with actual hash before release
            "REPLACE_WITH_BACKUP_CERTIFICATE_HASH_BASE64"
        ]
        #endif

        /// Check if SSL pinning is properly configured for production
        /// Returns false if using placeholder values or empty array
        static var isSSLPinningConfigured: Bool {
            #if DEBUG
            return true // Pinning is intentionally disabled in debug
            #else
            // Check that we have hashes and they're not placeholder values
            guard !pinnedCertificateHashes.isEmpty else { return false }
            let placeholders = ["REPLACE_WITH_PRIMARY_CERTIFICATE_HASH_BASE64", "REPLACE_WITH_BACKUP_CERTIFICATE_HASH_BASE64"]
            return !pinnedCertificateHashes.allSatisfy { placeholders.contains($0) }
            #endif
        }
    }

    // MARK: - Crypto Configuration

    enum Crypto {
        // KAZ-KEM key sizes (bytes)
        static let kazKemPublicKeySize = 236
        static let kazKemPrivateKeySize = 86
        static let kazKemCiphertextSize = 236
        static let kazKemSharedSecretSize = 32

        // ML-KEM-768 key sizes (bytes)
        static let mlKemPublicKeySize = 1184
        static let mlKemPrivateKeySize = 2400
        static let mlKemCiphertextSize = 1088
        static let mlKemSharedSecretSize = 32

        // KAZ-SIGN key sizes (bytes)
        static let kazSignPublicKeySize = 2144
        static let kazSignPrivateKeySize = 4512
        static let kazSignSignatureSize = 4595

        // ML-DSA-65 key sizes (bytes)
        static let mlDsaPublicKeySize = 1952
        static let mlDsaPrivateKeySize = 4032
        static let mlDsaSignatureSize = 3309

        // AES-256-GCM
        static let aesKeySize = 32
        static let aesNonceSize = 12
        static let aesTagSize = 16

        // Key derivation
        static let masterKeySize = 32
        static let saltSize = 16
        static let pbkdf2Iterations = 100_000
    }

    // MARK: - Keychain

    enum Keychain {
        static let serviceName = "my.ssdid.drive.ios"
        static var accessGroup: String? {
            guard let teamId = Bundle.main.infoDictionary?["AppIdentifierPrefix"] as? String else { return nil }
            return "\(teamId)my.ssdid.drive.shared"
        }

        // Keys
        static let accessToken = "access_token"
        static let refreshToken = "refresh_token"
        static let masterKey = "master_key"
        static let encryptedKeys = "encrypted_keys"
        static let deviceId = "device_id"
        static let devicePrivateKey = "device_private_key"
        static let userId = "user_id"
        static let pinHash = "pin_hash"
        static let tenantId = "tenant_id"
        static let currentRole = "current_role"
        static let userTenants = "user_tenants"
        static let tenantTransactionId = "tenant_transaction_id"
        static let tenantTransactionComplete = "tenant_transaction_complete"
    }

    // MARK: - UserDefaults Keys

    enum UserDefaultsKeys {
        static let hasCompletedOnboarding = "has_completed_onboarding"
        static let themeMode = "theme_mode"
        static let biometricEnabled = "biometric_enabled"
        static let autoLockEnabled = "auto_lock_enabled"
        static let autoLockTimeout = "auto_lock_timeout"
        static let notificationsEnabled = "notifications_enabled"
        static let shareNotificationsEnabled = "share_notifications_enabled"
        static let recoveryNotificationsEnabled = "recovery_notifications_enabled"
        static let compactViewEnabled = "compact_view_enabled"
        static let showFileSizes = "show_file_sizes"
        static let favoriteFileIds = "favorite_file_ids"
        static let pendingDeepLink = "pending_deep_link"
    }

    // MARK: - Auto Lock Timeout

    enum AutoLockTimeout: String, CaseIterable, Codable {
        case immediately
        case oneMinute
        case fiveMinutes
        case fifteenMinutes
        case thirtyMinutes
        case never

        var minutes: Int {
            switch self {
            case .immediately: return 0
            case .oneMinute: return 1
            case .fiveMinutes: return 5
            case .fifteenMinutes: return 15
            case .thirtyMinutes: return 30
            case .never: return -1
            }
        }

        var displayName: String {
            switch self {
            case .immediately: return "Immediately"
            case .oneMinute: return "1 minute"
            case .fiveMinutes: return "5 minutes"
            case .fifteenMinutes: return "15 minutes"
            case .thirtyMinutes: return "30 minutes"
            case .never: return "Never"
            }
        }
    }

    // MARK: - Theme Mode

    enum ThemeMode: String, CaseIterable, Codable {
        case light
        case dark
        case system

        var displayName: String {
            switch self {
            case .light: return "Light"
            case .dark: return "Dark"
            case .system: return "System"
            }
        }
    }

    // MARK: - App Info

    enum App {
        static let name = "SsdidDrive"
        static let bundleId = "my.ssdid.drive.ios"

        static var version: String {
            Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        }

        static var build: String {
            Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        }

        static var fullVersion: String {
            "\(version) (\(build))"
        }
    }

    // MARK: - Push Notifications (OneSignal)

    enum OneSignal {
        /// OneSignal App ID - same across all environments
        static let appId = "265f3b98-a29f-405c-b45e-d104b1c9aec0"
    }

    // MARK: - Crash Reporting (Sentry)

    enum Sentry {
        /// Sentry DSN (Data Source Name) for crash reporting
        /// Get this from: https://sentry.io/settings/projects/{project}/keys/
        #if DEBUG
        /// Debug DSN - can be empty to disable in debug builds
        static let dsn = ""
        #else
        /// Production DSN
        static let dsn = "https://f00607f8f70d7603ee05b4b34c506e30@o4507469191380992.ingest.de.sentry.io/4510738302632016"
        #endif

        /// Environment name for Sentry
        #if DEBUG
        static let environment = "development"
        #else
        static let environment = "production"
        #endif

        /// Sample rate for performance monitoring (0.0 to 1.0)
        /// 1.0 = 100% of transactions, 0.2 = 20% of transactions
        static let tracesSampleRate: Double = 0.2

        /// Sample rate for profiling (0.0 to 1.0)
        static let profilesSampleRate: Double = 0.1

        /// SECURITY: Screenshots disabled to prevent capturing sensitive data
        /// (decrypted files, passwords, encryption keys)
        static let attachScreenshot = false

        /// SECURITY: View hierarchy disabled to prevent capturing sensitive UI text
        static let attachViewHierarchy = false

        /// Whether to enable Sentry (can be disabled via remote config later)
        static var isEnabled: Bool {
            !dsn.isEmpty
        }
    }

    // MARK: - UI

    enum UI {
        static let minimumTouchTarget: CGFloat = 44
        static let cornerRadius: CGFloat = 12
        static let spacing: CGFloat = 16
        static let smallSpacing: CGFloat = 8
        static let largeSpacing: CGFloat = 24
    }
}

// MARK: - Notification Names

extension Notification.Name {
    /// Posted when a push notification is tapped
    static let didTapPushNotification = Notification.Name("didTapPushNotification")
    /// Posted when the tenant/organization is switched
    static let tenantDidSwitch = Notification.Name("tenantDidSwitch")

    // MARK: - macOS Menu/Toolbar/Keyboard Shortcut Actions
    static let uploadFileRequested = Notification.Name("uploadFileRequested")
    static let createFolderRequested = Notification.Name("createFolderRequested")
    static let lockAppRequested = Notification.Name("lockAppRequested")
}
