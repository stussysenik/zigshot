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
        guard sqrt(dx * dx + dy * dy) >= 5 else { return nil }
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

        // Arrowhead
        let angle = atan2(to.y - from.y, to.x - from.x)
        let headLength: CGFloat = 12
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
        guard sqrt(dx * dx + dy * dy) >= 5 else { return nil }
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

/// Semi-transparent color overlay (like a highlighter pen).
final class HighlightToolHandler: AnnotationToolHandler {
    func start(at point: CGPoint) {}
    func update(to point: CGPoint) {}

    func finish(from start: CGPoint, to end: CGPoint,
                color: NSColor, width: UInt32) -> AnnotationDescriptor? {
        let rect = CGRect(
            x: min(start.x, end.x), y: min(start.y, end.y),
            width: abs(end.x - start.x), height: abs(end.y - start.y)
        )
        guard rect.width >= 3 && rect.height >= 3 else { return nil }
        return .highlight(rect: rect, color: color.withAlphaComponent(0.4))
    }

    func drawPreview(in ctx: CGContext, from: CGPoint, to: CGPoint,
                     color: NSColor, width: CGFloat, imageRect: CGRect) {
        let rect = CGRect(
            x: min(from.x, to.x), y: min(from.y, to.y),
            width: abs(to.x - from.x), height: abs(to.y - from.y)
        )
        ctx.setFillColor(color.withAlphaComponent(0.3).cgColor)
        ctx.fill(rect)
    }
}

// MARK: - Ruler Tool

/// Drag to measure pixel distance. Shows px value along the line.
final class RulerToolHandler: AnnotationToolHandler {
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

        // Distance label
        let dx = to.x - from.x
        let dy = to.y - from.y
        let dist = sqrt(dx * dx + dy * dy)
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
    var nextNumber: Int = 1

    func start(at point: CGPoint) {}
    func update(to point: CGPoint) {}

    func finish(from start: CGPoint, to end: CGPoint,
                color: NSColor, width: UInt32) -> AnnotationDescriptor? {
        let number = nextNumber
        nextNumber += 1
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
        textController.beginEditing(
            in: view,
            at: viewPoint,
            imagePosition: start,
            fontSize: 16,
            color: color
        ) { [weak view] text, position, fontSize, color in
            guard let view = view else { return }
            let annotation = AnnotationDescriptor.text(
                position: position,
                content: text,
                fontSize: fontSize,
                color: color
            )
            view.model.add(annotation)

            // Render text bitmap and composite onto Zig buffer
            if let bitmap = TextEditingController.renderTextBitmap(
                text: text, fontSize: fontSize, color: color
            ) {
                bitmap.pixels.withUnsafeBufferPointer { buf in
                    guard let base = buf.baseAddress else { return }
                    view.workingImage.compositeRGBA(
                        base,
                        width: UInt32(bitmap.width),
                        height: UInt32(bitmap.height),
                        stride: UInt32(bitmap.width * 4),
                        at: Int32(position.x),
                        y: Int32(position.y)
                    )
                }
                view.needsDisplay = true
            }
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
