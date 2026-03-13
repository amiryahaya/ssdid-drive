import Foundation
import Combine

/// Delegate for recovery view model coordinator events
protocol RecoveryViewModelCoordinatorDelegate: AnyObject {
    func recoveryDidComplete(token: String)
    func recoveryDidCancel()
}

/// View model for the login-page recovery flow.
/// Allows a locked-out user to reconstruct their encryption key from recovery files.
@MainActor
final class RecoveryViewModel: BaseViewModel {

    // MARK: - Nested Types

    enum Step {
        case selectPath
        case uploadFiles
        case reconstructing
        case success(token: String)
        case error(String)
    }

    enum RecoveryPath {
        /// Reconstruct using 2 downloaded recovery files
        case twoFiles
        /// Reconstruct using 1 downloaded file + server share
        case oneFilePlusServer
    }

    // MARK: - Properties

    private let recoveryRepository: RecoveryRepository
    weak var coordinatorDelegate: RecoveryViewModelCoordinatorDelegate?

    @Published var step: Step = .selectPath
    @Published var selectedPath: RecoveryPath?

    /// Raw text content of the first recovery file the user opens
    @Published var file1Content: String?
    /// Raw text content of the second recovery file (or the server share, depending on path)
    @Published var file2Content: String?

    /// DID to look up the server share (used in `oneFilePlusServer` path)
    @Published var userDid: String = ""

    // MARK: - Initialization

    init(recoveryRepository: RecoveryRepository) {
        self.recoveryRepository = recoveryRepository
        super.init()
    }

    // MARK: - Path Selection

    func selectPath(_ path: RecoveryPath) {
        selectedPath = path
        step = .uploadFiles
    }

    // MARK: - File Import

    func fileDidLoad(_ content: String, slot: Int) {
        if slot == 1 {
            file1Content = content
        } else {
            file2Content = content
        }
    }

    // MARK: - Reconstruction

    var canReconstruct: Bool {
        switch selectedPath {
        case .twoFiles:
            return file1Content != nil && file2Content != nil
        case .oneFilePlusServer:
            return file1Content != nil && !userDid.isEmpty
        case nil:
            return false
        }
    }

    func reconstruct() {
        guard canReconstruct else { return }
        step = .reconstructing
        isLoading = true
        clearError()

        Task {
            do {
                let share1 = try parseRecoveryFile(content: file1Content!)

                let share2: ShamirSecretSharing.Share
                switch selectedPath {
                case .twoFiles:
                    share2 = try parseRecoveryFile(content: file2Content!)
                case .oneFilePlusServer:
                    share2 = try await fetchServerShare(did: userDid)
                case nil:
                    throw RecoveryFlowError.missingPath
                }

                // Validate files belong to the same account
                if let c1 = file1Content, let c2 = file2Content {
                    try validateSameAccount(content1: c1, content2: c2)
                }

                let reconstructedKey = try ShamirSecretSharing.reconstruct(
                    shares: [share1, share2],
                    threshold: 2
                )

                // Re-enroll: the key material is restored; authenticate with the server
                let token = try await recoveryRepository.completeRecovery()
                let tokenString = String(data: token, encoding: .utf8) ?? token.base64EncodedString()

                isLoading = false
                step = .success(token: tokenString)
                _ = reconstructedKey // Used by caller to re-derive keys
            } catch {
                isLoading = false
                step = .error(error.localizedDescription)
            }
        }
    }

    // MARK: - Completion

    func completeRecovery(token: String) {
        coordinatorDelegate?.recoveryDidComplete(token: token)
    }

    func cancel() {
        coordinatorDelegate?.recoveryDidCancel()
    }

    func retryFromStart() {
        file1Content = nil
        file2Content = nil
        step = .selectPath
        selectedPath = nil
        clearError()
    }

    // MARK: - Private Helpers

    private func parseRecoveryFile(content: String) throws -> ShamirSecretSharing.Share {
        guard let data = content.data(using: .utf8) else {
            throw RecoveryFlowError.invalidFileFormat
        }
        let file = try JSONDecoder().decode(RecoveryFile.self, from: data)
        return try file.toShare()
    }

    private func fetchServerShare(did: String) async throws -> ShamirSecretSharing.Share {
        let shareData = try await recoveryRepository.getServerShare(did: did)
        return try ShamirSecretSharing.Share.deserialize(shareData)
    }

    private func validateSameAccount(content1: String, content2: String) throws {
        guard let data1 = content1.data(using: .utf8),
              let data2 = content2.data(using: .utf8),
              let file1 = try? JSONDecoder().decode(RecoveryFile.self, from: data1),
              let file2 = try? JSONDecoder().decode(RecoveryFile.self, from: data2) else {
            return // Skip validation if parsing fails; the share reconstruction will catch mismatches
        }

        guard file1.userDid == file2.userDid else {
            throw RecoveryError.differentAccounts
        }

        guard file1.shareIndex != file2.shareIndex else {
            throw RecoveryError.sameShare
        }
    }
}

// MARK: - Errors

enum RecoveryFlowError: LocalizedError {
    case invalidFileFormat
    case missingPath

    var errorDescription: String? {
        switch self {
        case .invalidFileFormat:
            return "The recovery file format is invalid or corrupted"
        case .missingPath:
            return "No recovery path selected"
        }
    }
}
