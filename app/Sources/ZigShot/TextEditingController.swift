import AppKit

/// Manages an inline NSTextView for the Text annotation tool.
/// Click → text field appears → type → click elsewhere to commit, Escape to cancel.
final class TextEditingController: NSObject, NSTextViewDelegate {

    private var textView: NSTextView?
    private var position: CGPoint = .zero
    private var fontSize: CGFloat = 16
    private var textColor: NSColor = .red
    private var onCommit: ((String, CGPoint, CGFloat, NSColor) -> Void)?

    /// Begin text editing at the given view-space position.
    func beginEditing(
        in parentView: NSView,
        at viewPosition: CGPoint,
        imagePosition: CGPoint,
        fontSize: CGFloat,
        color: NSColor,
        onCommit: @escaping (String, CGPoint, CGFloat, NSColor) -> Void
    ) {
        endEditing()

        self.position = imagePosition
        self.fontSize = fontSize
        self.textColor = color
        self.onCommit = onCommit

        let tv = NSTextView(frame: CGRect(
            x: viewPosition.x,
            y: viewPosition.y,
            width: 300,
            height: fontSize * 2
        ))
        tv.isRichText = false
        tv.font = NSFont.systemFont(ofSize: fontSize)
        tv.textColor = color
        tv.backgroundColor = NSColor.black.withAlphaComponent(0.3)
        tv.insertionPointColor = color
        tv.isAutomaticQuoteSubstitutionEnabled = false
        tv.isAutomaticDashSubstitutionEnabled = false
        tv.delegate = self

        parentView.addSubview(tv)
        tv.window?.makeFirstResponder(tv)

        self.textView = tv
    }

    /// Commit current text and remove the text view.
    func endEditing() {
        guard let tv = textView else { return }
        let text = tv.string.trimmingCharacters(in: .whitespacesAndNewlines)
        if !text.isEmpty {
            onCommit?(text, position, fontSize, textColor)
        }
        tv.removeFromSuperview()
        textView = nil
        onCommit = nil
    }

    /// Discard the current text edit without committing — triggered by Escape.
    func cancelEditing() {
        guard let tv = textView else { return }
        tv.removeFromSuperview()
        textView = nil
        onCommit = nil
    }

    // MARK: - NSTextViewDelegate

    func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
            cancelEditing()
            return true
        }
        return false
    }

    /// Render text into an RGBA bitmap for compositing onto the Zig pixel buffer.
    static func renderTextBitmap(
        text: String, fontSize: CGFloat, color: NSColor
    ) -> (pixels: [UInt8], width: Int, height: Int)? {
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: fontSize),
            .foregroundColor: color,
        ]
        let attrStr = NSAttributedString(string: text, attributes: attrs)
        let size = attrStr.size()

        let width = Int(ceil(size.width)) + 4
        let height = Int(ceil(size.height)) + 4
        guard width > 0 && height > 0 else { return nil }

        // Use straight (non-premultiplied) alpha with big-endian byte order so bytes
        // are laid out as R, G, B, A in memory on all platforms. This matches what
        // zs_composite_rgba expects: overlay[off+0]=R, +1=G, +2=B, +3=A.
        // Premultiplied alpha would cause Zig's Porter-Duff blender to double-apply
        // alpha, producing colors that are too dark.
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let ctx = CGContext(
                  data: nil,
                  width: width,
                  height: height,
                  bitsPerComponent: 8,
                  bytesPerRow: width * 4,
                  space: colorSpace,
                  bitmapInfo: CGImageAlphaInfo.last.rawValue
                      | CGBitmapInfo.byteOrder32Big.rawValue
              ) else { return nil }

        // Flip for text rendering
        ctx.translateBy(x: 0, y: CGFloat(height))
        ctx.scaleBy(x: 1, y: -1)

        let nsCtx = NSGraphicsContext(cgContext: ctx, flipped: true)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = nsCtx
        attrStr.draw(at: CGPoint(x: 2, y: 2))
        NSGraphicsContext.restoreGraphicsState()

        guard let data = ctx.data else { return nil }
        let buffer = UnsafeBufferPointer(
            start: data.assumingMemoryBound(to: UInt8.self),
            count: width * height * 4
        )
        return (Array(buffer), width, height)
    }
}
