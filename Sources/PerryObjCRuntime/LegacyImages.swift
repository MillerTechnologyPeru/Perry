#if arch(i386)
import CPerryObjC
import Glibc

/// Objective-C metadata of 32-bit Mac programs, the old ABI: the __OBJC
/// segment, with classes that name their superclasses and fixed instance
/// variable offsets. Each class becomes one of this runtime's, built when
/// the image is mapped. The compiled code reads only the superclass field of
/// its own class structures, for super sends, which is pointed at the class
/// built here; its objects' isa are the built classes.
private enum OldClass {
    static let isa = 0, superclass = 4, name = 8, info = 16, instanceSize = 20, ivars = 24, methods = 28,
        protocols = 36, ivarLayout = 40, ext = 44
    static let hasCxxStructors: UInt32 = 0x2000
    /// The structure has ivarLayout and ext.
    static let hasExt: UInt32 = 0x20000
}

/// { name, class name, instance methods, class methods, protocols, size, properties }
private enum OldCategory {
    static let name = 0, className = 4, instanceMethods = 8, classMethods = 12, protocols = 16, size = 20,
        properties = 24
}

/// { isa or extension, name, protocol list, instance methods, class methods }
private enum OldProtocol {
    static let isa = 0, name = 4, protocols = 8, instanceMethods = 12, classMethods = 16
    static let size = 20
}

private struct BuiltClass {
    let old: UnsafeMutableRawPointer
    let oldMeta: UnsafeMutableRawPointer
    let cls: ClassPointer
    let meta: ClassPointer
}

private extension UnsafeMutableRawPointer {
    func word(_ offset: Int) -> UnsafeMutableRawPointer? { load(fromByteOffset: offset, as: UnsafeMutableRawPointer?.self) }
    func setWord(_ offset: Int, _ value: UnsafeRawPointer?) {
        storeBytes(of: UInt(bitPattern: value), toByteOffset: offset, as: UInt.self)
    }
    func cString(_ offset: Int) -> UnsafePointer<CChar>? { load(fromByteOffset: offset, as: UnsafePointer<CChar>?.self) }
}

extension Runtime {
    /// Registers the image's old-ABI metadata, with the runtime lock held.
    static func mapLegacyMetadata(_ image: MachOImage, classNames: inout [UnsafePointer<CChar>],
                                  loadClasses: inout [ClassInfo],
                                  loadCategories: inout [UnsafeMutablePointer<perry_category>]) {
        guard let modules = image.section(segment: "__OBJC", name: "__module_info") else { return }

        if let references = image.section(segment: "__OBJC", name: "__message_refs") {
            registerSelectors(references.baseAddress!, count: references.count / Layout.word)
        }
        convertProtocols(image)

        var built: [BuiltClass] = []
        var byName: [String: BuiltClass] = [:]
        var categories: [UnsafeMutableRawPointer] = []
        var offset = 0
        while offset + 16 <= modules.count {
            let module = modules.baseAddress! + offset
            let moduleSize = Int(module.load(fromByteOffset: 4, as: UInt32.self))
            guard moduleSize > 0 else { break }
            offset += moduleSize
            guard let symbols = module.word(12) else { continue }
            // { selector count, selectors, class count, category count, definitions }
            let selectorCount = Int(symbols.load(as: UInt32.self))
            if selectorCount > 0, let selectors = symbols.word(4) {
                registerSelectors(selectors, count: selectorCount)
            }
            let classCount = Int(symbols.load(fromByteOffset: 8, as: UInt16.self))
            let categoryCount = Int(symbols.load(fromByteOffset: 10, as: UInt16.self))
            for index in 0..<(classCount + categoryCount) {
                guard let definition = symbols.word(12 + index * Layout.word) else { continue }
                if index < classCount {
                    if let cls = buildClass(definition) {
                        built.append(cls)
                        if let name = definition.cString(OldClass.name) { byName[String(cString: name)] = cls }
                    }
                } else {
                    categories.append(definition)
                }
            }
        }

        func resolve(_ name: UnsafePointer<CChar>) -> ClassPointer? {
            byName[String(cString: name)]?.cls ?? lookUpClass(name)
        }

        // Superclasses by name, then the metaclasses' isa, which needs the
        // chain to its root.
        var linked: [BuiltClass] = []
        for cls in built {
            guard let superName = cls.old.cString(OldClass.superclass) else {
                cls.meta.pointee.superclass = cls.cls
                linked.append(cls)
                continue
            }
            guard let superclass = resolve(superName) else {
                let own = cls.old.cString(OldClass.name).map { String(cString: $0) } ?? "?"
                objcWarning("class \(own) inherits from \(String(cString: superName)), which is not available")
                continue
            }
            cls.cls.pointee.superclass = superclass
            cls.meta.pointee.superclass = superclass.pointee.isa
            linked.append(cls)
        }
        for cls in linked {
            var root = cls.cls
            while let superclass = root.pointee.superclass { root = superclass }
            cls.meta.pointee.isa = root.pointee.isa
            // Super sends read these.
            cls.old.setWord(OldClass.superclass, UnsafeRawPointer(cls.cls.pointee.superclass))
            cls.oldMeta.setWord(OldClass.superclass, UnsafeRawPointer(cls.meta.pointee.superclass))
        }
        for cls in linked {
            guard let info = Runtime.info(cls.cls) else { continue }
            classNames.append(info.name)
            if MethodList.find(Sel.load, in: info.partner?.baseMethods) != nil { loadClasses.append(info) }
        }

        // Class references name the class; afterwards they are the class.
        if let references = image.section(segment: "__OBJC", name: "__cls_refs") {
            let slots = references.baseAddress!
            for index in 0..<(references.count / Layout.word) {
                guard let name = slots.cString(index * Layout.word) else { continue }
                slots.setWord(index * Layout.word, UnsafeRawPointer(resolve(name)))
            }
        }

        for old in categories {
            guard let className = old.cString(OldCategory.className), let cls = resolve(className) else {
                let name = old.cString(OldCategory.className).map { String(cString: $0) } ?? "?"
                objcWarning("a category extends \(name), which is not available")
                continue
            }
            let category = UnsafeMutablePointer<perry_category>.allocate(capacity: 1)
            category.initialize(to: perry_category(
                name: old.cString(OldCategory.name), cls: cls,
                instance_methods: UnsafeRawPointer(modernized(old.word(OldCategory.instanceMethods))),
                class_methods: UnsafeRawPointer(modernized(old.word(OldCategory.classMethods))),
                protocols: protocolList(old.word(OldCategory.protocols)),
                instance_properties: old.load(fromByteOffset: OldCategory.size, as: UInt32.self) >= 28
                    ? UnsafeRawPointer(old.word(OldCategory.properties)) : nil))
            attach(category)
            if MethodList.find(Sel.load, in: category.pointee.class_methods) != nil { loadCategories.append(category) }
        }
    }

    private static func registerSelectors(_ references: UnsafeMutableRawPointer, count: Int) {
        for index in 0..<count {
            guard let name = references.cString(index * Layout.word) else { continue }
            references.setWord(index * Layout.word, UnsafeRawPointer(Selectors.register(name, copying: false)))
        }
    }

    /// An old method list has a word the runtime used and the count, then
    /// entries of { name, types, IMP }: a method list once that word says how
    /// big an entry is. The list is in the image's writable __OBJC segment.
    private static func modernized(_ list: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer? {
        list?.storeBytes(of: UInt32(MemoryLayout<perry_method>.size), as: UInt32.self)
        return list
    }

    private static func buildClass(_ old: UnsafeMutableRawPointer) -> BuiltClass? {
        guard let oldMeta = old.word(OldClass.isa) else { return nil }
        let cls = makeClass(from: old, isMeta: false)
        let meta = makeClass(from: oldMeta, isMeta: true)
        cls.pointee.isa = meta
        return BuiltClass(old: old, oldMeta: oldMeta, cls: cls, meta: meta)
    }

    private static func makeClass(from old: UnsafeMutableRawPointer, isMeta: Bool) -> ClassPointer {
        let info = old.load(fromByteOffset: OldClass.info, as: UInt32.self)
        let size = old.load(fromByteOffset: OldClass.instanceSize, as: UInt32.self)
        let ro = UnsafeMutablePointer<perry_class_ro>.allocate(capacity: 1)
        memset(ro, 0, MemoryLayout<perry_class_ro>.size)
        ro.pointee.flags = (isMeta ? ROFlags.meta : 0)
            | (old.word(OldClass.superclass) == nil ? ROFlags.root : 0)
            | (info & OldClass.hasCxxStructors != 0 ? ROFlags.hasCxxStructors : 0)
        // Above any superclass's size, so that offsets the compiled code holds
        // are not moved.
        ro.pointee.instance_start = 0x7fff_ffff
        ro.pointee.instance_size = size
        ro.pointee.name = UnsafePointer(old.cString(OldClass.name)?.withMemoryRebound(to: CChar.self, capacity: 1) { $0 })
        ro.pointee.base_methods = UnsafeRawPointer(modernized(old.word(OldClass.methods)))
        ro.pointee.base_protocols = protocolList(old.word(OldClass.protocols))
        if !isMeta { ro.pointee.ivars = ivarList(old.word(OldClass.ivars), instanceSize: Int(size)) }
        if info & OldClass.hasExt != 0 {
            ro.pointee.ivar_layout = old.load(fromByteOffset: OldClass.ivarLayout, as: UnsafePointer<UInt8>?.self)
            if let ext = old.word(OldClass.ext) {
                // { size, weak ivar layout, properties }
                ro.pointee.weak_ivar_layout = ext.load(fromByteOffset: 4, as: UnsafePointer<UInt8>?.self)
                ro.pointee.base_properties = UnsafeRawPointer(ext.word(8))
            }
        }
        let cls = ClassPointer.allocate(capacity: 1)
        memset(cls, 0, MemoryLayout<perry_objc_class>.size)
        cls.pointee.cache = perry_objc_empty_cache()
        cls.pointee.bits = UInt(bitPattern: ro)
        return cls
    }

    /// { count, entries of { name, type, offset } } as an ivar list, each with
    /// a variable for its offset.
    private static func ivarList(_ old: UnsafeMutableRawPointer?, instanceSize: Int) -> UnsafeRawPointer? {
        guard let old else { return nil }
        let count = Int(old.load(as: UInt32.self))
        let list = UnsafeMutableRawPointer.allocate(byteCount: 8 + count * MemoryLayout<perry_ivar>.size, alignment: 4)
        list.storeBytes(of: UInt32(MemoryLayout<perry_ivar>.size), as: UInt32.self)
        list.storeBytes(of: UInt32(count), toByteOffset: 4, as: UInt32.self)
        for index in 0..<count {
            let entry = old + 4 + index * 12
            let offset = entry.load(fromByteOffset: 8, as: Int32.self)
            let next = index + 1 < count ? (old + 4 + (index + 1) * 12).load(fromByteOffset: 8, as: Int32.self) : Int32(instanceSize)
            let variable = UnsafeMutablePointer<Int32>.allocate(capacity: 1)
            variable.initialize(to: offset)
            (list + 8 + index * MemoryLayout<perry_ivar>.size).assumingMemoryBound(to: perry_ivar.self)
                .initialize(to: perry_ivar(offset: variable, name: entry.cString(0), type: entry.cString(4),
                                           alignment_raw: 2, size: UInt32(max(next - offset, 0))))
        }
        return UnsafeRawPointer(list)
    }

    /// { next list, count, protocols } as { count, protocols }.
    private static func protocolList(_ old: UnsafeMutableRawPointer?) -> UnsafeRawPointer? {
        var protocols: [UnsafeMutableRawPointer] = []
        var current = old
        while let list = current {
            let count = Int(list.load(fromByteOffset: 4, as: UInt32.self))
            for index in 0..<count {
                if let proto = list.word(8 + index * Layout.word) { protocols.append(proto) }
            }
            current = list.word(0)
        }
        guard !protocols.isEmpty else { return nil }
        let list = UnsafeMutableRawPointer.allocate(byteCount: (protocols.count + 1) * Layout.word, alignment: 4)
        list.storeBytes(of: UInt(protocols.count), as: UInt.self)
        for (index, proto) in protocols.enumerated() {
            list.setWord(Layout.protocolEntry(index), UnsafeRawPointer(proto))
        }
        return UnsafeRawPointer(list)
    }

    /// { count, entries of { name, types } } as a method list.
    private static func methodDescriptions(_ old: UnsafeMutableRawPointer?) -> UnsafeRawPointer? {
        guard let old else { return nil }
        let count = Int(old.load(as: UInt32.self))
        let entry = MemoryLayout<perry_method>.size
        let list = UnsafeMutableRawPointer.allocate(byteCount: 8 + count * entry, alignment: 4)
        list.storeBytes(of: UInt32(entry), as: UInt32.self)
        list.storeBytes(of: UInt32(count), toByteOffset: 4, as: UInt32.self)
        for index in 0..<count {
            let description = old + 4 + index * Layout.pair
            (list + 8 + index * entry).assumingMemoryBound(to: perry_method.self)
                .initialize(to: perry_method(name: description.cString(0), types: description.cString(4), imp: nil))
        }
        return UnsafeRawPointer(list)
    }

    /// Code holds the addresses of the old protocols themselves, so each is
    /// rewritten where it is to read as the start of a protocol_t, and the
    /// runtime's canonical one is complete.
    private static func convertProtocols(_ image: MachOImage) {
        guard let section = image.section(segment: "__OBJC", name: "__protocol") else { return }
        var offset = 0
        while offset + OldProtocol.size <= section.count {
            defer { offset += OldProtocol.size }
            let old = section.baseAddress! + offset
            guard let name = old.cString(OldProtocol.name) else { continue }
            // The first word is the extension, if there is one:
            // { size, optional instance methods, optional class methods, properties }
            let ext = old.word(OldProtocol.isa)
            let protocols = protocolList(old.word(OldProtocol.protocols))
            let instanceMethods = methodDescriptions(old.word(OldProtocol.instanceMethods))
            let classMethods = methodDescriptions(old.word(OldProtocol.classMethods))
            old.setWord(OldProtocol.isa, UnsafeRawPointer(perry_objc_protocol_class()))
            old.setWord(OldProtocol.protocols, protocols)
            old.setWord(OldProtocol.instanceMethods, instanceMethods)
            old.setWord(OldProtocol.classMethods, classMethods)

            let key = CStringKey(pointer: name)
            guard protocolsByName[key] == nil else { continue }
            let canonical = UnsafeMutablePointer<perry_protocol>.allocate(capacity: 1)
            memset(canonical, 0, MemoryLayout<perry_protocol>.size)
            canonical.pointee.isa = UnsafeMutableRawPointer(perry_objc_protocol_class())
            canonical.pointee.name = name
            canonical.pointee.protocols = protocols
            canonical.pointee.instance_methods = instanceMethods
            canonical.pointee.class_methods = classMethods
            if let ext {
                canonical.pointee.optional_instance_methods = methodDescriptions(ext.word(4))
                canonical.pointee.optional_class_methods = methodDescriptions(ext.word(8))
                canonical.pointee.instance_properties = UnsafeRawPointer(ext.word(12))
            }
            canonical.pointee.size = UInt32(MemoryLayout<perry_protocol>.size)
            protocolsByName[key] = canonical
        }
    }
}
#endif
