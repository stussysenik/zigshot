import AppKit

// MARK: - Tool Enum

/// All annotation tools available in the toolbar.
enum AnnotationTool: String, CaseIterable {
    case crop, arrow, rectangle, line, blur, highlight, ruler, numbering, text, stickyNote, eraser, ocr

    /// Human-readable name used for tooltips and accessibility.
    var label: String {
        switch self {
        case .crop:       return "Crop"
        case .arrow:      return "Arrow"
        case .rectangle:  return "Rectangle"
        case .text:       return "Text"
        case .blur:       return "Blur"
        case .line:       return "Line"
        case .ruler:      return "Ruler"
        case .numbering:  return "Numbering"
        case .highlight:  return "Highlight"
        case .stickyNote: return "Sticky Note"
        case .eraser:     return "Eraser"
        case .ocr:        return "OCR"
        }
    }

    /// Single-key shortcut shown in the tooltip.
    var keyEquivalent: String {
        switch self {
        case .crop:       return "c"
        case .arrow:      return "a"
        case .rectangle:  return "r"
        case .text:       return "t"
        case .blur:       return "b"
        case .line:       return "l"
        case .ruler:      return "u"
        case .numbering:  return "n"
        case .highlight:  return "h"
        case .stickyNote: return "s"
        case .eraser:     return "e"
        case .ocr:        return "o"
        }
    }

    /// SF Symbol name for each tool.
    var systemImage: String {
        switch self {
        case .crop:       return "crop"
        case .arrow:      return "arrow.up.right"
        case .rectangle:  return "rectangle"
        case .text:       return "character.textbox"
        case .blur:       return "eye.slash"
        case .line:       return "line.diagonal"
        case .ruler:      return "ruler"
        case .numbering:  return "number.circle"
        case .highlight:  return "highlighter"
        case .stickyNote: return "note.text"
        case .eraser:     return "eraser.line.dashed"
        case .ocr:        return "doc.text.magnifyingglass"
        }
    }
}

// MARK: - Tool Button

/// A single square toolbar button that renders its own selected-state pill.
private final class ToolButton: NSView {

    private let imageView: NSImageView
    private let pill: NSView
    private let indicator: NSView
    private let tool: AnnotationTool

    var isSelected: Bool = false {
        didSet { updateAppearance() }
    }

    /// The current annotation color — used for the active tool indicator.
    var activeColor: NSColor = NSColor(red: 1.0, green: 0.231, blue: 0.188, alpha: 1.0) {
        didSet { updateAppearance() }
    }

    var action: ((AnnotationTool) -> Void)?

    init(tool: AnnotationTool) {
        self.tool = tool

        // Hover pill — subtle background on hover only
        pill = NSView()
        pill.wantsLayer = true
        pill.layer?.cornerRadius = 7
        pill.isHidden = true
        pill.translatesAutoresizingMaskIntoConstraints = false

        // Bottom color indicator — shows active tool in selected color
        indicator = NSView()
        indicator.wantsLayer = true
        indicator.layer?.cornerRadius = 1.5
        indicator.isHidden = true
        indicator.translatesAutoresizingMaskIntoConstraints = false

        // Icon
        let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .medium)
        let image = NSImage(systemSymbolName: tool.systemImage,
                            accessibilityDescription: tool.label)?
            .withSymbolConfiguration(config)
        imageView = NSImageView(image: image ?? NSImage())
        imageView.imageScaling = .scaleProportionallyDown
        imageView.translatesAutoresizingMaskIntoConstraints = false

        super.init(frame: .zero)

        wantsLayer = true
        addSubview(pill)
        addSubview(imageView)
        addSubview(indicator)

        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: 36),
            heightAnchor.constraint(equalToConstant: 36),

            pill.leadingAnchor.constraint(equalTo: leadingAnchor),
            pill.trailingAnchor.constraint(equalTo: trailingAnchor),
            pill.topAnchor.constraint(equalTo: topAnchor),
            pill.bottomAnchor.constraint(equalTo: bottomAnchor),

            imageView.centerXAnchor.constraint(equalTo: centerXAnchor),
            imageView.centerYAnchor.constraint(equalTo: centerYAnchor),
            imageView.widthAnchor.constraint(equalToConstant: 20),
            imageView.heightAnchor.constraint(equalToConstant: 20),

            indicator.centerXAnchor.constraint(equalTo: centerXAnchor),
            indicator.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -2),
            indicator.widthAnchor.constraint(equalToConstant: 16),
            indicator.heightAnchor.constraint(equalToConstant: 3),
        ])

        toolTip = "\(tool.label) (\(tool.keyEquivalent.uppercased()))"
        updateAppearance()

        let click = NSClickGestureRecognizer(target: self, action: #selector(handleClick))
        addGestureRecognizer(click)
    }

    required init?(coder: NSCoder) { fatalError("Not implemented") }

    private var isHovered = false

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas { removeTrackingArea(area) }
        addTrackingArea(NSTrackingArea(
            rect: bounds,
            options: [.activeAlways, .mouseEnteredAndExited],
            owner: self
        ))
    }

    override func mouseEntered(with event: NSEvent) {
        isHovered = true
        updateAppearance()
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
        updateAppearance()
    }

    @objc private func handleClick() {
        action?(tool)
    }

    private func updateAppearance() {
        if isSelected {
            pill.isHidden = true
            indicator.isHidden = false
            indicator.layer?.backgroundColor = activeColor.cgColor
            imageView.contentTintColor = activeColor
        } else if isHovered {
            pill.isHidden = false
            pill.layer?.backgroundColor = NSColor(calibratedWhite: 0.75, alpha: 1.0).cgColor
            indicator.isHidden = true
            imageView.contentTintColor = NSColor(calibratedWhite: 0.08, alpha: 1.0)
        } else {
            pill.isHidden = true
            indicator.isHidden = true
            imageView.contentTintColor = NSColor(calibratedWhite: 0.25, alpha: 1.0)
        }
    }
}

// MARK: - Color Dot Button

/// A circular color swatch that shows a selection ring when active.
private final class ColorDotButton: NSView {

    private let dot: NSView
    private let ringLayer: CAShapeLayer
    let color: NSColor
    let index: Int

    var isSelected: Bool = false {
        didSet { updateRing() }
    }

    var action: ((Int) -> Void)?

    init(color: NSColor, index: Int) {
        self.color = color
        self.index = index

        dot = NSView()
        dot.wantsLayer = true
        dot.layer?.backgroundColor = color.cgColor
        dot.layer?.cornerRadius = 12
        dot.translatesAutoresizingMaskIntoConstraints = false

        ringLayer = CAShapeLayer()
        ringLayer.fillColor = NSColor.clear.cgColor
        ringLayer.strokeColor = NSColor(calibratedWhite: 0.4, alpha: 1.0).cgColor
        ringLayer.lineWidth = 2
        ringLayer.isHidden = true

        super.init(frame: .zero)

        wantsLayer = true
        addSubview(dot)
        layer?.addSublayer(ringLayer)

        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: 28),
            heightAnchor.constraint(equalToConstant: 28),
            dot.widthAnchor.constraint(equalToConstant: 24),
            dot.heightAnchor.constraint(equalToConstant: 24),
            dot.centerXAnchor.constraint(equalTo: centerXAnchor),
            dot.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])

        let click = NSClickGestureRecognizer(target: self, action: #selector(handleClick))
        addGestureRecognizer(click)
    }

    required init?(coder: NSCoder) { fatalError("Not implemented") }

    override func layout() {
        super.layout()
        let inset: CGFloat = 1
        let rect = bounds.insetBy(dx: inset, dy: inset)
        ringLayer.frame = bounds
        ringLayer.path = CGPath(ellipseIn: rect, transform: nil)
    }

    @objc private func handleClick() {
        action?(index)
    }

    private func updateRing() {
        ringLayer.isHidden = !isSelected
    }
}

// MARK: - Action Button

/// A compact icon button for one-shot actions (rotate, flip). No selected state.
private final class ActionButton: NSView {

    private let imageView: NSImageView
    private var isHovered = false
    var onClick: (() -> Void)?

    init(systemImage: String, tooltip: String) {
        let config = NSImage.SymbolConfiguration(pointSize: 13, weight: .medium)
        let image = NSImage(systemSymbolName: systemImage,
                            accessibilityDescription: tooltip)?
            .withSymbolConfiguration(config)
        imageView = NSImageView(image: image ?? NSImage())
        imageView.imageScaling = .scaleProportionallyDown
        imageView.translatesAutoresizingMaskIntoConstraints = false

        super.init(frame: .zero)

        wantsLayer = true
        layer?.cornerRadius = 6
        addSubview(imageView)

        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: 30),
            heightAnchor.constraint(equalToConstant: 30),
            imageView.centerXAnchor.constraint(equalTo: centerXAnchor),
            imageView.centerYAnchor.constraint(equalTo: centerYAnchor),
            imageView.widthAnchor.constraint(equalToConstant: 18),
            imageView.heightAnchor.constraint(equalToConstant: 18),
        ])

        toolTip = tooltip
        imageView.contentTintColor = NSColor(calibratedWhite: 0.30, alpha: 1.0)

        let click = NSClickGestureRecognizer(target: self, action: #selector(handleClick))
        addGestureRecognizer(click)
    }

    required init?(coder: NSCoder) { fatalError("Not implemented") }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas { removeTrackingArea(area) }
        addTrackingArea(NSTrackingArea(
            rect: bounds,
            options: [.activeAlways, .mouseEnteredAndExited],
            owner: self
        ))
    }

    override func mouseEntered(with event: NSEvent) {
        isHovered = true
        layer?.backgroundColor = NSColor(calibratedWhite: 0.85, alpha: 1.0).cgColor
        imageView.contentTintColor = NSColor(calibratedWhite: 0.10, alpha: 1.0)
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
        layer?.backgroundColor = nil
        imageView.contentTintColor = NSColor(calibratedWhite: 0.30, alpha: 1.0)
    }

    @objc private func handleClick() { onClick?() }
}

// MARK: - Separator

private func makeSeparator() -> NSView {
    let v = NSView()
    v.wantsLayer = true
    v.layer?.backgroundColor = NSColor(calibratedWhite: 0.82, alpha: 1.0).cgColor
    v.translatesAutoresizingMaskIntoConstraints = false
    v.widthAnchor.constraint(equalToConstant: 1).isActive = true
    v.heightAnchor.constraint(equalToConstant: 24).isActive = true
    return v
}

// MARK: - AnnotationToolbar

/// Single-row annotation toolbar with Things/iA Writer aesthetic.
///
/// Layout:
///   Left:  [crop · arrow · rect · text · highlight · blur · line · ruler · #] | [color dots]
///   Right: [rotateCCW · rotateCW · flipH · flipV]
final class AnnotationToolbar: NSView {

    // MARK: Callbacks

    var onToolSelected: ((AnnotationTool) -> Void)?
    var onColorChanged: ((NSColor) -> Void)?
    var onWidthChanged: ((UInt32) -> Void)?
    var onFontSizeChanged: ((CGFloat) -> Void)?
    var onBoldChanged: ((Bool) -> Void)?
    var onItalicChanged: ((Bool) -> Void)?
    var onAlignmentChanged: ((NSTextAlignment) -> Void)?
    var onFontNameChanged: ((String?) -> Void)?

    // Zoom actions
    var onZoomIn: (() -> Void)?
    var onZoomOut: (() -> Void)?
    var onZoomToFit: (() -> Void)?

    // Image transform actions (one-shot, not tools)
    var onRotateCW: (() -> Void)?
    var onRotateCCW: (() -> Void)?
    var onFlipH: (() -> Void)?
    var onFlipV: (() -> Void)?

    // MARK: State

    private(set) var selectedTool: AnnotationTool = .arrow
    private(set) var selectedColorIndex: Int = 0
    private(set) var selectedFontSizeIndex: Int = 1 // Default 16pt
    private(set) var isBold: Bool = false
    private(set) var isItalic: Bool = false
    private(set) var textAlignment: NSTextAlignment = .left
    private(set) var selectedFontName: String?

    private var zoomLabel: NSTextField?
    private var toolButtons: [AnnotationTool: ToolButton] = [:]
    private var colorDots: [ColorDotButton] = []
    private var colorWell: NSColorWell?
    private var colorStack: NSStackView?
    private var fontSizeButtons: [NSButton] = []
    private var fontSizeStack: NSStackView?
    private var textFormattingStack: NSStackView?
    private var boldButton: NSButton?
    private var italicButton: NSButton?
    private var alignLeftButton: NSButton?
    private var alignCenterButton: NSButton?
    private var alignRightButton: NSButton?
    private var fontPopup: NSPopUpButton?

    // MARK: Presets

    /// Stroke widths: thin, medium, thick.
    static let widthPresets: [UInt32] = [2, 4, 8]

    /// Font size presets for text and sticky note tools.
    static let fontSizePresets: [CGFloat] = [12, 16, 20, 24, 32]

    /// Color presets: 5 built-in + user-added custom colors (persisted to UserDefaults).
    static var colorPresets: [NSColor] = AnnotationToolbar.loadColorPresets()

    /// Number of built-in (non-removable) color presets.
    private static let builtInColorCount = 5

    private static func loadColorPresets() -> [NSColor] {
        let defaults: [NSColor] = [
            NSColor(red: 1.0,   green: 0.231, blue: 0.188, alpha: 1.0), // #FF3B30 Red
            NSColor(red: 1.0,   green: 0.80,  blue: 0.0,   alpha: 1.0), // #FFCC00 Yellow
            NSColor(red: 0.0,   green: 0.478, blue: 1.0,   alpha: 1.0), // #007AFF Blue
            NSColor(red: 0.204, green: 0.78,  blue: 0.349, alpha: 1.0), // #34C759 Green
            NSColor(calibratedWhite: 0.05, alpha: 1.0),                  // Black
        ]
        let saved = UserDefaults.standard.stringArray(forKey: "zigshot.customColors") ?? []
        let custom = saved.compactMap { NSColor.from(hex: $0) }
        return defaults + custom
    }

    static func saveCustomColors() {
        let customColors = Array(colorPresets.dropFirst(builtInColorCount))
        let hexStrings = customColors.map { $0.hexString }
        UserDefaults.standard.set(hexStrings, forKey: "zigshot.customColors")
    }

    // MARK: Init

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupUI()
    }

    required init?(coder: NSCoder) { fatalError("Not implemented") }

    // MARK: Setup

    private func setupUI() {
        wantsLayer = true
        layer?.backgroundColor = NSColor(calibratedWhite: 0.94, alpha: 1.0).cgColor

        // Fine top border
        let border = NSView()
        border.wantsLayer = true
        border.layer?.backgroundColor = NSColor(calibratedWhite: 0.82, alpha: 1.0).cgColor
        border.translatesAutoresizingMaskIntoConstraints = false
        addSubview(border)

        // ── Left group: Annotation tools (crop + drawing tools) ──
        let orderedTools: [AnnotationTool] = [
            .crop, .arrow, .rectangle, .text, .stickyNote, .highlight, .blur, .line, .ruler, .numbering, .eraser, .ocr
        ]

        let toolStack = NSStackView()
        toolStack.orientation = .horizontal
        toolStack.spacing = 2
        toolStack.translatesAutoresizingMaskIntoConstraints = false

        for tool in orderedTools {
            let btn = ToolButton(tool: tool)
            btn.isSelected = (tool == selectedTool)
            btn.action = { [weak self] tapped in
                guard let self else { return }
                self.selectTool(tapped)
                self.onToolSelected?(tapped)
            }
            toolButtons[tool] = btn
            toolStack.addArrangedSubview(btn)
        }

        let sep1 = makeSeparator()

        // ── Center group: Color dots ──
        let colorStack = NSStackView()
        colorStack.orientation = .horizontal
        colorStack.spacing = 6
        colorStack.translatesAutoresizingMaskIntoConstraints = false
        self.colorStack = colorStack

        for (index, color) in AnnotationToolbar.colorPresets.enumerated() {
            let dot = ColorDotButton(color: color, index: index)
            dot.isSelected = (index == selectedColorIndex)
            dot.action = { [weak self] tappedIndex in
                self?.selectColor(at: tappedIndex)
            }
            colorDots.append(dot)
            colorStack.addArrangedSubview(dot)
        }

        // Custom color well — opens system color picker
        let well = NSColorWell(frame: NSRect(x: 0, y: 0, width: 24, height: 24))
        well.color = AnnotationToolbar.colorPresets[selectedColorIndex]
        if #available(macOS 13.0, *) {
            well.colorWellStyle = .minimal
        }
        well.target = self
        well.action = #selector(colorWellChanged(_:))
        well.translatesAutoresizingMaskIntoConstraints = false
        well.toolTip = "Custom Color (P)"
        NSLayoutConstraint.activate([
            well.widthAnchor.constraint(equalToConstant: 28),
            well.heightAnchor.constraint(equalToConstant: 28),
        ])
        self.colorWell = well
        colorStack.addArrangedSubview(well)

        // "+" button — saves the current color well color as a new preset
        let addBtn = NSButton(title: "+", target: self, action: #selector(addFavoriteColor(_:)))
        addBtn.bezelStyle = .inline
        addBtn.isBordered = false
        addBtn.font = NSFont.systemFont(ofSize: 14, weight: .medium)
        addBtn.contentTintColor = NSColor(calibratedWhite: 0.45, alpha: 1.0)
        addBtn.toolTip = "Save current color as preset"
        addBtn.translatesAutoresizingMaskIntoConstraints = false
        colorStack.addArrangedSubview(addBtn)

        let sep2 = makeSeparator()

        // ── Font size segment (hidden until text/stickyNote tool selected) ──
        let fStack = NSStackView()
        fStack.orientation = .horizontal
        fStack.spacing = 2
        fStack.translatesAutoresizingMaskIntoConstraints = false

        for (i, size) in AnnotationToolbar.fontSizePresets.enumerated() {
            let btn = NSButton(title: "\(Int(size))", target: self, action: #selector(fontSizeTapped(_:)))
            btn.bezelStyle = .inline
            btn.isBordered = false
            btn.tag = i
            btn.font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: i == selectedFontSizeIndex ? .bold : .regular)
            btn.contentTintColor = i == selectedFontSizeIndex
                ? NSColor(calibratedWhite: 0.05, alpha: 1.0)
                : NSColor(calibratedWhite: 0.45, alpha: 1.0)
            btn.translatesAutoresizingMaskIntoConstraints = false
            fontSizeButtons.append(btn)
            fStack.addArrangedSubview(btn)
        }
        fStack.isHidden = true // Shown when text/stickyNote tool selected
        self.fontSizeStack = fStack

        // ── Text formatting controls (hidden until text/stickyNote tool selected) ──
        let tfStack = NSStackView()
        tfStack.orientation = .horizontal
        tfStack.spacing = 4
        tfStack.translatesAutoresizingMaskIntoConstraints = false

        let bBtn = NSButton(title: "B", target: self, action: #selector(boldToggled(_:)))
        bBtn.bezelStyle = .inline
        bBtn.isBordered = false
        bBtn.font = NSFont.systemFont(ofSize: 13, weight: .bold)
        bBtn.contentTintColor = NSColor(calibratedWhite: 0.45, alpha: 1.0)
        bBtn.translatesAutoresizingMaskIntoConstraints = false
        self.boldButton = bBtn

        let iBtn = NSButton(title: "I", target: self, action: #selector(italicToggled(_:)))
        iBtn.bezelStyle = .inline
        iBtn.isBordered = false
        iBtn.font = NSFont(name: "Georgia-Italic", size: 13) ?? NSFont.systemFont(ofSize: 13)
        iBtn.contentTintColor = NSColor(calibratedWhite: 0.45, alpha: 1.0)
        iBtn.translatesAutoresizingMaskIntoConstraints = false
        self.italicButton = iBtn

        let tfSep = makeSeparator()

        let alLeft = NSButton(image: NSImage(systemSymbolName: "text.alignleft", accessibilityDescription: "Left")!, target: self, action: #selector(alignLeftTapped(_:)))
        alLeft.bezelStyle = .inline; alLeft.isBordered = false
        alLeft.translatesAutoresizingMaskIntoConstraints = false
        alLeft.contentTintColor = NSColor(calibratedWhite: 0.05, alpha: 1.0)
        self.alignLeftButton = alLeft

        let alCenter = NSButton(image: NSImage(systemSymbolName: "text.aligncenter", accessibilityDescription: "Center")!, target: self, action: #selector(alignCenterTapped(_:)))
        alCenter.bezelStyle = .inline; alCenter.isBordered = false
        alCenter.translatesAutoresizingMaskIntoConstraints = false
        alCenter.contentTintColor = NSColor(calibratedWhite: 0.45, alpha: 1.0)
        self.alignCenterButton = alCenter

        let alRight = NSButton(image: NSImage(systemSymbolName: "text.alignright", accessibilityDescription: "Right")!, target: self, action: #selector(alignRightTapped(_:)))
        alRight.bezelStyle = .inline; alRight.isBordered = false
        alRight.translatesAutoresizingMaskIntoConstraints = false
        alRight.contentTintColor = NSColor(calibratedWhite: 0.45, alpha: 1.0)
        self.alignRightButton = alRight

        let tfSep2 = makeSeparator()

        let fontPop = NSPopUpButton(frame: .zero, pullsDown: false)
        fontPop.font = NSFont.systemFont(ofSize: 11)
        fontPop.translatesAutoresizingMaskIntoConstraints = false
        fontPop.target = self
        fontPop.action = #selector(fontChanged(_:))
        refreshFontPopup(fontPop)
        self.fontPopup = fontPop

        tfStack.addArrangedSubview(bBtn)
        tfStack.addArrangedSubview(iBtn)
        tfStack.addArrangedSubview(tfSep)
        tfStack.addArrangedSubview(alLeft)
        tfStack.addArrangedSubview(alCenter)
        tfStack.addArrangedSubview(alRight)
        tfStack.addArrangedSubview(tfSep2)
        tfStack.addArrangedSubview(fontPop)
        tfStack.isHidden = true
        self.textFormattingStack = tfStack

        let sep3 = makeSeparator()

        // ── Zoom controls ──
        let zoomOutBtn = ActionButton(systemImage: "minus.magnifyingglass", tooltip: "Zoom Out (\u{2318}-)")
        zoomOutBtn.onClick = { [weak self] in self?.onZoomOut?() }

        let zLabel = NSTextField(labelWithString: "100%")
        zLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium)
        zLabel.textColor = NSColor(calibratedWhite: 0.25, alpha: 1.0)
        zLabel.alignment = .center
        zLabel.translatesAutoresizingMaskIntoConstraints = false
        zLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 38).isActive = true
        self.zoomLabel = zLabel

        let zoomInBtn = ActionButton(systemImage: "plus.magnifyingglass", tooltip: "Zoom In (\u{2318}+)")
        zoomInBtn.onClick = { [weak self] in self?.onZoomIn?() }

        let zoomFitBtn = ActionButton(systemImage: "aspectratio", tooltip: "Zoom to Fit (\u{2318}0)")
        zoomFitBtn.onClick = { [weak self] in self?.onZoomToFit?() }

        let zoomStack = NSStackView(views: [zoomOutBtn, zLabel, zoomInBtn, zoomFitBtn])
        zoomStack.orientation = .horizontal
        zoomStack.spacing = 2
        zoomStack.alignment = .centerY
        zoomStack.translatesAutoresizingMaskIntoConstraints = false

        let sep4 = makeSeparator()

        // ── Right group: Image transform actions ──
        let rotateCCW = ActionButton(systemImage: "rotate.left", tooltip: "Rotate Left")
        rotateCCW.onClick = { [weak self] in self?.onRotateCCW?() }

        let rotateCW = ActionButton(systemImage: "rotate.right", tooltip: "Rotate Right")
        rotateCW.onClick = { [weak self] in self?.onRotateCW?() }

        let flipH = ActionButton(systemImage: "arrow.left.and.right.righttriangle.left.righttriangle.right", tooltip: "Flip Horizontal")
        flipH.onClick = { [weak self] in self?.onFlipH?() }

        let flipV = ActionButton(systemImage: "arrow.up.and.down.righttriangle.up.righttriangle.down", tooltip: "Flip Vertical")
        flipV.onClick = { [weak self] in self?.onFlipV?() }

        let actionStack = NSStackView(views: [rotateCCW, rotateCW, flipH, flipV])
        actionStack.orientation = .horizontal
        actionStack.spacing = 2
        actionStack.translatesAutoresizingMaskIntoConstraints = false

        // ── Assemble ──
        let leftGroup = NSStackView(views: [toolStack, sep1, colorStack, sep3, fStack, tfStack])
        leftGroup.orientation = .horizontal
        leftGroup.spacing = 10
        leftGroup.alignment = .centerY
        leftGroup.translatesAutoresizingMaskIntoConstraints = false

        let rightGroup = NSStackView(views: [zoomStack, sep2, actionStack, sep4])
        rightGroup.orientation = .horizontal
        rightGroup.spacing = 10
        rightGroup.alignment = .centerY
        rightGroup.translatesAutoresizingMaskIntoConstraints = false

        addSubview(leftGroup)
        addSubview(rightGroup)

        NSLayoutConstraint.activate([
            // Top border
            border.topAnchor.constraint(equalTo: topAnchor),
            border.leadingAnchor.constraint(equalTo: leadingAnchor),
            border.trailingAnchor.constraint(equalTo: trailingAnchor),
            border.heightAnchor.constraint(equalToConstant: 1),

            // Left group — pinned to leading edge
            leftGroup.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            leftGroup.centerYAnchor.constraint(equalTo: centerYAnchor),

            // Right group — pinned to trailing edge
            rightGroup.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            rightGroup.centerYAnchor.constraint(equalTo: centerYAnchor),

            // Fixed toolbar height
            heightAnchor.constraint(equalToConstant: 52),
        ])
    }

    // MARK: - Public API

    /// Programmatically select a tool (does not fire `onToolSelected`).
    /// Used by AnnotationEditorView.switchTool to sync toolbar UI.
    func selectTool(_ tool: AnnotationTool) {
        selectedTool = tool
        for (t, btn) in toolButtons {
            btn.isSelected = (t == tool)
        }
        // Show font size and text formatting controls only for text-producing tools
        let isTextTool = (tool == .text || tool == .stickyNote)
        fontSizeStack?.isHidden = !isTextTool
        textFormattingStack?.isHidden = !isTextTool
    }

    /// Update the zoom percentage label.
    func updateZoomLabel(_ level: CGFloat) {
        let pct = Int(round(level * 100))
        zoomLabel?.stringValue = "\(pct)%"
    }

    /// Refresh the font popup contents (call after font import/removal).
    func refreshFontPopup(_ popup: NSPopUpButton? = nil) {
        let pop = popup ?? fontPopup
        pop?.removeAllItems()
        pop?.addItem(withTitle: "System Font")
        pop?.menu?.addItem(.separator())

        let (custom, system) = FontManager.availableFontNames()
        if !custom.isEmpty {
            for name in custom {
                pop?.addItem(withTitle: name)
            }
            pop?.menu?.addItem(.separator())
        }
        for name in system {
            pop?.addItem(withTitle: name)
        }
    }

    // MARK: - Private helpers

    @objc private func fontSizeTapped(_ sender: NSButton) {
        let index = sender.tag
        guard index >= 0, index < AnnotationToolbar.fontSizePresets.count else { return }
        selectedFontSizeIndex = index
        for (i, btn) in fontSizeButtons.enumerated() {
            btn.font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: i == index ? .bold : .regular)
            btn.contentTintColor = i == index
                ? NSColor(calibratedWhite: 0.05, alpha: 1.0)
                : NSColor(calibratedWhite: 0.45, alpha: 1.0)
        }
        onFontSizeChanged?(AnnotationToolbar.fontSizePresets[index])
    }

    @objc private func boldToggled(_ sender: NSButton) {
        isBold.toggle()
        sender.contentTintColor = isBold
            ? NSColor(calibratedWhite: 0.05, alpha: 1.0)
            : NSColor(calibratedWhite: 0.45, alpha: 1.0)
        onBoldChanged?(isBold)
    }

    @objc private func italicToggled(_ sender: NSButton) {
        isItalic.toggle()
        sender.contentTintColor = isItalic
            ? NSColor(calibratedWhite: 0.05, alpha: 1.0)
            : NSColor(calibratedWhite: 0.45, alpha: 1.0)
        onItalicChanged?(isItalic)
    }

    @objc private func alignLeftTapped(_ sender: NSButton) {
        textAlignment = .left
        updateAlignmentButtons()
        onAlignmentChanged?(.left)
    }

    @objc private func alignCenterTapped(_ sender: NSButton) {
        textAlignment = .center
        updateAlignmentButtons()
        onAlignmentChanged?(.center)
    }

    @objc private func alignRightTapped(_ sender: NSButton) {
        textAlignment = .right
        updateAlignmentButtons()
        onAlignmentChanged?(.right)
    }

    private func updateAlignmentButtons() {
        let active = NSColor(calibratedWhite: 0.05, alpha: 1.0)
        let inactive = NSColor(calibratedWhite: 0.45, alpha: 1.0)
        alignLeftButton?.contentTintColor = textAlignment == .left ? active : inactive
        alignCenterButton?.contentTintColor = textAlignment == .center ? active : inactive
        alignRightButton?.contentTintColor = textAlignment == .right ? active : inactive
    }

    @objc private func fontChanged(_ sender: NSPopUpButton) {
        let title = sender.titleOfSelectedItem
        if title == "System Font" {
            selectedFontName = nil
        } else {
            selectedFontName = title
        }
        onFontNameChanged?(selectedFontName)
    }

    @objc private func colorWellChanged(_ sender: NSColorWell) {
        // Deselect all preset dots when custom color is picked
        selectedColorIndex = -1
        for dot in colorDots {
            dot.isSelected = false
        }
        updateToolActiveColor(sender.color)
        onColorChanged?(sender.color)
    }

    private func selectColor(at index: Int) {
        guard index >= 0, index < AnnotationToolbar.colorPresets.count else { return }
        selectedColorIndex = index
        for (i, dot) in colorDots.enumerated() {
            dot.isSelected = (i == index)
        }
        // Sync color well to match selected preset
        let color = AnnotationToolbar.colorPresets[index]
        colorWell?.color = color
        updateToolActiveColor(color)
        onColorChanged?(color)
    }

    // MARK: - Custom Color Presets

    @objc private func addFavoriteColor(_ sender: NSButton) {
        let color = colorWell?.color ?? NSColor.black
        let hex = color.hexString

        // Check if color already exists in presets
        if AnnotationToolbar.colorPresets.contains(where: { $0.hexString == hex }) {
            NSSound.beep()
            return
        }

        // Cap at 10 total presets
        if AnnotationToolbar.colorPresets.count >= 10 {
            let alert = NSAlert()
            alert.messageText = "Preset limit reached"
            alert.informativeText = "You can have up to 10 color presets. Right-click a custom color to remove it."
            alert.runModal()
            return
        }

        AnnotationToolbar.colorPresets.append(color)
        AnnotationToolbar.saveCustomColors()
        rebuildColorDots()
        selectColor(at: AnnotationToolbar.colorPresets.count - 1)
    }

    @objc private func removeCustomColor(_ gesture: NSClickGestureRecognizer) {
        guard let dot = gesture.view as? ColorDotButton,
              dot.index >= AnnotationToolbar.builtInColorCount else { return }
        let index = dot.index
        AnnotationToolbar.colorPresets.remove(at: index)
        AnnotationToolbar.saveCustomColors()
        if selectedColorIndex >= AnnotationToolbar.colorPresets.count {
            selectedColorIndex = AnnotationToolbar.colorPresets.count - 1
        }
        rebuildColorDots()
        // Re-apply selection visually
        if selectedColorIndex >= 0 {
            let color = AnnotationToolbar.colorPresets[selectedColorIndex]
            for (i, d) in colorDots.enumerated() {
                d.isSelected = (i == selectedColorIndex)
            }
            colorWell?.color = color
            updateToolActiveColor(color)
        }
    }

    private func rebuildColorDots() {
        // Remove existing dot views from the color stack
        for dot in colorDots {
            dot.removeFromSuperview()
        }
        colorDots.removeAll()

        // Re-create dots for all presets, inserted before the color well / "+" button
        for (index, color) in AnnotationToolbar.colorPresets.enumerated() {
            let dot = ColorDotButton(color: color, index: index)
            dot.isSelected = (index == selectedColorIndex)
            dot.action = { [weak self] tappedIndex in
                self?.selectColor(at: tappedIndex)
            }
            // Right-click to remove custom (non-built-in) colors
            if index >= AnnotationToolbar.builtInColorCount {
                let rightClick = NSClickGestureRecognizer(target: self, action: #selector(removeCustomColor(_:)))
                rightClick.buttonMask = 2 // right mouse button
                rightClick.numberOfClicksRequired = 1
                dot.addGestureRecognizer(rightClick)
                dot.toolTip = "Right-click to remove"
            }
            colorStack?.insertArrangedSubview(dot, at: index)
            colorDots.append(dot)
        }
    }

    /// Push the current annotation color into every tool button so the active
    /// indicator renders in the right color.
    private func updateToolActiveColor(_ color: NSColor) {
        for (_, btn) in toolButtons {
            btn.activeColor = color
        }
    }

}
