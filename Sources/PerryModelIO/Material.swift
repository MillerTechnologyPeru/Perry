import CPerryModelIO
import Glibc
import PerryObjCInterop

// Materials: MDLMaterialProperty's values, MDLScatteringFunction and its
// physically plausible kind, whose properties a material lists, the
// texture sampler and filter, and MDLMaterial.

/// MDLMaterialSemantic.
enum Semantic {
    static let baseColor: UInt = 0, subsurface: UInt = 1, metallic: UInt = 2, specular: UInt = 3, specularExponent: UInt = 4
    static let specularTint: UInt = 5, roughness: UInt = 6, anisotropic: UInt = 7, anisotropicRotation: UInt = 8, sheen: UInt = 9
    static let sheenTint: UInt = 10, clearcoat: UInt = 11, clearcoatGloss: UInt = 12, emission: UInt = 13, bump: UInt = 14
    static let opacity: UInt = 15, interfaceIndexOfRefraction: UInt = 16, materialIndexOfRefraction: UInt = 17
    static let objectSpaceNormal: UInt = 18, tangentSpaceNormal: UInt = 19, displacement: UInt = 20, displacementScale: UInt = 21
    static let ambientOcclusion: UInt = 22, ambientOcclusionScale: UInt = 23, none: UInt = 0x8000, userDefined: UInt = 0x8001
}

/// MDLMaterialPropertyType.
enum PropertyType {
    static let none: UInt = 0, string: UInt = 1, url: UInt = 2, texture: UInt = 3, color: UInt = 4, float: UInt = 5
    static let float2: UInt = 6, float3: UInt = 7, float4: UInt = 8, matrix44: UInt = 9, buffer: UInt = 10
}

/// CoreGraphics' colors, through its functions.
enum Colors {
    typealias Retain = @convention(c) (UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer?
    typealias Release = @convention(c) (UnsafeMutableRawPointer?) -> Void

    nonisolated(unsafe) static let retainFunction: Retain? = Runtime.lookup?(
        "/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics", "_CGColorRetain").map { unsafeBitCast($0, to: Retain.self) }
    nonisolated(unsafe) static let releaseFunction: Release? = Runtime.lookup?(
        "/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics", "_CGColorRelease").map { unsafeBitCast($0, to: Release.self) }

    /// A new sRGB color, +1.
    static func make(_ c: SIMD4<Float>) -> UnsafeMutableRawPointer? {
        Runtime.colorFunctions?.create(Double(c.x), Double(c.y), Double(c.z), Double(c.w))
    }

    /// A color's components, as RGBA.
    static func components(_ color: UnsafeMutableRawPointer) -> SIMD4<Float>? {
        guard let functions = Runtime.colorFunctions, let values = functions.components(color) else { return nil }
        switch functions.count(color) {
        case 2: return SIMD4(Float(values[0]), Float(values[0]), Float(values[0]), Float(values[1]))
        case 4...: return SIMD4(Float(values[0]), Float(values[1]), Float(values[2]), Float(values[3]))
        default: return nil
        }
    }
}

@ObjCClass("MDLMaterialProperty")
open class MDLMaterialProperty: NSObject {
    var semanticValue: UInt = 0
    var typeValue: UInt = PropertyType.none
    var nameValue = ""
    var stringValue: String?
    var urlValue: NSObject?
    var samplerValue: NSObject?
    var vector = SIMD4<Float>(repeating: 0)
    var matrixValue = Matrix4.identity
    var luminanceValue: Float = 0
    /// The CGColor, +1, made from `vector` when first asked for.
    var colorObject: UnsafeMutableRawPointer?

    @ObjCMethod("init") public required override init() { super.init() }

    @ObjCMethod("initWithName:semantic:") public init(name: String?, semantic: UInt) {
        nameValue = name ?? ""
        semanticValue = semantic
        super.init()
    }

    @ObjCMethod("initWithName:semantic:float:") public init(name: String?, semantic: UInt, float: Float) {
        (nameValue, semanticValue, typeValue, vector) = (name ?? "", semantic, PropertyType.float, SIMD4(float, 0, 0, 0))
        super.init()
    }

    @ObjCMethod("initWithName:semantic:float2:") public init(name: String?, semantic: UInt, float2: PerryMDLFloat2) {
        (nameValue, semanticValue, typeValue, vector) = (name ?? "", semantic, PropertyType.float2, SIMD4(float2.v.x, float2.v.y, 0, 0))
        super.init()
    }

    @ObjCMethod("initWithName:semantic:float3:") public init(name: String?, semantic: UInt, float3: PerryMDLFloat3) {
        (nameValue, semanticValue, typeValue, vector) = (name ?? "", semantic, PropertyType.float3, SIMD4(float3.v.x, float3.v.y, float3.v.z, 0))
        super.init()
    }

    @ObjCMethod("initWithName:semantic:float4:") public init(name: String?, semantic: UInt, float4: PerryMDLFloat4) {
        (nameValue, semanticValue, typeValue, vector) = (name ?? "", semantic, PropertyType.float4, float4.v)
        super.init()
    }

    @ObjCMethod("initWithName:semantic:matrix4x4:") public init(name: String?, semantic: UInt, matrix4x4: PerryMDLFloat4x4) {
        (nameValue, semanticValue, typeValue, matrixValue) = (name ?? "", semantic, PropertyType.matrix44, matrix4x4.matrix)
        super.init()
    }

    @ObjCMethod("initWithName:semantic:URL:") public init(name: String?, semantic: UInt, url: NSObject?) {
        (nameValue, semanticValue, typeValue, urlValue) = (name ?? "", semantic, PropertyType.url, url)
        super.init()
    }

    @ObjCMethod("initWithName:semantic:string:") public init(name: String?, semantic: UInt, string: String?) {
        (nameValue, semanticValue, typeValue, stringValue) = (name ?? "", semantic, PropertyType.string, string)
        super.init()
    }

    @ObjCMethod("initWithName:semantic:textureSampler:") public init(name: String?, semantic: UInt, textureSampler: NSObject?) {
        (nameValue, semanticValue, typeValue, samplerValue) = (name ?? "", semantic, PropertyType.texture, textureSampler)
        super.init()
    }

    @ObjCMethod("initWithName:semantic:color:") public init(name: String?, semantic: UInt, color: UnsafeMutableRawPointer?) {
        (nameValue, semanticValue, typeValue) = (name ?? "", semantic, PropertyType.color)
        super.init()
        setColor(color)
    }

    /// A color property of `rgba`.
    init(name: String, semantic: UInt, rgba: SIMD4<Float>) {
        (nameValue, semanticValue, typeValue, vector) = (name, semantic, PropertyType.color, rgba)
        super.init()
    }

    deinit {
        if let colorObject { Colors.releaseFunction?(colorObject) }
    }

    @ObjCMethod("setProperties:") func setProperties(_ other: MDLMaterialProperty?) {
        guard let other else { return }
        semanticValue = other.semanticValue
        typeValue = other.typeValue
        nameValue = other.nameValue
        stringValue = other.stringValue
        urlValue = other.urlValue
        samplerValue = other.samplerValue
        vector = other.vector
        matrixValue = other.matrixValue
        luminanceValue = other.luminanceValue
        setColorObject(nil)
    }

    func setColorObject(_ color: UnsafeMutableRawPointer?) {
        if let colorObject { Colors.releaseFunction?(colorObject) }
        colorObject = color
    }

    @ObjCMethod("semantic") func semantic() -> UInt { semanticValue }
    @ObjCMethod("setSemantic:") func setSemantic(_ value: UInt) { semanticValue = value }
    @ObjCMethod("type") func type() -> UInt { typeValue }
    @ObjCMethod("setType:") func setType(_ value: UInt) { typeValue = value }
    @ObjCMethod("name") func name() -> String { nameValue }
    @ObjCMethod("setName:") func setName(_ value: String?) { nameValue = value ?? "" }

    @ObjCMethod("stringValue") func string() -> String? { stringValue }
    @ObjCMethod("setStringValue:") func setString(_ value: String?) { stringValue = value; typeValue = PropertyType.string }

    @ObjCMethod("URLValue") func url() -> NSObject? {
        if urlValue == nil, typeValue == PropertyType.string, let stringValue, let base = baseURL {
            return NSURL.file(path: base + "/" + stringValue)
        }
        return urlValue
    }

    @ObjCMethod("setURLValue:") func setURL(_ value: NSObject?) { urlValue = value; typeValue = PropertyType.url }

    /// The directory of the file the material came from, for its textures.
    var baseURL: String?

    @ObjCMethod("textureSamplerValue") func textureSampler() -> NSObject? { samplerValue }
    @ObjCMethod("setTextureSamplerValue:") func setTextureSampler(_ value: NSObject?) { samplerValue = value; typeValue = PropertyType.texture }

    @ObjCMethod("color") func color() -> UnsafeMutableRawPointer? {
        guard typeValue == PropertyType.color else { return nil }
        if colorObject == nil { colorObject = Colors.make(vector) }
        return colorObject
    }

    @ObjCMethod("setColor:") func setColor(_ color: UnsafeMutableRawPointer?) {
        typeValue = PropertyType.color
        guard let color else {
            setColorObject(nil)
            return
        }
        if let components = Colors.components(color) { vector = components }
        setColorObject(Colors.retainFunction?(color))
    }

    /// The numeric values; a color's are its color's, not these.
    var number: SIMD4<Float> { typeValue == PropertyType.color ? .zero : vector }

    @ObjCMethod("floatValue") func floatValue() -> Float { number.x }
    @ObjCMethod("setFloatValue:") func setFloatValue(_ v: Float) { vector = SIMD4(v, 0, 0, 0); typeValue = PropertyType.float }
    @ObjCMethod("float2Value") func float2Value() -> PerryMDLFloat2 { PerryMDLFloat2(v: SIMD2(number.x, number.y)) }
    @ObjCMethod("setFloat2Value:") func setFloat2Value(_ v: PerryMDLFloat2) { vector = SIMD4(v.v.x, v.v.y, 0, 0); typeValue = PropertyType.float2 }
    @ObjCMethod("float3Value") func float3Value() -> PerryMDLFloat3 { PerryMDLFloat3(v: SIMD3(number.x, number.y, number.z)) }
    @ObjCMethod("setFloat3Value:") func setFloat3Value(_ v: PerryMDLFloat3) { vector = SIMD4(v.v.x, v.v.y, v.v.z, 0); typeValue = PropertyType.float3 }
    @ObjCMethod("float4Value") func float4Value() -> PerryMDLFloat4 { PerryMDLFloat4(v: number) }
    @ObjCMethod("setFloat4Value:") func setFloat4Value(_ v: PerryMDLFloat4) { vector = v.v; typeValue = PropertyType.float4 }
    @ObjCMethod("matrix4x4") func matrix4x4() -> PerryMDLFloat4x4 { PerryMDLFloat4x4(matrixValue) }
    @ObjCMethod("setMatrix4x4:") func setMatrix4x4(_ v: PerryMDLFloat4x4) { matrixValue = v.matrix; typeValue = PropertyType.matrix44 }
    @ObjCMethod("luminance") func luminance() -> Float { luminanceValue }
    @ObjCMethod("setLuminance:") func setLuminance(_ v: Float) { luminanceValue = v }

    @ObjCMethod("copyWithZone:") func copy(zone: UnsafeMutableRawPointer?) -> MDLMaterialProperty {
        let copy = MDLMaterialProperty(name: nameValue, semantic: semanticValue)
        copy.setProperties(self)
        copy.baseURL = baseURL
        return copy
    }

    /// The values as an OBJ material's: a color's or a float3's, or a float.
    var rgb: SIMD3<Float> { SIMD3(vector.x, vector.y, vector.z) }
}

@ObjCClass("MDLTextureFilter")
open class MDLTextureFilter: NSObject {
    var modes: [UInt] = [0, 0, 0, 0, 0, 0]

    @ObjCMethod("init") public required override init() { super.init() }

    @ObjCMethod("sWrapMode") func sWrapMode() -> UInt { modes[0] }
    @ObjCMethod("setSWrapMode:") func setSWrapMode(_ v: UInt) { modes[0] = v }
    @ObjCMethod("tWrapMode") func tWrapMode() -> UInt { modes[1] }
    @ObjCMethod("setTWrapMode:") func setTWrapMode(_ v: UInt) { modes[1] = v }
    @ObjCMethod("rWrapMode") func rWrapMode() -> UInt { modes[2] }
    @ObjCMethod("setRWrapMode:") func setRWrapMode(_ v: UInt) { modes[2] = v }
    @ObjCMethod("minFilter") func minFilter() -> UInt { modes[3] }
    @ObjCMethod("setMinFilter:") func setMinFilter(_ v: UInt) { modes[3] = v }
    @ObjCMethod("magFilter") func magFilter() -> UInt { modes[4] }
    @ObjCMethod("setMagFilter:") func setMagFilter(_ v: UInt) { modes[4] = v }
    @ObjCMethod("mipFilter") func mipFilter() -> UInt { modes[5] }
    @ObjCMethod("setMipFilter:") func setMipFilter(_ v: UInt) { modes[5] = v }
}

@ObjCClass("MDLTextureSampler")
open class MDLTextureSampler: NSObject {
    var textureObject: NSObject?
    var filterObject: NSObject?
    var transformObject: NSObject?

    @ObjCMethod("init") public required override init() { super.init() }

    @ObjCMethod("texture") func texture() -> NSObject? { textureObject }
    @ObjCMethod("setTexture:") func setTexture(_ v: NSObject?) { textureObject = v }
    @ObjCMethod("hardwareFilter") func hardwareFilter() -> NSObject? { filterObject }
    @ObjCMethod("setHardwareFilter:") func setHardwareFilter(_ v: NSObject?) { filterObject = v }
    @ObjCMethod("transform") func transform() -> NSObject? { transformObject }
    @ObjCMethod("setTransform:") func setTransform(_ v: NSObject?) { transformObject = v }
}

@ObjCClass("MDLScatteringFunction")
open class MDLScatteringFunction: NSObject {
    var nameValue = ""
    let baseColorProperty = MDLMaterialProperty(name: "baseColor", semantic: Semantic.baseColor, rgba: SIMD4(1, 1, 1, 1))
    let emissionProperty = MDLMaterialProperty(name: "emission", semantic: Semantic.emission, rgba: SIMD4(0, 0, 0, 1))
    let specularProperty = MDLMaterialProperty(name: "specular", semantic: Semantic.specular, float: 0)
    let materialIORProperty = MDLMaterialProperty(name: "materialIndexOfRefraction", semantic: Semantic.materialIndexOfRefraction, float: 1)
    let interfaceIORProperty = MDLMaterialProperty(name: "interfaceIndexOfRefraction", semantic: Semantic.interfaceIndexOfRefraction, float: 1)
    let normalProperty = MDLMaterialProperty(name: "normal", semantic: Semantic.tangentSpaceNormal, float3: PerryMDLFloat3(SIMD3(0, 0, 1)))
    let occlusionProperty = MDLMaterialProperty(name: "ambientOcclusion", semantic: Semantic.ambientOcclusion, float: 0)
    let occlusionScaleProperty = MDLMaterialProperty(name: "ambientOcclusionScale", semantic: Semantic.ambientOcclusionScale, float: 1)

    @ObjCMethod("init") public required override init() { super.init() }

    @ObjCMethod("name") func name() -> String { nameValue }
    @ObjCMethod("setName:") func setName(_ v: String?) { nameValue = v ?? "" }
    @ObjCMethod("baseColor") func baseColor() -> MDLMaterialProperty { baseColorProperty }
    @ObjCMethod("emission") func emission() -> MDLMaterialProperty { emissionProperty }
    @ObjCMethod("specular") func specular() -> MDLMaterialProperty { specularProperty }
    @ObjCMethod("materialIndexOfRefraction") func materialIndexOfRefraction() -> MDLMaterialProperty { materialIORProperty }
    @ObjCMethod("interfaceIndexOfRefraction") func interfaceIndexOfRefraction() -> MDLMaterialProperty { interfaceIORProperty }
    @ObjCMethod("normal") func normal() -> MDLMaterialProperty { normalProperty }
    @ObjCMethod("ambientOcclusion") func ambientOcclusion() -> MDLMaterialProperty { occlusionProperty }
    @ObjCMethod("ambientOcclusionScale") func ambientOcclusionScale() -> MDLMaterialProperty { occlusionScaleProperty }

    /// The properties a material of this function starts with.
    var materialProperties: [MDLMaterialProperty] {
        [baseColorProperty, emissionProperty, materialIORProperty, interfaceIORProperty, occlusionProperty, occlusionScaleProperty]
    }
}

@ObjCClass("MDLPhysicallyPlausibleScatteringFunction")
open class MDLPhysicallyPlausibleScatteringFunction: MDLScatteringFunction {
    let subsurfaceProperty = MDLMaterialProperty(name: "subsurface", semantic: Semantic.subsurface, float: 0)
    let metallicProperty = MDLMaterialProperty(name: "metallic", semantic: Semantic.metallic, float: 0)
    let specularAmountProperty = MDLMaterialProperty(name: "specular", semantic: Semantic.specular, float: 0)
    let specularTintProperty = MDLMaterialProperty(name: "specularTint", semantic: Semantic.specularTint, float: 0)
    let roughnessProperty = MDLMaterialProperty(name: "roughness", semantic: Semantic.roughness, float: 0.9)
    let anisotropicProperty = MDLMaterialProperty(name: "anisotropic", semantic: Semantic.anisotropic, float: 0)
    let anisotropicRotationProperty = MDLMaterialProperty(name: "anisotropicRotation", semantic: Semantic.anisotropicRotation, float: 0)
    let sheenProperty = MDLMaterialProperty(name: "sheen", semantic: Semantic.sheen, float: 0.05)
    let sheenTintProperty = MDLMaterialProperty(name: "sheenTint", semantic: Semantic.sheenTint, float: 0)
    let clearcoatProperty = MDLMaterialProperty(name: "clearcoat", semantic: Semantic.clearcoat, float: 0)
    let clearcoatGlossProperty = MDLMaterialProperty(name: "clearcoatGloss", semantic: Semantic.clearcoatGloss, float: 0)

    @ObjCMethod("version") func version() -> Int { 1 }
    @ObjCMethod("subsurface") func subsurface() -> MDLMaterialProperty { subsurfaceProperty }
    @ObjCMethod("metallic") func metallic() -> MDLMaterialProperty { metallicProperty }
    @ObjCMethod("specularAmount") func specularAmount() -> MDLMaterialProperty { specularAmountProperty }
    @ObjCMethod("specularTint") func specularTint() -> MDLMaterialProperty { specularTintProperty }
    @ObjCMethod("roughness") func roughness() -> MDLMaterialProperty { roughnessProperty }
    @ObjCMethod("anisotropic") func anisotropic() -> MDLMaterialProperty { anisotropicProperty }
    @ObjCMethod("anisotropicRotation") func anisotropicRotation() -> MDLMaterialProperty { anisotropicRotationProperty }
    @ObjCMethod("sheen") func sheen() -> MDLMaterialProperty { sheenProperty }
    @ObjCMethod("sheenTint") func sheenTint() -> MDLMaterialProperty { sheenTintProperty }
    @ObjCMethod("clearcoat") func clearcoat() -> MDLMaterialProperty { clearcoatProperty }
    @ObjCMethod("clearcoatGloss") func clearcoatGloss() -> MDLMaterialProperty { clearcoatGlossProperty }

    override var materialProperties: [MDLMaterialProperty] {
        [subsurfaceProperty, metallicProperty, specularAmountProperty, specularTintProperty, roughnessProperty, anisotropicRotationProperty,
         sheenProperty, sheenTintProperty, clearcoatProperty, clearcoatGlossProperty] + super.materialProperties
    }
}

@ObjCClass("MDLMaterial")
open class MDLMaterial: NSObject {
    var nameValue = ""
    var function: MDLScatteringFunction = MDLScatteringFunction()
    var base: MDLMaterial?
    var list: NSMutableArray = NSMutableArray.empty()
    var face: UInt = 0

    @ObjCMethod("init") public required override init() { super.init() }

    @ObjCMethod("initWithName:scatteringFunction:") public init(name: String?, scatteringFunction: NSObject?) {
        nameValue = name ?? ""
        if let scatteringFunction, let own = ObjCPeers.peer(of: scatteringFunction.objcObject) as? MDLScatteringFunction {
            function = own
        }
        super.init()
        list = NSMutableArray.with(function.materialProperties)
    }

    /// A physically plausible material, as the generators give meshes.
    convenience init(physicallyPlausible name: String) {
        self.init(name: name, scatteringFunction: MDLPhysicallyPlausibleScatteringFunction())
    }

    var properties: [MDLMaterialProperty] { list.elements.compactMap { ObjCPeers.peer(of: $0.objcObject) as? MDLMaterialProperty } }

    @ObjCMethod("setProperty:") func setProperty(_ property: NSObject?) {
        guard let property else { return }
        let name = (ObjCPeers.peer(of: property.objcObject) as? MDLMaterialProperty)?.nameValue
        if let index = properties.firstIndex(where: { $0.nameValue == name }) {
            list.replace(at: UInt(index), with: property)
        } else {
            list.add(property)
        }
    }

    @ObjCMethod("removeProperty:") func removeProperty(_ property: NSObject?) { if let property { list.removeIdentical(property) } }
    @ObjCMethod("removeAllProperties") func removeAllProperties() { list.removeAll() }

    @ObjCMethod("propertyNamed:") func property(named name: String?) -> MDLMaterialProperty? {
        properties.first { $0.nameValue == name } ?? base?.property(named: name)
    }

    @ObjCMethod("propertyWithSemantic:") func property(withSemantic semantic: UInt) -> MDLMaterialProperty? {
        properties.last { $0.semanticValue == semantic } ?? base?.property(withSemantic: semantic)
    }

    @ObjCMethod("scatteringFunction") func scatteringFunction() -> MDLScatteringFunction { function }
    @ObjCMethod("name") func name() -> String { nameValue }
    @ObjCMethod("setName:") func setName(_ v: String?) { nameValue = v ?? "" }
    @ObjCMethod("baseMaterial") func baseMaterial() -> MDLMaterial? { base }
    @ObjCMethod("setBaseMaterial:") func setBaseMaterial(_ v: MDLMaterial?) { base = v }
    @ObjCMethod("count") func count() -> UInt { list.count() }
    @ObjCMethod("materialFace") func materialFace() -> UInt { face }
    @ObjCMethod("setMaterialFace:") func setMaterialFace(_ v: UInt) { face = v }

    @ObjCMethod("objectAtIndexedSubscript:") func object(atIndexedSubscript index: UInt) -> NSObject? {
        index < list.count() ? list.object(at: index) : nil
    }

    @ObjCMethod("objectForKeyedSubscript:") func object(forKeyedSubscript name: String?) -> MDLMaterialProperty? { property(named: name) }

    @ObjCMethod("countByEnumeratingWithState:objects:count:")
    func countByEnumerating(state: UnsafeMutableRawPointer?, objects: UnsafeMutableRawPointer?, count: UInt) -> UInt {
        list.sendCountByEnumerating(state: state, objects: objects, count: count)
    }

    @ObjCMethod("copyWithZone:") func copy(zone: UnsafeMutableRawPointer?) -> MDLMaterial {
        let copy = MDLMaterial(name: nameValue, scatteringFunction: function)
        copy.list = NSMutableArray.with(list.elements)
        copy.base = base
        copy.face = face
        return copy
    }
}
