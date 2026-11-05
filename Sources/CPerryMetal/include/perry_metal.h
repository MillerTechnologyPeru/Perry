#ifndef PERRY_METAL_H
#define PERRY_METAL_H

// Metal's provider runs Metal's objects on metal2vulkan, a separate library
// (libmetal2vulkan.so, LGPL-3.0-or-later) opened at run time, so that it
// can be replaced and a system without it has no Metal devices rather than
// no provider. These are Perry's declarations of its C ABI, version 1: every
// object an opaque handle, freed by its release; a call that can fail takes
// `char **error` last, stores a message that string_free frees, and returns
// NULL, false or -1. Version 2 adds rendering, 3 vertex attribute reflection, 4 compute
// textures and samplers.

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

/// MTLSize, which Metal's methods take and return by value.
typedef struct MTLSize {
    unsigned long width;
    unsigned long height;
    unsigned long depth;
} MTLSize;

/// MTLOrigin, MTLRegion, MTLClearColor, MTLViewport and MTLScissorRect.
typedef struct MTLOrigin {
    unsigned long x, y, z;
} MTLOrigin;

typedef struct MTLRegion {
    MTLOrigin origin;
    MTLSize size;
} MTLRegion;

typedef struct MTLClearColor {
    double red, green, blue, alpha;
} MTLClearColor;

typedef struct MTLViewport {
    double originX, originY, width, height, znear, zfar;
} MTLViewport;

typedef struct MTLScissorRect {
    unsigned long x, y, width, height;
} MTLScissorRect;

typedef struct perry_m2v_texture_descriptor {
    uint32_t texture_type;
    uint32_t pixel_format;
    uint64_t width, height, depth;
    uint64_t mipmap_level_count, sample_count, array_length;
    uint64_t usage;
    uint64_t resource_options;
} perry_m2v_texture_descriptor;

typedef struct perry_m2v_sampler_descriptor {
    uint32_t min_filter, mag_filter, mip_filter;
    uint32_t s_address_mode, t_address_mode, r_address_mode;
    uint32_t border_color;
    bool normalized_coordinates;
    float lod_min_clamp, lod_max_clamp;
    uint32_t max_anisotropy;
    uint32_t compare_function;
} perry_m2v_sampler_descriptor;

typedef struct perry_m2v_stencil_descriptor {
    uint32_t compare_function;
    uint32_t stencil_failure_operation, depth_failure_operation, depth_stencil_pass_operation;
    uint32_t read_mask, write_mask;
} perry_m2v_stencil_descriptor;

typedef struct perry_m2v_depth_stencil_descriptor {
    uint32_t depth_compare_function;
    bool depth_write_enabled;
    perry_m2v_stencil_descriptor front_face_stencil, back_face_stencil;
} perry_m2v_depth_stencil_descriptor;

typedef struct perry_m2v_color_attachment {
    /// 0 for none.
    uint32_t pixel_format;
    bool blending_enabled;
    uint32_t source_rgb_blend_factor, destination_rgb_blend_factor, rgb_blend_operation;
    uint32_t source_alpha_blend_factor, destination_alpha_blend_factor, alpha_blend_operation;
    uint32_t write_mask;
} perry_m2v_color_attachment;

typedef struct perry_m2v_vertex_attribute {
    /// 0 for none.
    uint32_t format, offset, buffer_index;
} perry_m2v_vertex_attribute;

typedef struct perry_m2v_vertex_layout {
    /// UINT32_MAX for a dynamic stride.
    uint32_t stride, step_function, step_rate;
} perry_m2v_vertex_layout;

typedef struct perry_m2v_render_pipeline_descriptor {
    void *vertex_function;
    void *fragment_function;
    perry_m2v_color_attachment color_attachments[8];
    uint32_t depth_attachment_pixel_format, stencil_attachment_pixel_format;
    uint32_t raster_sample_count;
    bool alpha_to_coverage_enabled, alpha_to_one_enabled, rasterization_enabled;
    uint32_t input_primitive_topology;
    bool has_vertex_descriptor;
    perry_m2v_vertex_attribute attributes[31];
    perry_m2v_vertex_layout layouts[31];
} perry_m2v_render_pipeline_descriptor;

typedef struct perry_m2v_pass_attachment {
    void *texture;
    uint64_t level, slice, depth_plane;
    void *resolve_texture;
    uint64_t resolve_level, resolve_slice, resolve_depth_plane;
    uint64_t load_action, store_action;
    /// A colour's red, green, blue and alpha; the depth or stencil in [0].
    double clear[4];
} perry_m2v_pass_attachment;

typedef struct perry_m2v_render_pass_descriptor {
    perry_m2v_pass_attachment color_attachments[8];
    perry_m2v_pass_attachment depth_attachment, stencil_attachment;
    void *visibility_result_buffer;
    uint64_t render_target_width, render_target_height, render_target_array_length;
    uint64_t default_raster_sample_count;
} perry_m2v_render_pass_descriptor;

/// MTLVertexAttribute.
typedef struct perry_m2v_attribute {
    char *name;
    uint32_t attribute_index;
    uint32_t attribute_type;
    bool active, patch_data, patch_control_point_data;
} perry_m2v_attribute;

/// MTLArgument: a pipeline's binding of one stage. A buffer's struct, a
/// member's struct or array, and an array's element struct or array index
/// the reflection's tables, or are -1 for none.
typedef struct perry_m2v_argument {
    char *name;
    /// MTLArgumentType, MTLArgumentAccess.
    uint32_t binding_type, index, access;
    bool active, is_argument;
    uint64_t buffer_alignment, buffer_data_size;
    /// MTLDataType.
    uint32_t buffer_data_type;
    int64_t buffer_struct;
    /// MTLTextureType, MTLDataType.
    uint32_t texture_type, texture_data_type;
    bool is_depth_texture;
    uint32_t array_length;
    uint64_t threadgroup_alignment, threadgroup_data_size;
} perry_m2v_argument;

/// MTLStructType: its members, contiguous in the members table.
typedef struct perry_m2v_struct {
    uint64_t first_member, member_count;
} perry_m2v_struct;

typedef struct perry_m2v_struct_member {
    char *name;
    uint64_t offset;
    uint32_t data_type, argument_index;
    int64_t struct_type, array_type;
} perry_m2v_struct_member;

typedef struct perry_m2v_array_type {
    uint32_t element_type, array_length;
    uint64_t stride;
    uint32_t argument_index_stride;
    int64_t element_struct, element_array;
} perry_m2v_array_type;

/// MTLRenderPipelineReflection and MTLComputePipelineReflection.
typedef struct perry_m2v_reflection {
    perry_m2v_argument *vertex;
    size_t vertex_count;
    perry_m2v_argument *fragment;
    size_t fragment_count;
    perry_m2v_struct *structs;
    size_t struct_count;
    perry_m2v_struct_member *members;
    size_t member_count;
    perry_m2v_array_type *arrays;
    size_t array_count;
    /// A compute pipeline's kernel arguments; none for a render pipeline's.
    perry_m2v_argument *kernel;
    size_t kernel_count;
} perry_m2v_reflection;

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

    perry_m2v_handle (* _Nonnull device_new_texture)(perry_m2v_handle, const perry_m2v_texture_descriptor *, perry_m2v_error);
    void (* _Nonnull texture_release)(perry_m2v_handle);
    void (* _Nonnull texture_descriptor_get)(perry_m2v_handle, perry_m2v_texture_descriptor *);
    bool (* _Nonnull texture_replace_region)(perry_m2v_handle, MTLRegion, uint64_t level, uint64_t slice, const void *bytes,
                                   size_t length, uint64_t bytes_per_row, uint64_t bytes_per_image, perry_m2v_error);
    bool (* _Nonnull texture_get_bytes)(perry_m2v_handle, void *bytes, size_t length, uint64_t bytes_per_row,
                              uint64_t bytes_per_image, MTLRegion, uint64_t level, uint64_t slice, perry_m2v_error);
    perry_m2v_handle (* _Nonnull texture_new_view)(perry_m2v_handle, uint32_t pixel_format, uint32_t texture_type,
                                         uint64_t first_level, uint64_t level_count, uint64_t first_slice,
                                         uint64_t slice_count, perry_m2v_error);
    perry_m2v_handle (* _Nonnull device_new_sampler_state)(perry_m2v_handle, const perry_m2v_sampler_descriptor *,
                                                 perry_m2v_error);
    void (* _Nonnull sampler_state_release)(perry_m2v_handle);
    perry_m2v_handle (* _Nonnull device_new_depth_stencil_state)(perry_m2v_handle, const perry_m2v_depth_stencil_descriptor *,
                                                       perry_m2v_error);
    void (* _Nonnull depth_stencil_state_release)(perry_m2v_handle);
    perry_m2v_handle (* _Nonnull device_new_render_pipeline_state)(perry_m2v_handle,
                                                         const perry_m2v_render_pipeline_descriptor *,
                                                         perry_m2v_error);
    void (* _Nonnull render_pipeline_release)(perry_m2v_handle);

    perry_m2v_handle (* _Nonnull command_buffer_render_command_encoder)(perry_m2v_handle,
                                                              const perry_m2v_render_pass_descriptor *,
                                                              perry_m2v_error);
    void (* _Nonnull render_encoder_release)(perry_m2v_handle);
    bool (* _Nonnull render_encoder_set_render_pipeline_state)(perry_m2v_handle, perry_m2v_handle, perry_m2v_error);
    bool (* _Nonnull render_encoder_set_vertex_buffer)(perry_m2v_handle, perry_m2v_handle, uint64_t, uint32_t, perry_m2v_error);
    bool (* _Nonnull render_encoder_set_vertex_buffer_offset)(perry_m2v_handle, uint64_t, uint32_t, perry_m2v_error);
    bool (* _Nonnull render_encoder_set_vertex_bytes)(perry_m2v_handle, const void *, size_t, uint32_t, perry_m2v_error);
    bool (* _Nonnull render_encoder_set_vertex_texture)(perry_m2v_handle, perry_m2v_handle, uint32_t, perry_m2v_error);
    bool (* _Nonnull render_encoder_set_vertex_sampler_state)(perry_m2v_handle, perry_m2v_handle, uint32_t, perry_m2v_error);
    bool (* _Nonnull render_encoder_set_fragment_buffer)(perry_m2v_handle, perry_m2v_handle, uint64_t, uint32_t, perry_m2v_error);
    bool (* _Nonnull render_encoder_set_fragment_buffer_offset)(perry_m2v_handle, uint64_t, uint32_t, perry_m2v_error);
    bool (* _Nonnull render_encoder_set_fragment_bytes)(perry_m2v_handle, const void *, size_t, uint32_t, perry_m2v_error);
    bool (* _Nonnull render_encoder_set_fragment_texture)(perry_m2v_handle, perry_m2v_handle, uint32_t, perry_m2v_error);
    bool (* _Nonnull render_encoder_set_fragment_sampler_state)(perry_m2v_handle, perry_m2v_handle, uint32_t, perry_m2v_error);
    bool (* _Nonnull render_encoder_set_viewport)(perry_m2v_handle, MTLViewport, perry_m2v_error);
    bool (* _Nonnull render_encoder_set_scissor_rect)(perry_m2v_handle, uint64_t, uint64_t, uint64_t, uint64_t, perry_m2v_error);
    bool (* _Nonnull render_encoder_set_cull_mode)(perry_m2v_handle, uint32_t, perry_m2v_error);
    bool (* _Nonnull render_encoder_set_front_facing_winding)(perry_m2v_handle, uint32_t, perry_m2v_error);
    bool (* _Nonnull render_encoder_set_triangle_fill_mode)(perry_m2v_handle, uint32_t, perry_m2v_error);
    bool (* _Nonnull render_encoder_set_depth_stencil_state)(perry_m2v_handle, perry_m2v_handle, perry_m2v_error);
    bool (* _Nonnull render_encoder_set_stencil_reference_values)(perry_m2v_handle, uint32_t, uint32_t, perry_m2v_error);
    bool (* _Nonnull render_encoder_set_blend_color)(perry_m2v_handle, float, float, float, float, perry_m2v_error);
    bool (* _Nonnull render_encoder_set_depth_bias)(perry_m2v_handle, float, float, float, perry_m2v_error);
    bool (* _Nonnull render_encoder_set_visibility_result_mode)(perry_m2v_handle, uint64_t, uint64_t, perry_m2v_error);
    bool (* _Nonnull render_encoder_draw_primitives)(perry_m2v_handle, uint64_t type, uint32_t start, uint32_t count,
                                           uint32_t instances, uint32_t base_instance, perry_m2v_error);
    bool (* _Nonnull render_encoder_draw_indexed_primitives)(perry_m2v_handle, uint64_t type, uint32_t count,
                                                   uint32_t index_type, perry_m2v_handle index_buffer,
                                                   uint64_t offset, uint32_t instances, int32_t base_vertex,
                                                   uint32_t base_instance, perry_m2v_error);
    bool (* _Nonnull render_encoder_draw_primitives_indirect)(perry_m2v_handle, uint64_t type, perry_m2v_handle, uint64_t,
                                                    perry_m2v_error);
    bool (* _Nonnull render_encoder_draw_indexed_primitives_indirect)(perry_m2v_handle, uint64_t type, uint32_t index_type,
                                                            perry_m2v_handle index_buffer, uint64_t offset,
                                                            perry_m2v_handle indirect, uint64_t indirect_offset,
                                                            perry_m2v_error);
    bool (* _Nonnull render_encoder_end)(perry_m2v_handle, perry_m2v_error);

    perry_m2v_handle (* _Nonnull command_buffer_blit_command_encoder)(perry_m2v_handle, perry_m2v_error);
    void (* _Nonnull blit_encoder_release)(perry_m2v_handle);
    bool (* _Nonnull blit_encoder_copy_buffer_to_buffer)(perry_m2v_handle, perry_m2v_handle, uint64_t, perry_m2v_handle, uint64_t,
                                               uint64_t, perry_m2v_error);
    bool (* _Nonnull blit_encoder_copy_buffer_to_texture)(perry_m2v_handle, perry_m2v_handle source, uint64_t offset,
                                                uint64_t bytes_per_row, uint64_t bytes_per_image, MTLSize size,
                                                perry_m2v_handle texture, uint64_t slice, uint64_t level,
                                                MTLOrigin origin, uint64_t options, perry_m2v_error);
    bool (* _Nonnull blit_encoder_copy_texture_to_buffer)(perry_m2v_handle, perry_m2v_handle texture, uint64_t slice,
                                                uint64_t level, MTLOrigin origin, MTLSize size,
                                                perry_m2v_handle buffer, uint64_t offset, uint64_t bytes_per_row,
                                                uint64_t bytes_per_image, uint64_t options, perry_m2v_error);
    bool (* _Nonnull blit_encoder_copy_texture_to_texture)(perry_m2v_handle, perry_m2v_handle source, uint64_t slice,
                                                 uint64_t level, MTLOrigin origin, MTLSize size,
                                                 perry_m2v_handle destination, uint64_t destination_slice,
                                                 uint64_t destination_level, MTLOrigin destination_origin,
                                                 perry_m2v_error);
    bool (* _Nonnull blit_encoder_generate_mipmaps)(perry_m2v_handle, perry_m2v_handle, perry_m2v_error);
    bool (* _Nonnull blit_encoder_fill_buffer)(perry_m2v_handle, perry_m2v_handle, uint64_t, uint64_t, uint8_t, perry_m2v_error);
    bool (* _Nonnull blit_encoder_synchronize_resource)(perry_m2v_handle, perry_m2v_handle buffer, perry_m2v_handle texture,
                                              perry_m2v_error);
    bool (* _Nonnull blit_encoder_end)(perry_m2v_handle, perry_m2v_error);

    int64_t (* _Nonnull function_vertex_attributes)(perry_m2v_handle, perry_m2v_attribute **);
    void (* _Nonnull attributes_free)(perry_m2v_attribute *, size_t);
    bool (* _Nonnull render_pipeline_reflection)(perry_m2v_handle, perry_m2v_reflection *, perry_m2v_error);
    bool (* _Nonnull compute_pipeline_reflection)(perry_m2v_handle, perry_m2v_reflection *, perry_m2v_error);
    void (* _Nonnull reflection_free)(perry_m2v_reflection *);
    bool (* _Nonnull compute_encoder_set_texture)(perry_m2v_handle, perry_m2v_handle, uint32_t, perry_m2v_error);
    /// MTLBarrierScope.
    bool (* _Nonnull compute_encoder_memory_barrier)(perry_m2v_handle, uint64_t, perry_m2v_error);
    bool (* _Nonnull compute_encoder_dispatch_threadgroups_indirect)(perry_m2v_handle, perry_m2v_handle, uint64_t, MTLSize,
                                                                       perry_m2v_error);
    bool (* _Nonnull compute_encoder_set_sampler_state)(perry_m2v_handle, perry_m2v_handle, uint32_t, perry_m2v_error);
} perry_m2v;

/// Opens libmetal2vulkan.so the first time: PERRY_METAL2VULKAN's path, else
/// the one beside libPerryMetal.so, else the library path's. NULL when it
/// cannot be opened or is another ABI version; perry_metal2vulkan_error
/// then says why.
const perry_m2v *perry_metal2vulkan(void);
const char *perry_metal2vulkan_error(void);

#endif
