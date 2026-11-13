import CPerryGeometry
import Glibc
import PerryObjCInterop

// SceneKit's math: sixteen floats a matrix, in the order OpenGL reads them
// (column-major, the translation in the last column), which is the order of
// an SCNMatrix4's members. Rotations are quaternions as x, y, z, w.

typealias Matrix = [Float]

// SceneKit's structures as messages carry them: floats, so on 32-bit
// Darwin they pass in words.

extension SCNVector3: ObjCStructure {
    #if _pointerBitWidth(_32)
    public typealias ObjCType = ObjCWords3
    #else
    public typealias ObjCType = SCNVector3
    #endif
    public static var objCTypeEncoding: String { "{SCNVector3=fff}" }
}

extension SCNVector4: ObjCStructure {
    #if _pointerBitWidth(_32)
    public typealias ObjCType = ObjCWords4
    #else
    public typealias ObjCType = SCNVector4
    #endif
    public static var objCTypeEncoding: String { "{SCNVector4=ffff}" }
}

extension SCNMatrix4: ObjCStructure {
    #if _pointerBitWidth(_32)
    public typealias ObjCType = ObjCWords16
    #else
    public typealias ObjCType = SCNMatrix4
    #endif
    public static var objCTypeEncoding: String { "{SCNMatrix4=ffffffffffffffff}" }
}

enum SCNMath {
    static let identity: Matrix = [1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1]

    static func matrix(_ m: SCNMatrix4) -> Matrix {
        [m.m11, m.m12, m.m13, m.m14, m.m21, m.m22, m.m23, m.m24, m.m31, m.m32, m.m33, m.m34, m.m41, m.m42, m.m43, m.m44]
    }

    static func matrix4(_ a: Matrix) -> SCNMatrix4 {
        SCNMatrix4(m11: a[0], m12: a[1], m13: a[2], m14: a[3], m21: a[4], m22: a[5], m23: a[6], m24: a[7],
                   m31: a[8], m32: a[9], m33: a[10], m34: a[11], m41: a[12], m42: a[13], m43: a[14], m44: a[15])
    }

    /// `a` times `b`: `b` applied to a point first.
    static func multiply(_ a: Matrix, _ b: Matrix) -> Matrix {
        var r = Matrix(repeating: 0, count: 16)
        for column in 0..<4 {
            for row in 0..<4 {
                var sum: Float = 0
                for k in 0..<4 { sum += a[k * 4 + row] * b[column * 4 + k] }
                r[column * 4 + row] = sum
            }
        }
        return r
    }

    static func translation(_ x: Float, _ y: Float, _ z: Float) -> Matrix {
        var m = identity
        m[12] = x; m[13] = y; m[14] = z
        return m
    }

    static func scaling(_ x: Float, _ y: Float, _ z: Float) -> Matrix {
        var m = identity
        m[0] = x; m[5] = y; m[10] = z
        return m
    }

    // MARK: Quaternions

    typealias Quaternion = (x: Float, y: Float, z: Float, w: Float)

    static let noRotation: Quaternion = (0, 0, 0, 1)

    static func quaternion(axis: SCNVector3, angle: Float) -> Quaternion {
        let length = (axis.x * axis.x + axis.y * axis.y + axis.z * axis.z).squareRoot()
        guard length > 0 else { return noRotation }
        let s = sinf(angle / 2) / length
        return (axis.x * s, axis.y * s, axis.z * s, cosf(angle / 2))
    }

    static func multiply(_ a: Quaternion, _ b: Quaternion) -> Quaternion {
        (a.w * b.x + a.x * b.w + a.y * b.z - a.z * b.y,
         a.w * b.y - a.x * b.z + a.y * b.w + a.z * b.x,
         a.w * b.z + a.x * b.y - a.y * b.x + a.z * b.w,
         a.w * b.w - a.x * b.x - a.y * b.y - a.z * b.z)
    }

    static func normalized(_ q: Quaternion) -> Quaternion {
        let length = (q.x * q.x + q.y * q.y + q.z * q.z + q.w * q.w).squareRoot()
        return length > 0 ? (q.x / length, q.y / length, q.z / length, q.w / length) : noRotation
    }

    /// The rotation as an axis and angle, the axis y for none.
    static func axisAngle(_ q: Quaternion) -> SCNVector4 {
        let q = normalized(q)
        let s = (1 - q.w * q.w).squareRoot()
        guard s > 1e-6 else { return SCNVector4(x: 0, y: 1, z: 0, w: 0) }
        return SCNVector4(x: q.x / s, y: q.y / s, z: q.z / s, w: 2 * acosf(min(max(q.w, -1), 1)))
    }

    static func rotation(_ q: Quaternion) -> Matrix {
        let q = normalized(q)
        let x = q.x, y = q.y, z = q.z, w = q.w
        return [1 - 2 * (y * y + z * z), 2 * (x * y + z * w), 2 * (x * z - y * w), 0,
                2 * (x * y - z * w), 1 - 2 * (x * x + z * z), 2 * (y * z + x * w), 0,
                2 * (x * z + y * w), 2 * (y * z - x * w), 1 - 2 * (x * x + y * y), 0,
                0, 0, 0, 1]
    }

    /// The quaternion of a rotation matrix's upper left 3 by 3.
    static func quaternion(of m: Matrix) -> Quaternion {
        let trace = m[0] + m[5] + m[10]
        if trace > 0 {
            let s = (trace + 1).squareRoot() * 2
            return ((m[6] - m[9]) / s, (m[8] - m[2]) / s, (m[1] - m[4]) / s, s / 4)
        } else if m[0] > m[5], m[0] > m[10] {
            let s = (1 + m[0] - m[5] - m[10]).squareRoot() * 2
            return (s / 4, (m[4] + m[1]) / s, (m[8] + m[2]) / s, (m[6] - m[9]) / s)
        } else if m[5] > m[10] {
            let s = (1 + m[5] - m[0] - m[10]).squareRoot() * 2
            return ((m[4] + m[1]) / s, s / 4, (m[9] + m[6]) / s, (m[8] - m[2]) / s)
        }
        let s = (1 + m[10] - m[0] - m[5]).squareRoot() * 2
        return ((m[8] + m[2]) / s, (m[9] + m[6]) / s, s / 4, (m[1] - m[4]) / s)
    }

    /// Pitch, yaw and roll, applied roll first as SceneKit does: x, y, z.
    static func quaternion(euler e: SCNVector3) -> Quaternion {
        let x = quaternion(axis: SCNVector3(x: 1, y: 0, z: 0), angle: e.x)
        let y = quaternion(axis: SCNVector3(x: 0, y: 1, z: 0), angle: e.y)
        let z = quaternion(axis: SCNVector3(x: 0, y: 0, z: 1), angle: e.z)
        return multiply(multiply(x, y), z)
    }

    static func euler(_ q: Quaternion) -> SCNVector3 {
        let m = rotation(q)
        // m = Rx * Ry * Rz; the entry at row r, column c is m[c * 4 + r].
        let sine = min(max(m[8], -1), 1)
        let yaw = asinf(sine)
        if abs(sine) < 0.99999 {
            return SCNVector3(x: atan2f(-m[9], m[10]), y: yaw, z: atan2f(-m[4], m[0]))
        }
        return SCNVector3(x: atan2f(m[6], m[5]), y: yaw, z: 0)
    }

    // MARK: Matrices

    /// A matrix as a translation, rotation and scale; the scale is the
    /// lengths of the columns, and a reflection is not kept.
    static func decompose(_ m: Matrix) -> (position: SCNVector3, rotation: Quaternion, scale: SCNVector3) {
        func length(_ a: Int) -> Float { (m[a] * m[a] + m[a + 1] * m[a + 1] + m[a + 2] * m[a + 2]).squareRoot() }
        let sx = length(0), sy = length(4), sz = length(8)
        var r = identity
        for (column, scale) in [(0, sx), (4, sy), (8, sz)] where scale > 0 {
            for row in 0..<3 { r[column + row] = m[column + row] / scale }
        }
        return (SCNVector3(x: m[12], y: m[13], z: m[14]), normalized(quaternion(of: r)), SCNVector3(x: sx, y: sy, z: sz))
    }

    static func inverse(_ m: Matrix) -> Matrix { GLKMath.invert4(m) ?? identity }

    /// The inverse transpose of the upper left 3 by 3, for normals.
    static func normalMatrix(_ m: Matrix) -> [Float] {
        let upper: [Float] = [m[0], m[1], m[2], m[4], m[5], m[6], m[8], m[9], m[10]]
        let inverse = GLKMath.invert3(upper) ?? [1, 0, 0, 0, 1, 0, 0, 0, 1]
        return GLKMath.transpose(inverse, 3)
    }

    /// A perspective projection with a vertical field of view in degrees.
    static func perspective(fieldOfView: Float, aspect: Float, near: Float, far: Float) -> Matrix {
        let f = 1 / tanf(fieldOfView * .pi / 360)
        var m = Matrix(repeating: 0, count: 16)
        m[0] = f / aspect
        m[5] = f
        m[10] = (far + near) / (near - far)
        m[11] = -1
        m[14] = 2 * far * near / (near - far)
        return m
    }

    /// An orthographic projection whose height is twice `scale`.
    static func orthographic(scale: Float, aspect: Float, near: Float, far: Float) -> Matrix {
        let top = scale, right = scale * aspect
        var m = identity
        m[0] = 1 / right
        m[5] = 1 / top
        m[10] = -2 / (far - near)
        m[14] = -(far + near) / (far - near)
        return m
    }

    static func transform(_ m: Matrix, _ p: SCNVector3) -> SCNVector3 {
        SCNVector3(x: m[0] * p.x + m[4] * p.y + m[8] * p.z + m[12],
                   y: m[1] * p.x + m[5] * p.y + m[9] * p.z + m[13],
                   z: m[2] * p.x + m[6] * p.y + m[10] * p.z + m[14])
    }
}

// MARK: - SceneKit's C functions

// SceneKit's matrices act on row vectors: SCNMatrix4Mult(a, b) applies a first, then b.

private func scnMult(_ a: Matrix, _ b: Matrix) -> Matrix { SCNMath.multiply(b, a) }

@c(_SCNMatrix4Mult) public func SCNMatrix4Mult(_ a: SCNMatrix4, _ b: SCNMatrix4) -> SCNMatrix4 {
    SCNMath.matrix4(scnMult(SCNMath.matrix(a), SCNMath.matrix(b)))
}

@c(_SCNMatrix4Invert) public func SCNMatrix4Invert(_ m: SCNMatrix4) -> SCNMatrix4 {
    SCNMath.matrix4(GLKMath.invert4(SCNMath.matrix(m)) ?? SCNMath.matrix(m))
}

@c(_SCNMatrix4MakeTranslation) public func SCNMatrix4MakeTranslation(_ x: Float, _ y: Float, _ z: Float) -> SCNMatrix4 {
    SCNMath.matrix4(SCNMath.translation(x, y, z))
}

@c(_SCNMatrix4MakeScale) public func SCNMatrix4MakeScale(_ x: Float, _ y: Float, _ z: Float) -> SCNMatrix4 {
    SCNMath.matrix4(SCNMath.scaling(x, y, z))
}

@c(_SCNMatrix4MakeRotation) public func SCNMatrix4MakeRotation(_ angle: Float, _ x: Float, _ y: Float, _ z: Float) -> SCNMatrix4 {
    SCNMath.matrix4(SCNMath.rotation(SCNMath.quaternion(axis: SCNVector3(x: x, y: y, z: z), angle: angle)))
}

@c(_SCNMatrix4Translate) public func SCNMatrix4Translate(_ m: SCNMatrix4, _ x: Float, _ y: Float, _ z: Float) -> SCNMatrix4 {
    SCNMath.matrix4(scnMult(SCNMath.translation(x, y, z), SCNMath.matrix(m)))
}

@c(_SCNMatrix4Scale) public func SCNMatrix4Scale(_ m: SCNMatrix4, _ x: Float, _ y: Float, _ z: Float) -> SCNMatrix4 {
    SCNMath.matrix4(scnMult(SCNMath.scaling(x, y, z), SCNMath.matrix(m)))
}

@c(_SCNMatrix4Rotate) public func SCNMatrix4Rotate(_ m: SCNMatrix4, _ angle: Float, _ x: Float, _ y: Float, _ z: Float) -> SCNMatrix4 {
    let r = SCNMath.rotation(SCNMath.quaternion(axis: SCNVector3(x: x, y: y, z: z), angle: angle))
    return SCNMath.matrix4(scnMult(r, SCNMath.matrix(m)))
}

@c(_SCNMatrix4EqualToMatrix4) public func SCNMatrix4EqualToMatrix4(_ a: SCNMatrix4, _ b: SCNMatrix4) -> Bool { SCNMath.matrix(a) == SCNMath.matrix(b) }
@c(_SCNMatrix4IsIdentity) public func SCNMatrix4IsIdentity(_ m: SCNMatrix4) -> Bool { SCNMath.matrix(m) == SCNMath.identity }
