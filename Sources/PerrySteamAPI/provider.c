// libPerrysteam_api: the provider for Steamworks' libsteam_api.dylib, which
// games ship in their bundles and link or dlopen. Darwin's copy finds the
// Mac Steam client through a Mach service and loads its steamclient.dylib;
// this one loads the running Linux Steam client's steamclient.so for the
// same architecture (~/.steam/sdkarm64, as Valve's arm64 client installs
// it, or PERRY_STEAMCLIENT) and implements libsteam_api's own part over it:
// starting up, the interfaces' accessors and running callbacks.
//
// The interfaces themselves are steamclient's C++ objects, which games call
// through their vtables. arm64 Darwin and Linux share the Itanium C++ ABI
// and pass arguments alike, but for one difference: Darwin packs stack
// arguments smaller than 8 bytes, which only methods taking more than
// eight integer arguments see.
//
// The app ID comes from SteamAppId or SteamGameId, else steam_appid.txt in
// the working directory, as with Valve's library. PERRY_STEAM_TRACE traces
// startup, interfaces and callbacks.

#define _GNU_SOURCE
#include "PerrySteamAPI.h"

#include <dlfcn.h>
#include <pwd.h>
#include <pthread.h>
#include <signal.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/types.h>
#include <unistd.h>

#define EXPORT(name) __asm__("_" #name) __attribute__((visibility("default"), used))

typedef int32_t HSteamPipe;
typedef int32_t HSteamUser;
typedef uint64_t SteamAPICall_t;

// MARK: - Tracing

static bool tracing(void) {
    static int enabled = -1;
    if (enabled < 0)
        enabled = getenv("PERRY_STEAM_TRACE") != NULL;
    return enabled;
}

#define TRACE(...) do { if (tracing()) { fprintf(stderr, "perry: steam: " __VA_ARGS__); fputc('\n', stderr); } } while (0)

static void warn(const char *message) {
    // As Valve's library reports a failed SteamAPI_Init.
    fprintf(stderr, "[S_API FAIL] %s\n", message);
}

// MARK: - Call tracing

// With PERRY_STEAM_TRACE_CALLS, the interfaces the game asks for are the
// provider's objects, whose methods (trace.S) log each call's first
// arguments and its result around the client's own method.

enum { TRACE_SLOTS = 128, TRACE_DEPTH = 256, TRACED_INTERFACES = 64 };

typedef struct {
    void **vtable;
    void *object;
    char name[64];
} traced_interface;

typedef struct {
    void *return_address;
    traced_interface *interface;
    uint64_t slot;
} trace_frame;

extern char perry_steam_trace_stubs[];

static __thread trace_frame trace_frames[TRACE_DEPTH];
static __thread unsigned trace_depth;

static bool tracing_calls(void) {
    static int enabled = -1;
    if (enabled < 0)
        enabled = getenv("PERRY_STEAM_TRACE_CALLS") != NULL;
    return enabled;
}

void *perry_steam_trace_enter(traced_interface *interface, uint64_t slot, void *return_address, uint64_t *arguments)
    __attribute__((visibility("hidden")));
void *perry_steam_trace_enter(traced_interface *interface, uint64_t slot, void *return_address, uint64_t *arguments) {
    if (trace_depth == TRACE_DEPTH) {
        fprintf(stderr, "perry: steam: traced calls nest too deep\n");
        abort();
    }
    trace_frames[trace_depth++] = (trace_frame){ return_address, interface, slot };
    arguments[0] = (uint64_t)(uintptr_t)interface->object;
    fprintf(stderr, "perry: steam: %s[%llu](%#llx, %#llx, %#llx, %#llx) from %p\n", interface->name,
            (unsigned long long)slot, (unsigned long long)arguments[1], (unsigned long long)arguments[2],
            (unsigned long long)arguments[3], (unsigned long long)arguments[4], return_address);
    return (*(void ***)interface->object)[slot];
}

void *perry_steam_trace_leave(uint64_t result, uint64_t second) __attribute__((visibility("hidden")));
void *perry_steam_trace_leave(uint64_t result, uint64_t second) {
    trace_frame frame = trace_frames[--trace_depth];
    fprintf(stderr, "perry: steam: %s[%llu] = %#llx (%#llx)\n", frame.interface->name,
            (unsigned long long)frame.slot, (unsigned long long)result, (unsigned long long)second);
    return frame.return_address;
}

/// The traced object for one of the client's, made once for each.
static void *traced(void *object, const char *version) {
    static void *stubs[TRACE_SLOTS];
    static traced_interface interfaces[TRACED_INTERFACES];
    static unsigned count;
    static pthread_mutex_t lock = PTHREAD_MUTEX_INITIALIZER;
    if (!object || !tracing_calls())
        return object;
    pthread_mutex_lock(&lock);
    if (!stubs[0])
        for (unsigned i = 0; i < TRACE_SLOTS; i++)
            stubs[i] = perry_steam_trace_stubs + 8 * i;
    traced_interface *found = NULL;
    for (unsigned i = 0; i < count && !found; i++)
        if (interfaces[i].object == object)
            found = &interfaces[i];
    if (!found && count < TRACED_INTERFACES) {
        found = &interfaces[count++];
        found->vtable = stubs;
        found->object = object;
        snprintf(found->name, sizeof(found->name), "%s", version);
    }
    pthread_mutex_unlock(&lock);
    return found ? (void *)found : object;
}

// MARK: - steamclient

// ISteamClient's first methods, whose places every version since 017 keeps.
enum {
    CLIENT_CREATE_STEAM_PIPE = 0,
    CLIENT_RELEASE_STEAM_PIPE = 1,
    CLIENT_CONNECT_TO_GLOBAL_USER = 2,
    CLIENT_RELEASE_USER = 4,
    CLIENT_GET_GENERIC_INTERFACE = 12,
};

typedef void *(*create_interface_fn)(const char *version, int *result);
typedef bool (*get_callback_fn)(HSteamPipe pipe, void *message, int32_t *call);
typedef void (*free_last_callback_fn)(HSteamPipe pipe);
typedef bool (*get_call_result_fn)(HSteamPipe pipe, SteamAPICall_t call, void *result, int size, int expected, bool *failed);
typedef void (*release_thread_memory_fn)(bool exiting);
typedef void (*set_app_id_fn)(uint32_t app);

static struct {
    void *library;
    create_interface_fn create_interface;
    get_callback_fn get_callback;
    free_last_callback_fn free_last_callback;
    get_call_result_fn get_call_result;
    release_thread_memory_fn release_thread_memory;
    set_app_id_fn breakpad_set_app_id;
} client_library;

static pthread_mutex_t state_lock = PTHREAD_RECURSIVE_MUTEX_INITIALIZER_NP;
static void **steam_client;
static HSteamPipe steam_pipe;
static HSteamUser steam_user;
static int init_count;
/// Bumped by each SteamAPI_Init: the SDK's accessors fetch their interface
/// again when their counter differs.
static uintptr_t context_generation;
static bool manual_dispatch;

static void *vtable_entry(void **object, int index) { return ((void ***)object)[0][index]; }

static HSteamPipe client_create_pipe(void) {
    return ((HSteamPipe(*)(void **))vtable_entry(steam_client, CLIENT_CREATE_STEAM_PIPE))(steam_client);
}

static bool client_release_pipe(HSteamPipe pipe) {
    return ((bool (*)(void **, HSteamPipe))vtable_entry(steam_client, CLIENT_RELEASE_STEAM_PIPE))(steam_client, pipe);
}

static HSteamUser client_connect_user(HSteamPipe pipe) {
    return ((HSteamUser(*)(void **, HSteamPipe))vtable_entry(steam_client, CLIENT_CONNECT_TO_GLOBAL_USER))(steam_client, pipe);
}

static void client_release_user(HSteamPipe pipe, HSteamUser user) {
    ((void (*)(void **, HSteamPipe, HSteamUser))vtable_entry(steam_client, CLIENT_RELEASE_USER))(steam_client, pipe, user);
}

static void *client_generic_interface(HSteamUser user, HSteamPipe pipe, const char *version) {
    return ((void *(*)(void **, HSteamUser, HSteamPipe, const char *))vtable_entry(steam_client, CLIENT_GET_GENERIC_INTERFACE))(
        steam_client, user, pipe, version);
}

/// The user's home, where Steam keeps ~/.steam: the account's, as Perry
/// points HOME at the app's container.
static const char *home_directory(void) {
    struct passwd *user = getpwuid(getuid());
    if (user && user->pw_dir && *user->pw_dir)
        return user->pw_dir;
    const char *home = getenv("HOME");
    return home && *home ? home : "/";
}

static void client_path(char *path, size_t size) {
    const char *setting = getenv("PERRY_STEAMCLIENT");
    if (setting && *setting)
        snprintf(path, size, "%s", setting);
    else
        snprintf(path, size, "%s/.steam/sdkarm64/steamclient.so", home_directory());
}

static bool load_client_library(void) {
    if (client_library.library)
        return true;
    char path[4096];
    client_path(path, sizeof(path));
    void *library = dlopen(path, RTLD_NOW | RTLD_LOCAL);
    if (!library) {
        TRACE("cannot open %s: %s", path, dlerror());
        return false;
    }
    client_library.create_interface = (create_interface_fn)dlsym(library, "CreateInterface");
    client_library.get_callback = (get_callback_fn)dlsym(library, "Steam_BGetCallback");
    client_library.free_last_callback = (free_last_callback_fn)dlsym(library, "Steam_FreeLastCallback");
    client_library.get_call_result = (get_call_result_fn)dlsym(library, "Steam_GetAPICallResult");
    client_library.release_thread_memory = (release_thread_memory_fn)dlsym(library, "Steam_ReleaseThreadLocalMemory");
    client_library.breakpad_set_app_id = (set_app_id_fn)dlsym(library, "Breakpad_SteamSetAppID");
    if (!client_library.create_interface || !client_library.get_callback || !client_library.free_last_callback ||
        !client_library.get_call_result) {
        TRACE("%s is not a Steam client library", path);
        dlclose(library);
        memset(&client_library, 0, sizeof(client_library));
        return false;
    }
    client_library.library = library;
    TRACE("loaded %s", path);
    return true;
}

/// Whether the Steam client is running: the process ~/.steam/steam.pid names.
static bool steam_running(void) {
    char path[4096];
    snprintf(path, sizeof(path), "%s/.steam/steam.pid", home_directory());
    FILE *file = fopen(path, "r");
    if (!file)
        return false;
    long pid = 0;
    bool read = fscanf(file, "%ld", &pid) == 1;
    fclose(file);
    return read && pid > 0 && kill((pid_t)pid, 0) == 0;
}

// MARK: - The app ID

static uint32_t app_id_from_environment(void) {
    const char *names[] = { "SteamAppId", "SteamGameId" };
    for (size_t i = 0; i < 2; i++) {
        const char *value = getenv(names[i]);
        if (value && *value) {
            unsigned long id = strtoul(value, NULL, 10);
            if (id)
                return (uint32_t)id;
        }
    }
    FILE *file = fopen("steam_appid.txt", "r");
    if (!file)
        return 0;
    unsigned long id = 0;
    if (fscanf(file, "%lu", &id) != 1)
        id = 0;
    fclose(file);
    return (uint32_t)id;
}

// MARK: - Startup

bool darwin_SteamAPI_Init(void) EXPORT(SteamAPI_Init);
bool darwin_SteamAPI_Init(void) {
    pthread_mutex_lock(&state_lock);
    if (init_count > 0) {
        init_count++;
        pthread_mutex_unlock(&state_lock);
        return true;
    }
    bool ok = false;
    uint32_t app = app_id_from_environment();
    if (!app) {
        warn("SteamAPI_Init() failed; no appID found.\n"
             "Either launch the game from Steam, or put the file steam_appid.txt containing the correct appID in your game folder.");
        goto done;
    }
    char id[16];
    snprintf(id, sizeof(id), "%u", app);
    setenv("SteamAppId", id, 1);
    setenv("SteamGameId", id, 1);
    if (!steam_running()) {
        warn("SteamAPI_Init() failed; SteamAPI_IsSteamRunning() failed.");
        goto done;
    }
    if (!load_client_library()) {
        warn("SteamAPI_Init() failed; Sys_LoadModule failed to load: steamclient.so");
        goto done;
    }
    static const char *const versions[] = { "SteamClient021", "SteamClient020", "SteamClient019", "SteamClient018", "SteamClient017" };
    for (size_t i = 0; !steam_client && i < sizeof(versions) / sizeof(*versions); i++)
        steam_client = client_library.create_interface(versions[i], NULL);
    if (!steam_client) {
        warn("SteamAPI_Init() failed; unable to locate interface factory in steamclient.so.");
        goto done;
    }
    steam_pipe = client_create_pipe();
    if (!steam_pipe) {
        warn("SteamAPI_Init() failed; CreateSteamPipe() failed.");
        goto done;
    }
    steam_user = client_connect_user(steam_pipe);
    if (!steam_user) {
        warn("SteamAPI_Init() failed; ConnectToGlobalUser() failed.");
        client_release_pipe(steam_pipe);
        steam_pipe = 0;
        goto done;
    }
    if (client_library.breakpad_set_app_id)
        client_library.breakpad_set_app_id(app);
    init_count = 1;
    context_generation++;
    ok = true;
    TRACE("app %u, pipe %d, user %d", app, steam_pipe, steam_user);
done:
    pthread_mutex_unlock(&state_lock);
    return ok;
}

/// SteamAPI_InitSafe: the same, from SDKs that offered both.
bool darwin_SteamAPI_InitSafe(void) EXPORT(SteamAPI_InitSafe);
bool darwin_SteamAPI_InitSafe(void) { return darwin_SteamAPI_Init(); }

/// SteamAPI_InitFlat and SteamInternal_SteamAPI_Init, from SDK 1.59 on:
/// ESteamAPIInitResult (0 OK, 1 failed generic), with a message.
int darwin_SteamInternal_SteamAPI_Init(const char *versions, char *message) EXPORT(SteamInternal_SteamAPI_Init);
int darwin_SteamInternal_SteamAPI_Init(const char *versions, char *message) {
    (void)versions;
    bool ok = darwin_SteamAPI_Init();
    if (message)
        snprintf(message, 1024, "%s", ok ? "" : "SteamAPI_Init() failed");
    return ok ? 0 : 1;
}

int darwin_SteamAPI_InitFlat(char *message) EXPORT(SteamAPI_InitFlat);
int darwin_SteamAPI_InitFlat(char *message) { return darwin_SteamInternal_SteamAPI_Init(NULL, message); }

void darwin_SteamAPI_Shutdown(void) EXPORT(SteamAPI_Shutdown);
void darwin_SteamAPI_Shutdown(void) {
    pthread_mutex_lock(&state_lock);
    if (init_count > 0 && --init_count == 0) {
        if (steam_user)
            client_release_user(steam_pipe, steam_user);
        if (steam_pipe)
            client_release_pipe(steam_pipe);
        steam_user = 0;
        steam_pipe = 0;
        context_generation++;
        TRACE("shut down");
    }
    pthread_mutex_unlock(&state_lock);
}

bool darwin_SteamAPI_IsSteamRunning(void) EXPORT(SteamAPI_IsSteamRunning);
bool darwin_SteamAPI_IsSteamRunning(void) { return steam_running(); }

/// The game runs as it is: Steam launching it again would launch the
/// Darwin build, which is not what runs here.
bool darwin_SteamAPI_RestartAppIfNecessary(uint32_t app) EXPORT(SteamAPI_RestartAppIfNecessary);
bool darwin_SteamAPI_RestartAppIfNecessary(uint32_t app) {
    TRACE("SteamAPI_RestartAppIfNecessary(%u): no", app);
    return false;
}

HSteamUser darwin_SteamAPI_GetHSteamUser(void) EXPORT(SteamAPI_GetHSteamUser);
HSteamUser darwin_SteamAPI_GetHSteamUser(void) { return steam_user; }

HSteamPipe darwin_SteamAPI_GetHSteamPipe(void) EXPORT(SteamAPI_GetHSteamPipe);
HSteamPipe darwin_SteamAPI_GetHSteamPipe(void) { return steam_pipe; }

const char *darwin_SteamAPI_GetSteamInstallPath(void) EXPORT(SteamAPI_GetSteamInstallPath);
const char *darwin_SteamAPI_GetSteamInstallPath(void) {
    static char path[4096];
    char link[4096];
    snprintf(link, sizeof(link), "%s/.steam/steam", home_directory());
    if (!realpath(link, path))
        snprintf(path, sizeof(path), "%s", link);
    return path;
}

void darwin_SteamAPI_ReleaseCurrentThreadMemory(void) EXPORT(SteamAPI_ReleaseCurrentThreadMemory);
void darwin_SteamAPI_ReleaseCurrentThreadMemory(void) {
    if (client_library.release_thread_memory)
        client_library.release_thread_memory(false);
}

// Crash reporting is the Darwin build's, which sends nothing here.
void darwin_SteamAPI_SetMiniDumpComment(const char *comment) EXPORT(SteamAPI_SetMiniDumpComment);
void darwin_SteamAPI_SetMiniDumpComment(const char *comment) { (void)comment; }
void darwin_SteamAPI_WriteMiniDump(uint32_t code, void *info, uint32_t build) EXPORT(SteamAPI_WriteMiniDump);
void darwin_SteamAPI_WriteMiniDump(uint32_t code, void *info, uint32_t build) { (void)code, (void)info, (void)build; }
void darwin_SteamAPI_SetBreakpadAppID(uint32_t app) EXPORT(SteamAPI_SetBreakpadAppID);
void darwin_SteamAPI_SetBreakpadAppID(uint32_t app) { (void)app; }
void darwin_SteamAPI_UseBreakpadCrashHandler(const char *version, const char *date, const char *time, bool full,
                                             void *context, void *callback) EXPORT(SteamAPI_UseBreakpadCrashHandler);
void darwin_SteamAPI_UseBreakpadCrashHandler(const char *version, const char *date, const char *time, bool full,
                                             void *context, void *callback) {
    (void)version, (void)date, (void)time, (void)full, (void)context, (void)callback;
}
void darwin_SteamAPI_SetTryCatchCallbacks(bool on) EXPORT(SteamAPI_SetTryCatchCallbacks);
void darwin_SteamAPI_SetTryCatchCallbacks(bool on) { (void)on; }

// MARK: - Interfaces

void *darwin_SteamClient(void) EXPORT(SteamClient);
void *darwin_SteamClient(void) { return steam_client; }

/// The client itself by its version, or another interface of the user.
void *darwin_SteamInternal_CreateInterface(const char *version) EXPORT(SteamInternal_CreateInterface);
void *darwin_SteamInternal_CreateInterface(const char *version) {
    if (!version || !client_library.library)
        return NULL;
    void *interface = strncmp(version, "SteamClient", 11) == 0 ? client_library.create_interface(version, NULL)
                      : steam_client                           ? client_generic_interface(steam_user, steam_pipe, version)
                                                               : NULL;
    TRACE("SteamInternal_CreateInterface(%s) = %p", version, interface);
    return strncmp(version, "SteamClient", 11) == 0 ? interface : traced(interface, version);
}

void *darwin_SteamInternal_FindOrCreateUserInterface(HSteamUser user, const char *version)
    EXPORT(SteamInternal_FindOrCreateUserInterface);
void *darwin_SteamInternal_FindOrCreateUserInterface(HSteamUser user, const char *version) {
    if (!steam_client || !version)
        return NULL;
    void *interface = client_generic_interface(user, steam_pipe, version);
    TRACE("SteamInternal_FindOrCreateUserInterface(%d, %s) = %p", user, version, interface);
    return traced(interface, version);
}

/// There is no game server here.
void *darwin_SteamInternal_FindOrCreateGameServerInterface(HSteamUser user, const char *version)
    EXPORT(SteamInternal_FindOrCreateGameServerInterface);
void *darwin_SteamInternal_FindOrCreateGameServerInterface(HSteamUser user, const char *version) {
    (void)user, (void)version;
    return NULL;
}

/// The SDK's accessors' storage: { initializer, generation, context… }. The
/// initializer fills the context in when the generation is not the current
/// one, as after each SteamAPI_Init.
void *darwin_SteamInternal_ContextInit(void *data) EXPORT(SteamInternal_ContextInit);
void *darwin_SteamInternal_ContextInit(void *data) {
    void **storage = data;
    pthread_mutex_lock(&state_lock);
    if ((uintptr_t)storage[1] != context_generation) {
        void (*initialize)(void *) = (void (*)(void *))storage[0];
        initialize(&storage[2]);
        storage[1] = (void *)context_generation;
    }
    pthread_mutex_unlock(&state_lock);
    return &storage[2];
}

// MARK: - Game servers: none

bool darwin_SteamInternal_GameServer_Init(uint32_t ip, uint16_t steam_port, uint16_t game_port, uint16_t query_port,
                                         int mode, const char *version) EXPORT(SteamInternal_GameServer_Init);
bool darwin_SteamInternal_GameServer_Init(uint32_t ip, uint16_t steam_port, uint16_t game_port, uint16_t query_port,
                                         int mode, const char *version) {
    (void)ip, (void)steam_port, (void)game_port, (void)query_port, (void)mode, (void)version;
    return false;
}
void darwin_SteamGameServer_Shutdown(void) EXPORT(SteamGameServer_Shutdown);
void darwin_SteamGameServer_Shutdown(void) {}
void darwin_SteamGameServer_RunCallbacks(void) EXPORT(SteamGameServer_RunCallbacks);
void darwin_SteamGameServer_RunCallbacks(void) {}
bool darwin_SteamGameServer_BSecure(void) EXPORT(SteamGameServer_BSecure);
bool darwin_SteamGameServer_BSecure(void) { return false; }
uint64_t darwin_SteamGameServer_GetSteamID(void) EXPORT(SteamGameServer_GetSteamID);
uint64_t darwin_SteamGameServer_GetSteamID(void) { return 0; }
HSteamPipe darwin_SteamGameServer_GetHSteamPipe(void) EXPORT(SteamGameServer_GetHSteamPipe);
HSteamPipe darwin_SteamGameServer_GetHSteamPipe(void) { return 0; }
HSteamUser darwin_SteamGameServer_GetHSteamUser(void) EXPORT(SteamGameServer_GetHSteamUser);
HSteamUser darwin_SteamGameServer_GetHSteamUser(void) { return 0; }

// MARK: - Callbacks

/// CallbackMsg_t.
typedef struct {
    HSteamUser user;
    int callback;
    uint8_t *data;
    int size;
} callback_message;

/// SteamAPICallCompleted_t, the callback a call's result is ready with.
enum { CALL_COMPLETED = 703 };
typedef struct {
    SteamAPICall_t call;
    int callback;
    uint32_t size;
} call_completed;

/// The SDK's CCallbackBase: { vtable, m_nCallbackFlags, m_iCallback }, whose
/// virtual methods are Run(void *), Run(void *, bool, SteamAPICall_t) and
/// GetCallbackSizeBytes(). The bool is passed widened, as Darwin's callee
/// expects of its caller.
typedef struct {
    void **vtable;
    uint8_t flags;
    int callback;
} callback_base;

enum { CALLBACK_REGISTERED = 1, CALLBACK_GAME_SERVER = 2 };

typedef void (*run_fn)(callback_base *self, void *data);
typedef void (*run_result_fn)(callback_base *self, void *data, uint32_t failed, SteamAPICall_t call);
typedef int (*size_fn)(callback_base *self);

typedef struct {
    callback_base *object;
    SteamAPICall_t call;    // for a call result; 0 for a callback
} registration;

static registration *registrations;
static size_t registration_count, registration_capacity;

static void add_registration(callback_base *object, SteamAPICall_t call) {
    pthread_mutex_lock(&state_lock);
    if (registration_count == registration_capacity) {
        size_t capacity = registration_capacity ? registration_capacity * 2 : 64;
        registration *grown = realloc(registrations, capacity * sizeof(*grown));
        if (!grown) {
            pthread_mutex_unlock(&state_lock);
            return;
        }
        registrations = grown;
        registration_capacity = capacity;
    }
    registrations[registration_count++] = (registration){ object, call };
    pthread_mutex_unlock(&state_lock);
}

/// Removes the object's registrations: for `call`, or its callbacks when 0.
static void remove_registrations(callback_base *object, SteamAPICall_t call) {
    pthread_mutex_lock(&state_lock);
    size_t kept = 0;
    for (size_t i = 0; i < registration_count; i++)
        if (registrations[i].object != object || registrations[i].call != call)
            registrations[kept++] = registrations[i];
    registration_count = kept;
    pthread_mutex_unlock(&state_lock);
}

void darwin_SteamAPI_RegisterCallback(callback_base *object, int callback) EXPORT(SteamAPI_RegisterCallback);
void darwin_SteamAPI_RegisterCallback(callback_base *object, int callback) {
    if (!object)
        return;
    object->flags |= CALLBACK_REGISTERED;
    object->callback = callback;
    add_registration(object, 0);
    TRACE("registered %p for callback %d", (void *)object, callback);
}

void darwin_SteamAPI_UnregisterCallback(callback_base *object) EXPORT(SteamAPI_UnregisterCallback);
void darwin_SteamAPI_UnregisterCallback(callback_base *object) {
    if (!object)
        return;
    object->flags &= (uint8_t)~CALLBACK_REGISTERED;
    remove_registrations(object, 0);
}

void darwin_SteamAPI_RegisterCallResult(callback_base *object, SteamAPICall_t call) EXPORT(SteamAPI_RegisterCallResult);
void darwin_SteamAPI_RegisterCallResult(callback_base *object, SteamAPICall_t call) {
    if (!object || !call)
        return;
    add_registration(object, call);
    TRACE("registered %p for call %llu", (void *)object, (unsigned long long)call);
}

void darwin_SteamAPI_UnregisterCallResult(callback_base *object, SteamAPICall_t call) EXPORT(SteamAPI_UnregisterCallResult);
void darwin_SteamAPI_UnregisterCallResult(callback_base *object, SteamAPICall_t call) {
    if (object && call)
        remove_registrations(object, call);
}

/// The registrations that match, copied: a callback may register or
/// unregister others, or itself, while it runs.
static size_t matching(registration **out, int callback, SteamAPICall_t call) {
    pthread_mutex_lock(&state_lock);
    registration *found = registration_count ? malloc(registration_count * sizeof(*found)) : NULL;
    size_t count = 0;
    for (size_t i = 0; found && i < registration_count; i++) {
        registration entry = registrations[i];
        if (call ? entry.call == call
                 : entry.call == 0 && entry.object->callback == callback && !(entry.object->flags & CALLBACK_GAME_SERVER))
            found[count++] = entry;
    }
    pthread_mutex_unlock(&state_lock);
    *out = found;
    return count;
}

static bool still_registered(registration entry) {
    pthread_mutex_lock(&state_lock);
    bool found = false;
    for (size_t i = 0; !found && i < registration_count; i++)
        found = registrations[i].object == entry.object && registrations[i].call == entry.call;
    pthread_mutex_unlock(&state_lock);
    return found;
}

static void dispatch_call_result(const call_completed *completed) {
    registration *found;
    size_t count = matching(&found, 0, completed->call);
    if (count) {
        void *result = calloc(1, completed->size ? completed->size : 1);
        bool failed = false;
        if (result && !client_library.get_call_result(steam_pipe, completed->call, result, (int)completed->size,
                                                      completed->callback, &failed))
            failed = true;
        for (size_t i = 0; i < count; i++) {
            if (!still_registered(found[i]))
                continue;
            // A call's result runs once: CCallResult unregisters itself too.
            remove_registrations(found[i].object, completed->call);
            TRACE("call %llu result %d to %p%s", (unsigned long long)completed->call, completed->callback,
                  (void *)found[i].object, failed ? " (failed)" : "");
            ((run_result_fn)found[i].object->vtable[1])(found[i].object, result, failed ? 1 : 0, completed->call);
        }
        free(result);
    }
    free(found);
}

static void dispatch(const callback_message *message) {
    if (message->callback == CALL_COMPLETED && message->data)
        dispatch_call_result((const call_completed *)message->data);
    registration *found;
    size_t count = matching(&found, message->callback, 0);
    if (count)
        TRACE("callback %d to %zu", message->callback, count);
    for (size_t i = 0; i < count; i++)
        if (still_registered(found[i]))
            ((run_fn)found[i].object->vtable[0])(found[i].object, message->data);
    free(found);
}

void darwin_SteamAPI_RunCallbacks(void) EXPORT(SteamAPI_RunCallbacks);
void darwin_SteamAPI_RunCallbacks(void) {
    if (!steam_pipe || manual_dispatch)
        return;
    callback_message message;
    int32_t call = 0;
    while (client_library.get_callback(steam_pipe, &message, &call)) {
        dispatch(&message);
        client_library.free_last_callback(steam_pipe);
    }
}

// Manual dispatch (SDK 1.48 on): the game takes each callback itself.

void darwin_SteamAPI_ManualDispatch_Init(void) EXPORT(SteamAPI_ManualDispatch_Init);
void darwin_SteamAPI_ManualDispatch_Init(void) { manual_dispatch = true; }

void darwin_SteamAPI_ManualDispatch_RunFrame(HSteamPipe pipe) EXPORT(SteamAPI_ManualDispatch_RunFrame);
void darwin_SteamAPI_ManualDispatch_RunFrame(HSteamPipe pipe) { (void)pipe; }

bool darwin_SteamAPI_ManualDispatch_GetNextCallback(HSteamPipe pipe, callback_message *message)
    EXPORT(SteamAPI_ManualDispatch_GetNextCallback);
bool darwin_SteamAPI_ManualDispatch_GetNextCallback(HSteamPipe pipe, callback_message *message) {
    int32_t call = 0;
    return client_library.get_callback && client_library.get_callback(pipe, message, &call);
}

void darwin_SteamAPI_ManualDispatch_FreeLastCallback(HSteamPipe pipe) EXPORT(SteamAPI_ManualDispatch_FreeLastCallback);
void darwin_SteamAPI_ManualDispatch_FreeLastCallback(HSteamPipe pipe) {
    if (client_library.free_last_callback)
        client_library.free_last_callback(pipe);
}

bool darwin_SteamAPI_ManualDispatch_GetAPICallResult(HSteamPipe pipe, SteamAPICall_t call, void *result, int size,
                                                     int expected, bool *failed)
    EXPORT(SteamAPI_ManualDispatch_GetAPICallResult);
bool darwin_SteamAPI_ManualDispatch_GetAPICallResult(HSteamPipe pipe, SteamAPICall_t call, void *result, int size,
                                                     int expected, bool *failed) {
    return client_library.get_call_result && client_library.get_call_result(pipe, call, result, size, expected, failed);
}

// MARK: - The rest

/// Valve's flat C API (SteamAPI_ISteamUser_GetSteamID…) is not here: games
/// built in C++ call the interfaces directly. A trace names what is missed.
__attribute__((visibility("default")))
void *perry_provider_symbol(const char *name) {
    TRACE("no %s", name);
    return NULL;
}
