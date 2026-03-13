import Foundation
import Combine

/// Delegate for invite accept view model coordinator events
protocol InviteAcceptViewModelCoordinatorDelegate: AnyObject {
    func inviteAcceptViewModelDidRegister()
    func inviteAcceptViewModelDidRequestLogin()
}

/// View model for invitation acceptance screen.
/// Uses wallet-based flow: loads invitation info, launches SSDID Wallet,
/// and handles the wallet callback with a session token.
@MainActor
final class InviteAcceptViewModel: BaseViewModel {

    // MARK: - Published Properties

    @Published var invitation: TokenInvitation?
    @Published var isLoadingInvitation = true
    @Published var invitationError: String?
    @Published var isWaitingForWallet = false
    @Published var registrationError: String?

    // MARK: - Properties

    private let authRepository: AuthRepository
    private let token: String
    weak var coordinatorDelegate: InviteAcceptViewModelCoordinatorDelegate?

    // MARK: - Computed Properties

    var email: String { invitation?.email ?? "" }

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
                self.invitation = info
                self.isLoadingInvitation = false

                if !info.valid {
                    self.invitationError = info.errorReason?.displayMessage ?? "This invitation is no longer valid"
                }
            } catch {
                self.isLoadingInvitation = false
                self.invitationError = error.localizedDescription
            }
        }
    }

    func acceptWithWallet() {
        guard !isWaitingForWallet else { return }
        registrationError = nil

        Task {
            do {
                isLoading = true
                try await authRepository.launchWalletInvite(token: token)
                isLoading = false
                isWaitingForWallet = true
            } catch {
                isLoading = false
                registrationError = error.localizedDescription
            }
        }
    }

    func handleWalletCallback(sessionToken: String) {
        Task {
            do {
                try await authRepository.saveSessionFromWallet(sessionToken: sessionToken)
                isWaitingForWallet = false
                coordinatorDelegate?.inviteAcceptViewModelDidRegister()
            } catch {
                isWaitingForWallet = false
                registrationError = error.localizedDescription
            }
        }
    }

    func handleWalletError(message: String) {
        isWaitingForWallet = false
        registrationError = message
    }

    func requestLogin() {
        coordinatorDelegate?.inviteAcceptViewModelDidRequestLogin()
    }
}
