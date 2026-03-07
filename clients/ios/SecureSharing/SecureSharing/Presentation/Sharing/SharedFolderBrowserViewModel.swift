import Foundation
import Combine

/// View model for shared folder browser screen
final class SharedFolderBrowserViewModel: BaseViewModel {

    // MARK: - Properties

    private let share: Share
    private let fileRepository: FileRepository

    @Published var items: [FileItem] = []

    // MARK: - Initialization

    init(share: Share, fileRepository: FileRepository) {
        self.share = share
        self.fileRepository = fileRepository
        super.init()
    }

    // MARK: - Data Loading

    func loadContents() {
        isLoading = true
        clearError()

        Task {
            do {
                let result = try await fileRepository.listFiles(folderId: share.resourceId)
                await MainActor.run {
                    self.items = result.contents.files + result.contents.subfolders.map { folder in
                        FileItem(
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
                    }
                    self.isLoading = false
                }
            } catch {
                await MainActor.run {
                    handleError(error)
                }
            }
        }
    }

    // MARK: - Computed

    var folderName: String {
        "Shared Folder"
    }

    var isEmpty: Bool {
        items.isEmpty && !isLoading
    }
}
