import UIKit

/// Coordinator for shares flow
final class SharesCoordinator: BaseCoordinator {

    // MARK: - Start

    override func start() {
        showReceivedShares()
    }

    // MARK: - Navigation

    func showReceivedShares() {
        let viewModel = ReceivedSharesViewModel(shareRepository: container.shareRepository)
        viewModel.coordinatorDelegate = self

        let sharesVC = ReceivedSharesViewController(viewModel: viewModel)
        navigationController.setViewControllers([sharesVC], animated: false)
    }

    func showCreatedShares() {
        let viewModel = CreatedSharesViewModel(shareRepository: container.shareRepository)

        let createdVC = CreatedSharesViewController(viewModel: viewModel)
        navigationController.pushViewController(createdVC, animated: true)
    }

    func showInvitations() {
        let viewModel = InvitationsViewModel(shareRepository: container.shareRepository)

        let invitationsVC = InvitationsViewController(viewModel: viewModel)
        navigationController.pushViewController(invitationsVC, animated: true)
    }

    func showShareDetail(shareId: String) {
        Task {
            do {
                let share = try await container.shareRepository.getShare(shareId: shareId)
                await MainActor.run {
                    if share.isFolder {
                        showSharedFolder(share: share)
                    } else {
                        showSharedFilePreview(share: share)
                    }
                }
            } catch {
                await MainActor.run {
                    let alert = UIAlertController(
                        title: "Share Unavailable",
                        message: "This share may have been revoked or is no longer accessible.",
                        preferredStyle: .alert
                    )
                    alert.addAction(UIAlertAction(title: "OK", style: .default))
                    navigationController.present(alert, animated: true)
                }
            }
        }
    }

    func showSharedFilePreview(share: Share) {
        let viewModel = SharedFilePreviewViewModel(
            share: share,
            fileRepository: container.fileRepository,
            cryptoManager: container.cryptoManager
        )

        let previewVC = SharedFilePreviewViewController(viewModel: viewModel)
        navigationController.pushViewController(previewVC, animated: true)
    }

    func showSharedFolder(share: Share) {
        let viewModel = SharedFolderBrowserViewModel(
            share: share,
            fileRepository: container.fileRepository
        )

        let browserVC = SharedFolderBrowserViewController(viewModel: viewModel)
        navigationController.pushViewController(browserVC, animated: true)
    }
}

// MARK: - ReceivedSharesViewModelCoordinatorDelegate

extension SharesCoordinator: ReceivedSharesViewModelCoordinatorDelegate {
    func receivedSharesDidSelectFile(fileId: String) {
        // For shared files, we need to get the share and show shared file preview
        // This would typically involve fetching the share first
        // For now, just show a placeholder
    }

    func receivedSharesDidSelectFolder(folderId: String) {
        // Similar to above, show shared folder browser
    }

    func receivedSharesDidRequestCreatedShares() {
        showCreatedShares()
    }
}
