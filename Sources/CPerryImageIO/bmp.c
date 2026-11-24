// Windows bitmaps and icons, which ImageIO reads itself (no Linux library
// is needed): BMP files, and ICO and CUR files, whose images are each a
// PNG or a bitmap without its file header (a DIB) followed by a one-bit
// mask of the pixels that are transparent. Favicons are mostly ICO files.

#include "CPerryImageIO.h"

#include <stdlib.h>
#include <string.h>

static uint16_t le16(const uint8_t *p) { return (uint16_t)(p[0] | p[1] << 8); }
static uint32_t le32(const uint8_t *p) { return (uint32_t)p[0] | (uint32_t)p[1] << 8 | (uint32_t)p[2] << 16 | (uint32_t)p[3] << 24; }

/// Bitmaps larger than this a side are refused, so a corrupt header can't
/// ask for gigabytes.
#define DIB_MAX_SIDE 32768

/// A channel's value from a pixel by its mask, scaled to 8 bits.
static uint8_t channel(uint32_t pixel, uint32_t mask) {
    if (!mask) return 0;
    int shift = 0;
    while (!(mask & 1)) { mask >>= 1; shift++; }
    // The mask, shifted down, is the channel's largest value.
    uint32_t value = (pixel >> shift) & mask;
    if (mask == 0xff) return (uint8_t)value;
    return (uint8_t)(((uint64_t)value * 255 + mask / 2) / mask);
}

/// Expands run-length encoded rows (BI_RLE8, BI_RLE4) into one palette
/// index a byte, bottom row first, as the file stores them.
static int rle_expand(const uint8_t *data, size_t size, int four, int width, int height, uint8_t *indexes) {
    int x = 0, y = 0;
    size_t at = 0;
    while (at + 1 < size && y < height) {
        uint8_t count = data[at], value = data[at + 1];
        at += 2;
        if (count) {
            for (int i = 0; i < count && x < width; i++, x++) {
                indexes[(size_t)y * width + x] = four ? (i & 1 ? value & 0x0f : value >> 4) : value;
            }
        } else if (value == 0) {
            x = 0; y++;
        } else if (value == 1) {
            return 1;
        } else if (value == 2) {
            if (at + 1 >= size) return 0;
            x += data[at]; y += data[at + 1];
            at += 2;
        } else {
            // An absolute run, padded to a whole 16-bit word.
            size_t bytes = four ? (value + 1) / 2 : value;
            if (at + bytes > size) return 0;
            for (int i = 0; i < value && x < width; i++, x++) {
                uint8_t byte = four ? data[at + i / 2] : data[at + i];
                indexes[(size_t)y * width + x] = four ? (i & 1 ? byte & 0x0f : byte >> 4) : byte;
            }
            at += (bytes + 1) & ~(size_t)1;
        }
    }
    return 1;
}

/// A DIB as straight RGBA. `pixels`, when not NULL, is where the pixel
/// rows start (a BMP file says); otherwise they follow the palette. In an
/// icon the stored height is twice the image's, the AND mask following
/// the colors, and the mask's set bits are transparent.
static int dib_decode(const uint8_t *dib, size_t size, const uint8_t *pixels_at, int icon, uint8_t **out_rgba,
                      int *out_width, int *out_height, int *out_alpha, double *out_dpi_x, double *out_dpi_y) {
    if (size < 12) return 0;
    uint32_t header = le32(dib);
    int32_t width, height;
    int bpp, compression = 0;
    uint32_t colors_used = 0, masks[4] = {0, 0, 0, 0};
    int palette_entry = 4;
    double dpi_x = 72, dpi_y = 72;
    if (header == 12) {
        width = le16(dib + 4);
        height = (int16_t)le16(dib + 6);
        bpp = le16(dib + 10);
        palette_entry = 3;
    } else if (header >= 40 && header <= size) {
        width = (int32_t)le32(dib + 4);
        height = (int32_t)le32(dib + 8);
        bpp = le16(dib + 14);
        compression = (int)le32(dib + 16);
        uint32_t ppm_x = le32(dib + 24), ppm_y = le32(dib + 28);
        if (ppm_x) dpi_x = ppm_x * 0.0254;
        if (ppm_y) dpi_y = ppm_y * 0.0254;
        colors_used = le32(dib + 32);
        if (header >= 52) { masks[0] = le32(dib + 40); masks[1] = le32(dib + 44); masks[2] = le32(dib + 48); }
        if (header >= 56) masks[3] = le32(dib + 52);
    } else {
        return 0;
    }
    int top_down = height < 0;
    if (top_down) height = -height;
    if (icon) height /= 2;
    if (width <= 0 || height <= 0 || width > DIB_MAX_SIDE || height > DIB_MAX_SIDE) return 0;

    size_t at = header;
    // BI_BITFIELDS (3) and BI_ALPHABITFIELDS (6) after a 40-byte header
    // keep their masks after it.
    if (header == 40 && (compression == 3 || compression == 6)) {
        int count = compression == 6 ? 4 : 3;
        if (at + 4 * count > size) return 0;
        for (int i = 0; i < count; i++) masks[i] = le32(dib + at + 4 * i);
        at += 4 * count;
    }
    int bitfields = compression == 3 || compression == 6;
    if (compression != 0 && !bitfields && compression != 1 && compression != 2) return 0;
    if (bpp != 1 && bpp != 4 && bpp != 8 && bpp != 16 && bpp != 24 && bpp != 32) return 0;
    if ((compression == 1 && bpp != 8) || (compression == 2 && bpp != 4)) return 0;

    // The palette, BGR(X).
    uint8_t palette[256][4];
    memset(palette, 0, sizeof(palette));
    if (bpp <= 8) {
        uint32_t count = colors_used && colors_used <= 256 ? colors_used : 1u << bpp;
        if (at + (size_t)count * palette_entry > size) return 0;
        for (uint32_t i = 0; i < count; i++) memcpy(palette[i], dib + at + (size_t)i * palette_entry, 3);
        at += (size_t)count * palette_entry;
    }
    const uint8_t *pixels = pixels_at ? pixels_at : dib + at;
    if (pixels < dib || pixels > dib + size) return 0;
    size_t available = (size_t)(dib + size - pixels);

    if (!bitfields) {
        if (bpp == 16) { masks[0] = 0x7c00; masks[1] = 0x03e0; masks[2] = 0x001f; }
        if (bpp == 32) { masks[0] = 0x00ff0000; masks[1] = 0x0000ff00; masks[2] = 0x000000ff; }
    }
    size_t stride = (((size_t)width * bpp + 31) / 32) * 4;
    uint8_t *rgba = malloc((size_t)width * height * 4);
    if (!rgba) return 0;
    uint8_t *indexes = NULL;
    if (compression == 1 || compression == 2) {
        indexes = calloc((size_t)width * height, 1);
        if (!indexes || !rle_expand(pixels, available, compression == 2, width, height, indexes)) {
            free(indexes); free(rgba);
            return 0;
        }
    } else if (stride * height > available) {
        free(rgba);
        return 0;
    }

    // In a 32-bit bitmap without an alpha mask the fourth byte is alpha in
    // icons and, when any is set, in files that use it; otherwise unused.
    int alpha = 0;
    uint32_t alpha_mask = masks[3];
    if (bpp == 32 && !alpha_mask && (icon || compression == 0)) {
        for (int y = 0; y < height && !alpha; y++)
            for (int x = 0; x < width; x++)
                if (pixels[y * stride + x * 4 + 3]) { alpha = 1; break; }
        if (alpha) alpha_mask = 0xff000000;
    } else if (alpha_mask) {
        alpha = 1;
    }

    for (int y = 0; y < height; y++) {
        int row = top_down ? y : height - 1 - y;
        const uint8_t *in = indexes ? NULL : pixels + (size_t)row * stride;
        uint8_t *out = rgba + (size_t)y * width * 4;
        for (int x = 0; x < width; x++, out += 4) {
            if (bpp <= 8) {
                int index;
                if (indexes) index = indexes[(size_t)row * width + x];
                else if (bpp == 8) index = in[x];
                else if (bpp == 4) index = (in[x / 2] >> (x & 1 ? 0 : 4)) & 0x0f;
                else index = (in[x / 8] >> (7 - (x & 7))) & 1;
                out[0] = palette[index][2]; out[1] = palette[index][1]; out[2] = palette[index][0]; out[3] = 0xff;
            } else if (bpp == 24) {
                out[0] = in[x * 3 + 2]; out[1] = in[x * 3 + 1]; out[2] = in[x * 3]; out[3] = 0xff;
            } else {
                uint32_t pixel = bpp == 16 ? le16(in + x * 2) : le32(in + x * 4);
                out[0] = channel(pixel, masks[0]); out[1] = channel(pixel, masks[1]); out[2] = channel(pixel, masks[2]);
                out[3] = alpha_mask ? channel(pixel, alpha_mask) : 0xff;
            }
        }
    }
    free(indexes);

    // An icon's AND mask, when its colors have no alpha of their own.
    if (icon && !alpha && compression == 0) {
        size_t mask_stride = (((size_t)width + 31) / 32) * 4;
        const uint8_t *mask = pixels + stride * height;
        if (mask_stride * height <= available - stride * height) {
            for (int y = 0; y < height; y++) {
                int row = top_down ? y : height - 1 - y;
                for (int x = 0; x < width; x++)
                    if ((mask[(size_t)row * mask_stride + x / 8] >> (7 - (x & 7))) & 1) rgba[((size_t)y * width + x) * 4 + 3] = 0;
            }
            alpha = 1;
        }
    }

    *out_rgba = rgba;
    *out_width = width;
    *out_height = height;
    *out_alpha = alpha;
    if (out_dpi_x) *out_dpi_x = dpi_x;
    if (out_dpi_y) *out_dpi_y = dpi_y;
    return 1;
}

int perry_bmp_decode(const uint8_t *data, size_t size, perry_decoded *out) {
    memset(out, 0, sizeof(*out));
    if (size < 26 || data[0] != 'B' || data[1] != 'M') return 0;
    uint32_t offset = le32(data + 10);
    if (offset >= size) return 0;
    uint8_t *rgba = NULL;
    int width = 0, height = 0, alpha = 0;
    if (!dib_decode(data + 14, size - 14, data + offset, 0, &rgba, &width, &height, &alpha, &out->dpi_x, &out->dpi_y)) return 0;
    out->frames = calloc(1, sizeof(perry_frame));
    if (!out->frames) { free(rgba); return 0; }
    out->frames[0] = (perry_frame){rgba, width, height, 0};
    out->count = 1;
    out->has_alpha = alpha;
    out->components = 3;
    out->depth = 8;
    out->orientation = 1;
    out->loop_count = -1;
    return 1;
}

int perry_ico_decode(const uint8_t *data, size_t size, perry_decoded *out) {
    memset(out, 0, sizeof(*out));
    if (size < 6 || le16(data) != 0 || (le16(data + 2) != 1 && le16(data + 2) != 2)) return 0;
    int count = le16(data + 4);
    if (count == 0 || 6 + (size_t)count * 16 > size) return 0;
    out->frames = calloc((size_t)count, sizeof(perry_frame));
    if (!out->frames) return 0;
    out->components = 3;
    out->depth = 8;
    out->orientation = 1;
    out->loop_count = -1;
    out->dpi_x = out->dpi_y = 72;
    for (int i = 0; i < count; i++) {
        const uint8_t *entry = data + 6 + (size_t)i * 16;
        uint32_t length = le32(entry + 8), offset = le32(entry + 12);
        if (offset >= size || length > size - offset) continue;
        const uint8_t *image = data + offset;
        uint8_t *rgba = NULL;
        int width = 0, height = 0, alpha = 0;
        if (length >= 8 && !memcmp(image, "\x89PNG\r\n\x1a\n", 8)) {
            perry_decoded png;
            if (!perry_png_decode(image, length, &png)) continue;
            rgba = png.frames[0].rgba;
            width = png.frames[0].width;
            height = png.frames[0].height;
            alpha = png.has_alpha;
            free(png.frames);
        } else if (!dib_decode(image, length, NULL, 1, &rgba, &width, &height, &alpha, NULL, NULL)) {
            continue;
        }
        out->frames[out->count++] = (perry_frame){rgba, width, height, 0};
        if (alpha) out->has_alpha = 1;
    }
    if (out->count == 0) { free(out->frames); out->frames = NULL; return 0; }
    return 1;
}
