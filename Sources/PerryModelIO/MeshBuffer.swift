import Glibc
import PerryObjCInterop

// Mesh buffers: MDLMeshBufferData, whose bytes are an NSMutableData, its
// allocator and zone, and MDLMeshBufferMap. Meshes read and write any
// object that is an MDLMeshBuffer (MetalKit's, over Metal buffers) through
// its map, and make new buffers through their allocator.

/// MDLMeshBufferType.
enum BufferType {
    static let vertex: UInt = 1
    static let index: UInt = 2
}

@ObjCClass("MDLMeshBufferMap")
open class MDLMeshBufferMap: NSObject {
    var pointer: UnsafeMutableRawPointer?
    var deallocator: ObjCBlock?
    /// What the bytes belong to, kept while the map is.
    var owner: AnyObject?

    @ObjCMethod("init") public required override init() { super.init() }

    @ObjCMethod("initWithBytes:deallocator:") public init(bytes: UnsafeMutableRawPointer?, deallocator: ObjCBlock?) {
        pointer = bytes
        self.deallocator = deallocator
        super.init()
    }

    init(bytes: UnsafeMutableRawPointer?, owner: AnyObject) {
        pointer = bytes
        self.owner = owner
        super.init()
    }

    deinit {
        if let deallocator {
            typealias Invoke = @convention(c) (UnsafeMutableRawPointer?) -> Void
            deallocator.function(as: Invoke.self)(deallocator.object)
        }
    }

    @ObjCMethod("bytes") func bytes() -> UnsafeMutableRawPointer? { pointer }
}

@ObjCClass("MDLMeshBufferZoneDefault")
open class MDLMeshBufferZoneDefault: NSObject {
    var capacityValue: UInt = 0
    var allocatorObject: NSObject?

    @ObjCMethod("init") public required override init() { super.init() }

    init(capacity: UInt, allocator: NSObject?) {
        capacityValue = capacity
        allocatorObject = allocator
        super.init()
    }

    @ObjCMethod("capacity") func capacity() -> UInt { capacityValue }
    @ObjCMethod("allocator") func allocator() -> NSObject? { allocatorObject }
}

@ObjCClass("MDLMeshBufferData")
open class MDLMeshBufferData: NSObject {
    var typeValue: UInt = BufferType.vertex
    var storage: NSMutableData = NSMutableData.make(count: 0)
    var allocatorObject: NSObject?
    var zoneObject: NSObject?

    @ObjCMethod("init") public required override init() { super.init() }

    @ObjCMethod("initWithType:length:") public init(type: UInt, length: UInt) {
        typeValue = type
        storage = NSMutableData.make(count: Int(length))
        super.init()
    }

    @ObjCMethod("initWithType:data:") public init(type: UInt, data: NSObject?) {
        typeValue = type
        let copy = data.map { $0.unsafeCast(to: NSData.self) }
        let count = Int(copy?.length() ?? 0)
        storage = copy.flatMap { source in source.bytes().map { NSMutableData.make(UnsafeRawBufferPointer(start: $0, count: count)) } }
            ?? NSMutableData.make(count: count)
        super.init()
    }

    /// A buffer of `bytes`.
    init(type: UInt, bytes: UnsafeRawBufferPointer, allocator: NSObject?) {
        typeValue = type
        storage = NSMutableData.make(bytes)
        allocatorObject = allocator
        super.init()
    }

    var mutableBytes: UnsafeMutableRawPointer? { storage.mutableBytes() }
    var count: Int { Int(storage.length()) }

    @ObjCMethod("data") func data() -> NSObject { storage }
    @ObjCMethod("length") func length() -> UInt { storage.length() }
    @ObjCMethod("type") func type() -> UInt { typeValue }
    @ObjCMethod("map") func map() -> MDLMeshBufferMap { MDLMeshBufferMap(bytes: mutableBytes, owner: self) }

    @ObjCMethod("allocator") func allocator() -> NSObject {
        if let allocatorObject { return allocatorObject }
        let made = MDLMeshBufferDataAllocator()
        allocatorObject = made
        return made
    }

    @ObjCMethod("zone") func zone() -> NSObject? { zoneObject }

    @ObjCMethod("fillData:offset:") func fill(data: NSObject?, offset: UInt) {
        guard let source = data?.unsafeCast(to: NSData.self), let bytes = source.bytes(), let target = mutableBytes else { return }
        let count = min(Int(source.length()), max(self.count - Int(offset), 0))
        guard count > 0 else { return }
        (target + Int(offset)).copyMemory(from: bytes, byteCount: count)
    }

    @ObjCMethod("copyWithZone:") func copy(zone: UnsafeMutableRawPointer?) -> MDLMeshBufferData {
        let copy = MDLMeshBufferData(type: typeValue, bytes: UnsafeRawBufferPointer(start: mutableBytes, count: count), allocator: allocatorObject)
        copy.zoneObject = zoneObject
        return copy
    }
}

@ObjCClass("MDLMeshBufferDataAllocator")
open class MDLMeshBufferDataAllocator: NSObject {
    @ObjCMethod("init") public required override init() { super.init() }

    @ObjCMethod("newZone:") func newZone(capacity: UInt) -> NSObject { MDLMeshBufferZoneDefault(capacity: capacity, allocator: self) }

    @ObjCMethod("newZoneForBuffersWithSize:andType:") func newZone(sizes: NSObject?, types: NSObject?) -> NSObject {
        let total = sizes.map { $0.unsafeCast(to: NSArray.self).elements.reduce(UInt(0)) { $0 + $1.unsafeCast(to: NSNumber.self).unsignedValue() } } ?? 0
        return MDLMeshBufferZoneDefault(capacity: total, allocator: self)
    }

    @ObjCMethod("newBuffer:type:") func newBuffer(length: UInt, type: UInt) -> NSObject {
        let buffer = MDLMeshBufferData(type: type, length: length)
        buffer.allocatorObject = self
        return buffer
    }

    @ObjCMethod("newBufferWithData:type:") func newBuffer(data: NSObject?, type: UInt) -> NSObject {
        let buffer = MDLMeshBufferData(type: type, data: data)
        buffer.allocatorObject = self
        return buffer
    }

    @ObjCMethod("newBufferFromZone:length:type:") func newBuffer(zone: NSObject?, length: UInt, type: UInt) -> NSObject? {
        let buffer = MDLMeshBufferData(type: type, length: length)
        buffer.allocatorObject = self
        buffer.zoneObject = zone
        return buffer
    }

    @ObjCMethod("newBufferFromZone:data:type:") func newBuffer(zone: NSObject?, data: NSObject?, type: UInt) -> NSObject? {
        let buffer = MDLMeshBufferData(type: type, data: data)
        buffer.allocatorObject = self
        buffer.zoneObject = zone
        return buffer
    }
}

/// Model I/O's own allocator, as an app's MDLMeshBufferAllocatorDefault.
@ObjCClass("MDLMeshBufferAllocatorDefault")
open class MDLMeshBufferAllocatorDefault: MDLMeshBufferDataAllocator {}

/// The bytes of any mesh buffer, while `body` runs.
func withBytes<Result>(of buffer: NSObject, _ body: (UnsafeMutableRawPointer?, Int) -> Result) -> Result {
    if let data = ObjCPeers.peer(of: buffer.objcObject) as? MDLMeshBufferData {
        return body(data.mutableBytes, data.count)
    }
    let map = buffer.sendMap()
    let length = Int(buffer.sendLength())
    return withExtendedLifetime(map) { body(map?.sendBytes(), length) }
}

/// A copy of any mesh buffer's bytes.
func bytes(of buffer: NSObject) -> [UInt8] {
    withBytes(of: buffer) { pointer, count in
        guard let pointer, count > 0 else { return [] }
        return Array(UnsafeRawBufferPointer(start: pointer, count: count))
    }
}

/// A new buffer of `bytes` from `allocator`: Model I/O's own when there is
/// none, or when it is Model I/O's.
func makeBuffer(_ bytes: UnsafeRawBufferPointer, type: UInt, allocator: NSObject?) -> NSObject {
    if let allocator, !(ObjCPeers.peer(of: allocator.objcObject) is MDLMeshBufferDataAllocator),
       let buffer = allocator.sendNewBuffer(data: NSMutableData.make(bytes), type: type) {
        return buffer
    }
    return MDLMeshBufferData(type: type, bytes: bytes, allocator: allocator)
}

func makeBuffer(_ bytes: [UInt8], type: UInt, allocator: NSObject?) -> NSObject {
    bytes.withUnsafeBytes { makeBuffer($0, type: type, allocator: allocator) }
}
