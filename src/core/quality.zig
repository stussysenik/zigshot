//! Export quality and format configuration.
//!
//! These types define HOW an image gets exported — format, quality level,
//! DPI, and color profile embedding. On macOS, Swift reads these values
//! and passes them to ImageIO. On Linux (future), Zig-native encoders
//! will consume them directly.

const std = @import("std");

/// Supported export formats.
pub const Format = enum {
    png,
    jpeg,
    webp,
    tiff,
    heif,
};

/// Configuration for image export.
///
/// Smart defaults: PNG at 144 DPI with sRGB ICC profile.
/// Quality field only applies to lossy formats (JPEG, WebP, lossy HEIF).
pub const ExportConfig = struct {
    format: Format = .png,
    /// 0.0 (worst) to 1.0 (best). Only used for lossy formats.
    quality: f32 = 0.92,
    /// Dots per inch. 72 = 1x, 144 = 2x Retina, 216 = 3x.
    dpi: u32 = 144,
    /// Embed sRGB ICC color profile in output.
    embed_color_profile: bool = true,
    /// Strip EXIF/location metadata for privacy.
    strip_metadata: bool = false,
};

// ============================================================================
// Tests
// ============================================================================

test "ExportConfig: defaults are sane" {
    const config = ExportConfig{};
    try std.testing.expectEqual(Format.png, config.format);
    try std.testing.expectApproxEqAbs(@as(f32, 0.92), config.quality, 0.001);
    try std.testing.expectEqual(@as(u32, 144), config.dpi);
    try std.testing.expect(config.embed_color_profile);
    try std.testing.expect(!config.strip_metadata);
}

test "ExportConfig: custom JPEG config" {
    const config = ExportConfig{
        .format = .jpeg,
        .quality = 0.85,
        .dpi = 72,
        .strip_metadata = true,
    };
    try std.testing.expectEqual(Format.jpeg, config.format);
    try std.testing.expectApproxEqAbs(@as(f32, 0.85), config.quality, 0.001);
    try std.testing.expectEqual(@as(u32, 72), config.dpi);
    try std.testing.expect(config.strip_metadata);
}

test "Format: all variants exist" {
    // Compile-time check that all expected variants are present
    const formats = [_]Format{ .png, .jpeg, .webp, .tiff, .heif };
    try std.testing.expectEqual(@as(usize, 5), formats.len);
}
