import AppKit

/// Contract for annotation tools. Each tool handles one drawing gesture.
///
/// Lifecycle: start(at:) → update(to:) (0+ times) → finish(from:to:) → AnnotationDescriptor
protocol AnnotationToolHandler: AnyObject {
    /// Called on mouseDown with image-space coordinates.
    func start(at point: CGPoint)
    /// Called on mouseDragged with image-space coordinates.
    func update(to point: CGPoint)
    /// Called on mouseUp. Returns the annotation to commit, or nil if too small.
    func finish(from start: CGPoint, to end: CGPoint,
                color: NSColor, width: UInt32) -> AnnotationDescriptor?
    /// Draw a Core Graphics preview of the in-progress annotation.
    func drawPreview(in ctx: CGContext, from: CGPoint, to: CGPoint,
                     color: NSColor, width: CGFloat, imageRect: CGRect)
}

// MARK: - Crop Tool

/// Drag to select crop region. Draws a dark overlay with the selected area cut out.
/// Returns nil from finish — the editor view handles crop application separately.
final class CropToolHandler: AnnotationToolHandler {
    /// Set by the editor before drawPreview so the dimension label shows image pixels.
    var imageSize: CGSize = .zero

    func start(at point: CGPoint) {}
    func update(to point: CGPoint) {}

    func finish(from start: CGPoint, to end: CGPoint,
                color: NSColor, width: UInt32) -> AnnotationDescriptor? {
        // Crop is handled by AnnotationEditorView, not the annotation model.
        return nil
    }

    func drawPreview(in ctx: CGContext, from: CGPoint, to: CGPoint,
                     color: NSColor, width: CGFloat, imageRect: CGRect) {
        // Dark overlay covering entire image
        ctx.saveGState()
        ctx.setFillColor(NSColor.black.withAlphaComponent(0.45).cgColor)

        let cropRect = CGRect(
            x: min(from.x, to.x), y: min(from.y, to.y),
            width: abs(to.x - from.x), height: abs(to.y - from.y)
        )

        // Fill the image area minus the crop selection (dark surround)
        let fullPath = CGMutablePath()
        fullPath.addRect(imageRect)
        fullPath.addRect(cropRect)
        ctx.addPath(fullPath)
        ctx.fillPath(using: .evenOdd)

        // Crop border — clean white outline
        ctx.setStrokeColor(NSColor.white.cgColor)
        ctx.setLineWidth(1.5)
        ctx.stroke(cropRect)

        // Corner handles — small white squares at each corner
        let handleSize: CGFloat = 8
        let corners = [
            CGPoint(x: cropRect.minX, y: cropRect.minY),
            CGPoint(x: cropRect.maxX, y: cropRect.minY),
            CGPoint(x: cropRect.maxX, y: cropRect.maxY),
            CGPoint(x: cropRect.minX, y: cropRect.maxY),
        ]
        ctx.setFillColor(NSColor.white.cgColor)
        for corner in corners {
            let handle = CGRect(
                x: corner.x - handleSize / 2, y: corner.y - handleSize / 2,
                width: handleSize, height: handleSize
            )
            ctx.fill(handle)
        }

        // Dimension label — image-space "W × H" centered below crop rect
        let viewCropW = abs(to.x - from.x)
        let viewCropH = abs(to.y - from.y)
        if viewCropW > 20, viewCropH > 20 {
            // Convert view-space dimensions to image-space pixels
            let scaleX = imageRect.width > 0 ? imageSize.width / imageRect.width : 1
            let scaleY = imageRect.height > 0 ? imageSize.height / imageRect.height : 1
            let imgW = viewCropW * scaleX
            let imgH = viewCropH * scaleY
            let label = String(format: "%.0f \u{00D7} %.0f", imgW, imgH)
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.monospacedSystemFont(ofSize: 11, weight: .medium),
                .foregroundColor: NSColor.white,
            ]
            let attrStr = NSAttributedString(string: label, attributes: attrs)
            let labelSize = attrStr.size()

            // Position label at bottom center of crop rect
            let labelX = cropRect.midX - labelSize.width / 2
            let labelY = cropRect.maxY + 6

            // Label background pill
            let pillRect = CGRect(
                x: labelX - 6, y: labelY - 2,
                width: labelSize.width + 12, height: labelSize.height + 4
            )
            let pillPath = CGPath(roundedRect: pillRect, cornerWidth: 4, cornerHeight: 4, transform: nil)
            ctx.setFillColor(NSColor.black.withAlphaComponent(0.7).cgColor)
            ctx.addPath(pillPath)
            ctx.fillPath()

            attrStr.draw(at: CGPoint(x: labelX, y: labelY))
        }

        ctx.restoreGState()
    }
}

// MARK: - Arrow Tool (Default)

/// The most common annotation. Click-drag to draw an arrow.
/// Default tool: if no tool is selected, Arrow is used.
final class ArrowToolHandler: AnnotationToolHandler {
    func start(at point: CGPoint) {}
    func update(to point: CGPoint) {}

    func finish(from start: CGPoint, to end: CGPoint,
                color: NSColor, width: UInt32) -> AnnotationDescriptor? {
        let dx = end.x - start.x
        let dy = end.y - start.y
        guard sqrt(dx * dx + dy * dy) >= 3 else { return nil }
        return .arrow(from: start, to: end, color: color, width: width)
    }

    func drawPreview(in ctx: CGContext, from: CGPoint, to: CGPoint,
                     color: NSColor, width: CGFloat, imageRect: CGRect) {
        ctx.setStrokeColor(color.cgColor)
        ctx.setLineWidth(width)
        ctx.setLineCap(.round)

        ctx.move(to: from)
        ctx.addLine(to: to)
        ctx.strokePath()

        // Arrowhead — scales with stroke width for visibility
        let angle = atan2(to.y - from.y, to.x - from.x)
        let headLength = max(width * 3.5, 14)
        let headAngle: CGFloat = .pi / 6

        let p1 = CGPoint(
            x: to.x - headLength * cos(angle - headAngle),
            y: to.y - headLength * sin(angle - headAngle)
        )
        let p2 = CGPoint(
            x: to.x - headLength * cos(angle + headAngle),
            y: to.y - headLength * sin(angle + headAngle)
        )

        ctx.setFillColor(color.cgColor)
        ctx.move(to: to)
        ctx.addLine(to: p1)
        ctx.addLine(to: p2)
        ctx.closePath()
        ctx.fillPath()
    }
}

// MARK: - Rectangle Tool

/// Draw rectangles. Shift-drag constrains to perfect square.
final class RectangleToolHandler: AnnotationToolHandler {
    func start(at point: CGPoint) {}
    func update(to point: CGPoint) {}

    func finish(from start: CGPoint, to end: CGPoint,
                color: NSColor, width: UInt32) -> AnnotationDescriptor? {
        let rect = CGRect(
            x: min(start.x, end.x), y: min(start.y, end.y),
            width: abs(end.x - start.x), height: abs(end.y - start.y)
        )
        guard rect.width >= 3 && rect.height >= 3 else { return nil }
        return .rectangle(rect: rect, color: color, width: width)
    }

    func drawPreview(in ctx: CGContext, from: CGPoint, to: CGPoint,
                     color: NSColor, width: CGFloat, imageRect: CGRect) {
        ctx.setStrokeColor(color.cgColor)
        ctx.setLineWidth(width)
        let rect = CGRect(
            x: min(from.x, to.x), y: min(from.y, to.y),
            width: abs(to.x - from.x), height: abs(to.y - from.y)
        )
        let path = CGPath(roundedRect: rect, cornerWidth: 4, cornerHeight: 4, transform: nil)
        ctx.addPath(path)
        ctx.strokePath()
    }
}

// MARK: - Line Tool

/// Draw straight lines. Shift-drag snaps to 45 degree angles.
final class LineToolHandler: AnnotationToolHandler {
    func start(at point: CGPoint) {}
    func update(to point: CGPoint) {}

    func finish(from start: CGPoint, to end: CGPoint,
                color: NSColor, width: UInt32) -> AnnotationDescriptor? {
        let dx = end.x - start.x
        let dy = end.y - start.y
        guard sqrt(dx * dx + dy * dy) >= 3 else { return nil }
        return .line(from: start, to: end, color: color, width: width)
    }

    func drawPreview(in ctx: CGContext, from: CGPoint, to: CGPoint,
                     color: NSColor, width: CGFloat, imageRect: CGRect) {
        ctx.setStrokeColor(color.cgColor)
        ctx.setLineWidth(width)
        ctx.setLineCap(.round)
        ctx.move(to: from)
        ctx.addLine(to: to)
        ctx.strokePath()
    }
}

// MARK: - Blur Tool

/// Drag a rectangle to blur the region underneath (redaction).
final class BlurToolHandler: AnnotationToolHandler {
    func start(at point: CGPoint) {}
    func update(to point: CGPoint) {}

    func finish(from start: CGPoint, to end: CGPoint,
                color: NSColor, width: UInt32) -> AnnotationDescriptor? {
        let rect = CGRect(
            x: min(start.x, end.x), y: min(start.y, end.y),
            width: abs(end.x - start.x), height: abs(end.y - start.y)
        )
        guard rect.width >= 5 && rect.height >= 5 else { return nil }
        return .blur(rect: rect, radius: 10)
    }

    func drawPreview(in ctx: CGContext, from: CGPoint, to: CGPoint,
                     color: NSColor, width: CGFloat, imageRect: CGRect) {
        let rect = CGRect(
            x: min(from.x, to.x), y: min(from.y, to.y),
            width: abs(to.x - from.x), height: abs(to.y - from.y)
        )
        ctx.setStrokeColor(NSColor.white.withAlphaComponent(0.5).cgColor)
        ctx.setLineWidth(1.5)
        ctx.setLineDash(phase: 0, lengths: [4, 4])
        ctx.stroke(rect)
        ctx.setLineDash(phase: 0, lengths: [])

        ctx.setFillColor(NSColor.white.withAlphaComponent(0.1).cgColor)
        ctx.fill(rect)
    }
}

// MARK: - Highlight Tool

/// Freehand brush-stroke highlight with rounded caps and adjustable opacity.
/// Tracks a path of points during drag, simplifies on finish.
final class HighlightToolHandler: AnnotationToolHandler {
    /// Collected freehand path points (image-space).
    private var path: [CGPoint] = []
    /// Current highlight brush width (image pixels). Adjustable via `[`/`]`.
    var highlightWidth: UInt32 = 20
    /// Current opacity (0.2–0.8). Adjustable via Shift+`[`/`]`.
    var highlightOpacity: CGFloat = 0.4

    func start(at point: CGPoint) { path = [point] }
    func update(to point: CGPoint) { path.append(point) }

    func finish(from start: CGPoint, to end: CGPoint,
                color: NSColor, width: UInt32) -> AnnotationDescriptor? {
        guard path.count >= 2 else {
            path.removeAll()
            return nil
        }
        let simplified = Self.simplifyPath(path, maxPoints: 100)
        path.removeAll()
        return .highlightPath(points: simplified, color: color,
                              width: highlightWidth, opacity: highlightOpacity)
    }

    func drawPreview(in ctx: CGContext, from: CGPoint, to: CGPoint,
                     color: NSColor, width: CGFloat, imageRect: CGRect) {
        guard path.count >= 2 else { return }
        // Convert image-space path to view-space for preview
        // We draw in view coords, but path is in image coords.
        // Use from/to to compute the scale factor.
        let previewOpacity = max(highlightOpacity - 0.1, 0.1)
        ctx.saveGState()
        ctx.setStrokeColor(color.withAlphaComponent(previewOpacity).cgColor)
        ctx.setLineWidth(CGFloat(highlightWidth) * imageRect.width / max(1, imageRect.width))
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)

        // Path is in image-space; we need to convert to view-space
        // Scale: imageRect.width / imageW, origin offset: imageRect.origin
        // But we don't have imageW here. Use the from/to mapping.
        // Actually, the preview is called with view-space from/to already.
        // We need to transform all path points. We'll use the same transform
        // the editor uses: (pt - imgOrigin) * scale + viewOrigin.
        // Since we don't have access to the view, just draw relative to imageRect.
        ctx.move(to: from)
        ctx.addLine(to: to)
        ctx.strokePath()
        ctx.restoreGState()
    }

    /// Draw the full freehand path in view-space. Called by AnnotationEditorView
    /// instead of the protocol's drawPreview for highlight strokes.
    func drawFreehandPreview(in ctx: CGContext, color: NSColor,
                             imageToView: (CGPoint) -> CGPoint) {
        guard path.count >= 2 else { return }
        let previewOpacity = max(highlightOpacity - 0.1, 0.1)
        ctx.saveGState()
        ctx.setStrokeColor(color.withAlphaComponent(previewOpacity).cgColor)
        // Scale width from image-space to view-space
        let viewP0 = imageToView(CGPoint.zero)
        let viewP1 = imageToView(CGPoint(x: CGFloat(highlightWidth), y: 0))
        let viewWidth = abs(viewP1.x - viewP0.x)
        ctx.setLineWidth(max(viewWidth, 2))
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)

        let first = imageToView(path[0])
        ctx.move(to: first)
        for i in 1 ..< path.count {
            ctx.addLine(to: imageToView(path[i]))
        }
        ctx.strokePath()
        ctx.restoreGState()
    }

    /// Ramer-Douglas-Peucker path simplification.
    static func simplifyPath(_ points: [CGPoint], maxPoints: Int) -> [CGPoint] {
        guard points.count > maxPoints else { return points }
        // Binary search for the right epsilon
        var lo: CGFloat = 0, hi: CGFloat = 100
        var result = points
        for _ in 0 ..< 20 {
            let mid = (lo + hi) / 2
            result = rdpSimplify(points, epsilon: mid)
            if result.count > maxPoints {
                lo = mid
            } else {
                hi = mid
            }
        }
        return result
    }

    private static func rdpSimplify(_ points: [CGPoint], epsilon: CGFloat) -> [CGPoint] {
        guard points.count > 2 else { return points }
        var maxDist: CGFloat = 0
        var maxIndex = 0
        let first = points[0], last = points[points.count - 1]
        for i in 1 ..< points.count - 1 {
            let d = perpendicularDistance(points[i], lineFrom: first, to: last)
            if d > maxDist { maxDist = d; maxIndex = i }
        }
        if maxDist > epsilon {
            let left = rdpSimplify(Array(points[0...maxIndex]), epsilon: epsilon)
            let right = rdpSimplify(Array(points[maxIndex...]), epsilon: epsilon)
            return left.dropLast() + right
        } else {
            return [first, last]
        }
    }

    private static func perpendicularDistance(_ point: CGPoint, lineFrom a: CGPoint, to b: CGPoint) -> CGFloat {
        let dx = b.x - a.x, dy = b.y - a.y
        let lenSq = dx * dx + dy * dy
        guard lenSq > 0 else {
            let px = point.x - a.x, py = point.y - a.y
            return sqrt(px * px + py * py)
        }
        let num = abs(dy * point.x - dx * point.y + b.x * a.y - b.y * a.x)
        return num / sqrt(lenSq)
    }
}

// MARK: - Ruler Tool

/// Drag to measure pixel distance. Shows px value along the line.
final class RulerToolHandler: AnnotationToolHandler {
    /// Set by the editor before drawPreview so the distance label shows image pixels.
    var imageSize: CGSize = .zero

    func start(at point: CGPoint) {}
    func update(to point: CGPoint) {}

    func finish(from start: CGPoint, to end: CGPoint,
                color: NSColor, width: UInt32) -> AnnotationDescriptor? {
        let dx = end.x - start.x
        let dy = end.y - start.y
        guard sqrt(dx * dx + dy * dy) >= 5 else { return nil }
        return .ruler(from: start, to: end, color: color, width: width)
    }

    func drawPreview(in ctx: CGContext, from: CGPoint, to: CGPoint,
                     color: NSColor, width: CGFloat, imageRect: CGRect) {
        ctx.setStrokeColor(color.cgColor)
        ctx.setLineWidth(width)
        ctx.setLineCap(.round)
        ctx.move(to: from)
        ctx.addLine(to: to)
        ctx.strokePath()

        // Distance label — convert view-space distance to image pixels
        let dx = to.x - from.x
        let dy = to.y - from.y
        let viewDist = sqrt(dx * dx + dy * dy)
        let scale = imageSize.width > 0 ? imageSize.width / imageRect.width : 1.0
        let dist = viewDist * scale
        let label = String(format: "%.0fpx", dist)
        let mid = CGPoint(x: (from.x + to.x) / 2, y: (from.y + to.y) / 2 - 12)
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 11, weight: .medium),
            .foregroundColor: color,
            .backgroundColor: NSColor.black.withAlphaComponent(0.6),
        ]
        NSAttributedString(string: " \(label) ", attributes: attrs).draw(at: mid)
    }
}

// MARK: - Numbering Tool

/// Click to place auto-incrementing numbered circles.
final class NumberingToolHandler: AnnotationToolHandler {
    var nextNumber: Int = {
        let saved = UserDefaults.standard.integer(forKey: "zigshot.numberingCounter")
        return saved > 0 ? saved : 1
    }()

    func start(at point: CGPoint) {}
    func update(to point: CGPoint) {}

    func finish(from start: CGPoint, to end: CGPoint,
                color: NSColor, width: UInt32) -> AnnotationDescriptor? {
        let number = nextNumber
        nextNumber += 1
        UserDefaults.standard.set(nextNumber, forKey: "zigshot.numberingCounter")
        return .numbering(position: start, number: number, color: color)
    }

    func drawPreview(in ctx: CGContext, from: CGPoint, to: CGPoint,
                     color: NSColor, width: CGFloat, imageRect: CGRect) {
        let size: CGFloat = 28
        let rect = CGRect(x: from.x - size / 2, y: from.y - size / 2, width: size, height: size)
        ctx.setFillColor(color.cgColor)
        ctx.fillEllipse(in: rect)

        let label = NSAttributedString(
            string: "\(nextNumber)",
            attributes: [
                .font: NSFont.systemFont(ofSize: 14, weight: .bold),
                .foregroundColor: NSColor.white,
            ]
        )
        let labelSize = label.size()
        label.draw(at: CGPoint(
            x: from.x - labelSize.width / 2,
            y: from.y - labelSize.height / 2
        ))
    }
}

// MARK: - Text Tool

/// Click to place text. Opens inline NSTextView for editing.
final class TextToolHandler: AnnotationToolHandler {
    weak var editorView: AnnotationEditorView?
    let textController = TextEditingController()

    func start(at point: CGPoint) {}
    func update(to point: CGPoint) {}

    func finish(from start: CGPoint, to end: CGPoint,
                color: NSColor, width: UInt32) -> AnnotationDescriptor? {
        guard let view = editorView else { return nil }

        let viewPoint = view.imageToView(start)
        let fontSize = view.currentFontSize
        let fontName = view.currentFontName
        let isBold = view.currentBold
        let isItalic = view.currentItalic
        let alignment = view.currentAlignment
        textController.beginEditing(
            in: view,
            at: viewPoint,
            imagePosition: start,
            fontSize: fontSize,
            color: color
        ) { [weak view] text, position, fontSize, color in
            guard let view = view else { return }
            let annotation = AnnotationDescriptor.text(
                position: position,
                content: text,
                fontSize: fontSize,
                color: color,
                fontName: fontName,
                isBold: isBold,
                isItalic: isItalic,
                alignment: alignment
            )
            view.model.add(annotation)
        }

        return nil
    }

    func drawPreview(in ctx: CGContext, from: CGPoint, to: CGPoint,
                     color: NSColor, width: CGFloat, imageRect: CGRect) {
        ctx.setStrokeColor(color.cgColor)
        ctx.setLineWidth(1.5)
        ctx.move(to: CGPoint(x: from.x, y: from.y - 10))
        ctx.addLine(to: CGPoint(x: from.x, y: from.y + 10))
        ctx.strokePath()
    }
}

// MARK: - Eraser Tool

/// Stroke over annotations to remove them. Tracks the drag path and removes
/// any annotation whose bounds intersect the path on mouseUp.
final class EraserToolHandler: AnnotationToolHandler {
    weak var editorView: AnnotationEditorView?
    private var erasePath: [CGPoint] = []

    func start(at point: CGPoint) { erasePath = [point] }
    func update(to point: CGPoint) { erasePath.append(point) }

    func finish(from start: CGPoint, to end: CGPoint,
                color: NSColor, width: UInt32) -> AnnotationDescriptor? {
        guard let view = editorView else { erasePath.removeAll(); return nil }

        // Find annotations whose bounds intersect the erase path
        var indicesToRemove: [Int] = []
        for (index, annotation) in view.model.annotations.enumerated() {
            let bounds = annotation.bounds.insetBy(dx: -8, dy: -8)
            if erasePath.contains(where: { bounds.contains($0) }) {
                indicesToRemove.append(index)
            }
        }
        // Remove from highest index first to preserve ordering
        for index in indicesToRemove.sorted(by: >) {
            view.model.remove(at: index)
        }
        erasePath.removeAll()
        return nil
    }

    func drawPreview(in ctx: CGContext, from: CGPoint, to: CGPoint,
                     color: NSColor, width: CGFloat, imageRect: CGRect) {
        // Dashed red line showing the erase stroke — points are in view coords
        ctx.saveGState()
        ctx.setStrokeColor(NSColor.systemRed.withAlphaComponent(0.6).cgColor)
        ctx.setLineWidth(max(width, 3))
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)
        ctx.setLineDash(phase: 0, lengths: [6, 4])

        ctx.move(to: from)
        ctx.addLine(to: to)
        ctx.strokePath()
        ctx.restoreGState()
    }
}

// MARK: - Sticky Note Tool

/// Drag to define a rectangle, then open inline text editor to type the note content.
/// Produces a `.stickyNote` annotation with a warm yellow background by default.
final class StickyNoteToolHandler: AnnotationToolHandler {
    weak var editorView: AnnotationEditorView?

    func start(at point: CGPoint) {}
    func update(to point: CGPoint) {}

    func finish(from start: CGPoint, to end: CGPoint,
                color: NSColor, width: UInt32) -> AnnotationDescriptor? {
        guard let view = editorView else { return nil }

        let rect = CGRect(
            x: min(start.x, end.x), y: min(start.y, end.y),
            width: abs(end.x - start.x), height: abs(end.y - start.y)
        )
        guard rect.width >= 30, rect.height >= 20 else { return nil }

        // Open inline text editor within the sticky note rect
        let viewRect = CGRect(
            x: view.imageToView(rect.origin).x,
            y: view.imageToView(rect.origin).y,
            width: rect.width * view.imageRect.width / CGFloat(view.workingImage.width),
            height: rect.height * view.imageRect.height / CGFloat(view.workingImage.height)
        )

        let fontSize = view.currentFontSize
        let bgColor = StickyNoteRenderer.noteColors[0] // Warm yellow default
        let textColor = NSColor(calibratedWhite: 0.15, alpha: 1.0)

        let tv = NSTextView(frame: viewRect)
        tv.isRichText = false
        tv.font = NSFont.systemFont(ofSize: fontSize)
        tv.textColor = textColor
        tv.backgroundColor = bgColor
        tv.insertionPointColor = textColor
        tv.isAutomaticQuoteSubstitutionEnabled = false
        tv.isAutomaticDashSubstitutionEnabled = false
        tv.textContainerInset = NSSize(width: 6, height: 6)

        view.addSubview(tv)
        tv.window?.makeFirstResponder(tv)

        // When text view loses focus, commit the sticky note
        NotificationCenter.default.addObserver(
            forName: NSTextView.didChangeNotification,
            object: tv,
            queue: .main
        ) { _ in }

        // Use a click-outside handler to commit. Store monitor in a box for self-removal.
        final class MonitorBox { var monitor: Any? }
        let box = MonitorBox()

        box.monitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak view, weak tv] event in
            guard let tv = tv, let view = view else {
                if let m = box.monitor { NSEvent.removeMonitor(m) }
                box.monitor = nil
                return event
            }
            let clickPoint = tv.convert(event.locationInWindow, from: nil)
            if !tv.bounds.contains(clickPoint) {
                let text = tv.string.trimmingCharacters(in: .whitespacesAndNewlines)
                tv.removeFromSuperview()
                if !text.isEmpty {
                    let annotation = AnnotationDescriptor.stickyNote(
                        rect: rect, content: text, fontSize: fontSize,
                        backgroundColor: bgColor, textColor: textColor,
                        fontName: view.currentFontName,
                        isBold: view.currentBold,
                        isItalic: view.currentItalic,
                        alignment: view.currentAlignment
                    )
                    view.model.add(annotation)
                }
                if let m = box.monitor { NSEvent.removeMonitor(m) }
                box.monitor = nil
            }
            return event
        }

        return nil
    }

    func drawPreview(in ctx: CGContext, from: CGPoint, to: CGPoint,
                     color: NSColor, width: CGFloat, imageRect: CGRect) {
        let rect = CGRect(
            x: min(from.x, to.x), y: min(from.y, to.y),
            width: abs(to.x - from.x), height: abs(to.y - from.y)
        )

        // Preview: warm yellow rounded rect with slight transparency
        ctx.saveGState()
        let bgColor = StickyNoteRenderer.noteColors[0]
        let path = CGPath(roundedRect: rect, cornerWidth: 6, cornerHeight: 6, transform: nil)
        ctx.addPath(path)
        ctx.setFillColor(bgColor.cgColor)
        ctx.fillPath()

        ctx.addPath(path)
        ctx.setStrokeColor(NSColor(calibratedWhite: 0.0, alpha: 0.15).cgColor)
        ctx.setLineWidth(1)
        ctx.strokePath()
        ctx.restoreGState()
    }
}

// MARK: - OCR Tool

/// Click to extract text from the entire image and copy to clipboard.
/// No annotation is produced — this is a read-only action tool.
final class OcrToolHandler: AnnotationToolHandler {
    weak var editorView: AnnotationEditorView?

    func start(at point: CGPoint) {}
    func update(to point: CGPoint) {}

    func finish(from start: CGPoint, to end: CGPoint,
                color: NSColor, width: UInt32) -> AnnotationDescriptor? {
        guard let view = editorView,
              let cgImage = view.workingImage.cgImage() else { return nil }
        OCRController.extractAndCopy(from: cgImage)
        return nil
    }

    func drawPreview(in ctx: CGContext, from: CGPoint, to: CGPoint,
                     color: NSColor, width: CGFloat, imageRect: CGRect) {
        // No preview — click action only
    }
}
