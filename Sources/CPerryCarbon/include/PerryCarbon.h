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

// A 64-bit number's words in the processor's order: the low word first on
// i386, the high word first on ppc.
typedef struct {
#if defined(__BIG_ENDIAN__) || defined(__powerpc__)
    int32_t hi;
    int32_t lo;
#else
    int32_t lo;
    int32_t hi;
#endif
} UnsignedWide;

// MARK: File Manager

typedef struct {
    int16_t vRefNum;
    int32_t parID;
    unsigned char name[64];
} FSSpec;

typedef struct {
    uint16_t length;
    uint16_t unicode[255];
} HFSUniStr255;

/// CoreServices' own: an FSRef names a path in its table.
typedef struct { uint8_t hidden[80]; } FSRef;

/// Where FSIterateForks is in an item's forks: initialize is 0 before the
/// first call.
typedef struct {
    int32_t initialize;
    int16_t priv[6];
} CatPositionRec;

/// The original File Manager's read and write parameter block.
typedef struct io_block {
    struct io_block *qLink;
    int16_t qType, ioTrap;
    void *ioCmdAddr;
    void (*ioCompletion)(struct io_block *);
    volatile int16_t ioResult;
    unsigned char *ioNamePtr;
    int16_t ioVRefNum, ioRefNum;
    int8_t ioVersNum, ioPermssn;
    void *ioMisc, *ioBuffer;
    int32_t ioReqCount, ioActCount;
    int16_t ioPosMode;
    int32_t ioPosOffset;
} IOParam;

/// The header every other parameter block starts with: qLink, qType,
/// ioTrap, ioCmdAddr, ioCompletion, ioResult, ioNamePtr, ioVRefNum.
typedef struct {
    void *qLink;
    int16_t qType;
    int16_t ioTrap;
    void *ioCmdAddr;
    void *ioCompletion;
    OSErr ioResult;
    unsigned char *ioNamePtr;
    int16_t ioVRefNum;
} ParamHeader;

/// A file's or folder's catalog information: a file's Finder info, then
/// its ID and its forks' sizes; a folder's the same 16 bytes of Finder
/// info, its ID and its count of items.
typedef struct {
    ParamHeader header;
    int16_t ioFRefNum;
    int8_t ioFVersNum;
    int8_t filler1;
    int16_t ioFDirIndex;
    int8_t ioFlAttrib;
    int8_t ioACUser;
    uint8_t ioFlFndrInfo[16];
    int32_t ioDirID;            // ioDrDirID for a folder
    uint16_t ioFlStBlk;         // ioDrNmFls for a folder
    int32_t ioFlLgLen;
    int32_t ioFlPyLen;
    uint16_t ioFlRStBlk;
    int32_t ioFlRLgLen;
    int32_t ioFlRPyLen;
    uint32_t ioFlCrDat;
    uint32_t ioFlMdDat;
    uint32_t ioFlBkDat;
    uint8_t ioFlXFndrInfo[16];
    int32_t ioFlParID;          // ioDrParID for a folder
    int32_t ioFlClpSiz;
} CInfoPB;

typedef struct {
    ParamHeader header;
    int32_t filler1;
    int16_t ioVolIndex;
    uint32_t ioVCrDate;
    uint32_t ioVLsMod;
    int16_t ioVAtrb;
    uint16_t ioVNmFls;
    uint16_t ioVBitMap;
    uint16_t ioAllocPtr;
    uint16_t ioVNmAlBlks;
    uint32_t ioVAlBlkSiz;
    uint32_t ioVClpSiz;
    uint16_t ioAlBlSt;
    uint32_t ioVNxtCNID;
    uint16_t ioVFrBlk;
    uint16_t ioVSigWord;
    int16_t ioVDrvInfo;
    int16_t ioVDRefNum;
    int16_t ioVFSID;
    uint32_t ioVBkUp;
    int16_t ioVSeqNum;
    uint32_t ioVWrCnt;
    uint32_t ioVFilCnt;
    uint32_t ioVDirCnt;
    int32_t ioVFndrInfo[8];
} HVolumeParam;

typedef struct {
    ParamHeader header;
    int16_t ioRefNum;
    int8_t ioVersNum;
    int8_t ioPermssn;
    void *ioMisc;
    void *ioBuffer;
    int32_t ioReqCount;
    int32_t ioActCount;
} HIOParam;

typedef struct {
    ParamHeader header;
    int16_t ioDTRefNum;
    int16_t ioIndex;
    int32_t ioTagInfo;
    void *ioDTBuffer;
    int32_t ioDTReqCount;
    int32_t ioDTActCount;
    int8_t ioFiller1;
    uint8_t ioIconType;
    int16_t ioFiller2;
    int32_t ioDirID;
    OSType ioFileCreator;
    OSType ioFileType;
    int32_t ioFiller3;
    int32_t ioDTLgLen;
    int32_t ioDTPyLen;
    int16_t ioFiller4[14];
    int32_t ioAPPLParID;
} DTPB;

/// A working directory's parameters, for PBHSetVol and PBHGetVol.
typedef struct {
    ParamHeader header;
    int16_t filler1;
    int16_t ioWDIndex;
    int32_t ioWDProcID;
    int16_t ioWDVRefNum;
    int16_t filler2[7];
    int32_t reserved1;
    int32_t ioWDDirID;
    int32_t reserved2;
} WDPBRec;

/// A shared folder's access rights: AccessParam's fields after the header.
typedef struct {
    ParamHeader header;
    int16_t ioRefNum;
    int16_t ioDenyModes;
    int8_t filler4;
    int8_t ioACUser;
    int32_t filler5;
    int32_t ioACOwnerID;
    int32_t ioACGroupID;
    int32_t ioACAccess;
    int32_t ioDirID;
} AccessParam;

/// The volume's parameters, version 4's GetVolParmsInfoBuffer.
typedef struct {
    int16_t vMVersion;
    int32_t vMAttrib;
    void *vMLocalHand;
    int32_t vMServerAdr;
    int32_t vMVolumeGrade;
    int16_t vMForeignPrivID;
    int32_t vMExtendedAttributes;
    void *vMDeviceID;
    uint32_t vMMaxNameLength;
} GetVolParmsInfoBuffer;

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
void carbon_menu_set_plain(MenuRef menu);
id carbon_menu_object(MenuRef menu);
id carbon_pascal_string(const unsigned char *text);
ControlRef carbon_popup_control(WindowRef window, const Rect *bounds, MenuRef menu, int32_t value, uint32_t command, id title);
void carbon_label_fit(id field, const Rect *bounds, bool small);
ControlRef carbon_checkbox_control(WindowRef window, const Rect *bounds, id title, int32_t value, uint32_t command, bool small);
ControlRef carbon_radio_group_control(WindowRef window, const Rect *bounds, id *titles, int count, int rows, int spacing,
                                      int32_t value, uint32_t command, bool small);
ControlRef carbon_group_box_control(WindowRef window, const Rect *bounds, id title, bool small);
ControlRef carbon_edit_text_control(WindowRef window, const Rect *bounds, id text, bool small);
void carbon_menu_bar_set(MenuRef bar);

// MARK: - Event targets

typedef struct carbon_target carbon_target;
carbon_target *carbon_application_target(void);
carbon_target *carbon_target_new(void *owner);
void carbon_target_free(carbon_target *target);

/// Sends a command (a menu item's, a control's) to a target: the user
/// focus's when NULL.
OSStatus carbon_process_command(uint32_t command, void *control, void *menu, uint16_t item, carbon_target *target);

/// Whether the command is a Dialog Manager dialog's button's, which ends
/// that dialog's ModalDialog with the button's item.
bool carbon_dialog_command(uint32_t command);

/// The application is asked to quit (Quit in its menu).
OSStatus carbon_quit_requested(void);

// MARK: - Places

/// The main bundle's folder and its executable's path, NULL if there is no
/// bundle: programs find their data beside them.
const char *carbon_bundle_path(void);
const char *carbon_executable_path(void);
/// The disc mounted at `index` (from 0): its name and mount point. Returns
/// the count of discs mounted, so a disc is there if `index` is below it.
int carbon_disc_volume(int index, char *name, size_t name_size, char *mount, size_t mount_size);
/// Where the startup volume's space is counted: the home's file system.
const char *carbon_startup_volume_path(void);

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
