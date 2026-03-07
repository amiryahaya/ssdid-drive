import UIKit
import Combine

/// Shares list view controller with tabs for received/created
final class SharesViewController: BaseViewController {

    // MARK: - Properties

    private let viewModel: SharesViewModel
    private var dataSource: UICollectionViewDiffableDataSource<Section, Share>!

    enum Section {
        case main
    }

    // MARK: - UI Components

    private lazy var segmentedControl: UISegmentedControl = {
        let items = SharesViewModel.Tab.allCases.map { $0.title }
        let control = UISegmentedControl(items: items)
        control.translatesAutoresizingMaskIntoConstraints = false
        control.selectedSegmentIndex = 0
        control.addTarget(self, action: #selector(tabChanged), for: .valueChanged)
        control.accessibilityLabel = "Share tab selector"
        return control
    }()

    private lazy var collectionView: UICollectionView = {
        let config = UICollectionLayoutListConfiguration(appearance: .plain)
        let layout = UICollectionViewCompositionalLayout.list(using: config)

        let collection = UICollectionView(frame: .zero, collectionViewLayout: layout)
        collection.translatesAutoresizingMaskIntoConstraints = false
        collection.backgroundColor = .systemBackground
        collection.delegate = self
        collection.refreshControl = refreshControl
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

        let imageView = UIImageView(image: UIImage(systemName: "square.and.arrow.up.on.square"))
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.tintColor = .systemGray3
        imageView.contentMode = .scaleAspectFit

        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .systemFont(ofSize: 15)
        label.textColor = .secondaryLabel
        label.textAlignment = .center
        label.numberOfLines = 0
        label.tag = 100 // For updating text

        container.addSubview(imageView)
        container.addSubview(label)

        NSLayoutConstraint.activate([
            imageView.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            imageView.centerYAnchor.constraint(equalTo: container.centerYAnchor, constant: -40),
            imageView.widthAnchor.constraint(equalToConstant: 60),
            imageView.heightAnchor.constraint(equalToConstant: 60),

            label.topAnchor.constraint(equalTo: imageView.bottomAnchor, constant: 16),
            label.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 32),
            label.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -32)
        ])

        return container
    }()

    // MARK: - Initialization

    init(viewModel: SharesViewModel) {
        self.viewModel = viewModel
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Lifecycle

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        viewModel.loadShares()
    }

    // MARK: - Setup

    override func setupUI() {
        view.backgroundColor = .systemBackground
        title = "Shares"

        setupDataSource()

        view.addSubview(segmentedControl)
        view.addSubview(collectionView)
        view.addSubview(emptyStateView)

        NSLayoutConstraint.activate([
            segmentedControl.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 12),
            segmentedControl.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            segmentedControl.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),

            collectionView.topAnchor.constraint(equalTo: segmentedControl.bottomAnchor, constant: 12),
            collectionView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            collectionView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            emptyStateView.topAnchor.constraint(equalTo: segmentedControl.bottomAnchor),
            emptyStateView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            emptyStateView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            emptyStateView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    private func setupDataSource() {
        let cellRegistration = UICollectionView.CellRegistration<UICollectionViewListCell, Share> { [weak self] cell, _, share in
            var content = cell.defaultContentConfiguration()
            content.text = share.resourceId
            content.secondaryText = self?.shareSubtitle(for: share)
            content.image = UIImage(systemName: share.isFolder ? "folder.fill" : "doc.fill")
            content.imageProperties.tintColor = share.isFolder ? .systemBlue : .systemGray
            cell.contentConfiguration = content

            // Show active/revoked indicator
            if !share.isActive {
                let badge = UIView()
                badge.backgroundColor = .systemRed
                badge.layer.cornerRadius = 4
                badge.widthAnchor.constraint(equalToConstant: 8).isActive = true
                badge.heightAnchor.constraint(equalToConstant: 8).isActive = true

                var accessories: [UICellAccessory] = [.customView(configuration: .init(customView: badge, placement: .trailing()))]
                accessories.append(.disclosureIndicator())
                cell.accessories = accessories
            } else {
                cell.accessories = [.disclosureIndicator()]
            }
        }

        dataSource = UICollectionViewDiffableDataSource<Section, Share>(collectionView: collectionView) { collectionView, indexPath, share in
            collectionView.dequeueConfiguredReusableCell(using: cellRegistration, for: indexPath, item: share)
        }
    }

    override func setupBindings() {
        viewModel.$selectedTab
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updateSnapshot()
                self?.updateEmptyState()
            }
            .store(in: &cancellables)

        Publishers.CombineLatest(viewModel.$receivedShares, viewModel.$createdShares)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _, _ in
                self?.updateSnapshot()
                self?.updateEmptyState()
            }
            .store(in: &cancellables)

        viewModel.$isLoading
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isLoading in
                if isLoading && self?.viewModel.currentShares.isEmpty == true {
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

        viewModel.$errorMessage
            .receive(on: DispatchQueue.main)
            .compactMap { $0 }
            .sink { [weak self] message in
                self?.showError(message) {
                    self?.viewModel.loadShares()
                }
            }
            .store(in: &cancellables)
    }

    private func updateSnapshot() {
        var snapshot = NSDiffableDataSourceSnapshot<Section, Share>()
        snapshot.appendSections([.main])
        snapshot.appendItems(viewModel.currentShares)
        dataSource.apply(snapshot, animatingDifferences: true)
    }

    private func updateEmptyState() {
        emptyStateView.isHidden = !viewModel.isEmpty
        if let label = emptyStateView.viewWithTag(100) as? UILabel {
            label.text = viewModel.emptyMessage
        }
    }

    // MARK: - Actions

    @objc private func tabChanged() {
        let tab = SharesViewModel.Tab(rawValue: segmentedControl.selectedSegmentIndex) ?? .received
        viewModel.setTab(tab)
    }

    @objc private func handleRefresh() {
        viewModel.refreshShares()
    }

    // MARK: - Helpers

    private func shareSubtitle(for share: Share) -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .medium

        let dateString = dateFormatter.string(from: share.createdAt)
        let permissionLabel = share.permission.displayName

        if viewModel.selectedTab == .received {
            return "\(permissionLabel) • \(dateString)"
        } else {
            return "Shared • \(permissionLabel) • \(dateString)"
        }
    }

    private func showShareActions(for share: Share) {
        let alert = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet)

        if viewModel.selectedTab == .created && share.isActive {
            alert.addAction(UIAlertAction(title: "Revoke Access", style: .destructive) { [weak self] _ in
                self?.confirmRevoke(share)
            })
        }

        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))

        if let popover = alert.popoverPresentationController {
            popover.sourceView = collectionView
            popover.sourceRect = collectionView.bounds
        }

        present(alert, animated: true)
    }

    private func confirmRevoke(_ share: Share) {
        let alert = UIAlertController(
            title: "Revoke Access",
            message: "Are you sure you want to revoke access to this shared resource?",
            preferredStyle: .alert
        )

        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Revoke", style: .destructive) { [weak self] _ in
            self?.viewModel.revokeShare(share)
        })

        present(alert, animated: true)
    }
}

// MARK: - UICollectionViewDelegate

extension SharesViewController: UICollectionViewDelegate {
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        collectionView.deselectItem(at: indexPath, animated: true)
        triggerSelectionFeedback()

        guard let share = dataSource.itemIdentifier(for: indexPath) else { return }
        viewModel.selectShare(share)
    }

    func collectionView(_ collectionView: UICollectionView, contextMenuConfigurationForItemAt indexPath: IndexPath, point: CGPoint) -> UIContextMenuConfiguration? {
        guard let share = dataSource.itemIdentifier(for: indexPath) else { return nil }

        return UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { [weak self] _ in
            var actions: [UIAction] = []

            if self?.viewModel.selectedTab == .created && share.isActive {
                actions.append(UIAction(title: "Revoke Access", image: UIImage(systemName: "trash"), attributes: .destructive) { _ in
                    self?.confirmRevoke(share)
                })
            }

            return UIMenu(children: actions)
        }
    }
}
