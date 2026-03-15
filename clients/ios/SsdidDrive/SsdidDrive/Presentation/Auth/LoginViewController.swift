import UIKit
import Combine
import CoreImage.CIFilterBuiltins

/// Delegate protocol for LoginViewController navigation events
protocol LoginViewControllerDelegate: AnyObject {
    func loginDidRequestInviteCode()
    func loginDidRequestTotpVerify(email: String)
    func loginDidRequestOidc(provider: String)
    func loginDidRequestTenantRequest()
}

/// Login view controller displaying multiple authentication options:
/// invite code, email + TOTP, OIDC providers, and SSDID Wallet QR scanning.
final class LoginViewController: BaseViewController {

    // MARK: - Properties

    private let viewModel: LoginViewModel
    weak var delegate: LoginViewControllerDelegate?

    // MARK: - UI Components

    private lazy var scrollView: UIScrollView = {
        let scroll = UIScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.showsVerticalScrollIndicator = false
        return scroll
    }()

    private lazy var contentView: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private lazy var logoImageView: UIImageView = {
        let imageView = UIImageView()
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.image = UIImage(named: "Logo")
        imageView.contentMode = .scaleAspectFit
        imageView.layer.cornerRadius = 16
        imageView.clipsToBounds = true
        imageView.accessibilityIdentifier = "loginLogoImageView"
        imageView.accessibilityLabel = "SSDID Drive logo"
        return imageView
    }()

    private lazy var titleLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.text = "SSDID Drive"
        label.font = .systemFont(ofSize: 32, weight: .bold)
        label.textAlignment = .center
        label.accessibilityIdentifier = "loginTitleLabel"
        return label
    }()

    // MARK: - Invite Code Card

    private lazy var inviteCodeCard: UIView = {
        let card = UIView()
        card.translatesAutoresizingMaskIntoConstraints = false
        card.backgroundColor = .secondarySystemBackground
        card.layer.cornerRadius = 12
        card.isUserInteractionEnabled = true
        card.accessibilityIdentifier = "inviteCodeCard"
        card.accessibilityLabel = "Have an invite code? Enter your code to join an organization"
        card.accessibilityTraits = .button

        let tap = UITapGestureRecognizer(target: self, action: #selector(inviteCodeTapped))
        card.addGestureRecognizer(tap)

        let titleLabel = UILabel()
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.text = "Have an invite code?"
        titleLabel.font = .systemFont(ofSize: 16, weight: .semibold)

        let subtitleLabel = UILabel()
        subtitleLabel.translatesAutoresizingMaskIntoConstraints = false
        subtitleLabel.text = "Enter your code to join an organization"
        subtitleLabel.font = .systemFont(ofSize: 13)
        subtitleLabel.textColor = .secondaryLabel

        let chevron = UIImageView()
        chevron.translatesAutoresizingMaskIntoConstraints = false
        chevron.image = UIImage(systemName: "chevron.right")
        chevron.tintColor = .secondaryLabel
        chevron.contentMode = .scaleAspectFit

        card.addSubview(titleLabel)
        card.addSubview(subtitleLabel)
        card.addSubview(chevron)

        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: card.topAnchor, constant: 16),
            titleLabel.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 16),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: chevron.leadingAnchor, constant: -8),

            subtitleLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 4),
            subtitleLabel.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 16),
            subtitleLabel.trailingAnchor.constraint(lessThanOrEqualTo: chevron.leadingAnchor, constant: -8),
            subtitleLabel.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -16),

            chevron.centerYAnchor.constraint(equalTo: card.centerYAnchor),
            chevron.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -16),
            chevron.widthAnchor.constraint(equalToConstant: 12),
            chevron.heightAnchor.constraint(equalToConstant: 16)
        ])

        return card
    }()

    // MARK: - Dividers

    private lazy var signInDivider: UIView = {
        makeDivider(text: "or sign in")
    }()

    private lazy var orDivider: UIView = {
        makeDivider(text: "or")
    }()

    private lazy var walletDivider: UIView = {
        makeDivider(text: "or scan with wallet")
    }()

    // MARK: - Email Field & Button

    private lazy var emailTextField: UITextField = {
        let field = UITextField()
        field.translatesAutoresizingMaskIntoConstraints = false
        field.placeholder = "Email address"
        field.keyboardType = .emailAddress
        field.autocapitalizationType = .none
        field.autocorrectionType = .no
        field.textContentType = .emailAddress
        field.borderStyle = .roundedRect
        field.font = .systemFont(ofSize: 16)
        field.backgroundColor = .secondarySystemBackground
        field.layer.cornerRadius = 12
        field.accessibilityIdentifier = "emailTextField"
        field.accessibilityLabel = "Email address"
        field.applySsdidDriveStyle()
        return field
    }()

    private lazy var emailContinueButton: UIButton = {
        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.setTitle("Continue with Email", for: .normal)
        button.accessibilityIdentifier = "emailContinueButton"
        button.accessibilityLabel = "Continue with Email"
        button.applyPrimaryStyle()
        button.addTarget(self, action: #selector(emailContinueTapped), for: .touchUpInside)
        return button
    }()

    // MARK: - OIDC Buttons

    private lazy var googleSignInButton: UIButton = {
        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.setTitle("Sign in with Google", for: .normal)
        button.accessibilityIdentifier = "googleSignInButton"
        button.accessibilityLabel = "Sign in with Google"
        button.applySecondaryStyle()
        button.addTarget(self, action: #selector(googleSignInTapped), for: .touchUpInside)
        return button
    }()

    private lazy var microsoftSignInButton: UIButton = {
        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.setTitle("Sign in with Microsoft", for: .normal)
        button.accessibilityIdentifier = "microsoftSignInButton"
        button.accessibilityLabel = "Sign in with Microsoft"
        button.applySecondaryStyle()
        button.addTarget(self, action: #selector(microsoftSignInTapped), for: .touchUpInside)
        return button
    }()

    // MARK: - QR / Wallet (existing)

    private lazy var qrImageView: UIImageView = {
        let imageView = UIImageView()
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.contentMode = .scaleAspectFit
        imageView.accessibilityIdentifier = "qrCodeImageView"
        imageView.accessibilityLabel = "QR code for SSDID Wallet authentication"
        imageView.layer.magnificationFilter = .nearest
        return imageView
    }()

    private lazy var activityIndicator: UIActivityIndicatorView = {
        let indicator = UIActivityIndicatorView(style: .large)
        indicator.translatesAutoresizingMaskIntoConstraints = false
        indicator.hidesWhenStopped = true
        return indicator
    }()

    private lazy var errorLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.textColor = .systemRed
        label.font = .systemFont(ofSize: 14)
        label.textAlignment = .center
        label.numberOfLines = 0
        label.isHidden = true
        label.accessibilityIdentifier = "loginErrorLabel"
        return label
    }()

    private lazy var refreshButton: UIButton = {
        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.setTitle("Refresh", for: .normal)
        button.titleLabel?.font = .systemFont(ofSize: 16, weight: .medium)
        button.accessibilityIdentifier = "refreshButton"
        button.accessibilityLabel = "Refresh QR code"
        button.applyPrimaryStyle()
        button.addTarget(self, action: #selector(refreshTapped), for: .touchUpInside)
        button.isHidden = true
        return button
    }()

    private lazy var openWalletButton: UIButton = {
        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        let config = UIImage.SymbolConfiguration(pointSize: 16, weight: .medium)
        let icon = UIImage(systemName: "arrow.up.forward.app.fill", withConfiguration: config)
        button.setImage(icon, for: .normal)
        button.setTitle("  Open SSDID Wallet", for: .normal)
        button.titleLabel?.font = .systemFont(ofSize: 16, weight: .medium)
        button.accessibilityIdentifier = "openWalletButton"
        button.accessibilityLabel = "Open SSDID Wallet"
        button.accessibilityHint = "Double tap to open the SSDID Wallet app for authentication"
        button.applySecondaryStyle()
        button.addTarget(self, action: #selector(openWalletTapped), for: .touchUpInside)
        button.isHidden = true
        return button
    }()

    // MARK: - Request Org Button

    private lazy var requestOrgButton: UIButton = {
        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.setTitle("Need an organization? Request one", for: .normal)
        button.titleLabel?.font = .systemFont(ofSize: 15, weight: .medium)
        button.setTitleColor(.systemBlue, for: .normal)
        button.accessibilityIdentifier = "requestOrgButton"
        button.accessibilityLabel = "Need an organization? Request one"
        button.accessibilityHint = "Double tap to request creation of a new organization"
        button.addTarget(self, action: #selector(requestOrgTapped), for: .touchUpInside)
        return button
    }()

    // MARK: - Initialization

    init(viewModel: LoginViewModel) {
        self.viewModel = viewModel
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Setup

    override func setupUI() {
        setupKeyboardDismissOnTap()

        view.addSubview(scrollView)
        scrollView.addSubview(contentView)

        contentView.addSubview(logoImageView)
        contentView.addSubview(titleLabel)
        contentView.addSubview(inviteCodeCard)
        contentView.addSubview(signInDivider)
        contentView.addSubview(emailTextField)
        contentView.addSubview(emailContinueButton)
        contentView.addSubview(orDivider)
        contentView.addSubview(googleSignInButton)
        contentView.addSubview(microsoftSignInButton)
        contentView.addSubview(walletDivider)
        contentView.addSubview(qrImageView)
        contentView.addSubview(activityIndicator)
        contentView.addSubview(errorLabel)
        contentView.addSubview(refreshButton)
        contentView.addSubview(openWalletButton)
        contentView.addSubview(requestOrgButton)

        let horizontalInset: CGFloat = 24

        NSLayoutConstraint.activate([
            // Scroll view
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            // Content view
            contentView.topAnchor.constraint(equalTo: scrollView.topAnchor),
            contentView.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor),
            contentView.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor),
            contentView.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor),
            contentView.widthAnchor.constraint(equalTo: scrollView.widthAnchor),

            // Logo
            logoImageView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 60),
            logoImageView.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            logoImageView.widthAnchor.constraint(equalToConstant: 80),
            logoImageView.heightAnchor.constraint(equalToConstant: 80),

            // Title
            titleLabel.topAnchor.constraint(equalTo: logoImageView.bottomAnchor, constant: 24),
            titleLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: horizontalInset),
            titleLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -horizontalInset),

            // Invite code card
            inviteCodeCard.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 24),
            inviteCodeCard.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: horizontalInset),
            inviteCodeCard.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -horizontalInset),

            // "or sign in" divider
            signInDivider.topAnchor.constraint(equalTo: inviteCodeCard.bottomAnchor, constant: 20),
            signInDivider.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: horizontalInset),
            signInDivider.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -horizontalInset),

            // Email text field
            emailTextField.topAnchor.constraint(equalTo: signInDivider.bottomAnchor, constant: 20),
            emailTextField.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: horizontalInset),
            emailTextField.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -horizontalInset),
            emailTextField.heightAnchor.constraint(equalToConstant: 48),

            // Continue with Email button
            emailContinueButton.topAnchor.constraint(equalTo: emailTextField.bottomAnchor, constant: 12),
            emailContinueButton.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: horizontalInset),
            emailContinueButton.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -horizontalInset),
            emailContinueButton.heightAnchor.constraint(equalToConstant: 52),

            // "or" divider
            orDivider.topAnchor.constraint(equalTo: emailContinueButton.bottomAnchor, constant: 20),
            orDivider.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: horizontalInset),
            orDivider.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -horizontalInset),

            // Google Sign In
            googleSignInButton.topAnchor.constraint(equalTo: orDivider.bottomAnchor, constant: 20),
            googleSignInButton.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: horizontalInset),
            googleSignInButton.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -horizontalInset),
            googleSignInButton.heightAnchor.constraint(equalToConstant: 52),

            // Microsoft Sign In
            microsoftSignInButton.topAnchor.constraint(equalTo: googleSignInButton.bottomAnchor, constant: 12),
            microsoftSignInButton.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: horizontalInset),
            microsoftSignInButton.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -horizontalInset),
            microsoftSignInButton.heightAnchor.constraint(equalToConstant: 52),

            // "or scan with wallet" divider
            walletDivider.topAnchor.constraint(equalTo: microsoftSignInButton.bottomAnchor, constant: 20),
            walletDivider.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: horizontalInset),
            walletDivider.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -horizontalInset),

            // QR code (150x150)
            qrImageView.topAnchor.constraint(equalTo: walletDivider.bottomAnchor, constant: 20),
            qrImageView.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            qrImageView.widthAnchor.constraint(equalToConstant: 150),
            qrImageView.heightAnchor.constraint(equalToConstant: 150),

            // Activity indicator (centered on QR area)
            activityIndicator.centerXAnchor.constraint(equalTo: qrImageView.centerXAnchor),
            activityIndicator.centerYAnchor.constraint(equalTo: qrImageView.centerYAnchor),

            // Error label
            errorLabel.topAnchor.constraint(equalTo: qrImageView.bottomAnchor, constant: 16),
            errorLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: horizontalInset),
            errorLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -horizontalInset),

            // Refresh button
            refreshButton.topAnchor.constraint(equalTo: errorLabel.bottomAnchor, constant: 16),
            refreshButton.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            refreshButton.widthAnchor.constraint(equalToConstant: 160),
            refreshButton.heightAnchor.constraint(equalToConstant: 44),

            // Open Wallet button
            openWalletButton.topAnchor.constraint(equalTo: refreshButton.bottomAnchor, constant: 16),
            openWalletButton.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: horizontalInset),
            openWalletButton.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -horizontalInset),
            openWalletButton.heightAnchor.constraint(equalToConstant: 52),

            // Request org button
            requestOrgButton.topAnchor.constraint(equalTo: openWalletButton.bottomAnchor, constant: 24),
            requestOrgButton.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            requestOrgButton.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -40)
        ])
    }

    override func setupBindings() {
        // QR payload
        viewModel.$qrPayload
            .receive(on: DispatchQueue.main)
            .sink { [weak self] payload in
                if let payload = payload {
                    self?.qrImageView.image = self?.generateQRCode(from: payload)
                    self?.qrImageView.isHidden = false
                } else {
                    self?.qrImageView.isHidden = true
                }
            }
            .store(in: &cancellables)

        // Loading state
        viewModel.$isLoading
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isLoading in
                if isLoading {
                    self?.activityIndicator.startAnimating()
                    self?.qrImageView.isHidden = true
                } else {
                    self?.activityIndicator.stopAnimating()
                }
            }
            .store(in: &cancellables)

        // Error message
        viewModel.$errorMessage
            .receive(on: DispatchQueue.main)
            .sink { [weak self] message in
                self?.errorLabel.text = message
                self?.errorLabel.isHidden = message == nil
            }
            .store(in: &cancellables)

        // Expired state
        viewModel.$isExpired
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isExpired in
                self?.refreshButton.isHidden = !isExpired
            }
            .store(in: &cancellables)

        // Wallet deep link availability
        viewModel.$walletDeepLink
            .receive(on: DispatchQueue.main)
            .sink { [weak self] url in
                self?.openWalletButton.isHidden = (url == nil)
            }
            .store(in: &cancellables)

        // Navigate to TOTP verification
        viewModel.$navigateToTotp
            .compactMap { $0 }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] email in
                self?.delegate?.loginDidRequestTotpVerify(email: email)
            }
            .store(in: &cancellables)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        viewModel.createChallenge()
    }

    // MARK: - Actions

    @objc private func inviteCodeTapped() {
        triggerSelectionFeedback()
        delegate?.loginDidRequestInviteCode()
    }

    @objc private func emailContinueTapped() {
        triggerHapticFeedback()
        viewModel.email = emailTextField.text ?? ""
        viewModel.emailLogin()
    }

    @objc private func googleSignInTapped() {
        triggerSelectionFeedback()
        delegate?.loginDidRequestOidc(provider: "google")
    }

    @objc private func microsoftSignInTapped() {
        triggerSelectionFeedback()
        delegate?.loginDidRequestOidc(provider: "microsoft")
    }

    @objc private func requestOrgTapped() {
        triggerSelectionFeedback()
        delegate?.loginDidRequestTenantRequest()
    }

    @objc private func refreshTapped() {
        triggerHapticFeedback()
        viewModel.createChallenge()
    }

    @objc private func openWalletTapped() {
        triggerHapticFeedback()
        viewModel.openWallet()
    }

    // MARK: - Helpers

    /// Create a horizontal divider with centered text (e.g., "or sign in")
    private func makeDivider(text: String) -> UIView {
        let container = UIView()
        container.translatesAutoresizingMaskIntoConstraints = false

        let leftLine = UIView()
        leftLine.translatesAutoresizingMaskIntoConstraints = false
        leftLine.backgroundColor = .separator

        let rightLine = UIView()
        rightLine.translatesAutoresizingMaskIntoConstraints = false
        rightLine.backgroundColor = .separator

        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.text = text
        label.font = .systemFont(ofSize: 13)
        label.textColor = .secondaryLabel
        label.textAlignment = .center
        label.setContentHuggingPriority(.required, for: .horizontal)

        container.addSubview(leftLine)
        container.addSubview(label)
        container.addSubview(rightLine)

        NSLayoutConstraint.activate([
            leftLine.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            leftLine.trailingAnchor.constraint(equalTo: label.leadingAnchor, constant: -12),
            leftLine.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            leftLine.heightAnchor.constraint(equalToConstant: 1),

            label.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            label.topAnchor.constraint(equalTo: container.topAnchor),
            label.bottomAnchor.constraint(equalTo: container.bottomAnchor),

            rightLine.leadingAnchor.constraint(equalTo: label.trailingAnchor, constant: 12),
            rightLine.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            rightLine.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            rightLine.heightAnchor.constraint(equalToConstant: 1)
        ])

        return container
    }

    // MARK: - QR Code Generation

    private func generateQRCode(from string: String) -> UIImage {
        let data = Data(string.utf8)
        guard let filter = CIFilter(name: "CIQRCodeGenerator") else {
            return UIImage(systemName: "xmark.circle") ?? UIImage()
        }
        filter.setValue(data, forKey: "inputMessage")
        filter.setValue("M", forKey: "inputCorrectionLevel")
        let transform = CGAffineTransform(scaleX: 10, y: 10)
        if let output = filter.outputImage?.transformed(by: transform) {
            let context = CIContext()
            if let cgImage = context.createCGImage(output, from: output.extent) {
                return UIImage(cgImage: cgImage)
            }
        }
        return UIImage(systemName: "xmark.circle") ?? UIImage()
    }
}
