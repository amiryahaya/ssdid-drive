import Foundation
import Combine

/// Delegate for batch upload view model coordinator events
protocol BatchUploadViewModelCoordinatorDelegate: AnyObject {
    func batchUploadDidComplete()
    func batchUploadDidCancel()
}

/// View model for batch file upload from Share Extension
final class BatchUploadViewModel: BaseViewModel {

    // MARK: - Types

    struct ImportFileStatus: Identifiable {
        let id = UUID()
        let info: ImportManifest.ImportFileInfo
        var status: Status = .pending
        var progress: Double = 0

        enum Status {
            case pending
            case uploading
            case completed
            case failed(Error)
        }
    }

    enum UploadError: LocalizedError {
        case fileNotFound
        case invalidPath
        case pathTraversalDetected
        case fileTooLarge
        case encryptionFailed
        case uploadFailed(Error)

        var errorDescription: String? {
            switch self {
            case .fileNotFound:
                return "File not found in shared container"
            case .invalidPath:
                return "File path is outside the allowed directory"
            case .pathTraversalDetected:
                return "Invalid file path detected"
            case .fileTooLarge:
                return "File exceeds maximum allowed size"
            case .encryptionFailed:
                return "Failed to encrypt file"
            case .uploadFailed(let error):
                return "Upload failed: \(error.localizedDescription)"
            }
        }
    }

    // MARK: - Constants

    /// Maximum file size allowed for upload (100 MB in bytes)
    private static let maxFileSize: Int64 = 100 * 1024 * 1024

    /// File suffix for encrypted temporary files
    private static let encryptedFileSuffix = ".encrypted"

    // MARK: - Properties

    private let fileRepository: FileRepository
    private let cryptoManager: CryptoManager
    let manifest: ImportManifest

    /// Active upload task for cancellation support
    private var uploadTask: Task<Void, Never>?

    weak var coordinatorDelegate: BatchUploadViewModelCoordinatorDelegate?

    @Published var files: [ImportFileStatus] = []
    @Published var isUploading: Bool = false
    @Published var currentFileIndex: Int = 0
    @Published var overallProgress: Double = 0
    @Published var uploadComplete: Bool = false

    // MARK: - Computed Properties

    var totalFileCount: Int {
        files.count
    }

    var completedFileCount: Int {
        fileCount(matching: .completed)
    }

    var failedFileCount: Int {
        fileCount(matchingFailed: true)
    }

    // MARK: - Private Helpers

    /// Count files matching a specific status
    private func fileCount(matching status: ImportFileStatus.Status) -> Int {
        files.filter { file in
            switch (status, file.status) {
            case (.pending, .pending): return true
            case (.uploading, .uploading): return true
            case (.completed, .completed): return true
            case (.failed, .failed): return true
            default: return false
            }
        }.count
    }

    /// Count files with failed status
    private func fileCount(matchingFailed: Bool) -> Int {
        files.filter {
            if case .failed = $0.status { return matchingFailed }
            return !matchingFailed
        }.count
    }

    var totalSize: Int64 {
        manifest.files.reduce(0) { $0 + $1.size }
    }

    var formattedTotalSize: String {
        ByteCountFormatter.string(fromByteCount: totalSize, countStyle: .file)
    }

    // MARK: - Initialization

    /// Creates a batch upload view model
    /// - Parameters:
    ///   - fileRepository: Repository for file operations
    ///   - cryptoManager: Manager for encryption
    ///   - manifest: Import manifest with files to upload
    /// - Returns: nil if manifest is empty
    init?(fileRepository: FileRepository, cryptoManager: CryptoManager, manifest: ImportManifest) {
        // Validate manifest is not empty
        guard !manifest.files.isEmpty else {
            return nil
        }

        self.fileRepository = fileRepository
        self.cryptoManager = cryptoManager
        self.manifest = manifest
        super.init()

        self.files = manifest.files.map { ImportFileStatus(info: $0) }
    }

    // MARK: - Upload

    func uploadAll() {
        guard !isUploading else { return }

        isUploading = true
        clearError()

        uploadTask = Task {
            for (index, _) in files.enumerated() {
                // Check for cancellation before each file
                guard !Task.isCancelled else { break }

                await MainActor.run {
                    self.currentFileIndex = index
                    self.files[index].status = .uploading
                }

                do {
                    try await uploadFile(at: index)

                    // Check cancellation after upload
                    guard !Task.isCancelled else { break }

                    await MainActor.run {
                        self.files[index].status = .completed
                        self.files[index].progress = 1.0
                        self.updateOverallProgress()
                    }
                } catch {
                    await MainActor.run {
                        self.files[index].status = .failed(error)
                        self.updateOverallProgress()
                    }
                }
            }

            // Cleanup import files
            DeepLinkParser.cleanupImportFiles()

            await MainActor.run {
                self.isUploading = false
                self.uploadComplete = true
                self.uploadTask = nil

                // Notify coordinator
                if self.failedFileCount == 0 {
                    self.coordinatorDelegate?.batchUploadDidComplete()
                }
            }
        }
    }

    private func uploadFile(at index: Int) async throws {
        let fileInfo = files[index].info

        // SECURITY: Validate file path is within the shared container
        guard let sharedDir = DeepLinkParser.sharedFilesDirectoryURL() else {
            throw UploadError.invalidPath
        }

        // Normalize and validate the path to prevent path traversal
        let fileURL = URL(fileURLWithPath: fileInfo.path).standardizedFileURL
        let normalizedPath = fileURL.path

        guard normalizedPath.hasPrefix(sharedDir.path) else {
            throw UploadError.pathTraversalDetected
        }

        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            throw UploadError.fileNotFound
        }

        // SECURITY: Validate file size before loading into memory
        let attributes = try FileManager.default.attributesOfItem(atPath: fileURL.path)
        if let fileSize = attributes[.size] as? Int64, fileSize > Self.maxFileSize {
            throw UploadError.fileTooLarge
        }

        // Read file data
        let fileData = try Data(contentsOf: fileURL)

        // Encrypt file
        let encryptedData: Data
        do {
            encryptedData = try await cryptoManager.encryptFile(fileData)
        } catch {
            throw UploadError.encryptionFailed
        }

        // Write encrypted data to temp file
        let tempDir = FileManager.default.temporaryDirectory
        let tempURL = tempDir.appendingPathComponent(UUID().uuidString + "_" + fileInfo.name + Self.encryptedFileSuffix)

        try encryptedData.write(to: tempURL)

        defer {
            // SECURITY: Log if temp file deletion fails
            do {
                try FileManager.default.removeItem(at: tempURL)
            } catch {
                #if DEBUG
                print("Warning: Failed to delete temp file at \(tempURL.path): \(error.localizedDescription)")
                #endif
                // In production, consider queueing for cleanup on next launch
            }
        }

        // Upload
        do {
            _ = try await fileRepository.uploadFile(
                url: tempURL,
                folderId: nil,
                progress: { [weak self] progress in
                    DispatchQueue.main.async {
                        // Bounds check before accessing array
                        guard let self = self, index < self.files.count else { return }
                        self.files[index].progress = progress
                        self.updateOverallProgress()
                    }
                }
            )
        } catch {
            throw UploadError.uploadFailed(error)
        }
    }

    private func updateOverallProgress() {
        guard !files.isEmpty else {
            overallProgress = 0
            return
        }
        let totalProgress = files.reduce(0.0) { $0 + $1.progress }
        overallProgress = totalProgress / Double(files.count)
    }

    func cancel() {
        // Cancel the running upload task
        uploadTask?.cancel()
        uploadTask = nil
        isUploading = false

        // Cleanup import files
        DeepLinkParser.cleanupImportFiles()
        coordinatorDelegate?.batchUploadDidCancel()
    }

    func retryFailed() {
        // Reset failed files to pending and restart
        for index in files.indices {
            if case .failed = files[index].status {
                files[index].status = .pending
                files[index].progress = 0
            }
        }
        uploadComplete = false
        uploadAll()
    }

    func dismiss() {
        if failedFileCount == 0 {
            coordinatorDelegate?.batchUploadDidComplete()
        } else {
            // Clean up and dismiss even with failures
            DeepLinkParser.cleanupImportFiles()
            coordinatorDelegate?.batchUploadDidCancel()
        }
    }
}
