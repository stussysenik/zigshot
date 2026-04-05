import AppKit
import CZigShot

/// The annotation canvas. Displays the captured image and handles mouse events for drawing.
///
/// Rendering pipeline — two layers, one view:
/// 1. Base layer: Original capture + committed annotations (Zig pixel buffer → CGImage)
/// 2. Preview layer: In-progress annotation drawn with Core Graphics (updates every mouseDragged)
final class AnnotationEditorView: NSView {

    // MARK: - State

    /// The working image with committed annotations (Zig-owned pixels).
    private(set) var workingImage: ZigShotImage
    /// Pristine copy of original capture (never modified — used for undo reset).
    let originalImage: ZigShotImage

    let model: AnnotationModel

    /// The active tool handler. Defaults to Arrow.
    var activeToolHandler: AnnotationToolHandler = ArrowToolHandler()
    /// Current annotation color.
    var currentColor: NSColor = NSColor(red: 1.0, green: 0.231, blue: 0.188, alpha: 1.0) // #FF3B30
    /// Current stroke width.
    var currentStrokeWidth: UInt32 = 3
    /// Currently selected annotation index (nil = none).
    var selectedAnnotationIndex: Int?
    /// Toolbar reference (set by window during setup).
    weak var toolbar: AnnotationToolbar?
    /// Persistent NumberingToolHandler so the counter survives tool switches.
    private let numberingHandler = NumberingToolHandler()

    /// In-progress drawing state for Core Graphics preview.
    private var drawStartPoint: CGPoint?
    private var drawCurrentPoint: CGPoint?
    private var isDrawing = false

    /// Selection drag state.
    private var isDraggingSelection = false
    private var dragOffset: CGPoint = .zero

    /// Image rect in view coordinates (centered with padding).
    private(set) var imageRect: CGRect = .zero

    // MARK: - Init

    init(workingImage: ZigShotImage, originalImage: ZigShotImage, model: AnnotationModel) {
        self.workingImage = workingImage
        self.originalImage = originalImage
        self.model = model
        super.init(frame: .zero)

        wantsLayer = true
        layerContentsRedrawPolicy = .onSetNeedsDisplay

        model.onChange = { [weak self] in
            self?.rerender()
        }
    }

    required init?(coder: NSCoder) { fatalError("Not implemented") }

    // MARK: - Layout

    override func layout() {
        super.layout()
        recalcImageRect()
    }

    /// Centers the image in the view with proportional sizing.
    private func recalcImageRect() {
        let imgW = CGFloat(workingImage.width)
        let imgH = CGFloat(workingImage.height)
        let viewW = bounds.width
        let viewH = bounds.height

        // Fit image within 90% of view bounds, leave room for toolbar below
        let maxW = viewW * 0.9
        let maxH = viewH * 0.85
        let scale = min(maxW / imgW, maxH / imgH, 1.0) // Never upscale

        let drawW = imgW * scale
        let drawH = imgH * scale
        let x = (viewW - drawW) / 2
        let y = (viewH - drawH) / 2 + 20

        imageRect = CGRect(x: x, y: y, width: drawW, height: drawH)
    }

    // MARK: - Coordinate transforms

    /// Convert view coordinates to image pixel coordinates.
    func viewToImage(_ viewPoint: CGPoint) -> CGPoint {
        let imgW = CGFloat(workingImage.width)
        let imgH = CGFloat(workingImage.height)
        let scaleX = imgW / imageRect.width
        let scaleY = imgH / imageRect.height
        return CGPoint(
            x: (viewPoint.x - imageRect.origin.x) * scaleX,
            y: (viewPoint.y - imageRect.origin.y) * scaleY
        )
    }

    /// Convert image pixel coordinates to view coordinates.
    func imageToView(_ imgPoint: CGPoint) -> CGPoint {
        let imgW = CGFloat(workingImage.width)
        let imgH = CGFloat(workingImage.height)
        let scaleX = imageRect.width / imgW
        let scaleY = imageRect.height / imgH
        return CGPoint(
            x: imgPoint.x * scaleX + imageRect.origin.x,
            y: imgPoint.y * scaleY + imageRect.origin.y
        )
    }

    // MARK: - Rendering

    /// Re-render all annotations from the original image.
    func rerender() {
        workingImage.copyPixels(from: originalImage)
        model.renderAll(onto: workingImage)
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }

        // Layer 1: Zig pixel buffer as CGImage
        if let cgImage = workingImage.cgImage() {
            // Drop shadow behind image
            ctx.setShadow(offset: CGSize(width: 0, height: -4), blur: 20,
                          color: NSColor.black.withAlphaComponent(0.5).cgColor)
            ctx.draw(cgImage, in: imageRect)
            ctx.setShadow(offset: .zero, blur: 0)
        }

        // Layer 2: In-progress annotation preview (Core Graphics)
        if isDrawing, let start = drawStartPoint, let current = drawCurrentPoint {
            let viewStart = imageToView(start)
            let viewCurrent = imageToView(current)
            let handler = activeToolHandler
            handler.drawPreview(
                in: ctx,
                from: viewStart,
                to: viewCurrent,
                color: currentColor,
                width: CGFloat(currentStrokeWidth),
                imageRect: imageRect
            )
        }

        // Selection handles
        if let idx = selectedAnnotationIndex, idx < model.annotations.count {
            drawSelectionHandles(ctx, for: model.annotations[idx])
        }
    }

    private func drawSelectionHandles(_ ctx: CGContext, for annotation: AnnotationDescriptor) {
        ctx.saveGState()
        let bounds = annotation.bounds
        let corners = [
            imageToView(CGPoint(x: bounds.minX, y: bounds.minY)),
            imageToView(CGPoint(x: bounds.maxX, y: bounds.minY)),
            imageToView(CGPoint(x: bounds.maxX, y: bounds.maxY)),
            imageToView(CGPoint(x: bounds.minX, y: bounds.maxY)),
        ]

        ctx.setFillColor(NSColor.white.withAlphaComponent(0.6).cgColor)
        ctx.setStrokeColor(NSColor.white.cgColor)
        ctx.setLineWidth(1.0)
        for corner in corners {
            let handle = CGRect(x: corner.x - 3, y: corner.y - 3, width: 6, height: 6)
            ctx.fillEllipse(in: handle)
            ctx.strokeEllipse(in: handle)
        }
        ctx.restoreGState()
    }

    // MARK: - Coordinate system

    /// Flip the view so Y=0 is at the top-left, matching the Zig pixel buffer origin.
    /// Without this, AppKit's default bottom-left origin would require manual Y-flipping
    /// in every coordinate transform.
    override var isFlipped: Bool { true }

    // MARK: - Mouse events

    override var acceptsFirstResponder: Bool { true }

    override func mouseDown(with event: NSEvent) {
        let viewPoint = convert(event.locationInWindow, from: nil)
        let imgPoint = viewToImage(viewPoint)

        // Only handle clicks inside the image
        guard imageRect.contains(viewPoint) else { return }

        // Hit-test existing annotations only when using Arrow (default) tool.
        // Other tools always draw new annotations, even over existing ones.
        if activeToolHandler is ArrowToolHandler, let hitIndex = hitTest(at: imgPoint) {
            selectedAnnotationIndex = hitIndex
            isDraggingSelection = true
            let annotBounds = model.annotations[hitIndex].bounds
            dragOffset = CGPoint(
                x: imgPoint.x - annotBounds.origin.x,
                y: imgPoint.y - annotBounds.origin.y
            )
            needsDisplay = true
            return
        }

        // Deselect if clicking empty space
        selectedAnnotationIndex = nil
        isDraggingSelection = false

        // Start drawing with active tool
        let handler = activeToolHandler
        drawStartPoint = imgPoint
        drawCurrentPoint = imgPoint
        isDrawing = true
        handler.start(at: imgPoint)
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        let viewPoint = convert(event.locationInWindow, from: nil)
        // Clamp to imageRect so off-canvas drags don't produce out-of-bounds image coordinates.
        let clampedPoint = CGPoint(
            x: min(max(viewPoint.x, imageRect.minX), imageRect.maxX),
            y: min(max(viewPoint.y, imageRect.minY), imageRect.maxY)
        )
        let imgPoint = viewToImage(clampedPoint)

        if isDraggingSelection, let idx = selectedAnnotationIndex, idx < model.annotations.count {
            let newOrigin = CGPoint(x: imgPoint.x - dragOffset.x, y: imgPoint.y - dragOffset.y)
            let annotation = model.annotations[idx]
            if let moved = moveAnnotation(annotation, to: newOrigin) {
                model.update(at: idx, to: moved)
            }
            return
        }

        guard isDrawing else { return }
        drawCurrentPoint = imgPoint
        let handler = activeToolHandler
        handler.update(to: imgPoint)
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        if isDraggingSelection {
            isDraggingSelection = false
            rerender()
            return
        }

        guard isDrawing, let start = drawStartPoint, let current = drawCurrentPoint else { return }
        isDrawing = false

        let handler = activeToolHandler
        if let annotation = handler.finish(
            from: start, to: current,
            color: currentColor, width: currentStrokeWidth
        ) {
            model.add(annotation)
        }

        drawStartPoint = nil
        drawCurrentPoint = nil
        needsDisplay = true
    }

    // MARK: - Hit-testing

    /// Find the topmost annotation at the given image-space point.
    private func hitTest(at point: CGPoint) -> Int? {
        for i in model.annotations.indices.reversed() {
            let bounds = model.annotations[i].bounds.insetBy(dx: -4, dy: -4)
            if bounds.contains(point) {
                return i
            }
        }
        return nil
    }

    // MARK: - Annotation movement

    private func moveAnnotation(_ annotation: AnnotationDescriptor,
                                to newOrigin: CGPoint) -> AnnotationDescriptor? {
        switch annotation {
        case .arrow(let from, let to, let color, let width):
            let dx = newOrigin.x - annotation.bounds.origin.x
            let dy = newOrigin.y - annotation.bounds.origin.y
            return .arrow(from: CGPoint(x: from.x + dx, y: from.y + dy),
                          to: CGPoint(x: to.x + dx, y: to.y + dy),
                          color: color, width: width)
        case .rectangle(let rect, let color, let width):
            return .rectangle(rect: CGRect(origin: newOrigin, size: rect.size),
                              color: color, width: width)
        case .line(let from, let to, let color, let width):
            let dx = newOrigin.x - annotation.bounds.origin.x
            let dy = newOrigin.y - annotation.bounds.origin.y
            return .line(from: CGPoint(x: from.x + dx, y: from.y + dy),
                         to: CGPoint(x: to.x + dx, y: to.y + dy),
                         color: color, width: width)
        case .blur(let rect, let radius):
            return .blur(rect: CGRect(origin: newOrigin, size: rect.size), radius: radius)
        case .highlight(let rect, let color):
            return .highlight(rect: CGRect(origin: newOrigin, size: rect.size), color: color)
        case .ruler(let from, let to, let color, let width):
            let dx = newOrigin.x - annotation.bounds.origin.x
            let dy = newOrigin.y - annotation.bounds.origin.y
            return .ruler(from: CGPoint(x: from.x + dx, y: from.y + dy),
                          to: CGPoint(x: to.x + dx, y: to.y + dy),
                          color: color, width: width)
        case .numbering(_, let number, let color):
            return .numbering(position: newOrigin, number: number, color: color)
        case .text(_, let content, let fontSize, let color):
            return .text(position: newOrigin, content: content, fontSize: fontSize, color: color)
        }
    }

    // MARK: - Keyboard

    override func keyDown(with event: NSEvent) {
        // Cmd+Z / Cmd+Shift+Z for undo/redo
        if event.modifierFlags.contains(.command) {
            if event.charactersIgnoringModifiers == "z" {
                if event.modifierFlags.contains(.shift) {
                    model.redo()
                } else {
                    model.undo()
                }
                selectedAnnotationIndex = nil
                rerender()
                return
            }
            if event.charactersIgnoringModifiers == "s" {
                (window as? AnnotationEditorWindow)?.onSave?()
                return
            }
            if event.charactersIgnoringModifiers == "c" {
                (window as? AnnotationEditorWindow)?.onCopy?()
                return
            }
        }

        // Escape
        if event.keyCode == 53 {
            if isDrawing {
                isDrawing = false
                drawStartPoint = nil
                drawCurrentPoint = nil
                needsDisplay = true
            } else {
                (window as? AnnotationEditorWindow)?.onDiscard?()
            }
            return
        }

        // Delete / Forward Delete
        if event.keyCode == 51 || event.keyCode == 117 {
            if let idx = selectedAnnotationIndex {
                model.remove(at: idx)
                selectedAnnotationIndex = nil
                rerender()
            }
            return
        }

        // Enter = Copy and close
        if event.keyCode == 36 {
            (window as? AnnotationEditorWindow)?.onCopy?()
            return
        }

        // Tool switching via keyboard (only when not in a modifier key combo)
        guard !event.modifierFlags.contains(.command) else { return }
        let key = event.charactersIgnoringModifiers?.lowercased() ?? ""
        switch key {
        case "a": switchTool(.arrow)
        case "r": switchTool(.rectangle)
        case "b": switchTool(.blur)
        case "h": switchTool(.highlight)
        case "t": switchTool(.text)
        case "l": switchTool(.line)
        case "u": switchTool(.ruler)
        case "n": switchTool(.numbering)
        // Color presets
        case "1": currentColor = AnnotationToolbar.colorPresets[0]
        case "2": currentColor = AnnotationToolbar.colorPresets[1]
        case "3": currentColor = AnnotationToolbar.colorPresets[2]
        case "4": currentColor = AnnotationToolbar.colorPresets[3]
        case "5": currentColor = AnnotationToolbar.colorPresets[4]
        // Stroke width
        case "[": currentStrokeWidth = max(1, currentStrokeWidth - 1)
        case "]": currentStrokeWidth = min(20, currentStrokeWidth + 1)
        default: break
        }
    }

    // MARK: - Tool switching

    func switchTool(_ tool: AnnotationTool) {
        switch tool {
        case .arrow: activeToolHandler = ArrowToolHandler()
        case .rectangle: activeToolHandler = RectangleToolHandler()
        case .blur: activeToolHandler = BlurToolHandler()
        case .highlight: activeToolHandler = HighlightToolHandler()
        case .text:
            let handler = TextToolHandler()
            handler.editorView = self
            activeToolHandler = handler
        case .line: activeToolHandler = LineToolHandler()
        case .ruler: activeToolHandler = RulerToolHandler()
        case .numbering: activeToolHandler = numberingHandler // Persist counter
        }
        toolbar?.selectTool(tool)
    }
}
