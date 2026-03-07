import Foundation
import CoreSpotlight
import UniformTypeIdentifiers

/// Indexes file metadata in CoreSpotlight for macOS Spotlight search.
/// Only metadata (name, type, size) is indexed — never file content (zero-knowledge).
final class SpotlightIndexer {

    static let shared = SpotlightIndexer()

    private let domainIdentifier = "com.securesharing.files"
    private let searchableIndex = CSSearchableIndex.default()

    private init() {}

    // MARK: - Indexing

    func indexFile(_ file: FileItem) {
        guard let item = makeSearchableItem(for: file) else { return }

        searchableIndex.indexSearchableItems([item]) { error in
            #if DEBUG
            if let error = error {
                print("[Spotlight] Index error: \(error.localizedDescription)")
            }
            #endif
        }
    }

    func indexFiles(_ files: [FileItem]) {
        let items = files.compactMap { makeSearchableItem(for: $0) }
        guard !items.isEmpty else { return }

        searchableIndex.indexSearchableItems(items) { error in
            #if DEBUG
            if let error = error {
                print("[Spotlight] Batch index error: \(error.localizedDescription)")
            }
            #endif
        }
    }

    func removeFile(id: String) {
        searchableIndex.deleteSearchableItems(withIdentifiers: ["file_\(id)"]) { error in
            #if DEBUG
            if let error = error {
                print("[Spotlight] Remove error: \(error.localizedDescription)")
            }
            #endif
        }
    }

    func clearAllIndexes() {
        searchableIndex.deleteSearchableItems(withDomainIdentifiers: [domainIdentifier]) { error in
            #if DEBUG
            if let error = error {
                print("[Spotlight] Clear error: \(error.localizedDescription)")
            }
            #endif
        }
    }

    // MARK: - Private

    private func makeSearchableItem(for file: FileItem) -> CSSearchableItem? {
        guard !file.isFolder else { return nil }

        let attributeSet = CSSearchableItemAttributeSet(contentType: file.utType ?? .data)
        attributeSet.title = file.name
        attributeSet.contentDescription = file.formattedSize
        attributeSet.kind = file.mimeType

        let item = CSSearchableItem(
            uniqueIdentifier: "file_\(file.id)",
            domainIdentifier: domainIdentifier,
            attributeSet: attributeSet
        )
        item.expirationDate = Date().addingTimeInterval(30 * 24 * 60 * 60) // 30 days
        return item
    }
}
