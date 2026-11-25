// Standard alerts, as AppKit's NSAlerts: the message, the explanation and
// up to three buttons, OK (1), Cancel (2) and the other (3), run modally.
// Each alert's text is written to standard error too.

#include "PerryCarbon.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#pragma pack(push, 2)
typedef struct {
    uint32_t version;
    Boolean movable;
    Boolean helpButton;
    id defaultText;
    id cancelText;
    id otherText;
    int16_t defaultButton;
    int16_t cancelButton;
    uint16_t position;
    uint32_t flags;
} AlertStdCFStringAlertParamRec;

typedef struct {
    Boolean movable;
    Boolean helpButton;
    void *filterProc;
    const unsigned char *defaultText;
    const unsigned char *cancelText;
    const unsigned char *otherText;
    int16_t defaultButton;
    int16_t cancelButton;
    uint16_t position;
} AlertStdAlertParamRec;
#pragma pack(pop)

#define DEFAULT_TEXT ((id)(intptr_t)-1)

typedef struct {
    uint32_t magic;
    id alert;
    int16_t buttons[3];   // the item each of NSAlert's buttons is
    int count;
} carbon_alert;

#define CARBON_ALERT_MAGIC 0x414c5254u   // 'ALRT'

OSStatus carbon_GetStandardAlertDefaultParams(AlertStdCFStringAlertParamRec *parameters, uint32_t version)
    CARBON_SYMBOL(GetStandardAlertDefaultParams);
OSStatus carbon_GetStandardAlertDefaultParams(AlertStdCFStringAlertParamRec *parameters, uint32_t version) {
    if (!parameters) return paramErr;
    memset(parameters, 0, sizeof *parameters);
    parameters->version = version;
    parameters->movable = 1;
    parameters->defaultText = DEFAULT_TEXT;
    parameters->defaultButton = 1;   // kAlertStdAlertOKButton
    return noErr;
}

static const char *utf8(id string) {
    return string ? ((const char *(*)(id, SEL))objc_send)(string, SELECTOR("UTF8String")) : "";
}

static void add_button(carbon_alert *alert, id title, const char *fallback, int16_t item) {
    if (!title || alert->count >= 3) return;
    if (title == DEFAULT_TEXT) title = carbon_string(fallback);
    ((id (*)(id, SEL, id))objc_send)(alert->alert, SELECTOR("addButtonWithTitle:"), title);
    alert->buttons[alert->count++] = item;
}

/// kAlertStopAlert (0), kAlertNoteAlert (1), kAlertCautionAlert (2),
/// kAlertPlainAlert (3): NSAlert's critical, informational, warning and
/// informational styles.
OSStatus carbon_CreateStandardAlert(int16_t type, id error, id explanation, const AlertStdCFStringAlertParamRec *parameters,
                                    carbon_alert **out) CARBON_SYMBOL(CreateStandardAlert);
OSStatus carbon_CreateStandardAlert(int16_t type, id error, id explanation, const AlertStdCFStringAlertParamRec *parameters,
                                    carbon_alert **out) {
    if (!out) return paramErr;
    carbon_application();
    carbon_alert *alert = calloc(1, sizeof *alert);
    if (!alert) return memFullErr;
    alert->magic = CARBON_ALERT_MAGIC;
    alert->alert = SEND(SEND(CLASS("NSAlert"), "alloc"), "init");
    if (error) ((void (*)(id, SEL, id))objc_send)(alert->alert, SELECTOR("setMessageText:"), error);
    if (explanation) ((void (*)(id, SEL, id))objc_send)(alert->alert, SELECTOR("setInformativeText:"), explanation);
    static const unsigned long styles[] = {2, 1, 0, 1};
    ((void (*)(id, SEL, unsigned long))objc_send)(alert->alert, SELECTOR("setAlertStyle:"), styles[type & 3]);
    AlertStdCFStringAlertParamRec defaults;
    if (!parameters) {
        carbon_GetStandardAlertDefaultParams(&defaults, 1);
        parameters = &defaults;
    }
    add_button(alert, parameters->defaultText, "OK", 1);
    add_button(alert, parameters->cancelText, "Cancel", 2);
    add_button(alert, parameters->otherText, "Don't Save", 3);
    if (alert->count == 0) add_button(alert, DEFAULT_TEXT, "OK", 1);
    carbon_warn("alert: %s%s%s", utf8(error), explanation ? " — " : "", utf8(explanation));
    *out = alert;
    return noErr;
}

/// Runs the alert until a button is pressed: its item.
OSStatus carbon_RunStandardAlert(carbon_alert *alert, void *filter, int16_t *item) CARBON_SYMBOL(RunStandardAlert);
OSStatus carbon_RunStandardAlert(carbon_alert *alert, void *filter, int16_t *item) {
    (void)filter;
    if (!alert || alert->magic != CARBON_ALERT_MAGIC) return paramErr;
    long response = ((long (*)(id, SEL))objc_send)(alert->alert, SELECTOR("runModal"));
    long index = response - 1000;   // NSAlertFirstButtonReturn
    if (item) *item = index >= 0 && index < alert->count ? alert->buttons[index] : 1;
    SEND(alert->alert, "release");
    alert->magic = 0;
    free(alert);
    return noErr;
}

static id pascal_string(const unsigned char *text) {
    if (!text) return NULL;
    if (text == (const unsigned char *)(intptr_t)-1) return DEFAULT_TEXT;
    char buffer[256];
    memcpy(buffer, text + 1, text[0]);
    buffer[text[0]] = 0;
    return carbon_string(buffer);
}

/// The original StandardAlert, with Pascal strings.
OSErr carbon_StandardAlert(int16_t type, const unsigned char *error, const unsigned char *explanation,
                           const AlertStdAlertParamRec *parameters, int16_t *item) CARBON_SYMBOL(StandardAlert);
OSErr carbon_StandardAlert(int16_t type, const unsigned char *error, const unsigned char *explanation,
                           const AlertStdAlertParamRec *parameters, int16_t *item) {
    AlertStdCFStringAlertParamRec converted;
    carbon_GetStandardAlertDefaultParams(&converted, 1);
    if (parameters) {
        converted.defaultText = pascal_string(parameters->defaultText);
        converted.cancelText = pascal_string(parameters->cancelText);
        converted.otherText = pascal_string(parameters->otherText);
    }
    carbon_alert *alert = NULL;
    OSStatus status = carbon_CreateStandardAlert(type, pascal_string(error), pascal_string(explanation), &converted, &alert);
    if (status) return (OSErr)status;
    return (OSErr)carbon_RunStandardAlert(alert, NULL, item);
}

/// The window an alert is in: none of Carbon's.
WindowRef carbon_GetDialogWindow(void *dialog) CARBON_SYMBOL(GetDialogWindow);
WindowRef carbon_GetDialogWindow(void *dialog) {
    WindowRef window = carbon_window_from(dialog);
    return window;
}
