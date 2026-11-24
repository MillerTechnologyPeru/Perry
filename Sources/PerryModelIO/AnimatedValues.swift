import CPerryModelIO
import Glibc
import PerryObjCInterop

// Animated values: samples of a scalar, vector, quaternion or matrix (or an
// array of them) at times, kept as doubles and interpolated between, and
// MDLMatrix4x4Array. Their methods read and write C arrays of floats or
// doubles laid out as simd lays them out: a vector_float3 takes 16 bytes,
// a vector_double3 32.

/// How a kind of value lies in memory: its components and the bytes from
/// one to the next, as floats and as doubles.
struct ValueShape {
    let components: Int
    let floatStride: Int
    let doubleStride: Int

    static let scalar = ValueShape(components: 1, floatStride: 4, doubleStride: 8)
    static let vector2 = ValueShape(components: 2, floatStride: 8, doubleStride: 16)
    static let vector3 = ValueShape(components: 3, floatStride: 16, doubleStride: 32)
    static let vector4 = ValueShape(components: 4, floatStride: 16, doubleStride: 32)
    static let matrix = ValueShape(components: 16, floatStride: 64, doubleStride: 128)

    /// `count` values from memory, as doubles.
    func read(_ pointer: UnsafeRawPointer?, count: Int, double: Bool) -> [Double] {
        guard let pointer, count > 0 else { return [] }
        var result: [Double] = []
        result.reserveCapacity(count * components)
        let stride = double ? doubleStride : floatStride
        // A matrix is four columns of four.
        let componentStride = double ? 8 : 4
        for i in 0..<count {
            for c in 0..<components {
                let at = i * stride + c * componentStride
                result.append(double ? pointer.loadUnaligned(fromByteOffset: at, as: Double.self)
                                     : Double(pointer.loadUnaligned(fromByteOffset: at, as: Float.self)))
            }
        }
        return result
    }

    /// Writes values to memory, at most `maxCount`; returns how many.
    @discardableResult
    func write(_ values: [Double], to pointer: UnsafeMutableRawPointer?, maxCount: Int, double: Bool) -> Int {
        guard let pointer else { return 0 }
        let count = min(values.count / components, maxCount)
        let stride = double ? doubleStride : floatStride, componentStride = double ? 8 : 4
        for i in 0..<count {
            for c in 0..<components {
                let value = values[i * components + c], at = i * stride + c * componentStride
                if double { pointer.storeBytes(of: value, toByteOffset: at, as: Double.self) } else {
                    pointer.storeBytes(of: Float(value), toByteOffset: at, as: Float.self)
                }
            }
        }
        return count
    }
}

/// MDLDataPrecision.
enum Precision {
    static let undefined: UInt = 0, float: UInt = 1, double: UInt = 2
}

@ObjCClass("MDLAnimatedValue")
open class MDLAnimatedValue: NSObject {
    /// Samples, in time order: each the flattened values at its time.
    var samples: [(time: Double, values: [Double])] = []
    var interpolationValue: UInt = 1
    var precisionValue = Precision.undefined
    /// The doubles one sample has.
    var width: Int { 1 }

    @ObjCMethod("init") public required override init() { super.init() }

    @ObjCMethod("isAnimated") func isAnimated() -> Bool { samples.count > 1 }
    @ObjCMethod("precision") func precision() -> UInt { precisionValue }
    @ObjCMethod("timeSampleCount") func timeSampleCount() -> UInt { UInt(samples.count) }
    @ObjCMethod("minimumTime") func minimumTime() -> Double { samples.first?.time ?? 0 }
    @ObjCMethod("maximumTime") func maximumTime() -> Double { samples.last?.time ?? 0 }
    @ObjCMethod("interpolation") func interpolation() -> UInt { interpolationValue }
    @ObjCMethod("setInterpolation:") func setInterpolation(_ v: UInt) { interpolationValue = v }
    @ObjCMethod("keyTimes") func keyTimes() -> NSObject { NSArray.of(samples.map { NSNumber.make(double: $0.time) }) }
    @ObjCMethod("clear") func clear() { samples = [] }

    @ObjCMethod("getTimes:maxCount:") func getTimes(_ times: UnsafeMutablePointer<Double>?, maxCount: UInt) -> UInt {
        guard let times else { return 0 }
        let count = min(samples.count, Int(maxCount))
        for i in 0..<count { times[i] = samples[i].time }
        return UInt(count)
    }

    @ObjCMethod("copyWithZone:") func copy(zone: UnsafeMutableRawPointer?) -> MDLAnimatedValue {
        let copy = type(of: self).init()
        copy.samples = samples
        copy.interpolationValue = interpolationValue
        copy.precisionValue = precisionValue
        copyExtra(to: copy)
        return copy
    }

    func copyExtra(to copy: MDLAnimatedValue) {}

    /// Sets the values at `time`, replacing a sample there.
    func set(_ values: [Double], at time: Double, double: Bool) {
        precisionValue = double ? Precision.double : Precision.float
        if let index = samples.firstIndex(where: { $0.time == time }) {
            samples[index].values = values
        } else {
            let index = samples.firstIndex { $0.time > time } ?? samples.count
            samples.insert((time, values), at: index)
        }
    }

    /// Replaces every sample: `values` holds one sample per time.
    func reset(_ values: [Double], times: [Double], double: Bool) {
        precisionValue = double ? Precision.double : Precision.float
        samples = []
        let width = width
        for (i, time) in times.enumerated() where (i + 1) * width <= values.count {
            set(Array(values[(i * width)..<((i + 1) * width)]), at: time, double: double)
        }
    }

    /// The values at `time`: the nearest sample's beyond the ends, between
    /// samples the earlier one's or a blend, as the interpolation says.
    func values(at time: Double) -> [Double] {
        guard let first = samples.first, let last = samples.last else { return [Double](repeating: 0, count: width) }
        if time <= first.time { return first.values }
        if time >= last.time { return last.values }
        let next = samples.firstIndex { $0.time > time }!
        let (a, b) = (samples[next - 1], samples[next])
        guard interpolationValue == 1 else { return a.values }
        let t = (time - a.time) / (b.time - a.time)
        return blend(a.values, b.values, t)
    }

    func blend(_ a: [Double], _ b: [Double], _ t: Double) -> [Double] { zip(a, b).map { $0 + ($1 - $0) * t } }

    /// Every sample's values, one after another.
    var allValues: [Double] { samples.flatMap(\.values) }
}

/// An animated value of one kind, its values read and written as `shape`.
open class AnimatedSingle: MDLAnimatedValue {
    class var shape: ValueShape { .scalar }
    override var width: Int { Self.shape.components }

    func setValue(_ pointer: UnsafeRawPointer, at time: Double, double: Bool) {
        set(Self.shape.read(pointer, count: 1, double: double), at: time, double: double)
    }

    func getValue(_ pointer: UnsafeMutableRawPointer, at time: Double, double: Bool) {
        Self.shape.write(values(at: time), to: pointer, maxCount: 1, double: double)
    }

    func resetValues(_ values: UnsafeRawPointer?, times: UnsafePointer<Double>?, count: UInt, double: Bool) {
        let count = Int(count)
        reset(Self.shape.read(values, count: count, double: double),
              times: times.map { Array(UnsafeBufferPointer(start: $0, count: count)) } ?? [], double: double)
    }

    func getValues(_ pointer: UnsafeMutableRawPointer?, maxCount: UInt, double: Bool) -> UInt {
        UInt(Self.shape.write(allValues, to: pointer, maxCount: Int(maxCount), double: double))
    }
}

@ObjCClass("MDLAnimatedScalar")
open class MDLAnimatedScalar: AnimatedSingle {
    @ObjCMethod("setFloat:atTime:") func setFloat(_ v: Float, atTime time: Double) { set([Double(v)], at: time, double: false) }
    @ObjCMethod("setDouble:atTime:") func setDouble(_ v: Double, atTime time: Double) { set([v], at: time, double: true) }
    @ObjCMethod("floatAtTime:") func float(atTime time: Double) -> Float { Float(values(at: time)[0]) }
    @ObjCMethod("doubleAtTime:") func double(atTime time: Double) -> Double { values(at: time)[0] }
    @ObjCMethod("resetWithFloatArray:atTimes:count:")
    func reset(floats: UnsafeRawPointer?, times: UnsafePointer<Double>?, count: UInt) { resetValues(floats, times: times, count: count, double: false) }
    @ObjCMethod("resetWithDoubleArray:atTimes:count:")
    func reset(doubles: UnsafeRawPointer?, times: UnsafePointer<Double>?, count: UInt) { resetValues(doubles, times: times, count: count, double: true) }
    @ObjCMethod("getFloatArray:maxCount:") func getFloats(_ p: UnsafeMutableRawPointer?, maxCount: UInt) -> UInt { getValues(p, maxCount: maxCount, double: false) }
    @ObjCMethod("getDoubleArray:maxCount:") func getDoubles(_ p: UnsafeMutableRawPointer?, maxCount: UInt) -> UInt { getValues(p, maxCount: maxCount, double: true) }
}

@ObjCClass("MDLAnimatedVector2")
open class MDLAnimatedVector2: AnimatedSingle {
    override class var shape: ValueShape { .vector2 }

    @ObjCMethod("setFloat2:atTime:") func setFloat2(_ v: PerryMDLFloat2, atTime time: Double) { set([Double(v.v.x), Double(v.v.y)], at: time, double: false) }
    @ObjCMethod("setDouble2:atTime:") func setDouble2(_ v: PerryMDLDouble2, atTime time: Double) { set([v.v.x, v.v.y], at: time, double: true) }
    @ObjCMethod("float2AtTime:") func float2(atTime time: Double) -> PerryMDLFloat2 {
        let v = values(at: time)
        return PerryMDLFloat2(v: SIMD2(Float(v[0]), Float(v[1])))
    }
    @ObjCMethod("double2AtTime:") func double2(atTime time: Double) -> PerryMDLDouble2 {
        let v = values(at: time)
        return PerryMDLDouble2(v: SIMD2(v[0], v[1]))
    }
    @ObjCMethod("resetWithFloat2Array:atTimes:count:")
    func reset(floats: UnsafeRawPointer?, times: UnsafePointer<Double>?, count: UInt) { resetValues(floats, times: times, count: count, double: false) }
    @ObjCMethod("resetWithDouble2Array:atTimes:count:")
    func reset(doubles: UnsafeRawPointer?, times: UnsafePointer<Double>?, count: UInt) { resetValues(doubles, times: times, count: count, double: true) }
    @ObjCMethod("getFloat2Array:maxCount:") func getFloats(_ p: UnsafeMutableRawPointer?, maxCount: UInt) -> UInt { getValues(p, maxCount: maxCount, double: false) }
    @ObjCMethod("getDouble2Array:maxCount:") func getDoubles(_ p: UnsafeMutableRawPointer?, maxCount: UInt) -> UInt { getValues(p, maxCount: maxCount, double: true) }
}

/// Installs the x86_64 implementations of the vector_double3 and
/// vector_double4 getters, which return their lanes as Darwin does.
enum DoubleVectors {
    static func install(_ cls: ObjCClass, selector: String, lanes: Int) {
        #if arch(x86_64)
        perry_mdl_set_vector_getter { object, _, out, time in
            guard let object, let out, let value = ObjCPeers.peer(of: object) as? MDLAnimatedValue else { return }
            let values = value.samples.isEmpty ? [Double](repeating: 0, count: value.width) : value.values(at: time)
            for i in 0..<4 { out[i] = i < values.count ? values[i] : 0 }
        }
        let implementation: @convention(c) () -> Void = lanes == 3 ? perry_mdl_double3_return : perry_mdl_double4_return
        cls.addMethod(selector, types: "<\(lanes)d16@0:8d16", implementation: unsafeBitCast(implementation, to: UnsafeRawPointer.self),
                      isClassMethod: false)
        #endif
    }
}

@ObjCClass("MDLAnimatedVector3")
open class MDLAnimatedVector3: AnimatedSingle {
    override class var shape: ValueShape { .vector3 }

    open override class func didDefineObjCClass(_ cls: ObjCClass) { DoubleVectors.install(cls, selector: "double3AtTime:", lanes: 3) }

    @ObjCMethod("setFloat3:atTime:") func setFloat3(_ v: PerryMDLFloat3, atTime time: Double) {
        set([Double(v.v.x), Double(v.v.y), Double(v.v.z)], at: time, double: false)
    }
    @ObjCMethod("setDouble3:atTime:") func setDouble3(_ v: PerryMDLDouble3, atTime time: Double) { set(Array(v.values.prefix(3)), at: time, double: true) }
    @ObjCMethod("float3AtTime:") func float3(atTime time: Double) -> PerryMDLFloat3 {
        let v = values(at: time)
        return PerryMDLFloat3(v: SIMD3(Float(v[0]), Float(v[1]), Float(v[2])))
    }
    @ObjCMethod("double3AtTime:") func double3(atTime time: Double) -> PerryMDLDouble3 {
        let v = values(at: time)
        return PerryMDLDouble3([v[0], v[1], v[2], 0])
    }
    @ObjCMethod("resetWithFloat3Array:atTimes:count:")
    func reset(floats: UnsafeRawPointer?, times: UnsafePointer<Double>?, count: UInt) { resetValues(floats, times: times, count: count, double: false) }
    @ObjCMethod("resetWithDouble3Array:atTimes:count:")
    func reset(doubles: UnsafeRawPointer?, times: UnsafePointer<Double>?, count: UInt) { resetValues(doubles, times: times, count: count, double: true) }
    @ObjCMethod("getFloat3Array:maxCount:") func getFloats(_ p: UnsafeMutableRawPointer?, maxCount: UInt) -> UInt { getValues(p, maxCount: maxCount, double: false) }
    @ObjCMethod("getDouble3Array:maxCount:") func getDoubles(_ p: UnsafeMutableRawPointer?, maxCount: UInt) -> UInt { getValues(p, maxCount: maxCount, double: true) }
}

@ObjCClass("MDLAnimatedVector4")
open class MDLAnimatedVector4: AnimatedSingle {
    override class var shape: ValueShape { .vector4 }

    open override class func didDefineObjCClass(_ cls: ObjCClass) { DoubleVectors.install(cls, selector: "double4AtTime:", lanes: 4) }

    @ObjCMethod("setFloat4:atTime:") func setFloat4(_ v: PerryMDLFloat4, atTime time: Double) {
        set([Double(v.v.x), Double(v.v.y), Double(v.v.z), Double(v.v.w)], at: time, double: false)
    }
    @ObjCMethod("setDouble4:atTime:") func setDouble4(_ v: PerryMDLDouble4, atTime time: Double) { set(v.values, at: time, double: true) }
    @ObjCMethod("float4AtTime:") func float4(atTime time: Double) -> PerryMDLFloat4 {
        let v = values(at: time)
        return PerryMDLFloat4(v: SIMD4(Float(v[0]), Float(v[1]), Float(v[2]), Float(v[3])))
    }
    @ObjCMethod("double4AtTime:") func double4(atTime time: Double) -> PerryMDLDouble4 {
        let v = values(at: time)
        return PerryMDLDouble4(v)
    }
    @ObjCMethod("resetWithFloat4Array:atTimes:count:")
    func reset(floats: UnsafeRawPointer?, times: UnsafePointer<Double>?, count: UInt) { resetValues(floats, times: times, count: count, double: false) }
    @ObjCMethod("resetWithDouble4Array:atTimes:count:")
    func reset(doubles: UnsafeRawPointer?, times: UnsafePointer<Double>?, count: UInt) { resetValues(doubles, times: times, count: count, double: true) }
    @ObjCMethod("getFloat4Array:maxCount:") func getFloats(_ p: UnsafeMutableRawPointer?, maxCount: UInt) -> UInt { getValues(p, maxCount: maxCount, double: false) }
    @ObjCMethod("getDouble4Array:maxCount:") func getDoubles(_ p: UnsafeMutableRawPointer?, maxCount: UInt) -> UInt { getValues(p, maxCount: maxCount, double: true) }
}

/// Spherical interpolation of quaternions (x, y, z, w), by the shorter way.
func slerp(_ a: [Double], _ b: [Double], _ t: Double, offset: Int = 0) -> [Double] {
    var q = Array(b[offset..<(offset + 4)])
    let p = Array(a[offset..<(offset + 4)])
    var cosine = zip(p, q).map(*).reduce(0, +)
    if cosine < 0 {
        q = q.map { -$0 }
        cosine = -cosine
    }
    if cosine > 0.9995 {
        let mixed = zip(p, q).map { $0 + ($1 - $0) * t }
        let length = mixed.map { $0 * $0 }.reduce(0, +).squareRoot()
        return mixed.map { $0 / length }
    }
    let angle = acos(cosine), s = sin(angle)
    let wa = sin((1 - t) * angle) / s, wb = sin(t * angle) / s
    return zip(p, q).map { $0 * wa + $1 * wb }
}

@ObjCClass("MDLAnimatedQuaternion")
open class MDLAnimatedQuaternion: AnimatedSingle {
    override class var shape: ValueShape { .vector4 }

    override func blend(_ a: [Double], _ b: [Double], _ t: Double) -> [Double] { slerp(a, b, t) }

    @ObjCMethod("setFloatQuaternion:atTime:") func setFloatQuaternion(_ v: PerryMDLFloat4, atTime time: Double) {
        set([Double(v.v.x), Double(v.v.y), Double(v.v.z), Double(v.v.w)], at: time, double: false)
    }
    @ObjCMethod("setDoubleQuaternion:atTime:") func setDoubleQuaternion(_ v: PerryMDLDouble4, atTime time: Double) {
        set(v.values, at: time, double: true)
    }
    @ObjCMethod("floatQuaternionAtTime:") func floatQuaternion(atTime time: Double) -> PerryMDLFloat4 {
        guard !samples.isEmpty else { return PerryMDLFloat4(v: SIMD4(0, 0, 0, 1)) }
        let v = values(at: time)
        return PerryMDLFloat4(v: SIMD4(Float(v[0]), Float(v[1]), Float(v[2]), Float(v[3])))
    }
    @ObjCMethod("doubleQuaternionAtTime:") func doubleQuaternion(atTime time: Double) -> PerryMDLDouble4 {
        guard !samples.isEmpty else { return PerryMDLDouble4([0, 0, 0, 1]) }
        let v = values(at: time)
        return PerryMDLDouble4(v)
    }
    @ObjCMethod("resetWithFloatQuaternionArray:atTimes:count:")
    func reset(floats: UnsafeRawPointer?, times: UnsafePointer<Double>?, count: UInt) { resetValues(floats, times: times, count: count, double: false) }
    @ObjCMethod("resetWithDoubleQuaternionArray:atTimes:count:")
    func reset(doubles: UnsafeRawPointer?, times: UnsafePointer<Double>?, count: UInt) { resetValues(doubles, times: times, count: count, double: true) }
    @ObjCMethod("getFloatQuaternionArray:maxCount:")
    func getFloats(_ p: UnsafeMutableRawPointer?, maxCount: UInt) -> UInt { getValues(p, maxCount: maxCount, double: false) }
    @ObjCMethod("getDoubleQuaternionArray:maxCount:")
    func getDoubles(_ p: UnsafeMutableRawPointer?, maxCount: UInt) -> UInt { getValues(p, maxCount: maxCount, double: true) }
}

@ObjCClass("MDLAnimatedMatrix4x4")
open class MDLAnimatedMatrix4x4: AnimatedSingle {
    override class var shape: ValueShape { .matrix }

    @ObjCMethod("setFloat4x4:atTime:") func setFloat4x4(_ v: PerryMDLFloat4x4, atTime time: Double) {
        set(v.matrix.c.map(Double.init), at: time, double: false)
    }
    @ObjCMethod("setDouble4x4:atTime:") func setDouble4x4(_ v: PerryMDLDouble4x4, atTime time: Double) {
        set(v.values, at: time, double: true)
    }
    @ObjCMethod("float4x4AtTime:") func float4x4(atTime time: Double) -> PerryMDLFloat4x4 {
        guard !samples.isEmpty else { return PerryMDLFloat4x4(Matrix4.identity) }
        return PerryMDLFloat4x4(Matrix4(values(at: time).map(Float.init)))
    }
    @ObjCMethod("double4x4AtTime:") func double4x4(atTime time: Double) -> PerryMDLDouble4x4 {
        PerryMDLDouble4x4(samples.isEmpty ? Matrix4.identity.c.map(Double.init) : values(at: time))
    }
    @ObjCMethod("resetWithFloat4x4Array:atTimes:count:")
    func reset(floats: UnsafeRawPointer?, times: UnsafePointer<Double>?, count: UInt) { resetValues(floats, times: times, count: count, double: false) }
    @ObjCMethod("resetWithDouble4x4Array:atTimes:count:")
    func reset(doubles: UnsafeRawPointer?, times: UnsafePointer<Double>?, count: UInt) { resetValues(doubles, times: times, count: count, double: true) }
    @ObjCMethod("getFloat4x4Array:maxCount:") func getFloats(_ p: UnsafeMutableRawPointer?, maxCount: UInt) -> UInt { getValues(p, maxCount: maxCount, double: false) }
    @ObjCMethod("getDouble4x4Array:maxCount:") func getDoubles(_ p: UnsafeMutableRawPointer?, maxCount: UInt) -> UInt { getValues(p, maxCount: maxCount, double: true) }
}

// MARK: - Arrays

/// An animated array of `elementCount` values of one kind.
open class AnimatedArray: MDLAnimatedValue {
    class var shape: ValueShape { .scalar }
    var elements = 0
    override var width: Int { elements * Self.shape.components }

    override func copyExtra(to copy: MDLAnimatedValue) { (copy as? AnimatedArray)?.elements = elements }

    func setArray(_ pointer: UnsafeRawPointer?, count: UInt, at time: Double, double: Bool) {
        var values = Self.shape.read(pointer, count: min(Int(count), elements), double: double)
        values += [Double](repeating: 0, count: max(width - values.count, 0))
        set(values, at: time, double: double)
    }

    func getArray(_ pointer: UnsafeMutableRawPointer?, maxCount: UInt, at time: Double, double: Bool) -> UInt {
        UInt(Self.shape.write(values(at: time), to: pointer, maxCount: Int(maxCount), double: double))
    }

    func resetArrays(_ values: UnsafeRawPointer?, count: UInt, times: UnsafePointer<Double>?, timesCount: UInt, double: Bool) {
        let all = Self.shape.read(values, count: Int(count), double: double)
        reset(all, times: times.map { Array(UnsafeBufferPointer(start: $0, count: Int(timesCount))) } ?? [], double: double)
    }

    func getAll(_ pointer: UnsafeMutableRawPointer?, maxCount: UInt, double: Bool) -> UInt {
        UInt(Self.shape.write(allValues, to: pointer, maxCount: Int(maxCount), double: double))
    }
}

@ObjCClass("MDLAnimatedScalarArray")
open class MDLAnimatedScalarArray: AnimatedArray {
    @ObjCMethod("initWithElementCount:") public init(elementCount: UInt) {
        super.init()
        elements = Int(elementCount)
    }

    public required init() { super.init() }

    @ObjCMethod("elementCount") func elementCount() -> UInt { UInt(elements) }

    @ObjCMethod("setFloatArray:count:atTime:") func setFloats(_ p: UnsafeRawPointer?, count: UInt, atTime time: Double) {
        setArray(p, count: count, at: time, double: false)
    }
    @ObjCMethod("setDoubleArray:count:atTime:") func setDoubles(_ p: UnsafeRawPointer?, count: UInt, atTime time: Double) {
        setArray(p, count: count, at: time, double: true)
    }
    @ObjCMethod("getFloatArray:maxCount:atTime:") func getFloats(_ p: UnsafeMutableRawPointer?, maxCount: UInt, atTime time: Double) -> UInt {
        getArray(p, maxCount: maxCount, at: time, double: false)
    }
    @ObjCMethod("getDoubleArray:maxCount:atTime:") func getDoubles(_ p: UnsafeMutableRawPointer?, maxCount: UInt, atTime time: Double) -> UInt {
        getArray(p, maxCount: maxCount, at: time, double: true)
    }
    @ObjCMethod("resetWithFloatArray:count:atTimes:count:")
    func reset(floats: UnsafeRawPointer?, count: UInt, times: UnsafePointer<Double>?, timesCount: UInt) {
        resetArrays(floats, count: count, times: times, timesCount: timesCount, double: false)
    }
    @ObjCMethod("resetWithDoubleArray:count:atTimes:count:")
    func reset(doubles: UnsafeRawPointer?, count: UInt, times: UnsafePointer<Double>?, timesCount: UInt) {
        resetArrays(doubles, count: count, times: times, timesCount: timesCount, double: true)
    }
    @ObjCMethod("getFloatArray:maxCount:") func getAllFloats(_ p: UnsafeMutableRawPointer?, maxCount: UInt) -> UInt { getAll(p, maxCount: maxCount, double: false) }
    @ObjCMethod("getDoubleArray:maxCount:") func getAllDoubles(_ p: UnsafeMutableRawPointer?, maxCount: UInt) -> UInt { getAll(p, maxCount: maxCount, double: true) }
}

@ObjCClass("MDLAnimatedVector3Array")
open class MDLAnimatedVector3Array: AnimatedArray {
    @ObjCMethod("initWithElementCount:") public init(elementCount: UInt) {
        super.init()
        elements = Int(elementCount)
    }

    public required init() { super.init() }

    @ObjCMethod("elementCount") func elementCount() -> UInt { UInt(elements) }

    override class var shape: ValueShape { .vector3 }

    @ObjCMethod("setFloat3Array:count:atTime:") func setFloats(_ p: UnsafeRawPointer?, count: UInt, atTime time: Double) {
        setArray(p, count: count, at: time, double: false)
    }
    @ObjCMethod("setDouble3Array:count:atTime:") func setDoubles(_ p: UnsafeRawPointer?, count: UInt, atTime time: Double) {
        setArray(p, count: count, at: time, double: true)
    }
    @ObjCMethod("getFloat3Array:maxCount:atTime:") func getFloats(_ p: UnsafeMutableRawPointer?, maxCount: UInt, atTime time: Double) -> UInt {
        getArray(p, maxCount: maxCount, at: time, double: false)
    }
    @ObjCMethod("getDouble3Array:maxCount:atTime:") func getDoubles(_ p: UnsafeMutableRawPointer?, maxCount: UInt, atTime time: Double) -> UInt {
        getArray(p, maxCount: maxCount, at: time, double: true)
    }
    @ObjCMethod("resetWithFloat3Array:count:atTimes:count:")
    func reset(floats: UnsafeRawPointer?, count: UInt, times: UnsafePointer<Double>?, timesCount: UInt) {
        resetArrays(floats, count: count, times: times, timesCount: timesCount, double: false)
    }
    @ObjCMethod("resetWithDouble3Array:count:atTimes:count:")
    func reset(doubles: UnsafeRawPointer?, count: UInt, times: UnsafePointer<Double>?, timesCount: UInt) {
        resetArrays(doubles, count: count, times: times, timesCount: timesCount, double: true)
    }
    @ObjCMethod("getFloat3Array:maxCount:") func getAllFloats(_ p: UnsafeMutableRawPointer?, maxCount: UInt) -> UInt { getAll(p, maxCount: maxCount, double: false) }
    @ObjCMethod("getDouble3Array:maxCount:") func getAllDoubles(_ p: UnsafeMutableRawPointer?, maxCount: UInt) -> UInt { getAll(p, maxCount: maxCount, double: true) }
}

@ObjCClass("MDLAnimatedQuaternionArray")
open class MDLAnimatedQuaternionArray: AnimatedArray {
    @ObjCMethod("initWithElementCount:") public init(elementCount: UInt) {
        super.init()
        elements = Int(elementCount)
    }

    public required init() { super.init() }

    @ObjCMethod("elementCount") func elementCount() -> UInt { UInt(elements) }

    override class var shape: ValueShape { .vector4 }

    override func blend(_ a: [Double], _ b: [Double], _ t: Double) -> [Double] {
        stride(from: 0, to: a.count, by: 4).flatMap { slerp(a, b, t, offset: $0) }
    }

    @ObjCMethod("setFloatQuaternionArray:count:atTime:") func setFloats(_ p: UnsafeRawPointer?, count: UInt, atTime time: Double) {
        setArray(p, count: count, at: time, double: false)
    }
    @ObjCMethod("setDoubleQuaternionArray:count:atTime:") func setDoubles(_ p: UnsafeRawPointer?, count: UInt, atTime time: Double) {
        setArray(p, count: count, at: time, double: true)
    }
    @ObjCMethod("getFloatQuaternionArray:maxCount:atTime:")
    func getFloats(_ p: UnsafeMutableRawPointer?, maxCount: UInt, atTime time: Double) -> UInt { getArray(p, maxCount: maxCount, at: time, double: false) }
    @ObjCMethod("getDoubleQuaternionArray:maxCount:atTime:")
    func getDoubles(_ p: UnsafeMutableRawPointer?, maxCount: UInt, atTime time: Double) -> UInt { getArray(p, maxCount: maxCount, at: time, double: true) }
    @ObjCMethod("resetWithFloatQuaternionArray:count:atTimes:count:")
    func reset(floats: UnsafeRawPointer?, count: UInt, times: UnsafePointer<Double>?, timesCount: UInt) {
        resetArrays(floats, count: count, times: times, timesCount: timesCount, double: false)
    }
    @ObjCMethod("resetWithDoubleQuaternionArray:count:atTimes:count:")
    func reset(doubles: UnsafeRawPointer?, count: UInt, times: UnsafePointer<Double>?, timesCount: UInt) {
        resetArrays(doubles, count: count, times: times, timesCount: timesCount, double: true)
    }
    @ObjCMethod("getFloatQuaternionArray:maxCount:") func getAllFloats(_ p: UnsafeMutableRawPointer?, maxCount: UInt) -> UInt { getAll(p, maxCount: maxCount, double: false) }
    @ObjCMethod("getDoubleQuaternionArray:maxCount:") func getAllDoubles(_ p: UnsafeMutableRawPointer?, maxCount: UInt) -> UInt { getAll(p, maxCount: maxCount, double: true) }
}

@ObjCClass("MDLMatrix4x4Array")
open class MDLMatrix4x4Array: NSObject {
    var elements = 0
    var values: [Double] = []
    var precisionValue = Precision.undefined

    @ObjCMethod("init") public required override init() { super.init() }

    @ObjCMethod("initWithElementCount:") public init(elementCount: UInt) {
        elements = Int(elementCount)
        values = [Double](repeating: 0, count: elements * 16)
        super.init()
    }

    @ObjCMethod("elementCount") func elementCount() -> UInt { UInt(elements) }
    @ObjCMethod("precision") func precision() -> UInt { precisionValue }
    @ObjCMethod("clear") func clear() { values = [Double](repeating: 0, count: elements * 16) }

    func setValues(_ p: UnsafeRawPointer?, count: UInt, double: Bool) {
        precisionValue = double ? Precision.double : Precision.float
        var read = ValueShape.matrix.read(p, count: min(Int(count), elements), double: double)
        read += [Double](repeating: 0, count: max(elements * 16 - read.count, 0))
        values = read
    }

    @ObjCMethod("setFloat4x4Array:count:") func setFloats(_ p: UnsafeRawPointer?, count: UInt) { setValues(p, count: count, double: false) }
    @ObjCMethod("setDouble4x4Array:count:") func setDoubles(_ p: UnsafeRawPointer?, count: UInt) { setValues(p, count: count, double: true) }
    @ObjCMethod("getFloat4x4Array:maxCount:") func getFloats(_ p: UnsafeMutableRawPointer?, maxCount: UInt) -> UInt {
        UInt(ValueShape.matrix.write(values, to: p, maxCount: Int(maxCount), double: false))
    }
    @ObjCMethod("getDouble4x4Array:maxCount:") func getDoubles(_ p: UnsafeMutableRawPointer?, maxCount: UInt) -> UInt {
        UInt(ValueShape.matrix.write(values, to: p, maxCount: Int(maxCount), double: true))
    }

    @ObjCMethod("copyWithZone:") func copy(zone: UnsafeMutableRawPointer?) -> MDLMatrix4x4Array {
        let copy = MDLMatrix4x4Array(elementCount: UInt(elements))
        copy.values = values
        copy.precisionValue = precisionValue
        return copy
    }
}
