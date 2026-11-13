#ifndef CPERRY_GEOMETRY_H
#define CPERRY_GEOMETRY_H

// CoreGraphics' geometry types, laid out as on Darwin. Declared in C so Swift
// passes them as clang does: a CGRect is four doubles in d0-d3. CGFloat is
// double on 64-bit Darwin and float on 32-bit; it is a macro because Swift's
// C importer treats a typedef named CGFloat specially and drops it on Linux.
#if defined(__LP64__)
#define PERRY_CGFLOAT double
#else
#define PERRY_CGFLOAT float
#endif

typedef struct CGPoint {
    PERRY_CGFLOAT x;
    PERRY_CGFLOAT y;
} CGPoint;

typedef struct CGSize {
    PERRY_CGFLOAT width;
    PERRY_CGFLOAT height;
} CGSize;

typedef struct CGRect {
    CGPoint origin;
    CGSize size;
} CGRect;

typedef struct CGAffineTransform {
    PERRY_CGFLOAT a, b, c, d;
    PERRY_CGFLOAT tx, ty;
} CGAffineTransform;

typedef struct UIEdgeInsets {
    PERRY_CGFLOAT top, left, bottom, right;
} UIEdgeInsets;

// Core Animation's 4x4 transform, row by row, as CATransform3D is.
typedef struct CATransform3D {
    PERRY_CGFLOAT m11, m12, m13, m14;
    PERRY_CGFLOAT m21, m22, m23, m24;
    PERRY_CGFLOAT m31, m32, m33, m34;
    PERRY_CGFLOAT m41, m42, m43, m44;
} CATransform3D;

// Metal's clear color, MTLClearColor, as MetalKit's views take it: four
// doubles on any architecture.
typedef struct PerryClearColor {
    double red, green, blue, alpha;
} PerryClearColor;

// A display link's frame rates: lowest, highest, and preferred; zero for
// the display's own.
typedef struct CAFrameRateRange {
    float minimum, maximum, preferred;
} CAFrameRateRange;

// GLKit's vectors, quaternions and matrices: floats, the matrices in
// column-major order, as unions of these layouts are on Darwin.
typedef struct GLKVector2 { float v[2]; } GLKVector2;
typedef struct GLKVector3 { float v[3]; } GLKVector3;
typedef struct GLKVector4 { float v[4]; } GLKVector4;
typedef struct GLKQuaternion { float q[4]; } GLKQuaternion;
typedef struct GLKMatrix2 { float m[4]; } GLKMatrix2;
typedef struct GLKMatrix3 { float m[9]; } GLKMatrix3;
typedef struct GLKMatrix4 { float m[16]; } GLKMatrix4;

// SceneKit's vectors and matrices, floats on iOS. A matrix's sixteen
// floats lie in the order OpenGL reads them (the translation in m41, m42
// and m43), so a matrix is passed to a shader as it is.
typedef struct SCNVector3 { float x, y, z; } SCNVector3;
typedef struct SCNVector4 { float x, y, z, w; } SCNVector4;
typedef struct SCNMatrix4 {
    float m11, m12, m13, m14;
    float m21, m22, m23, m24;
    float m31, m32, m33, m34;
    float m41, m42, m43, m44;
} SCNMatrix4;

// simd's float vectors and matrix, wrapped in structures: a structure of
// vector members passes in vector registers as the vectors themselves do,
// and Swift can use a structure from C where it cannot use SIMD types in a
// C function's signature.
typedef float perry_float2 __attribute__((ext_vector_type(2)));
typedef float perry_float3 __attribute__((ext_vector_type(3)));
typedef float perry_float4 __attribute__((ext_vector_type(4)));
typedef struct PerrySimdFloat2 { perry_float2 v; } PerrySimdFloat2;
typedef struct PerrySimdFloat3 { perry_float3 v; } PerrySimdFloat3;
typedef struct PerrySimdFloat4 { perry_float4 v; } PerrySimdFloat4;
typedef struct PerrySimdFloat4x4 { perry_float4 c0, c1, c2, c3; } PerrySimdFloat4x4;

// Core Location's coordinates and MapKit's regions and map geometry: all
// doubles, so they pass in floating-point registers as on Darwin.
typedef struct CLLocationCoordinate2D {
    double latitude;
    double longitude;
} CLLocationCoordinate2D;

typedef struct MKCoordinateSpan {
    double latitudeDelta;
    double longitudeDelta;
} MKCoordinateSpan;

typedef struct MKCoordinateRegion {
    CLLocationCoordinate2D center;
    MKCoordinateSpan span;
} MKCoordinateRegion;

typedef struct MKMapPoint {
    double x;
    double y;
} MKMapPoint;

typedef struct MKMapSize {
    double width;
    double height;
} MKMapSize;

typedef struct MKMapRect {
    MKMapPoint origin;
    MKMapSize size;
} MKMapRect;

// Foundation's NSRange, as UIKit's methods take it.
typedef struct PerryRange {
    unsigned long location;
    unsigned long length;
} PerryRange;

// CFRange, for frameworks that take one without importing Foundation's
// declaration of it (CoreText's, in UIKit).
typedef struct PerryCFRange {
    long location;
    long length;
} PerryCFRange;

// The function Darwin code calls for the host's OpenGL ES function `name`
// ("glClearColor"): on armv7 a thunk for those with floating-point
// parameters, which Darwin passes in core registers; otherwise `host`.
void *perry_gles_darwin_function(const char *name, void *host);

#endif
