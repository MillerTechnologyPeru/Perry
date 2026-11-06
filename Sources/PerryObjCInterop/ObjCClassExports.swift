// Classes that Objective-C code binds to as exported data symbols, such as
// `_OBJC_CLASS_$_UIResponder` for a subclass's superclass pointer. Swift
// cannot define a data symbol by name, so the provider's
// perry_provider_symbol hook hands the loader zeroed storage for each class
// and metaclass while images bind, and defineObjCClass() builds the class
// in that storage at startup, before any image's classes are realized.

/// The classes a provider defines, by name, and their exported storage.
public final class ObjCClassExports: @unchecked Sendable {
    public static let shared = ObjCClassExports()

    /// objc_class: isa, superclass, cache, vtable, bits.
    private static let classSize = 5 * MemoryLayout<UnsafeRawPointer>.size

    private let lock = InteropLock()
    private var names: Set<String> = []
    private var storage: [String: (cls: UnsafeMutableRawPointer, metaclass: UnsafeMutableRawPointer)] = [:]

    /// Adds the names of classes this provider defines.
    public func register(_ classNames: [String]) {
        lock.withLock { names.formUnion(classNames) }
    }

    /// For perry_provider_symbol: storage for `_OBJC_CLASS_$_Name` or
    /// `_OBJC_METACLASS_$_Name`, made on first request; nil for other
    /// names. Once the class is defined, the class itself.
    public func symbol(_ machOName: String) -> UnsafeMutableRawPointer? {
        let isMetaclass: Bool
        let name: Substring
        if machOName.hasPrefix("_OBJC_CLASS_$_") {
            isMetaclass = false
            name = machOName.dropFirst("_OBJC_CLASS_$_".count)
        } else if machOName.hasPrefix("_OBJC_METACLASS_$_") {
            isMetaclass = true
            name = machOName.dropFirst("_OBJC_METACLASS_$_".count)
        } else {
            return nil
        }
        return lock.withLock {
            guard names.contains(String(name)) else { return nil }
            if let pair = storage[String(name)] { return isMetaclass ? pair.metaclass : pair.cls }
            // Defined already, on the heap, as no image had asked for it:
            // a library the program loads while it runs gets the class.
            if let pair = ObjCRuntime.registeredClassPair(String(name)) { return isMetaclass ? pair.metaclass : pair.cls }
            let pair = allocate(String(name))
            return isMetaclass ? pair.metaclass : pair.cls
        }
    }

    /// The storage handed out for a class, if an image asked for it.
    public func storage(for name: String) -> (UnsafeMutableRawPointer, UnsafeMutableRawPointer)? {
        lock.withLock { storage[name].map { ($0.cls, $0.metaclass) } }
    }

    private func allocate(_ name: String) -> (cls: UnsafeMutableRawPointer, metaclass: UnsafeMutableRawPointer) {
        func zeroed() -> UnsafeMutableRawPointer {
            let memory = UnsafeMutableRawPointer.allocate(byteCount: Self.classSize, alignment: 16)
            memory.initializeMemory(as: UInt8.self, repeating: 0, count: Self.classSize)
            return memory
        }
        let pair = (cls: zeroed(), metaclass: zeroed())
        storage[name] = pair
        return pair
    }
}
