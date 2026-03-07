import FileProvider

/// Enumerates items in a container (folder) for the File Provider.
/// Uses FPAPIClient to fetch folder contents from the backend.
class FileProviderEnumerator: NSObject, NSFileProviderEnumerator {

    // MARK: - Properties

    private let enumeratedItemIdentifier: NSFileProviderItemIdentifier
    private let apiClient: FPAPIClient

    // MARK: - Initialization

    init(enumeratedItemIdentifier: NSFileProviderItemIdentifier, apiClient: FPAPIClient) {
        self.enumeratedItemIdentifier = enumeratedItemIdentifier
        self.apiClient = apiClient
        super.init()
    }

    // MARK: - NSFileProviderEnumerator

    func invalidate() {
        // No resources to clean up
    }

    /// Enumerate items in the current container
    func enumerateItems(for observer: NSFileProviderEnumerationObserver, startingAt page: NSFileProviderPage) {
        Task {
            do {
                let folderId = resolveFolderId()
                let contents = try await apiClient.listFolder(folderId)

                var items: [NSFileProviderItem] = []

                let parentId = enumeratedItemIdentifier

                for folder in contents.subfolders {
                    items.append(FileProviderItem.from(fpFolder: folder, parentIdentifier: parentId))
                }

                for file in contents.files {
                    items.append(FileProviderItem.from(fpFile: file, parentIdentifier: parentId))
                }

                observer.didEnumerate(items)
                observer.finishEnumerating(upTo: nil)

                // Update sync anchor
                let containerId = folderId ?? "root"
                FPSyncAnchorStore.writeAnchor(Date(), for: containerId)
            } catch {
                observer.finishEnumeratingWithError(mapError(error))
            }
        }
    }

    /// Enumerate changes since the given sync anchor.
    /// Currently does a full re-enumerate on each change request (simple but correct).
    func enumerateChanges(for observer: NSFileProviderChangeObserver, from anchor: NSFileProviderSyncAnchor) {
        Task {
            do {
                let folderId = resolveFolderId()
                let contents = try await apiClient.listFolder(folderId)

                let parentId = enumeratedItemIdentifier
                var items: [NSFileProviderItem] = []

                for folder in contents.subfolders {
                    items.append(FileProviderItem.from(fpFolder: folder, parentIdentifier: parentId))
                }
                for file in contents.files {
                    items.append(FileProviderItem.from(fpFile: file, parentIdentifier: parentId))
                }

                if !items.isEmpty {
                    observer.didUpdate(items)
                }

                let newAnchor = makeAnchor()
                let containerId = folderId ?? "root"
                FPSyncAnchorStore.writeAnchor(Date(), for: containerId)

                observer.finishEnumeratingChanges(upTo: newAnchor, moreComing: false)
            } catch {
                observer.finishEnumeratingWithError(mapError(error))
            }
        }
    }

    /// Return the current sync anchor
    func currentSyncAnchor(completionHandler: @escaping (NSFileProviderSyncAnchor?) -> Void) {
        let containerId = resolveFolderId() ?? "root"
        if let date = FPSyncAnchorStore.readAnchor(for: containerId) {
            completionHandler(makeAnchor(from: date))
        } else {
            completionHandler(makeAnchor())
        }
    }

    // MARK: - Private Methods

    private func resolveFolderId() -> String? {
        if enumeratedItemIdentifier == .rootContainer {
            return nil
        }
        return enumeratedItemIdentifier.rawValue
    }

    private func makeAnchor(from date: Date = Date()) -> NSFileProviderSyncAnchor {
        let data = String(date.timeIntervalSince1970).data(using: .utf8) ?? Data()
        return NSFileProviderSyncAnchor(data)
    }

    private func mapError(_ error: Error) -> Error {
        if error is NSFileProviderError { return error }
        return NSFileProviderError(.serverUnreachable)
    }
}
