// The Carbon Event Manager over AppKit's events. AppKit's NSEvents become
// Carbon events, sent to the window's event target and from there to the
// application's, through each target's handlers in the order Carbon calls
// them (the last installed first). Timers are the event loop's own, fired
// while it waits. RunApplicationEventLoop runs until
// QuitApplicationEventLoop; WaitNextEvent gives the original Event
// Manager's records. The keyboard's and mouse's state comes from the
// events seen.

#include "PerryCarbon.h"

#include <math.h>
#include <stdlib.h>
#include <string.h>

typedef struct { float x, y; } HIPoint;

#define FOUR(a, b, c, d) ((uint32_t)(a) << 24 | (uint32_t)(b) << 16 | (uint32_t)(c) << 8 | (uint32_t)(d))

enum {
    kEventClassMouse = FOUR('m', 'o', 'u', 's'),
    kEventClassKeyboard = FOUR('k', 'e', 'y', 'b'),
    kEventClassApplication = FOUR('a', 'p', 'p', 'l'),
    kEventClassWindow = FOUR('w', 'i', 'n', 'd'),
    kEventClassCommand = FOUR('c', 'm', 'd', 's'),
    kEventClassAppleEvent = FOUR('e', 'p', 'p', 'c'),

    kEventParamDirectObject = FOUR('-', '-', '-', '-'),
    kEventParamWindowRef = FOUR('w', 'i', 'n', 'd'),
    kEventParamMouseLocation = FOUR('m', 'l', 'o', 'c'),
    kEventParamWindowMouseLocation = FOUR('w', 'm', 'o', 'u'),
    kEventParamMouseButton = FOUR('m', 'b', 't', 'n'),
    kEventParamClickCount = FOUR('c', 'c', 'n', 't'),
    kEventParamKeyModifiers = FOUR('k', 'm', 'o', 'd'),
    kEventParamMouseWheelAxis = FOUR('m', 'w', 'a', 'x'),
    kEventParamMouseWheelDelta = FOUR('m', 'w', 'd', 'l'),
    kEventParamMouseDelta = FOUR('m', 'd', 't', 'a'),
    kEventParamMouseChord = FOUR('c', 'h', 'o', 'r'),
    kEventParamKeyCode = FOUR('k', 'c', 'o', 'd'),
    kEventParamKeyMacCharCodes = FOUR('k', 'c', 'h', 'r'),
    kEventParamKeyUnicodes = FOUR('k', 'u', 'n', 'i'),
    kEventParamKeyboardType = FOUR('k', 'b', 'd', 't'),
    kEventParamHICommand = FOUR('h', 'c', 'm', 'd'),

    typeWildCard = FOUR('*', '*', '*', '*'),
    typeWindowRef = FOUR('w', 'i', 'n', 'd'),
    typeHIPoint = FOUR('h', 'i', 'p', 't'),
    typeQDPoint = FOUR('Q', 'D', 'p', 't'),
    typeMouseButton = FOUR('m', 'b', 't', 'n'),
    typeUInt32 = FOUR('m', 'a', 'g', 'n'),
    typeSInt32 = FOUR('l', 'o', 'n', 'g'),
    typeMouseWheelAxis = FOUR('m', 'w', 'a', 'x'),
    typeChar = FOUR('T', 'E', 'X', 'T'),
    typeUnicodeText = FOUR('u', 't', 'x', 't'),
    typeHICommand = FOUR('h', 'c', 'm', 'd'),

    kHICommandQuit = FOUR('q', 'u', 'i', 't'),
};

// MARK: - Events

typedef struct event_parameter {
    uint32_t name, type;
    size_t size;
    void *data;
    struct event_parameter *next;
} event_parameter;

typedef struct carbon_event {
    uint32_t magic;
    uint32_t eventClass, kind;
    double time;
    int retains;
    event_parameter *parameters;
    id nsevent;
} carbon_event, *EventRef;

#define CARBON_EVENT_MAGIC 0x45564e54u   // 'EVNT'

static EventRef event_from(void *pointer) {
    EventRef event = pointer;
    return event && event->magic == CARBON_EVENT_MAGIC ? event : NULL;
}

static EventRef event_new(uint32_t eventClass, uint32_t kind, double time) {
    EventRef event = calloc(1, sizeof *event);
    if (!event) return NULL;
    event->magic = CARBON_EVENT_MAGIC;
    event->eventClass = eventClass;
    event->kind = kind;
    event->time = time ? time : carbon_now();
    event->retains = 1;
    return event;
}

static void event_set(EventRef event, uint32_t name, uint32_t type, size_t size, const void *data) {
    event_parameter *parameter = event->parameters;
    while (parameter && parameter->name != name) parameter = parameter->next;
    if (!parameter) {
        parameter = calloc(1, sizeof *parameter);
        if (!parameter) return;
        parameter->name = name;
        parameter->next = event->parameters;
        event->parameters = parameter;
    }
    free(parameter->data);
    parameter->type = type;
    parameter->size = size;
    parameter->data = malloc(size ? size : 1);
    if (parameter->data && size) memcpy(parameter->data, data, size);
}

static void event_release(EventRef event) {
    if (!event || --event->retains > 0) return;
    for (event_parameter *parameter = event->parameters, *next; parameter; parameter = next) {
        next = parameter->next;
        free(parameter->data);
        free(parameter);
    }
    event->magic = 0;
    free(event);
}

OSStatus carbon_CreateEvent(void *allocator, uint32_t eventClass, uint32_t kind, double time, uint32_t attributes, EventRef *out)
    CARBON_SYMBOL(CreateEvent);
OSStatus carbon_CreateEvent(void *allocator, uint32_t eventClass, uint32_t kind, double time, uint32_t attributes, EventRef *out) {
    (void)allocator; (void)attributes;
    if (!out) return paramErr;
    *out = event_new(eventClass, kind, time);
    return *out ? noErr : memFullErr;
}

EventRef carbon_RetainEvent(EventRef event) CARBON_SYMBOL(RetainEvent);
EventRef carbon_RetainEvent(EventRef event) {
    if ((event = event_from(event))) event->retains++;
    return event;
}

void carbon_ReleaseEvent(EventRef event) CARBON_SYMBOL(ReleaseEvent);
void carbon_ReleaseEvent(EventRef event) { event_release(event_from(event)); }

EventRef carbon_CopyEvent(EventRef event) CARBON_SYMBOL(CopyEvent);
EventRef carbon_CopyEvent(EventRef event) {
    if (!(event = event_from(event))) return NULL;
    EventRef copy = event_new(event->eventClass, event->kind, event->time);
    for (event_parameter *parameter = event->parameters; copy && parameter; parameter = parameter->next)
        event_set(copy, parameter->name, parameter->type, parameter->size, parameter->data);
    return copy;
}

uint32_t carbon_GetEventClass(EventRef event) CARBON_SYMBOL(GetEventClass);
uint32_t carbon_GetEventClass(EventRef event) { return (event = event_from(event)) ? event->eventClass : 0; }

uint32_t carbon_GetEventKind(EventRef event) CARBON_SYMBOL(GetEventKind);
uint32_t carbon_GetEventKind(EventRef event) { return (event = event_from(event)) ? event->kind : 0; }

double carbon_GetEventTime(EventRef event) CARBON_SYMBOL(GetEventTime);
double carbon_GetEventTime(EventRef event) { return (event = event_from(event)) ? event->time : 0; }

double carbon_GetCurrentEventTime(void) CARBON_SYMBOL(GetCurrentEventTime);
double carbon_GetCurrentEventTime(void) { return carbon_now(); }

OSStatus carbon_SetEventParameter(EventRef event, uint32_t name, uint32_t type, size_t size, const void *data)
    CARBON_SYMBOL(SetEventParameter);
OSStatus carbon_SetEventParameter(EventRef event, uint32_t name, uint32_t type, size_t size, const void *data) {
    if (!(event = event_from(event)) || (size && !data)) return paramErr;
    event_set(event, name, type, size, data);
    return noErr;
}

/// A parameter as the type asked for: points convert between QuickDraw's
/// and HIToolbox's, integers between their sizes.
OSStatus carbon_GetEventParameter(EventRef event, uint32_t name, uint32_t desired, uint32_t *actual, size_t size,
                                  size_t *actualSize, void *data) CARBON_SYMBOL(GetEventParameter);
OSStatus carbon_GetEventParameter(EventRef event, uint32_t name, uint32_t desired, uint32_t *actual, size_t size,
                                  size_t *actualSize, void *data) {
    if (!(event = event_from(event))) return paramErr;
    event_parameter *parameter = event->parameters;
    while (parameter && parameter->name != name) parameter = parameter->next;
    if (!parameter) return eventParameterNotFoundErr;
    const void *value = parameter->data;
    size_t length = parameter->size;
    uint32_t type = parameter->type;
    Point qd;
    HIPoint hi;
    if (desired == typeQDPoint && type == typeHIPoint) {
        const HIPoint *point = value;
        qd = (Point){(int16_t)lroundf(point->y), (int16_t)lroundf(point->x)};
        value = &qd, length = sizeof qd, type = typeQDPoint;
    } else if (desired == typeHIPoint && type == typeQDPoint) {
        const Point *point = value;
        hi = (HIPoint){point->h, point->v};
        value = &hi, length = sizeof hi, type = typeHIPoint;
    }
    if (actual) *actual = type;
    if (actualSize) *actualSize = length;
    if (data) memcpy(data, value, length < size ? length : size);
    return noErr;
}

// MARK: - Targets and handlers

typedef struct {
    uint32_t eventClass, kind;
} EventTypeSpec;

typedef OSStatus (*EventHandlerProc)(void *next, EventRef event, void *userData);

typedef struct carbon_handler {
    uint32_t magic;
    carbon_target *target;
    EventHandlerProc procedure;
    void *userData;
    EventTypeSpec *types;
    size_t count;
    struct carbon_handler *next;
} carbon_handler;

#define CARBON_HANDLER_MAGIC 0x484e444cu   // 'HNDL'

struct carbon_target {
    void *owner;
    carbon_handler *handlers;   // the last installed first
};

static carbon_target application_target, dispatcher_target;

carbon_target *carbon_application_target(void) { return &application_target; }

carbon_target *carbon_target_new(void *owner) {
    carbon_target *target = calloc(1, sizeof *target);
    if (target) target->owner = owner;
    return target;
}

void carbon_target_free(carbon_target *target) {
    if (!target) return;
    for (carbon_handler *handler = target->handlers, *next; handler; handler = next) {
        next = handler->next;
        handler->magic = 0;
        free(handler->types);
        free(handler);
    }
    free(target);
}

carbon_target *carbon_GetApplicationEventTarget(void) CARBON_SYMBOL(GetApplicationEventTarget);
carbon_target *carbon_GetApplicationEventTarget(void) { return &application_target; }

carbon_target *carbon_GetEventDispatcherTarget(void) CARBON_SYMBOL(GetEventDispatcherTarget);
carbon_target *carbon_GetEventDispatcherTarget(void) { return &dispatcher_target; }

carbon_target *carbon_GetWindowEventTarget(WindowRef window) CARBON_SYMBOL(GetWindowEventTarget);
carbon_target *carbon_GetWindowEventTarget(WindowRef window) {
    return (window = carbon_window_from(window)) ? window->target : NULL;
}

carbon_target *carbon_GetUserFocusEventTarget(void) CARBON_SYMBOL(GetUserFocusEventTarget);
carbon_target *carbon_GetUserFocusEventTarget(void) {
    WindowRef window = carbon_front_window();
    return window ? window->target : &application_target;
}

static bool handles(const carbon_handler *handler, uint32_t eventClass, uint32_t kind) {
    for (size_t index = 0; index < handler->count; index++)
        if (handler->types[index].eventClass == eventClass && handler->types[index].kind == kind) return true;
    return false;
}

static OSStatus add_types(carbon_handler *handler, size_t count, const EventTypeSpec *types) {
    if (!count) return noErr;
    EventTypeSpec *grown = realloc(handler->types, (handler->count + count) * sizeof *grown);
    if (!grown) return memFullErr;
    memcpy(grown + handler->count, types, count * sizeof *grown);
    handler->types = grown;
    handler->count += count;
    return noErr;
}

OSStatus carbon_InstallEventHandler(carbon_target *target, EventHandlerProc procedure, size_t count, const EventTypeSpec *types,
                                    void *userData, carbon_handler **out) CARBON_SYMBOL(InstallEventHandler);
OSStatus carbon_InstallEventHandler(carbon_target *target, EventHandlerProc procedure, size_t count, const EventTypeSpec *types,
                                    void *userData, carbon_handler **out) {
    if (!target || !procedure) return paramErr;
    carbon_handler *handler = calloc(1, sizeof *handler);
    if (!handler) return memFullErr;
    handler->magic = CARBON_HANDLER_MAGIC;
    handler->target = target;
    handler->procedure = procedure;
    handler->userData = userData;
    if (add_types(handler, count, types) != noErr) {
        free(handler);
        return memFullErr;
    }
    handler->next = target->handlers;
    target->handlers = handler;
    if (out) *out = handler;
    CARBON_TRACE("handler %p on target %p for %zu types", (void *)handler, (void *)target, count);
    return noErr;
}

OSStatus carbon_RemoveEventHandler(carbon_handler *handler) CARBON_SYMBOL(RemoveEventHandler);
OSStatus carbon_RemoveEventHandler(carbon_handler *handler) {
    if (!handler || handler->magic != CARBON_HANDLER_MAGIC) return paramErr;
    for (carbon_handler **link = &handler->target->handlers; *link; link = &(*link)->next)
        if (*link == handler) {
            *link = handler->next;
            break;
        }
    handler->magic = 0;
    free(handler->types);
    free(handler);
    return noErr;
}

OSStatus carbon_AddEventTypesToHandler(carbon_handler *handler, size_t count, const EventTypeSpec *types)
    CARBON_SYMBOL(AddEventTypesToHandler);
OSStatus carbon_AddEventTypesToHandler(carbon_handler *handler, size_t count, const EventTypeSpec *types) {
    if (!handler || handler->magic != CARBON_HANDLER_MAGIC) return paramErr;
    return add_types(handler, count, types);
}

OSStatus carbon_RemoveEventTypesFromHandler(carbon_handler *handler, size_t count, const EventTypeSpec *types)
    CARBON_SYMBOL(RemoveEventTypesFromHandler);
OSStatus carbon_RemoveEventTypesFromHandler(carbon_handler *handler, size_t count, const EventTypeSpec *types) {
    if (!handler || handler->magic != CARBON_HANDLER_MAGIC) return paramErr;
    for (size_t removed = 0; removed < count; removed++)
        for (size_t index = 0; index < handler->count; index++)
            if (handler->types[index].eventClass == types[removed].eventClass && handler->types[index].kind == types[removed].kind) {
                handler->types[index] = handler->types[--handler->count];
                break;
            }
    return noErr;
}

// The handlers still to call for an event, in the chain from the target
// it was sent to, to the application's.
typedef struct {
    carbon_target *chain[3];
    int target;
    carbon_handler *handler;
} handler_call;

static OSStatus default_handling(EventRef event, carbon_target *target);

static OSStatus call_from(handler_call *call, EventRef event) {
    for (; call->target < 3 && call->chain[call->target]; call->target++, call->handler = NULL) {
        carbon_handler *handler = call->handler ? call->handler->next : call->chain[call->target]->handlers;
        for (; handler; handler = handler->next) {
            if (!handles(handler, event->eventClass, event->kind)) continue;
            call->handler = handler;
            OSStatus status = handler->procedure(call, event, handler->userData);
            if (status != eventNotHandledErr) return status;
        }
    }
    return default_handling(event, call->chain[0]);
}

OSStatus carbon_CallNextEventHandler(handler_call *call, EventRef event) CARBON_SYMBOL(CallNextEventHandler);
OSStatus carbon_CallNextEventHandler(handler_call *call, EventRef event) {
    if (!call || !(event = event_from(event))) return paramErr;
    // The handler that calls this goes on from its own place in the chain.
    handler_call next = *call;
    return call_from(&next, event);
}

static OSStatus send_event(EventRef event, carbon_target *target) {
    handler_call call = {{target, NULL, NULL}, 0, NULL};
    if (target != &application_target) call.chain[1] = &application_target;
    return call_from(&call, event);
}

OSStatus carbon_SendEventToEventTarget(EventRef event, carbon_target *target) CARBON_SYMBOL(SendEventToEventTarget);
OSStatus carbon_SendEventToEventTarget(EventRef event, carbon_target *target) {
    if (!(event = event_from(event)) || !target) return paramErr;
    return send_event(event, target);
}

OSStatus carbon_SendEventToEventTargetWithOptions(EventRef event, carbon_target *target, uint32_t options)
    CARBON_SYMBOL(SendEventToEventTargetWithOptions);
OSStatus carbon_SendEventToEventTargetWithOptions(EventRef event, carbon_target *target, uint32_t options) {
    (void)options;
    return carbon_SendEventToEventTarget(event, target);
}

// MARK: - The event loop

static int loop_token, quit_requested, loop_depth;

void *carbon_GetMainEventLoop(void) CARBON_SYMBOL(GetMainEventLoop);
void *carbon_GetMainEventLoop(void) { return &loop_token; }

void *carbon_GetCurrentEventLoop(void) CARBON_SYMBOL(GetCurrentEventLoop);
void *carbon_GetCurrentEventLoop(void) { return &loop_token; }

void *carbon_GetMainEventQueue(void) CARBON_SYMBOL(GetMainEventQueue);
void *carbon_GetMainEventQueue(void) { return &loop_token; }

void *carbon_GetCurrentEventQueue(void) CARBON_SYMBOL(GetCurrentEventQueue);
void *carbon_GetCurrentEventQueue(void) { return &loop_token; }

typedef void (*EventLoopTimerProc)(void *timer, void *userData);

typedef struct carbon_timer {
    uint32_t magic;
    double fire, interval;
    EventLoopTimerProc procedure;
    void *userData;
    bool firing, removed;
    struct carbon_timer *next;
} carbon_timer;

#define CARBON_TIMER_MAGIC 0x544d5252u   // 'TMRR'

static carbon_timer *timers;

OSStatus carbon_InstallEventLoopTimer(void *loop, double delay, double interval, EventLoopTimerProc procedure, void *userData,
                                      carbon_timer **out) CARBON_SYMBOL(InstallEventLoopTimer);
OSStatus carbon_InstallEventLoopTimer(void *loop, double delay, double interval, EventLoopTimerProc procedure, void *userData,
                                      carbon_timer **out) {
    (void)loop;
    if (!procedure) return paramErr;
    carbon_timer *timer = calloc(1, sizeof *timer);
    if (!timer) return memFullErr;
    timer->magic = CARBON_TIMER_MAGIC;
    timer->fire = carbon_now() + delay;
    timer->interval = interval;
    timer->procedure = procedure;
    timer->userData = userData;
    timer->next = timers;
    timers = timer;
    if (out) *out = timer;
    CARBON_TRACE("timer %p: in %.3f s, every %.3f s", (void *)timer, delay, interval);
    return noErr;
}

static void timer_free(carbon_timer *timer) {
    for (carbon_timer **link = &timers; *link; link = &(*link)->next)
        if (*link == timer) {
            *link = timer->next;
            break;
        }
    timer->magic = 0;
    free(timer);
}

OSStatus carbon_RemoveEventLoopTimer(carbon_timer *timer) CARBON_SYMBOL(RemoveEventLoopTimer);
OSStatus carbon_RemoveEventLoopTimer(carbon_timer *timer) {
    if (!timer || timer->magic != CARBON_TIMER_MAGIC) return paramErr;
    // A timer removing itself while it fires goes once it returns.
    if (timer->firing) timer->removed = true;
    else timer_free(timer);
    return noErr;
}

OSStatus carbon_SetEventLoopTimerNextFireTime(carbon_timer *timer, double delay) CARBON_SYMBOL(SetEventLoopTimerNextFireTime);
OSStatus carbon_SetEventLoopTimerNextFireTime(carbon_timer *timer, double delay) {
    if (!timer || timer->magic != CARBON_TIMER_MAGIC) return paramErr;
    // kEventDurationForever: never, until set again.
    timer->fire = delay >= 1e9 ? INFINITY : carbon_now() + delay;
    return noErr;
}

/// Fires the timers that are due; the time until the next one.
static double fire_timers(void) {
    double now = carbon_now();
    for (carbon_timer *timer = timers, *next; timer; timer = next) {
        next = timer->next;
        if (timer->fire > now || timer->firing) continue;
        timer->firing = true;
        timer->fire = timer->interval > 0 ? now + timer->interval : INFINITY;
        timer->procedure(timer, timer->userData);
        timer->firing = false;
        // The list may have changed while it fired: start again from the
        // front the next time round.
        if (timer->removed) timer_free(timer);
        next = NULL;
        now = carbon_now();
        for (carbon_timer *other = timers; other; other = other->next)
            if (other->fire <= now && !other->firing) { next = other; break; }
    }
    double soonest = INFINITY;
    for (carbon_timer *timer = timers; timer; timer = timer->next)
        if (timer->fire < soonest) soonest = timer->fire;
    return soonest - carbon_now();
}

// MARK: - The keyboard and mouse

static uint8_t key_map[16];
static uint32_t modifiers;   // Carbon's
static uint32_t buttons;
static int click_count;

static uint32_t carbon_modifiers(unsigned long flags) {
    uint32_t result = 0;
    if (flags & (1ul << 16)) result |= 0x0400;   // alphaLock
    if (flags & (1ul << 17)) result |= 0x0200;   // shiftKey
    if (flags & (1ul << 18)) result |= 0x1000;   // controlKey
    if (flags & (1ul << 19)) result |= 0x0800;   // optionKey
    if (flags & (1ul << 20)) result |= 0x0100;   // cmdKey
    return result;
}

static void set_key(unsigned code, bool down) {
    if (code >= 128) return;
    if (down) key_map[code >> 3] |= (uint8_t)(1u << (code & 7));
    else key_map[code >> 3] &= (uint8_t)~(1u << (code & 7));
}

void carbon_GetKeys(uint8_t *keys) CARBON_SYMBOL(GetKeys);
void carbon_GetKeys(uint8_t *keys) { if (keys) memcpy(keys, key_map, sizeof key_map); }

uint32_t carbon_GetCurrentKeyModifiers(void) CARBON_SYMBOL(GetCurrentKeyModifiers);
uint32_t carbon_GetCurrentKeyModifiers(void) { return modifiers; }

uint32_t carbon_GetCurrentEventKeyModifiers(void) CARBON_SYMBOL(GetCurrentEventKeyModifiers);
uint32_t carbon_GetCurrentEventKeyModifiers(void) { return modifiers; }

uint32_t carbon_GetCurrentButtonState(void) CARBON_SYMBOL(GetCurrentButtonState);
uint32_t carbon_GetCurrentButtonState(void) { return buttons; }

uint32_t carbon_GetCurrentEventButtonState(void) CARBON_SYMBOL(GetCurrentEventButtonState);
uint32_t carbon_GetCurrentEventButtonState(void) { return buttons; }

Boolean carbon_Button(void) CARBON_SYMBOL(Button);
Boolean carbon_Button(void) { return (buttons & 1) != 0; }

Boolean carbon_StillDown(void) CARBON_SYMBOL(StillDown);
Boolean carbon_StillDown(void) { return (buttons & 1) != 0; }

/// The mouse, in global coordinates: from the top left of the main screen.
static Point global_mouse(void) {
    NSPoint location = ((NSPoint (*)(id, SEL))objc_send)(CLASS("NSEvent"), SELECTOR("mouseLocation"));
    int16_t height = (*carbon_main_device())->gdRect.bottom;
    return (Point){(int16_t)lround(height - location.y), (int16_t)lround(location.x)};
}

void carbon_GetGlobalMouse(Point *point) CARBON_SYMBOL(GetGlobalMouse);
void carbon_GetGlobalMouse(Point *point) { if (point) *point = global_mouse(); }

void carbon_GetMouse(Point *point) CARBON_SYMBOL(GetMouse);
void carbon_GetMouse(Point *point) {
    if (!point) return;
    *point = global_mouse();
    carbon_GlobalToLocal(point);
}

// MARK: - From AppKit's events

enum {
    NSLeftMouseDown = 1, NSLeftMouseUp = 2, NSRightMouseDown = 3, NSRightMouseUp = 4, NSMouseMoved = 5,
    NSLeftMouseDragged = 6, NSRightMouseDragged = 7, NSKeyDown = 10, NSKeyUp = 11, NSFlagsChanged = 12,
    NSScrollWheel = 22, NSOtherMouseDown = 25, NSOtherMouseUp = 26, NSOtherMouseDragged = 27,
};

static unsigned long ns_type(id event) { return ((unsigned long (*)(id, SEL))objc_send)(event, SELECTOR("type")); }

static WindowRef event_window(id event) {
    id nswindow = SEND(event, "window");
    return nswindow ? carbon_window_for_nswindow(nswindow) : NULL;
}

/// The Carbon event an NSEvent is, or NULL.
static EventRef carbon_event_for(id nsevent) {
    unsigned long type = ns_type(nsevent);
    unsigned long flags = ((unsigned long (*)(id, SEL))objc_send)(nsevent, SELECTOR("modifierFlags"));
    double time = ((double (*)(id, SEL))objc_send)(nsevent, SELECTOR("timestamp"));
    modifiers = carbon_modifiers(flags);
    EventRef event = NULL;
    switch (type) {
    case NSLeftMouseDown: case NSRightMouseDown: case NSOtherMouseDown:
    case NSLeftMouseUp: case NSRightMouseUp: case NSOtherMouseUp:
    case NSMouseMoved: case NSLeftMouseDragged: case NSRightMouseDragged: case NSOtherMouseDragged:
    case NSScrollWheel: {
        uint32_t kind;
        uint16_t button = 1;
        if (type == NSRightMouseDown || type == NSRightMouseUp || type == NSRightMouseDragged) button = 2;
        if (type == NSOtherMouseDown || type == NSOtherMouseUp || type == NSOtherMouseDragged) button = 3;
        switch (type) {
        case NSLeftMouseDown: case NSRightMouseDown: case NSOtherMouseDown:
            kind = 1; buttons |= 1u << (button - 1); break;
        case NSLeftMouseUp: case NSRightMouseUp: case NSOtherMouseUp:
            kind = 2; buttons &= ~(1u << (button - 1)); break;
        case NSMouseMoved: kind = 5; break;
        case NSScrollWheel: kind = 10; break;
        default: kind = 6; break;
        }
        event = event_new(kEventClassMouse, kind, time);
        Point where = global_mouse();
        HIPoint location = {where.h, where.v};
        event_set(event, kEventParamMouseLocation, typeHIPoint, sizeof location, &location);
        WindowRef window = event_window(nsevent);
        if (window) {
            HIPoint local = {location.x - window->bounds.left, location.y - window->bounds.top};
            event_set(event, kEventParamWindowMouseLocation, typeHIPoint, sizeof local, &local);
            event_set(event, kEventParamWindowRef, typeWindowRef, sizeof window, &window);
        }
        event_set(event, kEventParamKeyModifiers, typeUInt32, sizeof modifiers, &modifiers);
        if (kind == 1 || kind == 2 || kind == 6) {
            event_set(event, kEventParamMouseButton, typeMouseButton, sizeof button, &button);
            long clicks = ((long (*)(id, SEL))objc_send)(nsevent, SELECTOR("clickCount"));
            click_count = (int)clicks;
            uint32_t count = (uint32_t)clicks;
            event_set(event, kEventParamClickCount, typeUInt32, sizeof count, &count);
            event_set(event, kEventParamMouseChord, typeUInt32, sizeof buttons, &buttons);
        }
        if (kind == 5 || kind == 6) {
            CGFloat dx = ((CGFloat (*)(id, SEL))objc_send)(nsevent, SELECTOR("deltaX"));
            CGFloat dy = ((CGFloat (*)(id, SEL))objc_send)(nsevent, SELECTOR("deltaY"));
            HIPoint delta = {(float)dx, (float)dy};
            event_set(event, kEventParamMouseDelta, typeHIPoint, sizeof delta, &delta);
        }
        if (kind == 10) {
            CGFloat dy = ((CGFloat (*)(id, SEL))objc_send)(nsevent, SELECTOR("deltaY"));
            CGFloat dx = ((CGFloat (*)(id, SEL))objc_send)(nsevent, SELECTOR("deltaX"));
            uint16_t axis = fabs((double)dx) > fabs((double)dy) ? 0 : 1;   // kEventMouseWheelAxisX, Y
            int32_t delta = (int32_t)lround(axis ? dy : dx);
            if (delta == 0) delta = (axis ? dy : dx) > 0 ? 1 : -1;
            event_set(event, kEventParamMouseWheelAxis, typeMouseWheelAxis, sizeof axis, &axis);
            event_set(event, kEventParamMouseWheelDelta, typeSInt32, sizeof delta, &delta);
        }
        break;
    }
    case NSKeyDown: case NSKeyUp: {
        unsigned short code = ((unsigned short (*)(id, SEL))objc_send)(nsevent, SELECTOR("keyCode"));
        bool repeat = type == NSKeyDown && ((signed char (*)(id, SEL))objc_send)(nsevent, SELECTOR("isARepeat"));
        set_key(code, type == NSKeyDown);
        event = event_new(kEventClassKeyboard, type == NSKeyUp ? 3 : repeat ? 2 : 1, time);
        uint32_t key = code;
        event_set(event, kEventParamKeyCode, typeUInt32, sizeof key, &key);
        event_set(event, kEventParamKeyModifiers, typeUInt32, sizeof modifiers, &modifiers);
        uint32_t keyboard = 40;   // an ANSI keyboard
        event_set(event, kEventParamKeyboardType, typeUInt32, sizeof keyboard, &keyboard);
        id characters = SEND(nsevent, "charactersIgnoringModifiers");
        id typed = SEND(nsevent, "characters");
        const char *utf8 = typed ? ((const char *(*)(id, SEL))objc_send)(typed, SELECTOR("UTF8String")) : NULL;
        if (!utf8 && characters) utf8 = ((const char *(*)(id, SEL))objc_send)(characters, SELECTOR("UTF8String"));
        char mac = utf8 && (unsigned char)utf8[0] < 0x80 ? utf8[0] : 0;
        event_set(event, kEventParamKeyMacCharCodes, typeChar, 1, &mac);
        unsigned long length = typed ? ((unsigned long (*)(id, SEL))objc_send)(typed, SELECTOR("length")) : 0;
        if (length) {
            uint16_t units[16];
            if (length > 16) length = 16;
            for (unsigned long index = 0; index < length; index++)
                units[index] = ((uint16_t (*)(id, SEL, unsigned long))objc_send)(typed, SELECTOR("characterAtIndex:"), index);
            event_set(event, kEventParamKeyUnicodes, typeUnicodeText, length * 2, units);
        }
        break;
    }
    case NSFlagsChanged: {
        unsigned short code = ((unsigned short (*)(id, SEL))objc_send)(nsevent, SELECTOR("keyCode"));
        // The modifier key's own state, from whether its flag is now set.
        uint32_t bit = 0;
        switch (code) {
        case 56: case 60: bit = 0x0200; break;
        case 59: case 62: bit = 0x1000; break;
        case 58: case 61: bit = 0x0800; break;
        case 55: case 54: bit = 0x0100; break;
        case 57: bit = 0x0400; break;
        }
        set_key(code, (modifiers & bit) != 0);
        event = event_new(kEventClassKeyboard, 4, time);
        event_set(event, kEventParamKeyModifiers, typeUInt32, sizeof modifiers, &modifiers);
        break;
    }
    default:
        break;
    }
    if (event) event->nsevent = nsevent;
    return event;
}

/// The next of AppKit's events, waiting at most `timeout` seconds.
static id next_nsevent(double timeout) {
    id application = carbon_application();
    id date = timeout <= 0 ? SEND(CLASS("NSDate"), "distantPast")
            : timeout >= 1e9 ? SEND(CLASS("NSDate"), "distantFuture")
            : ((id (*)(id, SEL, double))objc_send)(CLASS("NSDate"), SELECTOR("dateWithTimeIntervalSinceNow:"), timeout);
    id mode = carbon_string("kCFRunLoopDefaultMode");
    return ((id (*)(id, SEL, unsigned long, id, id, signed char))objc_send)(
        application, SELECTOR("nextEventMatchingMask:untilDate:inMode:dequeue:"), ~0ul, date, mode, 1);
}

/// Sends an AppKit event to Carbon's handlers, then to AppKit, which keeps
/// its windows: moving them, closing them, its menus.
static void dispatch(id nsevent) {
    EventRef event = carbon_event_for(nsevent);
    OSStatus status = eventNotHandledErr;
    if (event) {
        WindowRef window = event->eventClass == kEventClassMouse ? event_window(nsevent) : carbon_front_window();
        status = send_event(event, window ? window->target : &application_target);
        event_release(event);
    }
    (void)status;
    ((void (*)(id, SEL, id))objc_send)(carbon_application(), SELECTOR("sendEvent:"), nsevent);
}

/// What happens to an event no handler took: a quit command quits.
static OSStatus default_handling(EventRef event, carbon_target *target) {
    (void)target;
    if (event->eventClass == kEventClassCommand && event->kind == 1) {
        uint32_t command[4] = {0};
        if (carbon_GetEventParameter(event, kEventParamDirectObject, typeHICommand, NULL, sizeof command, NULL, command) == noErr &&
            command[1] == kHICommandQuit) {
            return carbon_quit_requested();
        }
    }
    return eventNotHandledErr;
}

/// The application is asked to quit: its Apple event handler for 'quit' if
/// it has one, else the event loop ends.
OSStatus carbon_quit_requested(void) {
    if (!carbon_apple_event_quit()) quit_requested = 1;
    return noErr;
}

/// Runs the loop until it is told to quit, firing the timers and handing
/// on events as they come.
static void run_loop(int *quit) {
    loop_depth++;
    while (!*quit) {
        double wait = fire_timers();
        if (*quit) break;
        id event = next_nsevent(wait < 0 ? 0 : wait > 0.25 ? 0.25 : wait);
        if (event) dispatch(event);
    }
    loop_depth--;
}

void carbon_RunApplicationEventLoop(void) CARBON_SYMBOL(RunApplicationEventLoop);
void carbon_RunApplicationEventLoop(void) {
    carbon_apple_event_open();
    quit_requested = 0;
    run_loop(&quit_requested);
}

void carbon_QuitApplicationEventLoop(void) CARBON_SYMBOL(QuitApplicationEventLoop);
void carbon_QuitApplicationEventLoop(void) { quit_requested = 1; }

/// Runs the loop for at most `timeout` seconds.
OSStatus carbon_RunCurrentEventLoop(double timeout) CARBON_SYMBOL(RunCurrentEventLoop);
OSStatus carbon_RunCurrentEventLoop(double timeout) {
    double until = carbon_now() + timeout;
    do {
        double wait = fire_timers();
        double left = until - carbon_now();
        if (wait > left) wait = left;
        id event = next_nsevent(wait < 0 ? 0 : wait);
        if (event) dispatch(event);
    } while (carbon_now() < until && !quit_requested);
    return quit_requested ? eventLoopQuitErr : eventLoopTimedOutErr;
}

// Modal loops: one for each window, until it's told to end.
static int modal_quit[8];
static WindowRef modal_windows[8];
static int modal_depth;

OSStatus carbon_RunAppModalLoopForWindow(WindowRef window) CARBON_SYMBOL(RunAppModalLoopForWindow);
OSStatus carbon_RunAppModalLoopForWindow(WindowRef window) {
    if (modal_depth >= 8) return paramErr;
    int depth = modal_depth++;
    modal_windows[depth] = window;
    modal_quit[depth] = 0;
    run_loop(&modal_quit[depth]);
    modal_depth--;
    return noErr;
}

OSStatus carbon_QuitAppModalLoopForWindow(WindowRef window) CARBON_SYMBOL(QuitAppModalLoopForWindow);
OSStatus carbon_QuitAppModalLoopForWindow(WindowRef window) {
    for (int depth = modal_depth - 1; depth >= 0; depth--)
        if (modal_windows[depth] == window) {
            modal_quit[depth] = 1;
            return noErr;
        }
    return paramErr;
}

OSStatus carbon_BeginAppModalStateForWindow(WindowRef window) CARBON_SYMBOL(BeginAppModalStateForWindow);
OSStatus carbon_BeginAppModalStateForWindow(WindowRef window) { return carbon_window_from(window) ? noErr : errInvalidWindowRef; }

OSStatus carbon_EndAppModalStateForWindow(WindowRef window) CARBON_SYMBOL(EndAppModalStateForWindow);
OSStatus carbon_EndAppModalStateForWindow(WindowRef window) { return carbon_window_from(window) ? noErr : errInvalidWindowRef; }

/// Takes the next event from the queue, firing timers while it waits.
OSStatus carbon_ReceiveNextEvent(size_t count, const EventTypeSpec *types, double timeout, Boolean pull, EventRef *out)
    CARBON_SYMBOL(ReceiveNextEvent);
OSStatus carbon_ReceiveNextEvent(size_t count, const EventTypeSpec *types, double timeout, Boolean pull, EventRef *out) {
    double until = carbon_now() + (timeout > 1e9 ? 1e9 : timeout);
    for (;;) {
        double wait = fire_timers();
        double left = until - carbon_now();
        if (wait > left) wait = left;
        id nsevent = next_nsevent(wait < 0 ? 0 : wait);
        if (nsevent) {
            EventRef event = carbon_event_for(nsevent);
            bool wanted = event && (count == 0 || !types);
            for (size_t index = 0; event && !wanted && index < count; index++)
                wanted = types[index].eventClass == event->eventClass && types[index].kind == event->kind;
            if (wanted) {
                if (out) *out = event;
                else event_release(event);
                (void)pull;
                return noErr;
            }
            event_release(event);
            ((void (*)(id, SEL, id))objc_send)(carbon_application(), SELECTOR("sendEvent:"), nsevent);
        }
        if (quit_requested) return eventLoopQuitErr;
        if (carbon_now() >= until) return eventLoopTimedOutErr;
    }
}

// MARK: - The original Event Manager

enum { nullEvent = 0, mouseDown = 1, mouseUp = 2, keyDown = 3, keyUp = 4, autoKey = 5, osEvt = 15 };

static void fill_record(EventRecord *record, int16_t what, uint32_t message) {
    record->what = what;
    record->message = message;
    record->when = (uint32_t)(carbon_now() * 60.0);
    record->where = global_mouse();
    record->modifiers = (uint16_t)(modifiers | (buttons & 1 ? 0 : 0x80));   // btnState: the button is up
}

/// The next event of those in the mask, waiting at most `sleep` ticks: the
/// mouse's and keyboard's become records; the others go to AppKit.
Boolean carbon_WaitNextEvent(uint16_t mask, EventRecord *record, uint32_t sleep, RgnHandle mouse) CARBON_SYMBOL(WaitNextEvent);
Boolean carbon_WaitNextEvent(uint16_t mask, EventRecord *record, uint32_t sleep, RgnHandle mouse) {
    (void)mouse;
    double until = carbon_now() + sleep / 60.0;
    for (;;) {
        double wait = fire_timers();
        double left = until - carbon_now();
        if (wait > left) wait = left;
        id nsevent = next_nsevent(wait < 0 ? 0 : wait);
        if (nsevent) {
            EventRef event = carbon_event_for(nsevent);
            int16_t what = nullEvent;
            uint32_t message = 0;
            if (event && event->eventClass == kEventClassMouse && (event->kind == 1 || event->kind == 2))
                what = event->kind == 1 ? mouseDown : mouseUp;
            if (event && event->eventClass == kEventClassKeyboard && event->kind <= 3) {
                what = event->kind == 1 ? keyDown : event->kind == 2 ? autoKey : keyUp;
                uint32_t code = 0;
                char character = 0;
                carbon_GetEventParameter(event, kEventParamKeyCode, typeUInt32, NULL, sizeof code, NULL, &code);
                carbon_GetEventParameter(event, kEventParamKeyMacCharCodes, typeChar, NULL, 1, NULL, &character);
                message = (code & 0xff) << 8 | (uint8_t)character;
            }
            event_release(event);
            if (what != nullEvent && (mask & (1u << what))) {
                fill_record(record, what, message);
                return 1;
            }
            ((void (*)(id, SEL, id))objc_send)(carbon_application(), SELECTOR("sendEvent:"), nsevent);
        }
        if (carbon_now() >= until) break;
    }
    fill_record(record, nullEvent, 0);
    return 0;
}

/// Whether an event of those in the mask is waiting, without taking it.
/// AppKit's queue can't be looked into without taking from it, so none is:
/// the record is a null event's with the mouse and the modifier keys, which
/// is what programs asking with a mask of 0 at startup (is Option down?) want.
Boolean carbon_EventAvail(uint16_t mask, EventRecord *record) CARBON_SYMBOL(EventAvail);
Boolean carbon_EventAvail(uint16_t mask, EventRecord *record) {
    (void)mask;
    if (record) fill_record(record, nullEvent, 0);
    return 0;
}

Boolean carbon_GetNextEvent(uint16_t mask, EventRecord *record) CARBON_SYMBOL(GetNextEvent);
Boolean carbon_GetNextEvent(uint16_t mask, EventRecord *record) { return carbon_WaitNextEvent(mask, record, 0, NULL); }

void carbon_FlushEvents(uint16_t mask, uint16_t stop) CARBON_SYMBOL(FlushEvents);
void carbon_FlushEvents(uint16_t mask, uint16_t stop) {
    (void)mask; (void)stop;
    // AppKit's queue keeps its own; the events already waiting are dropped.
    id event;
    while ((event = next_nsevent(0))) {
        unsigned long type = ns_type(event);
        if (type != NSKeyDown && type != NSKeyUp && type != NSLeftMouseDown && type != NSLeftMouseUp)
            ((void (*)(id, SEL, id))objc_send)(carbon_application(), SELECTOR("sendEvent:"), event);
    }
}

/// Drops the events waiting in the queue, as FlushEvents does all of them.
OSStatus carbon_FlushEventQueue(void *queue) CARBON_SYMBOL(FlushEventQueue);
OSStatus carbon_FlushEventQueue(void *queue) {
    (void)queue;
    carbon_FlushEvents(0xffff, 0);
    return noErr;
}

/// An event as the original Event Manager's record.
Boolean carbon_ConvertEventRefToEventRecord(EventRef event, EventRecord *record) CARBON_SYMBOL(ConvertEventRefToEventRecord);
Boolean carbon_ConvertEventRefToEventRecord(EventRef event, EventRecord *record) {
    if (!(event = event_from(event)) || !record) return 0;
    if (event->eventClass == kEventClassMouse && (event->kind == 1 || event->kind == 2)) {
        fill_record(record, event->kind == 1 ? mouseDown : mouseUp, 0);
        return 1;
    }
    if (event->eventClass == kEventClassKeyboard && event->kind <= 3) {
        uint32_t code = 0;
        char character = 0;
        carbon_GetEventParameter(event, kEventParamKeyCode, typeUInt32, NULL, sizeof code, NULL, &code);
        carbon_GetEventParameter(event, kEventParamKeyMacCharCodes, typeChar, NULL, 1, NULL, &character);
        fill_record(record, event->kind == 1 ? keyDown : event->kind == 2 ? autoKey : keyUp, (code & 0xff) << 8 | (uint8_t)character);
        return 1;
    }
    fill_record(record, nullEvent, 0);
    return 0;
}

/// A key's character in the US keyboard layout, from its code and
/// modifiers ('KCHR' resources aren't kept).
uint32_t carbon_KeyTranslate(const void *table, uint16_t keycode, uint32_t *state) CARBON_SYMBOL(KeyTranslate);
uint32_t carbon_KeyTranslate(const void *table, uint16_t keycode, uint32_t *state) {
    (void)table; (void)state;
    static const char lower[] = "asdfhgzxcv\0bqweryt123465=97-80]ou[ip\rlj'k;\\,/nm.\t `";
    static const char upper[] = "ASDFHGZXCV\0BQWERYT!@#$^%+(&_*)}OU{IP\rLJ\"K:|<?NM>\t ~";
    unsigned code = keycode & 0x7f;
    bool shift = (keycode & 0x200) != 0;
    char character = code < sizeof lower - 1 ? (shift ? upper : lower)[code] : 0;
    if (code == 51) character = 8;     // delete
    if (code == 53) character = 27;    // escape
    return (uint8_t)character;
}

// MARK: - Hot keys

OSStatus carbon_RegisterEventHotKey(uint32_t code, uint32_t modifierKeys, uint64_t identifier, carbon_target *target,
                                    uint32_t options, void **out) CARBON_SYMBOL(RegisterEventHotKey);
OSStatus carbon_RegisterEventHotKey(uint32_t code, uint32_t modifierKeys, uint64_t identifier, carbon_target *target,
                                    uint32_t options, void **out) {
    (void)code; (void)modifierKeys; (void)identifier; (void)target; (void)options;
    // System-wide hot keys aren't taken from other programs: the key comes
    // to the program as a key press when it is in front.
    static int token;
    if (out) *out = &token;
    return noErr;
}

OSStatus carbon_UnregisterEventHotKey(void *hotKey) CARBON_SYMBOL(UnregisterEventHotKey);
OSStatus carbon_UnregisterEventHotKey(void *hotKey) { (void)hotKey; return noErr; }

// MARK: - Commands

/// A command from a menu item or a control, as Carbon sends it: a
/// kEventCommandProcess event with its HICommand, to the target (a
/// window's for a control's, the focus's for a menu's), on from there to
/// the application's.
OSStatus carbon_process_command(uint32_t command, void *menu, uint16_t item, carbon_target *target) {
#pragma pack(push, 2)
    struct { uint32_t attributes, commandID; void *menuRef; uint16_t menuItemIndex; } hicommand = {menu ? 1u : 0u, command, menu, item};
#pragma pack(pop)
    EventRef event = event_new(kEventClassCommand, 1, 0);
    if (!event) return memFullErr;
    event_set(event, kEventParamDirectObject, typeHICommand, sizeof hicommand, &hicommand);
    CARBON_TRACE("command %c%c%c%c", (char)(command >> 24), (char)(command >> 16), (char)(command >> 8), (char)command);
    if (!target) target = carbon_GetUserFocusEventTarget();
    OSStatus status = send_event(event, target);
    event_release(event);
    return status;
}
