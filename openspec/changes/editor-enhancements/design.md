# Editor Enhancements Design

## Context

ZigShot has successfully implemented Phase 3 features including rich text annotations, session persistence, PDF export, and custom fonts. The editor now has a functional toolbar with 12 tools, but lacks advanced editing capabilities like zoom controls, proper undo/redo, and professional UI design. The current implementation has:

- Basic annotation tools with limited functionality
- No zoom or scaling capabilities
- Limited color customization options
- No OCR or advanced text processing
- Simple toolbar layout without organization
- Minimal UI polish

## Goals / Non-Goals

**Goals:**
- Implement zoom in/out functionality with keyboard shortcuts
- Redesign toolbar for better space utilization and organization
- Modernize UI with clean, professional design
- Add favorite colors and persistent color presets
- Implement comprehensive undo/redo system
- Fix text positioning stability during crop operations
- Add OCR functionality for text extraction
- Support item-level color customization
- Implement truth table generation and visualization
- Extend toolbar with additional tools and features
- Add share button with export format selection

**Non-Goals:**
- Cloud synchronization (Phase 5)
- Collaboration features
- Advanced image processing (beyond OCR)
- AI-powered enhancements
- Complex mathematical tools beyond truth tables
- Custom tool creation by users

## Architecture Decisions

### D1: Zoom System Implementation

**Choice**: Implement zoom as a transform applied to the entire editor canvas rather than individual annotation scaling.

**Why**: This approach maintains annotation coordinates relative to the image, making it easier to handle complex operations like crop and resize. Zoom state is managed in `AnnotationEditorView` with coordinate transformation functions.

**Implementation**:
- Add `zoomLevel: CGFloat` property to `AnnotationEditorView`
- Implement `setZoomLevel(_:)` method with coordinate transformation
- Add keyboard shortcut handling for Cmd + and Cmd -
- Update rendering pipeline to apply zoom transform
- Maintain annotation positions during zoom operations

**Alternative rejected**: Individual annotation scaling would require complex coordinate recalculations and could lead to precision issues.

### D2: Toolbar Redesign

**Choice**: Implement a modern, organized toolbar with tool groups, separators, and collapsible sections.

**Why**: The current toolbar is crowded and lacks organization. Grouping related tools improves usability and space efficiency.

**Implementation**:
- Redesign `AnnotationToolbar` with tool groups
- Add separators between tool categories
- Implement responsive layout for different screen sizes
- Add tool visibility toggles for customization
- Improve icon clarity and consistency

**Tool Groups**:
1. **Selection Tools**: Move, Select, Crop, Rotate
2. **Drawing Tools**: Pen, Highlight, Ruler, Arrow
3. **Text Tools**: Text, Sticky Note, Numbering
4. **Special Tools**: OCR, Truth Table, Share

### D3: Undo/Redo System

**Choice**: Implement a command pattern-based undo/redo system with state snapshots.

**Why**: This provides a robust mechanism for handling complex annotation operations and maintains a clear separation of concerns.

**Implementation**:
- Create `AnnotationCommand` protocol with `execute()` and `undo()` methods
- Implement `UndoManager` class to manage command history
- Add state snapshotting for each operation
- Support multiple history levels with configurable limits
- Add visual feedback for undo/redo state

**Command Types**:
- `AddAnnotationCommand`
- `RemoveAnnotationCommand` 
- `ModifyAnnotationCommand`
- `CropCommand`
- `ZoomCommand`

### D4: OCR Integration

**Choice**: Use Apple's Vision framework for OCR functionality with Tesseract fallback for advanced features.

**Why**: Vision framework provides native macOS OCR capabilities with good accuracy and performance. Tesseract can be used as a fallback for more advanced text recognition.

**Implementation**:
- Integrate Vision framework for basic OCR
- Add OCR tool to toolbar
- Implement text extraction and highlighting
- Support multiple languages
- Add text editing capabilities for extracted text

**Workflow**:
1. User selects OCR tool and draws bounding box
2. System processes image region with Vision framework
3. Extracted text is displayed and can be edited
4. User can add extracted text as annotation or export

### D5: Favorite Colors System

**Choice**: Extend existing color system with persistent favorites and preset management.

**Why**: Users need the ability to save custom colors for consistent annotation work.

**Implementation**:
- Extend `colorPresets` to support favorites
- Add color preset management UI
- Implement UserDefaults persistence
- Add "+" button for saving custom colors
- Support right-click to remove custom colors

**Storage**:
- Built-in colors: 5 system colors
- Custom colors: Up to 5 user-defined colors
- Total limit: 10 colors

### D6: Text Stability on Crop

**Choice**: Implement crop-aware coordinate system that maintains annotation positions relative to image content.

**Why**: Current implementation loses text positioning when cropping, which is a critical usability issue.

**Implementation**:
- Update coordinate system to be crop-aware
- Maintain annotation positions relative to image boundaries
- Implement crop transformation for all annotations
- Test with various crop scenarios and edge cases

### D7: Truth Table Implementation

**Choice**: Implement truth table generator with logical operation support.

**Why**: This adds value for users working with logical operations and digital logic design.

**Implementation**:
- Create `TruthTableGenerator` class
- Support basic logical operations (AND, OR, NOT, XOR)
- Allow custom input values and variable count
- Implement table visualization
- Add export functionality (text, image, PDF)

**Features**:
- Variable count: 2-4 variables
- Operations: AND, OR, NOT, XOR, NAND, NOR
- Export formats: Text, CSV, Image, PDF
- Customizable table appearance

### D8: Share Button Implementation

**Choice**: Implement direct share functionality with export format selection.

**Why**: Users need quick and easy ways to share their annotated images.

**Implementation**:
- Add share button to toolbar
- Implement export format selection dialog
- Support multiple export destinations (Mail, Messages, Files, etc.)
- Add quick export presets
- Implement format-specific export options

**Export Formats**:
- PNG (with transparency)
- JPEG (with quality settings)
- PDF (single page)
- WebP (if supported)
- TIFF (high quality)

## Risks / Trade-offs

- **Performance Impact**: Zoom and OCR features may impact performance with large images
  - Mitigation: Implement efficient rendering with caching and background processing
  - Testing: Profile with large Retina captures and complex annotations

- **Complexity**: Undo system and OCR integration are complex
  - Mitigation: Modular implementation with clear separation of concerns
  - Testing: Comprehensive unit and integration tests

- **UI Clutter**: Adding many features may overwhelm users
  - Mitigation: Organize tools logically and provide customization options
  - Testing: User testing and feedback collection

- **Compatibility**: OCR and truth table features may have platform limitations
  - Mitigation: Use native frameworks and provide fallback options
  - Testing: Test across different macOS versions and hardware

## Implementation Plan

### Phase 1: Core Enhancements
1. Zoom controls and toolbar redesign
2. Clean UI design implementation
3. Favorite colors and undo system
4. Text stability fixes

### Phase 2: Advanced Features
1. OCR integration
2. Item color customization
3. Font enhancements and improvements

### Phase 3: Specialized Tools
1. Truth table implementation
2. Toolbar extension with new tools
3. Share button and export improvements

## Success Metrics

- **User Satisfaction**: Improved ratings and positive feedback
- **Feature Adoption**: High usage of new features (target: 70%+)
- **Performance**: No significant performance degradation (target: <5% impact)
- **Stability**: Minimal bugs and crashes (target: <1% error rate)
- **Usability**: Improved task completion times and user efficiency
```
