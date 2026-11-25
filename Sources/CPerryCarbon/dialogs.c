// The original Dialog Manager: dialogs made from 'DLOG' and 'DITL'
// resources, run by ModalDialog, and alerts from 'ALRT' resources. A
// dialog is a window of Carbon's with a control of AppKit's for each item:
// push buttons, static text and edit text (the other kinds, check boxes,
// icons, pictures and user items, take their place and draw nothing). A
// DialogRef is the dialog's WindowRef.
//
// ModalDialog runs the application modally until a button is pressed and
// gives its item; a dialog's filter procedure is not called. Return presses
// the default item's button.

#include "PerryCarbon.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define FOUR(a, b, c, d) ((uint32_t)(a) << 24 | (uint32_t)(b) << 16 | (uint32_t)(c) << 8 | (uint32_t)(d))

// A dialog's buttons send 'DLG' and their item's number.
#define DIALOG_COMMAND 0x444c4700u

enum { ITEM_USER = 0, ITEM_CONTROL = 4, ITEM_BUTTON = 4, ITEM_CHECKBOX = 5, ITEM_RADIO = 6, ITEM_RESOURCE_CONTROL = 7,
       ITEM_STATIC_TEXT = 8, ITEM_EDIT_TEXT = 16, ITEM_ICON = 32, ITEM_PICTURE = 64, ITEM_DISABLED = 128 };

#define DIALOG_ITEM_MAGIC 0x4449544du   // 'DITM'

typedef struct {
    uint32_t magic;
    int16_t type;
    Rect bounds;
    id view;
    ControlRef control;
} dialog_item;

typedef struct carbon_dialog {
    WindowRef window;
    dialog_item *items;
    int count;
    int16_t default_item;
    int16_t hit;
    bool running;
    struct carbon_dialog *next;
} carbon_dialog;

static carbon_dialog *dialogs;

static carbon_dialog *dialog_from(void *pointer) {
    for (carbon_dialog *dialog = dialogs; dialog; dialog = dialog->next)
        if (dialog->window == pointer) return dialog;
    return NULL;
}

static dialog_item *item_from(void *pointer) {
    dialog_item *item = pointer;
    return item && item->magic == DIALOG_ITEM_MAGIC ? item : NULL;
}

Handle carbon_GetResource(OSType type, int16_t identifier) CARBON_SYMBOL(GetResource);
void carbon_DisposeWindow(WindowRef window) CARBON_SYMBOL(DisposeWindow);
OSStatus carbon_RunAppModalLoopForWindow(WindowRef window) CARBON_SYMBOL(RunAppModalLoopForWindow);
OSStatus carbon_QuitAppModalLoopForWindow(WindowRef window) CARBON_SYMBOL(QuitAppModalLoopForWindow);
void carbon_SelectWindow(WindowRef window) CARBON_SYMBOL(SelectWindow);

static long resource_size(Handle resource) {
    static long (*size)(Handle);
    if (!size) size = (long (*)(Handle))carbon_function(CORESERVICES, "_GetHandleSize");
    return resource && size ? size(resource) : 0;
}

static int16_t word(const uint8_t *bytes) { return (int16_t)(bytes[0] << 8 | bytes[1]); }

// MARK: - ParamText

static char parameters[4][256];

/// The text that stands for ^0 to ^3 in dialogs' and alerts' static text.
void carbon_ParamText(ConstStr255Param first, ConstStr255Param second, ConstStr255Param third, ConstStr255Param fourth)
    CARBON_SYMBOL(ParamText);
void carbon_ParamText(ConstStr255Param first, ConstStr255Param second, ConstStr255Param third, ConstStr255Param fourth) {
    ConstStr255Param given[4] = {first, second, third, fourth};
    for (int index = 0; index < 4; index++) {
        const char *text = given[index] ? ((const char *(*)(id, SEL))objc_send)(carbon_pascal_string(given[index]), SELECTOR("UTF8String")) : "";
        snprintf(parameters[index], sizeof parameters[index], "%s", text ? text : "");
    }
}

/// An item's text, from its Mac Roman bytes: an NSString, with returns as
/// new lines and ^0 to ^3 replaced.
static id item_text(const uint8_t *bytes, size_t length) {
    unsigned char pascal[256];
    if (length > 255) length = 255;
    pascal[0] = (unsigned char)length;
    memcpy(pascal + 1, bytes, length);
    const char *utf8 = ((const char *(*)(id, SEL))objc_send)(carbon_pascal_string(pascal), SELECTOR("UTF8String"));
    char text[2048];
    size_t written = 0;
    for (const char *character = utf8 ? utf8 : ""; *character && written + 1 < sizeof text; character++) {
        if (character[0] == '^' && character[1] >= '0' && character[1] <= '3') {
            written += (size_t)snprintf(text + written, sizeof text - written, "%s", parameters[character[1] - '0']);
            if (written >= sizeof text) written = sizeof text - 1;
            character++;
        } else {
            text[written++] = *character == '\r' ? '\n' : *character;
        }
    }
    text[written] = '\0';
    return carbon_string(text);
}

// MARK: - Item lists

typedef struct {
    int16_t type;
    Rect bounds;
    const uint8_t *data;
    size_t length;
} parsed_item;

/// A 'DITL': the count less one, then for each item four bytes kept for a
/// handle, its rectangle, its type and its data, a length byte before it
/// and padded to an even length.
static int parse_items(Handle list, parsed_item *out, int capacity) {
    long size = resource_size(list);
    if (!list || !*list || size < 2) return 0;
    const uint8_t *bytes = (const uint8_t *)*list, *end = bytes + size;
    int count = word(bytes) + 1, parsed = 0;
    const uint8_t *next = bytes + 2;
    while (parsed < count && parsed < capacity && next + 14 <= end) {
        parsed_item *item = &out[parsed];
        item->bounds = (Rect){word(next + 4), word(next + 6), word(next + 8), word(next + 10)};
        item->type = next[12];
        item->length = next[13];
        item->data = next + 14;
        if (item->data + item->length > end) break;
        next = item->data + item->length + (item->length & 1);
        parsed++;
    }
    return parsed;
}

// MARK: - Dialogs

/// DialogRef GetNewDialog(SInt16 dialogID, void *storage, WindowRef
/// behind): the dialog of that 'DLOG' and its 'DITL', NULL if there is none.
WindowRef carbon_GetNewDialog(int16_t identifier, void *storage, WindowRef behind) CARBON_SYMBOL(GetNewDialog);
WindowRef carbon_GetNewDialog(int16_t identifier, void *storage, WindowRef behind) {
    (void)storage; (void)behind;
    Handle resource = carbon_GetResource(FOUR('D', 'L', 'O', 'G'), identifier);
    if (!resource || !*resource || resource_size(resource) < 21) {
        CARBON_TRACE("dialog %d: no DLOG", identifier);
        return NULL;
    }
    // bounds, procID, visible, goAway, refCon, the item list's ID, the title.
    const uint8_t *bytes = (const uint8_t *)*resource;
    Rect bounds = {word(bytes), word(bytes + 2), word(bytes + 4), word(bytes + 6)};
    bool visible = bytes[10] != 0;
    int16_t list = word(bytes + 18);
    parsed_item parsed[64];
    int count = parse_items(carbon_GetResource(FOUR('D', 'I', 'T', 'L'), list), parsed, 64);
    carbon_application();
    WindowRef window = NULL;
    // kMovableModalWindowClass (4), at the middle of the screen: the
    // resource's place is on the screen it was laid out for.
    if (carbon_CreateNewWindow(4, 0, &bounds, &window) != noErr || !window) return NULL;
    carbon_SetWindowTitleWithCFString(window, carbon_pascal_string(bytes + 20));
    carbon_RepositionWindow(window, NULL, 1);
    carbon_dialog *dialog = calloc(1, sizeof *dialog);
    dialog_item *items = calloc((size_t)(count > 0 ? count : 1), sizeof *items);
    if (!dialog || !items) {
        free(dialog); free(items);
        carbon_DisposeWindow(window);
        return NULL;
    }
    dialog->window = window;
    dialog->items = items;
    dialog->count = count;
    dialog->default_item = 1;
    dialog->next = dialogs;
    dialogs = dialog;
    id first_field = NULL;
    for (int index = 0; index < count; index++) {
        dialog_item *item = &items[index];
        item->magic = DIALOG_ITEM_MAGIC;
        item->type = parsed[index].type;
        item->bounds = parsed[index].bounds;
        id text = item_text(parsed[index].data, parsed[index].length);
        switch (item->type & 0x7f) {
        case ITEM_BUTTON:
            item->view = carbon_button_view(text, DIALOG_COMMAND | (uint32_t)(index + 1), window, index == 0 ? 1 : 0);
            item->control = carbon_control_new(window, NULL, item->view, &item->bounds, FOUR('b', 'u', 't', 'n'));
            break;
        case ITEM_STATIC_TEXT: {
            // Static text fills its rectangle's lines, in the small font a
            // dialog's twelve-point text is nearest to here.
            item->view = SEND(SEND1(CLASS("NSTextField"), "wrappingLabelWithString:", text), "retain");
            id font = ((id (*)(id, SEL, CGFloat))objc_send)(CLASS("NSFont"), SELECTOR("systemFontOfSize:"), 11);
            if (font) SEND1(item->view, "setFont:", font);
            item->control = carbon_control_new(window, NULL, item->view, &item->bounds, FOUR('s', 't', 'x', 't'));
            break;
        }
        case ITEM_EDIT_TEXT: {
            // The item's rectangle is its text's: the field's frame is
            // three pixels outside it.
            Rect frame = {(int16_t)(item->bounds.top - 3), (int16_t)(item->bounds.left - 3), (int16_t)(item->bounds.bottom + 3),
                          (int16_t)(item->bounds.right + 3)};
            item->view = SEND(SEND(CLASS("NSTextField"), "alloc"), "init");
            SEND1(item->view, "setStringValue:", text);
            item->control = carbon_control_new(window, NULL, item->view, &frame, FOUR('e', 't', 'x', 't'));
            if (!first_field) first_field = item->view;
            break;
        }
        default:
            break;
        }
    }
    if (first_field) SEND1(window->nswindow, "makeFirstResponder:", first_field);
    CARBON_TRACE("dialog %d: %d items, %d×%d", identifier, count, bounds.right - bounds.left, bounds.bottom - bounds.top);
    if (visible) carbon_ShowWindow(window);
    return window;
}

void carbon_DisposeDialog(WindowRef dialog) CARBON_SYMBOL(DisposeDialog);
void carbon_DisposeDialog(WindowRef dialog) {
    for (carbon_dialog **link = &dialogs; *link; link = &(*link)->next) {
        if ((*link)->window != dialog) continue;
        carbon_dialog *found = *link;
        *link = found->next;
        for (int index = 0; index < found->count; index++) found->items[index].magic = 0;
        free(found->items);
        free(found);
        break;
    }
    carbon_DisposeWindow(dialog);
}

void carbon_SetPortDialogPort(WindowRef dialog) CARBON_SYMBOL(SetPortDialogPort);
void carbon_SetPortDialogPort(WindowRef dialog) {
    if ((dialog = carbon_window_from(dialog)) && dialog->port) carbon_SetPort((CGrafPtr)dialog->port);
}

/// The item Return presses.
OSErr carbon_SetDialogDefaultItem(WindowRef dialog, int16_t number) CARBON_SYMBOL(SetDialogDefaultItem);
OSErr carbon_SetDialogDefaultItem(WindowRef dialog, int16_t number) {
    carbon_dialog *found = dialog_from(dialog);
    if (!found) return paramErr;
    for (int index = 0; index < found->count; index++) {
        dialog_item *item = &found->items[index];
        if ((item->type & 0x7f) != ITEM_BUTTON || !item->view) continue;
        SEND1(item->view, "setKeyEquivalent:", carbon_string(index + 1 == number ? "\r" : ""));
    }
    found->default_item = number;
    return noErr;
}

OSErr carbon_SetDialogCancelItem(WindowRef dialog, int16_t number) CARBON_SYMBOL(SetDialogCancelItem);
OSErr carbon_SetDialogCancelItem(WindowRef dialog, int16_t number) {
    carbon_dialog *found = dialog_from(dialog);
    if (!found || number < 1 || number > found->count) return paramErr;
    dialog_item *item = &found->items[number - 1];
    if ((item->type & 0x7f) == ITEM_BUTTON && item->view) SEND1(item->view, "setKeyEquivalent:", carbon_string("\x1b"));
    return noErr;
}

/// void GetDialogItem(DialogRef, DialogItemIndex, DialogItemType *, Handle
/// *item, Rect *box): the item's handle is what GetDialogItemText and
/// SetDialogItemText take.
void carbon_GetDialogItem(WindowRef dialog, int16_t number, int16_t *type, Handle *item, Rect *box) CARBON_SYMBOL(GetDialogItem);
void carbon_GetDialogItem(WindowRef dialog, int16_t number, int16_t *type, Handle *item, Rect *box) {
    carbon_dialog *found = dialog_from(dialog);
    if (type) *type = 0;
    if (item) *item = NULL;
    if (box) *box = (Rect){0, 0, 0, 0};
    if (!found || number < 1 || number > found->count) return;
    dialog_item *entry = &found->items[number - 1];
    if (type) *type = entry->type;
    if (item) *item = (Handle)entry;
    if (box) *box = entry->bounds;
}

OSErr carbon_GetDialogItemAsControl(WindowRef dialog, int16_t number, ControlRef *control) CARBON_SYMBOL(GetDialogItemAsControl);
OSErr carbon_GetDialogItemAsControl(WindowRef dialog, int16_t number, ControlRef *control) {
    carbon_dialog *found = dialog_from(dialog);
    if (!found || number < 1 || number > found->count || !control) return paramErr;
    *control = found->items[number - 1].control;
    return *control ? noErr : paramErr;
}

int16_t carbon_CountDITL(WindowRef dialog) CARBON_SYMBOL(CountDITL);
int16_t carbon_CountDITL(WindowRef dialog) {
    carbon_dialog *found = dialog_from(dialog);
    return found ? (int16_t)found->count : 0;
}

/// An item's text, as a Pascal string of Mac Roman: characters outside
/// ASCII are question marks.
void carbon_GetDialogItemText(Handle item, Str255 text) CARBON_SYMBOL(GetDialogItemText);
void carbon_GetDialogItemText(Handle item, Str255 text) {
    if (!text) return;
    text[0] = 0;
    dialog_item *entry = item_from(item);
    if (!entry || !entry->view) return;
    const char *utf8 = ((const char *(*)(id, SEL))objc_send)(SEND(entry->view, "stringValue"), SELECTOR("UTF8String"));
    size_t length = 0;
    for (const unsigned char *character = (const unsigned char *)(utf8 ? utf8 : ""); *character && length < 255; character++) {
        if (*character < 0x80) text[++length] = *character == '\n' ? '\r' : *character;
        else if ((*character & 0xc0) != 0x80) text[++length] = '?';
    }
    text[0] = (unsigned char)length;
}

void carbon_SetDialogItemText(Handle item, ConstStr255Param text) CARBON_SYMBOL(SetDialogItemText);
void carbon_SetDialogItemText(Handle item, ConstStr255Param text) {
    dialog_item *entry = item_from(item);
    if (!entry || !entry->view || !text) return;
    SEND1(entry->view, "setStringValue:", item_text(text + 1, text[0]));
}

/// Selects an edit text item's text: the item is given the keyboard.
void carbon_SelectDialogItemText(WindowRef dialog, int16_t number, int16_t start, int16_t end) CARBON_SYMBOL(SelectDialogItemText);
void carbon_SelectDialogItemText(WindowRef dialog, int16_t number, int16_t start, int16_t end) {
    (void)start; (void)end;
    carbon_dialog *found = dialog_from(dialog);
    if (!found || number < 1 || number > found->count) return;
    dialog_item *item = &found->items[number - 1];
    if ((item->type & 0x7f) == ITEM_EDIT_TEXT && item->view) SEND1(found->window->nswindow, "makeFirstResponder:", item->view);
}

/// The dialog's TextEdit record: one that holds nothing, as its fields are
/// AppKit's.
Handle carbon_GetDialogTextEditHandle(WindowRef dialog) CARBON_SYMBOL(GetDialogTextEditHandle);
Handle carbon_GetDialogTextEditHandle(WindowRef dialog) {
    (void)dialog;
    static char record[256];
    static char *pointer = record;
    return &pointer;
}

/// A dialog's button was pressed: ModalDialog's loop ends with its item.
bool carbon_dialog_command(uint32_t command) {
    if ((command & 0xffffff00u) != DIALOG_COMMAND) return false;
    for (carbon_dialog *dialog = dialogs; dialog; dialog = dialog->next) {
        if (!dialog->running) continue;
        dialog->hit = (int16_t)(command & 0xff);
        carbon_QuitAppModalLoopForWindow(dialog->window);
        break;
    }
    return true;
}

/// void ModalDialog(ModalFilterUPP, DialogItemIndex *itemHit): runs the
/// front dialog until one of its buttons is pressed.
void carbon_ModalDialog(void *filter, int16_t *hit) CARBON_SYMBOL(ModalDialog);
void carbon_ModalDialog(void *filter, int16_t *hit) {
    (void)filter;
    // The newest dialog is the front one.
    carbon_dialog *dialog = dialogs;
    if (hit) *hit = 0;
    if (!dialog) return;
    if (!dialog->window->visible) carbon_ShowWindow(dialog->window);
    carbon_SelectWindow(dialog->window);
    dialog->hit = 0;
    dialog->running = true;
    carbon_RunAppModalLoopForWindow(dialog->window);
    dialog->running = false;
    CARBON_TRACE("dialog: item %d", dialog->hit);
    if (hit) *hit = dialog->hit;
}

// MARK: - Alerts

/// An alert from its 'ALRT' and the 'DITL' it names: the static text is
/// the alert's message and explanation, the buttons its buttons, the first
/// the default; the button pressed is its item's number.
static int16_t run_alert(int16_t identifier, unsigned long style) {
    Handle resource = carbon_GetResource(FOUR('A', 'L', 'R', 'T'), identifier);
    if (!resource || !*resource || resource_size(resource) < 10) {
        CARBON_TRACE("alert %d: no ALRT", identifier);
        return -1;
    }
    parsed_item parsed[32];
    int count = parse_items(carbon_GetResource(FOUR('D', 'I', 'T', 'L'), word((const uint8_t *)*resource + 8)), parsed, 32);
    carbon_application();
    id alert = SEND(SEND(CLASS("NSAlert"), "alloc"), "init");
    ((void (*)(id, SEL, unsigned long))objc_send)(alert, SELECTOR("setAlertStyle:"), style);
    int16_t buttons[8];
    int button_count = 0, texts = 0;
    char explanation[4096] = "";
    const char *message = "";
    for (int index = 0; index < count; index++) {
        id text = item_text(parsed[index].data, parsed[index].length);
        int kind = parsed[index].type & 0x7f;
        if (kind == ITEM_BUTTON && button_count < 8) {
            SEND1(alert, "addButtonWithTitle:", text);
            buttons[button_count++] = (int16_t)(index + 1);
        } else if (kind == ITEM_STATIC_TEXT) {
            const char *utf8 = ((const char *(*)(id, SEL))objc_send)(text, SELECTOR("UTF8String"));
            if (texts++ == 0) {
                SEND1(alert, "setMessageText:", text);
                message = utf8 ? utf8 : "";
            } else {
                size_t length = strlen(explanation);
                snprintf(explanation + length, sizeof explanation - length, "%s%s", length ? "\n" : "", utf8 ? utf8 : "");
            }
        }
    }
    if (explanation[0]) SEND1(alert, "setInformativeText:", carbon_string(explanation));
    if (button_count == 0) {
        SEND1(alert, "addButtonWithTitle:", carbon_string("OK"));
        buttons[button_count++] = 1;
    }
    carbon_warn("alert: %s%s%s", message, explanation[0] ? " — " : "", explanation);
    long response = ((long (*)(id, SEL))objc_send)(alert, SELECTOR("runModal"));
    SEND(alert, "release");
    long index = response - 1000;   // NSAlertFirstButtonReturn
    return index >= 0 && index < button_count ? buttons[index] : buttons[0];
}

int16_t carbon_Alert(int16_t identifier, void *filter) CARBON_SYMBOL(Alert);
int16_t carbon_Alert(int16_t identifier, void *filter) { (void)filter; return run_alert(identifier, 1); }

int16_t carbon_StopAlert(int16_t identifier, void *filter) CARBON_SYMBOL(StopAlert);
int16_t carbon_StopAlert(int16_t identifier, void *filter) { (void)filter; return run_alert(identifier, 2); }

int16_t carbon_NoteAlert(int16_t identifier, void *filter) CARBON_SYMBOL(NoteAlert);
int16_t carbon_NoteAlert(int16_t identifier, void *filter) { (void)filter; return run_alert(identifier, 1); }

int16_t carbon_CautionAlert(int16_t identifier, void *filter) CARBON_SYMBOL(CautionAlert);
int16_t carbon_CautionAlert(int16_t identifier, void *filter) { (void)filter; return run_alert(identifier, 0); }
