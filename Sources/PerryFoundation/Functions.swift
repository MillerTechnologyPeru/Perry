import CPerryFoundation
import Glibc
import PerryObjCInterop

// Foundation's C functions, under their Mach-O names. Each returns an
// autoreleased object, as Foundation's do.

private func environment(_ name: String) -> String? {
    getenv(name).map { String(cString: $0) }
}

/// The temporary directory, with a trailing slash as on Darwin.
@c(_NSTemporaryDirectory)
public func NSTemporaryDirectory() -> UnsafeMutableRawPointer? {
    var path = environment("TMPDIR") ?? "/tmp/"
    if !path.hasSuffix("/") { path += "/" }
    return Strings.autoreleased(path)
}

@c(_NSHomeDirectory)
public func NSHomeDirectory() -> UnsafeMutableRawPointer? {
    Strings.autoreleased(environment("HOME") ?? "/")
}

@c(_NSUserName)
public func NSUserName() -> UnsafeMutableRawPointer? {
    let name = environment("USER") ?? getpwuid(getuid()).flatMap { $0.pointee.pw_name.map { String(cString: $0) } } ?? ""
    return Strings.autoreleased(name)
}

@c(_NSFullUserName)
public func NSFullUserName() -> UnsafeMutableRawPointer? {
    let gecos = getpwuid(getuid()).flatMap { $0.pointee.pw_gecos.map { String(cString: $0) } } ?? ""
    let name = gecos.split(separator: ",").first.map(String.init) ?? ""
    return name.isEmpty ? NSUserName() : Strings.autoreleased(name)
}

@c(_NSStringFromSelector)
public func NSStringFromSelector(_ selector: UnsafeRawPointer?) -> UnsafeMutableRawPointer? {
    selector.map { Strings.autoreleased(String(cString: $0.assumingMemoryBound(to: CChar.self))) }
}

@c(_NSSelectorFromString)
public func NSSelectorFromString(_ string: UnsafeMutableRawPointer?) -> UnsafeRawPointer? {
    Strings.value(of: string).map { ObjCRuntime.selector($0) }
}

@c(_NSStringFromClass)
public func NSStringFromClass(_ cls: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer? {
    guard let cls else { return nil }
    // A class object's class is its metaclass, which has the same name.
    return Strings.autoreleased(ObjC.className(cls))
}

@c(_NSClassFromString)
public func NSClassFromString(_ string: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer? {
    Strings.value(of: string).flatMap { name in name.withCString { ObjC.getClass($0) } }.map(UnsafeMutableRawPointer.init)
}

@c(_NSProtocolFromString)
public func NSProtocolFromString(_ string: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer? {
    guard let name = Strings.value(of: string) else { return nil }
    return name.withCString { ObjCRuntime.protocolFunctions?.getProtocol($0) }
}

/// CFRetain and CFRelease: every CoreFoundation object here is an
/// Objective-C object.
@c(_CFRetain)
public func CFRetain(_ object: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer? {
    ObjC.retain(object)
}

@c(_CFRelease)
public func CFRelease(_ object: UnsafeMutableRawPointer?) {
    ObjC.release(object)
}

@c(_CFEqual)
public func CFEqual(_ first: UnsafeMutableRawPointer?, _ second: UnsafeMutableRawPointer?) -> Bool {
    guard let first, let second else { return first == second }
    return first == second || ObjC.sendBool(first, Selectors.isEqual, second)
}

@c(_CFHash)
public func CFHash(_ object: UnsafeMutableRawPointer?) -> UInt {
    object.map { ObjC.sendUInt($0, Selectors.hash) } ?? 0
}

/// A CoreFoundation type's ID: what the object's -_cfTypeID answers, as
/// toll-free bridged classes answer on Darwin.
@c(_CFGetTypeID)
public func CFGetTypeID(_ object: UnsafeMutableRawPointer?) -> UInt {
    guard let object else { return 0 }
    let selector = ObjC.selector("_cfTypeID")
    guard ObjC.sendBool(object, ObjC.selector("respondsToSelector:"), UnsafeMutableRawPointer(mutating: selector)) else {
        return 1
    }
    return ObjC.sendUInt(object, selector)
}

@c(_CFCopyDescription)
public func CFCopyDescription(_ object: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer? {
    Strings.make(Format.describe(object))
}

@c(_NSStringFromProtocol)
public func NSStringFromProtocol(_ proto: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer? {
    // protocol_t: isa, then the name.
    proto?.load(fromByteOffset: 8, as: UnsafePointer<CChar>?.self).map { Strings.autoreleased(String(cString: $0)) }
}

// MARK: - Ranges

/// "{location, length}".
@c(_NSStringFromRange)
public func NSStringFromRange(_ range: NSRange) -> UnsafeMutableRawPointer? {
    Strings.autoreleased("{\(range.location), \(range.length)}")
}

/// The first two integers in a string, as NSRangeFromString reads them.
@c(_NSRangeFromString)
public func NSRangeFromString(_ string: UnsafeMutableRawPointer?) -> NSRange {
    let text = Strings.value(of: string) ?? ""
    let numbers = text.split { !$0.isNumber }.compactMap { UInt($0) }
    return NSRange(location: numbers.first ?? 0, length: numbers.dropFirst().first ?? 0)
}

@c(_NSUnionRange)
public func NSUnionRange(_ a: NSRange, _ b: NSRange) -> NSRange {
    let start = min(a.location, b.location), end = max(a.location + a.length, b.location + b.length)
    return NSRange(location: start, length: end - start)
}

/// The overlap, or an empty range where they do not meet.
@c(_NSIntersectionRange)
public func NSIntersectionRange(_ a: NSRange, _ b: NSRange) -> NSRange {
    let start = max(a.location, b.location), end = min(a.location + a.length, b.location + b.length)
    return end > start ? NSRange(location: start, length: end - start) : NSRange(location: 0, length: 0)
}
