import Foundation
import Combine

/// Delegate for file browser view model coordinator events
protocol FileBrowserViewModelCoordinatorDelegate: AnyObject {
    func fileBrowserDidSelectFile(_ file: FileItem)
    func fileBrowserDidRequestUpload(inFolder folderId: String?)
    func fileBrowserDidRequestNewFolder(inFolder folderId: String?)
    func fileBrowserDidRequestShare(_ file: FileItem)
    func fileBrowserDidRequestBatchUpload(manifest: ImportManifest)
}

/// View model for file browser screen
final class FileBrowserViewModel: BaseViewModel {

    // MARK: - Properties

    private let fileRepository: FileRepository
    weak var coordinatorDelegate: FileBrowserViewModelCoordinatorDelegate?

    @Published var files: [FileItem] = []
    @Published var currentFolder: FileItem?
    @Published var folderPath: [FileItem] = []
    @Published var isGridView: Bool = true
    @Published var sortOption: SortOption = .nameAsc
    @Published var isRefreshing: Bool = false
    @Published var isOffline: Bool = false

    // Search
    @Published var searchQuery: String = ""
    @Published var isSearchActive: Bool = false
    @Published var searchResults: [FileItem] = []
    @Published var isSearching: Bool = false
    private var allAccessibleFiles: [FileItem] = []
    private var searchDebounceTimer: Timer?

    enum SortOption {
        case nameAsc, nameDesc, dateAsc, dateDesc, sizeAsc, sizeDesc
    }

    // MARK: - Initialization

    init(fileRepository: FileRepository, folder: FileItem? = nil) {
        self.fileRepository = fileRepository
        self.currentFolder = folder
        super.init()

        if let folder = folder {
            folderPath.append(folder)
        }
    }

    // MARK: - Data Loading

    func loadFiles() {
        isLoading = true
        clearError()

        Task {
            do {
                let result = try await fileRepository.listFiles(folderId: currentFolder?.id)
                let contents = result.contents
                await MainActor.run {
                    // Convert FolderContents to [FileItem]
                    let folderItems = contents.subfolders.map { folder in
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
                    let allItems = folderItems + contents.files
                    self.files = self.sortFiles(allItems)
                    self.isLoading = false
                    self.isRefreshing = false
                    self.isOffline = result.isFromCache

                    // M2: Mark sync as connected after successful API call
                    let shared = SharedDefaults.shared
                    if !self.isOffline {
                        shared.writeSyncStatus(.connected)
                        shared.writeLastSyncDate(Date())
                    } else {
                        shared.writeSyncStatus(.offline)
                    }

                    // M4: Accumulate recent files across folder navigations (merge, don't replace)
                    let newFiles = contents.files
                        .sorted { $0.updatedAt > $1.updatedAt }
                        .prefix(5)
                        .map { RecentFile(id: $0.id, name: $0.name, mimeType: $0.mimeType, size: $0.size, updatedAt: $0.updatedAt, isFolder: false) }
                    var existing = shared.readRecentFiles()
                    for file in newFiles {
                        if let idx = existing.firstIndex(where: { $0.id == file.id }) {
                            existing[idx] = file
                        } else {
                            existing.append(file)
                        }
                    }
                    let topRecent = Array(existing.sorted { $0.updatedAt > $1.updatedAt }.prefix(5))
                    shared.writeRecentFiles(topRecent)
                    shared.notifyHelper()

                    DependencyContainer.shared.fileProviderDomainManager.signalEnumerator()

                    // Index file metadata in Spotlight (macOS only, zero-knowledge: metadata only)
                    #if targetEnvironment(macCatalyst)
                    SpotlightIndexer.shared.indexFiles(contents.files)
                    #endif
                }
            } catch {
                await MainActor.run {
                    handleError(error)
                    self.isRefreshing = false
                    self.isOffline = true

                    // M2: Reflect error in sync status
                    SharedDefaults.shared.writeSyncStatus(.error)
                    SharedDefaults.shared.notifyHelper()
                }
            }
        }
    }

    func refreshFiles() {
        isRefreshing = true
        loadFiles()
    }

    // MARK: - Sorting

    private func sortFiles(_ files: [FileItem]) -> [FileItem] {
        // Folders first, then files
        let folders = files.filter { $0.isFolder }
        let items = files.filter { !$0.isFolder }

        let sortedFolders = sortItems(folders)
        let sortedItems = sortItems(items)

        return sortedFolders + sortedItems
    }

    private func sortItems(_ items: [FileItem]) -> [FileItem] {
        switch sortOption {
        case .nameAsc:
            return items.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        case .nameDesc:
            return items.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedDescending }
        case .dateAsc:
            return items.sorted { $0.updatedAt < $1.updatedAt }
        case .dateDesc:
            return items.sorted { $0.updatedAt > $1.updatedAt }
        case .sizeAsc:
            return items.sorted { $0.size < $1.size }
        case .sizeDesc:
            return items.sorted { $0.size > $1.size }
        }
    }

    func setSortOption(_ option: SortOption) {
        sortOption = option
        files = sortFiles(files)
    }

    // MARK: - Actions

    func selectFile(_ file: FileItem) {
        if file.isFolder {
            navigateToFolder(file)
        } else {
            coordinatorDelegate?.fileBrowserDidSelectFile(file)
        }
    }

    func navigateToFolder(_ folder: FileItem) {
        folderPath.append(folder)
        currentFolder = folder
        loadFiles()
    }

    func navigateUp() {
        guard !folderPath.isEmpty else { return }
        folderPath.removeLast()
        currentFolder = folderPath.last
        loadFiles()
    }

    func navigateToPathIndex(_ index: Int) {
        guard index < folderPath.count else { return }
        folderPath = Array(folderPath.prefix(index + 1))
        currentFolder = folderPath.last
        loadFiles()
    }

    func deleteFile(_ file: FileItem) {
        isLoading = true

        Task {
            do {
                try await fileRepository.deleteFile(fileId: file.id)
                await MainActor.run {
                    self.files.removeAll { $0.id == file.id }
                    self.isLoading = false
                    DependencyContainer.shared.fileProviderDomainManager.signalEnumerator()

                    #if targetEnvironment(macCatalyst)
                    SpotlightIndexer.shared.removeFile(id: file.id)
                    #endif
                }
            } catch {
                await MainActor.run {
                    handleError(error)
                }
            }
        }
    }

    func requestUpload() {
        coordinatorDelegate?.fileBrowserDidRequestUpload(inFolder: currentFolder?.id)
    }

    func requestNewFolder() {
        coordinatorDelegate?.fileBrowserDidRequestNewFolder(inFolder: currentFolder?.id)
    }

    func requestShare(_ file: FileItem) {
        coordinatorDelegate?.fileBrowserDidRequestShare(file)
    }

    func toggleViewMode() {
        isGridView.toggle()
    }

    func uploadDroppedFiles(_ manifest: ImportManifest) {
        coordinatorDelegate?.fileBrowserDidRequestBatchUpload(manifest: manifest)
    }

    // MARK: - Search

    func activateSearch() {
        isSearchActive = true
        if allAccessibleFiles.isEmpty {
            loadAllAccessibleFiles()
        }
    }

    func deactivateSearch() {
        isSearchActive = false
        searchQuery = ""
        searchResults = []
        searchDebounceTimer?.invalidate()
    }

    func updateSearchQuery(_ query: String) {
        searchQuery = query
        searchDebounceTimer?.invalidate()

        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else {
            searchResults = []
            return
        }

        // Debounce: filter after 300ms of no typing
        searchDebounceTimer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: false) { [weak self] _ in
            self?.performLocalSearch(query)
        }
    }

    private func performLocalSearch(_ query: String) {
        let lowercasedQuery = query.lowercased()

        // First, search within currently loaded files (fast path)
        let localResults = files.filter {
            $0.name.lowercased().contains(lowercasedQuery)
        }

        // Then, search all accessible files (broader search)
        let globalResults = allAccessibleFiles.filter {
            $0.name.lowercased().contains(lowercasedQuery)
        }

        // Merge: local results first, then global results that aren't already included
        let localIds = Set(localResults.map { $0.id })
        let additionalResults = globalResults.filter { !localIds.contains($0.id) }

        searchResults = sortFiles(localResults + additionalResults)
    }

    private func loadAllAccessibleFiles() {
        isSearching = true

        Task {
            do {
                let contents = try await fileRepository.search(query: "")
                await MainActor.run {
                    self.allAccessibleFiles = contents.files
                    self.isSearching = false
                    // Re-run search if query was entered while loading
                    if !self.searchQuery.isEmpty {
                        self.performLocalSearch(self.searchQuery)
                    }
                }
            } catch {
                await MainActor.run {
                    self.isSearching = false
                }
            }
        }
    }

    // MARK: - Folder Creation

    func createFolder(name: String) {
        isLoading = true

        Task {
            do {
                let folder = try await fileRepository.createFolder(name: name, parentId: currentFolder?.id)
                await MainActor.run {
                    // Convert Folder to FileItem
                    let newFolderItem = FileItem(
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
                    self.files.insert(newFolderItem, at: 0)
                    self.files = self.sortFiles(self.files)
                    self.isLoading = false
                    DependencyContainer.shared.fileProviderDomainManager.signalEnumerator()
                }
            } catch {
                await MainActor.run {
                    handleError(error)
                }
            }
        }
    }

    // MARK: - Computed

    var navigationTitle: String {
        currentFolder?.name ?? "My Files"
    }

    var isEmpty: Bool {
        files.isEmpty && !isLoading
    }
}
