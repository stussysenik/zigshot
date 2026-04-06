## ADDED Requirements

### Requirement: Preferences window
The app SHALL provide a Preferences window accessible via Cmd+, from the app menu. The window SHALL use NSTabView with tabs: General, Shortcuts, Fonts.

#### Scenario: Open preferences
- **WHEN** user presses Cmd+, or selects Preferences from the ZigShot menu
- **THEN** the Preferences window opens centered on screen

#### Scenario: Single instance
- **WHEN** user presses Cmd+, while Preferences is already open
- **THEN** the existing window is brought to front (no duplicate)

### Requirement: General tab
The General tab SHALL allow configuring: default export format (PNG/JPEG/PDF), default save location (directory picker), default annotation color (color well), default stroke width (slider 1-20).

#### Scenario: Change default export format
- **WHEN** user selects "PDF" as default export format in General tab
- **THEN** the Save dialog defaults to PDF format for new captures

#### Scenario: Change default save location
- **WHEN** user picks ~/Documents as default save location
- **THEN** Quick Save (Cmd+S) saves to ~/Documents instead of Desktop

#### Scenario: Settings persist
- **WHEN** user changes settings and quits the app
- **THEN** settings are preserved on next launch (stored in UserDefaults)

### Requirement: Shortcuts tab
The Shortcuts tab SHALL display a two-column table: Action name and current shortcut. Users SHALL be able to click a shortcut cell and press a new key combination to rebind it.

#### Scenario: Rebind capture shortcut
- **WHEN** user clicks the shortcut cell for "Capture Area" and presses Cmd+Shift+2
- **THEN** the shortcut is updated and the hotkey manager uses the new binding immediately

#### Scenario: Conflict detection
- **WHEN** user assigns a shortcut that conflicts with an existing binding
- **THEN** the system shows a warning: "This shortcut is already assigned to [Action]. Replace?" with Replace/Cancel buttons

#### Scenario: Reset to defaults
- **WHEN** user clicks "Reset to Defaults" button
- **THEN** all shortcuts revert to their factory values

### Requirement: Fonts tab
The Fonts tab SHALL list all imported custom fonts with Add and Remove buttons. See custom-fonts spec for details.

#### Scenario: Add font from Fonts tab
- **WHEN** user clicks "Add Font" in the Fonts tab
- **THEN** an open panel appears filtered to .ttf and .otf files

### Requirement: Menu bar integration
The app menu SHALL include: Preferences (Cmd+,), Re-open Last Edit (Cmd+Shift+L), and Recent Captures submenu.

#### Scenario: Menu items present
- **WHEN** user clicks the ZigShot menu bar icon
- **THEN** the menu shows: Capture Fullscreen, Capture Area, Capture Window, separator, Recent Captures >, Re-open Last Edit, separator, Preferences, Quit
