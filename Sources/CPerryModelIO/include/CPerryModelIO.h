#ifndef CPERRY_MODELIO_H
#define CPERRY_MODELIO_H

// Model I/O's simd vectors and matrices, each wrapped in a structure: a
// structure of one vector passes in the registers the vector itself does
// (an xmm register on x86_64, a v register on arm64), and Swift can use a
// structure in a C function's signature where it cannot use a SIMD type.
// Vectors wider than 16 bytes and the matrices pass in memory, as on Darwin.

typedef float perry_mdl_float2 __attribute__((ext_vector_type(2)));
typedef float perry_mdl_float3 __attribute__((ext_vector_type(3)));
typedef float perry_mdl_float4 __attribute__((ext_vector_type(4)));
typedef double perry_mdl_double2 __attribute__((ext_vector_type(2)));
typedef unsigned int perry_mdl_uint2 __attribute__((ext_vector_type(2)));
typedef unsigned int perry_mdl_uint3 __attribute__((ext_vector_type(3)));
typedef int perry_mdl_int2 __attribute__((ext_vector_type(2)));

typedef struct PerryMDLFloat2 { perry_mdl_float2 v; } PerryMDLFloat2;
typedef struct PerryMDLFloat3 { perry_mdl_float3 v; } PerryMDLFloat3;
typedef struct PerryMDLFloat4 { perry_mdl_float4 v; } PerryMDLFloat4;
typedef struct PerryMDLDouble2 { perry_mdl_double2 v; } PerryMDLDouble2;
/// vector_double3 and vector_double4, 32 bytes, which pass and return in
/// memory (indirectly on arm64): Swift imports no vector that wide, and a
/// structure of four doubles would be a homogeneous aggregate arm64 passes
/// in registers, so the last lane is kept as its bits.
typedef struct PerryMDLDouble4 { double x, y, z; unsigned long long wBits; } PerryMDLDouble4;
typedef PerryMDLDouble4 PerryMDLDouble3;
typedef struct PerryMDLUInt2 { perry_mdl_uint2 v; } PerryMDLUInt2;
typedef struct PerryMDLUInt3 { perry_mdl_uint3 v; } PerryMDLUInt3;
typedef struct PerryMDLInt2 { perry_mdl_int2 v; } PerryMDLInt2;

/// matrix_float4x4 and matrix_double4x4: four columns.
typedef struct PerryMDLFloat4x4 { perry_mdl_float4 c0, c1, c2, c3; } PerryMDLFloat4x4;
/// matrix_double4x4 as sixteen doubles, column by column: in memory either way.
typedef struct PerryMDLDouble4x4 { double m[16]; } PerryMDLDouble4x4;

/// MDLAxisAlignedBoundingBox: the maximum first.
typedef struct PerryMDLBoundingBox {
    perry_mdl_float3 maxBounds;
    perry_mdl_float3 minBounds;
} PerryMDLBoundingBox;

/// NSFastEnumerationState.
typedef struct PerryMDLFastEnumerationState {
    unsigned long state;
    void **itemsPtr;
    unsigned long *mutationsPtr;
    unsigned long extra[5];
} PerryMDLFastEnumerationState;

/// Fills `out` with a vector_double3's or vector_double4's lanes for the
/// object's value at `time`.
typedef void (*perry_mdl_vector_getter)(void *object, const void *selector, double *out, double time);

/// x86_64 Darwin returns a vector_double4 in xmm0 and xmm1 and a
/// vector_double3 in xmm0, xmm1 and st(0), which no C function type gives:
/// these method implementations call the getter for a buffer and return
/// its lanes so. They take the receiver, selector and a time.
void perry_mdl_set_vector_getter(perry_mdl_vector_getter getter);
void perry_mdl_double3_return(void);
void perry_mdl_double4_return(void);

#endif
