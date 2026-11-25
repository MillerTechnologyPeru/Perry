// Pictures: a 'PICT' resource drawn into a port. A picture is a list of
// QuickDraw's operations; the ones programs of Carbon's time keep in their
// resources are an image QuickTime compressed, with a few operations before
// it that set the port up, and that image is what is drawn here: its data
// is a file of its codec's kind (TIFF, JPEG, PNG), which ImageIO reads.
// MacSoft's Halo shows its loading picture so, a TIFF in PICT 10000.

#include "PerryCarbon.h"

#include <stdlib.h>
#include <string.h>

#define FOUR(a, b, c, d) ((uint32_t)(a) << 24 | (uint32_t)(b) << 16 | (uint32_t)(c) << 8 | (uint32_t)(d))
#define CORESERVICES "/System/Library/Frameworks/CoreServices.framework/CoreServices"
#define GRAPHICS "/System/Library/Frameworks/ApplicationServices.framework/ApplicationServices"

static uint16_t be16(const uint8_t *bytes) { return (uint16_t)(bytes[0] << 8 | bytes[1]); }
static uint32_t be32(const uint8_t *bytes) { return (uint32_t)bytes[0] << 24 | (uint32_t)bytes[1] << 16 | (uint32_t)bytes[2] << 8 | bytes[3]; }

Handle carbon_GetPicture(int16_t identifier) CARBON_SYMBOL(GetPicture);
Handle carbon_GetPicture(int16_t identifier) {
    Handle (*get_resource)(OSType, int16_t) = (Handle (*)(OSType, int16_t))carbon_function(
        "/System/Library/Frameworks/Carbon.framework/Versions/A/Carbon", "_GetResource");
    return get_resource ? get_resource(FOUR('P', 'I', 'C', 'T'), identifier) : NULL;
}

/// The compressed image in a version 2 picture: its data, after the
/// operations that come before it. Operations are words, each with data
/// whose length its kind gives; one this doesn't know ends the search.
static const uint8_t *compressed_image(const uint8_t *picture, size_t size, size_t *length) {
    // The picture's size and frame, then the version operation and header.
    size_t at = 10;
    while (at + 2 <= size) {
        uint16_t operation = be16(picture + at);
        at += 2;
        size_t data;
        switch (operation) {
        case 0x0000: case 0x001C: case 0x001E: case 0x0038: case 0x0039: case 0x003A: case 0x003B: case 0x003C:
            data = 0; break;                                                  // NOP, highlight modes, the same rectangle
        case 0x0011: case 0x0003: case 0x0004: case 0x0005: case 0x0008: case 0x000D: case 0x0015: case 0x0016: case 0x00A0:
            data = 2; break;                                                  // version, text and pen settings, a short comment
        case 0x0006: case 0x0007: case 0x000B: case 0x000C: case 0x000E: case 0x000F:
            data = 4; break;
        case 0x001A: case 0x001B: case 0x001D: case 0x001F:
            data = 6; break;                                                  // colors
        case 0x0002: case 0x0009: case 0x000A: case 0x0010: case 0x0030: case 0x0031: case 0x0032: case 0x0033: case 0x0034:
            data = 8; break;                                                  // patterns, rectangles
        case 0x0C00: data = 24; break;                                        // the header
        case 0x0001:                                                          // the clip: a region, with its size first
            if (at + 2 > size) return NULL;
            data = be16(picture + at);
            break;
        case 0x00A1:                                                          // a long comment: kind, size, data
            if (at + 4 > size) return NULL;
            data = 4 + (size_t)be16(picture + at + 2);
            break;
        case 0x8200: {                                                        // CompressedQuickTime
            if (at + 4 > size) return NULL;
            size_t whole = be32(picture + at), start = at + 4;
            if (whole < 68 + 86 || start + whole > size) return NULL;
            // Version (2), matrix (36), matte size (4) and rectangle (8),
            // mode (2), source rectangle (8), accuracy (4), mask size (4);
            // then a matte's description and data, a mask's region, and
            // the image's description, whose size is its first long and
            // whose data's size is at 44.
            size_t matte = be32(picture + start + 38), mask = be32(picture + start + 64), next = start + 68;
            if (matte) {
                if (next + 4 > size) return NULL;
                next += be32(picture + next) + matte;
            }
            next += mask;
            if (next + 86 > start + whole) return NULL;
            size_t description = be32(picture + next), bytes = be32(picture + next + 44);
            if (description < 86 || next + description > start + whole) return NULL;
            if (bytes == 0 || next + description + bytes > start + whole) bytes = start + whole - next - description;
            *length = bytes;
            return picture + next + description;
        }
        default:
            return NULL;
        }
        at += data;
        if (at & 1) at++;                                                     // operations start on words
    }
    return NULL;
}

/// Draws the picture's image into the current port, scaled to the rectangle.
void carbon_DrawPicture(Handle picture, const Rect *frame) CARBON_SYMBOL(DrawPicture);
void carbon_DrawPicture(Handle picture, const Rect *frame) {
    CGrafPtr port = carbon_current_port();
    if (!picture || !*picture || !frame || !port || !port->pixmap) return;
    long (*handle_size)(Handle) = (long (*)(Handle))carbon_function(CORESERVICES, "_GetHandleSize");
    long size = handle_size ? handle_size(picture) : 0;
    size_t length = 0;
    const uint8_t *data = size > 10 ? compressed_image((const uint8_t *)*picture, (size_t)size, &length) : NULL;
    if (!data) {
        CARBON_TRACE("DrawPicture: a picture with no compressed image, not drawn");
        return;
    }
    PixMap *pixmap = *port->pixmap;
    int width = pixmap->bounds.right - pixmap->bounds.left, height = pixmap->bounds.bottom - pixmap->bounds.top;
    if (pixmap->pixelSize != 32 || width <= 0 || height <= 0 || !pixmap->baseAddr) {
        CARBON_TRACE("DrawPicture: a port of %d bits, %dx%d, not drawn into", pixmap->pixelSize, width, height);
        return;
    }

    void *(*source_create)(id, id) = (void *(*)(id, id))carbon_function(GRAPHICS, "_CGImageSourceCreateWithData");
    void *(*image_at)(void *, size_t, id) = (void *(*)(void *, size_t, id))carbon_function(GRAPHICS, "_CGImageSourceCreateImageAtIndex");
    void *(*color_space)(void) = (void *(*)(void))carbon_function(GRAPHICS, "_CGColorSpaceCreateDeviceRGB");
    void *(*bitmap)(void *, size_t, size_t, size_t, size_t, void *, uint32_t) =
        (void *(*)(void *, size_t, size_t, size_t, size_t, void *, uint32_t))carbon_function(GRAPHICS, "_CGBitmapContextCreate");
    void (*draw)(void *, NSRect, void *) = (void (*)(void *, NSRect, void *))carbon_function(GRAPHICS, "_CGContextDrawImage");
    void (*release_context)(void *) = (void (*)(void *))carbon_function(GRAPHICS, "_CGContextRelease");
    void (*release_image)(void *) = (void (*)(void *))carbon_function(GRAPHICS, "_CGImageRelease");
    void (*release_space)(void *) = (void (*)(void *))carbon_function(GRAPHICS, "_CGColorSpaceRelease");
    if (!source_create || !image_at || !color_space || !bitmap || !draw || !release_context || !release_image) {
        CARBON_TRACE("DrawPicture: no ImageIO or Core Graphics to draw with (%p %p %p %p)", (void *)source_create, (void *)image_at,
                     (void *)bitmap, (void *)draw);
        return;
    }

    id bytes = ((id (*)(id, SEL, const void *, unsigned long))objc_send)(CLASS("NSData"), SELECTOR("dataWithBytes:length:"), data,
                                                                       (unsigned long)length);
    void *source = bytes ? source_create(bytes, NULL) : NULL;
    void *image = source ? image_at(source, 0, NULL) : NULL;
    if (source) SEND((id)source, "release");
    if (!image) {
        CARBON_TRACE("DrawPicture: an image ImageIO can't read (%lu bytes), not drawn", (unsigned long)length);
        return;
    }
    // The port's pixels are xRGB, the first row the top one, as a bitmap
    // context's are; its coordinates go up from the bottom.
    void *space = color_space();
    void *context = bitmap(pixmap->baseAddr, (size_t)width, (size_t)height, 8, (size_t)(pixmap->rowBytes & 0x3fff), space,
                           6 | (4u << 12));   // kCGImageAlphaNoneSkipFirst, big-endian
    if (context) {
        NSRect where = {{(CGFloat)(frame->left - pixmap->bounds.left), (CGFloat)(pixmap->bounds.bottom - frame->bottom)},
                        {(CGFloat)(frame->right - frame->left), (CGFloat)(frame->bottom - frame->top)}};
        draw(context, where, image);
        release_context(context);
    }
    if (space && release_space) release_space(space);
    release_image(image);
}

/// A picture made by OpenPicture is freed; one from a resource is its
/// resource's, which ReleaseResource lets go. There are none of the first
/// kind here.
void carbon_KillPicture(Handle picture) CARBON_SYMBOL(KillPicture);
void carbon_KillPicture(Handle picture) { (void)picture; }

/// The picture's frame, as its first words after its size have it.
Rect *carbon_QDGetPictureBounds(Handle picture, Rect *bounds) CARBON_SYMBOL(QDGetPictureBounds);
Rect *carbon_QDGetPictureBounds(Handle picture, Rect *bounds) {
    if (!bounds) return NULL;
    *bounds = (Rect){0, 0, 0, 0};
    if (picture && *picture) {
        const uint8_t *bytes = (const uint8_t *)*picture;
        *bounds = (Rect){(int16_t)be16(bytes + 2), (int16_t)be16(bytes + 4), (int16_t)be16(bytes + 6), (int16_t)be16(bytes + 8)};
    }
    return bounds;
}
