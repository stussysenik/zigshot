import AppKit
import UniformTypeIdentifiers

/// Menu bar app delegate. Wires capture triggers to the capture manager.
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private let captureManager = CaptureManager()
    private let hotkeyManager = HotkeyManager()
    private var selectionOverlay: SelectionOverlay?
    private var windowPicker: WindowPicker?
    private var editorWindow: AnnotationEditorWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Check / request screen recording permission
        if !CaptureManager.hasPermission() {
            CaptureManager.requestPermission()
        }

        setupMenuBar()

        hotkeyManager.register { [weak self] action in
            self?.handleAction(action)
        }

        FontManager.loadAllFonts()
        SessionManager.pruneHistory()

        print("[ZigShot] Ready. Hotkeys: Cmd+Shift+3/4/5")
    }

    // MARK: - Menu bar

    private func setupMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            button.image = NSImage(
                systemSymbolName: "camera.viewfinder",
                accessibilityDescription: "ZigShot"
            )
        }

        let menu = NSMenu()

        let fullscreenItem = NSMenuItem(
            title: "Capture Fullscreen",
            action: #selector(captureFullscreen),
            keyEquivalent: "3"
        )
        fullscreenItem.target = self
        menu.addItem(fullscreenItem)

        let areaItem = NSMenuItem(
            title: "Capture Area",
            action: #selector(captureArea),
            keyEquivalent: "4"
        )
        areaItem.target = self
        menu.addItem(areaItem)

        let windowItem = NSMenuItem(
            title: "Capture Window",
            action: #selector(captureWindow),
            keyEquivalent: "5"
        )
        windowItem.target = self
        menu.addItem(windowItem)

        menu.addItem(.separator())

        let reopenItem = NSMenuItem(
            title: "Re-open Last Edit",
            action: #selector(reopenLastEdit),
            keyEquivalent: "l"
        )
        reopenItem.keyEquivalentModifierMask = [.command, .shift]
        reopenItem.target = self
        menu.addItem(reopenItem)

        // Recent Captures submenu
        let recentItem = NSMenuItem(title: "Recent Captures", action: nil, keyEquivalent: "")
        let recentMenu = NSMenu(title: "Recent Captures")
        recentItem.submenu = recentMenu
        menu.addItem(recentItem)

        menu.addItem(.separator())

        let prefsItem = NSMenuItem(
            title: "Preferences…",
            action: #selector(showPreferences),
            keyEquivalent: ","
        )
        prefsItem.target = self
        menu.addItem(prefsItem)

        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit ZigShot",
                     action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")

        menu.delegate = self
        statusItem.menu = menu
    }

    // MARK: - Capture actions

    private func handleAction(_ action: HotkeyManager.Action) {
        switch action {
        case .captureFullscreen: captureFullscreen()
        case .captureArea: captureArea()
        case .captureWindow: captureWindow()
        }
    }

    @objc func captureFullscreen() {
        Task {
            do {
                let cgImage = try await captureManager.captureFullscreen()
                await handleCapturedImage(cgImage)
            } catch {
                print("[ZigShot] Fullscreen capture failed: \(error)")
            }
        }
    }

    @objc func captureArea() {
        let overlay = SelectionOverlay()
        self.selectionOverlay = overlay

        overlay.show { [weak self] rect in
            guard let self = self, let rect = rect else { return }
            Task {
                do {
                    let cgImage = try await self.captureManager.captureArea(rect)
                    await self.handleCapturedImage(cgImage)
                } catch {
                    print("[ZigShot] Area capture failed: \(error)")
                }
            }
        }
    }

    @objc func captureWindow() {
        let picker = WindowPicker()
        self.windowPicker = picker

        picker.show { [weak self] windowID in
            guard let self = self, let windowID = windowID else { return }
            Task {
                do {
                    let cgImage = try await self.captureManager.captureWindow(windowID)
                    await self.handleCapturedImage(cgImage)
                } catch {
                    print("[ZigShot] Window capture failed: \(error)")
                }
            }
        }
    }

    // MARK: - Process captured image

    // MARK: - UserDefaults helpers

    private var defaultSaveDirectory: URL {
        if let path = UserDefaults.standard.string(forKey: "defaultSaveLocation") {
            return URL(fileURLWithPath: path)
        }
        return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Desktop")
    }

    private var defaultColor: NSColor {
        if let hex = UserDefaults.standard.string(forKey: "defaultColor") {
            return NSColor.from(hex: hex)
        }
        return NSColor(red: 1.0, green: 0.231, blue: 0.188, alpha: 1.0)
    }

    private var defaultStrokeWidth: UInt32 {
        let saved = UserDefaults.standard.integer(forKey: "defaultStrokeWidth")
        return saved > 0 ? UInt32(saved) : 4
    }

    @MainActor
    private func handleCapturedImage(_ cgImage: CGImage) {
        guard let originalImage = ZigShotImage.fromCGImage(cgImage) else {
            print("[ZigShot] Failed to convert captured image to Zig format")
            return
        }
        guard let workingImage = ZigShotImage(width: originalImage.width, height: originalImage.height) else {
            print("[ZigShot] Failed to allocate working image buffer")
            return
        }
        workingImage.copyPixels(from: originalImage)

        let width = workingImage.width
        let height = workingImage.height
        print("[ZigShot] Captured \(width)x\(height) — opening editor")

        openAnnotationEditor(workingImage: workingImage, originalImage: originalImage)
        SessionManager.addToHistory(originalImage: originalImage, annotations: [])
    }

    @MainActor
    private func openAnnotationEditor(workingImage: ZigShotImage, originalImage: ZigShotImage) {
        let model = AnnotationModel()
        let editorView = AnnotationEditorView(
            workingImage: workingImage,
            originalImage: originalImage,
            model: model
        )
        editorView.currentColor = defaultColor
        editorView.currentStrokeWidth = defaultStrokeWidth

        let window = AnnotationEditorWindow(
            imageWidth: Int(workingImage.width),
            imageHeight: Int(workingImage.height)
        )

        let scaleFactor = NSScreen.main?.backingScaleFactor ?? 2.0
        let dpi = 72.0 * scaleFactor
        let saveDir = defaultSaveDirectory

        window.onCopy = { [weak window, weak editorView] in
            guard let editorView = editorView else { return }
            let image = editorView.workingImage
            editorView.rerender()
            SessionManager.saveSession(originalImage: editorView.originalImage, annotations: editorView.model.annotations)
            if image.copyToClipboard() {
                print("[ZigShot] Copied to clipboard")
            }
            window?.dismiss()
        }

        window.onQuickSave = { [weak editorView] in
            guard let editorView = editorView else { return }
            let image = editorView.workingImage
            editorView.rerender()
            SessionManager.saveSession(originalImage: editorView.originalImage, annotations: editorView.model.annotations)
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd-HHmmss"
            let filename = "ZigShot-\(formatter.string(from: Date())).png"
            let url = saveDir.appendingPathComponent(filename)
            if image.savePNG(to: url, dpi: dpi) {
                print("[ZigShot] Quick-saved: \(url.path)")
            }
        }

        window.onPDF = { [weak window, weak editorView] in
            guard let editorView = editorView else { return }
            let image = editorView.workingImage
            editorView.rerender()
            SessionManager.saveSession(originalImage: editorView.originalImage, annotations: editorView.model.annotations)
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd-HHmmss"
            let filename = "ZigShot-\(formatter.string(from: Date())).pdf"
            let url = saveDir.appendingPathComponent(filename)
            if image.savePDF(to: url, dpi: dpi) {
                print("[ZigShot] Saved PDF: \(url.path)")
            }
            window?.dismiss()
        }

        window.onPNG = { [weak window, weak editorView] in
            guard let editorView = editorView else { return }
            let image = editorView.workingImage
            editorView.rerender()
            SessionManager.saveSession(originalImage: editorView.originalImage, annotations: editorView.model.annotations)
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd-HHmmss"
            let filename = "ZigShot-\(formatter.string(from: Date())).png"
            let url = saveDir.appendingPathComponent(filename)
            if image.savePNG(to: url, dpi: dpi) {
                print("[ZigShot] Quick-saved: \(url.path)")
            }
            window?.dismiss()
        }

        window.onShare = { [weak editorView] anchorView in
            guard let editorView = editorView else { return }
            editorView.rerender()
            let image = editorView.workingImage
            guard let cgImage = image.cgImage() else { return }
            let nsImage = NSImage(
                cgImage: cgImage,
                size: NSSize(width: Int(image.width), height: Int(image.height))
            )
            let picker = NSSharingServicePicker(items: [nsImage])
            picker.show(relativeTo: anchorView.bounds, of: anchorView, preferredEdge: .minY)
        }

        window.onSave = { [weak window, weak editorView] in
            guard let window = window, let editorView = editorView else { return }
            editorView.rerender()
            SessionManager.saveSession(originalImage: editorView.originalImage, annotations: editorView.model.annotations)
            let image = editorView.workingImage

            let panel = NSSavePanel()
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd-HHmmss"
            panel.nameFieldStringValue = "ZigShot-\(formatter.string(from: Date()))"
            panel.directoryURL = saveDir

            // Format picker accessory — pre-select user's default format
            let formatLabel = NSTextField(labelWithString: "Format:")
            formatLabel.font = NSFont.systemFont(ofSize: 12)
            let formatPopup = NSPopUpButton(frame: .zero, pullsDown: false)
            formatPopup.addItems(withTitles: ["PNG", "JPEG", "PDF"])
            let defaultFormat = UserDefaults.standard.string(forKey: "defaultExportFormat") ?? "PNG"
            formatPopup.selectItem(withTitle: defaultFormat)
            formatPopup.sizeToFit()

            let accessory = NSStackView(views: [formatLabel, formatPopup])
            accessory.orientation = .horizontal
            accessory.spacing = 8
            accessory.edgeInsets = NSEdgeInsets(top: 8, left: 12, bottom: 8, right: 12)
            panel.accessoryView = accessory
            panel.isExtensionHidden = false
            panel.allowedContentTypes = [.png, .jpeg, .pdf]

            panel.beginSheetModal(for: window) { response in
                guard response == .OK, let url = panel.url else { return }
                let selectedIndex = formatPopup.indexOfSelectedItem
                switch selectedIndex {
                case 1:
                    if image.saveJPEG(to: url, quality: 0.92, dpi: dpi) {
                        print("[ZigShot] Saved JPEG: \(url.path)")
                    }
                case 2:
                    if image.savePDF(to: url, dpi: dpi) {
                        print("[ZigShot] Saved PDF: \(url.path)")
                    }
                default:
                    if image.savePNG(to: url, dpi: dpi) {
                        print("[ZigShot] Saved PNG: \(url.path)")
                    }
                }
                window.dismiss()
            }
        }

        window.onDiscard = { [weak window] in
            print("[ZigShot] Discarded")
            window?.dismiss()
        }

        // Create toolbar pinned to bottom of editor view
        let toolbar = AnnotationToolbar(frame: .zero)
        toolbar.translatesAutoresizingMaskIntoConstraints = false
        editorView.addSubview(toolbar)
        editorView.toolbar = toolbar

        NSLayoutConstraint.activate([
            toolbar.leadingAnchor.constraint(equalTo: editorView.leadingAnchor),
            toolbar.trailingAnchor.constraint(equalTo: editorView.trailingAnchor),
            toolbar.bottomAnchor.constraint(equalTo: editorView.bottomAnchor),
            toolbar.heightAnchor.constraint(equalToConstant: 52),
        ])

        toolbar.onToolSelected = { [weak editorView] tool in
            editorView?.switchTool(tool)
        }
        toolbar.onColorChanged = { [weak editorView] color in
            editorView?.currentColor = color
        }
        toolbar.onWidthChanged = { [weak editorView] width in
            editorView?.currentStrokeWidth = width
        }
        toolbar.onFontSizeChanged = { [weak editorView] size in
            editorView?.currentFontSize = size
        }
        toolbar.onBoldChanged = { [weak editorView] bold in
            editorView?.currentBold = bold
        }
        toolbar.onItalicChanged = { [weak editorView] italic in
            editorView?.currentItalic = italic
        }
        toolbar.onAlignmentChanged = { [weak editorView] alignment in
            editorView?.currentAlignment = alignment
        }
        toolbar.onFontNameChanged = { [weak editorView] fontName in
            editorView?.currentFontName = fontName
        }

        // Zoom actions
        toolbar.onZoomIn = { [weak editorView] in editorView?.zoomIn() }
        toolbar.onZoomOut = { [weak editorView] in editorView?.zoomOut() }
        toolbar.onZoomToFit = { [weak editorView] in editorView?.zoomToFit() }

        // Image transform actions
        toolbar.onRotateCW = { [weak editorView] in
            editorView?.rotateImage90CW()
        }
        toolbar.onRotateCCW = { [weak editorView] in
            editorView?.rotateImage90CCW()
        }
        toolbar.onFlipH = { [weak editorView] in
            editorView?.flipImageH()
        }
        toolbar.onFlipV = { [weak editorView] in
            editorView?.flipImageV()
        }

        window.contentView = editorView

        self.editorWindow = window
        window.present()
    }

    @objc func showPreferences() {
        PreferencesWindow.show()
    }

    // MARK: - Session persistence

    @MainActor @objc func reopenLastEdit() {
        guard let session = SessionManager.loadLastSession() else {
            NSSound.beep()
            return
        }
        guard let workingImage = ZigShotImage(width: session.image.width, height: session.image.height) else { return }
        workingImage.copyPixels(from: session.image)
        openAnnotationEditor(workingImage: workingImage, originalImage: session.image)
        // Restore annotations
        if let editorView = editorWindow?.contentView as? AnnotationEditorView {
            for annotation in session.annotations {
                editorView.model.add(annotation)
            }
        }
    }

    @MainActor @objc func openHistoryEntry(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String,
              let entry = SessionManager.loadHistoryEntry(id: id) else { return }
        guard let workingImage = ZigShotImage(width: entry.image.width, height: entry.image.height) else { return }
        workingImage.copyPixels(from: entry.image)
        openAnnotationEditor(workingImage: workingImage, originalImage: entry.image)
        if let editorView = editorWindow?.contentView as? AnnotationEditorView {
            for annotation in entry.annotations {
                editorView.model.add(annotation)
            }
        }
    }
}

// MARK: - NSMenuDelegate

extension AppDelegate: NSMenuDelegate {
    func menuNeedsUpdate(_ menu: NSMenu) {
        // Find the Recent Captures submenu and populate it
        guard let recentItem = menu.items.first(where: { $0.title == "Recent Captures" }),
              let recentMenu = recentItem.submenu else { return }
        recentMenu.removeAllItems()
        let entries = SessionManager.recentCaptures(limit: 10)
        if entries.isEmpty {
            recentMenu.addItem(withTitle: "No Recent Captures", action: nil, keyEquivalent: "")
        } else {
            let formatter = DateFormatter()
            formatter.dateStyle = .short
            formatter.timeStyle = .short
            for entry in entries {
                let title = "\(entry.imageWidth)\u{00D7}\(entry.imageHeight) \u{2014} \(formatter.string(from: entry.timestamp))"
                let item = NSMenuItem(title: title, action: #selector(openHistoryEntry(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = entry.id
                if let thumb = SessionManager.thumbnailImage(for: entry.id) {
                    let scaledThumb = NSImage(size: NSSize(width: 40, height: 30))
                    scaledThumb.lockFocus()
                    thumb.draw(in: NSRect(x: 0, y: 0, width: 40, height: 30))
                    scaledThumb.unlockFocus()
                    item.image = scaledThumb
                }
                recentMenu.addItem(item)
            }
        }
    }
}
