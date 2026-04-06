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
    /// Pristine copy of original capture (reset target for undo).
    /// Replaced when image transforms (crop, rotate, flip) are applied.
    private(set) var originalImage: ZigShotImage

    let model: AnnotationModel

    /// The active tool handler. Defaults to Arrow.
    var activeToolHandler: AnnotationToolHandler = ArrowToolHandler()
    /// Current annotation color.
    var currentColor: NSColor = NSColor(red: 1.0, green: 0.231, blue: 0.188, alpha: 1.0) // #FF3B30
    /// Current stroke width.
    var currentStrokeWidth: UInt32 = 4
    /// Current font size for text and sticky note annotations.
    var currentFontSize: CGFloat = 16
    /// Current font name (nil = system font).
    var currentFontName: String?
    /// Current bold state for text annotations.
    var currentBold: Bool = false
    /// Current italic state for text annotations.
    var currentItalic: Bool = false
    /// Current text alignment.
    var currentAlignment: NSTextAlignment = .left
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

    // MARK: - Zoom

    /// Current zoom level (1.0 = fit-to-view).
    private(set) var zoomLevel: CGFloat = 1.0
    private let minZoom: CGFloat = 0.25
    private let maxZoom: CGFloat = 4.0

    /// Discrete zoom steps for zoomIn/zoomOut.
    private let zoomSteps: [CGFloat] = [0.25, 0.5, 0.75, 1.0, 1.25, 1.5, 2.0, 3.0, 4.0]

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

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.makeFirstResponder(self)
    }

    // MARK: - Layout

    override func layout() {
        super.layout()
        recalcImageRect()
    }

    /// Centers the image in the view with proportional sizing, scaled by `zoomLevel`.
    private func recalcImageRect() {
        let imgW = CGFloat(workingImage.width)
        let imgH = CGFloat(workingImage.height)
        let viewW = bounds.width
        let viewH = bounds.height

        // Fit image within 90% of available space, leave 60px for toolbar at bottom
        let maxW = viewW * 0.9
        let maxH = (viewH - 60) * 0.90
        let fitScale = min(maxW / imgW, maxH / imgH, 1.0) // Never upscale at 1x zoom
        let scale = fitScale * zoomLevel

        let drawW = imgW * scale
        let drawH = imgH * scale
        let x = (viewW - drawW) / 2
        let y = (viewH - 60 - drawH) / 2  // Center in available space above toolbar

        imageRect = CGRect(x: x, y: y, width: drawW, height: drawH)
    }

    // MARK: - Zoom controls

    /// Set an explicit zoom level, clamped to [minZoom, maxZoom].
    func setZoomLevel(_ level: CGFloat) {
        zoomLevel = min(max(level, minZoom), maxZoom)
        recalcImageRect()
        needsDisplay = true
        toolbar?.updateZoomLabel(zoomLevel)
    }

    /// Step zoom in to the next discrete level.
    func zoomIn() {
        if let next = zoomSteps.first(where: { $0 > zoomLevel + 0.001 }) {
            setZoomLevel(next)
        }
    }

    /// Step zoom out to the previous discrete level.
    func zoomOut() {
        if let prev = zoomSteps.last(where: { $0 < zoomLevel - 0.001 }) {
            setZoomLevel(prev)
        }
    }

    /// Reset zoom to 1.0 (fit-to-view).
    func zoomToFit() {
        setZoomLevel(1.0)
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

        // Light gray canvas background
        ctx.setFillColor(NSColor(calibratedWhite: 0.94, alpha: 1.0).cgColor)
        ctx.fill(dirtyRect)

        // Layer 1: Zig pixel buffer as CGImage
        if let cgImage = workingImage.cgImage() {
            // Shadow: filled shape behind the image casts the drop shadow
            ctx.saveGState()
            ctx.setShadow(offset: CGSize(width: 0, height: 4), blur: 20,
                          color: NSColor.black.withAlphaComponent(0.3).cgColor)
            ctx.setFillColor(NSColor.white.cgColor)
            let shadowPath = CGPath(roundedRect: imageRect, cornerWidth: 8, cornerHeight: 8, transform: nil)
            ctx.addPath(shadowPath)
            ctx.fillPath()
            ctx.restoreGState()

            // Image: clipped to rounded rect.
            // In a flipped NSView, CGContext.draw() renders images upside-down
            // because it maps the image bottom to rect.minY (which is the view top).
            // Counter-flip around the image rect's vertical center.
            ctx.saveGState()
            let clipPath = CGPath(roundedRect: imageRect, cornerWidth: 8, cornerHeight: 8, transform: nil)
            ctx.addPath(clipPath)
            ctx.clip()
            ctx.translateBy(x: 0, y: imageRect.minY + imageRect.maxY)
            ctx.scaleBy(x: 1, y: -1)
            ctx.draw(cgImage, in: imageRect)
            ctx.restoreGState()
        }

        // Layer 2: In-progress annotation preview (Core Graphics)
        if isDrawing, let start = drawStartPoint, let current = drawCurrentPoint {
            let viewStart = imageToView(start)
            let viewCurrent = imageToView(current)
            let handler = activeToolHandler
            // Provide image dimensions so crop/ruler handlers can show correct pixel values
            if let cropHandler = handler as? CropToolHandler {
                cropHandler.imageSize = CGSize(width: CGFloat(workingImage.width),
                                               height: CGFloat(workingImage.height))
            }
            if let rulerHandler = handler as? RulerToolHandler {
                rulerHandler.imageSize = CGSize(width: CGFloat(workingImage.width),
                                                height: CGFloat(workingImage.height))
            }
            // Highlight brush: draw full freehand path in view-space
            if let hlHandler = handler as? HighlightToolHandler {
                hlHandler.drawFreehandPreview(in: ctx, color: currentColor,
                                              imageToView: { self.imageToView($0) })
            } else {
                handler.drawPreview(
                    in: ctx,
                    from: viewStart,
                    to: viewCurrent,
                    color: currentColor,
                    width: CGFloat(currentStrokeWidth),
                    imageRect: imageRect
                )
            }
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

        // Dashed selection outline
        let accentColor = NSColor.controlAccentColor
        ctx.setStrokeColor(accentColor.cgColor)
        ctx.setLineWidth(1.5)
        ctx.setLineDash(phase: 0, lengths: [5, 3])
        ctx.move(to: corners[0])
        for i in 1 ..< corners.count { ctx.addLine(to: corners[i]) }
        ctx.closePath()
        ctx.strokePath()
        ctx.setLineDash(phase: 0, lengths: [])

        // Corner handles — 10px white circles with accent border
        let handleSize: CGFloat = 10
        for corner in corners {
            let handle = CGRect(x: corner.x - handleSize / 2, y: corner.y - handleSize / 2,
                                width: handleSize, height: handleSize)
            ctx.setFillColor(NSColor.white.cgColor)
            ctx.fillEllipse(in: handle)
            ctx.setStrokeColor(accentColor.cgColor)
            ctx.setLineWidth(1.5)
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
            // Double-click on text annotation → re-edit in place
            if event.clickCount == 2,
               case let .text(position, content, fontSize, color, fontName, isBold, isItalic, alignment) = model.annotations[hitIndex] {
                selectedAnnotationIndex = nil
                let editIndex = hitIndex
                let viewPos = imageToView(position)
                let textHandler = TextToolHandler()
                textHandler.editorView = self
                textHandler.textController.beginEditing(
                    in: self,
                    at: viewPos,
                    imagePosition: position,
                    fontSize: fontSize,
                    color: color,
                    initialText: content
                ) { [weak self] text, pos, size, col in
                    guard let self = self else { return }
                    let newAnnotation = AnnotationDescriptor.text(
                        position: pos, content: text, fontSize: size, color: col,
                        fontName: fontName, isBold: isBold, isItalic: isItalic, alignment: alignment
                    )
                    self.model.update(at: editIndex, to: newAnnotation)
                    self.rerender()
                }
                return
            }

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

        // Crop tool: apply crop and switch back to arrow
        if activeToolHandler is CropToolHandler {
            let cropRect = CGRect(
                x: min(start.x, current.x), y: min(start.y, current.y),
                width: abs(current.x - start.x), height: abs(current.y - start.y)
            )
            drawStartPoint = nil
            drawCurrentPoint = nil
            if cropRect.width >= 5, cropRect.height >= 5 {
                applyCrop(rect: cropRect)
            } else {
                needsDisplay = true
            }
            return
        }

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
            let bounds = model.annotations[i].bounds.insetBy(dx: -8, dy: -8)
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
        case .highlightPath(let points, let color, let width, let opacity):
            guard !points.isEmpty else { return nil }
            let dx = newOrigin.x - annotation.bounds.origin.x
            let dy = newOrigin.y - annotation.bounds.origin.y
            let moved = points.map { CGPoint(x: $0.x + dx, y: $0.y + dy) }
            return .highlightPath(points: moved, color: color, width: width, opacity: opacity)
        case .ruler(let from, let to, let color, let width):
            let dx = newOrigin.x - annotation.bounds.origin.x
            let dy = newOrigin.y - annotation.bounds.origin.y
            return .ruler(from: CGPoint(x: from.x + dx, y: from.y + dy),
                          to: CGPoint(x: to.x + dx, y: to.y + dy),
                          color: color, width: width)
        case .numbering(_, let number, let color):
            return .numbering(position: newOrigin, number: number, color: color)
        case .text(_, let content, let fontSize, let color, let fontName, let isBold, let isItalic, let alignment):
            return .text(position: newOrigin, content: content, fontSize: fontSize, color: color,
                         fontName: fontName, isBold: isBold, isItalic: isItalic, alignment: alignment)
        case .stickyNote(let rect, let content, let fontSize, let bgColor, let textColor, let fontName, let isBold, let isItalic, let alignment):
            return .stickyNote(rect: CGRect(origin: newOrigin, size: rect.size),
                               content: content, fontSize: fontSize,
                               backgroundColor: bgColor, textColor: textColor,
                               fontName: fontName, isBold: isBold, isItalic: isItalic, alignment: alignment)
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
                if event.modifierFlags.contains(.shift) {
                    // Cmd+Shift+S = Share
                    if let shareBtn = (window as? AnnotationEditorWindow)?.shareButton {
                        (window as? AnnotationEditorWindow)?.onShare?(shareBtn)
                    }
                } else {
                    // Cmd+S = Quick Save
                    (window as? AnnotationEditorWindow)?.onQuickSave?()
                }
                return
            }
            if event.charactersIgnoringModifiers == "c" {
                (window as? AnnotationEditorWindow)?.onCopy?()
                return
            }
            if event.charactersIgnoringModifiers == "w" {
                (window as? AnnotationEditorWindow)?.dismiss()
                return
            }
            // Zoom: Cmd+= / Cmd++ zooms in, Cmd+- zooms out, Cmd+0 fits
            if event.charactersIgnoringModifiers == "=" || event.charactersIgnoringModifiers == "+" {
                zoomIn()
                return
            }
            if event.charactersIgnoringModifiers == "-" {
                zoomOut()
                return
            }
            if event.charactersIgnoringModifiers == "0" {
                zoomToFit()
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
        case "c": switchTool(.crop)
        case "a": switchTool(.arrow)
        case "r": switchTool(.rectangle)
        case "b": switchTool(.blur)
        case "h": switchTool(.highlight)
        case "t": switchTool(.text)
        case "l": switchTool(.line)
        case "u": switchTool(.ruler)
        case "n": switchTool(.numbering)
        case "s": switchTool(.stickyNote)
        case "e": switchTool(.eraser)
        case "o": switchTool(.ocr)
        case "p": NSColorPanel.shared.orderFront(nil)
        // Color presets
        case "1": currentColor = AnnotationToolbar.colorPresets[0]
        case "2": currentColor = AnnotationToolbar.colorPresets[1]
        case "3": currentColor = AnnotationToolbar.colorPresets[2]
        case "4": currentColor = AnnotationToolbar.colorPresets[3]
        case "5": currentColor = AnnotationToolbar.colorPresets[4]
        // Stroke width / highlight width+opacity
        case "[":
            if let hlHandler = activeToolHandler as? HighlightToolHandler {
                if event.modifierFlags.contains(.shift) {
                    hlHandler.highlightOpacity = max(0.2, hlHandler.highlightOpacity - 0.1)
                } else {
                    hlHandler.highlightWidth = max(8, hlHandler.highlightWidth - 2)
                }
            } else {
                currentStrokeWidth = max(1, currentStrokeWidth - 1)
            }
        case "]":
            if let hlHandler = activeToolHandler as? HighlightToolHandler {
                if event.modifierFlags.contains(.shift) {
                    hlHandler.highlightOpacity = min(0.8, hlHandler.highlightOpacity + 0.1)
                } else {
                    hlHandler.highlightWidth = min(40, hlHandler.highlightWidth + 2)
                }
            } else {
                currentStrokeWidth = min(20, currentStrokeWidth + 1)
            }
        default: break
        }
    }

    // MARK: - Scroll wheel zoom

    override func scrollWheel(with event: NSEvent) {
        if event.modifierFlags.contains(.command) || event.momentumPhase != [] {
            let delta: CGFloat = event.scrollingDeltaY > 0 ? 0.1 : -0.1
            setZoomLevel(zoomLevel + delta)
        }
    }

    // MARK: - Cursor

    override func resetCursorRects() {
        let cursor: NSCursor
        if activeToolHandler is ArrowToolHandler {
            cursor = .arrow
        } else if activeToolHandler is TextToolHandler {
            cursor = .iBeam
        } else {
            cursor = .crosshair
        }
        addCursorRect(imageRect, cursor: cursor)
    }

    // MARK: - Tool switching

    func switchTool(_ tool: AnnotationTool) {
        // Commit any pending text edit from the outgoing tool
        if let textHandler = activeToolHandler as? TextToolHandler {
            textHandler.textController.endEditing()
        }

        switch tool {
        case .crop: activeToolHandler = CropToolHandler()
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
        case .stickyNote:
            let handler = StickyNoteToolHandler()
            handler.editorView = self
            activeToolHandler = handler
        case .eraser:
            let handler = EraserToolHandler()
            handler.editorView = self
            activeToolHandler = handler
        case .ocr:
            let handler = OcrToolHandler()
            handler.editorView = self
            activeToolHandler = handler
        }
        toolbar?.selectTool(tool)
        window?.invalidateCursorRects(for: self)
    }

    // MARK: - Image transforms

    /// Apply crop, preserving annotations by transforming their coordinates
    /// into the new cropped image space. Annotations outside the crop are removed.
    func applyCrop(rect: CGRect) {
        // Crop the ORIGINAL image (without annotations baked in)
        guard let newOriginal = ZigShotImage.cropped(from: originalImage, rect: rect),
              let newWorking = ZigShotImage(width: newOriginal.width, height: newOriginal.height)
        else { return }
        newWorking.copyPixels(from: newOriginal)

        // Transform annotation coordinates to new crop space
        model.transformForCrop(cropRect: rect)

        // Replace images WITHOUT clearing annotations
        workingImage = newWorking
        originalImage = newOriginal
        selectedAnnotationIndex = nil
        recalcImageRect()
        rerender()

        if let win = window as? AnnotationEditorWindow {
            win.title = "Screenshot \u{2014} \(workingImage.width) \u{00D7} \(workingImage.height)"
        }
        switchTool(.arrow)
    }

    /// Rotate the image 90° clockwise.
    func rotateImage90CW() {
        rerender()
        guard let newOriginal = ZigShotImage.rotated90CW(from: workingImage),
              let newWorking = ZigShotImage(width: newOriginal.width, height: newOriginal.height)
        else { return }
        newWorking.copyPixels(from: newOriginal)
        replaceImages(working: newWorking, original: newOriginal)
    }

    /// Rotate the image 90° counter-clockwise.
    func rotateImage90CCW() {
        rerender()
        guard let newOriginal = ZigShotImage.rotated90CCW(from: workingImage),
              let newWorking = ZigShotImage(width: newOriginal.width, height: newOriginal.height)
        else { return }
        newWorking.copyPixels(from: newOriginal)
        replaceImages(working: newWorking, original: newOriginal)
    }

    /// Flip the image horizontally (mirror left���right).
    func flipImageH() {
        rerender()
        guard let newOriginal = ZigShotImage.flippedH(from: workingImage),
              let newWorking = ZigShotImage(width: newOriginal.width, height: newOriginal.height)
        else { return }
        newWorking.copyPixels(from: newOriginal)
        replaceImages(working: newWorking, original: newOriginal)
    }

    /// Flip the image vertically (mirror top↔bottom).
    func flipImageV() {
        rerender()
        guard let newOriginal = ZigShotImage.flippedV(from: workingImage),
              let newWorking = ZigShotImage(width: newOriginal.width, height: newOriginal.height)
        else { return }
        newWorking.copyPixels(from: newOriginal)
        replaceImages(working: newWorking, original: newOriginal)
    }

    /// Replace both images, clear annotations, update layout and window title.
    private func replaceImages(working: ZigShotImage, original: ZigShotImage) {
        workingImage = working
        originalImage = original
        model.clearAll()
        selectedAnnotationIndex = nil
        recalcImageRect()
        needsDisplay = true

        // Update window title with new dimensions
        if let win = window as? AnnotationEditorWindow {
            win.title = "Screenshot \u{2014} \(workingImage.width) \u{00D7} \(workingImage.height)"
        }
    }
}
