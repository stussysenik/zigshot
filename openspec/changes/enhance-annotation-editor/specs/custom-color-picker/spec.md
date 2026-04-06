# Custom Color Picker

## ADDED Requirements

### Requirement: Users MUST be able to pick any arbitrary color for annotations

The toolbar SHALL provide a system color picker (NSColorWell) in addition to the 5 preset color dots, allowing selection of any color via hex input, eyedropper, or color wheel.

#### Scenario: Open color picker from toolbar
- **Given** the annotation editor is open
- **When** the user clicks the color well in the toolbar
- **Then** the system color panel opens
- **And** the user can select any color

#### Scenario: Custom color applies to drawing tools
- **Given** the user selects a custom color from the color picker
- **When** they draw an annotation (arrow, rectangle, line, etc.)
- **Then** the annotation uses the custom color

#### Scenario: Preset dot deselects when custom color active
- **Given** a preset color dot is selected (showing ring)
- **When** the user picks a custom color from the color well
- **Then** all preset dots deselect (rings hidden)
- **And** the color well shows the active custom color

#### Scenario: Selecting preset dot syncs color well
- **Given** a custom color is active in the color well
- **When** the user clicks a preset color dot
- **Then** the dot shows its selection ring
- **And** the color well updates to match the preset color

#### Scenario: Keyboard shortcut for custom color
- **Given** the editor has focus
- **When** the user presses a designated key (e.g., "p" for picker)
- **Then** the system color panel opens
