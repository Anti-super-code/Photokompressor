#include "include/cvips_shim.h"
#include <vips/vips.h>

int cvips_init(const char *argv0) {
    return VIPS_INIT(argv0);
}

const char *cvips_error_buffer(void) {
    return vips_error_buffer();
}

void cvips_error_clear(void) {
    vips_error_clear();
}

void cvips_unref(cvips_image_t image) {
    if (image) g_object_unref(image);
}

cvips_image_t cvips_thumbnail_file(const char *filename, int width, int height) {
    VipsImage *out = NULL;
    if (vips_thumbnail(filename, &out, width,
            "height", height,
            "size", VIPS_SIZE_DOWN,
            "export-profile", "srgb",
            NULL)) {
        return NULL;
    }
    return out;
}

cvips_image_t cvips_thumbnail_image(cvips_image_t in, int width, int height) {
    VipsImage *out = NULL;
    if (vips_thumbnail_image((VipsImage *)in, &out, width,
            "height", height,
            "size", VIPS_SIZE_DOWN,
            NULL)) {
        return NULL;
    }
    return out;
}

cvips_image_t cvips_image_from_srgb_buffer(const unsigned char *data, size_t len,
                                            int width, int height, int bands) {
    VipsImage *raw = vips_image_new_from_memory_copy(data, len, width, height, bands,
                                                       VIPS_FORMAT_UCHAR);
    if (!raw) return NULL;
    VipsImage *tagged = NULL;
    if (vips_copy(raw, &tagged, "interpretation", VIPS_INTERPRETATION_sRGB, NULL)) {
        g_object_unref(raw);
        return NULL;
    }
    g_object_unref(raw);
    return tagged;
}

int cvips_get_n_pages(cvips_image_t image) {
    VipsImage *img = (VipsImage *)image;
    int pages = 1;
    if (vips_image_get_typeof(img, "n-pages") != 0) {
        if (vips_image_get_int(img, "n-pages", &pages)) {
            return 1;
        }
    }
    return pages;
}

int cvips_has_alpha(cvips_image_t image) {
    return vips_image_hasalpha((VipsImage *)image);
}

cvips_image_t cvips_flatten_white(cvips_image_t in) {
    VipsImage *out = NULL;
    double background[3] = { 255.0, 255.0, 255.0 };
    VipsArrayDouble *bg = vips_array_double_new(background, 3);
    int rc = vips_flatten((VipsImage *)in, &out, "background", bg, NULL);
    vips_area_unref(VIPS_AREA(bg));
    if (rc) return NULL;
    return out;
}

int cvips_jpegsave_mozjpeg(cvips_image_t in, const char *filename, int q, int subsample_on) {
    return vips_jpegsave((VipsImage *)in, filename,
            "Q", q,
            "subsample-mode", subsample_on ? VIPS_FOREIGN_SUBSAMPLE_ON : VIPS_FOREIGN_SUBSAMPLE_AUTO,
            "optimize_coding", TRUE,
            "interlace", TRUE,
            "trellis_quant", TRUE,
            "overshoot_deringing", TRUE,
            "optimize_scans", TRUE,
            "quant_table", 3,
            "keep", VIPS_FOREIGN_KEEP_NONE,
            NULL);
}

int cvips_jpegsave_baseline(cvips_image_t in, const char *filename, int q, int subsample_on) {
    return vips_jpegsave((VipsImage *)in, filename,
            "Q", q,
            "subsample-mode", subsample_on ? VIPS_FOREIGN_SUBSAMPLE_ON : VIPS_FOREIGN_SUBSAMPLE_AUTO,
            "optimize_coding", TRUE,
            "interlace", TRUE,
            "keep", VIPS_FOREIGN_KEEP_NONE,
            NULL);
}

int cvips_pngsave_palette(cvips_image_t in, const char *filename, int q, double dither, int effort) {
    return vips_pngsave((VipsImage *)in, filename,
            "compression", 9,
            "palette", TRUE,
            "Q", q,
            "dither", dither,
            "effort", effort,
            "keep", VIPS_FOREIGN_KEEP_NONE,
            NULL);
}

int cvips_pngsave_lossless(cvips_image_t in, const char *filename) {
    return vips_pngsave((VipsImage *)in, filename,
            "compression", 9,
            "keep", VIPS_FOREIGN_KEEP_NONE,
            NULL);
}

int cvips_webpsave(cvips_image_t in, const char *filename, int q, int effort, int alpha_q) {
    return vips_webpsave((VipsImage *)in, filename,
            "Q", q,
            "effort", effort,
            "smart_subsample", TRUE,
            "alpha_q", alpha_q,
            "preset", VIPS_FOREIGN_WEBP_PRESET_PHOTO,
            "keep", VIPS_FOREIGN_KEEP_NONE,
            NULL);
}

int cvips_image_get_width(cvips_image_t image) {
    return ((VipsImage *)image)->Xsize;
}

int cvips_image_get_height(cvips_image_t image) {
    return ((VipsImage *)image)->Ysize;
}

void cvips_set_concurrency(int concurrency) {
    vips_concurrency_set(concurrency);
}

void cvips_set_cache_max(int max) {
    vips_cache_set_max(max);
}
