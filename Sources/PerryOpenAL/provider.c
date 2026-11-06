// libPerryOpenAL: the provider for OpenAL.framework, over OpenAL Soft.
//
// Apple's OpenAL implements the same OpenAL 1.1 C API, with plain
// functions and no variadics, so every import binds by name. OpenAL Soft
// is opened when first asked for; without it, the imports stay unbound.
// Without a sound device, its null backend plays nothing.

#include "PerryOpenAL.h"
#include "perry_wrapped.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <strings.h>
#include <unistd.h>

static perry_wrapped_library openal = PERRY_WRAPPED_SONAME("libopenal.so.1");

// OpenAL Soft keeps the first backend that loads, even when it then cannot
// open a device; so without a sound server or sound card (a container, a
// server), its null backend is chosen, and apps that require a device run
// silently. A choice already made in ALSOFT_DRIVERS is kept.
static int sound_available(void) {
    if (access("/dev/snd", F_OK) == 0 || getenv("PULSE_SERVER"))
        return 1;
    const char *runtime = getenv("XDG_RUNTIME_DIR");
    if (!runtime)
        return 0;
    char path[4096];
    snprintf(path, sizeof(path), "%s/pipewire-0", runtime);
    if (access(path, F_OK) == 0)
        return 1;
    snprintf(path, sizeof(path), "%s/pulse/native", runtime);
    return access(path, F_OK) == 0;
}

__attribute__((constructor))
static void choose_backends(void) {
    setenv("ALSOFT_DRIVERS", sound_available() ? "pipewire,pulse,alsa,oss,jack,null" : "null", 0);
    setenv("ALSOFT_LOGLEVEL", "0", 0);
}

// Apple's OpenAL has fewer extensions than OpenAL Soft; apps written for
// it take other paths where they find more (MonoGame passes ADPCM sound
// straight to AL_SOFT_MSADPCM and then misjudges its length), so only
// Apple's are reported.
static int apple_extension(const char *name) {
    static const char *const names[] = {
        "AL_EXT_OFFSET", "AL_EXT_LINEAR_DISTANCE", "AL_EXT_EXPONENT_DISTANCE", "AL_EXT_float32",
        "AL_EXT_MCFORMATS", "AL_EXT_SOURCE_DISTANCE_MODEL", "ALC_EXT_capture", "ALC_ENUMERATION_EXT",
        "ALC_ENUMERATE_ALL_EXT", "ALC_EXT_MAC_OSX", NULL,
    };
    for (const char *const *entry = names; name && *entry; entry++)
        if (strcasecmp(*entry, name) == 0)
            return 1;
    return 0;
}

typedef char (*is_extension_present)(const char *name);
typedef char (*alc_is_extension_present)(void *device, const char *name);

char darwin_alIsExtensionPresent(const char *name) __asm__("_alIsExtensionPresent") __attribute__((visibility("default")));
char darwin_alIsExtensionPresent(const char *name) {
    is_extension_present present = (is_extension_present)perry_wrapped_symbol(&openal, "_alIsExtensionPresent", NULL);
    return apple_extension(name) && present && present(name);
}

char darwin_alcIsExtensionPresent(void *device, const char *name) __asm__("_alcIsExtensionPresent") __attribute__((visibility("default")));
char darwin_alcIsExtensionPresent(void *device, const char *name) {
    alc_is_extension_present present = (alc_is_extension_present)perry_wrapped_symbol(&openal, "_alcIsExtensionPresent", NULL);
    return apple_extension(name) && present && present(device, name);
}

#if defined(__arm__)

// 32-bit Darwin passes and returns floating point in core registers, as
// AAPCS's base standard does, where Linux's armhf uses VFP registers: the
// functions that take or return it are entered through these, or a source's
// gain and pitch arrive as whatever the VFP registers held.
#define DARWIN_FLOAT_ABI __attribute__((pcs("aapcs")))

#define THUNK(name, result, parameters, arguments) \
    static result (*host_##name) parameters; \
    static DARWIN_FLOAT_ABI result thunk_##name parameters { return host_##name arguments; }

THUNK(alSourcef, void, (unsigned source, int parameter, float value), (source, parameter, value))
THUNK(alSource3f, void, (unsigned source, int parameter, float x, float y, float z), (source, parameter, x, y, z))
THUNK(alListenerf, void, (int parameter, float value), (parameter, value))
THUNK(alListener3f, void, (int parameter, float x, float y, float z), (parameter, x, y, z))
THUNK(alBufferf, void, (unsigned buffer, int parameter, float value), (buffer, parameter, value))
THUNK(alBuffer3f, void, (unsigned buffer, int parameter, float x, float y, float z), (buffer, parameter, x, y, z))
THUNK(alDopplerFactor, void, (float value), (value))
THUNK(alDopplerVelocity, void, (float value), (value))
THUNK(alSpeedOfSound, void, (float value), (value))
THUNK(alGetFloat, float, (int parameter), (parameter))
THUNK(alGetDouble, double, (int parameter), (parameter))

#define ENTRY(name) { "_" #name, (void **)&host_##name, (void *)thunk_##name }
static const struct { const char *name; void **host; void *thunk; } thunks[] = {
    ENTRY(alSourcef), ENTRY(alSource3f), ENTRY(alListenerf), ENTRY(alListener3f), ENTRY(alBufferf), ENTRY(alBuffer3f),
    ENTRY(alDopplerFactor), ENTRY(alDopplerVelocity), ENTRY(alSpeedOfSound), ENTRY(alGetFloat), ENTRY(alGetDouble),
};

/// The thunk for a function that takes or returns floating point, with the
/// host's function behind it; else the host's function itself.
static void *darwin_function(const char *name, void *host) {
    for (unsigned i = 0; host && i < sizeof(thunks) / sizeof(thunks[0]); i++) {
        if (strcmp(thunks[i].name, name) == 0) {
            *thunks[i].host = host;
            return thunks[i].thunk;
        }
    }
    return host;
}

#else

static void *darwin_function(const char *name, void *host) {
    (void)name;
    return host;
}

#endif

__attribute__((visibility("default")))
void *perry_provider_symbol(const char *name) {
    return darwin_function(name, perry_wrapped_symbol(&openal, name, NULL));
}
