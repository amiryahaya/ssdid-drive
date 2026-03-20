import Foundation
import Combine
import CryptoKit

/// Step in the recovery setup wizard
enum RecoverySetupStep {
    case explanation
    case generating
    case download
    case uploading
    case success
    case error(String)
}

/// Delegate for recovery setup view model coordinator events
protocol RecoverySetupViewModelCoordinatorDelegate: AnyObject {
    func recoverySetupDidComplete()
    func recoverySetupDidCancel()
    func recoverySetupDidRequestTrusteeSelection(totalShares: Int, masterKey: Data)
}

/// View model for recovery setup wizard.
/// Guides the user through generating 3 Shamir shares (2 downloaded as files,
/// 1 uploaded to the server), then uploading the server share.
@MainActor
final class RecoverySetupViewModel: BaseViewModel {

    // MARK: - Properties

    private let recoveryRepository: RecoveryRepository
    weak var coordinatorDelegate: RecoverySetupViewModelCoordinatorDelegate?

    @Published var step: RecoverySetupStep = .explanation
    @Published var selfFileContent: String?
    @Published var trustedFileContent: String?
    @Published var selfSaved = false
    @Published var trustedSaved = false

    private var serverShare: String?
    private var keyProof: String?

    // MARK: - Initialization

    init(recoveryRepository: RecoveryRepository) {
        self.recoveryRepository = recoveryRepository
        super.init()
    }

    // MARK: - Actions

    func beginSetup() {
        step = .generating
    }

    /// Generate 3 Shamir shares from the master key.
    /// Shares 0 and 1 are presented for download; share 2 is held for server upload.
    func generateShares(masterKey: Data, userDid: String, kemPublicKey: Data) {
        step = .generating
        Task {
            do {
                let shares = try ShamirSecretSharing.split(
                    secret: masterKey,
                    threshold: 2,
                    totalShares: 3
                )

                let file1 = RecoveryFile.create(share: shares[0], userDid: userDid, kemPublicKey: kemPublicKey)
                let file2 = RecoveryFile.create(share: shares[1], userDid: userDid, kemPublicKey: kemPublicKey)

                // Server share is share index 2 (serialized, base64 encoded)
                serverShare = shares[2].serialize().base64EncodedString()

                // Compute key_proof: SHA3-256 of the KEM public key as hex
                let hash = SHA3_256.hash(data: kemPublicKey)
                keyProof = hash.map { String(format: "%02x", $0) }.joined()

                let encoder = JSONEncoder()
                encoder.outputFormatting = .prettyPrinted

                selfFileContent = String(data: try encoder.encode(file1), encoding: .utf8)
                trustedFileContent = String(data: try encoder.encode(file2), encoding: .utf8)

                step = .download
            } catch {
                step = .error(error.localizedDescription)
            }
        }
    }

    func markSelfSaved() {
        selfSaved = true
    }

    func markTrustedSaved() {
        trustedSaved = true
    }

    var canProceed: Bool {
        selfSaved && trustedSaved
    }

    func uploadServerShare() {
        guard let serverShare, let keyProof else { return }
        step = .uploading
        Task {
            do {
                try await recoveryRepository.setupRecovery(
                    serverShare: serverShare,
                    keyProof: keyProof
                )
                step = .success
            } catch {
                step = .error(error.localizedDescription)
            }
        }
    }

    func cancel() {
        coordinatorDelegate?.recoverySetupDidCancel()
    }

    func done() {
        coordinatorDelegate?.recoverySetupDidComplete()
    }
}
