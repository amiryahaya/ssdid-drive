import UIKit
import Combine

/// View controller for received shares
final class ReceivedSharesViewController: BaseViewController {

    // MARK: - Properties

    private let viewModel: ReceivedSharesViewModel

    // MARK: - UI Components

    private lazy var tableView: UITableView = {
        let tableView = UITableView(frame: .zero, style: .plain)
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.delegate = self
        tableView.dataSource = self
        tableView.register(ShareCell.self, forCellReuseIdentifier: ShareCell.reuseIdentifier)
        tableView.separatorInset = UIEdgeInsets(top: 0, left: 72, bottom: 0, right: 0)
        return tableView
    }()

    private lazy var emptyStateLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.text = "No files have been shared with you yet."
        label.font = .systemFont(ofSize: 15)
        label.textColor = .tertiaryLabel
        label.textAlignment = .center
        label.numberOfLines = 0
        label.isHidden = true
        return label
    }()

    private lazy var refreshControl: UIRefreshControl = {
        let control = UIRefreshControl()
        control.addTarget(self, action: #selector(refreshData), for: .valueChanged)
        return control
    }()

    // MARK: - Initialization

    init(viewModel: ReceivedSharesViewModel) {
        self.viewModel = viewModel
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        viewModel.loadShares()
    }

    // MARK: - Setup

    override func setupUI() {
        view.backgroundColor = .systemBackground
        title = "Shared With Me"

        navigationItem.rightBarButtonItem = UIBarButtonItem(
            title: "Created",
            style: .plain,
            target: self,
            action: #selector(showCreatedShares)
        )

        view.addSubview(tableView)
        view.addSubview(emptyStateLabel)

        tableView.refreshControl = refreshControl

        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            emptyStateLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            emptyStateLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            emptyStateLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 32),
            emptyStateLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -32)
        ])
    }

    override func setupBindings() {
        viewModel.$shares
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.tableView.reloadData()
                self?.updateEmptyState()
            }
            .store(in: &cancellables)

        viewModel.$isLoading
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isLoading in
                if !isLoading {
                    self?.refreshControl.endRefreshing()
                }
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

    private func updateEmptyState() {
        emptyStateLabel.isHidden = !viewModel.shares.isEmpty || viewModel.isLoading
    }

    // MARK: - Actions

    @objc private func refreshData() {
        viewModel.loadShares()
    }

    @objc private func showCreatedShares() {
        viewModel.coordinatorDelegate?.receivedSharesDidRequestCreatedShares()
    }
}

// MARK: - UITableViewDataSource & Delegate

extension ReceivedSharesViewController: UITableViewDataSource, UITableViewDelegate {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return viewModel.shares.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: ShareCell.reuseIdentifier, for: indexPath) as! ShareCell
        let share = viewModel.shares[indexPath.row]
        cell.configure(with: share, showGrantor: true)
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let share = viewModel.shares[indexPath.row]
        viewModel.selectShare(share)
    }

    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        return 72
    }
}

// MARK: - Share Cell

final class ShareCell: UITableViewCell {
    static let reuseIdentifier = "ShareCell"

    private lazy var iconView: UIImageView = {
        let imageView = UIImageView()
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.contentMode = .scaleAspectFit
        imageView.tintColor = .systemBlue
        return imageView
    }()

    private lazy var nameLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .systemFont(ofSize: 16, weight: .medium)
        return label
    }()

    private lazy var detailLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .systemFont(ofSize: 14)
        label.textColor = .secondaryLabel
        return label
    }()

    private lazy var permissionBadge: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .systemFont(ofSize: 12, weight: .medium)
        label.textAlignment = .center
        label.layer.cornerRadius = 4
        label.layer.masksToBounds = true
        return label
    }()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setupUI()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupUI() {
        contentView.addSubview(iconView)
        contentView.addSubview(nameLabel)
        contentView.addSubview(detailLabel)
        contentView.addSubview(permissionBadge)

        NSLayoutConstraint.activate([
            iconView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            iconView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 44),
            iconView.heightAnchor.constraint(equalToConstant: 44),

            nameLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 16),
            nameLabel.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 12),
            nameLabel.trailingAnchor.constraint(equalTo: permissionBadge.leadingAnchor, constant: -8),

            detailLabel.topAnchor.constraint(equalTo: nameLabel.bottomAnchor, constant: 4),
            detailLabel.leadingAnchor.constraint(equalTo: nameLabel.leadingAnchor),
            detailLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),

            permissionBadge.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            permissionBadge.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            permissionBadge.widthAnchor.constraint(greaterThanOrEqualToConstant: 60),
            permissionBadge.heightAnchor.constraint(equalToConstant: 22)
        ])
    }

    func configure(with share: Share, showGrantor: Bool) {
        let resourceLabel = share.resourceType == .folder ? "Shared Folder" : "Shared File"
        nameLabel.text = resourceLabel
        iconView.image = UIImage(systemName: share.isFolder ? "folder.fill" : "doc.fill")

        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .medium
        let dateString = dateFormatter.string(from: share.createdAt)
        detailLabel.text = "\(share.permission.displayName) • \(dateString)"

        // Permission badge
        permissionBadge.text = " \(share.permission.displayName) "
        if share.isActive {
            permissionBadge.backgroundColor = .systemGreen.withAlphaComponent(0.2)
            permissionBadge.textColor = .systemGreen
        } else {
            permissionBadge.backgroundColor = .systemGray.withAlphaComponent(0.2)
            permissionBadge.textColor = .systemGray
        }

        // Accessibility
        isAccessibilityElement = true
        accessibilityLabel = "\(resourceLabel), \(share.permission.displayName), \(dateString)"
        accessibilityTraits = [.button]
        accessibilityHint = "Double tap to open"
    }
}
