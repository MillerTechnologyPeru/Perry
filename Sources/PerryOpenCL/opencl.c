// libPerryOpenCL: the provider for a Mac program's OpenCL.framework, with
// no platform and no device. Every Mac has the framework, and programs that
// link it weakly call it without checking it is there: here each function
// is, and answers as a Mac with no OpenCL device would, so a program falls
// back to drawing with OpenGL alone. Objects can't be made, so the functions
// that take them say that what they were given is not one.

#include "PerryOpenCL.h"

#include <stddef.h>
#include <stdint.h>

#define CL_SYMBOL(name) __asm__("_" #name) __attribute__((visibility("default"), used))

enum {
    CL_SUCCESS = 0,
    CL_DEVICE_NOT_FOUND = -1,
    CL_INVALID_VALUE = -30,
    CL_INVALID_PLATFORM = -32,
    CL_INVALID_DEVICE = -33,
    CL_INVALID_CONTEXT = -34,
    CL_INVALID_COMMAND_QUEUE = -36,
    CL_INVALID_MEM_OBJECT = -38,
    CL_INVALID_SAMPLER = -41,
    CL_INVALID_PROGRAM = -44,
    CL_INVALID_KERNEL = -48,
    CL_INVALID_EVENT = -58,
    CL_PLATFORM_NOT_FOUND_KHR = -1001,
};

typedef int32_t cl_int;
typedef uint32_t cl_uint;

static void *fail(cl_int *error, cl_int code) {
    if (error) *error = code;
    return NULL;
}

// MARK: - Platforms and devices

cl_int perry_clGetPlatformIDs(cl_uint count, void **platforms, cl_uint *found) CL_SYMBOL(clGetPlatformIDs);
cl_int perry_clGetPlatformIDs(cl_uint count, void **platforms, cl_uint *found) {
    if ((count == 0 && platforms) || (!platforms && !found)) return CL_INVALID_VALUE;
    if (found) *found = 0;
    return CL_PLATFORM_NOT_FOUND_KHR;
}

cl_int perry_clGetPlatformInfo(void *platform, cl_uint name, size_t size, void *value, size_t *returned)
    CL_SYMBOL(clGetPlatformInfo);
cl_int perry_clGetPlatformInfo(void *platform, cl_uint name, size_t size, void *value, size_t *returned) {
    (void)platform; (void)name; (void)size; (void)value;
    if (returned) *returned = 0;
    return CL_INVALID_PLATFORM;
}

cl_int perry_clGetDeviceIDs(void *platform, uint64_t type, cl_uint count, void **devices, cl_uint *found)
    CL_SYMBOL(clGetDeviceIDs);
cl_int perry_clGetDeviceIDs(void *platform, uint64_t type, cl_uint count, void **devices, cl_uint *found) {
    (void)platform; (void)type; (void)count; (void)devices;
    if (found) *found = 0;
    return CL_DEVICE_NOT_FOUND;
}

cl_int perry_clGetDeviceInfo(void *device, cl_uint name, size_t size, void *value, size_t *returned)
    CL_SYMBOL(clGetDeviceInfo);
cl_int perry_clGetDeviceInfo(void *device, cl_uint name, size_t size, void *value, size_t *returned) {
    (void)device; (void)name; (void)size; (void)value;
    if (returned) *returned = 0;
    return CL_INVALID_DEVICE;
}

// MARK: - Contexts

void *perry_clCreateContext(const intptr_t *properties, cl_uint count, void *const *devices, void *notify, void *data,
                            cl_int *error) CL_SYMBOL(clCreateContext);
void *perry_clCreateContext(const intptr_t *properties, cl_uint count, void *const *devices, void *notify, void *data,
                            cl_int *error) {
    (void)properties; (void)notify; (void)data;
    return fail(error, count == 0 || !devices ? CL_INVALID_VALUE : CL_INVALID_DEVICE);
}

void *perry_clCreateContextFromType(const intptr_t *properties, uint64_t type, void *notify, void *data, cl_int *error)
    CL_SYMBOL(clCreateContextFromType);
void *perry_clCreateContextFromType(const intptr_t *properties, uint64_t type, void *notify, void *data, cl_int *error) {
    (void)properties; (void)type; (void)notify; (void)data;
    return fail(error, CL_DEVICE_NOT_FOUND);
}

#define TAKES(kind, error_code)                                                                                        \
    cl_int perry_cl##kind(void *object) CL_SYMBOL(cl##kind);                                                           \
    cl_int perry_cl##kind(void *object) { (void)object; return error_code; }

TAKES(RetainContext, CL_INVALID_CONTEXT)
TAKES(ReleaseContext, CL_INVALID_CONTEXT)
TAKES(RetainCommandQueue, CL_INVALID_COMMAND_QUEUE)
TAKES(ReleaseCommandQueue, CL_INVALID_COMMAND_QUEUE)
TAKES(Flush, CL_INVALID_COMMAND_QUEUE)
TAKES(Finish, CL_INVALID_COMMAND_QUEUE)
TAKES(RetainMemObject, CL_INVALID_MEM_OBJECT)
TAKES(ReleaseMemObject, CL_INVALID_MEM_OBJECT)
TAKES(RetainSampler, CL_INVALID_SAMPLER)
TAKES(ReleaseSampler, CL_INVALID_SAMPLER)
TAKES(RetainProgram, CL_INVALID_PROGRAM)
TAKES(ReleaseProgram, CL_INVALID_PROGRAM)
TAKES(RetainKernel, CL_INVALID_KERNEL)
TAKES(ReleaseKernel, CL_INVALID_KERNEL)
TAKES(RetainEvent, CL_INVALID_EVENT)
TAKES(ReleaseEvent, CL_INVALID_EVENT)

// The clGet*Info functions: (object, name, size, value, size returned).
#define INFO(kind, error_code)                                                                                         \
    cl_int perry_clGet##kind##Info(void *object, cl_uint name, size_t size, void *value, size_t *returned)             \
        CL_SYMBOL(clGet##kind##Info);                                                                                  \
    cl_int perry_clGet##kind##Info(void *object, cl_uint name, size_t size, void *value, size_t *returned) {           \
        (void)object; (void)name; (void)size; (void)value;                                                             \
        if (returned) *returned = 0;                                                                                   \
        return error_code;                                                                                             \
    }

INFO(Context, CL_INVALID_CONTEXT)
INFO(CommandQueue, CL_INVALID_COMMAND_QUEUE)
INFO(MemObject, CL_INVALID_MEM_OBJECT)
INFO(Program, CL_INVALID_PROGRAM)
INFO(Kernel, CL_INVALID_KERNEL)
INFO(Event, CL_INVALID_EVENT)

cl_int perry_clGetKernelArgInfo(void *kernel, cl_uint index, cl_uint name, size_t size, void *value, size_t *returned)
    CL_SYMBOL(clGetKernelArgInfo);
cl_int perry_clGetKernelArgInfo(void *kernel, cl_uint index, cl_uint name, size_t size, void *value, size_t *returned) {
    (void)kernel; (void)index; (void)name; (void)size; (void)value;
    if (returned) *returned = 0;
    return CL_INVALID_KERNEL;
}

cl_int perry_clGetKernelWorkGroupInfo(void *kernel, void *device, cl_uint name, size_t size, void *value, size_t *returned)
    CL_SYMBOL(clGetKernelWorkGroupInfo);
cl_int perry_clGetKernelWorkGroupInfo(void *kernel, void *device, cl_uint name, size_t size, void *value, size_t *returned) {
    (void)kernel; (void)device; (void)name; (void)size; (void)value;
    if (returned) *returned = 0;
    return CL_INVALID_KERNEL;
}

cl_int perry_clGetProgramBuildInfo(void *program, void *device, cl_uint name, size_t size, void *value, size_t *returned)
    CL_SYMBOL(clGetProgramBuildInfo);
cl_int perry_clGetProgramBuildInfo(void *program, void *device, cl_uint name, size_t size, void *value, size_t *returned) {
    (void)program; (void)device; (void)name; (void)size; (void)value;
    if (returned) *returned = 0;
    return CL_INVALID_PROGRAM;
}

// MARK: - Making objects in a context

void *perry_clCreateCommandQueue(void *context, void *device, uint64_t properties, cl_int *error)
    CL_SYMBOL(clCreateCommandQueue);
void *perry_clCreateCommandQueue(void *context, void *device, uint64_t properties, cl_int *error) {
    (void)context; (void)device; (void)properties;
    return fail(error, CL_INVALID_CONTEXT);
}

void *perry_clCreateBuffer(void *context, uint64_t flags, size_t size, void *host, cl_int *error) CL_SYMBOL(clCreateBuffer);
void *perry_clCreateBuffer(void *context, uint64_t flags, size_t size, void *host, cl_int *error) {
    (void)context; (void)flags; (void)size; (void)host;
    return fail(error, CL_INVALID_CONTEXT);
}

void *perry_clCreateFromGLBuffer(void *context, uint64_t flags, cl_uint buffer, cl_int *error) CL_SYMBOL(clCreateFromGLBuffer);
void *perry_clCreateFromGLBuffer(void *context, uint64_t flags, cl_uint buffer, cl_int *error) {
    (void)context; (void)flags; (void)buffer;
    return fail(error, CL_INVALID_CONTEXT);
}

void *perry_clCreateFromGLTexture(void *context, uint64_t flags, cl_uint target, int32_t level, cl_uint texture, cl_int *error)
    CL_SYMBOL(clCreateFromGLTexture);
void *perry_clCreateFromGLTexture(void *context, uint64_t flags, cl_uint target, int32_t level, cl_uint texture, cl_int *error) {
    (void)context; (void)flags; (void)target; (void)level; (void)texture;
    return fail(error, CL_INVALID_CONTEXT);
}

void *perry_clCreateSampler(void *context, cl_uint normalized, cl_uint addressing, cl_uint filter, cl_int *error)
    CL_SYMBOL(clCreateSampler);
void *perry_clCreateSampler(void *context, cl_uint normalized, cl_uint addressing, cl_uint filter, cl_int *error) {
    (void)context; (void)normalized; (void)addressing; (void)filter;
    return fail(error, CL_INVALID_CONTEXT);
}

void *perry_clCreateProgramWithSource(void *context, cl_uint count, const char **strings, const size_t *lengths, cl_int *error)
    CL_SYMBOL(clCreateProgramWithSource);
void *perry_clCreateProgramWithSource(void *context, cl_uint count, const char **strings, const size_t *lengths, cl_int *error) {
    (void)context; (void)count; (void)strings; (void)lengths;
    return fail(error, CL_INVALID_CONTEXT);
}

cl_int perry_clBuildProgram(void *program, cl_uint count, void *const *devices, const char *options, void *notify, void *data)
    CL_SYMBOL(clBuildProgram);
cl_int perry_clBuildProgram(void *program, cl_uint count, void *const *devices, const char *options, void *notify, void *data) {
    (void)program; (void)count; (void)devices; (void)options; (void)notify; (void)data;
    return CL_INVALID_PROGRAM;
}

void *perry_clCreateKernel(void *program, const char *name, cl_int *error) CL_SYMBOL(clCreateKernel);
void *perry_clCreateKernel(void *program, const char *name, cl_int *error) {
    (void)program; (void)name;
    return fail(error, CL_INVALID_PROGRAM);
}

cl_int perry_clCreateKernelsInProgram(void *program, cl_uint count, void **kernels, cl_uint *made)
    CL_SYMBOL(clCreateKernelsInProgram);
cl_int perry_clCreateKernelsInProgram(void *program, cl_uint count, void **kernels, cl_uint *made) {
    (void)program; (void)count; (void)kernels;
    if (made) *made = 0;
    return CL_INVALID_PROGRAM;
}

cl_int perry_clSetKernelArg(void *kernel, cl_uint index, size_t size, const void *value) CL_SYMBOL(clSetKernelArg);
cl_int perry_clSetKernelArg(void *kernel, cl_uint index, size_t size, const void *value) {
    (void)kernel; (void)index; (void)size; (void)value;
    return CL_INVALID_KERNEL;
}

// MARK: - Commands

cl_int perry_clEnqueueNDRangeKernel(void *queue, void *kernel, cl_uint dimensions, const size_t *offset, const size_t *global,
                                    const size_t *local, cl_uint waits, const void *wait_list, void **event)
    CL_SYMBOL(clEnqueueNDRangeKernel);
cl_int perry_clEnqueueNDRangeKernel(void *queue, void *kernel, cl_uint dimensions, const size_t *offset, const size_t *global,
                                    const size_t *local, cl_uint waits, const void *wait_list, void **event) {
    (void)queue; (void)kernel; (void)dimensions; (void)offset; (void)global; (void)local; (void)waits; (void)wait_list;
    if (event) *event = NULL;
    return CL_INVALID_COMMAND_QUEUE;
}

#define GL_OBJECTS(kind)                                                                                               \
    cl_int perry_clEnqueue##kind##GLObjects(void *queue, cl_uint count, void *const *objects, cl_uint waits,           \
                                            const void *wait_list, void **event) CL_SYMBOL(clEnqueue##kind##GLObjects); \
    cl_int perry_clEnqueue##kind##GLObjects(void *queue, cl_uint count, void *const *objects, cl_uint waits,           \
                                            const void *wait_list, void **event) {                                     \
        (void)queue; (void)count; (void)objects; (void)waits; (void)wait_list;                                         \
        if (event) *event = NULL;                                                                                      \
        return CL_INVALID_COMMAND_QUEUE;                                                                               \
    }

GL_OBJECTS(Acquire)
GL_OBJECTS(Release)

cl_int perry_clWaitForEvents(cl_uint count, void *const *events) CL_SYMBOL(clWaitForEvents);
cl_int perry_clWaitForEvents(cl_uint count, void *const *events) {
    return count == 0 || !events ? CL_INVALID_VALUE : CL_INVALID_EVENT;
}

// Apple's notification function for contexts, which logs their errors: as
// no context is made, nothing calls it.
void perry_clLogMessagesToStdoutAPPLE(const char *message, const void *info, size_t size, void *data)
    CL_SYMBOL(clLogMessagesToStdoutAPPLE);
void perry_clLogMessagesToStdoutAPPLE(const char *message, const void *info, size_t size, void *data) {
    (void)message; (void)info; (void)size; (void)data;
}
