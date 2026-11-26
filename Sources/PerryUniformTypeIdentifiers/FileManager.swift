import Glibc
import GraphiteBase
import GraphiteFiles

// Mac apps' alone: armv7 runs only iOS apps, so it has none of this.
#if !arch(arm)
// Carbon's File Manager, as Mac apps from before NSURL's file APIs find
// their folders and files with it: FSRefs over paths. An FSRef is 80 opaque
// bytes; here it holds a tag and the index of its path in a table that only
// grows, so a copy names the same item and two refs to one path are equal.
// Catalog information and aliases are Graphite's File Manager's: folder IDs
// are inodes with the root as 2, as Carbon's FSSpecs name folders, Finder
// info and resource forks are in AppleDouble files beside their items, and
// an alias finds its item after it moves. There are no alias files.

private let noErr: Int16 = 0
private let fnfErr: Int16 = -43
private let paramErr: Int16 = -50
private let dirNFErr: Int16 = -120

enum FileRefs {
    /// 'PFSR', where an FSRef's first word is.
    static let tag: UInt32 = 0x5046_5352
    private static let lock = Lock()
    nonisolated(unsafe) private static var paths: [String] = []
    nonisolated(unsafe) private static var indices: [String: UInt32] = [:]

    /// A path without "." or "..", repeated or trailing slashes: the one
    /// spelling an item gets an FSRef by.
    static func standardized(_ path: String) -> String {
        var parts: [Substring] = []
        for part in path.split(separator: "/", omittingEmptySubsequences: true) {
            if part == "." { continue }
            if part == ".." { _ = parts.popLast(); continue }
            parts.append(part)
        }
        return "/" + parts.joined(separator: "/")
    }

    static func store(_ path: String, in ref: UnsafeMutableRawPointer) {
        let path = standardized(path)
        let index: UInt32 = lock.withLock {
            if let index = indices[path] { return index }
            paths.append(path)
            let index = UInt32(paths.count - 1)
            indices[path] = index
            return index
        }
        ref.initializeMemory(as: UInt8.self, repeating: 0, count: 80)
        ref.storeBytes(of: tag, as: UInt32.self)
        ref.storeBytes(of: index, toByteOffset: 4, as: UInt32.self)
    }

    static func path(of ref: UnsafeRawPointer?) -> String? {
        guard let ref, ref.loadUnaligned(as: UInt32.self) == tag else { return nil }
        let index = Int(ref.loadUnaligned(fromByteOffset: 4, as: UInt32.self))
        return lock.withLock { index < paths.count ? paths[index] : nil }
    }

    static func exists(_ path: String) -> Bool {
        var info = stat()
        return stat(path, &info) == 0
    }

    /// The path of the item `path` names on a Mac's file system, which
    /// tells no case apart: `path` itself if it is there, else the path
    /// whose components match its in any case, if there is one. A program
    /// written for HFS+ asks for "shaders/fx" where its folder is "Shaders".
    static func inAnyCase(_ path: String) -> String? {
        if exists(path) { return path }
        var found = ""
        for part in standardized(path).split(separator: "/") {
            let exact = found + "/" + part
            if exists(exact) {
                found = exact
                continue
            }
            guard let directory = opendir(found.isEmpty ? "/" : found) else { return nil }
            defer { closedir(directory) }
            let wanted = part.lowercased()
            var match: String?
            while let entry = readdir(directory) {
                let name = withUnsafePointer(to: &entry.pointee.d_name) {
                    $0.withMemoryRebound(to: CChar.self, capacity: 256) { String(cString: $0) }
                }
                if name.lowercased() == wanted {
                    match = name
                    break
                }
            }
            guard let match else { return nil }
            found += "/" + match
        }
        return found.isEmpty ? "/" : found
    }

    static func isDirectory(_ path: String) -> Bool {
        var info = stat()
        return stat(path, &info) == 0 && info.st_mode & S_IFMT == S_IFDIR
    }

    /// A four-character code, as an OSType.
    static func code(_ text: String) -> UInt32 { text.utf8.reduce(0) { $0 << 8 | UInt32($1) } }

    /// The folders FSFindFolder knows, by type, in the user's home as
    /// Foundation's search paths are: every domain's is the home's.
    static func folder(_ type: UInt32) -> String? {
        let home = getenv("HOME").map { String(cString: $0) } ?? "/"
        switch type {
        case code("pref"): return home + "/Library/Preferences"
        case code("asup"): return home + "/Library/Application Support"
        case code("cach"): return home + "/Library/Caches"
        case code("dlib"): return home + "/Library"
        case code("docs"): return home + "/Documents"
        case code("desk"): return home + "/Desktop"
        case code("trsh"): return home + "/.Trash"
        case code("apps"): return home + "/Applications"
        case code("fnts"): return home + "/Library/Fonts"
        case code("fram"): return home + "/Library/Frameworks"
        case code("logs"): return home + "/Library/Logs"
        case code("ssnd"): return home + "/Library/Sounds"
        case code("cusr"): return home
        case code("temp"), code("chew"):
            return getenv("TMPDIR").map { String(cString: $0) } ?? "/tmp"
        default: return nil
        }
    }
}

/// OSStatus FSPathMakeRef(const UInt8 *path, FSRef *ref, Boolean
/// *isDirectory): fnfErr if nothing is there.
@c(_FSPathMakeRef)
public func FSPathMakeRef(_ path: UnsafePointer<CChar>?, _ ref: UnsafeMutableRawPointer?, _ isDirectory: UnsafeMutablePointer<UInt8>?) -> Int32 {
    guard let path, let ref else { return Int32(paramErr) }
    let given = String(cString: path)
    guard given.hasPrefix("/"), let string = FileRefs.inAnyCase(given) else { return Int32(fnfErr) }
    FileRefs.store(string, in: ref)
    isDirectory?.pointee = FileRefs.isDirectory(string) ? 1 : 0
    return Int32(noErr)
}

/// OSStatus FSRefMakePath(const FSRef *ref, UInt8 *path, UInt32 maxPathSize).
@c(_FSRefMakePath)
public func FSRefMakePath(_ ref: UnsafeRawPointer?, _ path: UnsafeMutablePointer<CChar>?, _ maxPathSize: UInt32) -> Int32 {
    guard let string = FileRefs.path(of: ref), let path else { return Int32(paramErr) }
    let bytes = Array(string.utf8)
    guard bytes.count < Int(maxPathSize) else { return -2110 }   // pathTooLongErr
    for (index, byte) in bytes.enumerated() { path[index] = CChar(bitPattern: byte) }
    path[bytes.count] = 0
    return Int32(noErr)
}

/// OSErr FSFindFolder(FSVolumeRefNum vRefNum, OSType folderType, Boolean
/// createFolder, FSRef *foundRef): the folder, made first when asked.
@c(_FSFindFolder)
public func FSFindFolder(_ volume: Int16, _ type: UInt32, _ create: UInt8, _ ref: UnsafeMutableRawPointer?) -> Int16 {
    // The system's Frameworks folder (kFrameworksFolderType in the system
    // domain, on the system disk or on the appropriate disk): its frameworks
    // are the providers', with no directories here, which CFBundle opens by
    // path. Programs find System.framework there to look up libSystem's
    // functions, as Feral's ports do free.
    if let ref, type == FileRefs.code("fram"), [-32768, -32767, -32766].contains(volume) {
        FileRefs.store("/System/Library/Frameworks", in: ref)
        return noErr
    }
    guard let ref, let folder = FileRefs.folder(type) else { return fnfErr }
    if !FileRefs.isDirectory(folder) {
        guard create != 0 else { return fnfErr }
        var made = ""
        for part in folder.split(separator: "/") {
            made += "/" + part
            mkdir(made, 0o755)
        }
        guard FileRefs.isDirectory(folder) else { return dirNFErr }
    }
    FileRefs.store(folder, in: ref)
    return noErr
}

/// OSErr FSCompareFSRefs(const FSRef *, const FSRef *): noErr when both name
/// one item, diffRefErr (-1320) when not.
@c(_FSCompareFSRefs)
public func FSCompareFSRefs(_ first: UnsafeRawPointer?, _ second: UnsafeRawPointer?) -> Int16 {
    guard let one = FileRefs.path(of: first), let other = FileRefs.path(of: second) else { return paramErr }
    return one == other ? noErr : -1320
}

/// OSErr FSMakeFSRefUnicode(const FSRef *parent, UniCharCount nameLength,
/// const UniChar *name, TextEncoding hint, FSRef *newRef): the item by that
/// name in the folder, which must be there.
@c(_FSMakeFSRefUnicode)
public func FSMakeFSRefUnicode(_ parent: UnsafeRawPointer?, _ length: Int, _ name: UnsafePointer<UInt16>?, _ hint: UInt32,
                               _ ref: UnsafeMutableRawPointer?) -> Int16 {
    guard let folder = FileRefs.path(of: parent), let ref else { return paramErr }
    let leaf = name.map { String(decoding: UnsafeBufferPointer(start: $0, count: length), as: UTF16.self) } ?? ""
    guard let path = FileRefs.inAnyCase(folder == "/" ? "/" + leaf : folder + "/" + leaf) else { return fnfErr }
    FileRefs.store(path, in: ref)
    return noErr
}

/// OSErr FSIsAliasFile(const FSRef *, Boolean *aliasFileFlag, Boolean
/// *folderFlag): nothing is an alias here.
@c(_FSIsAliasFile)
public func FSIsAliasFile(_ ref: UnsafeRawPointer?, _ isAlias: UnsafeMutablePointer<UInt8>?, _ isFolder: UnsafeMutablePointer<UInt8>?) -> Int16 {
    guard let path = FileRefs.path(of: ref) else { return paramErr }
    isAlias?.pointee = 0
    isFolder?.pointee = FileRefs.isDirectory(path) ? 1 : 0
    return noErr
}

/// OSErr FSResolveAliasFile(FSRef *, Boolean resolveAliasChains, Boolean
/// *targetIsFolder, Boolean *wasAliased): the item itself, as it is no
/// alias.
@c(_FSResolveAliasFile)
public func FSResolveAliasFile(_ ref: UnsafeMutableRawPointer?, _ chains: UInt8, _ targetIsFolder: UnsafeMutablePointer<UInt8>?,
                               _ wasAliased: UnsafeMutablePointer<UInt8>?) -> Int16 {
    guard let path = FileRefs.path(of: ref) else { return paramErr }
    guard FileRefs.exists(path) else { return fnfErr }
    targetIsFolder?.pointee = FileRefs.isDirectory(path) ? 1 : 0
    wasAliased?.pointee = 0
    return noErr
}

/// OSErr FSResolveAliasFileWithMountFlags(FSRef *, Boolean
/// resolveAliasChains, Boolean *targetIsFolder, Boolean *wasAliased,
/// unsigned long mountFlags): as FSResolveAliasFile.
@c(_FSResolveAliasFileWithMountFlags)
public func FSResolveAliasFileWithMountFlags(_ ref: UnsafeMutableRawPointer?, _ chains: UInt8, _ targetIsFolder: UnsafeMutablePointer<UInt8>?,
                                             _ wasAliased: UnsafeMutablePointer<UInt8>?, _ flags: UInt) -> Int16 {
    FSResolveAliasFile(ref, chains, targetIsFolder, wasAliased)
}

// An alias record is opaque past its user type (4 bytes) and its size (2,
// in this machine's byte order): after them, Graphite's record ('PRRY', the
// item's path, and its device and inode), which FSResolveAlias makes an
// FSRef of again.
private let aliasHeaderSize = 6

/// The File Manager's catalog, for folder IDs and aliases.
let catalogFileSystem = FileSystem(folders: .macHome(getenv("HOME").map { String(cString: $0) } ?? "/"))

private func newAlias(_ target: UnsafeRawPointer?, _ alias: UnsafeMutablePointer<UnsafeMutableRawPointer?>?) -> Int16 {
    guard let alias else { return paramErr }
    alias.pointee = nil
    guard let path = FileRefs.path(of: target), let record = try? Alias(target: path).record else { return fnfErr }
    let size = aliasHeaderSize + record.count
    guard size <= 0xffff else { return paramErr }
    guard let handle = NewHandleClear(size),
          let storage = handle.assumingMemoryBound(to: UnsafeMutableRawPointer?.self).pointee else { return -108 }   // memFullErr
    storage.storeBytes(of: UInt16(size), toByteOffset: 4, as: UInt16.self)
    record.withUnsafeBytes { (storage + aliasHeaderSize).copyMemory(from: $0.baseAddress!, byteCount: $0.count) }
    alias.pointee = handle
    return noErr
}

/// OSErr FSNewAlias(const FSRef *fromFile, const FSRef *target, AliasHandle
/// *): an alias of the target, by its path whatever it is relative to.
@c(_FSNewAlias)
public func FSNewAlias(_ from: UnsafeRawPointer?, _ target: UnsafeRawPointer?, _ alias: UnsafeMutablePointer<UnsafeMutableRawPointer?>?) -> Int16 {
    newAlias(target, alias)
}

/// OSErr FSNewAliasMinimal(const FSRef *target, AliasHandle *).
@c(_FSNewAliasMinimal)
public func FSNewAliasMinimal(_ target: UnsafeRawPointer?, _ alias: UnsafeMutablePointer<UnsafeMutableRawPointer?>?) -> Int16 {
    newAlias(target, alias)
}

/// OSErr FSResolveAliasWithMountFlags(const FSRef *fromFile, AliasHandle,
/// FSRef *target, Boolean *wasChanged, unsigned long mountFlags): the item
/// an alias of Perry's names, if it is there.
@c(_FSResolveAliasWithMountFlags)
public func FSResolveAliasWithMountFlags(_ from: UnsafeRawPointer?, _ alias: UnsafeMutableRawPointer?, _ target: UnsafeMutableRawPointer?,
                                         _ changed: UnsafeMutablePointer<UInt8>?, _ flags: UInt) -> Int16 {
    changed?.pointee = 0
    guard let target, let storage = alias?.assumingMemoryBound(to: UnsafeMutableRawPointer?.self).pointee else { return paramErr }
    let size = Int(storage.loadUnaligned(fromByteOffset: 4, as: UInt16.self))
    guard size > aliasHeaderSize,
          let alias = try? Alias(record: UnsafeRawBufferPointer(start: storage + aliasHeaderSize, count: size - aliasHeaderSize)) else {
        return paramErr
    }
    guard let (path, moved) = try? alias.resolve(in: catalogFileSystem) else { return fnfErr }
    FileRefs.store(path, in: target)
    changed?.pointee = moved ? 1 : 0
    return noErr
}

/// OSErr FSResolveAlias(const FSRef *fromFile, AliasHandle, FSRef *target,
/// Boolean *wasChanged).
@c(_FSResolveAlias)
public func FSResolveAlias(_ from: UnsafeRawPointer?, _ alias: UnsafeMutableRawPointer?, _ target: UnsafeMutableRawPointer?,
                           _ changed: UnsafeMutablePointer<UInt8>?) -> Int16 {
    FSResolveAliasWithMountFlags(from, alias, target, changed, 0)
}

/// Size GetAliasSize(AliasHandle).
@c(_GetAliasSize)
public func GetAliasSize(_ alias: UnsafeMutableRawPointer?) -> Int {
    guard let record = alias?.assumingMemoryBound(to: UnsafeMutableRawPointer?.self).pointee else { return 0 }
    return Int(record.loadUnaligned(fromByteOffset: 4, as: UInt16.self))
}

/// The discs mounted, as libPerrySystem finds them for getmntinfo: volumes
/// after "Macintosh HD", numbered -101 and down. Its perry_disc_volume is
/// found in the library as it is loaded here.
enum DiscVolumes {
    private typealias Volume = @convention(c) (Int32, UnsafeMutablePointer<CChar>?, Int, UnsafeMutablePointer<CChar>?, Int) -> Int32

    nonisolated(unsafe) private static let volume: Volume? = {
        // The library's path, from this process's mappings: it is loaded
        // by its path, with no name to ask the loader for.
        guard let maps = fopen("/proc/self/maps", "r") else { return nil }
        defer { fclose(maps) }
        var line = [CChar](repeating: 0, count: 4096)
        while fgets(&line, Int32(line.count), maps) != nil {
            let text = String(cString: line)
            guard text.hasSuffix("/libPerrySystem.so\n"), let start = text.firstIndex(of: "/") else { continue }
            let path = String(text[start...].dropLast())
            guard let library = dlopen(path, RTLD_NOW | RTLD_NOLOAD), let symbol = dlsym(library, "perry_disc_volume") else { return nil }
            return unsafeBitCast(symbol, to: Volume.self)
        }
        return nil
    }()

    static var count: Int { volume.map { Int($0(-1, nil, 0, nil, 0)) } ?? 0 }

    /// The name and mount point of the disc at `index`, from 0.
    static func disc(_ index: Int) -> (name: String, mount: String)? {
        guard let volume, index >= 0 else { return nil }
        var name = [CChar](repeating: 0, count: 256), mount = [CChar](repeating: 0, count: 4096)
        guard index < Int(volume(Int32(index), &name, name.count, &mount, mount.count)) else { return nil }
        return (String(cString: name), String(cString: mount))
    }

    /// The disc a volume reference number names: -101 is the first.
    static func index(ofVolume volume: Int16) -> Int? { volume <= -101 && volume > -101 - 8 ? Int(-101 - Int(volume)) : nil }
}

/// OSErr FSGetVolumeInfo(FSVolumeRefNum volume, ItemCount volumeIndex,
/// FSVolumeRefNum *actualVolume, FSVolumeInfoBitmap whichInfo, FSVolumeInfo
/// *info, HFSUniStr255 *volumeName, FSRef *rootDirectory): the volume
/// "Macintosh HD" (refnum -100) over the home's file system, and after it
/// the discs mounted, each by its name over its mount point. FSVolumeInfo
/// (2-byte packed, 126 bytes): four UTCDateTimes, file and folder counts at
/// 32, total and free bytes at 40 and 48, block size and total and free
/// blocks at 56, 60 and 64, flags at 116 and the signature ('H+') at 120.
@c(_FSGetVolumeInfo)
public func FSGetVolumeInfo(_ volume: Int16, _ index: Int, _ actual: UnsafeMutablePointer<Int16>?, _ which: UInt32,
                            _ info: UnsafeMutableRawPointer?, _ name: UnsafeMutablePointer<UInt16>?,
                            _ root: UnsafeMutableRawPointer?) -> Int16 {
    // By index, from 1, when no volume is named (kFSInvalidVolumeRefNum):
    // the discs follow the first.
    var disc: (name: String, mount: String)?
    var discNumber = 0
    if volume == 0, index > 1 {
        discNumber = index - 2
        disc = DiscVolumes.disc(discNumber)
        if disc == nil { return -35 }               // nsvErr
    } else if let number = DiscVolumes.index(ofVolume: volume) {
        discNumber = number
        disc = DiscVolumes.disc(number)
        if disc == nil { return -35 }
    } else {
        if volume == 0 && index != 1 { return -35 }
        if volume != 0 && volume != -100 && volume != -32768 && volume != -32767 && volume != -32763 { return -35 }
    }
    actual?.pointee = disc == nil ? -100 : Int16(-101 - discNumber)
    if let info {
        info.initializeMemory(as: UInt8.self, repeating: 0, count: 126)
        var stats = statvfs()
        let home = disc?.mount ?? getenv("HOME").map { String(cString: $0) } ?? "/"
        if statvfs(home, &stats) == 0 {
            let block = UInt64(stats.f_frsize)
            info.storeBytes(of: UInt64(stats.f_blocks) * block, toByteOffset: 40, as: UInt64.self)
            info.storeBytes(of: UInt64(stats.f_bavail) * block, toByteOffset: 48, as: UInt64.self)
            // Block counts are 32 bits: blocks large enough for them to fit.
            var size = block
            while UInt64(stats.f_blocks) * block / size > UInt64(UInt32.max) { size *= 2 }
            info.storeBytes(of: UInt32(size), toByteOffset: 56, as: UInt32.self)
            info.storeBytes(of: UInt32(UInt64(stats.f_blocks) * block / size), toByteOffset: 60, as: UInt32.self)
            info.storeBytes(of: UInt32(UInt64(stats.f_bavail) * block / size), toByteOffset: 64, as: UInt32.self)
        }
        info.storeBytes(of: UInt16(0x482B), toByteOffset: 120, as: UInt16.self)
    }
    if let name {
        let units = Array((disc?.name ?? "Macintosh HD").utf16.prefix(255))
        name.pointee = UInt16(units.count)
        for (offset, unit) in units.enumerated() { name[1 + offset] = unit }
    }
    if let root { FileRefs.store(disc?.mount ?? "/", in: root) }
    _ = which
    return noErr
}

/// OSErr FSGetCatalogInfo(const FSRef *, FSCatalogInfoBitmap whichInfo,
/// FSCatalogInfo *, HFSUniStr255 *outName, FSSpec *, FSRef *parentRef):
/// the item's flags, IDs, dates, Finder info, sizes and count of items in a
/// folder, its name, its FSSpec and its folder. FSCatalogInfo (2-byte
/// packed, 144 bytes): nodeFlags at 0, the volume (the one, -100) at 2, the
/// parent's and the item's IDs at 4 and 8 (a folder's as Carbon's FSSpecs
/// name it, the root 2 and its parent 1; a file's its inode), five
/// UTCDateTimes from 16, Finder info at 72 and extended Finder info at 88,
/// the data fork's sizes at 104 and 112, the resource fork's at 120 and
/// 128, valence at 136.
@c(_FSGetCatalogInfo)
public func FSGetCatalogInfo(_ ref: UnsafeRawPointer?, _ which: UInt32, _ catalog: UnsafeMutableRawPointer?,
                             _ outName: UnsafeMutablePointer<UInt16>?, _ spec: UnsafeMutableRawPointer?,
                             _ parent: UnsafeMutableRawPointer?) -> Int16 {
    guard let path = FileRefs.path(of: ref) else { return paramErr }
    let info: CatalogInfo
    do {
        info = try catalogFileSystem.catalogInfo(at: path)
    } catch {
        return Int16(truncatingIfNeeded: error.code)
    }
    if let catalog {
        catalog.initializeMemory(as: UInt8.self, repeating: 0, count: 144)
        var flags: UInt16 = info.isDirectory ? 0x0010 : 0   // kFSNodeIsDirectoryMask
        if info.isLocked { flags |= 0x0001 }                // kFSNodeLockedMask
        catalog.storeBytes(of: flags, as: UInt16.self)
        catalog.storeBytes(of: Int16(-100), toByteOffset: 2, as: Int16.self)
        catalog.storeBytes(of: info.parentID.rawValue, toByteOffset: 4, as: UInt32.self)
        catalog.storeBytes(of: info.nodeID, toByteOffset: 8, as: UInt32.self)
        // UTCDateTime: seconds since 1904 in a 48-bit count, then a fraction.
        func store(_ date: MacDate, at offset: Int) {
            let since1904 = UInt64(max(0, date.utcSeconds))
            catalog.storeBytes(of: UInt16(truncatingIfNeeded: since1904 >> 32), toByteOffset: offset, as: UInt16.self)
            catalog.storeBytes(of: UInt32(truncatingIfNeeded: since1904), toByteOffset: offset + 2, as: UInt32.self)
        }
        store(info.created, at: 16)
        store(info.contentModified, at: 24)
        store(info.attributeModified, at: 32)
        store(info.accessed, at: 40)
        for (index, byte) in info.finderInfo.bytes.enumerated() {
            catalog.storeBytes(of: byte, toByteOffset: 72 + index, as: UInt8.self)
        }
        if info.isDirectory {
            catalog.storeBytes(of: info.valence, toByteOffset: 136, as: UInt32.self)
        } else {
            catalog.storeBytes(of: UInt64(info.dataLogicalSize), toByteOffset: 104, as: UInt64.self)
            catalog.storeBytes(of: UInt64(info.dataPhysicalSize), toByteOffset: 112, as: UInt64.self)
            catalog.storeBytes(of: UInt64(info.resourceLogicalSize), toByteOffset: 120, as: UInt64.self)
            catalog.storeBytes(of: UInt64(info.resourcePhysicalSize), toByteOffset: 128, as: UInt64.self)
        }
    }
    if let outName {
        let leaf = Array((path == "/" ? "" : FileNames.hfs(String(path.split(separator: "/").last ?? ""))).utf16.prefix(255))
        outName.pointee = UInt16(leaf.count)
        for (index, unit) in leaf.enumerated() { outName[1 + index] = unit }
    }
    if let parent {
        let folder = path.split(separator: "/").dropLast().joined(separator: "/")
        FileRefs.store("/" + folder, in: parent)
    }
    // FSSpec (2-byte packed, 70 bytes): the volume at 0, the folder's ID at
    // 2, and the name as a Pascal string of at most 63 MacRoman bytes at 6.
    if let spec {
        let made = catalogFileSystem.spec(forPath: path)
        spec.initializeMemory(as: UInt8.self, repeating: 0, count: 70)
        spec.storeBytes(of: made.volume, as: Int16.self)
        spec.storeBytes(of: made.parent.rawValue, toByteOffset: 2, as: UInt32.self)
        spec.storeBytes(of: UInt8(made.name.count), toByteOffset: 6, as: UInt8.self)
        for (index, byte) in made.name.bytes.enumerated() { spec.storeBytes(of: byte, toByteOffset: 7 + index, as: UInt8.self) }
    }
    return noErr
}

/// OSStatus FSGetHFSUniStrFromString(CFStringRef, HFSUniStr255 *): the
/// string's UTF-16, after its length; a name of more than 255 units is
/// paramErr.
@c(_FSGetHFSUniStrFromString)
public func FSGetHFSUniStrFromString(_ string: UnsafeMutableRawPointer?, _ name: UnsafeMutablePointer<UInt16>?) -> Int32 {
    guard let string, let name else { return -50 }
    let units = Array(String(objCArgument: string).utf16)
    guard units.count <= 255 else { return -50 }
    name.pointee = UInt16(units.count)
    for (index, unit) in units.enumerated() { name[1 + index] = unit }
    return 0
}
#endif
