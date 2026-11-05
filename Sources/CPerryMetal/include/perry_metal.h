#ifndef PERRY_METAL_H
#define PERRY_METAL_H

// Metal's provider runs Metal's objects on metal2vulkan, a separate library
// (libmetal2vulkan.so, LGPL-3.0-or-later) opened at run time, so that it
// can be replaced and a system without it has no Metal devices rather than
// no provider. These are Perry's declarations of its C ABI, version 1: every
// object an opaque handle, freed by its release; a call that can fail takes
// `char **error` last, stores a message that string_free frees, and returns
// NULL, false or -1.

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

/// MTLSize, which Metal's methods take and return by value.
typedef struct MTLSize {
    unsigned long width;
    unsigned long height;
    unsigned long depth;
} MTLSize;

/// Metal's device queries.
typedef struct perry_m2v_device_properties {
    uint64_t registry_id;
    uint64_t max_buffer_length;
    MTLSize max_threads_per_threadgroup;
    uint64_t max_threadgroup_memory_length;
    /// 0 discrete, 1 integrated, 2 virtual, 3 CPU, 4 other.
    uint32_t kind;
    bool has_unified_memory;
    uint32_t argument_buffers_support;
    uint32_t read_write_texture_support;
    uint32_t vendor_id;
    uint32_t device_id;
    uint8_t device_uuid[16];
} perry_m2v_device_properties;

typedef void *perry_m2v_handle;
typedef char **perry_m2v_error;
typedef void (*perry_m2v_handler)(void *context);

/// libmetal2vulkan.so's functions.
typedef struct perry_m2v {
    void (* _Nonnull string_free)(char *);

    int64_t (* _Nonnull copy_all_devices)(perry_m2v_handle *devices, size_t capacity, perry_m2v_error);
    void (* _Nonnull device_release)(perry_m2v_handle);
    const char *(* _Nonnull device_name)(perry_m2v_handle);
    void (* _Nonnull device_properties_get)(perry_m2v_handle, perry_m2v_device_properties *);
    bool (* _Nonnull device_supports_family)(perry_m2v_handle, int64_t);
    int (* _Nonnull device_supports_texture_sample_count)(perry_m2v_handle, uint64_t);

    perry_m2v_handle (* _Nonnull device_new_buffer)(perry_m2v_handle, const void *bytes, uint64_t length, uint64_t options,
                                          perry_m2v_error);
    void (* _Nonnull buffer_release)(perry_m2v_handle);
    uint64_t (* _Nonnull buffer_length)(perry_m2v_handle);
    void *(* _Nonnull buffer_contents)(perry_m2v_handle);
    bool (* _Nonnull buffer_did_modify_range)(perry_m2v_handle, uint64_t location, uint64_t length, perry_m2v_error);

    perry_m2v_handle (* _Nonnull device_new_library_with_data)(perry_m2v_handle, const void *, size_t, perry_m2v_error);
    void (* _Nonnull library_release)(perry_m2v_handle);
    size_t (* _Nonnull library_function_names)(perry_m2v_handle, char ***names);
    void (* _Nonnull strings_free)(char **, size_t);
    perry_m2v_handle (* _Nonnull library_new_function_with_name)(perry_m2v_handle, const char *, perry_m2v_error);
    void (* _Nonnull function_release)(perry_m2v_handle);
    const char *(* _Nonnull function_name)(perry_m2v_handle);
    uint32_t (* _Nonnull function_type)(perry_m2v_handle);

    perry_m2v_handle (* _Nonnull device_new_compute_pipeline_state_with_function)(perry_m2v_handle device,
                                                                        perry_m2v_handle function, perry_m2v_error);
    void (* _Nonnull compute_pipeline_release)(perry_m2v_handle);
    uint32_t (* _Nonnull compute_pipeline_max_total_threads_per_threadgroup)(perry_m2v_handle);
    uint32_t (* _Nonnull compute_pipeline_thread_execution_width)(perry_m2v_handle);
    uint32_t (* _Nonnull compute_pipeline_static_threadgroup_memory_length)(perry_m2v_handle);

    perry_m2v_handle (* _Nonnull device_new_command_queue)(perry_m2v_handle, perry_m2v_error);
    void (* _Nonnull command_queue_release)(perry_m2v_handle);
    perry_m2v_handle (* _Nonnull command_queue_command_buffer)(perry_m2v_handle, perry_m2v_error);
    void (* _Nonnull command_buffer_release)(perry_m2v_handle);
    bool (* _Nonnull command_buffer_commit)(perry_m2v_handle, perry_m2v_error);
    bool (* _Nonnull command_buffer_wait_until_scheduled)(perry_m2v_handle, perry_m2v_error);
    bool (* _Nonnull command_buffer_wait_until_completed)(perry_m2v_handle, perry_m2v_error);
    uint32_t (* _Nonnull command_buffer_status)(perry_m2v_handle);
    char *(* _Nonnull command_buffer_error)(perry_m2v_handle);
    bool (* _Nonnull command_buffer_add_scheduled_handler)(perry_m2v_handle, perry_m2v_handler, void *, perry_m2v_error);
    bool (* _Nonnull command_buffer_add_completed_handler)(perry_m2v_handle, perry_m2v_handler, void *, perry_m2v_error);

    perry_m2v_handle (* _Nonnull command_buffer_compute_command_encoder)(perry_m2v_handle, perry_m2v_error);
    void (* _Nonnull compute_encoder_release)(perry_m2v_handle);
    bool (* _Nonnull compute_encoder_set_compute_pipeline_state)(perry_m2v_handle, perry_m2v_handle, perry_m2v_error);
    bool (* _Nonnull compute_encoder_set_buffer)(perry_m2v_handle, perry_m2v_handle buffer, uint64_t offset, uint32_t index,
                                       perry_m2v_error);
    bool (* _Nonnull compute_encoder_set_buffer_offset)(perry_m2v_handle, uint64_t offset, uint32_t index, perry_m2v_error);
    bool (* _Nonnull compute_encoder_set_bytes)(perry_m2v_handle, const void *, size_t, uint32_t index, perry_m2v_error);
    bool (* _Nonnull compute_encoder_set_threadgroup_memory_length)(perry_m2v_handle, uint32_t length, uint32_t index,
                                                          perry_m2v_error);
    bool (* _Nonnull compute_encoder_dispatch_threads)(perry_m2v_handle, MTLSize threads, MTLSize per_group, perry_m2v_error);
    bool (* _Nonnull compute_encoder_dispatch_threadgroups)(perry_m2v_handle, MTLSize groups, MTLSize per_group,
                                                  perry_m2v_error);
    bool (* _Nonnull compute_encoder_end)(perry_m2v_handle, perry_m2v_error);
} perry_m2v;

/// Opens libmetal2vulkan.so the first time: PERRY_METAL2VULKAN's path, else
/// the one beside libPerryMetal.so, else the library path's. NULL when it
/// cannot be opened or is another ABI version; perry_metal2vulkan_error
/// then says why.
const perry_m2v *perry_metal2vulkan(void);
const char *perry_metal2vulkan_error(void);

#endif
