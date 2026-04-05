import AppKit

/// Tool identifiers matching the spec's 8 tools.
enum AnnotationTool: String, CaseIterable {
    case arrow, rectangle, line, blur, highlight, ruler, numbering, text

    var label: String {
        switch self {
        case .arrow: return "Arrow"
        case .rectangle: return "Rectangle"
        case .blur: return "Blur"
        case .highlight: return "Highlight"
        case .text: return "Text"
        case .line: return "Line"
        case .ruler: return "Ruler"
        case .numbering: return "Numbering"
        }
    }

    var keyEquivalent: String {
        switch self {
        case .arrow: return "a"
        case .rectangle: return "r"
        case .blur: return "b"
        case .highlight: return "h"
        case .text: return "t"
        case .line: return "l"
        case .ruler: return "u"
        case .numbering: return "n"
        }
    }

    var systemImage: String {
        switch self {
        case .arrow: return "arrow.up.right"
        case .rectangle: return "rectangle"
        case .blur: return "eye.slash"
        case .highlight: return "highlighter"
        case .text: return "textformat"
        case .line: return "line.diagonal"
        case .ruler: return "ruler"
        case .numbering: return "number.circle"
        }
    }
}

/// Frosted glass toolbar with tool buttons and action buttons.
final class AnnotationToolbar: NSView {

    var onToolSelected: ((AnnotationTool) -> Void)?
    var onCopy: (() -> Void)?
    var onSave: (() -> Void)?
    var onDiscard: (() -> Void)?

    private(set) var selectedTool: AnnotationTool = .arrow
    private var toolButtons: [AnnotationTool: NSButton] = [:]
    private var colorButtons: [NSButton] = []
    private var widthButtons: [NSButton] = []

    /// Stroke widths: thin, medium, thick
    static let widthPresets: [UInt32] = [2, 4, 8]

    /// Color presets: Red, Yellow, Blue, Green, White
    static let colorPresets: [NSColor] = [
        NSColor(red: 1.0, green: 0.231, blue: 0.188, alpha: 1.0),  // #FF3B30
        NSColor(red: 1.0, green: 0.8, blue: 0.0, alpha: 1.0),      // #FFCC00
        NSColor(red: 0.0, green: 0.478, blue: 1.0, alpha: 1.0),    // #007AFF
        NSColor(red: 0.204, green: 0.78, blue: 0.349, alpha: 1.0), // #34C759
        NSColor.white,
    ]

    var onColorChanged: ((NSColor) -> Void)?
    var onWidthChanged: ((UInt32) -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupUI()
    }

    required init?(coder: NSCoder) { fatalError("Not implemented") }

    private func setupUI() {
        wantsLayer = true

        // Frosted glass background
        let visualEffect = NSVisualEffectView()
        visualEffect.material = .hudWindow
        visualEffect.blendingMode = .withinWindow
        visualEffect.state = .active
        visualEffect.wantsLayer = true
        visualEffect.layer?.cornerRadius = 12
        visualEffect.translatesAutoresizingMaskIntoConstraints = false
        addSubview(visualEffect)

        // Tool buttons
        let toolStack = NSStackView()
        toolStack.orientation = .horizontal
        toolStack.spacing = 4
        toolStack.translatesAutoresizingMaskIntoConstraints = false

        for tool in AnnotationTool.allCases {
            let button = NSButton()
            button.bezelStyle = .inline
            button.isBordered = false
            button.image = NSImage(systemSymbolName: tool.systemImage,
                                   accessibilityDescription: tool.label)
            button.imageScaling = .scaleProportionallyDown
            button.toolTip = "\(tool.label) (\(tool.keyEquivalent.uppercased()))"
            button.target = self
            button.action = #selector(toolButtonClicked(_:))
            button.tag = AnnotationTool.allCases.firstIndex(of: tool) ?? 0

            button.widthAnchor.constraint(equalToConstant: 28).isActive = true
            button.heightAnchor.constraint(equalToConstant: 28).isActive = true

            toolButtons[tool] = button
            toolStack.addArrangedSubview(button)
        }

        // Separator
        let separator = NSView()
        separator.wantsLayer = true
        separator.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.2).cgColor
        separator.translatesAutoresizingMaskIntoConstraints = false
        separator.widthAnchor.constraint(equalToConstant: 1).isActive = true
        separator.heightAnchor.constraint(equalToConstant: 20).isActive = true

        // Action buttons
        let copyButton = makeActionButton(title: "Copy", primary: true)
        copyButton.target = self
        copyButton.action = #selector(copyClicked)

        let saveButton = makeActionButton(title: "Save", primary: false)
        saveButton.target = self
        saveButton.action = #selector(saveClicked)

        let discardButton = makeActionButton(title: "Discard", primary: false)
        discardButton.target = self
        discardButton.action = #selector(discardClicked)

        let actionStack = NSStackView(views: [copyButton, saveButton, discardButton])
        actionStack.orientation = .horizontal
        actionStack.spacing = 8
        actionStack.translatesAutoresizingMaskIntoConstraints = false

        let topRow = NSStackView(views: [toolStack, separator, actionStack])
        topRow.orientation = .horizontal
        topRow.spacing = 12

        // Config row: color swatches + width selector
        let configRow = makeConfigRow()

        let mainStack = NSStackView(views: [topRow, configRow])
        mainStack.orientation = .vertical
        mainStack.alignment = .leading
        mainStack.spacing = 6
        mainStack.edgeInsets = NSEdgeInsets(top: 6, left: 12, bottom: 6, right: 12)
        mainStack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(mainStack)

        NSLayoutConstraint.activate([
            visualEffect.leadingAnchor.constraint(equalTo: leadingAnchor),
            visualEffect.trailingAnchor.constraint(equalTo: trailingAnchor),
            visualEffect.topAnchor.constraint(equalTo: topAnchor),
            visualEffect.bottomAnchor.constraint(equalTo: bottomAnchor),
            mainStack.leadingAnchor.constraint(equalTo: leadingAnchor),
            mainStack.trailingAnchor.constraint(equalTo: trailingAnchor),
            mainStack.topAnchor.constraint(equalTo: topAnchor),
            mainStack.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])

        updateToolSelection()
    }

    private func makeConfigRow() -> NSStackView {
        // Color swatches
        for (index, color) in AnnotationToolbar.colorPresets.enumerated() {
            let button = NSButton()
            button.bezelStyle = .inline
            button.isBordered = false
            button.wantsLayer = true
            button.layer?.backgroundColor = color.cgColor
            button.layer?.cornerRadius = 9
            button.layer?.borderWidth = 1.5
            button.layer?.borderColor = NSColor.white.withAlphaComponent(0.3).cgColor
            button.toolTip = colorName(at: index)
            button.target = self
            button.action = #selector(colorButtonClicked(_:))
            button.tag = index
            button.widthAnchor.constraint(equalToConstant: 18).isActive = true
            button.heightAnchor.constraint(equalToConstant: 18).isActive = true
            colorButtons.append(button)
        }

        let colorStack = NSStackView(views: colorButtons)
        colorStack.orientation = .horizontal
        colorStack.spacing = 6

        // Width buttons: thin / medium / thick line indicators
        let widthSeparator = NSView()
        widthSeparator.wantsLayer = true
        widthSeparator.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.2).cgColor
        widthSeparator.translatesAutoresizingMaskIntoConstraints = false
        widthSeparator.widthAnchor.constraint(equalToConstant: 1).isActive = true
        widthSeparator.heightAnchor.constraint(equalToConstant: 14).isActive = true

        for (index, width) in AnnotationToolbar.widthPresets.enumerated() {
            let button = NSButton()
            button.bezelStyle = .inline
            button.isBordered = false
            button.toolTip = widthLabel(width)
            button.target = self
            button.action = #selector(widthButtonClicked(_:))
            button.tag = index
            // Draw a horizontal line scaled to the stroke width
            let lineHeight = CGFloat(width)
            let img = NSImage(size: NSSize(width: 24, height: 18), flipped: false) { rect in
                NSColor.white.withAlphaComponent(0.8).setFill()
                let lineRect = NSRect(
                    x: 0,
                    y: (rect.height - lineHeight) / 2,
                    width: rect.width,
                    height: lineHeight
                )
                NSBezierPath(roundedRect: lineRect, xRadius: lineHeight / 2, yRadius: lineHeight / 2).fill()
                return true
            }
            button.image = img
            button.imageScaling = .scaleNone
            button.widthAnchor.constraint(equalToConstant: 28).isActive = true
            button.heightAnchor.constraint(equalToConstant: 18).isActive = true
            widthButtons.append(button)
        }

        let widthStack = NSStackView(views: widthButtons)
        widthStack.orientation = .horizontal
        widthStack.spacing = 4

        let configRow = NSStackView(views: [colorStack, widthSeparator, widthStack])
        configRow.orientation = .horizontal
        configRow.spacing = 10
        return configRow
    }

    private func colorName(at index: Int) -> String {
        ["Red", "Yellow", "Blue", "Green", "White"][index]
    }

    private func widthLabel(_ width: UInt32) -> String {
        switch width {
        case 2: return "Thin"
        case 4: return "Medium"
        case 8: return "Thick"
        default: return "\(width)px"
        }
    }

    private func makeActionButton(title: String, primary: Bool) -> NSButton {
        let button = NSButton(title: title, target: nil, action: nil)
        button.bezelStyle = primary ? .rounded : .inline
        button.isBordered = primary
        if !primary {
            button.contentTintColor = .secondaryLabelColor
        }
        button.font = NSFont.systemFont(ofSize: 12, weight: primary ? .medium : .regular)
        return button
    }

    // MARK: - Tool selection

    func selectTool(_ tool: AnnotationTool) {
        selectedTool = tool
        updateToolSelection()
        onToolSelected?(tool)
    }

    private func updateToolSelection() {
        for (tool, button) in toolButtons {
            button.contentTintColor = (tool == selectedTool)
                ? .white
                : .white.withAlphaComponent(0.5)
        }
    }

    // MARK: - Actions

    @objc private func toolButtonClicked(_ sender: NSButton) {
        let tool = AnnotationTool.allCases[sender.tag]
        selectTool(tool)
    }

    @objc private func colorButtonClicked(_ sender: NSButton) {
        let color = AnnotationToolbar.colorPresets[sender.tag]
        onColorChanged?(color)
    }

    @objc private func widthButtonClicked(_ sender: NSButton) {
        let width = AnnotationToolbar.widthPresets[sender.tag]
        onWidthChanged?(width)
    }

    @objc private func copyClicked() { onCopy?() }
    @objc private func saveClicked() { onSave?() }
    @objc private func discardClicked() { onDiscard?() }
}
