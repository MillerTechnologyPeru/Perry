// The provider's startup, the Objective-C runtime it reaches AppKit
// through, and Carbon's small services: the Script Manager's answers for a
// Roman-script system, the Date and Time Utilities, Driver Services' clock
// and atomic operations, Multiprocessing Services' memory and delays,
// Pascal strings, UPPs (which on Mac OS X are the function pointers
// themselves), the cursor and the menu bar.

#include "PerryCarbon.h"
#include "perry_interface.h"

#include <ctype.h>
#include <sched.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <unistd.h>

id (*objc_send)(id, SEL, ...);
SEL (*objc_selector)(const char *);
id (*objc_class)(const char *);
void *(*carbon_lookup)(const char *library, const char *name);

__attribute__((visibility("default")))
void perry_provider_startup(const perry_startup_info *info) {
    if (info->version < 2 || !info->lookup_symbol) return;
    carbon_lookup = info->lookup_symbol;
    const char *objc = "/usr/lib/libobjc.A.dylib";
    objc_send = (id (*)(id, SEL, ...))info->lookup_symbol(objc, "_objc_msgSend");
    objc_selector = (SEL (*)(const char *))info->lookup_symbol(objc, "_sel_registerName");
    objc_class = (id (*)(const char *))info->lookup_symbol(objc, "_objc_getClass");
    // AppKit's provider, for the windows and events Carbon's are.
    info->lookup_symbol(APPKIT, "_NSApplicationMain");
}

void *carbon_function(const char *library, const char *name) {
    return carbon_lookup ? carbon_lookup(library, name) : NULL;
}

void carbon_warn(const char *format, ...) {
    char line[1024];
    va_list arguments;
    va_start(arguments, format);
    vsnprintf(line, sizeof line, format, arguments);
    va_end(arguments);
    fprintf(stderr, "perry: Carbon: %s\n", line);
}

bool carbon_trace_enabled(void) {
    static int enabled = -1;
    if (enabled < 0) enabled = getenv("PERRY_CARBON_TRACE") != NULL;
    return enabled;
}

id carbon_application(void) {
    static id application;
    if (!application) {
        application = SEND(CLASS("NSApplication"), "sharedApplication");
        SEND(application, "finishLaunching");
    }
    return application;
}

id carbon_string(const char *utf8) {
    return ((id (*)(id, SEL, const char *))objc_send)(CLASS("NSString"), SELECTOR("stringWithUTF8String:"), utf8 ? utf8 : "");
}

double carbon_now(void) {
    struct timespec now;
    clock_gettime(CLOCK_MONOTONIC, &now);
    return (double)now.tv_sec + (double)now.tv_nsec / 1e9;
}

// MARK: - Script Manager

// One script, Roman, with English and the United States' conventions.
enum {
    smScriptEnabled = 4, smScriptRight = 6, smScriptSysFond = 12, smScriptAppFond = 14,
    smScriptNumber = 16, smScriptDate = 18, smScriptEncoding = 26, smScriptLang = 28,
    smScriptMonoFondSize = 78, smScriptPrefFondSize = 80, smScriptSmallFondSize = 82,
    smScriptSysFondSize = 84, smScriptAppFondSize = 86, smScriptHelpFondSize = 88,
};

long carbon_GetScriptVariable(int16_t script, int16_t selector) CARBON_SYMBOL(GetScriptVariable);
long carbon_GetScriptVariable(int16_t script, int16_t selector) {
    if (script != 0) return 0;
    switch (selector) {
    case smScriptEnabled: return -1;
    case smScriptSysFond: return 0;        // the system font
    case smScriptAppFond: return 1;        // the application font
    case smScriptSysFondSize: case smScriptAppFondSize: return 12;
    case smScriptMonoFondSize: case smScriptPrefFondSize: return 0x0016000c;  // Monaco 12
    case smScriptSmallFondSize: case smScriptHelpFondSize: return 9;
    default: return 0;                    // left to right, langEnglish, MacRoman
    }
}

enum { smVersion = 0, smEnabled = 2, smSysScript = 18, smKeyScript = 22, smRegionCode = 40, smKeyCache = 64 };

long carbon_GetScriptManagerVariable(int16_t selector) CARBON_SYMBOL(GetScriptManagerVariable);
long carbon_GetScriptManagerVariable(int16_t selector) {
    switch (selector) {
    case smVersion: return 0x0710;
    case smEnabled: return 1;
    default: return 0;                    // smRoman, verUS
    }
}

int16_t carbon_IntlScript(void) CARBON_SYMBOL(IntlScript);
int16_t carbon_IntlScript(void) { return 0; }

// MARK: - Dates and times

// Seconds since the start of 1904, in local time, as the Mac's clock counts.
static uint32_t mac_seconds(time_t unix_time) {
    struct tm local;
    localtime_r(&unix_time, &local);
    return (uint32_t)((int64_t)unix_time + local.tm_gmtoff + 2082844800LL);
}

void carbon_GetDateTime(uint32_t *seconds) CARBON_SYMBOL(GetDateTime);
void carbon_GetDateTime(uint32_t *seconds) {
    if (seconds) *seconds = mac_seconds(time(NULL));
}

static void date_from(int64_t mac, DateTimeRec *date) {
    time_t unix_time = (time_t)(mac - 2082844800LL);
    struct tm parts;
    gmtime_r(&unix_time, &parts);
    date->year = (int16_t)(parts.tm_year + 1900);
    date->month = (int16_t)(parts.tm_mon + 1);
    date->day = (int16_t)parts.tm_mday;
    date->hour = (int16_t)parts.tm_hour;
    date->minute = (int16_t)parts.tm_min;
    date->second = (int16_t)parts.tm_sec;
    date->dayOfWeek = (int16_t)(parts.tm_wday + 1);
}

void carbon_SecondsToDate(uint32_t seconds, DateTimeRec *date) CARBON_SYMBOL(SecondsToDate);
void carbon_SecondsToDate(uint32_t seconds, DateTimeRec *date) {
    if (date) date_from(seconds, date);
}

#pragma pack(push, 2)
typedef struct {
    int16_t era, year, month, day, hour, minute, second, dayOfWeek, dayOfYear, weekOfYear, pm, res1, res2, res3;
} LongDateRec;
#pragma pack(pop)

void carbon_LongSecondsToDate(const int64_t *seconds, LongDateRec *date) CARBON_SYMBOL(LongSecondsToDate);
void carbon_LongSecondsToDate(const int64_t *seconds, LongDateRec *date) {
    if (!seconds || !date) return;
    memset(date, 0, sizeof *date);
    time_t unix_time = (time_t)(*seconds - 2082844800LL);
    struct tm parts;
    gmtime_r(&unix_time, &parts);
    date->year = (int16_t)(parts.tm_year + 1900);
    date->month = (int16_t)(parts.tm_mon + 1);
    date->day = (int16_t)parts.tm_mday;
    date->hour = (int16_t)parts.tm_hour;
    date->minute = (int16_t)parts.tm_min;
    date->second = (int16_t)parts.tm_sec;
    date->dayOfWeek = (int16_t)(parts.tm_wday + 1);
    date->dayOfYear = (int16_t)(parts.tm_yday + 1);
    date->weekOfYear = (int16_t)(parts.tm_yday / 7 + 1);
    date->pm = parts.tm_hour >= 12;
}

#pragma pack(push, 2)
typedef struct { uint16_t highSeconds; uint32_t lowSeconds; uint16_t fraction; } UTCDateTime;
typedef struct { uint16_t highSeconds; uint32_t lowSeconds; uint16_t fraction; } LocalDateTime;
#pragma pack(pop)

OSStatus carbon_ConvertUTCToLocalTime(const UTCDateTime *utc, LocalDateTime *local) CARBON_SYMBOL(ConvertUTCToLocalTime);
OSStatus carbon_ConvertUTCToLocalTime(const UTCDateTime *utc, LocalDateTime *local) {
    if (!utc || !local) return paramErr;
    int64_t seconds = ((int64_t)utc->highSeconds << 32) | utc->lowSeconds;
    time_t unix_time = (time_t)(seconds - 2082844800LL);
    struct tm parts;
    localtime_r(&unix_time, &parts);
    seconds += parts.tm_gmtoff;
    local->highSeconds = (uint16_t)(seconds >> 32);
    local->lowSeconds = (uint32_t)seconds;
    local->fraction = utc->fraction;
    return noErr;
}

/// Ticks, sixtieths of a second, since the system started.
uint32_t carbon_TickCount(void) CARBON_SYMBOL(TickCount);
uint32_t carbon_TickCount(void) { return (uint32_t)(carbon_now() * 60.0); }

void carbon_Microseconds(UnsignedWide *microseconds) CARBON_SYMBOL(Microseconds);
void carbon_Microseconds(UnsignedWide *microseconds) {
    uint64_t now = (uint64_t)(carbon_now() * 1e6);
    microseconds->hi = (int32_t)(now >> 32);
    microseconds->lo = (int32_t)(uint32_t)now;
}

// Durations: positive milliseconds, negative microseconds. AbsoluteTime
// counts nanoseconds here, as mach_absolute_time does.
static int64_t duration_nanoseconds(int32_t duration) {
    return duration >= 0 ? (int64_t)duration * 1000000 : -(int64_t)duration * 1000;
}

uint64_t carbon_DurationToAbsolute(int32_t duration) CARBON_SYMBOL(DurationToAbsolute);
uint64_t carbon_DurationToAbsolute(int32_t duration) { return (uint64_t)duration_nanoseconds(duration); }

uint64_t carbon_AddDurationToAbsolute(int32_t duration, uint64_t absolute) CARBON_SYMBOL(AddDurationToAbsolute);
uint64_t carbon_AddDurationToAbsolute(int32_t duration, uint64_t absolute) {
    return absolute + (uint64_t)duration_nanoseconds(duration);
}

// MARK: - Atomic operations

Boolean carbon_CompareAndSwap(uint32_t old, uint32_t new, uint32_t *address) CARBON_SYMBOL(CompareAndSwap);
Boolean carbon_CompareAndSwap(uint32_t old, uint32_t new, uint32_t *address) {
    return __atomic_compare_exchange_n(address, &old, new, false, __ATOMIC_SEQ_CST, __ATOMIC_SEQ_CST);
}

/// The value before.
int32_t carbon_IncrementAtomic(int32_t *value) CARBON_SYMBOL(IncrementAtomic);
int32_t carbon_IncrementAtomic(int32_t *value) { return __atomic_fetch_add(value, 1, __ATOMIC_SEQ_CST); }

int32_t carbon_DecrementAtomic(int32_t *value) CARBON_SYMBOL(DecrementAtomic);
int32_t carbon_DecrementAtomic(int32_t *value) { return __atomic_fetch_sub(value, 1, __ATOMIC_SEQ_CST); }

// MARK: - Multiprocessing Services

void *carbon_MPAllocateAligned(size_t size, uint8_t alignment, uint32_t options) CARBON_SYMBOL(MPAllocateAligned);
void *carbon_MPAllocateAligned(size_t size, uint8_t alignment, uint32_t options) {
    size_t bytes = (size_t)1 << (alignment < 4 ? 4 : alignment);
    void *memory = NULL;
    if (posix_memalign(&memory, bytes, size ? size : 1) != 0) return NULL;
    if (options & 0x4) memset(memory, 0, size);   // kMPAllocateClearMask
    return memory;
}

void carbon_MPFree(void *memory) CARBON_SYMBOL(MPFree);
void carbon_MPFree(void *memory) { free(memory); }

void *carbon_MPCurrentTaskID(void) CARBON_SYMBOL(MPCurrentTaskID);
void *carbon_MPCurrentTaskID(void) {
    static _Thread_local char task;
    return &task;
}

void carbon_MPYield(void) CARBON_SYMBOL(MPYield);
void carbon_MPYield(void) { sched_yield(); }

/// Waits until an AbsoluteTime, nanoseconds of the monotonic clock.
OSStatus carbon_MPDelayUntil(const uint64_t *deadline) CARBON_SYMBOL(MPDelayUntil);
OSStatus carbon_MPDelayUntil(const uint64_t *deadline) {
    if (!deadline) return paramErr;
    struct timespec until = { (time_t)(*deadline / 1000000000u), (long)(*deadline % 1000000000u) };
    while (clock_nanosleep(CLOCK_MONOTONIC, TIMER_ABSTIME, &until, NULL) != 0) {}
    return noErr;
}

// MARK: - Strings

void carbon_c2pstrcpy(unsigned char *pascal, const char *c) CARBON_SYMBOL(c2pstrcpy);
void carbon_c2pstrcpy(unsigned char *pascal, const char *c) {
    size_t length = strlen(c);
    if (length > 255) length = 255;
    memmove(pascal + 1, c, length);
    pascal[0] = (unsigned char)length;
}

void carbon_p2cstrcpy(char *c, const unsigned char *pascal) CARBON_SYMBOL(p2cstrcpy);
void carbon_p2cstrcpy(char *c, const unsigned char *pascal) {
    size_t length = pascal[0];
    memmove(c, pascal + 1, length);
    c[length] = 0;
}

/// 0 when equal, ignoring case, as the Roman script compares.
int16_t carbon_IdenticalString(ConstStr255Param a, ConstStr255Param b, void *table) CARBON_SYMBOL(IdenticalString);
int16_t carbon_IdenticalString(ConstStr255Param a, ConstStr255Param b, void *table) {
    (void)table;
    if (a[0] != b[0]) return 1;
    for (int index = 1; index <= a[0]; index++)
        if (tolower(a[index]) != tolower(b[index])) return 1;
    return 0;
}

/// A 16.16 fixed-point number rounded to an integer.
int32_t carbon_Fix2Long(int32_t value) CARBON_SYMBOL(Fix2Long);
int32_t carbon_Fix2Long(int32_t value) { return (value + 0x8000) >> 16; }

// MARK: - UPPs

// A universal procedure pointer is the procedure itself.
#define UPP(name) \
    void *carbon_New##name##UPP(void *procedure) CARBON_SYMBOL(New##name##UPP); \
    void *carbon_New##name##UPP(void *procedure) { return procedure; } \
    void carbon_Dispose##name##UPP(void *procedure) CARBON_SYMBOL(Dispose##name##UPP); \
    void carbon_Dispose##name##UPP(void *procedure) { (void)procedure; }

UPP(EventHandler)
UPP(EventLoopTimer)
UPP(AEEventHandler)
UPP(SndCallBack)
UPP(DMDisplayModeListIterator)
UPP(EventComparator)
UPP(ControlAction)
UPP(ModalFilter)
UPP(NavEvent)
UPP(MovieProgress)

// MARK: - Cursor and menu bar

static int cursor_hidden;

void carbon_InitCursor(void) CARBON_SYMBOL(InitCursor);
void carbon_InitCursor(void) {
    SEND(SEND(CLASS("NSCursor"), "arrowCursor"), "set");
    while (cursor_hidden > 0) {
        SEND(CLASS("NSCursor"), "unhide");
        cursor_hidden--;
    }
}

void carbon_HideCursor(void) CARBON_SYMBOL(HideCursor);
void carbon_HideCursor(void) {
    if (cursor_hidden++ == 0) SEND(CLASS("NSCursor"), "hide");
}

void carbon_ShowCursor(void) CARBON_SYMBOL(ShowCursor);
void carbon_ShowCursor(void) {
    if (cursor_hidden > 0 && --cursor_hidden == 0) SEND(CLASS("NSCursor"), "unhide");
}

// Cursors from 'CURS' resources are the arrow; the watch (4) too.
void *carbon_GetCursor(int16_t identifier) CARBON_SYMBOL(GetCursor);
void *carbon_GetCursor(int16_t identifier) {
    static void *cursor = &cursor;
    (void)identifier;
    return &cursor;
}

void carbon_SetCursor(const void *cursor) CARBON_SYMBOL(SetCursor);
void carbon_SetCursor(const void *cursor) {
    (void)cursor;
    SEND(SEND(CLASS("NSCursor"), "arrowCursor"), "set");
}

static uint32_t ui_mode, ui_options;

void carbon_HideMenuBar(void) CARBON_SYMBOL(HideMenuBar);
void carbon_HideMenuBar(void) { ui_mode = 3; }  // kUIModeAllHidden

void carbon_ShowMenuBar(void) CARBON_SYMBOL(ShowMenuBar);
void carbon_ShowMenuBar(void) { ui_mode = 0; }

bool ui_menu_bar_visible(void) { return ui_mode == 0; }

void carbon_GetSystemUIMode(uint32_t *mode, uint32_t *options) CARBON_SYMBOL(GetSystemUIMode);
void carbon_GetSystemUIMode(uint32_t *mode, uint32_t *options) {
    if (mode) *mode = ui_mode;
    if (options) *options = ui_options;
}

void carbon_SysBeep(int16_t duration) CARBON_SYMBOL(SysBeep);
void carbon_SysBeep(int16_t duration) {
    (void)duration;
    void (*beep)(void) = (void (*)(void))carbon_function(APPKIT, "_NSBeep");
    if (beep) beep();
}

// MARK: - QuickDraw globals

static uint32_t random_seed = 1;

void carbon_SetQDGlobalsRandomSeed(int32_t seed) CARBON_SYMBOL(SetQDGlobalsRandomSeed);
void carbon_SetQDGlobalsRandomSeed(int32_t seed) { random_seed = (uint32_t)seed; }

int16_t carbon_Random(void) CARBON_SYMBOL(Random);
int16_t carbon_Random(void) {
    // QuickDraw's: the Park-Miller generator.
    random_seed = (uint32_t)(((uint64_t)random_seed * 16807u) % 0x7fffffffu);
    int16_t value = (int16_t)(random_seed & 0xffff);
    return value == -32768 ? 0 : value;
}

// The five patterns, eight rows of bits each.
#define PATTERN(name, a, b) \
    const uint8_t *carbon_GetQDGlobals##name(uint8_t *pattern) CARBON_SYMBOL(GetQDGlobals##name); \
    const uint8_t *carbon_GetQDGlobals##name(uint8_t *pattern) { \
        for (int row = 0; row < 8; row++) pattern[row] = row & 1 ? (b) : (a); \
        return pattern; \
    }

PATTERN(Black, 0xff, 0xff)
PATTERN(White, 0x00, 0x00)
PATTERN(Gray, 0xaa, 0x55)
PATTERN(LightGray, 0x88, 0x22)
PATTERN(DarkGray, 0x77, 0xdd)

// MARK: - Machine

/// The computer's name, as the Sharing preferences give it: the host name.
void *carbon_CSCopyMachineName(void) CARBON_SYMBOL(CSCopyMachineName);
void *carbon_CSCopyMachineName(void) {
    char name[256] = "";
    gethostname(name, sizeof name - 1);
    char *dot = strchr(name, '.');
    if (dot) *dot = 0;
    return SEND(carbon_string(name), "retain");
}

// MARK: - Gestalt

#define QUICKTIME "/System/Library/Frameworks/QuickTime.framework/Versions/A/QuickTime"

/// What the libraries Carbon apps check for answer, as they register their
/// selectors on a Mac: QuickTime's version when QuickTime's provider is
/// there. The rest are CoreServices' answers (the system's version).
OSErr carbon_Gestalt(OSType selector, int32_t *response) CARBON_SYMBOL(Gestalt);
OSErr carbon_Gestalt(OSType selector, int32_t *response) {
    if (!response) return paramErr;
    switch (selector) {
    case 0x7174696d:   // 'qtim': QuickTime 7.6.4
        if (!carbon_function(QUICKTIME, "_EnterMovies")) return -5551;
        *response = 0x07648000;
        return noErr;
    case 0x71746673:   // 'qtfs': QuickTime's features, with the movie toolbox and image codecs
        if (!carbon_function(QUICKTIME, "_EnterMovies")) return -5551;
        *response = 0x3f;
        return noErr;
    case 0x72616d20: {  // 'ram ': the physical memory, in bytes (at most 2 GB, which an SInt32 holds)
        long pages = sysconf(_SC_PHYS_PAGES), size = sysconf(_SC_PAGESIZE);
        int64_t bytes = (int64_t)pages * size;
        *response = bytes > 0x7fffffff ? 0x7fffffff : (int32_t)bytes;
        return noErr;
    }
    case 0x6c72616d:   // 'lram': the logical memory, the same
        return carbon_Gestalt(0x72616d20, response);
    case 0x73797361:   // 'sysa': the architecture, Intel's (gestaltIntel)
        *response = 10;
        return noErr;
    default: break;
    }
    OSErr (*services)(OSType, int32_t *) = (OSErr (*)(OSType, int32_t *))carbon_function(CORESERVICES, "_Gestalt");
    return services ? services(selector, response) : -5551;
}
