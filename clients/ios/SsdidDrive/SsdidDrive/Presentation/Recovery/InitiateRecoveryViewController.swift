import UIKit
import Combine

/// Initiate recovery view controller
final class InitiateRecoveryViewController: BaseViewController {

    // MARK: - Properties

    private let viewModel: InitiateRecoveryViewModel

    // MARK: - UI Components

    private lazy var scrollView: UIScrollView = {
        let scroll = UIScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.keyboardDismissMode = .onDrag
        return scroll
    }()

    private lazy var contentView: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private lazy var headerImageView: UIImageView = {
        let imageView = UIImageView()
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.image = UIImage(systemName: "arrow.counterclockwise.circle")
        imageView.tintColor = .systemOrange
        imageView.contentMode = .scaleAspectFit
        return imageView
    }()

    private lazy var titleLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.text = "Account Recovery"
        label.font = .systemFont(ofSize: 24, weight: .bold)
        label.textAlignment = .center
        return label
    }()

    private lazy var descriptionLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.text = "If you've lost access to your account, your trusted contacts can help you recover it."
        label.font = .systemFont(ofSize: 15)
        label.textColor = .secondaryLabel
        label.textAlignment = .center
        label.numberOfLines = 0
        return label
    }()

    private lazy var emailTextField: UITextField = {
        let textField = UITextField()
        textField.translatesAutoresizingMaskIntoConstraints = false
        textField.placeholder = "Enter your email"
        textField.applySsdidDriveStyle()
        textField.keyboardType = .emailAddress
        textField.autocapitalizationType = .none
        textField.addTarget(self, action: #selector(textFieldDidChange), for: .editingChanged)
        return textField
    }()

    private lazy var statusView: UIView = {
        let container = UIView()
        container.translatesAutoresizingMaskIntoConstraints = false
        container.backgroundColor = .systemGray6
        container.layer.cornerRadius = 12
        container.isHidden = true
        return container
    }()

    private lazy var statusIconImageView: UIImageView = {
        let imageView = UIImageView()
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.contentMode = .scaleAspectFit
        return imageView
    }()

    private lazy var statusTitleLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .systemFont(ofSize: 17, weight: .semibold)
        return label
    }()

    private lazy var statusDescriptionLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .systemFont(ofSize: 14)
        label.textColor = .secondaryLabel
        label.numberOfLines = 0
        return label
    }()

    private lazy var actionButton: UIButton = {
        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.setTitle("Check Status", for: .normal)
        button.applyPrimaryStyle()
        button.addTarget(self, action: #selector(actionTapped), for: .touchUpInside)
        button.isEnabled = false
        button.alpha = 0.5
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

    init(viewModel: InitiateRecoveryViewModel) {
        self.viewModel = viewModel
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Setup

    override func setupUI() {
        view.backgroundColor = .systemBackground
        title = "Recovery"

        setupKeyboardDismissOnTap()

        view.addSubview(scrollView)
        scrollView.addSubview(contentView)

        contentView.addSubview(headerImageView)
        contentView.addSubview(titleLabel)
        contentView.addSubview(descriptionLabel)
        contentView.addSubview(emailTextField)
        contentView.addSubview(statusView)
        contentView.addSubview(actionButton)

        statusView.addSubview(statusIconImageView)
        statusView.addSubview(statusTitleLabel)
        statusView.addSubview(statusDescriptionLabel)
        actionButton.addSubview(activityIndicator)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            contentView.topAnchor.constraint(equalTo: scrollView.topAnchor),
            contentView.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor),
            contentView.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor),
            contentView.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor),
            contentView.widthAnchor.constraint(equalTo: scrollView.widthAnchor),

            headerImageView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 40),
            headerImageView.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            headerImageView.widthAnchor.constraint(equalToConstant: 80),
            headerImageView.heightAnchor.constraint(equalToConstant: 80),

            titleLabel.topAnchor.constraint(equalTo: headerImageView.bottomAnchor, constant: 24),
            titleLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 24),
            titleLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -24),

            descriptionLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 12),
            descriptionLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 24),
            descriptionLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -24),

            emailTextField.topAnchor.constraint(equalTo: descriptionLabel.bottomAnchor, constant: 32),
            emailTextField.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 24),
            emailTextField.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -24),
            emailTextField.heightAnchor.constraint(equalToConstant: 52),

            statusView.topAnchor.constraint(equalTo: emailTextField.bottomAnchor, constant: 24),
            statusView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 24),
            statusView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -24),

            statusIconImageView.leadingAnchor.constraint(equalTo: statusView.leadingAnchor, constant: 16),
            statusIconImageView.topAnchor.constraint(equalTo: statusView.topAnchor, constant: 16),
            statusIconImageView.widthAnchor.constraint(equalToConstant: 32),
            statusIconImageView.heightAnchor.constraint(equalToConstant: 32),

            statusTitleLabel.leadingAnchor.constraint(equalTo: statusIconImageView.trailingAnchor, constant: 12),
            statusTitleLabel.trailingAnchor.constraint(equalTo: statusView.trailingAnchor, constant: -16),
            statusTitleLabel.topAnchor.constraint(equalTo: statusView.topAnchor, constant: 16),

            statusDescriptionLabel.leadingAnchor.constraint(equalTo: statusIconImageView.trailingAnchor, constant: 12),
            statusDescriptionLabel.trailingAnchor.constraint(equalTo: statusView.trailingAnchor, constant: -16),
            statusDescriptionLabel.topAnchor.constraint(equalTo: statusTitleLabel.bottomAnchor, constant: 4),
            statusDescriptionLabel.bottomAnchor.constraint(equalTo: statusView.bottomAnchor, constant: -16),

            actionButton.topAnchor.constraint(equalTo: statusView.bottomAnchor, constant: 32),
            actionButton.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 24),
            actionButton.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -24),
            actionButton.heightAnchor.constraint(equalToConstant: 52),
            actionButton.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -32),

            activityIndicator.centerXAnchor.constraint(equalTo: actionButton.centerXAnchor),
            activityIndicator.centerYAnchor.constraint(equalTo: actionButton.centerYAnchor)
        ])
    }

    override func setupBindings() {
        viewModel.$recoveryStatus
            .receive(on: DispatchQueue.main)
            .sink { [weak self] status in
                self?.updateStatusView(status)
            }
            .store(in: &cancellables)

        viewModel.$isLoading
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isLoading in
                if isLoading {
                    self?.actionButton.setTitle("", for: .normal)
                    self?.activityIndicator.startAnimating()
                    self?.actionButton.isEnabled = false
                } else {
                    self?.activityIndicator.stopAnimating()
                    self?.updateActionButton()
                }
            }
            .store(in: &cancellables)

        viewModel.$errorMessage
            .receive(on: DispatchQueue.main)
            .compactMap { $0 }
            .sink { [weak self] message in
                self?.showError(message)
            }
            .store(in: &cancellables)
    }

    // MARK: - Actions

    @objc private func textFieldDidChange() {
        viewModel.email = emailTextField.text ?? ""
        updateActionButton()
    }

    @objc private func actionTapped() {
        triggerHapticFeedback()

        if viewModel.recoveryStatus == nil {
            viewModel.checkRecoveryStatus()
        } else if case .notStarted = viewModel.recoveryStatus {
            viewModel.initiateRecovery()
        } else if case .ready = viewModel.recoveryStatus {
            showNewPasswordDialog()
        }
    }

    // MARK: - Helpers

    private func updateStatusView(_ status: InitiateRecoveryViewModel.RecoveryStatus?) {
        guard let status = status else {
            statusView.isHidden = true
            return
        }

        statusView.isHidden = false

        switch status {
        case .notStarted:
            statusIconImageView.image = UIImage(systemName: "exclamationmark.circle")
            statusIconImageView.tintColor = .systemOrange
            statusTitleLabel.text = "Recovery Available"
            statusDescriptionLabel.text = "You have recovery set up. Tap 'Start Recovery' to request help from your trustees."
            actionButton.setTitle("Start Recovery", for: .normal)

        case .pending(let received, let needed):
            statusIconImageView.image = UIImage(systemName: "clock")
            statusIconImageView.tintColor = .systemBlue
            statusTitleLabel.text = "Waiting for Approvals"
            statusDescriptionLabel.text = "\(received) of \(needed) trustees have approved your recovery request."
            actionButton.setTitle("Check Again", for: .normal)

        case .ready:
            statusIconImageView.image = UIImage(systemName: "checkmark.circle")
            statusIconImageView.tintColor = .systemGreen
            statusTitleLabel.text = "Recovery Ready"
            statusDescriptionLabel.text = "Your trustees have approved the recovery. You can now set a new password."
            actionButton.setTitle("Set New Password", for: .normal)

        case .failed:
            statusIconImageView.image = UIImage(systemName: "xmark.circle")
            statusIconImageView.tintColor = .systemRed
            statusTitleLabel.text = "Recovery Failed"
            statusDescriptionLabel.text = "The recovery request has expired or was rejected."
            actionButton.setTitle("Try Again", for: .normal)
        }
    }

    private func updateActionButton() {
        let canProceed = viewModel.canCheckStatus
        actionButton.isEnabled = canProceed
        actionButton.alpha = canProceed ? 1.0 : 0.5

        if viewModel.recoveryStatus == nil {
            actionButton.setTitle("Check Status", for: .normal)
        }
    }

    private func showNewPasswordDialog() {
        let alert = UIAlertController(
            title: "Set New Password",
            message: "Enter a new password for your account",
            preferredStyle: .alert
        )

        alert.addTextField { textField in
            textField.placeholder = "New password"
            textField.isSecureTextEntry = true
        }

        alert.addTextField { textField in
            textField.placeholder = "Confirm password"
            textField.isSecureTextEntry = true
        }

        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Set Password", style: .default) { [weak self] _ in
            guard let password = alert.textFields?[0].text,
                  let confirm = alert.textFields?[1].text,
                  password == confirm,
                  password.count >= 8 else {
                self?.showError("Passwords must match and be at least 8 characters")
                return
            }
            self?.viewModel.completeRecovery(newPassword: password)
        })

        present(alert, animated: true)
    }
}
