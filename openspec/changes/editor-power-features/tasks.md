## 1. Foundation — AnnotationDescriptor changes

- [x] 1.1 Replace `.highlight(rect:color:)` with `.highlightPath(points:color:width:opacity:)` in AnnotationDescriptor enum, update `bounds` computed property to use path bounding box
- [x] 1.2 Extend `.text` case to add `fontName: String?`, `isBold: Bool`, `isItalic: Bool`, `alignment: NSTextAlignment` — update all call sites
- [x] 1.3 Extend `.stickyNote` case to add `fontName: String?`, `isBold: Bool`, `isItalic: Bool`, `alignment: NSTextAlignment` — update all call sites
- [x] 1.4 Add `Codable` conformance to `AnnotationDescriptor` with custom CodingKeys (NSColor as hex, CGPoint/CGRect standard)
- [x] 1.5 Update `AnnotationModel.renderAll()` to handle the new `highlightPath` case — render as series of thick line segments via Zig bridge

## 2. Highlight brush tool

- [x] 2.1 Rewrite `HighlightToolHandler` to track freehand path: `start` inits path, `update` appends points, `finish` simplifies and returns `.highlightPath`
- [x] 2.2 Implement Ramer-Douglas-Peucker path simplification (max 100 points) as a standalone function
- [x] 2.3 Update `drawPreview` in HighlightToolHandler to render the freehand path with rounded caps via Core Graphics
- [x] 2.4 Add highlight width control (`[`/`]` keys, range 8-40px, default 20px) in `AnnotationEditorView.keyDown`
- [x] 2.5 Add highlight opacity control (Shift+`[`/`]`, range 20%-80%, step 10%, default 40%) in `AnnotationEditorView.keyDown`
- [x] 2.6 Render committed highlight paths in `AnnotationModel.renderAll()` via Zig line segments with round caps

## 3. PDF export

- [x] 3.1 Add `savePDF(to:dpi:)` method to `ZigShotImage` using `CGContext` with PDF media type
- [x] 3.2 Add "PDF" button to `AnnotationEditorWindow` title bar accessory (alongside PNG, Save, Copy)
- [x] 3.3 Wire `window.onPDF` callback in `AppDelegate.openAnnotationEditor` — saves to default save directory as `ZigShot-YYYY-MM-DD-HHmmss.pdf`
- [x] 3.4 Add PDF as third format option in the save dialog format picker (NSPopUpButton), handle `.pdf` UTType

## 4. Session persistence — re-open last edit

- [x] 4.1 Create `SessionManager` class: `saveSession(originalImage:model:)` and `loadLastSession() -> (ZigShotImage, AnnotationModel)?`
- [x] 4.2 Serialize AnnotationModel to JSON via Codable — write to `~/Library/Application Support/ZigShot/sessions/last.json`, save original as `last-original.png`
- [x] 4.3 Call `SessionManager.saveSession()` from all editor close paths (onCopy, onPNG, onQuickSave, onSave)
- [x] 4.4 Add "Re-open Last Edit" (Cmd+Shift+L) menu item to AppDelegate menu bar; on click, load session and call `openAnnotationEditor`
- [x] 4.5 Handle no-session case: `NSSound.beep()` when no `last.json` exists

## 5. Capture history

- [x] 5.1 Create `CaptureHistoryManager` (merged into `SessionManager`): `addToHistory(image:annotations:)`, `recentCaptures(limit:)`, `pruneHistory(max:)`
- [x] 5.2 Generate and save thumbnails (max 300px wide) + metadata JSON per capture in `~/Library/Application Support/ZigShot/history/`
- [x] 5.3 Call `SessionManager.addToHistory()` from `handleCapturedImage` in AppDelegate
- [x] 5.4 Add "Recent Captures" submenu to menu bar with last 10 entries (thumbnail + timestamp)
- [x] 5.5 Wire submenu click to re-open capture in editor with saved annotations
- [x] 5.6 Add history pruning on app launch (cap at 50 entries)

## 6. Rich text controls

- [x] 6.1 Add Bold (B) and Italic (I) toggle buttons to AnnotationToolbar, visible when text/stickyNote tool is selected
- [x] 6.2 Add alignment buttons (Left/Center/Right) to AnnotationToolbar, visible when text/stickyNote tool is selected
- [x] 6.3 Add font picker NSPopUpButton to toolbar — list system fonts + custom fonts under separator
- [x] 6.4 Wire toolbar formatting state (bold, italic, alignment, fontName) into AnnotationEditorView as current properties
- [x] 6.5 Update TextEditingController to apply font/bold/italic/alignment to the NSTextView
- [x] 6.6 Update `TextEditingController.renderTextBitmap()` to use NSAttributedString with font name, bold, italic, alignment
- [x] 6.7 Update StickyNoteToolHandler to pass font/style attributes through to the descriptor
- [x] 6.8 Update `StickyNoteRenderer.renderBitmap()` to respect font name, bold, italic, alignment

## 7. Custom font management

- [x] 7.1 Create `FontManager` class: `importFont(from:)`, `removeFont(name:)`, `loadAllFonts()`, `availableFonts() -> [String]`
- [x] 7.2 Copy font files to `~/Library/Application Support/ZigShot/fonts/`, register via `CTFontManagerRegisterFontsForURL(.process)`
- [x] 7.3 Call `FontManager.loadAllFonts()` on app launch in AppDelegate
- [x] 7.4 Validate font files on import — show alert for invalid/corrupted files
- [x] 7.5 Wire FontManager into the toolbar font picker (refresh list after import/remove)

## 8. Preferences window

- [x] 8.1 Create `PreferencesWindow` (NSWindow + NSTabView) with General, Shortcuts, Fonts tabs
- [x] 8.2 General tab: default export format popup, save location directory picker, default color well, default stroke width slider — all backed by UserDefaults
- [x] 8.3 Shortcuts tab: two-column NSTableView (action name, shortcut), display of current shortcuts
- [x] 8.4 Shortcuts tab: "Reset to Defaults" button
- [x] 8.5 Fonts tab: NSTableView listing imported fonts, Add/Remove buttons wired to FontManager
- [x] 8.6 Add "Preferences" (Cmd+,) menu item to AppDelegate menu bar, ensure single-instance window
- [x] 8.7 Wire UserDefaults settings into AppDelegate (default save location, default format) and AnnotationEditorView (default color, default width)
- [ ] 8.8 Wire shortcut UserDefaults into HotkeyManager to support user-customized hotkeys (deferred — requires click-to-record shortcut binding)

## 9. Menu bar integration

- [x] 9.1 Restructure AppDelegate menu: add Recent Captures submenu, Re-open Last Edit item, Preferences item, separators
- [x] 9.2 Populate Recent Captures submenu dynamically from SessionManager on menu open

## 10. Verification

- [x] 10.1 Build and verify all features compile without warnings
- [ ] 10.2 Test highlight brush: draw freehand strokes, adjust width/opacity, verify preview and committed rendering match
- [ ] 10.3 Test PDF export: one-click and save-dialog, verify PDF opens correctly in Preview.app
- [ ] 10.4 Test session persistence: annotate, copy, re-open — verify annotations restored
- [ ] 10.5 Test capture history: capture 3 screenshots, verify Recent Captures menu populates, click to re-open
- [ ] 10.6 Test rich text: bold, italic, alignment, font change — verify rendering in text and sticky notes
- [ ] 10.7 Test custom fonts: import TTF, use in text annotation, quit and relaunch, verify font persists
- [ ] 10.8 Test preferences: change defaults, verify they take effect, quit and relaunch
