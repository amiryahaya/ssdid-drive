import UIKit
import Combine

/// View controller for batch file upload from Share Extension
final class BatchUploadViewController: BaseViewController {

    // MARK: - Layout Constants

    private enum Layout {
        static let cellHeight: CGFloat = 72
        static let footerHeight: CGFloat = 140
        static let buttonHeight: CGFloat = 52
        static let buttonCornerRadius: CGFloat = 12
        static let horizontalPadding: CGFloat = 24
        static let verticalSpacing: CGFloat = 16
        static let smallSpacing: CGFloat = 8
        static let tableViewDebounceMs = 100
        static let autoDismissDelay: TimeInterval = 0.5
    }

    // MARK: - Localized Strings

    private enum Strings {
        static let title = NSLocalizedString("batch_upload.title", value: "Upload Files", comment: "Batch upload screen title")
        static let uploadAll = NSLocalizedString("batch_upload.upload_all", value: "Upload All", comment: "Upload all files button")
        static let cancelTitle = NSLocalizedString("batch_upload.cancel.title", value: "Cancel Upload?", comment: "Cancel upload alert title")
        static let cancelMessage = NSLocalizedString("batch_upload.cancel.message", value: "Some files have not been uploaded yet. Are you sure you want to cancel?", comment: "Cancel upload alert message")
        static let continueAction = NSLocalizedString("batch_upload.continue", value: "Continue", comment: "Continue action")
        static let cancelAction = NSLocalizedString("batch_upload.cancel_action", value: "Cancel Upload", comment: "Cancel upload action")
        static let incompleteTitle = NSLocalizedString("batch_upload.incomplete.title", value: "Upload Incomplete", comment: "Incomplete upload alert title")
        static let retryFailed = NSLocalizedString("batch_upload.retry_failed", value: "Retry Failed", comment: "Retry failed uploads action")
        static let done = NSLocalizedString("batch_upload.done", value: "Done", comment: "Done action")
        static let uploadComplete = NSLocalizedString("batch_upload.complete", value: "Upload complete", comment: "Upload complete status")
        static let sectionHeader = NSLocalizedString("batch_upload.section_header", value: "Files to Upload", comment: "Files section header")

        static func uploadingStatus(current: Int, total: Int) -> String {
            String(format: NSLocalizedString("batch_upload.uploading", value: "Uploading file %d of %d...", comment: "Uploading status"), current, total)
        }

        static func incompleteMessage(completed: Int, total: Int, failed: Int) -> String {
            String(format: NSLocalizedString("batch_upload.incomplete.message", value: "%d of %d files uploaded successfully. %d file(s) failed.", comment: "Incomplete upload message"), completed, total, failed)
        }

        static func completedWithFailures(completed: Int, failed: Int) -> String {
            String(format: NSLocalizedString("batch_upload.status.with_failures", value: "%d uploaded, %d failed", comment: "Status with failures"), completed, failed)
        }

        static func fileCount(count: Int, size: String) -> String {
            String(format: NSLocalizedString("batch_upload.file_count", value: "%d files (%@)", comment: "File count status"), count, size)
        }
    }

    // MARK: - Properties

    private let viewModel: BatchUploadViewModel

    // MARK: - UI Components

    private lazy var tableView: UITableView = {
        let table = UITableView(frame: .zero, style: .insetGrouped)
        table.translatesAutoresizingMaskIntoConstraints = false
        table.register(BatchUploadCell.self, forCellReuseIdentifier: BatchUploadCell.reuseIdentifier)
        table.dataSource = self
        table.rowHeight = Layout.cellHeight
        table.allowsSelection = false
        return table
    }()

    private lazy var footerView: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.backgroundColor = .systemBackground
        return view
    }()

    private lazy var overallProgressView: UIProgressView = {
        let progress = UIProgressView(progressViewStyle: .default)
        progress.translatesAutoresizingMaskIntoConstraints = false
        progress.progressTintColor = .systemBlue
        return progress
    }()

    private lazy var statusLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .systemFont(ofSize: 14)
        label.textColor = .secondaryLabel
        label.textAlignment = .center
        return label
    }()

    private lazy var uploadButton: UIButton = {
        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.setTitle(Strings.uploadAll, for: .normal)
        button.titleLabel?.font = .systemFont(ofSize: 17, weight: .semibold)
        button.backgroundColor = .systemBlue
        button.setTitleColor(.white, for: .normal)
        button.setTitleColor(.white.withAlphaComponent(0.5), for: .disabled)
        button.layer.cornerRadius = Layout.buttonCornerRadius
        button.addTarget(self, action: #selector(uploadTapped), for: .touchUpInside)
        return button
    }()

    // MARK: - Initialization

    init(viewModel: BatchUploadViewModel) {
        self.viewModel = viewModel
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Setup

    override func setupUI() {
        title = Strings.title

        navigationItem.leftBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .cancel,
            target: self,
            action: #selector(cancelTapped)
        )

        view.addSubview(tableView)
        view.addSubview(footerView)
        footerView.addSubview(overallProgressView)
        footerView.addSubview(statusLabel)
        footerView.addSubview(uploadButton)

        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: footerView.topAnchor),

            footerView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            footerView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            footerView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
            footerView.heightAnchor.constraint(equalToConstant: Layout.footerHeight),

            overallProgressView.topAnchor.constraint(equalTo: footerView.topAnchor, constant: Layout.verticalSpacing),
            overallProgressView.leadingAnchor.constraint(equalTo: footerView.leadingAnchor, constant: Layout.horizontalPadding),
            overallProgressView.trailingAnchor.constraint(equalTo: footerView.trailingAnchor, constant: -Layout.horizontalPadding),

            statusLabel.topAnchor.constraint(equalTo: overallProgressView.bottomAnchor, constant: Layout.smallSpacing),
            statusLabel.leadingAnchor.constraint(equalTo: footerView.leadingAnchor, constant: Layout.horizontalPadding),
            statusLabel.trailingAnchor.constraint(equalTo: footerView.trailingAnchor, constant: -Layout.horizontalPadding),

            uploadButton.topAnchor.constraint(equalTo: statusLabel.bottomAnchor, constant: Layout.verticalSpacing),
            uploadButton.leadingAnchor.constraint(equalTo: footerView.leadingAnchor, constant: Layout.horizontalPadding),
            uploadButton.trailingAnchor.constraint(equalTo: footerView.trailingAnchor, constant: -Layout.horizontalPadding),
            uploadButton.heightAnchor.constraint(equalToConstant: Layout.buttonHeight)
        ])

        updateStatusLabel()
    }

    override func setupBindings() {
        viewModel.$files
            .debounce(for: .milliseconds(Layout.tableViewDebounceMs), scheduler: DispatchQueue.main)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.tableView.reloadData()
            }
            .store(in: &cancellables)

        viewModel.$overallProgress
            .receive(on: DispatchQueue.main)
            .sink { [weak self] progress in
                self?.overallProgressView.progress = Float(progress)
            }
            .store(in: &cancellables)

        viewModel.$isUploading
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isUploading in
                self?.uploadButton.isEnabled = !isUploading
                self?.uploadButton.alpha = isUploading ? 0.5 : 1.0
                self?.uploadButton.backgroundColor = isUploading ? .systemGray : .systemBlue
                self?.navigationItem.leftBarButtonItem?.isEnabled = !isUploading
                self?.updateStatusLabel()
            }
            .store(in: &cancellables)

        viewModel.$currentFileIndex
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updateStatusLabel()
            }
            .store(in: &cancellables)

        viewModel.$uploadComplete
            .receive(on: DispatchQueue.main)
            .sink { [weak self] complete in
                guard let self = self, complete else { return }
                self.handleUploadComplete()
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

    @objc private func uploadTapped() {
        triggerHapticFeedback(.medium)
        viewModel.uploadAll()
    }

    @objc private func cancelTapped() {
        if viewModel.isUploading {
            showCancelConfirmation()
        } else {
            viewModel.cancel()
        }
    }

    private func showCancelConfirmation() {
        let alert = UIAlertController(
            title: Strings.cancelTitle,
            message: Strings.cancelMessage,
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: Strings.continueAction, style: .cancel))
        alert.addAction(UIAlertAction(title: Strings.cancelAction, style: .destructive) { [weak self] _ in
            self?.viewModel.cancel()
        })
        present(alert, animated: true)
    }

    private func handleUploadComplete() {
        if viewModel.failedFileCount > 0 {
            showUploadResultWithFailures()
        } else {
            triggerNotificationFeedback(.success)
            // Auto-dismiss after successful upload
            DispatchQueue.main.asyncAfter(deadline: .now() + Layout.autoDismissDelay) { [weak self] in
                self?.viewModel.dismiss()
            }
        }
    }

    private func showUploadResultWithFailures() {
        triggerNotificationFeedback(.warning)

        let alert = UIAlertController(
            title: Strings.incompleteTitle,
            message: Strings.incompleteMessage(
                completed: viewModel.completedFileCount,
                total: viewModel.totalFileCount,
                failed: viewModel.failedFileCount
            ),
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: Strings.retryFailed, style: .default) { [weak self] _ in
            self?.viewModel.retryFailed()
        })
        alert.addAction(UIAlertAction(title: Strings.done, style: .cancel) { [weak self] _ in
            self?.viewModel.dismiss()
        })
        present(alert, animated: true)
    }

    private func updateStatusLabel() {
        if viewModel.isUploading {
            let current = viewModel.currentFileIndex + 1
            let total = viewModel.totalFileCount
            statusLabel.text = Strings.uploadingStatus(current: current, total: total)
        } else if viewModel.uploadComplete {
            let completed = viewModel.completedFileCount
            let failed = viewModel.failedFileCount
            if failed > 0 {
                statusLabel.text = Strings.completedWithFailures(completed: completed, failed: failed)
            } else {
                statusLabel.text = Strings.uploadComplete
            }
        } else {
            statusLabel.text = Strings.fileCount(count: viewModel.totalFileCount, size: viewModel.formattedTotalSize)
        }
    }
}

// MARK: - UITableViewDataSource

extension BatchUploadViewController: UITableViewDataSource {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        viewModel.files.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard let cell = tableView.dequeueReusableCell(
            withIdentifier: BatchUploadCell.reuseIdentifier,
            for: indexPath
        ) as? BatchUploadCell else {
            return UITableViewCell()
        }
        cell.configure(with: viewModel.files[indexPath.row])
        return cell
    }

    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        Strings.sectionHeader
    }
}

// MARK: - BatchUploadCell

final class BatchUploadCell: UITableViewCell {

    static let reuseIdentifier = "BatchUploadCell"

    // MARK: - Layout Constants

    private enum Layout {
        static let iconSize: CGFloat = 32
        static let statusIconSize: CGFloat = 24
        static let horizontalPadding: CGFloat = 16
        static let iconToLabelSpacing: CGFloat = 12
        static let labelToStatusSpacing: CGFloat = 8
        static let verticalPadding: CGFloat = 12
        static let labelVerticalSpacing: CGFloat = 2
    }

    // MARK: - Accessibility Strings

    private enum AccessibilityStrings {
        static let pending = NSLocalizedString("batch_upload.status.pending", value: "Pending", comment: "Pending status accessibility label")
        static let uploading = NSLocalizedString("batch_upload.status.uploading", value: "Uploading", comment: "Uploading status accessibility label")
        static let completed = NSLocalizedString("batch_upload.status.completed", value: "Completed", comment: "Completed status accessibility label")
        static let failed = NSLocalizedString("batch_upload.status.failed", value: "Failed", comment: "Failed status accessibility label")
        static let imageFile = NSLocalizedString("batch_upload.file_type.image", value: "Image file", comment: "Image file type accessibility label")
        static let pdfFile = NSLocalizedString("batch_upload.file_type.pdf", value: "PDF document", comment: "PDF file type accessibility label")
        static let videoFile = NSLocalizedString("batch_upload.file_type.video", value: "Video file", comment: "Video file type accessibility label")
        static let audioFile = NSLocalizedString("batch_upload.file_type.audio", value: "Audio file", comment: "Audio file type accessibility label")
        static let archiveFile = NSLocalizedString("batch_upload.file_type.archive", value: "Archive file", comment: "Archive file type accessibility label")
        static let textFile = NSLocalizedString("batch_upload.file_type.text", value: "Text file", comment: "Text file type accessibility label")
        static let genericFile = NSLocalizedString("batch_upload.file_type.generic", value: "File", comment: "Generic file type accessibility label")
    }

    // MARK: - UI Components

    private let fileIconImageView: UIImageView = {
        let imageView = UIImageView()
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.contentMode = .scaleAspectFit
        imageView.tintColor = .systemBlue
        return imageView
    }()

    private let fileNameLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .systemFont(ofSize: 15, weight: .medium)
        label.numberOfLines = 1
        return label
    }()

    private let fileSizeLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .systemFont(ofSize: 13)
        label.textColor = .secondaryLabel
        return label
    }()

    private let progressView: UIProgressView = {
        let progress = UIProgressView(progressViewStyle: .default)
        progress.translatesAutoresizingMaskIntoConstraints = false
        return progress
    }()

    private let statusImageView: UIImageView = {
        let imageView = UIImageView()
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.contentMode = .scaleAspectFit
        return imageView
    }()

    // MARK: - Initialization

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setupUI()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Setup

    private func setupUI() {
        contentView.addSubview(fileIconImageView)
        contentView.addSubview(fileNameLabel)
        contentView.addSubview(fileSizeLabel)
        contentView.addSubview(progressView)
        contentView.addSubview(statusImageView)

        NSLayoutConstraint.activate([
            fileIconImageView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: Layout.horizontalPadding),
            fileIconImageView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            fileIconImageView.widthAnchor.constraint(equalToConstant: Layout.iconSize),
            fileIconImageView.heightAnchor.constraint(equalToConstant: Layout.iconSize),

            fileNameLabel.leadingAnchor.constraint(equalTo: fileIconImageView.trailingAnchor, constant: Layout.iconToLabelSpacing),
            fileNameLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: Layout.verticalPadding),
            fileNameLabel.trailingAnchor.constraint(equalTo: statusImageView.leadingAnchor, constant: -Layout.labelToStatusSpacing),

            fileSizeLabel.leadingAnchor.constraint(equalTo: fileNameLabel.leadingAnchor),
            fileSizeLabel.topAnchor.constraint(equalTo: fileNameLabel.bottomAnchor, constant: Layout.labelVerticalSpacing),

            progressView.leadingAnchor.constraint(equalTo: fileNameLabel.leadingAnchor),
            progressView.trailingAnchor.constraint(equalTo: statusImageView.leadingAnchor, constant: -Layout.labelToStatusSpacing),
            progressView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -Layout.verticalPadding),

            statusImageView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -Layout.horizontalPadding),
            statusImageView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            statusImageView.widthAnchor.constraint(equalToConstant: Layout.statusIconSize),
            statusImageView.heightAnchor.constraint(equalToConstant: Layout.statusIconSize)
        ])
    }

    // MARK: - Configuration

    func configure(with status: BatchUploadViewModel.ImportFileStatus) {
        fileNameLabel.text = status.info.name
        fileSizeLabel.text = ByteCountFormatter.string(fromByteCount: status.info.size, countStyle: .file)

        let (icon, accessibilityLabel) = iconAndAccessibilityLabel(for: status.info.name)
        fileIconImageView.image = icon
        fileIconImageView.accessibilityLabel = accessibilityLabel

        progressView.progress = Float(status.progress)

        switch status.status {
        case .pending:
            statusImageView.image = UIImage(systemName: "clock")
            statusImageView.tintColor = .systemGray
            statusImageView.accessibilityLabel = AccessibilityStrings.pending
            progressView.progressTintColor = .systemGray
            progressView.isHidden = true

        case .uploading:
            statusImageView.image = nil
            statusImageView.accessibilityLabel = AccessibilityStrings.uploading
            progressView.progressTintColor = .systemBlue
            progressView.isHidden = false

        case .completed:
            statusImageView.image = UIImage(systemName: "checkmark.circle.fill")
            statusImageView.tintColor = .systemGreen
            statusImageView.accessibilityLabel = AccessibilityStrings.completed
            progressView.progressTintColor = .systemGreen
            progressView.isHidden = true

        case .failed:
            statusImageView.image = UIImage(systemName: "exclamationmark.circle.fill")
            statusImageView.tintColor = .systemRed
            statusImageView.accessibilityLabel = AccessibilityStrings.failed
            progressView.progressTintColor = .systemRed
            progressView.isHidden = true
        }
    }

    /// Returns the icon and accessibility label for a file based on its extension
    private func iconAndAccessibilityLabel(for fileName: String) -> (UIImage?, String) {
        let ext = (fileName as NSString).pathExtension.lowercased()

        switch ext {
        case "jpg", "jpeg", "png", "gif", "heic", "webp":
            return (UIImage(systemName: "photo.fill"), AccessibilityStrings.imageFile)
        case "pdf":
            return (UIImage(systemName: "doc.fill"), AccessibilityStrings.pdfFile)
        case "mp4", "mov", "m4v", "avi":
            return (UIImage(systemName: "video.fill"), AccessibilityStrings.videoFile)
        case "mp3", "m4a", "wav", "aac":
            return (UIImage(systemName: "music.note"), AccessibilityStrings.audioFile)
        case "zip", "tar", "gz", "7z":
            return (UIImage(systemName: "archivebox.fill"), AccessibilityStrings.archiveFile)
        case "txt", "md", "json", "xml":
            return (UIImage(systemName: "doc.text.fill"), AccessibilityStrings.textFile)
        default:
            return (UIImage(systemName: "doc.fill"), AccessibilityStrings.genericFile)
        }
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        fileNameLabel.text = nil
        fileSizeLabel.text = nil
        progressView.progress = 0
        statusImageView.image = nil
    }
}
