import ScreenCaptureKit
import CoreGraphics
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
    func captureArea(_ rect: CGRect) async throws -> CGImage {
        let fullImage = try await captureFullscreen()

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

        guard let cropped = fullImage.cropping(to: pixelRect) else {
            throw CaptureError.captureFailure
        }
        return cropped
    }

    /// Capture a specific window by its CGWindowID.
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

        let filter = SCContentFilter(desktopIndependentWindow: window)
        let config = SCStreamConfiguration()
        config.width = Int(window.frame.width * scaleFactor)
        config.height = Int(window.frame.height * scaleFactor)
        config.pixelFormat = kCVPixelFormatType_32BGRA
        config.showsCursor = false
        config.colorSpaceName = CGColorSpace.sRGB

        return try await SCScreenshotManager.captureImage(
            contentFilter: filter, configuration: config
        )
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
