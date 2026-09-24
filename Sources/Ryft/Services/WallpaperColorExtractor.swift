import AppKit
import CoreImage

struct WallpaperColorExtractor {
    static func palette(from url: URL, basedOn base: ThemePalette) -> ThemePalette? {
        guard let image = NSImage(contentsOf: url), let data = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: data), let ci = CIImage(bitmapImageRep: bitmap) else { return nil }
        let extent = ci.extent
        guard let filter = CIFilter(name: "CIAreaAverage", parameters: [kCIInputImageKey: ci, kCIInputExtentKey: CIVector(cgRect: extent)])?.outputImage else { return nil }
        var pixel = [UInt8](repeating: 0, count: 4)
        CIContext(options: [.workingColorSpace: NSNull()]).render(filter, toBitmap: &pixel, rowBytes: 4, bounds: CGRect(x: 0, y: 0, width: 1, height: 1), format: .RGBA8, colorSpace: nil)
        let sampled = NSColor(srgbRed: CGFloat(pixel[0]) / 255, green: CGFloat(pixel[1]) / 255, blue: CGFloat(pixel[2]) / 255, alpha: 1)
        let accent = sampled.blended(withFraction: 0.28, of: .white) ?? sampled
        let background = sampled.blended(withFraction: 0.78, of: NSColor(srgbRed: 0.055, green: 0.05, blue: 0.055, alpha: 1)) ?? .black
        let surface = background.blended(withFraction: 0.12, of: accent) ?? background
        var palette = base
        palette.id = "wallpaper-adaptive"; palette.name = "Wallpaper adaptive"; palette.source = "Wallpaper color extraction"
        palette.background = background.hexString; palette.surface = surface.hexString; palette.accent = accent.hexString
        palette.muted = accent.blended(withFraction: 0.35, of: .gray)?.hexString ?? base.muted
        palette.foreground = "#E6E1E1"; palette.success = "#B5CCBA"
        return palette
    }
}
