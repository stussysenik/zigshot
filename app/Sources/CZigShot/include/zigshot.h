/**
 * zigshot.h — C API for libzigshot
 *
 * This header defines the public interface for the ZigShot image processing
 * library. Swift (macOS) and GTK4 (Linux) call these functions via FFI.
 *
 * Usage:
 *   1. Link against libzigshot.a
 *   2. #include "zigshot.h"
 *   3. Create images, apply annotations, read pixels back
 *
 * Memory: All ZsImage* handles are owned by libzigshot. Call
 * zs_image_destroy() when done. Never free() a ZsImage* directly.
 *
 * Colors: Packed as 0xRRGGBBAA (e.g., red = 0xFF0000FF).
 */

#ifndef ZIGSHOT_H
#define ZIGSHOT_H

#include <stdint.h>
#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

/** Opaque image handle. Never dereference — only pass to zs_* functions. */
typedef struct ZsImage ZsImage;

/* ---- Image lifecycle ---- */

/** Create image from raw RGBA pixel buffer (copies data). Returns NULL on failure. */
ZsImage* zs_image_create(const uint8_t* pixels, uint32_t width, uint32_t height, uint32_t stride);

/** Create empty image (transparent black). Returns NULL on failure. */
ZsImage* zs_image_create_empty(uint32_t width, uint32_t height);

/** Free an image and its pixel buffer. */
void zs_image_destroy(ZsImage* img);

/* ---- Pixel access ---- */

/** Get mutable pointer to RGBA pixel data. Valid until zs_image_destroy(). */
uint8_t* zs_image_get_pixels(ZsImage* img);
uint32_t zs_image_get_width(ZsImage* img);
uint32_t zs_image_get_height(ZsImage* img);
uint32_t zs_image_get_stride(ZsImage* img);

/* ---- Annotations (color = 0xRRGGBBAA) ---- */

/** Draw anti-aliased arrow from (x0,y0) to (x1,y1). */
void zs_annotate_arrow(ZsImage* img, int32_t x0, int32_t y0, int32_t x1, int32_t y1, uint32_t color, uint32_t width);

/** Draw rectangle. filled=true fills area, false draws outline. */
void zs_annotate_rect(ZsImage* img, int32_t x, int32_t y, uint32_t w, uint32_t h, uint32_t color, uint32_t width, bool filled);

/** Blur rectangular region (for redaction). Returns false on failure. */
bool zs_annotate_blur(ZsImage* img, int32_t x, int32_t y, uint32_t w, uint32_t h, uint32_t radius);

/** Draw semi-transparent highlight overlay. */
void zs_annotate_highlight(ZsImage* img, int32_t x, int32_t y, uint32_t w, uint32_t h, uint32_t color);

/** Draw anti-aliased line. */
void zs_annotate_line(ZsImage* img, int32_t x0, int32_t y0, int32_t x1, int32_t y1, uint32_t color, uint32_t width);

/** Draw measurement ruler with tick marks. Returns pixel distance. */
double zs_annotate_ruler(ZsImage* img, int32_t x0, int32_t y0, int32_t x1, int32_t y1, uint32_t color, uint32_t width);

/** Draw ellipse outline inside rectangle. */
void zs_annotate_ellipse(ZsImage* img, int32_t x, int32_t y, uint32_t w, uint32_t h, uint32_t color, uint32_t width);

#ifdef __cplusplus
}
#endif

#endif /* ZIGSHOT_H */
