#if canImport(Glibc)
import Glibc
#endif
import GraphiteBase
import GraphiteFiles
import GraphiteResources

// The Resource Manager over Graphite's: resource files' maps and bytes,
// the chain of open files from the current one back, and changes written
// back to their forks. A resource a program gets is a Memory Manager handle
// (CoreServices'), the same one each time it asks while the file is open, so
// ReleaseResource, DetachResource, ChangedResource and the rest act on it. A
// file's resources are its resource fork's, which Linux keeps beside it
// ("._name") or as "name.rsrc"; FSOpenResourceFile reads a data fork's, as
// .rsrc files in bundles keep them. Bytes are given as stored: resources
// are big-endian, as programs on Intel Macs read them too.

/// CoreServices' Memory Manager.
private enum Handles {

    private typealias New = @convention(c) (Int) -> UnsafeMutableRawPointer?
    private typealias Dispose = @convention(c) (UnsafeMutableRawPointer?) -> Void
    private typealias Size = @convention(c) (UnsafeMutableRawPointer?) -> Int
    private typealias SetSize = @convention(c) (UnsafeMutableRawPointer?, Int) -> Void

    private static func function<T>(_ name: String, as type: T.Type) -> T? {
        carbon_function(CORESERVICES, name).map { unsafeBitCast($0, to: T.self) }
    }

    nonisolated(unsafe) private static let newHandle = function("_NewHandle", as: New.self)
    nonisolated(unsafe) private static let disposeHandle = function("_DisposeHandle", as: Dispose.self)
    nonisolated(unsafe) private static let handleSize = function("_GetHandleSize", as: Size.self)
    nonisolated(unsafe) private static let setHandleSize = function("_SetHandleSize", as: SetSize.self)

    /// A new handle holding the bytes.
    static func make(_ bytes: [UInt8]) -> UnsafeMutableRawPointer? {
        guard let handle = newHandle?(bytes.count) else { return nil }
        if !bytes.isEmpty, let storage = handle.load(as: UnsafeMutableRawPointer?.self) {
            bytes.withUnsafeBytes { storage.copyMemory(from: $0.baseAddress!, byteCount: $0.count) }
        }
        return handle
    }

    /// Sets a handle's bytes: false if it can't grow to hold them.
    static func set(_ handle: UnsafeMutableRawPointer, to bytes: [UInt8]) -> Bool {
        setHandleSize?(handle, bytes.count)
        guard size(handle) == bytes.count else { return false }
        if !bytes.isEmpty, let storage = handle.load(as: UnsafeMutableRawPointer?.self) {
            bytes.withUnsafeBytes { storage.copyMemory(from: $0.baseAddress!, byteCount: $0.count) }
        }
        return true
    }

    static func bytes(_ handle: UnsafeMutableRawPointer) -> [UInt8] {
        let count = size(handle)
        guard count > 0, let storage = handle.load(as: UnsafeMutableRawPointer?.self) else { return [] }
        return Array(UnsafeRawBufferPointer(start: storage, count: count))
    }

    static func size(_ handle: UnsafeMutableRawPointer) -> Int { handleSize?(handle) ?? 0 }

    static func dispose(_ handle: UnsafeMutableRawPointer) { disposeHandle?(handle) }
}

/// The Resource Manager's state: the chain, ResError, and the handles given.
private struct ResourceState {

    struct Key: Hashable {
        var file: Int16
        var type: FourCharCode
        var id: Int16
    }

    /// A handle given for a resource.
    struct Given {
        var key: Key
        /// Read into the handle: not when SetResLoad(false) was in effect.
        var loaded: Bool
        /// ChangedResource: written to the file by WriteResource,
        /// UpdateResFile or CloseResFile.
        var changed = false
    }

    let chain = ResourceChain(fileSystem: fileSystem)
    var error: Int16 = 0
    var given: [UInt: Given] = [:]
    var handles: [Key: UInt] = [:]

    /// The handle for a resource found, the one given before if there is one.
    mutating func handle(for found: ResourceChain.Found) -> UnsafeMutableRawPointer? {
        let key = Key(file: found.reference, type: found.resource.type, id: found.resource.id)
        if let handle = handles[key] {
            error = 0
            return UnsafeMutableRawPointer(bitPattern: handle)
        }
        guard let handle = Handles.make(found.bytes ?? []) else {
            error = MacError.memoryFull.osErr
            return nil
        }
        let address = UInt(bitPattern: handle)
        given[address] = Given(key: key, loaded: found.bytes != nil)
        handles[key] = address
        error = 0
        return handle
    }

    mutating func forget(_ address: UInt) {
        guard let record = given.removeValue(forKey: address) else { return }
        handles[record.key] = nil
    }

    /// Writes a file's changed resources' handles into it.
    mutating func writeChanges(of reference: Int16) throws(MacError) {
        guard let file = chain.file(reference) else { throw .resourceFileNotFound }
        for (address, record) in given where record.key.file == reference && record.changed {
            guard let handle = UnsafeMutableRawPointer(bitPattern: address) else { continue }
            try file.setBytes(Handles.bytes(handle), type: record.key.type, id: record.key.id)
            given[address]?.changed = false
        }
    }
}

/// The Resource Manager's state behind a recursive lock: a program's
/// resource calls come from any thread, and one may call another.
private final class ResourceManager: @unchecked Sendable {

    private let mutex = UnsafeMutablePointer<pthread_mutex_t>.allocate(capacity: 1)
    private var state = ResourceState()

    init() {
        var attributes = pthread_mutexattr_t()
        pthread_mutexattr_init(&attributes)
        pthread_mutexattr_settype(&attributes, Int32(PTHREAD_MUTEX_RECURSIVE))
        pthread_mutex_init(mutex, &attributes)
        pthread_mutexattr_destroy(&attributes)
    }

    func withLock<T, E: Error>(_ body: (inout ResourceState) throws(E) -> T) throws(E) -> T {
        pthread_mutex_lock(mutex)
        defer { pthread_mutex_unlock(mutex) }
        return try body(&state)
    }
}

private let resourceState = ResourceManager()

/// Runs a Resource Manager call, ResError its result.
private func resources<T>(_ body: (inout ResourceState) throws(MacError) -> T, failing: T) -> T {
    resourceState.withLock { (state: inout ResourceState) -> T in
        do throws(MacError) {
            let result = try body(&state)
            state.error = 0
            return result
        } catch {
            state.error = error.osErr
            return failing
        }
    }
}

/// The record of a handle the Resource Manager gave: resNotFound for
/// another.
private func record(_ handle: UnsafeMutableRawPointer?, in state: ResourceState) throws(MacError) -> ResourceState.Given {
    guard let handle, let record = state.given[UInt(bitPattern: handle)] else { throw .resourceNotFound }
    return record
}

private func file(of record: ResourceState.Given, in state: ResourceState) throws(MacError) -> ResourceFile {
    guard let file = state.chain.file(record.key.file) else { throw .resourceFileNotFound }
    return file
}

// MARK: - Resource files

/// short FSOpenResFile(const FSRef *, SInt8 permission): -1, with ResError,
/// if it has no resources.
@c(_FSOpenResFile)
public func FSOpenResFile(_ ref: UnsafeRawPointer?, _ permission: Int8) -> Int16 {
    resources({ (state: inout ResourceState) throws(MacError) -> Int16 in
        guard let path = CoreServicesFiles.path(of: ref) else { throw .parameter }
        return try state.chain.open(path, fork: .resource, permission: ForkPermission(permission))
    }, failing: -1)
}

/// OSErr FSOpenResourceFile(const FSRef *, UniCharCount forkNameLength,
/// const UniChar *forkName, SInt8 permissions, ResFileRefNum *): a data
/// fork's resources for an empty fork name.
@c(_FSOpenResourceFile)
public func FSOpenResourceFile(_ ref: UnsafeRawPointer?, _ nameLength: Int, _ forkName: UnsafePointer<UInt16>?, _ permission: Int8,
                               _ reference: UnsafeMutablePointer<Int16>?) -> Int16 {
    guard let reference else { return MacError.parameter.osErr }
    reference.pointee = resources({ (state: inout ResourceState) throws(MacError) -> Int16 in
        guard let path = CoreServicesFiles.path(of: ref) else { throw .parameter }
        return try state.chain.open(path, fork: nameLength == 0 ? .data : .resource, permission: ForkPermission(permission))
    }, failing: -1)
    return ResError()
}

/// short FSpOpenResFile(const FSSpec *, SignedByte permission).
@c(_FSpOpenResFile)
public func FSpOpenResFile(_ spec: UnsafePointer<FSSpec>?, _ permission: Int8) -> Int16 {
    resources({ (state: inout ResourceState) throws(MacError) -> Int16 in
        guard let path = path(of: spec) else { throw .parameter }
        guard let found = fileSystem.lookUp(path) else { throw .fileNotFound }
        return try state.chain.open(found, fork: .resource, permission: ForkPermission(permission))
    }, failing: -1)
}

/// void FSCreateResFile(const FSRef *parentRef, UniCharCount nameLength,
/// const UniChar *name, FSCatalogInfoBitmap whichInfo, const FSCatalogInfo
/// *, FSRef *newRef, FSSpec *newSpec): a file with an empty resource fork;
/// dupFNErr if it has resources already.
@c(_FSCreateResFile)
public func FSCreateResFile(_ parent: UnsafeRawPointer?, _ length: Int, _ name: UnsafePointer<UInt16>?, _ which: UInt32,
                            _ info: UnsafeRawPointer?, _ ref: UnsafeMutableRawPointer?, _ spec: UnsafeMutablePointer<FSSpec>?) {
    resources({ (state: inout ResourceState) throws(MacError) in
        guard let folder = CoreServicesFiles.path(of: parent), let name, length > 0, length <= 255 else { throw .parameter }
        let leaf = FileNames.posix(String(decoding: UnsafeBufferPointer(start: name, count: length), as: UTF16.self))
        let path = folder == "/" ? "/" + leaf : folder + "/" + leaf
        let created = FSCreateFileUnicode(parent, length, name, which, info, nil, nil)
        guard created == 0 || created == MacError.duplicateFileName.osErr else { throw MacError(Int32(created)) }
        try state.chain.create(path)
        CoreServicesFiles.store(path, in: ref)
        store(fileSystem.spec(forPath: path), in: spec)
    }, failing: ())
}

/// void FSpCreateResFile(const FSSpec *, OSType creator, OSType fileType,
/// ScriptCode).
@c(_FSpCreateResFile)
public func FSpCreateResFile(_ spec: UnsafePointer<FSSpec>?, _ creator: UInt32, _ type: UInt32, _ script: Int16) {
    resources({ (state: inout ResourceState) throws(MacError) in
        guard let path = path(of: spec) else { throw .parameter }
        try state.chain.create(path, finderInfo: FinderInfo(type: FourCharCode(type), creator: FourCharCode(creator)))
    }, failing: ())
}

/// void CloseResFile(ResFileRefNum): its changes written, its resources'
/// handles disposed of.
@c(_CloseResFile)
public func CloseResFile(_ reference: Int16) {
    resources({ (state: inout ResourceState) throws(MacError) in
        try state.writeChanges(of: reference)
        for (address, record) in state.given where record.key.file == reference {
            state.forget(address)
            if let handle = UnsafeMutableRawPointer(bitPattern: address) { Handles.dispose(handle) }
        }
        try state.chain.close(reference)
    }, failing: ())
}

/// OSErr UpdateResFile(ResFileRefNum).
@c(_UpdateResFile)
public func UpdateResFile(_ reference: Int16) {
    resources({ (state: inout ResourceState) throws(MacError) in
        try state.writeChanges(of: reference)
        try state.chain.update(reference)
    }, failing: ())
}

/// ResFileRefNum CurResFile(void).
@c(_CurResFile)
public func CurResFile() -> Int16 {
    resourceState.withLock { $0.chain.current }
}

/// void UseResFile(ResFileRefNum).
@c(_UseResFile)
public func UseResFile(_ reference: Int16) {
    resources({ (state: inout ResourceState) throws(MacError) in try state.chain.use(reference) }, failing: ())
}

/// OSErr ResError(void).
@c(_ResError)
public func ResError() -> Int16 {
    resourceState.withLock { $0.error }
}

/// void SetResLoad(Boolean): whether Get calls read resources' bytes, or
/// give empty handles that LoadResource fills.
@c(_SetResLoad)
public func SetResLoad(_ load: UInt8) {
    resourceState.withLock { $0.chain.loadsResources = load != 0 }
}

// MARK: - Getting resources

private func get(_ find: (ResourceChain) throws(MacError) -> ResourceChain.Found) -> UnsafeMutableRawPointer? {
    resources({ (state: inout ResourceState) throws(MacError) -> UnsafeMutableRawPointer? in
        let handle = state.handle(for: try find(state.chain))
        if handle == nil { throw .memoryFull }
        return handle
    }, failing: nil)
}

/// Handle GetResource(ResType, ResID): from the current file back.
@c(_GetResource)
public func GetResource(_ type: UInt32, _ id: Int16) -> UnsafeMutableRawPointer? {
    get { (chain) throws(MacError) in try chain.get(type: FourCharCode(type), id: id) }
}

/// Handle Get1Resource(ResType, ResID): from the current file alone.
@c(_Get1Resource)
public func Get1Resource(_ type: UInt32, _ id: Int16) -> UnsafeMutableRawPointer? {
    get { (chain) throws(MacError) in try chain.get(type: FourCharCode(type), id: id, oneFile: true) }
}

/// Handle GetNamedResource(ResType, ConstStr255Param).
@c(_GetNamedResource)
public func GetNamedResource(_ type: UInt32, _ name: UnsafePointer<UInt8>?) -> UnsafeMutableRawPointer? {
    guard let name else { return nil }
    let string = pascalString(at: UnsafeRawPointer(name))
    return get { (chain) throws(MacError) in try chain.get(type: FourCharCode(type), named: string) }
}

/// Handle Get1NamedResource(ResType, ConstStr255Param).
@c(_Get1NamedResource)
public func Get1NamedResource(_ type: UInt32, _ name: UnsafePointer<UInt8>?) -> UnsafeMutableRawPointer? {
    guard let name else { return nil }
    let string = pascalString(at: UnsafeRawPointer(name))
    return get { (chain) throws(MacError) in try chain.get(type: FourCharCode(type), named: string, oneFile: true) }
}

/// Handle GetIndResource(ResType, ResourceIndex): the index-th (from 1) of a
/// type, through the files from the current one back.
@c(_GetIndResource)
public func GetIndResource(_ type: UInt32, _ index: Int16) -> UnsafeMutableRawPointer? {
    get { (chain) throws(MacError) in try chain.get(type: FourCharCode(type), index: Int(index)) }
}

/// Handle Get1IndResource(ResType, ResourceIndex).
@c(_Get1IndResource)
public func Get1IndResource(_ type: UInt32, _ index: Int16) -> UnsafeMutableRawPointer? {
    get { (chain) throws(MacError) in try chain.get(type: FourCharCode(type), index: Int(index), oneFile: true) }
}

/// ResourceCount CountResources(ResType).
@c(_CountResources)
public func CountResources(_ type: UInt32) -> Int16 {
    resourceState.withLock { Int16(clamping: $0.chain.count(type: FourCharCode(type))) }
}

/// ResourceCount Count1Resources(ResType).
@c(_Count1Resources)
public func Count1Resources(_ type: UInt32) -> Int16 {
    resourceState.withLock { Int16(clamping: $0.chain.count(type: FourCharCode(type), oneFile: true)) }
}

/// ResourceCount CountTypes(void).
@c(_CountTypes)
public func CountTypes() -> Int16 {
    resourceState.withLock { Int16(clamping: $0.chain.types().count) }
}

/// ResourceCount Count1Types(void).
@c(_Count1Types)
public func Count1Types() -> Int16 {
    resourceState.withLock { Int16(clamping: $0.chain.types(oneFile: true).count) }
}

private func indexedType(_ type: UnsafeMutablePointer<UInt32>?, _ index: Int16, oneFile: Bool) {
    resources({ (state: inout ResourceState) throws(MacError) in
        let types = state.chain.types(oneFile: oneFile)
        guard index >= 1, Int(index) <= types.count else {
            type?.pointee = 0
            throw .resourceNotFound
        }
        type?.pointee = types[Int(index) - 1].rawValue
    }, failing: ())
}

/// void GetIndType(ResType *, ResourceIndex).
@c(_GetIndType)
public func GetIndType(_ type: UnsafeMutablePointer<UInt32>?, _ index: Int16) {
    indexedType(type, index, oneFile: false)
}

/// void Get1IndType(ResType *, ResourceIndex).
@c(_Get1IndType)
public func Get1IndType(_ type: UnsafeMutablePointer<UInt32>?, _ index: Int16) {
    indexedType(type, index, oneFile: true)
}

/// ResID UniqueID(ResType).
@c(_UniqueID)
public func UniqueID(_ type: UInt32) -> Int16 {
    resourceState.withLock { $0.chain.uniqueID(type: FourCharCode(type)) }
}

/// ResID Unique1ID(ResType).
@c(_Unique1ID)
public func Unique1ID(_ type: UInt32) -> Int16 {
    resourceState.withLock { $0.chain.uniqueID(type: FourCharCode(type), oneFile: true) }
}

/// The international resources ('itl0' to 'itl4') aren't the system's
/// here: programs use their own defaults when there are none.
@c(_GetIntlResource)
public func GetIntlResource(_ id: Int16) -> UnsafeMutableRawPointer? {
    resourceState.withLock { $0.error = MacError.resourceNotFound.osErr }
    return nil
}

// MARK: - Resources' handles

/// void LoadResource(Handle): an unloaded resource's bytes read into it.
@c(_LoadResource)
public func LoadResource(_ handle: UnsafeMutableRawPointer?) {
    resources({ (state: inout ResourceState) throws(MacError) in
        guard let handle else { throw .nilHandle }
        let given = try record(handle, in: state)
        guard !given.loaded else { return }
        let bytes = try file(of: given, in: state).bytes(type: given.key.type, id: given.key.id)
        guard Handles.set(handle, to: bytes) else { throw .memoryFull }
        state.given[UInt(bitPattern: handle)]?.loaded = true
    }, failing: ())
}

/// void ReleaseResource(Handle): the handle is disposed of; getting the
/// resource again makes another.
@c(_ReleaseResource)
public func ReleaseResource(_ handle: UnsafeMutableRawPointer?) {
    resources({ (state: inout ResourceState) throws(MacError) in
        _ = try record(handle, in: state)
        guard let handle else { return }
        state.forget(UInt(bitPattern: handle))
        Handles.dispose(handle)
    }, failing: ())
}

/// void DetachResource(Handle): the handle is the program's from now on.
@c(_DetachResource)
public func DetachResource(_ handle: UnsafeMutableRawPointer?) {
    resources({ (state: inout ResourceState) throws(MacError) in
        _ = try record(handle, in: state)
        if let handle { state.forget(UInt(bitPattern: handle)) }
    }, failing: ())
}

/// ResFileRefNum HomeResFile(Handle): -1 for a handle that isn't a
/// resource's.
@c(_HomeResFile)
public func HomeResFile(_ handle: UnsafeMutableRawPointer?) -> Int16 {
    resources({ (state: inout ResourceState) throws(MacError) -> Int16 in try record(handle, in: state).key.file }, failing: -1)
}

/// void GetResInfo(Handle, ResID *, ResType *, Str255 name).
@c(_GetResInfo)
public func GetResInfo(_ handle: UnsafeMutableRawPointer?, _ id: UnsafeMutablePointer<Int16>?, _ type: UnsafeMutablePointer<UInt32>?,
                       _ name: UnsafeMutablePointer<UInt8>?) {
    resources({ (state: inout ResourceState) throws(MacError) in
        let given = try record(handle, in: state)
        id?.pointee = given.key.id
        type?.pointee = given.key.type.rawValue
        if let name {
            let resource = try file(of: given, in: state).resource(type: given.key.type, id: given.key.id)
            store(resource?.name ?? PascalString(), at: UnsafeMutableRawPointer(name))
        }
    }, failing: ())
}

/// void SetResInfo(Handle, ResID, ConstStr255Param name): a new ID, and a
/// new name unless it is NULL.
@c(_SetResInfo)
public func SetResInfo(_ handle: UnsafeMutableRawPointer?, _ id: Int16, _ name: UnsafePointer<UInt8>?) {
    resources({ (state: inout ResourceState) throws(MacError) in
        let given = try record(handle, in: state)
        let newName: PascalString?? = name.map { .some(pascalString(at: UnsafeRawPointer($0))) }
        try file(of: given, in: state).setInfo(type: given.key.type, id: given.key.id, newID: id, name: newName)
        guard let handle else { return }
        let address = UInt(bitPattern: handle)
        state.forget(address)
        var moved = given
        moved.key.id = id
        state.given[address] = moved
        state.handles[moved.key] = address
    }, failing: ())
}

/// ResAttributes GetResAttrs(Handle).
@c(_GetResAttrs)
public func GetResAttrs(_ handle: UnsafeMutableRawPointer?) -> Int16 {
    resources({ (state: inout ResourceState) throws(MacError) -> Int16 in
        let given = try record(handle, in: state)
        let resource = try file(of: given, in: state).resource(type: given.key.type, id: given.key.id)
        var attributes = resource?.attributes ?? []
        if given.changed { attributes.insert(.changed) }
        return Int16(attributes.rawValue)
    }, failing: 0)
}

/// void SetResAttrs(Handle, ResAttributes).
@c(_SetResAttrs)
public func SetResAttrs(_ handle: UnsafeMutableRawPointer?, _ attributes: Int16) {
    resources({ (state: inout ResourceState) throws(MacError) in
        let given = try record(handle, in: state)
        try file(of: given, in: state).setAttributes(
            ResourceAttributes(rawValue: UInt8(truncatingIfNeeded: attributes)), type: given.key.type, id: given.key.id
        )
    }, failing: ())
}

/// long GetResourceSizeOnDisk(Handle).
@c(_GetResourceSizeOnDisk)
public func GetResourceSizeOnDisk(_ handle: UnsafeMutableRawPointer?) -> Int {
    resources({ (state: inout ResourceState) throws(MacError) -> Int in
        let given = try record(handle, in: state)
        return try file(of: given, in: state).size(type: given.key.type, id: given.key.id)
    }, failing: -1)
}

/// long GetMaxResourceSize(Handle): its handle's size if it is loaded.
@c(_GetMaxResourceSize)
public func GetMaxResourceSize(_ handle: UnsafeMutableRawPointer?) -> Int {
    resources({ (state: inout ResourceState) throws(MacError) -> Int in
        let given = try record(handle, in: state)
        if given.loaded, let handle { return Handles.size(handle) }
        return try file(of: given, in: state).size(type: given.key.type, id: given.key.id)
    }, failing: -1)
}

// MARK: - Changing resources

/// void AddResource(Handle, ResType, ResID, ConstStr255Param name): the
/// handle's bytes, a resource of the current file, written when it is
/// updated. addResFailed if it has one of the type and ID.
@c(_AddResource)
public func AddResource(_ handle: UnsafeMutableRawPointer?, _ type: UInt32, _ id: Int16, _ name: UnsafePointer<UInt8>?) {
    resources({ (state: inout ResourceState) throws(MacError) in
        guard let handle else { throw .addResourceFailed }
        guard state.given[UInt(bitPattern: handle)] == nil else { throw .addResourceFailed }
        let reference = state.chain.current
        guard let file = state.chain.file(reference) else { throw .resourceFileNotFound }
        let resourceName = name.map { pascalString(at: UnsafeRawPointer($0)) }
        try file.add(Resource(type: FourCharCode(type), id: id, name: resourceName), bytes: Handles.bytes(handle))
        let key = ResourceState.Key(file: reference, type: FourCharCode(type), id: id)
        state.given[UInt(bitPattern: handle)] = ResourceState.Given(key: key, loaded: true)
        state.handles[key] = UInt(bitPattern: handle)
    }, failing: ())
}

/// void ChangedResource(Handle): its handle's bytes are written when the
/// file is updated. resAttrErr for a protected resource.
@c(_ChangedResource)
public func ChangedResource(_ handle: UnsafeMutableRawPointer?) {
    resources({ (state: inout ResourceState) throws(MacError) in
        let given = try record(handle, in: state)
        let resource = try file(of: given, in: state).resource(type: given.key.type, id: given.key.id)
        guard resource?.attributes.contains(.protected) != true else { throw .resourceAttribute }
        if let handle { state.given[UInt(bitPattern: handle)]?.changed = true }
    }, failing: ())
}

/// void WriteResource(Handle): a changed resource's bytes written to its
/// file now.
@c(_WriteResource)
public func WriteResource(_ handle: UnsafeMutableRawPointer?) {
    resources({ (state: inout ResourceState) throws(MacError) in
        let given = try record(handle, in: state)
        guard given.changed, let handle else { return }
        let file = try file(of: given, in: state)
        try file.setBytes(Handles.bytes(handle), type: given.key.type, id: given.key.id)
        state.given[UInt(bitPattern: handle)]?.changed = false
        try file.update()
    }, failing: ())
}

/// void RemoveResource(Handle): taken out of its file, which is written
/// when it is updated; the handle is the program's. rmvResFailed for a
/// protected resource.
@c(_RemoveResource)
public func RemoveResource(_ handle: UnsafeMutableRawPointer?) {
    resources({ (state: inout ResourceState) throws(MacError) in
        let given = try record(handle, in: state)
        try file(of: given, in: state).remove(type: given.key.type, id: given.key.id)
        if let handle { state.forget(UInt(bitPattern: handle)) }
    }, failing: ())
}

// MARK: - Strings

/// void GetIndString(Str255 theString, short strListID, short index): the
/// index-th (from 1) string of a 'STR#' resource; empty if there is none.
@c(_GetIndString)
public func GetIndString(_ string: UnsafeMutablePointer<UInt8>?, _ listID: Int16, _ index: Int16) {
    guard let string else { return }
    string.pointee = 0
    let list = resources({ (state: inout ResourceState) throws(MacError) -> StringList? in
        let found = try state.chain.get(type: StringList.resourceType, id: listID)
        var bytes = found.bytes ?? []
        if found.bytes == nil, let file = state.chain.file(found.reference) {
            bytes = try file.bytes(type: StringList.resourceType, id: listID)
        }
        return try StringList(bytes: bytes)
    }, failing: nil)
    if let list { store(list[Int(index)], at: UnsafeMutableRawPointer(string)) }
}

/// StringHandle GetString(short stringID): a 'STR ' resource's handle.
@c(_GetString)
public func GetString(_ id: Int16) -> UnsafeMutableRawPointer? {
    GetResource(StringResource.resourceType.rawValue, id)
}
