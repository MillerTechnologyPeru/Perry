#ifndef PERRY_CARBON_H
#define PERRY_CARBON_H

// libPerryCarbon: the provider for Carbon.framework (HIToolbox, QuickDraw
// and the rest of what Carbon apps link), for Mac apps built before Cocoa
// took over. Windows are AppKit's NSWindows and events AppKit's NSEvents,
// reached through the Objective-C runtime; QuickDraw's ports and offscreen
// worlds are memory of its own. What it lacks, CoreServices',
// ApplicationServices' and AppKit's providers have: Carbon re-exports them.

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#define CARBON_SYMBOL(name) __asm__("_" #name) __attribute__((visibility("default"), used))

typedef int32_t OSStatus;
typedef int16_t OSErr;
typedef uint32_t OSType;
typedef unsigned char Boolean;
typedef unsigned char Str255[256];
typedef const unsigned char *ConstStr255Param;
typedef char **Handle;
typedef void *id;
typedef void *SEL;

enum {
    noErr = 0,
    paramErr = -50,
    memFullErr = -108,
    nilHandleErr = -109,
    resNotFound = -192,
    eventNotHandledErr = -9874,
    eventLoopTimedOutErr = -9875,
    eventLoopQuitErr = -9876,
    eventParameterNotFoundErr = -9870,
    errUnknownWindowClass = -5600,
    errInvalidWindowRef = -5603,
    unimpErr = -4,
};

// Darwin's i386 Carbon structures are laid out as on the 68000: two-byte
// alignment at most.
#pragma pack(push, 2)

typedef struct { int16_t v, h; } Point;
typedef struct { int16_t top, left, bottom, right; } Rect;
typedef struct { uint16_t red, green, blue; } RGBColor;
typedef struct { int16_t value; RGBColor rgb; } ColorSpec;
typedef struct {
    int32_t ctSeed;
    int16_t ctFlags;
    int16_t ctSize;
    ColorSpec ctTable[1];
} ColorTable, *CTabPtr, **CTabHandle;

typedef struct {
    void *baseAddr;
    int16_t rowBytes;
    Rect bounds;
    int16_t pmVersion;
    int16_t packType;
    int32_t packSize;
    int32_t hRes;
    int32_t vRes;
    int16_t pixelType;
    int16_t pixelSize;
    int16_t cmpCount;
    int16_t cmpSize;
    OSType pixelFormat;
    CTabHandle pmTable;
    void *pmExt;
} PixMap, *PixMapPtr, **PixMapHandle;

typedef struct {
    void *baseAddr;
    int16_t rowBytes;
    Rect bounds;
} BitMap;

typedef struct {
    int16_t gdRefNum;
    int16_t gdID;
    int16_t gdType;
    void *gdITable;
    int16_t gdResPref;
    void *gdSearchProc;
    void *gdCompProc;
    int16_t gdFlags;
    PixMapHandle gdPMap;
    int32_t gdRefCon;
    void *gdNextGD;
    Rect gdRect;
    int32_t gdMode;
    int16_t gdCCBytes;
    int16_t gdCCDepth;
    Handle gdCCXData;
    Handle gdCCXMask;
    Handle gdExt;
} GDevice, *GDPtr, **GDHandle;

typedef struct {
    int16_t what;
    uint32_t message;
    uint32_t when;
    Point where;
    uint16_t modifiers;
} EventRecord;

typedef struct {
    int16_t ascent, descent, widMax, leading;
} FontInfo;

typedef struct {
    int16_t year, month, day, hour, minute, second, dayOfWeek;
} DateTimeRec;

typedef struct {
    Point pnLoc;
    Point pnSize;
    int16_t pnMode;
    uint8_t pnPat[8];
} PenState;

typedef struct {
    int32_t lo;
    int32_t hi;
} UnsignedWide;

#pragma pack(pop)

// AppKit's geometry: CGFloat is a float on 32-bit Darwin.
#if defined(__LP64__)
typedef double CGFloat;
#else
typedef float CGFloat;
#endif
typedef struct { CGFloat x, y; } NSPoint;
typedef struct { CGFloat width, height; } NSSize;
typedef struct { NSPoint origin; NSSize size; } NSRect;

// MARK: - Regions

// A region is a rectangle here, or empty: what Carbon apps ask of them
// (clips, update areas, window structures) needs nothing more.
typedef struct carbon_region {
    Rect bounds;
} carbon_region, **RgnHandle;

RgnHandle carbon_region_new(const Rect *bounds);

// MARK: - Ports

// A port, a window's or an offscreen world's: QuickDraw draws into its
// pixels, a window's is shown in its content view.
typedef struct carbon_port {
    uint32_t magic;
    struct carbon_window *window;
    PixMapHandle pixmap;
    Rect portRect;
    RGBColor foreground, background;
    Point pen;
    RgnHandle clip, visible;
    int16_t textFont, textSize, textFace, textMode;
    GDHandle device;
    bool ownsPixels;
} carbon_port, *CGrafPtr;

#define CARBON_PORT_MAGIC 0x50525450u   // 'PRTP'

CGrafPtr carbon_port_new(int width, int height, int depth, void *pixels, long rowBytes);
void carbon_port_resize(CGrafPtr port, int width, int height);
void carbon_port_free(CGrafPtr port);
CGrafPtr carbon_current_port(void);
GDHandle carbon_main_device(void);
/// Shows what QuickDraw drew into a window's port in its content view.
void carbon_port_flush(CGrafPtr port);

// MARK: - Windows

typedef struct carbon_window {
    uint32_t magic;
    id nswindow;
    id view;
    carbon_port *port;
    /// The content's, in global coordinates.
    Rect bounds;
    uint32_t windowClass;
    uint32_t attributes;
    int16_t kind;
    long refCon;
    bool visible;
    struct carbon_window_group *group;
    struct carbon_target *target;
    struct carbon_window *next;
} carbon_window, *WindowRef;

#define CARBON_WINDOW_MAGIC 0x57494e44u   // 'WIND'

WindowRef carbon_window_from(void *pointer);
WindowRef carbon_window_for_nswindow(id nswindow);
WindowRef carbon_front_window(void);

OSStatus carbon_CreateNewWindow(uint32_t windowClass, uint32_t attributes, const Rect *bounds, WindowRef *out)
    CARBON_SYMBOL(CreateNewWindow);
OSStatus carbon_SetWindowTitleWithCFString(WindowRef window, id title) CARBON_SYMBOL(SetWindowTitleWithCFString);
OSStatus carbon_RepositionWindow(WindowRef window, WindowRef parent, uint32_t method) CARBON_SYMBOL(RepositionWindow);
void carbon_OffsetRect(Rect *rect, int16_t dh, int16_t dv) CARBON_SYMBOL(OffsetRect);
void carbon_SetPort(CGrafPtr port) CARBON_SYMBOL(SetPort);
void carbon_GlobalToLocal(Point *point) CARBON_SYMBOL(GlobalToLocal);
void carbon_LocalToGlobal(Point *point) CARBON_SYMBOL(LocalToGlobal);
void carbon_ShowWindow(WindowRef window) CARBON_SYMBOL(ShowWindow);
bool ui_menu_bar_visible(void);

// MARK: - Controls

typedef struct carbon_control carbon_control, *ControlRef;

/// What AppKit's buttons and menu items do when chosen: their command to
/// the window's target, or the focus's.
void carbon_action_register(id sender, uint32_t command, WindowRef window, void *menu, uint16_t item);
id carbon_action_target(void);
/// The window's root control, made the first time it's asked for.
ControlRef carbon_root_control(WindowRef window);
/// A control over a view of AppKit's, in the window's content, at bounds
/// in the window's coordinates.
ControlRef carbon_control_new(WindowRef window, ControlRef parent, id view, const Rect *bounds, OSType kind);
void carbon_control_set_id(ControlRef control, OSType signature, int32_t identifier);
NSRect carbon_view_frame(WindowRef window, const Rect *bounds);
/// A label's view, and a push button's that sends its command.
id carbon_label_view(id text, bool small);
id carbon_button_view(id title, uint32_t command, WindowRef window, int type);

// MARK: - Menus

typedef struct carbon_menu *MenuRef;
MenuRef carbon_menu_new(int16_t identifier, id title);
/// An item, or a separator for no title: its NSMenuItem.
id carbon_menu_add(MenuRef menu, id title, uint32_t command, const char *key, uint32_t modifiers);
void carbon_menu_set_submenu(MenuRef menu, id item, MenuRef submenu);
void carbon_menu_bar_set(MenuRef bar);

// MARK: - Event targets

typedef struct carbon_target carbon_target;
carbon_target *carbon_application_target(void);
carbon_target *carbon_target_new(void *owner);
void carbon_target_free(carbon_target *target);

/// Sends a command (a menu item's, a control's) to a target: the user
/// focus's when NULL.
OSStatus carbon_process_command(uint32_t command, void *menu, uint16_t item, carbon_target *target);

/// The application is asked to quit (Quit in its menu).
OSStatus carbon_quit_requested(void);

// MARK: - Apple events

/// Sends the application its 'oapp' event, once, as it starts its loop.
void carbon_apple_event_open(void);
/// Sends it 'quit': false if it has no handler for it.
bool carbon_apple_event_quit(void);

// MARK: - The runtime

extern id (*objc_send)(id, SEL, ...);
extern SEL (*objc_selector)(const char *);
extern id (*objc_class)(const char *);
extern void *(*carbon_lookup)(const char *library, const char *name);

#define SELECTOR(name) ({ static SEL selector_; if (!selector_) selector_ = objc_selector(name); selector_; })
#define CLASS(name) ({ static id class_; if (!class_) class_ = objc_class(name); class_; })
#define SEND(object, name) objc_send((id)(object), SELECTOR(name))
/// A message with one object argument (a sender, nil for none).
#define SEND1(object, name, argument) ((id (*)(id, SEL, id))objc_send)((id)(object), SELECTOR(name), (id)(argument))

/// A function of another library: CoreFoundation's, AppKit's.
void *carbon_function(const char *library, const char *name);
#define COREFOUNDATION "/System/Library/Frameworks/CoreFoundation.framework/CoreFoundation"
#define APPKIT "/System/Library/Frameworks/AppKit.framework/Versions/C/AppKit"
#define CORESERVICES "/System/Library/Frameworks/CoreServices.framework/CoreServices"

/// The application, made and launched the first time it's needed.
id carbon_application(void);
/// A UTF-8 string as an autoreleased NSString.
id carbon_string(const char *utf8);
double carbon_now(void);

void carbon_warn(const char *format, ...) __attribute__((format(printf, 1, 2)));
bool carbon_trace_enabled(void);
#define CARBON_TRACE(...) do { if (carbon_trace_enabled()) carbon_warn(__VA_ARGS__); } while (0)

#endif
