import UIKit
import Combine

/// View controller for conversation list
final class ConversationListViewController: BaseViewController {

    // MARK: - Properties

    private let viewModel: ConversationListViewModel
    private var dataSource: UITableViewDiffableDataSource<Int, PiiConversation>!

    // MARK: - UI Components

    private lazy var tableView: UITableView = {
        let tableView = UITableView(frame: .zero, style: .plain)
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.delegate = self
        tableView.register(ConversationCell.self, forCellReuseIdentifier: ConversationCell.reuseIdentifier)
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 80
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
        iconView.image = UIImage(systemName: "message.badge.waveform")
        iconView.tintColor = .tertiaryLabel
        iconView.contentMode = .scaleAspectFit
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.widthAnchor.constraint(equalToConstant: 60).isActive = true
        iconView.heightAnchor.constraint(equalToConstant: 60).isActive = true

        let titleLabel = UILabel()
        titleLabel.text = NSLocalizedString("pii.chat.empty.title", value: "No Conversations", comment: "Empty state title")
        titleLabel.font = .systemFont(ofSize: 18, weight: .semibold)
        titleLabel.textColor = .secondaryLabel
        titleLabel.textAlignment = .center

        let subtitleLabel = UILabel()
        subtitleLabel.text = NSLocalizedString("pii.chat.empty.message", value: "Start a secure AI conversation with post-quantum encryption.", comment: "Empty state message")
        subtitleLabel.font = .systemFont(ofSize: 15)
        subtitleLabel.textColor = .tertiaryLabel
        subtitleLabel.textAlignment = .center
        subtitleLabel.numberOfLines = 0

        let newChatButton = UIButton(type: .system)
        newChatButton.setTitle(NSLocalizedString("pii.chat.newChat", value: "New Chat", comment: "New chat button"), for: .normal)
        newChatButton.titleLabel?.font = .systemFont(ofSize: 16, weight: .semibold)
        newChatButton.addTarget(self, action: #selector(newChatTapped), for: .touchUpInside)

        stackView.addArrangedSubview(iconView)
        stackView.addArrangedSubview(titleLabel)
        stackView.addArrangedSubview(subtitleLabel)
        stackView.addArrangedSubview(newChatButton)
        stackView.setCustomSpacing(24, after: subtitleLabel)

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

    init(viewModel: ConversationListViewModel) {
        self.viewModel = viewModel
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Setup

    override func setupUI() {
        view.backgroundColor = .systemBackground
        title = NSLocalizedString("pii.chat.title", value: "AI Chat", comment: "Chat screen title")

        configureDataSource()

        // Navigation bar items
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            image: UIImage(systemName: "square.and.pencil"),
            style: .plain,
            target: self,
            action: #selector(newChatTapped)
        )

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
        dataSource = UITableViewDiffableDataSource<Int, PiiConversation>(
            tableView: tableView
        ) { tableView, indexPath, conversation in
            guard let cell = tableView.dequeueReusableCell(
                withIdentifier: ConversationCell.reuseIdentifier,
                for: indexPath
            ) as? ConversationCell else {
                return UITableViewCell()
            }
            cell.configure(with: conversation)
            return cell
        }

        dataSource.defaultRowAnimation = .fade
    }

    private func applySnapshot(conversations: [PiiConversation], animatingDifferences: Bool = true) {
        var snapshot = NSDiffableDataSourceSnapshot<Int, PiiConversation>()
        snapshot.appendSections([0])
        snapshot.appendItems(conversations, toSection: 0)
        dataSource.apply(snapshot, animatingDifferences: animatingDifferences)
    }

    override func setupBindings() {
        viewModel.$conversations
            .receive(on: DispatchQueue.main)
            .sink { [weak self] conversations in
                self?.applySnapshot(conversations: conversations)
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

        viewModel.$isLoading
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isLoading in
                if isLoading {
                    self?.showLoading()
                } else {
                    self?.hideLoading()
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
        let isEmpty = viewModel.isEmpty && !viewModel.isLoading
        emptyStateView.isHidden = !isEmpty
        tableView.isHidden = isEmpty
    }

    // MARK: - Actions

    @objc private func refreshData() {
        viewModel.refreshConversations()
    }

    @objc private func newChatTapped() {
        viewModel.requestNewConversation()
    }
}

// MARK: - UITableViewDelegate

extension ConversationListViewController: UITableViewDelegate {

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard let conversation = dataSource.itemIdentifier(for: indexPath) else { return }
        viewModel.selectConversation(conversation)
    }

    func tableView(_ tableView: UITableView, trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath) -> UISwipeActionsConfiguration? {
        guard let conversation = dataSource.itemIdentifier(for: indexPath) else { return nil }

        let deleteAction = UIContextualAction(style: .destructive, title: nil) { [weak self] _, _, completion in
            self?.viewModel.deleteConversation(conversation)
            completion(true)
        }
        deleteAction.image = UIImage(systemName: "trash")

        return UISwipeActionsConfiguration(actions: [deleteAction])
    }
}
