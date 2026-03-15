import UIKit
import Combine

/// Delegate protocol for TOTP verification navigation events
protocol TotpVerifyViewControllerDelegate: AnyObject {
    func totpVerifyDidComplete()
    func totpVerifyDidRequestRecovery(email: String)
}

/// View controller for TOTP two-factor authentication.
/// Displays a 6-digit code input and auto-submits when all digits are entered.
final class TotpVerifyViewController: BaseViewController {

    // MARK: - Properties

    private let viewModel: TotpVerifyViewModel

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

    private lazy var lockImageView: UIImageView = {
        let config = UIImage.SymbolConfiguration(pointSize: 48, weight: .medium)
        let imageView = UIImageView()
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.image = UIImage(systemName: "lock.fill", withConfiguration: config)
        imageView.tintColor = .systemBlue
        imageView.contentMode = .scaleAspectFit
        imageView.accessibilityIdentifier = "totpLockImageView"
        return imageView
    }()

    private lazy var titleLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.text = "Two-Factor Authentication"
        label.font = .systemFont(ofSize: 28, weight: .bold)
        label.textAlignment = .center
        label.numberOfLines = 0
        label.accessibilityIdentifier = "totpTitleLabel"
        return label
    }()

    private lazy var subtitleLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.text = "Enter the 6-digit code from your authenticator app"
        label.font = .systemFont(ofSize: 15)
        label.textColor = .secondaryLabel
        label.textAlignment = .center
        label.numberOfLines = 0
        return label
    }()

    private lazy var codeTextField: UITextField = {
        let field = UITextField()
        field.translatesAutoresizingMaskIntoConstraints = false
        field.font = .monospacedDigitSystemFont(ofSize: 32, weight: .medium)
        field.textAlignment = .center
        field.keyboardType = .numberPad
        field.textContentType = .oneTimeCode
        field.placeholder = "000000"
        field.borderStyle = .none
        field.backgroundColor = .secondarySystemBackground
        field.layer.cornerRadius = 12
        field.accessibilityIdentifier = "totpCodeTextField"
        field.accessibilityLabel = "TOTP verification code"
        field.addTarget(self, action: #selector(codeTextDidChange(_:)), for: .editingChanged)
        return field
    }()

    private lazy var verifyButton: UIButton = {
        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.setTitle("Verify", for: .normal)
        button.applyPrimaryStyle()
        button.accessibilityIdentifier = "totpVerifyButton"
        button.addTarget(self, action: #selector(verifyTapped), for: .touchUpInside)
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
        label.accessibilityIdentifier = "totpErrorLabel"
        return label
    }()

    private lazy var activityIndicator: UIActivityIndicatorView = {
        let indicator = UIActivityIndicatorView(style: .medium)
        indicator.translatesAutoresizingMaskIntoConstraints = false
        indicator.hidesWhenStopped = true
        indicator.color = .white
        return indicator
    }()

    private lazy var recoveryButton: UIButton = {
        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.setTitle("Lost your authenticator? Recover access", for: .normal)
        button.titleLabel?.font = .systemFont(ofSize: 15, weight: .medium)
        button.setTitleColor(.systemBlue, for: .normal)
        button.accessibilityIdentifier = "totpRecoveryButton"
        button.accessibilityLabel = "Lost your authenticator? Recover access"
        button.addTarget(self, action: #selector(recoveryTapped), for: .touchUpInside)
        return button
    }()

    // MARK: - Initialization

    init(viewModel: TotpVerifyViewModel) {
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

        let stackView = UIStackView(arrangedSubviews: [
            lockImageView,
            titleLabel,
            subtitleLabel,
            codeTextField,
            errorLabel,
            verifyButton,
            recoveryButton
        ])
        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.axis = .vertical
        stackView.alignment = .fill
        stackView.spacing = 16

        // Custom spacing after specific items
        stackView.setCustomSpacing(24, after: lockImageView)
        stackView.setCustomSpacing(8, after: titleLabel)
        stackView.setCustomSpacing(32, after: subtitleLabel)
        stackView.setCustomSpacing(16, after: codeTextField)
        stackView.setCustomSpacing(24, after: verifyButton)

        contentView.addSubview(stackView)
        verifyButton.addSubview(activityIndicator)

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

            // Stack view
            stackView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 60),
            stackView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 24),
            stackView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -24),
            stackView.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor, constant: -40),

            // Code text field height
            codeTextField.heightAnchor.constraint(equalToConstant: 64),

            // Verify button height
            verifyButton.heightAnchor.constraint(equalToConstant: 52),

            // Activity indicator centered in verify button
            activityIndicator.centerXAnchor.constraint(equalTo: verifyButton.centerXAnchor),
            activityIndicator.centerYAnchor.constraint(equalTo: verifyButton.centerYAnchor)
        ])
    }

    override func setupBindings() {
        // Error message
        viewModel.$errorMessage
            .receive(on: DispatchQueue.main)
            .sink { [weak self] message in
                self?.errorLabel.text = message
                self?.errorLabel.isHidden = message == nil
            }
            .store(in: &cancellables)

        // Loading state
        viewModel.$isLoading
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isLoading in
                if isLoading {
                    self?.verifyButton.setTitle("", for: .normal)
                    self?.activityIndicator.startAnimating()
                    self?.verifyButton.isEnabled = false
                    self?.codeTextField.isEnabled = false
                } else {
                    self?.verifyButton.setTitle("Verify", for: .normal)
                    self?.activityIndicator.stopAnimating()
                    self?.verifyButton.isEnabled = true
                    self?.codeTextField.isEnabled = true
                }
            }
            .store(in: &cancellables)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        codeTextField.becomeFirstResponder()
    }

    // MARK: - Actions

    @objc private func codeTextDidChange(_ textField: UITextField) {
        // Limit to 6 digits
        let filtered = (textField.text ?? "").filter { $0.isNumber }
        let truncated = String(filtered.prefix(6))

        if textField.text != truncated {
            textField.text = truncated
        }

        viewModel.code = truncated

        // Auto-submit when 6 digits entered
        if truncated.count == 6 {
            triggerHapticFeedback(.light)
            viewModel.verify()
        }
    }

    @objc private func verifyTapped() {
        triggerHapticFeedback()
        viewModel.verify()
    }

    @objc private func recoveryTapped() {
        triggerSelectionFeedback()
        viewModel.requestRecovery()
    }
}
