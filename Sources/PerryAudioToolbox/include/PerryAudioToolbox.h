#ifndef PERRY_AUDIO_TOOLBOX_H
#define PERRY_AUDIO_TOOLBOX_H

// libPerryAudioToolbox: the provider for AudioToolbox.framework.
//
// - System sounds: created and disposed of; playing one finishes at once.
// - Audio files: CAF, WAV, AIFF and AAC in MPEG-4 (M4A) are read as they
//   are, their packets in the file's own format; other files GStreamer can
//   decode (MP3, Ogg, Apple Lossless) are decoded when opened and read as
//   16-bit PCM.
// - Audio converters: linear PCM to linear PCM, with any sample rate and
//   channel count, and Apple's IMA4 to linear PCM.
// - Audio queues: output queues, played through GStreamer, which decodes
//   the compressed formats.
// - Audio units: RemoteIO, the multichannel mixer and the 3D mixer, mixed
//   here and played through GStreamer.

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#define DARWIN_SYMBOL(name) __asm__("_" #name) __attribute__((visibility("default"), used))

// For a function with floating-point parameters: 32-bit Darwin passes them
// in core registers and on the stack, as AAPCS's base standard does, where
// Linux's armhf passes them in VFP registers.
#if defined(__arm__)
#define DARWIN_FLOAT_ABI __attribute__((pcs("aapcs")))
#else
#define DARWIN_FLOAT_ABI
#endif

typedef int32_t OSStatus;
typedef uint32_t SystemSoundID;
typedef uint32_t AudioServicesPropertyID;

#define FOURCC(a, b, c, d) (((uint32_t)(a) << 24) | ((uint32_t)(b) << 16) | ((uint32_t)(c) << 8) | (uint32_t)(d))

// MARK: - CoreAudio types, as Darwin lays them out on arm64

typedef struct AudioStreamBasicDescription {
    double mSampleRate;
    uint32_t mFormatID;
    uint32_t mFormatFlags;
    uint32_t mBytesPerPacket;
    uint32_t mFramesPerPacket;
    uint32_t mBytesPerFrame;
    uint32_t mChannelsPerFrame;
    uint32_t mBitsPerChannel;
    uint32_t mReserved;
} AudioStreamBasicDescription;

typedef struct AudioStreamPacketDescription {
    int64_t mStartOffset;
    uint32_t mVariableFramesInPacket;
    uint32_t mDataByteSize;
} AudioStreamPacketDescription;

typedef struct AudioBuffer {
    uint32_t mNumberChannels;
    uint32_t mDataByteSize;
    void *mData;
} AudioBuffer;

typedef struct AudioBufferList {
    uint32_t mNumberBuffers;
    AudioBuffer mBuffers[1];
} AudioBufferList;

typedef struct AudioTimeStamp {
    double mSampleTime;
    uint64_t mHostTime;
    double mRateScalar;
    uint64_t mWordClockTime;
    uint8_t mSMPTETime[24];
    uint32_t mFlags;
    uint32_t mReserved;
} AudioTimeStamp;

#define kAudioTimeStampSampleTimeValid (1u << 0)
#define kAudioTimeStampHostTimeValid (1u << 1)

// Formats and their flags.
#define kAudioFormatLinearPCM FOURCC('l', 'p', 'c', 'm')
#define kAudioFormatAppleIMA4 FOURCC('i', 'm', 'a', '4')
#define kAudioFormatMPEG4AAC FOURCC('a', 'a', 'c', ' ')
#define kAudioFormatMPEGLayer3 FOURCC('.', 'm', 'p', '3')
#define kAudioFormatFlagIsFloat (1u << 0)
#define kAudioFormatFlagIsBigEndian (1u << 1)
#define kAudioFormatFlagIsSignedInteger (1u << 2)
#define kAudioFormatFlagIsPacked (1u << 3)
#define kAudioFormatFlagIsNonInterleaved (1u << 5)
#define kLinearPCMFormatFlagsSampleFractionShift 7
#define kLinearPCMFormatFlagsSampleFractionMask (0x3Fu << kLinearPCMFormatFlagsSampleFractionShift)

// Errors.
#define kAudio_ParamError (-50)
#define kAudio_MemFullError (-108)
#define kAudioFileUnspecifiedError FOURCC('w', 'h', 't', '?')
#define kAudioFileUnsupportedFileTypeError FOURCC('t', 'y', 'p', '?')
#define kAudioFileUnsupportedDataFormatError FOURCC('f', 'm', 't', '?')
#define kAudioFileUnsupportedPropertyError FOURCC('p', 't', 'y', '?')
#define kAudioFileBadPropertySizeError FOURCC('!', 's', 'i', 'z')
#define kAudioFileInvalidFileError FOURCC('d', 't', 'a', '?')
#define kAudioFileNotOpenError (-38)
#define kAudioFileEndOfFileError (-39)
#define kAudioFileInvalidPacketOffsetError (-66678)
#define kAudioConverterErr_FormatNotSupported FOURCC('f', 'm', 't', '?')
#define kAudioConverterErr_PropertyNotSupported FOURCC('p', 'r', 'o', 'p')
#define kAudioConverterErr_InvalidInputSize FOURCC('i', 'n', 's', 'z')
#define kAudioQueueErr_InvalidBuffer (-66687)
#define kAudioQueueErr_InvalidQueueType (-66682)
#define kAudioQueueErr_InvalidProperty (-66680)
#define kAudioQueueErr_InvalidParameter (-66673)
#define kAudioUnitErr_InvalidProperty (-10879)
#define kAudioUnitErr_InvalidParameter (-10878)
#define kAudioUnitErr_InvalidElement (-10877)
#define kAudioUnitErr_InvalidScope (-10866)
#define kAudioUnitErr_FormatNotSupported (-10868)
#define kAudioUnitErr_Uninitialized (-10867)
#define kAudioUnitErr_InvalidPropertyValue (-10851)
#define kAudioUnitErr_NoConnection (-10876)

// MARK: - Shared within the provider

/// Looks up another library's Darwin symbol, as the loader resolves it.
void *perry_audio_lookup(const char *install_name, const char *name);

/// A file path from a CFURLRef, in `buffer`; false if it has none.
bool perry_audio_url_path(const void *url, char *buffer, size_t size);

/// Logged once per message when PERRY_TRACE_AUDIO is set.
void perry_audio_trace(const char *format, ...) __attribute__((format(printf, 1, 2)));
void perry_audio_warn(const char *format, ...) __attribute__((format(printf, 1, 2)));

/// Whether `format` is linear PCM this provider reads and writes: 8, 16,
/// 24 and 32-bit integers (any fixed-point fraction), 32 and 64-bit floats,
/// either byte order, interleaved or not.
bool perry_pcm_supported(const AudioStreamBasicDescription *format);

/// `frames` frames of `format` from `buffers` (one per channel when
/// non-interleaved), as interleaved floats of format's channels.
void perry_pcm_read(const AudioStreamBasicDescription *format, const AudioBufferList *buffers,
                    size_t first_frame, size_t frames, float *out);
/// The reverse: interleaved floats into `buffers` in `format`.
void perry_pcm_write(const AudioStreamBasicDescription *format, AudioBufferList *buffers,
                     size_t first_frame, size_t frames, const float *in);
/// Interleaved floats from `in_channels` channels to `out_channels`: mono
/// copied to each, others mixed down to mono or dropped.
void perry_pcm_remap(const float *in, uint32_t in_channels, float *out, uint32_t out_channels, size_t frames);

/// Decodes one IMA4 packet (34 bytes a channel, 64 frames) to interleaved
/// floats.
void perry_ima4_decode(const uint8_t *packet, uint32_t channels, float *out);

// GStreamer, loaded the first time it's needed.

typedef struct perry_gst perry_gst;
struct perry_gst {
    void *(*parse_launch)(const char *description, void **error);
    /// gst_element_factory_find: whether an element can be made; optional.
    void *(*factory_find)(const char *name);
    void *(*bin_get_by_name)(void *bin, const char *name);
    int (*set_state)(void *element, int state);
    int (*get_state)(void *element, int *state, int *pending, uint64_t timeout);
    void *(*get_bus)(void *element);
    void *(*bus_pop_filtered)(void *bus, uint32_t types);
    void *(*bus_timed_pop_filtered)(void *bus, uint64_t timeout, uint32_t types);
    void (*object_unref)(void *object);
    void (*mini_object_unref)(void *object);
    void *(*buffer_new_allocate)(void *allocator, size_t size, void *params);
    size_t (*buffer_fill)(void *buffer, size_t offset, const void *data, size_t size);
    int (*buffer_map)(void *buffer, void *info, int flags);
    void (*buffer_unmap)(void *buffer, void *info);
    int (*app_src_push_buffer)(void *src, void *buffer);
    int (*app_src_end_of_stream)(void *src);
    void *(*app_sink_try_pull_sample)(void *sink, uint64_t timeout);
    void *(*sample_get_buffer)(void *sample);
    void *(*sample_get_caps)(void *sample);
    void *(*caps_get_structure)(void *caps, uint32_t index);
    int (*structure_get_int)(void *structure, const char *field, int *value);
    void (*object_set)(void *object, const char *first, ...);
    void (*message_parse_error)(void *message, void **error, char **debug);
    int (*element_send_event)(void *element, void *event);
    void *(*event_new_flush_start)(void);
    void *(*event_new_flush_stop)(int reset_time);
};

/// GStreamer, initialized; NULL when it isn't installed.
/// Turns an open audio file (an AudioFileID) of compressed audio into its
/// decoded PCM.
OSStatus perry_audio_file_decode(void *file);

const perry_gst *perry_gst_get(void);

#define PERRY_GST_STATE_NULL 1
#define PERRY_GST_STATE_READY 2
#define PERRY_GST_STATE_PAUSED 3
#define PERRY_GST_STATE_PLAYING 4
#define PERRY_GST_MESSAGE_EOS (1u << 0)
#define PERRY_GST_MESSAGE_ERROR (1u << 1)
#define PERRY_GST_SECOND 1000000000ull
#define PERRY_GST_MAP_READ 1
/// GstMapInfo's size (at most), and where its data and size are: after its
/// memory pointer and flags, a word each with the flags' padding.
#define PERRY_GST_MAP_INFO_SIZE 104
#define PERRY_GST_MAP_INFO_DATA (2 * sizeof(void *))
#define PERRY_GST_MAP_INFO_LENGTH (3 * sizeof(void *))

/// Sets a buffer's presentation time and duration (GstBuffer's pts and
/// duration fields, after its GstMiniObject and pool).
void perry_gst_buffer_set_time(void *buffer, uint64_t pts, uint64_t duration);

/// The first error a pipeline's bus holds, logged; true if there was one.
bool perry_gst_check_error(const perry_gst *gst, void *pipeline, const char *what);

/// Caps for `format`'s data as GStreamer names it, or false when GStreamer
/// can't play it from packets. `cookie` is the magic cookie, if any.
bool perry_gst_caps(const AudioStreamBasicDescription *format, const void *cookie, uint32_t cookie_size,
                    char *caps, size_t size);

/// Decodes a whole file's bytes with GStreamer to interleaved 16-bit PCM,
/// malloc'd in `*samples`; false if GStreamer can't.
bool perry_gst_decode(const void *data, size_t size, int16_t **samples, size_t *frames,
                      uint32_t *rate, uint32_t *channels);

#endif
