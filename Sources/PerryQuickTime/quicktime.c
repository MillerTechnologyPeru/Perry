// QuickTime's Movie Toolbox, for programs that play movies into a graphics
// world: a movie is a GStreamer playbin (GStreamer loaded the first time a
// movie is opened), whose video comes out as xRGB frames that MoviesTask
// draws into the movie's GWorld at its box, scaled, and whose sound plays
// on its own. Times are in the movie's time scale, 600 to the second, as
// QuickTime's movies made by its exporters have.

#include "perry_interface.h"

#include <dlfcn.h>
#include <limits.h>
#include <pthread.h>
#include <stdarg.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

#define QT_SYMBOL(name) __asm__("_" #name) __attribute__((visibility("default"), used))

typedef int16_t OSErr;
typedef int32_t OSStatus;
typedef unsigned char Boolean;
typedef uint32_t OSType;
typedef int32_t TimeValue;

enum {
    noErr = 0, paramErr = -50, memFullErr = -108, fnfErr = -43, invalidMovie = -2010, couldNotResolveDataRef = -2000,
    noCodecErr = -8961, cantFindHandler = -2003,
};

#define TIME_SCALE 600

#pragma pack(push, 2)
typedef struct { int16_t top, left, bottom, right; } Rect;
typedef struct { int16_t vRefNum; int32_t parID; unsigned char name[64]; } FSSpec;
typedef struct {
    void *baseAddr;
    int16_t rowBytes;
    Rect bounds;
    int16_t pmVersion, packType;
    int32_t packSize, hRes, vRes;
    int16_t pixelType, pixelSize, cmpCount, cmpSize;
    OSType pixelFormat;
    void *pmTable, *pmExt;
} PixMap;
typedef struct {
    int64_t value;     // a CompTimeValue
    int32_t scale;
    void *base;
} TimeRecord;
#pragma pack(pop)

// MARK: - The loader and Carbon

static void *(*lookup_symbol)(const char *install_name, const char *name);

__attribute__((visibility("default")))
void perry_provider_startup(const perry_startup_info *info) {
    if (info->version >= 2) lookup_symbol = info->lookup_symbol;
}

#define CARBON "/System/Library/Frameworks/Carbon.framework/Versions/A/Carbon"

static void *carbon(const char *name) { return lookup_symbol ? lookup_symbol(CARBON, name) : NULL; }

static void warn(const char *format, ...) {
    va_list arguments;
    va_start(arguments, format);
    fputs("perry: QuickTime: ", stderr);
    vfprintf(stderr, format, arguments);
    fputc('\n', stderr);
    va_end(arguments);
}

static bool tracing(void) {
    static int enabled = -1;
    if (enabled < 0) enabled = getenv("PERRY_QUICKTIME_TRACE") != NULL;
    return enabled;
}

#define TRACE(...) do { if (tracing()) warn(__VA_ARGS__); } while (0)

// MARK: - GStreamer

enum {
    GST_STATE_NULL = 1, GST_STATE_PAUSED = 3, GST_STATE_PLAYING = 4,
    GST_FORMAT_TIME = 3,
    GST_SEEK_FLAG_FLUSH = 1, GST_SEEK_FLAG_ACCURATE = 2,
    GST_MESSAGE_EOS = 1, GST_MESSAGE_ERROR = 2,
    GST_MAP_READ = 1,
};

typedef struct {
    void *memory;
    unsigned flags;
    uint8_t *data;
    size_t size, maxsize;
    void *user_data[4];
    void *padding[4];
} GstMapInfo;

static struct {
    void *(*parse_launch)(const char *, void **);
    void *(*bin_get_by_name)(void *, const char *);
    int (*set_state)(void *, int);
    int (*get_state)(void *, int *, int *, uint64_t);
    void *(*get_bus)(void *);
    void *(*bus_pop_filtered)(void *, int);
    void (*object_unref)(void *);
    void (*mini_object_unref)(void *);
    int (*buffer_map)(void *, GstMapInfo *, int);
    void (*buffer_unmap)(void *, GstMapInfo *);
    void *(*try_pull_sample)(void *, uint64_t);
    void *(*try_pull_preroll)(void *, uint64_t);
    void *(*sample_get_buffer)(void *);
    void *(*sample_get_caps)(void *);
    void *(*caps_get_structure)(void *, unsigned);
    int (*structure_get_int)(void *, const char *, int *);
    void (*object_set)(void *, const char *, ...);
    int (*query_position)(void *, int, int64_t *);
    int (*query_duration)(void *, int, int64_t *);
    int (*seek_simple)(void *, int, int, int64_t);
    char *(*filename_to_uri)(const char *, void **);
    void (*g_free)(void *);
} gst;

static bool gst_ready;
static pthread_once_t gst_once = PTHREAD_ONCE_INIT;

static void load_gst(void) {
    void *core = dlopen("libgstreamer-1.0.so.0", RTLD_NOW | RTLD_GLOBAL);
    void *app = dlopen("libgstapp-1.0.so.0", RTLD_NOW | RTLD_GLOBAL);
    void *gobject = dlopen("libgobject-2.0.so.0", RTLD_NOW | RTLD_GLOBAL);
    void *glib = dlopen("libglib-2.0.so.0", RTLD_NOW | RTLD_GLOBAL);
    if (!core || !app || !gobject || !glib) {
        warn("GStreamer is not installed; movies don't play");
        return;
    }
    int (*init_check)(int *, char ***, void **) = (int (*)(int *, char ***, void **))dlsym(core, "gst_init_check");
#define BIND(field, library, name) if (!(*(void **)&gst.field = dlsym(library, name))) { warn("GStreamer lacks %s; movies don't play", name); return; }
    BIND(parse_launch, core, "gst_parse_launch");
    BIND(bin_get_by_name, core, "gst_bin_get_by_name");
    BIND(set_state, core, "gst_element_set_state");
    BIND(get_state, core, "gst_element_get_state");
    BIND(get_bus, core, "gst_element_get_bus");
    BIND(bus_pop_filtered, core, "gst_bus_pop_filtered");
    BIND(object_unref, core, "gst_object_unref");
    BIND(mini_object_unref, core, "gst_mini_object_unref");
    BIND(buffer_map, core, "gst_buffer_map");
    BIND(buffer_unmap, core, "gst_buffer_unmap");
    BIND(try_pull_sample, app, "gst_app_sink_try_pull_sample");
    BIND(try_pull_preroll, app, "gst_app_sink_try_pull_preroll");
    BIND(sample_get_buffer, core, "gst_sample_get_buffer");
    BIND(sample_get_caps, core, "gst_sample_get_caps");
    BIND(caps_get_structure, core, "gst_caps_get_structure");
    BIND(structure_get_int, core, "gst_structure_get_int");
    BIND(object_set, gobject, "g_object_set");
    BIND(query_position, core, "gst_element_query_position");
    BIND(query_duration, core, "gst_element_query_duration");
    BIND(seek_simple, core, "gst_element_seek_simple");
    BIND(filename_to_uri, glib, "g_filename_to_uri");
    BIND(g_free, glib, "g_free");
#undef BIND
    void *error = NULL;
    if (!init_check || !init_check(NULL, NULL, &error)) {
        warn("GStreamer didn't initialize; movies don't play");
        return;
    }
    gst_ready = true;
}

static bool gst_load(void) {
    pthread_once(&gst_once, load_gst);
    return gst_ready;
}

// MARK: - Movie files

#define MAX_MOVIE_FILES 64
static char *movie_files[MAX_MOVIE_FILES];

OSErr qt_EnterMovies(void) QT_SYMBOL(EnterMovies);
OSErr qt_EnterMovies(void) { return noErr; }

void qt_ExitMovies(void) QT_SYMBOL(ExitMovies);
void qt_ExitMovies(void) {}

OSErr qt_GetMoviesError(void) QT_SYMBOL(GetMoviesError);
OSErr qt_GetMoviesError(void) { return noErr; }

/// A movie file's reference number, from 1: the path it names.
OSErr qt_OpenMovieFile(const FSSpec *spec, int16_t *reference, int8_t permission) QT_SYMBOL(OpenMovieFile);
OSErr qt_OpenMovieFile(const FSSpec *spec, int16_t *reference, int8_t permission) {
    (void)permission;
    if (!spec || !reference) return paramErr;
    // Carbon's: the FSSpec as an FSRef, the FSRef as a path.
    OSErr (*make_ref)(const FSSpec *, void *) = (OSErr (*)(const FSSpec *, void *))carbon("_FSpMakeFSRef");
    int32_t (*ref_path)(const void *, char *, uint32_t) = (int32_t (*)(const void *, char *, uint32_t))carbon("_FSRefMakePath");
    uint8_t ref[80];
    char path[PATH_MAX];
    if (!make_ref || !ref_path || make_ref(spec, ref) != noErr || ref_path(ref, path, sizeof path) != noErr) return fnfErr;
    for (int index = 1; index < MAX_MOVIE_FILES; index++)
        if (!movie_files[index]) {
            movie_files[index] = strdup(path);
            *reference = (int16_t)index;
            TRACE("movie file %d: %s", index, path);
            return noErr;
        }
    return -42;   // tmfoErr
}

OSErr qt_CloseMovieFile(int16_t reference) QT_SYMBOL(CloseMovieFile);
OSErr qt_CloseMovieFile(int16_t reference) {
    if (reference <= 0 || reference >= MAX_MOVIE_FILES || !movie_files[reference]) return -51;   // rfNumErr
    free(movie_files[reference]);
    movie_files[reference] = NULL;
    return noErr;
}

// MARK: - Movies

typedef struct qt_movie {
    uint32_t magic;
    char *path;
    void *pipeline, *sink;
    int width, height;
    Rect box;
    void *port;
    void *device;
    bool playing, done, active, looping;
    float volume;
    int64_t duration;      // nanoseconds
    void *frame;           // the last sample, drawn each task
    bool fresh;
} qt_movie;

#define QT_MOVIE_MAGIC 0x4d4f4f56u   // 'MOOV'

static qt_movie *movie_from(void *pointer) {
    qt_movie *movie = pointer;
    return movie && movie->magic == QT_MOVIE_MAGIC ? movie : NULL;
}

/// Prerolls the movie: its pipeline paused, its first frame and size known.
static bool movie_open(qt_movie *movie) {
    if (!gst_load()) return false;
    void *error = NULL;
    char *uri = gst.filename_to_uri(movie->path, &error);
    if (!uri) return false;
    char description[PATH_MAX * 3 + 256];
    snprintf(description, sizeof description,
             "playbin uri=\"%s\" video-sink=\"videoconvert ! video/x-raw,format=xRGB ! appsink name=frames max-buffers=2 drop=true sync=true\"",
             uri);
    gst.g_free(uri);
    movie->pipeline = gst.parse_launch(description, &error);
    if (!movie->pipeline) {
        warn("can't play %s", movie->path);
        return false;
    }
    movie->sink = gst.bin_get_by_name(movie->pipeline, "frames");
    gst.set_state(movie->pipeline, GST_STATE_PAUSED);
    int state = 0, pending = 0;
    gst.get_state(movie->pipeline, &state, &pending, 5000000000ull);
    void *sample = movie->sink ? gst.try_pull_preroll(movie->sink, 2000000000ull) : NULL;
    if (sample) {
        void *structure = gst.caps_get_structure(gst.sample_get_caps(sample), 0);
        gst.structure_get_int(structure, "width", &movie->width);
        gst.structure_get_int(structure, "height", &movie->height);
        movie->frame = sample;
        movie->fresh = true;
    }
    int64_t duration = 0;
    if (gst.query_duration(movie->pipeline, GST_FORMAT_TIME, &duration)) movie->duration = duration;
    movie->box = (Rect){0, 0, (int16_t)movie->height, (int16_t)movie->width};
    TRACE("movie %s: %d×%d, %.2f s", movie->path, movie->width, movie->height, movie->duration / 1e9);
    return true;
}

OSErr qt_NewMovieFromFile(qt_movie **out, int16_t reference, int16_t *resourceID, unsigned char *name, int16_t flags,
                          Boolean *changed) QT_SYMBOL(NewMovieFromFile);
OSErr qt_NewMovieFromFile(qt_movie **out, int16_t reference, int16_t *resourceID, unsigned char *name, int16_t flags,
                          Boolean *changed) {
    (void)resourceID; (void)flags;
    if (!out) return paramErr;
    *out = NULL;
    if (name) name[0] = 0;
    if (changed) *changed = 0;
    if (reference <= 0 || reference >= MAX_MOVIE_FILES || !movie_files[reference]) return -51;
    qt_movie *movie = calloc(1, sizeof *movie);
    if (!movie) return memFullErr;
    movie->magic = QT_MOVIE_MAGIC;
    movie->path = strdup(movie_files[reference]);
    movie->volume = 1;
    movie->active = true;
    if (!movie_open(movie)) {
        free(movie->path);
        free(movie);
        return invalidMovie;
    }
    *out = movie;
    return noErr;
}

void qt_DisposeMovie(qt_movie *movie) QT_SYMBOL(DisposeMovie);
void qt_DisposeMovie(qt_movie *movie) {
    if (!(movie = movie_from(movie))) return;
    if (movie->frame) gst.mini_object_unref(movie->frame);
    if (movie->sink) gst.object_unref(movie->sink);
    if (movie->pipeline) {
        gst.set_state(movie->pipeline, GST_STATE_NULL);
        gst.object_unref(movie->pipeline);
    }
    free(movie->path);
    movie->magic = 0;
    free(movie);
}

void qt_GetMovieBox(qt_movie *movie, Rect *box) QT_SYMBOL(GetMovieBox);
void qt_GetMovieBox(qt_movie *movie, Rect *box) {
    if (box) *box = (movie = movie_from(movie)) ? movie->box : (Rect){0, 0, 0, 0};
}

void qt_SetMovieBox(qt_movie *movie, const Rect *box) QT_SYMBOL(SetMovieBox);
void qt_SetMovieBox(qt_movie *movie, const Rect *box) {
    if ((movie = movie_from(movie)) && box) movie->box = *box;
}

void qt_SetMovieGWorld(qt_movie *movie, void *port, void *device) QT_SYMBOL(SetMovieGWorld);
void qt_SetMovieGWorld(qt_movie *movie, void *port, void *device) {
    if (!(movie = movie_from(movie))) return;
    if (!port) {
        void (*get_gworld)(void **, void **) = (void (*)(void **, void **))carbon("_GetGWorld");
        if (get_gworld) get_gworld(&port, &device);
    }
    movie->port = port;
    movie->device = device;
}

void qt_SetMovieActive(qt_movie *movie, Boolean active) QT_SYMBOL(SetMovieActive);
void qt_SetMovieActive(qt_movie *movie, Boolean active) { if ((movie = movie_from(movie))) movie->active = active; }

void qt_SetMovieActiveSegment(qt_movie *movie, TimeValue start, TimeValue duration) QT_SYMBOL(SetMovieActiveSegment);
void qt_SetMovieActiveSegment(qt_movie *movie, TimeValue start, TimeValue duration) { (void)movie; (void)start; (void)duration; }

void qt_SetMoviePlayHints(qt_movie *movie, uint32_t flags, uint32_t mask) QT_SYMBOL(SetMoviePlayHints);
void qt_SetMoviePlayHints(qt_movie *movie, uint32_t flags, uint32_t mask) { (void)movie; (void)flags; (void)mask; }

/// 0x100 is full volume; a negative one is muted.
void qt_SetMovieVolume(qt_movie *movie, int16_t volume) QT_SYMBOL(SetMovieVolume);
void qt_SetMovieVolume(qt_movie *movie, int16_t volume) {
    if (!(movie = movie_from(movie))) return;
    movie->volume = volume <= 0 ? 0 : volume / 256.0f;
    if (movie->pipeline) gst.object_set(movie->pipeline, "volume", (double)movie->volume, NULL);
}

int16_t qt_GetMovieVolume(qt_movie *movie) QT_SYMBOL(GetMovieVolume);
int16_t qt_GetMovieVolume(qt_movie *movie) { return (movie = movie_from(movie)) ? (int16_t)(movie->volume * 256) : 0; }

OSErr qt_PrerollMovie(qt_movie *movie, TimeValue time, int32_t rate) QT_SYMBOL(PrerollMovie);
OSErr qt_PrerollMovie(qt_movie *movie, TimeValue time, int32_t rate) {
    (void)time; (void)rate;
    return movie_from(movie) ? noErr : invalidMovie;
}

void qt_StartMovie(qt_movie *movie) QT_SYMBOL(StartMovie);
void qt_StartMovie(qt_movie *movie) {
    if (!(movie = movie_from(movie)) || !movie->pipeline) return;
    movie->playing = true;
    movie->done = false;
    gst.set_state(movie->pipeline, GST_STATE_PLAYING);
}

void qt_StopMovie(qt_movie *movie) QT_SYMBOL(StopMovie);
void qt_StopMovie(qt_movie *movie) {
    if (!(movie = movie_from(movie)) || !movie->pipeline) return;
    movie->playing = false;
    gst.set_state(movie->pipeline, GST_STATE_PAUSED);
}

static void seek_to(qt_movie *movie, int64_t nanoseconds) {
    if (!movie->pipeline) return;
    gst.seek_simple(movie->pipeline, GST_FORMAT_TIME, GST_SEEK_FLAG_FLUSH | GST_SEEK_FLAG_ACCURATE, nanoseconds);
    movie->done = false;
}

void qt_GoToBeginningOfMovie(qt_movie *movie) QT_SYMBOL(GoToBeginningOfMovie);
void qt_GoToBeginningOfMovie(qt_movie *movie) { if ((movie = movie_from(movie))) seek_to(movie, 0); }

void qt_GoToEndOfMovie(qt_movie *movie) QT_SYMBOL(GoToEndOfMovie);
void qt_GoToEndOfMovie(qt_movie *movie) {
    if (!(movie = movie_from(movie))) return;
    seek_to(movie, movie->duration);
    movie->done = true;
}

TimeValue qt_GetMovieDuration(qt_movie *movie) QT_SYMBOL(GetMovieDuration);
TimeValue qt_GetMovieDuration(qt_movie *movie) {
    return (movie = movie_from(movie)) ? (TimeValue)(movie->duration * TIME_SCALE / 1000000000) : 0;
}

TimeValue qt_GetMovieTimeScale(qt_movie *movie) QT_SYMBOL(GetMovieTimeScale);
TimeValue qt_GetMovieTimeScale(qt_movie *movie) { (void)movie; return TIME_SCALE; }

TimeValue qt_GetMovieTime(qt_movie *movie, TimeRecord *record) QT_SYMBOL(GetMovieTime);
TimeValue qt_GetMovieTime(qt_movie *movie, TimeRecord *record) {
    int64_t position = 0;
    if ((movie = movie_from(movie)) && movie->pipeline) gst.query_position(movie->pipeline, GST_FORMAT_TIME, &position);
    if (movie && movie->done) position = movie->duration;
    TimeValue value = (TimeValue)(position * TIME_SCALE / 1000000000);
    if (record) {
        // A CompTimeValue (wide) is its low word, then its high, on Intel.
        record->value = value;
        record->scale = TIME_SCALE;
        record->base = movie;
    }
    return value;
}

void qt_SetMovieTimeValue(qt_movie *movie, TimeValue value) QT_SYMBOL(SetMovieTimeValue);
void qt_SetMovieTimeValue(qt_movie *movie, TimeValue value) {
    if ((movie = movie_from(movie))) seek_to(movie, (int64_t)value * 1000000000 / TIME_SCALE);
}

/// A movie's time base is the movie; its flags say whether it loops.
void *qt_GetMovieTimeBase(qt_movie *movie) QT_SYMBOL(GetMovieTimeBase);
void *qt_GetMovieTimeBase(qt_movie *movie) { return movie_from(movie); }

uint32_t qt_GetTimeBaseFlags(qt_movie *base) QT_SYMBOL(GetTimeBaseFlags);
uint32_t qt_GetTimeBaseFlags(qt_movie *base) { return (base = movie_from(base)) && base->looping ? 1 : 0; }   // loopTimeBase

void qt_SetTimeBaseFlags(qt_movie *base, uint32_t flags) QT_SYMBOL(SetTimeBaseFlags);
void qt_SetTimeBaseFlags(qt_movie *base, uint32_t flags) { if ((base = movie_from(base))) base->looping = flags & 1; }

/// Draws the latest frame into the movie's GWorld at its box.
static void draw(qt_movie *movie) {
    if (!movie->frame || !movie->port) return;
    void *(*get_pixmap)(void *) = (void *(*)(void *))carbon("_GetGWorldPixMap");
    PixMap **handle = get_pixmap ? get_pixmap(movie->port) : NULL;
    if (!handle || !*handle || !(*handle)->baseAddr) return;
    PixMap *pixmap = *handle;
    void *buffer = gst.sample_get_buffer(movie->frame);
    GstMapInfo map;
    if (!buffer || !gst.buffer_map(buffer, &map, GST_MAP_READ)) return;
    int width = movie->width, height = movie->height;
    long stride = width * 4;
    long rowBytes = pixmap->rowBytes & 0x3fff;
    Rect box = movie->box;
    int boxWidth = box.right - box.left, boxHeight = box.bottom - box.top;
    for (int y = box.top; boxWidth > 0 && boxHeight > 0 && y < box.bottom; y++) {
        if (y < pixmap->bounds.top || y >= pixmap->bounds.bottom) continue;
        int sy = (y - box.top) * height / boxHeight;
        const uint8_t *row = map.data + sy * stride;
        uint8_t *out = (uint8_t *)pixmap->baseAddr + (long)(y - pixmap->bounds.top) * rowBytes;
        for (int x = box.left; x < box.right; x++) {
            if (x < pixmap->bounds.left || x >= pixmap->bounds.right) continue;
            const uint8_t *pixel = row + ((x - box.left) * width / boxWidth) * 4;
            int column = x - pixmap->bounds.left;
            if (pixmap->pixelSize == 16) {
                uint16_t value = (uint16_t)((pixel[1] >> 3) << 10 | (pixel[2] >> 3) << 5 | pixel[3] >> 3);
                out[column * 2] = (uint8_t)(value >> 8);
                out[column * 2 + 1] = (uint8_t)value;
            } else {
                out[column * 4] = 0xff;
                out[column * 4 + 1] = pixel[1];
                out[column * 4 + 2] = pixel[2];
                out[column * 4 + 3] = pixel[3];
            }
        }
    }
    gst.buffer_unmap(buffer, &map);
    // A window's port is shown.
    void *(*window_of)(void *) = (void *(*)(void *))carbon("_GetWindowFromPort");
    void (*flush)(void *, void *) = (void (*)(void *, void *))carbon("_QDFlushPortBuffer");
    if (window_of && flush && window_of(movie->port)) flush(movie->port, NULL);
}

/// Plays the movie on: its next frame drawn, its end noticed (and looped).
void qt_MoviesTask(qt_movie *movie, long milliseconds) QT_SYMBOL(MoviesTask);
void qt_MoviesTask(qt_movie *movie, long milliseconds) {
    (void)milliseconds;
    if (!(movie = movie_from(movie)) || !movie->pipeline) return;
    if (movie->playing && movie->sink) {
        void *sample = gst.try_pull_sample(movie->sink, 0);
        if (sample) {
            if (movie->frame) gst.mini_object_unref(movie->frame);
            movie->frame = sample;
            movie->fresh = true;
        }
    }
    if (movie->fresh && movie->active) {
        draw(movie);
        movie->fresh = false;
    }
    void *bus = gst.get_bus(movie->pipeline);
    void *message = bus ? gst.bus_pop_filtered(bus, GST_MESSAGE_EOS | GST_MESSAGE_ERROR) : NULL;
    if (bus) gst.object_unref(bus);
    if (message) {
        gst.mini_object_unref(message);
        if (movie->looping) seek_to(movie, 0);
        else {
            movie->done = true;
            movie->playing = false;
        }
    }
}

Boolean qt_IsMovieDone(qt_movie *movie) QT_SYMBOL(IsMovieDone);
Boolean qt_IsMovieDone(qt_movie *movie) {
    if (!(movie = movie_from(movie))) return 1;
    if (!movie->pipeline) return 1;
    return movie->done;
}

void qt_UpdateMovie(qt_movie *movie) QT_SYMBOL(UpdateMovie);
void qt_UpdateMovie(qt_movie *movie) { if ((movie = movie_from(movie))) movie->fresh = movie->frame != NULL; }

// MARK: - Graphics importers

/// Image importers: none; programs that ask draw their pictures otherwise.
OSErr qt_GetGraphicsImporterForDataRef(void *dataRef, OSType type, void **importer) QT_SYMBOL(GetGraphicsImporterForDataRef);
OSErr qt_GetGraphicsImporterForDataRef(void *dataRef, OSType type, void **importer) {
    (void)dataRef; (void)type;
    if (importer) *importer = NULL;
    return cantFindHandler;
}

OSErr qt_GetGraphicsImporterForFile(const FSSpec *spec, void **importer) QT_SYMBOL(GetGraphicsImporterForFile);
OSErr qt_GetGraphicsImporterForFile(const FSSpec *spec, void **importer) {
    (void)spec;
    if (importer) *importer = NULL;
    return cantFindHandler;
}
