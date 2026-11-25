import Glibc
import PerryObjCInterop

// Mac apps' alone: armv7 runs only iOS apps, so it has none of this.
#if !arch(arm)
// DiskArbitration: sessions, and disks made from a volume's mount point or
// a BSD name, described as Darwin describes them. The disks are the volumes
// Perry's statfs and getmntinfo report: the one at / ("Macintosh HD", from
// disk1s1), which every file of this machine's own is on, and the discs
// mounted, each at /Volumes/<its name> from disk<n>s1, n from 2. Each is
// described by the file system it really is here, from /proc/self/mountinfo
// (the volume at / by the one the home is on, whose sizes statfs reports):
// its type as the volume's kind (with Darwin's names where there is one:
// msdos, cd9660, hfs, nfs, smbfs), its UUID from /dev/disk/by-uuid, and its
// drive's model, vendor and removability from /sys/class/block. A network
// file system's mount point (NFS, SMB, sshfs…) is a network volume of its
// own, with no BSD name or media, as Darwin's network volumes have none.
// Sessions never call back: no disks come and go here.

/// CFTypeIDs no CoreFoundation type has.
private let sessionTypeID: UInt = 0x4441_5365   // 'DASe'
private let diskTypeID: UInt = 0x4441_4469      // 'DADi'

@ObjCConstants
enum DiskDescriptionKeys {
    static let kDADiskDescriptionVolumeKindKey = "DAVolumeKind"
    static let kDADiskDescriptionVolumeMountableKey = "DAVolumeMountable"
    static let kDADiskDescriptionVolumeNameKey = "DAVolumeName"
    static let kDADiskDescriptionVolumeNetworkKey = "DAVolumeNetwork"
    static let kDADiskDescriptionVolumePathKey = "DAVolumePath"
    static let kDADiskDescriptionVolumeTypeKey = "DAVolumeType"
    static let kDADiskDescriptionVolumeUUIDKey = "DAVolumeUUID"
    static let kDADiskDescriptionMediaBlockSizeKey = "DAMediaBlockSize"
    static let kDADiskDescriptionMediaBSDMajorKey = "DAMediaBSDMajor"
    static let kDADiskDescriptionMediaBSDMinorKey = "DAMediaBSDMinor"
    static let kDADiskDescriptionMediaBSDNameKey = "DAMediaBSDName"
    static let kDADiskDescriptionMediaBSDUnitKey = "DAMediaBSDUnit"
    static let kDADiskDescriptionMediaContentKey = "DAMediaContent"
    static let kDADiskDescriptionMediaEjectableKey = "DAMediaEjectable"
    static let kDADiskDescriptionMediaIconKey = "DAMediaIcon"
    static let kDADiskDescriptionMediaKindKey = "DAMediaKind"
    static let kDADiskDescriptionMediaLeafKey = "DAMediaLeaf"
    static let kDADiskDescriptionMediaNameKey = "DAMediaName"
    static let kDADiskDescriptionMediaPathKey = "DAMediaPath"
    static let kDADiskDescriptionMediaRemovableKey = "DAMediaRemovable"
    static let kDADiskDescriptionMediaSizeKey = "DAMediaSize"
    static let kDADiskDescriptionMediaTypeKey = "DAMediaType"
    static let kDADiskDescriptionMediaUUIDKey = "DAMediaUUID"
    static let kDADiskDescriptionMediaWholeKey = "DAMediaWhole"
    static let kDADiskDescriptionMediaWritableKey = "DAMediaWritable"
    static let kDADiskDescriptionMediaEncryptedKey = "DAMediaEncrypted"
    static let kDADiskDescriptionDeviceGUIDKey = "DADeviceGUID"
    static let kDADiskDescriptionDeviceInternalKey = "DADeviceInternal"
    static let kDADiskDescriptionDeviceModelKey = "DADeviceModel"
    static let kDADiskDescriptionDevicePathKey = "DADevicePath"
    static let kDADiskDescriptionDeviceProtocolKey = "DADeviceProtocol"
    static let kDADiskDescriptionDeviceRevisionKey = "DADeviceRevision"
    static let kDADiskDescriptionDeviceUnitKey = "DADeviceUnit"
    static let kDADiskDescriptionDeviceVendorKey = "DADeviceVendor"
    static let kDADiskDescriptionBusNameKey = "DABusName"
    static let kDADiskDescriptionBusPathKey = "DABusPath"
}

@ObjCWrapper("NSURL")
class DiskURL: NSObject {
    @ObjCClassMethod("fileURLWithPath:isDirectory:") static func make(path: String, isDirectory: Bool) -> DiskURL
    @ObjCMethod("path") func path() -> String?
}

@ObjCWrapper("NSNumber")
class DiskNumber: NSObject {
    @ObjCClassMethod("numberWithLongLong:") static func make(_ value: Int64) -> DiskNumber
    @ObjCClassMethod("numberWithBool:") static func make(bool value: Bool) -> DiskNumber
}

// MARK: - This machine's file systems

/// A file system mounted here, from /proc/self/mountinfo.
struct HostMount {
    var mountPoint: String
    var type: String
    var source: String
}

enum HostMounts {
    /// mountinfo's fields undo \040-style escapes.
    static func unescaped(_ field: Substring) -> String {
        var bytes: [UInt8] = []
        let units = Array(field.utf8)
        var index = 0
        while index < units.count {
            if units[index] == UInt8(ascii: "\\"), index + 3 < units.count,
               let value = UInt8(String(decoding: units[(index + 1)...(index + 3)], as: UTF8.self), radix: 8) {
                bytes.append(value)
                index += 4
            } else {
                bytes.append(units[index])
                index += 1
            }
        }
        return String(decoding: bytes, as: UTF8.self)
    }

    static func all() -> [HostMount] {
        guard let file = fopen("/proc/self/mountinfo", "r") else { return [] }
        defer { fclose(file) }
        var mounts: [HostMount] = []
        var line = [CChar](repeating: 0, count: 8192)
        while fgets(&line, Int32(line.count), file) != nil {
            let text = String(cString: line)
            // "id parent major:minor root mount options [tags] - type source super".
            let parts = text.split(separator: " ", omittingEmptySubsequences: false)
            guard parts.count > 4, let dash = parts.firstIndex(of: "-"), dash + 2 < parts.count else { continue }
            mounts.append(HostMount(mountPoint: unescaped(parts[4]), type: String(parts[dash + 1]), source: unescaped(parts[dash + 2])))
        }
        return mounts
    }

    /// The file system a path is on: the deepest mount point over it.
    static func containing(_ path: String) -> HostMount? {
        var resolved = [CChar](repeating: 0, count: Int(PATH_MAX) + 1)
        let real = realpath(path, &resolved) != nil ? String(cString: resolved) : path
        return all().filter { mount in
            mount.mountPoint == "/" || real == mount.mountPoint || real.hasPrefix(mount.mountPoint + "/")
        }.reversed().max { $0.mountPoint.count < $1.mountPoint.count }
    }

    static let networkTypes: Set<String> = [
        "nfs", "nfs4", "cifs", "smb3", "smbfs", "ncpfs", "afs", "ceph", "glusterfs", "lustre", "9p", "prl_fs", "vboxsf",
        "fuse.sshfs", "fuse.rclone", "fuse.s3fs", "fuse.glusterfs", "fuse.davfs2", "davfs",
    ]

    /// Darwin's name for a file system type, where it has one.
    static func kind(_ type: String) -> String {
        switch type {
        case "nfs", "nfs4": return "nfs"
        case "cifs", "smb3": return "smbfs"
        case "vfat", "fat": return "msdos"
        case "iso9660": return "cd9660"
        case "hfsplus": return "hfs"
        case "ntfs3": return "ntfs"
        default: return type
        }
    }

    /// A file's first line, without its line ending.
    static func read(_ path: String) -> String? {
        guard let file = fopen(path, "r") else { return nil }
        defer { fclose(file) }
        var line = [CChar](repeating: 0, count: 512)
        guard fgets(&line, Int32(line.count), file) != nil else { return nil }
        var text = String(cString: line)
        while let last = text.last, last.isWhitespace { text.removeLast() }
        while let first = text.first, first.isWhitespace { text.removeFirst() }
        return text
    }

    static func resolved(_ path: String) -> String? {
        var buffer = [CChar](repeating: 0, count: Int(PATH_MAX) + 1)
        return realpath(path, &buffer) != nil ? String(cString: buffer) : nil
    }

    /// The UUID of the file system on a device, from /dev/disk/by-uuid,
    /// when it is one of the 128-bit kind (ext4's, Btrfs's, XFS's).
    static func uuid(of source: String) -> String? {
        guard source.hasPrefix("/dev/"), let device = resolved(source), let directory = opendir("/dev/disk/by-uuid") else { return nil }
        defer { closedir(directory) }
        while let entry = readdir(directory) {
            let name = withUnsafeBytes(of: entry.pointee.d_name) { raw in String(decoding: raw.prefix { $0 != 0 }, as: UTF8.self) }
            guard name.count == 36, name.split(separator: "-").map(\.count) == [8, 4, 4, 4, 12],
                  resolved("/dev/disk/by-uuid/" + name) == device else { continue }
            return name.uppercased()
        }
        return nil
    }

    /// The drive a device is on, in /sys/class/block: its model, vendor,
    /// whether it is removable, and its size in bytes.
    static func drive(of source: String) -> (model: String?, vendor: String?, removable: Bool, size: Int64?)? {
        guard source.hasPrefix("/dev/"), let device = resolved(source) else { return nil }
        let name = String(device.split(separator: "/").last ?? "")
        var block = "/sys/class/block/" + name
        guard access(block, F_OK) == 0 else { return nil }
        // A partition's drive is the block device over it.
        if access(block + "/partition", F_OK) == 0, let real = resolved(block) {
            let parent = real.split(separator: "/").dropLast().last.map(String.init) ?? name
            block = "/sys/class/block/" + parent
        }
        let model = read(block + "/device/model").flatMap { $0.isEmpty ? nil : $0 }
        let vendor = read(block + "/device/vendor").flatMap { $0.isEmpty ? nil : $0 }
        let sectors = read(block + "/size").flatMap { Int64($0) }
        return (model, vendor, read(block + "/removable") == "1", sectors.map { $0 * 512 })
    }
}

// MARK: - Disks

final class DiskState {
    /// "disk1s1", "disk1"; nil for a network volume.
    var bsdName: String?
    /// False for a BSD name that names no disk here, which has no
    /// description, as Darwin makes a disk for any name.
    var known = true
    var whole = false
    var volumeName = ""
    /// The volume's path as the program sees it.
    var volumePath = "/"
    var kind = ""
    var network = false
    var uuid: String?
    var writable = true
    var removable = false
    var ejectable = false
    var model: String?
    var vendor: String?
    var mediaSize: Int64 = 0
    /// The whole drive's size, when /sys/class/block has it.
    var driveSize: Int64?
    var blockSize: Int64 = 512
    var major: Int64 = 0
    var minor: Int64 = 0
    /// The BSD name as C text, for DADiskGetBSDName, which hands it out.
    private(set) lazy var bsdNameText: UnsafeMutablePointer<CChar>? = bsdName.flatMap { strdup($0) }

    var unit: Int64 {
        guard let bsdName else { return 0 }
        return Int64(bsdName.dropFirst(4).prefix { character in character.isNumber }) ?? 0
    }

    deinit { free(bsdNameText) }

    /// The whole disk this volume's partition is on: "disk1" for "disk1s1".
    func wholeDisk() -> DiskState {
        let other = DiskState()
        other.bsdName = bsdName.map { name in "disk" + name.dropFirst(4).prefix { character in character.isNumber } }
        other.whole = true
        other.volumeName = volumeName
        other.volumePath = volumePath
        (other.kind, other.network, other.uuid, other.writable) = (kind, network, uuid, writable)
        (other.removable, other.ejectable, other.model, other.vendor) = (removable, ejectable, model, vendor)
        (other.mediaSize, other.blockSize, other.major, other.minor) = (driveSize ?? mediaSize, blockSize, major, minor)
        return other
    }
}

@ObjCClass("PerryDASession")
public final class DiskArbitrationSession: NSObject {
    @ObjCMethod("_cfTypeID") func cfTypeID() -> UInt { sessionTypeID }
}

@ObjCClass("PerryDADisk")
public final class DiskArbitrationDisk: NSObject {
    static let states = StateTable<DiskState>()

    @ObjCMethod("dealloc")
    func dealloc() {
        DiskArbitrationDisk.states.remove(objcObject)
        ObjCRuntime.superDealloc(objcObject, definedOn: DiskArbitrationDisk.objCClass.pointer)
    }

    @ObjCMethod("_cfTypeID") func cfTypeID() -> UInt { diskTypeID }

    @ObjCMethod("isEqual:")
    func isEqual(_ other: NSObject?) -> Bool {
        guard let mine = DiskArbitrationDisk.states[objcObject], let theirs = DiskArbitrationDisk.states[other?.objcObject] else { return false }
        return mine.bsdName == theirs.bsdName && mine.volumePath == theirs.volumePath && mine.whole == theirs.whole
    }

    @ObjCMethod("hash")
    func hash() -> UInt {
        guard let state = DiskArbitrationDisk.states[objcObject] else { return 0 }
        return UInt(bitPattern: (state.bsdName ?? state.volumePath).hashValue)
    }
}

enum Disks {
    static func object(_ state: DiskState) -> UnsafeMutableRawPointer {
        let object = DiskArbitrationDisk.objCClass.ownedInstance()
        DiskArbitrationDisk.states.set(object, state)
        return object
    }

    /// Fills in what the file system mounted at `hostPath` says of itself.
    static func describe(_ state: DiskState, hostPath: String, mount: HostMount?) {
        var stats = statvfs()
        if statvfs(hostPath, &stats) == 0 {
            state.mediaSize = Int64(stats.f_blocks) * Int64(stats.f_frsize)
            state.blockSize = Int64(stats.f_bsize)
            state.writable = stats.f_flag & UInt(ST_RDONLY) == 0
        }
        var info = stat()
        if stat(hostPath, &info) == 0 {
            let device = UInt64(info.st_dev)
            state.major = Int64((device >> 8) & 0xfff | (device >> 32) & ~UInt64(0xfff))
            state.minor = Int64(device & 0xff | (device >> 12) & ~UInt64(0xff))
        }
        guard let mount else { return }
        state.kind = HostMounts.kind(mount.type)
        state.uuid = HostMounts.uuid(of: mount.source)
        if let drive = HostMounts.drive(of: mount.source) {
            (state.model, state.vendor, state.removable, state.ejectable) = (drive.model, drive.vendor, drive.removable, drive.removable)
            state.driveSize = drive.size
        }
        // A loop device is a disk image, as Darwin calls its own.
        if mount.source.hasPrefix("/dev/loop") {
            state.model = "Disk Image"
            state.ejectable = true
        }
    }

    /// The volume at /: the file system the home is on, where the program
    /// keeps what it writes and whose sizes statfs reports, unless that is
    /// a network one; then the one at / here.
    static func startup() -> DiskState {
        let home = getenv("HOME").map { String(cString: $0) } ?? "/"
        var mount = HostMounts.containing(home)
        if let found = mount, HostMounts.networkTypes.contains(found.type) { mount = HostMounts.containing("/") }
        let state = DiskState()
        (state.bsdName, state.volumeName, state.volumePath) = ("disk1s1", "Macintosh HD", "/")
        describe(state, hostPath: mount?.mountPoint ?? "/", mount: mount)
        return state
    }

    /// The disc at `index`, from 0: disk<index + 2>s1, read-only and
    /// removable, at /Volumes/<its name>.
    static func disc(_ index: Int) -> DiskState? {
        guard let disc = DiscVolumes.disc(index) else { return nil }
        var stats = statvfs()
        guard statvfs(disc.mount, &stats) == 0 else { return nil }
        let state = DiskState()
        (state.bsdName, state.volumeName, state.volumePath) = ("disk\(index + 2)s1", disc.name, "/Volumes/" + disc.name)
        describe(state, hostPath: disc.mount, mount: HostMounts.all().last { $0.mountPoint == disc.mount })
        if state.kind.isEmpty { state.kind = "cd9660" }
        (state.writable, state.removable, state.ejectable) = (false, true, true)
        return state
    }

    /// A network file system's mount point, a volume of its own.
    static func network(_ mount: HostMount) -> DiskState {
        let state = DiskState()
        state.volumeName = mount.mountPoint.split(separator: "/").last.map(String.init) ?? mount.mountPoint
        state.volumePath = mount.mountPoint
        state.network = true
        describe(state, hostPath: mount.mountPoint, mount: nil)
        state.kind = HostMounts.kind(mount.type)
        return state
    }

    /// The volume mounted at a path, which must be its mount point, as on
    /// Darwin: /, a disc's /Volumes/<name> (or where it is mounted here),
    /// or a network file system's mount point.
    static func volume(at path: String) -> DiskState? {
        var path = path
        while path.count > 1 && path.hasSuffix("/") { path.removeLast() }
        if path == "/" { return startup() }
        for index in 0..<DiscVolumes.count {
            guard let disc = DiscVolumes.disc(index), path == "/Volumes/" + disc.name || path == disc.mount else { continue }
            return Disks.disc(index)
        }
        let resolved = HostMounts.resolved(path) ?? path
        if let mount = HostMounts.all().last(where: { $0.mountPoint == resolved }), HostMounts.networkTypes.contains(mount.type) {
            return network(mount)
        }
        return nil
    }

    /// A disk by BSD name: disk1s1 and disk1, the discs' disk<n>s1 and
    /// disk<n>, n from 2, with or without "/dev/". Any other name is a disk
    /// with no description.
    static func named(_ text: String) -> DiskState {
        var name = Substring(text)
        if name.hasPrefix("/dev/") { name = name.dropFirst(5) }
        let unknown = DiskState()
        unknown.bsdName = String(name)
        unknown.known = false
        guard name.hasPrefix("disk") else { return unknown }
        let rest = name.dropFirst(4)
        let digits = rest.prefix { character in character.isNumber }
        let slice = rest.dropFirst(digits.count)
        guard let number = Int(digits), slice.isEmpty || slice == "s1" else { return unknown }
        let found: DiskState? = number == 1 ? startup() : number >= 2 ? disc(number - 2) : nil
        guard let found else { return unknown }
        return slice.isEmpty ? found.wholeDisk() : found
    }
}

// MARK: - Sessions

@c(_DASessionGetTypeID) public func DASessionGetTypeID() -> UInt { sessionTypeID }

@c(_DASessionCreate)
public func DASessionCreate(_ allocator: UnsafeRawPointer?) -> UnsafeMutableRawPointer? {
    DiskArbitrationSession.objCClass.ownedInstance()
}

/// A session's callbacks would come on the run loop or queue; none come.
@c(_DASessionScheduleWithRunLoop)
public func DASessionScheduleWithRunLoop(_ session: UnsafeMutableRawPointer?, _ runLoop: UnsafeMutableRawPointer?,
                                         _ mode: UnsafeMutableRawPointer?) {}

@c(_DASessionUnscheduleFromRunLoop)
public func DASessionUnscheduleFromRunLoop(_ session: UnsafeMutableRawPointer?, _ runLoop: UnsafeMutableRawPointer?,
                                           _ mode: UnsafeMutableRawPointer?) {}

@c(_DASessionSetDispatchQueue)
public func DASessionSetDispatchQueue(_ session: UnsafeMutableRawPointer?, _ queue: UnsafeMutableRawPointer?) {}

// MARK: - Disks

@c(_DADiskGetTypeID) public func DADiskGetTypeID() -> UInt { diskTypeID }

/// DADiskRef DADiskCreateFromVolumePath(CFAllocatorRef, DASessionRef,
/// CFURLRef): the volume mounted there (+1), or NULL when the path isn't a
/// volume's mount point, as on Darwin.
@c(_DADiskCreateFromVolumePath)
public func DADiskCreateFromVolumePath(_ allocator: UnsafeRawPointer?, _ session: UnsafeMutableRawPointer?,
                                       _ url: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer? {
    guard let url, let path = DiskURL(url).path(), let state = Disks.volume(at: path) else { return nil }
    return Disks.object(state)
}

/// DADiskRef DADiskCreateFromBSDName(CFAllocatorRef, DASessionRef, const
/// char *): a disk for any name (+1); one that names none here has no
/// description.
@c(_DADiskCreateFromBSDName)
public func DADiskCreateFromBSDName(_ allocator: UnsafeRawPointer?, _ session: UnsafeMutableRawPointer?,
                                    _ name: UnsafePointer<CChar>?) -> UnsafeMutableRawPointer? {
    guard let name else { return nil }
    return Disks.object(Disks.named(String(cString: name)))
}

/// The BSD name, which the disk keeps; NULL for a network volume.
@c(_DADiskGetBSDName)
public func DADiskGetBSDName(_ disk: UnsafeMutableRawPointer?) -> UnsafePointer<CChar>? {
    DiskArbitrationDisk.states[disk]?.bsdNameText.map { UnsafePointer($0) }
}

/// The whole disk a volume's partition is on (+1), itself for a whole
/// disk; NULL for a network volume or a disk that isn't here.
@c(_DADiskCopyWholeDisk)
public func DADiskCopyWholeDisk(_ disk: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer? {
    guard let state = DiskArbitrationDisk.states[disk], state.known, state.bsdName != nil else { return nil }
    return Disks.object(state.whole ? state : state.wholeDisk())
}

/// CFDictionaryRef DADiskCopyDescription(DADiskRef): the volume's keys (for
/// a partition or a network volume), the media's and the drive's that are
/// known (for a disk with a BSD name) (+1); NULL for a disk that isn't here.
@c(_DADiskCopyDescription)
public func DADiskCopyDescription(_ disk: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer? {
    guard let state = DiskArbitrationDisk.states[disk], state.known else { return nil }
    typealias Keys = DiskDescriptionKeys
    var entries: [(String, NSObject)] = []
    func add(_ key: String, _ value: NSObject) { entries.append((key, value)) }
    func addFlag(_ key: String, _ flag: Bool) { entries.append((key, DiskNumber.make(bool: flag))) }
    func addNumber(_ key: String, _ number: Int64) { entries.append((key, DiskNumber.make(number))) }
    if !state.whole {
        add(Keys.kDADiskDescriptionVolumeKindKey, NSObject.string(state.kind))
        addFlag(Keys.kDADiskDescriptionVolumeMountableKey, true)
        add(Keys.kDADiskDescriptionVolumeNameKey, NSObject.string(state.volumeName))
        addFlag(Keys.kDADiskDescriptionVolumeNetworkKey, state.network)
        add(Keys.kDADiskDescriptionVolumePathKey, DiskURL.make(path: state.volumePath, isDirectory: true))
        if let uuid = state.uuid, let made = DiskUUIDs.make(uuid) {
            add(Keys.kDADiskDescriptionVolumeUUIDKey, NSObject(objCOwned: made))
        }
    }
    if let bsdName = state.bsdName {
        add(Keys.kDADiskDescriptionMediaBSDNameKey, NSObject.string(bsdName))
        addNumber(Keys.kDADiskDescriptionMediaBSDMajorKey, state.major)
        addNumber(Keys.kDADiskDescriptionMediaBSDMinorKey, state.minor)
        addNumber(Keys.kDADiskDescriptionMediaBSDUnitKey, state.unit)
        addNumber(Keys.kDADiskDescriptionMediaBlockSizeKey, state.blockSize)
        addFlag(Keys.kDADiskDescriptionMediaEjectableKey, state.ejectable)
        add(Keys.kDADiskDescriptionMediaKindKey, NSObject.string("IOMedia"))
        addFlag(Keys.kDADiskDescriptionMediaLeafKey, !state.whole)
        add(Keys.kDADiskDescriptionMediaNameKey,
            NSObject.string(state.whole ? (state.model.map { $0 + " Media" } ?? "Media") : state.volumeName))
        addFlag(Keys.kDADiskDescriptionMediaRemovableKey, state.removable)
        addNumber(Keys.kDADiskDescriptionMediaSizeKey, state.mediaSize)
        addFlag(Keys.kDADiskDescriptionMediaWholeKey, state.whole)
        addFlag(Keys.kDADiskDescriptionMediaWritableKey, state.writable)
        addFlag(Keys.kDADiskDescriptionDeviceInternalKey, !state.removable)
        if let model = state.model { add(Keys.kDADiskDescriptionDeviceModelKey, NSObject.string(model)) }
        if let vendor = state.vendor { add(Keys.kDADiskDescriptionDeviceVendorKey, NSObject.string(vendor)) }
    }
    return ObjCRuntime.retain(NSMutableDictionary.of(entries).objcObject)
}

/// CFUUIDs, from CoreFoundation's provider.
enum DiskUUIDs {
    typealias Create = @convention(c) (UnsafeRawPointer?, UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer?

    nonisolated(unsafe) private static let create: Create? = {
        guard let lookup = providerSymbolLookup else { return nil }
        let foundation = "/System/Library/Frameworks/CoreFoundation.framework/CoreFoundation"
        return foundation.withCString { library in lookup(library, "_CFUUIDCreateFromString") }.map { unsafeBitCast($0, to: Create.self) }
    }()

    /// A CFUUID (+1) for "68753A44-4D6F-1226-9C60-0050E4C00067".
    static func make(_ text: String) -> UnsafeMutableRawPointer? {
        guard let create else { return nil }
        let string = NSObject.string(text)
        return withExtendedLifetime(string) { create(nil, string.objcObject) }
    }
}
#endif
