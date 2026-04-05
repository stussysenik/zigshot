import AppKit

/// Fullscreen overlay for area selection.
/// Shows a semi-transparent dark layer over the screen. User drags to
/// select a rectangle. Displays live dimensions. ESC to cancel.
final class SelectionOverlay {
    private var window: NSWindow?
    private var completion: ((CGRect?) -> Void)?

    func show(completion: @escaping (CGRect?) -> Void) {
        self.completion = completion

        guard let screen = NSScreen.main else {
            completion(nil)
            return
        }

        let window = NSWindow(
            contentRect: screen.frame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        window.level = .screenSaver
        window.isOpaque = false
        window.backgroundColor = .clear
        window.ignoresMouseEvents = false
        window.hasShadow = false
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        let overlayView = SelectionView { [weak self] rect in
            self?.window?.orderOut(nil)
            self?.window = nil
            self?.completion?(rect)
        }
        window.contentView = overlayView
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(overlayView)
        NSApp.activate(ignoringOtherApps: true)

        self.window = window
    }

    func cancel() {
        window?.orderOut(nil)
        window = nil
        completion?(nil)
    }
}

// MARK: - SelectionView

private final class SelectionView: NSView {
    private var startPoint: NSPoint?
    private var currentPoint: NSPoint?
    private let onComplete: (CGRect?) -> Void

    init(onComplete: @escaping (CGRect?) -> Void) {
        self.onComplete = onComplete
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        NSCursor.crosshair.push()
    }

    override func mouseDown(with event: NSEvent) {
        startPoint = convert(event.locationInWindow, from: nil)
        currentPoint = startPoint
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        currentPoint = convert(event.locationInWindow, from: nil)
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        NSCursor.pop()
        guard let start = startPoint, let end = currentPoint else {
            onComplete(nil)
            return
        }

        let rect = CGRect(
            x: min(start.x, end.x),
            y: min(start.y, end.y),
            width: abs(end.x - start.x),
            height: abs(end.y - start.y)
        )

        // Minimum selection size (ignore accidental clicks)
        if rect.width < 3 || rect.height < 3 {
            onComplete(nil)
        } else {
            onComplete(rect)
        }
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { // Escape
            NSCursor.pop()
            onComplete(nil)
        }
    }

    override var acceptsFirstResponder: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        // Dark overlay over entire screen
        NSColor.black.withAlphaComponent(0.3).setFill()
        bounds.fill()

        guard let start = startPoint, let current = currentPoint else { return }

        let selectionRect = CGRect(
            x: min(start.x, current.x),
            y: min(start.y, current.y),
            width: abs(current.x - start.x),
            height: abs(current.y - start.y)
        )

        // Clear the selection area (punch a hole in the overlay)
        NSColor.clear.setFill()
        selectionRect.fill(using: .copy)

        // White border around selection
        NSColor.white.setStroke()
        let path = NSBezierPath(rect: selectionRect)
        path.lineWidth = 1.5
        path.stroke()

        // Dimensions label
        let sizeText = "\(Int(selectionRect.width)) x \(Int(selectionRect.height))"
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 12, weight: .medium),
            .foregroundColor: NSColor.white,
            .backgroundColor: NSColor.black.withAlphaComponent(0.7),
        ]
        let label = NSAttributedString(string: " \(sizeText) ", attributes: attrs)
        let labelOrigin = CGPoint(
            x: selectionRect.midX - label.size().width / 2,
            y: selectionRect.maxY + 4
        )
        label.draw(at: labelOrigin)
    }
}
