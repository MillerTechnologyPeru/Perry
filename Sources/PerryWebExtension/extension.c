// libPerryWebExtension: WPE WebKit's web-process extension for AppKit's
// WebView. A Mac app puts Objective-C objects on a web view's window script
// object ([[webView windowScriptObject] setValue:object forKey:@"name"]) in
// webView:didClearWindowObject:forFrame:, and its pages call their methods
// as window.name.method(...), getting the result back at once. WPE's pages
// run in this process, and the objects are in the app's: so as each main
// frame's window object is cleared, this asks the app (a "perry.cleared"
// message, answered as the app's delegate has set the objects) which
// objects there are and what methods each has, and makes them on the
// window; a call sends "perry.call" with the arguments as JSON and waits
// for the result, running this process's main loop meanwhile, so the page
// sees an ordinary call. Messages and replies are JSON strings.
//
// It is loaded into WPEWebProcess, which has WebKit, JavaScriptCore and
// GLib loaded: their functions are declared here as they are in WPE
// WebKit 2.0's API, and bound when it loads.

#include "PerryWebExtension.h"

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>

typedef void *gpointer;
typedef int gboolean;
typedef unsigned long GType;
typedef void (*GCallback)(void);
typedef void (*GDestroyNotify)(gpointer);
typedef void (*GAsyncReadyCallback)(void *source, void *result, gpointer data);

typedef struct {
    gpointer *pdata;
    unsigned len;
} GPtrArray;

// GLib and GObject.
extern unsigned long g_signal_connect_data(gpointer instance, const char *signal, GCallback handler, gpointer data,
                                           void *destroy, int flags);
extern gboolean g_main_context_iteration(void *context, gboolean may_block);
extern void *g_variant_new_string(const char *string);
extern const char *g_variant_get_string(void *variant, size_t *length);
extern void g_free(gpointer memory);
extern char *g_strdup(const char *string);
extern void g_object_unref(gpointer object);
extern void g_error_free(void *error);

// WPE WebKit's web-process extension API.
extern void *webkit_script_world_get_default(void);
extern gboolean webkit_frame_is_main_frame(void *frame);
extern void *webkit_frame_get_js_context_for_script_world(void *frame, void *world);
extern void *webkit_user_message_new(const char *name, void *parameters);
extern void *webkit_user_message_get_parameters(void *message);
extern void webkit_web_page_send_message_to_view(void *page, void *message, void *cancellable, GAsyncReadyCallback callback,
                                                 gpointer data);
extern void *webkit_web_page_send_message_to_view_finish(void *page, void *result, void **error);

// JavaScriptCore's GLib API.
extern GType jsc_value_get_type(void);
extern void *jsc_context_get_global_object(void *context);
extern void *jsc_value_new_object(void *context, gpointer instance, void *klass);
extern void *jsc_value_new_from_json(void *context, const char *json);
extern void *jsc_value_new_null(void *context);
extern void *jsc_value_new_function_variadic(void *context, const char *name, GCallback callback, gpointer data,
                                             GDestroyNotify destroy, GType return_type);
extern void jsc_value_object_set_property(void *value, const char *name, void *property);
extern void *jsc_value_object_get_property(void *value, const char *name);
extern char **jsc_value_object_enumerate_properties(void *value);
extern gboolean jsc_value_is_array(void *value);
extern gboolean jsc_value_is_object(void *value);
extern gboolean jsc_value_is_function(void *value);
extern char *jsc_value_to_string(void *value);
extern char *jsc_value_to_json(void *value, unsigned indent);
extern void *jsc_value_get_context(void *value);
extern void g_strfreev(char **strings);

// MARK: - Messages to the app

typedef struct {
    bool done;
    char *reply;
} waiting;

static void replied(void *page, void *result, gpointer data) {
    waiting *wait = data;
    void *error = NULL;
    void *message = webkit_web_page_send_message_to_view_finish(page, result, &error);
    if (message) {
        void *parameters = webkit_user_message_get_parameters(message);
        const char *text = parameters ? g_variant_get_string(parameters, NULL) : NULL;
        wait->reply = text ? g_strdup(text) : NULL;
        g_object_unref(message);
    }
    if (error)
        g_error_free(error);
    wait->done = true;
}

/// Sends a message and waits for the app's reply (g_free it), running the
/// main loop meanwhile; NULL without one.
static char *ask(void *page, const char *name, const char *json) {
    waiting wait = { false, NULL };
    webkit_web_page_send_message_to_view(page, webkit_user_message_new(name, g_variant_new_string(json)), NULL, replied, &wait);
    while (!wait.done)
        g_main_context_iteration(NULL, true);
    return wait.reply;
}

// MARK: - Objects on the window

/// A method of an object of the app's: which object, by its key on the
/// window, and the method's name in scripts.
typedef struct {
    void *page;
    char *key;
    char *method;
} method_closure;

static void method_closure_free(gpointer data) {
    method_closure *closure = data;
    g_free(closure->key);
    g_free(closure->method);
    free(closure);
}

/// Appends text to a growing buffer.
static void append(char **buffer, size_t *length, size_t *capacity, const char *text) {
    size_t more = strlen(text);
    if (*length + more + 1 > *capacity) {
        *capacity = (*length + more + 1) * 2;
        *buffer = realloc(*buffer, *capacity);
    }
    memcpy(*buffer + *length, text, more + 1);
    *length += more;
}

/// A method's call: its arguments as a JSON array (functions and values
/// with no JSON as null), sent to the app; its result is the reply's value.
static void *called(GPtrArray *arguments, gpointer data) {
    method_closure *closure = data;
    void *context = NULL;
    char *json = NULL;
    size_t length = 0, capacity = 0;
    append(&json, &length, &capacity, "{\"key\":");
    // The key and method are plain names; quoted as JSON strings are.
    append(&json, &length, &capacity, "\"");
    append(&json, &length, &capacity, closure->key);
    append(&json, &length, &capacity, "\",\"method\":\"");
    append(&json, &length, &capacity, closure->method);
    append(&json, &length, &capacity, "\",\"arguments\":[");
    for (unsigned i = 0; arguments && i < arguments->len; i++) {
        void *argument = arguments->pdata[i];
        if (!context)
            context = jsc_value_get_context(argument);
        char *value = jsc_value_is_function(argument) ? NULL : jsc_value_to_json(argument, 0);
        if (i)
            append(&json, &length, &capacity, ",");
        append(&json, &length, &capacity, value ? value : "null");
        g_free(value);
    }
    append(&json, &length, &capacity, "]}");
    char *reply = ask(closure->page, "perry.call", json);
    free(json);
    if (!context) {
        g_free(reply);
        return NULL;
    }
    void *result = reply && *reply ? jsc_value_new_from_json(context, reply) : NULL;
    g_free(reply);
    return result ? result : jsc_value_new_null(context);
}

/// The window object is new: the app's delegate sets its objects, and the
/// reply names them and their methods ({ key: [method, …] }), or gives
/// values that are not objects ({ key: { "value": json } }).
static void window_cleared(void *world, void *page, void *frame, gpointer data) {
    (void)data;
    if (!webkit_frame_is_main_frame(frame))
        return;
    char *reply = ask(page, "perry.cleared", "{}");
    if (!reply)
        return;
    void *context = webkit_frame_get_js_context_for_script_world(frame, world);
    void *objects = context ? jsc_value_new_from_json(context, reply) : NULL;
    g_free(reply);
    if (!objects || !jsc_value_is_object(objects))
        return;
    void *window = jsc_context_get_global_object(context);
    char **keys = jsc_value_object_enumerate_properties(objects);
    for (char **key = keys; key && *key; key++) {
        void *entry = jsc_value_object_get_property(objects, *key);
        if (!jsc_value_is_array(entry)) {
            // A value the app set that isn't an object: { "value": … }.
            void *value = jsc_value_object_get_property(entry, "value");
            jsc_value_object_set_property(window, *key, value);
            g_object_unref(value);
            g_object_unref(entry);
            continue;
        }
        void *object = jsc_value_new_object(context, NULL, NULL);
        char **indices = jsc_value_object_enumerate_properties(entry);
        for (char **index = indices; index && *index; index++) {
            void *name = jsc_value_object_get_property(entry, *index);
            char *method = jsc_value_to_string(name);
            g_object_unref(name);
            if (!method)
                continue;
            method_closure *closure = calloc(1, sizeof(*closure));
            closure->page = page;
            closure->key = g_strdup(*key);
            closure->method = method;
            void *function = jsc_value_new_function_variadic(context, method, (GCallback)called, closure,
                                                             method_closure_free, jsc_value_get_type());
            jsc_value_object_set_property(object, method, function);
            g_object_unref(function);
        }
        g_strfreev(indices);
        jsc_value_object_set_property(window, *key, object);
        g_object_unref(object);
        g_object_unref(entry);
    }
    g_strfreev(keys);
    g_object_unref(objects);
    g_object_unref(context);
}

__attribute__((visibility("default")))
void webkit_web_process_extension_initialize(void *extension) {
    (void)extension;
    g_signal_connect_data(webkit_script_world_get_default(), "window-object-cleared", (GCallback)window_cleared, NULL, NULL, 0);
}
