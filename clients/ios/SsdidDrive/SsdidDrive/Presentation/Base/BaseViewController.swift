import UIKit
import Combine

/// Base view controller with common functionality
class BaseViewController: UIViewController {

    // MARK: - Properties

    var cancellables = Set<AnyCancellable>()

    /// Loading indicator
    private lazy var loadingView: UIView = {
        let view = UIView()
        view.backgroundColor = UIColor.black.withAlphaComponent(0.3)
        view.translatesAutoresizingMaskIntoConstraints = false

        let indicator = UIActivityIndicatorView(style: .large)
        indicator.color = .white
        indicator.translatesAutoresizingMaskIntoConstraints = false
        indicator.startAnimating()

        view.addSubview(indicator)
        NSLayoutConstraint.activate([
            indicator.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            indicator.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])

        return view
    }()

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        #if targetEnvironment(macCatalyst)
        configureForCatalyst()
        #endif
        setupUI()
        setupBindings()
    }

    // MARK: - Setup Methods (Override in subclasses)

    func setupUI() {
        // Override in subclasses
    }

    func setupBindings() {
        // Override in subclasses
    }

    // MARK: - Loading State

    func showLoading() {
        view.addSubview(loadingView)
        NSLayoutConstraint.activate([
            loadingView.topAnchor.constraint(equalTo: view.topAnchor),
            loadingView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            loadingView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            loadingView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    func hideLoading() {
        loadingView.removeFromSuperview()
    }

    // MARK: - Error Handling

    func showError(_ message: String, retryAction: (() -> Void)? = nil) {
        let alert = UIAlertController(
            title: "Error",
            message: message,
            preferredStyle: .alert
        )

        alert.addAction(UIAlertAction(title: "OK", style: .default))

        if let retry = retryAction {
            alert.addAction(UIAlertAction(title: "Retry", style: .default) { _ in
                retry()
            })
        }

        present(alert, animated: true)
    }

    func showSuccess(_ message: String, completion: (() -> Void)? = nil) {
        let alert = UIAlertController(
            title: "Success",
            message: message,
            preferredStyle: .alert
        )

        alert.addAction(UIAlertAction(title: "OK", style: .default) { _ in
            completion?()
        })

        present(alert, animated: true)
    }

    // MARK: - Keyboard Handling

    func setupKeyboardDismissOnTap() {
        let tap = UITapGestureRecognizer(target: self, action: #selector(dismissKeyboard))
        tap.cancelsTouchesInView = false
        view.addGestureRecognizer(tap)
    }

    @objc private func dismissKeyboard() {
        view.endEditing(true)
    }

    // MARK: - Haptic Feedback

    func triggerHapticFeedback(_ style: UIImpactFeedbackGenerator.FeedbackStyle = .medium) {
        let generator = UIImpactFeedbackGenerator(style: style)
        generator.impactOccurred()
    }

    func triggerSelectionFeedback() {
        let generator = UISelectionFeedbackGenerator()
        generator.selectionChanged()
    }

    func triggerNotificationFeedback(_ type: UINotificationFeedbackGenerator.FeedbackType) {
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(type)
    }
}
