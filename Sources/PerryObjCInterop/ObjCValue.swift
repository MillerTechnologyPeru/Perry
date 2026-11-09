@_exported import CPerryObjCInterop
#if canImport(Glibc)
import Glibc
#elseif canImport(Darwin)
import Darwin
#endif

// Swift values that cross the Objective-C boundary. Each has an ABI representation (`ObjCType`), a
// type encoding, and conversions that follow Objective-C's ownership rules:
//
// - arguments are borrowed: valid for the duration of the call;
// - ordinary results are +0 (autoreleased);
// - results of alloc, new, copy, mutableCopy and init methods are +1.

/// A Swift type that can be an Objective-C argument or result.
public protocol ObjCValue {
    /// The C-representable type the value has in a message send.
    associatedtype ObjCType
    /// The type it has as a method's result: ObjCType, except where 32-bit
    /// Darwin returns a value in other registers than it passes it in (a
    /// double or a 64-bit integer passes as two words, ObjCWordPair, and
    /// returns in r0 and r1, a UInt64).
    associatedtype ObjCResultType = ObjCType

    /// The Objective-C type encoding: "q", "d", "@" and so on.
    static var objCTypeEncoding: String { get }

    /// From an argument, which the caller keeps alive during the call.
    init(objCArgument value: ObjCType)
    /// From a +0 result.
    init(objCReturnValue value: ObjCType)
    /// From a +1 result, taking ownership.
    init(objCOwned value: ObjCType)

    /// The same conversions, which for an object give its Swift object (its
    /// peer) when it has one, rather than a new wrapper.
    static func objCValue(argument value: ObjCType) -> Self
    static func objCValue(returnValue value: ObjCType) -> Self
    static func objCValue(owned value: ObjCType) -> Self

    /// As an argument, valid until the current autorelease pool drains.
    func objCArgument() -> ObjCType
    /// As a +0 result.
    func objCReturnValue() -> ObjCType
    /// As a +1 result, for methods in the owned families.
    func objCOwnedReturnValue() -> ObjCType

    /// A result's ABI form from its argument form, and back.
    static func objCResult(_ value: ObjCType) -> ObjCResultType
    static func objCArgumentForm(ofResult value: ObjCResultType) -> ObjCType

    /// Whether 32-bit Darwin returns it through a pointer in r0 (a structure
    /// of more than 4 bytes), which its sends must use objc_msgSend_stret for.
    static var objCReturnsIndirectly: Bool { get }
}

extension ObjCValue {
    public static var objCReturnsIndirectly: Bool {
        #if arch(x86_64)
        // Over 16 bytes, x86_64 returns through a pointer in rdi.
        MemoryLayout<ObjCResultType>.size > 16
        #else
        false
        #endif
    }
}

extension ObjCValue where ObjCResultType == ObjCType {
    @inline(__always) public static func objCResult(_ value: ObjCType) -> ObjCType { value }
    @inline(__always) public static func objCArgumentForm(ofResult value: ObjCType) -> ObjCType { value }
}

extension ObjCValue {
    public static func objCValue(argument value: ObjCType) -> Self { Self(objCArgument: value) }
    public static func objCValue(returnValue value: ObjCType) -> Self { Self(objCReturnValue: value) }
    public static func objCValue(owned value: ObjCType) -> Self { Self(objCOwned: value) }
}

/// A value that crosses unchanged: numbers, Booleans, structs, pointers.
public protocol ObjCScalar: ObjCValue where ObjCType == Self {}

extension ObjCScalar {
    @inline(__always) public init(objCArgument value: Self) { self = value }
    @inline(__always) public init(objCReturnValue value: Self) { self = value }
    @inline(__always) public init(objCOwned value: Self) { self = value }
    @inline(__always) public func objCArgument() -> Self { self }
    @inline(__always) public func objCReturnValue() -> Self { self }
    @inline(__always) public func objCOwnedReturnValue() -> Self { self }
}

#if _pointerBitWidth(_32)
// 32-bit Darwin's NSInteger and NSUInteger are int and unsigned int, and its
// BOOL is a signed char.
extension Int: ObjCScalar { public static var objCTypeEncoding: String { "i" } }
extension UInt: ObjCScalar { public static var objCTypeEncoding: String { "I" } }
extension Bool: ObjCScalar { public static var objCTypeEncoding: String { "c" } }
#else
extension Int: ObjCScalar { public static var objCTypeEncoding: String { "q" } }
extension UInt: ObjCScalar { public static var objCTypeEncoding: String { "Q" } }
extension Int64: ObjCScalar { public static var objCTypeEncoding: String { "q" } }
extension UInt64: ObjCScalar { public static var objCTypeEncoding: String { "Q" } }
extension Double: ObjCScalar { public static var objCTypeEncoding: String { "d" } }
extension Float: ObjCScalar { public static var objCTypeEncoding: String { "f" } }
#if arch(x86_64)
// x86_64 Darwin's BOOL is a signed char.
extension Bool: ObjCScalar { public static var objCTypeEncoding: String { "c" } }
#else
extension Bool: ObjCScalar { public static var objCTypeEncoding: String { "B" } }
#endif
#endif
extension Int32: ObjCScalar { public static var objCTypeEncoding: String { "i" } }
extension UInt32: ObjCScalar { public static var objCTypeEncoding: String { "I" } }
extension Int16: ObjCScalar { public static var objCTypeEncoding: String { "s" } }
extension UInt16: ObjCScalar { public static var objCTypeEncoding: String { "S" } }
extension Int8: ObjCScalar { public static var objCTypeEncoding: String { "c" } }
extension UInt8: ObjCScalar { public static var objCTypeEncoding: String { "C" } }

// MARK: - Structures

/// A C structure that crosses as Darwin passes it. Its ObjCType is the
/// structure itself on 64-bit, where Darwin and Linux pass structures the same
/// way, and on 32-bit Darwin the words it is made of (ObjCWords2 and so on),
/// since Darwin passes a structure of floats or doubles in core registers and
/// on the stack where Linux's armhf uses VFP registers. The two are the same
/// size; values convert by their bits.
public protocol ObjCStructure: ObjCValue {}

extension ObjCStructure {
    public static var objCReturnsIndirectly: Bool {
        #if _pointerBitWidth(_32)
        MemoryLayout<ObjCResultType>.size > 4
        #elseif arch(x86_64)
        MemoryLayout<ObjCResultType>.size > 16
        #else
        false
        #endif
    }

    @inline(__always) public init(objCArgument value: ObjCType) { self = unsafeBitCast(value, to: Self.self) }
    @inline(__always) public init(objCReturnValue value: ObjCType) { self = unsafeBitCast(value, to: Self.self) }
    @inline(__always) public init(objCOwned value: ObjCType) { self = unsafeBitCast(value, to: Self.self) }
    @inline(__always) public func objCArgument() -> ObjCType { unsafeBitCast(self, to: ObjCType.self) }
    @inline(__always) public func objCReturnValue() -> ObjCType { unsafeBitCast(self, to: ObjCType.self) }
    @inline(__always) public func objCOwnedReturnValue() -> ObjCType { unsafeBitCast(self, to: ObjCType.self) }
}

public typealias ObjCWords2 = perry_words2
public typealias ObjCWords3 = perry_words3
public typealias ObjCWords4 = perry_words4
public typealias ObjCWords6 = perry_words6
public typealias ObjCWords8 = perry_words8
public typealias ObjCWords16 = perry_words16

// MARK: - 32-bit Darwin's floating point and 64-bit integers

/// Two words, the low one first: how 32-bit Darwin passes a double or a
/// 64-bit integer (perry_word_pair, a C structure so that @c functions can
/// take it).
public typealias ObjCWordPair = perry_word_pair

extension perry_word_pair {
    @inline(__always) public init(_ bits: UInt64) {
        self.init(low: UInt32(truncatingIfNeeded: bits), high: UInt32(truncatingIfNeeded: bits >> 32))
    }

    @inline(__always) public var bits: UInt64 { UInt64(high) << 32 | UInt64(low) }
}

/// A 64-bit value that 32-bit Darwin passes as an ObjCWordPair and returns
/// in r0 and r1.
public protocol ObjCWordPairValue: ObjCValue where ObjCType == ObjCWordPair, ObjCResultType == UInt64 {
    init(objCBits: UInt64)
    var objCBits: UInt64 { get }
}

extension ObjCWordPairValue {
    @inline(__always) public init(objCArgument value: ObjCWordPair) { self.init(objCBits: value.bits) }
    @inline(__always) public init(objCReturnValue value: ObjCWordPair) { self.init(objCBits: value.bits) }
    @inline(__always) public init(objCOwned value: ObjCWordPair) { self.init(objCBits: value.bits) }
    @inline(__always) public func objCArgument() -> ObjCWordPair { ObjCWordPair(objCBits) }
    @inline(__always) public func objCReturnValue() -> ObjCWordPair { ObjCWordPair(objCBits) }
    @inline(__always) public func objCOwnedReturnValue() -> ObjCWordPair { ObjCWordPair(objCBits) }
    @inline(__always) public static func objCResult(_ value: ObjCWordPair) -> UInt64 { value.bits }
    @inline(__always) public static func objCArgumentForm(ofResult value: UInt64) -> ObjCWordPair { ObjCWordPair(value) }
}

#if _pointerBitWidth(_32)
extension Double: ObjCWordPairValue {
    public static var objCTypeEncoding: String { "d" }
    @inline(__always) public init(objCBits: UInt64) { self.init(bitPattern: objCBits) }
    @inline(__always) public var objCBits: UInt64 { bitPattern }
}

extension Int64: ObjCWordPairValue {
    public static var objCTypeEncoding: String { "q" }
    @inline(__always) public init(objCBits: UInt64) { self.init(bitPattern: objCBits) }
    @inline(__always) public var objCBits: UInt64 { UInt64(bitPattern: self) }
}

extension UInt64: ObjCWordPairValue {
    public static var objCTypeEncoding: String { "Q" }
    @inline(__always) public init(objCBits: UInt64) { self = objCBits }
    @inline(__always) public var objCBits: UInt64 { self }
}

/// A float, which 32-bit Darwin passes and returns in a core register: its
/// bits as a word.
extension Float: ObjCValue {
    public typealias ObjCType = UInt32
    public static var objCTypeEncoding: String { "f" }
    @inline(__always) public init(objCArgument value: UInt32) { self.init(bitPattern: value) }
    @inline(__always) public init(objCReturnValue value: UInt32) { self.init(bitPattern: value) }
    @inline(__always) public init(objCOwned value: UInt32) { self.init(bitPattern: value) }
    @inline(__always) public func objCArgument() -> UInt32 { bitPattern }
    @inline(__always) public func objCReturnValue() -> UInt32 { bitPattern }
    @inline(__always) public func objCOwnedReturnValue() -> UInt32 { bitPattern }
}
#endif

// MARK: - Nullable values and Optional

/// A value whose ABI form can be nil (objects, selectors, pointers), so
/// that `Optional` of it is an ObjCValue with the same representation.
public protocol ObjCNullable: ObjCValue {
    static var objCNil: ObjCType { get }
    static func objCIsNil(_ value: ObjCType) -> Bool
}

extension Optional: ObjCValue where Wrapped: ObjCNullable {
    public typealias ObjCType = Wrapped.ObjCType

    public static var objCTypeEncoding: String { Wrapped.objCTypeEncoding }

    public init(objCArgument value: ObjCType) {
        self = Wrapped.objCIsNil(value) ? nil : Wrapped(objCArgument: value)
    }

    public init(objCReturnValue value: ObjCType) {
        self = Wrapped.objCIsNil(value) ? nil : Wrapped(objCReturnValue: value)
    }

    public init(objCOwned value: ObjCType) {
        self = Wrapped.objCIsNil(value) ? nil : Wrapped(objCOwned: value)
    }

    public static func objCValue(argument value: ObjCType) -> Self {
        Wrapped.objCIsNil(value) ? nil : Wrapped.objCValue(argument: value)
    }

    public static func objCValue(returnValue value: ObjCType) -> Self {
        Wrapped.objCIsNil(value) ? nil : Wrapped.objCValue(returnValue: value)
    }

    public static func objCValue(owned value: ObjCType) -> Self {
        Wrapped.objCIsNil(value) ? nil : Wrapped.objCValue(owned: value)
    }

    public func objCArgument() -> ObjCType { map { $0.objCArgument() } ?? Wrapped.objCNil }
    public func objCReturnValue() -> ObjCType { map { $0.objCReturnValue() } ?? Wrapped.objCNil }
    public func objCOwnedReturnValue() -> ObjCType { map { $0.objCOwnedReturnValue() } ?? Wrapped.objCNil }
}

/// Reports nil where a non-optional Swift type was declared.
@usableFromInline
func objCUnexpectedNil(_ type: Any.Type) -> Never {
    objcInteropFatal("nil was passed where \(type) was expected; declare the parameter or result optional")
}

/// `value`, which must not be nil for a non-optional `type`.
@inline(__always)
func objCRequire<Value>(_ value: Value?, _ type: Any.Type) -> Value {
    guard let value else { objCUnexpectedNil(type) }
    return value
}

// MARK: - Pointers

extension UnsafeRawPointer: ObjCNullable {
    public typealias ObjCType = UnsafeRawPointer?
    public static var objCTypeEncoding: String { "^v" }
    public static var objCNil: UnsafeRawPointer? { nil }
    public static func objCIsNil(_ value: UnsafeRawPointer?) -> Bool { value == nil }
    public init(objCArgument value: UnsafeRawPointer?) { self = objCRequire(value, Self.self) }
    public init(objCReturnValue value: UnsafeRawPointer?) { self.init(objCArgument: value) }
    public init(objCOwned value: UnsafeRawPointer?) { self.init(objCArgument: value) }
    public func objCArgument() -> UnsafeRawPointer? { self }
    public func objCReturnValue() -> UnsafeRawPointer? { self }
    public func objCOwnedReturnValue() -> UnsafeRawPointer? { self }
}

extension UnsafeMutableRawPointer: ObjCNullable {
    public typealias ObjCType = UnsafeMutableRawPointer?
    public static var objCTypeEncoding: String { "^v" }
    public static var objCNil: UnsafeMutableRawPointer? { nil }
    public static func objCIsNil(_ value: UnsafeMutableRawPointer?) -> Bool { value == nil }
    public init(objCArgument value: UnsafeMutableRawPointer?) { self = objCRequire(value, Self.self) }
    public init(objCReturnValue value: UnsafeMutableRawPointer?) { self.init(objCArgument: value) }
    public init(objCOwned value: UnsafeMutableRawPointer?) { self.init(objCArgument: value) }
    public func objCArgument() -> UnsafeMutableRawPointer? { self }
    public func objCReturnValue() -> UnsafeMutableRawPointer? { self }
    public func objCOwnedReturnValue() -> UnsafeMutableRawPointer? { self }
}

extension UnsafePointer: ObjCValue, ObjCNullable {
    public typealias ObjCType = UnsafePointer<Pointee>?
    /// `const char *` for CChar, `r^v` otherwise.
    public static var objCTypeEncoding: String { Pointee.self == CChar.self ? "r*" : "r^v" }
    public static var objCNil: UnsafePointer<Pointee>? { nil }
    public static func objCIsNil(_ value: UnsafePointer<Pointee>?) -> Bool { value == nil }
    public init(objCArgument value: UnsafePointer<Pointee>?) { self = objCRequire(value, Self.self) }
    public init(objCReturnValue value: UnsafePointer<Pointee>?) { self.init(objCArgument: value) }
    public init(objCOwned value: UnsafePointer<Pointee>?) { self.init(objCArgument: value) }
    public func objCArgument() -> UnsafePointer<Pointee>? { self }
    public func objCReturnValue() -> UnsafePointer<Pointee>? { self }
    public func objCOwnedReturnValue() -> UnsafePointer<Pointee>? { self }
}

extension UnsafeMutablePointer: ObjCValue, ObjCNullable {
    public typealias ObjCType = UnsafeMutablePointer<Pointee>?
    public static var objCTypeEncoding: String { Pointee.self == CChar.self ? "*" : "^v" }
    public static var objCNil: UnsafeMutablePointer<Pointee>? { nil }
    public static func objCIsNil(_ value: UnsafeMutablePointer<Pointee>?) -> Bool { value == nil }
    public init(objCArgument value: UnsafeMutablePointer<Pointee>?) { self = objCRequire(value, Self.self) }
    public init(objCReturnValue value: UnsafeMutablePointer<Pointee>?) { self.init(objCArgument: value) }
    public init(objCOwned value: UnsafeMutablePointer<Pointee>?) { self.init(objCArgument: value) }
    public func objCArgument() -> UnsafeMutablePointer<Pointee>? { self }
    public func objCReturnValue() -> UnsafeMutablePointer<Pointee>? { self }
    public func objCOwnedReturnValue() -> UnsafeMutablePointer<Pointee>? { self }
}

// MARK: - Selectors and classes

/// A selector (SEL).
public struct ObjCSelector: ObjCNullable, Hashable {
    public let pointer: UnsafeRawPointer

    public init(_ pointer: UnsafeRawPointer) { self.pointer = pointer }
    public init(_ name: String) { pointer = ObjCRuntime.selector(name) }

    public var name: String { String(cString: pointer.assumingMemoryBound(to: CChar.self)) }

    public typealias ObjCType = UnsafeRawPointer?
    public static var objCTypeEncoding: String { ":" }
    public static var objCNil: UnsafeRawPointer? { nil }
    public static func objCIsNil(_ value: UnsafeRawPointer?) -> Bool { value == nil }
    public init(objCArgument value: UnsafeRawPointer?) { pointer = objCRequire(value, Self.self) }
    public init(objCReturnValue value: UnsafeRawPointer?) { self.init(objCArgument: value) }
    public init(objCOwned value: UnsafeRawPointer?) { self.init(objCArgument: value) }
    public func objCArgument() -> UnsafeRawPointer? { pointer }
    public func objCReturnValue() -> UnsafeRawPointer? { pointer }
    public func objCOwnedReturnValue() -> UnsafeRawPointer? { pointer }
}

/// A class object (Class). Classes live forever, so it holds no reference.
/// It is also a registrar: @ObjCImplementation methods install into it.
public struct ObjCClass: ObjCNullable, Hashable, ObjCMethodRegistrar {
    public let pointer: UnsafeMutableRawPointer

    public init(_ pointer: UnsafeMutableRawPointer) { self.pointer = pointer }
    public init(named name: String) { pointer = ObjCRuntime.classObject(name) }

    public var superclass: ObjCClass? {
        pointer.load(fromByteOffset: MemoryLayout<UnsafeRawPointer>.size, as: UnsafeMutableRawPointer?.self).map(ObjCClass.init)
    }

    /// The metaclass, where class methods live.
    public var metaclass: ObjCClass {
        ObjCClass(pointer.load(as: UnsafeMutableRawPointer.self))
    }

    /// Adds a method, replacing one the class itself already defines.
    public func addMethod(_ selector: String, types: String, implementation: UnsafeRawPointer, isClassMethod: Bool) {
        let target = isClassMethod ? metaclass.pointer : pointer
        let sel = ObjCRuntime.selector(selector)
        // The runtime keeps the encoding, so it must outlive this call.
        let encoding = UnsafePointer(strdup(types)!)
        if !ObjCRuntime.functions.addMethod(target, sel, implementation, encoding) {
            _ = ObjCRuntime.functions.replaceMethod(target, sel, implementation, encoding)
        }
    }

    public typealias ObjCType = UnsafeMutableRawPointer?
    public static var objCTypeEncoding: String { "#" }
    public static var objCNil: UnsafeMutableRawPointer? { nil }
    public static func objCIsNil(_ value: UnsafeMutableRawPointer?) -> Bool { value == nil }
    public init(objCArgument value: UnsafeMutableRawPointer?) { pointer = objCRequire(value, Self.self) }
    public init(objCReturnValue value: UnsafeMutableRawPointer?) { self.init(objCArgument: value) }
    public init(objCOwned value: UnsafeMutableRawPointer?) { self.init(objCArgument: value) }
    public func objCArgument() -> UnsafeMutableRawPointer? { pointer }
    public func objCReturnValue() -> UnsafeMutableRawPointer? { pointer }
    public func objCOwnedReturnValue() -> UnsafeMutableRawPointer? { pointer }
}
