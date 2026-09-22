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
            let imageView = NSImageView(frame: NSRect(origin: .zero, size: screen.frame.size))
            imageView.image = image; imageView.imageScaling = .scaleProportionallyUpOrDown
            panel.contentView = imageView; panel.orderFrontRegardless()
            return panel
        }
    }

    func reveal() {
        guard !panels.isEmpty else { return }
        let current = panels
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.48; context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            current.forEach { $0.animator().alphaValue = 0 }
        } completionHandler: { [weak self] in
            current.forEach { $0.orderOut(nil) }
            if self?.panels.first === current.first { self?.panels.removeAll() }
        }
    }

    private func finishImmediately() { panels.forEach { $0.orderOut(nil) }; panels.removeAll() }
}
