import UIKit
import Combine

/// View controller for shared file preview
final class SharedFilePreviewViewController: BaseViewController {

    // MARK: - Properties

    private let viewModel: SharedFilePreviewViewModel

    // MARK: - UI Components

    private lazy var previewContainerView: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private lazy var progressView: UIProgressView = {
        let progress = UIProgressView(progressViewStyle: .default)
        progress.translatesAutoresizingMaskIntoConstraints = false
        progress.isHidden = true
        return progress
    }()

    private lazy var loadingLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.text = "Downloading and decrypting..."
        label.font = .systemFont(ofSize: 15)
        label.textColor = .secondaryLabel
        label.textAlignment = .center
        label.isHidden = true
        return label
    }()

    private lazy var imageView: UIImageView = {
        let imageView = UIImageView()
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.contentMode = .scaleAspectFit
        imageView.isHidden = true
        return imageView
    }()

    private lazy var textView: UITextView = {
        let textView = UITextView()
        textView.translatesAutoresizingMaskIntoConstraints = false
        textView.isEditable = false
        textView.font = .monospacedSystemFont(ofSize: 14, weight: .regular)
        textView.isHidden = true
        return textView
    }()

    private lazy var unsupportedLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.text = "Preview not available for this file type"
        label.font = .systemFont(ofSize: 15)
        label.textColor = .tertiaryLabel
        label.textAlignment = .center
        label.numberOfLines = 0
        label.isHidden = true
        return label
    }()

    // MARK: - Initialization

    init(viewModel: SharedFilePreviewViewModel) {
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
        title = viewModel.fileName

        view.addSubview(previewContainerView)
        view.addSubview(progressView)
        view.addSubview(loadingLabel)
        previewContainerView.addSubview(imageView)
        previewContainerView.addSubview(textView)
        previewContainerView.addSubview(unsupportedLabel)

        NSLayoutConstraint.activate([
            progressView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            progressView.centerYAnchor.constraint(equalTo: view.centerYAnchor, constant: -20),
            progressView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 40),
            progressView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -40),

            loadingLabel.topAnchor.constraint(equalTo: progressView.bottomAnchor, constant: 16),
            loadingLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),

            previewContainerView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            previewContainerView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            previewContainerView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            previewContainerView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            imageView.topAnchor.constraint(equalTo: previewContainerView.topAnchor),
            imageView.leadingAnchor.constraint(equalTo: previewContainerView.leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: previewContainerView.trailingAnchor),
            imageView.bottomAnchor.constraint(equalTo: previewContainerView.bottomAnchor),

            textView.topAnchor.constraint(equalTo: previewContainerView.topAnchor, constant: 16),
            textView.leadingAnchor.constraint(equalTo: previewContainerView.leadingAnchor, constant: 16),
            textView.trailingAnchor.constraint(equalTo: previewContainerView.trailingAnchor, constant: -16),
            textView.bottomAnchor.constraint(equalTo: previewContainerView.bottomAnchor, constant: -16),

            unsupportedLabel.centerXAnchor.constraint(equalTo: previewContainerView.centerXAnchor),
            unsupportedLabel.centerYAnchor.constraint(equalTo: previewContainerView.centerYAnchor)
        ])
    }

    override func setupBindings() {
        viewModel.$isLoading
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isLoading in
                self?.progressView.isHidden = !isLoading
                self?.loadingLabel.isHidden = !isLoading
                self?.previewContainerView.isHidden = isLoading
            }
            .store(in: &cancellables)

        viewModel.$downloadProgress
            .receive(on: DispatchQueue.main)
            .sink { [weak self] progress in
                self?.progressView.progress = Float(progress)
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
            .sink { [weak self] error in
                self?.showError(error)
            }
            .store(in: &cancellables)
    }

    private func displayContent(_ data: Data) {
        switch viewModel.fileType {
        case .image:
            if let image = UIImage(data: data) {
                imageView.image = image
                imageView.isHidden = false
            }
        case .text:
            if let text = String(data: data, encoding: .utf8) {
                textView.text = text
                textView.isHidden = false
            }
        case .pdf, .video, .audio:
            // For these types, we would use specialized viewers
            unsupportedLabel.text = "Preview available - tap to open"
            unsupportedLabel.isHidden = false
        case .unknown:
            unsupportedLabel.isHidden = false
        }
    }
}
