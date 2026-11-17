// The Window Manager: a Carbon window is an NSWindow whose content view
// its port's pixels are shown in, and which AGL draws into. Bounds are
// Carbon's, global coordinates from the top left of the main screen; AppKit's
// are from the bottom left. Window groups keep a level for their windows.

#include "PerryCarbon.h"

#include <stdlib.h>
#include <string.h>


static carbon_window *windows;

WindowRef carbon_window_from(void *pointer) {
    WindowRef window = pointer;
    return window && window->magic == CARBON_WINDOW_MAGIC ? window : NULL;
}

WindowRef carbon_window_for_nswindow(id nswindow) {
    for (carbon_window *window = windows; window; window = window->next)
        if (window->nswindow == nswindow) return window;
    return NULL;
}

static CGFloat screen_height(void) {
    GDHandle device = carbon_main_device();
    return (CGFloat)(*device)->gdRect.bottom;
}

/// The titled classes have a title bar of 22 points above the content.
static bool titled(uint32_t windowClass, uint32_t attributes) {
    if (attributes & (1u << 9)) return false;   // kWindowNoTitleBarAttribute
    switch (windowClass) {
    case 2: case 4: case 5: case 6: case 8: return true;   // movable alert and modal, floating, document, utility
    default: return false;
    }
}

static NSRect ns_content(const Rect *bounds) {
    return (NSRect){{bounds->left, screen_height() - bounds->bottom},
                    {bounds->right - bounds->left, bounds->bottom - bounds->top}};
}

static void place(WindowRef window, const Rect *bounds) {
    NSRect content = ns_content(bounds);
    ((void (*)(id, SEL, NSSize))objc_send)(window->nswindow, SELECTOR("setContentSize:"), content.size);
    CGFloat title = titled(window->windowClass, window->attributes) ? 22 : 0;
    NSPoint topLeft = {content.origin.x, content.origin.y + content.size.height + title};
    ((void (*)(id, SEL, NSPoint))objc_send)(window->nswindow, SELECTOR("setFrameTopLeftPoint:"), topLeft);
    carbon_port_resize(window->port, bounds->right - bounds->left, bounds->bottom - bounds->top);
}

static Rect content_bounds(WindowRef window) {
    // The bounds kept are the content's, global: the window's port's
    // bounds are those, from its own origin.
    return window->bounds;
}

// MARK: - Making windows

OSStatus carbon_CreateNewWindow(uint32_t windowClass, uint32_t attributes, const Rect *bounds, WindowRef *out)
    CARBON_SYMBOL(CreateNewWindow);
OSStatus carbon_CreateNewWindow(uint32_t windowClass, uint32_t attributes, const Rect *bounds, WindowRef *out) {
    if (!bounds || !out) return paramErr;
    carbon_application();
    WindowRef window = calloc(1, sizeof *window);
    if (!window) return memFullErr;
    window->magic = CARBON_WINDOW_MAGIC;
    window->windowClass = windowClass;
    window->attributes = attributes;
    window->kind = 8;   // kApplicationWindowKind
    window->bounds = *bounds;
    unsigned long style = 0;
    if (titled(windowClass, attributes)) {
        style = 1;                                 // NSWindowStyleMaskTitled
        if (attributes & 1) style |= 2;            // kWindowCloseBoxAttribute
        if (attributes & 8) style |= 4;            // kWindowCollapseBoxAttribute
        if (attributes & 16) style |= 8;           // kWindowResizableAttribute
    }
    NSRect content = ns_content(bounds);
    id nswindow = SEND(CLASS("NSWindow"), "alloc");
    nswindow = ((id (*)(id, SEL, NSRect, unsigned long, unsigned long, signed char))objc_send)(
        nswindow, SELECTOR("initWithContentRect:styleMask:backing:defer:"), content, style, 2, 0);
    if (!nswindow) {
        free(window);
        return errUnknownWindowClass;
    }
    ((void (*)(id, SEL, signed char))objc_send)(nswindow, SELECTOR("setReleasedWhenClosed:"), 0);
    window->nswindow = nswindow;
    window->view = SEND(nswindow, "contentView");
    window->port = carbon_port_new(bounds->right - bounds->left, bounds->bottom - bounds->top, 32, NULL, 0);
    window->port->window = window;
    window->target = carbon_target_new(window);
    window->next = windows;
    windows = window;
    *out = window;
    CARBON_TRACE("window %p: class %u, %d×%d at %d,%d", (void *)window, windowClass,
                 bounds->right - bounds->left, bounds->bottom - bounds->top, bounds->left, bounds->top);
    return noErr;
}

/// The original Window Manager's: a document window unless the procID asks
/// for a plain or dialog one.
WindowRef carbon_NewCWindow(void *storage, const Rect *bounds, ConstStr255Param title, Boolean visible, int16_t procID,
                            WindowRef behind, Boolean goAway, long refCon) CARBON_SYMBOL(NewCWindow);
WindowRef carbon_NewCWindow(void *storage, const Rect *bounds, ConstStr255Param title, Boolean visible, int16_t procID,
                            WindowRef behind, Boolean goAway, long refCon) {
    (void)storage; (void)behind;
    uint32_t windowClass = 6;
    if (procID == 2 || procID == 3) windowClass = 13;          // plainDBox, altDBoxProc
    else if (procID == 1) windowClass = 3;                     // dBoxProc: modal
    else if (procID == 5) windowClass = 4;                     // movableDBoxProc: movable modal
    WindowRef window = NULL;
    if (carbon_CreateNewWindow(windowClass, goAway ? 1 : 0, bounds, &window) != noErr) return NULL;
    window->refCon = refCon;
    if (title && title[0]) {
        char name[256];
        memcpy(name, title + 1, title[0]);
        name[title[0]] = 0;
        ((void (*)(id, SEL, id))objc_send)(window->nswindow, SELECTOR("setTitle:"), carbon_string(name));
    }
    if (visible) carbon_ShowWindow(window);
    return window;
}

WindowRef carbon_NewWindow(void *storage, const Rect *bounds, ConstStr255Param title, Boolean visible, int16_t procID,
                           WindowRef behind, Boolean goAway, long refCon) CARBON_SYMBOL(NewWindow);
WindowRef carbon_NewWindow(void *storage, const Rect *bounds, ConstStr255Param title, Boolean visible, int16_t procID,
                           WindowRef behind, Boolean goAway, long refCon) {
    return carbon_NewCWindow(storage, bounds, title, visible, procID, behind, goAway, refCon);
}

void carbon_DisposeWindow(WindowRef window) CARBON_SYMBOL(DisposeWindow);
void carbon_DisposeWindow(WindowRef window) {
    if (!(window = carbon_window_from(window))) return;
    for (carbon_window **link = &windows; *link; link = &(*link)->next)
        if (*link == window) {
            *link = window->next;
            break;
        }
    SEND1(window->nswindow, "orderOut:", NULL);
    SEND(window->nswindow, "close");
    SEND(window->nswindow, "release");
    carbon_target_free(window->target);
    if (carbon_current_port() == window->port) {
        carbon_SetPort(NULL);
    }
    carbon_port_free(window->port);
    window->magic = 0;
    free(window);
}

// MARK: - Showing windows

void carbon_ShowWindow(WindowRef window) CARBON_SYMBOL(ShowWindow);
void carbon_ShowWindow(WindowRef window) {
    if (!(window = carbon_window_from(window))) return;
    window->visible = true;
    SEND1(window->nswindow, "makeKeyAndOrderFront:", NULL);
}

void carbon_HideWindow(WindowRef window) CARBON_SYMBOL(HideWindow);
void carbon_HideWindow(WindowRef window) {
    if (!(window = carbon_window_from(window))) return;
    window->visible = false;
    SEND1(window->nswindow, "orderOut:", NULL);
}

void carbon_ShowHide(WindowRef window, Boolean show) CARBON_SYMBOL(ShowHide);
void carbon_ShowHide(WindowRef window, Boolean show) {
    if (show) carbon_ShowWindow(window);
    else carbon_HideWindow(window);
}

Boolean carbon_IsWindowVisible(WindowRef window) CARBON_SYMBOL(IsWindowVisible);
Boolean carbon_IsWindowVisible(WindowRef window) { return (window = carbon_window_from(window)) && window->visible; }

void carbon_SelectWindow(WindowRef window) CARBON_SYMBOL(SelectWindow);
void carbon_SelectWindow(WindowRef window) {
    if (!(window = carbon_window_from(window))) return;
    // The front of the list is the front window.
    for (carbon_window **link = &windows; *link; link = &(*link)->next)
        if (*link == window) {
            *link = window->next;
            break;
        }
    window->next = windows;
    windows = window;
    if (window->visible) SEND1(window->nswindow, "makeKeyAndOrderFront:", NULL);
}

void carbon_BringToFront(WindowRef window) CARBON_SYMBOL(BringToFront);
void carbon_BringToFront(WindowRef window) {
    if ((window = carbon_window_from(window)) && window->visible) SEND1(window->nswindow, "orderFront:", NULL);
}

OSStatus carbon_ActivateWindow(WindowRef window, Boolean activate) CARBON_SYMBOL(ActivateWindow);
OSStatus carbon_ActivateWindow(WindowRef window, Boolean activate) {
    if (!(window = carbon_window_from(window))) return errInvalidWindowRef;
    if (activate && window->visible) SEND(window->nswindow, "makeKeyWindow");
    return noErr;
}

WindowRef carbon_front_window(void) {
    for (carbon_window *window = windows; window; window = window->next)
        if (window->visible) return window;
    return NULL;
}

WindowRef carbon_FrontWindow(void) CARBON_SYMBOL(FrontWindow);
WindowRef carbon_FrontWindow(void) { return carbon_front_window(); }

WindowRef carbon_FrontNonFloatingWindow(void) CARBON_SYMBOL(FrontNonFloatingWindow);
WindowRef carbon_FrontNonFloatingWindow(void) {
    for (carbon_window *window = windows; window; window = window->next)
        if (window->visible && window->windowClass != 5 && window->windowClass != 8) return window;
    return NULL;
}

WindowRef carbon_ActiveNonFloatingWindow(void) CARBON_SYMBOL(ActiveNonFloatingWindow);
WindowRef carbon_ActiveNonFloatingWindow(void) { return carbon_FrontNonFloatingWindow(); }

WindowRef carbon_GetNextWindow(WindowRef window) CARBON_SYMBOL(GetNextWindow);
WindowRef carbon_GetNextWindow(WindowRef window) { return (window = carbon_window_from(window)) ? window->next : NULL; }

WindowRef carbon_GetWindowList(void) CARBON_SYMBOL(GetWindowList);
WindowRef carbon_GetWindowList(void) { return windows; }

// MARK: - Ports

CGrafPtr carbon_GetWindowPort(WindowRef window) CARBON_SYMBOL(GetWindowPort);
CGrafPtr carbon_GetWindowPort(WindowRef window) { return (window = carbon_window_from(window)) ? window->port : NULL; }

WindowRef carbon_GetWindowFromPort(CGrafPtr port) CARBON_SYMBOL(GetWindowFromPort);
WindowRef carbon_GetWindowFromPort(CGrafPtr port) {
    return port && port->magic == CARBON_PORT_MAGIC ? port->window : NULL;
}

void carbon_SetPortWindowPort(WindowRef window) CARBON_SYMBOL(SetPortWindowPort);
void carbon_SetPortWindowPort(WindowRef window) {
    if ((window = carbon_window_from(window))) carbon_SetPort(window->port);
}

Boolean carbon_IsValidWindowPtr(WindowRef window) CARBON_SYMBOL(IsValidWindowPtr);
Boolean carbon_IsValidWindowPtr(WindowRef window) { return carbon_window_from(window) != NULL; }

/// The content view AGL draws into, for a port (agl.c).
id carbon_PerryCarbonPortView(CGrafPtr port) CARBON_SYMBOL(PerryCarbonPortView);
id carbon_PerryCarbonPortView(CGrafPtr port) {
    WindowRef window = carbon_GetWindowFromPort(port);
    return window ? window->view : NULL;
}

/// The port of the window a content view is of (aglGetDrawable).
CGrafPtr carbon_PerryCarbonViewPort(id view) CARBON_SYMBOL(PerryCarbonViewPort);
CGrafPtr carbon_PerryCarbonViewPort(id view) {
    for (carbon_window *window = windows; window; window = window->next)
        if (window->view == view) return window->port;
    return NULL;
}

// What QuickDraw drew into a window's port, shown in its content view: an
// image of the port's pixels as the content view's layer's contents.
void carbon_port_flush(CGrafPtr port) {
    if (!port || !port->window) return;
    static void *(*color_space)(void), *(*provider)(void *, const void *, size_t, void *),
        *(*image)(size_t, size_t, size_t, size_t, size_t, void *, uint32_t, void *, const void *, bool, int);
    static void (*release_provider)(void *), (*release_image)(void *);
    const char *library = "/System/Library/Frameworks/ApplicationServices.framework/ApplicationServices";
    if (!image) {
        color_space = (void *(*)(void))carbon_function(library, "_CGColorSpaceCreateDeviceRGB");
        provider = (void *(*)(void *, const void *, size_t, void *))carbon_function(library, "_CGDataProviderCreateWithData");
        image = (void *(*)(size_t, size_t, size_t, size_t, size_t, void *, uint32_t, void *, const void *, bool, int))
            carbon_function(library, "_CGImageCreate");
        release_provider = (void (*)(void *))carbon_function(library, "_CGDataProviderRelease");
        release_image = (void (*)(void *))carbon_function(library, "_CGImageRelease");
        if (!color_space || !provider || !image || !release_provider || !release_image) {
            image = NULL;
            return;
        }
    }
    PixMap *pixmap = *port->pixmap;
    int width = pixmap->bounds.right - pixmap->bounds.left, height = pixmap->bounds.bottom - pixmap->bounds.top;
    if (width <= 0 || height <= 0 || !pixmap->baseAddr) return;
    size_t stride = (size_t)(pixmap->rowBytes & 0x3fff);
    // A copy, which the image keeps: the port goes on being drawn into.
    void *copy = malloc(stride * (size_t)height);
    if (!copy) return;
    memcpy(copy, pixmap->baseAddr, stride * (size_t)height);
    void *data = provider(copy, copy, stride * (size_t)height, (void *)free);
    static void *space;
    if (!space) space = color_space();
    // kCGImageAlphaNoneSkipFirst, big-endian: QuickDraw's xRGB.
    uint32_t info = 6 | (4u << 12);
    int bits = pixmap->pixelSize == 16 ? 5 : 8;
    if (pixmap->pixelSize == 16) info = 6 | (1u << 12);   // big-endian 16-bit xRGB 1-5-5-5
    void *picture = image((size_t)width, (size_t)height, (size_t)bits, (size_t)pixmap->pixelSize, stride, space, info, data, NULL, false, 0);
    release_provider(data);
    if (!picture) return;
    id view = port->window->view;
    ((void (*)(id, SEL, signed char))objc_send)(view, SELECTOR("setWantsLayer:"), 1);
    ((void (*)(id, SEL, void *))objc_send)(SEND(view, "layer"), SELECTOR("setContents:"), picture);
    release_image(picture);
}

void carbon_QDFlushPortBuffer(CGrafPtr port, RgnHandle region) CARBON_SYMBOL(QDFlushPortBuffer);
void carbon_QDFlushPortBuffer(CGrafPtr port, RgnHandle region) {
    (void)region;
    if (port && port->magic == CARBON_PORT_MAGIC) carbon_port_flush(port);
}

// MARK: - Bounds

enum {
    kWindowTitleBarRgn = 0, kWindowStructureRgn = 32, kWindowContentRgn = 33, kWindowUpdateRgn = 34,
    kWindowGlobalPortRgn = 40,
};

static Rect region_bounds(WindowRef window, uint16_t region) {
    Rect bounds = content_bounds(window);
    int16_t title = titled(window->windowClass, window->attributes) ? 22 : 0;
    switch (region) {
    case kWindowStructureRgn: bounds.top -= title; break;
    case kWindowTitleBarRgn: bounds.bottom = bounds.top; bounds.top -= title; break;
    default: break;
    }
    return bounds;
}

OSStatus carbon_GetWindowBounds(WindowRef window, uint16_t region, Rect *bounds) CARBON_SYMBOL(GetWindowBounds);
OSStatus carbon_GetWindowBounds(WindowRef window, uint16_t region, Rect *bounds) {
    if (!(window = carbon_window_from(window)) || !bounds) return errInvalidWindowRef;
    *bounds = region_bounds(window, region);
    return noErr;
}

OSStatus carbon_SetWindowBounds(WindowRef window, uint16_t region, const Rect *bounds) CARBON_SYMBOL(SetWindowBounds);
OSStatus carbon_SetWindowBounds(WindowRef window, uint16_t region, const Rect *bounds) {
    if (!(window = carbon_window_from(window)) || !bounds) return errInvalidWindowRef;
    Rect content = *bounds;
    if (region == kWindowStructureRgn) content.top += titled(window->windowClass, window->attributes) ? 22 : 0;
    window->bounds = content;
    place(window, &content);
    return noErr;
}

OSStatus carbon_GetWindowRegion(WindowRef window, uint16_t region, RgnHandle out) CARBON_SYMBOL(GetWindowRegion);
OSStatus carbon_GetWindowRegion(WindowRef window, uint16_t region, RgnHandle out) {
    if (!(window = carbon_window_from(window)) || !out) return errInvalidWindowRef;
    (*out)->bounds = region == kWindowUpdateRgn ? (Rect){0, 0, 0, 0} : region_bounds(window, region);
    return noErr;
}

Rect *carbon_GetWindowPortBounds(WindowRef window, Rect *bounds) CARBON_SYMBOL(GetWindowPortBounds);
Rect *carbon_GetWindowPortBounds(WindowRef window, Rect *bounds) {
    if (!bounds) return NULL;
    *bounds = (window = carbon_window_from(window)) ? window->port->portRect : (Rect){0, 0, 0, 0};
    return bounds;
}

void carbon_MoveWindow(WindowRef window, int16_t h, int16_t v, Boolean front) CARBON_SYMBOL(MoveWindow);
void carbon_MoveWindow(WindowRef window, int16_t h, int16_t v, Boolean front) {
    if (!(window = carbon_window_from(window))) return;
    Rect bounds = window->bounds;
    bounds.right += h - bounds.left;
    bounds.bottom += v - bounds.top;
    bounds.left = h;
    bounds.top = v;
    carbon_SetWindowBounds(window, kWindowContentRgn, &bounds);
    if (front) carbon_SelectWindow(window);
}

void carbon_SizeWindow(WindowRef window, int16_t width, int16_t height, Boolean update) CARBON_SYMBOL(SizeWindow);
void carbon_SizeWindow(WindowRef window, int16_t width, int16_t height, Boolean update) {
    (void)update;
    if (!(window = carbon_window_from(window))) return;
    Rect bounds = window->bounds;
    bounds.right = bounds.left + width;
    bounds.bottom = bounds.top + height;
    carbon_SetWindowBounds(window, kWindowContentRgn, &bounds);
}

/// Centered on the main screen (kWindowCenterOnMainScreen and the rest).
OSStatus carbon_RepositionWindow(WindowRef window, WindowRef parent, uint32_t method) CARBON_SYMBOL(RepositionWindow);
OSStatus carbon_RepositionWindow(WindowRef window, WindowRef parent, uint32_t method) {
    (void)parent; (void)method;
    if (!(window = carbon_window_from(window))) return errInvalidWindowRef;
    Rect screen = (*carbon_main_device())->gdRect;
    int width = window->bounds.right - window->bounds.left, height = window->bounds.bottom - window->bounds.top;
    Rect bounds;
    bounds.left = (int16_t)((screen.right - width) / 2);
    bounds.top = (int16_t)((screen.bottom - height) / 3);
    bounds.right = (int16_t)(bounds.left + width);
    bounds.bottom = (int16_t)(bounds.top + height);
    return carbon_SetWindowBounds(window, kWindowContentRgn, &bounds);
}

// The front window's content origin, for local coordinates.
static Point origin(void) {
    CGrafPtr port = carbon_current_port();
    if (!port->window) return (Point){0, 0};
    return (Point){port->window->bounds.top, port->window->bounds.left};
}

void carbon_GlobalToLocal(Point *point) {
    Point at = origin();
    point->h -= at.h;
    point->v -= at.v;
}

void carbon_LocalToGlobal(Point *point) {
    Point at = origin();
    point->h += at.h;
    point->v += at.v;
}

/// Where a point is: in a window's content, its title bar, or the desktop.
int16_t carbon_FindWindow(Point point, WindowRef *out) CARBON_SYMBOL(FindWindow);
int16_t carbon_FindWindow(Point point, WindowRef *out) {
    if (out) *out = NULL;
    if (point.v < 22 && ui_menu_bar_visible()) return 1;   // inMenuBar
    for (carbon_window *window = windows; window; window = window->next) {
        if (!window->visible) continue;
        Rect content = window->bounds, structure = region_bounds(window, kWindowStructureRgn);
        if (out && (point.h >= structure.left && point.h < structure.right &&
                    point.v >= structure.top && point.v < structure.bottom)) *out = window;
        if (point.h >= content.left && point.h < content.right && point.v >= content.top && point.v < content.bottom)
            return 3;   // inContent
        if (point.h >= structure.left && point.h < structure.right && point.v >= structure.top && point.v < structure.bottom)
            return 4;   // inDrag
    }
    return 0;   // inDesk
}

// MARK: - Properties

OSStatus carbon_SetWindowTitleWithCFString(WindowRef window, id title) CARBON_SYMBOL(SetWindowTitleWithCFString);
OSStatus carbon_SetWindowTitleWithCFString(WindowRef window, id title) {
    if (!(window = carbon_window_from(window))) return errInvalidWindowRef;
    ((void (*)(id, SEL, id))objc_send)(window->nswindow, SELECTOR("setTitle:"), title ? title : carbon_string(""));
    return noErr;
}

void carbon_SetWTitle(WindowRef window, ConstStr255Param title) CARBON_SYMBOL(SetWTitle);
void carbon_SetWTitle(WindowRef window, ConstStr255Param title) {
    char name[256] = "";
    if (title) {
        memcpy(name, title + 1, title[0]);
        name[title[0]] = 0;
    }
    carbon_SetWindowTitleWithCFString(window, carbon_string(name));
}

long carbon_GetWRefCon(WindowRef window) CARBON_SYMBOL(GetWRefCon);
long carbon_GetWRefCon(WindowRef window) { return (window = carbon_window_from(window)) ? window->refCon : 0; }

void carbon_SetWRefCon(WindowRef window, long refCon) CARBON_SYMBOL(SetWRefCon);
void carbon_SetWRefCon(WindowRef window, long refCon) { if ((window = carbon_window_from(window))) window->refCon = refCon; }

int16_t carbon_GetWindowKind(WindowRef window) CARBON_SYMBOL(GetWindowKind);
int16_t carbon_GetWindowKind(WindowRef window) { return (window = carbon_window_from(window)) ? window->kind : 0; }

void carbon_SetWindowKind(WindowRef window, int16_t kind) CARBON_SYMBOL(SetWindowKind);
void carbon_SetWindowKind(WindowRef window, int16_t kind) { if ((window = carbon_window_from(window))) window->kind = kind; }

OSStatus carbon_GetWindowClass(WindowRef window, uint32_t *windowClass) CARBON_SYMBOL(GetWindowClass);
OSStatus carbon_GetWindowClass(WindowRef window, uint32_t *windowClass) {
    if (!(window = carbon_window_from(window)) || !windowClass) return errInvalidWindowRef;
    *windowClass = window->windowClass;
    return noErr;
}

OSStatus carbon_GetWindowAttributes(WindowRef window, uint32_t *attributes) CARBON_SYMBOL(GetWindowAttributes);
OSStatus carbon_GetWindowAttributes(WindowRef window, uint32_t *attributes) {
    if (!(window = carbon_window_from(window)) || !attributes) return errInvalidWindowRef;
    *attributes = window->attributes;
    return noErr;
}

OSStatus carbon_SetWindowContentColor(WindowRef window, const RGBColor *color) CARBON_SYMBOL(SetWindowContentColor);
OSStatus carbon_SetWindowContentColor(WindowRef window, const RGBColor *color) {
    if (!(window = carbon_window_from(window))) return errInvalidWindowRef;
    if (color) window->port->background = *color;
    return noErr;
}

OSStatus carbon_SetWindowModified(WindowRef window, Boolean modified) CARBON_SYMBOL(SetWindowModified);
OSStatus carbon_SetWindowModified(WindowRef window, Boolean modified) {
    if (!(window = carbon_window_from(window))) return errInvalidWindowRef;
    ((void (*)(id, SEL, signed char))objc_send)(window->nswindow, SELECTOR("setDocumentEdited:"), modified ? 1 : 0);
    return noErr;
}

OSStatus carbon_SetWindowProxyCreatorAndType(WindowRef window, OSType creator, OSType type, int16_t volume)
    CARBON_SYMBOL(SetWindowProxyCreatorAndType);
OSStatus carbon_SetWindowProxyCreatorAndType(WindowRef window, OSType creator, OSType type, int16_t volume) {
    (void)creator; (void)type; (void)volume;
    return carbon_window_from(window) ? noErr : errInvalidWindowRef;
}

// MARK: - Updates

// Windows are drawn when the program draws: there are no update regions to
// keep.
void carbon_BeginUpdate(WindowRef window) CARBON_SYMBOL(BeginUpdate);
void carbon_BeginUpdate(WindowRef window) { (void)window; }

void carbon_EndUpdate(WindowRef window) CARBON_SYMBOL(EndUpdate);
void carbon_EndUpdate(WindowRef window) {
    if ((window = carbon_window_from(window))) carbon_port_flush(window->port);
}

OSStatus carbon_InvalWindowRect(WindowRef window, const Rect *bounds) CARBON_SYMBOL(InvalWindowRect);
OSStatus carbon_InvalWindowRect(WindowRef window, const Rect *bounds) {
    (void)bounds;
    return carbon_window_from(window) ? noErr : errInvalidWindowRef;
}

OSStatus carbon_ValidWindowRect(WindowRef window, const Rect *bounds) CARBON_SYMBOL(ValidWindowRect);
OSStatus carbon_ValidWindowRect(WindowRef window, const Rect *bounds) {
    (void)bounds;
    return carbon_window_from(window) ? noErr : errInvalidWindowRef;
}

OSStatus carbon_InvalWindowRgn(WindowRef window, RgnHandle region) CARBON_SYMBOL(InvalWindowRgn);
OSStatus carbon_InvalWindowRgn(WindowRef window, RgnHandle region) {
    (void)region;
    return carbon_window_from(window) ? noErr : errInvalidWindowRef;
}

void carbon_DrawGrowIcon(WindowRef window) CARBON_SYMBOL(DrawGrowIcon);
void carbon_DrawGrowIcon(WindowRef window) { (void)window; }

// MARK: - Window groups

typedef struct carbon_window_group {
    int32_t level;
    int retains;
    uint32_t attributes;
} carbon_window_group;

/// A group's level as AppKit's: the floating and modal levels above
/// documents, the overlay and alert levels above those.
static long ns_level(int32_t level) {
    if (level >= 1000) return 101;   // kCGPopUpMenuWindowLevel and above
    if (level >= 8) return 8;        // modal panels
    if (level >= 3) return 3;        // floating
    return 0;
}

OSStatus carbon_CreateWindowGroup(uint32_t attributes, carbon_window_group **out) CARBON_SYMBOL(CreateWindowGroup);
OSStatus carbon_CreateWindowGroup(uint32_t attributes, carbon_window_group **out) {
    if (!out) return paramErr;
    carbon_window_group *group = calloc(1, sizeof *group);
    if (!group) return memFullErr;
    group->attributes = attributes;
    group->retains = 1;
    *out = group;
    return noErr;
}

OSStatus carbon_ReleaseWindowGroup(carbon_window_group *group) CARBON_SYMBOL(ReleaseWindowGroup);
OSStatus carbon_ReleaseWindowGroup(carbon_window_group *group) {
    if (!group) return paramErr;
    if (--group->retains == 0) {
        for (carbon_window *window = windows; window; window = window->next)
            if (window->group == group) window->group = NULL;
        free(group);
    }
    return noErr;
}

OSStatus carbon_RetainWindowGroup(carbon_window_group *group) CARBON_SYMBOL(RetainWindowGroup);
OSStatus carbon_RetainWindowGroup(carbon_window_group *group) {
    if (!group) return paramErr;
    group->retains++;
    return noErr;
}

OSStatus carbon_SetWindowGroupLevel(carbon_window_group *group, int32_t level) CARBON_SYMBOL(SetWindowGroupLevel);
OSStatus carbon_SetWindowGroupLevel(carbon_window_group *group, int32_t level) {
    if (!group) return paramErr;
    group->level = level;
    for (carbon_window *window = windows; window; window = window->next)
        if (window->group == group)
            ((void (*)(id, SEL, long))objc_send)(window->nswindow, SELECTOR("setLevel:"), ns_level(level));
    return noErr;
}

OSStatus carbon_GetWindowGroupLevel(carbon_window_group *group, int32_t *level) CARBON_SYMBOL(GetWindowGroupLevel);
OSStatus carbon_GetWindowGroupLevel(carbon_window_group *group, int32_t *level) {
    if (!group || !level) return paramErr;
    *level = group->level;
    return noErr;
}

OSStatus carbon_SetWindowGroup(WindowRef window, carbon_window_group *group) CARBON_SYMBOL(SetWindowGroup);
OSStatus carbon_SetWindowGroup(WindowRef window, carbon_window_group *group) {
    if (!(window = carbon_window_from(window))) return errInvalidWindowRef;
    window->group = group;
    ((void (*)(id, SEL, long))objc_send)(window->nswindow, SELECTOR("setLevel:"), group ? ns_level(group->level) : 0);
    return noErr;
}

carbon_window_group *carbon_GetWindowGroup(WindowRef window) CARBON_SYMBOL(GetWindowGroup);
carbon_window_group *carbon_GetWindowGroup(WindowRef window) { return (window = carbon_window_from(window)) ? window->group : NULL; }

Boolean carbon_IsWindowContainedInGroup(WindowRef window, carbon_window_group *group) CARBON_SYMBOL(IsWindowContainedInGroup);
Boolean carbon_IsWindowContainedInGroup(WindowRef window, carbon_window_group *group) {
    return (window = carbon_window_from(window)) && window->group == group;
}

// MARK: - Full screen

/// AGL's full-screen drawable: a window without a frame over the main
/// screen, at the size asked for, above the others.
CGrafPtr carbon_PerryCarbonFullScreenPort(int width, int height) CARBON_SYMBOL(PerryCarbonFullScreenPort);
CGrafPtr carbon_PerryCarbonFullScreenPort(int width, int height) {
    static WindowRef window;
    Rect screen = (*carbon_main_device())->gdRect;
    if (width <= 0 || height <= 0) {
        width = screen.right;
        height = screen.bottom;
    }
    Rect bounds = {0, 0, (int16_t)height, (int16_t)width};
    if (!window) {
        if (carbon_CreateNewWindow(13, 0, &bounds, &window) != noErr) return NULL;   // kPlainWindowClass
        ((void (*)(id, SEL, long))objc_send)(window->nswindow, SELECTOR("setLevel:"), 1000);   // the shielding level
    } else {
        window->bounds = bounds;
        place(window, &bounds);
    }
    carbon_ShowWindow(window);
    return window->port;
}
