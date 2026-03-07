import UIKit
import Combine

/// Login view controller
final class LoginViewController: BaseViewController {

    // MARK: - Properties

    private let viewModel: LoginViewModel
    private let oidcViewModel: OidcLoginViewModel?
    private let passkeyViewModel: PasskeyLoginViewModel?

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
        imageView.image = UIImage(systemName: "lock.shield.fill")
        imageView.tintColor = .systemBlue
        imageView.contentMode = .scaleAspectFit
        imageView.accessibilityIdentifier = "loginLogoImageView"
        imageView.accessibilityLabel = "SsdidDrive logo"
        return imageView
    }()

    private lazy var titleLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.text = "SsdidDrive"
        label.font = .systemFont(ofSize: 32, weight: .bold)
        label.textAlignment = .center
        label.accessibilityIdentifier = "loginTitleLabel"
        return label
    }()

    private lazy var subtitleLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.text = "Sign in to access your secure files"
        label.font = .systemFont(ofSize: 15)
        label.textColor = .secondaryLabel
        label.textAlignment = .center
        return label
    }()

    private lazy var emailTextField: UITextField = {
        let textField = UITextField()
        textField.translatesAutoresizingMaskIntoConstraints = false
        textField.placeholder = "Email"
        textField.keyboardType = .emailAddress
        textField.autocapitalizationType = .none
        textField.autocorrectionType = .no
        textField.textContentType = .emailAddress
        textField.accessibilityIdentifier = "loginEmailTextField"
        textField.accessibilityLabel = "Email address"
        textField.applySsdidDriveStyle()
        textField.addTarget(self, action: #selector(textFieldDidChange), for: .editingChanged)
        return textField
    }()

    private lazy var passwordTextField: UITextField = {
        let textField = UITextField()
        textField.translatesAutoresizingMaskIntoConstraints = false
        textField.placeholder = "Password"
        textField.isSecureTextEntry = true
        textField.textContentType = .password
        textField.accessibilityIdentifier = "loginPasswordTextField"
        textField.accessibilityLabel = "Password"
        textField.applySsdidDriveStyle()
        textField.addTarget(self, action: #selector(textFieldDidChange), for: .editingChanged)
        return textField
    }()

    private lazy var showPasswordButton: UIButton = {
        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.setImage(UIImage(systemName: "eye"), for: .normal)
        button.tintColor = .secondaryLabel
        button.accessibilityIdentifier = "showPasswordButton"
        button.accessibilityLabel = "Show password"
        button.addTarget(self, action: #selector(togglePasswordVisibility), for: .touchUpInside)
        return button
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

    private lazy var loginButton: UIButton = {
        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.setTitle("Sign In", for: .normal)
        button.accessibilityIdentifier = "loginButton"
        button.accessibilityLabel = "Sign in"
        button.accessibilityHint = "Double tap to sign in with email and password"
        button.applyPrimaryStyle()
        button.addTarget(self, action: #selector(loginTapped), for: .touchUpInside)
        button.isEnabled = false
        button.alpha = 0.5
        return button
    }()

    private lazy var dividerStack: UIStackView = {
        let leftLine = UIView()
        leftLine.translatesAutoresizingMaskIntoConstraints = false
        leftLine.backgroundColor = .separator
        leftLine.heightAnchor.constraint(equalToConstant: 1).isActive = true

        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.text = "OR"
        label.font = .systemFont(ofSize: 13, weight: .medium)
        label.textColor = .secondaryLabel
        label.textAlignment = .center
        label.setContentHuggingPriority(.required, for: .horizontal)

        let rightLine = UIView()
        rightLine.translatesAutoresizingMaskIntoConstraints = false
        rightLine.backgroundColor = .separator
        rightLine.heightAnchor.constraint(equalToConstant: 1).isActive = true

        let stack = UIStackView(arrangedSubviews: [leftLine, label, rightLine])
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .horizontal
        stack.alignment = .center
        stack.spacing = 12
        stack.distribution = .fill
        return stack
    }()

    private lazy var passkeyButton: UIButton = {
        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        let config = UIImage.SymbolConfiguration(pointSize: 16, weight: .medium)
        let icon = UIImage(systemName: "person.badge.key.fill", withConfiguration: config)
        button.setImage(icon, for: .normal)
        button.setTitle("  Sign in with Passkey", for: .normal)
        button.titleLabel?.font = .systemFont(ofSize: 16, weight: .medium)
        button.accessibilityIdentifier = "passkeyButton"
        button.accessibilityLabel = "Sign in with Passkey"
        button.applySecondaryStyle()
        button.addTarget(self, action: #selector(passkeyTapped), for: .touchUpInside)
        return button
    }()

    private lazy var oidcButtonsStack: UIStackView = {
        let stack = UIStackView()
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .vertical
        stack.spacing = 8
        return stack
    }()

    private lazy var noAccountLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.text = "Don't have an account?"
        label.font = .systemFont(ofSize: 15)
        label.textColor = .secondaryLabel
        label.textAlignment = .center
        return label
    }()

    private lazy var contactAdminLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.text = "Contact your administrator to receive an invitation."
        label.font = .systemFont(ofSize: 13)
        label.textColor = .tertiaryLabel
        label.textAlignment = .center
        label.numberOfLines = 0
        return label
    }()

    private lazy var activityIndicator: UIActivityIndicatorView = {
        let indicator = UIActivityIndicatorView(style: .medium)
        indicator.translatesAutoresizingMaskIntoConstraints = false
        indicator.hidesWhenStopped = true
        indicator.color = .white
        return indicator
    }()

    // MARK: - Initialization

    init(
        viewModel: LoginViewModel,
        oidcViewModel: OidcLoginViewModel? = nil,
        passkeyViewModel: PasskeyLoginViewModel? = nil
    ) {
        self.viewModel = viewModel
        self.oidcViewModel = oidcViewModel
        self.passkeyViewModel = passkeyViewModel
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
        contentView.addSubview(subtitleLabel)
        contentView.addSubview(emailTextField)
        contentView.addSubview(passwordTextField)
        contentView.addSubview(showPasswordButton)
        contentView.addSubview(errorLabel)
        contentView.addSubview(loginButton)
        contentView.addSubview(noAccountLabel)
        contentView.addSubview(contactAdminLabel)

        loginButton.addSubview(activityIndicator)

        contentView.addSubview(dividerStack)
        contentView.addSubview(passkeyButton)
        contentView.addSubview(oidcButtonsStack)

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
            titleLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 24),
            titleLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -24),

            // Subtitle
            subtitleLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 8),
            subtitleLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 24),
            subtitleLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -24),

            // Email
            emailTextField.topAnchor.constraint(equalTo: subtitleLabel.bottomAnchor, constant: 48),
            emailTextField.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 24),
            emailTextField.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -24),
            emailTextField.heightAnchor.constraint(equalToConstant: 52),

            // Password
            passwordTextField.topAnchor.constraint(equalTo: emailTextField.bottomAnchor, constant: 16),
            passwordTextField.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 24),
            passwordTextField.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -24),
            passwordTextField.heightAnchor.constraint(equalToConstant: 52),

            // Show password button
            showPasswordButton.centerYAnchor.constraint(equalTo: passwordTextField.centerYAnchor),
            showPasswordButton.trailingAnchor.constraint(equalTo: passwordTextField.trailingAnchor, constant: -12),
            showPasswordButton.widthAnchor.constraint(equalToConstant: 44),
            showPasswordButton.heightAnchor.constraint(equalToConstant: 44),

            // Error label
            errorLabel.topAnchor.constraint(equalTo: passwordTextField.bottomAnchor, constant: 16),
            errorLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 24),
            errorLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -24),

            // Login button
            loginButton.topAnchor.constraint(equalTo: errorLabel.bottomAnchor, constant: 24),
            loginButton.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 24),
            loginButton.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -24),
            loginButton.heightAnchor.constraint(equalToConstant: 52),

            // Activity indicator
            activityIndicator.centerXAnchor.constraint(equalTo: loginButton.centerXAnchor),
            activityIndicator.centerYAnchor.constraint(equalTo: loginButton.centerYAnchor),

            // Divider
            dividerStack.topAnchor.constraint(equalTo: loginButton.bottomAnchor, constant: 24),
            dividerStack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 24),
            dividerStack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -24),

            // Passkey button
            passkeyButton.topAnchor.constraint(equalTo: dividerStack.bottomAnchor, constant: 24),
            passkeyButton.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 24),
            passkeyButton.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -24),
            passkeyButton.heightAnchor.constraint(equalToConstant: 52),

            // OIDC buttons stack
            oidcButtonsStack.topAnchor.constraint(equalTo: passkeyButton.bottomAnchor, constant: 8),
            oidcButtonsStack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 24),
            oidcButtonsStack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -24),

            // No account label
            noAccountLabel.topAnchor.constraint(equalTo: oidcButtonsStack.bottomAnchor, constant: 32),
            noAccountLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 24),
            noAccountLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -24),

            // Contact admin label
            contactAdminLabel.topAnchor.constraint(equalTo: noAccountLabel.bottomAnchor, constant: 4),
            contactAdminLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 24),
            contactAdminLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -24),
            contactAdminLabel.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -40)
        ])

        // Load OIDC providers
        loadOidcProviders()
    }

    override func setupBindings() {
        // Loading state
        viewModel.$isLoading
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isLoading in
                self?.updateLoadingState(isLoading)
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

        // OIDC loading state
        oidcViewModel?.$isLoading
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isLoading in
                self?.oidcButtonsStack.isUserInteractionEnabled = !isLoading
                self?.oidcButtonsStack.alpha = isLoading ? 0.5 : 1.0
            }
            .store(in: &cancellables)

        // OIDC error
        oidcViewModel?.$errorMessage
            .receive(on: DispatchQueue.main)
            .sink { [weak self] message in
                if let message = message {
                    self?.errorLabel.text = message
                    self?.errorLabel.isHidden = false
                }
            }
            .store(in: &cancellables)

        // Passkey loading state
        passkeyViewModel?.$isLoading
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isLoading in
                self?.passkeyButton.isEnabled = !isLoading
                self?.passkeyButton.alpha = isLoading ? 0.5 : 1.0
            }
            .store(in: &cancellables)

        // Passkey error
        passkeyViewModel?.$errorMessage
            .receive(on: DispatchQueue.main)
            .sink { [weak self] message in
                if let message = message {
                    self?.errorLabel.text = message
                    self?.errorLabel.isHidden = false
                }
            }
            .store(in: &cancellables)

        // OIDC providers
        oidcViewModel?.$providers
            .receive(on: DispatchQueue.main)
            .sink { [weak self] providers in
                self?.updateOidcButtons(providers: providers)
            }
            .store(in: &cancellables)
    }

    // MARK: - Actions

    @objc private func textFieldDidChange() {
        let email = emailTextField.text ?? ""
        let password = passwordTextField.text ?? ""

        let isValid = email.contains("@") && password.count >= 8
        loginButton.isEnabled = isValid
        loginButton.alpha = isValid ? 1.0 : 0.5
    }

    @objc private func togglePasswordVisibility() {
        passwordTextField.isSecureTextEntry.toggle()
        let imageName = passwordTextField.isSecureTextEntry ? "eye" : "eye.slash"
        showPasswordButton.setImage(UIImage(systemName: imageName), for: .normal)
        showPasswordButton.accessibilityLabel = passwordTextField.isSecureTextEntry ? "Show password" : "Hide password"
    }

    @objc private func loginTapped() {
        triggerHapticFeedback()

        let email = emailTextField.text ?? ""
        let password = passwordTextField.text ?? ""

        viewModel.login(email: email, password: password)
    }

    @objc private func passkeyTapped() {
        triggerHapticFeedback()

        let email = emailTextField.text?.isEmpty == false ? emailTextField.text : nil
        passkeyViewModel?.beginLogin(email: email, presentationAnchor: view.window!)
    }

    @objc private func oidcProviderTapped(_ sender: UIButton) {
        triggerHapticFeedback()

        guard let providers = oidcViewModel?.providers,
              sender.tag < providers.count else { return }
        let provider = providers[sender.tag]
        oidcViewModel?.beginLogin(providerId: provider.id, presentationAnchor: view.window!)
    }

    // MARK: - OIDC Provider Loading

    private func loadOidcProviders() {
        oidcViewModel?.loadProviders(tenantSlug: "default")
    }

    private func updateOidcButtons(providers: [AuthProvider]) {
        // Remove existing buttons
        oidcButtonsStack.arrangedSubviews.forEach {
            oidcButtonsStack.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }

        // Add a button for each provider
        for (index, provider) in providers.enumerated() {
            let button = UIButton(type: .system)
            button.translatesAutoresizingMaskIntoConstraints = false
            let config = UIImage.SymbolConfiguration(pointSize: 16, weight: .medium)
            let icon = UIImage(systemName: "globe", withConfiguration: config)
            button.setImage(icon, for: .normal)
            button.setTitle("  Sign in with \(provider.name)", for: .normal)
            button.titleLabel?.font = .systemFont(ofSize: 16, weight: .medium)
            button.applySecondaryStyle()
            button.tag = index
            button.addTarget(self, action: #selector(oidcProviderTapped(_:)), for: .touchUpInside)
            button.heightAnchor.constraint(equalToConstant: 52).isActive = true
            oidcButtonsStack.addArrangedSubview(button)
        }
    }

    // MARK: - Helpers

    private func updateLoadingState(_ isLoading: Bool) {
        if isLoading {
            loginButton.setTitle("", for: .normal)
            activityIndicator.startAnimating()
            loginButton.isEnabled = false
        } else {
            loginButton.setTitle("Sign In", for: .normal)
            activityIndicator.stopAnimating()
            textFieldDidChange() // Re-validate
        }
    }
}
