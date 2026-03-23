// appkit_bridge.m — AppKit bridge using Objective-C
//
// This file uses Objective-C (compiled with -fobjc-arc) to interact with
// AppKit. It exports plain C functions that Zig calls via @cImport.
//
// Why .m instead of pure C with objc_msgSend?
// ARM64 (Apple Silicon) requires properly typed objc_msgSend calls.
// Using Objective-C directly is simpler, more readable, and correct.
// The exported API is still plain C — Zig doesn't know or care that
// the implementation is ObjC.

#import <Cocoa/Cocoa.h>
#include "appkit_bridge.h"

// ============================================================================
// Selection Overlay
// ============================================================================

// Global state for the selection overlay
static NSPoint g_start_point = {0, 0};
static NSPoint g_current_point = {0, 0};
static BOOL g_is_dragging = NO;
static BOOL g_selection_done = NO;
static BOOL g_selection_cancelled = NO;

@interface ZigShotOverlayView : NSView
@end

@implementation ZigShotOverlayView

- (void)mouseDown:(NSEvent *)event {
    g_start_point = [NSEvent mouseLocation];
    g_current_point = g_start_point;
    g_is_dragging = YES;
    [self setNeedsDisplay:YES];
}

- (void)mouseDragged:(NSEvent *)event {
    g_current_point = [NSEvent mouseLocation];
    [self setNeedsDisplay:YES];
}

- (void)mouseUp:(NSEvent *)event {
    g_current_point = [NSEvent mouseLocation];
    g_is_dragging = NO;
    g_selection_done = YES;
    [NSApp stop:nil];
    // Post a dummy event to unblock the run loop
    NSEvent *dummy = [NSEvent otherEventWithType:NSEventTypeApplicationDefined
                                        location:NSZeroPoint
                                   modifierFlags:0
                                       timestamp:0
                                    windowNumber:0
                                         context:nil
                                         subtype:0
                                           data1:0
                                           data2:0];
    [NSApp postEvent:dummy atStart:YES];
}

- (void)keyDown:(NSEvent *)event {
    if (event.keyCode == 53) { // ESC
        g_selection_cancelled = YES;
        g_selection_done = YES;
        [NSApp stop:nil];
        NSEvent *dummy = [NSEvent otherEventWithType:NSEventTypeApplicationDefined
                                            location:NSZeroPoint
                                       modifierFlags:0
                                           timestamp:0
                                        windowNumber:0
                                             context:nil
                                             subtype:0
                                               data1:0
                                               data2:0];
        [NSApp postEvent:dummy atStart:YES];
    }
}

- (BOOL)acceptsFirstResponder { return YES; }
- (BOOL)canBecomeKeyView { return YES; }

- (void)drawRect:(NSRect)dirtyRect {
    // Draw semi-transparent dark overlay
    [[NSColor colorWithWhite:0.0 alpha:0.3] set];
    NSRectFill(dirtyRect);

    if (g_is_dragging || g_selection_done) {
        // Calculate selection rectangle
        CGFloat x = fmin(g_start_point.x, g_current_point.x);
        CGFloat y = fmin(g_start_point.y, g_current_point.y);
        CGFloat w = fabs(g_current_point.x - g_start_point.x);
        CGFloat h = fabs(g_current_point.y - g_start_point.y);

        // Convert from screen to window coordinates
        NSRect screenFrame = [[NSScreen mainScreen] frame];
        NSRect selRect = NSMakeRect(x, y, w, h);

        // Clear the selection area (show the screen through)
        [[NSColor clearColor] set];
        NSRectFill(selRect);

        // Draw selection border
        NSBezierPath *border = [NSBezierPath bezierPathWithRect:selRect];
        [[NSColor colorWithRed:0.2 green:0.5 blue:1.0 alpha:0.9] set];
        [border setLineWidth:2.0];
        [border stroke];

        // Draw dimension label
        NSString *dimText = [NSString stringWithFormat:@"%.0f × %.0f", w, h];
        NSDictionary *attrs = @{
            NSFontAttributeName: [NSFont systemFontOfSize:13 weight:NSFontWeightMedium],
            NSForegroundColorAttributeName: [NSColor whiteColor],
        };
        NSSize textSize = [dimText sizeWithAttributes:attrs];

        // Position label below selection (or above if near bottom)
        CGFloat labelX = x + (w - textSize.width) / 2;
        CGFloat labelY = y - textSize.height - 8;
        if (labelY < screenFrame.origin.y + 20) {
            labelY = y + h + 8;
        }

        // Draw label background
        NSRect labelBg = NSMakeRect(labelX - 6, labelY - 2, textSize.width + 12, textSize.height + 4);
        [[NSColor colorWithWhite:0.0 alpha:0.7] set];
        NSBezierPath *roundedBg = [NSBezierPath bezierPathWithRoundedRect:labelBg xRadius:4 yRadius:4];
        [roundedBg fill];

        // Draw label text
        [dimText drawAtPoint:NSMakePoint(labelX, labelY) withAttributes:attrs];
    }

    // Draw crosshair at current mouse position
    if (!g_selection_done) {
        NSPoint mouse = [NSEvent mouseLocation];
        NSRect screenFrame = [[NSScreen mainScreen] frame];

        [[NSColor colorWithWhite:1.0 alpha:0.4] set];
        NSBezierPath *hLine = [NSBezierPath bezierPath];
        [hLine moveToPoint:NSMakePoint(screenFrame.origin.x, mouse.y)];
        [hLine lineToPoint:NSMakePoint(screenFrame.origin.x + screenFrame.size.width, mouse.y)];
        [hLine setLineWidth:0.5];
        [hLine stroke];

        NSBezierPath *vLine = [NSBezierPath bezierPath];
        [vLine moveToPoint:NSMakePoint(mouse.x, screenFrame.origin.y)];
        [vLine lineToPoint:NSMakePoint(mouse.x, screenFrame.origin.y + screenFrame.size.height)];
        [vLine setLineWidth:0.5];
        [vLine stroke];
    }
}

@end

SelectionResult appkit_show_selection_overlay(void) {
    @autoreleasepool {
        // Reset state
        g_is_dragging = NO;
        g_selection_done = NO;
        g_selection_cancelled = NO;

        // Ensure NSApplication exists
        [NSApplication sharedApplication];
        [NSApp setActivationPolicy:NSApplicationActivationPolicyAccessory];

        // Get the main screen frame
        NSRect screenFrame = [[NSScreen mainScreen] frame];

        // Create transparent borderless window covering the entire screen
        NSWindow *window = [[NSWindow alloc]
            initWithContentRect:screenFrame
                      styleMask:NSWindowStyleMaskBorderless
                        backing:NSBackingStoreBuffered
                          defer:NO];

        [window setOpaque:NO];
        [window setBackgroundColor:[NSColor clearColor]];
        [window setLevel:NSScreenSaverWindowLevel];
        [window setCollectionBehavior:NSWindowCollectionBehaviorCanJoinAllSpaces |
                                      NSWindowCollectionBehaviorStationary];

        // Create and set the custom view
        ZigShotOverlayView *view = [[ZigShotOverlayView alloc] initWithFrame:screenFrame];
        [window setContentView:view];
        [window makeKeyAndOrderFront:nil];
        [window makeFirstResponder:view];

        // Force app to front
        [NSApp activateIgnoringOtherApps:YES];

        // Set up a timer to redraw crosshairs as mouse moves
        NSTimer *timer = [NSTimer scheduledTimerWithTimeInterval:1.0/60.0
                                                         repeats:YES
                                                           block:^(NSTimer *t) {
            if (!g_selection_done) {
                [view setNeedsDisplay:YES];
            }
        }];

        // Run modal until selection is done
        [NSApp run];

        // Cleanup
        [timer invalidate];
        [window close];

        SelectionResult result;
        if (g_selection_cancelled) {
            result.cancelled = true;
            result.x = 0;
            result.y = 0;
            result.width = 0;
            result.height = 0;
        } else {
            // Convert from screen coordinates (origin bottom-left) to
            // CoreGraphics coordinates (origin top-left)
            NSRect screenFrame2 = [[NSScreen mainScreen] frame];
            CGFloat x = fmin(g_start_point.x, g_current_point.x);
            CGFloat y = fmin(g_start_point.y, g_current_point.y);
            CGFloat w = fabs(g_current_point.x - g_start_point.x);
            CGFloat h = fabs(g_current_point.y - g_start_point.y);

            // Flip Y coordinate for CoreGraphics
            CGFloat cg_y = screenFrame2.size.height - y - h;

            result.cancelled = false;
            result.x = (int32_t)x;
            result.y = (int32_t)cg_y;
            result.width = (uint32_t)w;
            result.height = (uint32_t)h;
        }
        return result;
    }
}

// ============================================================================
// Menu Bar
// ============================================================================

static MenuActionCallback g_menu_callback = NULL;

@interface ZigShotMenuDelegate : NSObject
- (void)captureFullscreen:(id)sender;
- (void)captureArea:(id)sender;
- (void)captureWindow:(id)sender;
- (void)ocrCapture:(id)sender;
- (void)quitApp:(id)sender;
@end

@implementation ZigShotMenuDelegate
- (void)captureFullscreen:(id)sender {
    if (g_menu_callback) g_menu_callback(MENU_ACTION_CAPTURE_FULLSCREEN);
}
- (void)captureArea:(id)sender {
    if (g_menu_callback) g_menu_callback(MENU_ACTION_CAPTURE_AREA);
}
- (void)captureWindow:(id)sender {
    if (g_menu_callback) g_menu_callback(MENU_ACTION_CAPTURE_WINDOW);
}
- (void)ocrCapture:(id)sender {
    if (g_menu_callback) g_menu_callback(MENU_ACTION_OCR);
}
- (void)quitApp:(id)sender {
    if (g_menu_callback) g_menu_callback(MENU_ACTION_QUIT);
    [NSApp terminate:nil];
}
@end

static ZigShotMenuDelegate *g_delegate = nil;

void appkit_init_app(void) {
    [NSApplication sharedApplication];
    [NSApp setActivationPolicy:NSApplicationActivationPolicyAccessory];
}

void appkit_create_menubar(MenuActionCallback callback) {
    @autoreleasepool {
        g_menu_callback = callback;
        g_delegate = [[ZigShotMenuDelegate alloc] init];

        NSStatusItem *statusItem = [[NSStatusBar systemStatusBar]
            statusItemWithLength:NSVariableStatusItemLength];

        // Use SF Symbol for camera icon
        NSImage *icon = [NSImage imageWithSystemSymbolName:@"camera.fill"
                                 accessibilityDescription:@"ZigShot"];
        if (icon) {
            [icon setSize:NSMakeSize(18, 18)];
            statusItem.button.image = icon;
        } else {
            statusItem.button.title = @"📷";
        }

        // Build menu
        NSMenu *menu = [[NSMenu alloc] init];

        NSMenuItem *titleItem = [[NSMenuItem alloc] initWithTitle:@"ZigShot"
                                                           action:nil
                                                    keyEquivalent:@""];
        [titleItem setEnabled:NO];
        [menu addItem:titleItem];
        [menu addItem:[NSMenuItem separatorItem]];

        NSMenuItem *fsItem = [[NSMenuItem alloc] initWithTitle:@"Capture Fullscreen"
                                                        action:@selector(captureFullscreen:)
                                                 keyEquivalent:@"3"];
        [fsItem setKeyEquivalentModifierMask:NSEventModifierFlagCommand | NSEventModifierFlagShift];
        [fsItem setTarget:g_delegate];
        [menu addItem:fsItem];

        NSMenuItem *areaItem = [[NSMenuItem alloc] initWithTitle:@"Capture Area"
                                                          action:@selector(captureArea:)
                                                   keyEquivalent:@"4"];
        [areaItem setKeyEquivalentModifierMask:NSEventModifierFlagCommand | NSEventModifierFlagShift];
        [areaItem setTarget:g_delegate];
        [menu addItem:areaItem];

        NSMenuItem *winItem = [[NSMenuItem alloc] initWithTitle:@"Capture Window"
                                                         action:@selector(captureWindow:)
                                                  keyEquivalent:@"5"];
        [winItem setKeyEquivalentModifierMask:NSEventModifierFlagCommand | NSEventModifierFlagShift];
        [winItem setTarget:g_delegate];
        [menu addItem:winItem];

        [menu addItem:[NSMenuItem separatorItem]];

        NSMenuItem *ocrItem = [[NSMenuItem alloc] initWithTitle:@"OCR (Extract Text)"
                                                         action:@selector(ocrCapture:)
                                                  keyEquivalent:@"2"];
        [ocrItem setKeyEquivalentModifierMask:NSEventModifierFlagCommand | NSEventModifierFlagShift];
        [ocrItem setTarget:g_delegate];
        [menu addItem:ocrItem];

        [menu addItem:[NSMenuItem separatorItem]];

        NSMenuItem *quitItem = [[NSMenuItem alloc] initWithTitle:@"Quit ZigShot"
                                                          action:@selector(quitApp:)
                                                   keyEquivalent:@"q"];
        [quitItem setTarget:g_delegate];
        [menu addItem:quitItem];

        statusItem.menu = menu;

        // Retain the status item (otherwise it disappears when ARC releases it)
        // We use a global to prevent deallocation
        static NSStatusItem *retained = nil;
        retained = statusItem;
    }
}

void appkit_run_app(void) {
    [NSApp run];
}
