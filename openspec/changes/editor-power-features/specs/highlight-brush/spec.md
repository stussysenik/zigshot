## ADDED Requirements

### Requirement: Freehand highlight brush
The highlight tool (H) SHALL draw a freehand brush stroke instead of a filled rectangle. The stroke SHALL use rounded line caps and the currently selected color at 40% opacity.

#### Scenario: Drawing a highlight stroke
- **WHEN** user selects the Highlight tool and drags across the canvas
- **THEN** a freehand path follows the mouse with rounded caps, rendered in the selected color at 40% opacity

#### Scenario: Highlight width control
- **WHEN** user presses `[` or `]` while the Highlight tool is selected
- **THEN** the highlight brush width decreases or increases (range 8-40px, default 20px)

### Requirement: Highlight opacity adjustment
The highlight tool SHALL support opacity adjustment via Shift+`[` and Shift+`]` keys (range 20%-80%, step 10%, default 40%).

#### Scenario: Adjusting highlight opacity
- **WHEN** user presses Shift+`[` while the Highlight tool is active
- **THEN** the highlight opacity decreases by 10% (minimum 20%)

#### Scenario: Opacity visible in preview
- **WHEN** user is dragging a highlight stroke
- **THEN** the Core Graphics preview SHALL render at the current opacity setting minus 10% (to differentiate preview from committed)

### Requirement: Highlight path simplification
The system SHALL simplify freehand highlight paths before storing them in the annotation model to limit storage size.

#### Scenario: Path point reduction
- **WHEN** user finishes drawing a highlight stroke
- **THEN** the path SHALL be simplified to at most 100 points using Ramer-Douglas-Peucker algorithm while preserving visual fidelity

### Requirement: Highlight annotation descriptor
The AnnotationDescriptor SHALL include a `highlightPath` case with points array, color, width, and opacity.

#### Scenario: Descriptor replaces old highlight
- **WHEN** the codebase compiles
- **THEN** the old `.highlight(rect:color:)` case SHALL NOT exist; it is replaced by `.highlightPath(points:color:width:opacity:)`
