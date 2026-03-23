// appkit_bridge.h — Thin C bridge to macOS AppKit via ObjC runtime.
//
// This file provides C functions that Zig can call to interact with
// AppKit (NSWindow, NSView, NSStatusItem, NSMenu, NSApplication).
// The implementation uses the ObjC runtime directly — no .m files needed.

#ifndef APPKIT_BRIDGE_H
#define APPKIT_BRIDGE_H

#include <stdint.h>
#include <stdbool.h>

// Selection overlay result
typedef struct {
    int32_t x;
    int32_t y;
    uint32_t width;
    uint32_t height;
    bool cancelled;
} SelectionResult;

// Callback type for menu bar actions
typedef void (*MenuActionCallback)(int action_id);

// Show a transparent fullscreen overlay for area selection.
// Blocks until the user completes selection or presses ESC.
// Returns the selected rectangle (in screen coordinates).
SelectionResult appkit_show_selection_overlay(void);

// Initialize the NSApplication (required before any AppKit usage).
void appkit_init_app(void);

// Create a menu bar status item with default menu.
// callback is invoked when a menu item is clicked.
void appkit_create_menubar(MenuActionCallback callback);

// Run the NSApplication main event loop (blocks forever).
void appkit_run_app(void);

// Menu action IDs (passed to callback)
#define MENU_ACTION_CAPTURE_FULLSCREEN 1
#define MENU_ACTION_CAPTURE_AREA       2
#define MENU_ACTION_CAPTURE_WINDOW     3
#define MENU_ACTION_OCR                4
#define MENU_ACTION_QUIT               99

// ============================================================================
// Global Hotkey Tap (runs alongside NSApp event loop)
// ============================================================================

// Callback for global hotkey actions.
// action_id: 0=fullscreen, 1=area, 2=window, 3=ocr
typedef void (*HotkeyActionCallback)(int action_id);

// Install a CGEventTap on NSApp's main run loop.
// Monitors Cmd+Shift+2/3/4/5 and dispatches to callback via dispatch_async.
// Call appkit_run_app() afterward to start the event loop.
// Returns 0 on success, -1 on failure (missing permissions).
int appkit_install_hotkey_tap(HotkeyActionCallback callback);

// Get the CGWindowID of the frontmost window (excluding ZigShot itself).
// Returns 0 if no suitable window found.
uint32_t appkit_get_frontmost_window_id(void);

// ============================================================================
// Quick Access Overlay (floating thumbnail after capture)
// ============================================================================

// Callback for quick overlay actions.
// action_id: one of QUICK_ACTION_* constants.
// path: the image file path associated with the capture.
typedef void (*QuickOverlayCallback)(int action_id, const char* path);

// Quick overlay action IDs
#define QUICK_ACTION_COPY     10
#define QUICK_ACTION_SAVE     11
#define QUICK_ACTION_ANNOTATE 12
#define QUICK_ACTION_PIN      13
#define QUICK_ACTION_CLOSE    14

// Show a floating thumbnail panel after a capture.
// image_path: path to the captured PNG on disk.
// width, height: image dimensions (for aspect ratio).
// callback: invoked when user clicks an action button.
void appkit_show_quick_overlay(const char* image_path,
                                uint32_t width, uint32_t height,
                                QuickOverlayCallback callback);

// Dismiss the quick overlay (if visible).
void appkit_dismiss_quick_overlay(void);

// Pin a screenshot as an always-on-top floating window.
void appkit_pin_screenshot(const char* image_path,
                           uint32_t width, uint32_t height);

// Dismiss the pinned screenshot window.
void appkit_unpin_screenshot(void);

// ============================================================================
// Annotation Editor
// ============================================================================

// Editor tool types
#define EDITOR_TOOL_ARROW     1
#define EDITOR_TOOL_RECT      2
#define EDITOR_TOOL_BLUR      3
#define EDITOR_TOOL_HIGHLIGHT  4
#define EDITOR_TOOL_TEXT      5
#define EDITOR_TOOL_NUMBERING 6

// Called when user finishes drawing a shape (mouseUp).
// tool: which EDITOR_TOOL_* was active.
// x0,y0: start point.  x1,y1: end point (image coordinates).
typedef void (*EditorToolCallback)(int tool, int32_t x0, int32_t y0,
                                    int32_t x1, int32_t y1);

// Called when user clicks Save / Copy / Undo / Redo / Close.
// action: 1=copy, 2=save, 3=undo, 4=redo, 5=close
typedef void (*EditorActionCallback)(int action, const char* path);

// Editor action IDs
#define EDITOR_ACTION_COPY    1
#define EDITOR_ACTION_SAVE    2
#define EDITOR_ACTION_UNDO    3
#define EDITOR_ACTION_REDO    4
#define EDITOR_ACTION_CLOSE   5

// Opaque handle to an open editor window.
typedef void* EditorHandle;

// Open the annotation editor with an RGBA pixel buffer.
// pixels: width * height * 4 bytes, RGBA, owned by caller (Zig).
// The editor reads from this pointer — caller must keep it alive.
EditorHandle appkit_open_editor(const uint8_t* pixels,
                                 uint32_t width, uint32_t height,
                                 EditorToolCallback tool_cb,
                                 EditorActionCallback action_cb);

// Push updated pixels to the editor after Zig applies an annotation.
void appkit_editor_update_image(EditorHandle handle,
                                 const uint8_t* pixels,
                                 uint32_t width, uint32_t height);

// Close the editor window.
void appkit_editor_close(EditorHandle handle);

// Set the active tool color (0xRRGGBBAA).
void appkit_editor_set_color(EditorHandle handle, uint32_t rgba);

// Set the active tool stroke width.
void appkit_editor_set_size(EditorHandle handle, float size);

// ============================================================================
// Screen Recording
// ============================================================================

// Recording status callback
typedef void (*RecordingStatusCallback)(int status, const char* info);

#define RECORDING_STATUS_STARTED  1
#define RECORDING_STATUS_STOPPED  2
#define RECORDING_STATUS_ERROR    3

// Start recording a screen area.
// format: "mp4" or "gif"
void appkit_start_recording(int32_t x, int32_t y, uint32_t width, uint32_t height,
                            const char* output_path, const char* format,
                            uint32_t fps, RecordingStatusCallback callback);

// Stop the current recording.
void appkit_stop_recording(void);

// Check if currently recording.
bool appkit_is_recording(void);

// ============================================================================
// Text Rendering
// ============================================================================

// Render text into an RGBA pixel buffer.
// Returns a heap-allocated buffer (caller must free with appkit_free_text_buffer).
// out_width/out_height receive the actual rendered dimensions.
uint8_t* appkit_render_text(const char* text, float font_size,
                             uint32_t color_rgba,
                             uint32_t* out_width, uint32_t* out_height);

// Free a buffer returned by appkit_render_text.
void appkit_free_text_buffer(uint8_t* buffer);

#endif // APPKIT_BRIDGE_H
