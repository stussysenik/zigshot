import AppKit

let app = NSApplication.shared
app.setActivationPolicy(.accessory) // Menu bar app, no Dock icon

let delegate = AppDelegate()
app.delegate = delegate
app.run()
