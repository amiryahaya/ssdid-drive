import UIKit
import Combine
import UniformTypeIdentifiers

/// Recovery setup wizard view controller.
/// Guides the user through 3 steps:
///   1. Explanation — describe what recovery files are and why they matter
///   2. Download    — download 2 recovery files (self + trusted contact)
///   3. Upload      — upload the server share, show success
final class RecoverySetupViewController: BaseViewController {

    // MARK: - Properties

    private let viewModel: RecoverySetupViewModel

    // MARK: - Container views (one per step)

    private lazy var explanationView = makeExplanationView()
    private lazy var downloadView = makeDownloadView()
    private lazy var uploadingView = makeUploadingView()
    private lazy var successView = makeSuccessView()

    // MARK: - Download step subviews (kept as properties for binding)

    private lazy var saveSelfButton: UIButton = makeSaveButton(
        title: "Save My Recovery File",
        systemImage: "arrow.down.circle"
    )
    private lazy var saveTrustedButton: UIButton = makeSaveButton(
        title: "Save Trusted Contact File",
        systemImage: "person.crop.circle.badge.plus"
    )
    private lazy var selfCheckmark = makeCheckmark()
    private lazy var trustedCheckmark = makeCheckmark()
    private lazy var continueButton: UIButton = {
        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.setTitle("Continue", for: .normal)
        button.applyPrimaryStyle()
        button.isEnabled = false
        button.alpha = 0.5
        button.addTarget(self, action: #selector(continueTapped), for: .touchUpInside)
        return button
    }()

    // MARK: - Initialization

    init(viewModel: RecoverySetupViewModel) {
        self.viewModel = viewModel
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Setup

    override func setupUI() {
        view.backgroundColor = .systemBackground
        title = "Recovery Setup"

        navigationItem.leftBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .cancel,
            target: self,
            action: #selector(cancelTapped)
        )

        [explanationView, downloadView, uploadingView, successView].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview($0)
            NSLayoutConstraint.activate([
                $0.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
                $0.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                $0.trailingAnchor.constraint(equalTo: view.trailingAnchor),
                $0.bottomAnchor.constraint(equalTo: view.bottomAnchor)
            ])
            $0.isHidden = true
        }
        explanationView.isHidden = false
    }

    override func setupBindings() {
        viewModel.$step
            .receive(on: DispatchQueue.main)
            .sink { [weak self] step in
                self?.handleStep(step)
            }
            .store(in: &cancellables)

        viewModel.$selfSaved
            .receive(on: DispatchQueue.main)
            .sink { [weak self] saved in
                self?.selfCheckmark.isHidden = !saved
                self?.updateContinueButton()
            }
            .store(in: &cancellables)

        viewModel.$trustedSaved
            .receive(on: DispatchQueue.main)
            .sink { [weak self] saved in
                self?.trustedCheckmark.isHidden = !saved
                self?.updateContinueButton()
            }
            .store(in: &cancellables)
    }

    // MARK: - Step Handling

    private func handleStep(_ step: RecoverySetupStep) {
        [explanationView, downloadView, uploadingView, successView].forEach { $0.isHidden = true }

        switch step {
        case .explanation:
            explanationView.isHidden = false
        case .generating:
            showLoading()
        case .download:
            hideLoading()
            downloadView.isHidden = false
        case .uploading:
            downloadView.isHidden = true
            uploadingView.isHidden = false
        case .success:
            uploadingView.isHidden = true
            successView.isHidden = false
        case .error(let message):
            hideLoading()
            explanationView.isHidden = false
            showError(message)
        }
    }

    // MARK: - Actions

    @objc private func cancelTapped() {
        viewModel.cancel()
    }

    @objc private func beginSetupTapped() {
        triggerHapticFeedback()
        viewModel.beginSetup()
        // In production, the master key and KEM key come from KeyManager.
        // For now, the coordinator / calling code will call generateShares(masterKey:userDid:kemPublicKey:).
    }

    @objc private func saveSelfTapped() {
        triggerHapticFeedback()
        guard let content = viewModel.selfFileContent else { return }
        saveFile(content: content, filename: "ssdid-recovery-self.recovery") { [weak self] in
            self?.viewModel.markSelfSaved()
        }
    }

    @objc private func saveTrustedTapped() {
        triggerHapticFeedback()
        guard let content = viewModel.trustedFileContent else { return }
        saveFile(content: content, filename: "ssdid-recovery-trusted.recovery") { [weak self] in
            self?.viewModel.markTrustedSaved()
        }
    }

    @objc private func continueTapped() {
        guard viewModel.canProceed else { return }
        triggerHapticFeedback()
        viewModel.uploadServerShare()
    }

    @objc private func doneTapped() {
        triggerNotificationFeedback(.success)
        viewModel.done()
    }

    // MARK: - File Save

    private func saveFile(content: String, filename: String, completion: @escaping () -> Void) {
        guard let data = content.data(using: .utf8) else { return }

        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
        do {
            try data.write(to: tempURL)
        } catch {
            showError("Failed to prepare file: \(error.localizedDescription)")
            return
        }

        let activityVC = UIActivityViewController(activityItems: [tempURL], applicationActivities: nil)
        activityVC.completionWithItemsHandler = { _, completed, _, _ in
            if completed {
                completion()
            }
        }

        if let popover = activityVC.popoverPresentationController {
            popover.sourceView = view
            popover.sourceRect = CGRect(x: view.bounds.midX, y: view.bounds.midY, width: 0, height: 0)
        }

        present(activityVC, animated: true)
    }

    // MARK: - UI Helpers

    private func updateContinueButton() {
        let enabled = viewModel.canProceed
        continueButton.isEnabled = enabled
        continueButton.alpha = enabled ? 1.0 : 0.5
    }

    // MARK: - Step View Factories

    private func makeExplanationView() -> UIView {
        let container = UIView()

        let imageView = UIImageView(image: UIImage(systemName: "shield.checkered"))
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.tintColor = .systemBlue
        imageView.contentMode = .scaleAspectFit

        let title = makeLabel("Set Up Account Recovery", font: .systemFont(ofSize: 24, weight: .bold))
        title.textAlignment = .center

        let body = makeLabel(
            "Recovery uses Shamir's Secret Sharing to split your encryption key into 3 parts:\n\n" +
            "• Your Recovery File — keep it safe\n" +
            "• Trusted Contact File — give to someone you trust\n" +
            "• Server Share — stored securely on the server\n\n" +
            "Any 2 of the 3 shares can reconstruct your key.",
            font: .systemFont(ofSize: 15),
            color: .secondaryLabel
        )
        body.numberOfLines = 0

        let beginButton = UIButton(type: .system)
        beginButton.translatesAutoresizingMaskIntoConstraints = false
        beginButton.setTitle("Begin Setup", for: .normal)
        beginButton.applyPrimaryStyle()
        beginButton.addTarget(self, action: #selector(beginSetupTapped), for: .touchUpInside)

        [imageView, title, body, beginButton].forEach { container.addSubview($0) }

        NSLayoutConstraint.activate([
            imageView.topAnchor.constraint(equalTo: container.topAnchor, constant: 48),
            imageView.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            imageView.widthAnchor.constraint(equalToConstant: 80),
            imageView.heightAnchor.constraint(equalToConstant: 80),

            title.topAnchor.constraint(equalTo: imageView.bottomAnchor, constant: 24),
            title.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 24),
            title.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -24),

            body.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 16),
            body.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 24),
            body.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -24),

            beginButton.topAnchor.constraint(equalTo: body.bottomAnchor, constant: 40),
            beginButton.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 24),
            beginButton.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -24),
            beginButton.heightAnchor.constraint(equalToConstant: 52)
        ])

        return container
    }

    private func makeDownloadView() -> UIView {
        let container = UIScrollView()
        let contentView = UIView()
        contentView.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(contentView)
        NSLayoutConstraint.activate([
            contentView.topAnchor.constraint(equalTo: container.topAnchor),
            contentView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            contentView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            contentView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            contentView.widthAnchor.constraint(equalTo: container.widthAnchor)
        ])

        let title = makeLabel("Save Your Recovery Files", font: .systemFont(ofSize: 22, weight: .bold))
        title.textAlignment = .center

        let subtitle = makeLabel(
            "Download both recovery files and store them in separate, secure locations.",
            font: .systemFont(ofSize: 15),
            color: .secondaryLabel
        )
        subtitle.numberOfLines = 0
        subtitle.textAlignment = .center

        saveSelfButton.addTarget(self, action: #selector(saveSelfTapped), for: .touchUpInside)
        saveTrustedButton.addTarget(self, action: #selector(saveTrustedTapped), for: .touchUpInside)

        // Self file row
        let selfRow = makeFileRow(button: saveSelfButton, checkmark: selfCheckmark)

        // Trusted file row
        let trustedRow = makeFileRow(button: saveTrustedButton, checkmark: trustedCheckmark)

        let warningLabel = makeLabel(
            "Keep these files private. Anyone with 2 files can recover your account.",
            font: .systemFont(ofSize: 13),
            color: .systemOrange
        )
        warningLabel.numberOfLines = 0

        [title, subtitle, selfRow, trustedRow, warningLabel, continueButton].forEach {
            contentView.addSubview($0)
        }

        NSLayoutConstraint.activate([
            title.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 32),
            title.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 24),
            title.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -24),

            subtitle.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 8),
            subtitle.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 24),
            subtitle.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -24),

            selfRow.topAnchor.constraint(equalTo: subtitle.bottomAnchor, constant: 32),
            selfRow.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 24),
            selfRow.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -24),

            trustedRow.topAnchor.constraint(equalTo: selfRow.bottomAnchor, constant: 16),
            trustedRow.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 24),
            trustedRow.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -24),

            warningLabel.topAnchor.constraint(equalTo: trustedRow.bottomAnchor, constant: 24),
            warningLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 24),
            warningLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -24),

            continueButton.topAnchor.constraint(equalTo: warningLabel.bottomAnchor, constant: 32),
            continueButton.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 24),
            continueButton.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -24),
            continueButton.heightAnchor.constraint(equalToConstant: 52),
            continueButton.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -32)
        ])

        return container
    }

    private func makeUploadingView() -> UIView {
        let container = UIView()

        let indicator = UIActivityIndicatorView(style: .large)
        indicator.translatesAutoresizingMaskIntoConstraints = false
        indicator.startAnimating()

        let label = makeLabel(
            "Uploading server share…",
            font: .systemFont(ofSize: 17),
            color: .secondaryLabel
        )
        label.textAlignment = .center

        container.addSubview(indicator)
        container.addSubview(label)

        NSLayoutConstraint.activate([
            indicator.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            indicator.centerYAnchor.constraint(equalTo: container.centerYAnchor, constant: -20),
            label.topAnchor.constraint(equalTo: indicator.bottomAnchor, constant: 16),
            label.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 24),
            label.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -24)
        ])

        return container
    }

    private func makeSuccessView() -> UIView {
        let container = UIView()

        let imageView = UIImageView(image: UIImage(systemName: "checkmark.seal.fill"))
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.tintColor = .systemGreen
        imageView.contentMode = .scaleAspectFit

        let title = makeLabel("Recovery Setup Complete", font: .systemFont(ofSize: 24, weight: .bold))
        title.textAlignment = .center

        let body = makeLabel(
            "Your account can now be recovered using any 2 of your 3 recovery shares.",
            font: .systemFont(ofSize: 15),
            color: .secondaryLabel
        )
        body.textAlignment = .center
        body.numberOfLines = 0

        let doneButton = UIButton(type: .system)
        doneButton.translatesAutoresizingMaskIntoConstraints = false
        doneButton.setTitle("Done", for: .normal)
        doneButton.applyPrimaryStyle()
        doneButton.addTarget(self, action: #selector(doneTapped), for: .touchUpInside)

        [imageView, title, body, doneButton].forEach { container.addSubview($0) }

        NSLayoutConstraint.activate([
            imageView.topAnchor.constraint(equalTo: container.topAnchor, constant: 80),
            imageView.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            imageView.widthAnchor.constraint(equalToConstant: 80),
            imageView.heightAnchor.constraint(equalToConstant: 80),

            title.topAnchor.constraint(equalTo: imageView.bottomAnchor, constant: 24),
            title.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 24),
            title.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -24),

            body.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 12),
            body.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 24),
            body.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -24),

            doneButton.topAnchor.constraint(equalTo: body.bottomAnchor, constant: 40),
            doneButton.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 24),
            doneButton.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -24),
            doneButton.heightAnchor.constraint(equalToConstant: 52)
        ])

        return container
    }

    // MARK: - Layout Helpers

    private func makeFileRow(button: UIButton, checkmark: UIImageView) -> UIView {
        let row = UIView()
        row.translatesAutoresizingMaskIntoConstraints = false
        row.addSubview(button)
        row.addSubview(checkmark)

        NSLayoutConstraint.activate([
            button.leadingAnchor.constraint(equalTo: row.leadingAnchor),
            button.topAnchor.constraint(equalTo: row.topAnchor),
            button.bottomAnchor.constraint(equalTo: row.bottomAnchor),
            button.heightAnchor.constraint(equalToConstant: 52),

            checkmark.leadingAnchor.constraint(equalTo: button.trailingAnchor, constant: 12),
            checkmark.trailingAnchor.constraint(equalTo: row.trailingAnchor),
            checkmark.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            checkmark.widthAnchor.constraint(equalToConstant: 28),
            checkmark.heightAnchor.constraint(equalToConstant: 28)
        ])

        return row
    }

    private func makeSaveButton(title: String, systemImage: String) -> UIButton {
        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        let config = UIImage.SymbolConfiguration(pointSize: 15, weight: .medium)
        button.setImage(UIImage(systemName: systemImage, withConfiguration: config), for: .normal)
        button.setTitle("  \(title)", for: .normal)
        button.applySecondaryStyle()
        return button
    }

    private func makeCheckmark() -> UIImageView {
        let imageView = UIImageView(image: UIImage(systemName: "checkmark.circle.fill"))
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.tintColor = .systemGreen
        imageView.contentMode = .scaleAspectFit
        imageView.isHidden = true
        return imageView
    }

    private func makeLabel(_ text: String, font: UIFont, color: UIColor = .label) -> UILabel {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.text = text
        label.font = font
        label.textColor = color
        return label
    }
}
