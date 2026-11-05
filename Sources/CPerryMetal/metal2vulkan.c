#define _GNU_SOURCE
#include <dlfcn.h>
#include <limits.h>
#include <pthread.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "perry_metal.h"

// libmetal2vulkan.so, opened the first time Metal is asked for a device and
// kept for the life of the process.

/// The ABI these declarations are of.
#define ABI_VERSION 1

static pthread_once_t once = PTHREAD_ONCE_INIT;
static perry_m2v table;
static const perry_m2v *loaded;
static char error[PATH_MAX + 256];

static void *open_library(void) {
    const char *setting = getenv("PERRY_METAL2VULKAN");
    if (setting && *setting) {
        void *library = dlopen(setting, RTLD_NOW | RTLD_LOCAL);
        if (!library)
            snprintf(error, sizeof(error), "cannot open %s: %s", setting, dlerror());
        return library;
    }
    // Beside this provider, as a port ships it.
    Dl_info info;
    if (dladdr((void *)perry_metal2vulkan, &info) && info.dli_fname) {
        char path[PATH_MAX];
        snprintf(path, sizeof(path), "%s", info.dli_fname);
        char *slash = strrchr(path, '/');
        if (slash) {
            snprintf(slash + 1, sizeof(path) - (size_t)(slash + 1 - path), "libmetal2vulkan.so");
            void *library = dlopen(path, RTLD_NOW | RTLD_LOCAL);
            if (library)
                return library;
        }
    }
    void *library = dlopen("libmetal2vulkan.so", RTLD_NOW | RTLD_LOCAL);
    if (!library)
        snprintf(error, sizeof(error), "cannot open libmetal2vulkan.so: %s", dlerror());
    return library;
}

static void load(void) {
    void *library = open_library();
    if (!library)
        return;
    uint32_t (*abi_version)(void) = (uint32_t (*)(void))dlsym(library, "m2v_abi_version");
    if (!abi_version || abi_version() != ABI_VERSION) {
        snprintf(error, sizeof(error), "libmetal2vulkan.so has ABI version %u; Perry needs %u",
                 abi_version ? abi_version() : 0, ABI_VERSION);
        return;
    }
#define BIND(name)                                                                                   \
    if (!(*(void **)&table.name = dlsym(library, "m2v_" #name))) {                                    \
        snprintf(error, sizeof(error), "libmetal2vulkan.so has no m2v_" #name);                      \
        return;                                                                                      \
    }
    BIND(string_free)
    BIND(copy_all_devices)
    BIND(device_release)
    BIND(device_name)
    BIND(device_properties_get)
    BIND(device_supports_family)
    BIND(device_supports_texture_sample_count)
    BIND(device_new_buffer)
    BIND(buffer_release)
    BIND(buffer_length)
    BIND(buffer_contents)
    BIND(buffer_did_modify_range)
    BIND(device_new_library_with_data)
    BIND(library_release)
    BIND(library_function_names)
    BIND(strings_free)
    BIND(library_new_function_with_name)
    BIND(function_release)
    BIND(function_name)
    BIND(function_type)
    BIND(device_new_compute_pipeline_state_with_function)
    BIND(compute_pipeline_release)
    BIND(compute_pipeline_max_total_threads_per_threadgroup)
    BIND(compute_pipeline_thread_execution_width)
    BIND(compute_pipeline_static_threadgroup_memory_length)
    BIND(device_new_command_queue)
    BIND(command_queue_release)
    BIND(command_queue_command_buffer)
    BIND(command_buffer_release)
    BIND(command_buffer_commit)
    BIND(command_buffer_wait_until_scheduled)
    BIND(command_buffer_wait_until_completed)
    BIND(command_buffer_status)
    BIND(command_buffer_error)
    BIND(command_buffer_add_scheduled_handler)
    BIND(command_buffer_add_completed_handler)
    BIND(command_buffer_compute_command_encoder)
    BIND(compute_encoder_release)
    BIND(compute_encoder_set_compute_pipeline_state)
    BIND(compute_encoder_set_buffer)
    BIND(compute_encoder_set_buffer_offset)
    BIND(compute_encoder_set_bytes)
    BIND(compute_encoder_set_threadgroup_memory_length)
    BIND(compute_encoder_dispatch_threads)
    BIND(compute_encoder_dispatch_threadgroups)
    BIND(compute_encoder_end)
#undef BIND
    loaded = &table;
}

const perry_m2v *perry_metal2vulkan(void) {
    pthread_once(&once, load);
    return loaded;
}

const char *perry_metal2vulkan_error(void) {
    pthread_once(&once, load);
    return error[0] ? error : NULL;
}
