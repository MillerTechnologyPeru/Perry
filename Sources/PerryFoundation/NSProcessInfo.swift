import CPerryFoundation
import FoundationEssentials
import Glibc
import PerryInterface
import PerryObjCInterop
import Synchronization

/// What the loader tells Foundation about the program: its own arguments
/// and paths, not perry's.
enum Process {
    nonisolated(unsafe) static var arguments: [String] = []
    nonisolated(unsafe) static var name = "perry"
    nonisolated(unsafe) static var executablePath = ""
    nonisolated(unsafe) static var bundlePath: String?
    /// The main executable's Mach-O header, once the loader has mapped it.
    nonisolated(unsafe) static var mainHeader: UnsafeRawPointer?
    /// The SDK the main executable was built with, from LC_BUILD_VERSION.
    nonisolated(unsafe) static var sdkVersion = NSOperatingSystemVersion(majorVersion: 18, minorVersion: 0, patchVersion: 0)

    static func start(_ info: perry_startup_info) {
        arguments = (0..<Int(info.argc)).compactMap { info.argv?[$0].map { String(cString: $0) } }
        if let progname = info.progname { name = String(cString: progname) }
        if let path = info.executable_path { executablePath = String(cString: path) }
        bundlePath = info.bundle_path.map { String(cString: $0) }
        mainHeader = info.main_header.map { UnsafeRawPointer($0) }
        if let header = info.main_header {
            // MH_MAGIC_64: a 64-bit program.
            let is64Bit = UnsafeRawPointer(header).load(as: UInt32.self) == 0xfeed_facf
            sdkVersion = buildSDK(header) ?? (is64Bit ? legacyMac64Version : legacyMacVersion)
        }
        // PERRY_OS_VERSION ("13.7", "10.6.8") is the version to be, in
        // place of the one the app was built for.
        if let setting = getenv("PERRY_OS_VERSION") {
            let parts = String(cString: setting).split(separator: ".").compactMap { Int($0) }
            if let major = parts.first {
                sdkVersion = NSOperatingSystemVersion(majorVersion: major, minorVersion: parts.count > 1 ? parts[1] : 0,
                                                      patchVersion: parts.count > 2 ? parts[2] : 0)
            }
        }
    }

    /// The system a Mac program with no version in it runs on: one built
    /// with Mac OS X 10.6's SDK or before, which named none. It sees Mac OS X
    /// 10.5, as programs of that time knew it.
    static let legacyMacVersion = NSOperatingSystemVersion(majorVersion: 10, minorVersion: 5, patchVersion: 8)

    /// The same for a 64-bit one: Mac OS X 10.6, the first system most
    /// 64-bit programs were built for, and the one whose functions they
    /// check for before using them (SDL 1.2's display modes), having no
    /// older ones in 64 bits to fall back on.
    static let legacyMac64Version = NSOperatingSystemVersion(majorVersion: 10, minorVersion: 6, patchVersion: 8)

    /// The SDK the program was built with: LC_BUILD_VERSION's, or
    /// LC_VERSION_MIN_MACOSX's or LC_VERSION_MIN_IPHONEOS's (xxxx.yy.zz in
    /// nibbles); nil for a program that names none.
    private static func buildSDK(_ header: UnsafeRawPointer) -> NSOperatingSystemVersion? {
        func version(_ sdk: UInt32) -> NSOperatingSystemVersion {
            NSOperatingSystemVersion(majorVersion: Int(sdk >> 16), minorVersion: Int((sdk >> 8) & 0xff), patchVersion: Int(sdk & 0xff))
        }
        let count = Int(header.load(fromByteOffset: 16, as: UInt32.self))
        var command = header + DarwinLayout.machHeaderSize(header)
        for _ in 0..<count {
            switch command.load(as: UInt32.self) {
            case 0x32:                              // LC_BUILD_VERSION
                return version(command.load(fromByteOffset: 16, as: UInt32.self))
            case 0x24, 0x25:                        // LC_VERSION_MIN_MACOSX, LC_VERSION_MIN_IPHONEOS
                let sdk = command.load(fromByteOffset: 12, as: UInt32.self)
                // An SDK of 0 is a linker's that didn't name it: the
                // minimum version stands for it.
                return version(sdk != 0 ? sdk : command.load(fromByteOffset: 8, as: UInt32.self))
            default:
                break
            }
            command += Int(command.load(fromByteOffset: 4, as: UInt32.self))
        }
        return nil
    }

    /// Mac OS X's build of the version, for SystemVersion.plist.
    static var buildVersion: String {
        switch (sdkVersion.majorVersion, sdkVersion.minorVersion) {
        case (10, 5): "9L31a"
        case (10, 6): "10K549"
        default: "Perry"
        }
    }

    nonisolated(unsafe) static var processInfo: id!

}

/// NSProcessInfo.
@ObjCClass("NSProcessInfo")
public final class NSProcessInfo: NSObject {
    /// Set-up after the class is defined.
    override public class func didDefineObjCClass(_ cls: ObjCClass) {
        Process.processInfo = ObjC.createInstance(cls.storage, 0)
    }

    private static var info: ProcessInfo { ProcessInfo.processInfo }

    @ObjCClassMethod("processInfo")
    static func shared() -> UnsafeMutableRawPointer? { Process.processInfo }

    @ObjCMethod("arguments")
    func arguments() -> NSArray { Arrays.owned(Process.arguments.map { Strings.autoreleased($0) }) }

    /// The last dictionary -environment made, and the environ entries it
    /// was made from: setenv and unsetenv change the entries (a changed
    /// value is a new string), so an unchanged list is an unchanged
    /// environment. Ad SDKs ask for the environment many times a second (to
    /// tell a simulator by SIMULATOR_DEVICE_NAME); a dictionary of fresh
    /// strings each time filled memory faster than pools drained.
    private static let environmentCache = Mutex<(entries: [UInt], dictionary: UInt)>(([], 0))

    @ObjCMethod("environment")
    func environment() -> NSDictionary {
        var current: [UInt] = []
        var cursor = environ
        while let entry = cursor.pointee {
            current.append(UInt(bitPattern: entry))
            cursor += 1
        }
        let dictionary = Self.environmentCache.withLock { cache -> id in
            if cache.dictionary != 0, cache.entries == current, let cached = UnsafeMutableRawPointer(bitPattern: cache.dictionary) {
                return ObjC.retain(cached)!
            }
            var entries: [(key: id, value: id)] = []
            for address in current {
                let text = String(cString: UnsafePointer<CChar>(bitPattern: address)!)
                if let equals = text.firstIndex(of: "=") {
                    entries.append((key: Strings.autoreleased(String(text[..<equals])),
                                    value: Strings.autoreleased(String(text[text.index(after: equals)...]))))
                }
            }
            let made = Dictionaries.make(entries)
            if let old = UnsafeMutableRawPointer(bitPattern: cache.dictionary) { ObjC.release(old) }
            cache = (current, UInt(bitPattern: ObjC.retain(made)!))
            return made
        }
        return NSDictionary(objCOwned: dictionary)
    }

    @ObjCMethod("processName") func processName() -> String { Process.name }
    /// The name the process goes by for Foundation (defaults domains and
    /// the like); nil leaves it as it is.
    @ObjCMethod("setProcessName:") func setProcessName(_ name: String?) { if let name { Process.name = name } }
    @ObjCMethod("processIdentifier") func processIdentifier() -> Int32 { getpid() }
    @ObjCMethod("globallyUniqueString") func globallyUniqueString() -> String { Self.info.globallyUniqueString }
    @ObjCMethod("hostName") func hostName() -> String { Self.info.hostName }
    /// The machine's memory, as hw.memsize reports it: at most 1 GB to a
    /// 32-bit program, which takes more for a fault. Counted here, as
    /// swift-foundation's count of it overflows a 32-bit Int.
    @ObjCMethod("physicalMemory")
    func physicalMemory() -> UInt64 {
        let pages = UInt64(max(sysconf(Int32(_SC_PHYS_PAGES)), 0)), size = UInt64(max(sysconf(Int32(_SC_PAGESIZE)), 0))
        let bytes = pages * size
        return MemoryLayout<Int>.size == 4 ? min(bytes, 1 << 30) : bytes
    }
    @ObjCMethod("processorCount") func processorCount() -> UInt { UInt(Self.info.processorCount) }
    @ObjCMethod("activeProcessorCount") func activeProcessorCount() -> UInt { UInt(Self.info.activeProcessorCount) }
    @ObjCMethod("systemUptime") func systemUptime() -> Double { Self.info.systemUptime }
    @ObjCMethod("thermalState") func thermalState() -> Int { 0 }
    @ObjCMethod("isLowPowerModeEnabled") func isLowPowerModeEnabled() -> Bool { false }
    @ObjCMethod("isMacCatalystApp") func isMacCatalystApp() -> Bool { false }
    @ObjCMethod("isiOSAppOnMac") func isiOSAppOnMac() -> Bool { false }
    /// iOS 26.1's: an iPhone or iPad app running on visionOS; it never is.
    @ObjCMethod("isiOSAppOnVision") func isiOSAppOnVision() -> Bool { false }

    /// NSMACHOperatingSystem (5), which Darwin always answers.
    @ObjCMethod("operatingSystem") func operatingSystem() -> UInt { 5 }
    @ObjCMethod("operatingSystemName") func operatingSystemName() -> String { "NSMACHOperatingSystem" }

    /// macOS's: the user's short and full names, as NSUserName and
    /// NSFullUserName give them.
    @ObjCMethod("userName") func userName() -> UnsafeMutableRawPointer? { NSUserName() }
    @ObjCMethod("fullUserName") func fullUserName() -> UnsafeMutableRawPointer? { NSFullUserName() }

    /// macOS's automatic termination, which nothing here does: the setting
    /// is kept for the asking.
    nonisolated(unsafe) private static var automaticTermination = false
    @ObjCMethod("automaticTerminationSupportEnabled")
    func automaticTerminationSupportEnabled() -> Bool { Self.automaticTermination }
    @ObjCMethod("setAutomaticTerminationSupportEnabled:")
    func setAutomaticTerminationSupportEnabled(_ enabled: Bool) { Self.automaticTermination = enabled }

    /// The iOS version the app was built for.
    @ObjCMethod("operatingSystemVersion")
    func operatingSystemVersion() -> NSOperatingSystemVersion { Process.sdkVersion }

    @ObjCMethod("operatingSystemVersionString")
    func operatingSystemVersionString() -> String {
        let version = Process.sdkVersion
        return "Version \(version.majorVersion).\(version.minorVersion)"
            + (version.patchVersion > 0 ? ".\(version.patchVersion)" : "") + " (Perry)"
    }

    /// A process is ended as it ends here: nothing terminates it suddenly.
    @ObjCMethod("disableSuddenTermination") func disableSuddenTermination() {}
    @ObjCMethod("enableSuddenTermination") func enableSuddenTermination() {}
    @ObjCMethod("disableAutomaticTermination:") func disableAutomaticTermination(_ reason: ObjCObject?) {}
    @ObjCMethod("enableAutomaticTermination:") func enableAutomaticTermination(_ reason: ObjCObject?) {}

    @ObjCMethod("isOperatingSystemAtLeastVersion:")
    func isAtLeast(_ version: NSOperatingSystemVersion) -> Bool {
        let current = Process.sdkVersion
        return (current.majorVersion, current.minorVersion, current.patchVersion)
            >= (version.majorVersion, version.minorVersion, version.patchVersion)
    }

    // MARK: Activities

    /// An activity's token: nothing here sleeps or throttles an app, so it
    /// only has to be an object the app keeps until it ends the activity.
    @ObjCMethod("beginActivityWithOptions:reason:")
    func beginActivity(options: UInt64, reason: id?) -> id? { Arrays.autoreleased([]) }

    @ObjCMethod("endActivity:") func endActivity(_ activity: id?) {}

    /// iOS's: the block runs asynchronously, on a global queue, with NO for
    /// expired; nothing suspends the app here, so it is never called again
    /// with YES.
    @ObjCMethod("performExpiringActivityWithReason:usingBlock:")
    func performExpiringActivity(reason: id?, block: ObjCObject?) {
        guard let block, let copied = ObjC.retainBlock(block.id), let queue = Dispatch.globalQueue?(0x15, 0) else { return }
        let delivered = DispatchedWork.async(queue) {
            Blocks.invoke(copied, as: (@convention(c) (id, Bool) -> Void).self)(copied, false)
            ObjC.release(copied)
        }
        if !delivered { ObjC.release(copied) }
    }

    /// Runs the block at once, on this thread.
    @ObjCMethod("performActivityWithOptions:reason:usingBlock:")
    func performActivity(options: UInt64, reason: id?, block: ObjCBlock?) {
        typealias Invoke = @convention(c) (UnsafeMutableRawPointer) -> Void
        guard let block else { return }
        block.function(as: Invoke.self)(block.object)
    }

    // The shared instance lives for the whole process.
    @ObjCMethod("retain") func retain() -> UnsafeMutableRawPointer { objcObject }
    @ObjCMethod("release", types: "Vv16@0:8") func release() {}
    @ObjCMethod("autorelease") func autorelease() -> UnsafeMutableRawPointer { objcObject }
}

/// Posted when Low Power Mode or the thermal state changes, which they
/// never do here.
@ObjCConstants
enum ProcessInfoConstants {
    static let NSProcessInfoPowerStateDidChangeNotification = "NSProcessInfoPowerStateDidChangeNotification"
    static let NSProcessInfoThermalStateDidChangeNotification = "NSProcessInfoThermalStateDidChangeNotification"
}
