#ifndef CPERRY_IMAGEIO_H
#define CPERRY_IMAGEIO_H

// ImageIO's codecs over Linux's libpng, libjpeg-turbo, giflib, libwebp and
// libheif. Images cross as straight (not premultiplied) RGBA, 8 bits per
// component, rows packed; buffers the codecs return are malloc'd and the
// caller frees them with free().

#include <stddef.h>
#include <stdint.h>

typedef struct perry_frame {
    uint8_t *rgba;
    int width, height;
    /// Seconds a GIF frame shows.
    double delay;
} perry_frame;

typedef struct perry_decoded {
    perry_frame *frames;
    int count;
    /// Whether any pixel may be transparent: an alpha channel or a transparent GIF color.
    int has_alpha;
    /// 1 for gray, 3 for color.
    int components;
    /// Bits per component in the file.
    int depth;
    /// EXIF orientation, 1 when the file has none.
    int orientation;
    double dpi_x, dpi_y;
    /// GIF: times to loop, 0 forever, -1 when the file says nothing.
    int loop_count;
} perry_decoded;

int perry_png_decode(const uint8_t *data, size_t size, perry_decoded *out);
int perry_jpeg_decode(const uint8_t *data, size_t size, perry_decoded *out);
int perry_gif_decode(const uint8_t *data, size_t size, perry_decoded *out);
int perry_webp_decode(const uint8_t *data, size_t size, perry_decoded *out);
int perry_heif_decode(const uint8_t *data, size_t size, perry_decoded *out);
void perry_decoded_free(perry_decoded *decoded);

int perry_png_encode(const uint8_t *rgba, int width, int height, int has_alpha, uint8_t **out, size_t *out_size);
int perry_jpeg_encode(const uint8_t *rgba, int width, int height, int quality, int orientation, uint8_t **out, size_t *out_size);
int perry_gif_encode(const perry_frame *frames, int count, int loop_count, uint8_t **out, size_t *out_size);

#endif
