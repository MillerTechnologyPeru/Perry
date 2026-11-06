// CoreMotion's values have Darwin's sizes.

#include "CPerryMotion.h"

_Static_assert(sizeof(CMAcceleration) == 24, "CMAcceleration is three doubles");
_Static_assert(sizeof(CMRotationRate) == 24, "CMRotationRate is three doubles");
_Static_assert(sizeof(CMQuaternion) == 32, "CMQuaternion is four doubles");
_Static_assert(sizeof(CMRotationMatrix) == 72, "CMRotationMatrix is nine doubles");
