import Foundation
import Combine

/// Delegate for file preview view model coordinator events
protocol FilePreviewViewModelCoordinatorDelegate: AnyObject {
    func filePreviewDidRequestShare(_ file: FileItem)
    func filePreviewDidRequestDelete(_ file: FileItem)
}

/// View model for file preview screen
final class FilePreviewViewModel: BaseViewModel {

    // MARK: - Properties

    private let fileRepository: FileRepository
    private let cryptoManager: CryptoManager
    weak var coordinatorDelegate: FilePreviewViewModelCoordinatorDelegate?

    let file: FileItem
    @Published var decryptedData: Data?
    @Published var downloadProgress: Double = 0

    // MARK: - Initialization

    init(file: FileItem, fileRepository: FileRepository, cryptoManager: CryptoManager) {
        self.file = file
        self.fileRepository = fileRepository
        self.cryptoManager = cryptoManager
        super.init()
    }

    // MARK: - Data Loading

    func loadFileContent() {
        isLoading = true
        clearError()

        Task {
            do {
                // Download encrypted file
                let fileURL = try await fileRepository.downloadFile(
                    fileId: file.id,
                    progress: { [weak self] progress in
                        DispatchQueue.main.async {
                            self?.downloadProgress = progress
                        }
                    }
                )
                let encryptedData = try Data(contentsOf: fileURL)

                // Decrypt file
                let decrypted = try cryptoManager.decryptFile(encryptedData: encryptedData)

                await MainActor.run {
                    self.decryptedData = decrypted
                    self.isLoading = false
                }
            } catch {
                await MainActor.run {
                    handleError(error)
                }
            }
        }
    }

    // MARK: - Actions

    func requestShare() {
        coordinatorDelegate?.filePreviewDidRequestShare(file)
    }

    func requestDelete() {
        coordinatorDelegate?.filePreviewDidRequestDelete(file)
    }

    func deleteFile() {
        isLoading = true

        Task {
            do {
                try await fileRepository.deleteFile(fileId: file.id)
                await MainActor.run {
                    self.isLoading = false
                    self.coordinatorDelegate?.filePreviewDidRequestDelete(file)
                }
            } catch {
                await MainActor.run {
                    handleError(error)
                }
            }
        }
    }

    // MARK: - Computed

    var fileType: FileType {
        FileType.from(mimeType: file.mimeType)
    }

    var canPreview: Bool {
        switch fileType {
        case .image, .pdf, .video, .audio, .text:
            return true
        case .unknown:
            return false
        }
    }
}

// MARK: - File Type

enum FileType {
    case image
    case pdf
    case video
    case audio
    case text
    case unknown

    static func from(mimeType: String) -> FileType {
        if mimeType.hasPrefix("image/") {
            return .image
        } else if mimeType == "application/pdf" {
            return .pdf
        } else if mimeType.hasPrefix("video/") {
            return .video
        } else if mimeType.hasPrefix("audio/") {
            return .audio
        } else if mimeType.hasPrefix("text/") || mimeType == "application/json" {
            return .text
        } else {
            return .unknown
        }
    }
}
