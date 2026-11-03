#ifndef CPERRY_GEOMETRY_H
#define CPERRY_GEOMETRY_H

// CoreGraphics' geometry types, laid out as on 64-bit Darwin. Declared in C
// so Swift passes them as clang does: a CGRect is four doubles in d0-d3.
// CGFloat is double on 64-bit Darwin; it is spelled out because Swift's C
// importer treats a typedef named CGFloat specially and drops it on Linux.

typedef struct CGPoint {
    double x;
    double y;
} CGPoint;

typedef struct CGSize {
    double width;
    double height;
} CGSize;

typedef struct CGRect {
    CGPoint origin;
    CGSize size;
} CGRect;

typedef struct CGAffineTransform {
    double a, b, c, d;
    double tx, ty;
} CGAffineTransform;

typedef struct UIEdgeInsets {
    double top, left, bottom, right;
} UIEdgeInsets;

// Core Animation's 4x4 transform, row by row, as CATransform3D is.
typedef struct CATransform3D {
    double m11, m12, m13, m14;
    double m21, m22, m23, m24;
    double m31, m32, m33, m34;
    double m41, m42, m43, m44;
} CATransform3D;

// GLKit's vectors, quaternions and matrices: floats, the matrices in
// column-major order, as unions of these layouts are on Darwin.
typedef struct GLKVector2 { float v[2]; } GLKVector2;
typedef struct GLKVector3 { float v[3]; } GLKVector3;
typedef struct GLKVector4 { float v[4]; } GLKVector4;
typedef struct GLKQuaternion { float q[4]; } GLKQuaternion;
typedef struct GLKMatrix2 { float m[4]; } GLKMatrix2;
typedef struct GLKMatrix3 { float m[9]; } GLKMatrix3;
typedef struct GLKMatrix4 { float m[16]; } GLKMatrix4;

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

#endif
