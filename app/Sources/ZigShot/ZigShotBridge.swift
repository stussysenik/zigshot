import Foundation
import AppKit
import CZigShot

/// Swift wrapper around libzigshot's C API.
/// Provides memory-safe, Swifty interface to Zig image processing.
final class ZigShotImage {
    private let handle: OpaquePointer

    var width: UInt32 { zs_image_get_width(handle) }
    var height: UInt32 { zs_image_get_height(handle) }
    var stride: UInt32 { zs_image_get_stride(handle) }
    var pixels: UnsafeMutablePointer<UInt8> { zs_image_get_pixels(handle) }

    // MARK: - Lifecycle

    /// Create from raw RGBA pixel buffer (copies the data).
    init?(pixels: UnsafePointer<UInt8>, width: UInt32, height: UInt32, stride: UInt32) {
        guard let h = zs_image_create(pixels, width, height, stride) else { return nil }
        self.handle = h
    }

    /// Create empty image.
    init?(width: UInt32, height: UInt32) {
        guard let h = zs_image_create_empty(width, height) else { return nil }
        self.handle = h
    }

    /// Create from CGImage (renders into RGBA buffer, copies to Zig).
    static func fromCGImage(_ cgImage: CGImage) -> ZigShotImage? {
        let width = cgImage.width
        let height = cgImage.height
        let bytesPerRow = width * 4

        let rawData = UnsafeMutablePointer<UInt8>.allocate(capacity: bytesPerRow * height)
        defer { rawData.deallocate() }

        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                  data: rawData,
                  width: width,
                  height: height,
                  bitsPerComponent: 8,
                  bytesPerRow: bytesPerRow,
                  space: colorSpace,
                  bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
                      | CGBitmapInfo.byteOrder32Big.rawValue
              ) else { return nil }

        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: CGFloat(width), height: CGFloat(height)))

        return ZigShotImage(
            pixels: rawData,
            width: UInt32(width),
            height: UInt32(height),
            stride: UInt32(bytesPerRow)
        )
    }

    deinit {
        zs_image_destroy(handle)
    }

    // MARK: - Annotations

    func drawArrow(from: CGPoint, to: CGPoint, color: NSColor, width: UInt32 = 3) {
        zs_annotate_arrow(handle,
            Int32(from.x), Int32(from.y),
            Int32(to.x), Int32(to.y),
            color.zigColor, width)
    }

    func drawRect(_ rect: CGRect, color: NSColor, width: UInt32 = 2, filled: Bool = false) {
        zs_annotate_rect(handle,
            Int32(rect.origin.x), Int32(rect.origin.y),
            UInt32(rect.width), UInt32(rect.height),
            color.zigColor, width, filled)
    }

    @discardableResult
    func blur(_ rect: CGRect, radius: UInt32 = 10) -> Bool {
        return zs_annotate_blur(handle,
            Int32(rect.origin.x), Int32(rect.origin.y),
            UInt32(rect.width), UInt32(rect.height), radius)
    }

    func highlight(_ rect: CGRect, color: NSColor) {
        zs_annotate_highlight(handle,
            Int32(rect.origin.x), Int32(rect.origin.y),
            UInt32(rect.width), UInt32(rect.height),
            color.zigColor)
    }

    func drawLine(from: CGPoint, to: CGPoint, color: NSColor, width: UInt32 = 2) {
        zs_annotate_line(handle,
            Int32(from.x), Int32(from.y),
            Int32(to.x), Int32(to.y),
            color.zigColor, width)
    }

    func drawRuler(from: CGPoint, to: CGPoint, color: NSColor, width: UInt32 = 1) -> Double {
        return zs_annotate_ruler(handle,
            Int32(from.x), Int32(from.y),
            Int32(to.x), Int32(to.y),
            color.zigColor, width)
    }

    func drawEllipse(_ rect: CGRect, color: NSColor, width: UInt32 = 2) {
        zs_annotate_ellipse(handle,
            Int32(rect.origin.x), Int32(rect.origin.y),
            UInt32(rect.width), UInt32(rect.height),
            color.zigColor, width)
    }

    // MARK: - Export (via ImageIO)

    /// Convert to CGImage for display or saving.
    func cgImage() -> CGImage? {
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        guard let context = CGContext(
            data: pixels,
            width: Int(width),
            height: Int(height),
            bitsPerComponent: 8,
            bytesPerRow: Int(stride),
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
                | CGBitmapInfo.byteOrder32Big.rawValue
        ) else { return nil }
        return context.makeImage()
    }

    /// Save as PNG with DPI metadata and sRGB ICC profile.
    func savePNG(to url: URL, dpi: CGFloat = 144) -> Bool {
        guard let cgImage = cgImage() else { return false }
        guard let dest = CGImageDestinationCreateWithURL(
            url as CFURL, "public.png" as CFString, 1, nil
        ) else { return false }

        let properties: [CFString: Any] = [
            kCGImagePropertyDPIWidth: dpi,
            kCGImagePropertyDPIHeight: dpi,
            kCGImagePropertyHasAlpha: true,
        ]
        CGImageDestinationAddImage(dest, cgImage, properties as CFDictionary)
        return CGImageDestinationFinalize(dest)
    }

    /// Save as JPEG with quality and DPI metadata.
    func saveJPEG(to url: URL, quality: CGFloat = 0.92, dpi: CGFloat = 144) -> Bool {
        guard let cgImage = cgImage() else { return false }
        guard let dest = CGImageDestinationCreateWithURL(
            url as CFURL, "public.jpeg" as CFString, 1, nil
        ) else { return false }

        let properties: [CFString: Any] = [
            kCGImageDestinationLossyCompressionQuality: quality,
            kCGImagePropertyDPIWidth: dpi,
            kCGImagePropertyDPIHeight: dpi,
        ]
        CGImageDestinationAddImage(dest, cgImage, properties as CFDictionary)
        return CGImageDestinationFinalize(dest)
    }

    /// Copy to clipboard as PNG.
    func copyToClipboard() -> Bool {
        guard let cgImage = cgImage() else { return false }
        let rep = NSBitmapImageRep(cgImage: cgImage)
        guard let pngData = rep.representation(using: .png, properties: [:]) else { return false }

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setData(pngData, forType: .png)
        return true
    }
}

// MARK: - NSColor extension

extension NSColor {
    /// Convert to 0xRRGGBBAA format for the Zig C API.
    var zigColor: UInt32 {
        guard let rgb = usingColorSpace(.sRGB) else { return 0xFF0000FF }
        let r = UInt32(rgb.redComponent * 255) & 0xFF
        let g = UInt32(rgb.greenComponent * 255) & 0xFF
        let b = UInt32(rgb.blueComponent * 255) & 0xFF
        let a = UInt32(rgb.alphaComponent * 255) & 0xFF
        return (r << 24) | (g << 16) | (b << 8) | a
    }
}
