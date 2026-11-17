// QuickDraw: rectangles, regions (a rectangle each, here), color ports and
// offscreen graphics worlds over memory of their own, the colors and pen
// they draw with, the main graphics device, and CopyBits between pixel
// maps. Pixels are QuickDraw's on Intel too: 32-bit ones are ARGB and
// 16-bit ones xRGB 1-5-5-5, each big-endian. A window's port is shown in
// its content view when the program flushes it (QDFlushPortBuffer).

#include "PerryCarbon.h"

#include <stdlib.h>
#include <string.h>

// MARK: - Rectangles

void carbon_SetRect(Rect *rect, int16_t left, int16_t top, int16_t right, int16_t bottom) CARBON_SYMBOL(SetRect);
void carbon_SetRect(Rect *rect, int16_t left, int16_t top, int16_t right, int16_t bottom) {
    rect->left = left;
    rect->top = top;
    rect->right = right;
    rect->bottom = bottom;
}

void carbon_OffsetRect(Rect *rect, int16_t dh, int16_t dv) CARBON_SYMBOL(OffsetRect);
void carbon_OffsetRect(Rect *rect, int16_t dh, int16_t dv) {
    rect->left += dh;
    rect->right += dh;
    rect->top += dv;
    rect->bottom += dv;
}

Boolean carbon_EmptyRect(const Rect *rect) CARBON_SYMBOL(EmptyRect);
Boolean carbon_EmptyRect(const Rect *rect) { return rect->right <= rect->left || rect->bottom <= rect->top; }

Boolean carbon_EqualRect(const Rect *a, const Rect *b) CARBON_SYMBOL(EqualRect);
Boolean carbon_EqualRect(const Rect *a, const Rect *b) {
    return a->left == b->left && a->top == b->top && a->right == b->right && a->bottom == b->bottom;
}

Boolean carbon_SectRect(const Rect *a, const Rect *b, Rect *out) CARBON_SYMBOL(SectRect);
Boolean carbon_SectRect(const Rect *a, const Rect *b, Rect *out) {
    Rect result = {
        a->top > b->top ? a->top : b->top, a->left > b->left ? a->left : b->left,
        a->bottom < b->bottom ? a->bottom : b->bottom, a->right < b->right ? a->right : b->right,
    };
    if (carbon_EmptyRect(&result)) result = (Rect){0, 0, 0, 0};
    *out = result;
    return !carbon_EmptyRect(&result);
}

void carbon_UnionRect(const Rect *a, const Rect *b, Rect *out) CARBON_SYMBOL(UnionRect);
void carbon_UnionRect(const Rect *a, const Rect *b, Rect *out) {
    Rect result = {
        a->top < b->top ? a->top : b->top, a->left < b->left ? a->left : b->left,
        a->bottom > b->bottom ? a->bottom : b->bottom, a->right > b->right ? a->right : b->right,
    };
    *out = result;
}

void carbon_InsetRect(Rect *rect, int16_t dh, int16_t dv) CARBON_SYMBOL(InsetRect);
void carbon_InsetRect(Rect *rect, int16_t dh, int16_t dv) {
    rect->left += dh;
    rect->right -= dh;
    rect->top += dv;
    rect->bottom -= dv;
}

Boolean carbon_PtInRect(Point point, const Rect *rect) CARBON_SYMBOL(PtInRect);
Boolean carbon_PtInRect(Point point, const Rect *rect) {
    return point.h >= rect->left && point.h < rect->right && point.v >= rect->top && point.v < rect->bottom;
}

/// The point, moved into the rectangle: its vertical change in the high
/// word, its horizontal in the low.
int32_t carbon_PinRect(const Rect *rect, Point point) CARBON_SYMBOL(PinRect);
int32_t carbon_PinRect(const Rect *rect, Point point) {
    int16_t h = point.h, v = point.v;
    if (h < rect->left) h = rect->left;
    if (h >= rect->right) h = rect->right - 1;
    if (v < rect->top) v = rect->top;
    if (v >= rect->bottom) v = rect->bottom - 1;
    return ((int32_t)(uint16_t)v << 16) | (uint16_t)h;
}

// MARK: - Regions

RgnHandle carbon_region_new(const Rect *bounds) {
    carbon_region **handle = malloc(sizeof *handle);
    carbon_region *region = calloc(1, sizeof *region);
    if (!handle || !region) {
        free(handle);
        free(region);
        return NULL;
    }
    if (bounds) region->bounds = *bounds;
    *handle = region;
    return handle;
}

RgnHandle carbon_NewRgn(void) CARBON_SYMBOL(NewRgn);
RgnHandle carbon_NewRgn(void) { return carbon_region_new(NULL); }

void carbon_DisposeRgn(RgnHandle region) CARBON_SYMBOL(DisposeRgn);
void carbon_DisposeRgn(RgnHandle region) {
    if (!region) return;
    free(*region);
    free(region);
}

void carbon_RectRgn(RgnHandle region, const Rect *rect) CARBON_SYMBOL(RectRgn);
void carbon_RectRgn(RgnHandle region, const Rect *rect) {
    if (region && rect) (*region)->bounds = carbon_EmptyRect(rect) ? (Rect){0, 0, 0, 0} : *rect;
}

void carbon_SetRectRgn(RgnHandle region, int16_t left, int16_t top, int16_t right, int16_t bottom) CARBON_SYMBOL(SetRectRgn);
void carbon_SetRectRgn(RgnHandle region, int16_t left, int16_t top, int16_t right, int16_t bottom) {
    Rect rect = {top, left, bottom, right};
    carbon_RectRgn(region, &rect);
}

void carbon_CopyRgn(RgnHandle source, RgnHandle destination) CARBON_SYMBOL(CopyRgn);
void carbon_CopyRgn(RgnHandle source, RgnHandle destination) {
    if (source && destination) **destination = **source;
}

Boolean carbon_EmptyRgn(RgnHandle region) CARBON_SYMBOL(EmptyRgn);
Boolean carbon_EmptyRgn(RgnHandle region) { return !region || carbon_EmptyRect(&(*region)->bounds); }

Rect *carbon_GetRegionBounds(RgnHandle region, Rect *bounds) CARBON_SYMBOL(GetRegionBounds);
Rect *carbon_GetRegionBounds(RgnHandle region, Rect *bounds) {
    *bounds = region ? (*region)->bounds : (Rect){0, 0, 0, 0};
    return bounds;
}

void carbon_OffsetRgn(RgnHandle region, int16_t dh, int16_t dv) CARBON_SYMBOL(OffsetRgn);
void carbon_OffsetRgn(RgnHandle region, int16_t dh, int16_t dv) {
    if (region) carbon_OffsetRect(&(*region)->bounds, dh, dv);
}

void carbon_SectRgn(RgnHandle a, RgnHandle b, RgnHandle out) CARBON_SYMBOL(SectRgn);
void carbon_SectRgn(RgnHandle a, RgnHandle b, RgnHandle out) {
    if (a && b && out) carbon_SectRect(&(*a)->bounds, &(*b)->bounds, &(*out)->bounds);
}

void carbon_UnionRgn(RgnHandle a, RgnHandle b, RgnHandle out) CARBON_SYMBOL(UnionRgn);
void carbon_UnionRgn(RgnHandle a, RgnHandle b, RgnHandle out) {
    if (!a || !b || !out) return;
    if (carbon_EmptyRgn(a)) **out = **b;
    else if (carbon_EmptyRgn(b)) **out = **a;
    else carbon_UnionRect(&(*a)->bounds, &(*b)->bounds, &(*out)->bounds);
}

// MARK: - Pixel maps

static PixMapHandle pixmap_new(int width, int height, int depth, void *pixels, long rowBytes) {
    PixMapHandle handle = malloc(sizeof *handle);
    PixMap *pixmap = calloc(1, sizeof *pixmap);
    if (!handle || !pixmap) {
        free(handle);
        free(pixmap);
        return NULL;
    }
    if (depth != 16) depth = 32;
    if (!rowBytes) rowBytes = ((long)width * (depth / 8) + 15) & ~15L;
    pixmap->baseAddr = pixels;
    pixmap->rowBytes = (int16_t)(0x8000 | (rowBytes & 0x3fff));
    pixmap->bounds = (Rect){0, 0, (int16_t)height, (int16_t)width};
    pixmap->hRes = pixmap->vRes = 72 << 16;
    pixmap->pixelType = 16;           // RGBDirect
    pixmap->pixelSize = (int16_t)depth;
    pixmap->cmpCount = 3;
    pixmap->cmpSize = depth == 32 ? 8 : 5;
    pixmap->pixelFormat = depth == 32 ? 0x20 : 0x10;   // k32ARGBPixelFormat, k16BE555PixelFormat
    *handle = pixmap;
    return handle;
}

static long row_bytes(const PixMap *pixmap) { return pixmap->rowBytes & 0x3fff; }

// MARK: - Graphics devices

GDHandle carbon_main_device(void) {
    static GDHandle device;
    if (device) return device;
    int width = 1920, height = 1080;
    size_t (*pixels_wide)(uint32_t) = (size_t (*)(uint32_t))carbon_function(
        "/System/Library/Frameworks/ApplicationServices.framework/ApplicationServices", "_CGDisplayPixelsWide");
    size_t (*pixels_high)(uint32_t) = (size_t (*)(uint32_t))carbon_function(
        "/System/Library/Frameworks/ApplicationServices.framework/ApplicationServices", "_CGDisplayPixelsHigh");
    if (pixels_wide && pixels_high) {
        width = (int)pixels_wide(1);
        height = (int)pixels_high(1);
    }
    GDPtr record = calloc(1, sizeof *record);
    device = malloc(sizeof *device);
    record->gdType = 2;               // directType
    record->gdFlags = (int16_t)0xb801;   // screen, main screen, active, ram-based
    record->gdPMap = pixmap_new(width, height, 32, NULL, 0);
    record->gdRect = (Rect){0, 0, (int16_t)height, (int16_t)width};
    record->gdMode = 0x80;
    *device = record;
    return device;
}

static GDHandle current_device;

GDHandle carbon_GetMainDevice(void) CARBON_SYMBOL(GetMainDevice);
GDHandle carbon_GetMainDevice(void) { return carbon_main_device(); }

GDHandle carbon_GetGDevice(void) CARBON_SYMBOL(GetGDevice);
GDHandle carbon_GetGDevice(void) { return current_device ? current_device : carbon_main_device(); }

void carbon_SetGDevice(GDHandle device) CARBON_SYMBOL(SetGDevice);
void carbon_SetGDevice(GDHandle device) { current_device = device; }

GDHandle carbon_GetDeviceList(void) CARBON_SYMBOL(GetDeviceList);
GDHandle carbon_GetDeviceList(void) { return carbon_main_device(); }

GDHandle carbon_GetNextDevice(GDHandle device) CARBON_SYMBOL(GetNextDevice);
GDHandle carbon_GetNextDevice(GDHandle device) { (void)device; return NULL; }

/// The Display Manager's screens: the one display's device.
GDHandle carbon_DMGetFirstScreenDevice(Boolean activeOnly) CARBON_SYMBOL(DMGetFirstScreenDevice);
GDHandle carbon_DMGetFirstScreenDevice(Boolean activeOnly) {
    (void)activeOnly;
    return carbon_main_device();
}

GDHandle carbon_DMGetNextScreenDevice(GDHandle device, Boolean activeOnly) CARBON_SYMBOL(DMGetNextScreenDevice);
GDHandle carbon_DMGetNextScreenDevice(GDHandle device, Boolean activeOnly) {
    (void)device, (void)activeOnly;
    return NULL;
}

// MARK: - Ports

CGrafPtr carbon_port_new(int width, int height, int depth, void *pixels, long rowBytes) {
    CGrafPtr port = calloc(1, sizeof *port);
    if (!port) return NULL;
    port->magic = CARBON_PORT_MAGIC;
    port->ownsPixels = pixels == NULL;
    if (!pixels) {
        long stride = ((long)(width > 0 ? width : 1) * (depth == 16 ? 2 : 4) + 15) & ~15L;
        pixels = calloc((size_t)(height > 0 ? height : 1), (size_t)stride);
        rowBytes = stride;
    }
    port->pixmap = pixmap_new(width, height, depth, pixels, rowBytes);
    port->portRect = (Rect){0, 0, (int16_t)height, (int16_t)width};
    port->foreground = (RGBColor){0, 0, 0};
    port->background = (RGBColor){0xffff, 0xffff, 0xffff};
    port->clip = carbon_region_new(&(Rect){-32767, -32767, 32767, 32767});
    port->visible = carbon_region_new(&port->portRect);
    port->textSize = 12;
    port->device = carbon_main_device();
    return port;
}

void carbon_port_resize(CGrafPtr port, int width, int height) {
    PixMap *pixmap = *port->pixmap;
    if (pixmap->bounds.right == width && pixmap->bounds.bottom == height) return;
    int depth = pixmap->pixelSize;
    long stride = ((long)(width > 0 ? width : 1) * (depth / 8) + 15) & ~15L;
    if (port->ownsPixels) {
        free(pixmap->baseAddr);
        pixmap->baseAddr = calloc((size_t)(height > 0 ? height : 1), (size_t)stride);
    }
    pixmap->rowBytes = (int16_t)(0x8000 | (stride & 0x3fff));
    pixmap->bounds = (Rect){0, 0, (int16_t)height, (int16_t)width};
    port->portRect = pixmap->bounds;
    (*port->visible)->bounds = port->portRect;
}

void carbon_port_free(CGrafPtr port) {
    if (!port) return;
    if (port->ownsPixels) free((*port->pixmap)->baseAddr);
    free(*port->pixmap);
    free(port->pixmap);
    carbon_DisposeRgn(port->clip);
    carbon_DisposeRgn(port->visible);
    port->magic = 0;
    free(port);
}

static CGrafPtr current_port;

CGrafPtr carbon_current_port(void) {
    if (!current_port) current_port = carbon_port_new(1, 1, 32, NULL, 0);
    return current_port;
}

static CGrafPtr port_from(void *pointer) {
    CGrafPtr port = pointer;
    return port && port->magic == CARBON_PORT_MAGIC ? port : NULL;
}

void carbon_GetPort(CGrafPtr *port) CARBON_SYMBOL(GetPort);
void carbon_GetPort(CGrafPtr *port) { if (port) *port = carbon_current_port(); }

void carbon_SetPort(CGrafPtr port) CARBON_SYMBOL(SetPort);
void carbon_SetPort(CGrafPtr port) { if (!port || port_from(port)) current_port = port; }

Boolean carbon_QDSwapPort(CGrafPtr port, CGrafPtr *old) CARBON_SYMBOL(QDSwapPort);
Boolean carbon_QDSwapPort(CGrafPtr port, CGrafPtr *old) {
    CGrafPtr previous = carbon_current_port();
    if (old) *old = previous;
    carbon_SetPort(port);
    return previous != port;
}

void carbon_GetGWorld(CGrafPtr *port, GDHandle *device) CARBON_SYMBOL(GetGWorld);
void carbon_GetGWorld(CGrafPtr *port, GDHandle *device) {
    if (port) *port = carbon_current_port();
    if (device) *device = carbon_GetGDevice();
}

void carbon_SetGWorld(CGrafPtr port, GDHandle device) CARBON_SYMBOL(SetGWorld);
void carbon_SetGWorld(CGrafPtr port, GDHandle device) {
    carbon_SetPort(port);
    if (device) current_device = device;
}

Rect *carbon_GetPortBounds(CGrafPtr port, Rect *bounds) CARBON_SYMBOL(GetPortBounds);
Rect *carbon_GetPortBounds(CGrafPtr port, Rect *bounds) {
    port = port_from(port);
    *bounds = port ? port->portRect : (Rect){0, 0, 0, 0};
    return bounds;
}

void carbon_SetPortBounds(CGrafPtr port, const Rect *bounds) CARBON_SYMBOL(SetPortBounds);
void carbon_SetPortBounds(CGrafPtr port, const Rect *bounds) {
    if ((port = port_from(port)) && bounds) port->portRect = *bounds;
}

PixMapHandle carbon_GetPortPixMap(CGrafPtr port) CARBON_SYMBOL(GetPortPixMap);
PixMapHandle carbon_GetPortPixMap(CGrafPtr port) { return (port = port_from(port)) ? port->pixmap : NULL; }

const BitMap *carbon_GetPortBitMapForCopyBits(CGrafPtr port) CARBON_SYMBOL(GetPortBitMapForCopyBits);
const BitMap *carbon_GetPortBitMapForCopyBits(CGrafPtr port) {
    return (port = port_from(port)) ? (const BitMap *)*port->pixmap : NULL;
}

RgnHandle carbon_GetPortClipRegion(CGrafPtr port, RgnHandle region) CARBON_SYMBOL(GetPortClipRegion);
RgnHandle carbon_GetPortClipRegion(CGrafPtr port, RgnHandle region) {
    if ((port = port_from(port)) && region) **region = **port->clip;
    return region;
}

RgnHandle carbon_GetPortVisibleRegion(CGrafPtr port, RgnHandle region) CARBON_SYMBOL(GetPortVisibleRegion);
RgnHandle carbon_GetPortVisibleRegion(CGrafPtr port, RgnHandle region) {
    if ((port = port_from(port)) && region) **region = **port->visible;
    return region;
}

void carbon_GetClip(RgnHandle region) CARBON_SYMBOL(GetClip);
void carbon_GetClip(RgnHandle region) { if (region) **region = **carbon_current_port()->clip; }

void carbon_SetClip(RgnHandle region) CARBON_SYMBOL(SetClip);
void carbon_SetClip(RgnHandle region) { if (region) **carbon_current_port()->clip = **region; }

void carbon_ClipRect(const Rect *rect) CARBON_SYMBOL(ClipRect);
void carbon_ClipRect(const Rect *rect) { if (rect) carbon_RectRgn(carbon_current_port()->clip, rect); }

int16_t carbon_GetPortTextFont(CGrafPtr port) CARBON_SYMBOL(GetPortTextFont);
int16_t carbon_GetPortTextFont(CGrafPtr port) { return (port = port_from(port)) ? port->textFont : 0; }

int16_t carbon_GetPortTextFace(CGrafPtr port) CARBON_SYMBOL(GetPortTextFace);
int16_t carbon_GetPortTextFace(CGrafPtr port) { return (port = port_from(port)) ? port->textFace : 0; }

int16_t carbon_GetPortTextSize(CGrafPtr port) CARBON_SYMBOL(GetPortTextSize);
int16_t carbon_GetPortTextSize(CGrafPtr port) { return (port = port_from(port)) ? port->textSize : 12; }

void carbon_TextFont(int16_t font) CARBON_SYMBOL(TextFont);
void carbon_TextFont(int16_t font) { carbon_current_port()->textFont = font; }

void carbon_TextFace(int16_t face) CARBON_SYMBOL(TextFace);
void carbon_TextFace(int16_t face) { carbon_current_port()->textFace = face; }

void carbon_TextSize(int16_t size) CARBON_SYMBOL(TextSize);
void carbon_TextSize(int16_t size) { carbon_current_port()->textSize = size; }

void carbon_TextMode(int16_t mode) CARBON_SYMBOL(TextMode);
void carbon_TextMode(int16_t mode) { carbon_current_port()->textMode = mode; }

// MARK: - Colors

void carbon_RGBForeColor(const RGBColor *color) CARBON_SYMBOL(RGBForeColor);
void carbon_RGBForeColor(const RGBColor *color) { if (color) carbon_current_port()->foreground = *color; }

void carbon_RGBBackColor(const RGBColor *color) CARBON_SYMBOL(RGBBackColor);
void carbon_RGBBackColor(const RGBColor *color) { if (color) carbon_current_port()->background = *color; }

void carbon_GetForeColor(RGBColor *color) CARBON_SYMBOL(GetForeColor);
void carbon_GetForeColor(RGBColor *color) { if (color) *color = carbon_current_port()->foreground; }

void carbon_GetBackColor(RGBColor *color) CARBON_SYMBOL(GetBackColor);
void carbon_GetBackColor(RGBColor *color) { if (color) *color = carbon_current_port()->background; }

RGBColor *carbon_GetPortForeColor(CGrafPtr port, RGBColor *color) CARBON_SYMBOL(GetPortForeColor);
RGBColor *carbon_GetPortForeColor(CGrafPtr port, RGBColor *color) {
    if ((port = port_from(port)) && color) *color = port->foreground;
    return color;
}

RGBColor *carbon_GetPortBackColor(CGrafPtr port, RGBColor *color) CARBON_SYMBOL(GetPortBackColor);
RGBColor *carbon_GetPortBackColor(CGrafPtr port, RGBColor *color) {
    if ((port = port_from(port)) && color) *color = port->background;
    return color;
}

// The eight colors of the original QuickDraw, by their constants.
static RGBColor classic_color(int32_t color) {
    switch (color) {
    case 33: return (RGBColor){0, 0, 0};                 // blackColor
    case 30: return (RGBColor){0xffff, 0xffff, 0xffff};  // whiteColor
    case 205: return (RGBColor){0xffff, 0, 0};           // redColor
    case 341: return (RGBColor){0, 0xffff, 0};           // greenColor
    case 409: return (RGBColor){0, 0, 0xffff};           // blueColor
    case 273: return (RGBColor){0, 0xffff, 0xffff};      // cyanColor
    case 137: return (RGBColor){0xffff, 0, 0xffff};      // magentaColor
    case 69: return (RGBColor){0xffff, 0xffff, 0};       // yellowColor
    default: return (RGBColor){0, 0, 0};
    }
}

void carbon_ForeColor(int32_t color) CARBON_SYMBOL(ForeColor);
void carbon_ForeColor(int32_t color) { carbon_current_port()->foreground = classic_color(color); }

void carbon_BackColor(int32_t color) CARBON_SYMBOL(BackColor);
void carbon_BackColor(int32_t color) { carbon_current_port()->background = classic_color(color); }

// MARK: - Color tables and palettes

// Color tables are 8-bit gray ramps; direct pixels don't use them.
CTabHandle carbon_GetCTable(int16_t identifier) CARBON_SYMBOL(GetCTable);
CTabHandle carbon_GetCTable(int16_t identifier) {
    int count = identifier > 0 && identifier <= 8 ? 1 << identifier : 256;
    if (identifier > 32 && identifier <= 40) count = 1 << (identifier - 32);
    CTabHandle handle = malloc(sizeof *handle);
    ColorTable *table = calloc(1, sizeof(ColorTable) + sizeof(ColorSpec) * (size_t)count);
    table->ctSize = (int16_t)(count - 1);
    for (int index = 0; index < count; index++) {
        uint16_t level = (uint16_t)(0xffff - index * (0xffff / (count > 1 ? count - 1 : 1)));
        table->ctTable[index] = (ColorSpec){(int16_t)index, {level, level, level}};
    }
    *handle = table;
    return handle;
}

void carbon_DisposeCTable(CTabHandle table) CARBON_SYMBOL(DisposeCTable);
void carbon_DisposeCTable(CTabHandle table) {
    if (!table) return;
    free(*table);
    free(table);
}

void carbon_CTabChanged(CTabHandle table) CARBON_SYMBOL(CTabChanged);
void carbon_CTabChanged(CTabHandle table) { if (table && *table) (*table)->ctSeed++; }

typedef struct { int16_t count; RGBColor colors[256]; } carbon_palette;

void *carbon_NewPalette(int16_t count, CTabHandle table, int16_t usage, int16_t tolerance) CARBON_SYMBOL(NewPalette);
void *carbon_NewPalette(int16_t count, CTabHandle table, int16_t usage, int16_t tolerance) {
    (void)usage; (void)tolerance;
    carbon_palette **handle = malloc(sizeof *handle);
    carbon_palette *palette = calloc(1, sizeof *palette);
    palette->count = count > 256 ? 256 : count;
    for (int index = 0; table && index < palette->count && index <= (*table)->ctSize; index++)
        palette->colors[index] = (*table)->ctTable[index].rgb;
    *handle = palette;
    return handle;
}

void carbon_DisposePalette(carbon_palette **palette) CARBON_SYMBOL(DisposePalette);
void carbon_DisposePalette(carbon_palette **palette) {
    if (!palette) return;
    free(*palette);
    free(palette);
}

void carbon_SetEntryColor(carbon_palette **palette, int16_t entry, const RGBColor *color) CARBON_SYMBOL(SetEntryColor);
void carbon_SetEntryColor(carbon_palette **palette, int16_t entry, const RGBColor *color) {
    if (palette && color && entry >= 0 && entry < (*palette)->count) (*palette)->colors[entry] = *color;
}

void carbon_Index2Color(int32_t index, RGBColor *color) CARBON_SYMBOL(Index2Color);
void carbon_Index2Color(int32_t index, RGBColor *color) {
    uint16_t level = (uint16_t)(0xffff - (index & 0xff) * 257);
    *color = (RGBColor){level, level, level};
}

// MARK: - Offscreen graphics worlds

OSErr carbon_NewGWorld(CGrafPtr *world, int16_t depth, const Rect *bounds, CTabHandle table, GDHandle device, uint32_t flags)
    CARBON_SYMBOL(NewGWorld);
OSErr carbon_NewGWorld(CGrafPtr *world, int16_t depth, const Rect *bounds, CTabHandle table, GDHandle device, uint32_t flags) {
    (void)table; (void)device; (void)flags;
    if (!world || !bounds) return paramErr;
    CGrafPtr port = carbon_port_new(bounds->right - bounds->left, bounds->bottom - bounds->top, depth == 16 ? 16 : 32, NULL, 0);
    if (!port) return memFullErr;
    port->portRect = *bounds;
    (*port->pixmap)->bounds = *bounds;
    *world = port;
    return noErr;
}

OSErr carbon_NewGWorldFromPtr(CGrafPtr *world, uint32_t format, const Rect *bounds, CTabHandle table, GDHandle device,
                              uint32_t flags, void *pixels, int32_t rowBytes) CARBON_SYMBOL(NewGWorldFromPtr);
OSErr carbon_NewGWorldFromPtr(CGrafPtr *world, uint32_t format, const Rect *bounds, CTabHandle table, GDHandle device,
                              uint32_t flags, void *pixels, int32_t rowBytes) {
    (void)table; (void)device; (void)flags;
    if (!world || !bounds || !pixels) return paramErr;
    int depth = format == 16 || format == 0x10 ? 16 : 32;
    CGrafPtr port = carbon_port_new(bounds->right - bounds->left, bounds->bottom - bounds->top, depth, pixels, rowBytes);
    if (!port) return memFullErr;
    port->portRect = *bounds;
    (*port->pixmap)->bounds = *bounds;
    if (format != 16 && format != 32) (*port->pixmap)->pixelFormat = format;
    *world = port;
    return noErr;
}

void carbon_DisposeGWorld(CGrafPtr world) CARBON_SYMBOL(DisposeGWorld);
void carbon_DisposeGWorld(CGrafPtr world) {
    if (!port_from(world)) return;
    if (current_port == world) current_port = NULL;
    carbon_port_free(world);
}

PixMapHandle carbon_GetGWorldPixMap(CGrafPtr world) CARBON_SYMBOL(GetGWorldPixMap);
PixMapHandle carbon_GetGWorldPixMap(CGrafPtr world) { return carbon_GetPortPixMap(world); }

GDHandle carbon_GetGWorldDevice(CGrafPtr world) CARBON_SYMBOL(GetGWorldDevice);
GDHandle carbon_GetGWorldDevice(CGrafPtr world) { return (world = port_from(world)) ? world->device : carbon_main_device(); }

Boolean carbon_LockPixels(PixMapHandle pixmap) CARBON_SYMBOL(LockPixels);
Boolean carbon_LockPixels(PixMapHandle pixmap) { return pixmap != NULL; }

void carbon_UnlockPixels(PixMapHandle pixmap) CARBON_SYMBOL(UnlockPixels);
void carbon_UnlockPixels(PixMapHandle pixmap) { (void)pixmap; }

void *carbon_GetPixBaseAddr(PixMapHandle pixmap) CARBON_SYMBOL(GetPixBaseAddr);
void *carbon_GetPixBaseAddr(PixMapHandle pixmap) { return pixmap ? (*pixmap)->baseAddr : NULL; }

int32_t carbon_GetPixRowBytes(PixMapHandle pixmap) CARBON_SYMBOL(GetPixRowBytes);
int32_t carbon_GetPixRowBytes(PixMapHandle pixmap) { return pixmap ? (int32_t)row_bytes(*pixmap) : 0; }

int16_t carbon_GetPixDepth(PixMapHandle pixmap) CARBON_SYMBOL(GetPixDepth);
int16_t carbon_GetPixDepth(PixMapHandle pixmap) { return pixmap ? (*pixmap)->pixelSize : 0; }

/// Ports are all in memory: nothing is purged.
uint32_t carbon_GetPixelsState(PixMapHandle pixmap) CARBON_SYMBOL(GetPixelsState);
uint32_t carbon_GetPixelsState(PixMapHandle pixmap) { (void)pixmap; return 0x80; }

void carbon_SetPixelsState(PixMapHandle pixmap, uint32_t state) CARBON_SYMBOL(SetPixelsState);
void carbon_SetPixelsState(PixMapHandle pixmap, uint32_t state) { (void)pixmap; (void)state; }

// MARK: - Pixels

// A pixel as 8-bit ARGB, and back.
static uint32_t read_pixel(const PixMap *pixmap, int x, int y) {
    const uint8_t *row = (const uint8_t *)pixmap->baseAddr + (long)(y - pixmap->bounds.top) * row_bytes(pixmap);
    int column = x - pixmap->bounds.left;
    if (pixmap->pixelSize == 16) {
        const uint8_t *pixel = row + column * 2;
        uint16_t value = (uint16_t)(pixel[0] << 8 | pixel[1]);
        uint32_t r = (value >> 10) & 31, g = (value >> 5) & 31, b = value & 31;
        return 0xff000000u | (r << 3 | r >> 2) << 16 | (g << 3 | g >> 2) << 8 | (b << 3 | b >> 2);
    }
    const uint8_t *pixel = row + column * 4;
    return (uint32_t)pixel[0] << 24 | (uint32_t)pixel[1] << 16 | (uint32_t)pixel[2] << 8 | pixel[3];
}

static void write_pixel(PixMap *pixmap, int x, int y, uint32_t argb) {
    uint8_t *row = (uint8_t *)pixmap->baseAddr + (long)(y - pixmap->bounds.top) * row_bytes(pixmap);
    int column = x - pixmap->bounds.left;
    if (pixmap->pixelSize == 16) {
        uint16_t value = (uint16_t)(((argb >> 19) & 31) << 10 | ((argb >> 11) & 31) << 5 | ((argb >> 3) & 31));
        row[column * 2] = (uint8_t)(value >> 8);
        row[column * 2 + 1] = (uint8_t)value;
        return;
    }
    uint8_t *pixel = row + column * 4;
    pixel[0] = (uint8_t)(argb >> 24);
    pixel[1] = (uint8_t)(argb >> 16);
    pixel[2] = (uint8_t)(argb >> 8);
    pixel[3] = (uint8_t)argb;
}

static uint32_t argb(RGBColor color) {
    return 0xff000000u | (uint32_t)(color.red >> 8) << 16 | (uint32_t)(color.green >> 8) << 8 | (uint32_t)(color.blue >> 8);
}

/// Fills a rectangle of the current port, within its clip and bounds.
static void fill(const Rect *rect, uint32_t color) {
    CGrafPtr port = carbon_current_port();
    PixMap *pixmap = *port->pixmap;
    if (!pixmap->baseAddr) return;
    Rect area;
    if (!carbon_SectRect(rect, &pixmap->bounds, &area) || !carbon_SectRect(&area, &(*port->clip)->bounds, &area)) return;
    for (int y = area.top; y < area.bottom; y++)
        for (int x = area.left; x < area.right; x++)
            write_pixel(pixmap, x, y, color);
}

void carbon_PaintRect(const Rect *rect) CARBON_SYMBOL(PaintRect);
void carbon_PaintRect(const Rect *rect) { fill(rect, argb(carbon_current_port()->foreground)); }

void carbon_EraseRect(const Rect *rect) CARBON_SYMBOL(EraseRect);
void carbon_EraseRect(const Rect *rect) { fill(rect, argb(carbon_current_port()->background)); }

/// Patterns are solid here: black's, or the background's for white.
void carbon_FillRect(const Rect *rect, const uint8_t *pattern) CARBON_SYMBOL(FillRect);
void carbon_FillRect(const Rect *rect, const uint8_t *pattern) {
    fill(rect, pattern && pattern[0] == 0 ? argb(carbon_current_port()->background) : argb(carbon_current_port()->foreground));
}

void carbon_MoveTo(int16_t h, int16_t v) CARBON_SYMBOL(MoveTo);
void carbon_MoveTo(int16_t h, int16_t v) { carbon_current_port()->pen = (Point){v, h}; }

void carbon_Move(int16_t dh, int16_t dv) CARBON_SYMBOL(Move);
void carbon_Move(int16_t dh, int16_t dv) {
    Point *pen = &carbon_current_port()->pen;
    pen->h += dh;
    pen->v += dv;
}

void carbon_LineTo(int16_t h, int16_t v) CARBON_SYMBOL(LineTo);
void carbon_LineTo(int16_t h, int16_t v) {
    CGrafPtr port = carbon_current_port();
    uint32_t color = argb(port->foreground);
    int x = port->pen.h, y = port->pen.v;
    int dx = abs(h - x), dy = -abs(v - y), sx = x < h ? 1 : -1, sy = y < v ? 1 : -1, error = dx + dy;
    for (;;) {
        Rect dot = {(int16_t)y, (int16_t)x, (int16_t)(y + 1), (int16_t)(x + 1)};
        fill(&dot, color);
        if (x == h && y == v) break;
        int twice = 2 * error;
        if (twice >= dy) { error += dy; x += sx; }
        if (twice <= dx) { error += dx; y += sy; }
    }
    port->pen = (Point){v, h};
}

void carbon_GetPenState(PenState *state) CARBON_SYMBOL(GetPenState);
void carbon_GetPenState(PenState *state) {
    if (!state) return;
    memset(state, 0, sizeof *state);
    state->pnLoc = carbon_current_port()->pen;
    state->pnSize = (Point){1, 1};
    state->pnMode = 8;   // patCopy
    memset(state->pnPat, 0xff, sizeof state->pnPat);
}

void carbon_SetPenState(const PenState *state) CARBON_SYMBOL(SetPenState);
void carbon_SetPenState(const PenState *state) { if (state) carbon_current_port()->pen = state->pnLoc; }

/// Copies a rectangle of one pixel map into another's, scaled to fit, as
/// srcCopy does; other modes copy too.
void carbon_CopyBits(const BitMap *source, const BitMap *destination, const Rect *from, const Rect *to, int16_t mode,
                     RgnHandle mask) CARBON_SYMBOL(CopyBits);
void carbon_CopyBits(const BitMap *source, const BitMap *destination, const Rect *from, const Rect *to, int16_t mode,
                     RgnHandle mask) {
    (void)mode;
    if (!source || !destination || !from || !to) return;
    const PixMap *in = (const PixMap *)source;
    PixMap *out = (PixMap *)destination;
    if (!in->baseAddr || !out->baseAddr) return;
    int fromWidth = from->right - from->left, fromHeight = from->bottom - from->top;
    int toWidth = to->right - to->left, toHeight = to->bottom - to->top;
    if (fromWidth <= 0 || fromHeight <= 0 || toWidth <= 0 || toHeight <= 0) return;
    Rect area;
    if (!carbon_SectRect(to, &out->bounds, &area)) return;
    if (mask && !carbon_SectRect(&area, &(*mask)->bounds, &area)) return;
    for (int y = area.top; y < area.bottom; y++) {
        int sy = from->top + (y - to->top) * fromHeight / toHeight;
        if (sy < in->bounds.top || sy >= in->bounds.bottom) continue;
        for (int x = area.left; x < area.right; x++) {
            int sx = from->left + (x - to->left) * fromWidth / toWidth;
            if (sx < in->bounds.left || sx >= in->bounds.right) continue;
            write_pixel(out, x, y, read_pixel(in, sx, sy));
        }
    }
    // A window's port shows what was copied into it.
    CGrafPtr port = carbon_current_port();
    if (port->window && *port->pixmap == out) carbon_port_flush(port);
}

// MARK: - Coordinates

void carbon_GlobalToLocal(Point *point) CARBON_SYMBOL(GlobalToLocal);
void carbon_LocalToGlobal(Point *point) CARBON_SYMBOL(LocalToGlobal);
