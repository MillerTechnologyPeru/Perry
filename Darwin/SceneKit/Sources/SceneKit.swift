import CoreGraphics
import Foundation
import QuartzCore
import simd

// SceneKit's Swift API: vector and matrix conversions between SceneKit's,
// simd's and Core Animation's types, geometry from Swift arrays, bounding
// volumes as tuples and SCNVector3/SCNVector4 bridged to NSValue.

#if os(macOS)
public typealias SCNFloat = CGFloat
#else
public typealias SCNFloat = Float
#endif

extension SCNVector3 {
    public init(_ x: Float, _ y: Float, _ z: Float) {
        self.init(x: SCNFloat(x), y: SCNFloat(y), z: SCNFloat(z))
    }
    public init(_ x: CGFloat, _ y: CGFloat, _ z: CGFloat) {
        self.init(x: SCNFloat(x), y: SCNFloat(y), z: SCNFloat(z))
    }
    public init(_ x: Double, _ y: Double, _ z: Double) {
        self.init(x: SCNFloat(x), y: SCNFloat(y), z: SCNFloat(z))
    }
    public init(_ x: Int, _ y: Int, _ z: Int) {
        self.init(x: SCNFloat(x), y: SCNFloat(y), z: SCNFloat(z))
    }
    public init(_ v: SIMD3<Float>) {
        self.init(x: SCNFloat(v.x), y: SCNFloat(v.y), z: SCNFloat(v.z))
    }
    public init(_ v: SIMD3<Double>) {
        self.init(x: SCNFloat(v.x), y: SCNFloat(v.y), z: SCNFloat(v.z))
    }
}

extension SIMD3 where Scalar == Float {
    public init(_ v: SCNVector3) {
        self.init(Float(v.x), Float(v.y), Float(v.z))
    }
}

extension SIMD3 where Scalar == Double {
    public init(_ v: SCNVector3) {
        self.init(Double(v.x), Double(v.y), Double(v.z))
    }
}

extension SCNVector4 {
    public init(_ x: Float, _ y: Float, _ z: Float, _ w: Float) {
        self.init(x: SCNFloat(x), y: SCNFloat(y), z: SCNFloat(z), w: SCNFloat(w))
    }
    public init(_ x: CGFloat, _ y: CGFloat, _ z: CGFloat, _ w: CGFloat) {
        self.init(x: SCNFloat(x), y: SCNFloat(y), z: SCNFloat(z), w: SCNFloat(w))
    }
    public init(_ x: Double, _ y: Double, _ z: Double, _ w: Double) {
        self.init(x: SCNFloat(x), y: SCNFloat(y), z: SCNFloat(z), w: SCNFloat(w))
    }
    public init(_ x: Int, _ y: Int, _ z: Int, _ w: Int) {
        self.init(x: SCNFloat(x), y: SCNFloat(y), z: SCNFloat(z), w: SCNFloat(w))
    }
    public init(_ v: SIMD4<Float>) {
        self.init(x: SCNFloat(v.x), y: SCNFloat(v.y), z: SCNFloat(v.z), w: SCNFloat(v.w))
    }
    public init(_ v: SIMD4<Double>) {
        self.init(x: SCNFloat(v.x), y: SCNFloat(v.y), z: SCNFloat(v.z), w: SCNFloat(v.w))
    }
}

extension SIMD4 where Scalar == Float {
    public init(_ v: SCNVector4) {
        self.init(Float(v.x), Float(v.y), Float(v.z), Float(v.w))
    }
}

extension SIMD4 where Scalar == Double {
    public init(_ v: SCNVector4) {
        self.init(Double(v.x), Double(v.y), Double(v.z), Double(v.w))
    }
}

// A transform's rows m1x...m4x are a simd matrix's columns, as
// SCNMatrix4ToMat4 and SCNMatrix4FromMat4 have them. On macOS SCNMatrix4 is
// CATransform3D; elsewhere it is SceneKit's own struct of Floats.

#if os(macOS)
extension CATransform3D {
    public init(_ m: float4x4) {
        self.init(m11: CGFloat(m.columns.0.x), m12: CGFloat(m.columns.0.y), m13: CGFloat(m.columns.0.z), m14: CGFloat(m.columns.0.w),
                  m21: CGFloat(m.columns.1.x), m22: CGFloat(m.columns.1.y), m23: CGFloat(m.columns.1.z), m24: CGFloat(m.columns.1.w),
                  m31: CGFloat(m.columns.2.x), m32: CGFloat(m.columns.2.y), m33: CGFloat(m.columns.2.z), m34: CGFloat(m.columns.2.w),
                  m41: CGFloat(m.columns.3.x), m42: CGFloat(m.columns.3.y), m43: CGFloat(m.columns.3.z), m44: CGFloat(m.columns.3.w))
    }

    public init(_ m: double4x4) {
        self.init(m11: CGFloat(m.columns.0.x), m12: CGFloat(m.columns.0.y), m13: CGFloat(m.columns.0.z), m14: CGFloat(m.columns.0.w),
                  m21: CGFloat(m.columns.1.x), m22: CGFloat(m.columns.1.y), m23: CGFloat(m.columns.1.z), m24: CGFloat(m.columns.1.w),
                  m31: CGFloat(m.columns.2.x), m32: CGFloat(m.columns.2.y), m33: CGFloat(m.columns.2.z), m34: CGFloat(m.columns.2.w),
                  m41: CGFloat(m.columns.3.x), m42: CGFloat(m.columns.3.y), m43: CGFloat(m.columns.3.z), m44: CGFloat(m.columns.3.w))
    }
}

#else
extension SCNMatrix4 {
    public init(_ m: float4x4) {
        self.init(m11: m.columns.0.x, m12: m.columns.0.y, m13: m.columns.0.z, m14: m.columns.0.w,
                  m21: m.columns.1.x, m22: m.columns.1.y, m23: m.columns.1.z, m24: m.columns.1.w,
                  m31: m.columns.2.x, m32: m.columns.2.y, m33: m.columns.2.z, m34: m.columns.2.w,
                  m41: m.columns.3.x, m42: m.columns.3.y, m43: m.columns.3.z, m44: m.columns.3.w)
    }

    public init(_ m: double4x4) {
        self.init(float4x4(SIMD4<Float>(m.columns.0), SIMD4<Float>(m.columns.1),
                           SIMD4<Float>(m.columns.2), SIMD4<Float>(m.columns.3)))
    }
}
#endif

extension simd_float4x4 {
    public init(_ m: SCNMatrix4) {
        self.init(SIMD4<Float>(Float(m.m11), Float(m.m12), Float(m.m13), Float(m.m14)),
                  SIMD4<Float>(Float(m.m21), Float(m.m22), Float(m.m23), Float(m.m24)),
                  SIMD4<Float>(Float(m.m31), Float(m.m32), Float(m.m33), Float(m.m34)),
                  SIMD4<Float>(Float(m.m41), Float(m.m42), Float(m.m43), Float(m.m44)))
    }
}

extension simd_double4x4 {
    public init(_ m: SCNMatrix4) {
        self.init(SIMD4<Double>(Double(m.m11), Double(m.m12), Double(m.m13), Double(m.m14)),
                  SIMD4<Double>(Double(m.m21), Double(m.m22), Double(m.m23), Double(m.m24)),
                  SIMD4<Double>(Double(m.m31), Double(m.m32), Double(m.m33), Double(m.m34)),
                  SIMD4<Double>(Double(m.m41), Double(m.m42), Double(m.m43), Double(m.m44)))
    }
}

@available(macOS 10.8, *)
extension SCNGeometryElement {
    /// An element of the indices given, of their own size. For polygons the
    /// array is the polygons' vertex counts followed by their indices, as
    /// SceneKit takes it.
    public convenience init<IndexType>(indices: [IndexType], primitiveType: SCNGeometryPrimitiveType) where IndexType: FixedWidthInteger {
        let count: Int
        switch primitiveType {
        case .triangles: count = indices.count / 3
        case .triangleStrip: count = max(indices.count - 2, 0)
        case .line: count = indices.count / 2
        case .point: count = indices.count
        case .polygon: count = Self.polygonCount(indices)
        @unknown default: count = indices.count / 3
        }
        let data = indices.withUnsafeBufferPointer { Data(buffer: $0) }
        self.init(data: data, primitiveType: primitiveType, primitiveCount: count, bytesPerIndex: MemoryLayout<IndexType>.size)
    }

    /// The number of polygons n whose counts, the first n values, add up to
    /// the n indices that follow them.
    private static func polygonCount<IndexType: FixedWidthInteger>(_ indices: [IndexType]) -> Int {
        var sum = 0
        for (n, vertices) in indices.enumerated() {
            sum += Int(truncatingIfNeeded: vertices)
            if sum == indices.count - (n + 1) { return n + 1 }
            if sum > indices.count { break }
        }
        return 0
    }
}

@available(macOS 10.8, *)
extension SCNGeometrySource {
    @nonobjc public convenience init(vertices: [SCNVector3]) {
        self.init(__vertices: vertices, count: vertices.count)
    }

    @nonobjc public convenience init(normals: [SCNVector3]) {
        self.init(__normals: normals, count: normals.count)
    }

    @nonobjc public convenience init(textureCoordinates: [CGPoint]) {
        self.init(__textureCoordinates: textureCoordinates, count: textureCoordinates.count)
    }
}

@available(macOS 10.10, *)
extension SCNBoundingVolume {
    public var boundingBox: (min: SCNVector3, max: SCNVector3) {
        get {
            var min = SCNVector3Zero
            var max = SCNVector3Zero
            __getBoundingBoxMin(&min, max: &max)
            return (min, max)
        }
        set {
            var min = newValue.min
            var max = newValue.max
            __setBoundingBoxMin(&min, max: &max)
        }
    }

    public var boundingSphere: (center: SCNVector3, radius: Float) {
        var center = SCNVector3Zero
        var radius: CGFloat = 0
        __getBoundingSphereCenter(&center, radius: &radius)
        return (center, Float(radius))
    }
}

@available(macOS 10.8, *)
extension SCNSceneSource {
    public func entryWithIdentifier<T>(_ uid: String, withClass entryClass: T.Type) -> T? where T: AnyObject {
        __entry(withIdentifier: uid, with: entryClass) as? T
    }
}

extension SCNVector3: _ObjectiveCBridgeable {
    public func _bridgeToObjectiveC() -> NSValue {
        NSValue(scnVector3: self)
    }

    public static func _forceBridgeFromObjectiveC(_ source: NSValue, result: inout SCNVector3?) {
        result = source.scnVector3Value
    }

    public static func _conditionallyBridgeFromObjectiveC(_ source: NSValue, result: inout SCNVector3?) -> Bool {
        result = source.scnVector3Value
        return true
    }

    public static func _unconditionallyBridgeFromObjectiveC(_ source: NSValue?) -> SCNVector3 {
        source?.scnVector3Value ?? SCNVector3Zero
    }

    public typealias _ObjectiveCType = NSValue
}

extension SCNVector4: _ObjectiveCBridgeable {
    public func _bridgeToObjectiveC() -> NSValue {
        NSValue(scnVector4: self)
    }

    public static func _forceBridgeFromObjectiveC(_ source: NSValue, result: inout SCNVector4?) {
        result = source.scnVector4Value
    }

    public static func _conditionallyBridgeFromObjectiveC(_ source: NSValue, result: inout SCNVector4?) -> Bool {
        result = source.scnVector4Value
        return true
    }

    public static func _unconditionallyBridgeFromObjectiveC(_ source: NSValue?) -> SCNVector4 {
        source?.scnVector4Value ?? SCNVector4Zero
    }

    public typealias _ObjectiveCType = NSValue
}

#if !os(macOS)
extension SCNMatrix4: _ObjectiveCBridgeable {
    public func _bridgeToObjectiveC() -> NSValue {
        NSValue(scnMatrix4: self)
    }

    public static func _forceBridgeFromObjectiveC(_ source: NSValue, result: inout SCNMatrix4?) {
        result = source.scnMatrix4Value
    }

    public static func _conditionallyBridgeFromObjectiveC(_ source: NSValue, result: inout SCNMatrix4?) -> Bool {
        result = source.scnMatrix4Value
        return true
    }

    public static func _unconditionallyBridgeFromObjectiveC(_ source: NSValue?) -> SCNMatrix4 {
        source?.scnMatrix4Value ?? SCNMatrix4Identity
    }

    public typealias _ObjectiveCType = NSValue
}
#endif
