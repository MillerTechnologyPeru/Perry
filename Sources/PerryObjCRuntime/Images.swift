import CPerryObjC
import Glibc

/// A mapped Mach-O image's Objective-C sections.
struct MachOImage {
    let header: UnsafeRawPointer
    let slide: Int

    private static let segmentCommand: UInt32 = 0x19    // LC_SEGMENT_64

    /// A section in a __DATA* segment, as an array of pointer-sized slots.
    func pointers(_ name: String) -> UnsafeMutableBufferPointer<UnsafeMutableRawPointer?>? {
        let count = Int(header.load(fromByteOffset: 16, as: UInt32.self))
        var command = header + 32
        for _ in 0..<count {
            let cmd = command.load(as: UInt32.self)
            let size = Int(command.load(fromByteOffset: 4, as: UInt32.self))
            if cmd == Self.segmentCommand, strncmp(command.assumingMemoryBound(to: CChar.self) + 8, "__DATA", 6) == 0 {
                let sections = Int(command.load(fromByteOffset: 64, as: UInt32.self))
                for index in 0..<sections {
                    let section = command + 72 + index * 80
                    let matches = name.withCString { strncmp(section.assumingMemoryBound(to: CChar.self), $0, 16) == 0 }
                    if matches {
                        let address = Int(section.load(fromByteOffset: 32, as: UInt64.self)) + slide
                        let bytes = Int(section.load(fromByteOffset: 40, as: UInt64.self))
                        return UnsafeMutableBufferPointer(
                            start: UnsafeMutablePointer(bitPattern: address), count: bytes / 8)
                    }
                }
            }
            command += size
        }
        return nil
    }
}

extension Runtime {
    nonisolated(unsafe) static var protocolsByName: [CStringKey: UnsafeMutablePointer<perry_protocol>] = [:]

    /// Registers an image's Objective-C metadata and calls its +load
    /// methods, as Apple's runtime does when dyld maps and initializes an
    /// image. Dependencies are mapped first, so superclasses and the classes
    /// categories extend are already known.
    public static func mapImage(header: UnsafeRawPointer, slide: Int) {
        let image = MachOImage(header: header, slide: slide)
        var loadClasses: [ClassInfo] = []
        var loadCategories: [UnsafeMutablePointer<perry_category>] = []

        lock.withLock {
            // Selector references point at each image's own strings; make
            // them all the unique selector for their name.
            if let refs = image.pointers("__objc_selrefs") {
                for index in refs.indices {
                    if let name = refs[index] {
                        refs[index] = UnsafeMutableRawPointer(mutating: Selectors.register(
                            name.assumingMemoryBound(to: CChar.self), copying: false))
                    }
                }
            }

            // Protocols: one canonical protocol_t per name.
            for slot in image.pointers("__objc_protolist") ?? .init(start: nil, count: 0) {
                guard let proto = slot?.assumingMemoryBound(to: perry_protocol.self), let name = proto.pointee.name else {
                    continue
                }
                if proto.pointee.isa == nil {
                    proto.pointee.isa = UnsafeMutableRawPointer(perry_objc_protocol_class())
                }
                let key = CStringKey(pointer: name)
                if protocolsByName[key] == nil {
                    protocolsByName[key] = proto
                }
            }
            if let refs = image.pointers("__objc_protorefs") {
                for index in refs.indices {
                    if let name = refs[index]?.assumingMemoryBound(to: perry_protocol.self).pointee.name,
                       let canonical = protocolsByName[CStringKey(pointer: name)] {
                        refs[index] = UnsafeMutableRawPointer(canonical)
                    }
                }
            }

            for slot in image.pointers("__objc_classlist") ?? .init(start: nil, count: 0) {
                if let cls = slot?.assumingMemoryBound(to: perry_objc_class.self) {
                    _ = Runtime.info(cls)
                }
            }

            for slot in image.pointers("__objc_catlist") ?? .init(start: nil, count: 0) {
                if let category = slot?.assumingMemoryBound(to: perry_category.self) {
                    attach(category)
                }
            }

            for slot in image.pointers("__objc_nlclslist") ?? .init(start: nil, count: 0) {
                if let cls = slot?.assumingMemoryBound(to: perry_objc_class.self), let info = Runtime.info(cls) {
                    loadClasses.append(info)
                }
            }
            for slot in image.pointers("__objc_nlcatlist") ?? .init(start: nil, count: 0) {
                if let category = slot?.assumingMemoryBound(to: perry_category.self) {
                    loadCategories.append(category)
                }
            }
        }

        // +load runs without the runtime lock, classes before categories.
        for info in loadClasses {
            callLoad(info)
        }
        for category in loadCategories {
            guard let cls = category.pointee.cls, let info = Runtime.info(cls) else { continue }
            callLoad(info)
            if let imp = MethodList.find(Sel.load, in: category.pointee.class_methods) {
                typealias Load = @convention(c) (ObjectPointer, SEL) -> Void
                unsafeBitCast(imp, to: Load.self)(ObjectPointer(cls), Sel.load)
            }
        }
    }

    /// Adds a category's methods and protocols to its class. A category on
    /// a weak-linked class that is missing has a nil class and is skipped.
    static func attach(_ category: UnsafeMutablePointer<perry_category>) {
        guard let cls = category.pointee.cls, let info = Runtime.info(cls) else { return }
        lock.withLock {
            if let methods = category.pointee.instance_methods {
                info.addMethods(methods, replacing: true)
            }
            if let methods = category.pointee.class_methods, let meta = info.partner {
                meta.addMethods(methods, replacing: true)
            }
            if let protocols = category.pointee.protocols {
                info.protocolLists.append(protocols)
            }
            if let properties = category.pointee.instance_properties {
                info.propertyLists.append(properties)
            }
        }
        flushCaches()
    }

    /// Calls a class's own +load once, after its superclass's. Category
    /// +load methods are not inherited and are called separately.
    static func callLoad(_ info: ClassInfo) {
        if let superInfo = info.superInfo {
            callLoad(superInfo)
        }
        let first = lock.withLock {
            defer { info.loadCalled = true }
            return !info.loadCalled
        }
        guard first, let imp = MethodList.find(Sel.load, in: info.partner?.baseMethods) else { return }
        typealias Load = @convention(c) (ObjectPointer, SEL) -> Void
        unsafeBitCast(imp, to: Load.self)(ObjectPointer(info.cls), Sel.load)
    }
}

/// Protocol conformance, compared by name: images each emit their own copy
/// of a protocol, and the canonical one may not be the copy a class lists.
public enum Protocols {
    public static func lookUp(_ name: UnsafePointer<CChar>) -> UnsafeMutablePointer<perry_protocol>? {
        Runtime.lock.withLock { Runtime.protocolsByName[CStringKey(pointer: name)] }
    }

    static func sameProtocol(_ a: UnsafePointer<perry_protocol>, _ b: UnsafePointer<perry_protocol>) -> Bool {
        if a == b { return true }
        guard let nameA = a.pointee.name, let nameB = b.pointee.name else { return false }
        return strcmp(nameA, nameB) == 0
    }

    /// Whether `proto` is `target` or adopts it, directly or indirectly.
    public static func conforms(_ proto: UnsafePointer<perry_protocol>, to target: UnsafePointer<perry_protocol>) -> Bool {
        if sameProtocol(proto, target) { return true }
        guard let list = proto.pointee.protocols else { return false }
        return listContains(list, target)
    }

    static func listContains(_ list: UnsafeRawPointer, _ target: UnsafePointer<perry_protocol>) -> Bool {
        let count = Int(list.load(as: UInt64.self))
        for index in 0..<count {
            if let proto = list.load(fromByteOffset: 8 + index * 8, as: UnsafePointer<perry_protocol>?.self),
               conforms(proto, to: target) {
                return true
            }
        }
        return false
    }

    /// class_conformsToProtocol: the class's own protocols and its
    /// categories', not its superclasses'.
    public static func classConforms(_ info: ClassInfo, to target: UnsafePointer<perry_protocol>) -> Bool {
        let lists = Runtime.lock.withLock { info.protocolLists }
        return lists.contains { listContains($0, target) }
    }

    /// +conformsToProtocol:, which also checks superclasses.
    public static func classOrSuperclassConforms(_ info: ClassInfo, to target: UnsafePointer<perry_protocol>) -> Bool {
        var current: ClassInfo? = info
        while let cls = current {
            if classConforms(cls, to: target) { return true }
            current = cls.superInfo
        }
        return false
    }
}

// MARK: - Protocol introspection

extension Protocols {
    /// The protocols a protocol adopts, from its list: count, then pointers.
    public static func adopted(_ proto: UnsafePointer<perry_protocol>) -> [UnsafeMutablePointer<perry_protocol>] {
        guard let list = proto.pointee.protocols else { return [] }
        let count = Int(list.load(as: UInt64.self))
        return (0..<count).compactMap { list.load(fromByteOffset: 8 + $0 * 8, as: UnsafeMutablePointer<perry_protocol>?.self) }
    }

    /// The protocols a class lists itself, its categories' included.
    public static func listed(by info: ClassInfo) -> [UnsafeMutablePointer<perry_protocol>] {
        let lists = Runtime.lock.withLock { info.protocolLists }
        return lists.flatMap { list -> [UnsafeMutablePointer<perry_protocol>] in
            let count = Int(list.load(as: UInt64.self))
            return (0..<count).compactMap { list.load(fromByteOffset: 8 + $0 * 8, as: UnsafeMutablePointer<perry_protocol>?.self) }
        }
    }

    /// A protocol's method descriptions of one kind: selectors and types.
    public static func methods(_ proto: UnsafePointer<perry_protocol>, required: Bool, instance: Bool) -> [(SEL, UnsafePointer<CChar>?)] {
        let list: UnsafeRawPointer? = switch (required, instance) {
        case (true, true): proto.pointee.instance_methods
        case (true, false): proto.pointee.class_methods
        case (false, true): proto.pointee.optional_instance_methods
        case (false, false): proto.pointee.optional_class_methods
        }
        guard let list else { return [] }
        var methods: [(SEL, UnsafePointer<CChar>?)] = []
        MethodList.forEach(list) { selector, types, _ in methods.append((selector, types)) }
        return methods
    }

    /// A protocol's instance properties (property_t: name, attributes).
    public static func properties(_ proto: UnsafePointer<perry_protocol>) -> [UnsafeRawPointer] {
        guard let list = proto.pointee.instance_properties else { return [] }
        let entsize = Int(list.load(as: UInt32.self))
        let count = Int(list.load(fromByteOffset: 4, as: UInt32.self))
        return (0..<count).map { list + 8 + $0 * entsize }
    }
}
