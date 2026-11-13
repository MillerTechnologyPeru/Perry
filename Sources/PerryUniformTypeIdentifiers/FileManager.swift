import Glibc

// Mac apps' alone: armv7 runs only iOS apps, so it has none of this.
#if !arch(arm)
// Carbon's File Manager, as Mac apps from before NSURL's file APIs find
// their folders and files with it: FSRefs over paths. An FSRef is 80 opaque
// bytes; here it holds a tag and the index of its path in a table that only
// grows, so a copy names the same item and two refs to one path are equal.
// There are no aliases, resource forks or HFS catalog IDs here.

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
    let string = String(cString: path)
    guard string.hasPrefix("/"), FileRefs.exists(string) else { return Int32(fnfErr) }
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
    let path = folder == "/" ? "/" + leaf : folder + "/" + leaf
    guard FileRefs.exists(path) else { return fnfErr }
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

/// OSErr FSGetVolumeInfo(FSVolumeRefNum volume, ItemCount volumeIndex,
/// FSVolumeRefNum *actualVolume, FSVolumeInfoBitmap whichInfo, FSVolumeInfo
/// *info, HFSUniStr255 *volumeName, FSRef *rootDirectory): the one volume,
/// "Macintosh HD" (refnum -100) over the home's file system. FSVolumeInfo
/// (2-byte packed, 126 bytes): four UTCDateTimes, file and folder counts at
/// 32, total and free bytes at 40 and 48, block size and total and free
/// blocks at 56, 60 and 64, flags at 116 and the signature ('H+') at 120.
@c(_FSGetVolumeInfo)
public func FSGetVolumeInfo(_ volume: Int16, _ index: Int, _ actual: UnsafeMutablePointer<Int16>?, _ which: UInt32,
                            _ info: UnsafeMutableRawPointer?, _ name: UnsafeMutablePointer<UInt16>?,
                            _ root: UnsafeMutableRawPointer?) -> Int16 {
    // By index, from 1, when no volume is named (kFSInvalidVolumeRefNum).
    if volume == 0 && index != 1 { return -35 }     // nsvErr
    if volume != 0 && volume != -100 && volume != -32768 && volume != -32767 && volume != -32763 { return -35 }
    actual?.pointee = -100
    if let info {
        info.initializeMemory(as: UInt8.self, repeating: 0, count: 126)
        var stats = statvfs()
        let home = getenv("HOME").map { String(cString: $0) } ?? "/"
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
        let units = Array("Macintosh HD".utf16)
        name.pointee = UInt16(units.count)
        for (offset, unit) in units.enumerated() { name[1 + offset] = unit }
    }
    if let root { FileRefs.store("/", in: root) }
    _ = which
    return noErr
}

/// OSErr FSGetCatalogInfo(const FSRef *, FSCatalogInfoBitmap whichInfo,
/// FSCatalogInfo *, HFSUniStr255 *outName, FSSpec *, FSRef *parentRef):
/// the item's flags, dates, sizes and count of items in a folder, its name
/// and its folder. FSCatalogInfo (2-byte packed, 144 bytes): nodeFlags at
/// 0, the volume (the one, -100) at 2, the parent's and the item's IDs (their
/// inodes, as 32 bits) at 4 and 8, five UTCDateTimes from 16, the data fork's sizes at 104 and 112, the
/// resource fork's (none) at 120 and 128, valence at 136.
@c(_FSGetCatalogInfo)
public func FSGetCatalogInfo(_ ref: UnsafeRawPointer?, _ which: UInt32, _ catalog: UnsafeMutableRawPointer?,
                             _ outName: UnsafeMutablePointer<UInt16>?, _ spec: UnsafeMutableRawPointer?,
                             _ parent: UnsafeMutableRawPointer?) -> Int16 {
    guard let path = FileRefs.path(of: ref) else { return paramErr }
    var info = stat()
    guard stat(path, &info) == 0 else { return fnfErr }
    let directory = info.st_mode & S_IFMT == S_IFDIR
    if let catalog {
        catalog.initializeMemory(as: UInt8.self, repeating: 0, count: 144)
        var flags: UInt16 = directory ? 0x0010 : 0          // kFSNodeIsDirectoryMask
        if access(path, W_OK) != 0 { flags |= 0x0001 }      // kFSNodeLockedMask
        catalog.storeBytes(of: flags, as: UInt16.self)
        catalog.storeBytes(of: Int16(-100), toByteOffset: 2, as: Int16.self)
        var parentInfo = stat()
        let parentPath = path == "/" ? "/" : "/" + path.split(separator: "/").dropLast().joined(separator: "/")
        if stat(parentPath, &parentInfo) == 0 {
            catalog.storeBytes(of: UInt32(truncatingIfNeeded: parentInfo.st_ino), toByteOffset: 4, as: UInt32.self)
        }
        catalog.storeBytes(of: UInt32(truncatingIfNeeded: info.st_ino), toByteOffset: 8, as: UInt32.self)
        // UTCDateTime: seconds since 1904 in a 48-bit count, then a fraction.
        // In 64 bits: since 1904 passes a 32-bit Int's largest.
        func store(_ seconds: Int64, at offset: Int) {
            let since1904 = UInt64(max(0, seconds + 2_082_844_800))
            catalog.storeBytes(of: UInt16(truncatingIfNeeded: since1904 >> 32), toByteOffset: offset, as: UInt16.self)
            catalog.storeBytes(of: UInt32(truncatingIfNeeded: since1904), toByteOffset: offset + 2, as: UInt32.self)
        }
        store(Int64(info.st_ctim.tv_sec), at: 16)
        store(Int64(info.st_mtim.tv_sec), at: 24)
        store(Int64(info.st_ctim.tv_sec), at: 32)
        store(Int64(info.st_atim.tv_sec), at: 40)
        if !directory {
            catalog.storeBytes(of: UInt64(info.st_size), toByteOffset: 104, as: UInt64.self)
            catalog.storeBytes(of: UInt64(info.st_blocks) * 512, toByteOffset: 112, as: UInt64.self)
        } else if let folder = opendir(path) {
            var count: UInt32 = 0
            while let entry = readdir(folder) {
                let name = withUnsafeBytes(of: entry.pointee.d_name) { String(cString: $0.bindMemory(to: CChar.self).baseAddress!) }
                if name != "." && name != ".." { count += 1 }
            }
            closedir(folder)
            catalog.storeBytes(of: count, toByteOffset: 136, as: UInt32.self)
        }
    }
    if let outName {
        let leaf = Array((path == "/" ? "" : String(path.split(separator: "/").last ?? "")).utf16.prefix(255))
        outName.pointee = UInt16(leaf.count)
        for (index, unit) in leaf.enumerated() { outName[1 + index] = unit }
    }
    if let parent {
        let folder = path.split(separator: "/").dropLast().joined(separator: "/")
        FileRefs.store("/" + folder, in: parent)
    }
    _ = spec
    return noErr
}
#endif
