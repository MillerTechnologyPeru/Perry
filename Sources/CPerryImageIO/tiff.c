// TIFF reading, over the system's libtiff, opened when a TIFF is first
// read so that building needs no libtiff headers. Each directory is an
// image, as ImageIO counts a TIFF's; old Mac apps' TIFFs often hold the
// same picture at 72 and 144 dots an inch.

#include "CPerryImageIO.h"

#include <dlfcn.h>
#include <stdlib.h>
#include <string.h>
#include <sys/types.h>

typedef struct tiff TIFF;
typedef ssize_t (*tiff_io)(void *, void *, ssize_t);
typedef uint64_t (*tiff_seek)(void *, uint64_t, int);
typedef int (*tiff_close)(void *);
typedef uint64_t (*tiff_size)(void *);
typedef int (*tiff_map)(void *, void **, uint64_t *);
typedef void (*tiff_unmap)(void *, void *, uint64_t);

static struct {
    TIFF *(*client_open)(const char *, const char *, void *, tiff_io, tiff_io, tiff_seek, tiff_close, tiff_size, tiff_map,
                         tiff_unmap);
    void (*close)(TIFF *);
    int (*get_field)(TIFF *, uint32_t, ...);
    int (*get_field_defaulted)(TIFF *, uint32_t, ...);
    int (*read_rgba)(TIFF *, uint32_t, uint32_t, uint32_t *, int, int);
    int (*read_directory)(TIFF *);
    void *(*set_warning_handler)(void *);
    void *(*set_error_handler)(void *);
    int loaded;
} libtiff;

static int load_libtiff(void) {
    if (libtiff.loaded) return libtiff.loaded > 0;
    libtiff.loaded = -1;
    void *library = dlopen("libtiff.so.6", RTLD_NOW | RTLD_LOCAL);
    if (!library) library = dlopen("libtiff.so.5", RTLD_NOW | RTLD_LOCAL);
    if (!library) return 0;
    *(void **)&libtiff.client_open = dlsym(library, "TIFFClientOpen");
    *(void **)&libtiff.close = dlsym(library, "TIFFClose");
    *(void **)&libtiff.get_field = dlsym(library, "TIFFGetField");
    *(void **)&libtiff.get_field_defaulted = dlsym(library, "TIFFGetFieldDefaulted");
    *(void **)&libtiff.read_rgba = dlsym(library, "TIFFReadRGBAImageOriented");
    *(void **)&libtiff.read_directory = dlsym(library, "TIFFReadDirectory");
    *(void **)&libtiff.set_warning_handler = dlsym(library, "TIFFSetWarningHandler");
    *(void **)&libtiff.set_error_handler = dlsym(library, "TIFFSetErrorHandler");
    if (!libtiff.client_open || !libtiff.close || !libtiff.get_field || !libtiff.get_field_defaulted || !libtiff.read_rgba ||
        !libtiff.read_directory)
        return 0;
    // Unknown Apple tags warn on stderr otherwise.
    if (libtiff.set_warning_handler) libtiff.set_warning_handler(NULL);
    libtiff.loaded = 1;
    return 1;
}

typedef struct {
    const uint8_t *data;
    size_t size, at;
} memory_file;

static ssize_t memory_read(void *handle, void *buffer, ssize_t count) {
    memory_file *file = handle;
    if (count < 0 || file->at >= file->size) return 0;
    size_t length = file->size - file->at < (size_t)count ? file->size - file->at : (size_t)count;
    memcpy(buffer, file->data + file->at, length);
    file->at += length;
    return (ssize_t)length;
}

static ssize_t memory_write(void *handle, void *buffer, ssize_t count) {
    (void)handle, (void)buffer, (void)count;
    return -1;
}

static uint64_t memory_seek(void *handle, uint64_t offset, int whence) {
    memory_file *file = handle;
    uint64_t base = whence == 1 ? file->at : whence == 2 ? file->size : 0;
    file->at = (size_t)(base + offset);
    return file->at;
}

static int memory_close(void *handle) {
    (void)handle;
    return 0;
}

static uint64_t memory_size(void *handle) { return ((memory_file *)handle)->size; }

static int memory_map(void *handle, void **base, uint64_t *size) {
    memory_file *file = handle;
    *base = (void *)file->data;
    *size = file->size;
    return 1;
}

static void memory_unmap(void *handle, void *base, uint64_t size) { (void)handle, (void)base, (void)size; }

enum {
    TAG_IMAGE_WIDTH = 256, TAG_IMAGE_LENGTH = 257, TAG_BITS_PER_SAMPLE = 258, TAG_PHOTOMETRIC = 262,
    TAG_ORIENTATION = 274, TAG_SAMPLES_PER_PIXEL = 277, TAG_X_RESOLUTION = 282, TAG_Y_RESOLUTION = 283,
    TAG_RESOLUTION_UNIT = 296, TAG_EXTRA_SAMPLES = 338,
};

int perry_tiff_decode(const uint8_t *data, size_t size, perry_decoded *out) {
    memset(out, 0, sizeof(*out));
    if (!load_libtiff()) return 0;
    memory_file file = {data, size, 0};
    TIFF *tiff = libtiff.client_open("memory", "rm", &file, memory_read, memory_write, memory_seek, memory_close,
                                     memory_size, memory_map, memory_unmap);
    if (!tiff) return 0;
    int capacity = 0;
    do {
        uint32_t width = 0, height = 0;
        if (!libtiff.get_field(tiff, TAG_IMAGE_WIDTH, &width) || !libtiff.get_field(tiff, TAG_IMAGE_LENGTH, &height) ||
            width == 0 || height == 0 || (uint64_t)width * height > (1u << 28))
            continue;
        // libtiff's raster: one word a pixel, R in its low byte, so RGBA
        // bytes in memory on a little-endian machine, from the top row.
        uint32_t *raster = malloc((size_t)width * height * 4);
        if (!raster) break;
        if (!libtiff.read_rgba(tiff, width, height, raster, 1, 0)) {   // ORIENTATION_TOPLEFT
            free(raster);
            continue;
        }
        if (out->count == capacity) {
            int grown_capacity = capacity ? capacity * 2 : 2;
            perry_frame *grown = realloc(out->frames, (size_t)grown_capacity * sizeof *grown);
            if (!grown) {
                free(raster);
                break;
            }
            out->frames = grown;
            capacity = grown_capacity;
        }
        out->frames[out->count++] = (perry_frame){(uint8_t *)raster, (int)width, (int)height, 0};
        if (out->count > 1) continue;
        // The first image's description stands for the file's.
        uint16_t samples = 0, bits = 8, photometric = 2, extra_count = 0, unit = 2;
        uint16_t *extra = NULL;
        libtiff.get_field_defaulted(tiff, TAG_SAMPLES_PER_PIXEL, &samples);
        libtiff.get_field_defaulted(tiff, TAG_BITS_PER_SAMPLE, &bits);
        libtiff.get_field(tiff, TAG_PHOTOMETRIC, &photometric);
        libtiff.get_field_defaulted(tiff, TAG_EXTRA_SAMPLES, &extra_count, &extra);
        libtiff.get_field_defaulted(tiff, TAG_RESOLUTION_UNIT, &unit);
        float x_resolution = 0, y_resolution = 0;
        libtiff.get_field(tiff, TAG_X_RESOLUTION, &x_resolution);
        libtiff.get_field(tiff, TAG_Y_RESOLUTION, &y_resolution);
        double per_inch = unit == 3 ? 2.54 : 1;   // RESUNIT_CENTIMETER
        out->dpi_x = x_resolution > 0 ? x_resolution * per_inch : 72;
        out->dpi_y = y_resolution > 0 ? y_resolution * per_inch : out->dpi_x;
        out->has_alpha = extra_count > 0;
        out->components = photometric <= 1 ? 1 : 3;   // min-is-white or min-is-black
        out->depth = bits;
        (void)samples;
    } while (libtiff.read_directory(tiff));
    libtiff.close(tiff);
    if (out->count == 0) {
        free(out->frames);
        out->frames = NULL;
        return 0;
    }
    out->orientation = 1;
    out->loop_count = -1;
    return 1;
}
