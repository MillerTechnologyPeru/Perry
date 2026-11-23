import Foundation
import simd

// ModelIO's Swift API: the values of matrix arrays and animated values as
// Swift arrays, over the Objective-C methods that take a buffer and count,
// which the headers refine for Swift.

/// An array of up to `count` values that `fill` writes into a buffer,
/// returning how many it wrote.
private func filled<T>(_ count: Int, _ fill: (UnsafeMutablePointer<T>, Int) -> Int) -> [T] {
    guard count > 0 else { return [] }
    return [T](unsafeUninitializedCapacity: count) { buffer, initialized in
        initialized = min(fill(buffer.baseAddress!, count), count)
    }
}

private func checkCounts(_ values: Int, _ times: Int) {
    precondition(values == times, "the number of values must match the number of times")
}

@available(macOS 10.13, *)
extension MDLMatrix4x4Array {
    @nonobjc public var float4x4Array: [float4x4] {
        get { filled(elementCount) { __getFloat4x4Array($0, maxCount: $1) } }
        set(array) { __setFloat4x4(array, count: array.count) }
    }

    @nonobjc public var double4x4Array: [double4x4] {
        get { filled(elementCount) { __getDouble4x4Array($0, maxCount: $1) } }
        set(array) { __setDouble4x4(array, count: array.count) }
    }
}

@available(macOS 10.13, *)
extension MDLAnimatedValue {
    @nonobjc public var times: [TimeInterval] {
        filled(timeSampleCount) { __getTimes($0, maxCount: $1) }
    }
}

@available(macOS 10.13, *)
extension MDLAnimatedScalarArray {
    @nonobjc public func set(floatArray array: [Float], atTime time: TimeInterval) {
        __setFloat(array, count: array.count, atTime: time)
    }

    @nonobjc public func set(doubleArray array: [Double], atTime time: TimeInterval) {
        __setDouble(array, count: array.count, atTime: time)
    }

    @nonobjc public func floatArray(atTime time: TimeInterval) -> [Float] {
        filled(elementCount) { __getFloat($0, maxCount: $1, atTime: time) }
    }

    @nonobjc public func doubleArray(atTime time: TimeInterval) -> [Double] {
        filled(elementCount) { __getDouble($0, maxCount: $1, atTime: time) }
    }

    @nonobjc public func reset(floatArray array: [Float], atTimes times: [TimeInterval]) {
        __reset(with: array, count: array.count, atTimes: times, count: times.count)
    }

    @nonobjc public func reset(doubleArray array: [Double], atTimes times: [TimeInterval]) {
        __reset(with: array, count: array.count, atTimes: times, count: times.count)
    }

    @nonobjc public var floatArray: [Float] {
        filled(elementCount * timeSampleCount) { __getFloat($0, maxCount: $1) }
    }

    @nonobjc public var doubleArray: [Double] {
        filled(elementCount * timeSampleCount) { __getDouble($0, maxCount: $1) }
    }
}

@available(macOS 10.13, *)
extension MDLAnimatedVector3Array {
    @nonobjc public func set(float3Array array: [SIMD3<Float>], atTime time: TimeInterval) {
        __setFloat3(array, count: array.count, atTime: time)
    }

    @nonobjc public func set(double3Array array: [SIMD3<Double>], atTime time: TimeInterval) {
        __setDouble3(array, count: array.count, atTime: time)
    }

    @nonobjc public func float3Array(atTime time: TimeInterval) -> [SIMD3<Float>] {
        filled(elementCount) { __getFloat3Array($0, maxCount: $1, atTime: time) }
    }

    @nonobjc public func double3Array(atTime time: TimeInterval) -> [SIMD3<Double>] {
        filled(elementCount) { __getDouble3Array($0, maxCount: $1, atTime: time) }
    }

    @nonobjc public func reset(float3Array array: [SIMD3<Float>], atTimes times: [TimeInterval]) {
        __reset(withFloat3Array: array, count: array.count, atTimes: times, count: times.count)
    }

    @nonobjc public func reset(double3Array array: [SIMD3<Double>], atTimes times: [TimeInterval]) {
        __reset(withDouble3Array: array, count: array.count, atTimes: times, count: times.count)
    }

    @nonobjc public var float3Array: [SIMD3<Float>] {
        filled(elementCount * timeSampleCount) { __getFloat3Array($0, maxCount: $1) }
    }

    @nonobjc public var double3Array: [SIMD3<Double>] {
        filled(elementCount * timeSampleCount) { __getDouble3Array($0, maxCount: $1) }
    }
}

@available(macOS 10.13, *)
extension MDLAnimatedQuaternionArray {
    @nonobjc public func set(floatQuaternionArray array: [simd_quatf], atTime time: TimeInterval) {
        __setFloat(array, count: array.count, atTime: time)
    }

    @nonobjc public func set(doubleQuaternionArray array: [simd_quatd], atTime time: TimeInterval) {
        __setDouble(array, count: array.count, atTime: time)
    }

    @nonobjc public func floatQuaternionArray(atTime time: TimeInterval) -> [simd_quatf] {
        filled(elementCount) { __getFloat($0, maxCount: $1, atTime: time) }
    }

    @nonobjc public func doubleQuaternionArray(atTime time: TimeInterval) -> [simd_quatd] {
        filled(elementCount) { __getDouble($0, maxCount: $1, atTime: time) }
    }

    @nonobjc public func reset(floatQuaternionArray array: [simd_quatf], atTimes times: [TimeInterval]) {
        __reset(withFloat: array, count: array.count, atTimes: times, count: times.count)
    }

    @nonobjc public func reset(doubleQuaternionArray array: [simd_quatd], atTimes times: [TimeInterval]) {
        __reset(withDouble: array, count: array.count, atTimes: times, count: times.count)
    }

    @nonobjc public var floatQuaternionArray: [simd_quatf] {
        filled(elementCount * timeSampleCount) { __getFloat($0, maxCount: $1) }
    }

    @nonobjc public var doubleQuaternionArray: [simd_quatd] {
        filled(elementCount * timeSampleCount) { __getDouble($0, maxCount: $1) }
    }
}

@available(macOS 10.13, *)
extension MDLAnimatedScalar {
    @nonobjc public func reset(floatArray array: [Float], atTimes times: [TimeInterval]) {
        checkCounts(array.count, times.count)
        __reset(withFloatArray: array, atTimes: times, count: times.count)
    }

    @nonobjc public func reset(doubleArray array: [Double], atTimes times: [TimeInterval]) {
        checkCounts(array.count, times.count)
        __reset(withDoubleArray: array, atTimes: times, count: times.count)
    }

    @nonobjc public var floatArray: [Float] {
        filled(timeSampleCount) { __getFloatArray($0, maxCount: $1) }
    }

    @nonobjc public var doubleArray: [Double] {
        filled(timeSampleCount) { __getDoubleArray($0, maxCount: $1) }
    }
}

@available(macOS 10.13, *)
extension MDLAnimatedVector2 {
    @nonobjc public func reset(float2Array array: [SIMD2<Float>], atTimes times: [TimeInterval]) {
        checkCounts(array.count, times.count)
        __reset(withFloat2Array: array, atTimes: times, count: times.count)
    }

    @nonobjc public func reset(double2Array array: [SIMD2<Double>], atTimes times: [TimeInterval]) {
        checkCounts(array.count, times.count)
        __reset(withDouble2Array: array, atTimes: times, count: times.count)
    }

    @nonobjc public var float2Array: [SIMD2<Float>] {
        filled(timeSampleCount) { __getFloat2Array($0, maxCount: $1) }
    }

    @nonobjc public var double2Array: [SIMD2<Double>] {
        filled(timeSampleCount) { __getDouble2Array($0, maxCount: $1) }
    }
}

@available(macOS 10.13, *)
extension MDLAnimatedVector3 {
    @nonobjc public func reset(float3Array array: [SIMD3<Float>], atTimes times: [TimeInterval]) {
        checkCounts(array.count, times.count)
        __reset(withFloat3Array: array, atTimes: times, count: times.count)
    }

    @nonobjc public func reset(double3Array array: [SIMD3<Double>], atTimes times: [TimeInterval]) {
        checkCounts(array.count, times.count)
        __reset(withDouble3Array: array, atTimes: times, count: times.count)
    }

    @nonobjc public var float3Array: [SIMD3<Float>] {
        filled(timeSampleCount) { __getFloat3Array($0, maxCount: $1) }
    }

    @nonobjc public var double3Array: [SIMD3<Double>] {
        filled(timeSampleCount) { __getDouble3Array($0, maxCount: $1) }
    }
}

@available(macOS 10.13, *)
extension MDLAnimatedVector4 {
    @nonobjc public func reset(float4Array array: [SIMD4<Float>], atTimes times: [TimeInterval]) {
        checkCounts(array.count, times.count)
        __reset(withFloat4Array: array, atTimes: times, count: times.count)
    }

    @nonobjc public func reset(double4Array array: [SIMD4<Double>], atTimes times: [TimeInterval]) {
        checkCounts(array.count, times.count)
        __reset(withDouble4Array: array, atTimes: times, count: times.count)
    }

    @nonobjc public var float4Array: [SIMD4<Float>] {
        filled(timeSampleCount) { __getFloat4Array($0, maxCount: $1) }
    }

    @nonobjc public var double4Array: [SIMD4<Double>] {
        filled(timeSampleCount) { __getDouble4Array($0, maxCount: $1) }
    }
}

@available(macOS 10.13, *)
extension MDLAnimatedMatrix4x4 {
    @nonobjc public func reset(float4x4Array array: [float4x4], atTimes times: [TimeInterval]) {
        checkCounts(array.count, times.count)
        __reset(withFloat4x4Array: array, atTimes: times, count: times.count)
    }

    @nonobjc public func reset(double4Array array: [double4x4], atTimes times: [TimeInterval]) {
        checkCounts(array.count, times.count)
        __reset(withDouble4x4Array: array, atTimes: times, count: times.count)
    }

    @nonobjc public var float4x4Array: [float4x4] {
        filled(timeSampleCount) { __getFloat4x4Array($0, maxCount: $1) }
    }

    @nonobjc public var double4x4Array: [double4x4] {
        filled(timeSampleCount) { __getDouble4x4Array($0, maxCount: $1) }
    }
}

@available(macOS 10.15, *)
extension MDLAnimatedQuaternion {
    @nonobjc public func reset(floatQuaternionArray array: [simd_quatf], atTimes times: [TimeInterval]) {
        checkCounts(array.count, times.count)
        __reset(withFloatArray: array, atTimes: times, count: times.count)
    }

    @nonobjc public func reset(doubleQuaternionArray array: [simd_quatd], atTimes times: [TimeInterval]) {
        checkCounts(array.count, times.count)
        __reset(withDoubleArray: array, atTimes: times, count: times.count)
    }

    @nonobjc public var floatQuaternionArray: [simd_quatf] {
        filled(timeSampleCount) { __getFloatArray($0, maxCount: $1) }
    }

    @nonobjc public var doubleQuaternionArray: [simd_quatd] {
        filled(timeSampleCount) { __getDoubleArray($0, maxCount: $1) }
    }
}
