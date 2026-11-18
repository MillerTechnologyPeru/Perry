// PDF: the first page of a document, rendered to a bitmap by Poppler and
// Cairo, loaded when first needed. Mac programs ship artwork as PDF (Xcode's
// welcome window's backdrop); a page renders at 144 dpi, twice its size in
// points, so it is sharp on a display that needs two pixels a point and
// still measures as the PDF says.

#include "CPerryImageIO.h"

#include <dlfcn.h>
#include <stddef.h>
#include <stdlib.h>
#include <string.h>

typedef struct _cairo_surface cairo_surface_t;
typedef struct _cairo cairo_t;
enum { CAIRO_FORMAT_ARGB32 = 0 };

static struct {
    int loaded;
    void *(*document_new_from_data)(char *data, int length, const char *password, void **error);
    void *(*document_get_page)(void *document, int index);
    void (*page_get_size)(void *page, double *width, double *height);
    void (*page_render)(void *page, cairo_t *cairo);
    void (*object_unref)(void *object);
    void (*error_free)(void *error);
    cairo_surface_t *(*image_surface_create)(int format, int width, int height);
    unsigned char *(*image_surface_get_data)(cairo_surface_t *surface);
    int (*image_surface_get_stride)(cairo_surface_t *surface);
    void (*surface_flush)(cairo_surface_t *surface);
    void (*surface_destroy)(cairo_surface_t *surface);
    int (*surface_status)(cairo_surface_t *surface);
    cairo_t *(*create)(cairo_surface_t *surface);
    void (*scale)(cairo_t *cairo, double x, double y);
    void (*destroy)(cairo_t *cairo);
} poppler;

static int load_poppler(void) {
    if (poppler.loaded) return poppler.loaded > 0;
    poppler.loaded = -1;
    void *library = dlopen("libpoppler-glib.so.8", RTLD_NOW | RTLD_LOCAL);
    void *cairo = dlopen("libcairo.so.2", RTLD_NOW | RTLD_LOCAL);
    void *gobject = dlopen("libgobject-2.0.so.0", RTLD_NOW | RTLD_LOCAL);
    void *glib = dlopen("libglib-2.0.so.0", RTLD_NOW | RTLD_LOCAL);
    if (!library || !cairo || !gobject || !glib) return 0;
    *(void **)&poppler.document_new_from_data = dlsym(library, "poppler_document_new_from_data");
    *(void **)&poppler.document_get_page = dlsym(library, "poppler_document_get_page");
    *(void **)&poppler.page_get_size = dlsym(library, "poppler_page_get_size");
    *(void **)&poppler.page_render = dlsym(library, "poppler_page_render");
    *(void **)&poppler.object_unref = dlsym(gobject, "g_object_unref");
    *(void **)&poppler.error_free = dlsym(glib, "g_error_free");
    *(void **)&poppler.image_surface_create = dlsym(cairo, "cairo_image_surface_create");
    *(void **)&poppler.image_surface_get_data = dlsym(cairo, "cairo_image_surface_get_data");
    *(void **)&poppler.image_surface_get_stride = dlsym(cairo, "cairo_image_surface_get_stride");
    *(void **)&poppler.surface_flush = dlsym(cairo, "cairo_surface_flush");
    *(void **)&poppler.surface_destroy = dlsym(cairo, "cairo_surface_destroy");
    *(void **)&poppler.surface_status = dlsym(cairo, "cairo_surface_status");
    *(void **)&poppler.create = dlsym(cairo, "cairo_create");
    *(void **)&poppler.scale = dlsym(cairo, "cairo_scale");
    *(void **)&poppler.destroy = dlsym(cairo, "cairo_destroy");
    void **functions = (void **)&poppler.document_new_from_data;
    for (size_t i = 0; i < (sizeof(poppler) - offsetof(typeof(poppler), document_new_from_data)) / sizeof(void *); i++)
        if (!functions[i]) return 0;
    poppler.loaded = 1;
    return 1;
}

int perry_pdf_decode(const uint8_t *data, size_t size, perry_decoded *out) {
    memset(out, 0, sizeof(*out));
    if (size > 0x7fffffff || !load_poppler()) return 0;
    // Poppler reads the bytes in place; they outlive the document.
    void *error = NULL;
    void *document = poppler.document_new_from_data((char *)data, (int)size, NULL, &error);
    if (!document) {
        if (error) poppler.error_free(error);
        return 0;
    }
    void *page = poppler.document_get_page(document, 0);
    if (!page) {
        poppler.object_unref(document);
        return 0;
    }
    double width = 0, height = 0;
    poppler.page_get_size(page, &width, &height);
    const double scale = 2;
    int pixels_wide = (int)(width * scale + 0.5), pixels_high = (int)(height * scale + 0.5);
    int ok = 0;
    if (pixels_wide > 0 && pixels_high > 0 && pixels_wide <= 16384 && pixels_high <= 16384) {
        cairo_surface_t *surface = poppler.image_surface_create(CAIRO_FORMAT_ARGB32, pixels_wide, pixels_high);
        if (surface && poppler.surface_status(surface) == 0) {
            cairo_t *cairo = poppler.create(surface);
            poppler.scale(cairo, scale, scale);
            poppler.page_render(page, cairo);
            poppler.destroy(cairo);
            poppler.surface_flush(surface);
            const unsigned char *pixels = poppler.image_surface_get_data(surface);
            int stride = poppler.image_surface_get_stride(surface);
            uint8_t *rgba = malloc((size_t)pixels_wide * pixels_high * 4);
            out->frames = calloc(1, sizeof(perry_frame));
            if (rgba && out->frames && pixels) {
                // Cairo's ARGB32 is premultiplied, in native (little-endian
                // BGRA) order; frames are straight RGBA.
                for (int y = 0; y < pixels_high; y++) {
                    const uint32_t *row = (const uint32_t *)(pixels + (size_t)y * stride);
                    uint8_t *to = rgba + (size_t)y * pixels_wide * 4;
                    for (int x = 0; x < pixels_wide; x++, to += 4) {
                        uint32_t pixel = row[x];
                        unsigned alpha = pixel >> 24, red = (pixel >> 16) & 0xff, green = (pixel >> 8) & 0xff, blue = pixel & 0xff;
                        if (alpha && alpha < 255) {
                            red = red * 255 / alpha, green = green * 255 / alpha, blue = blue * 255 / alpha;
                        }
                        to[0] = (uint8_t)red, to[1] = (uint8_t)green, to[2] = (uint8_t)blue, to[3] = (uint8_t)alpha;
                    }
                }
                out->frames[0] = (perry_frame){rgba, pixels_wide, pixels_high, 0};
                out->count = 1;
                out->has_alpha = 1;
                out->components = 3;
                out->depth = 8;
                out->orientation = 1;
                out->loop_count = -1;
                out->dpi_x = out->dpi_y = 72 * scale;
                ok = 1;
            } else {
                free(rgba);
                free(out->frames);
                out->frames = NULL;
            }
        }
        if (surface) poppler.surface_destroy(surface);
    }
    poppler.object_unref(page);
    poppler.object_unref(document);
    return ok;
}
