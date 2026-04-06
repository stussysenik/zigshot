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
    /// Expose the opaque handle for direct C API calls (used by EditorView).
    var opaqueHandle: OpaquePointer { handle }

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

        // CGBitmapContext.draw() stores the CGImage data top-down in the buffer:
        // rawData[0] = top-left pixel. This matches Zig's top-left origin convention
        // directly — no row-flip needed.

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

    // MARK: - Pixel operations

    /// Copy all pixels from another image into this one (same dimensions required).
    /// Used by undo system to reset to original capture before replaying annotations.
    @discardableResult
    func copyPixels(from source: ZigShotImage) -> Bool {
        return zs_image_copy_pixels(handle, source.opaqueHandle)
    }

    /// Composite an RGBA bitmap onto this image at the given position.
    /// Used for overlaying Swift-rendered text onto the Zig pixel buffer.
    func compositeRGBA(_ pixels: UnsafePointer<UInt8>, width: UInt32, height: UInt32,
                       stride: UInt32, at x: Int32, y: Int32) {
        zs_composite_rgba(handle, pixels, width, height, stride, x, y)
    }

    // MARK: - Image transforms

    /// Create a new image cropped to the given rect (image pixel coordinates).
    static func cropped(from source: ZigShotImage, rect: CGRect) -> ZigShotImage? {
        let x = max(0, Int(rect.origin.x))
        let y = max(0, Int(rect.origin.y))
        let w = min(Int(rect.width), Int(source.width) - x)
        let h = min(Int(rect.height), Int(source.height) - y)
        guard w > 0, h > 0 else { return nil }

        guard let newImage = ZigShotImage(width: UInt32(w), height: UInt32(h)) else { return nil }
        let srcStride = Int(source.stride)
        let dstStride = Int(newImage.stride)
        let srcPixels = source.pixels
        let dstPixels = newImage.pixels

        for row in 0 ..< h {
            let srcOffset = (y + row) * srcStride + x * 4
            let dstOffset = row * dstStride
            dstPixels.advanced(by: dstOffset)
                .update(from: srcPixels.advanced(by: srcOffset), count: w * 4)
        }
        return newImage
    }

    /// Create a new image rotated 90° clockwise.
    static func rotated90CW(from source: ZigShotImage) -> ZigShotImage? {
        let srcW = Int(source.width), srcH = Int(source.height)
        let srcStride = Int(source.stride)
        guard let newImage = ZigShotImage(width: UInt32(srcH), height: UInt32(srcW)) else { return nil }
        let dstStride = Int(newImage.stride)
        let src = source.pixels, dst = newImage.pixels

        for y in 0 ..< srcH {
            for x in 0 ..< srcW {
                let srcOff = y * srcStride + x * 4
                let dstOff = x * dstStride + (srcH - 1 - y) * 4
                dst[dstOff + 0] = src[srcOff + 0]
                dst[dstOff + 1] = src[srcOff + 1]
                dst[dstOff + 2] = src[srcOff + 2]
                dst[dstOff + 3] = src[srcOff + 3]
            }
        }
        return newImage
    }

    /// Create a new image rotated 90° counter-clockwise.
    static func rotated90CCW(from source: ZigShotImage) -> ZigShotImage? {
        let srcW = Int(source.width), srcH = Int(source.height)
        let srcStride = Int(source.stride)
        guard let newImage = ZigShotImage(width: UInt32(srcH), height: UInt32(srcW)) else { return nil }
        let dstStride = Int(newImage.stride)
        let src = source.pixels, dst = newImage.pixels

        for y in 0 ..< srcH {
            for x in 0 ..< srcW {
                let srcOff = y * srcStride + x * 4
                let dstOff = (srcW - 1 - x) * dstStride + y * 4
                dst[dstOff + 0] = src[srcOff + 0]
                dst[dstOff + 1] = src[srcOff + 1]
                dst[dstOff + 2] = src[srcOff + 2]
                dst[dstOff + 3] = src[srcOff + 3]
            }
        }
        return newImage
    }

    /// Create a new image flipped horizontally (mirror left↔right).
    static func flippedH(from source: ZigShotImage) -> ZigShotImage? {
        let w = Int(source.width), h = Int(source.height)
        let srcStride = Int(source.stride)
        guard let newImage = ZigShotImage(width: source.width, height: source.height) else { return nil }
        let dstStride = Int(newImage.stride)
        let src = source.pixels, dst = newImage.pixels

        for y in 0 ..< h {
            for x in 0 ..< w {
                let srcOff = y * srcStride + x * 4
                let dstOff = y * dstStride + (w - 1 - x) * 4
                dst[dstOff + 0] = src[srcOff + 0]
                dst[dstOff + 1] = src[srcOff + 1]
                dst[dstOff + 2] = src[srcOff + 2]
                dst[dstOff + 3] = src[srcOff + 3]
            }
        }
        return newImage
    }

    /// Create a new image flipped vertically (mirror top↔bottom).
    static func flippedV(from source: ZigShotImage) -> ZigShotImage? {
        let w = Int(source.width), h = Int(source.height)
        let srcStride = Int(source.stride)
        guard let newImage = ZigShotImage(width: source.width, height: source.height) else { return nil }
        let dstStride = Int(newImage.stride)
        let src = source.pixels, dst = newImage.pixels

        for y in 0 ..< h {
            let srcRow = src.advanced(by: y * srcStride)
            let dstRow = dst.advanced(by: (h - 1 - y) * dstStride)
            dstRow.update(from: srcRow, count: w * 4)
        }
        return newImage
    }

    // MARK: - Export (via ImageIO)

    /// Convert to CGImage for display or saving.
    /// Uses a data provider that references the live pixel buffer (zero-copy).
    /// The buffer is top-down (row 0 = top of image), matching CGImage's
    /// expected data layout from a data provider.
    ///
    /// Safety: The data provider retains `self` to prevent the Zig pixel
    /// buffer from being freed while the CGImage is alive. The returned
    /// CGImage must only be used from the main thread (the pixel buffer
    /// is mutated by annotation rendering on the main thread).
    func cgImage() -> CGImage? {
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        let bitmapInfo = CGImageAlphaInfo.noneSkipLast.rawValue
            | CGBitmapInfo.byteOrder32Big.rawValue

        let retainedSelf = Unmanaged.passRetained(self)
        guard let provider = CGDataProvider(
            dataInfo: retainedSelf.toOpaque(),
            data: pixels,
            size: Int(stride) * Int(height),
            releaseData: { info, _, _ in
                if let info { Unmanaged<ZigShotImage>.fromOpaque(info).release() }
            }
        ) else {
            retainedSelf.release()
            return nil
        }

        return CGImage(
            width: Int(width),
            height: Int(height),
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: Int(stride),
            space: colorSpace,
            bitmapInfo: CGBitmapInfo(rawValue: bitmapInfo),
            provider: provider,
            decode: nil,
            shouldInterpolate: true,
            intent: .defaultIntent
        )
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

    /// Save as single-page PDF via Quartz PDFContext.
    func savePDF(to url: URL, dpi: CGFloat = 144) -> Bool {
        guard let cgImage = cgImage() else { return false }
        let scaleFactor = dpi / 72.0
        let pageWidth = CGFloat(width) / scaleFactor
        let pageHeight = CGFloat(height) / scaleFactor
        var mediaBox = CGRect(x: 0, y: 0, width: pageWidth, height: pageHeight)
        guard let pdfContext = CGContext(url as CFURL, mediaBox: &mediaBox, nil) else { return false }
        pdfContext.beginPage(mediaBox: &mediaBox)
        pdfContext.draw(cgImage, in: mediaBox)
        pdfContext.endPage()
        pdfContext.closePDF()
        return true
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
