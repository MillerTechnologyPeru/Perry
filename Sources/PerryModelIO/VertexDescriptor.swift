import CPerryModelIO
import Glibc
import PerryObjCInterop

// Vertex descriptors: MDLVertexAttribute, MDLVertexBufferLayout and
// MDLVertexDescriptor, whose attributes and layouts are NSMutableArrays an
// app changes in place, as on Darwin, with 31 of each to start. The vertex
// formats' sizes and conversions, and the attribute names.

@ObjCConstants
enum ModelIOConstants {
    static let MDLVertexAttributeAnisotropy = "anisotropy"
    static let MDLVertexAttributeBinormal = "binormal"
    static let MDLVertexAttributeBitangent = "bitangent"
    static let MDLVertexAttributeColor = "color"
    static let MDLVertexAttributeEdgeCrease = "edgeCrease"
    static let MDLVertexAttributeJointIndices = "jointIndices"
    static let MDLVertexAttributeJointWeights = "jointWeights"
    static let MDLVertexAttributeNormal = "normal"
    static let MDLVertexAttributeOcclusionValue = "occlusionValue"
    static let MDLVertexAttributePosition = "position"
    static let MDLVertexAttributeShadingBasisU = "shadingBasisU"
    static let MDLVertexAttributeShadingBasisV = "shadingBasisV"
    static let MDLVertexAttributeSubdivisionStencil = "subdivisionStencil"
    static let MDLVertexAttributeTangent = "tangent"
    static let MDLVertexAttributeTextureCoordinate = "textureCoordinate"
    static let MDLVertexAttributeAOCoord = "aoCoord"
    static let MDLVertexAttributeLightmapCoord = "lightmapCoord"
    static let MDLVertexAttributeUnknown = "unknown"

    static let MDLAssetLoadingOptionAssetAtTime = "MDLAssetLoadingOptionAssetAtTime"
    static let MDLAssetLoadingOptionBufferAllocator = "MDLAssetLoadingOptionBufferAllocator"
    static let MDLAssetLoadingOptionComputeBitangents = "MDLAssetLoadingOptionComputeBitangents"
    static let MDLAssetLoadingOptionComputeExtents = "MDLAssetLoadingOptionComputeExtents"
    static let MDLAssetLoadingOptionComputeFaceNormals = "MDLAssetLoadingOptionComputeFaceNormals"
    static let MDLAssetLoadingOptionComputeTangents = "MDLAssetLoadingOptionComputeTangents"
    static let MDLAssetLoadingOptionComputeVertexNormals = "MDLAssetLoadingOptionComputeVertexNormals"
    static let MDLAssetLoadingOptionDefaultUSDColorSpace = "MDLAssetLoadingOptionDefaultUSDColorSpace"
    static let MDLAssetLoadingOptionDisplayNURBSPatches = "MDLAssetLoadingOptionDisplayNURBSPatches"
    static let MDLAssetLoadingOptionNormalSmoothingThreshold = "MDLAssetLoadingOptionNormalSmoothingThreshold"
    static let MDLAssetLoadingOptionPreserveExistingNormals = "MDLAssetLoadingOptionPreserveExistingNormals"
    static let MDLAssetLoadingOptionPreserveIndexing = "MDLAssetLoadingOptionPreserveIndexing"
    static let MDLAssetLoadingOptionPreserveTopology = "MDLAssetLoadingOptionPreserveTopology"
    static let MDLAssetLoadingOptionTangentSmoothingThreshold = "MDLAssetLoadingOptionTangentSmoothingThreshold"
    static let MDLAssetLoadingOptionTangentUVSet = "MDLAssetLoadingOptionTangentUVSet"
    static let MDLAssetLoadingOptionUSDMaterialOverrideDisplayColor = "MDLAssetLoadingOptionUSDMaterialOverrideDisplayColor"
    static let MDLAssetLoadingOptionVertexDescriptor = "MDLAssetLoadingOptionVertexDescriptor"

    static let ModelIOVersionNumber: Double = 1.0

    static let kUTType3dObject = "public.3d-object"
    static let kUTTypeAlembic = "org.alembic.abc"
    static let kUTTypePolygon = "public.polygon-file-format"
    static let kUTTypeStereolithography = "public.standard-tesselated-geometry-format"
    static let kUTTypeUniversalSceneDescription = "com.pixar.universal-scene-description"
    static let kUTTypeUniversalSceneDescriptionMobile = "com.pixar.universal-scene-description-mobile"
}

/// The attribute names, as Model I/O spells them.
enum AttributeName {
    static let position = "position"
    static let normal = "normal"
    static let textureCoordinate = "textureCoordinate"
    static let tangent = "tangent"
    static let bitangent = "bitangent"
    static let color = "color"
}

/// MDLVertexFormat: an element type in its bits above 0xFFFF, a count in its
/// low bits, and the packed 10-10-10-2 formats.
enum VertexFormat {
    static let invalid: UInt = 0
    static let float = 0xC0000 as UInt
    static let float2 = float | 2, float3 = float | 3, float4 = float | 4
    static let half = 0xB0000 as UInt
    static let packed = 0x1000 as UInt

    static func elementType(_ format: UInt) -> UInt { (format >> 16) & 0xF }
    static func count(_ format: UInt) -> Int { Int(format & 0xFFF) }

    /// The bytes one value takes, 0 for an invalid format.
    static func size(_ format: UInt) -> Int {
        if format & packed != 0 { return 4 }
        let count = count(format)
        switch elementType(format) {
        case 1, 2, 3, 4: return count
        case 5, 6, 7, 8, 11: return count * 2
        case 9, 10, 12: return count * 4
        default: return 0
        }
    }

    static func isValid(_ format: UInt) -> Bool { size(format) > 0 && (1...4).contains(count(format)) }

    /// A value read as four floats, the components it lacks from `fill`.
    static func read(_ format: UInt, _ pointer: UnsafeRawPointer, fill: SIMD4<Float> = SIMD4(0, 0, 0, 1)) -> SIMD4<Float> {
        var value = fill
        if format & packed != 0 {
            let word = pointer.loadUnaligned(as: UInt32.self)
            let signed = elementType(format) == 10
            for index in 0..<4 {
                let bits = index < 3 ? 10 : 2
                let raw = (word >> (UInt32(index) * 10)) & ((1 << UInt32(bits)) - 1)
                if signed {
                    let shift = 32 - bits
                    let value32 = Int32(bitPattern: raw << UInt32(shift)) >> Int32(shift)
                    value[index] = max(Float(value32) / Float((1 << (bits - 1)) - 1), -1)
                } else {
                    value[index] = Float(raw) / Float((1 << bits) - 1)
                }
            }
            return value
        }
        for index in 0..<min(count(format), 4) {
            switch elementType(format) {
            case 1: value[index] = Float(pointer.load(fromByteOffset: index, as: UInt8.self))
            case 2: value[index] = Float(pointer.load(fromByteOffset: index, as: Int8.self))
            case 3: value[index] = Float(pointer.load(fromByteOffset: index, as: UInt8.self)) / 255
            case 4: value[index] = max(Float(pointer.load(fromByteOffset: index, as: Int8.self)) / 127, -1)
            case 5: value[index] = Float(pointer.loadUnaligned(fromByteOffset: index * 2, as: UInt16.self))
            case 6: value[index] = Float(pointer.loadUnaligned(fromByteOffset: index * 2, as: Int16.self))
            case 7: value[index] = Float(pointer.loadUnaligned(fromByteOffset: index * 2, as: UInt16.self)) / 65535
            case 8: value[index] = max(Float(pointer.loadUnaligned(fromByteOffset: index * 2, as: Int16.self)) / 32767, -1)
            case 9: value[index] = Float(pointer.loadUnaligned(fromByteOffset: index * 4, as: UInt32.self))
            case 10: value[index] = Float(pointer.loadUnaligned(fromByteOffset: index * 4, as: Int32.self))
            case 11: value[index] = halfToFloat(pointer.loadUnaligned(fromByteOffset: index * 2, as: UInt16.self))
            case 12: value[index] = pointer.loadUnaligned(fromByteOffset: index * 4, as: Float.self)
            default: break
            }
        }
        return value
    }

    /// Writes the first components of `value` in `format`.
    static func write(_ format: UInt, _ pointer: UnsafeMutableRawPointer, _ value: SIMD4<Float>) {
        func clamp(_ v: Float, _ lo: Float, _ hi: Float) -> Float { v.isNaN ? 0 : min(max(v, lo), hi) }
        if format & packed != 0 {
            let signed = elementType(format) == 10
            var word: UInt32 = 0
            for index in 0..<4 {
                let bits = index < 3 ? 10 : 2
                let mask = UInt32((1 << bits) - 1)
                let raw: UInt32
                if signed {
                    let scaled = Int32((clamp(value[index], -1, 1) * Float((1 << (bits - 1)) - 1)).rounded())
                    raw = UInt32(bitPattern: scaled) & mask
                } else {
                    raw = UInt32((clamp(value[index], 0, 1) * Float(mask)).rounded())
                }
                word |= raw << UInt32(index * 10)
            }
            pointer.storeBytes(of: word, as: UInt32.self)
            return
        }
        for index in 0..<min(count(format), 4) {
            let v = value[index]
            switch elementType(format) {
            case 1: pointer.storeBytes(of: UInt8(clamp(v, 0, 255)), toByteOffset: index, as: UInt8.self)
            case 2: pointer.storeBytes(of: Int8(clamp(v, -128, 127)), toByteOffset: index, as: Int8.self)
            case 3: pointer.storeBytes(of: UInt8((clamp(v, 0, 1) * 255).rounded()), toByteOffset: index, as: UInt8.self)
            case 4: pointer.storeBytes(of: Int8((clamp(v, -1, 1) * 127).rounded()), toByteOffset: index, as: Int8.self)
            case 5: pointer.storeBytes(of: UInt16(clamp(v, 0, 65535)), toByteOffset: index * 2, as: UInt16.self)
            case 6: pointer.storeBytes(of: Int16(clamp(v, -32768, 32767)), toByteOffset: index * 2, as: Int16.self)
            case 7: pointer.storeBytes(of: UInt16((clamp(v, 0, 1) * 65535).rounded()), toByteOffset: index * 2, as: UInt16.self)
            case 8: pointer.storeBytes(of: Int16((clamp(v, -1, 1) * 32767).rounded()), toByteOffset: index * 2, as: Int16.self)
            case 9: pointer.storeBytes(of: UInt32(clamp(v, 0, 4294967040)), toByteOffset: index * 4, as: UInt32.self)
            case 10: pointer.storeBytes(of: Int32(clamp(v, -2147483648, 2147483520)), toByteOffset: index * 4, as: Int32.self)
            case 11: pointer.storeBytes(of: floatToHalf(v), toByteOffset: index * 2, as: UInt16.self)
            case 12: pointer.storeBytes(of: v, toByteOffset: index * 4, as: Float.self)
            default: break
            }
        }
    }

    static func halfToFloat(_ bits: UInt16) -> Float {
        let sign = UInt32(bits & 0x8000) << 16
        let exponent = Int((bits >> 10) & 0x1F)
        let mantissa = UInt32(bits & 0x3FF)
        if exponent == 0 {
            let magnitude = Float(mantissa) / 1024 / 16384
            return sign != 0 ? -magnitude : magnitude
        }
        if exponent == 31 { return Float(bitPattern: sign | 0x7F80_0000 | mantissa << 13) }
        return Float(bitPattern: sign | UInt32(exponent - 15 + 127) << 23 | mantissa << 13)
    }

    static func floatToHalf(_ value: Float) -> UInt16 {
        let bits = value.bitPattern
        let sign = UInt16((bits >> 16) & 0x8000)
        if value.isNaN { return sign | 0x7E00 }
        let magnitude = abs(value)
        if magnitude >= 65520 { return sign | 0x7C00 }
        if magnitude < 6.1035156e-05 {
            return sign | UInt16((magnitude * 16_777_216).rounded())    // subnormal: 2^24
        }
        let exponent = Int((bits >> 23) & 0xFF) - 127 + 15
        var mantissa = (bits & 0x7F_FFFF) + 0x1000    // round to nearest
        var e = exponent
        if mantissa & 0x80_0000 != 0 { mantissa = 0; e += 1 }
        return sign | UInt16(e) << 10 | UInt16(mantissa >> 13)
    }
}

@ObjCClass("MDLVertexBufferLayout")
open class MDLVertexBufferLayout: NSObject {
    var strideValue: UInt = 0

    @ObjCMethod("init") public required override init() { super.init() }

    @ObjCMethod("initWithStride:") public init(stride: UInt) {
        strideValue = stride
        super.init()
    }

    @ObjCMethod("stride") func stride() -> UInt { strideValue }
    @ObjCMethod("setStride:") func setStride(_ stride: UInt) { strideValue = stride }

    @ObjCMethod("copyWithZone:") func copy(zone: UnsafeMutableRawPointer?) -> MDLVertexBufferLayout { MDLVertexBufferLayout(stride: strideValue) }
}

@ObjCClass("MDLVertexAttribute")
open class MDLVertexAttribute: NSObject {
    var nameValue = ""
    var formatValue: UInt = 0
    var offsetValue: UInt = 0
    var bufferIndexValue: UInt = 0
    var timeValue: Double = 0
    var initialValue = SIMD4<Float>(0, 0, 0, 1)

    @ObjCMethod("init") public required override init() { super.init() }

    @ObjCMethod("initWithName:format:offset:bufferIndex:")
    public init(name: String?, format: UInt, offset: UInt, bufferIndex: UInt) {
        nameValue = name ?? ""
        formatValue = format
        offsetValue = offset
        bufferIndexValue = bufferIndex
        super.init()
    }

    @ObjCMethod("name") func name() -> String { nameValue }
    @ObjCMethod("setName:") func setName(_ name: String?) { nameValue = name ?? "" }
    @ObjCMethod("format") func format() -> UInt { formatValue }
    @ObjCMethod("setFormat:") func setFormat(_ format: UInt) { formatValue = format }
    @ObjCMethod("offset") func offset() -> UInt { offsetValue }
    @ObjCMethod("setOffset:") func setOffset(_ offset: UInt) { offsetValue = offset }
    @ObjCMethod("bufferIndex") func bufferIndex() -> UInt { bufferIndexValue }
    @ObjCMethod("setBufferIndex:") func setBufferIndex(_ index: UInt) { bufferIndexValue = index }
    @ObjCMethod("time") func time() -> Double { timeValue }
    @ObjCMethod("setTime:") func setTime(_ time: Double) { timeValue = time }
    @ObjCMethod("initializationValue") func initializationValue() -> PerryMDLFloat4 { PerryMDLFloat4(v: initialValue) }
    @ObjCMethod("setInitializationValue:") func setInitializationValue(_ value: PerryMDLFloat4) { initialValue = value.v }

    @ObjCMethod("copyWithZone:") func copy(zone: UnsafeMutableRawPointer?) -> MDLVertexAttribute { duplicate() }

    func duplicate() -> MDLVertexAttribute {
        let copy = MDLVertexAttribute(name: nameValue, format: formatValue, offset: offsetValue, bufferIndex: bufferIndexValue)
        copy.timeValue = timeValue
        copy.initialValue = initialValue
        return copy
    }

    @ObjCMethod("description") func describe() -> String {
        "<MDLVertexAttribute name=\(nameValue) format=0x\(String(formatValue, radix: 16)) offset=\(offsetValue) bufferIndex=\(bufferIndexValue)>"
    }
}

/// An attribute's values, whichever object an app put in the array.
struct Attribute {
    var name: String
    var format: UInt
    var offset: Int
    var bufferIndex: Int
    var time: Double = 0
    var initialValue = SIMD4<Float>(0, 0, 0, 1)

    init(name: String, format: UInt, offset: Int, bufferIndex: Int) {
        (self.name, self.format, self.offset, self.bufferIndex) = (name, format, offset, bufferIndex)
    }

    init(_ object: NSObject) {
        if let attribute = ObjCPeers.peer(of: object.objcObject) as? MDLVertexAttribute {
            name = attribute.nameValue
            format = attribute.formatValue
            offset = Int(attribute.offsetValue)
            bufferIndex = Int(attribute.bufferIndexValue)
            time = attribute.timeValue
            initialValue = attribute.initialValue
        } else {
            name = object.attributeName() ?? ""
            format = object.attributeFormat()
            offset = Int(object.attributeOffset())
            bufferIndex = Int(object.attributeBufferIndex())
        }
    }

    var object: MDLVertexAttribute {
        let made = MDLVertexAttribute(name: name, format: format, offset: UInt(offset), bufferIndex: UInt(bufferIndex))
        made.timeValue = time
        made.initialValue = initialValue
        return made
    }
}

extension NSObject {
    @ObjCMethod("name") func attributeName() -> String?
    @ObjCMethod("format") func attributeFormat() -> UInt
    @ObjCMethod("offset") func attributeOffset() -> UInt
    @ObjCMethod("bufferIndex") func attributeBufferIndex() -> UInt
    @ObjCMethod("stride") func layoutStride() -> UInt
}

@ObjCClass("MDLVertexDescriptor")
open class MDLVertexDescriptor: NSObject {
    static let slots = 31
    var attributeArray: NSMutableArray = MDLVertexDescriptor.freshAttributes()
    var layoutArray: NSMutableArray = MDLVertexDescriptor.freshLayouts()

    static func freshAttributes() -> NSMutableArray { NSMutableArray.with((0..<slots).map { _ in MDLVertexAttribute() }) }
    static func freshLayouts() -> NSMutableArray { NSMutableArray.with((0..<slots).map { _ in MDLVertexBufferLayout() }) }

    @ObjCMethod("init") public required override init() { super.init() }

    @ObjCMethod("initWithVertexDescriptor:") public init(vertexDescriptor: NSObject?) {
        super.init()
        if let vertexDescriptor { load(Layout(vertexDescriptor)) }
    }

    /// A descriptor of `layout`.
    convenience init(_ layout: Layout) {
        self.init()
        load(layout)
    }

    /// Replaces the arrays with new objects of `layout`'s values.
    func load(_ layout: Layout) {
        var attributes = layout.attributes.map { $0.object }
        while attributes.count < Self.slots { attributes.append(MDLVertexAttribute()) }
        var layouts = layout.strides.map { MDLVertexBufferLayout(stride: UInt($0)) }
        while layouts.count < Self.slots { layouts.append(MDLVertexBufferLayout()) }
        attributeArray = NSMutableArray.with(attributes)
        layoutArray = NSMutableArray.with(layouts)
    }

    @ObjCMethod("attributes") func attributes() -> NSMutableArray { attributeArray }
    @ObjCMethod("setAttributes:") func setAttributes(_ array: NSObject?) {
        attributeArray = array.map { NSMutableArray.with($0.unsafeCast(to: NSArray.self).elements) } ?? NSMutableArray.empty()
    }
    @ObjCMethod("layouts") func layouts() -> NSMutableArray { layoutArray }
    @ObjCMethod("setLayouts:") func setLayouts(_ array: NSObject?) {
        layoutArray = array.map { NSMutableArray.with($0.unsafeCast(to: NSArray.self).elements) } ?? NSMutableArray.empty()
    }

    @ObjCMethod("attributeNamed:") func attribute(named name: String?) -> NSObject? {
        guard let name else { return nil }
        return attributeArray.elements.first { Attribute($0).name == name }
    }

    @ObjCMethod("addOrReplaceAttribute:") func addOrReplace(attribute: NSObject?) {
        guard let attribute else { return }
        let added = Attribute(attribute)
        let elements = attributeArray.elements
        if let index = elements.firstIndex(where: { let a = Attribute($0); return a.name == added.name && a.time == added.time }) ??
            elements.firstIndex(where: { Attribute($0).format == VertexFormat.invalid }) {
            attributeArray.replace(at: UInt(index), with: attribute)
        } else {
            attributeArray.add(attribute)
        }
    }

    @ObjCMethod("removeAttributeNamed:") func removeAttribute(named name: String?) {
        guard let name else { return }
        for (index, element) in attributeArray.elements.enumerated() where Attribute(element).name == name {
            attributeArray.replace(at: UInt(index), with: MDLVertexAttribute())
        }
    }

    @ObjCMethod("reset") func reset() {
        attributeArray = Self.freshAttributes()
        layoutArray = Self.freshLayouts()
    }

    /// Each buffer's attributes one after another, in the array's order.
    @ObjCMethod("setPackedOffsets") func setPackedOffsets() {
        var next: [UInt: UInt] = [:]
        for element in attributeArray.elements {
            let attribute = Attribute(element)
            guard VertexFormat.isValid(attribute.format) else { continue }
            let offset = next[UInt(attribute.bufferIndex), default: 0]
            element.setAttributeOffset(offset)
            next[UInt(attribute.bufferIndex)] = offset + UInt(VertexFormat.size(attribute.format))
        }
    }

    /// Each layout's stride the end of its last attribute.
    @ObjCMethod("setPackedStrides") func setPackedStrides() {
        var ends: [Int: Int] = [:]
        for element in attributeArray.elements {
            let attribute = Attribute(element)
            guard VertexFormat.isValid(attribute.format) else { continue }
            ends[attribute.bufferIndex] = max(ends[attribute.bufferIndex, default: 0], attribute.offset + VertexFormat.size(attribute.format))
        }
        for (index, layout) in layoutArray.elements.enumerated() {
            if let end = ends[index] { layout.setLayoutStride(UInt(end)) }
        }
    }

    @ObjCMethod("copyWithZone:") func copy(zone: UnsafeMutableRawPointer?) -> MDLVertexDescriptor { MDLVertexDescriptor(Layout(self)) }

    @ObjCMethod("description") func describe() -> String {
        let layout = Layout(self)
        return "<MDLVertexDescriptor attributes: " + layout.attributes.filter { VertexFormat.isValid($0.format) }
            .map { "\($0.name) 0x\(String($0.format, radix: 16)) +\($0.offset) [\($0.bufferIndex)]" }.joined(separator: ", ")
            + "; strides: \(layout.strides.filter { $0 > 0 })>"
    }
}

extension NSObject {
    @ObjCMethod("setOffset:") func setAttributeOffset(_ offset: UInt)
    @ObjCMethod("setStride:") func setLayoutStride(_ stride: UInt)
}

/// A descriptor's values: every attribute (valid or not) and every stride.
struct Layout {
    var attributes: [Attribute]
    var strides: [Int]

    init(attributes: [Attribute], strides: [Int]) {
        self.attributes = attributes
        self.strides = strides
    }

    /// The values of any vertex descriptor object.
    init(_ object: NSObject) {
        if let descriptor = ObjCPeers.peer(of: object.objcObject) as? MDLVertexDescriptor {
            attributes = descriptor.attributeArray.elements.map(Attribute.init)
            strides = descriptor.layoutArray.elements.map { Int($0.layoutStride()) }
        } else {
            attributes = object.descriptorAttributes().map { $0.unsafeCast(to: NSArray.self).elements.map(Attribute.init) } ?? []
            strides = object.descriptorLayouts().map { $0.unsafeCast(to: NSArray.self).elements.map { Int($0.layoutStride()) } } ?? []
        }
    }

    /// The valid attributes.
    var valid: [Attribute] { attributes.filter { VertexFormat.isValid($0.format) } }

    func attribute(named name: String) -> Attribute? { valid.first { $0.name == name } }

    func stride(_ buffer: Int) -> Int { buffer < strides.count ? strides[buffer] : 0 }

    /// The buffers the valid attributes are in, in order, and how many there are.
    var bufferCount: Int { (valid.map(\.bufferIndex).max() ?? -1) + 1 }

    /// Position, normal and texture coordinate interleaved in buffer 0, as
    /// the generators make them.
    static let standard = Layout(attributes: [
        Attribute(name: AttributeName.position, format: VertexFormat.float3, offset: 0, bufferIndex: 0),
        Attribute(name: AttributeName.normal, format: VertexFormat.float3, offset: 12, bufferIndex: 0),
        Attribute(name: AttributeName.textureCoordinate, format: VertexFormat.float2, offset: 24, bufferIndex: 0),
    ], strides: [32])
}

extension NSObject {
    @ObjCMethod("attributes") func descriptorAttributes() -> NSObject?
    @ObjCMethod("layouts") func descriptorLayouts() -> NSObject?
}
