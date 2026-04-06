# Zoom Controls Specification

## Overview
This specification details the implementation of zoom controls for the ZigShot annotation editor. The feature will provide users with the ability to zoom in and out of their annotated images using keyboard shortcuts (Cmd + / Cmd -) and toolbar controls.

## Requirements

### Functional Requirements
1. **Zoom In/Out**: Implement zoom functionality with keyboard shortcuts (Cmd + for zoom in, Cmd - for zoom out)
2. **Toolbar Controls**: Add zoom in/out buttons and zoom level display to the toolbar
3. **Zoom to Fit**: Implement zoom to fit functionality that scales the image to fit the available space
4. **Zoom Level Display**: Show current zoom percentage in the toolbar
5. **Zoom Limits**: Set minimum zoom level to 25% and maximum to 400%
6. **Smooth Zoom**: Implement smooth zoom transitions when changing zoom levels
7. **Coordinate Preservation**: Maintain annotation positions during zoom operations
8. **Keyboard Navigation**: Support keyboard shortcuts for zoom controls

### Non-Functional Requirements
1. **Performance**: Zoom operations should be responsive with no noticeable lag
2. **Memory Usage**: Zoom state should not significantly increase memory consumption
3. **Accessibility**: Zoom controls should be accessible via keyboard and screen readers
4. **Compatibility**: Work across different macOS versions and screen resolutions

## Implementation Details

### Architecture
The zoom system will be implemented as part of the `AnnotationEditorView` class with the following components:

```swift
class AnnotationEditorView: NSView {
    // Zoom state management
    private var zoomLevel: CGFloat = 1.0
    private let minZoomLevel: CGFloat = 0.25
    private let maxZoomLevel: CGFloat = 4.0
    private let zoomStep: CGFloat = 0.1
    
    // Zoom controls
    private var zoomInButton: NSButton!
    private var zoomOutButton: NSButton!
    private var zoomToFitButton: NSButton!
    private var zoomLevelLabel: NSTextField!
    
    // Coordinate transformation
    private func transformPoint(_ point: CGPoint) -> CGPoint {
        // Apply zoom transformation
        return CGPoint(x: point.x * zoomLevel, y: point.y * zoomLevel)
    }
    
    private func inverseTransformPoint(_ point: CGPoint) -> CGPoint {
        // Apply inverse zoom transformation
        return CGPoint(x: point.x / zoomLevel, y: point.y / zoomLevel)
    }
}
```

### Keyboard Shortcuts
- **Cmd +**: Zoom in (increase zoom level by 10%)
- **Cmd -**: Zoom out (decrease zoom level by 10%)
- **Cmd 0**: Zoom to fit (reset to 100%)

### Toolbar Integration
The zoom controls will be added to the `AnnotationToolbar`:

```swift
class AnnotationToolbar: NSView {
    // Zoom controls
    private var zoomInButton: NSButton!
    private var zoomOutButton: NSButton!
    private var zoomToFitButton: NSButton!
    private var zoomLevelLabel: NSTextField!
    
    // Initialization
    func setupZoomControls() {
        zoomInButton = createZoomButton("Zoom In", action: #selector(zoomIn))
        zoomOutButton = createZoomButton("Zoom Out", action: #selector(zoomOut))
        zoomToFitButton = createZoomButton("Zoom to Fit", action: #selector(zoomToFit))
        zoomLevelLabel = createZoomLevelLabel()
        
        // Add to toolbar layout
        addSubview(zoomInButton)
        addSubview(zoomOutButton)
        addSubview(zoomToFitButton)
        addSubview(zoomLevelLabel)
    }
}
```

### Coordinate System
The zoom system will maintain annotation coordinates relative to the image:

```swift
// When adding annotations
func addAnnotation(at point: CGPoint) {
    let transformedPoint = inverseTransformPoint(point)
    // Add annotation at transformedPoint
}

// When rendering
func renderAnnotations() {
    let context = NSGraphicsContext.current!.cgContext
    context.saveGState()
    
    // Apply zoom transform
    context.translateBy(x: bounds.midX, y: bounds.midY)
    context.scaleBy(x: zoomLevel, y: zoomLevel)
    context.translateBy(x: -bounds.midX, y: -bounds.midY)
    
    // Render annotations
    annotationModel.renderAll(in: context)
    
    context.restoreGState()
}
```

### Zoom State Management
```swift
func setZoomLevel(_ level: CGFloat) {
    let clampedLevel = max(minZoomLevel, min(maxZoomLevel, level))
    if clampedLevel != zoomLevel {
        zoomLevel = clampedLevel
        updateZoomUI()
        setNeedsDisplay()
    }
}

func zoomIn() {
    setZoomLevel(zoomLevel + zoomStep)
}

func zoomOut() {
    setZoomLevel(zoomLevel - zoomStep)
}

func zoomToFit() {
    // Calculate optimal zoom level to fit image in view
    let optimalZoom = calculateOptimalZoomLevel()
    setZoomLevel(optimalZoom)
}

func calculateOptimalZoomLevel() -> CGFloat {
    guard let imageSize = workingImage?.size else { return 1.0 }
    let widthRatio = bounds.width / imageSize.width
    let heightRatio = bounds.height / imageSize.height
    return min(widthRatio, heightRatio)
}
```

## Testing Requirements

### Unit Tests
1. **Zoom Level Clamping**: Test that zoom levels are properly clamped between min and max values
2. **Zoom Step Accuracy**: Verify that zoom steps work correctly (10% increments)
3. **Coordinate Transformation**: Test that point transformations work correctly
4. **Zoom to Fit Calculation**: Verify optimal zoom level calculation
5. **Zoom State Persistence**: Test that zoom state is maintained during operations

### Integration Tests
1. **Keyboard Shortcuts**: Test zoom in/out/fit keyboard shortcuts
2. **Toolbar Controls**: Verify zoom buttons functionality
3. **Annotation Positioning**: Test that annotations maintain position during zoom
4. **Smooth Zoom Transitions**: Verify smooth zoom animations
5. **Edge Cases**: Test zoom at minimum and maximum levels

### Performance Tests
1. **Large Images**: Test zoom performance with high-resolution images
2. **Many Annotations**: Test zoom performance with many annotations
3. **Memory Usage**: Monitor memory usage during zoom operations
4. **Render Performance**: Measure rendering time during zoom changes

## Success Criteria

- Zoom in/out functionality works with keyboard shortcuts
- Toolbar controls display correct zoom level and respond to user input
- Annotations maintain their positions during zoom operations
- Zoom to fit functionality works correctly
- Smooth zoom transitions without performance issues
- All edge cases handled properly
- Comprehensive test coverage