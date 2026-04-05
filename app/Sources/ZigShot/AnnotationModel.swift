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
    case highlight(rect: CGRect, color: NSColor)
    case ruler(from: CGPoint, to: CGPoint, color: NSColor, width: UInt32)
    case numbering(position: CGPoint, number: Int, color: NSColor)
    case text(position: CGPoint, content: String, fontSize: CGFloat, color: NSColor)

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
        case let .highlight(rect, _):
            return rect
        case let .ruler(from, to, _, width):
            let pad = CGFloat(width)
            let minX = min(from.x, to.x) - pad
            let minY = min(from.y, to.y) - pad
            let maxX = max(from.x, to.x) + pad
            let maxY = max(from.y, to.y) + pad
            return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
        case let .numbering(position, _, _):
            return CGRect(x: position.x - 14, y: position.y - 14, width: 28, height: 28)
        case let .text(position, content, fontSize, _):
            let estimatedWidth = CGFloat(content.count) * fontSize * 0.6
            return CGRect(x: position.x, y: position.y, width: estimatedWidth, height: fontSize * 1.5)
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
    /// Text and numbering annotations are skipped here — they are rendered
    /// by Swift and composited separately in the annotation editor.
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
            case let .highlight(rect, color):
                image.highlight(rect, color: color)
            case let .ruler(from, to, color, width):
                _ = image.drawRuler(from: from, to: to, color: color, width: width)
            case .numbering, .text:
                break
            }
        }
    }
}

