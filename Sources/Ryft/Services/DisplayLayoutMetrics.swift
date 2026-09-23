import AppKit

/// Shared display measurements that must survive Ryft hiding the native menu bar.
/// `visibleFrame` stops reporting its top inset after the menu bar is hidden, so
/// the first visible value is retained per display and reused by covers/tiling.
enum DisplayLayoutMetrics {
    private static var menuBarHeights: [NSNumber: CGFloat] = [:]

    static func menuBarHeight(for screen: NSScreen) -> CGFloat {
        let id = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber ?? 0
        let observed = max(0, screen.frame.maxY - screen.visibleFrame.maxY)
        if observed >= 1 {
            let value = min(observed, 64)
            menuBarHeights[id] = value
            return value
        }
        if let cached = menuBarHeights[id] { return cached }
        return min(64, max(NSStatusBar.system.thickness, screen.safeAreaInsets.top))
    }
}
