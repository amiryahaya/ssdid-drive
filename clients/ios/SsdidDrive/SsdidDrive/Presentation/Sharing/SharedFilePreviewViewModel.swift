import Foundation
import Combine

/// View model for shared file preview screen
final class SharedFilePreviewViewModel: BaseViewModel {

    // MARK: - Properties

    private let share: Share
    private let fileRepository: FileRepository
    private let cryptoManager: CryptoManager

    @Published var decryptedData: Data?
    @Published var downloadProgress: Double = 0

    // MARK: - Initialization

    init(share: Share, fileRepository: FileRepository, cryptoManager: CryptoManager) {
        self.share = share
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
                    fileId: share.resourceId,
                    progress: { [weak self] progress in
                        DispatchQueue.main.async {
                            self?.downloadProgress = progress
                        }
                    }
                )
                let encryptedData = try Data(contentsOf: fileURL)

                // Decrypt file using share's encrypted key
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

    // MARK: - Computed

    var fileName: String {
        share.resourceId
    }

    var fileType: FileType {
        // Determine file type from name extension
        let ext = (share.resourceId as NSString).pathExtension.lowercased()
        switch ext {
        case "jpg", "jpeg", "png", "gif", "heic":
            return .image
        case "pdf":
            return .pdf
        case "mp4", "mov", "avi":
            return .video
        case "mp3", "wav", "m4a":
            return .audio
        case "txt", "json", "md", "swift", "js":
            return .text
        default:
            return .unknown
        }
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
