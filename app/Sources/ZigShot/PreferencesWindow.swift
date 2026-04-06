import AppKit

/// Preferences window with tabs: General, Shortcuts, Fonts.
/// Accessible via Cmd+, from the menu bar.
final class PreferencesWindow: NSWindow {

    private static var shared: PreferencesWindow?

    /// Show the preferences window (singleton).
    static func show() {
        if let existing = shared {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let window = PreferencesWindow()
        shared = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 400),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        title = "ZigShot Preferences"
        isReleasedWhenClosed = false
        center()
        setupTabs()
    }

    // MARK: - Tabs

    private func setupTabs() {
        let tabView = NSTabView(frame: .zero)
        tabView.translatesAutoresizingMaskIntoConstraints = false

        tabView.addTabViewItem(makeGeneralTab())
        tabView.addTabViewItem(makeShortcutsTab())
        tabView.addTabViewItem(makeFontsTab())

        contentView = tabView
    }

    // MARK: - General Tab

    private func makeGeneralTab() -> NSTabViewItem {
        let item = NSTabViewItem(identifier: "general")
        item.label = "General"

        let container = NSView()

        // Default export format
        let formatLabel = NSTextField(labelWithString: "Default export format:")
        formatLabel.font = NSFont.systemFont(ofSize: 13, weight: .medium)
        let formatPopup = NSPopUpButton(frame: .zero, pullsDown: false)
        formatPopup.addItems(withTitles: ["PNG", "JPEG", "PDF"])
        let savedFormat = UserDefaults.standard.string(forKey: "defaultExportFormat") ?? "PNG"
        formatPopup.selectItem(withTitle: savedFormat)
        formatPopup.target = self
        formatPopup.action = #selector(formatChanged(_:))

        // Default save location
        let locationLabel = NSTextField(labelWithString: "Default save location:")
        locationLabel.font = NSFont.systemFont(ofSize: 13, weight: .medium)
        let locationButton = NSButton(title: currentSaveLocation(), target: self, action: #selector(changeSaveLocation(_:)))
        locationButton.bezelStyle = .rounded

        // Default color
        let colorLabel = NSTextField(labelWithString: "Default annotation color:")
        colorLabel.font = NSFont.systemFont(ofSize: 13, weight: .medium)
        let colorWell = NSColorWell(frame: NSRect(x: 0, y: 0, width: 44, height: 24))
        colorWell.color = defaultColor()
        colorWell.target = self
        colorWell.action = #selector(colorChanged(_:))
        if #available(macOS 13.0, *) {
            colorWell.colorWellStyle = .minimal
        }

        // Default stroke width
        let widthLabel = NSTextField(labelWithString: "Default stroke width:")
        widthLabel.font = NSFont.systemFont(ofSize: 13, weight: .medium)
        let widthSlider = NSSlider(value: Double(UserDefaults.standard.integer(forKey: "defaultStrokeWidth") == 0 ? 4 : UserDefaults.standard.integer(forKey: "defaultStrokeWidth")),
                                    minValue: 1, maxValue: 20,
                                    target: self, action: #selector(widthChanged(_:)))
        widthSlider.numberOfTickMarks = 20
        widthSlider.allowsTickMarkValuesOnly = true

        let views: [NSView] = [formatLabel, formatPopup, locationLabel, locationButton,
                                colorLabel, colorWell, widthLabel, widthSlider]
        for v in views {
            v.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(v)
        }

        NSLayoutConstraint.activate([
            formatLabel.topAnchor.constraint(equalTo: container.topAnchor, constant: 20),
            formatLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 20),
            formatPopup.centerYAnchor.constraint(equalTo: formatLabel.centerYAnchor),
            formatPopup.leadingAnchor.constraint(equalTo: formatLabel.trailingAnchor, constant: 10),
            formatPopup.widthAnchor.constraint(equalToConstant: 120),

            locationLabel.topAnchor.constraint(equalTo: formatLabel.bottomAnchor, constant: 16),
            locationLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 20),
            locationButton.centerYAnchor.constraint(equalTo: locationLabel.centerYAnchor),
            locationButton.leadingAnchor.constraint(equalTo: locationLabel.trailingAnchor, constant: 10),
            locationButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 120),

            colorLabel.topAnchor.constraint(equalTo: locationLabel.bottomAnchor, constant: 16),
            colorLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 20),
            colorWell.centerYAnchor.constraint(equalTo: colorLabel.centerYAnchor),
            colorWell.leadingAnchor.constraint(equalTo: colorLabel.trailingAnchor, constant: 10),
            colorWell.widthAnchor.constraint(equalToConstant: 44),
            colorWell.heightAnchor.constraint(equalToConstant: 24),

            widthLabel.topAnchor.constraint(equalTo: colorLabel.bottomAnchor, constant: 16),
            widthLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 20),
            widthSlider.centerYAnchor.constraint(equalTo: widthLabel.centerYAnchor),
            widthSlider.leadingAnchor.constraint(equalTo: widthLabel.trailingAnchor, constant: 10),
            widthSlider.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -20),
        ])

        item.view = container
        return item
    }

    // MARK: - Shortcuts Tab

    private func makeShortcutsTab() -> NSTabViewItem {
        let item = NSTabViewItem(identifier: "shortcuts")
        item.label = "Shortcuts"

        let container = NSView()
        let label = NSTextField(labelWithString: "Keyboard shortcuts can be customized here.\nClick a shortcut to change it.")
        label.font = NSFont.systemFont(ofSize: 12)
        label.maximumNumberOfLines = 2
        label.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(label)

        let scrollView = NSScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .bezelBorder

        let tableView = NSTableView()
        let actionCol = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("action"))
        actionCol.title = "Action"
        actionCol.width = 200
        let shortcutCol = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("shortcut"))
        shortcutCol.title = "Shortcut"
        shortcutCol.width = 200
        tableView.addTableColumn(actionCol)
        tableView.addTableColumn(shortcutCol)
        tableView.dataSource = shortcutsDataSource
        tableView.delegate = shortcutsDataSource
        scrollView.documentView = tableView
        container.addSubview(scrollView)

        let resetButton = NSButton(title: "Reset to Defaults", target: self, action: #selector(resetShortcuts(_:)))
        resetButton.bezelStyle = .rounded
        resetButton.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(resetButton)

        NSLayoutConstraint.activate([
            label.topAnchor.constraint(equalTo: container.topAnchor, constant: 16),
            label.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 20),
            label.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -20),

            scrollView.topAnchor.constraint(equalTo: label.bottomAnchor, constant: 12),
            scrollView.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 20),
            scrollView.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -20),
            scrollView.bottomAnchor.constraint(equalTo: resetButton.topAnchor, constant: -12),

            resetButton.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -20),
            resetButton.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -16),
        ])

        item.view = container
        return item
    }

    // MARK: - Fonts Tab

    private var fontsTableView: NSTableView?

    private func makeFontsTab() -> NSTabViewItem {
        let item = NSTabViewItem(identifier: "fonts")
        item.label = "Fonts"

        let container = NSView()

        let label = NSTextField(labelWithString: "Import custom .ttf or .otf fonts for use in annotations.")
        label.font = NSFont.systemFont(ofSize: 12)
        label.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(label)

        let scrollView = NSScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .bezelBorder

        let tableView = NSTableView()
        let nameCol = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("fontName"))
        nameCol.title = "Font Name"
        nameCol.width = 350
        tableView.addTableColumn(nameCol)
        tableView.dataSource = fontsDataSource
        tableView.delegate = fontsDataSource
        scrollView.documentView = tableView
        self.fontsTableView = tableView
        container.addSubview(scrollView)

        let addButton = NSButton(title: "Add Font…", target: self, action: #selector(addFont(_:)))
        addButton.bezelStyle = .rounded
        addButton.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(addButton)

        let removeButton = NSButton(title: "Remove", target: self, action: #selector(removeFont(_:)))
        removeButton.bezelStyle = .rounded
        removeButton.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(removeButton)

        NSLayoutConstraint.activate([
            label.topAnchor.constraint(equalTo: container.topAnchor, constant: 16),
            label.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 20),
            label.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -20),

            scrollView.topAnchor.constraint(equalTo: label.bottomAnchor, constant: 12),
            scrollView.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 20),
            scrollView.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -20),
            scrollView.bottomAnchor.constraint(equalTo: addButton.topAnchor, constant: -12),

            addButton.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 20),
            addButton.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -16),

            removeButton.leadingAnchor.constraint(equalTo: addButton.trailingAnchor, constant: 8),
            removeButton.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -16),
        ])

        item.view = container
        return item
    }

    // MARK: - Actions

    @objc private func formatChanged(_ sender: NSPopUpButton) {
        if let title = sender.titleOfSelectedItem {
            UserDefaults.standard.set(title, forKey: "defaultExportFormat")
        }
    }

    @objc private func changeSaveLocation(_ sender: NSButton) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = URL(fileURLWithPath: currentSaveLocation())
        panel.beginSheetModal(for: self) { response in
            guard response == .OK, let url = panel.url else { return }
            UserDefaults.standard.set(url.path, forKey: "defaultSaveLocation")
            sender.title = url.lastPathComponent
        }
    }

    @objc private func colorChanged(_ sender: NSColorWell) {
        UserDefaults.standard.set(sender.color.hexString, forKey: "defaultColor")
    }

    @objc private func widthChanged(_ sender: NSSlider) {
        UserDefaults.standard.set(sender.integerValue, forKey: "defaultStrokeWidth")
    }

    @objc private func resetShortcuts(_ sender: NSButton) {
        UserDefaults.standard.removeObject(forKey: "customShortcuts")
        // Reload table
    }

    @objc private func addFont(_ sender: NSButton) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.init(filenameExtension: "ttf")!, .init(filenameExtension: "otf")!]
        panel.allowsMultipleSelection = true
        panel.beginSheetModal(for: self) { [weak self] response in
            guard response == .OK else { return }
            for url in panel.urls {
                if FontManager.importFont(from: url) == nil {
                    let alert = NSAlert()
                    alert.messageText = "Could not load font"
                    alert.informativeText = "The file \"\(url.lastPathComponent)\" may be corrupted or in an unsupported format."
                    alert.alertStyle = .warning
                    alert.runModal()
                }
            }
            self?.fontsTableView?.reloadData()
        }
    }

    @objc private func removeFont(_ sender: NSButton) {
        guard let tableView = fontsTableView else { return }
        let row = tableView.selectedRow
        guard row >= 0, row < FontManager.customFontNames.count else { return }
        let name = FontManager.customFontNames[row]
        FontManager.removeFont(name: name)
        tableView.reloadData()
    }

    // MARK: - Helpers

    private func currentSaveLocation() -> String {
        UserDefaults.standard.string(forKey: "defaultSaveLocation")
            ?? FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Desktop").path
    }

    private func defaultColor() -> NSColor {
        if let hex = UserDefaults.standard.string(forKey: "defaultColor") {
            return NSColor.from(hex: hex)
        }
        return NSColor(red: 1.0, green: 0.231, blue: 0.188, alpha: 1.0)
    }

    // MARK: - Data Sources

    private let shortcutsDataSource = ShortcutsDataSource()
    private let fontsDataSource = FontsDataSource()
}

// MARK: - Shortcuts Data Source

private final class ShortcutsDataSource: NSObject, NSTableViewDataSource, NSTableViewDelegate {
    private let defaultShortcuts: [(action: String, shortcut: String)] = [
        ("Capture Fullscreen", "⌘⇧3"),
        ("Capture Area", "⌘⇧4"),
        ("Capture Window", "⌘⇧5"),
        ("Re-open Last Edit", "⌘⇧L"),
        ("Quick Save", "⌘S"),
        ("Copy", "⌘C"),
        ("Preferences", "⌘,"),
    ]

    func numberOfRows(in tableView: NSTableView) -> Int {
        defaultShortcuts.count
    }

    func tableView(_ tableView: NSTableView, objectValueFor tableColumn: NSTableColumn?, row: Int) -> Any? {
        guard row < defaultShortcuts.count else { return nil }
        if tableColumn?.identifier.rawValue == "action" {
            return defaultShortcuts[row].action
        } else {
            return defaultShortcuts[row].shortcut
        }
    }
}

// MARK: - Fonts Data Source

private final class FontsDataSource: NSObject, NSTableViewDataSource, NSTableViewDelegate {
    func numberOfRows(in tableView: NSTableView) -> Int {
        FontManager.customFontNames.count
    }

    func tableView(_ tableView: NSTableView, objectValueFor tableColumn: NSTableColumn?, row: Int) -> Any? {
        guard row < FontManager.customFontNames.count else { return nil }
        return FontManager.customFontNames[row]
    }
}
