import CPerryModelIO
import Glibc
import PerryObjCInterop

// Foundation's classes as Model I/O uses them, the simd values its methods
// take, and the messages it sends objects of other providers (buffers and
// allocators that aren't its own).

@ObjCWrapper("NSArray")
class NSArray: NSObject {
    @ObjCMethod("count") func count() -> UInt
    @ObjCMethod("objectAtIndex:") func object(at index: UInt) -> NSObject

    /// The elements, in order.
    var elements: [NSObject] { (0..<count()).map { object(at: $0) } }

    /// A new NSArray of `objects`, autoreleased.
    static func of(_ objects: [NSObject]) -> NSArray {
        typealias Make = @convention(c) (UnsafeMutableRawPointer?, UnsafeRawPointer?,
                                         UnsafePointer<UnsafeMutableRawPointer?>?, UInt) -> UnsafeMutableRawPointer?
        let pointers: [UnsafeMutableRawPointer?] = objects.map { $0.objcObject }
        let array = pointers.withUnsafeBufferPointer {
            unsafeBitCast(ObjCRuntime.msgSend, to: Make.self)(ObjCRuntime.classObject("NSArray"),
                                                            ObjCRuntime.selector("arrayWithObjects:count:"),
                                                            $0.baseAddress, UInt($0.count))
        }
        return NSArray(objCReturnValue: array)
    }
}

@ObjCWrapper("NSMutableArray")
class NSMutableArray: NSArray {
    @ObjCClassMethod("array") static func empty() -> NSMutableArray
    @ObjCMethod("addObject:") func add(_ object: NSObject)
    @ObjCMethod("insertObject:atIndex:") func insert(_ object: NSObject, at index: UInt)
    @ObjCMethod("removeObjectAtIndex:") func remove(at index: UInt)
    @ObjCMethod("removeAllObjects") func removeAll()
    @ObjCMethod("replaceObjectAtIndex:withObject:") func replace(at index: UInt, with object: NSObject)

    /// A new mutable array of `objects`.
    static func with(_ objects: [NSObject]) -> NSMutableArray {
        let array = empty()
        objects.forEach(array.add)
        return array
    }

    /// Removes the first element that is `object` itself.
    func removeIdentical(_ object: NSObject) {
        for (index, element) in elements.enumerated() where element.objcObject == object.objcObject {
            remove(at: UInt(index))
            return
        }
    }
}

@ObjCWrapper("NSData")
class NSData: NSObject {
    @ObjCMethod("bytes") func bytes() -> UnsafeRawPointer?
    @ObjCMethod("length") func length() -> UInt

    /// A copy of the bytes.
    var array: [UInt8] {
        let count = Int(length())
        guard count > 0, let bytes = bytes() else { return [] }
        return Array(UnsafeRawBufferPointer(start: bytes, count: count))
    }
}

@ObjCWrapper("NSMutableData")
class NSMutableData: NSData {
    @ObjCClassMethod("dataWithLength:") static func zeroed(length: UInt) -> NSMutableData
    @ObjCMethod("mutableBytes") func mutableBytes() -> UnsafeMutableRawPointer?

    /// A new NSMutableData of `count` zeroed bytes.
    static func make(count: Int) -> NSMutableData { zeroed(length: UInt(count)) }

    /// A new NSMutableData with a copy of `bytes`.
    static func make(_ bytes: UnsafeRawBufferPointer) -> NSMutableData {
        let data = zeroed(length: UInt(bytes.count))
        if bytes.count > 0, let target = data.mutableBytes(), let source = bytes.baseAddress {
            target.copyMemory(from: source, byteCount: bytes.count)
        }
        return data
    }

    static func make(_ bytes: [UInt8]) -> NSMutableData { bytes.withUnsafeBytes { make($0) } }
}

@ObjCWrapper("NSNumber")
class NSNumber: NSObject {
    @ObjCClassMethod("numberWithDouble:") static func make(double: Double) -> NSNumber
    @ObjCClassMethod("numberWithUnsignedInteger:") static func make(unsigned: UInt) -> NSNumber
    @ObjCMethod("doubleValue") func doubleValue() -> Double
    @ObjCMethod("unsignedIntegerValue") func unsignedValue() -> UInt
}

@ObjCWrapper("NSURL")
class NSURL: NSObject {
    @ObjCClassMethod("fileURLWithPath:") static func file(path: String) -> NSURL
    @ObjCClassMethod("URLWithString:") static func make(string: String) -> NSURL?
    @ObjCMethod("path") func path() -> String?
    @ObjCMethod("absoluteString") func absoluteString() -> String?
    @ObjCMethod("isFileURL") func isFileURL() -> Bool
}

@ObjCWrapper("NSDictionary")
class NSDictionary: NSObject {
    @ObjCClassMethod("dictionaryWithObject:forKey:") static func make(object: NSObject, key: String) -> NSDictionary
}

@ObjCWrapper("NSError")
class NSError: NSObject {
    @ObjCClassMethod("errorWithDomain:code:userInfo:") static func make(domain: String, code: Int, userInfo: NSObject?) -> NSError
}

extension NSObject {
    static func string(_ value: String) -> NSObject { NSObject(objCReturnValue: value.objCArgument()) }

    /// Whether this is the same object as `other`.
    func isSame(_ other: NSObject?) -> Bool { other?.objcObject == objcObject }

    // Messages to the buffers, allocators and zones of other providers.
    @ObjCMethod("map") func sendMap() -> NSObject?
    @ObjCMethod("bytes") func sendBytes() -> UnsafeMutableRawPointer?
    @ObjCMethod("length") func sendLength() -> UInt
    @ObjCMethod("type") func sendType() -> UInt
    @ObjCMethod("newBufferWithData:type:") func sendNewBuffer(data: NSObject, type: UInt) -> NSObject?
    @ObjCMethod("newBuffer:type:") func sendNewBuffer(length: UInt, type: UInt) -> NSObject?
    @ObjCMethod("copy") func sendCopy() -> NSObject?
    @ObjCMethod("isKindOfClass:") func sendIsKind(of cls: ObjCClass) -> Bool
    @ObjCMethod("countByEnumeratingWithState:objects:count:")
    func sendCountByEnumerating(state: UnsafeMutableRawPointer?, objects: UnsafeMutableRawPointer?, count: UInt) -> UInt
    // Transform components of other classes.
    @ObjCMethod("matrix") func sendMatrix() -> PerryMDLFloat4x4
    @ObjCMethod("localTransformAtTime:") func sendLocalTransform(at time: Double) -> PerryMDLFloat4x4
    @ObjCMethod("resetsTransform") func sendResetsTransform() -> Bool
}

/// An NSError in MDLErrorDomain, or another domain, with `message` as its
/// localized description, stored for an `error:` argument.
func storeError(_ pointer: UnsafeMutablePointer<UnsafeMutableRawPointer?>?, _ message: String,
                domain: String = "MDLErrorDomain", code: Int = 0) {
    guard let pointer else { return }
    let info = NSDictionary.make(object: NSObject.string(message), key: "NSLocalizedDescription")
    pointer.pointee = NSError.make(domain: domain, code: code, userInfo: info).objCReturnValue()
}

// MARK: - simd values

extension PerryMDLFloat2: ObjCStructure {
    public typealias ObjCType = PerryMDLFloat2
    public static var objCTypeEncoding: String { "<2f>" }
}

extension PerryMDLFloat3: ObjCStructure {
    public typealias ObjCType = PerryMDLFloat3
    public static var objCTypeEncoding: String { "<3f>" }
    init(_ v: SIMD3<Float>) { self.init(v: v) }
}

extension PerryMDLFloat4: ObjCStructure {
    public typealias ObjCType = PerryMDLFloat4
    public static var objCTypeEncoding: String { "<4f>" }
}

extension PerryMDLDouble2: ObjCStructure {
    public typealias ObjCType = PerryMDLDouble2
    public static var objCTypeEncoding: String { "<2d>" }
}

extension PerryMDLDouble4: ObjCStructure {
    public typealias ObjCType = PerryMDLDouble4
    public static var objCTypeEncoding: String { "<4d>" }

    init(_ v: [Double]) {
        self.init(x: v[0], y: v[1], z: v[2], wBits: (v.count > 3 ? v[3] : 0).bitPattern)
    }

    var values: [Double] { [x, y, z, Double(bitPattern: wBits)] }
}

extension PerryMDLUInt2: ObjCStructure {
    public typealias ObjCType = PerryMDLUInt2
    public static var objCTypeEncoding: String { "<2I>" }
}

extension PerryMDLUInt3: ObjCStructure {
    public typealias ObjCType = PerryMDLUInt3
    public static var objCTypeEncoding: String { "<3I>" }
}

extension PerryMDLInt2: ObjCStructure {
    public typealias ObjCType = PerryMDLInt2
    public static var objCTypeEncoding: String { "<2i>" }
}

extension PerryMDLFloat4x4: ObjCStructure {
    public typealias ObjCType = PerryMDLFloat4x4
    public static var objCTypeEncoding: String { "{?=[4<4f>]}" }

    init(_ m: Matrix4) {
        self.init(c0: SIMD4(m.c[0], m.c[1], m.c[2], m.c[3]), c1: SIMD4(m.c[4], m.c[5], m.c[6], m.c[7]),
                  c2: SIMD4(m.c[8], m.c[9], m.c[10], m.c[11]), c3: SIMD4(m.c[12], m.c[13], m.c[14], m.c[15]))
    }

    var matrix: Matrix4 {
        Matrix4([c0[0], c0[1], c0[2], c0[3], c1[0], c1[1], c1[2], c1[3], c2[0], c2[1], c2[2], c2[3], c3[0], c3[1], c3[2], c3[3]])
    }
}

extension PerryMDLDouble4x4: ObjCStructure {
    public typealias ObjCType = PerryMDLDouble4x4
    public static var objCTypeEncoding: String { "{?=[4<4d>]}" }

    init(_ v: [Double]) {
        self.init()
        withUnsafeMutableBytes(of: &m) { raw in
            for (i, value) in v.prefix(16).enumerated() { raw.storeBytes(of: value, toByteOffset: i * 8, as: Double.self) }
        }
    }

    var values: [Double] { withUnsafeBytes(of: m) { Array($0.bindMemory(to: Double.self)) } }
}

extension PerryMDLBoundingBox: ObjCStructure {
    public typealias ObjCType = PerryMDLBoundingBox
    public static var objCTypeEncoding: String { "{?=<3f><3f>}" }

    /// The box of no points: max below min.
    static var empty: PerryMDLBoundingBox {
        PerryMDLBoundingBox(maxBounds: SIMD3(repeating: -.greatestFiniteMagnitude), minBounds: SIMD3(repeating: .greatestFiniteMagnitude))
    }

    var isEmpty: Bool { maxBounds.x < minBounds.x }

    mutating func add(_ point: SIMD3<Float>) {
        minBounds = pointwiseMin(minBounds, point)
        maxBounds = pointwiseMax(maxBounds, point)
    }

    mutating func add(_ box: PerryMDLBoundingBox) {
        guard !box.isEmpty else { return }
        add(box.minBounds)
        add(box.maxBounds)
    }

    /// The box, or zeros for an empty one.
    var reported: PerryMDLBoundingBox { isEmpty ? PerryMDLBoundingBox(maxBounds: .zero, minBounds: .zero) : self }

    /// The box of this one's corners transformed.
    func transformed(_ matrix: Matrix4) -> PerryMDLBoundingBox {
        guard !isEmpty else { return self }
        var box = PerryMDLBoundingBox.empty
        for corner in 0..<8 {
            let point = SIMD3(corner & 1 == 0 ? minBounds.x : maxBounds.x, corner & 2 == 0 ? minBounds.y : maxBounds.y,
                              corner & 4 == 0 ? minBounds.z : maxBounds.z)
            box.add(matrix.transform(point))
        }
        return box
    }
}

// MARK: - Matrices

/// A 4x4 float matrix, its sixteen values column by column, as simd lays
/// out matrix_float4x4.
struct Matrix4: Equatable {
    var c: [Float]

    init(_ c: [Float]) { self.c = c }

    static let identity = Matrix4([1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1])

    subscript(row: Int, column: Int) -> Float {
        get { c[column * 4 + row] }
        set { c[column * 4 + row] = newValue }
    }

    static func * (a: Matrix4, b: Matrix4) -> Matrix4 {
        var result = Matrix4([Float](repeating: 0, count: 16))
        for column in 0..<4 {
            for row in 0..<4 {
                var sum: Float = 0
                for k in 0..<4 { sum += a[row, k] * b[k, column] }
                result[row, column] = sum
            }
        }
        return result
    }

    func transform(_ p: SIMD3<Float>) -> SIMD3<Float> {
        SIMD3(self[0, 0] * p.x + self[0, 1] * p.y + self[0, 2] * p.z + self[0, 3],
              self[1, 0] * p.x + self[1, 1] * p.y + self[1, 2] * p.z + self[1, 3],
              self[2, 0] * p.x + self[2, 1] * p.y + self[2, 2] * p.z + self[2, 3])
    }

    static func translation(_ t: SIMD3<Float>) -> Matrix4 {
        var m = identity
        (m[0, 3], m[1, 3], m[2, 3]) = (t.x, t.y, t.z)
        return m
    }

    static func scale(_ s: SIMD3<Float>) -> Matrix4 {
        var m = identity
        (m[0, 0], m[1, 1], m[2, 2]) = (s.x, s.y, s.z)
        return m
    }

    static func rotation(x angle: Float) -> Matrix4 {
        var m = identity
        let (c, s) = (cosf(angle), sinf(angle))
        (m[1, 1], m[1, 2], m[2, 1], m[2, 2]) = (c, -s, s, c)
        return m
    }

    static func rotation(y angle: Float) -> Matrix4 {
        var m = identity
        let (c, s) = (cosf(angle), sinf(angle))
        (m[0, 0], m[0, 2], m[2, 0], m[2, 2]) = (c, s, -s, c)
        return m
    }

    static func rotation(z angle: Float) -> Matrix4 {
        var m = identity
        let (c, s) = (cosf(angle), sinf(angle))
        (m[0, 0], m[0, 1], m[1, 0], m[1, 1]) = (c, -s, s, c)
        return m
    }
}

// MARK: - Vectors

func length(_ v: SIMD3<Float>) -> Float { (v * v).sum().squareRoot() }

func normalize(_ v: SIMD3<Float>) -> SIMD3<Float> {
    let l = length(v)
    return l > 0 ? v / l : v
}

func cross(_ a: SIMD3<Float>, _ b: SIMD3<Float>) -> SIMD3<Float> {
    SIMD3(a.y * b.z - a.z * b.y, a.z * b.x - a.x * b.z, a.x * b.y - a.y * b.x)
}

func dot(_ a: SIMD3<Float>, _ b: SIMD3<Float>) -> Float { (a * b).sum() }
