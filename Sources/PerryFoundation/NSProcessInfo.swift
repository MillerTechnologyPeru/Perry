import CPerryFoundation
import FoundationEssentials
import Glibc
import PerryInterface
import PerryObjCInterop

/// What the loader tells Foundation about the program: its own arguments
/// and paths, not perry's.
enum Process {
    nonisolated(unsafe) static var arguments: [String] = []
    nonisolated(unsafe) static var name = "perry"
    nonisolated(unsafe) static var executablePath = ""
    nonisolated(unsafe) static var bundlePath: String?
    /// The SDK the main executable was built with, from LC_BUILD_VERSION.
    nonisolated(unsafe) static var sdkVersion = NSOperatingSystemVersion(majorVersion: 18, minorVersion: 0, patchVersion: 0)

    static func start(_ info: perry_startup_info) {
        arguments = (0..<Int(info.argc)).compactMap { info.argv?[$0].map { String(cString: $0) } }
        if let progname = info.progname { name = String(cString: progname) }
        if let path = info.executable_path { executablePath = String(cString: path) }
        bundlePath = info.bundle_path.map { String(cString: $0) }
        if let header = info.main_header, let version = buildSDK(header) { sdkVersion = version }
        // PERRY_OS_VERSION ("13.7") is the iOS version to be, in place of
        // the one the app was built for.
        if let setting = getenv("PERRY_OS_VERSION") {
            let parts = String(cString: setting).split(separator: ".").compactMap { Int($0) }
            if let major = parts.first {
                sdkVersion = NSOperatingSystemVersion(majorVersion: major, minorVersion: parts.count > 1 ? parts[1] : 0,
                                                      patchVersion: parts.count > 2 ? parts[2] : 0)
            }
        }
    }

    /// LC_BUILD_VERSION's sdk field: xxxx.yy.zz in nibbles.
    private static func buildSDK(_ header: UnsafeRawPointer) -> NSOperatingSystemVersion? {
        let count = Int(header.load(fromByteOffset: 16, as: UInt32.self))
        var command = header + DarwinLayout.machHeaderSize(header)
        for _ in 0..<count {
            let cmd = command.load(as: UInt32.self)
            if cmd == 0x32 {                        // LC_BUILD_VERSION
                let sdk = command.load(fromByteOffset: 16, as: UInt32.self)
                return NSOperatingSystemVersion(majorVersion: Int(sdk >> 16), minorVersion: Int((sdk >> 8) & 0xff),
                                                patchVersion: Int(sdk & 0xff))
            }
            command += Int(command.load(fromByteOffset: 4, as: UInt32.self))
        }
        return nil
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

    @ObjCMethod("environment")
    func environment() -> NSDictionary {
        var entries: [(key: id, value: id)] = []
        var cursor = environ
        while let entry = cursor.pointee {
            let text = String(cString: entry)
            if let equals = text.firstIndex(of: "=") {
                entries.append((key: Strings.autoreleased(String(text[..<equals])),
                                value: Strings.autoreleased(String(text[text.index(after: equals)...]))))
            }
            cursor += 1
        }
        return Dictionaries.owned(entries)
    }

    @ObjCMethod("processName") func processName() -> String { Process.name }
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

    /// The iOS version the app was built for.
    @ObjCMethod("operatingSystemVersion")
    func operatingSystemVersion() -> NSOperatingSystemVersion { Process.sdkVersion }

    @ObjCMethod("operatingSystemVersionString")
    func operatingSystemVersionString() -> String {
        let version = Process.sdkVersion
        return "Version \(version.majorVersion).\(version.minorVersion)"
            + (version.patchVersion > 0 ? ".\(version.patchVersion)" : "") + " (Perry)"
    }

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
