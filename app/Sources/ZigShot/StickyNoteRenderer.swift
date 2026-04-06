import AppKit

/// Renders sticky note annotations into RGBA bitmaps for compositing onto the Zig pixel buffer.
/// A sticky note is a filled rounded rectangle with wrapped text inside.
enum StickyNoteRenderer {

    /// Predefined sticky note background colors (iA Writer / Things aesthetic).
    static let noteColors: [NSColor] = [
        NSColor(red: 1.0,  green: 0.95, blue: 0.70, alpha: 0.92),  // Warm yellow
        NSColor(red: 1.0,  green: 0.85, blue: 0.85, alpha: 0.92),  // Soft pink
        NSColor(red: 0.85, green: 0.92, blue: 1.0,  alpha: 0.92),  // Light blue
        NSColor(red: 0.85, green: 1.0,  blue: 0.88, alpha: 0.92),  // Mint green
    ]

    /// Render a sticky note with rounded-rect background and wrapped text.
    static func renderBitmap(
        rect: CGRect, content: String, fontSize: CGFloat,
        backgroundColor: NSColor, textColor: NSColor,
        fontName: String? = nil, isBold: Bool = false, isItalic: Bool = false,
        alignment: NSTextAlignment = .left
    ) -> (pixels: [UInt8], width: Int, height: Int)? {
        let w = max(Int(ceil(rect.width)), 1)
        let h = max(Int(ceil(rect.height)), 1)

        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let ctx = CGContext(
                  data: nil,
                  width: w,
                  height: h,
                  bitsPerComponent: 8,
                  bytesPerRow: w * 4,
                  space: colorSpace,
                  bitmapInfo: CGImageAlphaInfo.last.rawValue
                      | CGBitmapInfo.byteOrder32Big.rawValue
              ) else { return nil }

        ctx.translateBy(x: 0, y: CGFloat(h))
        ctx.scaleBy(x: 1, y: -1)

        let nsCtx = NSGraphicsContext(cgContext: ctx, flipped: true)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = nsCtx

        let noteRect = CGRect(x: 0, y: 0, width: w, height: h)
        let cornerRadius: CGFloat = 6

        // Filled rounded rectangle background
        let bgPath = NSBezierPath(roundedRect: noteRect, xRadius: cornerRadius, yRadius: cornerRadius)
        backgroundColor.setFill()
        bgPath.fill()

        // Subtle border
        NSColor(calibratedWhite: 0.0, alpha: 0.12).setStroke()
        bgPath.lineWidth = 1
        bgPath.stroke()

        // Text inset inside the note
        let padding: CGFloat = 8
        let textRect = noteRect.insetBy(dx: padding, dy: padding)
        if !content.isEmpty {
            let paragraphStyle = NSMutableParagraphStyle()
            paragraphStyle.lineBreakMode = .byWordWrapping
            paragraphStyle.alignment = alignment

            let font = TextEditingController.resolveFont(name: fontName, size: fontSize, bold: isBold, italic: isItalic)
            let attrs: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: textColor,
                .paragraphStyle: paragraphStyle,
            ]
            let attrStr = NSAttributedString(string: content, attributes: attrs)
            attrStr.draw(with: textRect, options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine])
        }

        NSGraphicsContext.restoreGraphicsState()

        guard let data = ctx.data else { return nil }
        let buffer = UnsafeBufferPointer(
            start: data.assumingMemoryBound(to: UInt8.self),
            count: w * h * 4
        )
        return (Array(buffer), w, h)
    }
}
