import UIKit
import UniformTypeIdentifiers

#if targetEnvironment(macCatalyst)
extension FileBrowserViewController {

    /// Configure drag and drop interactions for Mac Catalyst
    func configureDragAndDrop() {
        // Enable drop to upload files from Finder
        let dropInteraction = UIDropInteraction(delegate: self)
        view.addInteraction(dropInteraction)
    }
}

// MARK: - Drop to Upload

extension FileBrowserViewController: UIDropInteractionDelegate {

    func dropInteraction(_ interaction: UIDropInteraction,
                         canHandle session: UIDropSession) -> Bool {
        return session.hasItemsConforming(toTypeIdentifiers: [UTType.item.identifier])
    }

    func dropInteraction(_ interaction: UIDropInteraction,
                         sessionDidUpdate session: UIDropSession) -> UIDropProposal {
        return UIDropProposal(operation: .copy)
    }

    func dropInteraction(_ interaction: UIDropInteraction,
                         performDrop session: UIDropSession) {
        let dispatchGroup = DispatchGroup()
        var importFiles: [ImportManifest.ImportFileInfo] = []
        let lock = NSLock()
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("drop-\(UUID().uuidString)")

        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        for item in session.items {
            let itemProvider = item.itemProvider

            dispatchGroup.enter()
            itemProvider.loadFileRepresentation(forTypeIdentifier: UTType.item.identifier) { url, error in
                defer { dispatchGroup.leave() }
                guard let url = url else { return }

                // The provided URL is only valid during this callback — copy to temp
                let destURL = tempDir.appendingPathComponent(url.lastPathComponent)
                do {
                    try FileManager.default.copyItem(at: url, to: destURL)
                    let attrs = try? FileManager.default.attributesOfItem(atPath: destURL.path)
                    let size = (attrs?[.size] as? Int64) ?? 0

                    let fileInfo = ImportManifest.ImportFileInfo(
                        name: destURL.lastPathComponent,
                        path: destURL.path,
                        size: size
                    )
                    lock.lock()
                    importFiles.append(fileInfo)
                    lock.unlock()
                } catch {
                    // Skip files that fail to copy
                }
            }
        }

        dispatchGroup.notify(queue: .main) { [weak self] in
            guard !importFiles.isEmpty else {
                // No files extracted — clean up empty temp dir
                try? FileManager.default.removeItem(at: tempDir)
                return
            }
            let manifest = ImportManifest(files: importFiles)
            self?.viewModel.uploadDroppedFiles(manifest)

            // Schedule temp directory cleanup after upload has time to read the files.
            // BatchUploadViewController copies files into its own encrypted pipeline,
            // so the plaintext temps can be removed after a short delay.
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 60) {
                try? FileManager.default.removeItem(at: tempDir)
            }
        }
    }
}
#endif
