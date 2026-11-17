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
                                                         SELECTOR("perryCarbonPerform:"), carbon_string(key && !(modifiers & 8) ? key : ""));
        SEND1(item, "setTarget:", carbon_action_target());
        unsigned long mask = 1ul << 20;   // NSEventModifierFlagCommand
        if (modifiers & 1) mask |= 1ul << 17;   // kMenuShiftModifier
        if (modifiers & 2) mask |= 1ul << 19;   // kMenuOptionModifier
        if (modifiers & 4) mask |= 1ul << 18;   // kMenuControlModifier
        ((void (*)(id, SEL, unsigned long))objc_send)(item, SELECTOR("setKeyEquivalentModifierMask:"), mask);
    }
    SEND1(menu->menu, "addItem:", item);
    menu->items[menu->count] = (menu_item){item, command, true};
    menu->count++;
    if (!separator) carbon_action_register(item, command, NULL, menu, (uint16_t)menu->count);
    return item;
}

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
