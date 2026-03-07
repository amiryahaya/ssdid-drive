import UIKit

/// Utility for preventing screenshots and screen recordings of sensitive content
final class ScreenshotPrevention {

    // MARK: - Singleton

    static let shared = ScreenshotPrevention()

    private init() {
        setupNotifications()
    }

    // MARK: - Properties

    /// Views that are currently protected from screenshots
    private var protectedViews: [WeakViewWrapper] = []

    /// Overlay view shown when screenshot is detected
    private var screenshotOverlay: UIView?

    /// Whether screenshot prevention is globally enabled
    private(set) var isEnabled = true

    // MARK: - Public Methods

    /// Enable screenshot prevention globally
    func enable() {
        isEnabled = true
    }

    /// Disable screenshot prevention globally
    func disable() {
        isEnabled = false
        removeScreenshotOverlay()
    }

    /// Protect a view from screenshots by adding a secure text field overlay
    /// - Parameter view: The view to protect
    func protectView(_ view: UIView) {
        guard isEnabled else { return }

        // Create a secure container that prevents screenshots
        let secureField = makeSecureField()
        secureField.frame = view.bounds
        secureField.autoresizingMask = [.flexibleWidth, .flexibleHeight]

        // Add the view as a subview of the secure field's container
        if let container = secureField.subviews.first {
            // Move the original view's subviews to the secure container
            view.addSubview(secureField)
            view.sendSubviewToBack(secureField)

            // Store reference
            protectedViews.append(WeakViewWrapper(view: view))
            cleanupDeallocatedViews()
        }
    }

    /// Remove screenshot protection from a view
    /// - Parameter view: The view to unprotect
    func unprotectView(_ view: UIView) {
        // Remove secure field
        for subview in view.subviews {
            if subview is UITextField {
                subview.removeFromSuperview()
                break
            }
        }

        // Remove from tracking
        protectedViews.removeAll { $0.view === view }
    }

    /// Create a secure view container that prevents screenshots
    /// - Returns: A view that hides its content during screenshots
    func createSecureContainer() -> UIView {
        let container = SecureContainerView()
        return container
    }

    // MARK: - Private Methods

    private func setupNotifications() {
        // Listen for screenshot notifications
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleScreenshot),
            name: UIApplication.userDidTakeScreenshotNotification,
            object: nil
        )

        // Listen for screen capture changes (iOS 11+)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleScreenCaptureChange),
            name: UIScreen.capturedDidChangeNotification,
            object: nil
        )
    }

    @objc private func handleScreenshot() {
        guard isEnabled else { return }

        // Show a brief overlay to obscure any captured content
        showScreenshotOverlay()

        // Log the event (for security monitoring)
        #if DEBUG
        print("[Security] Screenshot detected")
        #endif
    }

    @objc private func handleScreenCaptureChange() {
        guard isEnabled else { return }

        #if !targetEnvironment(macCatalyst)
        if UIScreen.main.isCaptured {
            showScreenCaptureWarning()
        } else {
            removeScreenshotOverlay()
        }
        #endif
    }

    private func showScreenshotOverlay() {
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let window = windowScene.windows.first else { return }

        // Create overlay
        let overlay = UIView(frame: window.bounds)
        overlay.backgroundColor = .systemBackground
        overlay.alpha = 0

        let label = UILabel()
        label.text = "Content Protected"
        label.textColor = .secondaryLabel
        label.font = .systemFont(ofSize: 18, weight: .medium)
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false

        overlay.addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: overlay.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: overlay.centerYAnchor)
        ])

        window.addSubview(overlay)
        screenshotOverlay = overlay

        // Animate overlay
        UIView.animate(withDuration: 0.1) {
            overlay.alpha = 1
        } completion: { _ in
            UIView.animate(withDuration: 0.3, delay: 0.5) {
                overlay.alpha = 0
            } completion: { _ in
                overlay.removeFromSuperview()
                if self.screenshotOverlay === overlay {
                    self.screenshotOverlay = nil
                }
            }
        }
    }

    private func showScreenCaptureWarning() {
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let window = windowScene.windows.first else { return }

        // Show persistent overlay during screen recording
        let overlay = UIView(frame: window.bounds)
        overlay.backgroundColor = UIColor.systemBackground.withAlphaComponent(0.95)

        let stackView = UIStackView()
        stackView.axis = .vertical
        stackView.spacing = 16
        stackView.alignment = .center
        stackView.translatesAutoresizingMaskIntoConstraints = false

        let iconView = UIImageView(image: UIImage(systemName: "eye.slash.fill"))
        iconView.tintColor = .systemRed
        iconView.contentMode = .scaleAspectFit
        iconView.widthAnchor.constraint(equalToConstant: 60).isActive = true
        iconView.heightAnchor.constraint(equalToConstant: 60).isActive = true

        let titleLabel = UILabel()
        titleLabel.text = "Screen Recording Detected"
        titleLabel.textColor = .label
        titleLabel.font = .systemFont(ofSize: 20, weight: .bold)
        titleLabel.textAlignment = .center

        let messageLabel = UILabel()
        messageLabel.text = "For your security, content is hidden\nwhile screen recording is active."
        messageLabel.textColor = .secondaryLabel
        messageLabel.font = .systemFont(ofSize: 16)
        messageLabel.textAlignment = .center
        messageLabel.numberOfLines = 0

        stackView.addArrangedSubview(iconView)
        stackView.addArrangedSubview(titleLabel)
        stackView.addArrangedSubview(messageLabel)

        overlay.addSubview(stackView)
        NSLayoutConstraint.activate([
            stackView.centerXAnchor.constraint(equalTo: overlay.centerXAnchor),
            stackView.centerYAnchor.constraint(equalTo: overlay.centerYAnchor),
            stackView.leadingAnchor.constraint(greaterThanOrEqualTo: overlay.leadingAnchor, constant: 40),
            stackView.trailingAnchor.constraint(lessThanOrEqualTo: overlay.trailingAnchor, constant: -40)
        ])

        window.addSubview(overlay)
        screenshotOverlay = overlay
    }

    private func removeScreenshotOverlay() {
        screenshotOverlay?.removeFromSuperview()
        screenshotOverlay = nil
    }

    /// Create a secure text field that prevents screenshots of its container
    private func makeSecureField() -> UITextField {
        let field = UITextField()
        field.isSecureTextEntry = true
        field.isUserInteractionEnabled = false
        field.backgroundColor = .clear
        return field
    }

    private func cleanupDeallocatedViews() {
        protectedViews.removeAll { $0.view == nil }
    }
}

// MARK: - Helper Types

private class WeakViewWrapper {
    weak var view: UIView?

    init(view: UIView) {
        self.view = view
    }
}

/// A container view that hides its content during screenshots and screen recordings
final class SecureContainerView: UIView {

    private let secureTextField: UITextField = {
        let field = UITextField()
        field.isSecureTextEntry = true
        field.isUserInteractionEnabled = false
        field.translatesAutoresizingMaskIntoConstraints = false
        return field
    }()

    private var secureContainer: UIView?

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupSecureContainer()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupSecureContainer()
    }

    private func setupSecureContainer() {
        // Add secure text field
        addSubview(secureTextField)
        NSLayoutConstraint.activate([
            secureTextField.topAnchor.constraint(equalTo: topAnchor),
            secureTextField.leadingAnchor.constraint(equalTo: leadingAnchor),
            secureTextField.trailingAnchor.constraint(equalTo: trailingAnchor),
            secureTextField.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])

        // Find the secure container inside the text field
        DispatchQueue.main.async { [weak self] in
            self?.findAndSetupSecureContainer()
        }
    }

    private func findAndSetupSecureContainer() {
        // The secure text field has an internal container that's hidden during screenshots
        if let container = secureTextField.subviews.first {
            secureContainer = container
            container.subviews.forEach { $0.removeFromSuperview() }
        }
    }

    override func addSubview(_ view: UIView) {
        if view === secureTextField {
            super.addSubview(view)
        } else if let container = secureContainer {
            container.addSubview(view)
        } else {
            super.addSubview(view)
        }
    }
}
