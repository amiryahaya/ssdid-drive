import Foundation
import AuthenticationServices
import Combine

/// Delegate for passkey login coordinator events
protocol PasskeyLoginViewModelDelegate: AnyObject {
    func passkeyLoginDidComplete()
}

/// View model for WebAuthn/Passkey login flow using ASAuthorization
final class PasskeyLoginViewModel: BaseViewModel {

    // MARK: - Properties

    private let webAuthnRepository: WebAuthnRepository
    weak var delegate: PasskeyLoginViewModelDelegate?
    private var pendingChallengeId: String?

    // MARK: - Initialization

    init(webAuthnRepository: WebAuthnRepository) {
        self.webAuthnRepository = webAuthnRepository
        super.init()
    }

    // MARK: - Actions

    func beginLogin(email: String?, presentationAnchor: ASPresentationAnchor) {
        isLoading = true
        clearError()

        Task {
            do {
                let result = try await webAuthnRepository.loginBegin(email: email)
                self.pendingChallengeId = result.challengeId

                await MainActor.run {
                    self.startPasskeyAssertion(
                        optionsJson: result.optionsJson,
                        presentationAnchor: presentationAnchor
                    )
                }
            } catch {
                await MainActor.run {
                    self.handleError(error)
                }
            }
        }
    }

    // MARK: - Private

    private func startPasskeyAssertion(optionsJson: String, presentationAnchor: ASPresentationAnchor) {
        guard let optionsData = optionsJson.data(using: .utf8),
              let options = try? JSONSerialization.jsonObject(with: optionsData) as? [String: Any] else {
            handleError(AuthError.invalidCredentials)
            return
        }

        // Extract challenge and relying party from options
        guard let challengeB64 = options["challenge"] as? String,
              let challengeData = Data(base64Encoded: challengeB64),
              let rpId = (options["rpId"] as? String) ?? (options["rp"] as? [String: Any])?["id"] as? String else {
            handleError(AuthError.invalidCredentials)
            return
        }

        let provider = ASAuthorizationPlatformPublicKeyCredentialProvider(relyingPartyIdentifier: rpId)
        let assertionRequest = provider.createCredentialAssertionRequest(challenge: challengeData)

        // Extract allowCredentials if present
        if let allowCredentials = options["allowCredentials"] as? [[String: Any]] {
            assertionRequest.allowedCredentials = allowCredentials.compactMap { cred in
                guard let idB64 = cred["id"] as? String,
                      let idData = Data(base64Encoded: idB64) else { return nil }
                return ASAuthorizationPlatformPublicKeyCredentialDescriptor(credentialID: idData)
            }
        }

        let authController = ASAuthorizationController(authorizationRequests: [assertionRequest])
        let delegate = PasskeyAuthDelegate { [weak self] result in
            self?.handlePasskeyResult(result)
        }
        authController.delegate = delegate

        let contextProvider = PasskeyContextProvider(anchor: presentationAnchor)
        authController.presentationContextProvider = contextProvider

        // Keep strong references
        objc_setAssociatedObject(authController, "delegate", delegate, .OBJC_ASSOCIATION_RETAIN)
        objc_setAssociatedObject(authController, "context", contextProvider, .OBJC_ASSOCIATION_RETAIN)

        authController.performRequests()
    }

    private func handlePasskeyResult(_ result: Result<ASAuthorization, Error>) {
        switch result {
        case .success(let authorization):
            guard let credential = authorization.credential as? ASAuthorizationPlatformPublicKeyCredentialAssertion else {
                Task { @MainActor in self.handleError(AuthError.invalidCredentials) }
                return
            }

            guard let challengeId = pendingChallengeId else {
                Task { @MainActor in self.handleError(AuthError.invalidCredentials) }
                return
            }

            // Build assertion data
            let assertionData: [String: Any] = [
                "id": credential.credentialID.base64EncodedString(),
                "rawId": credential.credentialID.base64EncodedString(),
                "type": "public-key",
                "response": [
                    "authenticatorData": credential.rawAuthenticatorData.base64EncodedString(),
                    "clientDataJSON": credential.rawClientDataJSON.base64EncodedString(),
                    "signature": credential.signature.base64EncodedString()
                ]
            ]

            completeLogin(challengeId: challengeId, assertionData: assertionData)

        case .failure(let error):
            Task { @MainActor in
                if (error as NSError).code == ASAuthorizationError.canceled.rawValue {
                    self.isLoading = false
                } else {
                    self.handleError(error)
                }
            }
        }
    }

    private func completeLogin(challengeId: String, assertionData: [String: Any]) {
        Task {
            do {
                _ = try await webAuthnRepository.loginComplete(
                    challengeId: challengeId,
                    assertionData: assertionData
                )

                await MainActor.run {
                    self.isLoading = false
                    self.delegate?.passkeyLoginDidComplete()
                }
            } catch {
                await MainActor.run {
                    self.handleError(error)
                }
            }
        }
    }
}

// MARK: - ASAuthorization Delegate Wrapper

private class PasskeyAuthDelegate: NSObject, ASAuthorizationControllerDelegate {
    let completion: (Result<ASAuthorization, Error>) -> Void

    init(completion: @escaping (Result<ASAuthorization, Error>) -> Void) {
        self.completion = completion
    }

    func authorizationController(controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization) {
        completion(.success(authorization))
    }

    func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
        completion(.failure(error))
    }
}

private class PasskeyContextProvider: NSObject, ASAuthorizationControllerPresentationContextProviding {
    let anchor: ASPresentationAnchor

    init(anchor: ASPresentationAnchor) {
        self.anchor = anchor
    }

    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        return anchor
    }
}
