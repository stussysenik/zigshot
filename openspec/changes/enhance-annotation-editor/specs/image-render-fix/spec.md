# Image Render Fix

## MODIFIED Requirements

### Requirement: Captured image MUST render right-side-up in annotation editor

The annotation editor canvas MUST display the captured screenshot in its correct orientation — text readable left-to-right, top-to-bottom — regardless of the NSView's coordinate system.

#### Scenario: Fullscreen capture opens in editor
- **Given** a fullscreen screenshot is captured
- **When** the annotation editor window opens
- **Then** the image displays with correct orientation (not flipped or rotated)
- **And** text in the captured image is readable in normal reading order

#### Scenario: Area capture opens in editor
- **Given** an area selection screenshot is captured
- **When** the annotation editor window opens
- **Then** the image displays with correct orientation matching the screen content

#### Scenario: Image transforms preserve orientation
- **Given** the user applies rotate or flip from the toolbar
- **When** the transform completes
- **Then** the resulting image displays in the expected transformed orientation
