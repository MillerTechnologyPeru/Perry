import CPerryObjC
import Glibc

// Protocols made at run time (objc_allocateProtocol), as providers declare
// theirs, laid out like the protocol_t clang emits so the rest of the
// runtime reads them the same way.

extension Protocols {
    /// Protocols allocated but not yet registered, with what has been added.
    private final class Draft {
        var adopted: [UnsafeMutablePointer<perry_protocol>] = []
        /// Method descriptions by list: required/optional, instance/class.
        var methods: [[(name: SEL, types: UnsafePointer<CChar>)]] = [[], [], [], []]
    }

    nonisolated(unsafe) private static var drafts: [UnsafeMutablePointer<perry_protocol>: Draft] = [:]

    /// A new protocol, or nil if one with the name exists.
    public static func allocate(_ name: UnsafePointer<CChar>) -> UnsafeMutablePointer<perry_protocol>? {
        Runtime.lock.withLock {
            guard Runtime.protocolsByName[CStringKey(pointer: name)] == nil else { return nil }
            let proto = UnsafeMutablePointer<perry_protocol>.allocate(capacity: 1)
            proto.initialize(to: perry_protocol())
            proto.pointee.isa = UnsafeMutableRawPointer(perry_objc_protocol_class())
            proto.pointee.name = permanentCString(String(cString: name))
            proto.pointee.size = UInt32(MemoryLayout<perry_protocol>.size)
            drafts[proto] = Draft()
            return proto
        }
    }

    /// protocol_addProtocol: only before the protocol is registered.
    public static func add(_ adopted: UnsafeMutablePointer<perry_protocol>, to proto: UnsafeMutablePointer<perry_protocol>) {
        Runtime.lock.withLock { drafts[proto]?.adopted.append(adopted) }
    }

    /// protocol_addMethodDescription: only before the protocol is registered.
    public static func addMethod(_ name: SEL, types: UnsafePointer<CChar>?, to proto: UnsafeMutablePointer<perry_protocol>,
                                 isRequired: Bool, isInstanceMethod: Bool) {
        let types = types.map { UnsafePointer(strdup($0)!) } ?? permanentCString("")
        let index = (isRequired ? 0 : 2) + (isInstanceMethod ? 0 : 1)
        Runtime.lock.withLock { drafts[proto]?.methods[index].append((name, types)) }
    }

    /// objc_registerProtocol: builds the protocol's lists and makes it
    /// findable by name.
    public static func register(_ proto: UnsafeMutablePointer<perry_protocol>) {
        Runtime.lock.withLock {
            guard let draft = drafts.removeValue(forKey: proto), let name = proto.pointee.name else { return }
            if !draft.adopted.isEmpty { proto.pointee.protocols = UnsafeRawPointer(list(of: draft.adopted)) }
            proto.pointee.instance_methods = methodList(draft.methods[0])
            proto.pointee.class_methods = methodList(draft.methods[1])
            proto.pointee.optional_instance_methods = methodList(draft.methods[2])
            proto.pointee.optional_class_methods = methodList(draft.methods[3])
            let key = CStringKey(pointer: name)
            if Runtime.protocolsByName[key] == nil { Runtime.protocolsByName[key] = proto }
        }
    }

    /// class_addProtocol: false if the class already adopts it.
    public static func add(_ proto: UnsafeMutablePointer<perry_protocol>, toClass info: ClassInfo) -> Bool {
        guard !classConforms(info, to: proto) else { return false }
        let protocolList = list(of: [proto])
        Runtime.lock.withLock { info.protocolLists.append(protocolList) }
        return true
    }

    /// A protocol list: a count, then the pointers.
    private static func list(of protocols: [UnsafeMutablePointer<perry_protocol>]) -> UnsafeRawPointer {
        let memory = UnsafeMutableRawPointer.allocate(byteCount: 8 * (protocols.count + 1), alignment: 8)
        memory.storeBytes(of: UInt64(protocols.count), as: UInt64.self)
        for (index, proto) in protocols.enumerated() {
            memory.storeBytes(of: UnsafeRawPointer(proto), toByteOffset: 8 + 8 * index, as: UnsafeRawPointer.self)
        }
        return UnsafeRawPointer(memory)
    }

    /// A method_list_t of method descriptions: entry size and count, then
    /// {name, types, imp} with no implementations.
    private static func methodList(_ methods: [(name: SEL, types: UnsafePointer<CChar>)]) -> UnsafeRawPointer? {
        guard !methods.isEmpty else { return nil }
        let entrySize = MemoryLayout<perry_method>.size
        let memory = UnsafeMutableRawPointer.allocate(byteCount: 8 + entrySize * methods.count, alignment: 8)
        memory.storeBytes(of: UInt32(entrySize), as: UInt32.self)
        memory.storeBytes(of: UInt32(methods.count), toByteOffset: 4, as: UInt32.self)
        for (index, method) in methods.enumerated() {
            memory.storeBytes(of: perry_method(name: method.name, types: method.types, imp: nil),
                              toByteOffset: 8 + entrySize * index, as: perry_method.self)
        }
        return UnsafeRawPointer(memory)
    }
}
