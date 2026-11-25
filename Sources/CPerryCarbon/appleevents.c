// The Apple Event Manager, for the events an application gets from the
// system: 'oapp' as it starts, 'quit' when asked to quit, and those it
// sends itself. A descriptor's data is a record of this file's: its bytes,
// and for a list or an Apple event, its items or parameters and attributes.

#include "PerryCarbon.h"

#include <stdlib.h>
#include <string.h>

#define FOUR(a, b, c, d) ((uint32_t)(a) << 24 | (uint32_t)(b) << 16 | (uint32_t)(c) << 8 | (uint32_t)(d))

enum {
    typeNull = FOUR('n', 'u', 'l', 'l'),
    typeWildCard = FOUR('*', '*', '*', '*'),
    typeAEList = FOUR('l', 'i', 's', 't'),
    typeAERecord = FOUR('r', 'e', 'c', 'o'),
    typeAppleEvent = FOUR('a', 'e', 'v', 't'),
    typeType = FOUR('t', 'y', 'p', 'e'),
    typeProcessSerialNumber = FOUR('p', 's', 'n', ' '),
    keyEventClassAttr = FOUR('e', 'v', 'c', 'l'),
    keyEventIDAttr = FOUR('e', 'v', 'i', 'd'),
    keyAddressAttr = FOUR('a', 'd', 'd', 'r'),
    kCoreEventClass = FOUR('a', 'e', 'v', 't'),
    kAEOpenApplication = FOUR('o', 'a', 'p', 'p'),
    kAEQuitApplication = FOUR('q', 'u', 'i', 't'),
    errAEDescNotFound = -1701,
    errAEEventNotHandled = -1708,
    errAEWrongDataType = -1703,
    errAEIllegalIndex = -1719,
};

#pragma pack(push, 2)
typedef struct {
    OSType descriptorType;
    void *dataHandle;
} AEDesc;
#pragma pack(pop)

typedef struct ae_item {
    uint32_t keyword;
    AEDesc desc;
    struct ae_item *next;
} ae_item;

typedef struct {
    size_t size;
    void *bytes;
    ae_item *items;        // a list's, in order; a record's or event's parameters
    ae_item *attributes;   // an event's
} ae_data;

static ae_data *data_of(const AEDesc *desc) { return desc ? desc->dataHandle : NULL; }

static OSErr desc_make(OSType type, const void *bytes, size_t size, AEDesc *out) {
    out->descriptorType = type;
    out->dataHandle = NULL;
    if (type == typeNull) return noErr;
    ae_data *data = calloc(1, sizeof *data);
    if (!data) return memFullErr;
    if (size) {
        data->bytes = malloc(size);
        if (!data->bytes) {
            free(data);
            return memFullErr;
        }
        if (bytes) memcpy(data->bytes, bytes, size);
        data->size = size;
    }
    out->dataHandle = data;
    return noErr;
}

static void items_free(ae_item *item);

static void desc_free(AEDesc *desc) {
    ae_data *data = data_of(desc);
    if (data) {
        free(data->bytes);
        items_free(data->items);
        items_free(data->attributes);
        free(data);
    }
    desc->descriptorType = typeNull;
    desc->dataHandle = NULL;
}

static void items_free(ae_item *item) {
    while (item) {
        ae_item *next = item->next;
        desc_free(&item->desc);
        free(item);
        item = next;
    }
}

static OSErr desc_copy(const AEDesc *from, AEDesc *to) {
    ae_data *data = data_of(from);
    OSErr error = desc_make(from->descriptorType, data ? data->bytes : NULL, data ? data->size : 0, to);
    if (error || !data) return error;
    ae_data *copy = data_of(to);
    ae_item **items = &copy->items, **attributes = &copy->attributes;
    for (int pass = 0; pass < 2; pass++)
        for (ae_item *item = pass ? data->attributes : data->items; item; item = item->next) {
            ae_item *duplicate = calloc(1, sizeof *duplicate);
            if (!duplicate) return memFullErr;
            duplicate->keyword = item->keyword;
            desc_copy(&item->desc, &duplicate->desc);
            ae_item ***tail = pass ? &attributes : &items;
            **tail = duplicate;
            *tail = &duplicate->next;
        }
    return noErr;
}

/// Sets a keyword's descriptor in a list of items, replacing one there.
static OSErr put(ae_item **list, uint32_t keyword, OSType type, const void *bytes, size_t size) {
    ae_item **link = list;
    while (*link && (*link)->keyword != keyword) link = &(*link)->next;
    if (*link) desc_free(&(*link)->desc);
    else {
        *link = calloc(1, sizeof **link);
        if (!*link) return memFullErr;
        (*link)->keyword = keyword;
    }
    return desc_make(type, bytes, size, &(*link)->desc);
}

static ae_item *find(ae_item *list, uint32_t keyword) {
    while (list && list->keyword != keyword) list = list->next;
    return list;
}

/// Copies a descriptor's bytes out, as the type asked for when it can be.
static OSErr get_bytes(const AEDesc *desc, OSType desired, OSType *type, void *buffer, long maximum, long *actual) {
    ae_data *data = data_of(desc);
    if (desired != typeWildCard && desired != desc->descriptorType && desired != typeType) return errAEWrongDataType;
    if (type) *type = desc->descriptorType;
    size_t size = data ? data->size : 0;
    if (actual) *actual = (long)size;
    if (buffer && data && maximum > 0) memcpy(buffer, data->bytes, size < (size_t)maximum ? size : (size_t)maximum);
    return noErr;
}

// MARK: - Descriptors

OSErr carbon_AECreateDesc(OSType type, const void *bytes, long size, AEDesc *out) CARBON_SYMBOL(AECreateDesc);
OSErr carbon_AECreateDesc(OSType type, const void *bytes, long size, AEDesc *out) {
    if (!out || size < 0) return paramErr;
    return desc_make(type, bytes, (size_t)size, out);
}

OSErr carbon_AEDisposeDesc(AEDesc *desc) CARBON_SYMBOL(AEDisposeDesc);
OSErr carbon_AEDisposeDesc(AEDesc *desc) {
    if (desc) desc_free(desc);
    return noErr;
}

OSErr carbon_AEDuplicateDesc(const AEDesc *from, AEDesc *to) CARBON_SYMBOL(AEDuplicateDesc);
OSErr carbon_AEDuplicateDesc(const AEDesc *from, AEDesc *to) {
    if (!from || !to) return paramErr;
    return desc_copy(from, to);
}

void carbon_AEInitializeDesc(AEDesc *desc) CARBON_SYMBOL(AEInitializeDesc);
void carbon_AEInitializeDesc(AEDesc *desc) {
    if (desc) *desc = (AEDesc){typeNull, NULL};
}

long carbon_AEGetDescDataSize(const AEDesc *desc) CARBON_SYMBOL(AEGetDescDataSize);
long carbon_AEGetDescDataSize(const AEDesc *desc) {
    ae_data *data = data_of(desc);
    return data ? (long)data->size : 0;
}

OSErr carbon_AEGetDescData(const AEDesc *desc, void *buffer, long maximum) CARBON_SYMBOL(AEGetDescData);
OSErr carbon_AEGetDescData(const AEDesc *desc, void *buffer, long maximum) {
    return get_bytes(desc, typeWildCard, NULL, buffer, maximum, NULL);
}

OSErr carbon_AECreateList(const void *factoring, long size, Boolean isRecord, AEDesc *out) CARBON_SYMBOL(AECreateList);
OSErr carbon_AECreateList(const void *factoring, long size, Boolean isRecord, AEDesc *out) {
    (void)factoring; (void)size;
    if (!out) return paramErr;
    return desc_make(isRecord ? typeAERecord : typeAEList, NULL, 0, out);
}

OSErr carbon_AECountItems(const AEDesc *list, long *count) CARBON_SYMBOL(AECountItems);
OSErr carbon_AECountItems(const AEDesc *list, long *count) {
    ae_data *data = data_of(list);
    if (!count) return paramErr;
    *count = 0;
    for (ae_item *item = data ? data->items : NULL; item; item = item->next) (*count)++;
    return noErr;
}

/// The index-th item (from 1) of a list or record.
static ae_item *nth(const AEDesc *list, long index) {
    ae_data *data = data_of(list);
    ae_item *item = data ? data->items : NULL;
    for (long at = 1; item && at < index; at++) item = item->next;
    return index >= 1 ? item : NULL;
}

OSErr carbon_AEGetNthPtr(const AEDesc *list, long index, OSType desired, uint32_t *keyword, OSType *type, void *buffer,
                         long maximum, long *actual) CARBON_SYMBOL(AEGetNthPtr);
OSErr carbon_AEGetNthPtr(const AEDesc *list, long index, OSType desired, uint32_t *keyword, OSType *type, void *buffer,
                         long maximum, long *actual) {
    ae_item *item = nth(list, index);
    if (!item) return errAEIllegalIndex;
    if (keyword) *keyword = item->keyword;
    return get_bytes(&item->desc, desired, type, buffer, maximum, actual);
}

OSErr carbon_AEGetNthDesc(const AEDesc *list, long index, OSType desired, uint32_t *keyword, AEDesc *out) CARBON_SYMBOL(AEGetNthDesc);
OSErr carbon_AEGetNthDesc(const AEDesc *list, long index, OSType desired, uint32_t *keyword, AEDesc *out) {
    ae_item *item = nth(list, index);
    if (!item) return errAEIllegalIndex;
    if (desired != typeWildCard && desired != item->desc.descriptorType) return errAEWrongDataType;
    if (keyword) *keyword = item->keyword;
    return desc_copy(&item->desc, out);
}

OSErr carbon_AEPutPtr(AEDesc *list, long index, OSType type, const void *bytes, long size) CARBON_SYMBOL(AEPutPtr);
OSErr carbon_AEPutPtr(AEDesc *list, long index, OSType type, const void *bytes, long size) {
    ae_data *data = data_of(list);
    if (!data) return paramErr;
    ae_item **link = &data->items;
    for (long at = 1; *link && (index <= 0 || at < index); at++) link = &(*link)->next;
    if (*link && index > 0) {
        desc_free(&(*link)->desc);
        return desc_make(type, bytes, (size_t)size, &(*link)->desc);
    }
    *link = calloc(1, sizeof **link);
    if (!*link) return memFullErr;
    return desc_make(type, bytes, (size_t)size, &(*link)->desc);
}

// MARK: - Apple events

OSErr carbon_AECreateAppleEvent(OSType eventClass, OSType eventID, const AEDesc *target, int16_t returnID, int32_t transactionID,
                                AEDesc *out) CARBON_SYMBOL(AECreateAppleEvent);
OSErr carbon_AECreateAppleEvent(OSType eventClass, OSType eventID, const AEDesc *target, int16_t returnID, int32_t transactionID,
                                AEDesc *out) {
    (void)returnID; (void)transactionID;
    if (!out) return paramErr;
    OSErr error = desc_make(typeAppleEvent, NULL, 0, out);
    if (error) return error;
    ae_data *data = data_of(out);
    put(&data->attributes, keyEventClassAttr, typeType, &eventClass, sizeof eventClass);
    put(&data->attributes, keyEventIDAttr, typeType, &eventID, sizeof eventID);
    if (target && data_of(target))
        put(&data->attributes, keyAddressAttr, target->descriptorType, data_of(target)->bytes, data_of(target)->size);
    return noErr;
}

OSErr carbon_AEPutParamPtr(AEDesc *event, uint32_t keyword, OSType type, const void *bytes, long size) CARBON_SYMBOL(AEPutParamPtr);
OSErr carbon_AEPutParamPtr(AEDesc *event, uint32_t keyword, OSType type, const void *bytes, long size) {
    ae_data *data = data_of(event);
    if (!data || size < 0) return paramErr;
    return put(&data->items, keyword, type, bytes, (size_t)size);
}

OSErr carbon_AEPutParamDesc(AEDesc *event, uint32_t keyword, const AEDesc *desc) CARBON_SYMBOL(AEPutParamDesc);
OSErr carbon_AEPutParamDesc(AEDesc *event, uint32_t keyword, const AEDesc *desc) {
    ae_data *data = data_of(event);
    if (!data || !desc) return paramErr;
    ae_data *value = data_of(desc);
    OSErr error = put(&data->items, keyword, desc->descriptorType, value ? value->bytes : NULL, value ? value->size : 0);
    if (error || !value) return error;
    // A list's items too.
    ae_item *item = find(data->items, keyword);
    desc_free(&item->desc);
    return desc_copy(desc, &item->desc);
}

OSErr carbon_AEGetParamPtr(const AEDesc *event, uint32_t keyword, OSType desired, OSType *type, void *buffer, long maximum,
                           long *actual) CARBON_SYMBOL(AEGetParamPtr);
OSErr carbon_AEGetParamPtr(const AEDesc *event, uint32_t keyword, OSType desired, OSType *type, void *buffer, long maximum,
                           long *actual) {
    ae_data *data = data_of(event);
    ae_item *item = data ? find(data->items, keyword) : NULL;
    if (!item) return errAEDescNotFound;
    return get_bytes(&item->desc, desired, type, buffer, maximum, actual);
}

OSErr carbon_AEGetParamDesc(const AEDesc *event, uint32_t keyword, OSType desired, AEDesc *out) CARBON_SYMBOL(AEGetParamDesc);
OSErr carbon_AEGetParamDesc(const AEDesc *event, uint32_t keyword, OSType desired, AEDesc *out) {
    ae_data *data = data_of(event);
    ae_item *item = data ? find(data->items, keyword) : NULL;
    if (!out) return paramErr;
    *out = (AEDesc){typeNull, NULL};
    if (!item) return errAEDescNotFound;
    if (desired != typeWildCard && desired != item->desc.descriptorType &&
        !(desired == typeAEList && item->desc.descriptorType == typeAEList)) return errAEWrongDataType;
    return desc_copy(&item->desc, out);
}

OSErr carbon_AEGetAttributePtr(const AEDesc *event, uint32_t keyword, OSType desired, OSType *type, void *buffer, long maximum,
                               long *actual) CARBON_SYMBOL(AEGetAttributePtr);
OSErr carbon_AEGetAttributePtr(const AEDesc *event, uint32_t keyword, OSType desired, OSType *type, void *buffer, long maximum,
                               long *actual) {
    ae_data *data = data_of(event);
    ae_item *item = data ? find(data->attributes, keyword) : NULL;
    if (!item) return errAEDescNotFound;
    return get_bytes(&item->desc, desired, type, buffer, maximum, actual);
}

// MARK: - Handlers

typedef OSErr (*AEEventHandlerProc)(const AEDesc *event, AEDesc *reply, void *refCon);

typedef struct ae_handler {
    OSType eventClass, eventID;
    AEEventHandlerProc procedure;
    void *refCon;
    struct ae_handler *next;
} ae_handler;

static ae_handler *handlers;

OSErr carbon_AEInstallEventHandler(OSType eventClass, OSType eventID, AEEventHandlerProc procedure, void *refCon, Boolean system)
    CARBON_SYMBOL(AEInstallEventHandler);
OSErr carbon_AEInstallEventHandler(OSType eventClass, OSType eventID, AEEventHandlerProc procedure, void *refCon, Boolean system) {
    (void)system;
    for (ae_handler *handler = handlers; handler; handler = handler->next)
        if (handler->eventClass == eventClass && handler->eventID == eventID) {
            handler->procedure = procedure;
            handler->refCon = refCon;
            return noErr;
        }
    ae_handler *handler = calloc(1, sizeof *handler);
    if (!handler) return memFullErr;
    *handler = (ae_handler){eventClass, eventID, procedure, refCon, handlers};
    handlers = handler;
    return noErr;
}

OSErr carbon_AERemoveEventHandler(OSType eventClass, OSType eventID, AEEventHandlerProc procedure, Boolean system)
    CARBON_SYMBOL(AERemoveEventHandler);
OSErr carbon_AERemoveEventHandler(OSType eventClass, OSType eventID, AEEventHandlerProc procedure, Boolean system) {
    (void)procedure; (void)system;
    for (ae_handler **link = &handlers; *link; link = &(*link)->next)
        if ((*link)->eventClass == eventClass && (*link)->eventID == eventID) {
            ae_handler *handler = *link;
            *link = handler->next;
            free(handler);
            return noErr;
        }
    return errAEEventNotHandled;
}

static ae_handler *handler_for(OSType eventClass, OSType eventID) {
    ae_handler *wildcard = NULL;
    for (ae_handler *handler = handlers; handler; handler = handler->next) {
        if (handler->eventClass == eventClass && handler->eventID == eventID) return handler;
        if ((handler->eventClass == eventClass || handler->eventClass == typeWildCard) &&
            (handler->eventID == eventID || handler->eventID == typeWildCard)) wildcard = handler;
    }
    return wildcard;
}

/// Hands an Apple event to the application's handler for it.
static OSErr dispatch(const AEDesc *event, AEDesc *reply) {
    OSType eventClass = 0, eventID = 0;
    carbon_AEGetAttributePtr(event, keyEventClassAttr, typeWildCard, NULL, &eventClass, sizeof eventClass, NULL);
    carbon_AEGetAttributePtr(event, keyEventIDAttr, typeWildCard, NULL, &eventID, sizeof eventID, NULL);
    ae_handler *handler = handler_for(eventClass, eventID);
    if (!handler || !handler->procedure) return errAEEventNotHandled;
    AEDesc empty = {typeNull, NULL};
    CARBON_TRACE("Apple event %.4s/%.4s", (char[]){(char)(eventClass >> 24), (char)(eventClass >> 16), (char)(eventClass >> 8), (char)eventClass},
                 (char[]){(char)(eventID >> 24), (char)(eventID >> 16), (char)(eventID >> 8), (char)eventID});
    return handler->procedure(event, reply ? reply : &empty, handler->refCon);
}

/// Events the application sends: to itself, the only process here they
/// can go to, at once.
OSErr carbon_AESend(const AEDesc *event, AEDesc *reply, int32_t mode, int16_t priority, long timeout, void *idle, void *filter)
    CARBON_SYMBOL(AESend);
OSErr carbon_AESend(const AEDesc *event, AEDesc *reply, int32_t mode, int16_t priority, long timeout, void *idle, void *filter) {
    (void)mode; (void)priority; (void)timeout; (void)idle; (void)filter;
    if (!event) return paramErr;
    if (reply) desc_make(typeAppleEvent, NULL, 0, reply);
    OSErr error = dispatch(event, reply);
    return error == errAEEventNotHandled ? noErr : error;
}

/// High-level events from WaitNextEvent: none come here.
OSErr carbon_AEProcessAppleEvent(const EventRecord *record) CARBON_SYMBOL(AEProcessAppleEvent);
OSErr carbon_AEProcessAppleEvent(const EventRecord *record) {
    (void)record;
    return noErr;
}

static bool send_core(OSType eventID) {
    if (!handler_for(kCoreEventClass, eventID)) return false;
    AEDesc event, reply = {typeNull, NULL};
    uint32_t self[2] = {0, 2};   // kCurrentProcess
    AEDesc target;
    desc_make(typeProcessSerialNumber, self, sizeof self, &target);
    carbon_AECreateAppleEvent(kCoreEventClass, eventID, &target, -1, 0, &event);
    dispatch(&event, &reply);
    desc_free(&event);
    desc_free(&reply);
    desc_free(&target);
    return true;
}

void carbon_apple_event_open(void) {
    static bool sent;
    if (sent) return;
    sent = true;
    send_core(kAEOpenApplication);
}

bool carbon_apple_event_quit(void) { return send_core(kAEQuitApplication); }
