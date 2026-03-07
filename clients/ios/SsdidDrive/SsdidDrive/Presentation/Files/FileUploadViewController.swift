import UIKit
import Combine
import UniformTypeIdentifiers

/// File upload view controller
final class FileUploadViewController: BaseViewController {

    // MARK: - Properties

    private let viewModel: FileUploadViewModel

    // MARK: - UI Components

    private lazy var selectFileButton: UIButton = {
        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false

        var config = UIButton.Configuration.plain()
        config.title = "Select File"
        config.image = UIImage(systemName: "doc.badge.plus")
        config.imagePadding = 12
        config.imagePlacement = .top
        config.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(pointSize: 48)
        button.configuration = config

        button.layer.borderWidth = 2
        button.layer.borderColor = UIColor.systemGray4.cgColor
        button.layer.cornerRadius = 16
        button.addTarget(self, action: #selector(selectFileTapped), for: .touchUpInside)
        return button
    }()

    private lazy var selectedFileView: UIView = {
        let container = UIView()
        container.translatesAutoresizingMaskIntoConstraints = false
        container.backgroundColor = .systemGray6
        container.layer.cornerRadius = 12
        container.isHidden = true
        return container
    }()

    private lazy var fileIconImageView: UIImageView = {
        let imageView = UIImageView()
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.tintColor = .systemBlue
        imageView.contentMode = .scaleAspectFit
        return imageView
    }()

    private lazy var fileNameLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .systemFont(ofSize: 16, weight: .medium)
        label.numberOfLines = 2
        return label
    }()

    private lazy var fileSizeLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .systemFont(ofSize: 14)
        label.textColor = .secondaryLabel
        return label
    }()

    private lazy var clearButton: UIButton = {
        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.setImage(UIImage(systemName: "xmark.circle.fill"), for: .normal)
        button.tintColor = .systemGray3
        button.addTarget(self, action: #selector(clearFileTapped), for: .touchUpInside)
        return button
    }()

    private lazy var progressView: UIProgressView = {
        let progress = UIProgressView(progressViewStyle: .default)
        progress.translatesAutoresizingMaskIntoConstraints = false
        progress.progressTintColor = .systemBlue
        progress.isHidden = true
        return progress
    }()

    private lazy var progressLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .systemFont(ofSize: 14)
        label.textColor = .secondaryLabel
        label.textAlignment = .center
        label.isHidden = true
        return label
    }()

    private lazy var uploadButton: UIButton = {
        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.setTitle("Upload", for: .normal)
        button.applyPrimaryStyle()
        button.addTarget(self, action: #selector(uploadTapped), for: .touchUpInside)
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

    init(viewModel: FileUploadViewModel) {
        self.viewModel = viewModel
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Setup

    override func setupUI() {
        view.backgroundColor = .systemBackground
        title = "Upload File"

        setupNavigationBar()

        view.addSubview(selectFileButton)
        view.addSubview(selectedFileView)
        view.addSubview(progressView)
        view.addSubview(progressLabel)
        view.addSubview(uploadButton)

        selectedFileView.addSubview(fileIconImageView)
        selectedFileView.addSubview(fileNameLabel)
        selectedFileView.addSubview(fileSizeLabel)
        selectedFileView.addSubview(clearButton)
        uploadButton.addSubview(activityIndicator)

        NSLayoutConstraint.activate([
            selectFileButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 32),
            selectFileButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            selectFileButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
            selectFileButton.heightAnchor.constraint(equalToConstant: 180),

            selectedFileView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 32),
            selectedFileView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            selectedFileView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),

            fileIconImageView.leadingAnchor.constraint(equalTo: selectedFileView.leadingAnchor, constant: 16),
            fileIconImageView.centerYAnchor.constraint(equalTo: selectedFileView.centerYAnchor),
            fileIconImageView.widthAnchor.constraint(equalToConstant: 48),
            fileIconImageView.heightAnchor.constraint(equalToConstant: 48),

            fileNameLabel.leadingAnchor.constraint(equalTo: fileIconImageView.trailingAnchor, constant: 12),
            fileNameLabel.trailingAnchor.constraint(equalTo: clearButton.leadingAnchor, constant: -8),
            fileNameLabel.topAnchor.constraint(equalTo: selectedFileView.topAnchor, constant: 16),

            fileSizeLabel.leadingAnchor.constraint(equalTo: fileIconImageView.trailingAnchor, constant: 12),
            fileSizeLabel.topAnchor.constraint(equalTo: fileNameLabel.bottomAnchor, constant: 4),
            fileSizeLabel.bottomAnchor.constraint(equalTo: selectedFileView.bottomAnchor, constant: -16),

            clearButton.trailingAnchor.constraint(equalTo: selectedFileView.trailingAnchor, constant: -8),
            clearButton.centerYAnchor.constraint(equalTo: selectedFileView.centerYAnchor),
            clearButton.widthAnchor.constraint(equalToConstant: 44),
            clearButton.heightAnchor.constraint(equalToConstant: 44),

            progressView.topAnchor.constraint(equalTo: selectedFileView.bottomAnchor, constant: 24),
            progressView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            progressView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),

            progressLabel.topAnchor.constraint(equalTo: progressView.bottomAnchor, constant: 8),
            progressLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),

            uploadButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -24),
            uploadButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            uploadButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
            uploadButton.heightAnchor.constraint(equalToConstant: 52),

            activityIndicator.centerXAnchor.constraint(equalTo: uploadButton.centerXAnchor),
            activityIndicator.centerYAnchor.constraint(equalTo: uploadButton.centerYAnchor)
        ])
    }

    private func setupNavigationBar() {
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .cancel,
            target: self,
            action: #selector(cancelTapped)
        )
    }

    override func setupBindings() {
        viewModel.$selectedFileURL
            .receive(on: DispatchQueue.main)
            .sink { [weak self] url in
                let hasFile = url != nil
                self?.selectFileButton.isHidden = hasFile
                self?.selectedFileView.isHidden = !hasFile
                self?.updateUploadButton()

                if let url = url {
                    self?.updateFileInfo(url)
                }
            }
            .store(in: &cancellables)

        viewModel.$isUploading
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isUploading in
                self?.progressView.isHidden = !isUploading
                self?.progressLabel.isHidden = !isUploading
                self?.clearButton.isHidden = isUploading

                if isUploading {
                    self?.uploadButton.setTitle("", for: .normal)
                    self?.activityIndicator.startAnimating()
                    self?.uploadButton.isEnabled = false
                } else {
                    self?.uploadButton.setTitle("Upload", for: .normal)
                    self?.activityIndicator.stopAnimating()
                    self?.updateUploadButton()
                }
            }
            .store(in: &cancellables)

        viewModel.$uploadProgress
            .receive(on: DispatchQueue.main)
            .sink { [weak self] progress in
                self?.progressView.progress = Float(progress)
                self?.progressLabel.text = "Uploading... \(Int(progress * 100))%"
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

    @objc private func selectFileTapped() {
        triggerSelectionFeedback()

        let documentPicker = UIDocumentPickerViewController(forOpeningContentTypes: [.item])
        documentPicker.delegate = self
        documentPicker.allowsMultipleSelection = false
        present(documentPicker, animated: true)
    }

    @objc private func clearFileTapped() {
        triggerSelectionFeedback()
        viewModel.clearSelection()
    }

    @objc private func uploadTapped() {
        triggerHapticFeedback()
        viewModel.uploadFile()
    }

    @objc private func cancelTapped() {
        viewModel.cancel()
    }

    // MARK: - Helpers

    private func updateFileInfo(_ url: URL) {
        fileNameLabel.text = viewModel.fileName
        fileSizeLabel.text = viewModel.formattedFileSize

        // Set icon based on file type
        let ext = url.pathExtension.lowercased()
        let iconName: String
        switch ext {
        case "jpg", "jpeg", "png", "gif", "heic":
            iconName = "photo.fill"
        case "mp4", "mov", "avi":
            iconName = "video.fill"
        case "mp3", "wav", "m4a":
            iconName = "music.note"
        case "pdf":
            iconName = "doc.fill"
        case "txt", "md":
            iconName = "doc.text.fill"
        case "zip":
            iconName = "doc.zipper"
        default:
            iconName = "doc.fill"
        }
        fileIconImageView.image = UIImage(systemName: iconName)
    }

    private func updateUploadButton() {
        uploadButton.isEnabled = viewModel.canUpload
        uploadButton.alpha = viewModel.canUpload ? 1.0 : 0.5
    }
}

// MARK: - UIDocumentPickerDelegate

extension FileUploadViewController: UIDocumentPickerDelegate {
    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        guard let url = urls.first else { return }

        // Start accessing security-scoped resource
        guard url.startAccessingSecurityScopedResource() else {
            showError("Unable to access the selected file")
            return
        }

        defer { url.stopAccessingSecurityScopedResource() }

        // Copy to temp location for upload
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(url.lastPathComponent)
        try? FileManager.default.removeItem(at: tempURL)

        do {
            try FileManager.default.copyItem(at: url, to: tempURL)
            viewModel.selectFile(tempURL)
        } catch {
            showError("Failed to prepare file for upload")
        }
    }

    func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
        // User cancelled
    }
}
