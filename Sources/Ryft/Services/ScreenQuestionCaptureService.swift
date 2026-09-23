import AppKit
import CoreGraphics

/// Captures one in-memory JPEG only after the explicit Command+M action. The
/// bytes are passed directly to Gemini and are never written to disk.
enum ScreenQuestionCaptureService {
    static func capture() -> Result<Data, Error> {
        guard CGPreflightScreenCaptureAccess() || CGRequestScreenCaptureAccess() else {
            return .failure(NSError(
                domain: "Ryft.ScreenCapture",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Allow Screen Recording for Ryft, then press Command+M again."]
            ))
        }
        guard let displayID = focusedDisplayID(),
              let image = CGDisplayCreateImage(displayID) else {
            return .failure(NSError(domain: "Ryft.ScreenCapture", code: 2, userInfo: [NSLocalizedDescriptionKey: "Ryft could not capture the current display."]))
        }
        guard let data = jpegData(from: image, maximumDimension: 1_800) else {
            return .failure(NSError(domain: "Ryft.ScreenCapture", code: 3, userInfo: [NSLocalizedDescriptionKey: "Ryft could not prepare the screen image."]))
        }
        return .success(data)
    }

    private static func focusedDisplayID() -> CGDirectDisplayID? {
        if let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier,
           let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[CFString: Any]],
           let window = windows
            .filter({ ($0[kCGWindowOwnerPID] as? NSNumber)?.int32Value == pid && ($0[kCGWindowLayer] as? NSNumber)?.intValue == 0 })
            .compactMap({ info -> CGRect? in
                guard let bounds = info[kCGWindowBounds] as? NSDictionary else { return nil }
                return CGRect(dictionaryRepresentation: bounds)
            })
            .max(by: { $0.width * $0.height < $1.width * $1.height }) {
            var display = CGDirectDisplayID()
            var count: UInt32 = 0
            if CGGetDisplaysWithPoint(CGPoint(x: window.midX, y: window.midY), 1, &display, &count) == .success, count > 0 { return display }
        }
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first(where: { NSMouseInRect(mouse, $0.frame, false) }) ?? NSScreen.main
        return (screen?.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
    }

    private static func jpegData(from image: CGImage, maximumDimension: CGFloat) -> Data? {
        let sourceSize = CGSize(width: image.width, height: image.height)
        let scale = min(1, maximumDimension / max(sourceSize.width, sourceSize.height))
        let width = max(1, Int((sourceSize.width * scale).rounded()))
        let height = max(1, Int((sourceSize.height * scale).rounded()))
        guard let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: width,
            pixelsHigh: height,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: false,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else { return nil }
        bitmap.size = NSSize(width: width, height: height)
        NSGraphicsContext.saveGraphicsState()
        guard let context = NSGraphicsContext(bitmapImageRep: bitmap) else { NSGraphicsContext.restoreGraphicsState(); return nil }
        NSGraphicsContext.current = context
        context.imageInterpolation = .high
        NSImage(cgImage: image, size: sourceSize).draw(in: NSRect(x: 0, y: 0, width: width, height: height))
        context.flushGraphics()
        NSGraphicsContext.restoreGraphicsState()
        return bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.76])
    }
}
