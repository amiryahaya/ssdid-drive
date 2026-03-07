import UIKit
import Combine
import QuickLook
import AVKit
import PDFKit

/// File preview view controller
final class FilePreviewViewController: BaseViewController {

    // MARK: - Properties

    private let viewModel: FilePreviewViewModel
    private var previewURL: URL?

    // MARK: - UI Components

    private lazy var progressContainerView: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.isHidden = true
        return view
    }()

    private lazy var progressView: UIProgressView = {
        let progress = UIProgressView(progressViewStyle: .default)
        progress.translatesAutoresizingMaskIntoConstraints = false
        progress.progressTintColor = .systemBlue
        return progress
    }()

    private lazy var progressLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.text = "Decrypting..."
        label.font = .systemFont(ofSize: 14)
        label.textColor = .secondaryLabel
        label.textAlignment = .center
        return label
    }()

    private lazy var imageView: UIImageView = {
        let imageView = UIImageView()
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.contentMode = .scaleAspectFit
        imageView.isHidden = true
        return imageView
    }()

    private lazy var pdfView: PDFView = {
        let pdf = PDFView()
        pdf.translatesAutoresizingMaskIntoConstraints = false
        pdf.autoScales = true
        pdf.displayMode = .singlePageContinuous
        pdf.isHidden = true
        return pdf
    }()

    private lazy var textView: UITextView = {
        let text = UITextView()
        text.translatesAutoresizingMaskIntoConstraints = false
        text.isEditable = false
        text.font = .monospacedSystemFont(ofSize: 14, weight: .regular)
        text.isHidden = true
        return text
    }()

    private lazy var unsupportedView: UIView = {
        let container = UIView()
        container.translatesAutoresizingMaskIntoConstraints = false
        container.isHidden = true

        let imageView = UIImageView(image: UIImage(systemName: "doc.questionmark"))
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.tintColor = .systemGray3
        imageView.contentMode = .scaleAspectFit

        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.text = "Preview not available"
        label.font = .systemFont(ofSize: 17, weight: .medium)
        label.textColor = .secondaryLabel
        label.textAlignment = .center

        let exportButton = UIButton(type: .system)
        exportButton.translatesAutoresizingMaskIntoConstraints = false
        exportButton.setTitle("Export File", for: .normal)
        exportButton.applyPrimaryStyle()
        exportButton.addTarget(self, action: #selector(exportTapped), for: .touchUpInside)

        container.addSubview(imageView)
        container.addSubview(label)
        container.addSubview(exportButton)

        NSLayoutConstraint.activate([
            imageView.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            imageView.centerYAnchor.constraint(equalTo: container.centerYAnchor, constant: -60),
            imageView.widthAnchor.constraint(equalToConstant: 80),
            imageView.heightAnchor.constraint(equalToConstant: 80),

            label.topAnchor.constraint(equalTo: imageView.bottomAnchor, constant: 24),
            label.centerXAnchor.constraint(equalTo: container.centerXAnchor),

            exportButton.topAnchor.constraint(equalTo: label.bottomAnchor, constant: 24),
            exportButton.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            exportButton.widthAnchor.constraint(equalToConstant: 200),
            exportButton.heightAnchor.constraint(equalToConstant: 48)
        ])

        return container
    }()

    // MARK: - Initialization

    init(viewModel: FilePreviewViewModel) {
        self.viewModel = viewModel
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        viewModel.loadFileContent()
    }

    // MARK: - Setup

    override func setupUI() {
        view.backgroundColor = .systemBackground
        title = viewModel.file.name

        setupNavigationBar()

        view.addSubview(progressContainerView)
        view.addSubview(imageView)
        view.addSubview(pdfView)
        view.addSubview(textView)
        view.addSubview(unsupportedView)

        progressContainerView.addSubview(progressView)
        progressContainerView.addSubview(progressLabel)

        NSLayoutConstraint.activate([
            progressContainerView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            progressContainerView.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            progressContainerView.widthAnchor.constraint(equalToConstant: 200),

            progressView.topAnchor.constraint(equalTo: progressContainerView.topAnchor),
            progressView.leadingAnchor.constraint(equalTo: progressContainerView.leadingAnchor),
            progressView.trailingAnchor.constraint(equalTo: progressContainerView.trailingAnchor),

            progressLabel.topAnchor.constraint(equalTo: progressView.bottomAnchor, constant: 8),
            progressLabel.centerXAnchor.constraint(equalTo: progressContainerView.centerXAnchor),
            progressLabel.bottomAnchor.constraint(equalTo: progressContainerView.bottomAnchor),

            imageView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            imageView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            imageView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),

            pdfView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            pdfView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            pdfView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            pdfView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),

            textView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 16),
            textView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            textView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            textView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -16),

            unsupportedView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            unsupportedView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            unsupportedView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            unsupportedView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor)
        ])

        // Add pinch to zoom for images
        let pinchGesture = UIPinchGestureRecognizer(target: self, action: #selector(handlePinch(_:)))
        imageView.isUserInteractionEnabled = true
        imageView.addGestureRecognizer(pinchGesture)
    }

    private func setupNavigationBar() {
        let shareButton = UIBarButtonItem(
            image: UIImage(systemName: "square.and.arrow.up"),
            style: .plain,
            target: self,
            action: #selector(shareTapped)
        )
        shareButton.accessibilityLabel = "Share file"

        let moreButton = UIBarButtonItem(
            image: UIImage(systemName: "ellipsis.circle"),
            style: .plain,
            target: self,
            action: #selector(moreTapped)
        )
        moreButton.accessibilityLabel = "More options"

        navigationItem.rightBarButtonItems = [moreButton, shareButton]
    }

    override func setupBindings() {
        viewModel.$isLoading
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isLoading in
                self?.progressContainerView.isHidden = !isLoading
            }
            .store(in: &cancellables)

        viewModel.$downloadProgress
            .receive(on: DispatchQueue.main)
            .sink { [weak self] progress in
                self?.progressView.progress = Float(progress)
                if progress < 1.0 {
                    self?.progressLabel.text = "Downloading... \(Int(progress * 100))%"
                } else {
                    self?.progressLabel.text = "Decrypting..."
                }
            }
            .store(in: &cancellables)

        viewModel.$decryptedData
            .receive(on: DispatchQueue.main)
            .compactMap { $0 }
            .sink { [weak self] data in
                self?.displayContent(data)
            }
            .store(in: &cancellables)

        viewModel.$errorMessage
            .receive(on: DispatchQueue.main)
            .compactMap { $0 }
            .sink { [weak self] message in
                self?.showError(message) {
                    self?.viewModel.loadFileContent()
                }
            }
            .store(in: &cancellables)
    }

    // MARK: - Content Display

    private func displayContent(_ data: Data) {
        switch viewModel.fileType {
        case .image:
            displayImage(data)
        case .pdf:
            displayPDF(data)
        case .text:
            displayText(data)
        case .video, .audio:
            displayMedia(data)
        case .unknown:
            displayUnsupported(data)
        }
    }

    private func displayImage(_ data: Data) {
        if let image = UIImage(data: data) {
            imageView.image = image
            imageView.isHidden = false
            imageView.accessibilityLabel = "Preview of \(viewModel.file.name)"
            imageView.accessibilityTraits = .image

            // Cache thumbnail for grid view
            ThumbnailCache.shared.generateThumbnail(for: viewModel.file.id, data: data) { _ in }
        } else {
            displayUnsupported(data)
        }
    }

    private func displayPDF(_ data: Data) {
        if let document = PDFDocument(data: data) {
            pdfView.document = document
            pdfView.isHidden = false
        } else {
            displayUnsupported(data)
        }
    }

    private func displayText(_ data: Data) {
        if let text = String(data: data, encoding: .utf8) {
            textView.text = text
            textView.isHidden = false
        } else {
            displayUnsupported(data)
        }
    }

    private func displayMedia(_ data: Data) {
        // Save to temp file and play
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(viewModel.file.name)

        do {
            try data.write(to: tempURL)
            previewURL = tempURL

            let player = AVPlayer(url: tempURL)
            let playerVC = AVPlayerViewController()
            playerVC.player = player
            present(playerVC, animated: true) {
                player.play()
            }
        } catch {
            displayUnsupported(data)
        }
    }

    private func displayUnsupported(_ data: Data) {
        // Save to temp for export
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(viewModel.file.name)
        try? data.write(to: tempURL)
        previewURL = tempURL

        unsupportedView.isHidden = false
    }

    // MARK: - Actions

    @objc private func shareTapped() {
        triggerHapticFeedback()
        viewModel.requestShare()
    }

    @objc private func moreTapped() {
        let alert = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet)

        alert.addAction(UIAlertAction(title: "Export", style: .default) { [weak self] _ in
            self?.exportTapped()
        })

        alert.addAction(UIAlertAction(title: "Delete", style: .destructive) { [weak self] _ in
            self?.confirmDelete()
        })

        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))

        if let popover = alert.popoverPresentationController {
            popover.barButtonItem = navigationItem.rightBarButtonItems?.first
        }

        present(alert, animated: true)
    }

    @objc private func exportTapped() {
        guard let url = previewURL ?? saveTempFile() else { return }

        let activityVC = UIActivityViewController(activityItems: [url], applicationActivities: nil)

        if let popover = activityVC.popoverPresentationController {
            popover.barButtonItem = navigationItem.rightBarButtonItems?.last
        }

        present(activityVC, animated: true)
    }

    private func saveTempFile() -> URL? {
        guard let data = viewModel.decryptedData else { return nil }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(viewModel.file.name)
        try? data.write(to: url)
        previewURL = url
        return url
    }

    private func confirmDelete() {
        let alert = UIAlertController(
            title: "Delete File",
            message: "Are you sure you want to delete \"\(viewModel.file.name)\"? This action cannot be undone.",
            preferredStyle: .alert
        )

        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Delete", style: .destructive) { [weak self] _ in
            self?.viewModel.deleteFile()
        })

        present(alert, animated: true)
    }

    @objc private func handlePinch(_ gesture: UIPinchGestureRecognizer) {
        guard let view = gesture.view else { return }

        if gesture.state == .changed {
            view.transform = view.transform.scaledBy(x: gesture.scale, y: gesture.scale)
            gesture.scale = 1
        }
    }

    // MARK: - Cleanup

    deinit {
        // Clean up temp file
        if let url = previewURL {
            try? FileManager.default.removeItem(at: url)
        }
    }
}
