import UIKit
import Combine

/// View controller for chat screen
final class ChatViewController: BaseViewController {

    // MARK: - Properties

    private let viewModel: ChatViewModel

    // MARK: - UI Components

    private lazy var tableView: UITableView = {
        let tableView = UITableView(frame: .zero, style: .plain)
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.delegate = self
        tableView.dataSource = self
        tableView.register(UserMessageCell.self, forCellReuseIdentifier: UserMessageCell.reuseIdentifier)
        tableView.register(AssistantMessageCell.self, forCellReuseIdentifier: AssistantMessageCell.reuseIdentifier)
        tableView.separatorStyle = .none
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 80
        tableView.keyboardDismissMode = .interactive
        tableView.allowsSelection = false
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
        iconView.image = UIImage(systemName: "bubble.left.and.bubble.right")
        iconView.tintColor = .tertiaryLabel
        iconView.contentMode = .scaleAspectFit
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.widthAnchor.constraint(equalToConstant: 48).isActive = true
        iconView.heightAnchor.constraint(equalToConstant: 48).isActive = true

        let titleLabel = UILabel()
        titleLabel.text = NSLocalizedString("pii.chat.startConversation", value: "Start the conversation", comment: "Empty chat state")
        titleLabel.font = .systemFont(ofSize: 16, weight: .medium)
        titleLabel.textColor = .secondaryLabel
        titleLabel.textAlignment = .center

        let subtitleLabel = UILabel()
        subtitleLabel.text = NSLocalizedString("pii.chat.piiProtected", value: "Your messages will be scanned for PII\nand protected automatically.", comment: "PII protection info")
        subtitleLabel.font = .systemFont(ofSize: 14)
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

    private lazy var inputBar: MessageInputBar = {
        let bar = MessageInputBar()
        bar.translatesAutoresizingMaskIntoConstraints = false
        bar.delegate = self
        return bar
    }()

    private lazy var headerView: UIView = {
        let view = UIView()
        view.backgroundColor = .systemBackground
        view.translatesAutoresizingMaskIntoConstraints = false

        let stackView = UIStackView()
        stackView.axis = .horizontal
        stackView.spacing = 8
        stackView.alignment = .center
        stackView.translatesAutoresizingMaskIntoConstraints = false

        let providerBadge = UILabel()
        providerBadge.font = .systemFont(ofSize: 12, weight: .medium)
        providerBadge.textColor = .secondaryLabel
        providerBadge.backgroundColor = .tertiarySystemFill
        providerBadge.layer.cornerRadius = 4
        providerBadge.layer.masksToBounds = true
        providerBadge.text = "  \(viewModel.providerName)  "
        providerBadge.tag = 100

        let modelLabel = UILabel()
        modelLabel.font = .systemFont(ofSize: 12)
        modelLabel.textColor = .tertiaryLabel
        modelLabel.text = viewModel.conversation.llmModel
        modelLabel.tag = 101

        let kemStatusView = UIImageView()
        kemStatusView.contentMode = .scaleAspectFit
        kemStatusView.tintColor = viewModel.isKemRegistered ? .systemGreen : .tertiaryLabel
        kemStatusView.image = viewModel.isKemRegistered
            ? UIImage(systemName: "checkmark.shield.fill")
            : UIImage(systemName: "shield")
        kemStatusView.tag = 102

        stackView.addArrangedSubview(providerBadge)
        stackView.addArrangedSubview(modelLabel)
        stackView.addArrangedSubview(UIView()) // Spacer
        stackView.addArrangedSubview(kemStatusView)

        view.addSubview(stackView)

        NSLayoutConstraint.activate([
            stackView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            stackView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            stackView.topAnchor.constraint(equalTo: view.topAnchor, constant: 8),
            stackView.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -8),
            kemStatusView.widthAnchor.constraint(equalToConstant: 20),
            kemStatusView.heightAnchor.constraint(equalToConstant: 20)
        ])

        return view
    }()

    private var inputBarBottomConstraint: NSLayoutConstraint!

    // MARK: - Initialization

    init(viewModel: ChatViewModel) {
        self.viewModel = viewModel
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Lifecycle

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        setupKeyboardObservers()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        removeKeyboardObservers()
    }

    // MARK: - Setup

    override func setupUI() {
        view.backgroundColor = .systemBackground
        title = viewModel.conversation.title ?? NSLocalizedString("pii.chat.untitled", value: "Untitled Chat", comment: "Untitled conversation")

        view.addSubview(headerView)
        view.addSubview(tableView)
        view.addSubview(emptyStateView)
        view.addSubview(inputBar)

        inputBarBottomConstraint = inputBar.bottomAnchor.constraint(equalTo: view.bottomAnchor)

        NSLayoutConstraint.activate([
            headerView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            headerView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            headerView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            headerView.heightAnchor.constraint(equalToConstant: 40),

            tableView.topAnchor.constraint(equalTo: headerView.bottomAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: inputBar.topAnchor),

            emptyStateView.topAnchor.constraint(equalTo: headerView.bottomAnchor),
            emptyStateView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            emptyStateView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            emptyStateView.bottomAnchor.constraint(equalTo: inputBar.topAnchor),

            inputBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            inputBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            inputBarBottomConstraint
        ])
    }

    override func setupBindings() {
        viewModel.$messages
            .receive(on: DispatchQueue.main)
            .sink { [weak self] messages in
                self?.tableView.reloadData()
                self?.updateEmptyState()
                self?.scrollToBottom()
            }
            .store(in: &cancellables)

        viewModel.$isSending
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isSending in
                self?.inputBar.isSending = isSending
            }
            .store(in: &cancellables)

        viewModel.$isKemRegistered
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isRegistered in
                self?.updateKemStatus(isRegistered)
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
        let isEmpty = viewModel.messages.isEmpty
        emptyStateView.isHidden = !isEmpty
        tableView.isHidden = isEmpty
    }

    private func updateKemStatus(_ isRegistered: Bool) {
        if let kemStatusView = headerView.viewWithTag(102) as? UIImageView {
            kemStatusView.tintColor = isRegistered ? .systemGreen : .tertiaryLabel
            kemStatusView.image = isRegistered
                ? UIImage(systemName: "checkmark.shield.fill")
                : UIImage(systemName: "shield")
        }
    }

    private func scrollToBottom() {
        guard !viewModel.messages.isEmpty else { return }
        let indexPath = IndexPath(row: viewModel.messages.count - 1, section: 0)
        tableView.scrollToRow(at: indexPath, at: .bottom, animated: true)
    }

    // MARK: - Keyboard Handling

    private func setupKeyboardObservers() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(keyboardWillShow),
            name: UIResponder.keyboardWillShowNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(keyboardWillHide),
            name: UIResponder.keyboardWillHideNotification,
            object: nil
        )
    }

    private func removeKeyboardObservers() {
        NotificationCenter.default.removeObserver(self, name: UIResponder.keyboardWillShowNotification, object: nil)
        NotificationCenter.default.removeObserver(self, name: UIResponder.keyboardWillHideNotification, object: nil)
    }

    @objc private func keyboardWillShow(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let keyboardFrame = userInfo[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect,
              let duration = userInfo[UIResponder.keyboardAnimationDurationUserInfoKey] as? Double else {
            return
        }

        inputBarBottomConstraint.constant = -keyboardFrame.height

        UIView.animate(withDuration: duration) {
            self.view.layoutIfNeeded()
        }

        scrollToBottom()
    }

    @objc private func keyboardWillHide(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let duration = userInfo[UIResponder.keyboardAnimationDurationUserInfoKey] as? Double else {
            return
        }

        inputBarBottomConstraint.constant = 0

        UIView.animate(withDuration: duration) {
            self.view.layoutIfNeeded()
        }
    }
}

// MARK: - UITableViewDataSource

extension ChatViewController: UITableViewDataSource {

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        viewModel.messages.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let message = viewModel.messages[indexPath.row]

        switch message.role {
        case .user:
            guard let cell = tableView.dequeueReusableCell(
                withIdentifier: UserMessageCell.reuseIdentifier,
                for: indexPath
            ) as? UserMessageCell else {
                return UITableViewCell()
            }
            cell.configure(with: message)
            return cell

        case .assistant:
            guard let cell = tableView.dequeueReusableCell(
                withIdentifier: AssistantMessageCell.reuseIdentifier,
                for: indexPath
            ) as? AssistantMessageCell else {
                return UITableViewCell()
            }
            cell.configure(with: message)
            return cell
        }
    }
}

// MARK: - UITableViewDelegate

extension ChatViewController: UITableViewDelegate {
    // Add delegate methods if needed
}

// MARK: - MessageInputBarDelegate

extension ChatViewController: MessageInputBarDelegate {

    func messageInputBar(_ inputBar: MessageInputBar, didSendMessage text: String) {
        viewModel.sendMessage(text)
    }
}
