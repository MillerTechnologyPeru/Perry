// Audio files, read whole when opened. CAF, WAV, AIFF/AIFC and AAC in MPEG-4
// (M4A) are parsed here and read in their own format, their packets as
// stored; anything else GStreamer can decode (MP3, Ogg, Apple Lossless…) is
// decoded when opened and read as interleaved 16-bit PCM. Files are read
// only.

#include "PerryAudioToolbox.h"

#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

typedef OSStatus (*read_proc)(void *data, int64_t position, uint32_t count, void *buffer, uint32_t *actual);
typedef int64_t (*size_proc)(void *data);

typedef struct audio_file {
    uint32_t magic;
    uint32_t type;                      // AudioFileTypeID
    AudioStreamBasicDescription format;
    uint8_t *bytes;                     // the whole file, or decoded PCM
    size_t size;
    size_t data_offset, data_size;      // the audio data within bytes
    uint8_t *cookie;
    uint32_t cookie_size;
    uint64_t packets;
    /// Each packet's offset and size, for formats with variable packets.
    AudioStreamPacketDescription *table;
    uint32_t max_packet;
    int64_t valid_frames;               // from a CAF packet table; -1 if none
    int32_t priming, remainder;
    /// Opened with callbacks: audio is read through them, at its place in
    /// the file, as Darwin's reads do (apps watch where the reads go).
    read_proc read;
    void *client;
    bool decoded;                       // bytes are GStreamer's PCM, not the file's
} audio_file;

#define FILE_MAGIC FOURCC('p', 'a', 'f', 'l')

// AudioFileTypeIDs.
#define kAudioFileCAFType FOURCC('c', 'a', 'f', 'f')
#define kAudioFileWAVEType FOURCC('W', 'A', 'V', 'E')
#define kAudioFileAIFFType FOURCC('A', 'I', 'F', 'F')
#define kAudioFileAIFCType FOURCC('A', 'I', 'F', 'C')
#define kAudioFileMP3Type FOURCC('M', 'P', 'G', '3')
#define kAudioFileM4AType FOURCC('m', '4', 'a', 'f')

static uint32_t be32(const uint8_t *p) { return (uint32_t)p[0] << 24 | (uint32_t)p[1] << 16 | (uint32_t)p[2] << 8 | p[3]; }
static uint16_t be16(const uint8_t *p) { return (uint16_t)(p[0] << 8 | p[1]); }
static uint64_t be64(const uint8_t *p) { return (uint64_t)be32(p) << 32 | be32(p + 4); }
static uint32_t le32(const uint8_t *p) { return (uint32_t)p[3] << 24 | (uint32_t)p[2] << 16 | (uint32_t)p[1] << 8 | p[0]; }
static uint16_t le16(const uint8_t *p) { return (uint16_t)(p[1] << 8 | p[0]); }

static double be_double(const uint8_t *p) {
    uint64_t bits = be64(p);
    double value;
    memcpy(&value, &bits, 8);
    return value;
}

/// An 80-bit IEEE extended float, as AIFF stores its rate.
static double extended(const uint8_t *p) {
    int exponent = ((p[0] & 0x7f) << 8 | p[1]) - 16383 - 63;
    uint64_t mantissa = be64(p + 2);
    double value = ldexp((double)mantissa, exponent);
    return (p[0] & 0x80) ? -value : value;
}

static void lpcm(AudioStreamBasicDescription *f, double rate, uint32_t channels, uint32_t bits, bool is_float, bool big, bool is_signed) {
    memset(f, 0, sizeof *f);
    f->mSampleRate = rate;
    f->mFormatID = kAudioFormatLinearPCM;
    f->mFormatFlags = kAudioFormatFlagIsPacked | (is_float ? kAudioFormatFlagIsFloat : (is_signed ? kAudioFormatFlagIsSignedInteger : 0))
        | (big ? kAudioFormatFlagIsBigEndian : 0);
    f->mChannelsPerFrame = channels;
    f->mBitsPerChannel = bits;
    f->mBytesPerFrame = channels * ((bits + 7) / 8);
    f->mBytesPerPacket = f->mBytesPerFrame;
    f->mFramesPerPacket = 1;
}

/// A CAF packet table's variable-length integer.
static bool varint(const uint8_t **p, const uint8_t *end, uint64_t *value) {
    *value = 0;
    while (*p < end) {
        uint8_t byte = *(*p)++;
        *value = *value << 7 | (byte & 0x7f);
        if (!(byte & 0x80)) return true;
    }
    return false;
}

static OSStatus parse_caf(audio_file *file) {
    const uint8_t *b = file->bytes, *end = b + file->size;
    if (file->size < 8 || be16(b + 4) != 1) return kAudioFileInvalidFileError;
    const uint8_t *pakt = NULL;
    uint64_t pakt_size = 0;
    bool have_desc = false, have_data = false;
    for (const uint8_t *p = b + 8; p + 12 <= end;) {
        uint32_t type = be32(p);
        int64_t size = (int64_t)be64(p + 4);
        const uint8_t *body = p + 12;
        if (size < 0 || (uint64_t)size > (uint64_t)(end - body)) size = end - body;  // a data chunk to the end
        switch (type) {
        case FOURCC('d', 'e', 's', 'c'):
            if (size < 32) return kAudioFileInvalidFileError;
            memset(&file->format, 0, sizeof file->format);
            file->format.mSampleRate = be_double(body);
            file->format.mFormatID = be32(body + 8);
            file->format.mFormatFlags = be32(body + 12);
            file->format.mBytesPerPacket = be32(body + 16);
            file->format.mFramesPerPacket = be32(body + 20);
            file->format.mChannelsPerFrame = be32(body + 24);
            file->format.mBitsPerChannel = be32(body + 28);
            if (file->format.mFormatID == kAudioFormatLinearPCM) {
                // CAF's flags: float and little-endian only; integers are signed.
                uint32_t flags = file->format.mFormatFlags;
                bool is_float = flags & 1, little = flags & 2;
                lpcm(&file->format, file->format.mSampleRate, file->format.mChannelsPerFrame, file->format.mBitsPerChannel,
                     is_float, !little, true);
            } else if (file->format.mBytesPerPacket && file->format.mFramesPerPacket == 1) {
                file->format.mBytesPerFrame = file->format.mBytesPerPacket;
            }
            have_desc = true;
            break;
        case FOURCC('d', 'a', 't', 'a'):
            if (size < 4) return kAudioFileInvalidFileError;
            file->data_offset = (size_t)(body + 4 - b);    // after the edit count
            file->data_size = (size_t)size - 4;
            have_data = true;
            break;
        case FOURCC('k', 'u', 'k', 'i'):
            free(file->cookie);
            file->cookie = malloc((size_t)size ? (size_t)size : 1);
            memcpy(file->cookie, body, (size_t)size);
            file->cookie_size = (uint32_t)size;
            break;
        case FOURCC('p', 'a', 'k', 't'):
            pakt = body;
            pakt_size = (uint64_t)size;
            break;
        }
        p = body + size;
    }
    if (!have_desc || !have_data) return kAudioFileInvalidFileError;
    AudioStreamBasicDescription *f = &file->format;
    if (f->mBytesPerPacket) {
        file->packets = file->data_size / f->mBytesPerPacket;
        file->max_packet = f->mBytesPerPacket;
    }
    if (pakt && pakt_size >= 24) {
        uint64_t count = be64(pakt);
        file->valid_frames = (int64_t)be64(pakt + 8);
        file->priming = (int32_t)be32(pakt + 16);
        file->remainder = (int32_t)be32(pakt + 20);
        if (!f->mBytesPerPacket || !f->mFramesPerPacket) {
            const uint8_t *q = pakt + 24, *q_end = pakt + pakt_size;
            if (count > file->data_size) return kAudioFileInvalidFileError;
            file->table = calloc(count ? count : 1, sizeof *file->table);
            uint64_t offset = 0;
            for (uint64_t i = 0; i < count; i++) {
                uint64_t size = f->mBytesPerPacket, frames = 0;
                if (!f->mBytesPerPacket && !varint(&q, q_end, &size)) return kAudioFileInvalidFileError;
                if (!f->mFramesPerPacket && !varint(&q, q_end, &frames)) return kAudioFileInvalidFileError;
                if (offset + size > file->data_size) { count = i; break; }
                file->table[i] = (AudioStreamPacketDescription){ (int64_t)offset, (uint32_t)frames, (uint32_t)size };
                if (size > file->max_packet) file->max_packet = (uint32_t)size;
                offset += size;
            }
            file->packets = count;
        }
    } else if (!f->mBytesPerPacket) {
        return kAudioFileInvalidFileError;     // variable packets need a table
    }
    file->type = kAudioFileCAFType;
    return 0;
}

static OSStatus parse_wave(audio_file *file) {
    const uint8_t *b = file->bytes, *end = b + file->size;
    bool have_fmt = false;
    for (const uint8_t *p = b + 12; p + 8 <= end;) {
        uint32_t size = le32(p + 4);
        const uint8_t *body = p + 8;
        if (size > (uint64_t)(end - body)) size = (uint32_t)(end - body);
        if (!memcmp(p, "fmt ", 4) && size >= 16) {
            uint16_t tag = le16(body), channels = le16(body + 2), bits = le16(body + 14);
            uint32_t rate = le32(body + 4);
            if (tag == 0xfffe && size >= 26) tag = le16(body + 24);     // WAVE_FORMAT_EXTENSIBLE's sub-format
            if (tag != 1 && tag != 3) return kAudioFileUnsupportedDataFormatError;
            lpcm(&file->format, rate, channels, bits, tag == 3, false, bits > 8);
            have_fmt = true;
        } else if (!memcmp(p, "data", 4)) {
            file->data_offset = (size_t)(body - b);
            file->data_size = size;
        }
        p = body + size + (size & 1);
    }
    if (!have_fmt || !file->data_offset || !file->format.mBytesPerPacket) return kAudioFileInvalidFileError;
    file->packets = file->data_size / file->format.mBytesPerPacket;
    file->max_packet = file->format.mBytesPerPacket;
    file->type = kAudioFileWAVEType;
    return 0;
}

static OSStatus parse_aiff(audio_file *file, bool aifc) {
    const uint8_t *b = file->bytes, *end = b + file->size;
    bool have_comm = false;
    for (const uint8_t *p = b + 12; p + 8 <= end;) {
        uint32_t size = be32(p + 4);
        const uint8_t *body = p + 8;
        if (size > (uint64_t)(end - body)) size = (uint32_t)(end - body);
        if (!memcmp(p, "COMM", 4) && size >= 18) {
            uint16_t channels = be16(body), bits = be16(body + 6);
            double rate = extended(body + 8);
            uint32_t compression = (aifc && size >= 22) ? be32(body + 18) : FOURCC('N', 'O', 'N', 'E');
            switch (compression) {
            case FOURCC('N', 'O', 'N', 'E'): lpcm(&file->format, rate, channels, bits, false, true, true); break;
            case FOURCC('s', 'o', 'w', 't'): lpcm(&file->format, rate, channels, bits, false, false, true); break;
            case FOURCC('f', 'l', '3', '2'): case FOURCC('F', 'L', '3', '2'): lpcm(&file->format, rate, channels, 32, true, true, true); break;
            case FOURCC('f', 'l', '6', '4'): case FOURCC('F', 'L', '6', '4'): lpcm(&file->format, rate, channels, 64, true, true, true); break;
            case FOURCC('i', 'm', 'a', '4'):
                memset(&file->format, 0, sizeof file->format);
                file->format = (AudioStreamBasicDescription){ rate, kAudioFormatAppleIMA4, 0, 34 * channels, 64, 0, channels, 0, 0 };
                break;
            default: return kAudioFileUnsupportedDataFormatError;
            }
            have_comm = true;
        } else if (!memcmp(p, "SSND", 4) && size >= 8) {
            uint32_t offset = be32(body);
            file->data_offset = (size_t)(body + 8 + offset - b);
            file->data_size = size - 8 - offset;
        }
        p = body + size + (size & 1);
    }
    if (!have_comm || !file->data_offset || !file->format.mBytesPerPacket) return kAudioFileInvalidFileError;
    file->packets = file->data_size / file->format.mBytesPerPacket;
    file->max_packet = file->format.mBytesPerPacket;
    file->type = aifc ? kAudioFileAIFCType : kAudioFileAIFFType;
    return 0;
}

/// Anything else GStreamer decodes, kept as 16-bit PCM in place of the
/// file's bytes.
// MARK: - MPEG-4

/// The atom of `type` among those in [p, end): its body and the body's end.
static bool atom(const uint8_t *p, const uint8_t *end, uint32_t type, const uint8_t **body, const uint8_t **body_end) {
    while (end - p >= 8) {
        uint64_t size = be32(p);
        const uint8_t *start = p + 8;
        if (size == 1) {
            if (end - p < 16) return false;
            size = be64(p + 8);
            start = p + 16;
        } else if (size == 0) {
            size = (uint64_t)(end - p);
        }
        if (size < (uint64_t)(start - p) || size > (uint64_t)(end - p)) return false;
        if (be32(p + 4) == type) {
            *body = start;
            *body_end = p + size;
            return true;
        }
        p += size;
    }
    return false;
}

/// The atom at the end of a path of types, each inside the one before.
static bool atom_at(const uint8_t *p, const uint8_t *end, const uint32_t *path, int count, const uint8_t **body,
                    const uint8_t **body_end) {
    for (int i = 0; i < count; i++) {
        if (!atom(p, end, path[i], &p, &end)) return false;
    }
    *body = p;
    *body_end = end;
    return true;
}

/// The length of an MPEG-4 descriptor, after its tag.
static bool descriptor_size(const uint8_t **p, const uint8_t *end, uint32_t *size) {
    uint32_t value = 0;
    for (int i = 0; i < 4; i++) {
        if (*p >= end) return false;
        uint8_t byte = *(*p)++;
        value = value << 7 | (byte & 0x7f);
        if (!(byte & 0x80)) {
            *size = value;
            return true;
        }
    }
    return false;
}

/// The AudioSpecificConfig in an ES_Descriptor, when the stream is MPEG-4
/// audio.
static bool audio_config(const uint8_t *p, const uint8_t *end, const uint8_t **config, uint32_t *config_size) {
    uint32_t size;
    if (p >= end || *p++ != 0x03 || !descriptor_size(&p, end, &size) || end - p < 3) return false;
    uint8_t flags = p[2];
    p += 3;
    if (flags & 0x80) p += 2;                               // depends on another stream
    if (flags & 0x40) { if (p >= end) return false; p += 1 + *p; }   // a URL
    if (flags & 0x20) p += 2;                               // a clock reference stream
    if (p >= end || *p++ != 0x04 || !descriptor_size(&p, end, &size) || end - p < 13) return false;
    if (p[0] != 0x40) return false;                         // objectTypeIndication: MPEG-4 audio
    p += 13;
    if (p >= end || *p++ != 0x05 || !descriptor_size(&p, end, &size) || size < 2 || (uint32_t)(end - p) < size) return false;
    *config = p;
    *config_size = size;
    return true;
}

/// An MPEG-4 file whose sound track is AAC-LC: the packets as stored, each
/// 1024 frames, and the track's ES_Descriptor as the magic cookie. Other
/// codecs (Apple Lossless, HE-AAC) are left for GStreamer to decode.
static OSStatus parse_mpeg4(audio_file *file) {
    const uint8_t *b = file->bytes, *end = b + file->size;
    const uint8_t *moov, *moov_end, *trak, *trak_end, *stbl, *stbl_end, *p, *q;
    if (!atom(b, end, FOURCC('m', 'o', 'o', 'v'), &moov, &moov_end)) return kAudioFileUnsupportedDataFormatError;
    // The first track with a sample description for MPEG-4 audio.
    static const uint32_t to_stbl[] = { FOURCC('m', 'd', 'i', 'a'), FOURCC('m', 'i', 'n', 'f'), FOURCC('s', 't', 'b', 'l') };
    const uint8_t *entry = NULL, *entry_end = NULL;
    for (const uint8_t *next = moov; atom(next, moov_end, FOURCC('t', 'r', 'a', 'k'), &trak, &trak_end); next = trak_end) {
        if (!atom_at(trak, trak_end, to_stbl, 3, &stbl, &stbl_end)) continue;
        if (!atom(stbl, stbl_end, FOURCC('s', 't', 's', 'd'), &p, &q) || q - p < 8 || be32(p + 4) < 1) continue;
        if (atom(p + 8, q, FOURCC('m', 'p', '4', 'a'), &entry, &entry_end)) break;
        entry = NULL;
    }
    if (!entry || entry_end - entry < 28) return kAudioFileUnsupportedDataFormatError;

    // The sample entry: its sound description, then the esds atom, which a
    // QuickTime file keeps inside a wave atom.
    uint32_t version = be16(entry + 8), channels = be16(entry + 16);
    const uint8_t *children = entry + 28 + (version == 1 ? 16 : version == 2 ? 36 : 0);
    if (children > entry_end) return kAudioFileUnsupportedDataFormatError;
    const uint8_t *esds, *esds_end;
    if (!atom(children, entry_end, FOURCC('e', 's', 'd', 's'), &esds, &esds_end)) {
        const uint8_t *wave, *wave_end;
        if (!atom(children, entry_end, FOURCC('w', 'a', 'v', 'e'), &wave, &wave_end)
            || !atom(wave, wave_end, FOURCC('e', 's', 'd', 's'), &esds, &esds_end)) return kAudioFileUnsupportedDataFormatError;
    }
    if (esds_end - esds < 4) return kAudioFileUnsupportedDataFormatError;
    esds += 4;                                              // version and flags
    const uint8_t *config;
    uint32_t config_size;
    if (!audio_config(esds, esds_end, &config, &config_size)) return kAudioFileUnsupportedDataFormatError;
    static const uint32_t rates[] = { 96000, 88200, 64000, 48000, 44100, 32000, 24000, 22050, 16000, 12000, 11025, 8000, 7350 };
    uint32_t object = config[0] >> 3, rate_index = (config[0] & 7) << 1 | config[1] >> 7, layout = config[1] >> 3 & 15;
    if (object != 2 || rate_index > 12) return kAudioFileUnsupportedDataFormatError;
    if (layout) channels = layout == 7 ? 8 : layout;
    if (!channels) return kAudioFileUnsupportedDataFormatError;

    // Where the samples are: their sizes, how many each chunk holds, and
    // where the chunks start.
    const uint8_t *stsz, *stsz_end, *stsc, *stsc_end, *stco, *stco_end;
    bool wide = false;
    if (!atom(stbl, stbl_end, FOURCC('s', 't', 's', 'z'), &stsz, &stsz_end) || stsz_end - stsz < 12
        || !atom(stbl, stbl_end, FOURCC('s', 't', 's', 'c'), &stsc, &stsc_end) || stsc_end - stsc < 8) {
        return kAudioFileInvalidFileError;
    }
    if (!atom(stbl, stbl_end, FOURCC('s', 't', 'c', 'o'), &stco, &stco_end)) {
        if (!atom(stbl, stbl_end, FOURCC('c', 'o', '6', '4'), &stco, &stco_end)) return kAudioFileInvalidFileError;
        wide = true;
    }
    if (stco_end - stco < 8) return kAudioFileInvalidFileError;
    uint32_t fixed_size = be32(stsz + 4), count = be32(stsz + 8);
    uint32_t runs = be32(stsc + 4), chunks = be32(stco + 4);
    if ((!fixed_size && (uint64_t)count * 4 > (uint64_t)(stsz_end - stsz - 12)) || (uint64_t)runs * 12 > (uint64_t)(stsc_end - stsc - 8)
        || (uint64_t)chunks * (wide ? 8 : 4) > (uint64_t)(stco_end - stco - 8) || count > file->size) {
        return kAudioFileInvalidFileError;
    }
    AudioStreamPacketDescription *table = calloc(count ? count : 1, sizeof *table);
    if (!table) return kAudio_MemFullError;
    uint64_t first = UINT64_MAX, last = 0;
    uint32_t sample = 0, run = 0, per_chunk = 0, largest = 0;
    for (uint32_t chunk = 0; chunk < chunks && sample < count; chunk++) {
        // The run of chunks this one belongs to says how many samples it has.
        while (run < runs && be32(stsc + 8 + 12 * run) <= chunk + 1) per_chunk = be32(stsc + 8 + 12 * run++ + 4);
        uint64_t offset = wide ? be64(stco + 8 + 8 * (size_t)chunk) : be32(stco + 8 + 4 * (size_t)chunk);
        for (uint32_t i = 0; i < per_chunk && sample < count; i++, sample++) {
            uint32_t size = fixed_size ? fixed_size : be32(stsz + 12 + 4 * (size_t)sample);
            if (offset + size > file->size) { free(table); return kAudioFileInvalidFileError; }
            table[sample] = (AudioStreamPacketDescription){ (int64_t)offset, 0, size };
            if (offset < first) first = offset;
            if (offset + size > last) last = offset + size;
            if (size > largest) largest = size;
            offset += size;
        }
    }
    if (!sample) { free(table); return kAudioFileInvalidFileError; }
    // Packets are placed from the first one's start, the audio data's.
    for (uint32_t i = 0; i < sample; i++) table[i].mStartOffset -= (int64_t)first;

    file->format = (AudioStreamBasicDescription){ .mSampleRate = rates[rate_index], .mFormatID = kAudioFormatMPEG4AAC,
                                                  .mFramesPerPacket = 1024, .mChannelsPerFrame = channels };
    file->table = table;
    file->packets = sample;
    file->max_packet = largest;
    file->data_offset = (size_t)first;
    file->data_size = (size_t)(last - first);
    file->cookie_size = (uint32_t)(esds_end - esds);
    file->cookie = malloc(file->cookie_size);
    if (!file->cookie) return kAudio_MemFullError;
    memcpy(file->cookie, esds, file->cookie_size);

    // What plays of it: an edit list gives the encoder's priming frames and
    // the length without them; without one, an AAC encoder's usual priming.
    int64_t total = (int64_t)sample * 1024, priming = 2112, valid = -1;
    static const uint32_t to_elst[] = { FOURCC('e', 'd', 't', 's'), FOURCC('e', 'l', 's', 't') };
    const uint8_t *mvhd, *mvhd_end, *mdhd, *mdhd_end;
    static const uint32_t to_mdhd[] = { FOURCC('m', 'd', 'i', 'a'), FOURCC('m', 'd', 'h', 'd') };
    if (atom_at(trak, trak_end, to_elst, 2, &p, &q) && q - p >= 8 && be32(p + 4) >= 1
        && atom(moov, moov_end, FOURCC('m', 'v', 'h', 'd'), &mvhd, &mvhd_end)
        && atom_at(trak, trak_end, to_mdhd, 2, &mdhd, &mdhd_end)) {
        bool long_edit = p[0] == 1, long_movie = mvhd_end > mvhd && mvhd[0] == 1, long_media = mdhd_end > mdhd && mdhd[0] == 1;
        if (q - p >= (long_edit ? 28 : 20) && mvhd_end - mvhd >= (long_movie ? 24 : 16) && mdhd_end - mdhd >= (long_media ? 24 : 16)) {
            uint64_t duration = long_edit ? be64(p + 8) : be32(p + 8);
            int64_t media_time = long_edit ? (int64_t)be64(p + 16) : (int32_t)be32(p + 12);
            uint32_t movie_scale = be32(mvhd + (long_movie ? 20 : 12)), media_scale = be32(mdhd + (long_media ? 20 : 12));
            if (media_time >= 0 && media_time < total && movie_scale) {
                priming = media_time;
                valid = (int64_t)llround((double)duration * media_scale / movie_scale);
            }
        }
    }
    // iTunes writes them as text instead, in its iTunSMPB tag: zeros, the
    // priming, the remainder and the length, in hexadecimal.
    static const char tag[] = "iTunSMPB";
    for (const uint8_t *t = moov; valid < 0 && moov_end - t >= 8 && (t = memchr(t, 'i', (size_t)(moov_end - t - 7))); t++) {
        if (memcmp(t, tag, 8)) continue;
        const uint8_t *text = NULL;
        for (const uint8_t *d = t + 8; d + 12 <= moov_end && d < t + 40; d++) {
            if (!memcmp(d, "data", 4)) { text = d + 12; break; }
        }
        char line[64] = "";
        if (text) memcpy(line, text, (size_t)(moov_end - text) < sizeof line - 1 ? (size_t)(moov_end - text) : sizeof line - 1);
        unsigned zero, start, padding;
        unsigned long long length;
        if (sscanf(line, " %x %x %x %llx", &zero, &start, &padding, &length) == 4 && (int64_t)start + (int64_t)length <= total) {
            priming = start;
            valid = (int64_t)length;
        }
        break;
    }
    if (priming > total) priming = 0;
    if (valid < 0 || valid > total - priming) valid = total - priming;
    file->valid_frames = valid;
    file->priming = (int32_t)priming;
    file->remainder = (int32_t)(total - priming - valid);
    file->type = kAudioFileM4AType;
    return 0;
}

/// Whether the bytes begin as an MPEG-4 or QuickTime file does.
static bool is_mpeg4(const uint8_t *bytes, size_t size) {
    if (size < 12) return false;
    uint32_t type = be32(bytes + 4);
    return type == FOURCC('f', 't', 'y', 'p') || type == FOURCC('m', 'o', 'o', 'v') || type == FOURCC('m', 'd', 'a', 't')
        || type == FOURCC('f', 'r', 'e', 'e') || type == FOURCC('w', 'i', 'd', 'e');
}

static OSStatus decode_other(audio_file *file, uint32_t hint) {
    int16_t *samples;
    size_t frames;
    uint32_t rate, channels;
    if (!perry_gst_decode(file->bytes, file->size, &samples, &frames, &rate, &channels)) {
        return kAudioFileUnsupportedFileTypeError;
    }
    free(file->bytes);
    free(file->cookie);
    free(file->table);
    file->cookie = NULL;
    file->cookie_size = 0;
    file->table = NULL;
    file->valid_frames = -1;
    file->priming = file->remainder = 0;
    file->decoded = true;
    file->bytes = (uint8_t *)samples;
    file->size = frames * channels * 2;
    file->data_offset = 0;
    file->data_size = file->size;
    lpcm(&file->format, rate, channels, 16, false, false, true);
    file->packets = frames;
    file->max_packet = file->format.mBytesPerPacket;
    file->type = hint ? hint : kAudioFileMP3Type;
    return 0;
}

static OSStatus open_bytes(uint8_t *bytes, size_t size, uint32_t hint, audio_file **out) {
    audio_file *file = calloc(1, sizeof *file);
    if (!file) { free(bytes); return kAudio_MemFullError; }
    file->magic = FILE_MAGIC;
    file->bytes = bytes;
    file->size = size;
    file->valid_frames = -1;
    OSStatus status;
    if (size >= 8 && !memcmp(bytes, "caff", 4)) {
        status = parse_caf(file);
    } else if (size >= 12 && !memcmp(bytes, "RIFF", 4) && !memcmp(bytes + 8, "WAVE", 4)) {
        status = parse_wave(file);
    } else if (size >= 12 && !memcmp(bytes, "FORM", 4) && (!memcmp(bytes + 8, "AIFF", 4) || !memcmp(bytes + 8, "AIFC", 4))) {
        status = parse_aiff(file, !memcmp(bytes + 8, "AIFC", 4));
    } else if (is_mpeg4(bytes, size) && !parse_mpeg4(file)) {
        status = 0;
    } else {
        // A sound track parse_mpeg4 left half read is read again, decoded.
        free(file->cookie);
        free(file->table);
        file->cookie = NULL;
        file->table = NULL;
        status = decode_other(file, hint);
    }
    if (status) {
        free(file->bytes);
        free(file->cookie);
        free(file->table);
        free(file);
        return status;
    }
    perry_audio_trace("opened a file: '%.4s' %u Hz, %u channels, %llu packets",
                      (char[]){ (char)(file->format.mFormatID >> 24), (char)(file->format.mFormatID >> 16),
                                (char)(file->format.mFormatID >> 8), (char)file->format.mFormatID },
                      (unsigned)file->format.mSampleRate, file->format.mChannelsPerFrame, (unsigned long long)file->packets);
    *out = file;
    return 0;
}

static audio_file *valid(void *file) {
    audio_file *f = file;
    return f && f->magic == FILE_MAGIC ? f : NULL;
}

/// Turns an open file of compressed audio into its decoded PCM, for the
/// extended audio files built on these. Fails when GStreamer can't.
OSStatus perry_audio_file_decode(void *handle) {
    audio_file *file = valid(handle);
    if (!file) return kAudioFileNotOpenError;
    if (file->decoded || file->format.mFormatID == kAudioFormatLinearPCM) return 0;
    return decode_other(file, file->type);
}

// MARK: - Opening and closing

OSStatus darwin_AudioFileOpenURL(const void *url, int8_t permissions, uint32_t hint, void **out) DARWIN_SYMBOL(AudioFileOpenURL);
OSStatus darwin_AudioFileOpenURL(const void *url, int8_t permissions, uint32_t hint, void **out) {
    if (!out) return kAudio_ParamError;
    *out = NULL;
    char path[4096];
    if (!perry_audio_url_path(url, path, sizeof path)) return kAudio_ParamError;
    if (permissions & 2) return -54;     // writing: kAudioFilePermissionsError
    FILE *stream = fopen(path, "rb");
    if (!stream) return -43;             // fnfErr
    fseeko(stream, 0, SEEK_END);
    off_t size = ftello(stream);
    fseeko(stream, 0, SEEK_SET);
    uint8_t *bytes = malloc(size > 0 ? (size_t)size : 1);
    size_t read = bytes ? fread(bytes, 1, (size_t)size, stream) : 0;
    fclose(stream);
    if (!bytes || read != (size_t)size) { free(bytes); return kAudioFileUnspecifiedError; }
    perry_audio_trace("opening %s", path);
    return open_bytes(bytes, read, hint, (audio_file **)out);
}

OSStatus darwin_AudioFileOpenWithCallbacks(void *data, read_proc read, void *write, size_proc get_size, void *set_size,
                                           uint32_t hint, void **out) DARWIN_SYMBOL(AudioFileOpenWithCallbacks);
OSStatus darwin_AudioFileOpenWithCallbacks(void *data, read_proc read, void *write, size_proc get_size, void *set_size,
                                           uint32_t hint, void **out) {
    if (!out || !read || !get_size) return kAudio_ParamError;
    *out = NULL;
    perry_audio_trace("opening a file through callbacks, hint '%.4s'", (const char *)&hint);
    int64_t size = get_size(data);
    if (size < 0) return kAudioFileInvalidFileError;
    uint8_t *bytes = malloc(size ? (size_t)size : 1);
    if (!bytes) return kAudio_MemFullError;
    int64_t done = 0;
    while (done < size) {
        uint32_t want = (uint32_t)((size - done) > (1 << 30) ? (1 << 30) : (size - done)), got = 0;
        OSStatus status = read(data, done, want, bytes + done, &got);
        if (status && status != kAudioFileEndOfFileError) { free(bytes); return status; }
        if (!got) break;
        done += got;
    }
    OSStatus status = open_bytes(bytes, (size_t)done, hint, (audio_file **)out);
    if (status) perry_audio_trace("can't open the file (%d, %lld bytes)", (int)status, (long long)done);
    if (!status) {
        audio_file *file = *out;
        file->read = read;
        file->client = data;
    }
    return status;
}

OSStatus darwin_AudioFileClose(void *handle) DARWIN_SYMBOL(AudioFileClose);
OSStatus darwin_AudioFileClose(void *handle) {
    audio_file *file = valid(handle);
    if (!file) return kAudioFileNotOpenError;
    file->magic = 0;
    free(file->bytes);
    free(file->cookie);
    free(file->table);
    free(file);
    return 0;
}

// MARK: - Properties

#define kAudioFilePropertyFileFormat FOURCC('f', 'f', 'm', 't')
#define kAudioFilePropertyDataFormat FOURCC('d', 'f', 'm', 't')
#define kAudioFilePropertyIsOptimized FOURCC('o', 'p', 't', 'm')
#define kAudioFilePropertyMagicCookieData FOURCC('m', 'g', 'i', 'c')
#define kAudioFilePropertyAudioDataByteCount FOURCC('b', 'c', 'n', 't')
#define kAudioFilePropertyAudioDataPacketCount FOURCC('p', 'c', 'n', 't')
#define kAudioFilePropertyMaximumPacketSize FOURCC('p', 's', 'z', 'e')
#define kAudioFilePropertyDataOffset FOURCC('d', 'o', 'f', 'f')
#define kAudioFilePropertyPacketSizeUpperBound FOURCC('p', 'k', 'u', 'b')
#define kAudioFilePropertyEstimatedDuration FOURCC('e', 'd', 'u', 'r')
#define kAudioFilePropertyBitRate FOURCC('b', 'r', 'a', 't')
#define kAudioFilePropertyPacketTableInfo FOURCC('p', 'n', 'f', 'o')
#define kAudioFilePropertyFormatList FOURCC('f', 'l', 's', 't')

/// The property's value, copied to `value` when it fits.
static OSStatus property(audio_file *file, uint32_t id, uint32_t *size, void *value, bool info_only, uint32_t *writable) {
    union {
        uint32_t u32;
        uint64_t u64;
        int64_t i64;
        double f64;
        AudioStreamBasicDescription format;
        struct { AudioStreamBasicDescription format; uint32_t layout; } list;
        struct { int64_t valid; int32_t priming, remainder; } table;
    } v;
    const void *source = &v;
    uint32_t length;
    switch (id) {
    case kAudioFilePropertyFileFormat: v.u32 = file->type; length = 4; break;
    case kAudioFilePropertyDataFormat: v.format = file->format; length = sizeof v.format; break;
    case kAudioFilePropertyFormatList: v.list.format = file->format; v.list.layout = 0; length = 48; break;
    case kAudioFilePropertyIsOptimized: v.u32 = 1; length = 4; break;
    case kAudioFilePropertyMagicCookieData:
        if (!file->cookie) return kAudioFileUnsupportedPropertyError;
        source = file->cookie;
        length = file->cookie_size;
        break;
    case kAudioFilePropertyAudioDataByteCount: v.u64 = file->data_size; length = 8; break;
    case kAudioFilePropertyAudioDataPacketCount: v.u64 = file->packets; length = 8; break;
    case kAudioFilePropertyMaximumPacketSize: case kAudioFilePropertyPacketSizeUpperBound:
        v.u32 = file->max_packet; length = 4; break;
    case kAudioFilePropertyDataOffset: v.i64 = (int64_t)file->data_offset; length = 8; break;
    case kAudioFilePropertyEstimatedDuration: {
        double frames = file->valid_frames >= 0 ? (double)file->valid_frames
            : (double)file->packets * (file->format.mFramesPerPacket ? file->format.mFramesPerPacket : 1024);
        v.f64 = file->format.mSampleRate > 0 ? frames / file->format.mSampleRate : 0;
        length = 8;
        break;
    }
    case kAudioFilePropertyBitRate: {
        double seconds = 0;
        uint32_t s = 8;
        property(file, kAudioFilePropertyEstimatedDuration, &s, &seconds, false, NULL);
        v.u32 = seconds > 0 ? (uint32_t)(file->data_size * 8 / seconds) : 0;
        length = 4;
        break;
    }
    case kAudioFilePropertyPacketTableInfo:
        if (file->valid_frames < 0) return kAudioFileUnsupportedPropertyError;
        v.table.valid = file->valid_frames;
        v.table.priming = file->priming;
        v.table.remainder = file->remainder;
        length = 16;
        break;
    default:
        perry_audio_trace("unsupported file property '%c%c%c%c'", id >> 24, id >> 16 & 0xff, id >> 8 & 0xff, id & 0xff);
        return kAudioFileUnsupportedPropertyError;
    }
    if (writable) *writable = 0;
    if (info_only) {
        if (size) *size = length;
        return 0;
    }
    if (!size || !value) return kAudio_ParamError;
    if (*size < length && id != kAudioFilePropertyMagicCookieData) return kAudioFileBadPropertySizeError;
    if (*size > length) *size = length;
    memcpy(value, source, *size);
    return 0;
}

OSStatus darwin_AudioFileGetPropertyInfo(void *handle, uint32_t id, uint32_t *size, uint32_t *writable)
    DARWIN_SYMBOL(AudioFileGetPropertyInfo);
OSStatus darwin_AudioFileGetPropertyInfo(void *handle, uint32_t id, uint32_t *size, uint32_t *writable) {
    audio_file *file = valid(handle);
    if (!file) return kAudioFileNotOpenError;
    return property(file, id, size, NULL, true, writable);
}

OSStatus darwin_AudioFileGetProperty(void *handle, uint32_t id, uint32_t *size, void *value) DARWIN_SYMBOL(AudioFileGetProperty);
OSStatus darwin_AudioFileGetProperty(void *handle, uint32_t id, uint32_t *size, void *value) {
    audio_file *file = valid(handle);
    if (!file) return kAudioFileNotOpenError;
    return property(file, id, size, value, false, NULL);
}

OSStatus darwin_AudioFileSetProperty(void *handle, uint32_t id, uint32_t size, const void *value) DARWIN_SYMBOL(AudioFileSetProperty);
OSStatus darwin_AudioFileSetProperty(void *handle, uint32_t id, uint32_t size, const void *value) {
    return valid(handle) ? kAudioFileUnsupportedPropertyError : kAudioFileNotOpenError;
}

// MARK: - Reading

/// Packet `index`'s offset and size within the data.
static void packet(audio_file *file, uint64_t index, uint64_t *offset, uint32_t *size, uint32_t *frames) {
    if (file->table) {
        *offset = (uint64_t)file->table[index].mStartOffset;
        *size = file->table[index].mDataByteSize;
        *frames = file->table[index].mVariableFramesInPacket;
    } else {
        *offset = index * file->format.mBytesPerPacket;
        *size = file->format.mBytesPerPacket;
        *frames = 0;
    }
}

/// `size` bytes of audio data from `offset` within it: through the app's
/// callback for files opened with them, else from the bytes read at open.
static bool copy_data(audio_file *file, uint64_t offset, uint32_t size, void *buffer) {
    if (file->read && !file->decoded) {
        uint32_t actual = 0;
        OSStatus status = file->read(file->client, (int64_t)(file->data_offset + offset), size, buffer, &actual);
        if (!status && actual == size) return true;
    }
    if (offset + size > file->data_size) return false;
    memcpy(buffer, file->bytes + file->data_offset + offset, size);
    return true;
}

/// Reads up to `*packets` packets from `start`, stopping before `capacity`
/// bytes (when given) would be exceeded.
static OSStatus read_packets(audio_file *file, uint32_t *bytes, AudioStreamPacketDescription *descriptions, int64_t start,
                             uint32_t *packets, void *buffer, uint64_t capacity) {
    if (!packets || !buffer) return kAudio_ParamError;
    if (start < 0) return kAudioFileInvalidPacketOffsetError;
    uint32_t wanted = *packets, count = 0;
    uint64_t written = 0;
    while (count < wanted && (uint64_t)start + count < file->packets) {
        uint64_t offset;
        uint32_t size, frames;
        packet(file, (uint64_t)start + count, &offset, &size, &frames);
        if (written + size > capacity) break;
        if (!copy_data(file, offset, size, (uint8_t *)buffer + written)) break;
        // Only packets of varying size are described: a program reading a
        // format of constant packets (IMA4's 34 bytes) may give room for
        // one description, or none, with all the file's packets asked for.
        if (descriptions && file->table) descriptions[count] = (AudioStreamPacketDescription){ (int64_t)written, frames, size };
        written += size;
        count++;
    }
    *packets = count;
    if (bytes) *bytes = (uint32_t)written;
    return (count == 0 && wanted > 0) ? kAudioFileEndOfFileError : 0;
}

OSStatus darwin_AudioFileReadPackets(void *handle, uint8_t cache, uint32_t *bytes, AudioStreamPacketDescription *descriptions,
                                     int64_t start, uint32_t *packets, void *buffer) DARWIN_SYMBOL(AudioFileReadPackets);
OSStatus darwin_AudioFileReadPackets(void *handle, uint8_t cache, uint32_t *bytes, AudioStreamPacketDescription *descriptions,
                                     int64_t start, uint32_t *packets, void *buffer) {
    audio_file *file = valid(handle);
    if (!file) return kAudioFileNotOpenError;
    OSStatus status = read_packets(file, bytes, descriptions, start, packets, buffer, UINT64_MAX);
    // AudioFileReadPackets reports the end with no packets, not an error.
    return status == kAudioFileEndOfFileError ? 0 : status;
}

OSStatus darwin_AudioFileReadPacketData(void *handle, uint8_t cache, uint32_t *bytes, AudioStreamPacketDescription *descriptions,
                                        int64_t start, uint32_t *packets, void *buffer) DARWIN_SYMBOL(AudioFileReadPacketData);
OSStatus darwin_AudioFileReadPacketData(void *handle, uint8_t cache, uint32_t *bytes, AudioStreamPacketDescription *descriptions,
                                        int64_t start, uint32_t *packets, void *buffer) {
    audio_file *file = valid(handle);
    if (!file) return kAudioFileNotOpenError;
    if (!bytes) return kAudio_ParamError;
    return read_packets(file, bytes, descriptions, start, packets, buffer, *bytes);
}

OSStatus darwin_AudioFileReadBytes(void *handle, uint8_t cache, int64_t start, uint32_t *bytes, void *buffer)
    DARWIN_SYMBOL(AudioFileReadBytes);
OSStatus darwin_AudioFileReadBytes(void *handle, uint8_t cache, int64_t start, uint32_t *bytes, void *buffer) {
    audio_file *file = valid(handle);
    if (!file) return kAudioFileNotOpenError;
    if (!bytes || !buffer || start < 0) return kAudio_ParamError;
    if ((uint64_t)start >= file->data_size) { *bytes = 0; return kAudioFileEndOfFileError; }
    uint64_t available = file->data_size - (uint64_t)start;
    if (*bytes > available) *bytes = (uint32_t)available;
    return copy_data(file, (uint64_t)start, *bytes, buffer) ? 0 : kAudioFileUnspecifiedError;
}
