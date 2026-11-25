// Fonts for Carbon programs: the Font Manager's and ATS's fonts, and ATSUI
// text in them, measured and drawn with FreeType.
//
// A font is activated for the program alone, from a file (FMActivateFonts)
// or from memory (ATSFontActivateFromMemory, which games use for the fonts
// they keep in their own archives), and added to FontConfig's fonts, so
// text drawn in its name elsewhere uses it too. A font asked for by name
// (ATSFontFindFromName) is one activated so, by its family, full or
// PostScript name, or else FontConfig's best match, read from its file.
//
// Each font is numbered: its ATSFontRef and FMFont are FONT_REF_BASE plus
// that number, its ATSFontFamilyRef FAMILY_REF_BASE plus it, and its
// FMFontFamily, a 16-bit QuickDraw font number, FAMILY_NUMBER_BASE plus it.
//
// ATSUI's text is laid out one style a layout, as the programs that use it
// for a game's text do: each character's glyph from the font's character
// map, each after the last's advance. It is drawn into the current port's
// pixels, in the style's color.

#include "PerryCarbon.h"

#include <ft2build.h>
#include FT_FREETYPE_H
#include FT_TRUETYPE_TABLES_H

#include <dlfcn.h>
#include <limits.h>
#include <math.h>
#include <pthread.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>

bool carbon_spec_path(const void *spec, char *path, size_t size);

enum {
    kATSInvalidFontContainerRef = 0,
    fnfErr = -43,
    kATSInvalidFontTableAccess = -985,
    kATSUInvalidStyleErr = -8800,
    kATSUInvalidTextLayoutErr = -8801,
    kATSUInvalidFontErr = -8805,
    kATSUFontsMatched = -8808,
    kFMInvalidFontErr = -985,
    kFMInvalidFontFamilyErr = -981,
};

/// FontConfig's FcConfigAppFontAddFile or FcConfigAppFontAddDir, on the
/// current configuration.
static void add_to_fontconfig(const char *path, bool directory) {
    static int (*add_file)(void *, const unsigned char *);
    static int (*add_dir)(void *, const unsigned char *);
    if (!add_file) {
        void *library = dlopen("libfontconfig.so.1", RTLD_NOW | RTLD_GLOBAL);
        if (!library) return;
        add_file = (int (*)(void *, const unsigned char *))dlsym(library, "FcConfigAppFontAddFile");
        add_dir = (int (*)(void *, const unsigned char *))dlsym(library, "FcConfigAppFontAddDir");
    }
    if (directory && add_dir) add_dir(NULL, (const unsigned char *)path);
    else if (!directory && add_file) add_file(NULL, (const unsigned char *)path);
}

/// The file FontConfig would draw a family in, or false.
static bool fontconfig_file(const char *family, char *path, size_t size) {
    static void *(*name_parse)(const unsigned char *);
    static int (*substitute)(void *, void *, int);
    static void (*default_substitute)(void *);
    static void *(*font_match)(void *, void *, int *);
    static int (*get_string)(void *, const char *, int, unsigned char **);
    static void (*destroy)(void *);
    if (!name_parse) {
        void *library = dlopen("libfontconfig.so.1", RTLD_NOW | RTLD_GLOBAL);
        if (!library) return false;
        name_parse = (void *(*)(const unsigned char *))dlsym(library, "FcNameParse");
        substitute = (int (*)(void *, void *, int))dlsym(library, "FcConfigSubstitute");
        default_substitute = (void (*)(void *))dlsym(library, "FcDefaultSubstitute");
        font_match = (void *(*)(void *, void *, int *))dlsym(library, "FcFontMatch");
        get_string = (int (*)(void *, const char *, int, unsigned char **))dlsym(library, "FcPatternGetString");
        destroy = (void (*)(void *))dlsym(library, "FcPatternDestroy");
    }
    if (!name_parse || !substitute || !default_substitute || !font_match || !get_string || !destroy) return false;
    void *pattern = name_parse((const unsigned char *)family);
    if (!pattern) return false;
    substitute(NULL, pattern, 0);   // FcMatchPattern
    default_substitute(pattern);
    int result = 0;
    void *match = font_match(NULL, pattern, &result);
    destroy(pattern);
    unsigned char *file = NULL;
    bool found = match && get_string(match, "file", 0, &file) == 0 && file;
    if (found) snprintf(path, size, "%s", (const char *)file);
    if (match) destroy(match);
    return found;
}

// MARK: - The fonts

#define MAX_FONTS 256
#define FONT_REF_BASE 0x46000000u     // 'F'
#define FAMILY_REF_BASE 0x4a000000u   // 'J'
#define FAMILY_NUMBER_BASE 0x4000

typedef struct {
    uint32_t container;
    const uint8_t *data;
    size_t length;
    uint32_t directory;   // where its table directory starts in data
    int face;             // its number in a collection
    char family[128], full[128], postscript[128];
    char path[PATH_MAX];   // the file it was read from, if one
    FT_Face ft;
} font_entry;

/// Names asked for and the fonts they were given, so each is looked for
/// once.
#define MAX_ALIASES 256
static struct {
    char name[128];
    int font;
} aliases[MAX_ALIASES];
static int alias_count;

static font_entry fonts[MAX_FONTS];
static int font_count;
static uint32_t container_count;
static pthread_mutex_t fonts_lock = PTHREAD_MUTEX_INITIALIZER;
static FT_Library freetype;

static uint32_t read32(const uint8_t *bytes) { return (uint32_t)bytes[0] << 24 | (uint32_t)bytes[1] << 16 | (uint32_t)bytes[2] << 8 | bytes[3]; }
static uint16_t read16(const uint8_t *bytes) { return (uint16_t)(bytes[0] << 8 | bytes[1]); }

/// A table of a font: where it starts in the font's data and how long it
/// is, or false.
static bool find_table(const font_entry *font, uint32_t tag, uint32_t *start, uint32_t *extent) {
    if ((size_t)font->directory + 12 > font->length) return false;
    uint16_t tables = read16(font->data + font->directory + 4);
    for (uint16_t table = 0; table < tables; table++) {
        const uint8_t *record = font->data + font->directory + 12 + table * 16;
        if ((size_t)(record + 16 - font->data) > font->length) return false;
        if (read32(record) != tag) continue;
        *start = read32(record + 8);
        *extent = read32(record + 12);
        return (size_t)*start + *extent <= font->length;
    }
    return false;
}

/// A name from the font's name table (1 family, 4 full, 6 PostScript), as
/// UTF-8: a Windows Unicode one, else a Macintosh Roman one.
static void read_name(const font_entry *font, uint16_t wanted, char *out, size_t size) {
    out[0] = 0;
    uint32_t start, extent;
    if (!find_table(font, 0x6e616d65 /* 'name' */, &start, &extent) || extent < 6) return;
    const uint8_t *table = font->data + start;
    uint16_t count = read16(table + 2), strings = read16(table + 4);
    for (int pass = 0; pass < 2 && !out[0]; pass++) {
        for (uint16_t index = 0; index < count; index++) {
            const uint8_t *record = table + 6 + index * 12;
            if ((uint32_t)(record + 12 - table) > extent) return;
            uint16_t platform = read16(record), name = read16(record + 6);
            uint16_t length = read16(record + 8), offset = read16(record + 10);
            if (name != wanted || (uint32_t)strings + offset + length > extent) continue;
            const uint8_t *text = table + strings + offset;
            size_t written = 0;
            if (pass == 0 && (platform == 3 || platform == 0)) {
                for (uint16_t at = 0; at + 1 < length && written + 4 < size; at += 2) {
                    uint16_t unit = read16(text + at);
                    if (unit < 0x80) out[written++] = (char)unit;
                    else if (unit < 0x800) {
                        out[written++] = (char)(0xc0 | unit >> 6);
                        out[written++] = (char)(0x80 | (unit & 0x3f));
                    } else {
                        out[written++] = (char)(0xe0 | unit >> 12);
                        out[written++] = (char)(0x80 | ((unit >> 6) & 0x3f));
                        out[written++] = (char)(0x80 | (unit & 0x3f));
                    }
                }
            } else if (pass == 1 && platform == 1) {
                for (uint16_t at = 0; at < length && written + 1 < size; at++) out[written++] = (char)(text[at] < 0x80 ? text[at] : '?');
            } else {
                continue;
            }
            out[written] = 0;
            if (out[0]) return;
        }
    }
}

/// Adds a font's faces, from data the table keeps, and gives the number
/// of the first; -1 when no more fit.
static int add_fonts(const uint8_t *data, size_t length, uint32_t container) {
    uint32_t faces = 1, directories[64] = {0};
    if (read32(data) == 0x74746366 /* 'ttcf' */) {
        faces = read32(data + 8);
        if (faces > 64 || 12 + (size_t)faces * 4 > length) faces = 0;
        for (uint32_t face = 0; face < faces; face++) directories[face] = read32(data + 12 + face * 4);
    }
    int first = -1;
    for (uint32_t face = 0; face < faces && font_count < MAX_FONTS; face++) {
        font_entry *font = &fonts[font_count];
        memset(font, 0, sizeof *font);
        font->container = container;
        font->data = data;
        font->length = length;
        font->directory = directories[face];
        font->face = (int)face;
        read_name(font, 1, font->family, sizeof font->family);
        read_name(font, 4, font->full, sizeof font->full);
        read_name(font, 6, font->postscript, sizeof font->postscript);
        if (first < 0) first = font_count;
        font_count++;
    }
    return first;
}

/// A font by its ATSFontRef or FMFont; NULL for another.
static font_entry *font_for(uint32_t reference) {
    uint32_t index = reference - FONT_REF_BASE;
    return reference >= FONT_REF_BASE && index < (uint32_t)font_count ? &fonts[index] : NULL;
}

/// FreeType's face for a font, made the first time.
static FT_Face face_for(font_entry *font) {
    if (!font) return NULL;
    if (!font->ft) {
        if (!freetype && FT_Init_FreeType(&freetype) != 0) return NULL;
        if (FT_New_Memory_Face(freetype, font->data, (FT_Long)font->length, font->face, &font->ft) != 0) font->ft = NULL;
    }
    return font->ft;
}

static int font_from_file(const char *path);

/// FontConfig's pattern for a name like a Mac's, "Arial Bold": a family,
/// and a style when the last words are one.
static void fontconfig_pattern(const char *name, char *pattern, size_t size) {
    static const char *const styles[] = {"Bold Italic", "Bold Oblique", "Bold", "Italic", "Oblique", "Regular", "Medium", "Light"};
    size_t length = strlen(name);
    for (size_t index = 0; index < sizeof styles / sizeof styles[0]; index++) {
        size_t style = strlen(styles[index]);
        if (length > style + 1 && name[length - style - 1] == ' ' && !strcasecmp(name + length - style, styles[index])) {
            snprintf(pattern, size, "%.*s:style=%s", (int)(length - style - 1), name, styles[index]);
            return;
        }
    }
    snprintf(pattern, size, "%s", name);
}

/// The number of an activated font with this family, full or PostScript
/// name, in any case; else FontConfig's choice for the name, added from
/// its file once; else -1.
static int font_named(const char *name) {
    if (!name || !*name) return -1;
    pthread_mutex_lock(&fonts_lock);
    int found = -1;
    for (int index = 0; index < alias_count && found < 0; index++)
        if (!strcasecmp(aliases[index].name, name)) found = aliases[index].font;
    for (int index = 0; index < font_count && found < 0; index++)
        if (!strcasecmp(fonts[index].postscript, name) || !strcasecmp(fonts[index].full, name)) found = index;
    for (int index = 0; index < font_count && found < 0; index++)
        if (!strcasecmp(fonts[index].family, name)) found = index;
    pthread_mutex_unlock(&fonts_lock);
    if (found >= 0) return found;
    char pattern[300], path[PATH_MAX];
    fontconfig_pattern(name, pattern, sizeof pattern);
    if (!fontconfig_file(pattern, path, sizeof path)) return -1;
    pthread_mutex_lock(&fonts_lock);
    for (int index = 0; index < font_count && found < 0; index++)
        if (!strcmp(fonts[index].path, path)) found = index;
    pthread_mutex_unlock(&fonts_lock);
    if (found < 0) found = font_from_file(path);
    if (found >= 0) {
        pthread_mutex_lock(&fonts_lock);
        if (alias_count < MAX_ALIASES) {
            snprintf(aliases[alias_count].name, sizeof aliases[alias_count].name, "%s", name);
            aliases[alias_count].font = found;
            alias_count++;
        }
        pthread_mutex_unlock(&fonts_lock);
    }
    return found;
}

/// A font file's fonts, added: the first one's number, or -1.
static int font_from_file(const char *path) {
    int found = -1;
    FILE *file = fopen(path, "rb");
    if (!file) return -1;
    fseek(file, 0, SEEK_END);
    long length = ftell(file);
    fseek(file, 0, SEEK_SET);
    uint8_t *data = length > 12 ? malloc((size_t)length) : NULL;
    bool read = data && fread(data, 1, (size_t)length, file) == (size_t)length;
    fclose(file);
    if (!read) {
        free(data);
        return -1;
    }
    pthread_mutex_lock(&fonts_lock);
    found = add_fonts(data, (size_t)length, ++container_count);
    for (int index = found; index >= 0 && index < font_count; index++)
        if (fonts[index].data == data) snprintf(fonts[index].path, sizeof fonts[index].path, "%s", path);
    pthread_mutex_unlock(&fonts_lock);
    return found;
}

/// A CFString as UTF-8.
static bool cf_string(const void *string, char *out, size_t size) {
    static unsigned char (*get_c_string)(const void *, char *, long, uint32_t);
    if (!get_c_string) get_c_string = (unsigned char (*)(const void *, char *, long, uint32_t))carbon_function(COREFOUNDATION, "_CFStringGetCString");
    return string && get_c_string && get_c_string(string, out, (long)size, 0x08000100 /* kCFStringEncodingUTF8 */);
}

// MARK: - Activating

/// The files fonts from memory were written to for FontConfig, removed
/// when the program ends.
#define MAX_WRITTEN 64
static char *written[MAX_WRITTEN];
static int written_count;

static void remove_written(void) {
    for (int index = 0; index < written_count; index++) {
        unlink(written[index]);
        free(written[index]);
    }
    written_count = 0;
}

/// Writes a font's data where FontConfig reads it, once for each copy of
/// the same data the program activates.
static void write_for_fontconfig(const uint8_t *data, size_t length, uint32_t number) {
    const char *temporary = getenv("TMPDIR");
    char path[PATH_MAX];
    snprintf(path, sizeof path, "%s/perry-font-%d-%u.%s", temporary && *temporary ? temporary : "/tmp", (int)getpid(), number,
             read32(data) == 0x74746366 ? "ttc" : read32(data) == 0x4f54544f /* 'OTTO' */ ? "otf" : "ttf");
    FILE *file = fopen(path, "wb");
    if (!file) return;
    bool complete = fwrite(data, 1, length, file) == length;
    fclose(file);
    if (!complete) {
        unlink(path);
        return;
    }
    add_to_fontconfig(path, false);
    pthread_mutex_lock(&fonts_lock);
    if (written_count == 0) atexit(remove_written);
    if (written_count < MAX_WRITTEN) written[written_count++] = strdup(path);
    pthread_mutex_unlock(&fonts_lock);
}

/// Activates the fonts in a TrueType or OpenType font, or a collection of
/// them, given as data: a copy is kept, written where FontConfig reads it.
OSStatus carbon_ATSFontActivateFromMemory(const void *data, size_t length, uint32_t context, uint32_t format, void *reserved,
                                          uint32_t options, uint32_t *container) CARBON_SYMBOL(ATSFontActivateFromMemory);
OSStatus carbon_ATSFontActivateFromMemory(const void *data, size_t length, uint32_t context, uint32_t format, void *reserved,
                                          uint32_t options, uint32_t *container) {
    (void)context; (void)format; (void)reserved; (void)options;
    if (container) *container = kATSInvalidFontContainerRef;
    if (!data || length < 12 || !container) return paramErr;
    uint8_t *copy = malloc(length);
    if (!copy) return memFullErr;
    memcpy(copy, data, length);
    pthread_mutex_lock(&fonts_lock);
    uint32_t number = ++container_count;
    add_fonts(copy, length, number);
    pthread_mutex_unlock(&fonts_lock);
    // For FontConfig: the data as a file in the program's temporary folder,
    // unless the same font was activated before.
    bool seen = false;
    pthread_mutex_lock(&fonts_lock);
    for (int index = 0; index < font_count && !seen; index++)
        seen = fonts[index].data != copy && fonts[index].length == length && !memcmp(fonts[index].data, copy, length);
    pthread_mutex_unlock(&fonts_lock);
    if (!seen) write_for_fontconfig(copy, length, number);
    *container = number;
    CARBON_TRACE("fonts from memory: container %u, %zu bytes, %s", number, length, fonts[font_count - 1].postscript);
    return noErr;
}

/// The fonts a container holds: ATSFontRefs, as many as fit; with no
/// array, how many there are.
OSStatus carbon_ATSFontFindFromContainer(uint32_t container, uint32_t options, size_t count, uint32_t *array, size_t *found)
    CARBON_SYMBOL(ATSFontFindFromContainer);
OSStatus carbon_ATSFontFindFromContainer(uint32_t container, uint32_t options, size_t count, uint32_t *array, size_t *found) {
    (void)options;
    size_t matches = 0;
    pthread_mutex_lock(&fonts_lock);
    for (int index = 0; index < font_count; index++) {
        if (fonts[index].container != container) continue;
        if (array && matches < count) array[matches] = FONT_REF_BASE + (uint32_t)index;
        matches++;
    }
    pthread_mutex_unlock(&fonts_lock);
    if (found) *found = array && matches > count ? count : matches;
    return matches ? noErr : paramErr;
}

/// Activates the fonts in a file, or in a folder's files, for the program:
/// those in data forks, which FontConfig reads; a suitcase's resources are
/// not.
OSStatus carbon_FMActivateFonts(const void *spec, const void *filter, void *refCon, uint32_t options) CARBON_SYMBOL(FMActivateFonts);
OSStatus carbon_FMActivateFonts(const void *spec, const void *filter, void *refCon, uint32_t options) {
    (void)filter; (void)refCon; (void)options;
    char path[PATH_MAX];
    struct stat info;
    if (!spec || !carbon_spec_path(spec, path, sizeof path)) return paramErr;
    if (stat(path, &info) != 0) return fnfErr;
    add_to_fontconfig(path, S_ISDIR(info.st_mode));
    return noErr;
}

/// FontConfig keeps a program's fonts until it ends.
OSStatus carbon_FMDeactivateFonts(const void *spec, const void *filter, void *refCon, uint32_t options) CARBON_SYMBOL(FMDeactivateFonts);
OSStatus carbon_FMDeactivateFonts(const void *spec, const void *filter, void *refCon, uint32_t options) {
    (void)spec; (void)filter; (void)refCon; (void)options;
    return noErr;
}

// MARK: - Finding fonts

uint32_t carbon_ATSFontFindFromName(const void *name, uint32_t options) CARBON_SYMBOL(ATSFontFindFromName);
uint32_t carbon_ATSFontFindFromName(const void *name, uint32_t options) {
    (void)options;
    char text[256] = "";
    int index = cf_string(name, text, sizeof text) ? font_named(text) : -1;
    CARBON_TRACE("font named %s: %s", text, index < 0 ? "none" : fonts[index].postscript);
    return index < 0 ? 0 : FONT_REF_BASE + (uint32_t)index;
}

uint32_t carbon_ATSFontFamilyFindFromName(const void *name, uint32_t options) CARBON_SYMBOL(ATSFontFamilyFindFromName);
uint32_t carbon_ATSFontFamilyFindFromName(const void *name, uint32_t options) {
    (void)options;
    char text[256] = "";
    int index = cf_string(name, text, sizeof text) ? font_named(text) : -1;
    CARBON_TRACE("font family named %s: %s", text, index < 0 ? "none" : fonts[index].family);
    return index < 0 ? 0 : FAMILY_REF_BASE + (uint32_t)index;
}

int16_t carbon_FMGetFontFamilyFromATSFontFamilyRef(uint32_t family) CARBON_SYMBOL(FMGetFontFamilyFromATSFontFamilyRef);
int16_t carbon_FMGetFontFamilyFromATSFontFamilyRef(uint32_t family) {
    uint32_t index = family - FAMILY_REF_BASE;
    return family >= FAMILY_REF_BASE && index < (uint32_t)font_count ? (int16_t)(FAMILY_NUMBER_BASE + index) : -1;
}

uint32_t carbon_FMGetATSFontFamilyRefFromFontFamily(int16_t family) CARBON_SYMBOL(FMGetATSFontFamilyRefFromFontFamily);
uint32_t carbon_FMGetATSFontFamilyRefFromFontFamily(int16_t family) {
    int index = family - FAMILY_NUMBER_BASE;
    return index >= 0 && index < font_count ? FAMILY_REF_BASE + (uint32_t)index : 0;
}

/// The font of a family in a style: the family's own font, whose style it
/// is given intrinsically (none), the rest left to be made by QuickDraw.
OSStatus carbon_FMGetFontFromFontFamilyInstance(int16_t family, int16_t style, uint32_t *font, int16_t *intrinsic)
    CARBON_SYMBOL(FMGetFontFromFontFamilyInstance);
OSStatus carbon_FMGetFontFromFontFamilyInstance(int16_t family, int16_t style, uint32_t *font, int16_t *intrinsic) {
    (void)style;
    int index = family - FAMILY_NUMBER_BASE;
    if (index < 0 || index >= font_count) return kFMInvalidFontFamilyErr;
    if (font) *font = FONT_REF_BASE + (uint32_t)index;
    if (intrinsic) *intrinsic = 0;
    return noErr;
}

/// An FMFont is its ATSFontRef here, and the other way.
uint32_t carbon_FMGetFontFromATSFontRef(uint32_t font) CARBON_SYMBOL(FMGetFontFromATSFontRef);
uint32_t carbon_FMGetFontFromATSFontRef(uint32_t font) { return font_for(font) ? font : 0; }

uint32_t carbon_FMGetATSFontRefFromFont(uint32_t font) CARBON_SYMBOL(FMGetATSFontRefFromFont);
uint32_t carbon_FMGetATSFontRefFromFont(uint32_t font) { return font_for(font) ? font : 0; }

/// A QuickDraw font number's family name, as a Pascal string; the system
/// font's for 0.
void carbon_GetFontName(int16_t family, unsigned char *name) CARBON_SYMBOL(GetFontName);
void carbon_GetFontName(int16_t family, unsigned char *name) {
    if (!name) return;
    int index = family - FAMILY_NUMBER_BASE;
    const char *text = index >= 0 && index < font_count && fonts[index].family[0] ? fonts[index].family : family == 0 ? "Lucida Grande" : "";
    size_t length = strlen(text) > 255 ? 255 : strlen(text);
    name[0] = (unsigned char)length;
    memcpy(name + 1, text, length);
}

// MARK: - Metrics

/// A font table: its size alone with no buffer, else as much of it from
/// the offset as fits.
OSStatus carbon_ATSFontGetTable(uint32_t reference, uint32_t tag, size_t offset, size_t size, void *buffer, size_t *actual)
    CARBON_SYMBOL(ATSFontGetTable);
OSStatus carbon_ATSFontGetTable(uint32_t reference, uint32_t tag, size_t offset, size_t size, void *buffer, size_t *actual) {
    if (actual) *actual = 0;
    font_entry *font = font_for(reference);
    uint32_t start, extent;
    if (!font) return paramErr;
    if (!find_table(font, tag, &start, &extent)) return kATSInvalidFontTableAccess;
    if (!buffer) {
        if (actual) *actual = extent;
        return noErr;
    }
    if (offset >= extent) return noErr;
    size_t copied = extent - offset < size ? extent - offset : size;
    memcpy(buffer, font->data + start + offset, copied);
    if (actual) *actual = copied;
    return noErr;
}

typedef struct {
    uint32_t version;
    float ascent, descent, leading;
    float avgAdvanceWidth, maxAdvanceWidth;
    float minLeftSideBearing, minRightSideBearing;
    float stemWidth, stemHeight;
    float capHeight, xHeight;
    float italicAngle;
    float underlinePosition, underlineThickness;
} ATSFontMetrics;

/// A font's horizontal metrics, as fractions of its em: descent below the
/// baseline is negative.
OSStatus carbon_ATSFontGetHorizontalMetrics(uint32_t reference, uint32_t options, ATSFontMetrics *metrics)
    CARBON_SYMBOL(ATSFontGetHorizontalMetrics);
OSStatus carbon_ATSFontGetHorizontalMetrics(uint32_t reference, uint32_t options, ATSFontMetrics *metrics) {
    (void)options;
    FT_Face face = face_for(font_for(reference));
    if (!face || !metrics) return paramErr;
    float em = face->units_per_EM ? (float)face->units_per_EM : 1000.0f;
    memset(metrics, 0, sizeof *metrics);
    metrics->version = 0;
    metrics->ascent = face->ascender / em;
    metrics->descent = face->descender / em;
    metrics->leading = (face->height - face->ascender + face->descender) / em;
    if (metrics->leading < 0) metrics->leading = 0;
    metrics->maxAdvanceWidth = face->max_advance_width / em;
    metrics->minLeftSideBearing = face->bbox.xMin / em;
    metrics->minRightSideBearing = 0;
    metrics->underlinePosition = face->underline_position / em;
    metrics->underlineThickness = face->underline_thickness / em;
    TT_OS2 *os2 = (TT_OS2 *)FT_Get_Sfnt_Table(face, FT_SFNT_OS2);
    if (os2) {
        metrics->avgAdvanceWidth = os2->xAvgCharWidth / em;
        metrics->capHeight = os2->version >= 2 ? os2->sCapHeight / em : metrics->ascent;
        metrics->xHeight = os2->version >= 2 ? os2->sxHeight / em : metrics->ascent / 2;
    } else {
        metrics->avgAdvanceWidth = metrics->maxAdvanceWidth / 2;
        metrics->capHeight = metrics->ascent;
        metrics->xHeight = metrics->ascent / 2;
    }
    TT_Postscript *post = (TT_Postscript *)FT_Get_Sfnt_Table(face, FT_SFNT_POST);
    if (post) metrics->italicAngle = (float)post->italicAngle / 65536.0f;
    return noErr;
}

/// The current port's font's ascent, descent, widest advance and leading,
/// in pixels at its size: its own font if it is one here, else a sans
/// serif one.
void carbon_GetFontInfo(FontInfo *info) CARBON_SYMBOL(GetFontInfo);
void carbon_GetFontInfo(FontInfo *info) {
    if (!info) return;
    CGrafPtr port = carbon_current_port();
    int size = port && port->textSize > 0 ? port->textSize : 12;
    int index = port ? port->textFont - FAMILY_NUMBER_BASE : -1;
    if (index < 0 || index >= font_count) index = font_named("sans-serif");
    FT_Face face = index >= 0 ? face_for(&fonts[index]) : NULL;
    if (!face || !face->units_per_EM) {
        info->ascent = (int16_t)(size * 3 / 4 + 1);
        info->descent = (int16_t)(size / 4 + 1);
        info->widMax = (int16_t)size;
        info->leading = 0;
        return;
    }
    double scale = (double)size / face->units_per_EM;
    info->ascent = (int16_t)ceil(face->ascender * scale);
    info->descent = (int16_t)ceil(-face->descender * scale);
    info->widMax = (int16_t)ceil(face->max_advance_width * scale);
    int leading = (int)ceil((face->height - face->ascender + face->descender) * scale);
    info->leading = (int16_t)(leading > 0 ? leading : 0);
}

// MARK: - ATSUI styles and layouts

#define STYLE_MAGIC 0x41545359u    // 'ATSY'
#define LAYOUT_MAGIC 0x4154534cu   // 'ATSL'

typedef struct {
    uint32_t magic;
    uint32_t font;     // ATSUFontID: an FMFont
    int32_t size;      // Fixed
    float red, green, blue, alpha;
    bool bold, italic;
} atsu_style;

#pragma pack(push, 2)
typedef struct {
    uint16_t glyphID;
    uint32_t flags;
    uint32_t originalOffset;
    int32_t realPos;
} ATSLayoutRecord;
#pragma pack(pop)

typedef struct {
    uint32_t magic;
    const uint16_t *text;
    uint32_t offset, length, total;
    atsu_style *style;
    ATSLayoutRecord *records;   // the last laid out, for the direct access
} atsu_layout;

static atsu_style *style_from(void *pointer) {
    atsu_style *style = pointer;
    return style && style->magic == STYLE_MAGIC ? style : NULL;
}

static atsu_layout *layout_from(void *pointer) {
    atsu_layout *layout = pointer;
    return layout && layout->magic == LAYOUT_MAGIC ? layout : NULL;
}

OSStatus carbon_ATSUCreateStyle(void **out) CARBON_SYMBOL(ATSUCreateStyle);
OSStatus carbon_ATSUCreateStyle(void **out) {
    if (!out) return paramErr;
    atsu_style *style = calloc(1, sizeof *style);
    if (!style) return memFullErr;
    style->magic = STYLE_MAGIC;
    style->size = 12 << 16;
    style->alpha = 1;
    *out = style;
    return noErr;
}

OSStatus carbon_ATSUDisposeStyle(void *pointer) CARBON_SYMBOL(ATSUDisposeStyle);
OSStatus carbon_ATSUDisposeStyle(void *pointer) {
    atsu_style *style = style_from(pointer);
    if (!style) return kATSUInvalidStyleErr;
    style->magic = 0;
    free(style);
    return noErr;
}

enum {
    kATSUQDBoldfaceTag = 256, kATSUQDItalicTag = 257, kATSUFontTag = 261, kATSUSizeTag = 262, kATSUColorTag = 263,
    kATSURGBAlphaColorTag = 288,
};

/// A style's attributes: its font, size, color, bold and italic; the
/// others are taken and change nothing here.
OSStatus carbon_ATSUSetAttributes(void *pointer, size_t count, const uint32_t *tags, const size_t *sizes, void *const *values)
    CARBON_SYMBOL(ATSUSetAttributes);
OSStatus carbon_ATSUSetAttributes(void *pointer, size_t count, const uint32_t *tags, const size_t *sizes, void *const *values) {
    atsu_style *style = style_from(pointer);
    if (!style) return kATSUInvalidStyleErr;
    if (count && (!tags || !sizes || !values)) return paramErr;
    for (size_t index = 0; index < count; index++) {
        const void *value = values[index];
        if (!value) continue;
        switch (tags[index]) {
        case kATSUFontTag: style->font = *(const uint32_t *)value; break;
        case kATSUSizeTag: style->size = *(const int32_t *)value; break;
        case kATSUQDBoldfaceTag: style->bold = *(const uint8_t *)value != 0; break;
        case kATSUQDItalicTag: style->italic = *(const uint8_t *)value != 0; break;
        case kATSUColorTag: {
            const RGBColor *color = value;
            style->red = color->red / 65535.0f;
            style->green = color->green / 65535.0f;
            style->blue = color->blue / 65535.0f;
            style->alpha = 1;
            break;
        }
        case kATSURGBAlphaColorTag: {
            const float *color = value;
            style->red = color[0];
            style->green = color[1];
            style->blue = color[2];
            style->alpha = color[3];
            break;
        }
        default: break;
        }
        (void)sizes;
    }
    return noErr;
}

OSStatus carbon_ATSUCreateTextLayout(void **out) CARBON_SYMBOL(ATSUCreateTextLayout);
OSStatus carbon_ATSUCreateTextLayout(void **out) {
    if (!out) return paramErr;
    atsu_layout *layout = calloc(1, sizeof *layout);
    if (!layout) return memFullErr;
    layout->magic = LAYOUT_MAGIC;
    *out = layout;
    return noErr;
}

OSStatus carbon_ATSUDisposeTextLayout(void *pointer) CARBON_SYMBOL(ATSUDisposeTextLayout);
OSStatus carbon_ATSUDisposeTextLayout(void *pointer) {
    atsu_layout *layout = layout_from(pointer);
    if (!layout) return kATSUInvalidTextLayoutErr;
    layout->magic = 0;
    free(layout->records);
    free(layout);
    return noErr;
}

/// The text a layout lays out: the program's, which it keeps.
OSStatus carbon_ATSUSetTextPointerLocation(void *pointer, const uint16_t *text, uint32_t offset, uint32_t length, uint32_t total)
    CARBON_SYMBOL(ATSUSetTextPointerLocation);
OSStatus carbon_ATSUSetTextPointerLocation(void *pointer, const uint16_t *text, uint32_t offset, uint32_t length, uint32_t total) {
    atsu_layout *layout = layout_from(pointer);
    if (!layout) return kATSUInvalidTextLayoutErr;
    layout->text = text;
    layout->offset = offset;
    layout->length = length;
    layout->total = total;
    return noErr;
}

/// A run's style: the whole layout's here.
OSStatus carbon_ATSUSetRunStyle(void *pointer, void *style, uint32_t offset, uint32_t length) CARBON_SYMBOL(ATSUSetRunStyle);
OSStatus carbon_ATSUSetRunStyle(void *pointer, void *style, uint32_t offset, uint32_t length) {
    (void)offset; (void)length;
    atsu_layout *layout = layout_from(pointer);
    if (!layout) return kATSUInvalidTextLayoutErr;
    if (!style_from(style)) return kATSUInvalidStyleErr;
    layout->style = style;
    return noErr;
}

/// A style's face, set to its size in pixels; NULL when its font is none
/// here (a sans serif one stands in for no font).
static FT_Face sized_face(const atsu_style *style) {
    font_entry *font = font_for(style->font);
    if (!font) {
        int index = font_named("sans-serif");
        font = index >= 0 ? &fonts[index] : NULL;
    }
    FT_Face face = face_for(font);
    if (!face) return NULL;
    FT_F26Dot6 size = (FT_F26Dot6)((int64_t)style->size * 64 / 65536);
    if (size < 64) size = 64;
    if (FT_Set_Char_Size(face, 0, size, 72, 72) != 0) return NULL;
    return face;
}

/// The glyph of a character, decoding a surrogate pair from its two units.
static FT_UInt glyph_of(FT_Face face, const uint16_t *text, uint32_t *index, uint32_t end) {
    uint32_t character = text[*index];
    if (character >= 0xd800 && character < 0xdc00 && *index + 1 < end && text[*index + 1] >= 0xdc00 && text[*index + 1] < 0xe000) {
        character = 0x10000 + ((character - 0xd800) << 10) + (text[*index + 1] - 0xdc00);
        (*index)++;
    }
    return FT_Get_Char_Index(face, character);
}

/// Lays a layout's text from `start` out: its records, the last at the
/// end of the line, in Fixed pixels from its start; how many there are.
static size_t lay_out(atsu_layout *layout, uint32_t start, uint32_t length, ATSLayoutRecord **records) {
    *records = NULL;
    if (!layout->text || !layout->style) return 0;
    FT_Face face = sized_face(layout->style);
    if (!face) return 0;
    uint32_t end = start + length;
    ATSLayoutRecord *out = calloc((size_t)length + 1, sizeof *out);
    if (!out) return 0;
    size_t count = 0;
    int64_t position = 0;
    for (uint32_t index = start; index < end; index++) {
        uint32_t first = index;
        FT_UInt glyph = glyph_of(face, layout->text, &index, end);
        out[count].glyphID = (uint16_t)glyph;
        out[count].flags = 0;
        out[count].originalOffset = (first - start) * 2;
        out[count].realPos = (int32_t)position;
        if (FT_Load_Glyph(face, glyph, FT_LOAD_DEFAULT) == 0) position += (int64_t)face->glyph->advance.x * 1024;   // 26.6 to Fixed
        count++;
    }
    out[count].glyphID = 0xffff;   // kATSDeletedGlyphcode
    out[count].originalOffset = length * 2;
    out[count].realPos = (int32_t)position;
    *records = out;
    return count + 1;
}

static uint32_t text_start(const atsu_layout *layout, uint32_t offset, uint32_t *length) {
    if (offset == 0xffffffffu) offset = layout->offset;   // kATSUFromTextBeginning
    if (*length == 0xffffffffu) *length = layout->offset + layout->length - offset;   // kATSUToTextEnd
    return offset;
}

/// The layout's glyph records from a line's start, which ATSUI keeps for
/// the program to read until the next ones.
OSStatus carbon_ATSUDirectGetLayoutDataArrayPtrFromTextLayout(void *pointer, uint32_t offset, uint32_t selector, void **array,
                                                              size_t *count) CARBON_SYMBOL(ATSUDirectGetLayoutDataArrayPtrFromTextLayout);
OSStatus carbon_ATSUDirectGetLayoutDataArrayPtrFromTextLayout(void *pointer, uint32_t offset, uint32_t selector, void **array,
                                                              size_t *count) {
    atsu_layout *layout = layout_from(pointer);
    if (array) *array = NULL;
    if (count) *count = 0;
    if (!layout) return kATSUInvalidTextLayoutErr;
    if (selector != 100) return paramErr;   // kATSUDirectDataLayoutRecordATSLayoutRecordCurrent
    uint32_t length = 0xffffffffu;
    uint32_t start = text_start(layout, offset, &length);
    free(layout->records);
    size_t made = lay_out(layout, start, length, &layout->records);
    if (array) *array = layout->records;
    if (count) *count = made;
    return noErr;
}

/// The records are the layout's until it lays out again or goes.
OSStatus carbon_ATSUDirectReleaseLayoutDataArrayPtr(void *line, uint32_t selector, void **array)
    CARBON_SYMBOL(ATSUDirectReleaseLayoutDataArrayPtr);
OSStatus carbon_ATSUDirectReleaseLayoutDataArrayPtr(void *line, uint32_t selector, void **array) {
    (void)line; (void)selector;
    if (array) *array = NULL;
    return noErr;
}

/// The box a layout's text's glyphs ink, from its origin at (x, y) in
/// QuickDraw's coordinates: above the baseline is up, negative.
OSStatus carbon_ATSUMeasureTextImage(void *pointer, uint32_t offset, uint32_t length, int32_t x, int32_t y, Rect *box)
    CARBON_SYMBOL(ATSUMeasureTextImage);
OSStatus carbon_ATSUMeasureTextImage(void *pointer, uint32_t offset, uint32_t length, int32_t x, int32_t y, Rect *box) {
    atsu_layout *layout = layout_from(pointer);
    if (!layout) return kATSUInvalidTextLayoutErr;
    if (!box) return paramErr;
    *box = (Rect){0, 0, 0, 0};
    uint32_t start = text_start(layout, offset, &length);
    ATSLayoutRecord *records;
    size_t count = lay_out(layout, start, length, &records);
    FT_Face face = layout->style ? sized_face(layout->style) : NULL;
    if (!face || count == 0) {
        free(records);
        return noErr;
    }
    int left = INT32_MAX, top = INT32_MAX, right = INT32_MIN, bottom = INT32_MIN;
    for (size_t index = 0; index + 1 < count; index++) {
        if (FT_Load_Glyph(face, records[index].glyphID, FT_LOAD_DEFAULT) != 0) continue;
        FT_Glyph_Metrics *metrics = &face->glyph->metrics;
        if (metrics->width == 0 || metrics->height == 0) continue;
        int origin = records[index].realPos >> 16;
        int glyphLeft = origin + (int)floor(metrics->horiBearingX / 64.0);
        int glyphTop = -(int)ceil(metrics->horiBearingY / 64.0);
        int glyphRight = glyphLeft + (int)ceil(metrics->width / 64.0);
        int glyphBottom = glyphTop + (int)ceil(metrics->height / 64.0);
        if (glyphLeft < left) left = glyphLeft;
        if (glyphTop < top) top = glyphTop;
        if (glyphRight > right) right = glyphRight;
        if (glyphBottom > bottom) bottom = glyphBottom;
    }
    free(records);
    if (left > right) return noErr;
    int originX = x >> 16, originY = y >> 16;
    *box = (Rect){(int16_t)(top + originY), (int16_t)(left + originX), (int16_t)(bottom + originY), (int16_t)(right + originX)};
    return noErr;
}

typedef struct {
    float x, y;
} Float32Point;

typedef struct {
    Float32Point deviceAdvance;
    Float32Point topLeft;
    uint32_t height;
    uint32_t width;
    Float32Point sideBearing;
    Float32Point otherSideBearing;
} ATSGlyphScreenMetrics;

/// Glyphs' metrics in a style, in pixels: each glyph ID `stride` bytes
/// from the last.
OSStatus carbon_ATSUGlyphGetScreenMetrics(void *pointer, size_t count, const uint16_t *glyphs, size_t stride, uint8_t integers,
                                          uint8_t antialiased, ATSGlyphScreenMetrics *metrics) CARBON_SYMBOL(ATSUGlyphGetScreenMetrics);
OSStatus carbon_ATSUGlyphGetScreenMetrics(void *pointer, size_t count, const uint16_t *glyphs, size_t stride, uint8_t integers,
                                          uint8_t antialiased, ATSGlyphScreenMetrics *metrics) {
    (void)antialiased;
    atsu_style *style = style_from(pointer);
    if (!style) return kATSUInvalidStyleErr;
    if (count && (!glyphs || !metrics)) return paramErr;
    FT_Face face = sized_face(style);
    if (!face) return kATSUInvalidFontErr;
    if (stride == 0) stride = sizeof *glyphs;
    for (size_t index = 0; index < count; index++) {
        uint16_t glyph = *(const uint16_t *)((const uint8_t *)glyphs + index * stride);
        ATSGlyphScreenMetrics *out = &metrics[index];
        memset(out, 0, sizeof *out);
        if (FT_Load_Glyph(face, glyph, FT_LOAD_DEFAULT) != 0) continue;
        FT_Glyph_Metrics *m = &face->glyph->metrics;
        float advance = face->glyph->advance.x / 64.0f;
        out->deviceAdvance.x = integers ? roundf(advance) : advance;
        out->topLeft.x = floorf(m->horiBearingX / 64.0f);
        out->topLeft.y = ceilf(m->horiBearingY / 64.0f);
        out->width = (uint32_t)ceil(m->width / 64.0);
        out->height = (uint32_t)ceil(m->height / 64.0);
        out->sideBearing.x = m->horiBearingX / 64.0f;
        out->otherSideBearing.x = advance - (m->horiBearingX + m->width) / 64.0f;
    }
    return noErr;
}

/// Draws a layout's text into the current port's pixels, from its origin
/// at (x, y), or at the pen; within the port's bounds, each pixel blended
/// with the style's color by the glyph's coverage.
OSStatus carbon_ATSUDrawText(void *pointer, uint32_t offset, uint32_t length, int32_t x, int32_t y) CARBON_SYMBOL(ATSUDrawText);
OSStatus carbon_ATSUDrawText(void *pointer, uint32_t offset, uint32_t length, int32_t x, int32_t y) {
    atsu_layout *layout = layout_from(pointer);
    if (!layout) return kATSUInvalidTextLayoutErr;
    CGrafPtr port = carbon_current_port();
    if (!port || !port->pixmap || !*port->pixmap || !(*port->pixmap)->baseAddr) return noErr;
    PixMap *pixmap = *port->pixmap;
    if (x == (int32_t)0x80000000) x = port->pen.h << 16;   // kATSUUseGrafPortPenLoc
    if (y == (int32_t)0x80000000) y = port->pen.v << 16;
    uint32_t start = text_start(layout, offset, &length);
    ATSLayoutRecord *records;
    size_t count = lay_out(layout, start, length, &records);
    FT_Face face = layout->style ? sized_face(layout->style) : NULL;
    if (!face) {
        free(records);
        return noErr;
    }
    const atsu_style *style = layout->style;
    long rowBytes = pixmap->rowBytes & 0x3fff;
    int originY = (int)lround(y / 65536.0);
    for (size_t index = 0; index + 1 < count; index++) {
        if (FT_Load_Glyph(face, records[index].glyphID, FT_LOAD_DEFAULT) != 0) continue;
        if (FT_Render_Glyph(face->glyph, FT_RENDER_MODE_NORMAL) != 0) continue;
        FT_Bitmap *bitmap = &face->glyph->bitmap;
        int left = (int)lround((x + (int64_t)records[index].realPos) / 65536.0) + face->glyph->bitmap_left;
        int top = originY - face->glyph->bitmap_top;
        for (unsigned row = 0; row < bitmap->rows; row++) {
            int py = top + (int)row;
            if (py < pixmap->bounds.top || py >= pixmap->bounds.bottom) continue;
            const uint8_t *coverage = bitmap->buffer + (long)row * bitmap->pitch;
            uint8_t *line = (uint8_t *)pixmap->baseAddr + (long)(py - pixmap->bounds.top) * rowBytes;
            for (unsigned column = 0; column < bitmap->width; column++) {
                int px = left + (int)column;
                if (px < pixmap->bounds.left || px >= pixmap->bounds.right) continue;
                float a = coverage[column] / 255.0f * style->alpha;
                if (a <= 0) continue;
                int at = px - pixmap->bounds.left;
                if (pixmap->pixelSize == 16) {
                    uint8_t *pixel = line + at * 2;
                    uint16_t value = (uint16_t)(pixel[0] << 8 | pixel[1]);
                    float r = ((value >> 10) & 31) / 31.0f, g = ((value >> 5) & 31) / 31.0f, b = (value & 31) / 31.0f;
                    r += (style->red - r) * a;
                    g += (style->green - g) * a;
                    b += (style->blue - b) * a;
                    value = (uint16_t)((int)lroundf(r * 31) << 10 | (int)lroundf(g * 31) << 5 | (int)lroundf(b * 31));
                    pixel[0] = (uint8_t)(value >> 8);
                    pixel[1] = (uint8_t)value;
                } else if (pixmap->pixelSize == 32) {
                    uint8_t *pixel = line + at * 4;
                    float da = pixel[0] / 255.0f;
                    pixel[0] = (uint8_t)lroundf((a + da * (1 - a)) * 255);
                    pixel[1] = (uint8_t)lroundf(pixel[1] + (style->red * 255 - pixel[1]) * a);
                    pixel[2] = (uint8_t)lroundf(pixel[2] + (style->green * 255 - pixel[2]) * a);
                    pixel[3] = (uint8_t)lroundf(pixel[3] + (style->blue * 255 - pixel[3]) * a);
                }
            }
        }
    }
    free(records);
    if (port->window) carbon_port_flush(port);
    return noErr;
}
