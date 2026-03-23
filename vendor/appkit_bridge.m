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
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#import <QuartzCore/QuartzCore.h>
#import <ScreenCaptureKit/ScreenCaptureKit.h>
#import <AVFoundation/AVFoundation.h>
#import <CoreMedia/CoreMedia.h>
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

// ============================================================================
// Global Hotkey Tap (runs on NSApp's main run loop)
// ============================================================================

static HotkeyActionCallback g_hotkey_callback = NULL;

// macOS keycodes for number keys
#define KEYCODE_2 19
#define KEYCODE_3 20
#define KEYCODE_4 21
#define KEYCODE_5 23

static CGEventRef hotkey_tap_callback(CGEventTapProxy proxy, CGEventType type,
                                       CGEventRef event, void *refcon) {
    (void)proxy; (void)refcon;

    // Re-enable if macOS disabled the tap (happens if callback is too slow)
    if (type == kCGEventTapDisabledByTimeout || type == kCGEventTapDisabledByUserInput) {
        if (refcon) CGEventTapEnable((CFMachPortRef)refcon, true);
        return event;
    }

    if (type != kCGEventKeyDown) return event;

    CGEventFlags flags = CGEventGetFlags(event);
    int64_t keycode = CGEventGetIntegerValueField(event, kCGKeyboardEventKeycode);

    // Check for Cmd+Shift
    BOOL hasCmd = (flags & kCGEventFlagMaskCommand) != 0;
    BOOL hasShift = (flags & kCGEventFlagMaskShift) != 0;
    if (!hasCmd || !hasShift) return event;

    int action_id = -1;
    switch (keycode) {
        case KEYCODE_3: action_id = 0; break; // Cmd+Shift+3 = fullscreen
        case KEYCODE_4: action_id = 1; break; // Cmd+Shift+4 = area
        case KEYCODE_5: action_id = 2; break; // Cmd+Shift+5 = window
        case KEYCODE_2: action_id = 3; break; // Cmd+Shift+2 = OCR
        default: return event;
    }

    // Dispatch to main queue so the heavy work doesn't block the event tap.
    // macOS auto-disables taps if the callback takes >~1 second.
    if (g_hotkey_callback) {
        HotkeyActionCallback cb = g_hotkey_callback;
        dispatch_async(dispatch_get_main_queue(), ^{
            cb(action_id);
        });
    }

    return event;
}

int appkit_install_hotkey_tap(HotkeyActionCallback callback) {
    g_hotkey_callback = callback;

    CGEventMask eventMask = (1 << kCGEventKeyDown);
    CFMachPortRef tap = CGEventTapCreate(
        kCGSessionEventTap,
        kCGHeadInsertEventTap,
        kCGEventTapOptionDefault,
        eventMask,
        hotkey_tap_callback,
        NULL  // will be set to tap itself below for re-enable
    );

    if (!tap) return -1;

    // Pass the tap itself as refcon so we can re-enable on timeout
    // (CGEventTapCreate doesn't support this directly, so we recreate)
    CFRelease(tap);
    tap = CGEventTapCreate(
        kCGSessionEventTap,
        kCGHeadInsertEventTap,
        kCGEventTapOptionDefault,
        eventMask,
        hotkey_tap_callback,
        (void *)tap  // refcon = tap for re-enable
    );
    if (!tap) return -1;

    CFRunLoopSourceRef source = CFMachPortCreateRunLoopSource(NULL, tap, 0);
    if (!source) {
        CFRelease(tap);
        return -1;
    }

    // Add to NSApp's main run loop (not a private CFRunLoop)
    CFRunLoopAddSource(CFRunLoopGetMain(), source, kCFRunLoopCommonModes);
    CGEventTapEnable(tap, true);

    CFRelease(source);
    // Keep tap alive (don't release — it needs to stay active)

    return 0;
}

uint32_t appkit_get_frontmost_window_id(void) {
    CFArrayRef windowList = CGWindowListCopyWindowInfo(
        kCGWindowListOptionOnScreenOnly | kCGWindowListExcludeDesktopElements,
        kCGNullWindowID);
    if (!windowList) return 0;

    CFIndex count = CFArrayGetCount(windowList);
    for (CFIndex i = 0; i < count; i++) {
        CFDictionaryRef dict = (CFDictionaryRef)CFArrayGetValueAtIndex(windowList, i);

        // Only consider normal windows (layer 0)
        CFNumberRef layerRef = (CFNumberRef)CFDictionaryGetValue(dict, kCGWindowLayer);
        int32_t layer = -1;
        if (layerRef) CFNumberGetValue(layerRef, kCFNumberSInt32Type, &layer);
        if (layer != 0) continue;

        // Skip ZigShot's own windows
        CFStringRef ownerName = (CFStringRef)CFDictionaryGetValue(dict, kCGWindowOwnerName);
        if (ownerName && CFStringCompare(ownerName, CFSTR("zigshot"), kCFCompareCaseInsensitive) == kCFCompareEqualTo) continue;

        // Get window ID
        CFNumberRef idRef = (CFNumberRef)CFDictionaryGetValue(dict, kCGWindowNumber);
        int32_t wid = 0;
        if (idRef) CFNumberGetValue(idRef, kCFNumberSInt32Type, &wid);

        CFRelease(windowList);
        return (uint32_t)wid;
    }

    CFRelease(windowList);
    return 0;
}

// ============================================================================
// Quick Access Overlay (floating thumbnail after capture)
// ============================================================================

static NSPanel *g_quick_panel = nil;
static NSTimer *g_quick_timer = nil;
static QuickOverlayCallback g_quick_callback = NULL;
static char g_quick_path[1024] = {0};

@interface ZigShotQuickOverlayView : NSView
@property (nonatomic, strong) NSImageView *imageView;
@property (nonatomic, strong) NSStackView *buttonBar;
@end

@implementation ZigShotQuickOverlayView

- (instancetype)initWithFrame:(NSRect)frame imagePath:(NSString *)path {
    self = [super initWithFrame:frame];
    if (self) {
        self.wantsLayer = YES;
        self.layer.backgroundColor = [[NSColor colorWithWhite:0.12 alpha:0.95] CGColor];
        self.layer.cornerRadius = 10.0;

        // Load and display the image thumbnail
        NSImage *image = [[NSImage alloc] initWithContentsOfFile:path];
        if (!image) return self;

        _imageView = [[NSImageView alloc] initWithFrame:NSZeroRect];
        _imageView.image = image;
        _imageView.imageScaling = NSImageScaleProportionallyUpOrDown;
        _imageView.translatesAutoresizingMaskIntoConstraints = NO;
        _imageView.wantsLayer = YES;
        _imageView.layer.cornerRadius = 6.0;
        _imageView.layer.masksToBounds = YES;
        [self addSubview:_imageView];

        // Create action buttons
        NSButton *copyBtn = [self makeButton:@"doc.on.clipboard" tag:QUICK_ACTION_COPY tooltip:@"Copy"];
        NSButton *saveBtn = [self makeButton:@"square.and.arrow.down" tag:QUICK_ACTION_SAVE tooltip:@"Save"];
        NSButton *annotateBtn = [self makeButton:@"pencil.and.outline" tag:QUICK_ACTION_ANNOTATE tooltip:@"Annotate"];
        NSButton *pinBtn = [self makeButton:@"pin" tag:QUICK_ACTION_PIN tooltip:@"Pin"];
        NSButton *closeBtn = [self makeButton:@"xmark" tag:QUICK_ACTION_CLOSE tooltip:@"Close"];

        _buttonBar = [NSStackView stackViewWithViews:@[copyBtn, saveBtn, annotateBtn, pinBtn, closeBtn]];
        _buttonBar.orientation = NSUserInterfaceLayoutOrientationHorizontal;
        _buttonBar.spacing = 2;
        _buttonBar.translatesAutoresizingMaskIntoConstraints = NO;
        [self addSubview:_buttonBar];

        // Layout constraints
        [NSLayoutConstraint activateConstraints:@[
            [_imageView.topAnchor constraintEqualToAnchor:self.topAnchor constant:8],
            [_imageView.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:8],
            [_imageView.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-8],
            [_imageView.heightAnchor constraintEqualToConstant:120],

            [_buttonBar.topAnchor constraintEqualToAnchor:_imageView.bottomAnchor constant:6],
            [_buttonBar.centerXAnchor constraintEqualToAnchor:self.centerXAnchor],
            [_buttonBar.bottomAnchor constraintEqualToAnchor:self.bottomAnchor constant:-8],
        ]];
    }
    return self;
}

- (NSButton *)makeButton:(NSString *)symbolName tag:(NSInteger)tag tooltip:(NSString *)tooltip {
    NSButton *btn = [NSButton buttonWithImage:[NSImage imageWithSystemSymbolName:symbolName
                                               accessibilityDescription:tooltip]
                                       target:self
                                       action:@selector(buttonClicked:)];
    btn.bordered = NO;
    btn.tag = tag;
    btn.toolTip = tooltip;
    btn.contentTintColor = [NSColor whiteColor];
    btn.translatesAutoresizingMaskIntoConstraints = NO;
    [btn.widthAnchor constraintEqualToConstant:32].active = YES;
    [btn.heightAnchor constraintEqualToConstant:28].active = YES;
    return btn;
}

- (void)buttonClicked:(NSButton *)sender {
    // Cancel auto-dismiss timer
    [g_quick_timer invalidate];
    g_quick_timer = nil;

    int action_id = (int)sender.tag;

    if (action_id == QUICK_ACTION_SAVE) {
        // Show save panel
        NSSavePanel *panel = [NSSavePanel savePanel];
        panel.allowedContentTypes = @[[UTType typeWithFilenameExtension:@"png"]];
        panel.nameFieldStringValue = @"screenshot.png";
        if ([panel runModal] == NSModalResponseOK) {
            NSString *savePath = panel.URL.path;
            // Copy temp file to chosen location
            [[NSFileManager defaultManager] copyItemAtPath:[NSString stringWithUTF8String:g_quick_path]
                                                    toPath:savePath
                                                     error:nil];
            if (g_quick_callback) g_quick_callback(QUICK_ACTION_SAVE, savePath.UTF8String);
        }
    } else {
        if (g_quick_callback) g_quick_callback(action_id, g_quick_path);
    }

    // Dismiss overlay (unless annotate/pin — those keep the file alive)
    if (action_id != QUICK_ACTION_ANNOTATE && action_id != QUICK_ACTION_PIN) {
        appkit_dismiss_quick_overlay();
    }
}

// Allow mouse drag to reposition the panel
- (void)mouseDown:(NSEvent *)event {
    // Reset auto-dismiss timer on interaction
    if (g_quick_timer) {
        [g_quick_timer invalidate];
        g_quick_timer = [NSTimer scheduledTimerWithTimeInterval:5.0
                                                        repeats:NO
                                                          block:^(NSTimer *t) {
            appkit_dismiss_quick_overlay();
        }];
    }
}

- (void)mouseDragged:(NSEvent *)event {
    [self.window performWindowDragWithEvent:event];
}

@end

void appkit_show_quick_overlay(const char* image_path,
                                uint32_t width, uint32_t height,
                                QuickOverlayCallback callback) {
    @autoreleasepool {
        // Dismiss any existing overlay first
        appkit_dismiss_quick_overlay();

        g_quick_callback = callback;
        strncpy(g_quick_path, image_path, sizeof(g_quick_path) - 1);

        // Calculate thumbnail aspect ratio
        CGFloat thumbWidth = 220;
        CGFloat thumbHeight = 120;
        CGFloat panelWidth = thumbWidth + 16;
        CGFloat panelHeight = thumbHeight + 50; // room for buttons

        // Position: bottom-right corner of main screen
        NSRect screenFrame = [[NSScreen mainScreen] visibleFrame];
        CGFloat panelX = screenFrame.origin.x + screenFrame.size.width - panelWidth - 16;
        CGFloat panelY = screenFrame.origin.y + 16;

        NSRect panelFrame = NSMakeRect(panelX, panelY, panelWidth, panelHeight);

        g_quick_panel = [[NSPanel alloc]
            initWithContentRect:panelFrame
                      styleMask:NSWindowStyleMaskBorderless | NSWindowStyleMaskNonactivatingPanel
                        backing:NSBackingStoreBuffered
                          defer:NO];

        [g_quick_panel setOpaque:NO];
        [g_quick_panel setBackgroundColor:[NSColor clearColor]];
        [g_quick_panel setLevel:NSFloatingWindowLevel];
        [g_quick_panel setFloatingPanel:YES];
        [g_quick_panel setBecomesKeyOnlyIfNeeded:YES];
        [g_quick_panel setMovableByWindowBackground:YES];
        [g_quick_panel setHasShadow:YES];
        [g_quick_panel setCollectionBehavior:NSWindowCollectionBehaviorCanJoinAllSpaces |
                                              NSWindowCollectionBehaviorStationary];

        // Create the content view
        ZigShotQuickOverlayView *view = [[ZigShotQuickOverlayView alloc]
            initWithFrame:NSMakeRect(0, 0, panelWidth, panelHeight)
                imagePath:[NSString stringWithUTF8String:image_path]];
        [g_quick_panel setContentView:view];
        [g_quick_panel makeKeyAndOrderFront:nil];

        // Slide-in animation
        [g_quick_panel setAlphaValue:0.0];
        NSRect startFrame = panelFrame;
        startFrame.origin.x += 40;
        [g_quick_panel setFrame:startFrame display:NO];
        [NSAnimationContext runAnimationGroup:^(NSAnimationContext *ctx) {
            ctx.duration = 0.25;
            ctx.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseOut];
            [g_quick_panel.animator setFrame:panelFrame display:YES];
            [g_quick_panel.animator setAlphaValue:1.0];
        }];

        // Auto-dismiss after 5 seconds
        g_quick_timer = [NSTimer scheduledTimerWithTimeInterval:5.0
                                                        repeats:NO
                                                          block:^(NSTimer *t) {
            // Auto-copy to clipboard on dismiss
            if (g_quick_callback) g_quick_callback(QUICK_ACTION_COPY, g_quick_path);
            appkit_dismiss_quick_overlay();
        }];
    }
}

void appkit_dismiss_quick_overlay(void) {
    if (g_quick_timer) {
        [g_quick_timer invalidate];
        g_quick_timer = nil;
    }
    if (g_quick_panel) {
        // Fade-out animation
        [NSAnimationContext runAnimationGroup:^(NSAnimationContext *ctx) {
            ctx.duration = 0.2;
            [g_quick_panel.animator setAlphaValue:0.0];
        } completionHandler:^{
            [g_quick_panel close];
            g_quick_panel = nil;
        }];
    }
}

// ============================================================================
// Pin Screenshot (always-on-top floating window)
// ============================================================================

static NSPanel *g_pin_panel = nil;

@interface ZigShotPinView : NSView
@property (nonatomic, strong) NSImageView *imageView;
@end

@implementation ZigShotPinView

- (instancetype)initWithFrame:(NSRect)frame imagePath:(NSString *)path {
    self = [super initWithFrame:frame];
    if (self) {
        self.wantsLayer = YES;
        self.layer.cornerRadius = 6.0;
        self.layer.masksToBounds = YES;
        self.layer.borderColor = [[NSColor colorWithWhite:0.3 alpha:0.5] CGColor];
        self.layer.borderWidth = 1.0;

        NSImage *image = [[NSImage alloc] initWithContentsOfFile:path];
        if (!image) return self;

        _imageView = [[NSImageView alloc] initWithFrame:self.bounds];
        _imageView.image = image;
        _imageView.imageScaling = NSImageScaleProportionallyUpOrDown;
        _imageView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
        [self addSubview:_imageView];
    }
    return self;
}

- (BOOL)acceptsFirstResponder { return YES; }

- (void)keyDown:(NSEvent *)event {
    if (event.keyCode == 53) { // ESC
        appkit_unpin_screenshot();
    }
}

- (void)rightMouseDown:(NSEvent *)event {
    NSMenu *menu = [[NSMenu alloc] init];
    NSMenuItem *closeItem = [[NSMenuItem alloc] initWithTitle:@"Close Pin"
                                                       action:@selector(closePinAction:)
                                                keyEquivalent:@""];
    [closeItem setTarget:self];
    [menu addItem:closeItem];
    [NSMenu popUpContextMenu:menu withEvent:event forView:self];
}

- (void)closePinAction:(id)sender {
    appkit_unpin_screenshot();
}

- (void)mouseDragged:(NSEvent *)event {
    [self.window performWindowDragWithEvent:event];
}

@end

void appkit_pin_screenshot(const char* image_path,
                           uint32_t width, uint32_t height) {
    @autoreleasepool {
        // Dismiss existing pin
        appkit_unpin_screenshot();

        // Scale to reasonable size (max 400px wide)
        CGFloat scale = 1.0;
        if (width > 400) scale = 400.0 / width;
        CGFloat w = width * scale;
        CGFloat h = height * scale;

        // Center on screen
        NSRect screenFrame = [[NSScreen mainScreen] visibleFrame];
        CGFloat x = screenFrame.origin.x + (screenFrame.size.width - w) / 2;
        CGFloat y = screenFrame.origin.y + (screenFrame.size.height - h) / 2;

        NSRect frame = NSMakeRect(x, y, w, h);

        g_pin_panel = [[NSPanel alloc]
            initWithContentRect:frame
                      styleMask:NSWindowStyleMaskBorderless | NSWindowStyleMaskNonactivatingPanel
                        backing:NSBackingStoreBuffered
                          defer:NO];

        [g_pin_panel setOpaque:NO];
        [g_pin_panel setBackgroundColor:[NSColor clearColor]];
        [g_pin_panel setLevel:NSFloatingWindowLevel];
        [g_pin_panel setFloatingPanel:YES];
        [g_pin_panel setMovableByWindowBackground:YES];
        [g_pin_panel setHasShadow:YES];

        ZigShotPinView *view = [[ZigShotPinView alloc]
            initWithFrame:NSMakeRect(0, 0, w, h)
                imagePath:[NSString stringWithUTF8String:image_path]];
        [g_pin_panel setContentView:view];
        [g_pin_panel makeKeyAndOrderFront:nil];
    }
}

void appkit_unpin_screenshot(void) {
    if (g_pin_panel) {
        [g_pin_panel close];
        g_pin_panel = nil;
    }
}

// ============================================================================
// Annotation Editor
// ============================================================================

@interface ZigShotEditorView : NSView
@property (nonatomic) CGImageRef displayImage;
@property (nonatomic) int currentTool;
@property (nonatomic) uint32_t toolColor;      // 0xRRGGBBAA
@property (nonatomic) float toolSize;
@property (nonatomic) NSPoint dragStart;
@property (nonatomic) NSPoint dragCurrent;
@property (nonatomic) BOOL isDragging;
@property (nonatomic) uint32_t imageWidth;
@property (nonatomic) uint32_t imageHeight;
@property (nonatomic) EditorToolCallback toolCallback;
@property (nonatomic) EditorActionCallback actionCallback;
@end

@implementation ZigShotEditorView

- (instancetype)initWithPixels:(const uint8_t *)pixels
                         width:(uint32_t)w height:(uint32_t)h
                    toolCallback:(EditorToolCallback)tcb
                  actionCallback:(EditorActionCallback)acb {
    self = [super initWithFrame:NSMakeRect(0, 0, w, h)];
    if (self) {
        _imageWidth = w;
        _imageHeight = h;
        _currentTool = EDITOR_TOOL_RECT;
        _toolColor = 0xFF0000FF; // red, full alpha
        _toolSize = 3.0;
        _isDragging = NO;
        _toolCallback = tcb;
        _actionCallback = acb;
        [self updatePixels:pixels width:w height:h];
    }
    return self;
}

- (void)updatePixels:(const uint8_t *)pixels width:(uint32_t)w height:(uint32_t)h {
    if (_displayImage) CGImageRelease(_displayImage);

    CGColorSpaceRef cs = CGColorSpaceCreateDeviceRGB();
    CGContextRef ctx = CGBitmapContextCreate(
        (void *)pixels, w, h, 8, w * 4, cs,
        kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big
    );
    _displayImage = CGBitmapContextCreateImage(ctx);
    _imageWidth = w;
    _imageHeight = h;
    CGContextRelease(ctx);
    CGColorSpaceRelease(cs);
    [self setNeedsDisplay:YES];
}

- (void)dealloc {
    if (_displayImage) CGImageRelease(_displayImage);
}

- (BOOL)isFlipped { return YES; }
- (BOOL)acceptsFirstResponder { return YES; }

- (void)drawRect:(NSRect)dirtyRect {
    // Draw the base image
    if (_displayImage) {
        NSRect imageRect = NSMakeRect(0, 0, _imageWidth, _imageHeight);
        CGContextRef ctx = [[NSGraphicsContext currentContext] CGContext];
        CGContextDrawImage(ctx, imageRect, _displayImage);
    }

    // Draw rubber-band preview during drag
    if (_isDragging) {
        CGFloat x0 = fmin(_dragStart.x, _dragCurrent.x);
        CGFloat y0 = fmin(_dragStart.y, _dragCurrent.y);
        CGFloat w = fabs(_dragCurrent.x - _dragStart.x);
        CGFloat h = fabs(_dragCurrent.y - _dragStart.y);
        NSRect previewRect = NSMakeRect(x0, y0, w, h);

        // Color from toolColor
        CGFloat r = ((_toolColor >> 24) & 0xFF) / 255.0;
        CGFloat g = ((_toolColor >> 16) & 0xFF) / 255.0;
        CGFloat b = ((_toolColor >> 8) & 0xFF) / 255.0;
        CGFloat a = (_toolColor & 0xFF) / 255.0;
        NSColor *color = [NSColor colorWithRed:r green:g blue:b alpha:a];

        switch (_currentTool) {
            case EDITOR_TOOL_RECT: {
                NSBezierPath *path = [NSBezierPath bezierPathWithRect:previewRect];
                [color set];
                [path setLineWidth:_toolSize];
                [path stroke];
                break;
            }
            case EDITOR_TOOL_ARROW: {
                NSBezierPath *line = [NSBezierPath bezierPath];
                [line moveToPoint:_dragStart];
                [line lineToPoint:_dragCurrent];
                [color set];
                [line setLineWidth:_toolSize];
                [line stroke];

                // Draw arrowhead
                CGFloat angle = atan2(_dragCurrent.y - _dragStart.y, _dragCurrent.x - _dragStart.x);
                CGFloat headLen = 15.0;
                NSPoint p1 = NSMakePoint(
                    _dragCurrent.x - headLen * cos(angle - M_PI/6),
                    _dragCurrent.y - headLen * sin(angle - M_PI/6)
                );
                NSPoint p2 = NSMakePoint(
                    _dragCurrent.x - headLen * cos(angle + M_PI/6),
                    _dragCurrent.y - headLen * sin(angle + M_PI/6)
                );
                NSBezierPath *head = [NSBezierPath bezierPath];
                [head moveToPoint:_dragCurrent];
                [head lineToPoint:p1];
                [head moveToPoint:_dragCurrent];
                [head lineToPoint:p2];
                [head setLineWidth:_toolSize];
                [head stroke];
                break;
            }
            case EDITOR_TOOL_BLUR:
            case EDITOR_TOOL_HIGHLIGHT: {
                // Dashed outline preview
                NSBezierPath *path = [NSBezierPath bezierPathWithRect:previewRect];
                CGFloat dashPattern[] = {4, 4};
                [path setLineDash:dashPattern count:2 phase:0];
                [[NSColor colorWithWhite:1.0 alpha:0.7] set];
                [path setLineWidth:1.5];
                [path stroke];
                break;
            }
            default: break;
        }
    }
}

- (void)mouseDown:(NSEvent *)event {
    NSPoint loc = [self convertPoint:event.locationInWindow fromView:nil];
    _dragStart = loc;
    _dragCurrent = loc;
    _isDragging = YES;
    [self setNeedsDisplay:YES];
}

- (void)mouseDragged:(NSEvent *)event {
    _dragCurrent = [self convertPoint:event.locationInWindow fromView:nil];
    [self setNeedsDisplay:YES];
}

- (void)mouseUp:(NSEvent *)event {
    _dragCurrent = [self convertPoint:event.locationInWindow fromView:nil];
    _isDragging = NO;

    // Call back to Zig with the tool and coordinates
    if (_toolCallback) {
        _toolCallback(
            _currentTool,
            (int32_t)_dragStart.x, (int32_t)_dragStart.y,
            (int32_t)_dragCurrent.x, (int32_t)_dragCurrent.y
        );
    }
    [self setNeedsDisplay:YES];
}

- (void)keyDown:(NSEvent *)event {
    NSEventModifierFlags flags = event.modifierFlags;
    BOOL cmd = (flags & NSEventModifierFlagCommand) != 0;
    BOOL shift = (flags & NSEventModifierFlagShift) != 0;
    uint16_t kc = event.keyCode;

    // --- Modifier shortcuts ---

    // Cmd+Z = undo, Cmd+Shift+Z = redo
    if (kc == 6 && cmd) { // 'z'
        if (shift) {
            if (_actionCallback) _actionCallback(EDITOR_ACTION_REDO, "");
        } else {
            if (_actionCallback) _actionCallback(EDITOR_ACTION_UNDO, "");
        }
        return;
    }

    // Cmd+C = copy
    if (kc == 8 && cmd) { // 'c'
        if (_actionCallback) _actionCallback(EDITOR_ACTION_COPY, "");
        return;
    }

    // Cmd+S = save (triggers save via callback, ObjC controller handles NSSavePanel)
    if (kc == 1 && cmd) { // 's'
        if (_actionCallback) _actionCallback(EDITOR_ACTION_SAVE, "");
        return;
    }

    // Cmd+W = close editor
    if (kc == 13 && cmd) { // 'w'
        if (_actionCallback) _actionCallback(EDITOR_ACTION_CLOSE, "");
        return;
    }

    // ESC = cancel current drag, or close editor
    if (kc == 53) {
        if (_isDragging) {
            _isDragging = NO;
            [self setNeedsDisplay:YES];
        } else {
            if (_actionCallback) _actionCallback(EDITOR_ACTION_CLOSE, "");
        }
        return;
    }

    // --- Tool letter shortcuts (no modifiers) ---
    if (!cmd && !shift) {
        switch (kc) {
            case 0:  _currentTool = EDITOR_TOOL_ARROW; break;      // 'a'
            case 15: _currentTool = EDITOR_TOOL_RECT; break;       // 'r'
            case 11: _currentTool = EDITOR_TOOL_BLUR; break;       // 'b'
            case 4:  _currentTool = EDITOR_TOOL_HIGHLIGHT; break;  // 'h'
            case 17: _currentTool = EDITOR_TOOL_TEXT; break;        // 't'
            case 14: _currentTool = EDITOR_TOOL_NUMBERING; break;  // 'e' (ellipse)
            default: [super keyDown:event]; return;
        }
        [self setNeedsDisplay:YES];
        return;
    }

    [super keyDown:event];
}

@end

// The editor window controller holds all the state together
@interface ZigShotEditorController : NSObject
@property (nonatomic, strong) NSWindow *window;
@property (nonatomic, strong) ZigShotEditorView *editorView;
@property (nonatomic, strong) NSScrollView *scrollView;
@property (nonatomic) EditorActionCallback actionCallback;
@end

@implementation ZigShotEditorController

- (instancetype)initWithPixels:(const uint8_t *)pixels
                         width:(uint32_t)w height:(uint32_t)h
                    toolCallback:(EditorToolCallback)tcb
                  actionCallback:(EditorActionCallback)acb {
    self = [super init];
    if (self) {
        _actionCallback = acb;

        // Calculate window size: fit image up to 80% of screen
        NSRect screenFrame = [[NSScreen mainScreen] visibleFrame];
        CGFloat maxW = screenFrame.size.width * 0.8;
        CGFloat maxH = screenFrame.size.height * 0.8;
        CGFloat scale = fmin(maxW / w, maxH / h);
        if (scale > 1.0) scale = 1.0;
        CGFloat winW = fmax(w * scale, 500);
        CGFloat winH = fmax(h * scale, 400) + 80; // +80 for toolbar

        CGFloat winX = screenFrame.origin.x + (screenFrame.size.width - winW) / 2;
        CGFloat winY = screenFrame.origin.y + (screenFrame.size.height - winH) / 2;

        _window = [[NSWindow alloc]
            initWithContentRect:NSMakeRect(winX, winY, winW, winH)
                      styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable |
                                NSWindowStyleMaskResizable | NSWindowStyleMaskMiniaturizable
                        backing:NSBackingStoreBuffered
                          defer:NO];
        [_window setTitle:@"ZigShot — Annotate"];
        [_window setMinSize:NSMakeSize(400, 300)];

        // Create content view with toolbar at top
        NSView *contentView = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, winW, winH)];

        // Toolbar
        NSStackView *toolbar = [self createToolbarWithWidth:winW];
        toolbar.frame = NSMakeRect(0, winH - 80, winW, 44);
        toolbar.autoresizingMask = NSViewWidthSizable | NSViewMinYMargin;
        [contentView addSubview:toolbar];

        // Bottom action bar
        NSStackView *actionBar = [self createActionBar];
        actionBar.frame = NSMakeRect(0, 0, winW, 36);
        actionBar.autoresizingMask = NSViewWidthSizable | NSViewMaxYMargin;
        [contentView addSubview:actionBar];

        // Scroll view containing the editor
        _editorView = [[ZigShotEditorView alloc] initWithPixels:pixels
                                                           width:w height:h
                                                      toolCallback:tcb
                                                    actionCallback:acb];

        _scrollView = [[NSScrollView alloc] initWithFrame:NSMakeRect(0, 36, winW, winH - 80 - 36)];
        _scrollView.documentView = _editorView;
        _scrollView.hasVerticalScroller = YES;
        _scrollView.hasHorizontalScroller = YES;
        _scrollView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
        _scrollView.backgroundColor = [NSColor colorWithWhite:0.15 alpha:1.0];
        [contentView addSubview:_scrollView];

        [_window setContentView:contentView];
        [_window makeKeyAndOrderFront:nil];
        [NSApp activateIgnoringOtherApps:YES];
    }
    return self;
}

- (NSStackView *)createToolbarWithWidth:(CGFloat)width {
    NSButton *arrowBtn = [self toolButton:@"arrow.up.right" tag:EDITOR_TOOL_ARROW tooltip:@"Arrow"];
    NSButton *rectBtn = [self toolButton:@"rectangle" tag:EDITOR_TOOL_RECT tooltip:@"Rectangle"];
    NSButton *blurBtn = [self toolButton:@"eye.slash" tag:EDITOR_TOOL_BLUR tooltip:@"Blur"];
    NSButton *highlightBtn = [self toolButton:@"highlighter" tag:EDITOR_TOOL_HIGHLIGHT tooltip:@"Highlight"];
    NSButton *textBtn = [self toolButton:@"textformat" tag:EDITOR_TOOL_TEXT tooltip:@"Text"];
    NSButton *numBtn = [self toolButton:@"number.circle" tag:EDITOR_TOOL_NUMBERING tooltip:@"Numbering"];

    NSStackView *stack = [NSStackView stackViewWithViews:@[arrowBtn, rectBtn, blurBtn, highlightBtn, textBtn, numBtn]];
    stack.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    stack.spacing = 4;
    stack.alignment = NSLayoutAttributeCenterY;

    // Wrap in a background view
    NSView *bg = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, width, 44)];
    bg.wantsLayer = YES;
    bg.layer.backgroundColor = [[NSColor colorWithWhite:0.18 alpha:1.0] CGColor];

    stack.translatesAutoresizingMaskIntoConstraints = NO;
    [bg addSubview:stack];
    [NSLayoutConstraint activateConstraints:@[
        [stack.centerXAnchor constraintEqualToAnchor:bg.centerXAnchor],
        [stack.centerYAnchor constraintEqualToAnchor:bg.centerYAnchor],
    ]];

    // Wrap bg in a stack so it plays nice with layout
    NSStackView *outer = [NSStackView stackViewWithViews:@[bg]];
    [bg.widthAnchor constraintEqualToAnchor:outer.widthAnchor].active = YES;
    [bg.heightAnchor constraintEqualToConstant:44].active = YES;
    return outer;
}

- (NSButton *)toolButton:(NSString *)symbolName tag:(NSInteger)tag tooltip:(NSString *)tooltip {
    NSImage *img = [NSImage imageWithSystemSymbolName:symbolName accessibilityDescription:tooltip];
    NSButton *btn = [NSButton buttonWithImage:img target:self action:@selector(toolSelected:)];
    btn.bordered = NO;
    btn.tag = tag;
    btn.toolTip = tooltip;
    btn.contentTintColor = [NSColor whiteColor];
    btn.translatesAutoresizingMaskIntoConstraints = NO;
    [btn.widthAnchor constraintEqualToConstant:36].active = YES;
    [btn.heightAnchor constraintEqualToConstant:36].active = YES;
    return btn;
}

- (void)toolSelected:(NSButton *)sender {
    _editorView.currentTool = (int)sender.tag;
}

- (NSStackView *)createActionBar {
    NSButton *copyBtn = [NSButton buttonWithTitle:@"Copy" target:self action:@selector(copyAction:)];
    NSButton *saveBtn = [NSButton buttonWithTitle:@"Save" target:self action:@selector(saveAction:)];
    NSButton *undoBtn = [NSButton buttonWithTitle:@"Undo" target:self action:@selector(undoAction:)];

    undoBtn.keyEquivalent = @"z";
    undoBtn.keyEquivalentModifierMask = NSEventModifierFlagCommand;

    NSStackView *bar = [NSStackView stackViewWithViews:@[undoBtn, [NSView new], copyBtn, saveBtn]];
    bar.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    bar.spacing = 8;
    bar.edgeInsets = NSEdgeInsetsMake(4, 12, 4, 12);
    return bar;
}

- (void)copyAction:(id)sender {
    if (_actionCallback) _actionCallback(1, ""); // 1 = copy
}

- (void)saveAction:(id)sender {
    NSSavePanel *panel = [NSSavePanel savePanel];
    panel.allowedContentTypes = @[[UTType typeWithFilenameExtension:@"png"]];
    panel.nameFieldStringValue = @"annotated.png";
    if ([panel runModal] == NSModalResponseOK) {
        if (_actionCallback) _actionCallback(2, panel.URL.path.UTF8String); // 2 = save
    }
}

- (void)undoAction:(id)sender {
    if (_actionCallback) _actionCallback(3, ""); // 3 = undo
}

@end

// Global editor controller (retained to prevent ARC dealloc)
static ZigShotEditorController *g_editor = nil;

EditorHandle appkit_open_editor(const uint8_t* pixels,
                                 uint32_t width, uint32_t height,
                                 EditorToolCallback tool_cb,
                                 EditorActionCallback action_cb) {
    @autoreleasepool {
        // Close any existing editor
        appkit_editor_close((__bridge void *)g_editor);

        g_editor = [[ZigShotEditorController alloc] initWithPixels:pixels
                                                              width:width height:height
                                                         toolCallback:tool_cb
                                                       actionCallback:action_cb];
        return (__bridge void *)g_editor;
    }
}

void appkit_editor_update_image(EditorHandle handle,
                                 const uint8_t* pixels,
                                 uint32_t width, uint32_t height) {
    @autoreleasepool {
        ZigShotEditorController *editor = (__bridge ZigShotEditorController *)handle;
        [editor.editorView updatePixels:pixels width:width height:height];
    }
}

void appkit_editor_close(EditorHandle handle) {
    if (handle && g_editor) {
        [g_editor.window close];
        g_editor = nil;
    }
}

void appkit_editor_set_color(EditorHandle handle, uint32_t rgba) {
    if (handle) {
        ZigShotEditorController *editor = (__bridge ZigShotEditorController *)handle;
        editor.editorView.toolColor = rgba;
    }
}

void appkit_editor_set_size(EditorHandle handle, float size) {
    if (handle) {
        ZigShotEditorController *editor = (__bridge ZigShotEditorController *)handle;
        editor.editorView.toolSize = size;
    }
}

// ============================================================================
// Text Rendering via CoreText
// ============================================================================

uint8_t* appkit_render_text(const char* text, float font_size,
                             uint32_t color_rgba,
                             uint32_t* out_width, uint32_t* out_height) {
    @autoreleasepool {
        NSString *str = [NSString stringWithUTF8String:text];
        if (!str || str.length == 0) return NULL;

        // Parse color from RGBA packed uint32
        CGFloat r = ((color_rgba >> 24) & 0xFF) / 255.0;
        CGFloat g = ((color_rgba >> 16) & 0xFF) / 255.0;
        CGFloat b = ((color_rgba >> 8) & 0xFF) / 255.0;
        CGFloat a = (color_rgba & 0xFF) / 255.0;
        NSColor *color = [NSColor colorWithRed:r green:g blue:b alpha:a];

        // Create attributed string
        NSDictionary *attrs = @{
            NSFontAttributeName: [NSFont systemFontOfSize:font_size weight:NSFontWeightMedium],
            NSForegroundColorAttributeName: color,
        };

        // Measure the text
        NSSize textSize = [str sizeWithAttributes:attrs];
        uint32_t w = (uint32_t)ceil(textSize.width) + 4; // +4 for padding
        uint32_t h = (uint32_t)ceil(textSize.height) + 4;
        if (w < 1 || h < 1) return NULL;

        // Create RGBA bitmap context
        uint8_t *buffer = (uint8_t *)calloc(w * h * 4, 1);
        if (!buffer) return NULL;

        CGColorSpaceRef cs = CGColorSpaceCreateDeviceRGB();
        CGContextRef ctx = CGBitmapContextCreate(
            buffer, w, h, 8, w * 4, cs,
            kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big
        );
        CGColorSpaceRelease(cs);
        if (!ctx) { free(buffer); return NULL; }

        // Flip context (CoreGraphics has origin at bottom-left)
        CGContextTranslateCTM(ctx, 0, h);
        CGContextScaleCTM(ctx, 1.0, -1.0);

        // Draw text
        NSGraphicsContext *nsCtx = [NSGraphicsContext graphicsContextWithCGContext:ctx flipped:YES];
        [NSGraphicsContext saveGraphicsState];
        [NSGraphicsContext setCurrentContext:nsCtx];

        [str drawAtPoint:NSMakePoint(2, 2) withAttributes:attrs];

        [NSGraphicsContext restoreGraphicsState];
        CGContextRelease(ctx);

        *out_width = w;
        *out_height = h;
        return buffer;
    }
}

void appkit_free_text_buffer(uint8_t* buffer) {
    if (buffer) free(buffer);
}

// ============================================================================
// Screen Recording via ScreenCaptureKit + AVAssetWriter
// ============================================================================

API_AVAILABLE(macos(12.3))
@interface ZigShotRecorder : NSObject <SCStreamOutput>
@property (nonatomic, strong) SCStream *stream;
@property (nonatomic, strong) AVAssetWriter *assetWriter;
@property (nonatomic, strong) AVAssetWriterInput *videoInput;
@property (nonatomic) BOOL isRecording;
@property (nonatomic, copy) NSString *outputPath;
@property (nonatomic, copy) NSString *format;
@property (nonatomic) RecordingStatusCallback statusCallback;
@property (nonatomic) CMTime lastTimestamp;
@property (nonatomic) BOOL firstFrame;
// For GIF recording
@property (nonatomic, strong) NSMutableArray *gifFrames;
@property (nonatomic) uint32_t gifFps;
@end

API_AVAILABLE(macos(12.3))
@implementation ZigShotRecorder

- (void)startWithX:(int32_t)x y:(int32_t)y
              width:(uint32_t)width height:(uint32_t)height
         outputPath:(NSString *)path format:(NSString *)fmt
                fps:(uint32_t)fps callback:(RecordingStatusCallback)cb {
    _statusCallback = cb;
    _outputPath = path;
    _format = fmt;
    _isRecording = NO;
    _firstFrame = YES;
    _gifFps = fps;

    // Get all shareable content (displays, windows)
    [SCShareableContent getShareableContentWithCompletionHandler:^(SCShareableContent *content, NSError *error) {
        if (error || !content.displays.count) {
            if (self.statusCallback) self.statusCallback(RECORDING_STATUS_ERROR, "Failed to get shareable content");
            return;
        }

        SCDisplay *display = content.displays.firstObject;

        // Create content filter for the display
        SCContentFilter *filter = [[SCContentFilter alloc] initWithDisplay:display
                                                         excludingWindows:@[]];

        // Configure the stream
        SCStreamConfiguration *config = [[SCStreamConfiguration alloc] init];
        config.width = width;
        config.height = height;
        config.minimumFrameInterval = CMTimeMake(1, fps);
        config.pixelFormat = kCVPixelFormatType_32BGRA;

        // Set source rect for area capture
        config.sourceRect = CGRectMake(x, y, width, height);
        config.scalesToFit = YES;

        // Set up video output
        if ([fmt isEqualToString:@"mp4"]) {
            [self setupMP4WriterWithWidth:width height:height path:path];
        } else {
            self.gifFrames = [NSMutableArray new];
        }

        // Create and start the stream
        self.stream = [[SCStream alloc] initWithFilter:filter configuration:config delegate:nil];

        NSError *addErr = nil;
        [self.stream addStreamOutput:self type:SCStreamOutputTypeScreen
                      sampleHandlerQueue:dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0)
                                   error:&addErr];
        if (addErr) {
            if (self.statusCallback) self.statusCallback(RECORDING_STATUS_ERROR, addErr.localizedDescription.UTF8String);
            return;
        }

        [self.stream startCaptureWithCompletionHandler:^(NSError *startErr) {
            if (startErr) {
                if (self.statusCallback) self.statusCallback(RECORDING_STATUS_ERROR, startErr.localizedDescription.UTF8String);
                return;
            }
            self.isRecording = YES;
            if (self.statusCallback) self.statusCallback(RECORDING_STATUS_STARTED, path.UTF8String);
        }];
    }];
}

- (void)setupMP4WriterWithWidth:(uint32_t)w height:(uint32_t)h path:(NSString *)path {
    NSURL *url = [NSURL fileURLWithPath:path];
    // Remove existing file
    [[NSFileManager defaultManager] removeItemAtURL:url error:nil];

    NSError *err = nil;
    _assetWriter = [[AVAssetWriter alloc] initWithURL:url fileType:AVFileTypeMPEG4 error:&err];
    if (err) return;

    NSDictionary *settings = @{
        AVVideoCodecKey: AVVideoCodecTypeH264,
        AVVideoWidthKey: @(w),
        AVVideoHeightKey: @(h),
        AVVideoCompressionPropertiesKey: @{
            AVVideoAverageBitRateKey: @(w * h * 4), // reasonable bitrate
            AVVideoMaxKeyFrameIntervalKey: @30,
        },
    };
    _videoInput = [AVAssetWriterInput assetWriterInputWithMediaType:AVMediaTypeVideo outputSettings:settings];
    _videoInput.expectsMediaDataInRealTime = YES;

    if ([_assetWriter canAddInput:_videoInput]) {
        [_assetWriter addInput:_videoInput];
    }
    [_assetWriter startWriting];
    [_assetWriter startSessionAtSourceTime:kCMTimeZero];
}

- (void)stream:(SCStream *)stream didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer ofType:(SCStreamOutputType)type {
    if (!_isRecording || type != SCStreamOutputTypeScreen) return;
    if (!CMSampleBufferIsValid(sampleBuffer)) return;

    if ([_format isEqualToString:@"mp4"]) {
        if (_videoInput.isReadyForMoreMediaData) {
            if (_firstFrame) {
                _firstFrame = NO;
            }
            [_videoInput appendSampleBuffer:sampleBuffer];
        }
    } else {
        // GIF: extract CGImage from sample buffer
        CVImageBufferRef imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer);
        if (!imageBuffer) return;

        CIImage *ciImage = [CIImage imageWithCVImageBuffer:imageBuffer];
        CIContext *ciCtx = [CIContext context];
        CGImageRef cgImage = [ciCtx createCGImage:ciImage fromRect:ciImage.extent];
        if (cgImage) {
            @synchronized (self.gifFrames) {
                [self.gifFrames addObject:(__bridge id)cgImage];
            }
            CGImageRelease(cgImage);
        }
    }
}

- (void)stop {
    if (!_isRecording) return;
    _isRecording = NO;

    [_stream stopCaptureWithCompletionHandler:^(NSError *err) {
        if ([self.format isEqualToString:@"mp4"]) {
            [self.videoInput markAsFinished];
            [self.assetWriter finishWritingWithCompletionHandler:^{
                if (self.statusCallback) {
                    self.statusCallback(RECORDING_STATUS_STOPPED, self.outputPath.UTF8String);
                }
            }];
        } else {
            // Write GIF
            [self writeGIF];
            if (self.statusCallback) {
                self.statusCallback(RECORDING_STATUS_STOPPED, self.outputPath.UTF8String);
            }
        }
    }];
}

- (void)writeGIF {
    @synchronized (self.gifFrames) {
        if (self.gifFrames.count == 0) return;

        NSURL *url = [NSURL fileURLWithPath:_outputPath];
        CGImageDestinationRef dest = CGImageDestinationCreateWithURL(
            (__bridge CFURLRef)url,
            (__bridge CFStringRef)UTTypeGIF.identifier,
            self.gifFrames.count,
            NULL
        );
        if (!dest) return;

        // GIF properties: loop forever
        NSDictionary *gifProps = @{
            (__bridge NSString *)kCGImagePropertyGIFDictionary: @{
                (__bridge NSString *)kCGImagePropertyGIFLoopCount: @0,
            }
        };
        CGImageDestinationSetProperties(dest, (__bridge CFDictionaryRef)gifProps);

        // Frame delay
        float delay = 1.0 / _gifFps;
        NSDictionary *frameProps = @{
            (__bridge NSString *)kCGImagePropertyGIFDictionary: @{
                (__bridge NSString *)kCGImagePropertyGIFDelayTime: @(delay),
            }
        };

        for (id frame in self.gifFrames) {
            CGImageRef img = (__bridge CGImageRef)frame;
            CGImageDestinationAddImage(dest, img, (__bridge CFDictionaryRef)frameProps);
        }

        CGImageDestinationFinalize(dest);
        CFRelease(dest);
    }
}

@end

static ZigShotRecorder *g_recorder API_AVAILABLE(macos(12.3)) = nil;

void appkit_start_recording(int32_t x, int32_t y, uint32_t width, uint32_t height,
                            const char* output_path, const char* format,
                            uint32_t fps, RecordingStatusCallback callback) {
    if (@available(macOS 12.3, *)) {
        @autoreleasepool {
            if (g_recorder && g_recorder.isRecording) {
                appkit_stop_recording();
            }
            g_recorder = [[ZigShotRecorder alloc] init];
            [g_recorder startWithX:x y:y width:width height:height
                        outputPath:[NSString stringWithUTF8String:output_path]
                            format:[NSString stringWithUTF8String:format]
                               fps:fps
                          callback:callback];
        }
    } else {
        if (callback) callback(RECORDING_STATUS_ERROR, "Screen recording requires macOS 12.3+");
    }
}

void appkit_stop_recording(void) {
    if (@available(macOS 12.3, *)) {
        if (g_recorder) {
            [g_recorder stop];
        }
    }
}

bool appkit_is_recording(void) {
    if (@available(macOS 12.3, *)) {
        return g_recorder && g_recorder.isRecording;
    }
    return false;
}
