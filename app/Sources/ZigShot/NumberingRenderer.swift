import AppKit

/// Renders numbered circle annotations into RGBA bitmaps for compositing onto the Zig pixel buffer.
/// Parallel to `TextEditingController.renderTextBitmap` — same bitmap format and coordinate conventions.
enum NumberingRenderer {

    /// Render a filled circle with a white number centered inside.
    /// Returns an RGBA bitmap (straight alpha, big-endian byte order) matching `zs_composite_rgba` expectations.
    static func renderBitmap(
        number: Int, color: NSColor, size: CGFloat = 28
    ) -> (pixels: [UInt8], width: Int, height: Int)? {
        let dim = Int(ceil(size)) + 4  // Padding for anti-aliasing
        guard dim > 0 else { return nil }

        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let ctx = CGContext(
                  data: nil,
                  width: dim,
                  height: dim,
                  bitsPerComponent: 8,
                  bytesPerRow: dim * 4,
                  space: colorSpace,
                  bitmapInfo: CGImageAlphaInfo.last.rawValue
                      | CGBitmapInfo.byteOrder32Big.rawValue
              ) else { return nil }

        // Flip for text rendering (AppKit draws text top-down)
        ctx.translateBy(x: 0, y: CGFloat(dim))
        ctx.scaleBy(x: 1, y: -1)

        let nsCtx = NSGraphicsContext(cgContext: ctx, flipped: true)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = nsCtx

        // Filled circle
        let circleRect = CGRect(
            x: CGFloat(dim) / 2 - size / 2,
            y: CGFloat(dim) / 2 - size / 2,
            width: size,
            height: size
        )
        let path = NSBezierPath(ovalIn: circleRect)
        color.setFill()
        path.fill()

        // Centered number label
        let label = NSAttributedString(
            string: "\(number)",
            attributes: [
                .font: NSFont.systemFont(ofSize: size * 0.5, weight: .bold),
                .foregroundColor: NSColor.white,
            ]
        )
        let labelSize = label.size()
        label.draw(at: CGPoint(
            x: circleRect.midX - labelSize.width / 2,
            y: circleRect.midY - labelSize.height / 2
        ))

        NSGraphicsContext.restoreGraphicsState()

        guard let data = ctx.data else { return nil }
        let buffer = UnsafeBufferPointer(
            start: data.assumingMemoryBound(to: UInt8.self),
            count: dim * dim * 4
        )
        return (Array(buffer), dim, dim)
    }
}
