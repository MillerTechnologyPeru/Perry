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

@c(_NSStringFromProtocol)
public func NSStringFromProtocol(_ proto: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer? {
    // protocol_t: isa, then the name.
    proto?.load(fromByteOffset: 8, as: UnsafePointer<CChar>?.self).map { Strings.autoreleased(String(cString: $0)) }
}
