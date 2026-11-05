// Forge's kernels, built into the app's default.metallib.

#include <metal_stdlib>
using namespace metal;

kernel void add_arrays(device const float *a [[buffer(0)]],
                       device const float *b [[buffer(1)]],
                       device float *result [[buffer(2)]],
                       uint index [[thread_position_in_grid]]) {
    result[index] = a[index] + b[index];
}

kernel void scale(device float *values [[buffer(0)]],
                  constant float &factor [[buffer(1)]],
                  uint index [[thread_position_in_grid]]) {
    values[index] *= factor;
}

// Each threadgroup's sum, through threadgroup memory the encoder sizes.
kernel void sum_groups(device const uint *input [[buffer(0)]],
                       device uint *sums [[buffer(1)]],
                       threadgroup uint *scratch [[threadgroup(0)]],
                       uint tid [[thread_position_in_threadgroup]],
                       uint group [[threadgroup_position_in_grid]],
                       uint size [[threads_per_threadgroup]],
                       uint index [[thread_position_in_grid]]) {
    scratch[tid] = input[index];
    threadgroup_barrier(mem_flags::mem_threadgroup);
    for (uint stride = size / 2; stride > 0; stride /= 2) {
        if (tid < stride) scratch[tid] += scratch[tid + stride];
        threadgroup_barrier(mem_flags::mem_threadgroup);
    }
    if (tid == 0) sums[group] = scratch[0];
}
