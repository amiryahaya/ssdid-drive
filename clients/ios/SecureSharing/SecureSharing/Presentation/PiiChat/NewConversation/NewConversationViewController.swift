import UIKit
import Combine

/// View controller for creating a new conversation
final class NewConversationViewController: BaseViewController {

    // MARK: - Properties

    private let viewModel: NewConversationViewModel

    // MARK: - UI Components

    private lazy var scrollView: UIScrollView = {
        let scrollView = UIScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.keyboardDismissMode = .interactive
        return scrollView
    }()

    private lazy var contentStack: UIStackView = {
        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 24
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }()

    private lazy var titleTextField: UITextField = {
        let textField = UITextField()
        textField.placeholder = NSLocalizedString("pii.newChat.titlePlaceholder", value: "Enter a title (optional)", comment: "Title placeholder")
        textField.borderStyle = .roundedRect
        textField.font = .systemFont(ofSize: 16)
        textField.delegate = self
        textField.returnKeyType = .done
        return textField
    }()

    private lazy var providerPicker: UISegmentedControl = {
        let items = viewModel.providers.map { $0.name }
        let control = UISegmentedControl(items: items)
        control.selectedSegmentIndex = 0
        control.addTarget(self, action: #selector(providerChanged), for: .valueChanged)
        return control
    }()

    private lazy var modelPicker: UITableView = {
        let tableView = UITableView(frame: .zero, style: .insetGrouped)
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.dataSource = self
        tableView.delegate = self
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "ModelCell")
        tableView.isScrollEnabled = false
        return tableView
    }()

    private lazy var securityBanner: UIView = {
        let view = UIView()
        view.backgroundColor = .systemGreen.withAlphaComponent(0.1)
        view.layer.cornerRadius = 12
        view.translatesAutoresizingMaskIntoConstraints = false

        let iconView = UIImageView()
        iconView.image = UIImage(systemName: "checkmark.shield.fill")
        iconView.tintColor = .systemGreen
        iconView.contentMode = .scaleAspectFit
        iconView.translatesAutoresizingMaskIntoConstraints = false

        let titleLabel = UILabel()
        titleLabel.text = NSLocalizedString("pii.newChat.security.title", value: "Post-quantum encryption enabled", comment: "Security banner title")
        titleLabel.font = .systemFont(ofSize: 15, weight: .semibold)
        titleLabel.textColor = .systemGreen

        let descLabel = UILabel()
        descLabel.text = NSLocalizedString("pii.newChat.security.desc", value: "Your personal information will be automatically detected, tokenized, and protected using ML-KEM and KAZ-KEM encryption.", comment: "Security banner description")
        descLabel.font = .systemFont(ofSize: 13)
        descLabel.textColor = .secondaryLabel
        descLabel.numberOfLines = 0

        let textStack = UIStackView(arrangedSubviews: [titleLabel, descLabel])
        textStack.axis = .vertical
        textStack.spacing = 4
        textStack.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(iconView)
        view.addSubview(textStack)

        NSLayoutConstraint.activate([
            iconView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            iconView.topAnchor.constraint(equalTo: view.topAnchor, constant: 16),
            iconView.widthAnchor.constraint(equalToConstant: 24),
            iconView.heightAnchor.constraint(equalToConstant: 24),

            textStack.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 12),
            textStack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            textStack.topAnchor.constraint(equalTo: view.topAnchor, constant: 12),
            textStack.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -12)
        ])

        return view
    }()

    private lazy var createButton: UIButton = {
        var config = UIButton.Configuration.filled()
        config.title = NSLocalizedString("pii.newChat.create", value: "Create Conversation", comment: "Create button")
        config.cornerStyle = .large

        let button = UIButton(configuration: config)
        button.addTarget(self, action: #selector(createTapped), for: .touchUpInside)
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()

    private var modelPickerHeightConstraint: NSLayoutConstraint!

    // MARK: - Initialization

    init(viewModel: NewConversationViewModel) {
        self.viewModel = viewModel
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Setup

    override func setupUI() {
        view.backgroundColor = .systemBackground
        title = NSLocalizedString("pii.newChat.title", value: "New Conversation", comment: "New conversation title")

        navigationItem.leftBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .cancel,
            target: self,
            action: #selector(cancelTapped)
        )

        setupKeyboardDismissOnTap()

        view.addSubview(scrollView)
        scrollView.addSubview(contentStack)

        // Title section
        let titleSection = createSection(
            title: NSLocalizedString("pii.newChat.titleSection", value: "Title", comment: "Title section"),
            content: titleTextField
        )

        // Provider section
        let providerSection = createSection(
            title: NSLocalizedString("pii.newChat.providerSection", value: "AI Provider", comment: "Provider section"),
            content: providerPicker
        )

        // Model section
        let modelHeader = UILabel()
        modelHeader.text = NSLocalizedString("pii.newChat.modelSection", value: "Model", comment: "Model section")
        modelHeader.font = .systemFont(ofSize: 13, weight: .medium)
        modelHeader.textColor = .secondaryLabel

        modelPickerHeightConstraint = modelPicker.heightAnchor.constraint(equalToConstant: 150)

        contentStack.addArrangedSubview(titleSection)
        contentStack.addArrangedSubview(providerSection)
        contentStack.addArrangedSubview(modelHeader)
        contentStack.addArrangedSubview(modelPicker)
        contentStack.addArrangedSubview(securityBanner)
        contentStack.addArrangedSubview(createButton)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            contentStack.topAnchor.constraint(equalTo: scrollView.topAnchor, constant: 24),
            contentStack.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor, constant: 16),
            contentStack.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor, constant: -16),
            contentStack.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor, constant: -24),
            contentStack.widthAnchor.constraint(equalTo: scrollView.widthAnchor, constant: -32),

            modelPickerHeightConstraint,
            createButton.heightAnchor.constraint(equalToConstant: 50)
        ])

        updateModelPickerHeight()
    }

    private func createSection(title: String, content: UIView) -> UIView {
        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 8

        let label = UILabel()
        label.text = title
        label.font = .systemFont(ofSize: 13, weight: .medium)
        label.textColor = .secondaryLabel

        stack.addArrangedSubview(label)
        stack.addArrangedSubview(content)

        return stack
    }

    private func updateModelPickerHeight() {
        let rowHeight: CGFloat = 44
        let headerHeight: CGFloat = 20
        let count = CGFloat(viewModel.availableModels.count)
        modelPickerHeightConstraint.constant = (count * rowHeight) + headerHeight + 20
    }

    override func setupBindings() {
        viewModel.$selectedProviderId
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.modelPicker.reloadData()
                self?.updateModelPickerHeight()
            }
            .store(in: &cancellables)

        viewModel.$isCreating
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isCreating in
                self?.createButton.isEnabled = !isCreating
                self?.createButton.configuration?.showsActivityIndicator = isCreating
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

    // MARK: - Actions

    @objc private func providerChanged() {
        let provider = viewModel.providers[providerPicker.selectedSegmentIndex]
        viewModel.selectProvider(provider.id)
    }

    @objc private func createTapped() {
        viewModel.title = titleTextField.text ?? ""
        viewModel.createConversation()
    }

    @objc private func cancelTapped() {
        viewModel.cancel()
    }
}

// MARK: - UITableViewDataSource

extension NewConversationViewController: UITableViewDataSource {

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        viewModel.availableModels.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "ModelCell", for: indexPath)
        let model = viewModel.availableModels[indexPath.row]

        var content = cell.defaultContentConfiguration()
        content.text = model
        cell.contentConfiguration = content

        cell.accessoryType = model == viewModel.selectedModel ? .checkmark : .none

        return cell
    }
}

// MARK: - UITableViewDelegate

extension NewConversationViewController: UITableViewDelegate {

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let model = viewModel.availableModels[indexPath.row]
        viewModel.selectModel(model)
        tableView.reloadData()
    }
}

// MARK: - UITextFieldDelegate

extension NewConversationViewController: UITextFieldDelegate {

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        textField.resignFirstResponder()
        return true
    }
}
