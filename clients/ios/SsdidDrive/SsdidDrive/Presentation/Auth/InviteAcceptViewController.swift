import UIKit
import Combine

/// View controller for accepting invitations via SSDID Wallet
final class InviteAcceptViewController: BaseViewController {

    // MARK: - Properties

    private let viewModel: InviteAcceptViewModel

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
        imageView.image = UIImage(systemName: "envelope.badge.shield.half.filled")
        imageView.tintColor = .systemBlue
        imageView.contentMode = .scaleAspectFit
        return imageView
    }()

    private lazy var titleLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.text = "SsdidDrive"
        label.font = .systemFont(ofSize: 32, weight: .bold)
        label.textAlignment = .center
        return label
    }()

    private lazy var subtitleLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.text = "You've been invited!"
        label.font = .systemFont(ofSize: 17, weight: .medium)
        label.textColor = .secondaryLabel
        label.textAlignment = .center
        return label
    }()

    // Loading state
    private lazy var loadingIndicator: UIActivityIndicatorView = {
        let indicator = UIActivityIndicatorView(style: .large)
        indicator.translatesAutoresizingMaskIntoConstraints = false
        indicator.hidesWhenStopped = true
        return indicator
    }()

    private lazy var loadingLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.text = "Loading invitation..."
        label.font = .systemFont(ofSize: 15)
        label.textColor = .secondaryLabel
        label.textAlignment = .center
        return label
    }()

    // Invitation info card
    private lazy var invitationCard: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.backgroundColor = .systemBlue.withAlphaComponent(0.1)
        view.layer.cornerRadius = 12
        view.isHidden = true
        return view
    }()

    private lazy var organizationLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .systemFont(ofSize: 11, weight: .medium)
        label.textColor = .secondaryLabel
        label.text = "ORGANIZATION"
        return label
    }()

    private lazy var tenantNameLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .systemFont(ofSize: 17, weight: .semibold)
        return label
    }()

    private lazy var inviterLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .systemFont(ofSize: 15)
        label.textColor = .secondaryLabel
        label.numberOfLines = 0
        return label
    }()

    private lazy var emailInfoLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .systemFont(ofSize: 15)
        label.textColor = .label
        return label
    }()

    private lazy var messageLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .italicSystemFont(ofSize: 14)
        label.textColor = .secondaryLabel
        label.numberOfLines = 0
        label.isHidden = true
        return label
    }()

    // Error card
    private lazy var errorCard: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.backgroundColor = .systemRed.withAlphaComponent(0.1)
        view.layer.cornerRadius = 12
        view.isHidden = true
        return view
    }()

    private lazy var errorIcon: UIImageView = {
        let imageView = UIImageView()
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.image = UIImage(systemName: "exclamationmark.triangle.fill")
        imageView.tintColor = .systemRed
        imageView.contentMode = .scaleAspectFit
        return imageView
    }()

    private lazy var errorMessageLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .systemFont(ofSize: 15)
        label.textColor = .systemRed
        label.textAlignment = .center
        label.numberOfLines = 0
        return label
    }()

    private lazy var retryButton: UIButton = {
        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.setTitle("Try Again", for: .normal)
        button.addTarget(self, action: #selector(retryTapped), for: .touchUpInside)
        return button
    }()

    private lazy var goToLoginButton: UIButton = {
        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.setTitle("Go to Login", for: .normal)
        button.applyPrimaryStyle()
        button.addTarget(self, action: #selector(goToLoginTapped), for: .touchUpInside)
        return button
    }()

    // Multi-auth buttons container (shown between invitation card and wallet section)
    private lazy var authButtonsContainer: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.isHidden = true
        return view
    }()

    private lazy var acceptAsExistingButton: UIButton = {
        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.setTitle("Sign In to Accept", for: .normal)
        button.applySecondaryStyle()
        button.addTarget(self, action: #selector(acceptAsExistingTapped), for: .touchUpInside)
        return button
    }()

    private lazy var acceptExistingSpinner: UIActivityIndicatorView = {
        let indicator = UIActivityIndicatorView(style: .medium)
        indicator.translatesAutoresizingMaskIntoConstraints = false
        indicator.hidesWhenStopped = true
        return indicator
    }()

    private lazy var orCreateAccountLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.text = "or create account"
        label.font = .systemFont(ofSize: 13, weight: .medium)
        label.textColor = .secondaryLabel
        label.textAlignment = .center
        return label
    }()

    private lazy var continueWithEmailButton: UIButton = {
        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.setTitle("Continue with Email", for: .normal)
        button.applySecondaryStyle()
        button.addTarget(self, action: #selector(continueWithEmailTapped), for: .touchUpInside)
        return button
    }()

    private lazy var signInWithGoogleButton: UIButton = {
        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.setTitle("Sign in with Google", for: .normal)
        button.applySecondaryStyle()
        button.addTarget(self, action: #selector(signInWithGoogleTapped), for: .touchUpInside)
        return button
    }()

    private lazy var signInWithMicrosoftButton: UIButton = {
        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.setTitle("Sign in with Microsoft", for: .normal)
        button.applySecondaryStyle()
        button.addTarget(self, action: #selector(signInWithMicrosoftTapped), for: .touchUpInside)
        return button
    }()

    private lazy var acceptErrorLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.textColor = .systemRed
        label.font = .systemFont(ofSize: 14)
        label.textAlignment = .center
        label.numberOfLines = 0
        label.isHidden = true
        return label
    }()

    // Wallet action container
    private lazy var walletContainer: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.isHidden = true
        return view
    }()

    private lazy var walletIcon: UIImageView = {
        let imageView = UIImageView()
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.image = UIImage(systemName: "wallet.pass")
        imageView.tintColor = .systemBlue
        imageView.contentMode = .scaleAspectFit
        return imageView
    }()

    private lazy var walletDescriptionLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.text = "Accept this invitation using your SSDID Wallet. Your identity and encryption keys will be managed securely by the wallet."
        label.font = .systemFont(ofSize: 15)
        label.textColor = .secondaryLabel
        label.textAlignment = .center
        label.numberOfLines = 0
        return label
    }()

    private lazy var registrationErrorLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.textColor = .systemRed
        label.font = .systemFont(ofSize: 14)
        label.textAlignment = .center
        label.numberOfLines = 0
        label.isHidden = true
        return label
    }()

    private lazy var acceptWithWalletButton: UIButton = {
        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.setTitle("Accept with SSDID Wallet", for: .normal)
        button.applyPrimaryStyle()
        button.addTarget(self, action: #selector(acceptWithWalletTapped), for: .touchUpInside)
        return button
    }()

    private lazy var buttonActivityIndicator: UIActivityIndicatorView = {
        let indicator = UIActivityIndicatorView(style: .medium)
        indicator.translatesAutoresizingMaskIntoConstraints = false
        indicator.hidesWhenStopped = true
        indicator.color = .white
        return indicator
    }()

    private lazy var waitingActivityIndicator: UIActivityIndicatorView = {
        let indicator = UIActivityIndicatorView(style: .medium)
        indicator.hidesWhenStopped = true
        return indicator
    }()

    private lazy var waitingStack: UIStackView = {
        let label = UILabel()
        label.text = "Waiting for SSDID Wallet..."
        label.font = .systemFont(ofSize: 13)
        label.textColor = .secondaryLabel

        let stack = UIStackView(arrangedSubviews: [waitingActivityIndicator, label])
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .horizontal
        stack.spacing = 8
        stack.alignment = .center
        stack.isHidden = true
        return stack
    }()

    private lazy var loginLinkButton: UIButton = {
        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false

        let prefix = "Already have an account? "
        let action = "Sign In"
        let text = prefix + action
        let attributedString = NSMutableAttributedString(string: text)
        attributedString.addAttribute(.foregroundColor, value: UIColor.secondaryLabel, range: NSRange(location: 0, length: prefix.count))
        attributedString.addAttribute(.foregroundColor, value: UIColor.systemBlue, range: NSRange(location: prefix.count, length: action.count))
        attributedString.addAttribute(.font, value: UIFont.systemFont(ofSize: 15, weight: .semibold), range: NSRange(location: prefix.count, length: action.count))

        button.setAttributedTitle(attributedString, for: .normal)
        button.addTarget(self, action: #selector(loginLinkTapped), for: .touchUpInside)
        return button
    }()

    // MARK: - Initialization

    init(viewModel: InviteAcceptViewModel) {
        self.viewModel = viewModel
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Setup

    override func setupUI() {
        view.addSubview(scrollView)
        scrollView.addSubview(contentView)

        // Header
        contentView.addSubview(logoImageView)
        contentView.addSubview(titleLabel)
        contentView.addSubview(subtitleLabel)

        // Loading state
        contentView.addSubview(loadingIndicator)
        contentView.addSubview(loadingLabel)

        // Invitation card
        contentView.addSubview(invitationCard)
        invitationCard.addSubview(organizationLabel)
        invitationCard.addSubview(tenantNameLabel)
        invitationCard.addSubview(inviterLabel)
        invitationCard.addSubview(emailInfoLabel)
        invitationCard.addSubview(messageLabel)

        // Error card
        contentView.addSubview(errorCard)
        errorCard.addSubview(errorIcon)
        errorCard.addSubview(errorMessageLabel)
        errorCard.addSubview(retryButton)
        errorCard.addSubview(goToLoginButton)

        // Multi-auth buttons
        contentView.addSubview(authButtonsContainer)
        authButtonsContainer.addSubview(acceptAsExistingButton)
        authButtonsContainer.addSubview(acceptExistingSpinner)
        authButtonsContainer.addSubview(acceptErrorLabel)
        authButtonsContainer.addSubview(orCreateAccountLabel)
        authButtonsContainer.addSubview(continueWithEmailButton)
        authButtonsContainer.addSubview(signInWithGoogleButton)
        authButtonsContainer.addSubview(signInWithMicrosoftButton)

        // Wallet action
        contentView.addSubview(walletContainer)
        walletContainer.addSubview(walletIcon)
        walletContainer.addSubview(walletDescriptionLabel)
        walletContainer.addSubview(registrationErrorLabel)
        walletContainer.addSubview(acceptWithWalletButton)
        walletContainer.addSubview(waitingStack)
        walletContainer.addSubview(loginLinkButton)

        acceptWithWalletButton.addSubview(buttonActivityIndicator)

        setupConstraints()
    }

    private func setupConstraints() {
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
            logoImageView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 40),
            logoImageView.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            logoImageView.widthAnchor.constraint(equalToConstant: 70),
            logoImageView.heightAnchor.constraint(equalToConstant: 70),

            // Title
            titleLabel.topAnchor.constraint(equalTo: logoImageView.bottomAnchor, constant: 16),
            titleLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 24),
            titleLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -24),

            // Subtitle
            subtitleLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 8),
            subtitleLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 24),
            subtitleLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -24),

            // Loading
            loadingIndicator.topAnchor.constraint(equalTo: subtitleLabel.bottomAnchor, constant: 48),
            loadingIndicator.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),

            loadingLabel.topAnchor.constraint(equalTo: loadingIndicator.bottomAnchor, constant: 16),
            loadingLabel.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),

            // Invitation card
            invitationCard.topAnchor.constraint(equalTo: subtitleLabel.bottomAnchor, constant: 32),
            invitationCard.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 24),
            invitationCard.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -24),

            organizationLabel.topAnchor.constraint(equalTo: invitationCard.topAnchor, constant: 16),
            organizationLabel.leadingAnchor.constraint(equalTo: invitationCard.leadingAnchor, constant: 16),

            tenantNameLabel.topAnchor.constraint(equalTo: organizationLabel.bottomAnchor, constant: 4),
            tenantNameLabel.leadingAnchor.constraint(equalTo: invitationCard.leadingAnchor, constant: 16),
            tenantNameLabel.trailingAnchor.constraint(equalTo: invitationCard.trailingAnchor, constant: -16),

            inviterLabel.topAnchor.constraint(equalTo: tenantNameLabel.bottomAnchor, constant: 12),
            inviterLabel.leadingAnchor.constraint(equalTo: invitationCard.leadingAnchor, constant: 16),
            inviterLabel.trailingAnchor.constraint(equalTo: invitationCard.trailingAnchor, constant: -16),

            emailInfoLabel.topAnchor.constraint(equalTo: inviterLabel.bottomAnchor, constant: 8),
            emailInfoLabel.leadingAnchor.constraint(equalTo: invitationCard.leadingAnchor, constant: 16),
            emailInfoLabel.trailingAnchor.constraint(equalTo: invitationCard.trailingAnchor, constant: -16),

            messageLabel.topAnchor.constraint(equalTo: emailInfoLabel.bottomAnchor, constant: 12),
            messageLabel.leadingAnchor.constraint(equalTo: invitationCard.leadingAnchor, constant: 16),
            messageLabel.trailingAnchor.constraint(equalTo: invitationCard.trailingAnchor, constant: -16),
            messageLabel.bottomAnchor.constraint(equalTo: invitationCard.bottomAnchor, constant: -16),

            // Error card
            errorCard.topAnchor.constraint(equalTo: subtitleLabel.bottomAnchor, constant: 32),
            errorCard.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 24),
            errorCard.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -24),

            errorIcon.topAnchor.constraint(equalTo: errorCard.topAnchor, constant: 24),
            errorIcon.centerXAnchor.constraint(equalTo: errorCard.centerXAnchor),
            errorIcon.widthAnchor.constraint(equalToConstant: 48),
            errorIcon.heightAnchor.constraint(equalToConstant: 48),

            errorMessageLabel.topAnchor.constraint(equalTo: errorIcon.bottomAnchor, constant: 16),
            errorMessageLabel.leadingAnchor.constraint(equalTo: errorCard.leadingAnchor, constant: 24),
            errorMessageLabel.trailingAnchor.constraint(equalTo: errorCard.trailingAnchor, constant: -24),

            retryButton.topAnchor.constraint(equalTo: errorMessageLabel.bottomAnchor, constant: 24),
            retryButton.trailingAnchor.constraint(equalTo: errorCard.centerXAnchor, constant: -8),

            goToLoginButton.topAnchor.constraint(equalTo: errorMessageLabel.bottomAnchor, constant: 24),
            goToLoginButton.leadingAnchor.constraint(equalTo: errorCard.centerXAnchor, constant: 8),
            goToLoginButton.bottomAnchor.constraint(equalTo: errorCard.bottomAnchor, constant: -24),
            goToLoginButton.widthAnchor.constraint(equalToConstant: 120),
            goToLoginButton.heightAnchor.constraint(equalToConstant: 44),

            // Auth buttons container
            authButtonsContainer.topAnchor.constraint(equalTo: invitationCard.bottomAnchor, constant: 24),
            authButtonsContainer.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 32),
            authButtonsContainer.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -32),

            acceptAsExistingButton.topAnchor.constraint(equalTo: authButtonsContainer.topAnchor),
            acceptAsExistingButton.leadingAnchor.constraint(equalTo: authButtonsContainer.leadingAnchor),
            acceptAsExistingButton.trailingAnchor.constraint(equalTo: authButtonsContainer.trailingAnchor),
            acceptAsExistingButton.heightAnchor.constraint(equalToConstant: 50),

            acceptExistingSpinner.centerYAnchor.constraint(equalTo: acceptAsExistingButton.centerYAnchor),
            acceptExistingSpinner.trailingAnchor.constraint(equalTo: acceptAsExistingButton.trailingAnchor, constant: -16),

            acceptErrorLabel.topAnchor.constraint(equalTo: acceptAsExistingButton.bottomAnchor, constant: 8),
            acceptErrorLabel.leadingAnchor.constraint(equalTo: authButtonsContainer.leadingAnchor),
            acceptErrorLabel.trailingAnchor.constraint(equalTo: authButtonsContainer.trailingAnchor),

            orCreateAccountLabel.topAnchor.constraint(equalTo: acceptErrorLabel.bottomAnchor, constant: 16),
            orCreateAccountLabel.centerXAnchor.constraint(equalTo: authButtonsContainer.centerXAnchor),

            continueWithEmailButton.topAnchor.constraint(equalTo: orCreateAccountLabel.bottomAnchor, constant: 16),
            continueWithEmailButton.leadingAnchor.constraint(equalTo: authButtonsContainer.leadingAnchor),
            continueWithEmailButton.trailingAnchor.constraint(equalTo: authButtonsContainer.trailingAnchor),
            continueWithEmailButton.heightAnchor.constraint(equalToConstant: 50),

            signInWithGoogleButton.topAnchor.constraint(equalTo: continueWithEmailButton.bottomAnchor, constant: 12),
            signInWithGoogleButton.leadingAnchor.constraint(equalTo: authButtonsContainer.leadingAnchor),
            signInWithGoogleButton.trailingAnchor.constraint(equalTo: authButtonsContainer.trailingAnchor),
            signInWithGoogleButton.heightAnchor.constraint(equalToConstant: 50),

            signInWithMicrosoftButton.topAnchor.constraint(equalTo: signInWithGoogleButton.bottomAnchor, constant: 12),
            signInWithMicrosoftButton.leadingAnchor.constraint(equalTo: authButtonsContainer.leadingAnchor),
            signInWithMicrosoftButton.trailingAnchor.constraint(equalTo: authButtonsContainer.trailingAnchor),
            signInWithMicrosoftButton.heightAnchor.constraint(equalToConstant: 50),
            signInWithMicrosoftButton.bottomAnchor.constraint(equalTo: authButtonsContainer.bottomAnchor),

            // Wallet container
            walletContainer.topAnchor.constraint(equalTo: authButtonsContainer.bottomAnchor, constant: 24),
            walletContainer.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 24),
            walletContainer.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -24),
            walletContainer.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -40),

            walletIcon.topAnchor.constraint(equalTo: walletContainer.topAnchor),
            walletIcon.centerXAnchor.constraint(equalTo: walletContainer.centerXAnchor),
            walletIcon.widthAnchor.constraint(equalToConstant: 48),
            walletIcon.heightAnchor.constraint(equalToConstant: 48),

            walletDescriptionLabel.topAnchor.constraint(equalTo: walletIcon.bottomAnchor, constant: 16),
            walletDescriptionLabel.leadingAnchor.constraint(equalTo: walletContainer.leadingAnchor),
            walletDescriptionLabel.trailingAnchor.constraint(equalTo: walletContainer.trailingAnchor),

            registrationErrorLabel.topAnchor.constraint(equalTo: walletDescriptionLabel.bottomAnchor, constant: 16),
            registrationErrorLabel.leadingAnchor.constraint(equalTo: walletContainer.leadingAnchor),
            registrationErrorLabel.trailingAnchor.constraint(equalTo: walletContainer.trailingAnchor),

            acceptWithWalletButton.topAnchor.constraint(equalTo: registrationErrorLabel.bottomAnchor, constant: 24),
            acceptWithWalletButton.leadingAnchor.constraint(equalTo: walletContainer.leadingAnchor),
            acceptWithWalletButton.trailingAnchor.constraint(equalTo: walletContainer.trailingAnchor),
            acceptWithWalletButton.heightAnchor.constraint(equalToConstant: 52),

            buttonActivityIndicator.centerXAnchor.constraint(equalTo: acceptWithWalletButton.centerXAnchor),
            buttonActivityIndicator.centerYAnchor.constraint(equalTo: acceptWithWalletButton.centerYAnchor),

            waitingStack.topAnchor.constraint(equalTo: acceptWithWalletButton.bottomAnchor, constant: 16),
            waitingStack.centerXAnchor.constraint(equalTo: walletContainer.centerXAnchor),

            loginLinkButton.topAnchor.constraint(equalTo: waitingStack.bottomAnchor, constant: 24),
            loginLinkButton.centerXAnchor.constraint(equalTo: walletContainer.centerXAnchor),
            loginLinkButton.bottomAnchor.constraint(equalTo: walletContainer.bottomAnchor)
        ])
    }

    override func setupBindings() {
        // Loading state
        viewModel.$isLoadingInvitation
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isLoading in
                self?.loadingIndicator.isHidden = !isLoading
                self?.loadingLabel.isHidden = !isLoading
                if isLoading {
                    self?.loadingIndicator.startAnimating()
                } else {
                    self?.loadingIndicator.stopAnimating()
                }
            }
            .store(in: &cancellables)

        // Invitation
        viewModel.$invitation
            .receive(on: DispatchQueue.main)
            .sink { [weak self] invitation in
                self?.updateInvitationUI(invitation)
            }
            .store(in: &cancellables)

        // Invitation error
        viewModel.$invitationError
            .receive(on: DispatchQueue.main)
            .sink { [weak self] error in
                self?.updateInvitationError(error)
            }
            .store(in: &cancellables)

        // Loading (launching wallet)
        viewModel.$isLoading
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isLoading in
                self?.updateLaunchingState(isLoading)
            }
            .store(in: &cancellables)

        // Waiting for wallet
        viewModel.$isWaitingForWallet
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isWaiting in
                self?.waitingStack.isHidden = !isWaiting
                self?.authButtonsContainer.isHidden = isWaiting || self?.viewModel.invitation == nil || self?.viewModel.invitation?.valid == false
                if isWaiting {
                    self?.waitingActivityIndicator.startAnimating()
                } else {
                    self?.waitingActivityIndicator.stopAnimating()
                }
            }
            .store(in: &cancellables)

        // Registration error
        viewModel.$registrationError
            .receive(on: DispatchQueue.main)
            .sink { [weak self] error in
                self?.registrationErrorLabel.text = error
                self?.registrationErrorLabel.isHidden = error == nil
            }
            .store(in: &cancellables)

        // Accepting as existing user
        viewModel.$isAcceptingAsExisting
            .receive(on: DispatchQueue.main)
            .sink { [weak self] accepting in
                self?.acceptAsExistingButton.isEnabled = !accepting
                if accepting {
                    self?.acceptExistingSpinner.startAnimating()
                } else {
                    self?.acceptExistingSpinner.stopAnimating()
                }
            }
            .store(in: &cancellables)

        // Accept error
        viewModel.$acceptError
            .receive(on: DispatchQueue.main)
            .sink { [weak self] error in
                self?.acceptErrorLabel.text = error
                self?.acceptErrorLabel.isHidden = error == nil
            }
            .store(in: &cancellables)
    }

    // MARK: - UI Updates

    private func updateInvitationUI(_ invitation: TokenInvitation?) {
        guard let invitation = invitation, invitation.valid else {
            invitationCard.isHidden = true
            walletContainer.isHidden = true
            authButtonsContainer.isHidden = true
            return
        }

        invitationCard.isHidden = false
        walletContainer.isHidden = false
        authButtonsContainer.isHidden = false
        errorCard.isHidden = true

        tenantNameLabel.text = invitation.tenantName

        if let inviterName = invitation.inviterName {
            inviterLabel.text = "Invited by \(inviterName)"
            inviterLabel.isHidden = false
        } else {
            inviterLabel.isHidden = true
        }

        emailInfoLabel.text = "Your email: \(invitation.email)"

        if let message = invitation.message, !message.isEmpty {
            messageLabel.text = "\"\(message)\""
            messageLabel.isHidden = false
        } else {
            messageLabel.isHidden = true
        }
    }

    private func updateInvitationError(_ error: String?) {
        guard let error = error else {
            errorCard.isHidden = true
            return
        }

        invitationCard.isHidden = true
        walletContainer.isHidden = true
        authButtonsContainer.isHidden = true
        errorCard.isHidden = false
        errorMessageLabel.text = error
    }

    private func updateLaunchingState(_ isLaunching: Bool) {
        if isLaunching {
            acceptWithWalletButton.setTitle("", for: .normal)
            buttonActivityIndicator.startAnimating()
            acceptWithWalletButton.isEnabled = false
        } else {
            acceptWithWalletButton.setTitle("Accept with SSDID Wallet", for: .normal)
            buttonActivityIndicator.stopAnimating()
            acceptWithWalletButton.isEnabled = true
        }
    }

    // MARK: - Actions

    @objc private func acceptAsExistingTapped() {
        triggerHapticFeedback()
        viewModel.acceptAsExistingUser()
    }

    @objc private func continueWithEmailTapped() {
        triggerSelectionFeedback()
        viewModel.requestEmailRegister()
    }

    @objc private func signInWithGoogleTapped() {
        triggerSelectionFeedback()
        viewModel.requestOidc(provider: "google")
    }

    @objc private func signInWithMicrosoftTapped() {
        triggerSelectionFeedback()
        viewModel.requestOidc(provider: "microsoft")
    }

    @objc private func acceptWithWalletTapped() {
        triggerHapticFeedback()
        viewModel.acceptWithWallet()
    }

    @objc private func retryTapped() {
        triggerSelectionFeedback()
        viewModel.loadInvitationInfo()
    }

    @objc private func goToLoginTapped() {
        triggerSelectionFeedback()
        viewModel.requestLogin()
    }

    @objc private func loginLinkTapped() {
        triggerSelectionFeedback()
        viewModel.requestLogin()
    }
}
