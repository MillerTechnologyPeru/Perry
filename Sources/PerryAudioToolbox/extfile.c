// Extended audio files: an audio file read as frames of linear PCM in the
// format the client asks for, whatever the file holds. Built on the audio
// files of file.c: linear PCM and IMA4 are converted as they are read, and
// the files GStreamer decodes are already PCM once opened. Channels are
// remapped and the rate converted linearly. Files are read only.

#include "PerryAudioToolbox.h"

#include <math.h>
#include <stdlib.h>
#include <string.h>

// The audio files of file.c, by the names they're exported under.
OSStatus darwin_AudioFileOpenURL(const void *url, int8_t permissions, uint32_t hint, void **out) DARWIN_SYMBOL(AudioFileOpenURL);
OSStatus darwin_AudioFileClose(void *handle) DARWIN_SYMBOL(AudioFileClose);
OSStatus darwin_AudioFileGetProperty(void *handle, uint32_t id, uint32_t *size, void *value) DARWIN_SYMBOL(AudioFileGetProperty);
OSStatus darwin_AudioFileReadPacketData(void *handle, uint8_t cache, uint32_t *bytes, AudioStreamPacketDescription *descriptions,
                                        int64_t start, uint32_t *packets, void *buffer) DARWIN_SYMBOL(AudioFileReadPacketData);

typedef struct ext_file {
    uint32_t magic;
    void *file;                             // the AudioFileID
    bool owns_file;                         // opened here, so closed here
    AudioStreamBasicDescription format;     // the file's
    AudioStreamBasicDescription client;     // what reads give
    int64_t frames;                         // the file's length
    int32_t priming;                        // frames to skip at the start
    uint32_t max_packet;
    double position;                        // the next frame read, in the file's frames
    uint8_t *bytes;                         // scratch: packets as stored
    float *source, *mapped, *output;        // scratch: frames as floats
    size_t bytes_size, source_size, mapped_size, output_size;
} ext_file;

#define EXT_MAGIC FOURCC('p', 'x', 'a', 'f')
#define IMA4_FRAMES 64

#define kExtAudioFileProperty_FileDataFormat FOURCC('f', 'f', 'm', 't')
#define kExtAudioFileProperty_ClientDataFormat FOURCC('c', 'f', 'm', 't')
#define kExtAudioFileProperty_FileLengthFrames FOURCC('#', 'f', 'r', 'm')
#define kExtAudioFileProperty_AudioFile FOURCC('a', 'f', 'i', 'l')
#define kExtAudioFileProperty_AudioConverter FOURCC('a', 'c', 'n', 'v')
#define kExtAudioFileProperty_FileMaxPacketSize FOURCC('f', 'm', 'p', 's')
#define kExtAudioFileProperty_ClientMaxPacketSize FOURCC('c', 'm', 'p', 's')

#define kExtAudioFileError_InvalidProperty (-66561)
#define kExtAudioFileError_InvalidPropertySize (-66562)
#define kExtAudioFileError_NonPCMClientFormat (-66563)
#define kExtAudioFileError_InvalidDataFormat (-66566)
#define kExtAudioFileError_InvalidSeek (-66568)

static ext_file *valid(void *file) {
    ext_file *f = file;
    return f && f->magic == EXT_MAGIC ? f : NULL;
}

/// `*buffer` with room for `count` elements of `size` bytes.
static bool reserve(void *buffer, size_t *capacity, size_t count, size_t size) {
    void **b = buffer;
    if (count <= *capacity && *b) return true;
    void *grown = realloc(*b, (count ? count : 1) * size);
    if (!grown) return false;
    *b = grown;
    *capacity = count;
    return true;
}

/// Wraps an open audio file, reading what it needs to know from it.
static OSStatus wrap(void *file, bool owns, void **out) {
    ext_file *ext = calloc(1, sizeof *ext);
    if (!ext) return kAudio_MemFullError;
    uint32_t size = sizeof ext->format;
    OSStatus status = darwin_AudioFileGetProperty(file, FOURCC('d', 'f', 'm', 't'), &size, &ext->format);
    uint64_t packets = 0;
    size = sizeof packets;
    if (!status) status = darwin_AudioFileGetProperty(file, FOURCC('p', 'c', 'n', 't'), &size, &packets);
    if (status) { free(ext); return status; }
    const AudioStreamBasicDescription *f = &ext->format;
    bool pcm = f->mFormatID == kAudioFormatLinearPCM && perry_pcm_supported(f);
    bool ima4 = f->mFormatID == kAudioFormatAppleIMA4 && f->mChannelsPerFrame && f->mBytesPerPacket == 34 * f->mChannelsPerFrame;
    if (!pcm && !ima4) {
        perry_audio_warn("an extended audio file can't read format '%c%c%c%c'",
                         f->mFormatID >> 24, f->mFormatID >> 16 & 0xff, f->mFormatID >> 8 & 0xff, f->mFormatID & 0xff);
        free(ext);
        return kExtAudioFileError_InvalidDataFormat;
    }
    ext->frames = (int64_t)packets * (ima4 ? IMA4_FRAMES : 1);
    struct { int64_t valid; int32_t priming, remainder; } table;
    size = sizeof table;
    if (!darwin_AudioFileGetProperty(file, FOURCC('p', 'n', 'f', 'o'), &size, &table) && table.valid >= 0 && table.priming >= 0
        && table.valid + table.priming <= ext->frames) {
        ext->frames = table.valid;
        ext->priming = table.priming;
    }
    size = sizeof ext->max_packet;
    darwin_AudioFileGetProperty(file, FOURCC('p', 's', 'z', 'e'), &size, &ext->max_packet);
    // Until the client says otherwise: the file's own PCM, else 16 bits.
    ext->client = ext->format;
    if (!pcm) {
        ext->client = (AudioStreamBasicDescription){
            f->mSampleRate, kAudioFormatLinearPCM, kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked,
            2 * f->mChannelsPerFrame, 1, 2 * f->mChannelsPerFrame, f->mChannelsPerFrame, 16, 0,
        };
    }
    ext->magic = EXT_MAGIC;
    ext->file = file;
    ext->owns_file = owns;
    *out = ext;
    return 0;
}

// MARK: - Opening and closing

OSStatus darwin_ExtAudioFileOpenURL(const void *url, void **out) DARWIN_SYMBOL(ExtAudioFileOpenURL);
OSStatus darwin_ExtAudioFileOpenURL(const void *url, void **out) {
    if (!out) return kAudio_ParamError;
    *out = NULL;
    void *file = NULL;
    OSStatus status = darwin_AudioFileOpenURL(url, 1, 0, &file);
    if (status) return status;
    status = wrap(file, true, out);
    if (status) darwin_AudioFileClose(file);
    return status;
}

OSStatus darwin_ExtAudioFileWrapAudioFileID(void *file, uint8_t for_writing, void **out) DARWIN_SYMBOL(ExtAudioFileWrapAudioFileID);
OSStatus darwin_ExtAudioFileWrapAudioFileID(void *file, uint8_t for_writing, void **out) {
    if (!out) return kAudio_ParamError;
    *out = NULL;
    if (for_writing) return -54;        // kAudioFilePermissionsError
    return wrap(file, false, out);
}

OSStatus darwin_ExtAudioFileDispose(void *handle) DARWIN_SYMBOL(ExtAudioFileDispose);
OSStatus darwin_ExtAudioFileDispose(void *handle) {
    ext_file *ext = valid(handle);
    if (!ext) return kAudio_ParamError;
    ext->magic = 0;
    if (ext->owns_file) darwin_AudioFileClose(ext->file);
    free(ext->bytes);
    free(ext->source);
    free(ext->mapped);
    free(ext->output);
    free(ext);
    return 0;
}

// MARK: - Properties

/// The property's size and whether it can be set; false if there's none.
static bool describe(uint32_t id, uint32_t *size, bool *writable) {
    *writable = false;
    switch (id) {
    case kExtAudioFileProperty_FileDataFormat: *size = sizeof(AudioStreamBasicDescription); return true;
    case kExtAudioFileProperty_ClientDataFormat: *size = sizeof(AudioStreamBasicDescription); *writable = true; return true;
    case kExtAudioFileProperty_FileLengthFrames: *size = 8; return true;
    case kExtAudioFileProperty_AudioFile: case kExtAudioFileProperty_AudioConverter: *size = sizeof(void *); return true;
    case kExtAudioFileProperty_FileMaxPacketSize: case kExtAudioFileProperty_ClientMaxPacketSize: *size = 4; return true;
    default:
        perry_audio_trace("unsupported extended file property '%c%c%c%c'", id >> 24, id >> 16 & 0xff, id >> 8 & 0xff, id & 0xff);
        return false;
    }
}

OSStatus darwin_ExtAudioFileGetPropertyInfo(void *handle, uint32_t id, uint32_t *size, uint8_t *writable)
    DARWIN_SYMBOL(ExtAudioFileGetPropertyInfo);
OSStatus darwin_ExtAudioFileGetPropertyInfo(void *handle, uint32_t id, uint32_t *size, uint8_t *writable) {
    if (!valid(handle)) return kAudio_ParamError;
    uint32_t length;
    bool settable;
    if (!describe(id, &length, &settable)) return kExtAudioFileError_InvalidProperty;
    if (size) *size = length;
    if (writable) *writable = settable;
    return 0;
}

OSStatus darwin_ExtAudioFileGetProperty(void *handle, uint32_t id, uint32_t *size, void *value) DARWIN_SYMBOL(ExtAudioFileGetProperty);
OSStatus darwin_ExtAudioFileGetProperty(void *handle, uint32_t id, uint32_t *size, void *value) {
    ext_file *ext = valid(handle);
    if (!ext || !size || !value) return kAudio_ParamError;
    uint32_t length;
    bool settable;
    if (!describe(id, &length, &settable)) return kExtAudioFileError_InvalidProperty;
    if (*size < length) return kExtAudioFileError_InvalidPropertySize;
    union {
        AudioStreamBasicDescription format;
        int64_t frames;
        void *pointer;
        uint32_t u32;
    } v;
    memset(&v, 0, sizeof v);
    switch (id) {
    case kExtAudioFileProperty_FileDataFormat: v.format = ext->format; break;
    case kExtAudioFileProperty_ClientDataFormat: v.format = ext->client; break;
    case kExtAudioFileProperty_FileLengthFrames: v.frames = ext->frames; break;
    case kExtAudioFileProperty_AudioFile: v.pointer = ext->file; break;
    case kExtAudioFileProperty_AudioConverter: v.pointer = NULL; break;     // conversion is done here
    case kExtAudioFileProperty_FileMaxPacketSize: v.u32 = ext->max_packet; break;
    case kExtAudioFileProperty_ClientMaxPacketSize: v.u32 = ext->client.mBytesPerPacket; break;
    }
    memcpy(value, &v, length);
    *size = length;
    return 0;
}

OSStatus darwin_ExtAudioFileSetProperty(void *handle, uint32_t id, uint32_t size, const void *value) DARWIN_SYMBOL(ExtAudioFileSetProperty);
OSStatus darwin_ExtAudioFileSetProperty(void *handle, uint32_t id, uint32_t size, const void *value) {
    ext_file *ext = valid(handle);
    if (!ext || !value) return kAudio_ParamError;
    uint32_t length;
    bool settable;
    if (!describe(id, &length, &settable) || !settable) return kExtAudioFileError_InvalidProperty;
    if (size < length) return kExtAudioFileError_InvalidPropertySize;
    AudioStreamBasicDescription format;
    memcpy(&format, value, sizeof format);
    if (format.mFormatID != kAudioFormatLinearPCM) return kExtAudioFileError_NonPCMClientFormat;
    if (!perry_pcm_supported(&format) || !format.mChannelsPerFrame || !format.mBytesPerFrame) {
        return kAudioConverterErr_FormatNotSupported;
    }
    ext->client = format;
    return 0;
}

// MARK: - Reading

/// `count` of the file's frames from `first`, as interleaved floats of the
/// file's channels in `ext->source`. The frames are within the file.
static bool load(ext_file *ext, int64_t first, size_t count) {
    const AudioStreamBasicDescription *f = &ext->format;
    uint32_t channels = f->mChannelsPerFrame;
    if (!reserve(&ext->source, &ext->source_size, count * channels, sizeof(float))) return false;
    first += ext->priming;
    if (f->mFormatID == kAudioFormatLinearPCM) {
        uint32_t bytes = (uint32_t)(count * f->mBytesPerFrame), packets = (uint32_t)count;
        if (!reserve(&ext->bytes, &ext->bytes_size, bytes, 1)) return false;
        if (darwin_AudioFileReadPacketData(ext->file, 0, &bytes, NULL, first, &packets, ext->bytes) || packets != count) return false;
        AudioBufferList list = { 1, { { channels, bytes, ext->bytes } } };
        perry_pcm_read(f, &list, 0, count, ext->source);
        return true;
    }
    // IMA4: whole packets, each decoded on its own.
    float decoded[IMA4_FRAMES * 8];
    float *packet = channels <= 8 ? decoded : malloc(IMA4_FRAMES * channels * sizeof(float));
    if (!packet || !reserve(&ext->bytes, &ext->bytes_size, f->mBytesPerPacket, 1)) return false;
    bool ok = true;
    for (size_t done = 0; done < count && ok;) {
        int64_t index = (first + (int64_t)done) / IMA4_FRAMES;
        size_t skip = (size_t)((first + (int64_t)done) % IMA4_FRAMES);
        size_t take = IMA4_FRAMES - skip < count - done ? IMA4_FRAMES - skip : count - done;
        uint32_t bytes = f->mBytesPerPacket, packets = 1;
        ok = !darwin_AudioFileReadPacketData(ext->file, 0, &bytes, NULL, index, &packets, ext->bytes) && packets == 1;
        if (!ok) break;
        perry_ima4_decode(ext->bytes, channels, packet);
        memcpy(ext->source + done * channels, packet + skip * channels, take * channels * sizeof(float));
        done += take;
    }
    if (packet != decoded) free(packet);
    return ok;
}

OSStatus darwin_ExtAudioFileRead(void *handle, uint32_t *frames, AudioBufferList *data) DARWIN_SYMBOL(ExtAudioFileRead);
OSStatus darwin_ExtAudioFileRead(void *handle, uint32_t *frames, AudioBufferList *data) {
    ext_file *ext = valid(handle);
    if (!ext || !frames || !data || !data->mNumberBuffers) return kAudio_ParamError;
    const AudioStreamBasicDescription *client = &ext->client;
    uint32_t file_channels = ext->format.mChannelsPerFrame, channels = client->mChannelsPerFrame;
    // What the buffers hold; a non-interleaved format's frame is one channel's.
    size_t wanted = *frames;
    for (uint32_t i = 0; i < data->mNumberBuffers; i++) {
        size_t room = data->mBuffers[i].mData ? data->mBuffers[i].mDataByteSize / client->mBytesPerFrame : 0;
        if (room < wanted) wanted = room;
    }
    double step = ext->format.mSampleRate > 0 && client->mSampleRate > 0 ? ext->format.mSampleRate / client->mSampleRate : 1;
    size_t done = 0;
    while (done < wanted) {
        int64_t start = (int64_t)floor(ext->position);
        if (start >= ext->frames) break;
        size_t count = wanted - done < 4096 ? wanted - done : 4096;
        // The frames whose place in the file is before its end.
        double left = ((double)ext->frames - ext->position) / step;
        if (left < (double)count) count = (size_t)ceil(left);
        if (!count) break;
        int64_t last = (int64_t)floor(ext->position + (double)(count - 1) * step) + 1;      // the frame after, to interpolate with
        if (last >= ext->frames) last = ext->frames - 1;
        size_t loaded = (size_t)(last - start + 1);
        if (!load(ext, start, loaded)) return kAudioFileUnspecifiedError;
        const float *mapped = ext->source;
        if (channels != file_channels) {
            if (!reserve(&ext->mapped, &ext->mapped_size, loaded * channels, sizeof(float))) return kAudio_MemFullError;
            perry_pcm_remap(ext->source, file_channels, ext->mapped, channels, loaded);
            mapped = ext->mapped;
        }
        const float *output = mapped;
        if (step != 1) {
            if (!reserve(&ext->output, &ext->output_size, count * channels, sizeof(float))) return kAudio_MemFullError;
            for (size_t i = 0; i < count; i++) {
                double place = ext->position + (double)i * step - (double)start;
                size_t a = (size_t)place, b = a + 1 < loaded ? a + 1 : loaded - 1;
                if (a >= loaded) a = loaded - 1;
                float t = (float)(place - (double)a);
                for (uint32_t c = 0; c < channels; c++) {
                    ext->output[i * channels + c] = mapped[a * channels + c] * (1 - t) + mapped[b * channels + c] * t;
                }
            }
            output = ext->output;
        }
        perry_pcm_write(client, data, done, count, output);
        done += count;
        ext->position += (double)count * step;
    }
    for (uint32_t i = 0; i < data->mNumberBuffers; i++) {
        data->mBuffers[i].mDataByteSize = (uint32_t)(done * client->mBytesPerFrame);
    }
    *frames = (uint32_t)done;
    return 0;
}

OSStatus darwin_ExtAudioFileSeek(void *handle, int64_t frame) DARWIN_SYMBOL(ExtAudioFileSeek);
OSStatus darwin_ExtAudioFileSeek(void *handle, int64_t frame) {
    ext_file *ext = valid(handle);
    if (!ext) return kAudio_ParamError;
    if (frame < 0) return kExtAudioFileError_InvalidSeek;
    ext->position = (double)frame;
    return 0;
}

OSStatus darwin_ExtAudioFileTell(void *handle, int64_t *frame) DARWIN_SYMBOL(ExtAudioFileTell);
OSStatus darwin_ExtAudioFileTell(void *handle, int64_t *frame) {
    ext_file *ext = valid(handle);
    if (!ext || !frame) return kAudio_ParamError;
    *frame = (int64_t)floor(ext->position);
    return 0;
}
