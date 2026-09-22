import AppKit
import QuartzCore

/// Crossfades the visible desktop surface without covering application windows.
/// Panels sit just above the desktop wallpaper and below normal windows.
final class WallpaperTransitionController {
    private var panels: [NSPanel] = []

    func begin(from path: String) {
        finishImmediately()
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion,
              let image = NSImage(contentsOfFile: path) else { return }
        panels = NSScreen.screens.map { screen in
            let panel = NSPanel(contentRect: screen.frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            panel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow)) + 1)
            panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
            panel.backgroundColor = .clear; panel.isOpaque = false; panel.hasShadow = false
            panel.ignoresMouseEvents = true; panel.hidesOnDeactivate = false; panel.alphaValue = 1
            let imageView = AspectFillImageView(frame: NSRect(origin: .zero, size: screen.frame.size))
            imageView.image = image
            panel.contentView = imageView; panel.orderFrontRegardless()
            return panel
        }
    }

    func reveal() {
        guard !panels.isEmpty else { return }
        let current = panels
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.16) { [weak self] in
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.9
                context.timingFunction = CAMediaTimingFunction(controlPoints: 0.22, 1, 0.36, 1)
                current.forEach { $0.animator().alphaValue = 0 }
            } completionHandler: {
                current.forEach { $0.orderOut(nil) }
                if self?.panels.first === current.first { self?.panels.removeAll() }
            }
        }
    }

    private func finishImmediately() { panels.forEach { $0.orderOut(nil) }; panels.removeAll() }
}

private final class AspectFillImageView: NSImageView {
    override func draw(_ dirtyRect: NSRect) {
        guard let image, image.size.width > 0, image.size.height > 0 else { return }
        let scale = max(bounds.width / image.size.width, bounds.height / image.size.height)
        let size = NSSize(width: image.size.width * scale, height: image.size.height * scale)
        let rect = NSRect(x: (bounds.width - size.width) / 2, y: (bounds.height - size.height) / 2, width: size.width, height: size.height)
        image.draw(in: rect, from: .zero, operation: .copy, fraction: 1, respectFlipped: true, hints: [.interpolation: NSImageInterpolation.high])
    }
}
