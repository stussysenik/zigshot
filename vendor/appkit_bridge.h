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

#endif // APPKIT_BRIDGE_H
