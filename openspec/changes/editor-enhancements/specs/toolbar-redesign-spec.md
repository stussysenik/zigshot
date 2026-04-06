# Toolbar Redesign Specification

## Overview
This specification details the redesign and optimization of the ZigShot annotation toolbar. The goal is to create a more organized, space-efficient, and modern toolbar that improves user experience while maintaining all existing functionality.

## Requirements

### Functional Requirements
1. **Tool Grouping**: Organize tools into logical categories with separators
2. **Responsive Layout**: Adapt toolbar layout for different screen sizes and resolutions
3. **Tool Visibility**: Implement show/hide options for individual tools
4. **Icon Improvements**: Update all toolbar icons for consistency and clarity
5. **Space Optimization**: Improve spacing and reduce overall toolbar height
6. **Modern UI Elements**: Implement modern button styles and visual feedback
7. **Customization**: Allow users to customize toolbar layout and tool visibility
8. **Accessibility**: Ensure toolbar is accessible via keyboard and screen readers

### Non-Functional Requirements
1. **Performance**: Toolbar operations should be responsive with no lag
2. **Consistency**: Maintain consistent visual design across all tools
3. **Usability**: Improved discoverability and ease of use
4. **Compatibility**: Work across different macOS versions and screen resolutions
5. **Maintainability**: Easy to add new tools in the future

## Implementation Details

### Tool Categories
The toolbar will be organized into the following categories:

```swift
enum ToolCategory {
    case selection    // Move, Select, Crop, Rotate
    case drawing      // Pen, Highlight, Ruler, Arrow
    case text         // Text, Sticky Note, Numbering
    case special      // OCR, Truth Table, Share
}
```

### Toolbar Structure
```swift
class AnnotationToolbar: NSView {
    // Tool groups
    private var selectionGroup: NSView!
    private var drawingGroup: NSView!
    private var textGroup: NSView!
    private var specialGroup: NSView!
    
    // Group separators
    private var selectionSeparator: NSView!
    private var drawingSeparator: NSView!
    private var textSeparator: NSView!
    
    // Tool visibility state
    private var toolVisibility: [Tool: Bool] = [:]
    
    // Modern UI elements
    private var modernButtons: [NSButton: Tool] = [:]
    
    func setupToolbar() {
        setupToolGroups()
        setupSeparators()
        setupModernUI()
        setupToolVisibility()
    }
}
```

### Tool Group Implementation
```swift
func setupToolGroups() {
    // Selection Tools
    selectionGroup = createToolGroup([
        createToolButton(.move, icon: "move-icon"),
        createToolButton(.select, icon: "select-icon"),
        createToolButton(.crop, icon: "crop-icon"),
        createToolButton(.rotate, icon: "rotate-icon")
    ])
    
    // Drawing Tools
    drawingGroup = createToolGroup([
        createToolButton(.pen, icon: "pen-icon"),
        createToolButton(.highlight, icon: "highlight-icon"),
        createToolButton(.ruler, icon: "ruler-icon"),
        createToolButton(.arrow, icon: "arrow-icon")
    ])
    
    // Text Tools
    textGroup = createToolGroup([
        createToolButton(.text, icon: "text-icon"),
        createToolButton(.stickyNote, icon: "note-icon"),
        createToolButton(.numbering, icon: "number-icon")
    ])
    
    // Special Tools
    specialGroup = createToolGroup([
        createToolButton(.ocr, icon: "ocr-icon"),
        createToolButton(.truthTable, icon: "table-icon"),
        createToolButton(.share, icon: "share-icon")
    ])
}
```

### Separator Implementation
```swift
func setupSeparators() {
    let separatorHeight: CGFloat = 16
    let separatorWidth: CGFloat = 1
    
    selectionSeparator = createSeparator()
    drawingSeparator = createSeparator()
    textSeparator = createSeparator()
    
    // Add separators to layout
    addSubview(selectionSeparator)
    addSubview(drawingSeparator)
    addSubview(textSeparator)
}
```

### Modern UI Elements
```swift
func setupModernUI() {
    // Modern button styling
    let buttonStyle: NSButton.Style = .borderless
    let buttonFont = NSFont.systemFont(ofSize: 12)
    
    for (button, tool) in modernButtons {
        button.isBordered = false
        button.font = buttonFont
        button.contentTintColor = .labelColor
        button.setButtonType(buttonStyle)
        
        // Add hover effects
        button.mouseEnteredHandler = { [weak self] in
            self?.highlightButton(button)
        }
        
        button.mouseExitedHandler = { [weak self] in
            self?.unhighlightButton(button)
        }
    }
}
```

### Tool Visibility Management
```swift
func setupToolVisibility() {
    // Default visibility (all tools visible)
    Tool.allCases.forEach { tool in
        toolVisibility[tool] = true
    }
    
    // Load user preferences
    loadToolVisibilityPreferences()
    
    // Setup visibility toggles
    setupVisibilityToggles()
}

func toggleToolVisibility(_ tool: Tool, visible: Bool) {
    toolVisibility[tool] = visible
    updateToolbarLayout()
    saveToolVisibilityPreferences()
}

func updateToolbarLayout() {
    // Hide/show tools based on visibility state
    for (button, tool) in modernButtons {
        button.isHidden = !(toolVisibility[tool] ?? true)
    }
    
    // Adjust layout constraints
    layoutIfNeeded()
}
```

### Responsive Layout
```swift
func updateLayoutForScreenSize() {
    let availableWidth = bounds.width
    let compactWidth: CGFloat = 800
    
    if availableWidth < compactWidth {
        // Compact layout - hide some tools or use smaller icons
        adjustForCompactLayout()
    } else {
        // Regular layout - show all tools
        adjustForRegularLayout()
    }
}

func adjustForCompactLayout() {
    // Hide less frequently used tools
    toggleToolVisibility(.rotate, visible: false)
    toggleToolVisibility(.numbering, visible: false)
    toggleToolVisibility(.truthTable, visible: false)
    
    // Use smaller icons
    updateIconSizes(small: true)
}

func adjustForRegularLayout() {
    // Show all tools
    Tool.allCases.forEach { tool in
        toggleToolVisibility(tool, visible: true)
    }
    
    // Use regular icon sizes
    updateIconSizes(small: false)
}
```

### Icon Improvements
```swift
func updateIconSizes(small: Bool) {
    let iconSize: CGFloat = small ? 16 : 24
    
    for (button, _) in modernButtons {
        button.imageSize = NSSize(width: iconSize, height: iconSize)
    }
}

func updateIconSet() {
    // New modern icon set
    modernButtons[.move] = createButton(withImage: "move-icon-modern")
    modernButtons[.select] = createButton(withImage: "select-icon-modern")
    modernButtons[.crop] = createButton(withImage: "crop-icon-modern")
    // ... other tools
}
```

## Testing Requirements

### Unit Tests
1. **Tool Grouping**: Verify tools are properly grouped and separated
2. **Tool Visibility**: Test show/hide functionality for individual tools
3. **Responsive Layout**: Test layout adjustments for different screen sizes
4. **Icon Updates**: Verify icon changes and sizing work correctly
5. **Modern UI**: Test button styling and hover effects

### Integration Tests
1. **Toolbar Initialization**: Test toolbar setup and initial state
2. **Tool Selection**: Verify tool switching works with new layout
3. **Visibility Toggles**: Test user customization of toolbar
4. **Layout Adaptation**: Test responsive behavior with window resizing
5. **Icon Consistency**: Verify all icons follow the same style

### Usability Tests
1. **Discoverability**: Test users can find tools easily in the new layout
2. **Space Efficiency**: Verify toolbar doesn't take excessive vertical space
3. **Customization**: Test users can customize toolbar to their preferences
4. **Accessibility**: Verify toolbar is accessible via keyboard and screen readers

## Success Criteria

- Toolbar is organized into logical tool groups with clear separators
- Tool visibility can be customized by users
- Responsive layout adapts to different screen sizes
- Modern UI elements improve visual appeal and usability
- All existing functionality is maintained
- Performance is not degraded
- Comprehensive test coverage
- User feedback is positive about the new design