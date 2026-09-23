import AppKit
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

/// Captures one in-memory JPEG only after the explicit Command+M action. The
/// bytes are passed directly to Gemini and are never written to disk.
enum ScreenQuestionCaptureService {
    static func capture() -> Result<Data, Error> {
        // Do not call CGRequestScreenCaptureAccess here. Command+M should never
        // repeat a system prompt when TCC already has a decision. A direct,
        // non-interactive capture also recovers when preflight is briefly stale.
        guard let image = focusedWindowImage() ?? focusedDisplayID().flatMap({ CGDisplayCreateImage($0) }) else {
            UserDefaults.standard.set(false, forKey: "RyftVerifiedScreenRecording")
            let message = CGPreflightScreenCaptureAccess()
                ? "Ryft could not capture the current display."
                : "Review Screen Recording in General Settings, then press Command+M again."
            return .failure(NSError(domain: "Ryft.ScreenCapture", code: 1, userInfo: [NSLocalizedDescriptionKey: message]))
        }
        guard let data = jpegData(from: image, maximumDimension: 2_880) else {
            return .failure(NSError(domain: "Ryft.ScreenCapture", code: 2, userInfo: [NSLocalizedDescriptionKey: "Ryft could not encode the current display."]))
        }
        UserDefaults.standard.set(true, forKey: "RyftVerifiedScreenRecording")
        return .success(data)
    }

    private static func focusedWindowInfo() -> [CFString: Any]? {
        guard let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier,
              let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[CFString: Any]] else { return nil }
        return windows.first(where: { info in
            guard (info[kCGWindowOwnerPID] as? NSNumber)?.int32Value == pid,
                  (info[kCGWindowLayer] as? NSNumber)?.intValue == 0,
                  let bounds = info[kCGWindowBounds] as? NSDictionary,
                  let frame = CGRect(dictionaryRepresentation: bounds) else { return false }
            return frame.width >= 160 && frame.height >= 120
        })
    }

    private static func focusedWindowImage() -> CGImage? {
        guard let info = focusedWindowInfo(),
              let number = (info[kCGWindowNumber] as? NSNumber)?.uint32Value else { return nil }
        return CGWindowListCreateImage(.null, .optionIncludingWindow, CGWindowID(number), [.boundsIgnoreFraming, .bestResolution])
    }

    private static func focusedDisplayID() -> CGDirectDisplayID? {
        if let info = focusedWindowInfo(),
           let bounds = info[kCGWindowBounds] as? NSDictionary,
           let window = CGRect(dictionaryRepresentation: bounds) {
            var display = CGDirectDisplayID()
            var count: UInt32 = 0
            if CGGetDisplaysWithPoint(CGPoint(x: window.midX, y: window.midY), 1, &display, &count) == .success, count > 0 { return display }
        }
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first(where: { NSMouseInRect(mouse, $0.frame, false) }) ?? NSScreen.main
        return (screen?.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
    }

    private static func jpegData(from image: CGImage, maximumDimension: CGFloat) -> Data? {
        let scale = min(1, maximumDimension / max(CGFloat(image.width), CGFloat(image.height)))
        let width = max(1, Int((CGFloat(image.width) * scale).rounded()))
        let height = max(1, Int((CGFloat(image.height) * scale).rounded()))
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                data: nil,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width * 4,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
              ) else { return nil }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let resized = context.makeImage() else { return nil }
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, resized, [kCGImageDestinationLossyCompressionQuality: 0.9] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return data as Data
    }
}
