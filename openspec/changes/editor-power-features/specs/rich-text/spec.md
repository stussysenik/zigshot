## ADDED Requirements

### Requirement: Bold and italic toggles
The toolbar SHALL show Bold (B) and Italic (I) toggle buttons when the text or stickyNote tool is selected.

#### Scenario: Bold text annotation
- **WHEN** user enables Bold, types text, and commits
- **THEN** the text annotation renders in the bold variant of the current font

#### Scenario: Bold+Italic combined
- **WHEN** user enables both Bold and Italic
- **THEN** the text renders in bold-italic variant

#### Scenario: Toggle persistence within session
- **WHEN** user enables Bold for one text annotation and then creates another
- **THEN** the Bold toggle remains active for the new annotation

### Requirement: Text alignment control
The toolbar SHALL show alignment buttons (Left, Center, Right) when text or stickyNote tool is selected.

#### Scenario: Center-aligned text
- **WHEN** user selects Center alignment and types multi-line text in a sticky note
- **THEN** all lines are center-aligned within the sticky note bounds

#### Scenario: Default alignment
- **WHEN** user creates a text annotation without changing alignment
- **THEN** the text is left-aligned by default

### Requirement: Font picker
The toolbar SHALL show a font dropdown (NSPopUpButton) when text or stickyNote tool is selected. The dropdown SHALL list system fonts and any user-imported custom fonts.

#### Scenario: Change font
- **WHEN** user selects "Menlo" from the font picker and types text
- **THEN** the text annotation renders in Menlo at the selected size

#### Scenario: Font picker shows custom fonts
- **WHEN** user has imported custom fonts via Preferences
- **THEN** those fonts appear in the font picker dropdown under a "Custom" separator

### Requirement: Extended text descriptor
AnnotationDescriptor.text SHALL carry `fontName: String?`, `isBold: Bool`, `isItalic: Bool`, `alignment: NSTextAlignment` in addition to existing fields.

#### Scenario: Default values
- **WHEN** a text annotation is created without changing formatting
- **THEN** fontName is nil (system font), isBold is false, isItalic is false, alignment is .left

### Requirement: Extended sticky note descriptor
AnnotationDescriptor.stickyNote SHALL carry the same font/style fields as text.

#### Scenario: Styled sticky note
- **WHEN** user creates a sticky note with Bold enabled and Menlo font selected
- **THEN** the sticky note text renders in Menlo Bold
