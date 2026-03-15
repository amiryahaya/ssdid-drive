# iOS Onboarding UI Improvements — Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Achieve feature parity with Android for enterprise B2B onboarding: multi-auth login (Email+TOTP, OIDC, Wallet), multi-auth invitation acceptance, tenant request submission, and invitation creation polish.

**Architecture:** Extend existing UIKit view controllers (LoginViewController, InviteAcceptViewController) with new UI elements. Add TotpVerifyViewController as new UIKit VC. Add TenantRequestView as SwiftUI modal (matching JoinTenantView pattern). Wire via AuthCoordinator. No architecture changes — all additions follow existing patterns.

**Tech Stack:** Swift 5.9, UIKit (Auto Layout), SwiftUI (modals), Combine, MVVM + Coordinator, XCTest

---

## What Already Exists (Do NOT Rebuild)

- `LoginViewController` + `LoginViewModel` — QR/wallet login (extend, don't replace)
- `InviteAcceptViewController` + `InviteAcceptViewModel` — wallet invitation acceptance (extend)
- `AuthCoordinator` — manages auth flow navigation (extend with new methods)
- `JoinTenantView` + `JoinTenantViewModel` — invite code entry (reuse pattern)
- `CreateInvitationView` + `CreateInvitationViewModel` — invitation creation (enhance)
- `BaseViewModel` — `@Published isLoading`, `errorMessage`, `cancellables`
- `APIClient` — `request(_:method:body:requiresAuth:)` pattern
- Backend: All API endpoints exist (email login, TOTP verify, OIDC, tenant requests)

## File Structure

All paths relative to `clients/ios/SsdidDrive/SsdidDrive/`

| Action | File | Responsibility |
|--------|------|----------------|
| Modify | `Presentation/Auth/LoginViewController.swift` | Add email field, OIDC buttons, org request link |
| Modify | `Presentation/Auth/LoginViewModel.swift` | Add email login, OIDC result handling |
| Create | `Presentation/Auth/TotpVerifyViewController.swift` | 6-digit TOTP input screen |
| Create | `Presentation/Auth/TotpVerifyViewModel.swift` | TOTP verify API call + state |
| Modify | `Presentation/Auth/InviteAcceptViewController.swift` | Add multi-auth buttons |
| Modify | `Presentation/Auth/InviteAcceptViewModel.swift` | Add OIDC + existing-user accept |
| Create | `Presentation/Settings/TenantRequestView.swift` | SwiftUI org request form |
| Create | `Presentation/Settings/TenantRequestViewModel.swift` | Org request state + API |
| Modify | `Presentation/Settings/CreateInvitationView.swift` | Add copy/share, email_sent |
| Modify | `Presentation/Settings/CreateInvitationViewModel.swift` | Read email_sent from response |
| Modify | `Presentation/Coordinators/AuthCoordinator.swift` | Add TOTP + TenantRequest navigation |

---

## Chunk 1: Email Login + TOTP Verify

### Task 1: Add email login to LoginViewModel

**Files:**
- Modify: `Presentation/Auth/LoginViewModel.swift`

- [ ] **Step 1: Read LoginViewModel.swift to understand current structure**

Read the file fully. Note: it inherits from `BaseViewModel`, uses `@Published` properties, and has `SsdidAuthService` for wallet auth.

- [ ] **Step 2: Add email-related published properties**

Add to LoginViewModel:

```swift
@Published var email: String = ""
@Published var navigateToTotp: String? = nil  // set to email when TOTP required
```

- [ ] **Step 3: Add emailLogin method**

Add method that calls the backend email login endpoint:

```swift
func emailLogin() {
    guard !email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
        errorMessage = "Email is required"
        return
    }

    isLoading = true
    errorMessage = nil

    Task {
        do {
            struct EmailLoginRequest: Encodable {
                let email: String
            }
            struct EmailLoginResponse: Decodable {
                let requires_totp: Bool
                let email: String
            }

            let response: EmailLoginResponse = try await apiClient.request(
                "/api/auth/email/login",
                method: .post,
                body: EmailLoginRequest(email: email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()),
                requiresAuth: false
            )

            if response.requires_totp {
                self.navigateToTotp = response.email
            }
            self.isLoading = false
        } catch {
            self.isLoading = false
            self.handleError(error)
        }
    }
}
```

Note: Check if `apiClient` is already accessible in LoginViewModel. If not, inject it via init. The existing pattern injects services via the constructor.

- [ ] **Step 4: Add handleOidcResult method**

```swift
func handleOidcResult(provider: String, idToken: String) {
    isLoading = true
    errorMessage = nil

    Task {
        do {
            struct OidcVerifyRequest: Encodable {
                let provider: String
                let id_token: String
            }

            let _: AuthResponse = try await apiClient.request(
                "/api/auth/oidc/verify",
                method: .post,
                body: OidcVerifyRequest(provider: provider, id_token: idToken),
                requiresAuth: false
            )

            // Save session — check how existing wallet callback saves tokens
            // The response should contain a session token
            self.isLoading = false
            self.isAuthenticated = true
        } catch {
            self.isLoading = false
            self.handleError(error)
        }
    }
}
```

Note: Check the exact auth response type used in the codebase (`AuthResponse` or similar) and how tokens are saved to keychain. Match the pattern used in `handleAuthCallback(sessionToken:)`.

- [ ] **Step 5: Build**

Run: `cd clients/ios && xcodebuild build -project SsdidDrive.xcodeproj -scheme SsdidDrive -destination 'platform=iOS Simulator,name=iPhone 16' -quiet 2>&1 | tail -5`

Or if using XcodeGen: `cd clients/ios/SsdidDrive && xcodegen generate && xcodebuild build -scheme SsdidDrive -destination 'platform=iOS Simulator,name=iPhone 16' -quiet 2>&1 | tail -5`

- [ ] **Step 6: Commit**

```bash
git add clients/ios/
git commit -m "feat(ios): add email login and OIDC methods to LoginViewModel"
```

---

### Task 2: Add email field and auth buttons to LoginViewController

**Files:**
- Modify: `Presentation/Auth/LoginViewController.swift`

- [ ] **Step 1: Read LoginViewController.swift fully**

Understand the exact layout pattern: lazy UI properties, `setupUI()`, `setupConstraints()`, `setupBindings()`, button actions.

- [ ] **Step 2: Add new lazy UI properties**

Add these lazy properties following the existing pattern (with `translatesAutoresizingMaskIntoConstraints = false`):

```swift
// Invite code card
private lazy var inviteCodeCard: UIView = {
    let card = UIView()
    card.translatesAutoresizingMaskIntoConstraints = false
    card.backgroundColor = .systemGray6
    card.layer.cornerRadius = 12
    card.isUserInteractionEnabled = true
    card.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(inviteCodeTapped)))

    let titleLabel = UILabel()
    titleLabel.text = "Have an invite code?"
    titleLabel.font = .systemFont(ofSize: 16, weight: .semibold)
    titleLabel.translatesAutoresizingMaskIntoConstraints = false

    let subtitleLabel = UILabel()
    subtitleLabel.text = "Enter your code to join an organization"
    subtitleLabel.font = .systemFont(ofSize: 13)
    subtitleLabel.textColor = .secondaryLabel
    subtitleLabel.translatesAutoresizingMaskIntoConstraints = false

    let chevron = UIImageView(image: UIImage(systemName: "chevron.right"))
    chevron.tintColor = .systemBlue
    chevron.translatesAutoresizingMaskIntoConstraints = false

    card.addSubview(titleLabel)
    card.addSubview(subtitleLabel)
    card.addSubview(chevron)

    NSLayoutConstraint.activate([
        titleLabel.topAnchor.constraint(equalTo: card.topAnchor, constant: 14),
        titleLabel.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 16),
        subtitleLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 4),
        subtitleLabel.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 16),
        subtitleLabel.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -14),
        chevron.centerYAnchor.constraint(equalTo: card.centerYAnchor),
        chevron.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -16),
    ])
    return card
}()

// Email text field
private lazy var emailTextField: UITextField = {
    let tf = UITextField()
    tf.translatesAutoresizingMaskIntoConstraints = false
    tf.placeholder = "Email address"
    tf.borderStyle = .roundedRect
    tf.keyboardType = .emailAddress
    tf.autocapitalizationType = .none
    tf.autocorrectionType = .no
    tf.returnKeyType = .continue
    tf.delegate = self
    tf.backgroundColor = .systemGray6
    tf.font = .systemFont(ofSize: 16)
    return tf
}()

// Email continue button
private lazy var emailContinueButton: UIButton = {
    let btn = UIButton(type: .system)
    btn.translatesAutoresizingMaskIntoConstraints = false
    btn.setTitle("Continue with Email", for: .normal)
    btn.applyPrimaryStyle()  // Check existing button extension
    btn.addTarget(self, action: #selector(emailContinueTapped), for: .touchUpInside)
    return btn
}()

// Google button
private lazy var googleButton: UIButton = {
    let btn = UIButton(type: .system)
    btn.translatesAutoresizingMaskIntoConstraints = false
    btn.setTitle("Sign in with Google", for: .normal)
    btn.applySecondaryStyle()
    btn.addTarget(self, action: #selector(googleSignInTapped), for: .touchUpInside)
    return btn
}()

// Microsoft button
private lazy var microsoftButton: UIButton = {
    let btn = UIButton(type: .system)
    btn.translatesAutoresizingMaskIntoConstraints = false
    btn.setTitle("Sign in with Microsoft", for: .normal)
    btn.applySecondaryStyle()
    btn.addTarget(self, action: #selector(microsoftSignInTapped), for: .touchUpInside)
    return btn
}()

// Request organization link
private lazy var requestOrgButton: UIButton = {
    let btn = UIButton(type: .system)
    btn.translatesAutoresizingMaskIntoConstraints = false
    btn.setTitle("Need an organization? Request one", for: .normal)
    btn.titleLabel?.font = .systemFont(ofSize: 14)
    btn.addTarget(self, action: #selector(requestOrgTapped), for: .touchUpInside)
    return btn
}()
```

- [ ] **Step 3: Update setupUI to include new elements**

Reorganize the content stack/scroll view to include (top to bottom):
1. Logo + title (keep existing)
2. Invite code card (new)
3. Divider "or sign in"
4. Email text field + Continue button (new)
5. Divider "or"
6. Google + Microsoft buttons (new)
7. Divider "or scan with wallet"
8. QR code image (existing, reduce to 150x150)
9. Open Wallet button (existing)
10. Request organization link (new)

Wrap everything in a UIScrollView if not already done.

- [ ] **Step 4: Add action methods**

```swift
@objc private func inviteCodeTapped() {
    delegate?.loginDidRequestInviteCode()
}

@objc private func emailContinueTapped() {
    viewModel.email = emailTextField.text ?? ""
    viewModel.emailLogin()
}

@objc private func googleSignInTapped() {
    // Launch OIDC flow for Google
    // Use ASWebAuthenticationSession or native Google Sign-In
    delegate?.loginDidRequestOidc(provider: "google")
}

@objc private func microsoftSignInTapped() {
    delegate?.loginDidRequestOidc(provider: "microsoft")
}

@objc private func requestOrgTapped() {
    delegate?.loginDidRequestTenantRequest()
}
```

- [ ] **Step 5: Add Combine bindings for new state**

In `setupBindings()`, add:

```swift
viewModel.$navigateToTotp
    .compactMap { $0 }
    .receive(on: DispatchQueue.main)
    .sink { [weak self] email in
        self?.delegate?.loginDidRequestTotpVerify(email: email)
    }
    .store(in: &cancellables)
```

- [ ] **Step 6: Update delegate protocol**

Add new methods to the delegate protocol (defined in the same file or AuthCoordinator):

```swift
protocol LoginViewControllerDelegate: AnyObject {
    // Existing
    func loginDidComplete()
    func loginDidRequestInviteCode()
    // New
    func loginDidRequestTotpVerify(email: String)
    func loginDidRequestOidc(provider: String)
    func loginDidRequestTenantRequest()
}
```

- [ ] **Step 7: Make VC conform to UITextFieldDelegate**

```swift
extension LoginViewController: UITextFieldDelegate {
    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        if textField == emailTextField {
            emailContinueTapped()
        }
        return true
    }
}
```

- [ ] **Step 8: Build and verify**

Run: build command from Task 1 Step 5

- [ ] **Step 9: Commit**

```bash
git add clients/ios/
git commit -m "feat(ios): add email, OIDC, and org request to LoginViewController"
```

---

### Task 3: Create TotpVerifyViewController + ViewModel

**Files:**
- Create: `Presentation/Auth/TotpVerifyViewController.swift`
- Create: `Presentation/Auth/TotpVerifyViewModel.swift`

- [ ] **Step 1: Create TotpVerifyViewModel**

Create `clients/ios/SsdidDrive/SsdidDrive/Presentation/Auth/TotpVerifyViewModel.swift`:

```swift
import Foundation
import Combine

@MainActor
final class TotpVerifyViewModel: BaseViewModel {
    let email: String
    @Published var code: String = ""
    @Published var isAuthenticated: Bool = false

    private let apiClient: APIClient
    private let keychainManager: KeychainManager

    init(email: String, apiClient: APIClient, keychainManager: KeychainManager) {
        self.email = email
        self.apiClient = apiClient
        self.keychainManager = keychainManager
        super.init()
    }

    func verify() {
        let trimmedCode = code.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedCode.count == 6 else {
            errorMessage = "Enter a 6-digit code"
            return
        }

        isLoading = true
        errorMessage = nil

        Task {
            do {
                struct TotpVerifyRequest: Encodable {
                    let email: String
                    let code: String
                }
                struct TotpVerifyResponse: Decodable {
                    let token: String
                    let account_id: String
                    let email: String
                }

                let response: TotpVerifyResponse = try await apiClient.request(
                    "/api/auth/totp/verify",
                    method: .post,
                    body: TotpVerifyRequest(email: email, code: trimmedCode),
                    requiresAuth: false
                )

                // Save session token — match existing keychain pattern
                keychainManager.accessToken = response.token
                self.isLoading = false
                self.isAuthenticated = true
            } catch {
                self.isLoading = false
                self.handleError(error)
            }
        }
    }
}
```

Note: Check the exact `KeychainManager` property name and how the existing wallet callback saves tokens. Match exactly.

- [ ] **Step 2: Create TotpVerifyViewController**

Create `clients/ios/SsdidDrive/SsdidDrive/Presentation/Auth/TotpVerifyViewController.swift`:

```swift
import UIKit
import Combine

protocol TotpVerifyViewControllerDelegate: AnyObject {
    func totpVerifyDidComplete()
    func totpVerifyDidRequestRecovery(email: String)
}

final class TotpVerifyViewController: UIViewController {
    weak var delegate: TotpVerifyViewControllerDelegate?
    private let viewModel: TotpVerifyViewModel
    private var cancellables = Set<AnyCancellable>()

    init(viewModel: TotpVerifyViewModel) {
        self.viewModel = viewModel
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not implemented") }

    // MARK: - UI

    private lazy var lockIcon: UIImageView = {
        let iv = UIImageView(image: UIImage(systemName: "lock.fill"))
        iv.translatesAutoresizingMaskIntoConstraints = false
        iv.tintColor = .systemBlue
        iv.contentMode = .scaleAspectFit
        return iv
    }()

    private lazy var titleLabel: UILabel = {
        let lbl = UILabel()
        lbl.translatesAutoresizingMaskIntoConstraints = false
        lbl.text = "Two-Factor Authentication"
        lbl.font = .systemFont(ofSize: 24, weight: .bold)
        lbl.textAlignment = .center
        return lbl
    }()

    private lazy var subtitleLabel: UILabel = {
        let lbl = UILabel()
        lbl.translatesAutoresizingMaskIntoConstraints = false
        lbl.text = "Enter the 6-digit code from your authenticator app"
        lbl.font = .systemFont(ofSize: 15)
        lbl.textColor = .secondaryLabel
        lbl.textAlignment = .center
        lbl.numberOfLines = 0
        return lbl
    }()

    private lazy var codeTextField: UITextField = {
        let tf = UITextField()
        tf.translatesAutoresizingMaskIntoConstraints = false
        tf.placeholder = "000000"
        tf.font = .monospacedSystemFont(ofSize: 32, weight: .bold)
        tf.textAlignment = .center
        tf.keyboardType = .numberPad
        tf.borderStyle = .roundedRect
        tf.backgroundColor = .systemGray6
        tf.delegate = self
        return tf
    }()

    private lazy var verifyButton: UIButton = {
        let btn = UIButton(type: .system)
        btn.translatesAutoresizingMaskIntoConstraints = false
        btn.setTitle("Verify", for: .normal)
        btn.applyPrimaryStyle()
        btn.addTarget(self, action: #selector(verifyTapped), for: .touchUpInside)
        return btn
    }()

    private lazy var errorLabel: UILabel = {
        let lbl = UILabel()
        lbl.translatesAutoresizingMaskIntoConstraints = false
        lbl.textColor = .systemRed
        lbl.font = .systemFont(ofSize: 14)
        lbl.textAlignment = .center
        lbl.numberOfLines = 0
        lbl.isHidden = true
        return lbl
    }()

    private lazy var activityIndicator: UIActivityIndicatorView = {
        let ai = UIActivityIndicatorView(style: .medium)
        ai.translatesAutoresizingMaskIntoConstraints = false
        ai.hidesWhenStopped = true
        return ai
    }()

    private lazy var recoveryButton: UIButton = {
        let btn = UIButton(type: .system)
        btn.translatesAutoresizingMaskIntoConstraints = false
        btn.setTitle("Lost your authenticator? Recover access", for: .normal)
        btn.titleLabel?.font = .systemFont(ofSize: 14)
        btn.addTarget(self, action: #selector(recoveryTapped), for: .touchUpInside)
        return btn
    }()

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        title = ""
        setupUI()
        setupBindings()
        codeTextField.becomeFirstResponder()
    }

    private func setupUI() {
        let stack = UIStackView(arrangedSubviews: [
            lockIcon, titleLabel, subtitleLabel, codeTextField,
            activityIndicator, verifyButton, errorLabel, recoveryButton
        ])
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = 16
        stack.setCustomSpacing(8, after: titleLabel)
        stack.setCustomSpacing(24, after: subtitleLabel)
        stack.setCustomSpacing(8, after: verifyButton)
        stack.setCustomSpacing(24, after: errorLabel)

        view.addSubview(stack)

        NSLayoutConstraint.activate([
            lockIcon.heightAnchor.constraint(equalToConstant: 48),
            lockIcon.widthAnchor.constraint(equalToConstant: 48),
            codeTextField.widthAnchor.constraint(equalToConstant: 200),
            codeTextField.heightAnchor.constraint(equalToConstant: 56),
            verifyButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 32),
            verifyButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -32),
            verifyButton.heightAnchor.constraint(equalToConstant: 50),
            stack.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: view.centerYAnchor, constant: -40),
            stack.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 32),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -32),
        ])
    }

    private func setupBindings() {
        viewModel.$isLoading
            .receive(on: DispatchQueue.main)
            .sink { [weak self] loading in
                self?.verifyButton.isEnabled = !loading
                loading ? self?.activityIndicator.startAnimating() : self?.activityIndicator.stopAnimating()
            }
            .store(in: &cancellables)

        viewModel.$errorMessage
            .receive(on: DispatchQueue.main)
            .sink { [weak self] error in
                self?.errorLabel.text = error
                self?.errorLabel.isHidden = error == nil
            }
            .store(in: &cancellables)

        viewModel.$isAuthenticated
            .receive(on: DispatchQueue.main)
            .filter { $0 }
            .sink { [weak self] _ in
                self?.delegate?.totpVerifyDidComplete()
            }
            .store(in: &cancellables)
    }

    // MARK: - Actions

    @objc private func verifyTapped() {
        viewModel.code = codeTextField.text ?? ""
        viewModel.verify()
    }

    @objc private func recoveryTapped() {
        delegate?.totpVerifyDidRequestRecovery(email: viewModel.email)
    }
}

// MARK: - UITextFieldDelegate

extension TotpVerifyViewController: UITextFieldDelegate {
    func textField(_ textField: UITextField, shouldChangeCharactersIn range: NSRange, replacementString string: String) -> Bool {
        let allowedChars = CharacterSet.decimalDigits
        guard string.isEmpty || string.unicodeScalars.allSatisfy({ allowedChars.contains($0) }) else {
            return false
        }
        let currentText = textField.text ?? ""
        let newText = (currentText as NSString).replacingCharacters(in: range, with: string)
        if newText.count > 6 { return false }

        // Auto-submit on 6 digits
        if newText.count == 6 {
            DispatchQueue.main.async {
                self.viewModel.code = newText
                self.viewModel.verify()
            }
        }
        return true
    }
}
```

- [ ] **Step 3: Build**

- [ ] **Step 4: Commit**

```bash
git add clients/ios/
git commit -m "feat(ios): add TotpVerifyViewController and ViewModel"
```

---

### Task 4: Wire TOTP + TenantRequest in AuthCoordinator

**Files:**
- Modify: `Presentation/Coordinators/AuthCoordinator.swift`

- [ ] **Step 1: Read AuthCoordinator.swift fully**

- [ ] **Step 2: Add TOTP navigation method**

```swift
func showTotpVerify(email: String) {
    let vm = TotpVerifyViewModel(email: email, apiClient: apiClient, keychainManager: keychainManager)
    let vc = TotpVerifyViewController(viewModel: vm)
    vc.delegate = self
    navigationController.pushViewController(vc, animated: true)
}
```

- [ ] **Step 3: Add TenantRequest modal method**

```swift
func showTenantRequest() {
    let view = TenantRequestView()
    let hostingVC = UIHostingController(rootView: view)
    navigationController.present(hostingVC, animated: true)
}
```

- [ ] **Step 4: Conform to new delegate protocols**

Add `LoginViewControllerDelegate` conformance for new methods:

```swift
extension AuthCoordinator: LoginViewControllerDelegate {
    // Existing methods...

    func loginDidRequestTotpVerify(email: String) {
        showTotpVerify(email: email)
    }

    func loginDidRequestOidc(provider: String) {
        // Launch ASWebAuthenticationSession or native SDK
        // On success, call loginViewModel.handleOidcResult(provider:, idToken:)
    }

    func loginDidRequestTenantRequest() {
        showTenantRequest()
    }
}

extension AuthCoordinator: TotpVerifyViewControllerDelegate {
    func totpVerifyDidComplete() {
        delegate?.authCoordinatorDidComplete()
    }

    func totpVerifyDidRequestRecovery(email: String) {
        // Navigate to recovery screen
        showRecovery(email: email)
    }
}
```

Note: Check the exact method names used in the existing coordinator. The dependency injection (apiClient, keychainManager) must match what's available in AuthCoordinator.

- [ ] **Step 5: Build and verify**

- [ ] **Step 6: Commit**

```bash
git add clients/ios/
git commit -m "feat(ios): wire TOTP verify and TenantRequest in AuthCoordinator"
```

---

## Chunk 2: InviteAccept Multi-Auth + TenantRequest + CreateInvitation Polish

### Task 5: Extend InviteAcceptViewModel with multi-auth

**Files:**
- Modify: `Presentation/Auth/InviteAcceptViewModel.swift`

- [ ] **Step 1: Read InviteAcceptViewModel.swift fully**

- [ ] **Step 2: Add new published properties**

```swift
@Published var isAcceptingAsExisting: Bool = false
@Published var acceptError: String? = nil
```

- [ ] **Step 3: Add acceptAsExistingUser method**

```swift
func acceptAsExistingUser() {
    guard let invitation = invitation else { return }
    isAcceptingAsExisting = true
    acceptError = nil

    Task {
        do {
            // Call accept invitation by token — check existing repository method
            try await tenantRepository.acceptInvitationByToken(token)
            self.isAcceptingAsExisting = false
            self.isRegistered = true
        } catch {
            self.isAcceptingAsExisting = false
            self.acceptError = error.localizedDescription
        }
    }
}
```

- [ ] **Step 4: Add handleOidcResult method**

```swift
func handleOidcResult(provider: String, idToken: String) {
    isLoading = true
    errorMessage = nil

    Task {
        do {
            struct OidcVerifyRequest: Encodable {
                let provider: String
                let id_token: String
                let invitation_token: String?
            }

            let _: AuthResponse = try await apiClient.request(
                "/api/auth/oidc/verify",
                method: .post,
                body: OidcVerifyRequest(provider: provider, id_token: idToken, invitation_token: token),
                requiresAuth: false
            )

            self.isLoading = false
            self.isRegistered = true
        } catch {
            self.isLoading = false
            self.handleError(error)
        }
    }
}
```

- [ ] **Step 5: Build and commit**

```bash
git add clients/ios/
git commit -m "feat(ios): add multi-auth methods to InviteAcceptViewModel"
```

---

### Task 6: Add multi-auth buttons to InviteAcceptViewController

**Files:**
- Modify: `Presentation/Auth/InviteAcceptViewController.swift`

- [ ] **Step 1: Read InviteAcceptViewController.swift fully**

Understand where the "Accept with SSDID Wallet" button is placed in the layout.

- [ ] **Step 2: Add new buttons after invitation card**

Add these buttons between the invitation details card and the existing wallet button. Follow the existing lazy property + constraint pattern:

1. "Sign In to Accept" — secondary button (for existing users)
2. Divider label "or create account"
3. "Continue with Email" — secondary button
4. "Sign in with Google" — secondary button
5. "Sign in with Microsoft" — secondary button
6. Keep existing "Accept with SSDID Wallet" button

All buttons should have height 50pt, horizontal padding 32pt, spacing 10pt.

- [ ] **Step 3: Add action methods**

```swift
@objc private func acceptAsExistingTapped() {
    viewModel.acceptAsExistingUser()
}

@objc private func emailRegisterTapped() {
    delegate?.inviteAcceptDidRequestEmailRegister(token: viewModel.token)
}

@objc private func googleSignInTapped() {
    delegate?.inviteAcceptDidRequestOidc(provider: "google")
}

@objc private func microsoftSignInTapped() {
    delegate?.inviteAcceptDidRequestOidc(provider: "microsoft")
}
```

- [ ] **Step 4: Add bindings for new state**

```swift
viewModel.$isAcceptingAsExisting
    .receive(on: DispatchQueue.main)
    .sink { [weak self] accepting in
        self?.acceptAsExistingButton.isEnabled = !accepting
        // Show/hide spinner
    }
    .store(in: &cancellables)

viewModel.$acceptError
    .receive(on: DispatchQueue.main)
    .sink { [weak self] error in
        // Show error below buttons
    }
    .store(in: &cancellables)
```

- [ ] **Step 5: Hide all buttons when waiting for wallet**

In the existing `isWaitingForWallet` binding, also hide the new buttons.

- [ ] **Step 6: Update delegate protocol**

```swift
protocol InviteAcceptViewControllerDelegate: AnyObject {
    // Existing
    func inviteAcceptDidComplete()
    func inviteAcceptDidRequestLogin()
    // New
    func inviteAcceptDidRequestEmailRegister(token: String)
    func inviteAcceptDidRequestOidc(provider: String)
}
```

- [ ] **Step 7: Build and commit**

```bash
git add clients/ios/
git commit -m "feat(ios): add multi-auth buttons to InviteAcceptViewController"
```

---

### Task 7: Create TenantRequestView + ViewModel (SwiftUI)

**Files:**
- Create: `Presentation/Settings/TenantRequestView.swift`
- Create: `Presentation/Settings/TenantRequestViewModel.swift`

- [ ] **Step 1: Read JoinTenantView.swift and JoinTenantViewModel.swift for pattern**

- [ ] **Step 2: Create TenantRequestViewModel**

Create `clients/ios/SsdidDrive/SsdidDrive/Presentation/Settings/TenantRequestViewModel.swift`:

```swift
import Foundation
import Combine

@MainActor
final class TenantRequestViewModel: BaseViewModel {
    enum ViewState {
        case idle
        case loading
        case submitted
    }

    @Published var state: ViewState = .idle
    @Published var organizationName: String = ""
    @Published var reason: String = ""

    private let apiClient: APIClient

    init(apiClient: APIClient) {
        self.apiClient = apiClient
        super.init()
    }

    func submitRequest() {
        let name = organizationName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else {
            errorMessage = "Organization name is required"
            return
        }

        state = .loading
        isLoading = true
        errorMessage = nil

        Task {
            do {
                struct SubmitRequest: Encodable {
                    let organization_name: String
                    let reason: String?
                }
                struct SubmitResponse: Decodable {
                    let id: String
                    let organization_name: String
                    let status: String
                }

                let trimmedReason = reason.trimmingCharacters(in: .whitespacesAndNewlines)
                let _: SubmitResponse = try await apiClient.request(
                    "/api/tenant-requests",
                    method: .post,
                    body: SubmitRequest(
                        organization_name: name,
                        reason: trimmedReason.isEmpty ? nil : trimmedReason
                    ),
                    requiresAuth: true
                )

                self.isLoading = false
                self.state = .submitted
            } catch {
                self.isLoading = false
                self.state = .idle
                self.handleError(error)
            }
        }
    }
}
```

- [ ] **Step 3: Create TenantRequestView**

Create `clients/ios/SsdidDrive/SsdidDrive/Presentation/Settings/TenantRequestView.swift`:

```swift
import SwiftUI

struct TenantRequestView: View {
    @ObservedObject var viewModel: TenantRequestViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            Group {
                switch viewModel.state {
                case .idle:
                    formContent
                case .loading:
                    formContent
                case .submitted:
                    successContent
                }
            }
            .navigationTitle("Request Organization")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private var formContent: some View {
        ScrollView {
            VStack(spacing: 20) {
                Image(systemName: "building.2")
                    .font(.system(size: 48))
                    .foregroundColor(.blue)
                    .padding(.top, 20)

                Text("Create Your Organization")
                    .font(.title2.bold())

                Text("Request a new organization for your team. An administrator will review your request.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)

                VStack(alignment: .leading, spacing: 6) {
                    Text("Organization Name")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.secondary)
                    TextField("Acme Corp", text: $viewModel.organizationName)
                        .textFieldStyle(.roundedBorder)
                }
                .padding(.horizontal)

                VStack(alignment: .leading, spacing: 6) {
                    Text("Reason (optional)")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.secondary)
                    TextEditor(text: $viewModel.reason)
                        .frame(minHeight: 80)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.secondary.opacity(0.3))
                        )
                    HStack {
                        Spacer()
                        Text("\(viewModel.reason.count)/500")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.horizontal)

                if let error = viewModel.errorMessage {
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.red)
                        .padding(.horizontal)
                }

                Button(action: viewModel.submitRequest) {
                    HStack {
                        if viewModel.isLoading {
                            ProgressView()
                                .tint(.white)
                        }
                        Text("Submit Request")
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(viewModel.organizationName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || viewModel.isLoading ? Color.gray : Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(12)
                }
                .disabled(viewModel.organizationName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || viewModel.isLoading)
                .padding(.horizontal)
            }
            .padding(.bottom, 40)
        }
    }

    private var successContent: some View {
        VStack(spacing: 16) {
            Spacer()

            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 56))
                .foregroundColor(.green)

            Text("Request Submitted!")
                .font(.title2.bold())

            Text("Your request for \"\(viewModel.organizationName)\" has been submitted. An administrator will review and approve it.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            Text("You'll be notified when your organization is ready.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            Spacer()

            Button("Done") { dismiss() }
                .buttonStyle(.borderedProminent)
        }
        .padding()
    }
}
```

- [ ] **Step 4: Build and commit**

```bash
git add clients/ios/
git commit -m "feat(ios): add TenantRequestView and ViewModel"
```

---

### Task 8: Enhance CreateInvitationView with copy/share

**Files:**
- Modify: `Presentation/Settings/CreateInvitationView.swift`
- Modify: `Presentation/Settings/CreateInvitationViewModel.swift`

- [ ] **Step 1: Read CreateInvitationView.swift and ViewModel**

Understand the current success state display.

- [ ] **Step 2: Add short code copy/share to success state**

In the success state view, add:

```swift
// Short code display
Text(viewModel.createdShortCode ?? "")
    .font(.system(size: 28, weight: .bold, design: .monospaced))
    .foregroundColor(.blue)
    .padding()
    .background(Color(.systemGray6))
    .cornerRadius(12)
    .frame(maxWidth: .infinity)

// Copy and Share buttons
HStack(spacing: 12) {
    Button(action: {
        UIPasteboard.general.string = viewModel.createdShortCode
        // Show toast or change button text briefly
    }) {
        Label("Copy", systemImage: "doc.on.doc")
    }
    .buttonStyle(.bordered)

    ShareLink(item: "Join our organization on SSDID Drive! Use invite code: \(viewModel.createdShortCode ?? "")") {
        Label("Share", systemImage: "square.and.arrow.up")
    }
    .buttonStyle(.borderedProminent)
}

// Email sent status
if let emailSent = viewModel.emailSent {
    HStack {
        Image(systemName: emailSent ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
            .foregroundColor(emailSent ? .green : .orange)
        Text(emailSent ? "Email sent" : "Email failed to send")
            .font(.caption)
            .foregroundColor(.secondary)
    }
}
```

- [ ] **Step 3: Update ViewModel to expose short code and email_sent**

Add to CreateInvitationViewModel:

```swift
@Published var createdShortCode: String? = nil
@Published var emailSent: Bool? = nil
```

Update the success handler to read these from the API response. The backend now returns `short_code`, `email_sent`, and `email_error` in the create invitation response.

- [ ] **Step 4: Build and commit**

```bash
git add clients/ios/
git commit -m "feat(ios): add copy/share and email_sent status to CreateInvitationView"
```

---

### Task 9: Wire TenantRequest in Settings and add to XcodeGen

**Files:**
- Modify: `Presentation/Settings/SettingsViewController.swift`
- Modify: `project.yml` (if XcodeGen is used to register new files)

- [ ] **Step 1: Add TenantRequest to Settings**

Read `SettingsViewController.swift`. Add a "Request Organization" row in the Tenant Management section, near the existing "Join Organization" button:

```swift
// Follow the existing pattern for table view cells or buttons
// Add after "Join Organization" button:
let requestOrgButton = createSettingsButton(
    title: "Request Organization",
    icon: "building.2",
    action: #selector(requestOrgTapped)
)
```

- [ ] **Step 2: Add action**

```swift
@objc private func requestOrgTapped() {
    let vm = TenantRequestViewModel(apiClient: apiClient)
    let view = TenantRequestView(viewModel: vm)
    let hostingVC = UIHostingController(rootView: view)
    present(hostingVC, animated: true)
}
```

- [ ] **Step 3: Register new files in project.yml if needed**

If XcodeGen is used, new Swift files in existing directories are usually auto-discovered. Check `project.yml` for file inclusion patterns.

- [ ] **Step 4: Build full project**

- [ ] **Step 5: Commit**

```bash
git add clients/ios/
git commit -m "feat(ios): wire TenantRequestView in Settings and complete navigation"
```

---

### Task 10: Final build verification

- [ ] **Step 1: Full clean build**

```bash
cd clients/ios/SsdidDrive
xcodegen generate  # if using XcodeGen
xcodebuild clean build -scheme SsdidDrive -destination 'platform=iOS Simulator,name=iPhone 16' 2>&1 | tail -10
```

- [ ] **Step 2: Run tests if available**

```bash
xcodebuild test -scheme SsdidDrive -destination 'platform=iOS Simulator,name=iPhone 16' 2>&1 | tail -20
```

- [ ] **Step 3: Final commit**

```bash
git add clients/ios/
git commit -m "feat(ios): complete onboarding UI improvements — multi-auth login, TOTP verify, tenant request, invitation polish"
```

---

## Implementation Order & Dependencies

```
Task 1: LoginViewModel email/OIDC methods ──┐
Task 2: LoginViewController UI              ──┼── Chunk 1 (sequential)
Task 3: TotpVerifyVC + VM (new)             ──┤
Task 4: AuthCoordinator wiring              ──┘
                                              │
Task 5: InviteAcceptViewModel multi-auth    ──┤
Task 6: InviteAcceptViewController buttons  ──┼── Chunk 2 (5-6 sequential, 7-9 parallel)
Task 7: TenantRequestView + VM (new)        ──┤
Task 8: CreateInvitationView enhancement    ──┤
Task 9: Settings + navigation wiring        ──┤
Task 10: Final verification                 ──┘
```

Parallel opportunities:
- Tasks 5-6 and Tasks 7-9 modify completely independent files
- Task 8 is independent of everything else
