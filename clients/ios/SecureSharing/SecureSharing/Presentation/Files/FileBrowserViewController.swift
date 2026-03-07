import UIKit
import Combine

/// File browser view controller with grid/list toggle
final class FileBrowserViewController: BaseViewController {

    // MARK: - Properties

    let viewModel: FileBrowserViewModel
    private var dataSource: UICollectionViewDiffableDataSource<Section, FileItem>!

    enum Section {
        case main
    }

    // MARK: - UI Components

    private lazy var collectionView: UICollectionView = {
        let collection = UICollectionView(frame: .zero, collectionViewLayout: createLayout())
        collection.translatesAutoresizingMaskIntoConstraints = false
        collection.backgroundColor = .systemBackground
        collection.delegate = self
        collection.refreshControl = refreshControl
        collection.accessibilityIdentifier = "fileBrowserCollection"
        return collection
    }()

    private lazy var refreshControl: UIRefreshControl = {
        let control = UIRefreshControl()
        control.addTarget(self, action: #selector(handleRefresh), for: .valueChanged)
        return control
    }()

    private lazy var emptyStateView: UIView = {
        let container = UIView()
        container.translatesAutoresizingMaskIntoConstraints = false
        container.isHidden = true
        container.accessibilityIdentifier = "emptyStateView"
        container.isAccessibilityElement = true
        container.accessibilityLabel = "No files yet. Upload your first file using the add button."

        let imageView = UIImageView(image: UIImage(systemName: "folder.fill"))
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.tintColor = .systemGray3
        imageView.contentMode = .scaleAspectFit

        let titleLabel = UILabel()
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.text = "No Files Yet"
        titleLabel.font = .systemFont(ofSize: 20, weight: .semibold)
        titleLabel.textColor = .label
        titleLabel.textAlignment = .center

        let subtitleLabel = UILabel()
        subtitleLabel.translatesAutoresizingMaskIntoConstraints = false
        subtitleLabel.text = "Upload your first file using the + button"
        subtitleLabel.font = .systemFont(ofSize: 15)
        subtitleLabel.textColor = .secondaryLabel
        subtitleLabel.textAlignment = .center
        subtitleLabel.numberOfLines = 0

        container.addSubview(imageView)
        container.addSubview(titleLabel)
        container.addSubview(subtitleLabel)

        NSLayoutConstraint.activate([
            imageView.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            imageView.centerYAnchor.constraint(equalTo: container.centerYAnchor, constant: -60),
            imageView.widthAnchor.constraint(equalToConstant: 80),
            imageView.heightAnchor.constraint(equalToConstant: 80),

            titleLabel.topAnchor.constraint(equalTo: imageView.bottomAnchor, constant: 24),
            titleLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 32),
            titleLabel.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -32),

            subtitleLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 8),
            subtitleLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 32),
            subtitleLabel.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -32)
        ])

        return container
    }()

    private lazy var addButton: UIButton = {
        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.setImage(UIImage(systemName: "plus")?.withConfiguration(
            UIImage.SymbolConfiguration(pointSize: 24, weight: .medium)
        ), for: .normal)
        button.backgroundColor = .systemBlue
        button.tintColor = .white
        button.layer.cornerRadius = 28
        button.layer.shadowColor = UIColor.black.cgColor
        button.layer.shadowOffset = CGSize(width: 0, height: 4)
        button.layer.shadowRadius = 8
        button.layer.shadowOpacity = 0.2
        button.accessibilityIdentifier = "addFileButton"
        button.accessibilityLabel = "Add file or folder"
        button.accessibilityHint = "Double tap to upload a file or create a folder"
        button.addTarget(self, action: #selector(addButtonTapped), for: .touchUpInside)
        return button
    }()

    private lazy var searchController: UISearchController = {
        let controller = UISearchController(searchResultsController: nil)
        controller.searchResultsUpdater = self
        controller.obscuresBackgroundDuringPresentation = false
        controller.searchBar.placeholder = "Search files..."
        controller.searchBar.accessibilityIdentifier = "fileSearchBar"
        controller.delegate = self
        return controller
    }()

    private lazy var breadcrumbView: BreadcrumbView = {
        let view = BreadcrumbView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.delegate = self
        view.isHidden = true
        view.accessibilityIdentifier = "breadcrumbView"
        return view
    }()

    // MARK: - Initialization

    init(viewModel: FileBrowserViewModel) {
        self.viewModel = viewModel
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Lifecycle

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        viewModel.loadFiles()
    }

    // MARK: - Setup

    override func setupUI() {
        view.backgroundColor = .systemBackground
        title = viewModel.navigationTitle

        setupNavigationBar()
        setupDataSource()

        #if targetEnvironment(macCatalyst)
        configureDragAndDrop()
        #endif

        view.addSubview(breadcrumbView)
        view.addSubview(collectionView)
        view.addSubview(emptyStateView)
        view.addSubview(addButton)

        NSLayoutConstraint.activate([
            breadcrumbView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            breadcrumbView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            breadcrumbView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            breadcrumbView.heightAnchor.constraint(equalToConstant: 44),

            collectionView.topAnchor.constraint(equalTo: breadcrumbView.bottomAnchor),
            collectionView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            collectionView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            emptyStateView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            emptyStateView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            emptyStateView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            emptyStateView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            addButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
            addButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -24),
            addButton.widthAnchor.constraint(equalToConstant: 56),
            addButton.heightAnchor.constraint(equalToConstant: 56)
        ])
    }

    private func setupNavigationBar() {
        let viewModeButton = UIBarButtonItem(
            image: UIImage(systemName: viewModel.isGridView ? "list.bullet" : "square.grid.2x2"),
            style: .plain,
            target: self,
            action: #selector(toggleViewMode)
        )
        viewModeButton.accessibilityIdentifier = "viewModeButton"
        viewModeButton.accessibilityLabel = viewModel.isGridView ? "Switch to list view" : "Switch to grid view"

        let sortButton = UIBarButtonItem(
            image: UIImage(systemName: "arrow.up.arrow.down"),
            style: .plain,
            target: self,
            action: #selector(showSortOptions)
        )
        sortButton.accessibilityIdentifier = "sortButton"
        sortButton.accessibilityLabel = "Sort files"

        navigationItem.rightBarButtonItems = [sortButton, viewModeButton]
        navigationItem.searchController = searchController
        navigationItem.hidesSearchBarWhenScrolling = true
        definesPresentationContext = true
    }

    private func createLayout() -> UICollectionViewLayout {
        if viewModel.isGridView {
            return createGridLayout()
        } else {
            return createListLayout()
        }
    }

    private func createGridLayout() -> UICollectionViewCompositionalLayout {
        let itemSize = NSCollectionLayoutSize(
            widthDimension: .fractionalWidth(0.5),
            heightDimension: .estimated(160)
        )
        let item = NSCollectionLayoutItem(layoutSize: itemSize)
        item.contentInsets = NSDirectionalEdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8)

        let groupSize = NSCollectionLayoutSize(
            widthDimension: .fractionalWidth(1.0),
            heightDimension: .estimated(160)
        )
        let group = NSCollectionLayoutGroup.horizontal(layoutSize: groupSize, subitems: [item])

        let section = NSCollectionLayoutSection(group: group)
        section.contentInsets = NSDirectionalEdgeInsets(top: 8, leading: 8, bottom: 100, trailing: 8)

        return UICollectionViewCompositionalLayout(section: section)
    }

    private func createListLayout() -> UICollectionViewCompositionalLayout {
        var config = UICollectionLayoutListConfiguration(appearance: .plain)
        config.trailingSwipeActionsConfigurationProvider = { [weak self] indexPath in
            self?.trailingSwipeActions(for: indexPath)
        }

        return UICollectionViewCompositionalLayout.list(using: config)
    }

    private func trailingSwipeActions(for indexPath: IndexPath) -> UISwipeActionsConfiguration? {
        guard let file = dataSource.itemIdentifier(for: indexPath) else { return nil }

        let deleteAction = UIContextualAction(style: .destructive, title: "Delete") { [weak self] _, _, completion in
            self?.confirmDelete(file)
            completion(true)
        }
        deleteAction.image = UIImage(systemName: "trash")

        let shareAction = UIContextualAction(style: .normal, title: "Share") { [weak self] _, _, completion in
            self?.viewModel.requestShare(file)
            completion(true)
        }
        shareAction.backgroundColor = .systemBlue
        shareAction.image = UIImage(systemName: "square.and.arrow.up")

        return UISwipeActionsConfiguration(actions: [deleteAction, shareAction])
    }

    private func setupDataSource() {
        let gridCellRegistration = UICollectionView.CellRegistration<FileGridCell, FileItem> { cell, _, file in
            cell.configure(with: file)
        }

        let listCellRegistration = UICollectionView.CellRegistration<UICollectionViewListCell, FileItem> { cell, _, file in
            var content = cell.defaultContentConfiguration()
            content.text = file.name
            content.secondaryText = file.isFolder ? "Folder" : file.formattedSize
            content.image = UIImage(systemName: file.iconName)
            content.imageProperties.tintColor = file.isFolder ? .systemBlue : .systemGray
            cell.contentConfiguration = content

            cell.accessibilityTraits = [.button]
            cell.accessibilityHint = file.isFolder ? "Double tap to open folder" : "Double tap to open"
        }

        dataSource = UICollectionViewDiffableDataSource<Section, FileItem>(collectionView: collectionView) { [weak self] collectionView, indexPath, file in
            if self?.viewModel.isGridView == true {
                return collectionView.dequeueConfiguredReusableCell(using: gridCellRegistration, for: indexPath, item: file)
            } else {
                return collectionView.dequeueConfiguredReusableCell(using: listCellRegistration, for: indexPath, item: file)
            }
        }
    }

    override func setupBindings() {
        // Observe macOS menu/toolbar/keyboard shortcut actions
        NotificationCenter.default.publisher(for: .uploadFileRequested)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.viewModel.requestUpload()
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .createFolderRequested)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.showNewFolderDialog()
            }
            .store(in: &cancellables)

        viewModel.$files
            .receive(on: DispatchQueue.main)
            .sink { [weak self] files in
                self?.updateSnapshot(with: files)
                self?.emptyStateView.isHidden = !files.isEmpty || self?.viewModel.isLoading == true
            }
            .store(in: &cancellables)

        viewModel.$isLoading
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isLoading in
                if isLoading && self?.viewModel.files.isEmpty == true {
                    self?.showLoading()
                } else {
                    self?.hideLoading()
                }
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

        viewModel.$folderPath
            .receive(on: DispatchQueue.main)
            .sink { [weak self] path in
                self?.breadcrumbView.isHidden = path.isEmpty
                self?.breadcrumbView.update(with: path)
                self?.title = self?.viewModel.navigationTitle
            }
            .store(in: &cancellables)

        viewModel.$isGridView
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isGrid in
                self?.collectionView.setCollectionViewLayout(
                    isGrid ? self?.createGridLayout() ?? UICollectionViewLayout() : self?.createListLayout() ?? UICollectionViewLayout(),
                    animated: true
                )
                self?.navigationItem.rightBarButtonItems?.last?.image = UIImage(
                    systemName: isGrid ? "list.bullet" : "square.grid.2x2"
                )
                self?.navigationItem.rightBarButtonItems?.last?.accessibilityLabel = isGrid ? "Switch to list view" : "Switch to grid view"
            }
            .store(in: &cancellables)

        viewModel.$errorMessage
            .receive(on: DispatchQueue.main)
            .compactMap { $0 }
            .sink { [weak self] message in
                self?.showError(message) {
                    self?.viewModel.loadFiles()
                }
            }
            .store(in: &cancellables)

        // Search bindings
        viewModel.$searchResults
            .receive(on: DispatchQueue.main)
            .sink { [weak self] results in
                guard let self = self, self.viewModel.isSearchActive else { return }
                self.updateSnapshot(with: results)
            }
            .store(in: &cancellables)
    }

    private func updateSnapshot(with files: [FileItem]) {
        var snapshot = NSDiffableDataSourceSnapshot<Section, FileItem>()
        snapshot.appendSections([.main])
        snapshot.appendItems(files)
        dataSource.apply(snapshot, animatingDifferences: true)
    }

    // MARK: - Actions

    @objc private func handleRefresh() {
        viewModel.refreshFiles()
    }

    /// Public method to refresh the file list
    func refresh() {
        viewModel.refreshFiles()
    }

    @objc private func toggleViewMode() {
        triggerSelectionFeedback()
        viewModel.toggleViewMode()
    }

    @objc private func showSortOptions() {
        let alert = UIAlertController(title: "Sort By", message: nil, preferredStyle: .actionSheet)

        alert.addAction(UIAlertAction(title: "Name (A-Z)", style: .default) { [weak self] _ in
            self?.viewModel.setSortOption(.nameAsc)
        })
        alert.addAction(UIAlertAction(title: "Name (Z-A)", style: .default) { [weak self] _ in
            self?.viewModel.setSortOption(.nameDesc)
        })
        alert.addAction(UIAlertAction(title: "Date (Newest)", style: .default) { [weak self] _ in
            self?.viewModel.setSortOption(.dateDesc)
        })
        alert.addAction(UIAlertAction(title: "Date (Oldest)", style: .default) { [weak self] _ in
            self?.viewModel.setSortOption(.dateAsc)
        })
        alert.addAction(UIAlertAction(title: "Size (Largest)", style: .default) { [weak self] _ in
            self?.viewModel.setSortOption(.sizeDesc)
        })
        alert.addAction(UIAlertAction(title: "Size (Smallest)", style: .default) { [weak self] _ in
            self?.viewModel.setSortOption(.sizeAsc)
        })
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))

        if let popover = alert.popoverPresentationController {
            popover.barButtonItem = navigationItem.rightBarButtonItems?.first
        }

        present(alert, animated: true)
    }

    @objc private func addButtonTapped() {
        triggerHapticFeedback()

        let alert = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet)

        alert.addAction(UIAlertAction(title: "Upload File", style: .default) { [weak self] _ in
            self?.viewModel.requestUpload()
        })

        alert.addAction(UIAlertAction(title: "New Folder", style: .default) { [weak self] _ in
            self?.showNewFolderDialog()
        })

        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))

        if let popover = alert.popoverPresentationController {
            popover.sourceView = addButton
            popover.sourceRect = addButton.bounds
        }

        present(alert, animated: true)
    }

    private func showNewFolderDialog() {
        let alert = UIAlertController(title: "New Folder", message: "Enter a name for the folder", preferredStyle: .alert)

        alert.addTextField { textField in
            textField.placeholder = "Folder name"
            textField.autocapitalizationType = .words
        }

        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Create", style: .default) { [weak self] _ in
            if let name = alert.textFields?.first?.text, !name.isEmpty {
                self?.viewModel.createFolder(name: name)
            }
        })

        present(alert, animated: true)
    }

    private func confirmDelete(_ file: FileItem) {
        let alert = UIAlertController(
            title: "Delete \(file.isFolder ? "Folder" : "File")",
            message: "Are you sure you want to delete \"\(file.name)\"? This action cannot be undone.",
            preferredStyle: .alert
        )

        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Delete", style: .destructive) { [weak self] _ in
            self?.viewModel.deleteFile(file)
        })

        present(alert, animated: true)
    }
}

// MARK: - UICollectionViewDelegate

extension FileBrowserViewController: UICollectionViewDelegate {
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        collectionView.deselectItem(at: indexPath, animated: true)
        triggerSelectionFeedback()

        guard let file = dataSource.itemIdentifier(for: indexPath) else { return }
        viewModel.selectFile(file)
    }

    func collectionView(_ collectionView: UICollectionView, contextMenuConfigurationForItemAt indexPath: IndexPath, point: CGPoint) -> UIContextMenuConfiguration? {
        guard let file = dataSource.itemIdentifier(for: indexPath) else { return nil }

        return UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { [weak self] _ in
            let share = UIAction(title: "Share", image: UIImage(systemName: "square.and.arrow.up")) { _ in
                self?.viewModel.requestShare(file)
            }

            let delete = UIAction(title: "Delete", image: UIImage(systemName: "trash"), attributes: .destructive) { _ in
                self?.confirmDelete(file)
            }

            return UIMenu(children: [share, delete])
        }
    }
}

// MARK: - UISearchResultsUpdating

extension FileBrowserViewController: UISearchResultsUpdating {
    func updateSearchResults(for searchController: UISearchController) {
        let query = searchController.searchBar.text ?? ""
        viewModel.updateSearchQuery(query)
    }
}

// MARK: - UISearchControllerDelegate

extension FileBrowserViewController: UISearchControllerDelegate {
    func willPresentSearchController(_ searchController: UISearchController) {
        viewModel.activateSearch()
    }

    func willDismissSearchController(_ searchController: UISearchController) {
        viewModel.deactivateSearch()
        // Restore file list when search is dismissed
        updateSnapshot(with: viewModel.files)
    }
}

// MARK: - BreadcrumbViewDelegate

extension FileBrowserViewController: BreadcrumbViewDelegate {
    func breadcrumbDidSelectHome() {
        while !viewModel.folderPath.isEmpty {
            viewModel.navigateUp()
        }
    }

    func breadcrumbDidSelectItem(at index: Int) {
        viewModel.navigateToPathIndex(index)
    }
}

// MARK: - File Grid Cell

final class FileGridCell: UICollectionViewCell {

    private lazy var containerView: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.backgroundColor = .systemGray6
        view.layer.cornerRadius = 12
        return view
    }()

    private lazy var iconImageView: UIImageView = {
        let imageView = UIImageView()
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.contentMode = .scaleAspectFit
        imageView.tintColor = .systemBlue
        return imageView
    }()

    private lazy var nameLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .systemFont(ofSize: 14, weight: .medium)
        label.textAlignment = .center
        label.numberOfLines = 2
        return label
    }()

    private lazy var sizeLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .systemFont(ofSize: 12)
        label.textColor = .secondaryLabel
        label.textAlignment = .center
        return label
    }()

    private lazy var thumbnailImageView: UIImageView = {
        let imageView = UIImageView()
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        imageView.layer.cornerRadius = 6
        imageView.isHidden = true
        return imageView
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
        containerView.addSubview(iconImageView)
        containerView.addSubview(thumbnailImageView)
        containerView.addSubview(nameLabel)
        containerView.addSubview(sizeLabel)

        NSLayoutConstraint.activate([
            containerView.topAnchor.constraint(equalTo: contentView.topAnchor),
            containerView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            containerView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            containerView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),

            iconImageView.topAnchor.constraint(equalTo: containerView.topAnchor, constant: 20),
            iconImageView.centerXAnchor.constraint(equalTo: containerView.centerXAnchor),
            iconImageView.widthAnchor.constraint(equalToConstant: 48),
            iconImageView.heightAnchor.constraint(equalToConstant: 48),

            thumbnailImageView.topAnchor.constraint(equalTo: iconImageView.topAnchor),
            thumbnailImageView.centerXAnchor.constraint(equalTo: iconImageView.centerXAnchor),
            thumbnailImageView.widthAnchor.constraint(equalToConstant: 48),
            thumbnailImageView.heightAnchor.constraint(equalToConstant: 48),

            nameLabel.topAnchor.constraint(equalTo: iconImageView.bottomAnchor, constant: 12),
            nameLabel.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 8),
            nameLabel.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -8),

            sizeLabel.topAnchor.constraint(equalTo: nameLabel.bottomAnchor, constant: 4),
            sizeLabel.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 8),
            sizeLabel.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -8),
            sizeLabel.bottomAnchor.constraint(lessThanOrEqualTo: containerView.bottomAnchor, constant: -12)
        ])
    }

    func configure(with file: FileItem) {
        nameLabel.text = file.name
        sizeLabel.text = file.isFolder ? "Folder" : file.formattedSize
        iconImageView.image = UIImage(systemName: file.iconName)
        iconImageView.tintColor = file.isFolder ? .systemBlue : .systemGray

        // Accessibility
        isAccessibilityElement = true
        accessibilityTraits = [.button]
        accessibilityHint = file.isFolder ? "Double tap to open folder" : "Double tap to open"
        if file.isFolder {
            accessibilityLabel = file.name
        } else {
            accessibilityLabel = "\(file.name), \(file.fileExtension.isEmpty ? "file" : file.fileExtension), \(file.formattedSize)"
        }

        // Thumbnail
        if let cached = ThumbnailCache.shared.thumbnail(for: file.id) {
            thumbnailImageView.image = cached
            thumbnailImageView.isHidden = false
            iconImageView.isHidden = true
        } else {
            thumbnailImageView.isHidden = true
            iconImageView.isHidden = false
        }
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        thumbnailImageView.image = nil
        thumbnailImageView.isHidden = true
        iconImageView.isHidden = false
    }
}

// MARK: - Breadcrumb View

protocol BreadcrumbViewDelegate: AnyObject {
    func breadcrumbDidSelectHome()
    func breadcrumbDidSelectItem(at index: Int)
}

final class BreadcrumbView: UIView {

    weak var delegate: BreadcrumbViewDelegate?

    private lazy var scrollView: UIScrollView = {
        let scroll = UIScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.showsHorizontalScrollIndicator = false
        return scroll
    }()

    private lazy var stackView: UIStackView = {
        let stack = UIStackView()
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .horizontal
        stack.spacing = 4
        stack.alignment = .center
        return stack
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupUI()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupUI() {
        backgroundColor = .systemGray6

        addSubview(scrollView)
        scrollView.addSubview(stackView)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),

            stackView.topAnchor.constraint(equalTo: scrollView.topAnchor),
            stackView.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor, constant: 16),
            stackView.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor, constant: -16),
            stackView.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor),
            stackView.heightAnchor.constraint(equalTo: scrollView.heightAnchor)
        ])
    }

    func update(with path: [FileItem]) {
        stackView.arrangedSubviews.forEach { $0.removeFromSuperview() }

        // Home button
        let homeButton = UIButton(type: .system)
        homeButton.setImage(UIImage(systemName: "house.fill"), for: .normal)
        homeButton.accessibilityLabel = "Navigate to root folder"
        homeButton.addTarget(self, action: #selector(homeTapped), for: .touchUpInside)
        stackView.addArrangedSubview(homeButton)

        for (index, folder) in path.enumerated() {
            let chevron = UIImageView(image: UIImage(systemName: "chevron.right"))
            chevron.tintColor = .secondaryLabel
            chevron.contentMode = .scaleAspectFit
            chevron.widthAnchor.constraint(equalToConstant: 12).isActive = true
            stackView.addArrangedSubview(chevron)

            let button = UIButton(type: .system)
            button.setTitle(folder.name, for: .normal)
            button.titleLabel?.font = .systemFont(ofSize: 14, weight: .medium)
            button.tag = index
            button.accessibilityLabel = "Navigate to \(folder.name)"
            button.addTarget(self, action: #selector(itemTapped(_:)), for: .touchUpInside)
            stackView.addArrangedSubview(button)
        }

        // Scroll to end
        DispatchQueue.main.async {
            let rightOffset = CGPoint(x: max(0, self.scrollView.contentSize.width - self.scrollView.bounds.width), y: 0)
            self.scrollView.setContentOffset(rightOffset, animated: true)
        }
    }

    @objc private func homeTapped() {
        delegate?.breadcrumbDidSelectHome()
    }

    @objc private func itemTapped(_ sender: UIButton) {
        delegate?.breadcrumbDidSelectItem(at: sender.tag)
    }
}
