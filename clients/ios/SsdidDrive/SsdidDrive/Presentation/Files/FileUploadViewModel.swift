import Foundation
import Combine
import UniformTypeIdentifiers

/// Delegate for file upload view model coordinator events
protocol FileUploadViewModelCoordinatorDelegate: AnyObject {
    func fileUploadDidComplete(_ file: FileItem)
    func fileUploadDidCancel()
}

/// View model for file upload screen
final class FileUploadViewModel: BaseViewModel {

    // MARK: - Properties

    private let fileRepository: FileRepository
    private let cryptoManager: CryptoManager
    weak var coordinatorDelegate: FileUploadViewModelCoordinatorDelegate?

    let parentFolderId: String?

    @Published var selectedFileURL: URL?
    @Published var fileName: String = ""
    @Published var fileSize: Int64 = 0
    @Published var uploadProgress: Double = 0
    @Published var isUploading: Bool = false

    // MARK: - Initialization

    init(fileRepository: FileRepository, cryptoManager: CryptoManager, parentFolderId: String?) {
        self.fileRepository = fileRepository
        self.cryptoManager = cryptoManager
        self.parentFolderId = parentFolderId
        super.init()
    }

    // MARK: - File Selection

    func selectFile(_ url: URL) {
        selectedFileURL = url
        fileName = url.lastPathComponent
        fileSize = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int64) ?? 0
    }

    func clearSelection() {
        selectedFileURL = nil
        fileName = ""
        fileSize = 0
    }

    // MARK: - Upload

    func uploadFile() {
        guard let url = selectedFileURL else { return }

        isUploading = true
        clearError()

        Task {
            do {
                // Read file data
                let fileData = try Data(contentsOf: url)

                // Encrypt file
                let encryptedData = try await cryptoManager.encryptFile(fileData)

                // Write encrypted data to a temporary file
                let tempDir = FileManager.default.temporaryDirectory
                let tempURL = tempDir.appendingPathComponent(fileName + ".encrypted")
                try encryptedData.write(to: tempURL)

                // Upload encrypted file using the temp URL
                let uploadedFile = try await fileRepository.uploadFile(
                    url: tempURL,
                    folderId: parentFolderId,
                    progress: { [weak self] progress in
                        DispatchQueue.main.async {
                            self?.uploadProgress = progress
                        }
                    }
                )

                // Clean up temp file
                try? FileManager.default.removeItem(at: tempURL)

                await MainActor.run {
                    self.isUploading = false
                    self.coordinatorDelegate?.fileUploadDidComplete(uploadedFile)
                }
            } catch {
                await MainActor.run {
                    self.isUploading = false
                    handleError(error)
                }
            }
        }
    }

    func cancel() {
        coordinatorDelegate?.fileUploadDidCancel()
    }

    // MARK: - Helpers

    private func mimeType(for url: URL) -> String {
        if let type = UTType(filenameExtension: url.pathExtension) {
            return type.preferredMIMEType ?? "application/octet-stream"
        }
        return "application/octet-stream"
    }

    var formattedFileSize: String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: fileSize)
    }

    var canUpload: Bool {
        selectedFileURL != nil && !isUploading
    }
}
