// ImageIO's codecs. See CPerryImageIO.h.

#include "CPerryImageIO.h"

#include <stdio.h>

#include <gif_lib.h>
#include <jpeglib.h>
#include <libheif/heif.h>
#include <png.h>
#include <setjmp.h>
#include <stdlib.h>
#include <string.h>
#include <webp/decode.h>

void perry_decoded_free(perry_decoded *decoded) {
    for (int i = 0; i < decoded->count; i++) free(decoded->frames[i].rgba);
    free(decoded->frames);
    decoded->frames = NULL;
    decoded->count = 0;
}

static int one_frame(perry_decoded *out, uint8_t *rgba, int width, int height) {
    out->frames = calloc(1, sizeof(perry_frame));
    if (!out->frames) { free(rgba); return 0; }
    out->frames[0] = (perry_frame){rgba, width, height, 0};
    out->count = 1;
    if (out->orientation == 0) out->orientation = 1;
    if (out->loop_count == 0) out->loop_count = -1;
    return 1;
}

// MARK: - PNG

int perry_png_decode(const uint8_t *data, size_t size, perry_decoded *out) {
    memset(out, 0, sizeof(*out));
    png_image image;
    memset(&image, 0, sizeof(image));
    image.version = PNG_IMAGE_VERSION;
    if (!png_image_begin_read_from_memory(&image, data, size)) return 0;
    out->has_alpha = (image.format & PNG_FORMAT_FLAG_ALPHA) != 0;
    out->components = (image.format & PNG_FORMAT_FLAG_COLOR) ? 3 : 1;
    out->depth = (image.format & PNG_FORMAT_FLAG_LINEAR) ? 16 : 8;
    image.format = PNG_FORMAT_RGBA;
    uint8_t *rgba = malloc(PNG_IMAGE_SIZE(image));
    if (!rgba || !png_image_finish_read(&image, NULL, rgba, 0, NULL)) {
        free(rgba);
        png_image_free(&image);
        return 0;
    }
    out->dpi_x = out->dpi_y = 72;
    return one_frame(out, rgba, (int)image.width, (int)image.height);
}

int perry_png_encode(const uint8_t *rgba, int width, int height, int has_alpha, uint8_t **out, size_t *out_size) {
    png_image image;
    memset(&image, 0, sizeof(image));
    image.version = PNG_IMAGE_VERSION;
    image.width = (png_uint_32)width;
    image.height = (png_uint_32)height;
    image.format = PNG_FORMAT_RGBA;
    // An opaque image is written as RGB.
    uint8_t *rgb = NULL;
    const void *pixels = rgba;
    if (!has_alpha) {
        rgb = malloc((size_t)width * height * 3);
        if (!rgb) return 0;
        for (size_t i = 0; i < (size_t)width * height; i++) memcpy(rgb + i * 3, rgba + i * 4, 3);
        image.format = PNG_FORMAT_RGB;
        pixels = rgb;
    }
    png_alloc_size_t size = 0;
    if (!png_image_write_to_memory(&image, NULL, &size, 0, pixels, 0, NULL)) { free(rgb); return 0; }
    *out = malloc(size);
    int ok = *out && png_image_write_to_memory(&image, *out, &size, 0, pixels, 0, NULL);
    free(rgb);
    if (!ok) { free(*out); *out = NULL; return 0; }
    *out_size = size;
    return 1;
}

// MARK: - JPEG

typedef struct jpeg_failure {
    struct jpeg_error_mgr manager;
    jmp_buf jump;
} jpeg_failure;

static void jpeg_fail(j_common_ptr info) { longjmp(((jpeg_failure *)info->err)->jump, 1); }
static void jpeg_quiet(j_common_ptr info, int level) { (void)info; (void)level; }

/// The orientation in an Exif APP1 segment, or 0.
static int exif_orientation(const uint8_t *exif, size_t size) {
    if (size < 14 || memcmp(exif, "Exif\0\0", 6) != 0) return 0;
    const uint8_t *tiff = exif + 6;
    size_t length = size - 6;
    int big = tiff[0] == 'M';
    #define U16(p) (big ? (uint16_t)((p)[0] << 8 | (p)[1]) : (uint16_t)((p)[1] << 8 | (p)[0]))
    #define U32(p) (big ? (uint32_t)(p)[0] << 24 | (uint32_t)(p)[1] << 16 | (uint32_t)(p)[2] << 8 | (p)[3] \
                        : (uint32_t)(p)[3] << 24 | (uint32_t)(p)[2] << 16 | (uint32_t)(p)[1] << 8 | (p)[0])
    uint32_t ifd = U32(tiff + 4);
    if (ifd + 2 > length) return 0;
    uint16_t entries = U16(tiff + ifd);
    for (uint16_t i = 0; i < entries; i++) {
        size_t entry = ifd + 2 + (size_t)i * 12;
        if (entry + 12 > length) return 0;
        if (U16(tiff + entry) == 0x0112) return U16(tiff + entry + 8);
    }
    return 0;
    #undef U16
    #undef U32
}

int perry_jpeg_decode(const uint8_t *data, size_t size, perry_decoded *out) {
    memset(out, 0, sizeof(*out));
    struct jpeg_decompress_struct info;
    jpeg_failure failure;
    info.err = jpeg_std_error(&failure.manager);
    failure.manager.error_exit = jpeg_fail;
    failure.manager.emit_message = jpeg_quiet;
    uint8_t *rgba = NULL;
    if (setjmp(failure.jump)) {
        jpeg_destroy_decompress(&info);
        free(rgba);
        return 0;
    }
    jpeg_create_decompress(&info);
    jpeg_mem_src(&info, data, (unsigned long)size);
    jpeg_save_markers(&info, JPEG_APP0 + 1, 0xffff);
    if (jpeg_read_header(&info, TRUE) != JPEG_HEADER_OK) { jpeg_destroy_decompress(&info); return 0; }
    out->components = info.num_components == 1 ? 1 : 3;
    out->depth = 8;
    out->dpi_x = out->dpi_y = 72;
    if (info.saw_JFIF_marker && info.density_unit == 1) { out->dpi_x = info.X_density; out->dpi_y = info.Y_density; }
    for (jpeg_saved_marker_ptr marker = info.marker_list; marker; marker = marker->next) {
        int orientation = exif_orientation(marker->data, marker->data_length);
        if (orientation) out->orientation = orientation;
    }
    info.out_color_space = JCS_EXT_RGBA;
    jpeg_start_decompress(&info);
    int width = (int)info.output_width, height = (int)info.output_height;
    rgba = malloc((size_t)width * height * 4);
    if (!rgba) { jpeg_destroy_decompress(&info); return 0; }
    while (info.output_scanline < info.output_height) {
        JSAMPROW row = rgba + (size_t)info.output_scanline * width * 4;
        jpeg_read_scanlines(&info, &row, 1);
    }
    jpeg_finish_decompress(&info);
    jpeg_destroy_decompress(&info);
    return one_frame(out, rgba, width, height);
}

int perry_jpeg_encode(const uint8_t *rgba, int width, int height, int quality, int orientation, uint8_t **out, size_t *out_size) {
    struct jpeg_compress_struct info;
    jpeg_failure failure;
    info.err = jpeg_std_error(&failure.manager);
    failure.manager.error_exit = jpeg_fail;
    unsigned char *buffer = NULL;
    unsigned long length = 0;
    if (setjmp(failure.jump)) {
        jpeg_destroy_compress(&info);
        free(buffer);
        return 0;
    }
    jpeg_create_compress(&info);
    jpeg_mem_dest(&info, &buffer, &length);
    info.image_width = (JDIMENSION)width;
    info.image_height = (JDIMENSION)height;
    info.input_components = 4;
    info.in_color_space = JCS_EXT_RGBA;
    jpeg_set_defaults(&info);
    jpeg_set_quality(&info, quality, TRUE);
    jpeg_start_compress(&info, TRUE);
    if (orientation > 1) {
        // Exif, big-endian, IFD0 holding only the orientation.
        const uint8_t exif[] = {'E', 'x', 'i', 'f', 0, 0, 'M', 'M', 0, 42, 0, 0, 0, 8, 0, 1,
                                0x01, 0x12, 0, 3, 0, 0, 0, 1, 0, (uint8_t)orientation, 0, 0, 0, 0, 0, 0};
        jpeg_write_marker(&info, JPEG_APP0 + 1, exif, sizeof(exif));
    }
    while (info.next_scanline < info.image_height) {
        JSAMPROW row = (JSAMPROW)(rgba + (size_t)info.next_scanline * width * 4);
        jpeg_write_scanlines(&info, &row, 1);
    }
    jpeg_finish_compress(&info);
    jpeg_destroy_compress(&info);
    *out = buffer;
    *out_size = length;
    return 1;
}

// MARK: - GIF

typedef struct memory_reader {
    const uint8_t *data;
    size_t size, offset;
} memory_reader;

static int gif_read(GifFileType *gif, GifByteType *bytes, int count) {
    memory_reader *reader = gif->UserData;
    size_t available = reader->size - reader->offset;
    size_t n = (size_t)count < available ? (size_t)count : available;
    memcpy(bytes, reader->data + reader->offset, n);
    reader->offset += n;
    return (int)n;
}

int perry_gif_decode(const uint8_t *data, size_t size, perry_decoded *out) {
    memset(out, 0, sizeof(*out));
    memory_reader reader = {data, size, 0};
    int error = 0;
    GifFileType *gif = DGifOpen(&reader, gif_read, &error);
    if (!gif) return 0;
    if (DGifSlurp(gif) != GIF_OK || gif->ImageCount == 0) { DGifCloseFile(gif, &error); return 0; }
    int width = gif->SWidth, height = gif->SHeight;
    out->frames = calloc((size_t)gif->ImageCount, sizeof(perry_frame));
    out->components = 3;
    out->depth = 8;
    out->orientation = 1;
    out->loop_count = -1;
    out->dpi_x = out->dpi_y = 72;
    uint8_t *canvas = calloc((size_t)width * height, 4);
    for (int i = 0; i < gif->ImageCount && out->frames && canvas; i++) {
        SavedImage *frame = &gif->SavedImages[i];
        GraphicsControlBlock control = {DISPOSAL_UNSPECIFIED, 0, 0, NO_TRANSPARENT_COLOR};
        DGifSavedExtensionToGCB(gif, i, &control);
        for (int e = 0; e < frame->ExtensionBlockCount; e++) {
            ExtensionBlock *block = &frame->ExtensionBlocks[e];
            if (block->Function == APPLICATION_EXT_FUNC_CODE && block->ByteCount == 11 &&
                memcmp(block->Bytes, "NETSCAPE2.0", 11) == 0 && e + 1 < frame->ExtensionBlockCount &&
                frame->ExtensionBlocks[e + 1].ByteCount >= 3) {
                const uint8_t *sub = frame->ExtensionBlocks[e + 1].Bytes;
                out->loop_count = sub[1] | sub[2] << 8;
            }
        }
        if (control.TransparentColor != NO_TRANSPARENT_COLOR) out->has_alpha = 1;
        ColorMapObject *map = frame->ImageDesc.ColorMap ? frame->ImageDesc.ColorMap : gif->SColorMap;
        uint8_t *before = control.DisposalMode == DISPOSE_PREVIOUS ? malloc((size_t)width * height * 4) : NULL;
        if (before) memcpy(before, canvas, (size_t)width * height * 4);
        GifImageDesc *desc = &frame->ImageDesc;
        for (int y = 0; y < desc->Height; y++) {
            for (int x = 0; x < desc->Width; x++) {
                int cx = desc->Left + x, cy = desc->Top + y;
                if (cx >= width || cy >= height || !map) continue;
                int index = frame->RasterBits[y * desc->Width + x];
                if (index == control.TransparentColor || index >= map->ColorCount) continue;
                uint8_t *p = canvas + ((size_t)cy * width + cx) * 4;
                p[0] = map->Colors[index].Red;
                p[1] = map->Colors[index].Green;
                p[2] = map->Colors[index].Blue;
                p[3] = 255;
            }
        }
        uint8_t *copy = malloc((size_t)width * height * 4);
        if (copy) memcpy(copy, canvas, (size_t)width * height * 4);
        out->frames[i] = (perry_frame){copy, width, height, control.DelayTime / 100.0};
        out->count = i + 1;
        if (control.DisposalMode == DISPOSE_BACKGROUND) {
            for (int y = 0; y < desc->Height; y++)
                for (int x = 0; x < desc->Width; x++) {
                    int cx = desc->Left + x, cy = desc->Top + y;
                    if (cx < width && cy < height) memset(canvas + ((size_t)cy * width + cx) * 4, 0, 4);
                }
        } else if (before) {
            memcpy(canvas, before, (size_t)width * height * 4);
        }
        free(before);
    }
    free(canvas);
    DGifCloseFile(gif, &error);
    return out->count > 0;
}

typedef struct memory_writer {
    uint8_t *data;
    size_t size, capacity;
} memory_writer;

static int gif_write(GifFileType *gif, const GifByteType *bytes, int count) {
    memory_writer *writer = gif->UserData;
    if (writer->size + (size_t)count > writer->capacity) {
        size_t capacity = (writer->capacity + (size_t)count) * 2;
        uint8_t *grown = realloc(writer->data, capacity);
        if (!grown) return 0;
        writer->data = grown;
        writer->capacity = capacity;
    }
    memcpy(writer->data + writer->size, bytes, (size_t)count);
    writer->size += (size_t)count;
    return count;
}

/// A frame's palette: its own colors when there are at most 255, else a
/// 6x6x6 cube; index 255 is transparent.
static void gif_palette(const perry_frame *frame, GifColorType colors[256], int *count, uint8_t *indexes) {
    size_t pixels = (size_t)frame->width * frame->height;
    int used = 0, exact = 1;
    for (size_t i = 0; i < pixels && exact; i++) {
        const uint8_t *p = frame->rgba + i * 4;
        if (p[3] < 128) continue;
        int found = -1;
        for (int c = 0; c < used; c++)
            if (colors[c].Red == p[0] && colors[c].Green == p[1] && colors[c].Blue == p[2]) { found = c; break; }
        if (found < 0) {
            if (used == 255) { exact = 0; break; }
            colors[used] = (GifColorType){p[0], p[1], p[2]};
            used++;
        }
    }
    if (!exact) {
        used = 216;
        for (int r = 0; r < 6; r++)
            for (int g = 0; g < 6; g++)
                for (int b = 0; b < 6; b++) colors[r * 36 + g * 6 + b] = (GifColorType){(uint8_t)(r * 51), (uint8_t)(g * 51), (uint8_t)(b * 51)};
    }
    for (int c = used; c < 256; c++) colors[c] = (GifColorType){0, 0, 0};
    *count = 256;
    for (size_t i = 0; i < pixels; i++) {
        const uint8_t *p = frame->rgba + i * 4;
        if (p[3] < 128) { indexes[i] = 255; continue; }
        if (!exact) { indexes[i] = (uint8_t)(((p[0] + 25) / 51) * 36 + ((p[1] + 25) / 51) * 6 + (p[2] + 25) / 51); continue; }
        for (int c = 0; c < used; c++)
            if (colors[c].Red == p[0] && colors[c].Green == p[1] && colors[c].Blue == p[2]) { indexes[i] = (uint8_t)c; break; }
    }
}

int perry_gif_encode(const perry_frame *frames, int count, int loop_count, uint8_t **out, size_t *out_size) {
    if (count < 1) return 0;
    memory_writer writer = {0};
    int error = 0;
    GifFileType *gif = EGifOpen(&writer, gif_write, &error);
    if (!gif) return 0;
    int width = frames[0].width, height = frames[0].height;
    EGifSetGifVersion(gif, true);
    int ok = EGifPutScreenDesc(gif, width, height, 8, 0, NULL) == GIF_OK;
    if (ok && loop_count >= 0) {
        uint8_t loop[3] = {1, (uint8_t)(loop_count & 0xff), (uint8_t)(loop_count >> 8)};
        ok = EGifPutExtensionLeader(gif, APPLICATION_EXT_FUNC_CODE) == GIF_OK &&
             EGifPutExtensionBlock(gif, 11, "NETSCAPE2.0") == GIF_OK && EGifPutExtensionBlock(gif, 3, loop) == GIF_OK &&
             EGifPutExtensionTrailer(gif) == GIF_OK;
    }
    for (int f = 0; f < count && ok; f++) {
        const perry_frame *frame = &frames[f];
        GifColorType colors[256];
        int colorCount = 0;
        uint8_t *indexes = malloc((size_t)frame->width * frame->height);
        if (!indexes) { ok = 0; break; }
        gif_palette(frame, colors, &colorCount, indexes);
        GraphicsControlBlock control = {DISPOSAL_UNSPECIFIED, false, (int)(frame->delay * 100 + 0.5), 255};
        GifByteType extension[4];
        EGifGCBToExtension(&control, extension);
        ColorMapObject *map = GifMakeMapObject(colorCount, colors);
        ok = map && EGifPutExtension(gif, GRAPHICS_EXT_FUNC_CODE, 4, extension) == GIF_OK &&
             EGifPutImageDesc(gif, 0, 0, frame->width, frame->height, false, map) == GIF_OK;
        for (int y = 0; y < frame->height && ok; y++) ok = EGifPutLine(gif, indexes + (size_t)y * frame->width, frame->width) == GIF_OK;
        GifFreeMapObject(map);
        free(indexes);
    }
    if (EGifCloseFile(gif, &error) != GIF_OK) ok = 0;
    if (!ok) { free(writer.data); return 0; }
    *out = writer.data;
    *out_size = writer.size;
    return 1;
}

// MARK: - WebP and HEIF (reading)

int perry_webp_decode(const uint8_t *data, size_t size, perry_decoded *out) {
    memset(out, 0, sizeof(*out));
    WebPBitstreamFeatures features;
    if (WebPGetFeatures(data, size, &features) != VP8_STATUS_OK) return 0;
    int width = 0, height = 0;
    uint8_t *decoded = WebPDecodeRGBA(data, size, &width, &height);
    if (!decoded) return 0;
    uint8_t *rgba = malloc((size_t)width * height * 4);
    if (rgba) memcpy(rgba, decoded, (size_t)width * height * 4);
    WebPFree(decoded);
    if (!rgba) return 0;
    out->has_alpha = features.has_alpha;
    out->components = 3;
    out->depth = 8;
    out->dpi_x = out->dpi_y = 72;
    return one_frame(out, rgba, width, height);
}

int perry_heif_decode(const uint8_t *data, size_t size, perry_decoded *out) {
    memset(out, 0, sizeof(*out));
    struct heif_context *context = heif_context_alloc();
    struct heif_image_handle *handle = NULL;
    struct heif_image *image = NULL;
    int ok = 0;
    if (context && heif_context_read_from_memory_without_copy(context, data, size, NULL).code == heif_error_Ok &&
        heif_context_get_primary_image_handle(context, &handle).code == heif_error_Ok &&
        heif_decode_image(handle, &image, heif_colorspace_RGB, heif_chroma_interleaved_RGBA, NULL).code == heif_error_Ok) {
        int width = heif_image_get_width(image, heif_channel_interleaved);
        int height = heif_image_get_height(image, heif_channel_interleaved);
        int stride = 0;
        const uint8_t *plane = heif_image_get_plane_readonly(image, heif_channel_interleaved, &stride);
        uint8_t *rgba = plane ? malloc((size_t)width * height * 4) : NULL;
        if (rgba) {
            for (int y = 0; y < height; y++) memcpy(rgba + (size_t)y * width * 4, plane + (size_t)y * stride, (size_t)width * 4);
            out->has_alpha = heif_image_handle_has_alpha_channel(handle);
            out->components = 3;
            out->depth = heif_image_handle_get_luma_bits_per_pixel(handle);
            out->dpi_x = out->dpi_y = 72;
            ok = one_frame(out, rgba, width, height);
        }
    }
    if (image) heif_image_release(image);
    if (handle) heif_image_handle_release(handle);
    if (context) heif_context_free(context);
    return ok;
}
