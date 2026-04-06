import AppKit

/// A Shottr-style annotation editor window with standard macOS chrome.
///
/// Presents a titled, resizable window sized to fit the captured image, with
/// action buttons (PNG, Save, Copy) embedded in the trailing end of the title bar
/// via NSTitlebarAccessoryViewController.
final class AnnotationEditorWindow: NSWindow {
    var onCopy: (() -> Void)?
    var onSave: (() -> Void)?
    var onQuickSave: (() -> Void)?
    var onPDF: (() -> Void)?
    var onPNG: (() -> Void)?
    var onShare: ((NSView) -> Void)?
    var onDiscard: (() -> Void)?

    /// The share button stored for popover anchoring (e.g. from keyboard shortcut).
    private(set) var shareButton: NSButton?

    // MARK: - Init

    /// Creates a window sized to fit `imageWidth` × `imageHeight`, scaled to
    /// occupy at most 80 % of the main screen, with extra room for the toolbar
    /// (60 px) and standard title bar.
    init(imageWidth: Int, imageHeight: Int) {
        let contentRect = Self.contentRect(imageWidth: imageWidth, imageHeight: imageHeight)

        super.init(
            contentRect: contentRect,
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )

        // Blend the title bar into the light warm-gray content area.
        titlebarAppearsTransparent = true
        // We render our own centered title label rather than using the system title.
        titleVisibility = .hidden
        // Disabled: was causing the entire window to move when clicking on the
        // canvas background because AnnotationEditorView only consumes clicks
        // inside imageRect, letting uncaught events bubble to the window drag handler.
        isMovableByWindowBackground = false

        backgroundColor = NSColor(calibratedWhite: 0.94, alpha: 1.0)
        hasShadow = true

        center()
        setupTitleBar(imageWidth: imageWidth, imageHeight: imageHeight)
    }

    // MARK: - Title Bar

    /// Installs a centered title label and trailing action buttons into the title bar.
    func setupTitleBar(imageWidth: Int, imageHeight: Int) {
        // Centered title — placed as the window title so it sits naturally in
        // the title bar area without fighting the system layout.
        title = "Screenshot \u{2014} \(imageWidth) \u{00D7} \(imageHeight)"
        titleVisibility = .visible   // Let the system render the centred string …

        // … but we still want the transparent look, so we keep the flag set.
        titlebarAppearsTransparent = true

        // Trailing accessory: PDF · PNG · Save · Share · Copy
        let accessoryVC = makeTrailingAccessory()
        addTitlebarAccessoryViewController(accessoryVC)
    }

    // MARK: - Present / Dismiss

    func present() {
        makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func dismiss() {
        orderOut(nil)
    }

    // MARK: - Key / Main

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    // MARK: - Private helpers

    /// Computes the content rect (excludes title bar) for the given image dimensions.
    private static func contentRect(imageWidth: Int, imageHeight: Int) -> NSRect {
        let screen = NSScreen.main ?? NSScreen.screens.first
        let screenFrame = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1280, height: 800)

        let maxWidth  = screenFrame.width  * 0.80
        let maxHeight = screenFrame.height * 0.80

        let toolbarHeight: CGFloat = 60

        // Scale image down to fit within the 80 % envelope while keeping aspect ratio.
        let imgW = CGFloat(imageWidth)
        let imgH = CGFloat(imageHeight)
        let availableHeight = maxHeight - toolbarHeight

        let scale = min(maxWidth / imgW, availableHeight / imgH, 1.0)

        let windowWidth  = max(imgW * scale, 480)
        let windowHeight = max(imgH * scale + toolbarHeight, 320)

        let x = screenFrame.minX + (screenFrame.width  - windowWidth)  / 2
        let y = screenFrame.minY + (screenFrame.height - windowHeight) / 2

        return NSRect(x: x, y: y, width: windowWidth, height: windowHeight)
    }

    /// Builds the NSTitlebarAccessoryViewController that sits on the trailing
    /// edge of the title bar, containing PDF · PNG · Save · Share · Copy buttons.
    private func makeTrailingAccessory() -> NSTitlebarAccessoryViewController {
        let vc = NSTitlebarAccessoryViewController()
        vc.layoutAttribute = .trailing

        // Container view — zero height; the title bar sizes itself.
        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false

        // --- PDF button ---
        let pdfButton = makeSubtleButton(title: "PDF")
        pdfButton.target = self
        pdfButton.action = #selector(pdfTapped)

        // --- PNG button ---
        let pngButton = makeSubtleButton(title: "PNG")
        pngButton.target = self
        pngButton.action = #selector(pngTapped)

        // --- Save button ---
        let saveButton = makeSubtleButton(title: "Save")
        saveButton.target = self
        saveButton.action = #selector(saveTapped)

        // --- Share button ---
        let shareBtn = makeSubtleButton(title: "Share")
        shareBtn.target = self
        shareBtn.action = #selector(shareTapped)
        self.shareButton = shareBtn

        // --- Copy button (dark filled) ---
        let copyButton = makePrimaryButton(title: "Copy")
        copyButton.target = self
        copyButton.action = #selector(copyTapped)

        // Horizontal stack
        let stack = NSStackView(views: [pdfButton, pngButton, saveButton, shareBtn, copyButton])
        stack.orientation = .horizontal
        stack.spacing = 8
        stack.alignment = .centerY
        stack.translatesAutoresizingMaskIntoConstraints = false

        container.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 8),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -8),
            container.heightAnchor.constraint(equalToConstant: 32),
        ])

        vc.view = container
        return vc
    }

    /// A borderless text button — used for "PNG" and "Save".
    private func makeSubtleButton(title: String) -> NSButton {
        let button = NSButton(title: title, target: nil, action: nil)
        button.bezelStyle = .inline
        button.isBordered = false
        button.font = NSFont.systemFont(ofSize: 13, weight: .regular)
        button.contentTintColor = NSColor.secondaryLabelColor
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }

    /// A dark filled rounded-rect button — used for "Copy".
    private func makePrimaryButton(title: String) -> NSButton {
        let button = NSButton(title: title, target: nil, action: nil)
        button.bezelStyle = .rounded
        button.isBordered = true
        button.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        button.translatesAutoresizingMaskIntoConstraints = false

        // Dark appearance so the button appears filled even in light mode.
        button.appearance = NSAppearance(named: .darkAqua)

        NSLayoutConstraint.activate([
            button.widthAnchor.constraint(greaterThanOrEqualToConstant: 60),
        ])

        return button
    }

    // MARK: - Actions

    @objc private func pdfTapped() {
        onPDF?()
    }

    @objc private func pngTapped() {
        onPNG?()
    }

    @objc private func saveTapped() {
        onSave?()
    }

    @objc private func shareTapped() {
        if let btn = shareButton {
            onShare?(btn)
        }
    }

    @objc private func copyTapped() {
        onCopy?()
    }
}
