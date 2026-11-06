#ifndef CPERRY_MOTION_H
#define CPERRY_MOTION_H

// CoreMotion's values, laid out as on Darwin. Declared in C so Swift passes
// them as clang does: three or four doubles come back in floating-point
// registers, a rotation matrix's nine through x8.

typedef struct CMAcceleration {
    double x, y, z;         // in g
} CMAcceleration;

typedef struct CMRotationRate {
    double x, y, z;         // in radians a second
} CMRotationRate;

typedef struct CMQuaternion {
    double x, y, z, w;
} CMQuaternion;

typedef struct CMRotationMatrix {
    double m11, m12, m13;
    double m21, m22, m23;
    double m31, m32, m33;
} CMRotationMatrix;

#endif
