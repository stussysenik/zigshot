# Undo/Redo Specification

## Overview
This specification details the implementation of a comprehensive undo/redo system for the ZigShot annotation editor. The system will provide users with the ability to undo and redo annotation operations, maintaining a history of changes and supporting multiple levels of undo.

## Requirements

### Functional Requirements
1. **Undo/Redo Operations**: Implement undo (Cmd+Z) and redo (Cmd+Shift+Z) functionality
2. **Multiple History Levels**: Support at least 50 levels of undo history
3. **Command Pattern**: Use command pattern for operation management
4. **State Snapshots**: Take snapshots of editor state before each operation
5. **Visual Feedback**: Provide visual indicators for undo/redo availability
6. **Operation Grouping**: Group related operations for better undo behavior
7. **Clear State Management**: Clear history when opening new images
8. **Error Handling**: Handle undo/redo errors gracefully

### Non-Functional Requirements
1. **Performance**: Undo/redo operations should be responsive with no noticeable lag
2. **Memory Usage**: History should be memory-efficient with configurable limits
3. **Consistency**: Maintain consistent behavior across all annotation operations
4. **Accessibility**: Support keyboard shortcuts and screen reader announcements
5. **Thread Safety**: Ensure thread-safe operation in multi-threaded environment
6. **Persistence**: Optionally persist undo history (Phase 2 consideration)

## Implementation Details

### Command Pattern Architecture
```swift
protocol AnnotationCommand {
    func execute() -> Bool
    func undo() -> Bool
    var description: String { get }
    var timestamp: Date { get }
}

class UndoManager {
    private var undoStack: [AnnotationCommand] = []
    private var redoStack: [AnnotationCommand] = []
    private let maxHistorySize: Int = 50
    
    func execute(command: AnnotationCommand) {
        if command.execute() {
            undoStack.append(command)
            redoStack.removeAll()
            trimHistory()
        }
    }
    
    func undo() -> Bool {
        guard !undoStack.isEmpty else { return false }
        let command = undoStack.removeLast()
        if command.undo() {
            redoStack.append(command)
            return true
        }
        return false
    }
    
    func redo() -> Bool {
        guard !redoStack.isEmpty else { return false }
        let command = redoStack.removeLast()
        if command.execute() {
            undoStack.append(command)
            return true
        }
        return false
    }
    
    func canUndo() -> Bool {
        return !undoStack.isEmpty
    }
    
    func canRedo() -> Bool {
        return !redoStack.isEmpty
    }
    
    private func trimHistory() {
        if undoStack.count > maxHistorySize {
            undoStack.removeFirst(undoStack.count - maxHistorySize)
        }
    }
}
```

### Command Types
```swift
enum AnnotationOperation {
    case add(annotation: AnnotationDescriptor)
    case remove(annotation: AnnotationDescriptor)
    case modify(annotation: AnnotationDescriptor, previousState: AnnotationDescriptor)
    case crop(rect: CGRect)
    case zoom(level: CGFloat)
    case textEdit(text: String, previousText: String)
    case colorChange(color: NSColor, previousColor: NSColor)
}

class AnnotationCommandImpl: AnnotationCommand {
    private let operation: AnnotationOperation
    private let editor: AnnotationEditorView
    private let timestamp: Date
    
    init(operation: AnnotationOperation, editor: AnnotationEditorView) {
        self.operation = operation
        self.editor = editor
        self.timestamp = Date()
    }
    
    func execute() -> Bool {
        switch operation {
        case .add(let annotation):
            editor.addAnnotation(annotation)
            return true
        case .remove(let annotation):
            editor.removeAnnotation(annotation)
            return true
        case .modify(let annotation, let previousState):
            editor.modifyAnnotation(annotation, previousState: previousState)
            return true
        case .crop(let rect):
            editor.crop(to: rect)
            return true
        case .zoom(let level):
            editor.setZoomLevel(level)
            return true
        case .textEdit(let text, let previousText):
            editor.updateText(text, previousText: previousText)
            return true
        case .colorChange(let color, let previousColor):
            editor.updateColor(color, previousColor: previousColor)
            return true
        }
    }
    
    func undo() -> Bool {
        // Reverse the operation
        switch operation {
        case .add(let annotation):
            editor.removeAnnotation(annotation)
            return true
        case .remove(let annotation):
            editor.addAnnotation(annotation)
            return true
        case .modify(let annotation, let previousState):
            editor.modifyAnnotation(previousState, previousState: annotation)
            return true
        case .crop(let rect):
            editor.uncrop()
            return true
        case .zoom(let level):
            editor.setZoomLevel(1.0 / level) // Simplified undo
            return true
        case .textEdit(let text, let previousText):
            editor.updateText(previousText, previousText: text)
            return true
        case .colorChange(let color, let previousColor):
            editor.updateColor(previousColor, previousColor: color)
            return true
        }
    }
    
    var description: String {
        switch operation {
        case .add:
            return "Add Annotation"
        case .remove:
            return "Remove Annotation"
        case .modify:
            return "Modify Annotation"
        case .crop:
            return "Crop Image"
        case .zoom:
            return "Change Zoom Level"
        case .textEdit:
            return "Edit Text"
        case .colorChange:
            return "Change Color"
        }
    }
    
    var timestamp: Date {
        return timestamp
    }
}
```

### Integration with Editor
```swift
class AnnotationEditorView: NSView {
    private let undoManager = UndoManager()
    
    func addAnnotation(_ annotation: AnnotationDescriptor) {
        let command = AnnotationCommandImpl(operation: .add(annotation: annotation), editor: self)
        undoManager.execute(command: command)
        setNeedsDisplay()
    }
    
    func removeAnnotation(_ annotation: AnnotationDescriptor) {
        let command = AnnotationCommandImpl(operation: .remove(annotation: annotation), editor: self)
        undoManager.execute(command: command)
        setNeedsDisplay()
    }
    
    func modifyAnnotation(_ annotation: AnnotationDescriptor, previousState: AnnotationDescriptor) {
        let command = AnnotationCommandImpl(operation: .modify(annotation: annotation, previousState: previousState), editor: self)
        undoManager.execute(command: command)
        setNeedsDisplay()
    }
    
    @objc func undoAction() {
        if undoManager.canUndo() {
            undoManager.undo()
            setNeedsDisplay()
            updateUndoRedoUI()
        }
    }
    
    @objc func redoAction() {
        if undoManager.canRedo() {
            undoManager.redo()
            setNeedsDisplay()
            updateUndoRedoUI()
        }
    }
    
    func updateUndoRedoUI() {
        // Update toolbar buttons based on undo/redo availability
        toolbar.undoButton.isEnabled = undoManager.canUndo()
        toolbar.redoButton.isEnabled = undoManager.canRedo()
    }
}
```

### Toolbar Integration
```swift
class AnnotationToolbar: NSView {
    private var undoButton: NSButton!
    private var redoButton: NSButton!
    
    func setupUndoRedoControls() {
        undoButton = createButton(title: "Undo", action: #selector(undoAction))
        redoButton = createButton(title: "Redo", action: #selector(redoAction))
        
        addSubview(undoButton)
        addSubview(redoButton)
        
        // Initial state
        updateUndoRedoUI()
    }
    
    func updateUndoRedoUI() {
        undoButton.isEnabled = editor.canUndo()
        redoButton.isEnabled = editor.canRedo()
        
        // Update button appearance based on state
        if undoButton.isEnabled {
            undoButton.contentTintColor = .labelColor
        } else {
            undoButton.contentTintColor = .disabledControlTextColor
        }
        
        if redoButton.isEnabled {
            redoButton.contentTintColor = .labelColor
        } else {
            redoButton.contentTintColor = .disabledControlTextColor
        }
    }
}
```

### Operation Grouping
```swift
class OperationGroup: AnnotationCommand {
    private let commands: [AnnotationCommand]
    private let description: String
    
    init(description: String, commands: [AnnotationCommand]) {
        self.description = description
        self.commands = commands
    }
    
    func execute() -> Bool {
        for command in commands {
            if !command.execute() {
                // If any command fails, undo all previous commands
                for previousCommand in commands.reversed() {
                    previousCommand.undo()
                }
                return false
            }
        }
        return true
    }
    
    func undo() -> Bool {
        for command in commands.reversed() {
            if !command.undo() {
                return false
            }
        }
        return true
    }
    
    var description: String {
        return description
    }
    
    var timestamp: Date {
        return commands.last?.timestamp ?? Date()
    }
}

// Usage example
func performMultipleOperations() {
    let commands: [AnnotationCommand] = [
        AnnotationCommandImpl(operation: .add(annotation: textAnnotation1), editor: editor),
        AnnotationCommandImpl(operation: .add(annotation: textAnnotation2), editor: editor),
        AnnotationCommandImpl(operation: .crop(rect: cropRect), editor: editor)
    ]
    
    let group = OperationGroup(description: "Batch Annotation and Crop", commands: commands)
    editor.undoManager.execute(command: group)
}
```

## Testing Requirements

### Unit Tests
1. **Command Execution**: Test that commands execute and undo correctly
2. **History Management**: Verify undo/redo stack behavior
3. **History Limits**: Test that history is trimmed when exceeding limits
4. **Command Types**: Test all command types (add, remove, modify, crop, zoom, textEdit, colorChange)
5. **Operation Grouping**: Test grouped operations work correctly
6. **Edge Cases**: Test undo/redo with empty stacks and boundary conditions

### Integration Tests
1. **Keyboard Shortcuts**: Test Cmd+Z and Cmd+Shift+Z functionality
2. **Toolbar Integration**: Verify undo/redo buttons update correctly
3. **Multiple Operations**: Test complex operation sequences
4. **State Preservation**: Verify editor state is preserved during undo/redo
5. **Error Handling**: Test error conditions and recovery

### Performance Tests
1. **Large History**: Test performance with maximum history size
2. **Complex Operations**: Test performance with complex annotation operations
3. **Memory Usage**: Monitor memory usage during undo/redo operations
4. **Concurrent Operations**: Test thread safety in multi-threaded scenarios

## Success Criteria

- Undo/redo functionality works with keyboard shortcuts and toolbar buttons
- Multiple levels of history are supported (minimum 50)
- All annotation operations are undoable and redoable
- Visual feedback indicates undo/redo availability
- Operation grouping works correctly
- Performance is acceptable with no noticeable lag
- All edge cases are handled gracefully
- Comprehensive test coverage
- No regression in existing functionality
- User experience is improved with undo/redo capabilities