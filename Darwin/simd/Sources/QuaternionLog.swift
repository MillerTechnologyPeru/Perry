import Darwin

// The quaternion logarithm, which simd's C headers leave to the overlay:
// for q = s + v, log q = log|q| + (v / |v|) * atan2(|v|, s).

public func log(_ q: simd_quatf) -> simd_quatf {
    let v = q.imag
    let vectorLength = simd_length(v)
    let angle = Darwin.atan2(vectorLength, q.real)
    let scale: Float = vectorLength > 0 ? angle / vectorLength : 0
    return simd_quatf(real: Darwin.log(simd_length(q.vector)), imag: v * scale)
}

public func log(_ q: simd_quatd) -> simd_quatd {
    let v = q.imag
    let vectorLength = simd_length(v)
    let angle = Darwin.atan2(vectorLength, q.real)
    let scale: Double = vectorLength > 0 ? angle / vectorLength : 0
    return simd_quatd(real: Darwin.log(simd_length(q.vector)), imag: v * scale)
}
