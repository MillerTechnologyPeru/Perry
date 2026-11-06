import CPerryGeometry
import Glibc
import PerryObjCInterop

// GLKit's math that is not inline in its headers: inverses, projection,
// quaternion angles, axes and interpolation, and the string forms. Matrices
// are column-major: m[column * size + row].

enum GLKMath {
    static let identity4 = GLKMatrix4(m: (1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1))
    static let identity3 = GLKMatrix3(m: (1, 0, 0, 0, 1, 0, 0, 0, 1))

    static func array(_ m: GLKMatrix4) -> [Float] { withUnsafeBytes(of: m.m) { Array($0.bindMemory(to: Float.self)) } }
    static func array(_ m: GLKMatrix3) -> [Float] { withUnsafeBytes(of: m.m) { Array($0.bindMemory(to: Float.self)) } }

    static func matrix4(_ a: [Float]) -> GLKMatrix4 {
        var m = GLKMatrix4()
        withUnsafeMutableBytes(of: &m.m) { $0.bindMemory(to: Float.self).update(from: a) }
        return m
    }

    static func matrix3(_ a: [Float]) -> GLKMatrix3 {
        var m = GLKMatrix3()
        withUnsafeMutableBytes(of: &m.m) { $0.bindMemory(to: Float.self).update(from: a) }
        return m
    }

    /// The inverse of a 4 by 4 matrix by cofactors; nil when singular.
    static func invert4(_ m: [Float]) -> [Float]? {
        var inv = [Float](repeating: 0, count: 16)
        inv[0] = m[5] * m[10] * m[15] - m[5] * m[11] * m[14] - m[9] * m[6] * m[15] + m[9] * m[7] * m[14] + m[13] * m[6] * m[11] - m[13] * m[7] * m[10]
        inv[4] = -m[4] * m[10] * m[15] + m[4] * m[11] * m[14] + m[8] * m[6] * m[15] - m[8] * m[7] * m[14] - m[12] * m[6] * m[11] + m[12] * m[7] * m[10]
        inv[8] = m[4] * m[9] * m[15] - m[4] * m[11] * m[13] - m[8] * m[5] * m[15] + m[8] * m[7] * m[13] + m[12] * m[5] * m[11] - m[12] * m[7] * m[9]
        inv[12] = -m[4] * m[9] * m[14] + m[4] * m[10] * m[13] + m[8] * m[5] * m[14] - m[8] * m[6] * m[13] - m[12] * m[5] * m[10] + m[12] * m[6] * m[9]
        inv[1] = -m[1] * m[10] * m[15] + m[1] * m[11] * m[14] + m[9] * m[2] * m[15] - m[9] * m[3] * m[14] - m[13] * m[2] * m[11] + m[13] * m[3] * m[10]
        inv[5] = m[0] * m[10] * m[15] - m[0] * m[11] * m[14] - m[8] * m[2] * m[15] + m[8] * m[3] * m[14] + m[12] * m[2] * m[11] - m[12] * m[3] * m[10]
        inv[9] = -m[0] * m[9] * m[15] + m[0] * m[11] * m[13] + m[8] * m[1] * m[15] - m[8] * m[3] * m[13] - m[12] * m[1] * m[11] + m[12] * m[3] * m[9]
        inv[13] = m[0] * m[9] * m[14] - m[0] * m[10] * m[13] - m[8] * m[1] * m[14] + m[8] * m[2] * m[13] + m[12] * m[1] * m[10] - m[12] * m[2] * m[9]
        inv[2] = m[1] * m[6] * m[15] - m[1] * m[7] * m[14] - m[5] * m[2] * m[15] + m[5] * m[3] * m[14] + m[13] * m[2] * m[7] - m[13] * m[3] * m[6]
        inv[6] = -m[0] * m[6] * m[15] + m[0] * m[7] * m[14] + m[4] * m[2] * m[15] - m[4] * m[3] * m[14] - m[12] * m[2] * m[7] + m[12] * m[3] * m[6]
        inv[10] = m[0] * m[5] * m[15] - m[0] * m[7] * m[13] - m[4] * m[1] * m[15] + m[4] * m[3] * m[13] + m[12] * m[1] * m[7] - m[12] * m[3] * m[5]
        inv[14] = -m[0] * m[5] * m[14] + m[0] * m[6] * m[13] + m[4] * m[1] * m[14] - m[4] * m[2] * m[13] - m[12] * m[1] * m[6] + m[12] * m[2] * m[5]
        inv[3] = -m[1] * m[6] * m[11] + m[1] * m[7] * m[10] + m[5] * m[2] * m[11] - m[5] * m[3] * m[10] - m[9] * m[2] * m[7] + m[9] * m[3] * m[6]
        inv[7] = m[0] * m[6] * m[11] - m[0] * m[7] * m[10] - m[4] * m[2] * m[11] + m[4] * m[3] * m[10] + m[8] * m[2] * m[7] - m[8] * m[3] * m[6]
        inv[11] = -m[0] * m[5] * m[11] + m[0] * m[7] * m[9] + m[4] * m[1] * m[11] - m[4] * m[3] * m[9] - m[8] * m[1] * m[7] + m[8] * m[3] * m[5]
        inv[15] = m[0] * m[5] * m[10] - m[0] * m[6] * m[9] - m[4] * m[1] * m[10] + m[4] * m[2] * m[9] + m[8] * m[1] * m[6] - m[8] * m[2] * m[5]
        let determinant = m[0] * inv[0] + m[1] * inv[4] + m[2] * inv[8] + m[3] * inv[12]
        guard determinant != 0 else { return nil }
        return inv.map { $0 / determinant }
    }

    static func invert3(_ m: [Float]) -> [Float]? {
        let a = m[0], b = m[3], c = m[6], d = m[1], e = m[4], f = m[7], g = m[2], h = m[5], i = m[8]
        let determinant = a * (e * i - f * h) - b * (d * i - f * g) + c * (d * h - e * g)
        guard determinant != 0 else { return nil }
        // Row-major cofactors, written back column-major.
        let rows: [Float] = [e * i - f * h, c * h - b * i, b * f - c * e,
                             f * g - d * i, a * i - c * g, c * d - a * f,
                             d * h - e * g, b * g - a * h, a * e - b * d]
        return [rows[0], rows[3], rows[6], rows[1], rows[4], rows[7], rows[2], rows[5], rows[8]].map { $0 / determinant }
    }

    static func transpose(_ m: [Float], _ n: Int) -> [Float] {
        (0..<n * n).map { index in m[(index % n) * n + index / n] }
    }

    /// A number as GLKit's strings print it: %g.
    static func format(_ value: Float) -> String {
        var buffer = [CChar](repeating: 0, count: 32)
        _ = withVaList([Double(value)]) { vsnprintf(&buffer, buffer.count, "%g", $0) }
        return String(cString: buffer)
    }

    static func describe(_ values: [Float]) -> String { "{" + values.map(format).joined(separator: ", ") + "}" }

    static func describe(columns values: [Float], _ n: Int) -> String {
        "{" + (0..<n).map { column in describe(Array(values[column * n..<(column + 1) * n])) }.joined(separator: ", ") + "}"
    }
}

@c(_GLKMatrix4Invert)
public func GLKMatrix4Invert(_ matrix: GLKMatrix4, _ isInvertible: UnsafeMutablePointer<Bool>?) -> GLKMatrix4 {
    let inverse = GLKMath.invert4(GLKMath.array(matrix))
    isInvertible?.pointee = inverse != nil
    return inverse.map(GLKMath.matrix4) ?? GLKMath.identity4
}

@c(_GLKMatrix4InvertAndTranspose)
public func GLKMatrix4InvertAndTranspose(_ matrix: GLKMatrix4, _ isInvertible: UnsafeMutablePointer<Bool>?) -> GLKMatrix4 {
    let inverse = GLKMath.invert4(GLKMath.array(matrix))
    isInvertible?.pointee = inverse != nil
    return inverse.map { GLKMath.matrix4(GLKMath.transpose($0, 4)) } ?? GLKMath.identity4
}

@c(_GLKMatrix3Invert)
public func GLKMatrix3Invert(_ matrix: GLKMatrix3, _ isInvertible: UnsafeMutablePointer<Bool>?) -> GLKMatrix3 {
    let inverse = GLKMath.invert3(GLKMath.array(matrix))
    isInvertible?.pointee = inverse != nil
    return inverse.map(GLKMath.matrix3) ?? GLKMath.identity3
}

@c(_GLKMatrix3InvertAndTranspose)
public func GLKMatrix3InvertAndTranspose(_ matrix: GLKMatrix3, _ isInvertible: UnsafeMutablePointer<Bool>?) -> GLKMatrix3 {
    let inverse = GLKMath.invert3(GLKMath.array(matrix))
    isInvertible?.pointee = inverse != nil
    return inverse.map { GLKMath.matrix3(GLKMath.transpose($0, 3)) } ?? GLKMath.identity3
}

/// Object coordinates to window coordinates, as gluProject.
@c(_GLKMathProject)
public func GLKMathProject(_ object: GLKVector3, _ model: GLKMatrix4, _ projection: GLKMatrix4,
                           _ viewport: UnsafeMutablePointer<Int32>?) -> GLKVector3 {
    let mv = GLKMath.array(model), p = GLKMath.array(projection)
    let o = [object.v.0, object.v.1, object.v.2, 1]
    func multiply(_ m: [Float], _ v: [Float]) -> [Float] {
        (0..<4).map { row in (0..<4).reduce(Float(0)) { $0 + m[$1 * 4 + row] * v[$1] } }
    }
    let clip = multiply(p, multiply(mv, o))
    guard clip[3] != 0, let viewport else { return GLKVector3(v: (0, 0, 0)) }
    let ndc = clip.map { $0 / clip[3] }
    let x = Float(viewport[0]) + Float(viewport[2]) * (ndc[0] + 1) / 2
    let y = Float(viewport[1]) + Float(viewport[3]) * (ndc[1] + 1) / 2
    return GLKVector3(v: (x, y, (ndc[2] + 1) / 2))
}

/// Window coordinates back to object coordinates, as gluUnProject.
@c(_GLKMathUnproject)
public func GLKMathUnproject(_ window: GLKVector3, _ model: GLKMatrix4, _ projection: GLKMatrix4,
                             _ viewport: UnsafeMutablePointer<Int32>?, _ success: UnsafeMutablePointer<Bool>?) -> GLKVector3 {
    let mv = GLKMath.array(model), p = GLKMath.array(projection)
    let product = (0..<16).map { index -> Float in
        let column = index / 4, row = index % 4
        return (0..<4).reduce(Float(0)) { $0 + p[$1 * 4 + row] * mv[column * 4 + $1] }
    }
    guard let viewport, let inverse = GLKMath.invert4(product) else {
        success?.pointee = false
        return GLKVector3(v: (0, 0, 0))
    }
    let v: [Float] = [(window.v.0 - Float(viewport[0])) / Float(viewport[2]) * 2 - 1,
                      (window.v.1 - Float(viewport[1])) / Float(viewport[3]) * 2 - 1, window.v.2 * 2 - 1, 1]
    let out = (0..<4).map { row in (0..<4).reduce(Float(0)) { $0 + inverse[$1 * 4 + row] * v[$1] } }
    guard out[3] != 0 else {
        success?.pointee = false
        return GLKVector3(v: (0, 0, 0))
    }
    success?.pointee = true
    return GLKVector3(v: (out[0] / out[3], out[1] / out[3], out[2] / out[3]))
}

@DarwinC("_GLKQuaternionAngle")
public func GLKQuaternionAngle(_ quaternion: GLKQuaternion) -> Float {
    let q = quaternion.q
    let length = (q.0 * q.0 + q.1 * q.1 + q.2 * q.2 + q.3 * q.3).squareRoot()
    let w = length > 0 ? q.3 / length : 1
    return 2 * acosf(min(max(w, -1), 1))
}

@c(_GLKQuaternionAxis)
public func GLKQuaternionAxis(_ quaternion: GLKQuaternion) -> GLKVector3 {
    let q = quaternion.q
    let scale = (q.0 * q.0 + q.1 * q.1 + q.2 * q.2).squareRoot()
    guard scale > 0 else { return GLKVector3(v: (0, 0, 0)) }
    return GLKVector3(v: (q.0 / scale, q.1 / scale, q.2 / scale))
}

@DarwinC("_GLKQuaternionSlerp")
public func GLKQuaternionSlerp(_ start: GLKQuaternion, _ end: GLKQuaternion, _ t: Float) -> GLKQuaternion {
    let a = [start.q.0, start.q.1, start.q.2, start.q.3]
    var b = [end.q.0, end.q.1, end.q.2, end.q.3]
    var dot = zip(a, b).reduce(Float(0)) { $0 + $1.0 * $1.1 }
    if dot < 0 {
        b = b.map { -$0 }
        dot = -dot
    }
    let (wa, wb): (Float, Float)
    if dot > 0.9995 {
        (wa, wb) = (1 - t, t)
    } else {
        let theta = acosf(dot), sine = sinf(theta)
        (wa, wb) = (sinf((1 - t) * theta) / sine, sinf(t * theta) / sine)
    }
    let r = zip(a, b).map { wa * $0.0 + wb * $0.1 }
    return GLKQuaternion(q: (r[0], r[1], r[2], r[3]))
}

/// The rotation of an orthonormal 3 by 3 matrix as a quaternion.
@c(_GLKQuaternionMakeWithMatrix3)
public func GLKQuaternionMakeWithMatrix3(_ matrix: GLKMatrix3) -> GLKQuaternion {
    let m = GLKMath.array(matrix)
    return Quaternions.make(m00: m[0], m01: m[3], m02: m[6], m10: m[1], m11: m[4], m12: m[7], m20: m[2], m21: m[5], m22: m[8])
}

@c(_GLKQuaternionMakeWithMatrix4)
public func GLKQuaternionMakeWithMatrix4(_ matrix: GLKMatrix4) -> GLKQuaternion {
    let m = GLKMath.array(matrix)
    return Quaternions.make(m00: m[0], m01: m[4], m02: m[8], m10: m[1], m11: m[5], m12: m[9], m20: m[2], m21: m[6], m22: m[10])
}

enum Quaternions {
    /// From a rotation matrix by rows, as Shepperd's method.
    static func make(m00: Float, m01: Float, m02: Float, m10: Float, m11: Float, m12: Float, m20: Float, m21: Float, m22: Float)
        -> GLKQuaternion {
        let trace = m00 + m11 + m22
        if trace > 0 {
            let s = (trace + 1).squareRoot() * 2
            return GLKQuaternion(q: ((m21 - m12) / s, (m02 - m20) / s, (m10 - m01) / s, s / 4))
        } else if m00 > m11, m00 > m22 {
            let s = (1 + m00 - m11 - m22).squareRoot() * 2
            return GLKQuaternion(q: (s / 4, (m01 + m10) / s, (m02 + m20) / s, (m21 - m12) / s))
        } else if m11 > m22 {
            let s = (1 + m11 - m00 - m22).squareRoot() * 2
            return GLKQuaternion(q: ((m01 + m10) / s, s / 4, (m12 + m21) / s, (m02 - m20) / s))
        } else {
            let s = (1 + m22 - m00 - m11).squareRoot() * 2
            return GLKQuaternion(q: ((m02 + m20) / s, (m12 + m21) / s, s / 4, (m10 - m01) / s))
        }
    }

    static func rotate(_ q: GLKQuaternion, _ v: (Float, Float, Float)) -> (Float, Float, Float) {
        let (x, y, z, w) = q.q
        // v + 2w(q × v) + 2 q × (q × v)
        let t = (2 * (y * v.2 - z * v.1), 2 * (z * v.0 - x * v.2), 2 * (x * v.1 - y * v.0))
        return (v.0 + w * t.0 + (y * t.2 - z * t.1), v.1 + w * t.1 + (z * t.0 - x * t.2), v.2 + w * t.2 + (x * t.1 - y * t.0))
    }
}

@c(_GLKQuaternionRotateVector3Array)
public func GLKQuaternionRotateVector3Array(_ quaternion: GLKQuaternion, _ vectors: UnsafeMutablePointer<GLKVector3>?, _ count: Int) {
    guard let vectors else { return }
    for index in 0..<count {
        let v = vectors[index].v
        let r = Quaternions.rotate(quaternion, (v.0, v.1, v.2))
        vectors[index] = GLKVector3(v: (r.0, r.1, r.2))
    }
}

@c(_GLKQuaternionRotateVector4Array)
public func GLKQuaternionRotateVector4Array(_ quaternion: GLKQuaternion, _ vectors: UnsafeMutablePointer<GLKVector4>?, _ count: Int) {
    guard let vectors else { return }
    for index in 0..<count {
        let v = vectors[index].v
        let r = Quaternions.rotate(quaternion, (v.0, v.1, v.2))
        vectors[index] = GLKVector4(v: (r.0, r.1, r.2, v.3))
    }
}

@c(_NSStringFromGLKVector2)
public func NSStringFromGLKVector2(_ vector: GLKVector2) -> UnsafeMutableRawPointer? {
    GLKMath.describe([vector.v.0, vector.v.1]).objCReturnValue()
}

@c(_NSStringFromGLKVector3)
public func NSStringFromGLKVector3(_ vector: GLKVector3) -> UnsafeMutableRawPointer? {
    GLKMath.describe([vector.v.0, vector.v.1, vector.v.2]).objCReturnValue()
}

@c(_NSStringFromGLKVector4)
public func NSStringFromGLKVector4(_ vector: GLKVector4) -> UnsafeMutableRawPointer? {
    GLKMath.describe([vector.v.0, vector.v.1, vector.v.2, vector.v.3]).objCReturnValue()
}

@c(_NSStringFromGLKQuaternion)
public func NSStringFromGLKQuaternion(_ quaternion: GLKQuaternion) -> UnsafeMutableRawPointer? {
    "{\(GLKMath.describe([quaternion.q.0, quaternion.q.1, quaternion.q.2])), \(GLKMath.format(quaternion.q.3))}".objCReturnValue()
}

@c(_NSStringFromGLKMatrix2)
public func NSStringFromGLKMatrix2(_ matrix: GLKMatrix2) -> UnsafeMutableRawPointer? {
    let m = matrix.m
    return GLKMath.describe(columns: [m.0, m.1, m.2, m.3], 2).objCReturnValue()
}

@c(_NSStringFromGLKMatrix3)
public func NSStringFromGLKMatrix3(_ matrix: GLKMatrix3) -> UnsafeMutableRawPointer? {
    GLKMath.describe(columns: GLKMath.array(matrix), 3).objCReturnValue()
}

@c(_NSStringFromGLKMatrix4)
public func NSStringFromGLKMatrix4(_ matrix: GLKMatrix4) -> UnsafeMutableRawPointer? {
    GLKMath.describe(columns: GLKMath.array(matrix), 4).objCReturnValue()
}
