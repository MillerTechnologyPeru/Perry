// The Menu Manager over AppKit's menus: a Carbon menu is an NSMenu, its
// items NSMenuItems whose action sends their command as Carbon does. The
// menu bar is the application's main menu; the application menu
// (_NSAppleMenu) gets Quit at its end, as Carbon's does.

#include "PerryCarbon.h"

#include <stdlib.h>
#include <string.h>

#define FOUR(a, b, c, d) ((uint32_t)(a) << 24 | (uint32_t)(b) << 16 | (uint32_t)(c) << 8 | (uint32_t)(d))

typedef struct menu_item {
    id item;
    uint32_t command;
    bool enabled;
} menu_item;

typedef struct carbon_menu {
    uint32_t magic;
    id menu;
    int16_t identifier;
    menu_item *items;
    size_t count;
    bool plain;   // a pop-up button's: its items choose, they don't send commands
    struct carbon_menu *next;
} carbon_menu;

#define CARBON_MENU_MAGIC 0x4d454e55u   // 'MENU'

static MenuRef menus;

static MenuRef menu_from(void *pointer) {
    MenuRef menu = pointer;
    return menu && menu->magic == CARBON_MENU_MAGIC ? menu : NULL;
}

MenuRef carbon_menu_new(int16_t identifier, id title) {
    MenuRef menu = calloc(1, sizeof *menu);
    if (!menu) return NULL;
    menu->magic = CARBON_MENU_MAGIC;
    menu->identifier = identifier;
    menu->menu = SEND1(SEND(CLASS("NSMenu"), "alloc"), "initWithTitle:", title ? title : carbon_string(""));
    menu->next = menus;
    menus = menu;
    return menu;
}

/// An item: its title, its command and its key, with Command unless the
/// modifiers say kMenuNoCommandModifier (8).
id carbon_menu_add(MenuRef menu, id title, uint32_t command, const char *key, uint32_t modifiers) {
    if (!(menu = menu_from(menu))) return NULL;
    menu_item *grown = realloc(menu->items, (menu->count + 1) * sizeof *grown);
    if (!grown) return NULL;
    menu->items = grown;
    bool separator = !title;
    id item;
    if (separator) {
        item = SEND(CLASS("NSMenuItem"), "separatorItem");
    } else {
        item = SEND(CLASS("NSMenuItem"), "alloc");
        item = ((id (*)(id, SEL, id, SEL, id))objc_send)(item, SELECTOR("initWithTitle:action:keyEquivalent:"), title,
                                                         menu->plain ? NULL : SELECTOR("perryCarbonPerform:"),
                                                         carbon_string(key && !(modifiers & 8) ? key : ""));
        if (!menu->plain) SEND1(item, "setTarget:", carbon_action_target());
        unsigned long mask = 1ul << 20;   // NSEventModifierFlagCommand
        if (modifiers & 1) mask |= 1ul << 17;   // kMenuShiftModifier
        if (modifiers & 2) mask |= 1ul << 19;   // kMenuOptionModifier
        if (modifiers & 4) mask |= 1ul << 18;   // kMenuControlModifier
        ((void (*)(id, SEL, unsigned long))objc_send)(item, SELECTOR("setKeyEquivalentModifierMask:"), mask);
    }
    SEND1(menu->menu, "addItem:", item);
    menu->items[menu->count] = (menu_item){item, command, true};
    menu->count++;
    if (!separator && !menu->plain) carbon_action_register(item, command, NULL, menu, (uint16_t)menu->count);
    return item;
}

void carbon_menu_set_plain(MenuRef menu) { if ((menu = menu_from(menu))) menu->plain = true; }

void carbon_menu_set_submenu(MenuRef menu, id item, MenuRef submenu) {
    if (!(menu = menu_from(menu)) || !(submenu = menu_from(submenu)) || !item) return;
    SEND1(item, "setSubmenu:", submenu->menu);
}

id carbon_menu_object(MenuRef menu) { return (menu = menu_from(menu)) ? menu->menu : NULL; }

static MenuRef menu_bar;

/// The menu bar: each of its items' submenus a menu of the bar.
void carbon_menu_bar_set(MenuRef bar) {
    if (!(bar = menu_from(bar))) return;
    menu_bar = bar;
    SEND1(carbon_application(), "setMainMenu:", bar->menu);
}

MenuRef carbon_GetMenuHandle(int16_t identifier) CARBON_SYMBOL(GetMenuHandle);
MenuRef carbon_GetMenuHandle(int16_t identifier) {
    for (MenuRef menu = menus; menu; menu = menu->next)
        if (menu->identifier == identifier) return menu;
    return NULL;
}

MenuRef carbon_GetMenuRef(int16_t identifier) CARBON_SYMBOL(GetMenuRef);
MenuRef carbon_GetMenuRef(int16_t identifier) { return carbon_GetMenuHandle(identifier); }

int16_t carbon_GetMenuID(MenuRef menu) CARBON_SYMBOL(GetMenuID);
int16_t carbon_GetMenuID(MenuRef menu) { return (menu = menu_from(menu)) ? menu->identifier : 0; }

/// The item with a command, in a menu and its submenus, or in every menu
/// for none.
static menu_item *find_command(MenuRef menu, uint32_t command) {
    for (MenuRef each = menu ? menu : menus; each; each = menu ? NULL : each->next)
        for (size_t index = 0; index < each->count; index++)
            if (each->items[index].command == command) return &each->items[index];
    return NULL;
}

static void enable(MenuRef menu, uint32_t command, bool enabled) {
    menu = menu_from(menu);
    for (MenuRef each = menu ? menu : menus; each; each = menu ? NULL : each->next)
        for (size_t index = 0; index < each->count; index++)
            if (each->items[index].command == command) {
                each->items[index].enabled = enabled;
                ((void (*)(id, SEL, signed char))objc_send)(each->items[index].item, SELECTOR("setEnabled:"), enabled ? 1 : 0);
            }
}

void carbon_EnableMenuCommand(MenuRef menu, uint32_t command) CARBON_SYMBOL(EnableMenuCommand);
void carbon_EnableMenuCommand(MenuRef menu, uint32_t command) { enable(menu, command, true); }

void carbon_DisableMenuCommand(MenuRef menu, uint32_t command) CARBON_SYMBOL(DisableMenuCommand);
void carbon_DisableMenuCommand(MenuRef menu, uint32_t command) { enable(menu, command, false); }

Boolean carbon_IsMenuCommandEnabled(MenuRef menu, uint32_t command) CARBON_SYMBOL(IsMenuCommandEnabled);
Boolean carbon_IsMenuCommandEnabled(MenuRef menu, uint32_t command) {
    menu_item *item = find_command(menu_from(menu), command);
    return item && item->enabled;
}

OSStatus carbon_GetMenuItemCommandID(MenuRef menu, uint16_t index, uint32_t *command) CARBON_SYMBOL(GetMenuItemCommandID);
OSStatus carbon_GetMenuItemCommandID(MenuRef menu, uint16_t index, uint32_t *command) {
    if (!(menu = menu_from(menu)) || !command || index == 0 || index > menu->count) return -5620;   // menuItemNotFoundErr
    *command = menu->items[index - 1].command;
    return noErr;
}

OSStatus carbon_SetMenuItemCommandID(MenuRef menu, uint16_t index, uint32_t command) CARBON_SYMBOL(SetMenuItemCommandID);
OSStatus carbon_SetMenuItemCommandID(MenuRef menu, uint16_t index, uint32_t command) {
    if (!(menu = menu_from(menu)) || index == 0 || index > menu->count) return -5620;
    menu->items[index - 1].command = command;
    carbon_action_register(menu->items[index - 1].item, command, NULL, menu, index);
    return noErr;
}

OSStatus carbon_GetIndMenuItemWithCommandID(MenuRef menu, uint32_t command, uint32_t instance, MenuRef *out, uint16_t *index)
    CARBON_SYMBOL(GetIndMenuItemWithCommandID);
OSStatus carbon_GetIndMenuItemWithCommandID(MenuRef menu, uint32_t command, uint32_t instance, MenuRef *out, uint16_t *index) {
    menu = menu_from(menu);
    uint32_t seen = 0;
    for (MenuRef each = menu ? menu : menus; each; each = menu ? NULL : each->next)
        for (size_t at = 0; at < each->count; at++)
            if (each->items[at].command == command && ++seen == (instance ? instance : 1)) {
                if (out) *out = each;
                if (index) *index = (uint16_t)(at + 1);
                return noErr;
            }
    return -5620;
}

OSStatus carbon_CreateNewMenu(int16_t identifier, uint32_t attributes, MenuRef *out) CARBON_SYMBOL(CreateNewMenu);
OSStatus carbon_CreateNewMenu(int16_t identifier, uint32_t attributes, MenuRef *out) {
    (void)attributes;
    if (!out) return paramErr;
    *out = carbon_menu_new(identifier, NULL);
    return *out ? noErr : memFullErr;
}

/// The original way to make a menu, with a Pascal string for its title;
/// the Apple menu's (the apple, character 0x14) is AppKit's application
/// menu's here, so it is left untitled.
MenuRef carbon_NewMenu(int16_t identifier, ConstStr255Param title) CARBON_SYMBOL(NewMenu);
MenuRef carbon_NewMenu(int16_t identifier, ConstStr255Param title) {
    char text[256] = "";
    if (title && !(title[0] == 1 && title[1] == 0x14)) {
        memcpy(text, title + 1, title[0]);
        text[title[0]] = 0;
    }
    return carbon_menu_new(identifier, carbon_string(text));
}

OSStatus carbon_SetMenuTitleWithCFString(MenuRef menu, id title) CARBON_SYMBOL(SetMenuTitleWithCFString);
OSStatus carbon_SetMenuTitleWithCFString(MenuRef menu, id title) {
    if (!(menu = menu_from(menu))) return paramErr;
    SEND1(menu->menu, "setTitle:", title);
    return noErr;
}

OSStatus carbon_AppendMenuItemTextWithCFString(MenuRef menu, id title, uint32_t attributes, uint32_t command, uint16_t *index)
    CARBON_SYMBOL(AppendMenuItemTextWithCFString);
OSStatus carbon_AppendMenuItemTextWithCFString(MenuRef menu, id title, uint32_t attributes, uint32_t command, uint16_t *index) {
    if (!(menu = menu_from(menu))) return paramErr;
    carbon_menu_add(menu, (attributes & 0x40) ? NULL : title, command, NULL, 0);   // kMenuItemAttrSeparator
    if (index) *index = (uint16_t)menu->count;
    return noErr;
}

/// Adds a menu to the menu bar, before another or at the end.
void carbon_InsertMenu(MenuRef menu, int16_t before) CARBON_SYMBOL(InsertMenu);
void carbon_InsertMenu(MenuRef menu, int16_t before) {
    (void)before;
    if (!(menu = menu_from(menu))) return;
    if (!menu_bar) {
        menu_bar = carbon_menu_new(0, NULL);
        carbon_menu_bar_set(menu_bar);
    }
    id title = SEND(menu->menu, "title");
    id item = carbon_menu_add(menu_bar, title, 0, NULL, 0);
    carbon_menu_set_submenu(menu_bar, item, menu);
}

void carbon_DeleteMenu(int16_t identifier) CARBON_SYMBOL(DeleteMenu);
void carbon_DeleteMenu(int16_t identifier) { (void)identifier; }

void carbon_DrawMenuBar(void) CARBON_SYMBOL(DrawMenuBar);
void carbon_DrawMenuBar(void) {}

void carbon_InvalMenuBar(void) CARBON_SYMBOL(InvalMenuBar);
void carbon_InvalMenuBar(void) {}

void carbon_ClearMenuBar(void) CARBON_SYMBOL(ClearMenuBar);
void carbon_ClearMenuBar(void) {}

/// The classic way to track a menu, from a mouse-down in the menu bar:
/// AppKit tracks its menus itself, and sends their commands, so nothing
/// was chosen here.
int32_t carbon_MenuSelect(Point point) CARBON_SYMBOL(MenuSelect);
int32_t carbon_MenuSelect(Point point) {
    (void)point;
    return 0;
}

int32_t carbon_MenuEvent(const EventRecord *event) CARBON_SYMBOL(MenuEvent);
int32_t carbon_MenuEvent(const EventRecord *event) {
    (void)event;
    return 0;
}

void carbon_HiliteMenu(int16_t identifier) CARBON_SYMBOL(HiliteMenu);
void carbon_HiliteMenu(int16_t identifier) { (void)identifier; }

// MARK: - Items by number

/// A Pascal string's text, MacRoman's ASCII as it is and its other
/// characters as Latin-1's (a close enough reading for menus).
id carbon_pascal_string(const unsigned char *text) {
    char utf8[512];
    size_t out = 0;
    for (size_t index = 1; text && index <= text[0] && out + 3 < sizeof utf8; index++) {
        unsigned char c = text[index];
        if (c < 0x80) utf8[out++] = (char)c;
        else {
            utf8[out++] = (char)(0xC0 | c >> 6);
            utf8[out++] = (char)(0x80 | (c & 0x3F));
        }
    }
    utf8[out] = 0;
    return carbon_string(utf8);
}

uint16_t carbon_CountMenuItems(MenuRef menu) CARBON_SYMBOL(CountMenuItems);
uint16_t carbon_CountMenuItems(MenuRef menu) { return (menu = menu_from(menu)) ? (uint16_t)menu->count : 0; }

uint16_t carbon_CountMItems(MenuRef menu) CARBON_SYMBOL(CountMItems);
uint16_t carbon_CountMItems(MenuRef menu) { return carbon_CountMenuItems(menu); }

/// Removes `count` items from the 1-based `first` on.
OSStatus carbon_DeleteMenuItems(MenuRef menu, uint16_t first, uint32_t count) CARBON_SYMBOL(DeleteMenuItems);
OSStatus carbon_DeleteMenuItems(MenuRef menu, uint16_t first, uint32_t count) {
    if (!(menu = menu_from(menu))) return paramErr;
    if (first == 0 || first > menu->count) return count ? -5620 : noErr;   // menuItemNotFoundErr
    size_t start = first - 1u, end = start + count > menu->count ? menu->count : start + count;
    for (size_t index = end; index-- > start;)
        ((void (*)(id, SEL, long))objc_send)(menu->menu, SELECTOR("removeItemAtIndex:"), (long)index);
    memmove(menu->items + start, menu->items + end, (menu->count - end) * sizeof *menu->items);
    menu->count -= end - start;
    return noErr;
}

void carbon_DeleteMenuItem(MenuRef menu, uint16_t item) CARBON_SYMBOL(DeleteMenuItem);
void carbon_DeleteMenuItem(MenuRef menu, uint16_t item) { carbon_DeleteMenuItems(menu, item, 1); }

/// The Menu Manager's first way to add items: `data` holds items parted by
/// ';' or return, each with its metacharacters: '(' before disables it,
/// "-" alone is a separator, "/x" is its Command key, and '^', '!' and '<'
/// give it an icon, a mark and a style, each with the character after.
void carbon_AppendMenu(MenuRef menu, ConstStr255Param data) CARBON_SYMBOL(AppendMenu);
void carbon_AppendMenu(MenuRef menu, ConstStr255Param data) {
    if (!(menu = menu_from(menu)) || !data) return;
    size_t length = data[0], start = 1;
    while (start <= length) {
        size_t end = start;
        while (end <= length && data[end] != ';' && data[end] != '\r') end++;
        unsigned char title[256] = {0};
        char key[2] = {0, 0};
        bool disabled = false;
        for (size_t index = start; index < end; index++) {
            unsigned char c = data[index];
            if (c == '(' && title[0] == 0) disabled = true;
            else if ((c == '/' || c == '^' || c == '!' || c == '<') && index + 1 < end) {
                if (c == '/') key[0] = (char)(data[index + 1] | 0x20);
                index++;
            } else title[++title[0]] = c;
        }
        bool separator = title[0] == 1 && title[1] == '-';
        id item = carbon_menu_add(menu, separator ? NULL : carbon_pascal_string(title), 0, key[0] ? key : NULL, 0);
        if (item && disabled && !separator) {
            menu->items[menu->count - 1].enabled = false;
            ((void (*)(id, SEL, signed char))objc_send)(item, SELECTOR("setEnabled:"), 0);
        }
        start = end + 1;
    }
}

/// An item of the text, metacharacters and all.
void carbon_AppendMenuItemText(MenuRef menu, ConstStr255Param text) CARBON_SYMBOL(AppendMenuItemText);
void carbon_AppendMenuItemText(MenuRef menu, ConstStr255Param text) {
    if ((menu = menu_from(menu)) && text) carbon_menu_add(menu, carbon_pascal_string(text), 0, NULL, 0);
}

void carbon_GetMenuItemText(MenuRef menu, uint16_t item, unsigned char *text) CARBON_SYMBOL(GetMenuItemText);
void carbon_GetMenuItemText(MenuRef menu, uint16_t item, unsigned char *text) {
    if (!text) return;
    text[0] = 0;
    if (!(menu = menu_from(menu)) || item == 0 || item > menu->count) return;
    const char *utf8 = ((const char *(*)(id, SEL))objc_send)(SEND(menu->items[item - 1].item, "title"), SELECTOR("UTF8String"));
    for (size_t index = 0; utf8 && utf8[index] && text[0] < 255; index++) text[++text[0]] = (unsigned char)utf8[index];
}

void carbon_SetMenuItemText(MenuRef menu, uint16_t item, ConstStr255Param text) CARBON_SYMBOL(SetMenuItemText);
void carbon_SetMenuItemText(MenuRef menu, uint16_t item, ConstStr255Param text) {
    if (!(menu = menu_from(menu)) || item == 0 || item > menu->count || !text) return;
    SEND1(menu->items[item - 1].item, "setTitle:", carbon_pascal_string(text));
}
