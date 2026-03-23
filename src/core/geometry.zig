//! Geometry primitives — where all spatial math in ZigShot lives.
//!
//! Think of these as JS plain objects like `{ x, y }` or `{ width, height }`,
//! except for one massive difference: they're VALUE types, not references.
//!
//!   const a = Point{ .x = 1, .y = 2 };
//!   const b = a;  // COPY. b is a completely independent value.
//!   // In JS: const b = a would share the same reference.
//!   // In Zig: b gets its own stack copy. No aliasing. No surprises.
//!
//! This is fast for small types (a Point is just 8 bytes — two i32s) and
//! eliminates an entire class of "who mutated my object?" bugs.

const std = @import("std");

/// A 2D point with integer coordinates (pixel space).
pub const Point = struct {
    x: i32,
    y: i32,

    pub const zero = Point{ .x = 0, .y = 0 };

    pub fn eql(self: Point, other: Point) bool {
        return self.x == other.x and self.y == other.y;
    }

    /// Distance between two points (Euclidean).
    ///
    /// In JS, `Math.sqrt((a.x - b.x) ** 2 + ...)` just works because JS
    /// silently coerces integers to floats. Zig refuses to do that.
    /// `@floatFromInt` is your explicit "yes, I know I'm converting an
    /// integer to a float." Annoying at first, lifesaving in a codebase
    /// with 10 different numeric types flying around.
    pub fn distanceTo(self: Point, other: Point) f64 {
        const dx: f64 = @floatFromInt(self.x - other.x);
        const dy: f64 = @floatFromInt(self.y - other.y);
        return @sqrt(dx * dx + dy * dy);
    }
};

/// A 2D size with unsigned dimensions.
pub const Size = struct {
    width: u32,
    height: u32,

    pub const zero = Size{ .width = 0, .height = 0 };

    pub fn eql(self: Size, other: Size) bool {
        return self.width == other.width and self.height == other.height;
    }

    pub fn area(self: Size) u64 {
        return @as(u64, self.width) * @as(u64, self.height);
    }
};

/// A rectangle defined by origin (top-left) and size.
///
/// LEARNING NOTE — Tagged vs plain structs:
/// This is a plain struct (all fields always present). Later, we'll see
/// tagged unions (like Annotation) where only one variant is active.
/// Choose plain structs when all fields are always meaningful.
pub const Rect = struct {
    x: i32,
    y: i32,
    width: u32,
    height: u32,

    pub fn init(x: i32, y: i32, width: u32, height: u32) Rect {
        return .{ .x = x, .y = y, .width = width, .height = height };
    }

    pub fn origin(self: Rect) Point {
        return .{ .x = self.x, .y = self.y };
    }

    pub fn size(self: Rect) Size {
        return .{ .width = self.width, .height = self.height };
    }

    /// Right edge x coordinate.
    pub fn right(self: Rect) i32 {
        return self.x + @as(i32, @intCast(self.width));
    }

    /// Bottom edge y coordinate.
    pub fn bottom(self: Rect) i32 {
        return self.y + @as(i32, @intCast(self.height));
    }

    /// Check if a point is inside this rectangle.
    pub fn contains(self: Rect, point: Point) bool {
        return point.x >= self.x and point.x < self.right() and
            point.y >= self.y and point.y < self.bottom();
    }

    /// Compute the intersection of two rectangles.
    /// Returns null if they don't overlap.
    ///
    /// Classic AABB (axis-aligned bounding box) overlap test — the same
    /// Math.max/Math.min logic you'd write in a 2D game engine. Take the
    /// max of the lefts, min of the rights. If they cross, no overlap.
    /// If you've ever done collision detection in a Canvas game, this is it.
    pub fn intersection(self: Rect, other: Rect) ?Rect {
        const ix = @max(self.x, other.x);
        const iy = @max(self.y, other.y);
        const ir = @min(self.right(), other.right());
        const ib = @min(self.bottom(), other.bottom());

        if (ix >= ir or iy >= ib) return null;

        return Rect{
            .x = ix,
            .y = iy,
            .width = @intCast(ir - ix),
            .height = @intCast(ib - iy),
        };
    }

    /// Clamp this rect to fit within bounds (0,0,max_w,max_h).
    ///
    /// Reuse over reimplementation: clamping IS intersection with the
    /// bounding rect. No need for four separate Math.min/Math.max calls
    /// when `intersection` already does the work. Elegant delegation.
    pub fn clampTo(self: Rect, max_width: u32, max_height: u32) Rect {
        const bounds = Rect.init(0, 0, max_width, max_height);
        return self.intersection(bounds) orelse Rect.init(0, 0, 0, 0);
    }

    pub fn eql(self: Rect, other: Rect) bool {
        return self.x == other.x and self.y == other.y and
            self.width == other.width and self.height == other.height;
    }

    /// Parse "x,y,w,h" string into a Rect.
    ///
    /// Like JS's `"x,y,w,h".split(",")`, but `splitScalar` returns a lazy
    /// iterator — it walks the string on each `.next()` call instead of
    /// allocating a fresh `[][]const u8` array up front. No heap, no GC,
    /// no garbage. You pull values one at a time, and the iterator dies
    /// on the stack when this function returns.
    pub fn parse(s: []const u8) !Rect {
        var iter = std.mem.splitScalar(u8, s, ',');
        const x_str = iter.next() orelse return error.InvalidRect;
        const y_str = iter.next() orelse return error.InvalidRect;
        const w_str = iter.next() orelse return error.InvalidRect;
        const h_str = iter.next() orelse return error.InvalidRect;

        return Rect{
            .x = std.fmt.parseInt(i32, std.mem.trim(u8, x_str, " "), 10) catch return error.InvalidRect,
            .y = std.fmt.parseInt(i32, std.mem.trim(u8, y_str, " "), 10) catch return error.InvalidRect,
            .width = std.fmt.parseInt(u32, std.mem.trim(u8, w_str, " "), 10) catch return error.InvalidRect,
            .height = std.fmt.parseInt(u32, std.mem.trim(u8, h_str, " "), 10) catch return error.InvalidRect,
        };
    }
};

// ============================================================================
// Tests
// ============================================================================

test "Point: equality and distance" {
    const a = Point{ .x = 0, .y = 0 };
    const b = Point{ .x = 3, .y = 4 };
    try std.testing.expect(!a.eql(b));
    try std.testing.expect(a.eql(Point.zero));
    try std.testing.expectApproxEqAbs(@as(f64, 5.0), a.distanceTo(b), 0.001);
}

test "Size: area calculation" {
    const s = Size{ .width = 1920, .height = 1080 };
    try std.testing.expectEqual(@as(u64, 2073600), s.area());
}

test "Rect: contains point" {
    const r = Rect.init(10, 20, 100, 50);
    try std.testing.expect(r.contains(.{ .x = 10, .y = 20 })); // top-left corner
    try std.testing.expect(r.contains(.{ .x = 50, .y = 40 })); // interior
    try std.testing.expect(!r.contains(.{ .x = 110, .y = 20 })); // right edge (exclusive)
    try std.testing.expect(!r.contains(.{ .x = 9, .y = 20 })); // just outside left
}

test "Rect: intersection" {
    const a = Rect.init(0, 0, 100, 100);
    const b = Rect.init(50, 50, 100, 100);
    const isect = a.intersection(b).?;
    try std.testing.expect(isect.eql(Rect.init(50, 50, 50, 50)));

    // Non-overlapping
    const c = Rect.init(200, 200, 50, 50);
    try std.testing.expectEqual(a.intersection(c), null);
}

test "Rect: clampTo bounds" {
    const r = Rect.init(-10, -10, 100, 100);
    const clamped = r.clampTo(50, 50);
    try std.testing.expect(clamped.eql(Rect.init(0, 0, 50, 50)));
}

test "Rect: parse string" {
    const r = try Rect.parse("100,200,800,600");
    try std.testing.expect(r.eql(Rect.init(100, 200, 800, 600)));

    const r2 = try Rect.parse("0, 0, 1920, 1080");
    try std.testing.expect(r2.eql(Rect.init(0, 0, 1920, 1080)));

    try std.testing.expectError(error.InvalidRect, Rect.parse("100,200"));
    try std.testing.expectError(error.InvalidRect, Rect.parse("abc,def,100,200"));
}

test "Rect: right and bottom edges" {
    const r = Rect.init(10, 20, 100, 50);
    try std.testing.expectEqual(@as(i32, 110), r.right());
    try std.testing.expectEqual(@as(i32, 70), r.bottom());
}
