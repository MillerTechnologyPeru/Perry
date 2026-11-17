// Interface Builder's Carbon nibs: a nib's objects.xib (IBCarbonFramework's
// XML), parsed whole, its windows made with their controls, hidden, and its
// menus with their items, by the names in its name table. The nib is the
// bundle's localized one, as CFBundle finds it.

#include "PerryCarbon.h"

#include <ctype.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define FOUR(a, b, c, d) ((uint32_t)(a) << 24 | (uint32_t)(b) << 16 | (uint32_t)(c) << 8 | (uint32_t)(d))

// MARK: - XML

typedef struct xml_node {
    char *tag;
    char *name, *class, *identifier, *reference, *value;
    char *text;
    struct xml_node *children, *next, *parent;
} xml_node;

static void xml_free(xml_node *node) {
    while (node) {
        xml_node *next = node->next;
        xml_free(node->children);
        free(node->tag); free(node->name); free(node->class); free(node->identifier);
        free(node->reference); free(node->value); free(node->text);
        free(node);
        node = next;
    }
}

/// Text with its entities as their characters.
static char *xml_text(const char *start, size_t length) {
    char *out = malloc(length + 1);
    if (!out) return NULL;
    size_t used = 0;
    for (size_t index = 0; index < length; index++) {
        if (start[index] != '&') {
            out[used++] = start[index];
            continue;
        }
        const char *entity = start + index + 1;
        const char *end = memchr(entity, ';', length - index - 1);
        if (!end) {
            out[used++] = '&';
            continue;
        }
        size_t size = (size_t)(end - entity);
        uint32_t code = 0;
        if (size == 3 && !strncmp(entity, "amp", 3)) code = '&';
        else if (size == 2 && !strncmp(entity, "lt", 2)) code = '<';
        else if (size == 2 && !strncmp(entity, "gt", 2)) code = '>';
        else if (size == 4 && !strncmp(entity, "quot", 4)) code = '"';
        else if (size == 4 && !strncmp(entity, "apos", 4)) code = '\'';
        else if (entity[0] == '#') code = (uint32_t)strtoul(entity + 1 + (entity[1] == 'x'), NULL, entity[1] == 'x' ? 16 : 10);
        if (!code) {
            out[used++] = '&';
            continue;
        }
        // As UTF-8.
        if (code < 0x80) out[used++] = (char)code;
        else if (code < 0x800) { out[used++] = (char)(0xc0 | code >> 6); out[used++] = (char)(0x80 | (code & 0x3f)); }
        else { out[used++] = (char)(0xe0 | code >> 12); out[used++] = (char)(0x80 | ((code >> 6) & 0x3f)); out[used++] = (char)(0x80 | (code & 0x3f)); }
        index += size + 1;
    }
    out[used] = 0;
    return out;
}

static char *attribute(const char *tag, size_t length, const char *name) {
    size_t name_length = strlen(name);
    for (const char *cursor = tag; cursor + name_length + 2 < tag + length; cursor++) {
        if (strncmp(cursor, name, name_length) != 0 || cursor[name_length] != '=' || !isspace((unsigned char)cursor[-1])) continue;
        char quote = cursor[name_length + 1];
        const char *value = cursor + name_length + 2;
        const char *end = memchr(value, quote, (size_t)(tag + length - value));
        return end ? xml_text(value, (size_t)(end - value)) : NULL;
    }
    return NULL;
}

/// The document's elements, as a tree.
static xml_node *xml_parse(const char *text) {
    xml_node *root = calloc(1, sizeof *root), *open = root;
    xml_node **last = &root->children;
    const char *cursor = text;
    while (open && (cursor = strchr(cursor, '<'))) {
        if (cursor[1] == '?' || cursor[1] == '!') {
            cursor = strchr(cursor, '>');
            if (!cursor) break;
            cursor++;
            continue;
        }
        const char *end = strchr(cursor, '>');
        if (!end) break;
        if (cursor[1] == '/') {
            // Its text, up to here, then the element ends.
            if (open != root) {
                open = open->parent;
                last = &open->children;
                while (*last) last = &(*last)->next;
            }
            cursor = end + 1;
            continue;
        }
        xml_node *node = calloc(1, sizeof *node);
        if (!node) break;
        const char *tag_end = cursor + 1;
        while (tag_end < end && !isspace((unsigned char)*tag_end) && *tag_end != '/') tag_end++;
        node->tag = xml_text(cursor + 1, (size_t)(tag_end - cursor - 1));
        size_t length = (size_t)(end - cursor);
        node->name = attribute(cursor, length, "name");
        node->class = attribute(cursor, length, "class");
        node->identifier = attribute(cursor, length, "id");
        node->reference = attribute(cursor, length, "idRef");
        node->value = attribute(cursor, length, "value");
        node->parent = open;
        *last = node;
        bool empty = end[-1] == '/';
        cursor = end + 1;
        if (empty) {
            last = &node->next;
            continue;
        }
        // Text up to the next tag is the element's.
        const char *next = strchr(cursor, '<');
        if (next && next[1] == '/') node->text = xml_text(cursor, (size_t)(next - cursor));
        open = node;
        last = &node->children;
    }
    return root;
}

static xml_node *child(xml_node *node, const char *name) {
    for (xml_node *each = node ? node->children : NULL; each; each = each->next)
        if (each->name && strcmp(each->name, name) == 0) return each;
    return NULL;
}

static const char *string_of(xml_node *node, const char *name) {
    xml_node *found = child(node, name);
    return found && found->text ? found->text : NULL;
}

static long int_of(xml_node *node, const char *name, long fallback) {
    const char *text = string_of(node, name);
    return text ? strtol(text, NULL, 10) : fallback;
}

static bool bool_of(xml_node *node, const char *name, bool fallback) {
    const char *text = string_of(node, name);
    if (!text) {
        xml_node *found = child(node, name);
        text = found ? found->value : NULL;
    }
    return text ? (strcmp(text, "TRUE") == 0 || strcmp(text, "YES") == 0 || strcmp(text, "1") == 0) : fallback;
}

static OSType ostype_of(xml_node *node, const char *name) {
    const char *text = string_of(node, name);
    if (!text) return 0;
    char code[4] = {' ', ' ', ' ', ' '};
    for (int index = 0; index < 4 && text[index]; index++) code[index] = text[index];
    return FOUR(code[0], code[1], code[2], code[3]);
}

/// "top left bottom right".
static bool rect_of(xml_node *node, const char *name, Rect *rect) {
    const char *text = string_of(node, name);
    int top, left, bottom, right;
    if (!text || sscanf(text, "%d %d %d %d", &top, &left, &bottom, &right) != 4) return false;
    *rect = (Rect){(int16_t)top, (int16_t)left, (int16_t)bottom, (int16_t)right};
    return true;
}

// MARK: - Nibs

typedef struct {
    uint32_t magic;
    xml_node *document;
    xml_node *data;   // the NSIBObjectData
} carbon_nib;

#define CARBON_NIB_MAGIC 0x4e494242u   // 'NIBB'

static carbon_nib *nib_from(void *pointer) {
    carbon_nib *nib = pointer;
    return nib && nib->magic == CARBON_NIB_MAGIC ? nib : NULL;
}

static const char *utf8(id string) { return string ? ((const char *(*)(id, SEL))objc_send)(string, SELECTOR("UTF8String")) : NULL; }

static char *read_text(const char *path) {
    FILE *file = fopen(path, "rb");
    if (!file) return NULL;
    fseek(file, 0, SEEK_END);
    long size = ftell(file);
    fseek(file, 0, SEEK_SET);
    char *text = size > 0 ? malloc((size_t)size + 1) : NULL;
    if (text && fread(text, 1, (size_t)size, file) == (size_t)size) text[size] = 0;
    else {
        free(text);
        text = NULL;
    }
    fclose(file);
    return text;
}

static OSStatus open_nib(id bundle, id name, carbon_nib **out) {
    if (!out || !name) return paramErr;
    *out = NULL;
    id path = ((id (*)(id, SEL, id, id))objc_send)(bundle, SELECTOR("pathForResource:ofType:"), name, carbon_string("nib"));
    if (!path) {
        CARBON_TRACE("nib %s isn't there", utf8(name));
        return -2450;   // kIBCarbonRuntimeCantFindNibFile
    }
    char file[4096];
    snprintf(file, sizeof file, "%s/objects.xib", utf8(path));
    char *text = read_text(file);
    if (!text) return -2450;
    xml_node *document = xml_parse(text);
    free(text);
    xml_node *data = document ? document->children : NULL;
    while (data && !(data->class && strcmp(data->class, "NSIBObjectData") == 0)) data = data->next;
    if (!data) {
        xml_free(document);
        return -2451;   // kIBCarbonRuntimeObjectNotOfRequestedType
    }
    carbon_nib *nib = calloc(1, sizeof *nib);
    if (!nib) {
        xml_free(document);
        return memFullErr;
    }
    nib->magic = CARBON_NIB_MAGIC;
    nib->document = document;
    nib->data = data;
    *out = nib;
    CARBON_TRACE("nib %s", file);
    return noErr;
}

OSStatus carbon_CreateNibReference(id name, carbon_nib **out) CARBON_SYMBOL(CreateNibReference);
OSStatus carbon_CreateNibReference(id name, carbon_nib **out) { return open_nib(SEND(CLASS("NSBundle"), "mainBundle"), name, out); }

/// A bundle's nib: a CFBundle is an NSBundle here.
OSStatus carbon_CreateNibReferenceWithCFBundle(id bundle, id name, carbon_nib **out) CARBON_SYMBOL(CreateNibReferenceWithCFBundle);
OSStatus carbon_CreateNibReferenceWithCFBundle(id bundle, id name, carbon_nib **out) {
    return open_nib(bundle ? bundle : SEND(CLASS("NSBundle"), "mainBundle"), name, out);
}

void carbon_DisposeNibReference(carbon_nib *nib) CARBON_SYMBOL(DisposeNibReference);
void carbon_DisposeNibReference(carbon_nib *nib) {
    if (!(nib = nib_from(nib))) return;
    xml_free(nib->document);
    nib->magic = 0;
    free(nib);
}

/// The object a name in the name table stands for.
static xml_node *named(carbon_nib *nib, id name) {
    const char *wanted = utf8(name);
    xml_node *table = child(nib->data, "nameTable");
    if (!wanted || !table) return NULL;
    const char *identifier = NULL;
    for (xml_node *entry = table->children; entry; entry = entry->next)
        if (entry->tag && strcmp(entry->tag, "string") == 0 && entry->text && strcmp(entry->text, wanted) == 0 && entry->next) {
            identifier = entry->next->reference ? entry->next->reference : entry->next->identifier;
            break;
        }
    if (!identifier) return NULL;
    // Anywhere in the document: objects are inside their parents.
    xml_node *stack[256];
    int depth = 0;
    stack[depth++] = nib->data;
    while (depth > 0) {
        xml_node *node = stack[--depth];
        if (node->identifier && strcmp(node->identifier, identifier) == 0 && node->class) return node;
        for (xml_node *each = node->children; each; each = each->next)
            if (depth < 256) stack[depth++] = each;
    }
    return NULL;
}

// MARK: - Windows

static id string_object(const char *text) { return text ? carbon_string(text) : NULL; }

/// A control's ID, if it has one.
static void identify(ControlRef control, xml_node *node) {
    OSType signature = ostype_of(node, "controlSignature");
    long identifier = int_of(node, "controlID", 0);
    if (signature || identifier) carbon_control_set_id(control, signature, (int32_t)identifier);
}

static void make_controls(WindowRef window, xml_node *root) {
    xml_node *subviews = child(root, "subviews");
    for (xml_node *node = subviews ? subviews->children : NULL; node; node = node->next) {
        if (!node->class) continue;
        Rect bounds;
        if (!rect_of(node, "bounds", &bounds)) continue;
        const char *title = string_of(node, "title");
        ControlRef control = NULL;
        if (strcmp(node->class, "IBCarbonButton") == 0) {
            uint32_t command = ostype_of(node, "command");
            id view = carbon_button_view(string_object(title), command, window, (int)int_of(node, "buttonType", 0));
            control = carbon_control_new(window, NULL, view, &bounds, FOUR('b', 'u', 't', 'n'));
            extern void set_command(ControlRef, uint32_t) __asm__("_SetControlCommandID");
            if (control) set_command(control, command);
        } else if (strcmp(node->class, "IBCarbonStaticText") == 0 || strcmp(node->class, "IBCarbonEditText") == 0) {
            id view = carbon_label_view(string_object(title), bool_of(node, "small", false));
            control = carbon_control_new(window, NULL, view, &bounds, FOUR('s', 't', 'x', 't'));
        } else {
            // Images, icons, panes: an empty view where they are.
            id view = SEND(SEND(CLASS("NSView"), "alloc"), "init");
            control = carbon_control_new(window, NULL, view, &bounds, ostype_of(node, "controlSignature"));
        }
        if (control) identify(control, node);
    }
}

OSStatus carbon_CreateWindowFromNib(carbon_nib *nib, id name, WindowRef *out) CARBON_SYMBOL(CreateWindowFromNib);
OSStatus carbon_CreateWindowFromNib(carbon_nib *nib, id name, WindowRef *out) {
    if (!(nib = nib_from(nib)) || !out) return paramErr;
    xml_node *node = named(nib, name);
    if (!node || strcmp(node->class, "IBCarbonWindow") != 0) return -2452;   // kIBCarbonRuntimeCantFindObject
    Rect bounds;
    if (!rect_of(node, "windowRect", &bounds)) bounds = (Rect){100, 100, 400, 500};
    uint32_t attributes = 0;
    if (bool_of(node, "hasCloseBox", true)) attributes |= 1;
    if (bool_of(node, "hasHorizontalZoom", false)) attributes |= 2;
    if (bool_of(node, "hasVerticalZoom", false)) attributes |= 4;
    if (bool_of(node, "hasCollapseBox", false)) attributes |= 8;
    if (bool_of(node, "isResizable", false)) attributes |= 16;
    uint32_t windowClass = (uint32_t)int_of(node, "carbonWindowClass", 6);
    OSStatus status = carbon_CreateNewWindow(windowClass, attributes, &bounds, out);
    if (status) return status;
    const char *title = string_of(node, "title");
    if (title) carbon_SetWindowTitleWithCFString(*out, carbon_string(title));
    xml_node *root = child(node, "rootControl");
    if (root) make_controls(*out, root);
    long position = int_of(node, "windowPosition", 0);
    if (position) carbon_RepositionWindow(*out, NULL, (uint32_t)position);
    return noErr;
}

// MARK: - Menus

static MenuRef make_menu(xml_node *node) {
    MenuRef menu = carbon_menu_new((int16_t)int_of(node, "menuID", 0), string_object(string_of(node, "title")));
    xml_node *items = child(node, "items");
    for (xml_node *item = items ? items->children : NULL; item; item = item->next) {
        if (!item->class || strcmp(item->class, "IBCarbonMenuItem") != 0) continue;
        if (bool_of(item, "isSeparator", false)) {
            carbon_menu_add(menu, NULL, 0, NULL, 0);
            continue;
        }
        const char *key = string_of(item, "keyEquivalent");
        char lower[8] = "";
        if (key) {
            snprintf(lower, sizeof lower, "%s", key);
            for (char *c = lower; *c; c++) *c = (char)tolower((unsigned char)*c);
        }
        id object = carbon_menu_add(menu, string_object(string_of(item, "title") ? string_of(item, "title") : ""),
                                    ostype_of(item, "command"), key ? lower : NULL, (uint32_t)int_of(item, "keyEquivalentModifier", 0));
        xml_node *submenu = child(item, "submenu");
        if (submenu && submenu->class && strcmp(submenu->class, "IBCarbonMenu") == 0)
            carbon_menu_set_submenu(menu, object, make_menu(submenu));
    }
    // The application menu ends with Quit, as Carbon's.
    const char *name = string_of(node, "name");
    if (name && strcmp(name, "_NSAppleMenu") == 0) {
        carbon_menu_add(menu, NULL, 0, NULL, 0);
        id bundle = SEND(CLASS("NSBundle"), "mainBundle");
        id info = SEND(bundle, "infoDictionary");
        id app = info ? SEND1(info, "objectForKey:", carbon_string("CFBundleName")) : NULL;
        char title[256];
        snprintf(title, sizeof title, "Quit %s", app ? utf8(app) : "");
        carbon_menu_add(menu, carbon_string(title), FOUR('q', 'u', 'i', 't'), "q", 0);
    }
    return menu;
}

OSStatus carbon_SetMenuBarFromNib(carbon_nib *nib, id name) CARBON_SYMBOL(SetMenuBarFromNib);
OSStatus carbon_SetMenuBarFromNib(carbon_nib *nib, id name) {
    if (!(nib = nib_from(nib))) return paramErr;
    xml_node *node = named(nib, name);
    if (!node || strcmp(node->class, "IBCarbonMenu") != 0) return -2452;
    carbon_menu_bar_set(make_menu(node));
    return noErr;
}

OSStatus carbon_CreateMenuFromNib(carbon_nib *nib, id name, MenuRef *out) CARBON_SYMBOL(CreateMenuFromNib);
OSStatus carbon_CreateMenuFromNib(carbon_nib *nib, id name, MenuRef *out) {
    if (!(nib = nib_from(nib)) || !out) return paramErr;
    xml_node *node = named(nib, name);
    if (!node || strcmp(node->class, "IBCarbonMenu") != 0) return -2452;
    *out = make_menu(node);
    return noErr;
}
