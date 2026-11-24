import Glibc
import PerryInterface
import PerryObjCInterop

// libPerryModelIO: the provider for Model I/O. Its objects are peers: each
// Model I/O object is a Swift object whose stored properties are its state.
// Meshes keep their vertices and indices in NSData, through
// MDLMeshBufferData, or in whatever buffers another allocator (MetalKit's)
// hands out, which are read through their maps. Assets load and export
// Wavefront OBJ files; other formats fail with an error.

private let libobjc = "/usr/lib/libobjc.A.dylib"
private let coreGraphics = "/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics"

func providerWillStart(_ info: perry_startup_info) -> Bool {
    guard info.version >= 2, let lookup = info.lookup_symbol else { return false }
    func symbol(_ library: String?, _ name: String) -> UnsafeMutableRawPointer? {
        name.withCString { name in
            guard let library else { return lookup(nil, name) }
            return library.withCString { lookup($0, name) }
        }
    }
    guard ObjCRuntime.load({ symbol(libobjc, $0) }) else {
        modelIOFatal("Model I/O needs libPerryobjc, which is missing or incomplete")
    }
    Runtime.protocolName = symbol(libobjc, "_protocol_getName").map { unsafeBitCast($0, to: Runtime.ProtocolName.self) }
    Runtime.lookup = { library, name in symbol(library, name) }
    return true
}

func modelIOFatal(_ message: String) -> Never {
    let line = "perry: ModelIO: *** \(message)\n"
    line.withCString { _ = write(2, $0, strlen($0)) }
    abort()
}

func modelIOWarning(_ message: String) {
    let line = "perry: ModelIO: \(message)\n"
    line.withCString { _ = write(2, $0, strlen($0)) }
}

/// Functions of other libraries, looked up when first needed.
enum Runtime {
    typealias ProtocolName = @convention(c) (UnsafeMutableRawPointer?) -> UnsafePointer<CChar>?
    typealias ColorCreate = @convention(c) (Double, Double, Double, Double) -> UnsafeMutableRawPointer?
    typealias ColorComponents = @convention(c) (UnsafeMutableRawPointer?) -> UnsafePointer<Double>?
    typealias ColorCount = @convention(c) (UnsafeMutableRawPointer?) -> Int

    nonisolated(unsafe) static var protocolName: ProtocolName?
    nonisolated(unsafe) static var lookup: ((String?, String) -> UnsafeMutableRawPointer?)?

    /// A protocol's name.
    static func name(ofProtocol pointer: UnsafeMutableRawPointer?) -> String? {
        guard let pointer, let name = protocolName?(pointer) else { return nil }
        return String(cString: name)
    }

    /// CoreGraphics' functions for material colors, looked up once.
    nonisolated(unsafe) static let colorFunctions: (create: ColorCreate, components: ColorComponents, count: ColorCount)? = {
        guard let lookup,
              let create = lookup(coreGraphics, "_CGColorCreateSRGB") ?? lookup(coreGraphics, "_CGColorCreateGenericRGB"),
              let components = lookup(coreGraphics, "_CGColorGetComponents"),
              let count = lookup(coreGraphics, "_CGColorGetNumberOfComponents") else { return nil }
        return (unsafeBitCast(create, to: ColorCreate.self), unsafeBitCast(components, to: ColorComponents.self),
                unsafeBitCast(count, to: ColorCount.self))
    }()
}

/// Model I/O's protocols, and the classes that adopt them, so that Swift's
/// casts (an NSArray of `any MDLMeshBuffer`) and -conformsToProtocol: find
/// them. A protocol an image already declared is used as it is.
func providerDidStart(_ info: perry_startup_info) {
    let protocols: [(name: String, adopts: [String], classes: [String])] = [
        ("MDLNamed", [], ["MDLObject", "MDLSubmesh", "MDLMaterial", "MDLMaterialProperty", "MDLScatteringFunction"]),
        ("MDLComponent", [], []),
        ("MDLTransformComponent", ["MDLComponent"], ["MDLTransform"]),
        ("MDLObjectContainerComponent", ["MDLComponent"], ["MDLObjectContainer"]),
        ("MDLMeshBuffer", [], ["MDLMeshBufferData"]),
        ("MDLMeshBufferAllocator", [], ["MDLMeshBufferDataAllocator"]),
        ("MDLMeshBufferZone", [], ["MDLMeshBufferZoneDefault"]),
    ]
    for entry in protocols {
        if ObjCRuntime.protocolObject(entry.name) == nil {
            ObjCRuntime.defineProtocol(named: entry.name, adopting: entry.adopts, methods: [])
        }
        for name in entry.classes { ObjCRuntime.addProtocol(named: entry.name, to: ObjCClass(named: name)) }
    }
}
