import Glibc

// Mac apps' alone: armv7 runs only iOS apps, so it has none of this.
#if !arch(arm)
// HIServices' Process Manager, which ApplicationServices re-exports and the
// loader maps here on Intel: the program is the only process there is, and
// the front one. Its serial number is { 0, pid }; kCurrentProcess ({ 0, 2 })
// names it too. Apps link these weakly, as Apple deprecated them, and call
// them without checking.

private let noErr: Int16 = 0
private let paramErr: Int16 = -50
private let procNotFound: Int16 = -600

enum Processes {
    static var own: (UInt32, UInt32) { (0, UInt32(getpid())) }

    /// The serial number at `psn`, if it names this process.
    static func isOwn(_ psn: UnsafeRawPointer?) -> Bool {
        guard let psn else { return false }
        let high = psn.loadUnaligned(as: UInt32.self), low = psn.loadUnaligned(fromByteOffset: 4, as: UInt32.self)
        return high == 0 && (low == 2 || low == own.1)
    }

    static func store(_ psn: UnsafeMutableRawPointer?) {
        psn?.storeBytes(of: own.0, as: UInt32.self)
        psn?.storeBytes(of: own.1, toByteOffset: 4, as: UInt32.self)
    }

    /// The bundle's Info.plist value for `key`, read as XML text: enough
    /// for the plain strings the Process Manager reports.
    static func infoString(_ key: String) -> String? {
        guard let bundle = programBundlePath, let file = fopen(bundle + "/Contents/Info.plist", "r") else { return nil }
        defer { fclose(file) }
        var text = [UInt8]()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while true {
            let count = fread(&buffer, 1, buffer.count, file)
            if count <= 0 { break }
            text += buffer[0..<count]
        }
        let plist = String(decoding: text, as: UTF8.self)
        guard let keyRange = plist.range(of: "<key>\(key)</key>"),
              let open = plist.range(of: "<string>", range: keyRange.upperBound..<plist.endIndex),
              let close = plist.range(of: "</string>", range: open.upperBound..<plist.endIndex) else { return nil }
        return String(plist[open.upperBound..<close.lowerBound])
    }
}

@c(_GetCurrentProcess)
public func GetCurrentProcess(_ psn: UnsafeMutableRawPointer?) -> Int16 {
    guard psn != nil else { return paramErr }
    Processes.store(psn)
    return noErr
}

@c(_GetFrontProcess)
public func GetFrontProcess(_ psn: UnsafeMutableRawPointer?) -> Int16 { GetCurrentProcess(psn) }

/// OSErr GetNextProcess(ProcessSerialNumber *): from kNoProcess ({ 0, 0 })
/// this process, then procNotFound.
@c(_GetNextProcess)
public func GetNextProcess(_ psn: UnsafeMutableRawPointer?) -> Int16 {
    guard let psn else { return paramErr }
    let high = psn.loadUnaligned(as: UInt32.self), low = psn.loadUnaligned(fromByteOffset: 4, as: UInt32.self)
    guard high == 0, low == 0 else {
        psn.storeBytes(of: UInt64(0), as: UInt64.self)
        return procNotFound
    }
    Processes.store(psn)
    return noErr
}

@c(_SameProcess)
public func SameProcess(_ first: UnsafeRawPointer?, _ second: UnsafeRawPointer?, _ result: UnsafeMutablePointer<UInt8>?) -> Int16 {
    guard let first, let second, let result else { return paramErr }
    let same = (Processes.isOwn(first) && Processes.isOwn(second))
        || (first.loadUnaligned(as: UInt64.self) == second.loadUnaligned(as: UInt64.self))
    result.pointee = same ? 1 : 0
    return noErr
}

@c(_SetFrontProcess)
public func SetFrontProcess(_ psn: UnsafeRawPointer?) -> Int16 { Processes.isOwn(psn) ? noErr : procNotFound }

/// OSStatus TransformProcessType(const ProcessSerialNumber *, type): the
/// program is a foreground app already.
@c(_TransformProcessType)
public func TransformProcessType(_ psn: UnsafeRawPointer?, _ type: UInt32) -> Int32 { Processes.isOwn(psn) ? 0 : Int32(procNotFound) }

/// OSErr GetProcessInformation(const ProcessSerialNumber *, ProcessInfoRec *):
/// the record (2-byte packed): processInfoLength at 0, processName (a Str31
/// the caller gives, or NULL) at 4, processNumber at 8, processType at 16,
/// processSignature at 20, processMode at 24, processLocation at 28,
/// processSize at 32, processFreeMem at 36, processLauncher at 40,
/// processLaunchDate at 48 and processActiveTime at 52; then processAppSpec
/// (an FSSpec, or on 64-bit an FSRef, the caller gives), left as it is.
@c(_GetProcessInformation)
public func GetProcessInformation(_ psn: UnsafeRawPointer?, _ info: UnsafeMutableRawPointer?) -> Int16 {
    guard let info else { return paramErr }
    guard Processes.isOwn(psn) else { return procNotFound }
    let word = MemoryLayout<UInt>.size
    let name = info.loadUnaligned(fromByteOffset: 4, as: UnsafeMutablePointer<UInt8>?.self)
    let number = 4 + word
    if let name {
        let executable = programExecutablePath.map { String($0.split(separator: "/").last ?? "") } ?? ""
        let bytes = Array(executable.utf8.prefix(31))
        name.pointee = UInt8(bytes.count)
        for (index, byte) in bytes.enumerated() { name[1 + index] = byte }
    }
    info.storeBytes(of: Processes.own.0, toByteOffset: number, as: UInt32.self)
    info.storeBytes(of: Processes.own.1, toByteOffset: number + 4, as: UInt32.self)
    func code(_ text: String) -> UInt32 { text.utf8.prefix(4).reduce(0) { $0 << 8 | UInt32($1) } }
    let signature = Processes.infoString("CFBundleSignature").flatMap { $0.utf8.count == 4 ? code($0) : nil } ?? code("????")
    info.storeBytes(of: code("APPL"), toByteOffset: number + 8, as: UInt32.self)
    info.storeBytes(of: signature, toByteOffset: number + 12, as: UInt32.self)
    // modeCanBackground | modeNeedSuspendResume | modeHighLevelEventAware.
    info.storeBytes(of: UInt32(0x5000 | 0x400), toByteOffset: number + 16, as: UInt32.self)
    info.storeBytes(of: UInt(0), toByteOffset: number + 20, as: UInt.self)
    info.storeBytes(of: UInt32(0), toByteOffset: number + 20 + word, as: UInt32.self)
    info.storeBytes(of: UInt32(0), toByteOffset: number + 24 + word, as: UInt32.self)
    info.storeBytes(of: UInt64(0), toByteOffset: number + 28 + word, as: UInt64.self)
    return noErr
}

/// OSStatus GetProcessBundleLocation(const ProcessSerialNumber *, FSRef *):
/// the app's bundle, as CoreServices' provider makes FSRefs.
@c(_GetProcessBundleLocation)
public func GetProcessBundleLocation(_ psn: UnsafeRawPointer?, _ location: UnsafeMutableRawPointer?) -> Int32 {
    typealias MakeRef = @convention(c) (UnsafePointer<CChar>?, UnsafeMutableRawPointer?, UnsafeMutablePointer<UInt8>?) -> Int32
    guard let location else { return Int32(paramErr) }
    guard Processes.isOwn(psn) else { return Int32(procNotFound) }
    guard let bundle = programBundlePath ?? programExecutablePath, let lookup = providerSymbolLookup,
          let function = "/System/Library/Frameworks/CoreServices.framework/Versions/A/CoreServices".withCString({ library in
              "_FSPathMakeRef".withCString { lookup(library, $0) }
          }) else { return -43 }
    return bundle.withCString { unsafeBitCast(function, to: MakeRef.self)($0, location, nil) }
}

/// OSErr LaunchApplication(LaunchPBPtr): there are no other apps here.
@c(_LaunchApplication)
public func LaunchApplication(_ parameters: UnsafeMutableRawPointer?) -> Int16 { procNotFound }

/// void ExitToShell(void).
@c(_ExitToShell)
public func ExitToShell() -> Never { exit(0) }
#endif
