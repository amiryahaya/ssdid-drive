import UIKit
import Combine
import CoreImage.CIFilterBuiltins

/// Login view controller displaying a QR code for SSDID Wallet authentication.
/// On iPad/Mac the user scans the QR with their phone wallet.
/// On iPhone an "Open SSDID Wallet" button launches the wallet app via deep link.
final class LoginViewController: BaseViewController {

    // MARK: - Properties

    private let viewModel: LoginViewModel

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

    private lazy var subtitleLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.text = "Scan with SSDID Wallet to sign in"
        label.font = .systemFont(ofSize: 15)
        label.textColor = .secondaryLabel
        label.textAlignment = .center
        return label
    }()

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

    private lazy var inviteCodeButton: UIButton = {
        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.setTitle("Have an invite code?", for: .normal)
        button.titleLabel?.font = .systemFont(ofSize: 15, weight: .medium)
        button.setTitleColor(.systemBlue, for: .normal)
        button.accessibilityIdentifier = "inviteCodeButton"
        button.accessibilityLabel = "Have an invite code?"
        button.accessibilityHint = "Double tap to enter an organization invite code"
        button.addTarget(self, action: #selector(inviteCodeTapped), for: .touchUpInside)
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
        view.addSubview(scrollView)
        scrollView.addSubview(contentView)

        contentView.addSubview(logoImageView)
        contentView.addSubview(titleLabel)
        contentView.addSubview(subtitleLabel)
        contentView.addSubview(qrImageView)
        contentView.addSubview(activityIndicator)
        contentView.addSubview(errorLabel)
        contentView.addSubview(refreshButton)
        contentView.addSubview(openWalletButton)
        contentView.addSubview(inviteCodeButton)

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

            // QR code
            qrImageView.topAnchor.constraint(equalTo: subtitleLabel.bottomAnchor, constant: 32),
            qrImageView.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            qrImageView.widthAnchor.constraint(equalToConstant: 250),
            qrImageView.heightAnchor.constraint(equalToConstant: 250),

            // Activity indicator (centered on QR area)
            activityIndicator.centerXAnchor.constraint(equalTo: qrImageView.centerXAnchor),
            activityIndicator.centerYAnchor.constraint(equalTo: qrImageView.centerYAnchor),

            // Error label
            errorLabel.topAnchor.constraint(equalTo: qrImageView.bottomAnchor, constant: 16),
            errorLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 24),
            errorLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -24),

            // Refresh button
            refreshButton.topAnchor.constraint(equalTo: errorLabel.bottomAnchor, constant: 16),
            refreshButton.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            refreshButton.widthAnchor.constraint(equalToConstant: 160),
            refreshButton.heightAnchor.constraint(equalToConstant: 44),

            // Open Wallet button
            openWalletButton.topAnchor.constraint(equalTo: refreshButton.bottomAnchor, constant: 24),
            openWalletButton.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 24),
            openWalletButton.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -24),
            openWalletButton.heightAnchor.constraint(equalToConstant: 52),

            // Invite code button
            inviteCodeButton.topAnchor.constraint(equalTo: openWalletButton.bottomAnchor, constant: 24),
            inviteCodeButton.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            inviteCodeButton.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -40)
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
                if isExpired {
                    self?.subtitleLabel.text = "QR code expired"
                } else {
                    self?.subtitleLabel.text = "Scan with SSDID Wallet to sign in"
                }
            }
            .store(in: &cancellables)

        // Wallet deep link availability
        viewModel.$walletDeepLink
            .receive(on: DispatchQueue.main)
            .sink { [weak self] url in
                self?.openWalletButton.isHidden = (url == nil)
            }
            .store(in: &cancellables)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        viewModel.createChallenge()
    }

    // MARK: - Actions

    @objc private func refreshTapped() {
        triggerHapticFeedback()
        viewModel.createChallenge()
    }

    @objc private func openWalletTapped() {
        triggerHapticFeedback()
        viewModel.openWallet()
    }

    @objc private func inviteCodeTapped() {
        triggerSelectionFeedback()
        viewModel.requestJoinTenant()
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
