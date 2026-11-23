import Glibc
import PerryObjCInterop

// Mac apps' alone: armv7 runs only iOS apps, so it has none of this.
#if !arch(arm)
// PackageKit, the private framework behind macOS's installer: a flat
// package's identifier and version, read from its PackageInfo, and the
// receipts of installed packages, of which there are none, as nothing is
// installed by macOS's installer here. Xcode 4 reads its bundled packages
// so on first launch, to install those that aren't (MobileDevice, which is
// iOS device support and can't be installed on Linux).

/// A flat package (a xar archive): its PackageInfo's identifier and version.
enum FlatPackages {
    /// zlib's uncompress and bzip2's buffer decompressor, from the
    /// system's libraries.
    private static let uncompress: (@convention(c) (UnsafeMutablePointer<UInt8>, UnsafeMutablePointer<UInt>, UnsafePointer<UInt8>, UInt) -> Int32)? = {
        guard let library = dlopen("libz.so.1", RTLD_NOW), let symbol = dlsym(library, "uncompress") else { return nil }
        return unsafeBitCast(symbol, to: (@convention(c) (UnsafeMutablePointer<UInt8>, UnsafeMutablePointer<UInt>, UnsafePointer<UInt8>, UInt) -> Int32).self)
    }()
    private static let bunzip: (@convention(c) (UnsafeMutablePointer<CChar>, UnsafeMutablePointer<UInt32>, UnsafeMutablePointer<CChar>, UInt32, Int32, Int32) -> Int32)? = {
        guard let library = dlopen("libbz2.so.1.0", RTLD_NOW) ?? dlopen("libbz2.so.1", RTLD_NOW),
              let symbol = dlsym(library, "BZ2_bzBuffToBuffDecompress") else { return nil }
        return unsafeBitCast(symbol, to: (@convention(c) (UnsafeMutablePointer<CChar>, UnsafeMutablePointer<UInt32>, UnsafeMutablePointer<CChar>, UInt32, Int32, Int32) -> Int32).self)
    }()

    private static func inflate(_ bytes: ArraySlice<UInt8>, size: Int) -> [UInt8]? {
        guard let uncompress else { return nil }
        var output = [UInt8](repeating: 0, count: max(size, 1))
        var length = UInt(size)
        let status = Array(bytes).withUnsafeBufferPointer { input in
            output.withUnsafeMutableBufferPointer { uncompress($0.baseAddress!, &length, input.baseAddress!, UInt(input.count)) }
        }
        return status == 0 ? Array(output[..<Int(length)]) : nil
    }

    private static func bunzip2(_ bytes: ArraySlice<UInt8>, size: Int) -> [UInt8]? {
        guard let bunzip else { return nil }
        var input = Array(bytes).map { CChar(bitPattern: $0) }
        var output = [CChar](repeating: 0, count: max(size, 1))
        var length = UInt32(size)
        let status = output.withUnsafeMutableBufferPointer { out in
            input.withUnsafeMutableBufferPointer { bunzip(out.baseAddress!, &length, $0.baseAddress!, UInt32($0.count), 0, 0) }
        }
        return status == 0 ? output[..<Int(length)].map { UInt8(bitPattern: $0) } : nil
    }

    private static func bigEndian(_ bytes: [UInt8], _ offset: Int, _ count: Int) -> Int {
        bytes[offset..<offset + count].reduce(0) { $0 << 8 | Int($1) }
    }

    /// The text between `<tag>` and `</tag>` in `xml`.
    private static func element(_ tag: String, in xml: Substring) -> Substring? {
        guard let open = xml.firstRange(of: "<\(tag)>"), let close = xml[open.upperBound...].firstRange(of: "</\(tag)>") else { return nil }
        return xml[open.upperBound..<close.lowerBound]
    }

    /// An attribute's value in a tag's text.
    static func attribute(_ name: String, in tag: Substring) -> String? {
        guard let start = tag.firstRange(of: " \(name)=\"") else { return nil }
        let rest = tag[start.upperBound...]
        return rest.firstIndex(of: "\"").map { String(rest[..<$0]) }
    }

    /// The PackageInfo of the flat package at `path`, as text.
    static func packageInfo(_ path: String) -> String? {
        guard let file = fopen(path, "rb") else { return nil }
        defer { fclose(file) }
        fseek(file, 0, SEEK_END)
        let size = ftell(file)
        fseek(file, 0, SEEK_SET)
        guard size > 28 else { return nil }
        var bytes = [UInt8](repeating: 0, count: size)
        guard fread(&bytes, 1, size, file) == size, bytes[0..<4] == [0x78, 0x61, 0x72, 0x21] else { return nil }   // "xar!"
        let headerSize = bigEndian(bytes, 4, 2)
        let tocCompressed = bigEndian(bytes, 8, 8), tocSize = bigEndian(bytes, 16, 8)
        guard headerSize + tocCompressed <= size,
              let tocBytes = inflate(bytes[headerSize..<headerSize + tocCompressed], size: tocSize) else { return nil }
        let toc = String(decoding: tocBytes, as: UTF8.self)
        let heap = headerSize + tocCompressed
        // The top-level file named PackageInfo, and its data.
        var search = toc[...]
        while let start = search.firstRange(of: "<file id=") {
            let rest = search[start.upperBound...]
            guard let end = rest.firstRange(of: "</file>") else { break }
            let entry = rest[..<end.lowerBound]
            search = rest[end.upperBound...]
            guard entry.contains("<name>PackageInfo</name>"), let data = element("data", in: entry),
                  let offset = element("offset", in: data).flatMap({ Int($0) }),
                  let length = element("length", in: data).flatMap({ Int($0) }),
                  let extracted = element("size", in: data).flatMap({ Int($0) }),
                  heap + offset + length <= size else { continue }
            let stored = bytes[heap + offset..<heap + offset + length]
            let contents: [UInt8]?
            if data.contains("application/x-bzip2") {
                contents = bunzip2(stored, size: extracted)
            } else if data.contains("application/x-gzip") || data.contains("application/zlib") {
                contents = inflate(stored, size: extracted)
            } else {
                contents = Array(stored)
            }
            return contents.map { String(decoding: $0, as: UTF8.self) }
        }
        return nil
    }
}

final class PackageState: @unchecked Sendable {
    let path: String
    let identifier: String
    let version: String

    init(path: String, identifier: String, version: String) {
        self.path = path
        self.identifier = identifier
        self.version = version
    }
}

/// PKPackage: a package on disk.
@ObjCClass("PKPackage")
public final class PKPackage: NSObject {
    static let states = StateTable<PackageState>()

    var state: PackageState? { PKPackage.states[objcObject] }

    /// The package at `path` (+0), or nil when it isn't a flat package
    /// with a PackageInfo naming its identifier.
    @ObjCClassMethod("packageWithPath:")
    static func package(path: String?) -> NSObject? {
        guard let path, let info = FlatPackages.packageInfo(path),
              let start = info.firstRange(of: "<pkg-info"), let end = info[start.upperBound...].firstIndex(of: ">") else { return nil }
        let tag = info[start.lowerBound..<end]
        guard let identifier = FlatPackages.attribute("identifier", in: tag) else { return nil }
        let object = NSObject(objCOwned: objCClass.ownedInstance())
        states.set(object.objcObject, PackageState(path: path, identifier: identifier,
                                                   version: FlatPackages.attribute("version", in: tag) ?? "0"))
        _ = ObjCRuntime.autorelease(ObjCRuntime.retain(object.objcObject))
        return object
    }

    @ObjCMethod("dealloc")
    func dealloc() {
        PKPackage.states.remove(objcObject)
        ObjCRuntime.superDealloc(objcObject, definedOn: PKPackage.objCClass.pointer)
    }

    @ObjCMethod("packageIdentifier") func packageIdentifier() -> String? { state?.identifier }
    @ObjCMethod("packageVersion") func packageVersion() -> String? { state?.version }
    @ObjCMethod("packagePath") func packagePath() -> String? { state?.path }
    /// The bundles the payload installs: none are read here.
    @ObjCMethod("enumerateBundleComponentsUsingBlock:") func enumerateBundleComponents(_ block: UnsafeRawPointer?) {}
}

/// PKReceipt: an installed package's receipt. Nothing has been installed
/// by macOS's installer here, so there are none.
@ObjCClass("PKReceipt")
public final class PKReceipt: NSObject {
    @ObjCClassMethod("receiptWithIdentifier:volume:")
    static func receipt(identifier: String?, volume: String?) -> NSObject? { nil }

    @ObjCClassMethod("receiptsOnVolumeAtPath:")
    static func receipts(volume: String?) -> NSObject? { NSMutableArray.of([NSObject]()) }
}
#endif
