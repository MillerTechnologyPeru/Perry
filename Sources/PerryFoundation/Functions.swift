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
    return Strings.autoreleased(ObjC.name(ofClass: cls))
}

@c(_NSClassFromString)
public func NSClassFromString(_ string: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer? {
    Strings.value(of: string).flatMap { name in name.withCString { ObjC.getClass($0) } }.map(UnsafeMutableRawPointer.init)
}

/// A new instance of the class with room after its instance variables,
/// as class_createInstance makes it: what a class's own +allocWithZone:
/// calls. The zone is ignored.
@c(_NSAllocateObject)
public func NSAllocateObject(_ cls: UnsafeMutableRawPointer?, _ extraBytes: UInt,
                             _ zone: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer? {
    guard let cls else { return nil }
    return ObjC.createInstance(cls.assumingMemoryBound(to: perry_class_storage.self), Int(extraBytes))
}

/// A copy of the object, bit for bit, with `extraBytes` more after its
/// instance variables: the object pointers in it are not retained, as
/// Foundation's are not. The zone is ignored.
@c(_NSCopyObject)
public func NSCopyObject(_ object: UnsafeMutableRawPointer?, _ extraBytes: UInt,
                         _ zone: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer? {
    guard let object, let size = ObjC.instanceSize?(ObjCRuntime.objectClass(object)?.assumingMemoryBound(to: perry_class_storage.self))
    else { return nil }
    return ObjC.copyObject?(object, size + Int(extraBytes))
}

@c(_NSDeallocateObject)
public func NSDeallocateObject(_ object: UnsafeMutableRawPointer?) {
    _ = ObjC.dispose?(object)
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
        return CFTypeIDs.of(object) ?? 1
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
    proto?.load(fromByteOffset: DarwinLayout.protocolName, as: UnsafePointer<CChar>?.self).map { Strings.autoreleased(String(cString: $0)) }
}

// MARK: - Ranges

/// "{location, length}".
@DarwinC("_NSStringFromRange")
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

@DarwinC("_NSUnionRange")
public func NSUnionRange(_ a: NSRange, _ b: NSRange) -> NSRange {
    let start = min(a.location, b.location), end = max(a.location + a.length, b.location + b.length)
    return NSRange(location: start, length: end - start)
}

/// The overlap, or an empty range where they do not meet.
@DarwinC("_NSIntersectionRange")
public func NSIntersectionRange(_ a: NSRange, _ b: NSRange) -> NSRange {
    let start = max(a.location, b.location), end = min(a.location + a.length, b.location + b.length)
    return end > start ? NSRange(location: start, length: end - start) : NSRange(location: 0, length: 0)
}

/// The physical memory, in bytes.
@c(_NSRealMemoryAvailable)
public func NSRealMemoryAvailable() -> UInt {
    let pages = sysconf(Int32(_SC_PHYS_PAGES)), size = sysconf(Int32(_SC_PAGESIZE))
    return pages > 0 && size > 0 ? UInt(pages) * UInt(size) : 0
}

@c(_NSPageSize)
public func NSPageSize() -> UInt { UInt(max(sysconf(Int32(_SC_PAGESIZE)), 0)) }

@c(_NSLogPageSize)
public func NSLogPageSize() -> UInt { UInt(NSPageSize().trailingZeroBitCount) }

// MARK: - Memory pages

/// Zeroed pages of at least `bytes`, as vm_allocate gives them; NULL when
/// there are none.
@c(_NSAllocateMemoryPages)
public func NSAllocateMemoryPages(_ bytes: UInt) -> UnsafeMutableRawPointer? {
    guard bytes > 0 else { return nil }
    guard let pages = mmap(nil, Int(bytes), PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANONYMOUS, -1, 0),
          pages != UnsafeMutableRawPointer(bitPattern: -1) else { return nil }
    return pages
}

@c(_NSDeallocateMemoryPages)
public func NSDeallocateMemoryPages(_ pointer: UnsafeMutableRawPointer?, _ bytes: UInt) {
    guard let pointer, bytes > 0 else { return }
    munmap(pointer, Int(bytes))
}

/// The bytes copied, overlapping or not.
@c(_NSCopyMemoryPages)
public func NSCopyMemoryPages(_ source: UnsafeRawPointer?, _ destination: UnsafeMutableRawPointer?, _ bytes: UInt) {
    guard let source, let destination, bytes > 0 else { return }
    memmove(destination, source, Int(bytes))
}

// MARK: - Reference counts

/// NSObject's own retain, release and retainCount, which a class that
/// overrides them calls these functions from: the root class's methods,
/// not the object's, as Darwin's _objc_rootRetain and the others are.
private enum RootReferenceCounts {
    typealias Message = @convention(c) (id?, SEL) -> UnsafeMutableRawPointer?
    typealias Count = @convention(c) (id?, SEL) -> UInt

    nonisolated(unsafe) static let rootClass: Class? = ObjC.getClass("NSObject")

    static func implementation(_ name: String) -> UnsafeRawPointer? {
        ObjC.methodImplementation(rootClass, ObjC.selector(name))
    }

    static func retain(_ object: id) {
        guard let imp = implementation("retain") else { return }
        _ = unsafeBitCast(imp, to: Message.self)(object, ObjC.selector("retain"))
    }

    static func release(_ object: id) {
        guard let imp = implementation("release") else { return }
        _ = unsafeBitCast(imp, to: Message.self)(object, ObjC.selector("release"))
    }

    static func count(_ object: id) -> UInt {
        guard let imp = implementation("retainCount") else { return 1 }
        return unsafeBitCast(imp, to: Count.self)(object, ObjC.selector("retainCount"))
    }
}

@c(_NSIncrementExtraRefCount)
public func NSIncrementExtraRefCount(_ object: UnsafeMutableRawPointer?) {
    guard let object else { return }
    RootReferenceCounts.retain(object)
}

/// Whether the object's last reference is the one going: then the count is
/// left for the caller to deallocate the object, as Darwin's does; else one
/// reference is let go.
@c(_NSDecrementExtraRefCountWasZero)
public func NSDecrementExtraRefCountWasZero(_ object: UnsafeMutableRawPointer?) -> Bool {
    guard let object else { return false }
    if RootReferenceCounts.count(object) <= 1 { return true }
    RootReferenceCounts.release(object)
    return false
}

/// The references beyond the first.
@c(_NSExtraRefCount)
public func NSExtraRefCount(_ object: UnsafeMutableRawPointer?) -> UInt {
    guard let object else { return 0 }
    let count = RootReferenceCounts.count(object)
    return count > 0 ? count - 1 : 0
}

/// YES: zones are one, as on Darwin, so an object may always be retained
/// rather than copied into another.
@c(_NSShouldRetainWithZone)
public func NSShouldRetainWithZone(_ object: UnsafeMutableRawPointer?, _ zone: UnsafeMutableRawPointer?) -> Bool { true }

// MARK: - Directories

/// A user's home directory from the password database; the current
/// user's for nil; nil for a user there is none of.
@c(_NSHomeDirectoryForUser)
public func NSHomeDirectoryForUser(_ name: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer? {
    guard let name else { return NSHomeDirectory() }
    guard let user = Strings.value(of: name), let entry = getpwnam(user), let directory = entry.pointee.pw_dir else { return nil }
    return Strings.autoreleased(String(cString: directory))
}

/// "/".
@c(_NSOpenStepRootDirectory)
public func NSOpenStepRootDirectory() -> UnsafeMutableRawPointer? { Strings.autoreleased("/") }
