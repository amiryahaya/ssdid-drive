import UIKit
import Combine

/// Share file view controller
final class ShareFileViewController: BaseViewController {

    // MARK: - Properties

    private let viewModel: ShareFileViewModel

    // MARK: - UI Components

    private lazy var scrollView: UIScrollView = {
        let scroll = UIScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.keyboardDismissMode = .onDrag
        return scroll
    }()

    private lazy var contentView: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private lazy var fileInfoView: UIView = {
        let container = UIView()
        container.translatesAutoresizingMaskIntoConstraints = false
        container.backgroundColor = .systemGray6
        container.layer.cornerRadius = 12

        let iconView = UIImageView(image: UIImage(systemName: viewModel.file.iconName))
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.tintColor = .systemBlue
        iconView.contentMode = .scaleAspectFit

        let nameLabel = UILabel()
        nameLabel.translatesAutoresizingMaskIntoConstraints = false
        nameLabel.text = viewModel.file.name
        nameLabel.font = .systemFont(ofSize: 16, weight: .medium)

        let sizeLabel = UILabel()
        sizeLabel.translatesAutoresizingMaskIntoConstraints = false
        sizeLabel.text = viewModel.file.formattedSize
        sizeLabel.font = .systemFont(ofSize: 13)
        sizeLabel.textColor = .secondaryLabel

        container.addSubview(iconView)
        container.addSubview(nameLabel)
        container.addSubview(sizeLabel)

        NSLayoutConstraint.activate([
            iconView.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 16),
            iconView.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 40),
            iconView.heightAnchor.constraint(equalToConstant: 40),

            nameLabel.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 12),
            nameLabel.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -16),
            nameLabel.topAnchor.constraint(equalTo: container.topAnchor, constant: 12),

            sizeLabel.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 12),
            sizeLabel.topAnchor.constraint(equalTo: nameLabel.bottomAnchor, constant: 4),
            sizeLabel.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -12)
        ])

        container.isAccessibilityElement = true
        container.accessibilityLabel = "\(viewModel.file.name), \(viewModel.file.formattedSize)"

        return container
    }()

    private lazy var searchTextField: UITextField = {
        let textField = UITextField()
        textField.translatesAutoresizingMaskIntoConstraints = false
        textField.placeholder = "Search by email or username"
        textField.applySsdidDriveStyle()
        textField.keyboardType = .emailAddress
        textField.autocapitalizationType = .none
        textField.addTarget(self, action: #selector(searchTextChanged), for: .editingChanged)

        let searchIcon = UIImageView(image: UIImage(systemName: "magnifyingglass"))
        searchIcon.tintColor = .secondaryLabel
        searchIcon.frame = CGRect(x: 0, y: 0, width: 40, height: 20)
        searchIcon.contentMode = .center
        textField.leftView = searchIcon
        textField.leftViewMode = .always
        textField.accessibilityLabel = "Search for a user to share with"

        return textField
    }()

    private lazy var searchResultsTableView: UITableView = {
        let table = UITableView()
        table.translatesAutoresizingMaskIntoConstraints = false
        table.register(UITableViewCell.self, forCellReuseIdentifier: "ResultCell")
        table.delegate = self
        table.dataSource = self
        table.isHidden = true
        table.layer.cornerRadius = 8
        table.layer.borderWidth = 1
        table.layer.borderColor = UIColor.systemGray4.cgColor
        return table
    }()

    private lazy var selectedUserView: UIView = {
        let container = UIView()
        container.translatesAutoresizingMaskIntoConstraints = false
        container.backgroundColor = .systemBlue.withAlphaComponent(0.1)
        container.layer.cornerRadius = 8
        container.isHidden = true
        return container
    }()

    private lazy var selectedUserLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .systemFont(ofSize: 15, weight: .medium)
        label.textColor = .systemBlue
        return label
    }()

    private lazy var clearUserButton: UIButton = {
        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.setImage(UIImage(systemName: "xmark.circle.fill"), for: .normal)
        button.tintColor = .systemBlue
        button.addTarget(self, action: #selector(clearUserTapped), for: .touchUpInside)
        return button
    }()

    private lazy var permissionLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.text = "Permission"
        label.font = .systemFont(ofSize: 15, weight: .medium)
        return label
    }()

    private lazy var permissionSegmentedControl: UISegmentedControl = {
        let items = ShareFileViewModel.SharePermission.allCases.map { $0.rawValue }
        let control = UISegmentedControl(items: items)
        control.translatesAutoresizingMaskIntoConstraints = false
        control.selectedSegmentIndex = 0
        control.addTarget(self, action: #selector(permissionChanged), for: .valueChanged)
        control.accessibilityLabel = "Permission level"
        return control
    }()

    private lazy var permissionDescriptionLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .systemFont(ofSize: 13)
        label.textColor = .secondaryLabel
        label.numberOfLines = 0
        return label
    }()

    private lazy var expirationLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.text = "Expiration (Optional)"
        label.font = .systemFont(ofSize: 15, weight: .medium)
        return label
    }()

    private lazy var expirationDatePicker: UIDatePicker = {
        let picker = UIDatePicker()
        picker.translatesAutoresizingMaskIntoConstraints = false
        picker.datePickerMode = .date
        picker.minimumDate = Date().addingTimeInterval(86400) // Tomorrow
        picker.preferredDatePickerStyle = .compact
        picker.addTarget(self, action: #selector(expirationChanged), for: .valueChanged)
        return picker
    }()

    private lazy var noExpirationButton: UIButton = {
        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.setTitle("No Expiration", for: .normal)
        button.titleLabel?.font = .systemFont(ofSize: 14)
        button.addTarget(self, action: #selector(noExpirationTapped), for: .touchUpInside)
        return button
    }()

    private lazy var shareButton: UIButton = {
        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.setTitle("Share", for: .normal)
        button.accessibilityLabel = "Share file"
        button.accessibilityHint = "Double tap to share the file with the selected user"
        button.applyPrimaryStyle()
        button.addTarget(self, action: #selector(shareTapped), for: .touchUpInside)
        button.isEnabled = false
        button.alpha = 0.5
        return button
    }()

    private lazy var activityIndicator: UIActivityIndicatorView = {
        let indicator = UIActivityIndicatorView(style: .medium)
        indicator.translatesAutoresizingMaskIntoConstraints = false
        indicator.hidesWhenStopped = true
        indicator.color = .white
        return indicator
    }()

    // MARK: - Initialization

    init(viewModel: ShareFileViewModel) {
        self.viewModel = viewModel
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Setup

    override func setupUI() {
        view.backgroundColor = .systemBackground
        title = "Share File"

        setupKeyboardDismissOnTap()
        setupNavigationBar()

        view.addSubview(scrollView)
        scrollView.addSubview(contentView)

        contentView.addSubview(fileInfoView)
        contentView.addSubview(searchTextField)
        contentView.addSubview(searchResultsTableView)
        contentView.addSubview(selectedUserView)
        contentView.addSubview(permissionLabel)
        contentView.addSubview(permissionSegmentedControl)
        contentView.addSubview(permissionDescriptionLabel)
        contentView.addSubview(expirationLabel)
        contentView.addSubview(expirationDatePicker)
        contentView.addSubview(noExpirationButton)
        contentView.addSubview(shareButton)

        selectedUserView.addSubview(selectedUserLabel)
        selectedUserView.addSubview(clearUserButton)
        shareButton.addSubview(activityIndicator)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            contentView.topAnchor.constraint(equalTo: scrollView.topAnchor),
            contentView.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor),
            contentView.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor),
            contentView.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor),
            contentView.widthAnchor.constraint(equalTo: scrollView.widthAnchor),

            fileInfoView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 24),
            fileInfoView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 24),
            fileInfoView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -24),

            searchTextField.topAnchor.constraint(equalTo: fileInfoView.bottomAnchor, constant: 24),
            searchTextField.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 24),
            searchTextField.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -24),
            searchTextField.heightAnchor.constraint(equalToConstant: 48),

            searchResultsTableView.topAnchor.constraint(equalTo: searchTextField.bottomAnchor, constant: 4),
            searchResultsTableView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 24),
            searchResultsTableView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -24),
            searchResultsTableView.heightAnchor.constraint(lessThanOrEqualToConstant: 200),

            selectedUserView.topAnchor.constraint(equalTo: searchTextField.bottomAnchor, constant: 12),
            selectedUserView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 24),
            selectedUserView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -24),

            selectedUserLabel.leadingAnchor.constraint(equalTo: selectedUserView.leadingAnchor, constant: 12),
            selectedUserLabel.centerYAnchor.constraint(equalTo: selectedUserView.centerYAnchor),

            clearUserButton.trailingAnchor.constraint(equalTo: selectedUserView.trailingAnchor, constant: -8),
            clearUserButton.centerYAnchor.constraint(equalTo: selectedUserView.centerYAnchor),
            clearUserButton.widthAnchor.constraint(equalToConstant: 32),
            clearUserButton.heightAnchor.constraint(equalToConstant: 32),
            clearUserButton.topAnchor.constraint(equalTo: selectedUserView.topAnchor, constant: 8),
            clearUserButton.bottomAnchor.constraint(equalTo: selectedUserView.bottomAnchor, constant: -8),

            permissionLabel.topAnchor.constraint(equalTo: selectedUserView.bottomAnchor, constant: 24),
            permissionLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 24),

            permissionSegmentedControl.topAnchor.constraint(equalTo: permissionLabel.bottomAnchor, constant: 12),
            permissionSegmentedControl.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 24),
            permissionSegmentedControl.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -24),

            permissionDescriptionLabel.topAnchor.constraint(equalTo: permissionSegmentedControl.bottomAnchor, constant: 8),
            permissionDescriptionLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 24),
            permissionDescriptionLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -24),

            expirationLabel.topAnchor.constraint(equalTo: permissionDescriptionLabel.bottomAnchor, constant: 24),
            expirationLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 24),

            expirationDatePicker.topAnchor.constraint(equalTo: expirationLabel.bottomAnchor, constant: 12),
            expirationDatePicker.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 24),

            noExpirationButton.centerYAnchor.constraint(equalTo: expirationDatePicker.centerYAnchor),
            noExpirationButton.leadingAnchor.constraint(equalTo: expirationDatePicker.trailingAnchor, constant: 16),

            shareButton.topAnchor.constraint(equalTo: expirationDatePicker.bottomAnchor, constant: 32),
            shareButton.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 24),
            shareButton.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -24),
            shareButton.heightAnchor.constraint(equalToConstant: 52),
            shareButton.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -32),

            activityIndicator.centerXAnchor.constraint(equalTo: shareButton.centerXAnchor),
            activityIndicator.centerYAnchor.constraint(equalTo: shareButton.centerYAnchor)
        ])

        updatePermissionDescription()
    }

    private func setupNavigationBar() {
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .cancel,
            target: self,
            action: #selector(cancelTapped)
        )
    }

    override func setupBindings() {
        viewModel.$searchResults
            .receive(on: DispatchQueue.main)
            .sink { [weak self] results in
                self?.searchResultsTableView.isHidden = results.isEmpty
                self?.searchResultsTableView.reloadData()
            }
            .store(in: &cancellables)

        viewModel.$selectedUser
            .receive(on: DispatchQueue.main)
            .sink { [weak self] user in
                if let user = user {
                    self?.selectedUserLabel.text = user.email
                    self?.selectedUserView.isHidden = false
                    self?.searchTextField.isHidden = true
                } else {
                    self?.selectedUserView.isHidden = true
                    self?.searchTextField.isHidden = false
                }
                self?.updateShareButton()
            }
            .store(in: &cancellables)

        viewModel.$isLoading
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isLoading in
                if isLoading {
                    self?.shareButton.setTitle("", for: .normal)
                    self?.activityIndicator.startAnimating()
                    self?.shareButton.isEnabled = false
                } else {
                    self?.shareButton.setTitle("Share", for: .normal)
                    self?.activityIndicator.stopAnimating()
                    self?.updateShareButton()
                }
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

    @objc private func searchTextChanged() {
        viewModel.searchQuery = searchTextField.text ?? ""
    }

    @objc private func clearUserTapped() {
        viewModel.clearSelectedUser()
    }

    @objc private func permissionChanged() {
        let permission = ShareFileViewModel.SharePermission.allCases[permissionSegmentedControl.selectedSegmentIndex]
        viewModel.setPermission(permission)
        updatePermissionDescription()
    }

    @objc private func expirationChanged() {
        viewModel.setExpirationDate(expirationDatePicker.date)
    }

    @objc private func noExpirationTapped() {
        viewModel.setExpirationDate(nil)
    }

    @objc private func shareTapped() {
        triggerHapticFeedback()
        viewModel.createShare()
    }

    @objc private func cancelTapped() {
        viewModel.cancel()
    }

    // MARK: - Helpers

    private func updatePermissionDescription() {
        let permission = ShareFileViewModel.SharePermission.allCases[permissionSegmentedControl.selectedSegmentIndex]
        permissionDescriptionLabel.text = permission.description
    }

    private func updateShareButton() {
        shareButton.isEnabled = viewModel.canShare
        shareButton.alpha = viewModel.canShare ? 1.0 : 0.5
    }
}

// MARK: - UITableViewDataSource

extension ShareFileViewController: UITableViewDataSource {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        viewModel.searchResults.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "ResultCell", for: indexPath)
        let user = viewModel.searchResults[indexPath.row]

        var content = cell.defaultContentConfiguration()
        content.text = user.email
        content.image = UIImage(systemName: "person.circle")
        cell.contentConfiguration = content

        return cell
    }
}

// MARK: - UITableViewDelegate

extension ShareFileViewController: UITableViewDelegate {
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let user = viewModel.searchResults[indexPath.row]
        viewModel.selectUser(user)
    }
}
