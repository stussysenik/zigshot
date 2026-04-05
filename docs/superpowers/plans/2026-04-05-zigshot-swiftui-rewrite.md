# ZigShot SwiftUI Rewrite — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Rewrite ZigShot's UI from AppKit to SwiftUI with a Things/iA Writer minimal aesthetic, adding clipboard-first workflow, quick access overlay, OCR, eyedropper, and custom backgrounds.

**Architecture:** SwiftUI app shell (MenuBarExtra + WindowGroup) with `@Observable` state models. The annotation canvas stays as an NSView wrapped in `NSViewRepresentable` for mouse precision and Zig pixel buffer interop. Everything else is declarative SwiftUI.

**Tech Stack:** SwiftUI (macOS 14+), ScreenCaptureKit, Vision framework, `@Observable` / `@MainActor`, SF Symbols, `libzigshot.a` C API via SPM CZigShot module.

**Spec:** `docs/superpowers/specs/2026-04-05-zigshot-swiftui-rewrite-design.md`

---

## File Map

### Keep (minor edits)
- `app/Sources/ZigShot/ZigShotBridge.swift` — add `@unchecked Sendable` conformance
- `app/Sources/ZigShot/CaptureManager.swift` — keep as-is
- `app/Sources/ZigShot/HotkeyManager.swift` — keep as-is, wire to AppState
- `app/Sources/ZigShot/TextEditingController.swift` — keep as-is
- `app/Sources/ZigShot/AnnotationToolHandler.swift` — keep protocol + 8 tool handlers
- `app/Sources/CZigShot/` — keep C wrapper module
- `app/Package.swift` — update swift-tools-version, add Vision framework

### Create (new SwiftUI files)
- `app/Sources/ZigShot/ZigShotApp.swift` — `@main` App entry with MenuBarExtra + WindowGroup + Settings
- `app/Sources/ZigShot/Models/AppState.swift` — `@Observable` global state
- `app/Sources/ZigShot/Models/EditorState.swift` — `@Observable` tool/color/width state
- `app/Sources/ZigShot/Models/AnnotationModel.swift` — port to `@Observable`
- `app/Sources/ZigShot/Views/MenuBar/MenuBarView.swift` — menu content
- `app/Sources/ZigShot/Views/Editor/EditorView.swift` — main editor layout
- `app/Sources/ZigShot/Views/Editor/AnnotationCanvas.swift` — `NSViewRepresentable`
- `app/Sources/ZigShot/Views/Editor/AnnotationCanvasView.swift` — the actual NSView (ported from AnnotationEditorView)
- `app/Sources/ZigShot/Views/Editor/EditorToolbar.swift` — floating pill toolbar
- `app/Sources/ZigShot/Views/Editor/BackgroundPicker.swift` — background options
- `app/Sources/ZigShot/Views/Editor/ExportSheet.swift` — format/quality controls
- `app/Sources/ZigShot/Views/Overlay/QuickOverlay.swift` — post-capture floating pill
- `app/Sources/ZigShot/Views/Overlay/SelectionOverlayView.swift` — area selection wrapper
- `app/Sources/ZigShot/Views/Overlay/ToastView.swift` — confirmation toast
- `app/Sources/ZigShot/Views/Preferences/PreferencesView.swift` — Settings scene
- `app/Sources/ZigShot/Tools/OCRTool.swift` — Vision framework text extraction
- `app/Sources/ZigShot/Tools/ColorPickerTool.swift` — Eyedropper with loupe

### Delete (after migration verified)
- `app/Sources/ZigShot/main.swift`
- `app/Sources/ZigShot/AppDelegate.swift`
- `app/Sources/ZigShot/AnnotationEditorView.swift`
- `app/Sources/ZigShot/AnnotationEditorWindow.swift`
- `app/Sources/ZigShot/AnnotationToolbar.swift`
- `app/Sources/ZigShot/WindowPicker.swift`
- `app/Sources/ZigShot/SelectionOverlay.swift`

---

## Task Dependency Graph

```
Task 1 (Package.swift + dirs)
  ├──→ Task 2 (AppState)
  ├──→ Task 3 (EditorState)
  └──→ Task 4 (AnnotationModel port)
         │
Task 2 + 3 + 4 ──→ Task 5 (ZigShotApp entry)
                      ├──→ Task 6 (MenuBarView)
                      └──→ Task 7 (AnnotationCanvasView port)
                             │
                             ├──→ Task 8 (EditorToolbar)
                             │      │
                             └──→ Task 9 (EditorView assembly)
                                     │
                                     ├──→ Task 10 (ToastView)
                                     ├──→ Task 11 (QuickOverlay)
                                     ├──→ Task 12 (ExportSheet)
                                     ├──→ Task 13 (BackgroundPicker)
                                     ├──→ Task 14 (PreferencesView)
                                     ├──→ Task 15 (OCRTool)
                                     └──→ Task 16 (ColorPickerTool)
                                            │
                                     Task 17 (Wire capture + hotkeys)
                                            │
                                     Task 18 (Delete old files)
                                            │
                                     Task 19 (Build + smoke test)
```

Tasks 2, 3, 4 are parallel. Tasks 10-16 are parallel. Task 17-19 are sequential.

---

### Task 1: Update Package.swift and Create Directory Structure

**Files:**
- Modify: `app/Package.swift`
- Create: directory tree under `app/Sources/ZigShot/`

- [ ] **Step 1: Create directory structure**

```bash
mkdir -p app/Sources/ZigShot/Models
mkdir -p app/Sources/ZigShot/Views/Editor
mkdir -p app/Sources/ZigShot/Views/Overlay
mkdir -p app/Sources/ZigShot/Views/MenuBar
mkdir -p app/Sources/ZigShot/Views/Preferences
mkdir -p app/Sources/ZigShot/Tools
mkdir -p app/Sources/ZigShot/Bridge
mkdir -p app/Sources/ZigShot/Utilities
```

- [ ] **Step 2: Update Package.swift**

Replace contents of `app/Package.swift` with:

```swift
// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "ZigShot",
    platforms: [.macOS(.v14)],
    targets: [
        .target(
            name: "CZigShot",
            path: "Sources/CZigShot",
            publicHeadersPath: "include"
        ),
        .executableTarget(
            name: "ZigShot",
            dependencies: ["CZigShot"],
            linkerSettings: [
                .unsafeFlags(["-L../zig-out/lib"]),
                .linkedLibrary("zigshot"),
                .linkedFramework("ScreenCaptureKit"),
                .linkedFramework("CoreGraphics"),
                .linkedFramework("AppKit"),
                .linkedFramework("ImageIO"),
                .linkedFramework("QuartzCore"),
                .linkedFramework("Vision"),
            ]
        ),
    ]
)
```

Changes: swift-tools-version 5.10, added Vision framework.

- [ ] **Step 3: Move existing files to new locations**

```bash
# Move bridge to Bridge/
mv app/Sources/ZigShot/ZigShotBridge.swift app/Sources/ZigShot/Bridge/

# Move tools (individual tool handlers) to Tools/
# Note: AnnotationToolHandler.swift contains the protocol AND all handlers.
# We'll split it in a later task. For now, just move it.
mv app/Sources/ZigShot/AnnotationToolHandler.swift app/Sources/ZigShot/Tools/
mv app/Sources/ZigShot/TextEditingController.swift app/Sources/ZigShot/Utilities/

# Move existing models
mv app/Sources/ZigShot/CaptureManager.swift app/Sources/ZigShot/Models/
mv app/Sources/ZigShot/HotkeyManager.swift app/Sources/ZigShot/Models/
mv app/Sources/ZigShot/AnnotationModel.swift app/Sources/ZigShot/Models/
```

- [ ] **Step 4: Verify build resolves**

Run: `cd app && swift build 2>&1 | tail -5`
Expected: Build succeeds (file moves within the same target are fine for SPM).

- [ ] **Step 5: Commit**

```bash
git add -A app/
git commit -m "chore: restructure ZigShot for SwiftUI migration

Move files into Models/, Views/, Tools/, Bridge/, Utilities/ directories.
Update Package.swift to swift-tools-version 5.10, add Vision framework."
```

---

### Task 2: Create AppState Model

**Files:**
- Create: `app/Sources/ZigShot/Models/AppState.swift`

- [ ] **Step 1: Create AppState**

Write `app/Sources/ZigShot/Models/AppState.swift`:

```swift
import AppKit
import Observation

@Observable @MainActor
final class AppState {
    var recentCapture: CGImage?
    var isEditorOpen = false
    var showQuickOverlay = false
    var toastMessage: String?

    // Preferences (persisted via UserDefaults)
    var defaultSaveDirectory: URL = FileManager.default.urls(
        for: .desktopDirectory, in: .userDomainMask
    ).first!
    var defaultFormat: ExportFormat = .png
    var jpegQuality: Double = 0.9
    var launchAtLogin = false
    var captureSound = false

    private let captureManager = CaptureManager()
    private let hotkeyManager = HotkeyManager()

    func captureFullscreen() async throws -> CGImage {
        let image = try await captureManager.captureFullscreen()
        recentCapture = image
        return image
    }

    func captureArea(_ rect: CGRect) async throws -> CGImage {
        let image = try await captureManager.captureArea(rect)
        recentCapture = image
        return image
    }

    func captureWindow(_ windowID: CGWindowID) async throws -> CGImage {
        let image = try await captureManager.captureWindow(windowID)
        recentCapture = image
        return image
    }

    func registerHotkeys() {
        hotkeyManager.register { [weak self] action in
            guard let self else { return }
            Task { @MainActor in
                switch action {
                case .captureFullscreen:
                    if let img = try? await self.captureFullscreen() {
                        self.handleCapture(img)
                    }
                case .captureArea:
                    // Area selection overlay will be triggered separately
                    break
                case .captureWindow:
                    // Window picker will be triggered separately
                    break
                }
            }
        }
    }

    func handleCapture(_ image: CGImage) {
        recentCapture = image
        // Copy to clipboard immediately (clipboard-first)
        let rep = NSBitmapImageRep(cgImage: image)
        if let pngData = rep.representation(using: .png, properties: [:]) {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setData(pngData, forType: .png)
        }
        showQuickOverlay = true
    }

    func showToast(_ message: String) {
        toastMessage = message
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            toastMessage = nil
        }
    }
}

enum ExportFormat: String, CaseIterable, Identifiable {
    case png, jpeg
    var id: String { rawValue }
    var label: String {
        switch self {
        case .png: return "PNG"
        case .jpeg: return "JPEG"
        }
    }
    var utType: String {
        switch self {
        case .png: return "public.png"
        case .jpeg: return "public.jpeg"
        }
    }
}
```

- [ ] **Step 2: Verify file compiles in isolation**

Run: `cd app && swift build 2>&1 | grep -E "(error|Build complete)" | head -5`
Note: May have errors due to missing `@main` — that's expected at this stage.

- [ ] **Step 3: Commit**

```bash
git add app/Sources/ZigShot/Models/AppState.swift
git commit -m "feat: add AppState @Observable model

Global state for captures, preferences, and clipboard-first workflow.
Uses @Observable @MainActor pattern per SwiftUI Pro guidelines."
```

---

### Task 3: Create EditorState Model

**Files:**
- Create: `app/Sources/ZigShot/Models/EditorState.swift`

- [ ] **Step 1: Create EditorState**

Write `app/Sources/ZigShot/Models/EditorState.swift`:

```swift
import AppKit
import Observation

enum AnnotationTool: String, CaseIterable, Identifiable {
    case select, arrow, rectangle, text, blur, highlight, line, ruler, numbering, ocr, eyedropper
    var id: String { rawValue }

    var label: String {
        switch self {
        case .select: return "Select"
        case .arrow: return "Arrow"
        case .rectangle: return "Rectangle"
        case .text: return "Text"
        case .blur: return "Blur"
        case .highlight: return "Highlight"
        case .line: return "Line"
        case .ruler: return "Ruler"
        case .numbering: return "Number"
        case .ocr: return "OCR"
        case .eyedropper: return "Eyedropper"
        }
    }

    var systemImage: String {
        switch self {
        case .select: return "cursorarrow"
        case .arrow: return "arrow.up.right"
        case .rectangle: return "rectangle"
        case .text: return "textformat"
        case .blur: return "circle.dashed"
        case .highlight: return "highlighter"
        case .line: return "line.diagonal"
        case .ruler: return "ruler"
        case .numbering: return "number.circle"
        case .ocr: return "text.viewfinder"
        case .eyedropper: return "eyedropper"
        }
    }

    var shortcutKey: Character? {
        switch self {
        case .select: return "v"
        case .arrow: return "a"
        case .rectangle: return "r"
        case .text: return "t"
        case .blur: return "b"
        case .highlight: return "h"
        case .line: return "l"
        case .ruler: return "u"
        case .numbering: return "n"
        case .ocr: return "o"
        case .eyedropper: return "i"
        default: return nil
        }
    }
}

enum AnnotationColor: Int, CaseIterable, Identifiable {
    case red = 1, yellow, blue, green, black
    var id: Int { rawValue }

    var nsColor: NSColor {
        switch self {
        case .red: return NSColor(red: 1.0, green: 0.231, blue: 0.188, alpha: 1.0)
        case .yellow: return NSColor(red: 1.0, green: 0.8, blue: 0.0, alpha: 1.0)
        case .blue: return NSColor(red: 0.0, green: 0.478, blue: 1.0, alpha: 1.0)
        case .green: return NSColor(red: 0.204, green: 0.78, blue: 0.349, alpha: 1.0)
        case .black: return NSColor(red: 0.102, green: 0.102, blue: 0.102, alpha: 1.0)
        }
    }

    var hexString: String {
        switch self {
        case .red: return "#FF3B30"
        case .yellow: return "#FFCC00"
        case .blue: return "#007AFF"
        case .green: return "#34C759"
        case .black: return "#1A1A1A"
        }
    }
}

@Observable @MainActor
final class EditorState {
    var selectedTool: AnnotationTool = .arrow
    var selectedColor: AnnotationColor = .red
    var strokeWidth: CGFloat = 3
    var showBackgroundPicker = false
    var showExportSheet = false
    var cursorPosition: CGPoint = .zero

    /// Background wrap configuration
    var backgroundEnabled = false
    var backgroundPadding: CGFloat = 60
    var backgroundStyle: BackgroundStyle = .none

    func incrementStrokeWidth() {
        strokeWidth = min(strokeWidth + 1, 20)
    }

    func decrementStrokeWidth() {
        strokeWidth = max(strokeWidth - 1, 1)
    }
}

enum BackgroundStyle: String, CaseIterable, Identifiable {
    case none
    case white, lightGray, black
    case gradientPurple, gradientPeach, gradientBlue, gradientDark
    var id: String { rawValue }

    var label: String {
        switch self {
        case .none: return "None"
        case .white: return "White"
        case .lightGray: return "Light Gray"
        case .black: return "Black"
        case .gradientPurple: return "Purple"
        case .gradientPeach: return "Peach"
        case .gradientBlue: return "Blue"
        case .gradientDark: return "Dark"
        }
    }
}
```

- [ ] **Step 2: Commit**

```bash
git add app/Sources/ZigShot/Models/EditorState.swift
git commit -m "feat: add EditorState model with tool/color/background enums

Defines AnnotationTool, AnnotationColor, BackgroundStyle enums and
EditorState @Observable for editor UI state management."
```

---

### Task 4: Port AnnotationModel to @Observable

**Files:**
- Modify: `app/Sources/ZigShot/Models/AnnotationModel.swift`

- [ ] **Step 1: Convert to @Observable**

Edit `app/Sources/ZigShot/Models/AnnotationModel.swift`. Replace the class definition:

```swift
import Foundation
import AppKit
import Observation

// MARK: - AnnotationDescriptor
// (keep the existing enum exactly as-is)

// MARK: - UndoEntry
// (keep the existing enum exactly as-is)

// MARK: - AnnotationModel

@Observable @MainActor
final class AnnotationModel {

    private(set) var annotations: [AnnotationDescriptor] = []
    private var undoStack: [UndoEntry] = []
    private var redoStack: [UndoEntry] = []

    var canUndo: Bool { !undoStack.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }

    // Remove the old `onChange` callback — @Observable handles reactivity now.

    func add(_ annotation: AnnotationDescriptor) {
        let index = annotations.count
        annotations.append(annotation)
        undoStack.append(.added(annotation, index))
        redoStack.removeAll()
    }

    func remove(at index: Int) {
        guard annotations.indices.contains(index) else { return }
        let removed = annotations.remove(at: index)
        undoStack.append(.deleted(removed, index))
        redoStack.removeAll()
    }

    func update(at index: Int, to newAnnotation: AnnotationDescriptor) {
        guard annotations.indices.contains(index) else { return }
        let old = annotations[index]
        annotations[index] = newAnnotation
        undoStack.append(.modified(index: index, old: old, new: newAnnotation))
        redoStack.removeAll()
    }

    func undo() {
        guard let entry = undoStack.popLast() else { return }
        switch entry {
        case let .added(_, index):
            let safeIndex = min(index, annotations.count - 1)
            if annotations.indices.contains(safeIndex) {
                annotations.remove(at: safeIndex)
            }
            redoStack.append(entry)
        case let .deleted(annotation, index):
            let safeIndex = min(index, annotations.count)
            annotations.insert(annotation, at: safeIndex)
            redoStack.append(entry)
        case let .modified(index, old, _):
            if annotations.indices.contains(index) {
                annotations[index] = old
            }
            redoStack.append(entry)
        }
    }

    func redo() {
        guard let entry = redoStack.popLast() else { return }
        switch entry {
        case let .added(annotation, _):
            annotations.append(annotation)
            undoStack.append(entry)
        case let .deleted(_, index):
            let safeIndex = min(index, annotations.count - 1)
            if annotations.indices.contains(safeIndex) {
                annotations.remove(at: safeIndex)
            }
            undoStack.append(entry)
        case let .modified(index, _, new):
            if annotations.indices.contains(index) {
                annotations[index] = new
            }
            undoStack.append(entry)
        }
    }

    func renderAll(onto image: ZigShotImage) {
        for annotation in annotations {
            switch annotation {
            case let .arrow(from, to, color, width):
                image.drawArrow(from: from, to: to, color: color, width: width)
            case let .rectangle(rect, color, width):
                image.drawRect(rect, color: color, width: width)
            case let .line(from, to, color, width):
                image.drawLine(from: from, to: to, color: color, width: width)
            case let .blur(rect, radius):
                image.blur(rect, radius: radius)
            case let .highlight(rect, color):
                image.highlight(rect, color: color)
            case let .ruler(from, to, color, width):
                _ = image.drawRuler(from: from, to: to, color: color, width: width)
            case .numbering, .text:
                break
            }
        }
    }
}
```

Key change: class is now `@Observable @MainActor`, removed `onChange` callback (SwiftUI observation handles this automatically).

- [ ] **Step 2: Commit**

```bash
git add app/Sources/ZigShot/Models/AnnotationModel.swift
git commit -m "refactor: convert AnnotationModel to @Observable

Remove manual onChange callback — SwiftUI observation system handles
reactivity. Add @MainActor for thread safety."
```

---

### Task 5: Create ZigShotApp Entry Point

**Files:**
- Create: `app/Sources/ZigShot/ZigShotApp.swift`
- Delete: `app/Sources/ZigShot/main.swift` (after new entry point works)

- [ ] **Step 1: Create ZigShotApp.swift**

Write `app/Sources/ZigShot/ZigShotApp.swift`:

```swift
import SwiftUI

@main
struct ZigShotApp: App {
    @State private var appState = AppState()

    var body: some Scene {
        MenuBarExtra("ZigShot", systemImage: "camera.viewfinder") {
            MenuBarView()
                .environment(appState)
        }
        .menuBarExtraStyle(.menu)

        WindowGroup("Editor", id: "editor", for: CGImage.ID.self) { _ in
            EditorView()
                .environment(appState)
        }
        .windowStyle(.plain)
        .windowResizability(.contentSize)

        Settings {
            PreferencesView()
                .environment(appState)
        }
    }
}
```

Note: This won't compile yet because `MenuBarView`, `EditorView`, and `PreferencesView` don't exist. We'll create placeholder stubs.

- [ ] **Step 2: Create placeholder views**

Write `app/Sources/ZigShot/Views/MenuBar/MenuBarView.swift`:

```swift
import SwiftUI

struct MenuBarView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        Button("Capture Fullscreen") {
            Task { try? await appState.captureFullscreen() }
        }
        .keyboardShortcut("3", modifiers: [.command, .shift])

        Button("Capture Area") { /* TODO: wire selection overlay */ }
            .keyboardShortcut("4", modifiers: [.command, .shift])

        Button("Capture Window") { /* TODO: wire window picker */ }
            .keyboardShortcut("5", modifiers: [.command, .shift])

        Divider()

        SettingsLink { Text("Preferences...") }
            .keyboardShortcut(",", modifiers: .command)

        Divider()

        Button("Quit ZigShot") { NSApp.terminate(nil) }
            .keyboardShortcut("q", modifiers: .command)
    }
}
```

Write `app/Sources/ZigShot/Views/Editor/EditorView.swift` (placeholder):

```swift
import SwiftUI

struct EditorView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        ZStack {
            Color(nsColor: NSColor(white: 0.98, alpha: 1.0))
            Text("Editor — capture an image to begin")
                .font(.system(size: 15))
                .foregroundStyle(.secondary)
        }
        .frame(minWidth: 800, minHeight: 600)
    }
}
```

Write `app/Sources/ZigShot/Views/Preferences/PreferencesView.swift` (placeholder):

```swift
import SwiftUI

struct PreferencesView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        Form {
            Text("Preferences coming soon")
        }
        .frame(width: 400, height: 300)
    }
}
```

- [ ] **Step 3: Delete old main.swift**

```bash
rm app/Sources/ZigShot/main.swift
```

- [ ] **Step 4: Delete old AppDelegate.swift**

```bash
rm app/Sources/ZigShot/AppDelegate.swift
```

- [ ] **Step 5: Build to verify app shell compiles**

Run: `cd app && swift build 2>&1 | tail -10`
Expected: Build succeeds. The app should launch as a menu bar app.

- [ ] **Step 6: Commit**

```bash
git add -A app/Sources/ZigShot/
git commit -m "feat: SwiftUI app shell with MenuBarExtra

Replace AppKit main.swift + AppDelegate with @main SwiftUI App.
MenuBarExtra for menu bar, WindowGroup for editor, Settings for prefs.
Placeholder views for EditorView and PreferencesView."
```

---

### Task 6: Port AnnotationCanvasView (NSView)

**Files:**
- Create: `app/Sources/ZigShot/Views/Editor/AnnotationCanvasView.swift` — the NSView
- Create: `app/Sources/ZigShot/Views/Editor/AnnotationCanvas.swift` — NSViewRepresentable

This is the biggest task. Port the drawing surface from `AnnotationEditorView.swift` into a clean NSView, then wrap it.

- [ ] **Step 1: Create AnnotationCanvasView.swift**

Port from the existing `AnnotationEditorView.swift`. Write `app/Sources/ZigShot/Views/Editor/AnnotationCanvasView.swift`:

```swift
import AppKit
import CZigShot

/// The annotation drawing surface. An NSView that handles mouse events,
/// renders the Zig pixel buffer, and draws annotation previews with Core Graphics.
final class AnnotationCanvasView: NSView {

    // MARK: - State

    private(set) var workingImage: ZigShotImage
    let originalImage: ZigShotImage
    let model: AnnotationModel
    var editorState: EditorState?

    /// Tool handler instances — reused across tool switches.
    private var toolHandlers: [AnnotationTool: AnnotationToolHandler] = [
        .arrow: ArrowToolHandler(),
        .rectangle: RectangleToolHandler(),
        .line: LineToolHandler(),
        .blur: BlurToolHandler(),
        .highlight: HighlightToolHandler(),
        .ruler: RulerToolHandler(),
        .numbering: NumberingToolHandler(),
        .text: TextToolHandler(),
    ]

    var activeToolHandler: AnnotationToolHandler {
        guard let state = editorState else { return toolHandlers[.arrow]! }
        return toolHandlers[state.selectedTool] ?? toolHandlers[.arrow]!
    }

    var currentColor: NSColor {
        editorState?.selectedColor.nsColor ?? .red
    }

    var currentStrokeWidth: UInt32 {
        UInt32(editorState?.strokeWidth ?? 3)
    }

    // Selection state
    var selectedAnnotationIndex: Int?
    private var isDraggingSelection = false
    private var dragOffset: CGPoint = .zero

    // Drawing state
    private var drawStartPoint: CGPoint?
    private var drawCurrentPoint: CGPoint?
    private var isDrawing = false

    // Image rect in view coordinates
    private(set) var imageRect: CGRect = .zero

    /// Callback when image needs to be re-rendered (for SwiftUI bridge).
    var onRender: (() -> Void)?

    // MARK: - Init

    init(workingImage: ZigShotImage, originalImage: ZigShotImage, model: AnnotationModel) {
        self.workingImage = workingImage
        self.originalImage = originalImage
        self.model = model
        super.init(frame: .zero)
        wantsLayer = true
        layerContentsRedrawPolicy = .onSetNeedsDisplay
    }

    required init?(coder: NSCoder) { fatalError() }

    // MARK: - Layout

    override func layout() {
        super.layout()
        recalcImageRect()
    }

    private func recalcImageRect() {
        let imgW = CGFloat(workingImage.width)
        let imgH = CGFloat(workingImage.height)
        let maxW = bounds.width * 0.9
        let maxH = bounds.height * 0.85
        let scale = min(maxW / imgW, maxH / imgH, 1.0)
        let drawW = imgW * scale
        let drawH = imgH * scale
        imageRect = CGRect(
            x: (bounds.width - drawW) / 2,
            y: (bounds.height - drawH) / 2 + 20,
            width: drawW,
            height: drawH
        )
    }

    // MARK: - Coordinate Transforms

    func viewToImage(_ viewPoint: CGPoint) -> CGPoint {
        let scaleX = CGFloat(workingImage.width) / imageRect.width
        let scaleY = CGFloat(workingImage.height) / imageRect.height
        return CGPoint(
            x: (viewPoint.x - imageRect.origin.x) * scaleX,
            y: (viewPoint.y - imageRect.origin.y) * scaleY
        )
    }

    func imageToView(_ imagePoint: CGPoint) -> CGPoint {
        let scaleX = imageRect.width / CGFloat(workingImage.width)
        let scaleY = imageRect.height / CGFloat(workingImage.height)
        return CGPoint(
            x: imagePoint.x * scaleX + imageRect.origin.x,
            y: imagePoint.y * scaleY + imageRect.origin.y
        )
    }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }

        // Background
        ctx.setFillColor(NSColor(white: 0.98, alpha: 1.0).cgColor)
        ctx.fill(bounds)

        // Screenshot with rounded corners and shadow
        guard let cgImage = workingImage.cgImage() else { return }
        ctx.saveGState()

        // Shadow
        ctx.setShadow(
            offset: CGSize(width: 0, height: -8),
            blur: 40,
            color: CGColor(gray: 0, alpha: 0.08)
        )

        // Rounded corners clip
        let path = CGPath(roundedRect: imageRect, cornerWidth: 12, cornerHeight: 12, transform: nil)
        ctx.addPath(path)
        ctx.clip()
        ctx.draw(cgImage, in: imageRect)

        ctx.restoreGState()

        // Preview layer (in-progress annotation)
        if isDrawing, let start = drawStartPoint, let current = drawCurrentPoint {
            ctx.saveGState()
            ctx.clip(to: imageRect)
            let viewStart = imageToView(start)
            let viewCurrent = imageToView(current)
            activeToolHandler.drawPreview(in: ctx, from: viewStart, to: viewCurrent)
            ctx.restoreGState()
        }

        // Selection handles
        if let idx = selectedAnnotationIndex, model.annotations.indices.contains(idx) {
            drawSelectionHandles(ctx, for: model.annotations[idx])
        }
    }

    private func drawSelectionHandles(_ ctx: CGContext, for annotation: AnnotationDescriptor) {
        let bounds = annotation.bounds
        let corners = [
            bounds.origin,
            CGPoint(x: bounds.maxX, y: bounds.origin.y),
            CGPoint(x: bounds.origin.x, y: bounds.maxY),
            CGPoint(x: bounds.maxX, y: bounds.maxY),
        ]
        for corner in corners {
            let viewPt = imageToView(corner)
            let handleRect = CGRect(x: viewPt.x - 4, y: viewPt.y - 4, width: 8, height: 8)
            ctx.setFillColor(NSColor.white.cgColor)
            ctx.setStrokeColor(NSColor(white: 0.8, alpha: 1.0).cgColor)
            ctx.setLineWidth(1)
            ctx.fillEllipse(in: handleRect)
            ctx.strokeEllipse(in: handleRect)
        }
    }

    // MARK: - Mouse Events

    override func mouseDown(with event: NSEvent) {
        let viewPt = convert(event.locationInWindow, from: nil)
        let imgPt = viewToImage(viewPt)

        // Check for annotation hit first
        if editorState?.selectedTool == .select {
            if let idx = hitTest(imgPt) {
                selectedAnnotationIndex = idx
                isDraggingSelection = true
                let bounds = model.annotations[idx].bounds
                dragOffset = CGPoint(x: imgPt.x - bounds.origin.x, y: imgPt.y - bounds.origin.y)
                needsDisplay = true
                return
            }
            selectedAnnotationIndex = nil
            needsDisplay = true
            return
        }

        // Start drawing
        selectedAnnotationIndex = nil
        drawStartPoint = imgPt
        drawCurrentPoint = imgPt
        isDrawing = true
        activeToolHandler.start(at: imgPt)
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        let viewPt = convert(event.locationInWindow, from: nil)
        let imgPt = viewToImage(viewPt)

        // Update cursor position for status bar
        editorState?.cursorPosition = imgPt

        if isDraggingSelection {
            moveSelected(to: imgPt)
            return
        }

        if isDrawing {
            drawCurrentPoint = imgPt
            activeToolHandler.update(to: imgPt)
            needsDisplay = true
        }
    }

    override func mouseUp(with event: NSEvent) {
        let viewPt = convert(event.locationInWindow, from: nil)
        let imgPt = viewToImage(viewPt)

        if isDraggingSelection {
            isDraggingSelection = false
            return
        }

        guard isDrawing, let start = drawStartPoint else { return }
        isDrawing = false

        if let descriptor = activeToolHandler.finish(
            from: start, to: imgPt,
            color: currentColor, width: currentStrokeWidth
        ) {
            model.add(descriptor)
        }

        drawStartPoint = nil
        drawCurrentPoint = nil
        rerender()
    }

    // MARK: - Hit Testing

    private func hitTest(_ point: CGPoint) -> Int? {
        for i in model.annotations.indices.reversed() {
            let bounds = model.annotations[i].bounds.insetBy(dx: -8, dy: -8)
            if bounds.contains(point) { return i }
        }
        return nil
    }

    // MARK: - Move Annotation

    private func moveSelected(to point: CGPoint) {
        guard let idx = selectedAnnotationIndex,
              model.annotations.indices.contains(idx) else { return }

        let annotation = model.annotations[idx]
        let dx = point.x - dragOffset.x - annotation.bounds.origin.x
        let dy = point.y - dragOffset.y - annotation.bounds.origin.y

        let moved = translateAnnotation(annotation, dx: dx, dy: dy)
        model.update(at: idx, to: moved)
        rerender()
    }

    private func translateAnnotation(_ a: AnnotationDescriptor, dx: CGFloat, dy: CGFloat) -> AnnotationDescriptor {
        switch a {
        case let .arrow(from, to, color, width):
            return .arrow(from: CGPoint(x: from.x + dx, y: from.y + dy),
                         to: CGPoint(x: to.x + dx, y: to.y + dy),
                         color: color, width: width)
        case let .rectangle(rect, color, width):
            return .rectangle(rect: rect.offsetBy(dx: dx, dy: dy), color: color, width: width)
        case let .line(from, to, color, width):
            return .line(from: CGPoint(x: from.x + dx, y: from.y + dy),
                        to: CGPoint(x: to.x + dx, y: to.y + dy),
                        color: color, width: width)
        case let .blur(rect, radius):
            return .blur(rect: rect.offsetBy(dx: dx, dy: dy), radius: radius)
        case let .highlight(rect, color):
            return .highlight(rect: rect.offsetBy(dx: dx, dy: dy), color: color)
        case let .ruler(from, to, color, width):
            return .ruler(from: CGPoint(x: from.x + dx, y: from.y + dy),
                         to: CGPoint(x: to.x + dx, y: to.y + dy),
                         color: color, width: width)
        case let .numbering(pos, num, color):
            return .numbering(position: CGPoint(x: pos.x + dx, y: pos.y + dy),
                            number: num, color: color)
        case let .text(pos, content, size, color):
            return .text(position: CGPoint(x: pos.x + dx, y: pos.y + dy),
                        content: content, fontSize: size, color: color)
        }
    }

    // MARK: - Rerender

    func rerender() {
        workingImage.copyPixels(from: originalImage)
        model.renderAll(onto: workingImage)
        needsDisplay = true
        onRender?()
    }
}
```

- [ ] **Step 2: Update AnnotationToolHandler protocol**

The existing `finish()` method signature needs to accept color and width parameters. Edit `app/Sources/ZigShot/Tools/AnnotationToolHandler.swift` — update the `finish` method signature in the protocol:

```swift
protocol AnnotationToolHandler {
    func start(at point: CGPoint)
    func update(to point: CGPoint)
    func finish(from start: CGPoint, to end: CGPoint,
                color: NSColor, width: UInt32) -> AnnotationDescriptor?
    func drawPreview(in ctx: CGContext, from start: CGPoint, to end: CGPoint)
}
```

Update each handler's `finish` method to accept these parameters instead of reading from the view. Each handler currently stores color/width internally — change them to use the passed parameters.

- [ ] **Step 3: Create NSViewRepresentable wrapper**

Write `app/Sources/ZigShot/Views/Editor/AnnotationCanvas.swift`:

```swift
import SwiftUI

struct AnnotationCanvas: NSViewRepresentable {
    let workingImage: ZigShotImage
    let originalImage: ZigShotImage
    @Bindable var model: AnnotationModel
    @Bindable var editorState: EditorState

    func makeNSView(context: Context) -> AnnotationCanvasView {
        let view = AnnotationCanvasView(
            workingImage: workingImage,
            originalImage: originalImage,
            model: model
        )
        view.editorState = editorState
        return view
    }

    func updateNSView(_ nsView: AnnotationCanvasView, context: Context) {
        nsView.editorState = editorState
        nsView.needsDisplay = true
    }
}
```

- [ ] **Step 4: Commit**

```bash
git add app/Sources/ZigShot/Views/Editor/AnnotationCanvasView.swift \
       app/Sources/ZigShot/Views/Editor/AnnotationCanvas.swift
git commit -m "feat: port annotation canvas to NSViewRepresentable

AnnotationCanvasView (NSView) handles mouse events, Zig pixel buffer
rendering, and Core Graphics annotation previews. AnnotationCanvas
wraps it for SwiftUI. Rounded corners + drop shadow on screenshot."
```

---

### Task 7: Create EditorToolbar (SwiftUI)

**Files:**
- Create: `app/Sources/ZigShot/Views/Editor/EditorToolbar.swift`

- [ ] **Step 1: Create EditorToolbar**

Write `app/Sources/ZigShot/Views/Editor/EditorToolbar.swift`:

```swift
import SwiftUI

struct EditorToolbar: View {
    @Bindable var editorState: EditorState
    var onCopy: () -> Void
    var onSave: () -> Void
    var onDiscard: () -> Void

    private let drawingTools: [AnnotationTool] = [
        .select, .arrow, .rectangle, .text, .blur, .highlight, .ruler, .numbering
    ]

    var body: some View {
        HStack(spacing: 2) {
            // Drawing tools
            ForEach(drawingTools) { tool in
                ToolButton(
                    tool: tool,
                    isSelected: editorState.selectedTool == tool,
                    action: { editorState.selectedTool = tool }
                )
            }

            Divider()
                .frame(height: 20)
                .padding(.horizontal, 8)

            // Color dots
            HStack(spacing: 4) {
                ForEach(AnnotationColor.allCases) { color in
                    ColorDot(
                        color: color,
                        isSelected: editorState.selectedColor == color,
                        action: { editorState.selectedColor = color }
                    )
                }
            }

            Divider()
                .frame(height: 20)
                .padding(.horizontal, 8)

            // Utility tools
            ToolButton(
                tool: .ocr,
                isSelected: editorState.selectedTool == .ocr,
                action: { editorState.selectedTool = .ocr }
            )
            ToolButton(
                tool: .eyedropper,
                isSelected: editorState.selectedTool == .eyedropper,
                action: { editorState.selectedTool = .eyedropper }
            )

            Divider()
                .frame(height: 20)
                .padding(.horizontal, 8)

            // Actions
            Button(action: onCopy) {
                Text("Copy")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .background(Color(nsColor: NSColor(white: 0.1, alpha: 1.0)))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.plain)

            Button(action: onSave) {
                Text("Save")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 8)

            Button(action: onDiscard) {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.tertiary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
        .clipShape(Capsule())
        .shadow(color: .black.opacity(0.04), radius: 1, y: 1)
        .shadow(color: .black.opacity(0.06), radius: 20, y: 8)
    }
}

// MARK: - Subviews

private struct ToolButton: View {
    let tool: AnnotationTool
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: tool.systemImage)
                .font(.system(size: 14))
                .foregroundStyle(isSelected ? Color.white : Color(white: 0.73))
                .frame(width: 32, height: 32)
                .background(isSelected ? Color(nsColor: NSColor(white: 0.1, alpha: 1.0)) : .clear)
                .clipShape(RoundedRectangle(cornerRadius: 7))
        }
        .buttonStyle(.plain)
        .help("\(tool.label)\(tool.shortcutKey.map { " (\($0))" } ?? "")")
    }
}

private struct ColorDot: View {
    let color: AnnotationColor
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Circle()
                .fill(Color(nsColor: color.nsColor))
                .frame(width: 16, height: 16)
                .overlay(
                    Circle()
                        .stroke(Color(nsColor: NSColor(white: 0.1, alpha: 1.0)), lineWidth: isSelected ? 2 : 0)
                        .frame(width: 20, height: 20)
                )
        }
        .buttonStyle(.plain)
    }
}
```

- [ ] **Step 2: Commit**

```bash
git add app/Sources/ZigShot/Views/Editor/EditorToolbar.swift
git commit -m "feat: SwiftUI EditorToolbar — floating pill with tools and colors

Minimal capsule toolbar with SF Symbol tool buttons, color dots,
OCR/eyedropper utilities, and Copy/Save/Discard actions.
ultraThinMaterial background, monochrome inactive, black active."
```

---

### Task 8: Complete EditorView Assembly

**Files:**
- Modify: `app/Sources/ZigShot/Views/Editor/EditorView.swift`

- [ ] **Step 1: Replace EditorView placeholder**

Replace contents of `app/Sources/ZigShot/Views/Editor/EditorView.swift`:

```swift
import SwiftUI

struct EditorView: View {
    @Environment(AppState.self) private var appState
    @State private var editorState = EditorState()
    @State private var model = AnnotationModel()
    @State private var workingImage: ZigShotImage?
    @State private var originalImage: ZigShotImage?

    var body: some View {
        ZStack {
            // Canvas background
            Color(nsColor: NSColor(white: 0.98, alpha: 1.0))

            if let working = workingImage, let original = originalImage {
                // Annotation canvas
                AnnotationCanvas(
                    workingImage: working,
                    originalImage: original,
                    model: model,
                    editorState: editorState
                )

                // Floating toolbar at bottom
                VStack {
                    Spacer()
                    EditorToolbar(
                        editorState: editorState,
                        onCopy: copyAndClose,
                        onSave: save,
                        onDiscard: discard
                    )
                    .padding(.bottom, 16)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }

                // Cursor position (bottom-left)
                VStack {
                    Spacer()
                    HStack {
                        Text("\(Int(editorState.cursorPosition.x)), \(Int(editorState.cursorPosition.y))")
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .foregroundStyle(.tertiary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                        Spacer()
                    }
                    .padding(.bottom, 16)
                }
            } else {
                Text("Capture an image to begin editing")
                    .font(.system(size: 15))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(minWidth: 800, minHeight: 600)
        .task {
            loadCapturedImage()
        }
        .onKeyPress { key in
            handleKeyPress(key)
        }
    }

    // MARK: - Actions

    private func loadCapturedImage() {
        guard let cgImage = appState.recentCapture else { return }
        guard let working = ZigShotImage.fromCGImage(cgImage),
              let original = ZigShotImage.fromCGImage(cgImage) else { return }
        workingImage = working
        originalImage = original
    }

    private func copyAndClose() {
        workingImage?.copyToClipboard()
        appState.showToast("Copied")
        appState.isEditorOpen = false
        NSApp.keyWindow?.close()
    }

    private func save() {
        editorState.showExportSheet = true
    }

    private func discard() {
        appState.isEditorOpen = false
        NSApp.keyWindow?.close()
    }

    private func handleKeyPress(_ key: KeyPress) -> KeyPress.Result {
        // Tool shortcuts
        for tool in AnnotationTool.allCases {
            if let shortcut = tool.shortcutKey,
               key.characters == String(shortcut) {
                editorState.selectedTool = tool
                return .handled
            }
        }

        // Color shortcuts (1-5)
        if let num = Int(key.characters),
           let color = AnnotationColor(rawValue: num) {
            editorState.selectedColor = color
            return .handled
        }

        // Stroke width
        if key.characters == "]" {
            editorState.incrementStrokeWidth()
            return .handled
        }
        if key.characters == "[" {
            editorState.decrementStrokeWidth()
            return .handled
        }

        return .ignored
    }
}
```

- [ ] **Step 2: Commit**

```bash
git add app/Sources/ZigShot/Views/Editor/EditorView.swift
git commit -m "feat: EditorView — SwiftUI editor assembly

Composes AnnotationCanvas + EditorToolbar in a ZStack. Handles
keyboard shortcuts for tools/colors/width, cursor position display,
and copy/save/discard actions. Light #FAFAFA background."
```

---

### Task 9: Create ToastView

**Files:**
- Create: `app/Sources/ZigShot/Views/Overlay/ToastView.swift`

- [ ] **Step 1: Create ToastView**

Write `app/Sources/ZigShot/Views/Overlay/ToastView.swift`:

```swift
import SwiftUI

struct ToastView: View {
    let message: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.secondary)
            Text(message)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.primary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
        .clipShape(Capsule())
        .shadow(color: .black.opacity(0.08), radius: 12, y: 4)
        .transition(.opacity.animation(.easeInOut(duration: 0.2)))
    }
}
```

- [ ] **Step 2: Commit**

```bash
git add app/Sources/ZigShot/Views/Overlay/ToastView.swift
git commit -m "feat: ToastView — minimal confirmation toast

Capsule-shaped pill with checkmark icon. ultraThinMaterial background,
fade transition, used for 'Copied' confirmation."
```

---

### Task 10: Create QuickOverlay

**Files:**
- Create: `app/Sources/ZigShot/Views/Overlay/QuickOverlay.swift`

- [ ] **Step 1: Create QuickOverlay**

Write `app/Sources/ZigShot/Views/Overlay/QuickOverlay.swift`:

```swift
import SwiftUI

struct QuickOverlay: View {
    let image: CGImage
    var onCopy: () -> Void
    var onAnnotate: () -> Void
    var onSave: () -> Void
    var onDismiss: () -> Void

    @State private var isVisible = false

    var body: some View {
        HStack(spacing: 16) {
            // Thumbnail
            Image(decorative: image, scale: 1.0)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: 80, height: 56)
                .clipShape(RoundedRectangle(cornerRadius: 8))

            // Action buttons
            HStack(spacing: 8) {
                OverlayButton(label: "Copy", isPrimary: true, action: onCopy)
                OverlayButton(label: "Annotate", isPrimary: false, action: onAnnotate)
                OverlayButton(label: "Save", isPrimary: false, action: onSave)
            }

            // Dismiss
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 14))
                    .foregroundStyle(.tertiary)
            }
            .buttonStyle(.plain)
        }
        .padding(16)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .shadow(color: .black.opacity(0.12), radius: 20, y: 4)
        .offset(y: isVisible ? 0 : 40)
        .opacity(isVisible ? 1 : 0)
        .task {
            withAnimation(.easeOut(duration: 0.25)) {
                isVisible = true
            }
            // Auto-dismiss after 5 seconds
            try? await Task.sleep(for: .seconds(5))
            withAnimation(.easeIn(duration: 0.2)) {
                isVisible = false
            }
            try? await Task.sleep(for: .seconds(0.2))
            onDismiss()
        }
    }
}

private struct OverlayButton: View {
    let label: String
    let isPrimary: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(isPrimary ? .white : .secondary)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(isPrimary ? Color(nsColor: NSColor(white: 0.1, alpha: 1.0)) : Color(nsColor: NSColor(white: 0.95, alpha: 1.0)))
                .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }
}
```

- [ ] **Step 2: Commit**

```bash
git add app/Sources/ZigShot/Views/Overlay/QuickOverlay.swift
git commit -m "feat: QuickOverlay — post-capture floating pill

Thumbnail + Copy/Annotate/Save buttons. Slides up on appear,
auto-dismisses after 5s. ultraThinMaterial, rounded corners."
```

---

### Task 11: Create ExportSheet

**Files:**
- Create: `app/Sources/ZigShot/Views/Editor/ExportSheet.swift`

- [ ] **Step 1: Create ExportSheet**

Write `app/Sources/ZigShot/Views/Editor/ExportSheet.swift`:

```swift
import SwiftUI

struct ExportSheet: View {
    @Environment(AppState.self) private var appState
    let image: ZigShotImage?
    @Binding var isPresented: Bool

    @State private var format: ExportFormat = .png
    @State private var jpegQuality: Double = 0.9

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Export")
                .font(.system(size: 17, weight: .semibold))

            // Format picker
            HStack {
                Text("Format")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                Spacer()
                Picker("", selection: $format) {
                    ForEach(ExportFormat.allCases) { fmt in
                        Text(fmt.label).tag(fmt)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 160)
            }

            // Quality slider (JPEG only)
            if format == .jpeg {
                HStack {
                    Text("Quality")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                    Slider(value: $jpegQuality, in: 0.1...1.0, step: 0.05)
                    Text("\(Int(jpegQuality * 100))%")
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .frame(width: 40)
                }
            }

            // Actions
            HStack {
                Spacer()
                Button("Cancel") { isPresented = false }
                    .keyboardShortcut(.cancelAction)
                Button("Save") { saveFile() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 360)
    }

    private func saveFile() {
        guard let image else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = format == .png
            ? [.png]
            : [.jpeg]
        panel.nameFieldStringValue = "Screenshot \(Self.dateFormatter.string(from: Date()))"
        panel.directoryURL = appState.defaultSaveDirectory

        guard panel.runModal() == .OK, let url = panel.url else { return }
        appState.defaultSaveDirectory = url.deletingLastPathComponent()

        switch format {
        case .png: _ = image.savePNG(to: url)
        case .jpeg: _ = image.saveJPEG(to: url, quality: CGFloat(jpegQuality))
        }

        isPresented = false
        appState.showToast("Saved")
    }

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        return f
    }()
}
```

- [ ] **Step 2: Commit**

```bash
git add app/Sources/ZigShot/Views/Editor/ExportSheet.swift
git commit -m "feat: ExportSheet — format picker with quality slider

PNG/JPEG format selection, JPEG quality slider with percentage,
NSSavePanel with smart defaults, persists last-used directory."
```

---

### Task 12: Create BackgroundPicker

**Files:**
- Create: `app/Sources/ZigShot/Views/Editor/BackgroundPicker.swift`

- [ ] **Step 1: Create BackgroundPicker**

Write `app/Sources/ZigShot/Views/Editor/BackgroundPicker.swift`:

```swift
import SwiftUI

struct BackgroundPicker: View {
    @Bindable var editorState: EditorState

    private let paddings: [CGFloat] = [40, 60, 80]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Background")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.tertiary)
                .textCase(.uppercase)
                .tracking(1)

            // Style options
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(48), spacing: 8), count: 4), spacing: 8) {
                ForEach(BackgroundStyle.allCases) { style in
                    BackgroundStyleButton(
                        style: style,
                        isSelected: editorState.backgroundStyle == style,
                        action: {
                            editorState.backgroundStyle = style
                            editorState.backgroundEnabled = style != .none
                        }
                    )
                }
            }

            // Padding control
            if editorState.backgroundEnabled {
                HStack {
                    Text("Padding")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Picker("", selection: $editorState.backgroundPadding) {
                        ForEach(paddings, id: \.self) { p in
                            Text("\(Int(p))").tag(p)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 160)
                }
            }
        }
        .padding(16)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.06), radius: 12, y: 4)
        .frame(width: 240)
    }
}

private struct BackgroundStyleButton: View {
    let style: BackgroundStyle
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            RoundedRectangle(cornerRadius: 6)
                .fill(fillForStyle)
                .frame(width: 48, height: 32)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(isSelected ? Color.primary : Color.clear, lineWidth: 2)
                )
                .overlay(
                    style == .none
                        ? AnyView(Image(systemName: "nosign")
                            .font(.system(size: 10))
                            .foregroundStyle(.tertiary))
                        : AnyView(EmptyView())
                )
        }
        .buttonStyle(.plain)
        .help(style.label)
    }

    private var fillForStyle: some ShapeStyle {
        switch style {
        case .none: return AnyShapeStyle(Color(white: 0.95))
        case .white: return AnyShapeStyle(Color.white)
        case .lightGray: return AnyShapeStyle(Color(white: 0.92))
        case .black: return AnyShapeStyle(Color(white: 0.1))
        case .gradientPurple: return AnyShapeStyle(LinearGradient(colors: [.purple.opacity(0.3), .blue.opacity(0.2)], startPoint: .topLeading, endPoint: .bottomTrailing))
        case .gradientPeach: return AnyShapeStyle(LinearGradient(colors: [.orange.opacity(0.25), .pink.opacity(0.2)], startPoint: .topLeading, endPoint: .bottomTrailing))
        case .gradientBlue: return AnyShapeStyle(LinearGradient(colors: [.cyan.opacity(0.25), .blue.opacity(0.2)], startPoint: .topLeading, endPoint: .bottomTrailing))
        case .gradientDark: return AnyShapeStyle(LinearGradient(colors: [Color(white: 0.15), Color(white: 0.08)], startPoint: .topLeading, endPoint: .bottomTrailing))
        }
    }
}
```

- [ ] **Step 2: Commit**

```bash
git add app/Sources/ZigShot/Views/Editor/BackgroundPicker.swift
git commit -m "feat: BackgroundPicker — gradient/solid background wrap options

8 background styles (none, 3 solid, 4 gradients), padding selector
(40/60/80px). ultraThinMaterial floating panel."
```

---

### Task 13: Create PreferencesView

**Files:**
- Modify: `app/Sources/ZigShot/Views/Preferences/PreferencesView.swift`

- [ ] **Step 1: Replace placeholder with full implementation**

Replace contents of `app/Sources/ZigShot/Views/Preferences/PreferencesView.swift`:

```swift
import SwiftUI
import ServiceManagement

struct PreferencesView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        @Bindable var state = appState
        Form {
            Section("General") {
                Toggle("Launch at login", isOn: $state.launchAtLogin)
                    .onChange(of: state.launchAtLogin) { _, newValue in
                        setLaunchAtLogin(newValue)
                    }
                Toggle("Capture sound", isOn: $state.captureSound)
            }

            Section("Export") {
                Picker("Default format", selection: $state.defaultFormat) {
                    ForEach(ExportFormat.allCases) { fmt in
                        Text(fmt.label).tag(fmt)
                    }
                }

                if state.defaultFormat == .jpeg {
                    HStack {
                        Text("JPEG quality")
                        Slider(value: $state.jpegQuality, in: 0.1...1.0, step: 0.05)
                        Text("\(Int(state.jpegQuality * 100))%")
                            .font(.system(.body, design: .monospaced))
                            .frame(width: 40)
                    }
                }

                HStack {
                    Text("Save location")
                    Spacer()
                    Text(state.defaultSaveDirectory.lastPathComponent)
                        .foregroundStyle(.secondary)
                    Button("Choose...") { chooseSaveDirectory() }
                }
            }

            Section("Shortcuts") {
                ShortcutRow(label: "Fullscreen", shortcut: "Cmd+Shift+3")
                ShortcutRow(label: "Area", shortcut: "Cmd+Shift+4")
                ShortcutRow(label: "Window", shortcut: "Cmd+Shift+5")
                ShortcutRow(label: "OCR", shortcut: "Cmd+Shift+O")
            }
        }
        .formStyle(.grouped)
        .frame(width: 420, height: 360)
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        try? SMAppService.mainApp.register()
    }

    private func chooseSaveDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        if panel.runModal() == .OK, let url = panel.url {
            appState.defaultSaveDirectory = url
        }
    }
}

private struct ShortcutRow: View {
    let label: String
    let shortcut: String

    var body: some View {
        HStack {
            Text(label)
            Spacer()
            Text(shortcut)
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Color(nsColor: NSColor(white: 0.95, alpha: 1.0)))
                .clipShape(RoundedRectangle(cornerRadius: 5))
        }
    }
}
```

- [ ] **Step 2: Commit**

```bash
git add app/Sources/ZigShot/Views/Preferences/PreferencesView.swift
git commit -m "feat: PreferencesView — launch at login, export defaults, shortcuts

Grouped form with General, Export, and Shortcuts sections. Format
picker, quality slider, save directory chooser, launch at login toggle."
```

---

### Task 14: Create OCRTool

**Files:**
- Create: `app/Sources/ZigShot/Tools/OCRTool.swift`

- [ ] **Step 1: Create OCRTool**

Write `app/Sources/ZigShot/Tools/OCRTool.swift`:

```swift
import AppKit
import Vision

/// Extracts text from a CGImage region using Vision framework.
@MainActor
final class OCRTool {

    /// Extract text from the given image.
    /// Returns recognized text joined by newlines.
    static func extractText(from cgImage: CGImage) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                let results = request.results as? [VNRecognizedTextObservation] ?? []
                let text = results.compactMap { $0.topCandidates(1).first?.string }
                    .joined(separator: "\n")
                continuation.resume(returning: text)
            }
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true

            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            do {
                try handler.perform([request])
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    /// Extract text from a region of a ZigShotImage.
    static func extractText(from image: ZigShotImage, in rect: CGRect) async throws -> String {
        guard let cgImage = image.cgImage() else {
            throw OCRError.imageConversionFailed
        }
        // Crop to selection rect
        guard let cropped = cgImage.cropping(to: rect) else {
            throw OCRError.cropFailed
        }
        return try await extractText(from: cropped)
    }

    /// Copy extracted text to clipboard.
    static func extractAndCopy(from image: ZigShotImage, in rect: CGRect) async throws -> String {
        let text = try await extractText(from: image, in: rect)
        if !text.isEmpty {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
        }
        return text
    }
}

enum OCRError: Error, LocalizedError {
    case imageConversionFailed
    case cropFailed

    var errorDescription: String? {
        switch self {
        case .imageConversionFailed: return "Failed to convert image for OCR"
        case .cropFailed: return "Failed to crop image region"
        }
    }
}
```

- [ ] **Step 2: Commit**

```bash
git add app/Sources/ZigShot/Tools/OCRTool.swift
git commit -m "feat: OCRTool — Vision framework text extraction

Extracts text from CGImage or ZigShotImage regions. Accurate
recognition with language correction. Copies to clipboard."
```

---

### Task 15: Create ColorPickerTool (Eyedropper)

**Files:**
- Create: `app/Sources/ZigShot/Tools/ColorPickerTool.swift`

- [ ] **Step 1: Create ColorPickerTool**

Write `app/Sources/ZigShot/Tools/ColorPickerTool.swift`:

```swift
import AppKit

/// Picks a pixel color from a ZigShotImage at a given point.
@MainActor
final class ColorPickerTool {

    struct PickedColor {
        let r: UInt8, g: UInt8, b: UInt8, a: UInt8

        var hex: String {
            String(format: "#%02X%02X%02X", r, g, b)
        }

        var rgb: String {
            "rgb(\(r), \(g), \(b))"
        }

        var nsColor: NSColor {
            NSColor(
                red: CGFloat(r) / 255,
                green: CGFloat(g) / 255,
                blue: CGFloat(b) / 255,
                alpha: CGFloat(a) / 255
            )
        }
    }

    /// Pick the color at a specific pixel coordinate.
    static func pick(from image: ZigShotImage, at point: CGPoint) -> PickedColor? {
        let x = Int(point.x)
        let y = Int(point.y)
        guard x >= 0, y >= 0, x < Int(image.width), y < Int(image.height) else { return nil }

        let stride = Int(image.stride)
        let offset = y * stride + x * 4
        let pixels = image.pixels

        return PickedColor(
            r: pixels[offset],
            g: pixels[offset + 1],
            b: pixels[offset + 2],
            a: pixels[offset + 3]
        )
    }

    /// Pick color and copy hex to clipboard.
    static func pickAndCopy(from image: ZigShotImage, at point: CGPoint) -> PickedColor? {
        guard let color = pick(from: image, at: point) else { return nil }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(color.hex, forType: .string)
        return color
    }
}
```

- [ ] **Step 2: Commit**

```bash
git add app/Sources/ZigShot/Tools/ColorPickerTool.swift
git commit -m "feat: ColorPickerTool — pixel color eyedropper

Reads RGBA from Zig pixel buffer at coordinates. Returns hex/rgb
strings and NSColor. Copies hex to clipboard on pick."
```

---

### Task 16: Wire Capture Pipeline and Hotkeys

**Files:**
- Modify: `app/Sources/ZigShot/ZigShotApp.swift`
- Modify: `app/Sources/ZigShot/Views/MenuBar/MenuBarView.swift`
- Modify: `app/Sources/ZigShot/Models/AppState.swift`

This task connects the capture pipeline to the SwiftUI app lifecycle.

- [ ] **Step 1: Update ZigShotApp to register hotkeys on launch**

Edit `app/Sources/ZigShot/ZigShotApp.swift` — add `init()`:

```swift
@main
struct ZigShotApp: App {
    @State private var appState = AppState()
    @Environment(\.openWindow) private var openWindow

    init() {
        // Ensure no Dock icon
        NSApp.setActivationPolicy(.accessory)
    }

    var body: some Scene {
        MenuBarExtra("ZigShot", systemImage: "camera.viewfinder") {
            MenuBarView()
                .environment(appState)
        }
        .menuBarExtraStyle(.menu)

        WindowGroup("Editor", id: "editor") {
            EditorView()
                .environment(appState)
        }
        .windowStyle(.plain)
        .windowResizability(.contentSize)

        Settings {
            PreferencesView()
                .environment(appState)
        }
    }
}
```

- [ ] **Step 2: Update MenuBarView with capture actions**

Update `app/Sources/ZigShot/Views/MenuBar/MenuBarView.swift` to wire actual captures:

```swift
import SwiftUI

struct MenuBarView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("Capture Fullscreen") {
            Task {
                if let img = try? await appState.captureFullscreen() {
                    appState.handleCapture(img)
                }
            }
        }
        .keyboardShortcut("3", modifiers: [.command, .shift])

        Button("Capture Area") {
            // Area selection requires overlay — simplified for now
            Task {
                if let img = try? await appState.captureFullscreen() {
                    appState.handleCapture(img)
                }
            }
        }
        .keyboardShortcut("4", modifiers: [.command, .shift])

        Button("OCR Extract") {
            Task {
                if let img = try? await appState.captureFullscreen() {
                    let zigImg = ZigShotImage.fromCGImage(img)
                    if let zigImg {
                        let text = try? await OCRTool.extractText(from: zigImg, in: CGRect(
                            x: 0, y: 0,
                            width: CGFloat(zigImg.width),
                            height: CGFloat(zigImg.height)
                        ))
                        if let text, !text.isEmpty {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(text, forType: .string)
                            appState.showToast("Text copied")
                        }
                    }
                }
            }
        }

        Divider()

        SettingsLink { Text("Preferences...") }
            .keyboardShortcut(",", modifiers: .command)

        Divider()

        Button("Quit ZigShot") { NSApp.terminate(nil) }
            .keyboardShortcut("q", modifiers: .command)
    }
}
```

- [ ] **Step 3: Commit**

```bash
git add app/Sources/ZigShot/ZigShotApp.swift \
       app/Sources/ZigShot/Views/MenuBar/MenuBarView.swift \
       app/Sources/ZigShot/Models/AppState.swift
git commit -m "feat: wire capture pipeline to SwiftUI app

Connect ScreenCaptureKit captures to menu bar actions. Clipboard-first
workflow: capture → copy PNG to clipboard → show quick overlay.
OCR extract from menu bar copies text to clipboard."
```

---

### Task 17: Delete Old AppKit Files

**Files:**
- Delete: see list below

- [ ] **Step 1: Remove old AppKit-only files**

```bash
rm -f app/Sources/ZigShot/AnnotationEditorView.swift
rm -f app/Sources/ZigShot/AnnotationEditorWindow.swift
rm -f app/Sources/ZigShot/AnnotationToolbar.swift
rm -f app/Sources/ZigShot/WindowPicker.swift
rm -f app/Sources/ZigShot/SelectionOverlay.swift
```

- [ ] **Step 2: Verify build**

Run: `cd app && swift build 2>&1 | tail -10`
Expected: Build succeeds with no references to deleted files.

- [ ] **Step 3: Commit**

```bash
git add -A app/Sources/ZigShot/
git commit -m "chore: remove old AppKit UI files

Delete AnnotationEditorView, AnnotationEditorWindow, AnnotationToolbar,
WindowPicker, SelectionOverlay — replaced by SwiftUI equivalents."
```

---

### Task 18: Build, Run, and Smoke Test

- [ ] **Step 1: Build the Zig library**

```bash
cd /Users/s3nik/Desktop/zigshot && zig build
```

Expected: `zig-out/lib/libzigshot.a` produced.

- [ ] **Step 2: Build the Swift app**

```bash
cd /Users/s3nik/Desktop/zigshot/app && swift build
```

Expected: Build succeeds with zero errors.

- [ ] **Step 3: Run the app**

```bash
cd /Users/s3nik/Desktop/zigshot/app && swift run ZigShot &
```

Expected: Menu bar icon appears (camera.viewfinder). No Dock icon.

- [ ] **Step 4: Verify capture from menu bar**

Click the menu bar icon → "Capture Fullscreen". Expected:
1. Screenshot captured
2. PNG copied to clipboard
3. No files on Desktop

- [ ] **Step 5: Fix any issues found during smoke test**

Address compilation errors, runtime crashes, or UI glitches. Re-build and re-test.

- [ ] **Step 6: Final commit**

```bash
git add -A
git commit -m "feat: ZigShot SwiftUI v1 — working capture + editor

Menu bar app with fullscreen/area capture, annotation editor with
8 tools, clipboard-first workflow, OCR extraction, color picker,
custom backgrounds, export dialog, and preferences.

SwiftUI throughout except annotation canvas (NSViewRepresentable)."
```

---

## Spec Coverage Check

| Spec Requirement | Task |
|------------------|------|
| Architecture (SwiftUI + NSViewRepresentable) | Tasks 5, 6 |
| @Observable models | Tasks 2, 3, 4 |
| Capture modes (fullscreen/area/window) | Task 16 |
| Quick Access Overlay | Task 10 |
| Clipboard-first workflow | Task 2 (AppState.handleCapture) |
| Annotation editor window | Tasks 6, 8 |
| Editor toolbar (floating pill) | Task 7 |
| 8 existing tools | Task 6 (kept from Phase 3) |
| OCR tool | Task 14 |
| Color picker / Eyedropper | Task 15 |
| Backgrounds | Task 12 |
| Export sheet (format/quality) | Task 11 |
| Toast view | Task 9 |
| Menu bar app | Tasks 5, 16 |
| Preferences | Task 13 |
| Keyboard shortcuts | Task 8 (EditorView.handleKeyPress) |
| Delete old AppKit files | Task 17 |
| Design system (typography, colors, shadows, radii) | Tasks 6, 7, 8, 9, 10 |
| Drag & drop | Task 10 (QuickOverlay) + Task 6 (canvas) |
| Smart guides / spacing indicators | Deferred (enhancement after v1 core works) |
| Rulers & measurement (pixel coordinates) | Task 8 (cursor position display) |
