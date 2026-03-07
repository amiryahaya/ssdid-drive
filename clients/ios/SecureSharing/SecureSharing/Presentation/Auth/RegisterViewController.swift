import UIKit
import Combine

/// Register view controller
final class RegisterViewController: BaseViewController {

    // MARK: - Properties

    private let viewModel: RegisterViewModel

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
        imageView.image = UIImage(systemName: "person.badge.plus.fill")
        imageView.tintColor = .systemBlue
        imageView.contentMode = .scaleAspectFit
        return imageView
    }()

    private lazy var titleLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.text = "Create Account"
        label.font = .systemFont(ofSize: 28, weight: .bold)
        label.textAlignment = .center
        return label
    }()

    private lazy var subtitleLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.text = "Join SecureSharing with quantum-resistant encryption"
        label.font = .systemFont(ofSize: 15)
        label.textColor = .secondaryLabel
        label.textAlignment = .center
        label.numberOfLines = 0
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
        textField.accessibilityIdentifier = "registerEmailTextField"
        textField.accessibilityLabel = "Email address"
        textField.applySecureSharingStyle()
        textField.addTarget(self, action: #selector(textFieldDidChange), for: .editingChanged)
        return textField
    }()

    private lazy var passwordTextField: UITextField = {
        let textField = UITextField()
        textField.translatesAutoresizingMaskIntoConstraints = false
        textField.placeholder = "Password (min 8 characters)"
        textField.isSecureTextEntry = true
        textField.textContentType = .newPassword
        textField.accessibilityIdentifier = "registerPasswordTextField"
        textField.accessibilityLabel = "Password"
        textField.applySecureSharingStyle()
        textField.addTarget(self, action: #selector(textFieldDidChange), for: .editingChanged)
        return textField
    }()

    private lazy var confirmPasswordTextField: UITextField = {
        let textField = UITextField()
        textField.translatesAutoresizingMaskIntoConstraints = false
        textField.placeholder = "Confirm password"
        textField.isSecureTextEntry = true
        textField.textContentType = .newPassword
        textField.accessibilityIdentifier = "registerConfirmPasswordTextField"
        textField.accessibilityLabel = "Confirm password"
        textField.applySecureSharingStyle()
        textField.addTarget(self, action: #selector(textFieldDidChange), for: .editingChanged)
        return textField
    }()

    private lazy var passwordStrengthView: PasswordStrengthView = {
        let view = PasswordStrengthView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.accessibilityIdentifier = "passwordStrengthView"
        return view
    }()

    private lazy var securityNoticeView: UIView = {
        let container = UIView()
        container.translatesAutoresizingMaskIntoConstraints = false
        container.backgroundColor = .systemGray6
        container.layer.cornerRadius = 12

        let icon = UIImageView(image: UIImage(systemName: "shield.checkered"))
        icon.translatesAutoresizingMaskIntoConstraints = false
        icon.tintColor = .systemBlue

        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.text = "Your files will be encrypted with post-quantum cryptography. Your password never leaves your device."
        label.font = .systemFont(ofSize: 13)
        label.textColor = .secondaryLabel
        label.numberOfLines = 0

        container.addSubview(icon)
        container.addSubview(label)

        NSLayoutConstraint.activate([
            icon.topAnchor.constraint(equalTo: container.topAnchor, constant: 12),
            icon.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 12),
            icon.widthAnchor.constraint(equalToConstant: 24),
            icon.heightAnchor.constraint(equalToConstant: 24),

            label.topAnchor.constraint(equalTo: container.topAnchor, constant: 12),
            label.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 12),
            label.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -12),
            label.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -12)
        ])

        return container
    }()

    private lazy var errorLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.textColor = .systemRed
        label.font = .systemFont(ofSize: 14)
        label.textAlignment = .center
        label.numberOfLines = 0
        label.isHidden = true
        label.accessibilityIdentifier = "registerErrorLabel"
        return label
    }()

    private lazy var registerButton: UIButton = {
        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.setTitle("Create Account", for: .normal)
        button.accessibilityIdentifier = "registerButton"
        button.accessibilityLabel = "Create account"
        button.accessibilityHint = "Double tap to create a new account"
        button.applyPrimaryStyle()
        button.addTarget(self, action: #selector(registerTapped), for: .touchUpInside)
        button.isEnabled = false
        button.alpha = 0.5
        return button
    }()

    private lazy var loginButton: UIButton = {
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
        button.addTarget(self, action: #selector(loginTapped), for: .touchUpInside)
        return button
    }()

    private lazy var activityIndicator: UIActivityIndicatorView = {
        let indicator = UIActivityIndicatorView(style: .medium)
        indicator.translatesAutoresizingMaskIntoConstraints = false
        indicator.hidesWhenStopped = true
        indicator.color = .white
        return indicator
    }()

    // MARK: - Initialization

    init(viewModel: RegisterViewModel) {
        self.viewModel = viewModel
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Setup

    override func setupUI() {
        title = "Create Account"
        setupKeyboardDismissOnTap()

        view.addSubview(scrollView)
        scrollView.addSubview(contentView)

        contentView.addSubview(logoImageView)
        contentView.addSubview(titleLabel)
        contentView.addSubview(subtitleLabel)
        contentView.addSubview(emailTextField)
        contentView.addSubview(passwordTextField)
        contentView.addSubview(passwordStrengthView)
        contentView.addSubview(confirmPasswordTextField)
        contentView.addSubview(securityNoticeView)
        contentView.addSubview(errorLabel)
        contentView.addSubview(registerButton)
        contentView.addSubview(loginButton)

        registerButton.addSubview(activityIndicator)

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
            logoImageView.widthAnchor.constraint(equalToConstant: 60),
            logoImageView.heightAnchor.constraint(equalToConstant: 60),

            // Title
            titleLabel.topAnchor.constraint(equalTo: logoImageView.bottomAnchor, constant: 16),
            titleLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 24),
            titleLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -24),

            // Subtitle
            subtitleLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 8),
            subtitleLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 24),
            subtitleLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -24),

            // Email
            emailTextField.topAnchor.constraint(equalTo: subtitleLabel.bottomAnchor, constant: 32),
            emailTextField.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 24),
            emailTextField.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -24),
            emailTextField.heightAnchor.constraint(equalToConstant: 52),

            // Password
            passwordTextField.topAnchor.constraint(equalTo: emailTextField.bottomAnchor, constant: 16),
            passwordTextField.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 24),
            passwordTextField.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -24),
            passwordTextField.heightAnchor.constraint(equalToConstant: 52),

            // Password strength
            passwordStrengthView.topAnchor.constraint(equalTo: passwordTextField.bottomAnchor, constant: 8),
            passwordStrengthView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 24),
            passwordStrengthView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -24),
            passwordStrengthView.heightAnchor.constraint(equalToConstant: 20),

            // Confirm password
            confirmPasswordTextField.topAnchor.constraint(equalTo: passwordStrengthView.bottomAnchor, constant: 16),
            confirmPasswordTextField.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 24),
            confirmPasswordTextField.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -24),
            confirmPasswordTextField.heightAnchor.constraint(equalToConstant: 52),

            // Security notice
            securityNoticeView.topAnchor.constraint(equalTo: confirmPasswordTextField.bottomAnchor, constant: 24),
            securityNoticeView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 24),
            securityNoticeView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -24),

            // Error label
            errorLabel.topAnchor.constraint(equalTo: securityNoticeView.bottomAnchor, constant: 16),
            errorLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 24),
            errorLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -24),

            // Register button
            registerButton.topAnchor.constraint(equalTo: errorLabel.bottomAnchor, constant: 24),
            registerButton.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 24),
            registerButton.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -24),
            registerButton.heightAnchor.constraint(equalToConstant: 52),

            // Activity indicator
            activityIndicator.centerXAnchor.constraint(equalTo: registerButton.centerXAnchor),
            activityIndicator.centerYAnchor.constraint(equalTo: registerButton.centerYAnchor),

            // Login button
            loginButton.topAnchor.constraint(equalTo: registerButton.bottomAnchor, constant: 24),
            loginButton.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            loginButton.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -40)
        ])
    }

    override func setupBindings() {
        viewModel.$isLoading
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isLoading in
                self?.updateLoadingState(isLoading)
            }
            .store(in: &cancellables)

        viewModel.$errorMessage
            .receive(on: DispatchQueue.main)
            .sink { [weak self] message in
                self?.errorLabel.text = message
                self?.errorLabel.isHidden = message == nil
            }
            .store(in: &cancellables)
    }

    // MARK: - Actions

    @objc private func textFieldDidChange() {
        let password = passwordTextField.text ?? ""
        passwordStrengthView.updateStrength(for: password)

        let email = emailTextField.text ?? ""
        let confirmPassword = confirmPasswordTextField.text ?? ""

        let isValid = email.contains("@") && password.count >= 8 && password == confirmPassword
        registerButton.isEnabled = isValid
        registerButton.alpha = isValid ? 1.0 : 0.5
    }

    @objc private func registerTapped() {
        triggerHapticFeedback()

        let email = emailTextField.text ?? ""
        let password = passwordTextField.text ?? ""

        viewModel.register(email: email, password: password)
    }

    @objc private func loginTapped() {
        triggerSelectionFeedback()
        viewModel.requestLogin()
    }

    private func updateLoadingState(_ isLoading: Bool) {
        if isLoading {
            registerButton.setTitle("", for: .normal)
            activityIndicator.startAnimating()
            registerButton.isEnabled = false
        } else {
            registerButton.setTitle("Create Account", for: .normal)
            activityIndicator.stopAnimating()
            textFieldDidChange()
        }
    }
}

// MARK: - Password Strength View

final class PasswordStrengthView: UIView {

    private lazy var progressView: UIProgressView = {
        let progress = UIProgressView(progressViewStyle: .default)
        progress.translatesAutoresizingMaskIntoConstraints = false
        progress.trackTintColor = .systemGray5
        return progress
    }()

    private lazy var strengthLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .systemFont(ofSize: 12)
        label.textColor = .secondaryLabel
        return label
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupUI()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupUI() {
        addSubview(progressView)
        addSubview(strengthLabel)

        NSLayoutConstraint.activate([
            progressView.topAnchor.constraint(equalTo: topAnchor),
            progressView.leadingAnchor.constraint(equalTo: leadingAnchor),
            progressView.trailingAnchor.constraint(equalTo: trailingAnchor),
            progressView.heightAnchor.constraint(equalToConstant: 4),

            strengthLabel.topAnchor.constraint(equalTo: progressView.bottomAnchor, constant: 4),
            strengthLabel.leadingAnchor.constraint(equalTo: leadingAnchor)
        ])
    }

    func updateStrength(for password: String) {
        let strength = calculateStrength(password)
        progressView.progress = strength.progress
        progressView.progressTintColor = strength.color
        strengthLabel.text = strength.label
        strengthLabel.textColor = strength.color

        // Accessibility
        isAccessibilityElement = true
        accessibilityLabel = "Password strength"
        accessibilityValue = strength.label
    }

    private func calculateStrength(_ password: String) -> (progress: Float, color: UIColor, label: String) {
        var score = 0

        if password.count >= 8 { score += 1 }
        if password.count >= 12 { score += 1 }
        if password.range(of: "[a-z]", options: .regularExpression) != nil { score += 1 }
        if password.range(of: "[A-Z]", options: .regularExpression) != nil { score += 1 }
        if password.range(of: "[0-9]", options: .regularExpression) != nil { score += 1 }
        if password.range(of: "[^a-zA-Z0-9]", options: .regularExpression) != nil { score += 1 }

        switch score {
        case 0...2:
            return (0.25, .systemRed, "Weak")
        case 3:
            return (0.5, .systemOrange, "Fair")
        case 4...5:
            return (0.75, .systemYellow, "Good")
        default:
            return (1.0, .systemGreen, "Strong")
        }
    }
}
