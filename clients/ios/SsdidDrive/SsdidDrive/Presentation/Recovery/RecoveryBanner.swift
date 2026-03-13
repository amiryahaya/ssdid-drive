import UIKit

/// A dismissible banner that prompts the user to set up account recovery.
/// Shown at most 3 times (tracked via UserDefaults).
/// After the third dismissal the banner should not be shown again.
final class RecoveryBanner: UIView {

    // MARK: - Constants

    private enum Keys {
        static let dismissCount = "recovery_dismiss_count"
        static let maxDismissals = 3
    }

    // MARK: - Callbacks

    /// Called when the user taps the "Set Up Recovery" call-to-action button.
    var onSetupTapped: (() -> Void)?

    // MARK: - Persistence

    private var dismissCount: Int {
        get { UserDefaults.standard.integer(forKey: Keys.dismissCount) }
        set { UserDefaults.standard.set(newValue, forKey: Keys.dismissCount) }
    }

    /// Returns `true` when the banner should be shown (dismissal count not yet exhausted
    /// and recovery has not been set up).
    static var shouldShow: Bool {
        UserDefaults.standard.integer(forKey: Keys.dismissCount) < Keys.maxDismissals
    }

    // MARK: - UI Components

    private lazy var shieldImageView: UIImageView = {
        let imageView = UIImageView()
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.image = UIImage(systemName: "exclamationmark.shield.fill")
        imageView.tintColor = .systemOrange
        imageView.contentMode = .scaleAspectFit
        imageView.setContentHuggingPriority(.required, for: .horizontal)
        imageView.setContentCompressionResistancePriority(.required, for: .horizontal)
        return imageView
    }()

    private lazy var messageLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.text = "Set up account recovery to protect your files if you lose access."
        label.font = .systemFont(ofSize: 13, weight: .medium)
        label.textColor = .label
        label.numberOfLines = 0
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return label
    }()

    private lazy var setupButton: UIButton = {
        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.setTitle("Set Up", for: .normal)
        button.titleLabel?.font = .systemFont(ofSize: 13, weight: .semibold)
        button.setTitleColor(.systemBlue, for: .normal)
        button.setContentHuggingPriority(.required, for: .horizontal)
        button.setContentCompressionResistancePriority(.required, for: .horizontal)
        button.addTarget(self, action: #selector(setupTapped), for: .touchUpInside)
        button.accessibilityLabel = "Set up account recovery"
        return button
    }()

    private lazy var dismissButton: UIButton = {
        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        let config = UIImage.SymbolConfiguration(pointSize: 12, weight: .medium)
        button.setImage(UIImage(systemName: "xmark", withConfiguration: config), for: .normal)
        button.tintColor = .tertiaryLabel
        button.setContentHuggingPriority(.required, for: .horizontal)
        button.setContentCompressionResistancePriority(.required, for: .horizontal)
        button.addTarget(self, action: #selector(dismissTapped), for: .touchUpInside)
        button.accessibilityLabel = "Dismiss recovery banner"
        button.accessibilityHint = "Hides the recovery setup reminder"
        return button
    }()

    // MARK: - Initialization

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupUI()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupUI()
    }

    // MARK: - Setup

    private func setupUI() {
        backgroundColor = UIColor.systemOrange.withAlphaComponent(0.12)
        layer.cornerRadius = 10
        layer.borderWidth = 1
        layer.borderColor = UIColor.systemOrange.withAlphaComponent(0.3).cgColor

        addSubview(shieldImageView)
        addSubview(messageLabel)
        addSubview(setupButton)
        addSubview(dismissButton)

        NSLayoutConstraint.activate([
            // Shield icon
            shieldImageView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            shieldImageView.centerYAnchor.constraint(equalTo: centerYAnchor),
            shieldImageView.widthAnchor.constraint(equalToConstant: 24),
            shieldImageView.heightAnchor.constraint(equalToConstant: 24),

            // Dismiss button (trailing edge)
            dismissButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            dismissButton.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            dismissButton.widthAnchor.constraint(equalToConstant: 24),
            dismissButton.heightAnchor.constraint(equalToConstant: 24),

            // Setup button (before dismiss button)
            setupButton.trailingAnchor.constraint(equalTo: dismissButton.leadingAnchor, constant: -8),
            setupButton.centerYAnchor.constraint(equalTo: centerYAnchor),

            // Message label (fills remaining space)
            messageLabel.leadingAnchor.constraint(equalTo: shieldImageView.trailingAnchor, constant: 8),
            messageLabel.trailingAnchor.constraint(equalTo: setupButton.leadingAnchor, constant: -8),
            messageLabel.topAnchor.constraint(equalTo: topAnchor, constant: 10),
            messageLabel.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -10)
        ])
    }

    // MARK: - Actions

    @objc private func setupTapped() {
        onSetupTapped?()
    }

    @objc private func dismissTapped() {
        dismissCount += 1
        animateOut()
    }

    // MARK: - Animation

    private func animateOut() {
        UIView.animate(withDuration: 0.3, delay: 0, options: .curveEaseOut) {
            self.alpha = 0
            self.transform = CGAffineTransform(translationX: 0, y: -8)
        } completion: { _ in
            self.removeFromSuperview()
        }
    }
}
