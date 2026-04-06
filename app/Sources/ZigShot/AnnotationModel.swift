import Foundation
import AppKit

// MARK: - AnnotationDescriptor

/// Mirrors Zig annotation types in a Swift-native enum.
/// Each case carries associated values matching the rendering parameters
/// expected by ZigShotImage's bridge methods.
enum AnnotationDescriptor: Equatable {
    case arrow(from: CGPoint, to: CGPoint, color: NSColor, width: UInt32)
    case rectangle(rect: CGRect, color: NSColor, width: UInt32)
    case line(from: CGPoint, to: CGPoint, color: NSColor, width: UInt32)
    case blur(rect: CGRect, radius: UInt32)
    case highlightPath(points: [CGPoint], color: NSColor, width: UInt32, opacity: CGFloat)
    case ruler(from: CGPoint, to: CGPoint, color: NSColor, width: UInt32)
    case numbering(position: CGPoint, number: Int, color: NSColor)
    case text(position: CGPoint, content: String, fontSize: CGFloat, color: NSColor,
              fontName: String? = nil, isBold: Bool = false, isItalic: Bool = false,
              alignment: NSTextAlignment = .left)
    case stickyNote(rect: CGRect, content: String, fontSize: CGFloat,
                    backgroundColor: NSColor, textColor: NSColor,
                    fontName: String? = nil, isBold: Bool = false, isItalic: Bool = false,
                    alignment: NSTextAlignment = .left)

    /// Bounding rectangle for hit-testing and spatial queries.
    var bounds: CGRect {
        switch self {
        case let .arrow(from, to, _, width):
            let pad = CGFloat(width)
            let minX = min(from.x, to.x) - pad
            let minY = min(from.y, to.y) - pad
            let maxX = max(from.x, to.x) + pad
            let maxY = max(from.y, to.y) + pad
            return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
        case let .rectangle(rect, _, _):
            return rect
        case let .line(from, to, _, width):
            let pad = CGFloat(width)
            let minX = min(from.x, to.x) - pad
            let minY = min(from.y, to.y) - pad
            let maxX = max(from.x, to.x) + pad
            let maxY = max(from.y, to.y) + pad
            return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
        case let .blur(rect, _):
            return rect
        case let .highlightPath(points, _, width, _):
            guard !points.isEmpty else { return .zero }
            let pad = CGFloat(width) / 2
            var minX = points[0].x, minY = points[0].y
            var maxX = points[0].x, maxY = points[0].y
            for p in points {
                minX = min(minX, p.x); minY = min(minY, p.y)
                maxX = max(maxX, p.x); maxY = max(maxY, p.y)
            }
            return CGRect(x: minX - pad, y: minY - pad,
                          width: maxX - minX + pad * 2, height: maxY - minY + pad * 2)
        case let .ruler(from, to, _, width):
            let pad = CGFloat(width)
            let minX = min(from.x, to.x) - pad
            let minY = min(from.y, to.y) - pad
            let maxX = max(from.x, to.x) + pad
            let maxY = max(from.y, to.y) + pad
            return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
        case let .numbering(position, _, _):
            return CGRect(x: position.x - 14, y: position.y - 14, width: 28, height: 28)
        case let .text(position, content, fontSize, _, _, _, _, _):
            let estimatedWidth = CGFloat(content.count) * fontSize * 0.6
            return CGRect(x: position.x, y: position.y, width: estimatedWidth, height: fontSize * 1.5)
        case let .stickyNote(rect, _, _, _, _, _, _, _, _):
            return rect
        }
    }

    /// Return a new descriptor with all coordinates offset by (dx, dy).
    /// Used when cropping to shift annotations into the new coordinate space.
    /// Returns nil if the annotation is completely outside the clip rect.
    func translated(by dx: CGFloat, dy: CGFloat, clippedTo clipRect: CGRect? = nil) -> AnnotationDescriptor? {
        func offsetPoint(_ p: CGPoint) -> CGPoint {
            CGPoint(x: p.x + dx, y: p.y + dy)
        }

        func offsetRect(_ r: CGRect) -> CGRect {
            CGRect(x: r.origin.x + dx, y: r.origin.y + dy, width: r.width, height: r.height)
        }

        func pointInside(_ p: CGPoint) -> Bool {
            guard let clip = clipRect else { return true }
            return clip.contains(p)
        }

        func rectIntersects(_ r: CGRect) -> Bool {
            guard let clip = clipRect else { return true }
            return clip.intersects(r)
        }

        func lineIntersects(_ a: CGPoint, _ b: CGPoint) -> Bool {
            guard let clip = clipRect else { return true }
            let lineBounds = CGRect(
                x: min(a.x, b.x), y: min(a.y, b.y),
                width: abs(b.x - a.x), height: abs(b.y - a.y)
            )
            return clip.intersects(lineBounds)
        }

        switch self {
        case let .arrow(from, to, color, width):
            let newFrom = offsetPoint(from), newTo = offsetPoint(to)
            guard lineIntersects(newFrom, newTo) else { return nil }
            return .arrow(from: newFrom, to: newTo, color: color, width: width)

        case let .line(from, to, color, width):
            let newFrom = offsetPoint(from), newTo = offsetPoint(to)
            guard lineIntersects(newFrom, newTo) else { return nil }
            return .line(from: newFrom, to: newTo, color: color, width: width)

        case let .ruler(from, to, color, width):
            let newFrom = offsetPoint(from), newTo = offsetPoint(to)
            guard lineIntersects(newFrom, newTo) else { return nil }
            return .ruler(from: newFrom, to: newTo, color: color, width: width)

        case let .rectangle(rect, color, width):
            let newRect = offsetRect(rect)
            guard rectIntersects(newRect) else { return nil }
            return .rectangle(rect: newRect, color: color, width: width)

        case let .blur(rect, radius):
            let newRect = offsetRect(rect)
            guard rectIntersects(newRect) else { return nil }
            return .blur(rect: newRect, radius: radius)

        case let .highlightPath(points, color, width, opacity):
            let newPoints = points.map { offsetPoint($0) }
            guard !newPoints.isEmpty else { return nil }
            // Check bounding box intersection
            var minX = newPoints[0].x, minY = newPoints[0].y
            var maxX = newPoints[0].x, maxY = newPoints[0].y
            for p in newPoints {
                minX = min(minX, p.x); minY = min(minY, p.y)
                maxX = max(maxX, p.x); maxY = max(maxY, p.y)
            }
            let pathBounds = CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
            guard rectIntersects(pathBounds) else { return nil }
            return .highlightPath(points: newPoints, color: color, width: width, opacity: opacity)

        case let .numbering(position, number, color):
            let newPos = offsetPoint(position)
            guard pointInside(newPos) else { return nil }
            return .numbering(position: newPos, number: number, color: color)

        case let .text(position, content, fontSize, color, fontName, isBold, isItalic, alignment):
            let newPos = offsetPoint(position)
            guard pointInside(newPos) else { return nil }
            return .text(position: newPos, content: content, fontSize: fontSize, color: color,
                         fontName: fontName, isBold: isBold, isItalic: isItalic, alignment: alignment)

        case let .stickyNote(rect, content, fontSize, bgColor, textColor, fontName, isBold, isItalic, alignment):
            let newRect = offsetRect(rect)
            guard rectIntersects(newRect) else { return nil }
            return .stickyNote(rect: newRect, content: content, fontSize: fontSize,
                               backgroundColor: bgColor, textColor: textColor,
                               fontName: fontName, isBold: isBold, isItalic: isItalic, alignment: alignment)
        }
    }
}

// MARK: - Codable

extension AnnotationDescriptor: Codable {
    private enum CodingType: String, Codable {
        case arrow, rectangle, line, blur, highlightPath, ruler, numbering, text, stickyNote
    }

    private enum CodingKeys: String, CodingKey {
        case type
        case fromX, fromY, toX, toY
        case x, y, w, h
        case colorHex, width, radius, opacity
        case points
        case posX, posY, number
        case content, fontSize, fontName, isBold, isItalic, alignment
        case bgColorHex, textColorHex
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .arrow(from, to, color, width):
            try c.encode(CodingType.arrow, forKey: .type)
            try c.encode(from.x, forKey: .fromX); try c.encode(from.y, forKey: .fromY)
            try c.encode(to.x, forKey: .toX); try c.encode(to.y, forKey: .toY)
            try c.encode(color.hexString, forKey: .colorHex)
            try c.encode(width, forKey: .width)
        case let .rectangle(rect, color, width):
            try c.encode(CodingType.rectangle, forKey: .type)
            try c.encode(rect.origin.x, forKey: .x); try c.encode(rect.origin.y, forKey: .y)
            try c.encode(rect.width, forKey: .w); try c.encode(rect.height, forKey: .h)
            try c.encode(color.hexString, forKey: .colorHex)
            try c.encode(width, forKey: .width)
        case let .line(from, to, color, width):
            try c.encode(CodingType.line, forKey: .type)
            try c.encode(from.x, forKey: .fromX); try c.encode(from.y, forKey: .fromY)
            try c.encode(to.x, forKey: .toX); try c.encode(to.y, forKey: .toY)
            try c.encode(color.hexString, forKey: .colorHex)
            try c.encode(width, forKey: .width)
        case let .blur(rect, radius):
            try c.encode(CodingType.blur, forKey: .type)
            try c.encode(rect.origin.x, forKey: .x); try c.encode(rect.origin.y, forKey: .y)
            try c.encode(rect.width, forKey: .w); try c.encode(rect.height, forKey: .h)
            try c.encode(radius, forKey: .radius)
        case let .highlightPath(points, color, width, opacity):
            try c.encode(CodingType.highlightPath, forKey: .type)
            try c.encode(points.map { [$0.x, $0.y] }, forKey: .points)
            try c.encode(color.hexString, forKey: .colorHex)
            try c.encode(width, forKey: .width)
            try c.encode(opacity, forKey: .opacity)
        case let .ruler(from, to, color, width):
            try c.encode(CodingType.ruler, forKey: .type)
            try c.encode(from.x, forKey: .fromX); try c.encode(from.y, forKey: .fromY)
            try c.encode(to.x, forKey: .toX); try c.encode(to.y, forKey: .toY)
            try c.encode(color.hexString, forKey: .colorHex)
            try c.encode(width, forKey: .width)
        case let .numbering(position, number, color):
            try c.encode(CodingType.numbering, forKey: .type)
            try c.encode(position.x, forKey: .posX); try c.encode(position.y, forKey: .posY)
            try c.encode(number, forKey: .number)
            try c.encode(color.hexString, forKey: .colorHex)
        case let .text(position, content, fontSize, color, fontName, isBold, isItalic, alignment):
            try c.encode(CodingType.text, forKey: .type)
            try c.encode(position.x, forKey: .posX); try c.encode(position.y, forKey: .posY)
            try c.encode(content, forKey: .content)
            try c.encode(fontSize, forKey: .fontSize)
            try c.encode(color.hexString, forKey: .colorHex)
            try c.encodeIfPresent(fontName, forKey: .fontName)
            try c.encode(isBold, forKey: .isBold)
            try c.encode(isItalic, forKey: .isItalic)
            try c.encode(alignment.rawValue, forKey: .alignment)
        case let .stickyNote(rect, content, fontSize, bgColor, textColor, fontName, isBold, isItalic, alignment):
            try c.encode(CodingType.stickyNote, forKey: .type)
            try c.encode(rect.origin.x, forKey: .x); try c.encode(rect.origin.y, forKey: .y)
            try c.encode(rect.width, forKey: .w); try c.encode(rect.height, forKey: .h)
            try c.encode(content, forKey: .content)
            try c.encode(fontSize, forKey: .fontSize)
            try c.encode(bgColor.hexString, forKey: .bgColorHex)
            try c.encode(textColor.hexString, forKey: .textColorHex)
            try c.encodeIfPresent(fontName, forKey: .fontName)
            try c.encode(isBold, forKey: .isBold)
            try c.encode(isItalic, forKey: .isItalic)
            try c.encode(alignment.rawValue, forKey: .alignment)
        }
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let type = try c.decode(CodingType.self, forKey: .type)
        switch type {
        case .arrow:
            self = .arrow(
                from: CGPoint(x: try c.decode(CGFloat.self, forKey: .fromX),
                              y: try c.decode(CGFloat.self, forKey: .fromY)),
                to: CGPoint(x: try c.decode(CGFloat.self, forKey: .toX),
                            y: try c.decode(CGFloat.self, forKey: .toY)),
                color: NSColor.from(hex: try c.decode(String.self, forKey: .colorHex)),
                width: try c.decode(UInt32.self, forKey: .width))
        case .rectangle:
            self = .rectangle(
                rect: CGRect(x: try c.decode(CGFloat.self, forKey: .x),
                             y: try c.decode(CGFloat.self, forKey: .y),
                             width: try c.decode(CGFloat.self, forKey: .w),
                             height: try c.decode(CGFloat.self, forKey: .h)),
                color: NSColor.from(hex: try c.decode(String.self, forKey: .colorHex)),
                width: try c.decode(UInt32.self, forKey: .width))
        case .line:
            self = .line(
                from: CGPoint(x: try c.decode(CGFloat.self, forKey: .fromX),
                              y: try c.decode(CGFloat.self, forKey: .fromY)),
                to: CGPoint(x: try c.decode(CGFloat.self, forKey: .toX),
                            y: try c.decode(CGFloat.self, forKey: .toY)),
                color: NSColor.from(hex: try c.decode(String.self, forKey: .colorHex)),
                width: try c.decode(UInt32.self, forKey: .width))
        case .blur:
            self = .blur(
                rect: CGRect(x: try c.decode(CGFloat.self, forKey: .x),
                             y: try c.decode(CGFloat.self, forKey: .y),
                             width: try c.decode(CGFloat.self, forKey: .w),
                             height: try c.decode(CGFloat.self, forKey: .h)),
                radius: try c.decode(UInt32.self, forKey: .radius))
        case .highlightPath:
            let rawPoints = try c.decode([[CGFloat]].self, forKey: .points)
            let points = rawPoints.map { CGPoint(x: $0[0], y: $0[1]) }
            self = .highlightPath(
                points: points,
                color: NSColor.from(hex: try c.decode(String.self, forKey: .colorHex)),
                width: try c.decode(UInt32.self, forKey: .width),
                opacity: try c.decode(CGFloat.self, forKey: .opacity))
        case .ruler:
            self = .ruler(
                from: CGPoint(x: try c.decode(CGFloat.self, forKey: .fromX),
                              y: try c.decode(CGFloat.self, forKey: .fromY)),
                to: CGPoint(x: try c.decode(CGFloat.self, forKey: .toX),
                            y: try c.decode(CGFloat.self, forKey: .toY)),
                color: NSColor.from(hex: try c.decode(String.self, forKey: .colorHex)),
                width: try c.decode(UInt32.self, forKey: .width))
        case .numbering:
            self = .numbering(
                position: CGPoint(x: try c.decode(CGFloat.self, forKey: .posX),
                                  y: try c.decode(CGFloat.self, forKey: .posY)),
                number: try c.decode(Int.self, forKey: .number),
                color: NSColor.from(hex: try c.decode(String.self, forKey: .colorHex)))
        case .text:
            self = .text(
                position: CGPoint(x: try c.decode(CGFloat.self, forKey: .posX),
                                  y: try c.decode(CGFloat.self, forKey: .posY)),
                content: try c.decode(String.self, forKey: .content),
                fontSize: try c.decode(CGFloat.self, forKey: .fontSize),
                color: NSColor.from(hex: try c.decode(String.self, forKey: .colorHex)),
                fontName: try c.decodeIfPresent(String.self, forKey: .fontName),
                isBold: try c.decodeIfPresent(Bool.self, forKey: .isBold) ?? false,
                isItalic: try c.decodeIfPresent(Bool.self, forKey: .isItalic) ?? false,
                alignment: NSTextAlignment(rawValue: try c.decodeIfPresent(Int.self, forKey: .alignment) ?? 0) ?? .left)
        case .stickyNote:
            self = .stickyNote(
                rect: CGRect(x: try c.decode(CGFloat.self, forKey: .x),
                             y: try c.decode(CGFloat.self, forKey: .y),
                             width: try c.decode(CGFloat.self, forKey: .w),
                             height: try c.decode(CGFloat.self, forKey: .h)),
                content: try c.decode(String.self, forKey: .content),
                fontSize: try c.decode(CGFloat.self, forKey: .fontSize),
                backgroundColor: NSColor.from(hex: try c.decode(String.self, forKey: .bgColorHex)),
                textColor: NSColor.from(hex: try c.decode(String.self, forKey: .textColorHex)),
                fontName: try c.decodeIfPresent(String.self, forKey: .fontName),
                isBold: try c.decodeIfPresent(Bool.self, forKey: .isBold) ?? false,
                isItalic: try c.decodeIfPresent(Bool.self, forKey: .isItalic) ?? false,
                alignment: NSTextAlignment(rawValue: try c.decodeIfPresent(Int.self, forKey: .alignment) ?? 0) ?? .left)
        }
    }
}

extension NSColor {
    /// Encode as "#RRGGBBAA" hex string.
    var hexString: String {
        guard let rgb = usingColorSpace(.sRGB) else { return "#FF0000FF" }
        let r = Int(rgb.redComponent * 255)
        let g = Int(rgb.greenComponent * 255)
        let b = Int(rgb.blueComponent * 255)
        let a = Int(rgb.alphaComponent * 255)
        return String(format: "#%02X%02X%02X%02X", r, g, b, a)
    }

    /// Decode from "#RRGGBB" or "#RRGGBBAA" hex string.
    static func from(hex: String) -> NSColor {
        var h = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if h.hasPrefix("#") { h.removeFirst() }
        guard h.count >= 6 else { return .red }
        let scanner = Scanner(string: h)
        var value: UInt64 = 0
        scanner.scanHexInt64(&value)
        if h.count == 8 {
            return NSColor(
                red: CGFloat((value >> 24) & 0xFF) / 255,
                green: CGFloat((value >> 16) & 0xFF) / 255,
                blue: CGFloat((value >> 8) & 0xFF) / 255,
                alpha: CGFloat(value & 0xFF) / 255)
        } else {
            return NSColor(
                red: CGFloat((value >> 16) & 0xFF) / 255,
                green: CGFloat((value >> 8) & 0xFF) / 255,
                blue: CGFloat(value & 0xFF) / 255,
                alpha: 1.0)
        }
    }
}

// MARK: - UndoEntry

/// Represents a single undoable mutation to the annotation list.
/// Index-based to avoid equality-matching ambiguity with duplicate annotations.
enum UndoEntry {
    case added(AnnotationDescriptor, Int)                     // annotation + index where added
    case deleted(AnnotationDescriptor, Int)                   // annotation + former index
    case modified(index: Int, old: AnnotationDescriptor, new: AnnotationDescriptor)
}

// MARK: - AnnotationModel

/// Manages the ordered list of annotations with full undo/redo support.
/// Annotations are stored in painter's algorithm order (first drawn = bottom).
final class AnnotationModel {

    // MARK: - Properties

    private(set) var annotations: [AnnotationDescriptor] = []
    private var undoStack: [UndoEntry] = []
    private var redoStack: [UndoEntry] = []

    /// Called after every mutation (add, remove, update, undo, redo).
    var onChange: (() -> Void)?

    var canUndo: Bool { !undoStack.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }

    /// Remove all annotations and clear undo/redo history.
    /// Used after image transforms (rotate, flip) that invalidate coordinates.
    func clearAll() {
        annotations.removeAll()
        undoStack.removeAll()
        redoStack.removeAll()
        onChange?()
    }

    /// Transform all annotations for a crop operation.
    /// Offsets coordinates so they remain correct in the cropped image space,
    /// and removes annotations that fall entirely outside the crop rect.
    func transformForCrop(cropRect: CGRect) {
        let dx = -cropRect.origin.x
        let dy = -cropRect.origin.y
        let newBounds = CGRect(x: 0, y: 0, width: cropRect.width, height: cropRect.height)

        var newAnnotations: [AnnotationDescriptor] = []
        for annotation in annotations {
            if let transformed = annotation.translated(by: dx, dy: dy, clippedTo: newBounds) {
                newAnnotations.append(transformed)
            }
        }
        annotations = newAnnotations
        undoStack.removeAll()
        redoStack.removeAll()
        onChange?()
    }

    // MARK: - Mutations

    func add(_ annotation: AnnotationDescriptor) {
        let index = annotations.count
        annotations.append(annotation)
        undoStack.append(.added(annotation, index))
        redoStack.removeAll()
        onChange?()
    }

    func remove(at index: Int) {
        guard annotations.indices.contains(index) else { return }
        let removed = annotations.remove(at: index)
        undoStack.append(.deleted(removed, index))
        redoStack.removeAll()
        onChange?()
    }

    func update(at index: Int, to newAnnotation: AnnotationDescriptor) {
        guard annotations.indices.contains(index) else { return }
        let old = annotations[index]
        annotations[index] = newAnnotation
        undoStack.append(.modified(index: index, old: old, new: newAnnotation))
        redoStack.removeAll()
        onChange?()
    }

    // MARK: - Undo / Redo

    func undo() {
        guard let entry = undoStack.popLast() else { return }
        switch entry {
        case let .added(_, index):
            let safeIndex = min(index, annotations.count - 1)
            if annotations.indices.contains(safeIndex) {
                annotations.remove(at: safeIndex)
            }
            redoStack.append(entry)
        case let .deleted(annotation, index):
            let safeIndex = min(index, annotations.count)
            annotations.insert(annotation, at: safeIndex)
            redoStack.append(entry)
        case let .modified(index, old, _):
            if annotations.indices.contains(index) {
                annotations[index] = old
            }
            redoStack.append(entry)
        }
        onChange?()
    }

    func redo() {
        guard let entry = redoStack.popLast() else { return }
        switch entry {
        case let .added(annotation, index):
            annotations.insert(annotation, at: min(index, annotations.count))
            undoStack.append(entry)
        case let .deleted(_, index):
            let safeIndex = min(index, annotations.count - 1)
            if annotations.indices.contains(safeIndex) {
                annotations.remove(at: safeIndex)
            }
            undoStack.append(entry)
        case let .modified(index, _, new):
            if annotations.indices.contains(index) {
                annotations[index] = new
            }
            undoStack.append(entry)
        }
        onChange?()
    }

    // MARK: - Rendering

    /// Renders all annotations onto the given image using Zig bridge methods.
    /// Text and numbering are rendered as Swift bitmaps and composited via `zs_composite_rgba`.
    func renderAll(onto image: ZigShotImage) {
        // IMPORTANT: The caller must reset `image` pixels from the original image
        // before calling renderAll, otherwise successive renders will compound
        // annotations on top of each other (e.g. copy originalPixels → workingPixels).
        for annotation in annotations {
            switch annotation {
            case let .arrow(from, to, color, width):
                image.drawArrow(from: from, to: to, color: color, width: width)
            case let .rectangle(rect, color, width):
                image.drawRect(rect, color: color, width: width)
            case let .line(from, to, color, width):
                image.drawLine(from: from, to: to, color: color, width: width)
            case let .blur(rect, radius):
                image.blur(rect, radius: radius)
            case let .highlightPath(points, color, width, opacity):
                // Render freehand highlight as series of thick line segments
                let hlColor = color.withAlphaComponent(opacity)
                for i in 1 ..< points.count {
                    image.drawLine(from: points[i - 1], to: points[i],
                                   color: hlColor, width: width)
                }
            case let .ruler(from, to, color, width):
                _ = image.drawRuler(from: from, to: to, color: color, width: width)
            case let .numbering(position, number, color):
                if let bitmap = NumberingRenderer.renderBitmap(number: number, color: color) {
                    bitmap.pixels.withUnsafeBufferPointer { buf in
                        guard let base = buf.baseAddress else { return }
                        image.compositeRGBA(
                            base,
                            width: UInt32(bitmap.width),
                            height: UInt32(bitmap.height),
                            stride: UInt32(bitmap.width * 4),
                            at: Int32(position.x) - Int32(bitmap.width / 2),
                            y: Int32(position.y) - Int32(bitmap.height / 2)
                        )
                    }
                }
            case let .text(position, content, fontSize, color, fontName, isBold, isItalic, alignment):
                if let bitmap = TextEditingController.renderTextBitmap(
                    text: content, fontSize: fontSize, color: color,
                    fontName: fontName, isBold: isBold, isItalic: isItalic, alignment: alignment
                ) {
                    bitmap.pixels.withUnsafeBufferPointer { buf in
                        guard let base = buf.baseAddress else { return }
                        image.compositeRGBA(
                            base,
                            width: UInt32(bitmap.width),
                            height: UInt32(bitmap.height),
                            stride: UInt32(bitmap.width * 4),
                            at: Int32(position.x),
                            y: Int32(position.y)
                        )
                    }
                }
            case let .stickyNote(rect, content, fontSize, bgColor, textColor, fontName, isBold, isItalic, alignment):
                if let bitmap = StickyNoteRenderer.renderBitmap(
                    rect: rect, content: content, fontSize: fontSize,
                    backgroundColor: bgColor, textColor: textColor,
                    fontName: fontName, isBold: isBold, isItalic: isItalic, alignment: alignment
                ) {
                    bitmap.pixels.withUnsafeBufferPointer { buf in
                        guard let base = buf.baseAddress else { return }
                        image.compositeRGBA(
                            base,
                            width: UInt32(bitmap.width),
                            height: UInt32(bitmap.height),
                            stride: UInt32(bitmap.width * 4),
                            at: Int32(rect.origin.x),
                            y: Int32(rect.origin.y)
                        )
                    }
                }
            }
        }
    }
}

