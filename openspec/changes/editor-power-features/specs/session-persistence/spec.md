## ADDED Requirements

### Requirement: Save session on editor close
The system SHALL persist the current editor session (original image + annotations) when the user copies, saves, or exports. The session SHALL be saved to `~/Library/Application Support/ZigShot/sessions/`.

#### Scenario: Session saved on copy
- **WHEN** user clicks Copy or presses Cmd+C/Enter in the editor
- **THEN** the original image is saved as `last-original.png` and the annotation model is serialized to `last.json` in the sessions directory

#### Scenario: Session saved on save/export
- **WHEN** user saves via PNG button, Save dialog, or Quick Save
- **THEN** the session state is persisted identically to the copy flow

### Requirement: Re-open last edit
The system SHALL provide a "Re-open Last Edit" action accessible via Cmd+Shift+L from the menu bar and the app menu.

#### Scenario: Re-open restores annotations
- **WHEN** user triggers Re-open Last Edit and a valid session exists
- **THEN** the editor opens with the original image loaded and all annotations restored from the saved model

#### Scenario: No previous session
- **WHEN** user triggers Re-open Last Edit and no session file exists
- **THEN** the system plays the system alert sound (NSSound.beep) and takes no further action

### Requirement: Annotation model Codable conformance
AnnotationDescriptor SHALL conform to Codable for JSON serialization. NSColor SHALL serialize as hex string. CGPoint and CGRect SHALL use standard Codable encoding.

#### Scenario: Round-trip serialization
- **WHEN** an annotation model with mixed annotation types is serialized to JSON and deserialized back
- **THEN** all annotation descriptors SHALL be identical to the originals (within floating-point tolerance of 0.001)

### Requirement: Capture history
The system SHALL maintain a history of the last 50 captures with thumbnails in `~/Library/Application Support/ZigShot/history/`.

#### Scenario: Capture added to history
- **WHEN** user captures a screenshot (fullscreen, area, or window)
- **THEN** a thumbnail (max 300px wide, aspect-preserved) and metadata (timestamp, dimensions, annotation count) are saved to the history directory

#### Scenario: Recent Captures menu
- **WHEN** user clicks the ZigShot menu bar icon
- **THEN** a "Recent Captures" submenu shows the last 10 captures with thumbnail preview and timestamp

#### Scenario: Open from history
- **WHEN** user clicks a capture in the Recent Captures submenu
- **THEN** the editor opens with that capture's original image and saved annotations (if any)

#### Scenario: History pruning
- **WHEN** the history exceeds 50 entries
- **THEN** the oldest entries are deleted on next app launch
