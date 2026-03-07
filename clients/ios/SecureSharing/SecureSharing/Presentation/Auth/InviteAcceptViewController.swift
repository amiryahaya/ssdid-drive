import UIKit
import Combine

/// View controller for accepting invitations and registering
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
        label.text = "SecureSharing"
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

    // Registration form
    private lazy var formContainer: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.isHidden = true
        return view
    }()

    private lazy var createAccountLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.text = "Create your account"
        label.font = .systemFont(ofSize: 17, weight: .semibold)
        return label
    }()

    private lazy var emailTextField: UITextField = {
        let textField = UITextField()
        textField.translatesAutoresizingMaskIntoConstraints = false
        textField.placeholder = "Email"
        textField.keyboardType = .emailAddress
        textField.isEnabled = false
        textField.applySecureSharingStyle()
        return textField
    }()

    private lazy var displayNameTextField: UITextField = {
        let textField = UITextField()
        textField.translatesAutoresizingMaskIntoConstraints = false
        textField.placeholder = "Your Name"
        textField.autocapitalizationType = .words
        textField.textContentType = .name
        textField.applySecureSharingStyle()
        textField.addTarget(self, action: #selector(textFieldDidChange), for: .editingChanged)
        return textField
    }()

    private lazy var passwordTextField: UITextField = {
        let textField = UITextField()
        textField.translatesAutoresizingMaskIntoConstraints = false
        textField.placeholder = "Password"
        textField.isSecureTextEntry = true
        textField.textContentType = .newPassword
        textField.applySecureSharingStyle()
        textField.addTarget(self, action: #selector(textFieldDidChange), for: .editingChanged)
        return textField
    }()

    private lazy var passwordHintLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.text = "At least 8 characters"
        label.font = .systemFont(ofSize: 12)
        label.textColor = .secondaryLabel
        return label
    }()

    private lazy var confirmPasswordTextField: UITextField = {
        let textField = UITextField()
        textField.translatesAutoresizingMaskIntoConstraints = false
        textField.placeholder = "Confirm Password"
        textField.isSecureTextEntry = true
        textField.textContentType = .newPassword
        textField.applySecureSharingStyle()
        textField.addTarget(self, action: #selector(textFieldDidChange), for: .editingChanged)
        return textField
    }()

    private lazy var showPasswordButton: UIButton = {
        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.setImage(UIImage(systemName: "eye"), for: .normal)
        button.tintColor = .secondaryLabel
        button.addTarget(self, action: #selector(togglePasswordVisibility), for: .touchUpInside)
        return button
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

    private lazy var keyGenProgressStack: UIStackView = {
        let indicator = UIActivityIndicatorView(style: .medium)
        indicator.startAnimating()

        let label = UILabel()
        label.text = "Generating secure encryption keys..."
        label.font = .systemFont(ofSize: 13)
        label.textColor = .secondaryLabel

        let stack = UIStackView(arrangedSubviews: [indicator, label])
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .horizontal
        stack.spacing = 8
        stack.alignment = .center
        stack.isHidden = true
        return stack
    }()

    private lazy var createAccountButton: UIButton = {
        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.setTitle("Create Account", for: .normal)
        button.applyPrimaryStyle()
        button.addTarget(self, action: #selector(createAccountTapped), for: .touchUpInside)
        button.isEnabled = false
        button.alpha = 0.5
        return button
    }()

    private lazy var buttonActivityIndicator: UIActivityIndicatorView = {
        let indicator = UIActivityIndicatorView(style: .medium)
        indicator.translatesAutoresizingMaskIntoConstraints = false
        indicator.hidesWhenStopped = true
        indicator.color = .white
        return indicator
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
        setupKeyboardDismissOnTap()

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

        // Form
        contentView.addSubview(formContainer)
        formContainer.addSubview(createAccountLabel)
        formContainer.addSubview(emailTextField)
        formContainer.addSubview(displayNameTextField)
        formContainer.addSubview(passwordTextField)
        formContainer.addSubview(passwordHintLabel)
        formContainer.addSubview(showPasswordButton)
        formContainer.addSubview(confirmPasswordTextField)
        formContainer.addSubview(registrationErrorLabel)
        formContainer.addSubview(keyGenProgressStack)
        formContainer.addSubview(createAccountButton)
        formContainer.addSubview(loginLinkButton)

        createAccountButton.addSubview(buttonActivityIndicator)

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

            // Form container
            formContainer.topAnchor.constraint(equalTo: invitationCard.bottomAnchor, constant: 24),
            formContainer.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 24),
            formContainer.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -24),
            formContainer.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -40),

            createAccountLabel.topAnchor.constraint(equalTo: formContainer.topAnchor),
            createAccountLabel.leadingAnchor.constraint(equalTo: formContainer.leadingAnchor),

            emailTextField.topAnchor.constraint(equalTo: createAccountLabel.bottomAnchor, constant: 16),
            emailTextField.leadingAnchor.constraint(equalTo: formContainer.leadingAnchor),
            emailTextField.trailingAnchor.constraint(equalTo: formContainer.trailingAnchor),
            emailTextField.heightAnchor.constraint(equalToConstant: 52),

            displayNameTextField.topAnchor.constraint(equalTo: emailTextField.bottomAnchor, constant: 16),
            displayNameTextField.leadingAnchor.constraint(equalTo: formContainer.leadingAnchor),
            displayNameTextField.trailingAnchor.constraint(equalTo: formContainer.trailingAnchor),
            displayNameTextField.heightAnchor.constraint(equalToConstant: 52),

            passwordTextField.topAnchor.constraint(equalTo: displayNameTextField.bottomAnchor, constant: 16),
            passwordTextField.leadingAnchor.constraint(equalTo: formContainer.leadingAnchor),
            passwordTextField.trailingAnchor.constraint(equalTo: formContainer.trailingAnchor),
            passwordTextField.heightAnchor.constraint(equalToConstant: 52),

            showPasswordButton.centerYAnchor.constraint(equalTo: passwordTextField.centerYAnchor),
            showPasswordButton.trailingAnchor.constraint(equalTo: passwordTextField.trailingAnchor, constant: -12),
            showPasswordButton.widthAnchor.constraint(equalToConstant: 44),
            showPasswordButton.heightAnchor.constraint(equalToConstant: 44),

            passwordHintLabel.topAnchor.constraint(equalTo: passwordTextField.bottomAnchor, constant: 4),
            passwordHintLabel.leadingAnchor.constraint(equalTo: formContainer.leadingAnchor, constant: 4),

            confirmPasswordTextField.topAnchor.constraint(equalTo: passwordHintLabel.bottomAnchor, constant: 12),
            confirmPasswordTextField.leadingAnchor.constraint(equalTo: formContainer.leadingAnchor),
            confirmPasswordTextField.trailingAnchor.constraint(equalTo: formContainer.trailingAnchor),
            confirmPasswordTextField.heightAnchor.constraint(equalToConstant: 52),

            registrationErrorLabel.topAnchor.constraint(equalTo: confirmPasswordTextField.bottomAnchor, constant: 16),
            registrationErrorLabel.leadingAnchor.constraint(equalTo: formContainer.leadingAnchor),
            registrationErrorLabel.trailingAnchor.constraint(equalTo: formContainer.trailingAnchor),

            keyGenProgressStack.topAnchor.constraint(equalTo: registrationErrorLabel.bottomAnchor, constant: 12),
            keyGenProgressStack.centerXAnchor.constraint(equalTo: formContainer.centerXAnchor),

            createAccountButton.topAnchor.constraint(equalTo: keyGenProgressStack.bottomAnchor, constant: 24),
            createAccountButton.leadingAnchor.constraint(equalTo: formContainer.leadingAnchor),
            createAccountButton.trailingAnchor.constraint(equalTo: formContainer.trailingAnchor),
            createAccountButton.heightAnchor.constraint(equalToConstant: 52),

            buttonActivityIndicator.centerXAnchor.constraint(equalTo: createAccountButton.centerXAnchor),
            buttonActivityIndicator.centerYAnchor.constraint(equalTo: createAccountButton.centerYAnchor),

            loginLinkButton.topAnchor.constraint(equalTo: createAccountButton.bottomAnchor, constant: 24),
            loginLinkButton.centerXAnchor.constraint(equalTo: formContainer.centerXAnchor),
            loginLinkButton.bottomAnchor.constraint(equalTo: formContainer.bottomAnchor)
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

        // Registration state
        viewModel.$isRegistering
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isRegistering in
                self?.updateRegistrationState(isRegistering)
            }
            .store(in: &cancellables)

        // Key generation
        viewModel.$isGeneratingKeys
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isGenerating in
                self?.keyGenProgressStack.isHidden = !isGenerating
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
    }

    // MARK: - UI Updates

    private func updateInvitationUI(_ invitation: TokenInvitation?) {
        guard let invitation = invitation, invitation.valid else {
            invitationCard.isHidden = true
            formContainer.isHidden = true
            return
        }

        invitationCard.isHidden = false
        formContainer.isHidden = false
        errorCard.isHidden = true

        tenantNameLabel.text = invitation.tenantName

        if let inviterName = invitation.inviterName {
            inviterLabel.text = "Invited by \(inviterName)"
            inviterLabel.isHidden = false
        } else {
            inviterLabel.isHidden = true
        }

        emailInfoLabel.text = "Your email: \(invitation.email)"
        emailTextField.text = invitation.email

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
        formContainer.isHidden = true
        errorCard.isHidden = false
        errorMessageLabel.text = error
    }

    private func updateRegistrationState(_ isRegistering: Bool) {
        if isRegistering {
            createAccountButton.setTitle("", for: .normal)
            buttonActivityIndicator.startAnimating()
            createAccountButton.isEnabled = false
        } else {
            createAccountButton.setTitle("Create Account", for: .normal)
            buttonActivityIndicator.stopAnimating()
            textFieldDidChange()
        }
    }

    // MARK: - Actions

    @objc private func textFieldDidChange() {
        viewModel.displayName = displayNameTextField.text ?? ""
        viewModel.password = passwordTextField.text ?? ""
        viewModel.confirmPassword = confirmPasswordTextField.text ?? ""

        let isValid = viewModel.isFormValid
        createAccountButton.isEnabled = isValid
        createAccountButton.alpha = isValid ? 1.0 : 0.5
    }

    @objc private func togglePasswordVisibility() {
        passwordTextField.isSecureTextEntry.toggle()
        confirmPasswordTextField.isSecureTextEntry = passwordTextField.isSecureTextEntry
        let imageName = passwordTextField.isSecureTextEntry ? "eye" : "eye.slash"
        showPasswordButton.setImage(UIImage(systemName: imageName), for: .normal)
    }

    @objc private func createAccountTapped() {
        triggerHapticFeedback()
        viewModel.acceptInvitation()
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
