#ifndef CVIPS_SHIM_H
#define CVIPS_SHIM_H

#include <stddef.h>

/*
 * Swift cannot call libvips' C API directly: nearly every vips_* save/load
 * operation is a variadic "name, value, ..., NULL" property list (the same
 * convention NetVips' C# binding hides on Windows), and Swift's C interop
 * only supports printf-style homogeneous variadics, not this heterogeneous
 * GObject-property convention. Every operation this app needs gets a fixed-
 * signature wrapper here instead, matching CompressionEngine.cs's calls
 * 1:1 (same option names, same values) so output is byte-for-byte the same
 * shape as the Windows build's.
 *
 * Image handles cross into Swift as opaque `void *` (not `VipsImage *`) on
 * purpose: VipsImage's full struct definition drags in GLib/GObject
 * internals that Swift's Clang importer has no reason to see, so every
 * function here casts internally in the .c file, which is the only place
 * <vips/vips.h> is included.
 */

typedef void *cvips_image_t;

int cvips_init(const char *argv0);
const char *cvips_error_buffer(void);
void cvips_error_clear(void);
void cvips_unref(cvips_image_t image);

/* Image.Thumbnail(path, boxW, height: boxH, size: Down, outputProfile: "srgb") */
cvips_image_t cvips_thumbnail_file(const char *filename, int width, int height);

/* image.ThumbnailImage(width, height: height, size: Down) */
cvips_image_t cvips_thumbnail_image(cvips_image_t in, int width, int height);

/* Raw decoded pixels (from ImageIO's HEIC decode) -> vips image, sRGB tagged. */
cvips_image_t cvips_image_from_srgb_buffer(const unsigned char *data, size_t len,
                                            int width, int height, int bands);

int cvips_get_n_pages(cvips_image_t image);
int cvips_has_alpha(cvips_image_t image);
cvips_image_t cvips_flatten_white(cvips_image_t in);

/* JPEG: mozjpeg-tuned save matching Presets.Jpeg + CompressionEngine.Save. */
int cvips_jpegsave_mozjpeg(cvips_image_t in, const char *filename, int q, int subsample_on);
/* Fallback if the bundled libvips ever lacks mozjpeg (baseline flags only). */
int cvips_jpegsave_baseline(cvips_image_t in, const char *filename, int q, int subsample_on);

/* PNG: palette+dither (Balanced/Smallest) or lossless (High). */
int cvips_pngsave_palette(cvips_image_t in, const char *filename, int q, double dither, int effort);
int cvips_pngsave_lossless(cvips_image_t in, const char *filename);

/* WebP: smart-subsample photo preset. */
int cvips_webpsave(cvips_image_t in, const char *filename, int q, int effort, int alpha_q);

int cvips_image_get_width(cvips_image_t image);
int cvips_image_get_height(cvips_image_t image);

/* Plain (non-variadic) vips globals — Swift could call the real ones
   directly, but routing through here keeps all vips.h exposure in one file. */
void cvips_set_concurrency(int concurrency);
void cvips_set_cache_max(int max);

#endif
