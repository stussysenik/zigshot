# ZigShot SwiftUI Rewrite — Design Specification

**Date:** 2026-04-05
**Status:** Draft
**Scope:** Rewrite UI layer from AppKit to SwiftUI; add Shottr/CleanShot X essential features

---

## Context

ZigShot has a complete Zig core (`libzigshot.a`) with 13 C API functions for image manipulation, annotations, and blur. The Swift app (Phases 0-3) works but uses imperative AppKit for all UI. This rewrite moves the UI layer to SwiftUI while preserving the Zig bridge and ScreenCaptureKit capture pipeline.

**Design language:** Things + iA Writer — monochrome, typographic, invisible until needed. Light theme first. Content is the color; the chrome disappears.

---

## Architecture

```
┌─────────────────────────────────────────────┐
│  SwiftUI Layer                              │
│  ┌──────────┐ ┌──────────┐ ┌─────────────┐ │
│  │ MenuBar  │ │ Quick    │ │ Editor      │ │
│  │ App      │ │ Overlay  │ │ Window      │ │
│  └──────────┘ └──────────┘ └──────┬──────┘ │
│                                    │        │
│  ┌──────────┐ ┌──────────┐ ┌──────┴──────┐ │
│  │ Toolbar  │ │ Export   │ │ Canvas      │ │
│  │ View     │ │ Sheet    │ │ (NSView     │ │
│  └──────────┘ └──────────┘ │  Reprable)  │ │
│                             └──────┬──────┘ │
├────────────────────────────────────┼────────┤
│  Bridge Layer                      │        │
│  ┌─────────────────────────────────┴──────┐ │
│  │ ZigShotBridge (ZigShotImage wrapper)   │ │
│  └─────────────────────────────────┬──────┘ │
├────────────────────────────────────┼────────┤
│  Zig Core (libzigshot.a)           │        │
│  image · annotations · blur · export       │
└─────────────────────────────────────────────┘
```

### Key Decision: NSViewRepresentable Canvas

The annotation canvas remains an NSView wrapped in `NSViewRepresentable`. Reason: mouse tracking with sub-pixel precision, Core Graphics direct rendering, and Zig pixel buffer interop all require AppKit-level control. SwiftUI's Canvas view lacks the mouse event granularity needed for annotation tools.

Everything else (toolbar, overlay, export sheet, preferences, window chrome) is pure SwiftUI.

### Data Flow (SwiftUI Pro rules)

- **`@Observable` for all shared state**, marked `@MainActor`
- **No `ObservableObject`/`@Published`** — modern `@Observable` only
- **`@State private`** for view-local state
- **`@Environment`** for passing shared models down the tree
- **`task()`** over `onAppear()` for async work
- **One type per file**, views extracted into separate structs

---

## Feature Scope — v1

### Capture Modes (existing, kept)
- **Fullscreen** — Cmd+Shift+3
- **Area selection** — Cmd+Shift+4, crosshair + live dimensions
- **Window** — Cmd+Shift+5, hover highlight

### Post-Capture UX (new)

#### Quick Access Overlay
After any capture, a floating pill appears in the bottom-right corner:
- **Thumbnail** (80x56pt, rounded corners, subtle shadow)
- **Actions:** Copy (primary), Annotate, Save
- **Dismiss:** Click X or auto-dismiss after 5s
- **Drag:** Drag thumbnail directly to any app for instant share
- Implemented as a SwiftUI `Window` with `.windowStyle(.plain)` and `.windowLevel(.floating)`

#### Clipboard-First
- Default action after capture: **copy PNG to clipboard**
- No files saved to Desktop unless user explicitly saves
- Enter in editor = copy + close
- Status bar flash confirms copy

### Annotation Editor (rewrite)

#### Window
- Borderless SwiftUI window, full-screen
- Light background (`#FAFAFA`), no dark backdrop
- Screenshot centered with breathing room (max 85% of viewport)
- Screenshot rendered with:
  - 12pt rounded corners (clipped)
  - Subtle drop shadow: `0 8px 40px rgba(0,0,0,0.08)`
  - Optional background wrap (see Backgrounds below)

#### Toolbar (bottom, floating)
Minimal pill anchored to bottom center, 12px from edge:

```
[ Select | Arrow | Rect | Text | Blur | Highlight | Ruler | Number ]  |  [ colors ]  |  OCR | Eyedropper  |  [ Copy  Save  ✕ ]
```

- **Material:** `.ultraThinMaterial` with `clipShape(.capsule)`
- **Icons:** SF Symbols, 16pt, monochrome
- **Active tool:** Black fill on white background (light theme)
- **Inactive:** `#BBBBBB`, 50% opacity
- **Color dots:** 16pt circles — Red (#FF3B30), Yellow (#FFCC00), Blue (#007AFF), Green (#34C759), Black (#1A1A1A)
- **Active color:** 2px black ring
- **Keyboard shortcuts:** A/R/B/H/T/L/U/N for tools, 1-5 for colors, [/] for width

#### Tools (8 existing + 2 new)

**Existing (from Phase 3, behavior preserved):**
1. **Arrow** — click-drag, anti-aliased, arrowhead
2. **Rectangle** — outline, 4pt rounded corners
3. **Blur** — drag region, Gaussian via Zig core
4. **Highlight** — semi-transparent overlay (40% alpha)
5. **Line** — anti-aliased straight line
6. **Ruler** — pixel distance with label at midpoint
7. **Numbering** — auto-incrementing circles
8. **Text** — inline NSTextView editing

**New:**
9. **OCR** (Cmd+Shift+O) — Select region, extract text via Vision framework, copy to clipboard. Toast notification confirms. Also available as a global hotkey without opening editor.
10. **Color Picker / Eyedropper** — Click any pixel, get hex/RGB value copied to clipboard. Magnified loupe (8x zoom, 100px diameter) follows cursor during pick mode. Value displayed in a floating label.

#### Undo/Redo
- Cmd+Z / Cmd+Shift+Z
- Existing dual-stack architecture preserved
- Full replay: copy original → apply all annotations in order

### Backgrounds (new)

Wrap screenshot in presentation-ready frame:
- **Padding:** 40/60/80px options
- **Corner radius:** 12pt on the screenshot itself
- **Background options:**
  - None (transparent)
  - Solid: White, Light Gray, Black
  - Gradient presets: 4-6 subtle gradients (soft purple, warm peach, cool blue, matte black, etc.)
- **Toggle:** Cmd+B to show/hide background panel
- **Rendering:** Background is composited around the annotated image at export time, not during editing. Editor always shows the clean screenshot.

### Rulers & Measurement (enhanced)

Beyond the existing ruler annotation tool:
- **Smart guides** — when moving annotations, show alignment lines to other annotations and image edges
- **Spacing indicators** — hold Option while hovering near an annotation to see distance to edges
- **Pixel coordinates** — status bar shows cursor position in image coordinates while in editor

### Export & Sharing

#### Clipboard Copy (default)
- Enter or Cmd+C → PNG to clipboard → close editor
- Toast: "Copied" with checkmark, fades after 1.5s

#### Save (Cmd+S)
- First save: NSSavePanel with smart defaults
  - Filename: `Screenshot YYYY-MM-DD at HH.MM.SS`
  - Format: PNG (default), JPEG
  - Location: last-used directory (persisted in UserDefaults)
- Subsequent saves in same session: save to same location silently

#### Drag & Drop
- Drag from the screenshot preview in editor → drop into any app
- Drag from quick overlay thumbnail → drop anywhere
- Uses `NSItemProvider` with PNG data

#### Format Controls
- Accessible from Save dialog or toolbar dropdown
- PNG (lossless, default), JPEG (quality slider 0-100)
- Live file size preview as quality changes
- WebP deferred until Zig core encoder is implemented

### Menu Bar App

- **No Dock icon** — `LSUIElement = true`
- **Status item:** Minimal camera icon (SF Symbol `camera.viewfinder`)
- **Menu:**
  - Capture Fullscreen (Cmd+Shift+3)
  - Capture Area (Cmd+Shift+4)
  - Capture Window (Cmd+Shift+5)
  - OCR Extract (Cmd+Shift+O)
  - ---
  - Preferences... (Cmd+,)
  - Quit ZigShot (Cmd+Q)

### Preferences (SwiftUI Settings scene)

Minimal, single-pane:
- **Save location** — default directory picker
- **Default format** — PNG / JPEG
- **JPEG quality** — slider (default 90)
- **Hotkeys** — display current mappings (custom hotkeys deferred)
- **Launch at login** — toggle
- **Capture sound** — toggle (default off)

---

## Design System

### Typography
- **SF Pro** (system font) throughout
- **Title:** 22pt, weight 700, tracking -0.02em
- **Body:** 13pt, weight 400
- **Label:** 11pt, weight 600, uppercase, tracking 0.1em, color `#BBBBBB`
- **Monospace (measurements):** SF Mono, 11pt, weight 600

### Color Palette
- **Background:** `#FAFAFA` (editor canvas), `#FFFFFF` (cards/panels)
- **Text primary:** `#1A1A1A`
- **Text secondary:** `#888888`
- **Text tertiary:** `#BBBBBB`
- **Border:** `#F0F0F0`
- **Annotation colors:** Red `#FF3B30`, Yellow `#FFCC00`, Blue `#007AFF`, Green `#34C759`, Black `#1A1A1A`

### Spacing
- Base unit: 4pt
- Toolbar padding: 12pt
- Canvas padding: 48pt
- Card padding: 16-24pt
- Inter-element gaps: 8-12pt

### Shadows
- **Screenshot:** `0 2px 8px rgba(0,0,0,0.06), 0 12px 48px rgba(0,0,0,0.08)`
- **Toolbar:** `0 1px 3px rgba(0,0,0,0.04), 0 8px 40px rgba(0,0,0,0.06)`
- **Quick overlay:** `0 4px 20px rgba(0,0,0,0.12)`

### Corner Radii
- **Screenshot preview:** 12pt
- **Toolbar pill:** capsule (full radius)
- **Buttons:** 8pt
- **Cards:** 14pt
- **Color dots:** circular

### Animations
- **Toolbar show/hide:** `.spring(response: 0.3, dampingFraction: 0.8)`
- **Quick overlay appear:** slide up + fade, 0.25s ease-out
- **Quick overlay dismiss:** slide right + fade, 0.2s ease-in
- **Tool switch:** cross-fade, 0.15s
- **Toast appear/dismiss:** fade, 0.2s

---

## File Structure

```
app/Sources/ZigShot/
├── ZigShotApp.swift              // @main App with MenuBarExtra + WindowGroup
├── Models/
│   ├── CaptureManager.swift      // ScreenCaptureKit (kept, minor cleanup)
│   ├── AnnotationModel.swift     // @Observable, annotation state + undo/redo
│   ├── EditorState.swift         // @Observable, tool selection, colors, width
│   ├── AppState.swift            // @Observable, global state (recent captures, prefs)
│   └── HotkeyManager.swift      // Global hotkey registration (kept)
├── Bridge/
│   ├── ZigShotBridge.swift       // C API wrapper (kept)
│   └── ZigShotImage+Export.swift // CGImage conversion, clipboard, save
├── Views/
│   ├── Editor/
│   │   ├── EditorWindow.swift    // WindowGroup scene
│   │   ├── EditorView.swift      // Main editor layout (canvas + toolbar)
│   │   ├── AnnotationCanvas.swift // NSViewRepresentable wrapping the drawing surface
│   │   ├── EditorToolbar.swift   // Bottom floating toolbar pill
│   │   ├── BackgroundPicker.swift // Background wrap options
│   │   └── ExportSheet.swift     // Format controls sheet
│   ├── Overlay/
│   │   ├── QuickOverlay.swift    // Floating post-capture pill
│   │   ├── SelectionOverlay.swift // Area selection (kept, SwiftUI wrapper)
│   │   └── ToastView.swift       // "Copied" confirmation toast
│   ├── MenuBar/
│   │   └── MenuBarView.swift     // MenuBarExtra content
│   └── Preferences/
│       └── PreferencesView.swift // Settings scene
├── Tools/
│   ├── AnnotationToolHandler.swift  // Protocol (kept)
│   ├── ArrowTool.swift
│   ├── RectangleTool.swift
│   ├── TextTool.swift
│   ├── BlurTool.swift
│   ├── HighlightTool.swift
│   ├── LineTool.swift
│   ├── RulerTool.swift
│   ├── NumberingTool.swift
│   ├── OCRTool.swift             // NEW: Vision framework text extraction
│   └── ColorPickerTool.swift     // NEW: Eyedropper with magnified loupe
└── Utilities/
    ├── TextEditingController.swift // NSTextView inline editing (kept)
    └── KeyboardShortcuts.swift    // Shortcut constants
```

**Principle: one type per file.** Each SwiftUI view, each `@Observable` model, each tool handler gets its own file. Small files are easier to reason about and produce better AI-assisted edits.

---

## SwiftUI Patterns

### App Entry Point
```swift
@main
struct ZigShotApp: App {
    @State private var appState = AppState()

    var body: some Scene {
        MenuBarExtra("ZigShot", systemImage: "camera.viewfinder") {
            MenuBarView()
        }
        .menuBarExtraStyle(.menu)

        WindowGroup("Editor", id: "editor") {
            EditorView()
                .environment(appState)
        }
        .windowStyle(.plain)
        .defaultSize(width: 1200, height: 800)

        Settings {
            PreferencesView()
                .environment(appState)
        }
    }
}
```

### Observable Models
```swift
@Observable @MainActor
final class EditorState {
    var selectedTool: AnnotationTool = .arrow
    var selectedColor: AnnotationColor = .red
    var strokeWidth: CGFloat = 2
    var showBackgroundPicker = false
    // ...
}
```

### NSViewRepresentable Canvas
```swift
struct AnnotationCanvas: NSViewRepresentable {
    let image: ZigShotImage
    @Bindable var model: AnnotationModel
    @Bindable var editorState: EditorState

    func makeNSView(context: Context) -> AnnotationCanvasView { ... }
    func updateNSView(_ nsView: AnnotationCanvasView, context: Context) { ... }
}
```

---

## Keyboard Shortcuts

| Action | Shortcut |
|--------|----------|
| Capture fullscreen | Cmd+Shift+3 |
| Capture area | Cmd+Shift+4 |
| Capture window | Cmd+Shift+5 |
| OCR extract | Cmd+Shift+O |
| Copy & close | Enter or Cmd+C |
| Save | Cmd+S |
| Undo | Cmd+Z |
| Redo | Cmd+Shift+Z |
| Delete annotation | Delete/Backspace |
| Toggle background | Cmd+B |
| Tool: Arrow | A |
| Tool: Rectangle | R |
| Tool: Blur | B |
| Tool: Highlight | H |
| Tool: Text | T |
| Tool: Line | L |
| Tool: Ruler | U |
| Tool: Number | N |
| Tool: OCR | O |
| Tool: Eyedropper | I |
| Colors 1-5 | 1/2/3/4/5 |
| Stroke width +/- | ] / [ |

---

## What's NOT in v1

- Scrolling capture
- Self-timer
- Screen recording (MP4/GIF)
- Cloud upload / shareable links
- Capture history panel
- Pin to desktop
- Custom hotkey remapping
- Dark theme (deferred — light first, dark follows naturally)
- Annotation templates/presets

---

## Migration Strategy

This is a **rewrite of the UI layer**, not a refactor. The approach:

1. Create new SwiftUI files alongside existing AppKit files
2. Build the SwiftUI app shell first (MenuBarExtra, window management)
3. Port the annotation canvas via NSViewRepresentable (reuse existing NSView logic)
4. Build new SwiftUI views (toolbar, overlay, export, preferences)
5. Delete old AppKit files once SwiftUI equivalents are verified
6. Add new features (OCR, eyedropper, backgrounds) on the SwiftUI foundation

The Zig bridge (`ZigShotBridge.swift`), capture pipeline (`CaptureManager.swift`), and hotkey manager are kept with minimal changes.

---

## Success Criteria

1. **Capture → Copy in < 500ms** — from hotkey press to clipboard
2. **Editor opens in < 200ms** — window appears with screenshot rendered
3. **Annotation feels instant** — no visible lag on draw, undo, or tool switch
4. **Total Swift LOC < 2500** — declarative SwiftUI should be more concise than the current ~4000 LOC AppKit
5. **Zero Desktop clutter** — clipboard-first, no files unless saved
6. **Looks like it belongs next to Things** — monochrome chrome, the screenshot is the star
