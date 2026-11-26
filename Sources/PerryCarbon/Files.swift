#if canImport(Glibc)
import Glibc
#endif
import GraphiteBase
import GraphiteFiles
import GraphiteTasks
import PerryObjCInterop
import Synchronization

// Carbon's File Manager over Graphite's: FSSpecs, files opened by reference
// number and read and written through it, as forks or the original way,
// folders' items one by one or in bulk, and the parameter-block calls of the
// original File Manager. FSRefs are CoreServices': they name paths in its
// table, and its catalog information, aliases and FSFindFolder are its own.
// A file's resource fork is the AppleDouble file beside it ("._name") or
// "name.rsrc". There is one volume, "Macintosh HD" (-100), the root, and
// the discs mounted after it.

/// The program's file system: names from folder 0 are in its executable's
/// folder when it is a bundle (Contents/MacOS, as Mac OS X starts one:
/// Pangea's games find "::Resources:Data:" from it), else in the working
/// folder; its bundle's folders and their parents are known by ID from the
/// start, as programs find their data beside the bundle by its parent's ID.
let fileSystem: FileSystem = {
    let bundle = carbon_bundle_path().map { String(cString: $0) }
    let executable = carbon_executable_path().map { String(cString: $0) }
    var start: String?
    if let executable, executable.contains("/Contents/MacOS/"), let slash = executable.lastIndex(of: "/") {
        start = String(executable[..<slash])
    }
    let home = getenv("HOME").map { String(cString: $0) } ?? "/"
    return FileSystem(
        defaultFolder: start,
        knownFolders: bundle.map { [$0] } ?? [],
        folders: .macHome(home),
        volume: Volume(spacePath: String(cString: carbon_startup_volume_path()))
    )
}()

/// The OSErr of a throwing call: noErr, or the code it threw.
func osErr(_ body: () throws(MacError) -> Void) -> Int16 {
    do {
        try body()
        return 0
    } catch {
        return error.osErr
    }
}

// MARK: - CoreServices' FSRefs

enum CoreServicesFiles {

    private typealias PathMakeRef = @convention(c) (UnsafePointer<CChar>?, UnsafeMutableRawPointer?, UnsafeMutablePointer<UInt8>?) -> Int32
    private typealias RefMakePath = @convention(c) (UnsafeRawPointer?, UnsafeMutablePointer<CChar>?, UInt32) -> Int32
    typealias GetCatalogInfo = @convention(c) (UnsafeRawPointer?, UInt32, UnsafeMutableRawPointer?, UnsafeMutablePointer<HFSUniStr255>?,
                                               UnsafeMutableRawPointer?, UnsafeMutableRawPointer?) -> Int16
    private typealias FindFolder = @convention(c) (Int16, UInt32, UInt8, UnsafeMutableRawPointer?) -> Int16

    private static func function<T>(_ name: String, as type: T.Type) -> T? {
        carbon_function(CORESERVICES, name).map { unsafeBitCast($0, to: T.self) }
    }

    nonisolated(unsafe) private static let pathMakeRef = function("_FSPathMakeRef", as: PathMakeRef.self)
    nonisolated(unsafe) private static let refMakePath = function("_FSRefMakePath", as: RefMakePath.self)
    nonisolated(unsafe) static let catalogInfo = function("_FSGetCatalogInfo", as: GetCatalogInfo.self)
    nonisolated(unsafe) private static let findFolder = function("_FSFindFolder", as: FindFolder.self)

    /// The path an FSRef names.
    static func path(of ref: UnsafeRawPointer?) -> String? {
        guard let ref, let refMakePath else { return nil }
        var buffer = [CChar](repeating: 0, count: 4096)
        guard refMakePath(ref, &buffer, UInt32(buffer.count)) == 0 else { return nil }
        return String(cString: buffer)
    }

    /// An FSRef for an item that is there: fnfErr if it isn't.
    @discardableResult
    static func store(_ path: String, in ref: UnsafeMutableRawPointer?) -> Int16 {
        guard let ref else { return 0 }
        guard let pathMakeRef else { return MacError.unimplemented.osErr }
        return Int16(truncatingIfNeeded: pathMakeRef(path, ref, nil))
    }

    /// FSFindFolder's folder's path.
    static func folder(volume: Int16, type: UInt32, create: Bool) throws(MacError) -> String {
        guard let findFolder else { throw .unimplemented }
        var ref = FSRef()
        let error = withUnsafeMutableBytes(of: &ref) { findFolder(volume, type, create ? 1 : 0, $0.baseAddress) }
        guard error == 0 else { throw MacError(Int32(error)) }
        guard let path = withUnsafeBytes(of: &ref, { path(of: $0.baseAddress) }) else { throw .fileNotFound }
        return path
    }
}

// MARK: - Names

/// A Pascal name, nil for none.
private func name(_ storage: UnsafePointer<UInt8>?) -> PascalString {
    storage.map { pascalString(at: UnsafeRawPointer($0)) } ?? PascalString()
}

/// Writes a Pascal string into a buffer of `capacity` bytes, length byte
/// included.
private func store(_ string: PascalString, at storage: UnsafeMutablePointer<UInt8>?, capacity: Int) {
    guard let storage, capacity > 0 else { return }
    let bytes = Array(string.bytes.prefix(capacity - 1))
    storage[0] = UInt8(bytes.count)
    for (index, byte) in bytes.enumerated() { storage[1 + index] = byte }
}

/// An HFSUniStr255's or a UniChar array's name, as POSIX keeps it.
private func unicodeName(_ length: Int, _ name: UnsafePointer<UInt16>?) -> String? {
    guard let name, length > 0, length <= 255 else { return nil }
    return FileNames.posix(String(decoding: UnsafeBufferPointer(start: name, count: length), as: UTF16.self))
}

private func store(_ name: String, in unicode: UnsafeMutablePointer<HFSUniStr255>?) {
    guard let unicode else { return }
    let units = Array(FileNames.hfs(name).utf16.prefix(255))
    unicode.pointee.length = UInt16(units.count)
    withUnsafeMutableBytes(of: &unicode.pointee.unicode) { buffer in
        for (index, unit) in units.enumerated() { buffer.storeBytes(of: unit, toByteOffset: 2 * index, as: UInt16.self) }
    }
}

// MARK: - FSSpecs

private func fileSpec(_ spec: UnsafePointer<FSSpec>) -> FileSpec {
    let record = spec.pointee
    let name = withUnsafeBytes(of: record.name) { PascalString(lengthPrefixed: $0) }
    return FileSpec(volume: record.vRefNum, parent: DirectoryID(UInt32(bitPattern: record.parID)), name: name)
}

private func store(_ spec: FileSpec, in record: UnsafeMutablePointer<FSSpec>?) {
    guard let record else { return }
    record.pointee.vRefNum = spec.volume
    record.pointee.parID = Int32(bitPattern: spec.parent.rawValue)
    withUnsafeMutableBytes(of: &record.pointee.name) { buffer in
        buffer.initializeMemory(as: UInt8.self, repeating: 0)
        let bytes = Array(spec.name.bytes.prefix(63))
        buffer[0] = UInt8(bytes.count)
        for (index, byte) in bytes.enumerated() { buffer[1 + index] = byte }
    }
}

/// The path an FSSpec names, whether or not the item is there.
private func path(of spec: UnsafePointer<FSSpec>?) -> String? {
    spec.flatMap { fileSystem.path(of: fileSpec($0)) }
}

/// An FSSpec's path, for Carbon's other parts (the Font Manager's).
@c(carbon_spec_path)
public func carbon_spec_path(_ spec: UnsafeRawPointer?, _ buffer: UnsafeMutablePointer<CChar>?, _ size: Int) -> Bool {
    guard let spec, let buffer, size > 0,
          let path = path(of: spec.assumingMemoryBound(to: FSSpec.self)) else { return false }
    let bytes = Array(path.utf8)
    guard bytes.count < size else { return false }
    for (index, byte) in bytes.enumerated() { buffer[index] = CChar(bitPattern: byte) }
    buffer[bytes.count] = 0
    return true
}

/// OSErr FSMakeFSSpec(short vRefNum, long dirID, ConstStr255Param, FSSpec *):
/// fnfErr, with the spec made, for an item that isn't there in a folder
/// that is.
@c(_FSMakeFSSpec)
public func FSMakeFSSpec(_ volume: Int16, _ directory: Int32, _ fileName: UnsafePointer<UInt8>?, _ spec: UnsafeMutablePointer<FSSpec>?) -> Int16 {
    guard let spec else { return MacError.parameter.osErr }
    do {
        let (made, exists) = try fileSystem.makeSpec(volume: volume, directory: directory, name: name(fileName))
        store(made, in: spec)
        return exists ? 0 : MacError.fileNotFound.osErr
    } catch {
        return error.osErr
    }
}

/// OSErr FSpMakeFSRef(const FSSpec *, FSRef *).
@c(_FSpMakeFSRef)
public func FSpMakeFSRef(_ spec: UnsafePointer<FSSpec>?, _ ref: UnsafeMutableRawPointer?) -> Int16 {
    guard let path = path(of: spec) else { return MacError.parameter.osErr }
    return CoreServicesFiles.store(path, in: ref)
}

/// OSErr FSpCreate(const FSSpec *, OSType creator, OSType fileType,
/// ScriptCode): the file, with its type and creator in its Finder info.
@c(_FSpCreate)
public func FSpCreate(_ spec: UnsafePointer<FSSpec>?, _ creator: UInt32, _ type: UInt32, _ script: Int16) -> Int16 {
    guard let path = path(of: spec) else { return MacError.parameter.osErr }
    return osErr { () throws(MacError) in
        try fileSystem.createFile(at: path, finderInfo: FinderInfo(type: FourCharCode(type), creator: FourCharCode(creator)))
    }
}

/// OSErr FSpDirCreate(const FSSpec *, ScriptCode, long *createdDirID).
@c(_FSpDirCreate)
public func FSpDirCreate(_ spec: UnsafePointer<FSSpec>?, _ script: Int16, _ created: UnsafeMutablePointer<Int32>?) -> Int16 {
    guard let path = path(of: spec) else { return MacError.parameter.osErr }
    return osErr { () throws(MacError) in
        let id = try fileSystem.createDirectory(at: path)
        created?.pointee = Int32(bitPattern: id.rawValue)
    }
}

/// OSErr DirCreate(short vRefNum, long parentDirID, ConstStr255Param,
/// long *createdDirID).
@c(_DirCreate)
public func DirCreate(_ volume: Int16, _ parent: Int32, _ directoryName: UnsafePointer<UInt8>?, _ created: UnsafeMutablePointer<Int32>?) -> Int16 {
    guard let folder = fileSystem.folder(volume: volume, directory: parent) else { return MacError.directoryNotFound.osErr }
    let leaf = name(directoryName)
    guard !leaf.isEmpty else { return MacError.badName.osErr }
    return osErr { () throws(MacError) in
        let id = try fileSystem.createDirectory(at: ColonPath.join(folder: folder, name: leaf))
        created?.pointee = Int32(bitPattern: id.rawValue)
    }
}

/// OSErr FSpDelete(const FSSpec *).
@c(_FSpDelete)
public func FSpDelete(_ spec: UnsafePointer<FSSpec>?) -> Int16 {
    guard let path = path(of: spec) else { return MacError.parameter.osErr }
    return osErr { () throws(MacError) in try fileSystem.delete(at: path) }
}

/// OSErr FSpRename(const FSSpec *, ConstStr255Param newName).
@c(_FSpRename)
public func FSpRename(_ spec: UnsafePointer<FSSpec>?, _ newName: UnsafePointer<UInt8>?) -> Int16 {
    guard let path = path(of: spec) else { return MacError.parameter.osErr }
    let leaf = name(newName)
    guard !leaf.isEmpty else { return MacError.badName.osErr }
    return osErr { () throws(MacError) in try fileSystem.rename(at: path, to: FileNames.posix(leaf.string)) }
}

// MARK: - Open files

private func open(_ path: String?, _ kind: ForkKind, _ permission: Int8, _ reference: UnsafeMutablePointer<Int16>?) -> Int16 {
    guard let path, let reference else { return MacError.parameter.osErr }
    return osErr { () throws(MacError) in
        reference.pointee = try fileSystem.open(path, fork: kind, permission: ForkPermission(permission)).reference
    }
}

/// OSErr FSpOpenDF(const FSSpec *, SInt8 permission, short *refNum).
@c(_FSpOpenDF)
public func FSpOpenDF(_ spec: UnsafePointer<FSSpec>?, _ permission: Int8, _ reference: UnsafeMutablePointer<Int16>?) -> Int16 {
    open(path(of: spec), .data, permission, reference)
}

/// OSErr FSpOpenRF(const FSSpec *, SInt8 permission, short *refNum): the
/// resource fork, empty for a file that has none.
@c(_FSpOpenRF)
public func FSpOpenRF(_ spec: UnsafePointer<FSSpec>?, _ permission: Int8, _ reference: UnsafeMutablePointer<Int16>?) -> Int16 {
    open(path(of: spec), .resource, permission, reference)
}

/// OSErr FSClose(short refNum).
@c(_FSClose)
public func FSClose(_ reference: Int16) -> Int16 {
    osErr { () throws(MacError) in try fileSystem.close(reference) }
}

/// Reads at the mark, or from `position`: eofErr if the end came first.
private func read(_ fork: Fork, _ buffer: UnsafeMutableRawPointer?, _ count: Int, from position: ForkPosition? = nil) -> (Int, Int16) {
    guard count > 0 else {
        if let position, (try? fork.seek(position)) == nil { return (0, MacError.position.osErr) }
        return (0, 0)
    }
    guard let buffer else { return (0, MacError.parameter.osErr) }
    do {
        let read = try fork.read(into: UnsafeMutableRawBufferPointer(start: buffer, count: count), from: position)
        return (read, read < count ? MacError.endOfFile.osErr : 0)
    } catch {
        return (0, error.osErr)
    }
}

/// Writes at the mark, or at `position`.
private func write(_ fork: Fork, _ buffer: UnsafeRawPointer?, _ count: Int, at position: ForkPosition? = nil) -> (Int, Int16) {
    guard count > 0 else { return (0, 0) }
    guard let buffer else { return (0, MacError.parameter.osErr) }
    do {
        return (try fork.write(UnsafeRawBufferPointer(start: buffer, count: count), at: position), 0)
    } catch {
        return (0, error.osErr)
    }
}

/// OSErr FSRead(short refNum, long *count, void *buffer).
@c(_FSRead)
public func FSRead(_ reference: Int16, _ count: UnsafeMutablePointer<Int32>?, _ buffer: UnsafeMutableRawPointer?) -> Int16 {
    guard let fork = fileSystem.fork(reference) else { return MacError.referenceNumber.osErr }
    guard let count, count.pointee >= 0 else { return MacError.parameter.osErr }
    let (read, error) = read(fork, buffer, Int(count.pointee))
    count.pointee = Int32(read)
    return error
}

/// OSErr FSWrite(short refNum, long *count, const void *buffer).
@c(_FSWrite)
public func FSWrite(_ reference: Int16, _ count: UnsafeMutablePointer<Int32>?, _ buffer: UnsafeRawPointer?) -> Int16 {
    guard let fork = fileSystem.fork(reference) else { return MacError.referenceNumber.osErr }
    guard let count, count.pointee >= 0 else { return MacError.parameter.osErr }
    let (written, error) = write(fork, buffer, Int(count.pointee))
    count.pointee = Int32(written)
    return error
}

/// OSErr GetEOF(short refNum, long *logEOF).
@c(_GetEOF)
public func GetEOF(_ reference: Int16, _ size: UnsafeMutablePointer<Int32>?) -> Int16 {
    guard let fork = fileSystem.fork(reference) else { return MacError.referenceNumber.osErr }
    size?.pointee = Int32(clamping: fork.size)
    return 0
}

/// OSErr SetEOF(short refNum, long logEOF).
@c(_SetEOF)
public func SetEOF(_ reference: Int16, _ size: Int32) -> Int16 {
    guard let fork = fileSystem.fork(reference) else { return MacError.referenceNumber.osErr }
    return osErr { () throws(MacError) in try fork.setSize(Int64(size)) }
}

/// OSErr SetFPos(short refNum, short posMode, long posOff): eofErr, with the
/// mark at the end, past the end.
@c(_SetFPos)
public func SetFPos(_ reference: Int16, _ mode: Int16, _ offset: Int32) -> Int16 {
    guard let fork = fileSystem.fork(reference) else { return MacError.referenceNumber.osErr }
    do {
        let position = try fork.seek(ForkPosition(mode: UInt16(bitPattern: mode), offset: Int64(offset)))
        if position > fork.size {
            try fork.seek(.end(0))
            return MacError.endOfFile.osErr
        }
        return 0
    } catch {
        return error.osErr
    }
}

/// OSErr GetFPos(short refNum, long *filePos).
@c(_GetFPos)
public func GetFPos(_ reference: Int16, _ position: UnsafeMutablePointer<Int32>?) -> Int16 {
    guard let fork = fileSystem.fork(reference) else { return MacError.referenceNumber.osErr }
    position?.pointee = Int32(clamping: fork.position)
    return 0
}

// MARK: - Reads by parameter block

/// A block's read: from where its mode says, its count, leaving the mark
/// after what was read in its offset.
private func read(_ block: UnsafeMutablePointer<IOParam>) -> Int16 {
    block.pointee.ioActCount = 0
    guard let fork = fileSystem.fork(block.pointee.ioRefNum) else { return MacError.referenceNumber.osErr }
    guard block.pointee.ioReqCount >= 0 else { return MacError.parameter.osErr }
    let position = ForkPosition(mode: UInt16(bitPattern: block.pointee.ioPosMode), offset: Int64(block.pointee.ioPosOffset))
    let (count, error) = read(fork, block.pointee.ioBuffer, Int(block.pointee.ioReqCount), from: position)
    block.pointee.ioActCount = Int32(count)
    block.pointee.ioPosOffset = Int32(clamping: fork.position)
    return error
}

/// OSErr PBReadSync(ParmBlkPtr).
@c(_PBReadSync)
public func PBReadSync(_ block: UnsafeMutablePointer<IOParam>?) -> Int16 {
    guard let block else { return MacError.parameter.osErr }
    let result = read(block)
    block.pointee.ioResult = result
    return result
}

/// A completion routine, as Darwin's code is called.
private typealias IOCompletion = @convention(c) (UnsafeMutablePointer<IOParam>?) -> Void

/// Asynchronous reads: in order, on a thread of their own, each block's
/// result set and then its completion routine called, as a Mac's are.
private enum AsynchronousReads {

    static let queue = MPQueue()

    static let reader: MPTask? = try? MPTask.create {
        while let message = try? queue.wait() {
            guard let block = UnsafeMutablePointer<IOParam>(bitPattern: message.first) else { continue }
            block.pointee.ioResult = read(block)
            // The result, then the completion routine, which may look at it.
            atomicMemoryFence(ordering: .sequentiallyConsistent)
            if let completion = block.pointee.ioCompletion {
                darwinCallable(unsafeBitCast(completion, to: IOCompletion.self))(block)
            }
        }
        return 0
    }
}

/// OSErr PBReadAsync(ParmBlkPtr): ioResult is ioInProgress (1) until the
/// read is done.
@c(_PBReadAsync)
public func PBReadAsync(_ block: UnsafeMutablePointer<IOParam>?) -> Int16 {
    guard let block else { return MacError.parameter.osErr }
    guard AsynchronousReads.reader != nil else { return MacError.tooManyFilesOpen.osErr }
    block.pointee.ioResult = 1
    block.pointee.qLink = nil
    return osErr { () throws(MacError) in try AsynchronousReads.queue.notify(UInt(bitPattern: block), 0, 0) }
}

// MARK: - Forks

private let resourceForkName = "RESOURCE_FORK"

/// void FSGetDataForkName(HFSUniStr255 *): an empty name.
@c(_FSGetDataForkName)
public func FSGetDataForkName(_ name: UnsafeMutablePointer<HFSUniStr255>?) {
    name?.pointee.length = 0
}

/// void FSGetResourceForkName(HFSUniStr255 *): "RESOURCE_FORK".
@c(_FSGetResourceForkName)
public func FSGetResourceForkName(_ name: UnsafeMutablePointer<HFSUniStr255>?) {
    store(resourceForkName, in: name)
}

/// OSErr FSOpenFork(const FSRef *, UniCharCount forkNameLength, const
/// UniChar *forkName, SInt8 permissions, FSIORefNum *): the data fork for
/// an empty name, else the resource fork.
@c(_FSOpenFork)
public func FSOpenFork(_ ref: UnsafeRawPointer?, _ nameLength: Int, _ forkName: UnsafePointer<UInt16>?, _ permission: Int8,
                       _ reference: UnsafeMutablePointer<Int16>?) -> Int16 {
    open(CoreServicesFiles.path(of: ref), nameLength == 0 ? .data : .resource, permission, reference)
}

/// OSErr FSCloseFork(FSIORefNum).
@c(_FSCloseFork)
public func FSCloseFork(_ reference: Int16) -> Int16 {
    FSClose(reference)
}

/// OSErr FSReadFork(FSIORefNum, UInt16 positionMode, SInt64 positionOffset,
/// ByteCount requestCount, void *buffer, ByteCount *actualCount).
@DarwinC("_FSReadFork")
public func FSReadFork(_ reference: Int16, _ mode: UInt16, _ offset: Int64, _ count: UInt32, _ buffer: UnsafeMutableRawPointer?,
                       _ actual: UnsafeMutablePointer<UInt32>?) -> Int16 {
    actual?.pointee = 0
    guard let fork = fileSystem.fork(reference) else { return MacError.referenceNumber.osErr }
    let (read, error) = read(fork, buffer, Int(count), from: ForkPosition(mode: mode, offset: offset))
    actual?.pointee = UInt32(read)
    return error
}

/// OSErr FSWriteFork(FSIORefNum, UInt16 positionMode, SInt64
/// positionOffset, ByteCount requestCount, const void *buffer, ByteCount
/// *actualCount).
@DarwinC("_FSWriteFork")
public func FSWriteFork(_ reference: Int16, _ mode: UInt16, _ offset: Int64, _ count: UInt32, _ buffer: UnsafeRawPointer?,
                        _ actual: UnsafeMutablePointer<UInt32>?) -> Int16 {
    actual?.pointee = 0
    guard let fork = fileSystem.fork(reference) else { return MacError.referenceNumber.osErr }
    let position = ForkPosition(mode: mode, offset: offset)
    if count == 0 { return osErr { () throws(MacError) in _ = try fork.seek(position) } }
    let (written, error) = write(fork, buffer, Int(count), at: position)
    actual?.pointee = UInt32(written)
    return error
}

/// OSErr FSGetForkSize(FSIORefNum, SInt64 *).
@c(_FSGetForkSize)
public func FSGetForkSize(_ reference: Int16, _ size: UnsafeMutablePointer<Int64>?) -> Int16 {
    guard let fork = fileSystem.fork(reference) else { return MacError.referenceNumber.osErr }
    size?.pointee = fork.size
    return 0
}

/// The offset a positioning mode names, without moving the mark.
private func offset(of fork: Fork, _ mode: UInt16, _ offset: Int64) -> Int64 {
    switch ForkPosition(mode: mode, offset: offset) {
    case .start(let offset): offset
    case .end(let offset): fork.size + offset
    case .mark(let offset): fork.position + offset
    }
}

/// OSErr FSSetForkSize(FSIORefNum, UInt16 positionMode, SInt64
/// positionOffset).
@DarwinC("_FSSetForkSize")
public func FSSetForkSize(_ reference: Int16, _ mode: UInt16, _ positionOffset: Int64) -> Int16 {
    guard let fork = fileSystem.fork(reference) else { return MacError.referenceNumber.osErr }
    let size = offset(of: fork, mode, positionOffset)
    guard size >= 0 else { return MacError.position.osErr }
    return osErr { () throws(MacError) in try fork.setSize(size) }
}

/// OSErr FSIterateForks(const FSRef *, CatPositionRec *, HFSUniStr255
/// *forkName, SInt64 *forkSize, UInt64 *forkPhysicalSize): a file's data
/// fork, then its resource fork if it has one; a folder has none.
@c(_FSIterateForks)
public func FSIterateForks(_ ref: UnsafeRawPointer?, _ position: UnsafeMutablePointer<CatPositionRec>?, _ forkName: UnsafeMutablePointer<HFSUniStr255>?,
                           _ size: UnsafeMutablePointer<Int64>?, _ physical: UnsafeMutablePointer<UInt64>?) -> Int16 {
    guard let position, let path = CoreServicesFiles.path(of: ref) else { return MacError.parameter.osErr }
    guard let info = try? fileSystem.catalogInfo(at: path) else { return MacError.fileNotFound.osErr }
    var forks: [(String, Int64, Int64)] = []
    if !info.isDirectory {
        forks.append(("", info.dataLogicalSize, info.dataPhysicalSize))
        if info.resourceLogicalSize > 0 { forks.append((resourceForkName, info.resourceLogicalSize, info.resourcePhysicalSize)) }
    }
    let index = Int(position.pointee.initialize)
    guard index >= 0, index < forks.count else { return MacError.noMoreItems.osErr }
    position.pointee.initialize = Int32(index + 1)
    store(forks[index].0, in: forkName)
    size?.pointee = forks[index].1
    physical?.pointee = UInt64(forks[index].2)
    return 0
}

/// OSErr FSCreateFork(const FSRef *, UniCharCount forkNameLength, const
/// UniChar *forkName): a file's data fork is always there; a resource fork
/// is made empty, as FSOpenFork opens one for writing.
@c(_FSCreateFork)
public func FSCreateFork(_ ref: UnsafeRawPointer?, _ nameLength: Int, _ forkName: UnsafePointer<UInt16>?) -> Int16 {
    guard let path = CoreServicesFiles.path(of: ref) else { return MacError.parameter.osErr }
    guard let info = try? fileSystem.catalogInfo(at: path) else { return MacError.fileNotFound.osErr }
    if nameLength == 0 || info.resourceLogicalSize > 0 { return MacError.forkExists.osErr }
    return 0
}

/// OSErr FSAllocateFork(FSIORefNum, FSAllocationFlags, UInt16 positionMode,
/// SInt64 positionOffset, UInt64 requestCount, UInt64 *actualCount): space
/// for a fork to grow into, which Linux's file systems give as it is
/// written, so all of it is taken as allocated. Its 64-bit arguments are
/// where Darwin's ppc passes them (@DarwinC), from r6, where Linux's would
/// be from r7.
@DarwinC("_FSAllocateFork")
public func FSAllocateFork(_ reference: Int16, _ flags: UInt16, _ mode: UInt16, _ positionOffset: Int64, _ count: UInt64,
                           _ actual: UnsafeMutablePointer<UInt64>?) -> Int16 {
    actual?.pointee = 0
    guard let fork = fileSystem.fork(reference) else { return MacError.referenceNumber.osErr }
    do {
        actual?.pointee = try fork.allocate(count)
        return 0
    } catch {
        return error.osErr
    }
}

/// OSErr FSGetForkPosition(FSIORefNum, SInt64 *).
@c(_FSGetForkPosition)
public func FSGetForkPosition(_ reference: Int16, _ position: UnsafeMutablePointer<Int64>?) -> Int16 {
    guard let fork = fileSystem.fork(reference) else { return MacError.referenceNumber.osErr }
    position?.pointee = fork.position
    return 0
}

/// OSErr FSSetForkPosition(FSIORefNum, UInt16 positionMode, SInt64
/// positionOffset).
@DarwinC("_FSSetForkPosition")
public func FSSetForkPosition(_ reference: Int16, _ mode: UInt16, _ positionOffset: Int64) -> Int16 {
    guard let fork = fileSystem.fork(reference) else { return MacError.referenceNumber.osErr }
    return osErr { () throws(MacError) in _ = try fork.seek(ForkPosition(mode: mode, offset: positionOffset)) }
}

/// OSErr FSFlushFork(FSIORefNum).
@c(_FSFlushFork)
public func FSFlushFork(_ reference: Int16) -> Int16 {
    guard let fork = fileSystem.fork(reference) else { return MacError.referenceNumber.osErr }
    return osErr { () throws(MacError) in try fork.flush() }
}

// MARK: - Making, moving and deleting

// FSCatalogInfo (2-byte packed): its Finder info at 72 and extended Finder
// info at 88; kFSCatInfoFinderInfo and kFSCatInfoFinderXInfo ask for them.
private let catalogFinderInfo: UInt32 = 0x0800
private let catalogFinderXInfo: UInt32 = 0x1000

/// The Finder info an FSCatalogInfo sets, over what the item has.
private func finderInfo(_ which: UInt32, _ info: UnsafeRawPointer?, over current: FinderInfo = FinderInfo()) -> FinderInfo? {
    guard let info, which & (catalogFinderInfo | catalogFinderXInfo) != 0 else { return nil }
    var bytes = current.bytes
    if which & catalogFinderInfo != 0 {
        for index in 0 ..< 16 { bytes[index] = info.load(fromByteOffset: 72 + index, as: UInt8.self) }
    }
    if which & catalogFinderXInfo != 0 {
        for index in 0 ..< 16 { bytes[16 + index] = info.load(fromByteOffset: 88 + index, as: UInt8.self) }
    }
    return FinderInfo(bytes: bytes)
}

private func childPath(_ parent: UnsafeRawPointer?, _ length: Int, _ name: UnsafePointer<UInt16>?) -> String? {
    guard let folder = CoreServicesFiles.path(of: parent), let leaf = unicodeName(length, name) else { return nil }
    return folder == "/" ? "/" + leaf : folder + "/" + leaf
}

/// OSErr FSCreateFileUnicode(const FSRef *parentRef, UniCharCount
/// nameLength, const UniChar *name, FSCatalogInfoBitmap whichInfo, const
/// FSCatalogInfo *, FSRef *newRef, FSSpec *newSpec): its Finder info from
/// the catalog information when it is given.
@c(_FSCreateFileUnicode)
public func FSCreateFileUnicode(_ parent: UnsafeRawPointer?, _ length: Int, _ name: UnsafePointer<UInt16>?, _ which: UInt32,
                                _ info: UnsafeRawPointer?, _ ref: UnsafeMutableRawPointer?, _ spec: UnsafeMutablePointer<FSSpec>?) -> Int16 {
    guard let path = childPath(parent, length, name) else { return MacError.parameter.osErr }
    let error = osErr { () throws(MacError) in try fileSystem.createFile(at: path, finderInfo: finderInfo(which, info)) }
    guard error == 0 else { return error }
    CoreServicesFiles.store(path, in: ref)
    store(fileSystem.spec(forPath: path), in: spec)
    return 0
}

/// OSErr FSCreateDirectoryUnicode(const FSRef *parentRef, UniCharCount
/// nameLength, const UniChar *name, FSCatalogInfoBitmap whichInfo, const
/// FSCatalogInfo *, FSRef *newRef, FSSpec *newSpec, UInt32 *newDirID).
@c(_FSCreateDirectoryUnicode)
public func FSCreateDirectoryUnicode(_ parent: UnsafeRawPointer?, _ length: Int, _ name: UnsafePointer<UInt16>?, _ which: UInt32,
                                     _ info: UnsafeRawPointer?, _ ref: UnsafeMutableRawPointer?, _ spec: UnsafeMutablePointer<FSSpec>?,
                                     _ directory: UnsafeMutablePointer<UInt32>?) -> Int16 {
    guard let path = childPath(parent, length, name) else { return MacError.parameter.osErr }
    do {
        let id = try fileSystem.createDirectory(at: path)
        if let finder = finderInfo(which, info) { try? fileSystem.setFinderInfo(finder, at: path) }
        directory?.pointee = id.rawValue
    } catch {
        return error.osErr
    }
    CoreServicesFiles.store(path, in: ref)
    store(fileSystem.spec(forPath: path), in: spec)
    return 0
}

/// OSErr FSDeleteObject(const FSRef *): fBsyErr for a folder that isn't
/// empty.
@c(_FSDeleteObject)
public func FSDeleteObject(_ ref: UnsafeRawPointer?) -> Int16 {
    guard let path = CoreServicesFiles.path(of: ref) else { return MacError.parameter.osErr }
    return osErr { () throws(MacError) in try fileSystem.delete(at: path) }
}

/// OSErr FSMoveObject(const FSRef *, const FSRef *destDirectory, FSRef
/// *newRef).
@c(_FSMoveObject)
public func FSMoveObject(_ ref: UnsafeRawPointer?, _ destination: UnsafeRawPointer?, _ moved: UnsafeMutableRawPointer?) -> Int16 {
    guard let path = CoreServicesFiles.path(of: ref), let folder = CoreServicesFiles.path(of: destination) else {
        return MacError.parameter.osErr
    }
    do {
        CoreServicesFiles.store(try fileSystem.move(at: path, into: folder), in: moved)
        return 0
    } catch {
        return error.osErr
    }
}

/// OSErr FSRenameUnicode(const FSRef *, UniCharCount nameLength, const
/// UniChar *name, TextEncoding textEncodingHint, FSRef *newRef).
@c(_FSRenameUnicode)
public func FSRenameUnicode(_ ref: UnsafeRawPointer?, _ length: Int, _ name: UnsafePointer<UInt16>?, _ hint: UInt32,
                            _ renamed: UnsafeMutableRawPointer?) -> Int16 {
    guard let path = CoreServicesFiles.path(of: ref), let leaf = unicodeName(length, name) else { return MacError.parameter.osErr }
    do {
        CoreServicesFiles.store(try fileSystem.rename(at: path, to: leaf), in: renamed)
        return 0
    } catch {
        return error.osErr
    }
}

/// OSErr FSSetCatalogInfo(const FSRef *, FSCatalogInfoBitmap whichInfo,
/// const FSCatalogInfo *): its Finder info is kept in the item's
/// AppleDouble file; dates and permissions aren't changed.
@c(_FSSetCatalogInfo)
public func FSSetCatalogInfo(_ ref: UnsafeRawPointer?, _ which: UInt32, _ info: UnsafeRawPointer?) -> Int16 {
    guard let path = CoreServicesFiles.path(of: ref) else { return MacError.parameter.osErr }
    return osErr { () throws(MacError) in
        let current = try fileSystem.finderInfo(at: path)
        if let finder = finderInfo(which, info, over: current), finder != current { try fileSystem.setFinderInfo(finder, at: path) }
    }
}

// MARK: - Folders' items

/// An FSIterator: a folder's names, taken when it was opened.
private final class FolderIterator {
    let folder: String
    let names: [String]
    var next = 0

    init(folder: String, names: [String]) {
        self.folder = folder
        self.names = names
    }
}

/// OSErr FSOpenIterator(const FSRef *container, FSIteratorFlags, FSIterator *).
@c(_FSOpenIterator)
public func FSOpenIterator(_ container: UnsafeRawPointer?, _ options: UInt32, _ iterator: UnsafeMutablePointer<UnsafeMutableRawPointer?>?) -> Int16 {
    guard let iterator else { return MacError.parameter.osErr }
    guard let folder = CoreServicesFiles.path(of: container),
          let names = try? fileSystem.contents(ofFolder: folder) else { return MacError.directoryNotFound.osErr }
    iterator.pointee = Unmanaged.passRetained(FolderIterator(folder: folder, names: names)).toOpaque()
    return 0
}

/// OSErr FSCloseIterator(FSIterator).
@c(_FSCloseIterator)
public func FSCloseIterator(_ iterator: UnsafeMutableRawPointer?) -> Int16 {
    guard let iterator else { return MacError.parameter.osErr }
    Unmanaged<FolderIterator>.fromOpaque(iterator).release()
    return 0
}

/// OSErr FSGetCatalogInfoBulk(FSIterator, ItemCount maximumObjects, ItemCount
/// *actualObjects, Boolean *containerChanged, FSCatalogInfoBitmap whichInfo,
/// FSCatalogInfo *catalogInfos, FSRef *refs, FSSpec *specs, HFSUniStr255
/// *names): CoreServices' catalog information for each, 144 bytes apart.
@c(_FSGetCatalogInfoBulk)
public func FSGetCatalogInfoBulk(_ iterator: UnsafeMutableRawPointer?, _ maximum: Int, _ count: UnsafeMutablePointer<Int>?,
                                 _ changed: UnsafeMutablePointer<UInt8>?, _ which: UInt32, _ infos: UnsafeMutableRawPointer?,
                                 _ refs: UnsafeMutablePointer<FSRef>?, _ specs: UnsafeMutablePointer<FSSpec>?,
                                 _ names: UnsafeMutablePointer<HFSUniStr255>?) -> Int16 {
    guard let iterator, let count else { return MacError.parameter.osErr }
    let items = Unmanaged<FolderIterator>.fromOpaque(iterator).takeUnretainedValue()
    changed?.pointee = 0
    var found = 0
    while found < maximum, items.next < items.names.count {
        let path = items.folder == "/" ? "/" + items.names[items.next] : items.folder + "/" + items.names[items.next]
        items.next += 1
        var ref = FSRef()
        guard withUnsafeMutableBytes(of: &ref, { CoreServicesFiles.store(path, in: $0.baseAddress) }) == 0 else { continue }
        refs?[found] = ref
        if let specs { store(fileSystem.spec(forPath: path), in: specs + found) }
        if infos != nil || names != nil, let catalog = CoreServicesFiles.catalogInfo {
            _ = withUnsafeBytes(of: &ref) { catalog($0.baseAddress, which, infos.map { $0 + found * 144 }, names.map { $0 + found }, nil, nil) }
        }
        found += 1
    }
    count.pointee = found
    return found == 0 ? MacError.noMoreItems.osErr : 0
}

// MARK: - The default folder

/// OSErr HGetVol(StringPtr volName, short *vRefNum, long *dirID).
@c(_HGetVol)
public func HGetVol(_ volumeName: UnsafeMutablePointer<UInt8>?, _ volume: UnsafeMutablePointer<Int16>?, _ directory: UnsafeMutablePointer<Int32>?) -> Int16 {
    store(PascalString(fileSystem.volume.name) ?? "Macintosh HD", at: volumeName, capacity: 28)
    volume?.pointee = fileSystem.volume.reference
    directory?.pointee = Int32(bitPattern: fileSystem.defaultDirectory.id.rawValue)
    return 0
}

/// OSErr HSetVol(ConstStr63Param volName, short vRefNum, long dirID).
@c(_HSetVol)
public func HSetVol(_ volumeName: UnsafePointer<UInt8>?, _ volume: Int16, _ directory: Int32) -> Int16 {
    guard volume == 0 || volume == fileSystem.volume.reference else { return MacError.noSuchVolume.osErr }
    guard directory != 0 else { return 0 }
    return osErr { () throws(MacError) in
        try fileSystem.setDefaultDirectory(volume: volume, directory: DirectoryID(UInt32(bitPattern: directory)))
    }
}

/// OSErr FindFolder(short vRefNum, OSType folderType, Boolean createFolder,
/// short *foundVRefNum, long *foundDirID): CoreServices' FSFindFolder's
/// folder, by its ID.
@c(_FindFolder)
public func FindFolder(_ volume: Int16, _ type: UInt32, _ create: UInt8, _ foundVolume: UnsafeMutablePointer<Int16>?,
                       _ foundDirectory: UnsafeMutablePointer<Int32>?) -> Int16 {
    do {
        let path = try CoreServicesFiles.folder(volume: volume, type: type, create: create != 0)
        guard let id = fileSystem.directoryID(ofFolder: path) else { return MacError.fileNotFound.osErr }
        foundVolume?.pointee = fileSystem.volume.reference
        foundDirectory?.pointee = Int32(bitPattern: id.rawValue)
        return 0
    } catch {
        return error.osErr
    }
}

// MARK: - Parameter blocks

/// OSErr PBGetCatInfoSync(CInfoPBPtr): an item by name (index 0), by
/// position in its folder (index > 0, its visible items in the order the
/// file system gives them), or the folder itself (index < 0).
@c(_PBGetCatInfoSync)
public func PBGetCatInfoSync(_ block: UnsafeMutablePointer<CInfoPB>?) -> Int16 {
    guard let block else { return MacError.parameter.osErr }
    let result = catalogInfo(block)
    block.pointee.header.ioResult = result
    return result
}

private func catalogInfo(_ block: UnsafeMutablePointer<CInfoPB>) -> Int16 {
    guard let folder = fileSystem.folder(volume: block.pointee.header.ioVRefNum, directory: block.pointee.ioDirID) else {
        return MacError.directoryNotFound.osErr
    }
    let index = block.pointee.ioFDirIndex
    let given = name(block.pointee.header.ioNamePtr.map { UnsafePointer($0) })
    var path: String
    if index < 0 || (index == 0 && given.isEmpty) {
        path = folder
    } else if index > 0 {
        guard let names = try? fileSystem.contents(ofFolder: folder, includingHidden: false), Int(index) <= names.count else {
            return MacError.fileNotFound.osErr
        }
        path = folder == "/" ? "/" + names[Int(index) - 1] : folder + "/" + names[Int(index) - 1]
    } else {
        guard let found = fileSystem.lookUp(ColonPath.join(folder: folder, name: given)) else { return MacError.fileNotFound.osErr }
        path = found
    }
    let info: CatalogInfo
    do {
        info = try fileSystem.catalogInfo(at: path)
    } catch {
        return error.osErr
    }
    // The item's name back, when the caller gave room for it.
    if index != 0, let storage = block.pointee.header.ioNamePtr {
        let spec = fileSystem.spec(forPath: path)
        store(spec.name, at: storage, capacity: 64)
    }
    block.pointee.header.ioVRefNum = fileSystem.volume.reference
    block.pointee.ioFlAttrib = info.isDirectory ? 0x10 : 0
    let finder = info.finderInfo.bytes
    withUnsafeMutableBytes(of: &block.pointee.ioFlFndrInfo) { for index in 0 ..< 16 { $0[index] = finder[index] } }
    withUnsafeMutableBytes(of: &block.pointee.ioFlXFndrInfo) { for index in 0 ..< 16 { $0[index] = finder[16 + index] } }
    block.pointee.ioFlParID = Int32(bitPattern: info.parentID.rawValue)
    block.pointee.ioFlCrDat = info.created.classicSeconds
    block.pointee.ioFlMdDat = info.contentModified.classicSeconds
    block.pointee.ioFlBkDat = 0
    block.pointee.ioDirID = Int32(bitPattern: info.nodeID)
    if info.isDirectory {
        block.pointee.ioFlStBlk = UInt16(clamping: info.valence)
    } else {
        block.pointee.ioFlStBlk = 0
        block.pointee.ioFlLgLen = Int32(clamping: info.dataLogicalSize)
        block.pointee.ioFlPyLen = Int32(clamping: info.dataPhysicalSize)
        block.pointee.ioFlRStBlk = 0
        block.pointee.ioFlRLgLen = Int32(clamping: info.resourceLogicalSize)
        block.pointee.ioFlRPyLen = Int32(clamping: info.resourcePhysicalSize)
    }
    return 0
}

/// OSErr PBGetCatInfoAsync(CInfoPBPtr): done at once.
@c(_PBGetCatInfoAsync)
public func PBGetCatInfoAsync(_ block: UnsafeMutablePointer<CInfoPB>?) -> Int16 {
    PBGetCatInfoSync(block)
}

/// The first disc's volume number; the others go down from it.
private let firstDiscVolume: Int16 = -101

/// A mounted disc: its index from 0, name and mount point.
private struct Disc {
    var index: Int
    var name: String
    var mount: String
}

/// The disc a volume number or a volume index (from 1; the discs from 2)
/// names; nil for the first volume. Throws nsvErr for no such volume.
private func disc(volume: Int16, index: Int) throws(MacError) -> Disc? {
    var number = -1
    if index > 1 {
        number = index - 2
    } else if index <= 0, volume <= firstDiscVolume {
        number = Int(firstDiscVolume) - Int(volume)
    } else if index <= 0, volume != 0, volume != fileSystem.volume.reference, volume != -1 {
        throw .noSuchVolume
    }
    guard number >= 0 else { return nil }
    var name = [CChar](repeating: 0, count: 256), mount = [CChar](repeating: 0, count: 4096)
    guard number < Int(carbon_disc_volume(Int32(number), &name, name.count, &mount, mount.count)) else { throw .noSuchVolume }
    return Disc(index: number, name: String(cString: name), mount: String(cString: mount))
}

/// OSErr PBHGetVInfoSync(HParmBlkPtr): a volume, by its number, its name or
/// its index (from 1): the first, and the discs mounted after it. Its sizes
/// are at most 2 GB, in blocks large enough for their counts to fit 16 bits,
/// as the File Manager reported a volume over 2 GB here.
@c(_PBHGetVInfoSync)
public func PBHGetVInfoSync(_ block: UnsafeMutablePointer<HVolumeParam>?) -> Int16 {
    guard let block else { return MacError.parameter.osErr }
    let found: Disc?
    do {
        found = try disc(volume: block.pointee.header.ioVRefNum, index: Int(block.pointee.ioVolIndex))
    } catch {
        block.pointee.header.ioResult = error.osErr
        return error.osErr
    }
    let space = Volume.Space(path: found?.mount ?? fileSystem.volume.spacePath) ?? Volume.Space(total: 0, free: 0)
    let classic = space.classic
    let volumeName = found?.name ?? fileSystem.volume.name
    store(PascalString(volumeName) ?? PascalString(bytes: volumeName.utf8), at: block.pointee.header.ioNamePtr, capacity: 28)
    block.pointee.header.ioVRefNum = found.map { firstDiscVolume - Int16($0.index) } ?? fileSystem.volume.reference
    block.pointee.ioVCrDate = MacDate(unixTime: 0).classicSeconds
    block.pointee.ioVLsMod = MacDate.now.classicSeconds
    // A disc is locked, by hardware and by software.
    block.pointee.ioVAtrb = found == nil ? 0 : Int16(bitPattern: 0x8080)
    block.pointee.ioVNmFls = 0
    block.pointee.ioVNmAlBlks = classic.blocks
    block.pointee.ioVAlBlkSiz = classic.blockSize
    block.pointee.ioVClpSiz = classic.blockSize
    block.pointee.ioVFrBlk = classic.freeBlocks
    block.pointee.ioVSigWord = 0x482B   // 'H+'
    block.pointee.ioVDrvInfo = 1
    block.pointee.ioVDRefNum = -1
    block.pointee.ioVFSID = 0
    block.pointee.ioVFilCnt = 0
    block.pointee.ioVDirCnt = 0
    withUnsafeMutableBytes(of: &block.pointee.ioVFndrInfo) { $0.initializeMemory(as: UInt8.self, repeating: 0) }
    block.pointee.header.ioResult = 0
    return 0
}

/// OSErr PBHSetVolSync(WDPBPtr): the default folder from a parameter
/// block's volume and folder ID, as HSetVol takes them. Pangea's games set
/// their Resources folder so and find ":Data:" in it.
@c(_PBHSetVolSync)
public func PBHSetVolSync(_ block: UnsafeMutablePointer<WDPBRec>?) -> Int16 {
    guard let block else { return MacError.parameter.osErr }
    let result = HSetVol(block.pointee.header.ioNamePtr.map { UnsafePointer($0) }, block.pointee.header.ioVRefNum, block.pointee.ioWDDirID)
    block.pointee.header.ioResult = result
    return result
}

/// OSErr PBHGetVolSync(WDPBPtr).
@c(_PBHGetVolSync)
public func PBHGetVolSync(_ block: UnsafeMutablePointer<WDPBRec>?) -> Int16 {
    guard let block else { return MacError.parameter.osErr }
    var volume: Int16 = 0
    var directory: Int32 = 0
    _ = HGetVol(block.pointee.header.ioNamePtr, &volume, &directory)
    block.pointee.header.ioVRefNum = volume
    block.pointee.ioWDVRefNum = volume
    block.pointee.ioWDDirID = directory
    block.pointee.ioWDProcID = 0
    block.pointee.header.ioResult = 0
    return 0
}

/// OSErr PBHGetDirAccessSync(HParmBlkPtr): a folder's access, as a local
/// volume's: the user owns it, with every right (a set bit in ioACUser is
/// one the user lacks), and it is not shared.
@c(_PBHGetDirAccessSync)
public func PBHGetDirAccessSync(_ block: UnsafeMutablePointer<AccessParam>?) -> Int16 {
    guard let block else { return MacError.parameter.osErr }
    let result: Int16
    if let folder = fileSystem.folder(volume: block.pointee.header.ioVRefNum, directory: block.pointee.ioDirID) {
        let given = name(block.pointee.header.ioNamePtr.map { UnsafePointer($0) })
        let path = given.isEmpty ? folder : fileSystem.lookUp(ColonPath.join(folder: folder, name: given))
        if let path, let info = try? fileSystem.catalogInfo(at: path) {
            result = info.isDirectory ? 0 : MacError.directoryNotFound.osErr
        } else {
            result = MacError.fileNotFound.osErr
        }
    } else {
        result = MacError.directoryNotFound.osErr
    }
    if result == 0 {
        block.pointee.ioACUser = 0
        block.pointee.ioACOwnerID = 0
        block.pointee.ioACGroupID = 0
        block.pointee.ioACAccess = 0
    }
    block.pointee.header.ioResult = result
    return result
}

/// The device IDs a volume's parameters point to, kept for as long as the
/// program runs: the first's "disk1s1", the discs' "disk2s1" and up, as
/// IOKit's media and getmntinfo name them.
nonisolated(unsafe) private let deviceNames: [UnsafeMutablePointer<CChar>] = (1 ... 9).map { strdup("disk\($0)s1")! }

/// OSErr PBHGetVolParmsSync(HParmBlkPtr): version 4's GetVolParmsInfoBuffer
/// of a local, fixed disk that keeps no desktop database; a disc's, of an
/// ejectable, removable one.
@c(_PBHGetVolParmsSync)
public func PBHGetVolParmsSync(_ block: UnsafeMutablePointer<HIOParam>?) -> Int16 {
    guard let block else { return MacError.parameter.osErr }
    let found: Disc?
    do {
        found = try disc(volume: block.pointee.header.ioVRefNum, index: 0)
    } catch {
        block.pointee.header.ioResult = error.osErr
        return error.osErr
    }
    var parameters = GetVolParmsInfoBuffer()
    parameters.vMVersion = 4
    parameters.vMAttrib = Int32(bitPattern: 1 << 31 | 1 << 20 | 1 << 17)
    parameters.vMDeviceID = UnsafeMutableRawPointer(deviceNames[0])
    parameters.vMMaxNameLength = 255
    if let found, found.index + 1 < deviceNames.count {
        parameters.vMDeviceID = UnsafeMutableRawPointer(deviceNames[found.index + 1])
        // bIsEjectable (0) and bIsRemovable (11).
        parameters.vMExtendedAttributes = 1 << 0 | 1 << 11
    }
    let size = max(0, min(Int(block.pointee.ioReqCount), MemoryLayout<GetVolParmsInfoBuffer>.size))
    if let buffer = block.pointee.ioBuffer, size > 0 {
        withUnsafeBytes(of: &parameters) { buffer.copyMemory(from: $0.baseAddress!, byteCount: size) }
    }
    block.pointee.ioActCount = Int32(size)
    block.pointee.header.ioResult = 0
    return 0
}

/// OSErr PBDTGetPath(DTPBPtr): there is no desktop database; its reference
/// number is the volume's.
@c(_PBDTGetPath)
public func PBDTGetPath(_ block: UnsafeMutablePointer<DTPB>?) -> Int16 {
    guard let block else { return MacError.parameter.osErr }
    block.pointee.ioDTRefNum = fileSystem.volume.reference
    block.pointee.header.ioResult = 0
    return 0
}

/// OSErr PBDTGetAPPLSync(DTPBPtr): an application looked up in the desktop
/// database isn't there.
@c(_PBDTGetAPPLSync)
public func PBDTGetAPPLSync(_ block: UnsafeMutablePointer<DTPB>?) -> Int16 {
    guard let block else { return MacError.parameter.osErr }
    block.pointee.header.ioResult = MacError.itemNotFound.osErr
    return MacError.itemNotFound.osErr
}

// MARK: - Launch Services

/// kLSApplicationNotFoundErr.
private let applicationNotFound: Int32 = -10814

/// OSStatus LSFindApplicationForInfo(OSType inCreator, CFStringRef
/// inBundleID, CFStringRef inName, FSRef *outAppRef, CFURLRef *outAppURL):
/// applications aren't found by creator: there is no Finder's database of
/// them here.
@c(_LSFindApplicationForInfo)
public func LSFindApplicationForInfo(_ creator: UInt32, _ bundle: UnsafeRawPointer?, _ name: UnsafeRawPointer?, _ ref: UnsafeMutableRawPointer?,
                                     _ url: UnsafeMutablePointer<UnsafeMutableRawPointer?>?) -> Int32 {
    url?.pointee = nil
    return applicationNotFound
}

/// OSStatus LSGetApplicationForURL(CFURLRef, LSRolesMask, FSRef *outAppRef,
/// CFURLRef *outAppURL).
@c(_LSGetApplicationForURL)
public func LSGetApplicationForURL(_ url: UnsafeRawPointer?, _ roles: UInt32, _ ref: UnsafeMutableRawPointer?,
                                   _ out: UnsafeMutablePointer<UnsafeMutableRawPointer?>?) -> Int32 {
    out?.pointee = nil
    return applicationNotFound
}

/// OSStatus LSCanURLAcceptURL(CFURLRef inItemURL, CFURLRef inTargetURL,
/// LSRolesMask, LSAcceptanceFlags, Boolean *outAcceptsItem).
@c(_LSCanURLAcceptURL)
public func LSCanURLAcceptURL(_ item: UnsafeRawPointer?, _ target: UnsafeRawPointer?, _ roles: UInt32, _ flags: UInt32,
                              _ accepts: UnsafeMutablePointer<UInt8>?) -> Int32 {
    accepts?.pointee = 0
    return 0
}

/// OSStatus LSOpenFSRef(const FSRef *, FSRef *outLaunchedRef): with the
/// desktop's opener, xdg-open.
@c(_LSOpenFSRef)
public func LSOpenFSRef(_ ref: UnsafeRawPointer?, _ launched: UnsafeMutableRawPointer?) -> Int32 {
    guard let path = CoreServicesFiles.path(of: ref) else { return Int32(MacError.parameter.code) }
    var child: pid_t = 0
    let arguments = ["xdg-open", path].map { strdup($0) } + [nil]
    defer { arguments.forEach { free($0) } }
    let spawned = posix_spawnp(&child, "xdg-open", nil, nil, arguments, environ)
    launched?.initializeMemory(as: UInt8.self, repeating: 0, count: MemoryLayout<FSRef>.size)
    return spawned == 0 ? 0 : -10810   // kLSUnknownErr
}
