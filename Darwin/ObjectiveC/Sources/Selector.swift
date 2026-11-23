// Selector and NSZone: the runtime's SEL and NSZone pointers as values.

@frozen public struct Selector: ExpressibleByStringLiteral, @unchecked Sendable {
    internal var ptr: OpaquePointer

    /// The selector registered under `str`, registering it if it is new.
    public init(_ str: String) {
        ptr = str.withCString { OpaquePointer(registerSelector($0)) }
    }

    public init(stringLiteral value: String) {
        self.init(value)
    }

    /// The selector's registered name.
    internal var name: String {
        String(cString: selectorName(UnsafeRawPointer(ptr)))
    }
}

extension Selector: Equatable, Hashable {
    // Selectors are unique: one registered name is one pointer.
    public static func == (a: Selector, b: Selector) -> Bool {
        a.ptr == b.ptr
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(ptr)
    }
}

extension Selector: CustomStringConvertible {
    public var description: String {
        name
    }
}

extension String {
    public init(_sel: Selector) {
        self = _sel.name
    }
}

extension Selector: CustomReflectable {
    public var customMirror: Mirror {
        Mirror(reflecting: name)
    }
}

extension Selector: BitwiseCopyable {}

@frozen public struct NSZone {
    internal var pointer: OpaquePointer
}

@available(*, unavailable)
extension NSZone: Sendable {}

extension NSZone: BitwiseCopyable {}

// sel_registerName and sel_getName, which the import of the headers gives
// Swift in terms of Selector, the type defined here.
@_silgen_name("sel_registerName")
private func registerSelector(_ name: UnsafePointer<CChar>) -> UnsafeRawPointer

@_silgen_name("sel_getName")
private func selectorName(_ selector: UnsafeRawPointer) -> UnsafePointer<CChar>
