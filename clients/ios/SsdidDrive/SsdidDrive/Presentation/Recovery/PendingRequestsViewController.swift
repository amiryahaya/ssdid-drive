import UIKit
import Combine

/// Pending requests view controller (trustee dashboard)
final class PendingRequestsViewController: BaseViewController {

    // MARK: - Properties

    private let viewModel: PendingRequestsViewModel

    // MARK: - UI Components

    private lazy var segmentedControl: UISegmentedControl = {
        let control = UISegmentedControl(items: ["Pending Requests", "Held Shares"])
        control.translatesAutoresizingMaskIntoConstraints = false
        control.selectedSegmentIndex = 0
        control.addTarget(self, action: #selector(segmentChanged), for: .valueChanged)
        return control
    }()

    private lazy var tableView: UITableView = {
        let tableView = UITableView(frame: .zero, style: .plain)
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.delegate = self
        tableView.dataSource = self
        tableView.register(PendingRequestCell.self, forCellReuseIdentifier: PendingRequestCell.reuseIdentifier)
        tableView.register(HeldShareCell.self, forCellReuseIdentifier: HeldShareCell.reuseIdentifier)
        tableView.separatorInset = UIEdgeInsets(top: 0, left: 72, bottom: 0, right: 0)
        return tableView
    }()

    private lazy var emptyStateView: EmptyStateView = {
        let view = EmptyStateView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.isHidden = true
        return view
    }()

    private lazy var refreshControl: UIRefreshControl = {
        let control = UIRefreshControl()
        control.addTarget(self, action: #selector(refreshData), for: .valueChanged)
        return control
    }()

    // MARK: - Initialization

    init(viewModel: PendingRequestsViewModel) {
        self.viewModel = viewModel
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        viewModel.loadData()
    }

    // MARK: - Setup

    override func setupUI() {
        view.backgroundColor = .systemBackground
        title = "Trustee Dashboard"

        view.addSubview(segmentedControl)
        view.addSubview(tableView)
        view.addSubview(emptyStateView)

        tableView.refreshControl = refreshControl

        NSLayoutConstraint.activate([
            segmentedControl.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 16),
            segmentedControl.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            segmentedControl.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),

            tableView.topAnchor.constraint(equalTo: segmentedControl.bottomAnchor, constant: 16),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            emptyStateView.centerXAnchor.constraint(equalTo: tableView.centerXAnchor),
            emptyStateView.centerYAnchor.constraint(equalTo: tableView.centerYAnchor),
            emptyStateView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 32),
            emptyStateView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -32)
        ])
    }

    override func setupBindings() {
        viewModel.$pendingRequests
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updateUI()
            }
            .store(in: &cancellables)

        viewModel.$heldShares
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updateUI()
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

    private func updateUI() {
        tableView.reloadData()
        updateEmptyState()
    }

    private func updateEmptyState() {
        let showPendingRequests = segmentedControl.selectedSegmentIndex == 0

        if showPendingRequests {
            emptyStateView.isHidden = !viewModel.pendingRequests.isEmpty
            emptyStateView.configure(
                icon: "bell.slash",
                title: "No Pending Requests",
                message: "You don't have any pending recovery requests to review."
            )
        } else {
            emptyStateView.isHidden = !viewModel.heldShares.isEmpty
            emptyStateView.configure(
                icon: "key.slash",
                title: "No Held Shares",
                message: "You are not holding any recovery shares for other users."
            )
        }
    }

    // MARK: - Actions

    @objc private func segmentChanged() {
        updateUI()
    }

    @objc private func refreshData() {
        viewModel.loadData()
    }

    private func approveRequest(_ request: RecoveryRequest) {
        let alert = UIAlertController(
            title: "Approve Recovery Request",
            message: "Are you sure you want to approve this recovery request from \(request.requesterEmail)?",
            preferredStyle: .alert
        )

        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Approve", style: .default) { [weak self] _ in
            self?.viewModel.approveRequest(request)
        })

        present(alert, animated: true)
    }

    private func rejectRequest(_ request: RecoveryRequest) {
        let alert = UIAlertController(
            title: "Reject Recovery Request",
            message: "Are you sure you want to reject this recovery request from \(request.requesterEmail)?",
            preferredStyle: .alert
        )

        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Reject", style: .destructive) { [weak self] _ in
            self?.viewModel.rejectRequest(request)
        })

        present(alert, animated: true)
    }
}

// MARK: - UITableViewDataSource & Delegate

extension PendingRequestsViewController: UITableViewDataSource, UITableViewDelegate {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        if segmentedControl.selectedSegmentIndex == 0 {
            return viewModel.pendingRequests.count
        } else {
            return viewModel.heldShares.count
        }
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        if segmentedControl.selectedSegmentIndex == 0 {
            let cell = tableView.dequeueReusableCell(withIdentifier: PendingRequestCell.reuseIdentifier, for: indexPath) as! PendingRequestCell
            let request = viewModel.pendingRequests[indexPath.row]
            cell.configure(with: request)
            cell.onApprove = { [weak self] in
                self?.approveRequest(request)
            }
            cell.onReject = { [weak self] in
                self?.rejectRequest(request)
            }
            return cell
        } else {
            let cell = tableView.dequeueReusableCell(withIdentifier: HeldShareCell.reuseIdentifier, for: indexPath) as! HeldShareCell
            let share = viewModel.heldShares[indexPath.row]
            cell.configure(with: share)
            return cell
        }
    }

    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        return segmentedControl.selectedSegmentIndex == 0 ? 100 : 72
    }
}

// MARK: - Pending Request Cell

final class PendingRequestCell: UITableViewCell {
    static let reuseIdentifier = "PendingRequestCell"

    var onApprove: (() -> Void)?
    var onReject: (() -> Void)?

    private lazy var avatarView: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.backgroundColor = .systemOrange.withAlphaComponent(0.1)
        view.layer.cornerRadius = 22
        return view
    }()

    private lazy var initialsLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .systemFont(ofSize: 16, weight: .semibold)
        label.textColor = .systemOrange
        label.textAlignment = .center
        return label
    }()

    private lazy var emailLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .systemFont(ofSize: 16, weight: .medium)
        return label
    }()

    private lazy var dateLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .systemFont(ofSize: 14)
        label.textColor = .secondaryLabel
        return label
    }()

    private lazy var approveButton: UIButton = {
        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.setTitle("Approve", for: .normal)
        button.setTitleColor(.white, for: .normal)
        button.backgroundColor = .systemGreen
        button.layer.cornerRadius = 8
        button.titleLabel?.font = .systemFont(ofSize: 14, weight: .medium)
        button.addTarget(self, action: #selector(approveTapped), for: .touchUpInside)
        return button
    }()

    private lazy var rejectButton: UIButton = {
        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.setTitle("Reject", for: .normal)
        button.setTitleColor(.systemRed, for: .normal)
        button.backgroundColor = .systemRed.withAlphaComponent(0.1)
        button.layer.cornerRadius = 8
        button.titleLabel?.font = .systemFont(ofSize: 14, weight: .medium)
        button.addTarget(self, action: #selector(rejectTapped), for: .touchUpInside)
        return button
    }()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setupUI()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupUI() {
        selectionStyle = .none

        contentView.addSubview(avatarView)
        avatarView.addSubview(initialsLabel)
        contentView.addSubview(emailLabel)
        contentView.addSubview(dateLabel)
        contentView.addSubview(approveButton)
        contentView.addSubview(rejectButton)

        NSLayoutConstraint.activate([
            avatarView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            avatarView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 16),
            avatarView.widthAnchor.constraint(equalToConstant: 44),
            avatarView.heightAnchor.constraint(equalToConstant: 44),

            initialsLabel.centerXAnchor.constraint(equalTo: avatarView.centerXAnchor),
            initialsLabel.centerYAnchor.constraint(equalTo: avatarView.centerYAnchor),

            emailLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 16),
            emailLabel.leadingAnchor.constraint(equalTo: avatarView.trailingAnchor, constant: 12),
            emailLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),

            dateLabel.topAnchor.constraint(equalTo: emailLabel.bottomAnchor, constant: 4),
            dateLabel.leadingAnchor.constraint(equalTo: emailLabel.leadingAnchor),

            approveButton.topAnchor.constraint(equalTo: dateLabel.bottomAnchor, constant: 12),
            approveButton.leadingAnchor.constraint(equalTo: emailLabel.leadingAnchor),
            approveButton.widthAnchor.constraint(equalToConstant: 80),
            approveButton.heightAnchor.constraint(equalToConstant: 32),

            rejectButton.topAnchor.constraint(equalTo: approveButton.topAnchor),
            rejectButton.leadingAnchor.constraint(equalTo: approveButton.trailingAnchor, constant: 8),
            rejectButton.widthAnchor.constraint(equalToConstant: 80),
            rejectButton.heightAnchor.constraint(equalToConstant: 32)
        ])
    }

    func configure(with request: RecoveryRequest) {
        emailLabel.text = request.requesterEmail

        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        dateLabel.text = "Requested \(formatter.localizedString(for: request.createdAt, relativeTo: Date()))"

        let email = request.requesterEmail
        initialsLabel.text = String(email.prefix(2)).uppercased()
    }

    @objc private func approveTapped() {
        onApprove?()
    }

    @objc private func rejectTapped() {
        onReject?()
    }
}

// MARK: - Held Share Cell

final class HeldShareCell: UITableViewCell {
    static let reuseIdentifier = "HeldShareCell"

    private lazy var iconView: UIImageView = {
        let imageView = UIImageView()
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.image = UIImage(systemName: "key.fill")
        imageView.tintColor = .systemBlue
        imageView.contentMode = .scaleAspectFit
        return imageView
    }()

    private lazy var ownerLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .systemFont(ofSize: 16, weight: .medium)
        return label
    }()

    private lazy var statusLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .systemFont(ofSize: 14)
        label.textColor = .secondaryLabel
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
        selectionStyle = .none

        contentView.addSubview(iconView)
        contentView.addSubview(ownerLabel)
        contentView.addSubview(statusLabel)

        NSLayoutConstraint.activate([
            iconView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            iconView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 44),
            iconView.heightAnchor.constraint(equalToConstant: 44),

            ownerLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 16),
            ownerLabel.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 12),
            ownerLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),

            statusLabel.topAnchor.constraint(equalTo: ownerLabel.bottomAnchor, constant: 4),
            statusLabel.leadingAnchor.constraint(equalTo: ownerLabel.leadingAnchor),
            statusLabel.trailingAnchor.constraint(equalTo: ownerLabel.trailingAnchor)
        ])
    }

    func configure(with share: RecoveryShare) {
        ownerLabel.text = "Recovery Share"
        statusLabel.text = "Share #\(share.shareIndex) (Trustee: \(share.trusteeId.prefix(8))...)"
    }
}

// MARK: - Empty State View

final class EmptyStateView: UIView {

    private lazy var iconImageView: UIImageView = {
        let imageView = UIImageView()
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.tintColor = .tertiaryLabel
        imageView.contentMode = .scaleAspectFit
        return imageView
    }()

    private lazy var titleLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .systemFont(ofSize: 17, weight: .semibold)
        label.textColor = .secondaryLabel
        label.textAlignment = .center
        return label
    }()

    private lazy var messageLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .systemFont(ofSize: 15)
        label.textColor = .tertiaryLabel
        label.textAlignment = .center
        label.numberOfLines = 0
        return label
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupUI()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupUI() {
        addSubview(iconImageView)
        addSubview(titleLabel)
        addSubview(messageLabel)

        NSLayoutConstraint.activate([
            iconImageView.topAnchor.constraint(equalTo: topAnchor),
            iconImageView.centerXAnchor.constraint(equalTo: centerXAnchor),
            iconImageView.widthAnchor.constraint(equalToConstant: 64),
            iconImageView.heightAnchor.constraint(equalToConstant: 64),

            titleLabel.topAnchor.constraint(equalTo: iconImageView.bottomAnchor, constant: 16),
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor),
            titleLabel.trailingAnchor.constraint(equalTo: trailingAnchor),

            messageLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 8),
            messageLabel.leadingAnchor.constraint(equalTo: leadingAnchor),
            messageLabel.trailingAnchor.constraint(equalTo: trailingAnchor),
            messageLabel.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    func configure(icon: String, title: String, message: String) {
        iconImageView.image = UIImage(systemName: icon)
        titleLabel.text = title
        messageLabel.text = message
    }
}
