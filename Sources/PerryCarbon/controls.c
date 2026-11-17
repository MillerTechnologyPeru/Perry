// The Control Manager and HIView: a control is a view of AppKit's in its
// window's content (a button, a text field, an image view), with Carbon's
// ID, bounds in the window's coordinates and a parent. A window's root
// control is its content view. Buttons send their commands as Carbon's do;
// a scrolling text box shows its 'TEXT' resource.

#include "PerryCarbon.h"

#include <stdlib.h>
#include <string.h>

#define FOUR(a, b, c, d) ((uint32_t)(a) << 24 | (uint32_t)(b) << 16 | (uint32_t)(c) << 8 | (uint32_t)(d))

struct carbon_control {
    uint32_t magic;
    WindowRef window;
    ControlRef parent;
    id view;
    Rect bounds;
    OSType kind;
    OSType signature;
    int32_t identifier;
    uint32_t command;
    long refCon;
    bool visible, active;
    carbon_target *target;
    ControlRef next;   // the window's controls
};

#define CARBON_CONTROL_MAGIC 0x434e544cu   // 'CNTL'

// The Event Manager's, for HIObjects' classes' handlers.
extern OSStatus install_handler(carbon_target *target, void *procedure, size_t count, const void *types, void *userData,
                                void **out) __asm__("_InstallEventHandler");

static ControlRef controls;

static ControlRef control_from(void *pointer) {
    ControlRef control = pointer;
    return control && control->magic == CARBON_CONTROL_MAGIC ? control : NULL;
}

// MARK: - Actions

typedef struct action {
    id sender;
    uint32_t command;
    WindowRef window;
    void *menu;
    uint16_t item;
    struct action *next;
} action;

static action *actions;

void carbon_action_register(id sender, uint32_t command, WindowRef window, void *menu, uint16_t item) {
    for (action *existing = actions; existing; existing = existing->next)
        if (existing->sender == sender) {
            existing->command = command;
            existing->window = window;
            existing->menu = menu;
            existing->item = item;
            return;
        }
    action *made = calloc(1, sizeof *made);
    if (!made) return;
    *made = (action){sender, command, window, menu, item, actions};
    actions = made;
}

static void perform(id self, SEL selector, id sender) {
    (void)self; (void)selector;
    for (action *found = actions; found; found = found->next)
        if (found->sender == sender) {
            WindowRef window = carbon_window_from(found->window);
            carbon_process_command(found->command, found->menu, found->item, window ? window->target : NULL);
            return;
        }
}

/// The object AppKit's controls and menu items send their actions to,
/// of a class made for it.
id carbon_action_target(void) {
    static id target;
    if (target) return target;
    id (*allocate)(id, const char *, size_t) = (id (*)(id, const char *, size_t))carbon_function("/usr/lib/libobjc.A.dylib", "_objc_allocateClassPair");
    void (*register_class)(id) = (void (*)(id))carbon_function("/usr/lib/libobjc.A.dylib", "_objc_registerClassPair");
    Boolean (*add_method)(id, SEL, void *, const char *) = (Boolean (*)(id, SEL, void *, const char *))carbon_function(
        "/usr/lib/libobjc.A.dylib", "_class_addMethod");
    if (!allocate || !register_class || !add_method) return NULL;
    id class = allocate(CLASS("NSObject"), "PerryCarbonActionTarget", 0);
    if (!class) return NULL;
    add_method(class, SELECTOR("perryCarbonPerform:"), (void *)perform, "v@:@");
    register_class(class);
    target = SEND(SEND(class, "alloc"), "init");
    return target;
}

// MARK: - Controls

NSRect carbon_view_frame(WindowRef window, const Rect *bounds) {
    CGFloat height = window->bounds.bottom - window->bounds.top;
    return (NSRect){{bounds->left, height - bounds->bottom}, {bounds->right - bounds->left, bounds->bottom - bounds->top}};
}

ControlRef carbon_root_control(WindowRef window) {
    if (!(window = carbon_window_from(window))) return NULL;
    for (ControlRef control = controls; control; control = control->next)
        if (control->window == window && !control->parent) return control;
    Rect bounds = {0, 0, (int16_t)(window->bounds.bottom - window->bounds.top), (int16_t)(window->bounds.right - window->bounds.left)};
    ControlRef root = calloc(1, sizeof *root);
    if (!root) return NULL;
    root->magic = CARBON_CONTROL_MAGIC;
    root->window = window;
    root->view = window->view;
    root->bounds = bounds;
    root->kind = FOUR('r', 'o', 'o', 't');
    root->visible = root->active = true;
    root->next = controls;
    controls = root;
    return root;
}

ControlRef carbon_control_new(WindowRef window, ControlRef parent, id view, const Rect *bounds, OSType kind) {
    if (!(window = carbon_window_from(window))) return NULL;
    if (!parent) parent = carbon_root_control(window);
    ControlRef control = calloc(1, sizeof *control);
    if (!control) return NULL;
    control->magic = CARBON_CONTROL_MAGIC;
    control->window = window;
    control->parent = parent;
    control->view = view;
    control->bounds = *bounds;
    control->kind = kind;
    control->visible = control->active = true;
    control->target = carbon_target_new(control);
    control->next = controls;
    controls = control;
    if (view) {
        ((void (*)(id, SEL, NSRect))objc_send)(view, SELECTOR("setFrame:"), carbon_view_frame(window, bounds));
        SEND1(window->view, "addSubview:", view);
    }
    return control;
}

void carbon_control_set_id(ControlRef control, OSType signature, int32_t identifier) {
    if (!(control = control_from(control))) return;
    control->signature = signature;
    control->identifier = identifier;
}

#pragma pack(push, 2)
typedef struct { OSType signature; int32_t id; } ControlID;
#pragma pack(pop)

OSStatus carbon_GetControlByID(WindowRef window, const ControlID *identifier, ControlRef *out) CARBON_SYMBOL(GetControlByID);
OSStatus carbon_GetControlByID(WindowRef window, const ControlID *identifier, ControlRef *out) {
    if (!(window = carbon_window_from(window)) || !identifier || !out) return paramErr;
    for (ControlRef control = controls; control; control = control->next)
        if (control->window == window && control->signature == identifier->signature && control->identifier == identifier->id) {
            *out = control;
            return noErr;
        }
    *out = NULL;
    return -30584;   // errItemNotControl
}

OSStatus carbon_HIViewFindByID(ControlRef root, ControlID identifier, ControlRef *out) CARBON_SYMBOL(HIViewFindByID);
OSStatus carbon_HIViewFindByID(ControlRef root, ControlID identifier, ControlRef *out) {
    if (!(root = control_from(root)) || !out) return paramErr;
    // kHIViewWindowContentID: the root.
    if (identifier.signature == FOUR('w', 'i', 'n', 'd') && identifier.id == 1) {
        *out = root;
        return noErr;
    }
    return carbon_GetControlByID(root->window, &identifier, out);
}

OSStatus carbon_GetControlID(ControlRef control, ControlID *identifier) CARBON_SYMBOL(GetControlID);
OSStatus carbon_GetControlID(ControlRef control, ControlID *identifier) {
    if (!(control = control_from(control)) || !identifier) return paramErr;
    *identifier = (ControlID){control->signature, control->identifier};
    return noErr;
}

OSStatus carbon_SetControlID(ControlRef control, const ControlID *identifier) CARBON_SYMBOL(SetControlID);
OSStatus carbon_SetControlID(ControlRef control, const ControlID *identifier) {
    if (!(control = control_from(control)) || !identifier) return paramErr;
    control->signature = identifier->signature;
    control->identifier = identifier->id;
    return noErr;
}

void carbon_SetControlCommandID(ControlRef control, uint32_t command) CARBON_SYMBOL(SetControlCommandID);
void carbon_SetControlCommandID(ControlRef control, uint32_t command) {
    if (!(control = control_from(control))) return;
    control->command = command;
    if (control->view) carbon_action_register(control->view, command, control->window, NULL, 0);
}

OSStatus carbon_GetControlCommandID(ControlRef control, uint32_t *command) CARBON_SYMBOL(GetControlCommandID);
OSStatus carbon_GetControlCommandID(ControlRef control, uint32_t *command) {
    if (!(control = control_from(control)) || !command) return paramErr;
    *command = control->command;
    return noErr;
}

Rect *carbon_GetControlBounds(ControlRef control, Rect *bounds) CARBON_SYMBOL(GetControlBounds);
Rect *carbon_GetControlBounds(ControlRef control, Rect *bounds) {
    if (bounds) *bounds = (control = control_from(control)) ? control->bounds : (Rect){0, 0, 0, 0};
    return bounds;
}

void carbon_SetControlBounds(ControlRef control, const Rect *bounds) CARBON_SYMBOL(SetControlBounds);
void carbon_SetControlBounds(ControlRef control, const Rect *bounds) {
    if (!(control = control_from(control)) || !bounds) return;
    control->bounds = *bounds;
    if (control->view && control->parent)
        ((void (*)(id, SEL, NSRect))objc_send)(control->view, SELECTOR("setFrame:"), carbon_view_frame(control->window, bounds));
}

static void set_hidden(ControlRef control, bool hidden) {
    control->visible = !hidden;
    if (control->view && control->parent)
        ((void (*)(id, SEL, signed char))objc_send)(control->view, SELECTOR("setHidden:"), hidden ? 1 : 0);
}

void carbon_ShowControl(ControlRef control) CARBON_SYMBOL(ShowControl);
void carbon_ShowControl(ControlRef control) { if ((control = control_from(control))) set_hidden(control, false); }

void carbon_HideControl(ControlRef control) CARBON_SYMBOL(HideControl);
void carbon_HideControl(ControlRef control) { if ((control = control_from(control))) set_hidden(control, true); }

OSStatus carbon_SetControlVisibility(ControlRef control, Boolean visible, Boolean draw) CARBON_SYMBOL(SetControlVisibility);
OSStatus carbon_SetControlVisibility(ControlRef control, Boolean visible, Boolean draw) {
    (void)draw;
    if (!(control = control_from(control))) return paramErr;
    set_hidden(control, !visible);
    return noErr;
}

static void set_enabled(ControlRef control, bool enabled) {
    control->active = enabled;
    if (control->view && control->parent && control->kind == FOUR('b', 'u', 't', 'n'))
        ((void (*)(id, SEL, signed char))objc_send)(control->view, SELECTOR("setEnabled:"), enabled ? 1 : 0);
}

OSStatus carbon_ActivateControl(ControlRef control) CARBON_SYMBOL(ActivateControl);
OSStatus carbon_ActivateControl(ControlRef control) {
    if (!(control = control_from(control))) return paramErr;
    set_enabled(control, true);
    return noErr;
}

OSStatus carbon_DeactivateControl(ControlRef control) CARBON_SYMBOL(DeactivateControl);
OSStatus carbon_DeactivateControl(ControlRef control) {
    if (!(control = control_from(control))) return paramErr;
    set_enabled(control, false);
    return noErr;
}

OSStatus carbon_EnableControl(ControlRef control) CARBON_SYMBOL(EnableControl);
OSStatus carbon_EnableControl(ControlRef control) { return carbon_ActivateControl(control); }

OSStatus carbon_DisableControl(ControlRef control) CARBON_SYMBOL(DisableControl);
OSStatus carbon_DisableControl(ControlRef control) { return carbon_DeactivateControl(control); }

void carbon_DisposeControl(ControlRef control) CARBON_SYMBOL(DisposeControl);
void carbon_DisposeControl(ControlRef control) {
    if (!(control = control_from(control)) || !control->parent) return;
    for (ControlRef *link = &controls; *link; link = &(*link)->next)
        if (*link == control) {
            *link = control->next;
            break;
        }
    if (control->view) {
        SEND(control->view, "removeFromSuperview");
        SEND(control->view, "release");
    }
    carbon_target_free(control->target);
    control->magic = 0;
    free(control);
}

long carbon_GetControlReference(ControlRef control) CARBON_SYMBOL(GetControlReference);
long carbon_GetControlReference(ControlRef control) { return (control = control_from(control)) ? control->refCon : 0; }

void carbon_SetControlReference(ControlRef control, long refCon) CARBON_SYMBOL(SetControlReference);
void carbon_SetControlReference(ControlRef control, long refCon) { if ((control = control_from(control))) control->refCon = refCon; }

carbon_target *carbon_GetControlEventTarget(ControlRef control) CARBON_SYMBOL(GetControlEventTarget);
carbon_target *carbon_GetControlEventTarget(ControlRef control) { return (control = control_from(control)) ? control->target : NULL; }

WindowRef carbon_GetControlOwner(ControlRef control) CARBON_SYMBOL(GetControlOwner);
WindowRef carbon_GetControlOwner(ControlRef control) { return (control = control_from(control)) ? control->window : NULL; }

void carbon_Draw1Control(ControlRef control) CARBON_SYMBOL(Draw1Control);
void carbon_Draw1Control(ControlRef control) {
    if ((control = control_from(control)) && control->view)
        ((void (*)(id, SEL, signed char))objc_send)(control->view, SELECTOR("setNeedsDisplay:"), 1);
}

// MARK: - Text

/// A label's or a text field's text: kControlStaticTextCFStringTag
/// ('cfst'), kControlEditTextCFStringTag ('cfst'), and the bytes of
/// kControlStaticTextTextTag ('text').
OSErr carbon_SetControlData(ControlRef control, int16_t part, OSType tag, size_t size, const void *data) CARBON_SYMBOL(SetControlData);
OSErr carbon_SetControlData(ControlRef control, int16_t part, OSType tag, size_t size, const void *data) {
    (void)part;
    if (!(control = control_from(control)) || !data) return paramErr;
    id text = NULL;
    if (tag == FOUR('c', 'f', 's', 't') && size >= sizeof(id)) text = *(const id *)data;
    else if (tag == FOUR('t', 'e', 'x', 't')) {
        char *buffer = malloc(size + 1);
        if (!buffer) return memFullErr;
        memcpy(buffer, data, size);
        buffer[size] = 0;
        for (size_t index = 0; index < size; index++) if (buffer[index] == '\r') buffer[index] = '\n';
        text = carbon_string(buffer);
        free(buffer);
    }
    if (!text || !control->view) return noErr;
    if (control->kind == FOUR('b', 'u', 't', 'n')) SEND1(control->view, "setTitle:", text);
    else SEND1(control->view, "setStringValue:", text);
    return noErr;
}

OSStatus carbon_SetControlTitleWithCFString(ControlRef control, id title) CARBON_SYMBOL(SetControlTitleWithCFString);
OSStatus carbon_SetControlTitleWithCFString(ControlRef control, id title) {
    if (!(control = control_from(control))) return paramErr;
    if (control->view && title)
        SEND1(control->view, control->kind == FOUR('b', 'u', 't', 'n') ? "setTitle:" : "setStringValue:", title);
    return noErr;
}

// MARK: - Making controls

/// A label: a text field that isn't edited, without a bezel or background.
id carbon_label_view(id text, bool small) {
    id field = SEND1(CLASS("NSTextField"), "labelWithString:", text ? text : carbon_string(""));
    SEND(field, "retain");
    if (small) {
        id font = ((id (*)(id, SEL, CGFloat))objc_send)(CLASS("NSFont"), SELECTOR("systemFontOfSize:"), 11);
        if (font) SEND1(field, "setFont:", font);
    }
    return field;
}

/// A push button: buttonType 1 is the default (Return), 2 the cancel (Escape).
id carbon_button_view(id title, uint32_t command, WindowRef window, int type) {
    id button = SEND(SEND(CLASS("NSButton"), "alloc"), "init");
    SEND1(button, "setTitle:", title ? title : carbon_string(""));
    ((void (*)(id, SEL, unsigned long))objc_send)(button, SELECTOR("setBezelStyle:"), 1);   // rounded
    if (type == 1) SEND1(button, "setKeyEquivalent:", carbon_string("\r"));
    if (type == 2) SEND1(button, "setKeyEquivalent:", carbon_string("\x1b"));
    SEND1(button, "setTarget:", carbon_action_target());
    ((void (*)(id, SEL, SEL))objc_send)(button, SELECTOR("setAction:"), SELECTOR("perryCarbonPerform:"));
    carbon_action_register(button, command, window, NULL, 0);
    return button;
}

OSStatus carbon_CreatePushButtonControl(WindowRef window, const Rect *bounds, id title, ControlRef *out)
    CARBON_SYMBOL(CreatePushButtonControl);
OSStatus carbon_CreatePushButtonControl(WindowRef window, const Rect *bounds, id title, ControlRef *out) {
    if (!(window = carbon_window_from(window)) || !bounds || !out) return paramErr;
    *out = carbon_control_new(window, NULL, carbon_button_view(title, 0, window, 0), bounds, FOUR('b', 'u', 't', 'n'));
    return *out ? noErr : memFullErr;
}

OSStatus carbon_CreateStaticTextControl(WindowRef window, const Rect *bounds, id text, const void *style, ControlRef *out)
    CARBON_SYMBOL(CreateStaticTextControl);
OSStatus carbon_CreateStaticTextControl(WindowRef window, const Rect *bounds, id text, const void *style, ControlRef *out) {
    (void)style;
    if (!(window = carbon_window_from(window)) || !bounds || !out) return paramErr;
    *out = carbon_control_new(window, NULL, carbon_label_view(text, false), bounds, FOUR('s', 't', 'x', 't'));
    return *out ? noErr : memFullErr;
}

/// A scrolling text box: its 'TEXT' resource's text, in a label as tall as
/// the box (the box doesn't scroll by itself here).
OSStatus carbon_CreateScrollingTextBoxControl(WindowRef window, const Rect *bounds, int16_t resource, Boolean autoScroll,
                                              uint32_t delay, uint32_t between, uint16_t amount, ControlRef *out)
    CARBON_SYMBOL(CreateScrollingTextBoxControl);
OSStatus carbon_CreateScrollingTextBoxControl(WindowRef window, const Rect *bounds, int16_t resource, Boolean autoScroll,
                                              uint32_t delay, uint32_t between, uint16_t amount, ControlRef *out) {
    (void)autoScroll; (void)delay; (void)between; (void)amount;
    if (!(window = carbon_window_from(window)) || !bounds || !out) return paramErr;
    Handle (*get_resource)(OSType, int16_t) = (Handle (*)(OSType, int16_t))carbon_function(
        "/System/Library/Frameworks/Carbon.framework/Versions/A/Carbon", "_GetResource");
    long (*handle_size)(Handle) = (long (*)(Handle))carbon_function(CORESERVICES, "_GetHandleSize");
    Handle text = get_resource ? get_resource(FOUR('T', 'E', 'X', 'T'), resource) : NULL;
    id view = carbon_label_view(NULL, true);
    *out = carbon_control_new(window, NULL, view, bounds, FOUR('s', 't', 'x', 't'));
    if (!*out) return memFullErr;
    if (text && handle_size) carbon_SetControlData(*out, 0, FOUR('t', 'e', 'x', 't'), (size_t)handle_size(text), *text);
    return noErr;
}

// MARK: - HIView

ControlRef carbon_HIViewGetRoot(WindowRef window) CARBON_SYMBOL(HIViewGetRoot);
ControlRef carbon_HIViewGetRoot(WindowRef window) { return carbon_root_control(window); }

/// HIRects are floats, from the parent's top left.
typedef struct { float x, y, width, height; } HIRect;

static Rect rect_of(HIRect frame) {
    return (Rect){(int16_t)frame.y, (int16_t)frame.x, (int16_t)(frame.y + frame.height), (int16_t)(frame.x + frame.width)};
}

OSStatus carbon_HIViewSetFrame(ControlRef control, const HIRect *frame) CARBON_SYMBOL(HIViewSetFrame);
OSStatus carbon_HIViewSetFrame(ControlRef control, const HIRect *frame) {
    if (!(control = control_from(control)) || !frame) return paramErr;
    Rect bounds = rect_of(*frame);
    if (control->parent && control->parent->parent) carbon_OffsetRect(&bounds, control->parent->bounds.left, control->parent->bounds.top);
    carbon_SetControlBounds(control, &bounds);
    return noErr;
}

OSStatus carbon_HIViewGetBounds(ControlRef control, HIRect *bounds) CARBON_SYMBOL(HIViewGetBounds);
OSStatus carbon_HIViewGetBounds(ControlRef control, HIRect *bounds) {
    if (!(control = control_from(control)) || !bounds) return paramErr;
    *bounds = (HIRect){0, 0, control->bounds.right - control->bounds.left, control->bounds.bottom - control->bounds.top};
    return noErr;
}

OSStatus carbon_HIViewGetFrame(ControlRef control, HIRect *frame) CARBON_SYMBOL(HIViewGetFrame);
OSStatus carbon_HIViewGetFrame(ControlRef control, HIRect *frame) {
    if (!(control = control_from(control)) || !frame) return paramErr;
    *frame = (HIRect){control->bounds.left, control->bounds.top, control->bounds.right - control->bounds.left,
                      control->bounds.bottom - control->bounds.top};
    return noErr;
}

OSStatus carbon_HIViewSetVisible(ControlRef control, Boolean visible) CARBON_SYMBOL(HIViewSetVisible);
OSStatus carbon_HIViewSetVisible(ControlRef control, Boolean visible) {
    if (!(control = control_from(control))) return paramErr;
    set_hidden(control, !visible);
    return noErr;
}

OSStatus carbon_HIViewSetNeedsDisplay(ControlRef control, Boolean needs) CARBON_SYMBOL(HIViewSetNeedsDisplay);
OSStatus carbon_HIViewSetNeedsDisplay(ControlRef control, Boolean needs) {
    if (!(control = control_from(control))) return paramErr;
    if (control->view && needs) ((void (*)(id, SEL, signed char))objc_send)(control->view, SELECTOR("setNeedsDisplay:"), 1);
    return noErr;
}

OSStatus carbon_HIViewSetBoundsOrigin(ControlRef control, float x, float y) CARBON_SYMBOL(HIViewSetBoundsOrigin);
OSStatus carbon_HIViewSetBoundsOrigin(ControlRef control, float x, float y) {
    (void)x; (void)y;
    return control_from(control) ? noErr : paramErr;
}

/// Adds a view made on its own (HIObjectCreate, HIScrollViewCreate) to a
/// window's: it takes the window's coordinates from its parent.
OSStatus carbon_HIViewAddSubview(ControlRef parent, ControlRef child) CARBON_SYMBOL(HIViewAddSubview);
OSStatus carbon_HIViewAddSubview(ControlRef parent, ControlRef child) {
    if (!(parent = control_from(parent)) || !(child = control_from(child))) return paramErr;
    child->parent = parent;
    child->window = parent->window;
    if (child->view && parent->window) {
        ((void (*)(id, SEL, NSRect))objc_send)(child->view, SELECTOR("setFrame:"), carbon_view_frame(parent->window, &child->bounds));
        SEND1(parent->window->view, "addSubview:", child->view);
    }
    return noErr;
}

/// A view that isn't in a window yet: an empty one of AppKit's.
static ControlRef loose_control(OSType kind) {
    ControlRef control = calloc(1, sizeof *control);
    if (!control) return NULL;
    control->magic = CARBON_CONTROL_MAGIC;
    control->kind = kind;
    control->visible = control->active = true;
    control->view = SEND(SEND(CLASS("NSView"), "alloc"), "init");
    control->target = carbon_target_new(control);
    control->next = controls;
    controls = control;
    return control;
}

OSStatus carbon_HIScrollViewCreate(uint32_t options, ControlRef *out) CARBON_SYMBOL(HIScrollViewCreate);
OSStatus carbon_HIScrollViewCreate(uint32_t options, ControlRef *out) {
    (void)options;
    if (!out) return paramErr;
    *out = loose_control(FOUR('s', 'c', 'r', 'l'));
    return *out ? noErr : memFullErr;
}

/// An image view: its image a CGImage, as the layer's contents.
OSStatus carbon_HIImageViewSetImage(ControlRef control, void *image) CARBON_SYMBOL(HIImageViewSetImage);
OSStatus carbon_HIImageViewSetImage(ControlRef control, void *image) {
    if (!(control = control_from(control)) || !control->view) return paramErr;
    ((void (*)(id, SEL, signed char))objc_send)(control->view, SELECTOR("setWantsLayer:"), 1);
    ((void (*)(id, SEL, void *))objc_send)(SEND(control->view, "layer"), SELECTOR("setContents:"), image);
    return noErr;
}

OSStatus carbon_HIImageViewSetScaleToFit(ControlRef control, Boolean scale) CARBON_SYMBOL(HIImageViewSetScaleToFit);
OSStatus carbon_HIImageViewSetScaleToFit(ControlRef control, Boolean scale) {
    (void)scale;
    return control_from(control) ? noErr : paramErr;
}

// HIObject subclasses: their classes are registered, and an object made of
// one is a view whose event handler is the class's, sent its construction.
typedef struct hi_class {
    id identifier;
    void *handler;
    size_t count;
    void *types;
    void *userData;
    struct hi_class *next;
} hi_class;

static hi_class *hi_classes;

OSStatus carbon_HIObjectRegisterSubclass(id identifier, id base, uint32_t options, void *handler, size_t count, const void *types,
                                         void *userData, void **out) CARBON_SYMBOL(HIObjectRegisterSubclass);
OSStatus carbon_HIObjectRegisterSubclass(id identifier, id base, uint32_t options, void *handler, size_t count, const void *types,
                                         void *userData, void **out) {
    (void)base; (void)options;
    hi_class *class = calloc(1, sizeof *class);
    if (!class) return memFullErr;
    class->identifier = identifier ? SEND(identifier, "copy") : NULL;
    class->handler = handler;
    class->count = count;
    class->types = count ? malloc(count * 8) : NULL;
    if (class->types) memcpy(class->types, types, count * 8);
    class->userData = userData;
    class->next = hi_classes;
    hi_classes = class;
    if (out) *out = class;
    return noErr;
}

OSStatus carbon_HIObjectCreate(id identifier, void *initialization, ControlRef *out) CARBON_SYMBOL(HIObjectCreate);
OSStatus carbon_HIObjectCreate(id identifier, void *initialization, ControlRef *out) {
    (void)initialization;
    if (!out) return paramErr;
    hi_class *class = hi_classes;
    while (class && !((signed char (*)(id, SEL, id))objc_send)(class->identifier, SELECTOR("isEqualToString:"), identifier))
        class = class->next;
    *out = loose_control(FOUR('h', 'i', 'o', 'b'));
    if (!*out) return memFullErr;
    if (class && class->handler)
        install_handler((*out)->target, class->handler, class->count, class->types, class->userData, NULL);
    return noErr;
}
