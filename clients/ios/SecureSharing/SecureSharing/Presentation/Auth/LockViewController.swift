import UIKit
import Combine
import LocalAuthentication

/// Delegate for lock view controller events
protocol LockViewControllerDelegate: AnyObject {
    func lockViewControllerDidUnlock()
}

/// Lock view controller for biometric/PIN unlock
final class LockViewController: BaseViewController {

    weak var delegate: LockViewControllerDelegate?

    // MARK: - Properties

    private let viewModel: LockViewModel

    // MARK: - UI Components

    private lazy var logoImageView: UIImageView = {
        let imageView = UIImageView()
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.image = UIImage(systemName: "lock.shield.fill")
        imageView.tintColor = .systemBlue
        imageView.contentMode = .scaleAspectFit
        return imageView
    }()

    private lazy var titleLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.text = "SecureSharing"
        label.font = .systemFont(ofSize: 28, weight: .bold)
        label.textAlignment = .center
        return label
    }()

    private lazy var subtitleLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.text = "Unlock to access your secure files"
        label.font = .systemFont(ofSize: 15)
        label.textColor = .secondaryLabel
        label.textAlignment = .center
        return label
    }()

    private lazy var pinStackView: UIStackView = {
        let stack = UIStackView()
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .horizontal
        stack.distribution = .fillEqually
        stack.spacing = 12
        return stack
    }()

    private var pinDots: [UIView] = []
    private var enteredPIN: String = ""
    private let pinLength = 6

    private lazy var biometricButton: UIButton = {
        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.tintColor = .systemBlue
        button.addTarget(self, action: #selector(biometricTapped), for: .touchUpInside)
        return button
    }()

    private lazy var numpadStackView: UIStackView = {
        let stack = UIStackView()
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .vertical
        stack.distribution = .fillEqually
        stack.spacing = 12
        return stack
    }()

    private lazy var errorLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.textColor = .systemRed
        label.font = .systemFont(ofSize: 14)
        label.textAlignment = .center
        label.numberOfLines = 0
        label.isHidden = true
        return label
    }()

    private lazy var logoutButton: UIButton = {
        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.setTitle("Log Out", for: .normal)
        button.setTitleColor(.systemRed, for: .normal)
        button.titleLabel?.font = .systemFont(ofSize: 15, weight: .medium)
        button.accessibilityLabel = "Log out"
        button.accessibilityHint = "Double tap to sign out of SecureSharing"
        button.addTarget(self, action: #selector(logoutTapped), for: .touchUpInside)
        return button
    }()

    private lazy var activityIndicator: UIActivityIndicatorView = {
        let indicator = UIActivityIndicatorView(style: .large)
        indicator.translatesAutoresizingMaskIntoConstraints = false
        indicator.hidesWhenStopped = true
        indicator.color = .systemBlue
        return indicator
    }()

    // MARK: - Initialization

    init(viewModel: LockViewModel) {
        self.viewModel = viewModel
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Lifecycle

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        // Auto-trigger biometric on appear if available
        if viewModel.isBiometricAvailable {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                self?.viewModel.unlockWithBiometrics()
            }
        }
    }

    // MARK: - Setup

    override func setupUI() {
        view.backgroundColor = .systemBackground

        setupPinDots()
        setupNumpad()
        updateBiometricButton()

        view.addSubview(logoImageView)
        view.addSubview(titleLabel)
        view.addSubview(subtitleLabel)
        view.addSubview(pinStackView)
        view.addSubview(biometricButton)
        view.addSubview(numpadStackView)
        view.addSubview(errorLabel)
        view.addSubview(logoutButton)
        view.addSubview(activityIndicator)

        NSLayoutConstraint.activate([
            // Logo
            logoImageView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 60),
            logoImageView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            logoImageView.widthAnchor.constraint(equalToConstant: 70),
            logoImageView.heightAnchor.constraint(equalToConstant: 70),

            // Title
            titleLabel.topAnchor.constraint(equalTo: logoImageView.bottomAnchor, constant: 16),
            titleLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            titleLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),

            // Subtitle
            subtitleLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 8),
            subtitleLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            subtitleLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),

            // PIN dots
            pinStackView.topAnchor.constraint(equalTo: subtitleLabel.bottomAnchor, constant: 40),
            pinStackView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            pinStackView.heightAnchor.constraint(equalToConstant: 16),

            // Biometric button
            biometricButton.topAnchor.constraint(equalTo: pinStackView.bottomAnchor, constant: 24),
            biometricButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            biometricButton.widthAnchor.constraint(equalToConstant: 60),
            biometricButton.heightAnchor.constraint(equalToConstant: 60),

            // Error label
            errorLabel.topAnchor.constraint(equalTo: biometricButton.bottomAnchor, constant: 16),
            errorLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            errorLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),

            // Numpad
            numpadStackView.topAnchor.constraint(equalTo: errorLabel.bottomAnchor, constant: 24),
            numpadStackView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            numpadStackView.widthAnchor.constraint(equalToConstant: 280),
            numpadStackView.heightAnchor.constraint(equalToConstant: 320),

            // Logout button
            logoutButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -24),
            logoutButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),

            // Activity indicator
            activityIndicator.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            activityIndicator.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])
    }

    private func setupPinDots() {
        for _ in 0..<pinLength {
            let dot = UIView()
            dot.translatesAutoresizingMaskIntoConstraints = false
            dot.backgroundColor = .systemGray4
            dot.layer.cornerRadius = 8

            NSLayoutConstraint.activate([
                dot.widthAnchor.constraint(equalToConstant: 16),
                dot.heightAnchor.constraint(equalToConstant: 16)
            ])

            pinDots.append(dot)
            pinStackView.addArrangedSubview(dot)
        }
    }

    private func setupNumpad() {
        let rows = [
            ["1", "2", "3"],
            ["4", "5", "6"],
            ["7", "8", "9"],
            ["", "0", "⌫"]
        ]

        for row in rows {
            let rowStack = UIStackView()
            rowStack.axis = .horizontal
            rowStack.distribution = .fillEqually
            rowStack.spacing = 12

            for key in row {
                let button = createNumpadButton(key)
                rowStack.addArrangedSubview(button)
            }

            numpadStackView.addArrangedSubview(rowStack)
        }
    }

    private func createNumpadButton(_ key: String) -> UIButton {
        let button = UIButton(type: .system)
        button.setTitle(key, for: .normal)
        button.titleLabel?.font = .systemFont(ofSize: 28, weight: .medium)
        button.setTitleColor(.label, for: .normal)
        button.backgroundColor = .systemGray6
        button.layer.cornerRadius = 40

        if key.isEmpty {
            button.isEnabled = false
            button.backgroundColor = .clear
        } else if key == "⌫" {
            button.setTitle(nil, for: .normal)
            button.setImage(UIImage(systemName: "delete.left"), for: .normal)
            button.tintColor = .label
            button.addTarget(self, action: #selector(deleteTapped), for: .touchUpInside)
        } else {
            button.addTarget(self, action: #selector(numpadTapped(_:)), for: .touchUpInside)
        }

        return button
    }

    private func updateBiometricButton() {
        if viewModel.isBiometricAvailable {
            biometricButton.isHidden = false
            let imageName = viewModel.biometricType == .faceID ? "faceid" : "touchid"
            biometricButton.setImage(UIImage(systemName: imageName)?.withConfiguration(
                UIImage.SymbolConfiguration(pointSize: 40, weight: .regular)
            ), for: .normal)
            biometricButton.accessibilityLabel = viewModel.biometricType == .faceID ? "Unlock with Face ID" : "Unlock with Touch ID"
        } else {
            biometricButton.isHidden = true
        }
    }

    override func setupBindings() {
        viewModel.$isLoading
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isLoading in
                if isLoading {
                    self?.activityIndicator.startAnimating()
                    self?.numpadStackView.isUserInteractionEnabled = false
                } else {
                    self?.activityIndicator.stopAnimating()
                    self?.numpadStackView.isUserInteractionEnabled = true
                }
            }
            .store(in: &cancellables)

        viewModel.$errorMessage
            .receive(on: DispatchQueue.main)
            .sink { [weak self] message in
                self?.errorLabel.text = message
                self?.errorLabel.isHidden = message == nil

                if message != nil {
                    self?.shakeAndClearPIN()
                }
            }
            .store(in: &cancellables)
    }

    // MARK: - Actions

    @objc private func numpadTapped(_ sender: UIButton) {
        guard let digit = sender.titleLabel?.text, enteredPIN.count < pinLength else { return }

        triggerSelectionFeedback()
        enteredPIN.append(digit)
        updatePinDots()

        if enteredPIN.count == pinLength {
            viewModel.unlockWithPIN(enteredPIN)
        }
    }

    @objc private func deleteTapped() {
        guard !enteredPIN.isEmpty else { return }

        triggerSelectionFeedback()
        enteredPIN.removeLast()
        updatePinDots()
    }

    @objc private func biometricTapped() {
        triggerHapticFeedback()
        viewModel.unlockWithBiometrics()
    }

    @objc private func logoutTapped() {
        let alert = UIAlertController(
            title: "Log Out",
            message: "Are you sure you want to log out? You'll need to sign in again.",
            preferredStyle: .alert
        )

        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Log Out", style: .destructive) { [weak self] _ in
            self?.viewModel.requestLogout()
        })

        present(alert, animated: true)
    }

    // MARK: - Helpers

    private func updatePinDots() {
        for (index, dot) in pinDots.enumerated() {
            dot.backgroundColor = index < enteredPIN.count ? .systemBlue : .systemGray4
        }
        pinStackView.accessibilityValue = "\(enteredPIN.count) of \(pinLength) digits entered"
    }

    private func shakeAndClearPIN() {
        let animation = CAKeyframeAnimation(keyPath: "transform.translation.x")
        animation.timingFunction = CAMediaTimingFunction(name: .linear)
        animation.duration = 0.5
        animation.values = [-20, 20, -15, 15, -10, 10, -5, 5, 0]

        pinStackView.layer.add(animation, forKey: "shake")
        triggerHapticFeedback()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.enteredPIN = ""
            self?.updatePinDots()
        }
    }
}
