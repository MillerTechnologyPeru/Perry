import Glibc
import PerryObjCInterop

// More of Foundation's Mac-only pieces: the scripting suite registry, which
// apps subclass and replace though no script ever reaches it here; HFS
// file types as strings; and constants: an Apple event notification
// (never posted, as no Apple events arrive), Spotlight's home scope, and
// the zombie switches, which tell what Perry's runtime does.

/// NSZombieEnabled and NSDeallocateZombies, BOOL variables a program may
/// read or set. Perry's runtime keeps dead objects as zombies when
/// PERRY_OBJC_ZOMBIES is set (Darwin's reads NSZombieEnabled from the
/// environment); it never frees a zombie, so NSDeallocateZombies is NO.
/// Setting either changes nothing.
@ObjCConstants
enum ZombieSwitches {
    static let NSZombieEnabled: UInt8 = getenv("PERRY_OBJC_ZOMBIES").map { String(cString: $0) != "0" } == true ? 1 : 0
    static let NSDeallocateZombies: UInt8 = 0
}

@ObjCConstants
enum MacSupportNames {
    static let NSAppleEventManagerWillProcessFirstEventNotification = "NSAppleEventManagerWillProcessFirstEvent"
    /// Spotlight's name for the scope, as Darwin's value is.
    static let NSMetadataQueryUserHomeScope = "kMDQueryScopeHome"
}

/// An HFS type code as a file type string: its four characters (Mac OS
/// Roman) in single quotes, with trailing NULs left out ('TEXT', 'ABC').
/// Darwin makes the string as a C string, so a NUL inside the code ends
/// it there, closing quote and all; a zero code is ''.
@c(_NSFileTypeForHFSTypeCode)
public func NSFileTypeForHFSTypeCode(_ code: UInt32) -> UnsafeMutableRawPointer? {
    var characters = (0..<4).map { UInt8(truncatingIfNeeded: code >> (24 - 8 * $0)) }
    while characters.last == 0 { characters.removeLast() }
    var bytes = [UInt8(ascii: "'")] + characters + [UInt8(ascii: "'")]
    if let end = bytes.firstIndex(of: 0) { bytes.removeSubrange(end...) }
    return Strings.autoreleased(MacOSRoman.decode(bytes))
}

// MARK: - Script suites

/// The registry of an app's scripting suites. Nothing sends Apple events
/// here, so no suite is loaded from bundles and none is found by code:
/// it knows no suites, classes or commands. An app may make its own
/// registry (a subclass) the shared one.
@ObjCClass("NSScriptSuiteRegistry")
open class NSScriptSuiteRegistry: NSObject {
    nonisolated(unsafe) static var shared: id?

    @ObjCClassMethod("sharedScriptSuiteRegistry")
    static func sharedRegistry(_ cls: ObjCClass) -> UnsafeMutableRawPointer? {
        if shared == nil, let registryClass = "NSScriptSuiteRegistry".withCString({ ObjC.getClass($0) }) {
            shared = ObjC.send(ObjC.send(UnsafeMutableRawPointer(registryClass), ObjC.selector("alloc")), ObjC.selector("init"))
        }
        return shared
    }

    @ObjCClassMethod("setSharedScriptSuiteRegistry:")
    static func setSharedRegistry(_ registry: UnsafeMutableRawPointer?) {
        let old = shared
        shared = ObjC.retain(registry)
        ObjC.release(old)
    }

    @ObjCMethod("loadSuitesFromBundle:") func loadSuites(from bundle: UnsafeMutableRawPointer?) {}
    @ObjCMethod("loadSuiteWithDictionary:fromBundle:")
    func loadSuite(with dictionary: UnsafeMutableRawPointer?, from bundle: UnsafeMutableRawPointer?) {}
    @ObjCMethod("registerClassDescription:") func registerClassDescription(_ description: UnsafeMutableRawPointer?) {}
    @ObjCMethod("registerCommandDescription:") func registerCommandDescription(_ description: UnsafeMutableRawPointer?) {}

    @ObjCMethod("suiteNames") func suiteNames() -> UnsafeMutableRawPointer? { Arrays.autoreleased([]) }
    @ObjCMethod("appleEventCodeForSuite:") func appleEventCode(forSuite name: UnsafeMutableRawPointer?) -> UInt32 { 0 }
    @ObjCMethod("bundleForSuite:") func bundle(forSuite name: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer? { nil }
    @ObjCMethod("classDescriptionsInSuite:")
    func classDescriptions(inSuite name: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer? { nil }
    @ObjCMethod("commandDescriptionsInSuite:")
    func commandDescriptions(inSuite name: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer? { nil }
    @ObjCMethod("suiteForAppleEventCode:") func suite(forAppleEventCode code: UInt32) -> UnsafeMutableRawPointer? { nil }
    @ObjCMethod("classDescriptionWithAppleEventCode:")
    func classDescription(withAppleEventCode code: UInt32) -> UnsafeMutableRawPointer? { nil }
    @ObjCMethod("commandDescriptionWithAppleEventClass:andAppleEventCode:")
    func commandDescription(withAppleEventClass eventClass: UInt32, andAppleEventCode code: UInt32) -> UnsafeMutableRawPointer? { nil }
    @ObjCMethod("aeteResource:") func aeteResource(_ language: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer? { nil }
}
