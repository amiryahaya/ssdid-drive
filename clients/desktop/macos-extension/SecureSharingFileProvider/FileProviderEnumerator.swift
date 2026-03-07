import FileProvider
import os.log

/// Enumerates the contents of a directory for the File Provider
class FileProviderEnumerator: NSObject, NSFileProviderEnumerator {

    // MARK: - Properties

    private let containerItemIdentifier: NSFileProviderItemIdentifier
    private let apiClient: APIClient
    private let keychainHelper: KeychainHelper
    private let logger = Logger(subsystem: "com.securesharing.fileprovider", category: "Enumerator")

    private var currentPage: Int = 0
    private var hasMorePages: Bool = true

    // MARK: - Initialization

    init(containerItemIdentifier: NSFileProviderItemIdentifier,
         apiClient: APIClient,
         keychainHelper: KeychainHelper) {
        self.containerItemIdentifier = containerItemIdentifier
        self.apiClient = apiClient
        self.keychainHelper = keychainHelper
        super.init()

        logger.debug("Enumerator created for: \(containerItemIdentifier.rawValue)")
    }

    // MARK: - NSFileProviderEnumerator

    func invalidate() {
        logger.debug("Enumerator invalidated")
    }

    /// Enumerate items in the container
    func enumerateItems(for observer: NSFileProviderEnumerationObserver,
                        startingAt page: NSFileProviderPage) {

        logger.info("Enumerating items for: \(self.containerItemIdentifier.rawValue), page: \(page.rawValue.hashValue)")

        // Determine the folder ID to list
        let folderId: String
        if containerItemIdentifier == .rootContainer {
            folderId = "root"
        } else if containerItemIdentifier == .workingSet {
            // Working set returns recently used files
            enumerateWorkingSet(observer: observer)
            return
        } else if containerItemIdentifier == .trashContainer {
            // Enumerate trashed items
            enumerateTrashed(observer: observer)
            return
        } else {
            folderId = containerItemIdentifier.rawValue
        }

        // Parse page token
        let pageNumber: Int
        if page == NSFileProviderPage.initialPageSortedByDate as NSFileProviderPage ||
           page == NSFileProviderPage.initialPageSortedByName as NSFileProviderPage {
            pageNumber = 0
        } else if let pageData = page.rawValue as? Data,
                  let pageStr = String(data: pageData, encoding: .utf8),
                  let num = Int(pageStr) {
            pageNumber = num
        } else {
            pageNumber = 0
        }

        Task {
            do {
                guard let authToken = keychainHelper.getAuthToken() else {
                    observer.finishEnumeratingWithError(NSFileProviderError(.notAuthenticated))
                    return
                }

                let (items, hasMore) = try await apiClient.listFiles(
                    folderId: folderId,
                    page: pageNumber,
                    authToken: authToken
                )

                // Sort items: folders first, then alphabetically
                let sortedItems = items.sorted()

                observer.didEnumerate(sortedItems)

                if hasMore {
                    let nextPage = "\(pageNumber + 1)".data(using: .utf8)!
                    observer.finishEnumerating(upTo: NSFileProviderPage(nextPage))
                } else {
                    observer.finishEnumerating(upTo: nil)
                }

            } catch {
                logger.error("Failed to enumerate: \(error.localizedDescription)")
                observer.finishEnumeratingWithError(error)
            }
        }
    }

    /// Enumerate changes since a sync anchor
    func enumerateChanges(for observer: NSFileProviderChangeObserver,
                          from anchor: NSFileProviderSyncAnchor) {

        logger.info("Enumerating changes from anchor")

        // Parse the sync anchor to get the last sync timestamp
        let lastSyncTimestamp: Date
        if let anchorDate = try? JSONDecoder().decode(Date.self, from: anchor.rawValue) {
            lastSyncTimestamp = anchorDate
        } else {
            lastSyncTimestamp = Date.distantPast
        }

        Task {
            do {
                guard let authToken = keychainHelper.getAuthToken() else {
                    observer.finishEnumeratingWithError(NSFileProviderError(.notAuthenticated))
                    return
                }

                let changes = try await apiClient.getChanges(
                    since: lastSyncTimestamp,
                    authToken: authToken
                )

                // Report updated items
                if !changes.updatedItems.isEmpty {
                    observer.didUpdate(changes.updatedItems)
                }

                // Report deleted items
                if !changes.deletedItemIds.isEmpty {
                    let deletedIdentifiers = changes.deletedItemIds.map {
                        NSFileProviderItemIdentifier($0)
                    }
                    observer.didDeleteItems(withIdentifiers: deletedIdentifiers)
                }

                // Create new sync anchor with current timestamp
                let newAnchor = try JSONEncoder().encode(Date())
                observer.finishEnumeratingChanges(upTo: NSFileProviderSyncAnchor(newAnchor), moreComing: false)

            } catch {
                logger.error("Failed to enumerate changes: \(error.localizedDescription)")
                observer.finishEnumeratingWithError(error)
            }
        }
    }

    /// Return the current sync anchor
    func currentSyncAnchor(completionHandler: @escaping (NSFileProviderSyncAnchor?) -> Void) {
        do {
            let anchorData = try JSONEncoder().encode(Date())
            completionHandler(NSFileProviderSyncAnchor(anchorData))
        } catch {
            completionHandler(nil)
        }
    }

    // MARK: - Private Methods

    /// Enumerate working set (recent files)
    private func enumerateWorkingSet(observer: NSFileProviderEnumerationObserver) {
        Task {
            do {
                guard let authToken = keychainHelper.getAuthToken() else {
                    observer.finishEnumeratingWithError(NSFileProviderError(.notAuthenticated))
                    return
                }

                let items = try await apiClient.getRecentFiles(authToken: authToken)
                observer.didEnumerate(items)
                observer.finishEnumerating(upTo: nil)

            } catch {
                logger.error("Failed to enumerate working set: \(error.localizedDescription)")
                observer.finishEnumeratingWithError(error)
            }
        }
    }

    /// Enumerate trashed items
    private func enumerateTrashed(observer: NSFileProviderEnumerationObserver) {
        Task {
            do {
                guard let authToken = keychainHelper.getAuthToken() else {
                    observer.finishEnumeratingWithError(NSFileProviderError(.notAuthenticated))
                    return
                }

                let items = try await apiClient.getTrashedFiles(authToken: authToken)
                observer.didEnumerate(items)
                observer.finishEnumerating(upTo: nil)

            } catch {
                logger.error("Failed to enumerate trash: \(error.localizedDescription)")
                observer.finishEnumeratingWithError(error)
            }
        }
    }
}

// MARK: - Changes Response

struct FileChangesResponse {
    let updatedItems: [FileProviderItem]
    let deletedItemIds: [String]
}
