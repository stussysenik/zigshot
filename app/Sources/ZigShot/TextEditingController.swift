import AppKit

/// Manages an inline NSTextView for the Text annotation tool.
/// Click → text field appears → type → click elsewhere to commit, Escape to cancel.
final class TextEditingController: NSObject, NSTextViewDelegate {

    private var textView: NSTextView?
    private var position: CGPoint = .zero
    private var fontSize: CGFloat = 16
    private var textColor: NSColor = .red
    private var onCommit: ((String, CGPoint, CGFloat, NSColor) -> Void)?
    private var clickMonitor: Any?

    /// Whether a text edit is currently in progress.
    var isEditing: Bool { textView != nil }

    /// Begin text editing at the given view-space position.
    /// Pass `initialText` to pre-fill for re-editing existing text annotations.
    func beginEditing(
        in parentView: NSView,
        at viewPosition: CGPoint,
        imagePosition: CGPoint,
        fontSize: CGFloat,
        color: NSColor,
        initialText: String = "",
        onCommit: @escaping (String, CGPoint, CGFloat, NSColor) -> Void
    ) {
        endEditing()

        self.position = imagePosition
        self.fontSize = fontSize
        self.textColor = color
        self.onCommit = onCommit

        let tv = NSTextView(frame: CGRect(
            x: viewPosition.x,
            y: viewPosition.y - fontSize * 0.2,
            width: 20,
            height: fontSize * 1.4
        ))
        tv.isRichText = false
        tv.font = NSFont.systemFont(ofSize: fontSize)
        tv.textColor = color
        tv.drawsBackground = false
        tv.insertionPointColor = color
        tv.isAutomaticQuoteSubstitutionEnabled = false
        tv.isAutomaticDashSubstitutionEnabled = false
        tv.delegate = self

        // Auto-resize to fit content — no wrapping, grows with text
        tv.isHorizontallyResizable = true
        tv.isVerticallyResizable = true
        tv.textContainer?.widthTracksTextView = false
        tv.textContainer?.containerSize = NSSize(
            width: CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude
        )
        tv.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        tv.minSize = NSSize(width: 20, height: fontSize * 1.3)

        if !initialText.isEmpty {
            tv.string = initialText
            tv.selectAll(nil)
        }

        parentView.addSubview(tv)
        tv.window?.makeFirstResponder(tv)

        self.textView = tv

        // Click-outside monitor: commit text when clicking outside the text view
        clickMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
            guard let self = self, let tv = self.textView else {
                self?.removeClickMonitor()
                return event
            }
            let clickPoint = tv.convert(event.locationInWindow, from: nil)
            if !tv.bounds.contains(clickPoint) {
                self.endEditing()
            }
            return event
        }
    }

    /// Commit current text and remove the text view.
    func endEditing() {
        removeClickMonitor()
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
        removeClickMonitor()
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
        // Return/Enter commits the text (instead of inserting newline)
        if commandSelector == #selector(NSResponder.insertNewline(_:)) {
            endEditing()
            return true
        }
        return false
    }

    // MARK: - Private

    private func removeClickMonitor() {
        if let monitor = clickMonitor {
            NSEvent.removeMonitor(monitor)
            clickMonitor = nil
        }
    }

    /// Render text into an RGBA bitmap for compositing onto the Zig pixel buffer.
    static func renderTextBitmap(
        text: String, fontSize: CGFloat, color: NSColor,
        fontName: String? = nil, isBold: Bool = false, isItalic: Bool = false,
        alignment: NSTextAlignment = .left
    ) -> (pixels: [UInt8], width: Int, height: Int)? {
        let font = Self.resolveFont(name: fontName, size: fontSize, bold: isBold, italic: isItalic)
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = alignment
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: color,
            .paragraphStyle: paragraphStyle,
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

    /// Resolve a font from name/bold/italic parameters.
    static func resolveFont(name: String?, size: CGFloat, bold: Bool, italic: Bool) -> NSFont {
        var traits: NSFontTraitMask = []
        if bold { traits.insert(.boldFontMask) }
        if italic { traits.insert(.italicFontMask) }

        if let fontName = name, let baseFont = NSFont(name: fontName, size: size) {
            if traits.isEmpty { return baseFont }
            let converted = NSFontManager.shared.convert(baseFont, toHaveTrait: traits)
            return converted
        }

        // System font
        let base: NSFont = bold
            ? NSFont.systemFont(ofSize: size, weight: .bold)
            : NSFont.systemFont(ofSize: size)
        if italic {
            let converted = NSFontManager.shared.convert(base, toHaveTrait: .italicFontMask)
            return converted
        }
        return base
    }
}
