import UIKit
import Social
import MobileCoreServices
import UniformTypeIdentifiers

/// Share Extension for SsdidDrive
/// Allows users to share files from other apps directly into SsdidDrive
class ShareViewController: UIViewController {

    // MARK: - UI Components

    private let containerView: UIView = {
        let view = UIView()
        view.backgroundColor = .systemBackground
        view.layer.cornerRadius = 16
        view.layer.masksToBounds = true
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private let headerView: UIView = {
        let view = UIView()
        view.backgroundColor = .systemGray6
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private let titleLabel: UILabel = {
        let label = UILabel()
        label.text = "Share to SsdidDrive"
        label.font = .systemFont(ofSize: 17, weight: .semibold)
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private let cancelButton: UIButton = {
        let button = UIButton(type: .system)
        button.setTitle("Cancel", for: .normal)
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()

    private let uploadButton: UIButton = {
        let button = UIButton(type: .system)
        button.setTitle("Upload", for: .normal)
        button.titleLabel?.font = .systemFont(ofSize: 17, weight: .semibold)
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()

    private let fileInfoStack: UIStackView = {
        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }()

    private let fileIconImageView: UIImageView = {
        let imageView = UIImageView()
        imageView.contentMode = .scaleAspectFit
        imageView.tintColor = .systemBlue
        imageView.translatesAutoresizingMaskIntoConstraints = false
        return imageView
    }()

    private let fileNameLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 15)
        label.textAlignment = .center
        label.numberOfLines = 2
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private let fileSizeLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 13)
        label.textColor = .secondaryLabel
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private let progressView: UIProgressView = {
        let progress = UIProgressView(progressViewStyle: .default)
        progress.isHidden = true
        progress.translatesAutoresizingMaskIntoConstraints = false
        return progress
    }()

    private let statusLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 13)
        label.textColor = .secondaryLabel
        label.textAlignment = .center
        label.isHidden = true
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    // MARK: - Properties

    private var sharedItems: [(url: URL, name: String, size: Int64)] = []
    private var isUploading = false

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        loadSharedContent()
    }

    // MARK: - UI Setup

    private func setupUI() {
        view.backgroundColor = UIColor.black.withAlphaComponent(0.4)

        view.addSubview(containerView)
        containerView.addSubview(headerView)
        headerView.addSubview(cancelButton)
        headerView.addSubview(titleLabel)
        headerView.addSubview(uploadButton)

        containerView.addSubview(fileIconImageView)
        containerView.addSubview(fileInfoStack)
        fileInfoStack.addArrangedSubview(fileNameLabel)
        fileInfoStack.addArrangedSubview(fileSizeLabel)
        containerView.addSubview(progressView)
        containerView.addSubview(statusLabel)

        NSLayoutConstraint.activate([
            // Container
            containerView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            containerView.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            containerView.widthAnchor.constraint(equalTo: view.widthAnchor, multiplier: 0.85),
            containerView.heightAnchor.constraint(greaterThanOrEqualToConstant: 250),

            // Header
            headerView.topAnchor.constraint(equalTo: containerView.topAnchor),
            headerView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            headerView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            headerView.heightAnchor.constraint(equalToConstant: 50),

            // Cancel button
            cancelButton.leadingAnchor.constraint(equalTo: headerView.leadingAnchor, constant: 16),
            cancelButton.centerYAnchor.constraint(equalTo: headerView.centerYAnchor),

            // Title
            titleLabel.centerXAnchor.constraint(equalTo: headerView.centerXAnchor),
            titleLabel.centerYAnchor.constraint(equalTo: headerView.centerYAnchor),

            // Upload button
            uploadButton.trailingAnchor.constraint(equalTo: headerView.trailingAnchor, constant: -16),
            uploadButton.centerYAnchor.constraint(equalTo: headerView.centerYAnchor),

            // File icon
            fileIconImageView.topAnchor.constraint(equalTo: headerView.bottomAnchor, constant: 24),
            fileIconImageView.centerXAnchor.constraint(equalTo: containerView.centerXAnchor),
            fileIconImageView.widthAnchor.constraint(equalToConstant: 60),
            fileIconImageView.heightAnchor.constraint(equalToConstant: 60),

            // File info stack
            fileInfoStack.topAnchor.constraint(equalTo: fileIconImageView.bottomAnchor, constant: 16),
            fileInfoStack.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 20),
            fileInfoStack.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -20),

            // Progress view
            progressView.topAnchor.constraint(equalTo: fileInfoStack.bottomAnchor, constant: 20),
            progressView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 20),
            progressView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -20),

            // Status label
            statusLabel.topAnchor.constraint(equalTo: progressView.bottomAnchor, constant: 8),
            statusLabel.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 20),
            statusLabel.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -20),
            statusLabel.bottomAnchor.constraint(equalTo: containerView.bottomAnchor, constant: -20)
        ])

        cancelButton.addTarget(self, action: #selector(cancelTapped), for: .touchUpInside)
        uploadButton.addTarget(self, action: #selector(uploadTapped), for: .touchUpInside)

        // Add tap gesture to dismiss
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(backgroundTapped))
        view.addGestureRecognizer(tapGesture)
    }

    // MARK: - Content Loading

    private func loadSharedContent() {
        guard let extensionItem = extensionContext?.inputItems.first as? NSExtensionItem,
              let attachments = extensionItem.attachments else {
            showError("No content to share")
            return
        }

        let group = DispatchGroup()

        for attachment in attachments {
            group.enter()
            loadAttachment(attachment) { [weak self] result in
                defer { group.leave() }
                switch result {
                case .success(let item):
                    self?.sharedItems.append(item)
                case .failure(let error):
                    print("Failed to load attachment: \(error)")
                }
            }
        }

        group.notify(queue: .main) { [weak self] in
            self?.updateUI()
        }
    }

    private func loadAttachment(_ attachment: NSItemProvider, completion: @escaping (Result<(url: URL, name: String, size: Int64), Error>) -> Void) {
        // Try to load as file URL first
        let fileTypes = [
            UTType.data.identifier,
            UTType.image.identifier,
            UTType.pdf.identifier,
            UTType.movie.identifier,
            UTType.audio.identifier,
            UTType.plainText.identifier
        ]

        for typeIdentifier in fileTypes {
            if attachment.hasItemConformingToTypeIdentifier(typeIdentifier) {
                attachment.loadFileRepresentation(forTypeIdentifier: typeIdentifier) { url, error in
                    if let error = error {
                        completion(.failure(error))
                        return
                    }

                    guard let url = url else {
                        completion(.failure(ShareError.noURL))
                        return
                    }

                    // Copy to temporary location
                    let tempDir = FileManager.default.temporaryDirectory
                    let fileName = url.lastPathComponent
                    let tempURL = tempDir.appendingPathComponent(UUID().uuidString + "_" + fileName)

                    do {
                        try FileManager.default.copyItem(at: url, to: tempURL)
                        let attributes = try FileManager.default.attributesOfItem(atPath: tempURL.path)
                        let size = attributes[.size] as? Int64 ?? 0
                        completion(.success((tempURL, fileName, size)))
                    } catch {
                        completion(.failure(error))
                    }
                }
                return
            }
        }

        completion(.failure(ShareError.unsupportedType))
    }

    private func updateUI() {
        guard let firstItem = sharedItems.first else {
            showError("No files to upload")
            return
        }

        fileNameLabel.text = sharedItems.count == 1 ? firstItem.name : "\(sharedItems.count) files"
        fileSizeLabel.text = formatFileSize(sharedItems.reduce(0) { $0 + $1.size })
        fileIconImageView.image = iconForFile(firstItem.name)

        uploadButton.isEnabled = true
    }

    // MARK: - Actions

    @objc private func cancelTapped() {
        cleanup()
        extensionContext?.cancelRequest(withError: ShareError.cancelled)
    }

    @objc private func backgroundTapped(_ gesture: UITapGestureRecognizer) {
        let location = gesture.location(in: view)
        if !containerView.frame.contains(location) && !isUploading {
            cancelTapped()
        }
    }

    @objc private func uploadTapped() {
        guard !sharedItems.isEmpty else { return }

        isUploading = true
        uploadButton.isEnabled = false
        cancelButton.isEnabled = false
        progressView.isHidden = false
        statusLabel.isHidden = false
        statusLabel.text = "Preparing upload..."

        // Pass files to main app via App Group
        saveFilesToAppGroup { [weak self] success in
            DispatchQueue.main.async {
                if success {
                    self?.statusLabel.text = "Opening SsdidDrive..."
                    self?.openMainApp()
                } else {
                    self?.showError("Failed to prepare files")
                    self?.isUploading = false
                    self?.uploadButton.isEnabled = true
                    self?.cancelButton.isEnabled = true
                }
            }
        }
    }

    // MARK: - File Handling

    private func saveFilesToAppGroup(completion: @escaping (Bool) -> Void) {
        guard let containerURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: "group.my.ssdid.drive"
        ) else {
            completion(false)
            return
        }

        let sharedDir = containerURL.appendingPathComponent("SharedFiles", isDirectory: true)

        do {
            // Create shared directory if needed
            try FileManager.default.createDirectory(at: sharedDir, withIntermediateDirectories: true)

            // Clear old files
            let existingFiles = try FileManager.default.contentsOfDirectory(at: sharedDir, includingPropertiesForKeys: nil)
            for file in existingFiles {
                try? FileManager.default.removeItem(at: file)
            }

            // Copy new files
            var fileList: [[String: Any]] = []
            for (index, item) in sharedItems.enumerated() {
                let progress = Float(index) / Float(sharedItems.count)
                DispatchQueue.main.async {
                    self.progressView.progress = progress
                    self.statusLabel.text = "Copying \(item.name)..."
                }

                let destURL = sharedDir.appendingPathComponent(item.name)
                try FileManager.default.copyItem(at: item.url, to: destURL)

                fileList.append([
                    "name": item.name,
                    "path": destURL.path,
                    "size": item.size
                ])
            }

            // Save file manifest
            let manifestURL = sharedDir.appendingPathComponent("manifest.json")
            let manifestData = try JSONSerialization.data(withJSONObject: fileList)
            try manifestData.write(to: manifestURL)

            DispatchQueue.main.async {
                self.progressView.progress = 1.0
            }

            completion(true)
        } catch {
            print("Failed to save files to app group: \(error)")
            completion(false)
        }
    }

    private func openMainApp() {
        // Use URL scheme to open main app
        guard let url = URL(string: "ssdid-drive://import") else {
            completeRequest()
            return
        }

        var responder: UIResponder? = self
        while responder != nil {
            if let application = responder as? UIApplication {
                application.open(url, options: [:]) { [weak self] _ in
                    self?.completeRequest()
                }
                return
            }
            responder = responder?.next
        }

        // Fallback: just complete
        completeRequest()
    }

    private func completeRequest() {
        cleanup()
        extensionContext?.completeRequest(returningItems: nil)
    }

    private func cleanup() {
        // Remove temporary files
        for item in sharedItems {
            try? FileManager.default.removeItem(at: item.url)
        }
    }

    // MARK: - Helpers

    private func showError(_ message: String) {
        let alert = UIAlertController(title: "Error", message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default) { [weak self] _ in
            self?.cancelTapped()
        })
        present(alert, animated: true)
    }

    private func formatFileSize(_ size: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: size)
    }

    private func iconForFile(_ fileName: String) -> UIImage? {
        let ext = (fileName as NSString).pathExtension.lowercased()

        switch ext {
        case "jpg", "jpeg", "png", "gif", "heic", "webp":
            return UIImage(systemName: "photo.fill")
        case "pdf":
            return UIImage(systemName: "doc.fill")
        case "mp4", "mov", "m4v", "avi":
            return UIImage(systemName: "video.fill")
        case "mp3", "m4a", "wav", "aac":
            return UIImage(systemName: "music.note")
        case "zip", "tar", "gz", "7z":
            return UIImage(systemName: "archivebox.fill")
        case "txt", "md", "json", "xml":
            return UIImage(systemName: "doc.text.fill")
        default:
            return UIImage(systemName: "doc.fill")
        }
    }
}

// MARK: - Errors

enum ShareError: Error {
    case cancelled
    case noURL
    case unsupportedType
    case uploadFailed
}
