import UIKit
import Combine
import UniformTypeIdentifiers

/// Recovery flow view controller for locked-out users.
/// Allows reconstruction of the encryption key from recovery files.
final class RecoveryViewController: BaseViewController {

    // MARK: - Properties

    private let viewModel: RecoveryViewModel

    // MARK: - Step container views

    private lazy var pathSelectionView = makePathSelectionView()
    private lazy var uploadFilesView = makeUploadFilesView()
    private lazy var reconstructingView = makeReconstructingView()
    private lazy var successView = makeSuccessView()

    // MARK: - Upload step sub-views kept as properties for binding

    private lazy var file1Button: UIButton = makeOpenFileButton(label: "Open Recovery File 1", tag: 1)
    private lazy var file2Button: UIButton = makeOpenFileButton(label: "Open Recovery File 2", tag: 2)
    private lazy var file1StatusLabel = makeStatusLabel()
    private lazy var file2StatusLabel = makeStatusLabel()
    private lazy var didTextField: UITextField = {
        let tf = UITextField()
        tf.translatesAutoresizingMaskIntoConstraints = false
        tf.placeholder = "Your DID (did:kaz:...)"
        tf.applySsdidDriveStyle()
        tf.autocapitalizationType = .none
        tf.autocorrectionType = .no
        tf.addTarget(self, action: #selector(didTextChanged), for: .editingChanged)
        tf.isHidden = true
        return tf
    }()
    private lazy var reconstructButton: UIButton = {
        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.setTitle("Recover Account", for: .normal)
        button.applyPrimaryStyle()
        button.isEnabled = false
        button.alpha = 0.5
        button.addTarget(self, action: #selector(reconstructTapped), for: .touchUpInside)
        return button
    }()

    // MARK: - Initialization

    init(viewModel: RecoveryViewModel) {
        self.viewModel = viewModel
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Setup

    override func setupUI() {
        view.backgroundColor = .systemBackground
        title = "Account Recovery"

        navigationItem.leftBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .cancel,
            target: self,
            action: #selector(cancelTapped)
        )

        [pathSelectionView, uploadFilesView, reconstructingView, successView].forEach {
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
        pathSelectionView.isHidden = false
    }

    override func setupBindings() {
        viewModel.$step
            .receive(on: DispatchQueue.main)
            .sink { [weak self] step in
                self?.handleStep(step)
            }
            .store(in: &cancellables)

        viewModel.$file1Content
            .receive(on: DispatchQueue.main)
            .sink { [weak self] content in
                self?.file1StatusLabel.text = content != nil ? "File loaded" : "No file selected"
                self?.file1StatusLabel.textColor = content != nil ? .systemGreen : .secondaryLabel
                self?.updateReconstructButton()
            }
            .store(in: &cancellables)

        viewModel.$file2Content
            .receive(on: DispatchQueue.main)
            .sink { [weak self] content in
                self?.file2StatusLabel.text = content != nil ? "File loaded" : "No file selected"
                self?.file2StatusLabel.textColor = content != nil ? .systemGreen : .secondaryLabel
                self?.updateReconstructButton()
            }
            .store(in: &cancellables)

        viewModel.$selectedPath
            .receive(on: DispatchQueue.main)
            .sink { [weak self] path in
                let showDid = (path == .oneFilePlusServer)
                self?.file2Button.isHidden = showDid
                self?.file2StatusLabel.isHidden = showDid
                self?.didTextField.isHidden = !showDid
                self?.updateReconstructButton()
            }
            .store(in: &cancellables)
    }

    // MARK: - Step Handling

    private func handleStep(_ step: RecoveryViewModel.Step) {
        [pathSelectionView, uploadFilesView, reconstructingView, successView].forEach { $0.isHidden = true }

        switch step {
        case .selectPath:
            pathSelectionView.isHidden = false
        case .uploadFiles:
            uploadFilesView.isHidden = false
        case .reconstructing:
            reconstructingView.isHidden = false
        case .success:
            successView.isHidden = false
        case .error(let message):
            uploadFilesView.isHidden = false
            showError(message, retryAction: { [weak self] in
                self?.viewModel.retryFromStart()
            })
        }
    }

    // MARK: - Actions

    @objc private func cancelTapped() {
        viewModel.cancel()
    }

    @objc private func selectTwoFilesTapped() {
        triggerHapticFeedback()
        viewModel.selectPath(.twoFiles)
    }

    @objc private func selectOneFilePlusServerTapped() {
        triggerHapticFeedback()
        viewModel.selectPath(.oneFilePlusServer)
    }

    @objc private func openFile1Tapped() {
        triggerHapticFeedback()
        presentFilePicker(slot: 1)
    }

    @objc private func openFile2Tapped() {
        triggerHapticFeedback()
        presentFilePicker(slot: 2)
    }

    @objc private func didTextChanged() {
        viewModel.userDid = didTextField.text ?? ""
        updateReconstructButton()
    }

    @objc private func reconstructTapped() {
        guard viewModel.canReconstruct else { return }
        triggerHapticFeedback()
        view.endEditing(true)
        viewModel.reconstruct()
    }

    @objc private func doneTapped() {
        if case .success(let token) = viewModel.step {
            triggerNotificationFeedback(.success)
            viewModel.completeRecovery(token: token)
        }
    }

    // MARK: - File Picker

    private func presentFilePicker(slot: Int) {
        let recoveryType: UTType
        if let custom = UTType(filenameExtension: "recovery") {
            recoveryType = custom
        } else {
            recoveryType = .data
        }

        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [recoveryType, .json, .plainText])
        picker.allowsMultipleSelection = false
        picker.delegate = self
        picker.accessibilityHint = "\(slot)"
        present(picker, animated: true)
    }

    // MARK: - UI State Helpers

    private func updateReconstructButton() {
        let enabled = viewModel.canReconstruct
        reconstructButton.isEnabled = enabled
        reconstructButton.alpha = enabled ? 1.0 : 0.5
    }

    // MARK: - Step View Factories

    private func makePathSelectionView() -> UIView {
        let container = UIView()

        let imageView = UIImageView(image: UIImage(systemName: "key.fill"))
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.tintColor = .systemOrange
        imageView.contentMode = .scaleAspectFit

        let title = makeLabel("Recover Your Account", font: .systemFont(ofSize: 24, weight: .bold))
        title.textAlignment = .center

        let subtitle = makeLabel(
            "Choose how you want to recover your encryption key:",
            font: .systemFont(ofSize: 15),
            color: .secondaryLabel
        )
        subtitle.textAlignment = .center
        subtitle.numberOfLines = 0

        let twoFilesButton = makePathButton(
            title: "Two Recovery Files",
            subtitle: "Use your own file + trusted contact's file",
            systemImage: "doc.on.doc",
            action: #selector(selectTwoFilesTapped)
        )

        let oneFilePlusServerButton = makePathButton(
            title: "One File + Server Share",
            subtitle: "Use one recovery file + retrieve your server share",
            systemImage: "server.rack",
            action: #selector(selectOneFilePlusServerTapped)
        )

        [imageView, title, subtitle, twoFilesButton, oneFilePlusServerButton].forEach {
            container.addSubview($0)
        }

        NSLayoutConstraint.activate([
            imageView.topAnchor.constraint(equalTo: container.topAnchor, constant: 48),
            imageView.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            imageView.widthAnchor.constraint(equalToConstant: 64),
            imageView.heightAnchor.constraint(equalToConstant: 64),

            title.topAnchor.constraint(equalTo: imageView.bottomAnchor, constant: 20),
            title.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 24),
            title.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -24),

            subtitle.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 8),
            subtitle.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 24),
            subtitle.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -24),

            twoFilesButton.topAnchor.constraint(equalTo: subtitle.bottomAnchor, constant: 40),
            twoFilesButton.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 24),
            twoFilesButton.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -24),

            oneFilePlusServerButton.topAnchor.constraint(equalTo: twoFilesButton.bottomAnchor, constant: 16),
            oneFilePlusServerButton.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 24),
            oneFilePlusServerButton.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -24)
        ])

        return container
    }

    private func makeUploadFilesView() -> UIView {
        let scroll = UIScrollView()
        let content = UIView()
        content.translatesAutoresizingMaskIntoConstraints = false
        scroll.addSubview(content)
        NSLayoutConstraint.activate([
            content.topAnchor.constraint(equalTo: scroll.topAnchor),
            content.leadingAnchor.constraint(equalTo: scroll.leadingAnchor),
            content.trailingAnchor.constraint(equalTo: scroll.trailingAnchor),
            content.bottomAnchor.constraint(equalTo: scroll.bottomAnchor),
            content.widthAnchor.constraint(equalTo: scroll.widthAnchor)
        ])

        let title = makeLabel("Open Recovery Files", font: .systemFont(ofSize: 22, weight: .bold))
        title.textAlignment = .center

        file1Button.addTarget(self, action: #selector(openFile1Tapped), for: .touchUpInside)
        file2Button.addTarget(self, action: #selector(openFile2Tapped), for: .touchUpInside)

        [title, file1Button, file1StatusLabel, file2Button, file2StatusLabel, didTextField, reconstructButton].forEach {
            content.addSubview($0)
        }

        NSLayoutConstraint.activate([
            title.topAnchor.constraint(equalTo: content.topAnchor, constant: 32),
            title.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 24),
            title.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -24),

            file1Button.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 32),
            file1Button.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 24),
            file1Button.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -24),
            file1Button.heightAnchor.constraint(equalToConstant: 52),

            file1StatusLabel.topAnchor.constraint(equalTo: file1Button.bottomAnchor, constant: 4),
            file1StatusLabel.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 24),

            file2Button.topAnchor.constraint(equalTo: file1StatusLabel.bottomAnchor, constant: 16),
            file2Button.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 24),
            file2Button.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -24),
            file2Button.heightAnchor.constraint(equalToConstant: 52),

            file2StatusLabel.topAnchor.constraint(equalTo: file2Button.bottomAnchor, constant: 4),
            file2StatusLabel.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 24),

            didTextField.topAnchor.constraint(equalTo: file1StatusLabel.bottomAnchor, constant: 16),
            didTextField.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 24),
            didTextField.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -24),
            didTextField.heightAnchor.constraint(equalToConstant: 52),

            reconstructButton.topAnchor.constraint(equalTo: file2StatusLabel.bottomAnchor, constant: 32),
            reconstructButton.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 24),
            reconstructButton.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -24),
            reconstructButton.heightAnchor.constraint(equalToConstant: 52),
            reconstructButton.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -32)
        ])

        return scroll
    }

    private func makeReconstructingView() -> UIView {
        let container = UIView()

        let indicator = UIActivityIndicatorView(style: .large)
        indicator.translatesAutoresizingMaskIntoConstraints = false
        indicator.startAnimating()

        let label = makeLabel(
            "Reconstructing encryption key…",
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

        let title = makeLabel("Account Recovered", font: .systemFont(ofSize: 24, weight: .bold))
        title.textAlignment = .center

        let body = makeLabel(
            "Your encryption key has been successfully reconstructed. You can now access your files.",
            font: .systemFont(ofSize: 15),
            color: .secondaryLabel
        )
        body.textAlignment = .center
        body.numberOfLines = 0

        let doneButton = UIButton(type: .system)
        doneButton.translatesAutoresizingMaskIntoConstraints = false
        doneButton.setTitle("Continue to App", for: .normal)
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

    // MARK: - Small View Factories

    private func makePathButton(title: String, subtitle: String, systemImage: String, action: Selector) -> UIView {
        let card = UIView()
        card.translatesAutoresizingMaskIntoConstraints = false
        card.backgroundColor = .systemGray6
        card.layer.cornerRadius = 12

        let iconView = UIImageView(image: UIImage(systemName: systemImage))
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.tintColor = .systemBlue
        iconView.contentMode = .scaleAspectFit

        let titleLabel = makeLabel(title, font: .systemFont(ofSize: 17, weight: .semibold))
        let subtitleLabel = makeLabel(subtitle, font: .systemFont(ofSize: 13), color: .secondaryLabel)
        subtitleLabel.numberOfLines = 0

        let chevron = UIImageView(image: UIImage(systemName: "chevron.right"))
        chevron.translatesAutoresizingMaskIntoConstraints = false
        chevron.tintColor = .tertiaryLabel
        chevron.contentMode = .scaleAspectFit

        let tapGR = UITapGestureRecognizer(target: self, action: action)
        card.addGestureRecognizer(tapGR)
        card.isUserInteractionEnabled = true

        [iconView, titleLabel, subtitleLabel, chevron].forEach { card.addSubview($0) }

        NSLayoutConstraint.activate([
            iconView.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 16),
            iconView.centerYAnchor.constraint(equalTo: card.centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 32),
            iconView.heightAnchor.constraint(equalToConstant: 32),

            titleLabel.topAnchor.constraint(equalTo: card.topAnchor, constant: 16),
            titleLabel.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 12),
            titleLabel.trailingAnchor.constraint(equalTo: chevron.leadingAnchor, constant: -8),

            subtitleLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 4),
            subtitleLabel.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 12),
            subtitleLabel.trailingAnchor.constraint(equalTo: chevron.leadingAnchor, constant: -8),
            subtitleLabel.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -16),

            chevron.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -16),
            chevron.centerYAnchor.constraint(equalTo: card.centerYAnchor),
            chevron.widthAnchor.constraint(equalToConstant: 12),
            chevron.heightAnchor.constraint(equalToConstant: 20)
        ])

        return card
    }

    private func makeOpenFileButton(label: String, tag: Int) -> UIButton {
        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        let config = UIImage.SymbolConfiguration(pointSize: 15, weight: .medium)
        button.setImage(UIImage(systemName: "folder", withConfiguration: config), for: .normal)
        button.setTitle("  \(label)", for: .normal)
        button.applySecondaryStyle()
        button.tag = tag
        return button
    }

    private func makeStatusLabel() -> UILabel {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.text = "No file selected"
        label.font = .systemFont(ofSize: 12)
        label.textColor = .secondaryLabel
        return label
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

// MARK: - UIDocumentPickerDelegate

extension RecoveryViewController: UIDocumentPickerDelegate {
    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        guard let url = urls.first else { return }

        // Resolve the slot from the accessibilityHint we set
        let slot = Int(controller.accessibilityHint ?? "1") ?? 1

        // Security-scoped access
        let accessing = url.startAccessingSecurityScopedResource()
        defer {
            if accessing { url.stopAccessingSecurityScopedResource() }
        }

        do {
            let content = try String(contentsOf: url, encoding: .utf8)
            viewModel.fileDidLoad(content, slot: slot)
        } catch {
            showError("Failed to read file: \(error.localizedDescription)")
        }
    }
}
