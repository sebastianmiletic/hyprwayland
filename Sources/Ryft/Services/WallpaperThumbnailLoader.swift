import AppKit
import Combine
import QuickLookThumbnailing

final class WallpaperThumbnailLoader: ObservableObject {
    @Published var image: NSImage?
    init(url: URL, size: CGSize = CGSize(width: 440, height: 240)) {
        let request = QLThumbnailGenerator.Request(fileAt: url, size: size, scale: NSScreen.main?.backingScaleFactor ?? 2, representationTypes: .thumbnail)
        QLThumbnailGenerator.shared.generateBestRepresentation(for: request) { [weak self] representation, _ in
            guard let image = representation?.nsImage else { return }
            DispatchQueue.main.async { self?.image = image }
        }
    }
}
