import Glibc

/// The selector table. A selector is the first C string registered for its
/// name; every selector reference in every image is rewritten to it, so
/// selectors compare by address.
public enum Selectors {
    private static let lock = RecursiveLock()
    nonisolated(unsafe) private static var table: [CStringKey: SEL] = [:]

    /// The selector named `name`. Strings inside Mach-O images live as long
    /// as the process and are used in place (`copying: false`).
    public static func register(_ name: UnsafePointer<CChar>, copying: Bool = true) -> SEL {
        lock.withLock {
            if let selector = table[CStringKey(pointer: name)] {
                return selector
            }
            let selector = copying ? UnsafePointer(strdup(name)!) : name
            table[CStringKey(pointer: selector)] = selector
            return selector
        }
    }

    public static func register(_ name: String) -> SEL {
        name.withCString { register($0) }
    }
}

/// Selectors the runtime sends or looks up itself.
enum Sel {
    nonisolated(unsafe) static let alloc = Selectors.register("alloc")
    nonisolated(unsafe) static let allocWithZone = Selectors.register("allocWithZone:")
    nonisolated(unsafe) static let `init` = Selectors.register("init")
    nonisolated(unsafe) static let new = Selectors.register("new")
    nonisolated(unsafe) static let dealloc = Selectors.register("dealloc")
    nonisolated(unsafe) static let retain = Selectors.register("retain")
    nonisolated(unsafe) static let release = Selectors.register("release")
    nonisolated(unsafe) static let autorelease = Selectors.register("autorelease")
    nonisolated(unsafe) static let retainCount = Selectors.register("retainCount")
    nonisolated(unsafe) static let `class` = Selectors.register("class")
    nonisolated(unsafe) static let initialize = Selectors.register("initialize")
    nonisolated(unsafe) static let load = Selectors.register("load")
    nonisolated(unsafe) static let copy = Selectors.register("copy")
    nonisolated(unsafe) static let copyWithZone = Selectors.register("copyWithZone:")
    nonisolated(unsafe) static let mutableCopyWithZone = Selectors.register("mutableCopyWithZone:")
    nonisolated(unsafe) static let description = Selectors.register("description")
    nonisolated(unsafe) static let isKindOfClass = Selectors.register("isKindOfClass:")
    nonisolated(unsafe) static let respondsToSelector = Selectors.register("respondsToSelector:")
    nonisolated(unsafe) static let resolveInstanceMethod = Selectors.register("resolveInstanceMethod:")
    nonisolated(unsafe) static let resolveClassMethod = Selectors.register("resolveClassMethod:")
    nonisolated(unsafe) static let forwardingTargetForSelector = Selectors.register("forwardingTargetForSelector:")
    nonisolated(unsafe) static let doesNotRecognizeSelector = Selectors.register("doesNotRecognizeSelector:")
    nonisolated(unsafe) static let cxxConstruct = Selectors.register(".cxx_construct")
    nonisolated(unsafe) static let cxxDestruct = Selectors.register(".cxx_destruct")
}
