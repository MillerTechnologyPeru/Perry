// The Apple Event Manager is CoreServices': a program's descriptors and
// handlers are there, whichever framework it bound them to. Carbon's event
// loop sends the application its 'oapp' as it starts and 'quit' when asked
// to quit, through CoreServices' handlers.

#include "PerryCarbon.h"

#define FOUR(a, b, c, d) ((uint32_t)(a) << 24 | (uint32_t)(b) << 16 | (uint32_t)(c) << 8 | (uint32_t)(d))

/// High-level events from WaitNextEvent: none come here.
OSErr carbon_AEProcessAppleEvent(const EventRecord *record) CARBON_SYMBOL(AEProcessAppleEvent);
OSErr carbon_AEProcessAppleEvent(const EventRecord *record) {
    (void)record;
    return noErr;
}

/// One of the required events, to the application's handler for it in
/// CoreServices: false if it has none.
static bool send_core(OSType eventID) {
    static bool (*send)(uint32_t);
    if (!send) send = (bool (*)(uint32_t))carbon_function(CORESERVICES, "perry_apple_event_send_core");
    return send && send(eventID);
}

void carbon_apple_event_open(void) {
    static bool sent;
    if (sent) return;
    sent = true;
    send_core(FOUR('o', 'a', 'p', 'p'));
}

bool carbon_apple_event_quit(void) { return send_core(FOUR('q', 'u', 'i', 't')); }
