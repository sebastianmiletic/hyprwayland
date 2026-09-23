import AppKit
import Combine
import QuickLookThumbnailing

final class WallpaperThumbnailLoader: ObservableObject {
    @Published private(set) var image: NSImage?

    private static let cache: NSCache<NSString, NSImage> = {
        let cache = NSCache<NSString, NSImage>()
        cache.countLimit = 600
        cache.totalCostLimit = 256 * 1024 * 1024
        return cache
    }()
    private static let lock = NSLock()
    private static var pending: [String: [(NSImage?) -> Void]] = [:]

    init(url: URL, size: CGSize = CGSize(width: 440, height: 240)) {
        let scale = NSScreen.main?.backingScaleFactor ?? 2
        let key = "\(url.path)|\(Int(size.width))x\(Int(size.height))@\(scale)"
        if let cached = Self.cache.object(forKey: key as NSString) {
            image = cached
            return
        }

        Self.lock.lock()
        let shouldStart = Self.pending[key] == nil
        Self.pending[key, default: []].append { [weak self] image in self?.image = image }
        Self.lock.unlock()
        guard shouldStart else { return }

        let request = QLThumbnailGenerator.Request(fileAt: url, size: size, scale: scale, representationTypes: .thumbnail)
        QLThumbnailGenerator.shared.generateBestRepresentation(for: request) { representation, _ in
            let image = representation?.nsImage
            if let image {
                let cost = max(1, Int(image.size.width * image.size.height * 4 * scale * scale))
                Self.cache.setObject(image, forKey: key as NSString, cost: cost)
            }
            Self.lock.lock()
            let completions = Self.pending.removeValue(forKey: key) ?? []
            Self.lock.unlock()
            DispatchQueue.main.async { completions.forEach { $0(image) } }
        }
    }
}
