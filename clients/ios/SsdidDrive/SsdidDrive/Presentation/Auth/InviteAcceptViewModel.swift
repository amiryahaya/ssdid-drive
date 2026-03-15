import Foundation
import Combine

/// Delegate for invite accept view model coordinator events
protocol InviteAcceptViewModelCoordinatorDelegate: AnyObject {
    func inviteAcceptViewModelDidRegister()
    func inviteAcceptViewModelDidRequestLogin()
    func inviteAcceptViewModelDidRequestEmailRegister(token: String)
    func inviteAcceptViewModelDidRequestOidc(provider: String, token: String)
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
    @Published var isAcceptingAsExisting = false
    @Published var acceptError: String?
    @Published var registrationError: String?

    // MARK: - Properties

    private let authRepository: AuthRepository
    let token: String
    weak var coordinatorDelegate: InviteAcceptViewModelCoordinatorDelegate?

    private var loadTask: Task<Void, Never>?
    private var acceptTask: Task<Void, Never>?
    private var callbackTask: Task<Void, Never>?

    deinit {
        loadTask?.cancel()
        acceptTask?.cancel()
        callbackTask?.cancel()
    }

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
        loadTask?.cancel()
        isLoadingInvitation = true
        invitationError = nil

        loadTask = Task { [weak self] in
            guard let self else { return }
            do {
                let info = try await authRepository.getInvitationInfo(token: token)
                guard !Task.isCancelled else { return }
                self.invitation = info
                self.isLoadingInvitation = false

                if !info.valid {
                    self.invitationError = info.errorReason?.displayMessage ?? "This invitation is no longer valid"
                }
            } catch {
                guard !Task.isCancelled else { return }
                self.isLoadingInvitation = false
                self.invitationError = error.localizedDescription
            }
        }
    }

    func acceptWithWallet() {
        guard !isWaitingForWallet, !isLoading else { return }
        isLoading = true
        registrationError = nil

        acceptTask?.cancel()
        acceptTask = Task { [weak self] in
            guard let self else { return }
            do {
                try await authRepository.launchWalletInvite(token: token)
                guard !Task.isCancelled else { return }
                isWaitingForWallet = true
                isLoading = false
            } catch {
                guard !Task.isCancelled else { return }
                isLoading = false
                registrationError = error.localizedDescription
            }
        }
    }

    func handleWalletCallback(sessionToken: String) {
        guard isWaitingForWallet, callbackTask == nil else { return }
        callbackTask = Task { [weak self] in
            guard let self else { return }
            do {
                try await authRepository.saveSessionFromWallet(sessionToken: sessionToken)
                guard !Task.isCancelled else { return }
                isWaitingForWallet = false
                coordinatorDelegate?.inviteAcceptViewModelDidRegister()
            } catch {
                guard !Task.isCancelled else { return }
                isWaitingForWallet = false
                registrationError = error.localizedDescription
            }
        }
    }

    func handleWalletError(message: String) {
        isWaitingForWallet = false
        registrationError = message
    }

    /// Accept the invitation as an already-authenticated user.
    /// Uses the invitation token to accept without re-registration.
    func acceptAsExistingUser() {
        guard invitation != nil else { return }
        isAcceptingAsExisting = true
        acceptError = nil

        acceptTask?.cancel()
        acceptTask = Task { [weak self] in
            guard let self else { return }
            do {
                try await authRepository.acceptInvitationAsExistingUser(token: token)
                guard !Task.isCancelled else { return }
                self.isAcceptingAsExisting = false
                self.coordinatorDelegate?.inviteAcceptViewModelDidRegister()
            } catch {
                guard !Task.isCancelled else { return }
                self.isAcceptingAsExisting = false
                self.acceptError = error.localizedDescription
            }
        }
    }

    /// Handle OIDC authentication result for invitation acceptance.
    /// Registers a new user via OIDC provider and accepts the invitation in one step.
    func handleOidcResult(provider: String, idToken: String) {
        isLoading = true
        errorMessage = nil

        acceptTask?.cancel()
        acceptTask = Task { [weak self] in
            guard let self else { return }
            do {
                try await authRepository.acceptInvitationWithOidc(
                    token: token,
                    provider: provider,
                    idToken: idToken
                )
                guard !Task.isCancelled else { return }
                self.isLoading = false
                self.coordinatorDelegate?.inviteAcceptViewModelDidRegister()
            } catch {
                guard !Task.isCancelled else { return }
                self.isLoading = false
                self.handleError(error)
            }
        }
    }

    func requestLogin() {
        coordinatorDelegate?.inviteAcceptViewModelDidRequestLogin()
    }

    func requestEmailRegister() {
        coordinatorDelegate?.inviteAcceptViewModelDidRequestEmailRegister(token: token)
    }

    func requestOidc(provider: String) {
        coordinatorDelegate?.inviteAcceptViewModelDidRequestOidc(provider: provider, token: token)
    }
}
