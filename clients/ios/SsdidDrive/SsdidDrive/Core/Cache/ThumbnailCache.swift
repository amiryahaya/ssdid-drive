import UIKit

/// NSCache-based image thumbnail cache for file grid cells.
final class ThumbnailCache {

    static let shared = ThumbnailCache()

    private let cache = NSCache<NSString, UIImage>()

    private init() {
        cache.totalCostLimit = 50 * 1024 * 1024 // 50 MB
        cache.countLimit = 200

        NotificationCenter.default.addObserver(
            forName: UIApplication.didReceiveMemoryWarningNotification,
            object: nil,
            queue: nil
        ) { [weak self] _ in
            self?.clearCache()
        }
    }

    // MARK: - Access

    func thumbnail(for fileId: String) -> UIImage? {
        cache.object(forKey: fileId as NSString)
    }

    func setThumbnail(_ image: UIImage, for fileId: String) {
        let cost = Int(image.size.width * image.scale * image.size.height * image.scale * 4)
        cache.setObject(image, forKey: fileId as NSString, cost: cost)
    }

    // MARK: - Generation

    func generateThumbnail(for fileId: String, data: Data, targetSize: CGSize = CGSize(width: 120, height: 120), completion: @escaping (UIImage?) -> Void) {
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let source = UIImage(data: data) else {
                DispatchQueue.main.async { completion(nil) }
                return
            }

            let renderer = UIGraphicsImageRenderer(size: targetSize)
            let thumbnail = renderer.image { _ in
                source.draw(in: CGRect(origin: .zero, size: targetSize))
            }

            self?.setThumbnail(thumbnail, for: fileId)

            DispatchQueue.main.async {
                completion(thumbnail)
            }
        }
    }

    func clearCache() {
        cache.removeAllObjects()
    }
}
