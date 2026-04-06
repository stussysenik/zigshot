import ScreenCaptureKit
import CoreGraphics
import CoreImage
import AppKit

enum CaptureError: Error, LocalizedError {
    case noDisplay
    case windowNotFound
    case captureFailure
    case permissionDenied

    var errorDescription: String? {
        switch self {
        case .noDisplay: return "No display found"
        case .windowNotFound: return "Window not found"
        case .captureFailure: return "Screen capture failed"
        case .permissionDenied: return "Screen Recording permission required"
        }
    }
}

/// Handles screen capture via ScreenCaptureKit.
/// All captures produce CGImages at native Retina resolution.
final class CaptureManager {

    /// Capture the entire primary display at native resolution.
    func captureFullscreen() async throws -> CGImage {
        let content = try await SCShareableContent.excludingDesktopWindows(
            false, onScreenWindowsOnly: true
        )
        guard let display = content.displays.first else {
            throw CaptureError.noDisplay
        }

        let scaleFactor = await MainActor.run {
            NSScreen.main?.backingScaleFactor ?? 2.0
        }

        let filter = SCContentFilter(display: display, excludingWindows: [])
        let config = SCStreamConfiguration()
        config.width = Int(CGFloat(display.width) * scaleFactor)
        config.height = Int(CGFloat(display.height) * scaleFactor)
        config.pixelFormat = kCVPixelFormatType_32BGRA
        config.showsCursor = false
        config.colorSpaceName = CGColorSpace.sRGB

        return try await SCScreenshotManager.captureImage(
            contentFilter: filter, configuration: config
        )
    }

    /// Capture a specific area of the screen.
    /// The rect is in screen coordinates (pre-scale-factor).
    /// Uses ScreenCaptureKit first, then falls back to CGWindowListCreateImage
    /// which reliably captures Terminal.app and other Metal-rendered windows.
    func captureArea(_ rect: CGRect) async throws -> CGImage {
        let scaleFactor = await MainActor.run {
            NSScreen.main?.backingScaleFactor ?? 2.0
        }

        // Convert screen coordinates to pixel coordinates
        let pixelRect = CGRect(
            x: rect.origin.x * scaleFactor,
            y: rect.origin.y * scaleFactor,
            width: rect.width * scaleFactor,
            height: rect.height * scaleFactor
        )

        // Try ScreenCaptureKit first
        let fullImage = try await captureFullscreen()
        if let cropped = fullImage.cropping(to: pixelRect) {
            // Check if the captured region is mostly blank (indicates a capture failure
            // with certain windows like Terminal.app using Metal rendering)
            if !Self.isMostlyBlank(cropped) {
                return cropped
            }
        }

        // Fallback: CGWindowListCreateImage captures all windows reliably
        // including Terminal.app and other Metal-rendered content.
        // Note: CGWindowListCreateImage uses flipped coordinates (origin top-left)
        // but screen coordinates are already top-left in macOS AppKit.
        let screenRect = CGRect(
            x: rect.origin.x,
            y: rect.origin.y,
            width: rect.width,
            height: rect.height
        )
        if let cgImage = CGWindowListCreateImage(
            screenRect,
            .optionOnScreenOnly,
            kCGNullWindowID,
            [.bestResolution, .boundsIgnoreFraming]
        ) {
            return cgImage
        }

        // Last resort: return whatever SCK gave us
        if let cropped = fullImage.cropping(to: pixelRect) {
            return cropped
        }
        throw CaptureError.captureFailure
    }

    /// Check if a captured image is mostly blank (white/transparent pixels).
    /// Used to detect ScreenCaptureKit failures with certain window types.
    private static func isMostlyBlank(_ image: CGImage, threshold: Float = 0.85) -> Bool {
        let w = image.width, h = image.height
        guard w > 0, h > 0 else { return true }

        // Sample a grid of pixels rather than every pixel for performance
        let stepSize = max(1, min(w, h) / 20)
        var blankCount = 0
        var totalCount = 0

        guard let context = CGContext(
            data: nil, width: w, height: h,
            bitsPerComponent: 8, bytesPerRow: w * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
        ) else { return false }

        context.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))

        guard let data = context.data else { return false }
        let buffer = data.bindMemory(to: UInt8.self, capacity: w * h * 4)

        for y in Swift.stride(from: 0, to: h, by: stepSize) {
            for x in Swift.stride(from: 0, to: w, by: stepSize) {
                let offset = (y * w + x) * 4
                let r = buffer[offset + 1]
                let g = buffer[offset + 2]
                let b = buffer[offset + 3]
                let a = buffer[offset]
                totalCount += 1
                // Consider pixel "blank" if nearly white or fully transparent
                if a < 10 || (r > 250 && g > 250 && b > 250) {
                    blankCount += 1
                }
            }
        }

        guard totalCount > 0 else { return true }
        return Float(blankCount) / Float(totalCount) >= threshold
    }

    /// Capture a specific window by its CGWindowID.
    /// Uses ScreenCaptureKit with CGWindowListCreateImage fallback
    /// for windows that don't render correctly with SCK (e.g. Terminal.app).
    func captureWindow(_ windowID: CGWindowID) async throws -> CGImage {
        let content = try await SCShareableContent.excludingDesktopWindows(
            false, onScreenWindowsOnly: true
        )
        guard let window = content.windows.first(where: { $0.windowID == windowID }) else {
            throw CaptureError.windowNotFound
        }

        let scaleFactor = await MainActor.run {
            NSScreen.main?.backingScaleFactor ?? 2.0
        }

        // Try ScreenCaptureKit first
        let filter = SCContentFilter(desktopIndependentWindow: window)
        let config = SCStreamConfiguration()
        config.width = Int(window.frame.width * scaleFactor)
        config.height = Int(window.frame.height * scaleFactor)
        config.pixelFormat = kCVPixelFormatType_32BGRA
        config.showsCursor = false
        config.colorSpaceName = CGColorSpace.sRGB

        let sckImage = try await SCScreenshotManager.captureImage(
            contentFilter: filter, configuration: config
        )

        // If SCK captured content looks good, use it
        if !Self.isMostlyBlank(sckImage) {
            return sckImage
        }

        // Fallback: CGWindowListCreateImage for this specific window
        if let cgImage = CGWindowListCreateImage(
            .null,
            .optionIncludingWindow,
            windowID,
            [.bestResolution, .boundsIgnoreFraming]
        ) {
            return cgImage
        }

        return sckImage
    }

    /// Check if Screen Recording permission is granted.
    static func hasPermission() -> Bool {
        return CGPreflightScreenCaptureAccess()
    }

    /// Request Screen Recording permission (shows system dialog).
    static func requestPermission() {
        CGRequestScreenCaptureAccess()
    }
}
