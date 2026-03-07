import UIKit
import PhotosUI

/// Delegate for files coordinator events
protocol FilesCoordinatorDelegate: AnyObject {
    func filesCoordinatorDidRequestShare(fileId: String)
}

/// Delegate for ShareFileViewController
protocol ShareFileViewControllerDelegate: AnyObject {
    func shareFileViewControllerDidComplete()
    func shareFileViewControllerDidCancel()
}

/// Coordinator for files flow
final class FilesCoordinator: BaseCoordinator {

    // MARK: - Properties

    weak var delegate: FilesCoordinatorDelegate?

    // MARK: - Start

    override func start() {
        showFileBrowser(folder: nil)
    }

    // MARK: - Navigation

    func showFileBrowser(folder: FileItem?) {
        let viewModel = FileBrowserViewModel(
            fileRepository: container.fileRepository,
            folder: folder
        )
        viewModel.coordinatorDelegate = self

        let browserVC = FileBrowserViewController(viewModel: viewModel)

        if folder == nil {
            // Root folder - set as root view controller
            navigationController.setViewControllers([browserVC], animated: false)
        } else {
            // Subfolder - push onto stack
            navigationController.pushViewController(browserVC, animated: true)
        }
    }

    func showFolder(_ folder: FileItem) {
        showFileBrowser(folder: folder)
    }

    // ID-based methods for deep linking
    func showFilePreview(fileId: String) {
        Task {
            do {
                let file = try await container.fileRepository.getFile(fileId: fileId)
                await MainActor.run {
                    self.showFilePreview(file: file)
                }
            } catch {
                // Handle error - file not found
            }
        }
    }

    func showFolder(folderId: String) {
        Task {
            do {
                let folder = try await container.fileRepository.getFolder(folderId: folderId)
                // Create a FileItem from the folder for navigation
                let folderItem = FileItem(
                    id: folder.id,
                    name: folder.name,
                    mimeType: "folder",
                    size: 0,
                    folderId: folder.parentId,
                    ownerId: folder.ownerId,
                    encryptedKey: nil,
                    createdAt: folder.createdAt,
                    updatedAt: folder.updatedAt,
                    isFolder: true
                )
                await MainActor.run {
                    self.showFolder(folderItem)
                }
            } catch {
                // Handle error - folder not found
            }
        }
    }

    func showFilePreview(file: FileItem) {
        let viewModel = FilePreviewViewModel(
            file: file,
            fileRepository: container.fileRepository,
            cryptoManager: container.cryptoManager
        )
        viewModel.coordinatorDelegate = self

        let previewVC = FilePreviewViewController(viewModel: viewModel)
        navigationController.pushViewController(previewVC, animated: true)
    }

    func showShareFile(_ file: FileItem) {
        let viewModel = ShareFileViewModel(
            file: file,
            shareRepository: container.shareRepository,
            cryptoManager: container.cryptoManager
        )
        viewModel.coordinatorDelegate = self

        let shareVC = ShareFileViewController(viewModel: viewModel)

        let nav = UINavigationController(rootViewController: shareVC)
        navigationController.present(nav, animated: true)
    }

    func showCreateFolder(parentId: String?) {
        let alert = UIAlertController(
            title: "Create Folder",
            message: "Enter a name for the new folder",
            preferredStyle: .alert
        )

        alert.addTextField { textField in
            textField.placeholder = "Folder name"
        }

        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Create", style: .default) { [weak self] _ in
            if let name = alert.textFields?.first?.text, !name.isEmpty {
                self?.createFolder(name: name, parentId: parentId)
            }
        })

        navigationController.present(alert, animated: true)
    }

    func showUploadPicker(inFolder folderId: String?) {
        // TODO: Implement document picker for file upload
        let alert = UIAlertController(
            title: "Upload",
            message: "Select a file to upload",
            preferredStyle: .actionSheet
        )

        alert.addAction(UIAlertAction(title: "Photo Library", style: .default) { [weak self] _ in
            self?.showPhotoPicker(inFolder: folderId)
        })

        alert.addAction(UIAlertAction(title: "Files", style: .default) { [weak self] _ in
            self?.showDocumentPicker(inFolder: folderId)
        })

        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))

        navigationController.present(alert, animated: true)
    }

    // MARK: - Batch Upload (from Share Extension)

    func showBatchUpload(manifest: ImportManifest) {
        guard let viewModel = BatchUploadViewModel(
            fileRepository: container.fileRepository,
            cryptoManager: container.cryptoManager,
            manifest: manifest
        ) else {
            // Empty manifest - cleanup and return
            DeepLinkParser.cleanupImportFiles()
            return
        }
        viewModel.coordinatorDelegate = self

        let uploadVC = BatchUploadViewController(viewModel: viewModel)
        let nav = UINavigationController(rootViewController: uploadVC)
        nav.modalPresentationStyle = .fullScreen

        navigationController.present(nav, animated: true)
    }

    private var pendingUploadFolderId: String?
    private var pendingTempURLs: [URL] = []

    private func showPhotoPicker(inFolder folderId: String?) {
        guard navigationController.presentedViewController == nil else { return }
        pendingUploadFolderId = folderId

        var config = PHPickerConfiguration()
        config.selectionLimit = 10
        config.filter = .any(of: [.images, .videos])

        let picker = PHPickerViewController(configuration: config)
        picker.delegate = self
        navigationController.present(picker, animated: true)
    }

    private func showDocumentPicker(inFolder folderId: String?) {
        guard navigationController.presentedViewController == nil else { return }
        pendingUploadFolderId = folderId

        let viewModel = FileUploadViewModel(
            fileRepository: container.fileRepository,
            cryptoManager: container.cryptoManager,
            parentFolderId: folderId
        )
        viewModel.coordinatorDelegate = self

        let uploadVC = FileUploadViewController(viewModel: viewModel)
        let nav = UINavigationController(rootViewController: uploadVC)
        navigationController.present(nav, animated: true)
    }

    private func createFolder(name: String, parentId: String?) {
        Task {
            do {
                _ = try await container.fileRepository.createFolder(name: name, parentId: parentId)
                // Refresh current view
                await MainActor.run {
                    if let browserVC = navigationController.topViewController as? FileBrowserViewController {
                        browserVC.refresh()
                    }
                }
            } catch {
                // Handle error
            }
        }
    }
}

// MARK: - FileBrowserViewModelCoordinatorDelegate

extension FilesCoordinator: FileBrowserViewModelCoordinatorDelegate {
    func fileBrowserDidSelectFile(_ file: FileItem) {
        if file.isFolder {
            showFolder(file)
        } else {
            showFilePreview(file: file)
        }
    }

    func fileBrowserDidRequestUpload(inFolder folderId: String?) {
        showUploadPicker(inFolder: folderId)
    }

    func fileBrowserDidRequestNewFolder(inFolder folderId: String?) {
        showCreateFolder(parentId: folderId)
    }

    func fileBrowserDidRequestShare(_ file: FileItem) {
        showShareFile(file)
    }

    func fileBrowserDidRequestBatchUpload(manifest: ImportManifest) {
        showBatchUpload(manifest: manifest)
    }
}

// MARK: - FilePreviewViewModelCoordinatorDelegate

extension FilesCoordinator: FilePreviewViewModelCoordinatorDelegate {
    func filePreviewDidRequestShare(_ file: FileItem) {
        showShareFile(file)
    }

    func filePreviewDidRequestDelete(_ file: FileItem) {
        // Pop back after deletion is handled by view model
        navigationController.popViewController(animated: true)
    }
}

// MARK: - ShareFileViewModelCoordinatorDelegate

extension FilesCoordinator: ShareFileViewModelCoordinatorDelegate {
    func shareFileDidComplete() {
        navigationController.dismiss(animated: true)
    }

    func shareFileDidCancel() {
        navigationController.dismiss(animated: true)
    }
}

// MARK: - FileUploadViewModelCoordinatorDelegate

extension FilesCoordinator: FileUploadViewModelCoordinatorDelegate {
    func fileUploadDidComplete(_ file: FileItem) {
        cleanupTempFiles()
        navigationController.dismiss(animated: true) { [weak self] in
            if let browserVC = self?.navigationController.topViewController as? FileBrowserViewController {
                browserVC.refresh()
            }
        }
    }

    func fileUploadDidCancel() {
        cleanupTempFiles()
        navigationController.dismiss(animated: true)
    }
}

// MARK: - PHPickerViewControllerDelegate

extension FilesCoordinator: PHPickerViewControllerDelegate {
    func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
        picker.dismiss(animated: true)

        guard !results.isEmpty else { return }

        let folderId = pendingUploadFolderId
        pendingUploadFolderId = nil

        // For a single photo, use the single-file upload flow
        if results.count == 1, let provider = results.first?.itemProvider {
            provider.loadFileRepresentation(forTypeIdentifier: "public.item") { [weak self] url, _ in
                guard let self, let url else { return }

                // Copy to temp location with UUID prefix to avoid collisions
                let tempDir = FileManager.default.temporaryDirectory
                let tempURL = tempDir.appendingPathComponent("\(UUID().uuidString)_\(url.lastPathComponent)")
                try? FileManager.default.copyItem(at: url, to: tempURL)

                DispatchQueue.main.async {
                    self.pendingTempURLs.append(tempURL)
                    let viewModel = FileUploadViewModel(
                        fileRepository: self.container.fileRepository,
                        cryptoManager: self.container.cryptoManager,
                        parentFolderId: folderId
                    )
                    viewModel.coordinatorDelegate = self
                    viewModel.selectFile(tempURL)

                    let uploadVC = FileUploadViewController(viewModel: viewModel)
                    let nav = UINavigationController(rootViewController: uploadVC)
                    self.navigationController.present(nav, animated: true)
                }
            }
            return
        }

        // Multiple photos — collect files, then use batch upload
        // Use a serial queue to synchronize concurrent access to importFiles
        let syncQueue = DispatchQueue(label: "my.ssdid.drive.photoPicker")
        var importFiles: [ImportManifest.ImportFileInfo] = []
        let group = DispatchGroup()

        for result in results {
            group.enter()
            result.itemProvider.loadFileRepresentation(forTypeIdentifier: "public.item") { url, _ in
                defer { group.leave() }
                guard let url else { return }

                // UUID prefix prevents name collisions between selected photos
                let tempDir = FileManager.default.temporaryDirectory
                let tempURL = tempDir.appendingPathComponent("\(UUID().uuidString)_\(url.lastPathComponent)")
                try? FileManager.default.copyItem(at: url, to: tempURL)

                let size = (try? FileManager.default.attributesOfItem(atPath: tempURL.path)[.size] as? Int64) ?? 0
                let info = ImportManifest.ImportFileInfo(
                    name: url.lastPathComponent,
                    path: tempURL.path,
                    size: size
                )
                syncQueue.sync {
                    importFiles.append(info)
                }
            }
        }

        group.notify(queue: .main) { [weak self] in
            guard let self else { return }
            let files = syncQueue.sync { importFiles }
            guard !files.isEmpty else { return }
            // Track temp URLs for cleanup after upload completes or cancels
            self.pendingTempURLs.append(contentsOf: files.map { URL(fileURLWithPath: $0.path) })
            let manifest = ImportManifest(files: files)
            self.showBatchUpload(manifest: manifest)
        }
    }
}

// MARK: - BatchUploadViewModelCoordinatorDelegate

extension FilesCoordinator: BatchUploadViewModelCoordinatorDelegate {
    func batchUploadDidComplete() {
        cleanupTempFiles()
        navigationController.dismiss(animated: true) { [weak self] in
            // Refresh file browser after upload
            if let browserVC = self?.navigationController.topViewController as? FileBrowserViewController {
                browserVC.refresh()
            }
        }
    }

    func batchUploadDidCancel() {
        cleanupTempFiles()
        navigationController.dismiss(animated: true)
    }
}

// MARK: - Temp File Cleanup

private extension FilesCoordinator {
    func cleanupTempFiles() {
        for url in pendingTempURLs {
            try? FileManager.default.removeItem(at: url)
        }
        pendingTempURLs.removeAll()
    }
}
