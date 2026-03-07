import Foundation
import Combine

/// Delegate for invite accept view model coordinator events
protocol InviteAcceptViewModelCoordinatorDelegate: AnyObject {
    func inviteAcceptViewModelDidRegister()
    func inviteAcceptViewModelDidRequestLogin()
}

/// View model for invitation acceptance screen
final class InviteAcceptViewModel: BaseViewModel {

    // MARK: - Published Properties

    @Published var invitation: TokenInvitation?
    @Published var isLoadingInvitation = true
    @Published var invitationError: String?

    @Published var displayName = ""
    @Published var password = ""
    @Published var confirmPassword = ""

    @Published var isRegistering = false
    @Published var isGeneratingKeys = false
    @Published var registrationError: String?

    // MARK: - Properties

    private let authRepository: AuthRepository
    private let token: String
    weak var coordinatorDelegate: InviteAcceptViewModelCoordinatorDelegate?

    // MARK: - Computed Properties

    var isFormValid: Bool {
        !displayName.isEmpty &&
        displayName.count <= 100 &&
        password.count >= 8 &&
        password == confirmPassword
    }

    var email: String {
        invitation?.email ?? ""
    }

    // MARK: - Initialization

    init(authRepository: AuthRepository, token: String) {
        self.authRepository = authRepository
        self.token = token
        super.init()

        loadInvitationInfo()
    }

    // MARK: - Actions

    func loadInvitationInfo() {
        isLoadingInvitation = true
        invitationError = nil

        Task {
            do {
                let info = try await authRepository.getInvitationInfo(token: token)
                await MainActor.run {
                    self.invitation = info
                    self.isLoadingInvitation = false

                    if !info.valid {
                        self.invitationError = info.errorReason?.displayMessage ?? "This invitation is no longer valid"
                    }
                }
            } catch {
                await MainActor.run {
                    self.isLoadingInvitation = false
                    self.invitationError = error.localizedDescription
                }
            }
        }
    }

    func acceptInvitation() {
        guard isFormValid else {
            if displayName.isEmpty {
                registrationError = "Name is required"
            } else if displayName.count > 100 {
                registrationError = "Name is too long"
            } else if password.count < 8 {
                registrationError = "Password must be at least 8 characters"
            } else if password != confirmPassword {
                registrationError = "Passwords do not match"
            }
            return
        }

        registrationError = nil
        isRegistering = true
        isGeneratingKeys = true

        Task {
            do {
                _ = try await authRepository.acceptInvitation(
                    token: token,
                    displayName: displayName,
                    password: password
                )

                await MainActor.run {
                    self.isRegistering = false
                    self.isGeneratingKeys = false
                    self.password = ""
                    self.confirmPassword = ""
                    self.coordinatorDelegate?.inviteAcceptViewModelDidRegister()
                }
            } catch {
                await MainActor.run {
                    self.isRegistering = false
                    self.isGeneratingKeys = false
                    self.registrationError = error.localizedDescription
                }
            }
        }
    }

    func requestLogin() {
        coordinatorDelegate?.inviteAcceptViewModelDidRequestLogin()
    }
}
