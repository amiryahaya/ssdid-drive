import UIKit
import Combine

/// Invitations view controller
final class InvitationsViewController: BaseViewController {

    // MARK: - Properties

    private let viewModel: InvitationsViewModel
    private var dataSource: UICollectionViewDiffableDataSource<Section, Invitation>!

    enum Section {
        case main
    }

    // MARK: - UI Components

    private lazy var collectionView: UICollectionView = {
        var config = UICollectionLayoutListConfiguration(appearance: .insetGrouped)
        let layout = UICollectionViewCompositionalLayout.list(using: config)

        let collection = UICollectionView(frame: .zero, collectionViewLayout: layout)
        collection.translatesAutoresizingMaskIntoConstraints = false
        collection.backgroundColor = .systemGroupedBackground
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

        let imageView = UIImageView(image: UIImage(systemName: "envelope.open"))
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.tintColor = .systemGray3
        imageView.contentMode = .scaleAspectFit

        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.text = "No pending invitations"
        label.font = .systemFont(ofSize: 15)
        label.textColor = .secondaryLabel
        label.textAlignment = .center

        container.addSubview(imageView)
        container.addSubview(label)

        NSLayoutConstraint.activate([
            imageView.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            imageView.centerYAnchor.constraint(equalTo: container.centerYAnchor, constant: -40),
            imageView.widthAnchor.constraint(equalToConstant: 60),
            imageView.heightAnchor.constraint(equalToConstant: 60),

            label.topAnchor.constraint(equalTo: imageView.bottomAnchor, constant: 16),
            label.centerXAnchor.constraint(equalTo: container.centerXAnchor)
        ])

        return container
    }()

    // MARK: - Initialization

    init(viewModel: InvitationsViewModel) {
        self.viewModel = viewModel
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Lifecycle

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        viewModel.loadInvitations()
    }

    // MARK: - Setup

    override func setupUI() {
        view.backgroundColor = .systemGroupedBackground
        title = "Invitations"

        setupDataSource()

        view.addSubview(collectionView)
        view.addSubview(emptyStateView)

        NSLayoutConstraint.activate([
            collectionView.topAnchor.constraint(equalTo: view.topAnchor),
            collectionView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            collectionView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            emptyStateView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            emptyStateView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            emptyStateView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            emptyStateView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    private func setupDataSource() {
        let cellRegistration = UICollectionView.CellRegistration<UICollectionViewListCell, Invitation> { cell, _, invitation in
            var content = cell.defaultContentConfiguration()
            content.text = invitation.fileName
            content.secondaryText = "From: \(invitation.ownerEmail)"
            content.image = UIImage(systemName: "doc.fill")
            content.imageProperties.tintColor = .systemBlue

            cell.contentConfiguration = content

            // Add accept/decline buttons
            let acceptButton = UIButton(type: .system)
            acceptButton.setImage(UIImage(systemName: "checkmark.circle.fill"), for: .normal)
            acceptButton.tintColor = .systemGreen

            let declineButton = UIButton(type: .system)
            declineButton.setImage(UIImage(systemName: "xmark.circle.fill"), for: .normal)
            declineButton.tintColor = .systemRed

            let stack = UIStackView(arrangedSubviews: [acceptButton, declineButton])
            stack.spacing = 8

            cell.accessories = [.customView(configuration: .init(customView: stack, placement: .trailing()))]
        }

        dataSource = UICollectionViewDiffableDataSource<Section, Invitation>(collectionView: collectionView) { collectionView, indexPath, invitation in
            collectionView.dequeueConfiguredReusableCell(using: cellRegistration, for: indexPath, item: invitation)
        }
    }

    override func setupBindings() {
        viewModel.$invitations
            .receive(on: DispatchQueue.main)
            .sink { [weak self] invitations in
                self?.updateSnapshot(with: invitations)
                self?.emptyStateView.isHidden = !invitations.isEmpty || self?.viewModel.isLoading == true
            }
            .store(in: &cancellables)

        viewModel.$isLoading
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isLoading in
                if isLoading && self?.viewModel.invitations.isEmpty == true {
                    self?.showLoading()
                } else {
                    self?.hideLoading()
                }
                self?.emptyStateView.isHidden = !(self?.viewModel.isEmpty ?? false)
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
                    self?.viewModel.loadInvitations()
                }
            }
            .store(in: &cancellables)
    }

    private func updateSnapshot(with invitations: [Invitation]) {
        var snapshot = NSDiffableDataSourceSnapshot<Section, Invitation>()
        snapshot.appendSections([.main])
        snapshot.appendItems(invitations)
        dataSource.apply(snapshot, animatingDifferences: true)
    }

    // MARK: - Actions

    @objc private func handleRefresh() {
        viewModel.refreshInvitations()
    }

    private func showInvitationActions(for invitation: Invitation) {
        let alert = UIAlertController(
            title: invitation.fileName,
            message: "Shared by \(invitation.ownerEmail)",
            preferredStyle: .actionSheet
        )

        alert.addAction(UIAlertAction(title: "Accept", style: .default) { [weak self] _ in
            self?.viewModel.acceptInvitation(invitation)
        })

        alert.addAction(UIAlertAction(title: "Decline", style: .destructive) { [weak self] _ in
            self?.viewModel.declineInvitation(invitation)
        })

        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))

        if let popover = alert.popoverPresentationController {
            popover.sourceView = collectionView
            popover.sourceRect = collectionView.bounds
        }

        present(alert, animated: true)
    }
}

// MARK: - UICollectionViewDelegate

extension InvitationsViewController: UICollectionViewDelegate {
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        collectionView.deselectItem(at: indexPath, animated: true)
        triggerSelectionFeedback()

        guard let invitation = dataSource.itemIdentifier(for: indexPath) else { return }
        showInvitationActions(for: invitation)
    }
}
