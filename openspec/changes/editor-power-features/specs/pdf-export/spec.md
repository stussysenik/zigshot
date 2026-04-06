## ADDED Requirements

### Requirement: PDF export button in title bar
The editor window title bar SHALL include a "PDF" button alongside the existing PNG, Save, and Copy buttons.

#### Scenario: One-click PDF export
- **WHEN** user clicks the PDF button in the title bar
- **THEN** the current annotated image is saved as a PDF to the Desktop with filename `ZigShot-YYYY-MM-DD-HHmmss.pdf` and the editor window closes

### Requirement: PDF in save dialog
The save dialog format picker SHALL include PDF as a third option alongside PNG and JPEG.

#### Scenario: Save as PDF via dialog
- **WHEN** user clicks Save, selects PDF from the format picker, and confirms
- **THEN** a single-page PDF is created at the chosen location with the annotated image rendered at full resolution

### Requirement: PDF rendering via Quartz
PDF export SHALL use `CGContext` with PDF media type. The media box SHALL match the image dimensions in points (pixels / screen scale factor). The image SHALL be drawn at full resolution.

#### Scenario: PDF quality
- **WHEN** a 2880x1800 Retina screenshot is exported as PDF
- **THEN** the PDF page size SHALL be 1440x900 points with the image rendered at 2x (144 DPI) for crisp display

#### Scenario: PDF includes DPI metadata
- **WHEN** a PDF is exported
- **THEN** the PDF SHALL contain the correct DPI metadata matching the source capture's scale factor
