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
    nonisolated(unsafe) static var sdkVersion = NSOperatingSystemVersion(majorVersion: 17, minorVersion: 0, patchVersion: 0)

    static func start(_ info: perry_startup_info) {
        arguments = (0..<Int(info.argc)).compactMap { info.argv?[$0].map { String(cString: $0) } }
        if let progname = info.progname { name = String(cString: progname) }
        if let path = info.executable_path { executablePath = String(cString: path) }
        bundlePath = info.bundle_path.map { String(cString: $0) }
        if let header = info.main_header, let version = buildSDK(header) { sdkVersion = version }
    }

    /// LC_BUILD_VERSION's sdk field: xxxx.yy.zz in nibbles.
    private static func buildSDK(_ header: UnsafeRawPointer) -> NSOperatingSystemVersion? {
        let count = Int(header.load(fromByteOffset: 16, as: UInt32.self))
        var command = header + 32
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
    @ObjCMethod("physicalMemory") func physicalMemory() -> UInt64 { Self.info.physicalMemory }
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
