import UIKit
import Combine

/// Trustee selection view controller
final class TrusteeSelectionViewController: BaseViewController {

    // MARK: - Properties

    private let viewModel: TrusteeSelectionViewModel

    // MARK: - UI Components

    private lazy var searchBar: UISearchBar = {
        let searchBar = UISearchBar()
        searchBar.translatesAutoresizingMaskIntoConstraints = false
        searchBar.placeholder = "Search by email"
        searchBar.searchBarStyle = .minimal
        searchBar.delegate = self
        return searchBar
    }()

    private lazy var selectedTrusteesLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .systemFont(ofSize: 15, weight: .medium)
        label.textColor = .secondaryLabel
        return label
    }()

    private lazy var selectedCollectionView: UICollectionView = {
        let layout = UICollectionViewFlowLayout()
        layout.scrollDirection = .horizontal
        layout.minimumInteritemSpacing = 8
        layout.estimatedItemSize = UICollectionViewFlowLayout.automaticSize

        let collectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        collectionView.backgroundColor = .clear
        collectionView.showsHorizontalScrollIndicator = false
        collectionView.delegate = self
        collectionView.dataSource = self
        collectionView.register(TrusteeChipCell.self, forCellWithReuseIdentifier: TrusteeChipCell.reuseIdentifier)
        return collectionView
    }()

    private lazy var tableView: UITableView = {
        let tableView = UITableView(frame: .zero, style: .plain)
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.delegate = self
        tableView.dataSource = self
        tableView.register(UserSearchResultCell.self, forCellReuseIdentifier: UserSearchResultCell.reuseIdentifier)
        tableView.separatorInset = UIEdgeInsets(top: 0, left: 72, bottom: 0, right: 0)
        return tableView
    }()

    private lazy var emptyStateLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.text = "Search for users by email to add as trustees"
        label.font = .systemFont(ofSize: 15)
        label.textColor = .tertiaryLabel
        label.textAlignment = .center
        label.numberOfLines = 0
        return label
    }()

    private lazy var completeButton: UIButton = {
        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.setTitle("Complete Setup", for: .normal)
        button.applyPrimaryStyle()
        button.addTarget(self, action: #selector(completeTapped), for: .touchUpInside)
        return button
    }()

    private lazy var loadingIndicator: UIActivityIndicatorView = {
        let indicator = UIActivityIndicatorView(style: .medium)
        indicator.translatesAutoresizingMaskIntoConstraints = false
        indicator.hidesWhenStopped = true
        return indicator
    }()

    // MARK: - Initialization

    init(viewModel: TrusteeSelectionViewModel) {
        self.viewModel = viewModel
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Setup

    override func setupUI() {
        view.backgroundColor = .systemBackground
        title = "Select Trustees"

        view.addSubview(searchBar)
        view.addSubview(selectedTrusteesLabel)
        view.addSubview(selectedCollectionView)
        view.addSubview(tableView)
        view.addSubview(emptyStateLabel)
        view.addSubview(completeButton)
        view.addSubview(loadingIndicator)

        NSLayoutConstraint.activate([
            searchBar.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            searchBar.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 8),
            searchBar.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -8),

            selectedTrusteesLabel.topAnchor.constraint(equalTo: searchBar.bottomAnchor, constant: 16),
            selectedTrusteesLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            selectedTrusteesLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),

            selectedCollectionView.topAnchor.constraint(equalTo: selectedTrusteesLabel.bottomAnchor, constant: 8),
            selectedCollectionView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            selectedCollectionView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            selectedCollectionView.heightAnchor.constraint(equalToConstant: 44),

            tableView.topAnchor.constraint(equalTo: selectedCollectionView.bottomAnchor, constant: 16),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: completeButton.topAnchor, constant: -16),

            emptyStateLabel.centerXAnchor.constraint(equalTo: tableView.centerXAnchor),
            emptyStateLabel.centerYAnchor.constraint(equalTo: tableView.centerYAnchor),
            emptyStateLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 32),
            emptyStateLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -32),

            loadingIndicator.centerXAnchor.constraint(equalTo: tableView.centerXAnchor),
            loadingIndicator.centerYAnchor.constraint(equalTo: tableView.centerYAnchor),

            completeButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            completeButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
            completeButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -16),
            completeButton.heightAnchor.constraint(equalToConstant: 52)
        ])
    }

    override func setupBindings() {
        viewModel.$selectedTrustees
            .receive(on: DispatchQueue.main)
            .sink { [weak self] trustees in
                self?.selectedTrusteesLabel.text = self?.viewModel.selectionStatus
                self?.selectedCollectionView.reloadData()
                self?.updateCompleteButton()
            }
            .store(in: &cancellables)

        viewModel.$searchResults
            .receive(on: DispatchQueue.main)
            .sink { [weak self] results in
                self?.tableView.reloadData()
                self?.updateEmptyState()
            }
            .store(in: &cancellables)

        viewModel.$isSearching
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isSearching in
                if isSearching {
                    self?.loadingIndicator.startAnimating()
                } else {
                    self?.loadingIndicator.stopAnimating()
                }
                self?.updateEmptyState()
            }
            .store(in: &cancellables)

        viewModel.$isLoading
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isLoading in
                self?.completeButton.isEnabled = !isLoading
                self?.completeButton.setTitle(isLoading ? "Setting up..." : "Complete Setup", for: .normal)
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
        let hasResults = !viewModel.searchResults.isEmpty
        let isSearching = viewModel.isSearching
        let hasQuery = !viewModel.searchQuery.isEmpty

        emptyStateLabel.isHidden = hasResults || isSearching

        if hasQuery && !hasResults && !isSearching {
            emptyStateLabel.text = "No users found"
        } else {
            emptyStateLabel.text = "Search for users by email to add as trustees"
        }
    }

    private func updateCompleteButton() {
        completeButton.isEnabled = viewModel.canComplete
        completeButton.alpha = viewModel.canComplete ? 1.0 : 0.5
    }

    // MARK: - Actions

    @objc private func completeTapped() {
        triggerHapticFeedback()
        viewModel.completeSelection()
    }
}

// MARK: - UISearchBarDelegate

extension TrusteeSelectionViewController: UISearchBarDelegate {
    func searchBar(_ searchBar: UISearchBar, textDidChange searchText: String) {
        viewModel.searchQuery = searchText
    }

    func searchBarSearchButtonClicked(_ searchBar: UISearchBar) {
        searchBar.resignFirstResponder()
    }
}

// MARK: - UITableViewDataSource & Delegate

extension TrusteeSelectionViewController: UITableViewDataSource, UITableViewDelegate {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return viewModel.searchResults.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: UserSearchResultCell.reuseIdentifier, for: indexPath) as! UserSearchResultCell
        let trustee = viewModel.searchResults[indexPath.row]
        let isSelected = viewModel.selectedTrustees.contains { $0.id == trustee.id }
        cell.configure(with: trustee, isSelected: isSelected)
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let trustee = viewModel.searchResults[indexPath.row]
        viewModel.selectTrustee(trustee)
    }

    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        return 64
    }
}

// MARK: - UICollectionViewDataSource & Delegate

extension TrusteeSelectionViewController: UICollectionViewDataSource, UICollectionViewDelegate {
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        return viewModel.selectedTrustees.count
    }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: TrusteeChipCell.reuseIdentifier, for: indexPath) as! TrusteeChipCell
        let trustee = viewModel.selectedTrustees[indexPath.item]
        cell.configure(with: trustee) { [weak self] in
            self?.viewModel.removeTrustee(trustee)
        }
        return cell
    }
}

// MARK: - Trustee Chip Cell

final class TrusteeChipCell: UICollectionViewCell {
    static let reuseIdentifier = "TrusteeChipCell"

    private var onRemove: (() -> Void)?

    private lazy var containerView: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.backgroundColor = .systemBlue.withAlphaComponent(0.1)
        view.layer.cornerRadius = 16
        return view
    }()

    private lazy var nameLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .systemFont(ofSize: 14, weight: .medium)
        label.textColor = .systemBlue
        return label
    }()

    private lazy var removeButton: UIButton = {
        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.setImage(UIImage(systemName: "xmark.circle.fill"), for: .normal)
        button.tintColor = .systemBlue
        button.addTarget(self, action: #selector(removeTapped), for: .touchUpInside)
        return button
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupUI()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupUI() {
        contentView.addSubview(containerView)
        containerView.addSubview(nameLabel)
        containerView.addSubview(removeButton)

        NSLayoutConstraint.activate([
            containerView.topAnchor.constraint(equalTo: contentView.topAnchor),
            containerView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            containerView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            containerView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),

            nameLabel.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 12),
            nameLabel.centerYAnchor.constraint(equalTo: containerView.centerYAnchor),

            removeButton.leadingAnchor.constraint(equalTo: nameLabel.trailingAnchor, constant: 4),
            removeButton.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -8),
            removeButton.centerYAnchor.constraint(equalTo: containerView.centerYAnchor),
            removeButton.widthAnchor.constraint(equalToConstant: 20),
            removeButton.heightAnchor.constraint(equalToConstant: 20)
        ])
    }

    func configure(with trustee: Trustee, onRemove: @escaping () -> Void) {
        nameLabel.text = trustee.displayName ?? trustee.email
        self.onRemove = onRemove

        // Accessibility
        isAccessibilityElement = true
        accessibilityLabel = "Selected trustee: \(trustee.displayName ?? trustee.email)"
        accessibilityHint = "Double tap to remove"
        accessibilityTraits = [.button]
    }

    @objc private func removeTapped() {
        onRemove?()
    }
}

// MARK: - User Search Result Cell

final class UserSearchResultCell: UITableViewCell {
    static let reuseIdentifier = "UserSearchResultCell"

    private lazy var avatarView: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.backgroundColor = .systemBlue.withAlphaComponent(0.1)
        view.layer.cornerRadius = 22
        return view
    }()

    private lazy var initialsLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .systemFont(ofSize: 16, weight: .semibold)
        label.textColor = .systemBlue
        label.textAlignment = .center
        return label
    }()

    private lazy var nameLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .systemFont(ofSize: 16, weight: .medium)
        return label
    }()

    private lazy var emailLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .systemFont(ofSize: 14)
        label.textColor = .secondaryLabel
        return label
    }()

    private lazy var checkmarkImageView: UIImageView = {
        let imageView = UIImageView()
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.image = UIImage(systemName: "checkmark.circle.fill")
        imageView.tintColor = .systemGreen
        imageView.isHidden = true
        return imageView
    }()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setupUI()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupUI() {
        contentView.addSubview(avatarView)
        avatarView.addSubview(initialsLabel)
        contentView.addSubview(nameLabel)
        contentView.addSubview(emailLabel)
        contentView.addSubview(checkmarkImageView)

        NSLayoutConstraint.activate([
            avatarView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            avatarView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            avatarView.widthAnchor.constraint(equalToConstant: 44),
            avatarView.heightAnchor.constraint(equalToConstant: 44),

            initialsLabel.centerXAnchor.constraint(equalTo: avatarView.centerXAnchor),
            initialsLabel.centerYAnchor.constraint(equalTo: avatarView.centerYAnchor),

            nameLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 12),
            nameLabel.leadingAnchor.constraint(equalTo: avatarView.trailingAnchor, constant: 12),
            nameLabel.trailingAnchor.constraint(equalTo: checkmarkImageView.leadingAnchor, constant: -8),

            emailLabel.topAnchor.constraint(equalTo: nameLabel.bottomAnchor, constant: 2),
            emailLabel.leadingAnchor.constraint(equalTo: nameLabel.leadingAnchor),
            emailLabel.trailingAnchor.constraint(equalTo: nameLabel.trailingAnchor),

            checkmarkImageView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            checkmarkImageView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            checkmarkImageView.widthAnchor.constraint(equalToConstant: 24),
            checkmarkImageView.heightAnchor.constraint(equalToConstant: 24)
        ])
    }

    func configure(with trustee: Trustee, isSelected: Bool) {
        let name = trustee.displayName ?? trustee.email
        nameLabel.text = name
        emailLabel.text = trustee.email
        checkmarkImageView.isHidden = !isSelected

        // Generate initials
        let words = name.split(separator: " ")
        if words.count >= 2 {
            initialsLabel.text = "\(words[0].prefix(1))\(words[1].prefix(1))".uppercased()
        } else {
            initialsLabel.text = String(name.prefix(2)).uppercased()
        }
    }
}
