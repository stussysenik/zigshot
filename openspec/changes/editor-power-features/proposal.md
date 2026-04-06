## Why

ZigShot's annotation editor is functional but missing key power-user features that Shottr/CleanShot users expect: the highlight tool is a flat rectangle with no brush feel, there's no way to re-open the last edit, no capture history, export is limited to PNG/JPEG (no PDF), text annotations lack formatting controls and custom fonts, and keyboard shortcuts aren't user-configurable. These gaps make ZigShot feel like a beta tool rather than a daily driver.

## What Changes

- **Highlight tool redesign**: Replace flat-rect highlight with a freehand brush-stroke mode (rounded caps, variable thickness via `[`/`]` keys, adjustable opacity)
- **Re-open last edit**: Persist the last editor session (original image + annotation model as JSON) to `~/Library/Application Support/ZigShot/sessions/` so users can re-open with Cmd+Shift+L
- **Capture history**: Store recent captures (last 50) with thumbnails in Application Support; add "Recent Captures" submenu to menu bar; click to re-open in editor
- **PDF export**: Add PDF as a third format option in the save dialog and as a one-click "PDF" button in the title bar alongside PNG
- **Rich text tool**: Add bold/italic toggles, text alignment (left/center/right), and a font picker popover to the toolbar when text/stickyNote tool is selected
- **Custom font import**: Let users load `.ttf`/`.otf` fonts from disk that appear in the font picker without system-wide installation
- **Settings/preferences**: Add a Preferences window (Cmd+,) with tabs for: keyboard shortcut customization, default export format, default save location, default annotation color/width

## Capabilities

### New Capabilities
- `highlight-brush`: Freehand brush-stroke highlight with rounded caps, variable width, and adjustable opacity
- `session-persistence`: Save/restore last editor session for re-open; recent captures history with thumbnails
- `pdf-export`: PDF export via ImageIO/Quartz, available in save dialog and as one-click title bar button
- `rich-text`: Bold/italic/alignment controls and font picker popover for text and sticky note tools
- `custom-fonts`: Load user .ttf/.otf fonts into an app-scoped font collection for use in annotations
- `preferences`: Preferences window with keyboard shortcut editor, default export/save settings, annotation defaults

### Modified Capabilities

## Impact

- **AnnotationToolHandler.swift**: HighlightToolHandler rewritten to track freehand path instead of rect
- **AnnotationModel.swift**: New `AnnotationDescriptor.highlight` case changes from `rect:` to `path:` points array — **BREAKING** for existing highlight annotations (none persisted yet, so safe)
- **AnnotationToolbar.swift**: New toolbar sections for text formatting, opacity slider for highlight
- **AnnotationEditorWindow.swift**: PDF button added to title bar accessory
- **AppDelegate.swift**: Preferences menu item, recent captures submenu, re-open last edit action, session persistence on close
- **TextEditingController.swift**: Font/style attributes flow through to AnnotationDescriptor.text
- **New files**: PreferencesWindow.swift, SessionManager.swift, CaptureHistoryManager.swift, FontManager.swift
- **Dependencies**: None new — PDF via Quartz/ImageIO (system), font loading via CTFontManager (system)
