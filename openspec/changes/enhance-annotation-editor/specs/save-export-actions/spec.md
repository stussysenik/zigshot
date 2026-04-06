# Save & Export Actions

## MODIFIED Requirements

### Requirement: PNG button MUST quick-save to Desktop

The "PNG" title bar button SHALL immediately save the current image (with annotations baked in) as a PNG file to the user's Desktop, with no dialog.

#### Scenario: Quick save via PNG button
- **Given** the annotation editor is open with an image
- **When** the user clicks the "PNG" button
- **Then** the image saves as `ZigShot-{timestamp}.png` on the Desktop
- **And** the DPI metadata matches the screen's backing scale factor
- **And** a brief visual confirmation appears (e.g., window title flash or subtle animation)

### Requirement: Save button MUST open NSSavePanel

The "Save" button SHALL open a standard macOS Save dialog where the user chooses location, filename, and format.

#### Scenario: Save with format selection
- **Given** the user clicks "Save" in the title bar
- **When** the NSSavePanel appears
- **Then** it shows a format picker accessory (PNG / JPEG)
- **And** the default filename is `ZigShot-{timestamp}`
- **And** the default location is Desktop

#### Scenario: Save as JPEG with quality
- **Given** the NSSavePanel is open
- **When** the user selects JPEG format
- **Then** the file saves as JPEG with 92% quality
- **And** the file extension updates to `.jpg`

#### Scenario: Save as PNG
- **Given** the NSSavePanel is open
- **When** the user selects PNG format (default)
- **Then** the file saves as PNG with sRGB color profile
- **And** the file extension is `.png`

### Requirement: Copy button MUST copy and dismiss

The "Copy" button SHALL copy the annotated image to the clipboard as PNG and close the window. (Already implemented — no changes needed.)

#### Scenario: Copy to clipboard
- **Given** the annotation editor is open
- **When** the user clicks "Copy" or presses Enter
- **Then** the image copies to clipboard as PNG
- **And** the editor window dismisses
