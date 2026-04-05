//! Annotation data model — the MODEL layer of ZigShot's annotation system.
//!
//! Describes WHAT to draw, not HOW. The pipeline handles rendering.
//! This separation lets us serialize annotations, test without rendering,
//! and share between CLI and GUI. Think of it like a Redux store for
//! annotations — pure data, no side effects.
//!
//! Tagged unions:
//! `Annotation` is a tagged union — think TypeScript's discriminated unions
//! (`type Shape = { kind: "circle", r: number } | { kind: "rect", w: number }`)
//! but the compiler actually enforces exhaustive `switch`. Forget a case?
//! Compile error. Not a lint warning. A hard stop.

const std = @import("std");
const geometry = @import("geometry.zig");
const image = @import("image.zig");
const Point = geometry.Point;
const Rect = geometry.Rect;
const Color = image.Color;

/// A single annotation on a screenshot.
pub const Annotation = union(enum) {
    arrow: Arrow,
    rectangle: Rectangle,
    ellipse: Ellipse,
    line: Line,
    text: Text,
    blur_region: BlurRegion,
    highlight: Highlight,
    numbering: Numbering,
    ruler: Ruler,

    // Default values in struct fields work like JS default params:
    // `function draw({ color = "red", width = 3.0 })`. Callers can
    // override any field; anything omitted gets the default.
    pub const Arrow = struct {
        start: Point,
        end: Point,
        color: Color = Color.red,
        width: f32 = 3.0,
        head_size: f32 = 12.0,
    };

    pub const Rectangle = struct {
        rect: Rect,
        color: Color = Color.red,
        width: f32 = 2.0,
        filled: bool = false,
        corner_radius: f32 = 0.0,
    };

    pub const Ellipse = struct {
        rect: Rect, // bounding box
        color: Color = Color.red,
        width: f32 = 2.0,
        filled: bool = false,
    };

    pub const Line = struct {
        start: Point,
        end: Point,
        color: Color = Color.red,
        width: f32 = 2.0,
    };

    pub const Text = struct {
        position: Point,
        content: []const u8,
        font_size: f32 = 16.0,
        color: Color = Color.white,
        background: ?Color = Color{ .r = 0, .g = 0, .b = 0, .a = 200 },
    };

    pub const BlurRegion = struct {
        rect: Rect,
        radius: u32 = 10,
    };

    pub const Highlight = struct {
        rect: Rect,
        color: Color = Color{ .r = 255, .g = 255, .b = 0, .a = 80 }, // semi-transparent yellow
    };

    pub const Numbering = struct {
        position: Point,
        number: u32,
        color: Color = Color.red,
        size: f32 = 24.0,
    };

    pub const Ruler = struct {
        start: Point,
        end: Point,
        color: Color = Color{ .r = 0, .g = 200, .b = 255, .a = 255 }, // cyan
        width: f32 = 1.0,
        tick_size: f32 = 6.0,
    };

    /// Get the bounding rectangle of this annotation.
    ///
    /// Exhaustive switch: the compiler won't let you add a new annotation type
    /// without adding its bounds case here. TypeScript's `never` check at the
    /// end of a switch, but enforced at compile time — no runtime surprise.
    pub fn bounds(self: Annotation) Rect {
        return switch (self) {
            .arrow => |a| {
                const min_x = @min(a.start.x, a.end.x);
                const min_y = @min(a.start.y, a.end.y);
                const max_x = @max(a.start.x, a.end.x);
                const max_y = @max(a.start.y, a.end.y);
                return Rect{
                    .x = min_x,
                    .y = min_y,
                    .width = @intCast(max_x - min_x),
                    .height = @intCast(max_y - min_y),
                };
            },
            .rectangle => |r| r.rect,
            .ellipse => |e| e.rect,
            .line => |l| {
                const min_x = @min(l.start.x, l.end.x);
                const min_y = @min(l.start.y, l.end.y);
                const max_x = @max(l.start.x, l.end.x);
                const max_y = @max(l.start.y, l.end.y);
                return Rect{
                    .x = min_x,
                    .y = min_y,
                    .width = @intCast(max_x - min_x),
                    .height = @intCast(max_y - min_y),
                };
            },
            .text => |t| Rect{ .x = t.position.x, .y = t.position.y, .width = 200, .height = @as(u32, @intFromFloat(t.font_size + 8)) },
            .blur_region => |b| b.rect,
            .highlight => |h| h.rect,
            .numbering => |n| Rect{ .x = n.position.x, .y = n.position.y, .width = @as(u32, @intFromFloat(n.size)), .height = @as(u32, @intFromFloat(n.size)) },
            .ruler => |r| {
                const min_x = @min(r.start.x, r.end.x);
                const min_y = @min(r.start.y, r.end.y);
                const max_x = @max(r.start.x, r.end.x);
                const max_y = @max(r.start.y, r.end.y);
                return Rect{
                    .x = min_x,
                    .y = min_y,
                    .width = @intCast(max_x - min_x),
                    .height = @intCast(max_y - min_y),
                };
            },
        };
    }
};

/// A list of annotations that can be applied to an image.
///
/// JS devs: this is `Annotation[] = []` but with manual memory management.
/// In JS, the garbage collector frees your arrays. Here, YOU must call
/// `.deinit()` when done or the memory leaks. `defer list.deinit()` is
/// your best friend — it's the Zig equivalent of a `finally` block that
/// always cleans up, even if an error propagates.
pub const AnnotationList = struct {
    items: std.ArrayList(Annotation) = .empty,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) AnnotationList {
        return .{ .allocator = allocator };
    }

    pub fn deinit(self: *AnnotationList) void {
        self.items.deinit(self.allocator);
    }

    pub fn add(self: *AnnotationList, ann: Annotation) !void {
        try self.items.append(self.allocator, ann);
    }

    pub fn remove(self: *AnnotationList, index: usize) void {
        _ = self.items.orderedRemove(index);
    }

    pub fn count(self: AnnotationList) usize {
        return self.items.items.len;
    }

    pub fn get(self: AnnotationList, index: usize) ?Annotation {
        if (index >= self.items.items.len) return null;
        return self.items.items[index];
    }

    pub fn clear(self: *AnnotationList) void {
        self.items.clearRetainingCapacity();
    }
};

// ============================================================================
// Tests
// ============================================================================

test "Annotation: arrow bounds" {
    const arrow = Annotation{ .arrow = .{
        .start = .{ .x = 10, .y = 20 },
        .end = .{ .x = 100, .y = 80 },
    } };
    const b = arrow.bounds();
    try std.testing.expectEqual(@as(i32, 10), b.x);
    try std.testing.expectEqual(@as(i32, 20), b.y);
    try std.testing.expectEqual(@as(u32, 90), b.width);
    try std.testing.expectEqual(@as(u32, 60), b.height);
}

test "Annotation: rectangle bounds passthrough" {
    const rect = Annotation{ .rectangle = .{
        .rect = Rect.init(50, 50, 200, 100),
    } };
    try std.testing.expect(rect.bounds().eql(Rect.init(50, 50, 200, 100)));
}

test "AnnotationList: add, count, remove" {
    const allocator = std.testing.allocator;
    var list = AnnotationList.init(allocator);
    defer list.deinit();

    try list.add(.{ .arrow = .{
        .start = .{ .x = 0, .y = 0 },
        .end = .{ .x = 100, .y = 100 },
    } });
    try list.add(.{ .rectangle = .{
        .rect = Rect.init(10, 10, 50, 50),
    } });
    try list.add(.{ .blur_region = .{
        .rect = Rect.init(0, 0, 200, 200),
        .radius = 15,
    } });

    try std.testing.expectEqual(@as(usize, 3), list.count());

    list.remove(1); // remove rectangle
    try std.testing.expectEqual(@as(usize, 2), list.count());

    // First should still be arrow, second should now be blur
    switch (list.get(0).?) {
        .arrow => {},
        else => return error.TestUnexpectedResult,
    }
    switch (list.get(1).?) {
        .blur_region => {},
        else => return error.TestUnexpectedResult,
    }
}

test "Annotation: ruler bounds" {
    const ruler = Annotation{ .ruler = .{
        .start = .{ .x = 50, .y = 100 },
        .end = .{ .x = 200, .y = 100 },
    } };
    const b = ruler.bounds();
    try std.testing.expectEqual(@as(i32, 50), b.x);
    try std.testing.expectEqual(@as(i32, 100), b.y);
    try std.testing.expectEqual(@as(u32, 150), b.width);
    try std.testing.expectEqual(@as(u32, 0), b.height);
}

test "AnnotationList: clear" {
    const allocator = std.testing.allocator;
    var list = AnnotationList.init(allocator);
    defer list.deinit();

    try list.add(.{ .highlight = .{ .rect = Rect.init(0, 0, 100, 100) } });
    try list.add(.{ .highlight = .{ .rect = Rect.init(50, 50, 100, 100) } });
    try std.testing.expectEqual(@as(usize, 2), list.count());

    list.clear();
    try std.testing.expectEqual(@as(usize, 0), list.count());
}
