import AppKit
import ScreenCaptureKit

/// Captures the current screen so the model can "see" what you're working on.
/// Uses ScreenCaptureKit (macOS 14+), which triggers the Screen Recording
/// permission prompt on first use.
enum ScreenContextProvider {
    /// Captures the display that currently contains the mouse cursor and returns
    /// a downscaled JPEG suitable for a vision model.
    static func captureScreenshotJPEG(maxWidth: CGFloat = 1280, quality: CGFloat = 0.6) async -> Data? {
        guard let cgImage = await captureCGImage() else { return nil }
        return jpeg(from: cgImage, maxWidth: maxWidth, quality: quality)
    }

    private static func captureCGImage() async -> CGImage? {
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(
                false, onScreenWindowsOnly: true
            )
            let mouse = NSEvent.mouseLocation
            let target = content.displays.first { display in
                NSRect(x: CGFloat(display.frame.origin.x),
                       y: CGFloat(display.frame.origin.y),
                       width: CGFloat(display.frame.width),
                       height: CGFloat(display.frame.height)).contains(mouse)
            } ?? content.displays.first

            guard let display = target else { return nil }

            let filter = SCContentFilter(display: display, excludingWindows: [])
            let config = SCStreamConfiguration()
            config.width = Int(display.width)
            config.height = Int(display.height)
            config.showsCursor = false

            return try await SCScreenshotManager.captureImage(
                contentFilter: filter, configuration: config
            )
        } catch {
            return nil
        }
    }

    private static func jpeg(from cgImage: CGImage, maxWidth: CGFloat, quality: CGFloat) -> Data? {
        let width = CGFloat(cgImage.width)
        let scale = width > maxWidth ? maxWidth / width : 1
        let targetSize = NSSize(width: width * scale, height: CGFloat(cgImage.height) * scale)

        let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(targetSize.width),
            pixelsHigh: Int(targetSize.height),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        )
        guard let rep else { return nil }
        rep.size = targetSize

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSGraphicsContext.current?.cgContext.draw(
            cgImage, in: CGRect(origin: .zero, size: targetSize)
        )
        NSGraphicsContext.restoreGraphicsState()

        return rep.representation(using: .jpeg, properties: [.compressionFactor: quality])
    }
}
