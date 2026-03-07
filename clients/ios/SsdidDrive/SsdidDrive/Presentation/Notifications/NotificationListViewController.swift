import UIKit
import Combine

/// View controller for notification list
final class NotificationListViewController: BaseViewController {

    // MARK: - Types

    /// Section identifier for diffable data source
    private struct SectionIdentifier: Hashable {
        let title: String
    }

    // MARK: - Properties

    private let viewModel: NotificationListViewModel
    private var dataSource: UITableViewDiffableDataSource<SectionIdentifier, AppNotification>!

    // MARK: - UI Components

    private lazy var tableView: UITableView = {
        let tableView = UITableView(frame: .zero, style: .grouped)
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.delegate = self
        tableView.register(NotificationCell.self, forCellReuseIdentifier: NotificationCell.reuseIdentifier)
        tableView.separatorInset = UIEdgeInsets(top: 0, left: 72, bottom: 0, right: 0)
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 80
        tableView.sectionHeaderTopPadding = 0
        return tableView
    }()

    private lazy var emptyStateView: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.isHidden = true

        let stackView = UIStackView()
        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.axis = .vertical
        stackView.alignment = .center
        stackView.spacing = 12

        let iconView = UIImageView()
        iconView.image = UIImage(systemName: "bell.slash")
        iconView.tintColor = .tertiaryLabel
        iconView.contentMode = .scaleAspectFit
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.widthAnchor.constraint(equalToConstant: 60).isActive = true
        iconView.heightAnchor.constraint(equalToConstant: 60).isActive = true

        let titleLabel = UILabel()
        titleLabel.text = NSLocalizedString("notification.empty.title", value: "No Notifications", comment: "Empty state title")
        titleLabel.font = .systemFont(ofSize: 18, weight: .semibold)
        titleLabel.textColor = .secondaryLabel
        titleLabel.textAlignment = .center

        let subtitleLabel = UILabel()
        subtitleLabel.text = NSLocalizedString("notification.empty.message", value: "You're all caught up! New notifications will appear here.", comment: "Empty state message")
        subtitleLabel.font = .systemFont(ofSize: 15)
        subtitleLabel.textColor = .tertiaryLabel
        subtitleLabel.textAlignment = .center
        subtitleLabel.numberOfLines = 0

        stackView.addArrangedSubview(iconView)
        stackView.addArrangedSubview(titleLabel)
        stackView.addArrangedSubview(subtitleLabel)
        view.addSubview(stackView)

        NSLayoutConstraint.activate([
            stackView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            stackView.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            stackView.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 32),
            stackView.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -32)
        ])

        return view
    }()

    private lazy var refreshControl: UIRefreshControl = {
        let control = UIRefreshControl()
        control.addTarget(self, action: #selector(refreshData), for: .valueChanged)
        return control
    }()

    // MARK: - Initialization

    init(viewModel: NotificationListViewModel) {
        self.viewModel = viewModel
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
    }

    // MARK: - Setup

    override func setupUI() {
        view.backgroundColor = .systemBackground
        title = NSLocalizedString("notification.title", value: "Notifications", comment: "Notifications screen title")

        // Configure diffable data source before adding tableView to hierarchy
        configureDataSource()

        // Navigation bar items
        setupNavigationItems()

        // Add subviews
        view.addSubview(tableView)
        view.addSubview(emptyStateView)

        tableView.refreshControl = refreshControl

        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            emptyStateView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            emptyStateView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            emptyStateView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            emptyStateView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    private func configureDataSource() {
        dataSource = UITableViewDiffableDataSource<SectionIdentifier, AppNotification>(
            tableView: tableView
        ) { [weak self] tableView, indexPath, notification in
            guard let cell = tableView.dequeueReusableCell(
                withIdentifier: NotificationCell.reuseIdentifier,
                for: indexPath
            ) as? NotificationCell else {
                return UITableViewCell()
            }
            cell.configure(with: notification)
            return cell
        }

        // Configure section header titles
        dataSource.defaultRowAnimation = .fade
    }

    private func applySnapshot(sections: [NotificationListViewModel.Section], animatingDifferences: Bool = true) {
        var snapshot = NSDiffableDataSourceSnapshot<SectionIdentifier, AppNotification>()

        for section in sections {
            let sectionIdentifier = SectionIdentifier(title: section.title)
            snapshot.appendSections([sectionIdentifier])
            snapshot.appendItems(section.notifications, toSection: sectionIdentifier)
        }

        dataSource.apply(snapshot, animatingDifferences: animatingDifferences)
    }

    private func setupNavigationItems() {
        // Mark all as read button (shown when there are unread notifications)
        updateMarkAllReadButton()

        // More actions menu
        let moreMenu = UIMenu(title: "", children: [
            UIAction(
                title: NSLocalizedString("notification.action.markAllRead", value: "Mark All as Read", comment: "Mark all notifications as read"),
                image: UIImage(systemName: "checkmark.circle")
            ) { [weak self] _ in
                self?.viewModel.markAllAsRead()
            },
            UIAction(
                title: NSLocalizedString("notification.action.deleteAll", value: "Delete All", comment: "Delete all notifications"),
                image: UIImage(systemName: "trash"),
                attributes: .destructive
            ) { [weak self] _ in
                self?.confirmDeleteAll()
            }
        ])

        navigationItem.rightBarButtonItem = UIBarButtonItem(
            image: UIImage(systemName: "ellipsis.circle"),
            menu: moreMenu
        )
    }

    private func updateMarkAllReadButton() {
        if viewModel.hasUnread {
            navigationItem.leftBarButtonItem = UIBarButtonItem(
                title: NSLocalizedString("notification.action.readAll", value: "Read All", comment: "Mark all as read button"),
                style: .plain,
                target: self,
                action: #selector(markAllAsRead)
            )
        } else {
            navigationItem.leftBarButtonItem = nil
        }
    }

    override func setupBindings() {
        viewModel.$sections
            .receive(on: DispatchQueue.main)
            .sink { [weak self] sections in
                self?.applySnapshot(sections: sections)
                self?.updateEmptyState()
            }
            .store(in: &cancellables)

        viewModel.$isRefreshing
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isRefreshing in
                if !isRefreshing {
                    self?.refreshControl.endRefreshing()
                }
            }
            .store(in: &cancellables)

        viewModel.$unreadCount
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updateMarkAllReadButton()
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
        let isEmpty = viewModel.isEmpty && !viewModel.isLoading
        emptyStateView.isHidden = !isEmpty
        tableView.isHidden = isEmpty
    }

    // MARK: - Actions

    @objc private func refreshData() {
        viewModel.refreshNotifications()
    }

    @objc private func markAllAsRead() {
        viewModel.markAllAsRead()
        triggerNotificationFeedback(.success)
    }

    private func confirmDeleteAll() {
        let alert = UIAlertController(
            title: NSLocalizedString("notification.deleteAll.title", value: "Delete All Notifications?", comment: "Delete all confirmation title"),
            message: NSLocalizedString("notification.deleteAll.message", value: "This action cannot be undone.", comment: "Delete all confirmation message"),
            preferredStyle: .alert
        )

        alert.addAction(UIAlertAction(
            title: NSLocalizedString("common.cancel", value: "Cancel", comment: "Cancel button"),
            style: .cancel
        ))

        alert.addAction(UIAlertAction(
            title: NSLocalizedString("common.delete", value: "Delete", comment: "Delete button"),
            style: .destructive
        ) { [weak self] _ in
            self?.viewModel.deleteAllNotifications()
        })

        present(alert, animated: true)
    }
}

// MARK: - UITableViewDelegate

extension NotificationListViewController: UITableViewDelegate {

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard let notification = dataSource.itemIdentifier(for: indexPath) else { return }
        viewModel.selectNotification(notification)
    }

    func tableView(_ tableView: UITableView, leadingSwipeActionsConfigurationForRowAt indexPath: IndexPath) -> UISwipeActionsConfiguration? {
        guard let notification = dataSource.itemIdentifier(for: indexPath) else { return nil }

        // Only show mark as read action if notification is unread
        guard notification.isUnread else { return nil }

        let markReadAction = UIContextualAction(style: .normal, title: nil) { [weak self] _, _, completion in
            self?.viewModel.markAsRead(notification)
            self?.triggerSelectionFeedback()
            completion(true)
        }
        markReadAction.image = UIImage(systemName: "checkmark.circle")
        markReadAction.backgroundColor = .systemBlue

        return UISwipeActionsConfiguration(actions: [markReadAction])
    }

    func tableView(_ tableView: UITableView, trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath) -> UISwipeActionsConfiguration? {
        guard let notification = dataSource.itemIdentifier(for: indexPath) else { return nil }

        let deleteAction = UIContextualAction(style: .destructive, title: nil) { [weak self] _, _, completion in
            self?.viewModel.deleteNotification(notification)
            completion(true)
        }
        deleteAction.image = UIImage(systemName: "trash")

        return UISwipeActionsConfiguration(actions: [deleteAction])
    }

    func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        let snapshot = dataSource.snapshot()
        guard section < snapshot.sectionIdentifiers.count else { return nil }

        let sectionIdentifier = snapshot.sectionIdentifiers[section]

        let headerView = UITableViewHeaderFooterView()
        headerView.textLabel?.text = sectionIdentifier.title
        headerView.textLabel?.font = .systemFont(ofSize: 13, weight: .semibold)
        headerView.textLabel?.textColor = .secondaryLabel
        return headerView
    }

    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        let snapshot = dataSource.snapshot()
        guard section < snapshot.sectionIdentifiers.count else { return nil }
        return snapshot.sectionIdentifiers[section].title
    }
}
