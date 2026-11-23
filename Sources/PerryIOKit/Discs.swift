import Glibc
import PerryObjCInterop

// Optical discs: an IOCDMedia (or IODVDMedia) for each disc or disc image
// mounted on this machine, as a Mac game looks for its CD: it matches
// IOCDMedia, reads the media's BSD name, and finds that device among the
// mounted file systems, where libSystem's getmntinfo lists it at
// /Volumes/<its name>.
//
// A disc is a file system mounted from an optical drive (/dev/sr0), or from
// a loop device with a disc's file system (ISO 9660, UDF, HFS, HFS+), which
// is how a desktop mounts a disc image. PERRY_DISCS names others, as paths
// or Name=path pairs, colon-separated: a folder or a FUSE mount to offer as
// a disc. libPerrySystem finds the same discs in the same order
// (Sources/PerrySystem/files.c), so that media "disk2" here is /dev/disk2
// there.

struct Disc {
    var name: String
    var mount: String
    /// "disk2" for the first: disk1 is the volume at /.
    var device: String
    var isDVD: Bool
    var bytes: Int64
}

enum Discs {
    /// The first disc's registry handle; the others follow it.
    static let firstHandle: Handle = 0x1100

    private static let fileSystems: Set<String> = ["iso9660", "udf", "hfs", "hfsplus"]

    /// A mountinfo field, with its octal escapes (\040 for a space) undone.
    private static func unescaped(_ field: Substring) -> String {
        var bytes: [UInt8] = []
        let source = Array(field.utf8)
        var index = 0
        while index < source.count {
            if source[index] == UInt8(ascii: "\\"), index + 3 < source.count,
               let value = UInt8(String(decoding: source[(index + 1)...(index + 3)], as: UTF8.self), radix: 8) {
                bytes.append(value)
                index += 4
            } else {
                bytes.append(source[index])
                index += 1
            }
        }
        return String(decoding: bytes, as: UTF8.self)
    }

    private static func lastComponent(_ path: String) -> String {
        path.split(separator: "/").last.map(String.init) ?? path
    }

    private static func size(of mount: String) -> Int64 {
        var info = statvfs()
        guard statvfs(mount, &info) == 0 else { return 0 }
        return Int64(info.f_blocks) * Int64(info.f_frsize)
    }

    private static func readFile(_ path: String) -> String {
        guard let file = fopen(path, "r") else { return "" }
        defer { fclose(file) }
        var bytes: [UInt8] = []
        var buffer = [UInt8](repeating: 0, count: 4096)
        while true {
            let count = fread(&buffer, 1, buffer.count, file)
            if count <= 0 { break }
            bytes.append(contentsOf: buffer[..<count])
        }
        return String(decoding: bytes, as: UTF8.self)
    }

    /// The discs mounted now.
    static func mounted() -> [Disc] {
        var found: [(name: String, mount: String, isDVD: Bool)] = []
        if let setting = getenv("PERRY_DISCS") {
            for item in String(cString: setting).split(separator: ":") where !item.isEmpty {
                if let equals = item.firstIndex(of: "="), !item[..<equals].contains("/") {
                    found.append((String(item[..<equals]), String(item[item.index(after: equals)...]), false))
                } else {
                    found.append((lastComponent(String(item)), String(item), false))
                }
            }
        }
        // mountinfo: "id parent major:minor root mount options [tags] - type source super".
        for line in readFile("/proc/self/mountinfo").split(separator: "\n") {
            let fields = line.split(separator: " ")
            guard let dash = fields.firstIndex(of: "-"), dash >= 6 else { continue }
            let before = fields[..<dash], after = Array(fields[(dash + 1)...])
            guard after.count >= 2 else { continue }
            let type = String(after[0]), source = String(after[1])
            let optical = source.hasPrefix("/dev/sr")
            guard optical || (source.hasPrefix("/dev/loop") && fileSystems.contains(type)) else { continue }
            let mount = unescaped(before[4])
            guard !found.contains(where: { $0.mount == mount }) else { continue }
            found.append((lastComponent(mount), mount, type == "udf"))
        }
        return found.prefix(8).enumerated().map { index, disc in
            Disc(name: disc.name, mount: disc.mount, device: "disk\(index + 2)", isDVD: disc.isDVD, bytes: size(of: disc.mount))
        }
    }

    static func handles() -> [Handle] { mounted().indices.map { firstHandle + Handle($0) } }

    static func entry(_ handle: Handle) -> RegistryEntry? {
        guard handle >= firstHandle, handle < firstHandle + 8 else { return nil }
        let discs = mounted()
        let index = Int(handle - firstHandle)
        guard index < discs.count else { return nil }
        let disc = discs[index]
        return RegistryEntry(className: disc.isDVD ? "IODVDMedia" : "IOCDMedia", name: disc.name, parent: Registry.platformHandle) {
            [("BSD Name", NSObject.string(disc.device)),
             ("BSD Unit", NSNumber.make(int64: Int64(index + 2))),
             ("BSD Major", NSNumber.make(int64: 14)),
             ("BSD Minor", NSNumber.make(int64: Int64(index + 2))),
             ("Ejectable", NSNumber.make(bool: true)),
             ("Removable", NSNumber.make(bool: true)),
             ("Writable", NSNumber.make(bool: false)),
             ("Whole", NSNumber.make(bool: true)),
             ("Leaf", NSNumber.make(bool: true)),
             ("Content", NSObject.string("")),
             ("Content Hint", NSObject.string("")),
             ("Type", NSObject.string(disc.isDVD ? "DVD-ROM" : "CD-ROM")),
             ("Preferred Block Size", NSNumber.make(int64: 2048)),
             ("Size", NSNumber.make(int64: disc.bytes)),
             ("IOMediaIcon", NSMutableDictionary.of([("IOBundleResourceFile", NSObject.string("CD.icns"))])),
             ("IOProviderClass", NSObject.string(disc.isDVD ? "IODVDMedia" : "IOCDMedia"))]
        }
    }

    /// Whether a matching class finds a media of this class: itself or what
    /// it inherits from.
    static func matches(_ entry: RegistryEntry, className: String) -> Bool {
        entry.className == className || className == "IOMedia" || className == "IOService"
    }
}
