## ADDED Requirements

### Requirement: Import custom fonts
The Preferences window SHALL allow users to import .ttf and .otf font files. Imported fonts SHALL be copied to `~/Library/Application Support/ZigShot/fonts/` and registered with `CTFontManagerRegisterFontsForURL` at process scope.

#### Scenario: Import a TTF font
- **WHEN** user clicks "Add Font" in Preferences and selects a .ttf file
- **THEN** the font is copied to the fonts directory, registered for the process, and appears in the font picker

#### Scenario: Import an OTF font
- **WHEN** user clicks "Add Font" in Preferences and selects a .otf file
- **THEN** the font is handled identically to TTF

### Requirement: Font persistence across launches
Imported fonts SHALL be automatically re-registered on app launch by scanning the fonts directory.

#### Scenario: Font available after restart
- **WHEN** user imports a font, quits the app, and relaunches
- **THEN** the font is available in the font picker without re-importing

### Requirement: Remove imported font
Users SHALL be able to remove an imported font from the Preferences font list.

#### Scenario: Remove font
- **WHEN** user selects an imported font in Preferences and clicks "Remove"
- **THEN** the font file is deleted from the fonts directory and the font is unregistered from the process

### Requirement: Invalid font handling
The system SHALL validate font files before importing.

#### Scenario: Invalid font file
- **WHEN** user attempts to import a corrupted or unsupported font file
- **THEN** the system shows an alert: "Could not load font. The file may be corrupted or in an unsupported format." and does not add it to the fonts directory
