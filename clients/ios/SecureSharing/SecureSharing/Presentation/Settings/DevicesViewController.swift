import UIKit
import Combine

/// Devices view controller
final class DevicesViewController: BaseViewController {

    // MARK: - Properties

    private let viewModel: DevicesViewModel
    private var dataSource: UICollectionViewDiffableDataSource<Section, Device>!

    enum Section {
        case main
    }

    // MARK: - UI Components

    private lazy var collectionView: UICollectionView = {
        var config = UICollectionLayoutListConfiguration(appearance: .insetGrouped)
        config.trailingSwipeActionsConfigurationProvider = { [weak self] indexPath in
            self?.trailingSwipeActions(for: indexPath)
        }

        let layout = UICollectionViewCompositionalLayout.list(using: config)

        let collection = UICollectionView(frame: .zero, collectionViewLayout: layout)
        collection.translatesAutoresizingMaskIntoConstraints = false
        collection.backgroundColor = .systemGroupedBackground
        collection.refreshControl = refreshControl
        return collection
    }()

    private lazy var refreshControl: UIRefreshControl = {
        let control = UIRefreshControl()
        control.addTarget(self, action: #selector(handleRefresh), for: .valueChanged)
        return control
    }()

    // MARK: - Initialization

    init(viewModel: DevicesViewModel) {
        self.viewModel = viewModel
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Lifecycle

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        viewModel.loadDevices()
    }

    // MARK: - Setup

    override func setupUI() {
        view.backgroundColor = .systemGroupedBackground
        title = "Devices"

        setupDataSource()

        view.addSubview(collectionView)

        NSLayoutConstraint.activate([
            collectionView.topAnchor.constraint(equalTo: view.topAnchor),
            collectionView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            collectionView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    private func setupDataSource() {
        let cellRegistration = UICollectionView.CellRegistration<UICollectionViewListCell, Device> { [weak self] cell, _, device in
            var content = cell.defaultContentConfiguration()
            content.text = device.name
            content.secondaryText = self?.deviceSubtitle(for: device)

            let isCurrent = device.isCurrent(deviceId: self?.viewModel.currentDeviceId)
            let iconName = isCurrent ? "iphone.circle.fill" : "iphone"
            content.image = UIImage(systemName: iconName)
            content.imageProperties.tintColor = isCurrent ? .systemGreen : .systemGray

            cell.contentConfiguration = content

            if isCurrent {
                let badge = UILabel()
                badge.text = "Current"
                badge.font = .systemFont(ofSize: 12, weight: .medium)
                badge.textColor = .systemGreen
                badge.sizeToFit()
                cell.accessories = [.customView(configuration: .init(customView: badge, placement: .trailing()))]
            } else {
                cell.accessories = []
            }
        }

        dataSource = UICollectionViewDiffableDataSource<Section, Device>(collectionView: collectionView) { collectionView, indexPath, device in
            collectionView.dequeueConfiguredReusableCell(using: cellRegistration, for: indexPath, item: device)
        }
    }

    private func trailingSwipeActions(for indexPath: IndexPath) -> UISwipeActionsConfiguration? {
        guard let device = dataSource.itemIdentifier(for: indexPath),
              !device.isCurrent(deviceId: viewModel.currentDeviceId) else { return nil }

        let revokeAction = UIContextualAction(style: .destructive, title: "Revoke") { [weak self] _, _, completion in
            self?.confirmRevoke(device)
            completion(true)
        }
        revokeAction.image = UIImage(systemName: "xmark.circle")

        return UISwipeActionsConfiguration(actions: [revokeAction])
    }

    override func setupBindings() {
        viewModel.$devices
            .receive(on: DispatchQueue.main)
            .sink { [weak self] devices in
                self?.updateSnapshot(with: devices)
            }
            .store(in: &cancellables)

        viewModel.$isLoading
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isLoading in
                if isLoading && self?.viewModel.devices.isEmpty == true {
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
                    self?.viewModel.loadDevices()
                }
            }
            .store(in: &cancellables)
    }

    private func updateSnapshot(with devices: [Device]) {
        var snapshot = NSDiffableDataSourceSnapshot<Section, Device>()
        snapshot.appendSections([.main])
        snapshot.appendItems(devices)
        dataSource.apply(snapshot, animatingDifferences: true)
    }

    // MARK: - Actions

    @objc private func handleRefresh() {
        viewModel.refreshDevices()
    }

    private func confirmRevoke(_ device: Device) {
        let alert = UIAlertController(
            title: "Revoke Device",
            message: "Are you sure you want to revoke access for \"\(device.name)\"? This device will be logged out immediately.",
            preferredStyle: .alert
        )

        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Revoke", style: .destructive) { [weak self] _ in
            self?.viewModel.revokeDevice(device)
        })

        present(alert, animated: true)
    }

    // MARK: - Helpers

    private func deviceSubtitle(for device: Device) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short

        if let lastActive = device.lastActiveAt {
            return "Last active: \(formatter.string(from: lastActive))"
        } else {
            return "Never active"
        }
    }
}
