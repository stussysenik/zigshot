import AppKit

final class AnnotationEditorWindow: NSWindow {
    var onCopy: (() -> Void)?
    var onSave: (() -> Void)?
    var onDiscard: (() -> Void)?

    init() {
        guard let screen = NSScreen.main ?? NSScreen.screens.first else {
            super.init(contentRect: .zero, styleMask: .borderless, backing: .buffered, defer: false)
            return
        }
        super.init(
            contentRect: screen.frame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        level = .floating
        isOpaque = false
        backgroundColor = NSColor.black.withAlphaComponent(0.4)
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        hasShadow = false
    }

    func present() {
        makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func dismiss() {
        orderOut(nil)
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}
