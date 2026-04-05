import AppKit

/// Menu bar app delegate. Wires capture triggers to the capture manager.
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private let captureManager = CaptureManager()
    private let hotkeyManager = HotkeyManager()
    private var selectionOverlay: SelectionOverlay?
    private var windowPicker: WindowPicker?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Check / request screen recording permission
        if !CaptureManager.hasPermission() {
            CaptureManager.requestPermission()
        }

        setupMenuBar()

        hotkeyManager.register { [weak self] action in
            self?.handleAction(action)
        }

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
        menu.addItem(withTitle: "Quit ZigShot",
                     action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")

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

    @MainActor
    private func handleCapturedImage(_ cgImage: CGImage) {
        guard let zigImage = ZigShotImage.fromCGImage(cgImage) else {
            print("[ZigShot] Failed to convert captured image to Zig format")
            return
        }

        let width = zigImage.width
        let height = zigImage.height
        print("[ZigShot] Captured \(width)x\(height)")

        // Save to Desktop with timestamp
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd-HHmmss"
        let filename = "ZigShot-\(formatter.string(from: Date())).png"
        let desktopURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Desktop")
            .appendingPathComponent(filename)

        let scaleFactor = NSScreen.main?.backingScaleFactor ?? 2.0
        let dpi = 72.0 * scaleFactor
        if zigImage.savePNG(to: desktopURL, dpi: dpi) {
            print("[ZigShot] Saved: \(desktopURL.path)")
        }

        // Copy to clipboard
        if zigImage.copyToClipboard() {
            print("[ZigShot] Copied to clipboard")
        }
    }
}
