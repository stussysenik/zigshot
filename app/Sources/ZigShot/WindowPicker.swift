import ScreenCaptureKit
import AppKit

/// Presents a menu of on-screen windows for the user to pick.
final class WindowPicker: NSObject {
    private var completion: ((CGWindowID?) -> Void)?

    func show(completion: @escaping (CGWindowID?) -> Void) {
        self.completion = completion

        Task {
            do {
                let content = try await SCShareableContent.excludingDesktopWindows(
                    true, onScreenWindowsOnly: true
                )
                let windows = content.windows.filter {
                    $0.isOnScreen && $0.frame.width > 50 && $0.frame.height > 50
                }

                await MainActor.run {
                    presentMenu(windows: windows)
                }
            } catch {
                await MainActor.run { completion(nil) }
            }
        }
    }

    @MainActor
    private func presentMenu(windows: [SCWindow]) {
        let menu = NSMenu(title: "Pick a Window")

        for window in windows {
            let title = window.title ?? "Untitled"
            let appName = window.owningApplication?.applicationName ?? ""
            let label = appName.isEmpty ? title : "\(appName) — \(title)"

            let item = NSMenuItem(
                title: label,
                action: #selector(windowSelected(_:)),
                keyEquivalent: ""
            )
            item.tag = Int(window.windowID)
            item.target = self
            menu.addItem(item)
        }

        if menu.items.isEmpty {
            completion?(nil)
            return
        }

        let mouseLocation = NSEvent.mouseLocation
        menu.popUp(positioning: nil, at: mouseLocation, in: nil)
    }

    @objc private func windowSelected(_ sender: NSMenuItem) {
        completion?(CGWindowID(sender.tag))
        completion = nil
    }
}
