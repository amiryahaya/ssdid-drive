import Foundation
import Combine

/// View model for credential management screen
final class CredentialManagerViewModel: BaseViewModel {

    // MARK: - Published Properties

    @Published var credentials: [UserCredential] = []

    // MARK: - Properties

    private let webAuthnRepository: WebAuthnRepository

    // MARK: - Initialization

    init(webAuthnRepository: WebAuthnRepository) {
        self.webAuthnRepository = webAuthnRepository
        super.init()
        loadCredentials()
    }

    // MARK: - Actions

    func loadCredentials() {
        isLoading = true
        clearError()

        Task {
            do {
                let result = try await webAuthnRepository.getCredentials()
                await MainActor.run {
                    self.credentials = result
                    self.isLoading = false
                }
            } catch {
                await MainActor.run {
                    self.handleError(error)
                }
            }
        }
    }

    func renameCredential(id: String, name: String) {
        Task {
            do {
                let updated = try await webAuthnRepository.renameCredential(credentialId: id, name: name)
                await MainActor.run {
                    if let index = self.credentials.firstIndex(where: { $0.id == id }) {
                        self.credentials[index] = updated
                    }
                }
            } catch {
                await MainActor.run {
                    self.handleError(error)
                }
            }
        }
    }

    func deleteCredential(id: String) {
        Task {
            do {
                try await webAuthnRepository.deleteCredential(credentialId: id)
                await MainActor.run {
                    self.credentials.removeAll { $0.id == id }
                }
            } catch {
                await MainActor.run {
                    self.handleError(error)
                }
            }
        }
    }
}
