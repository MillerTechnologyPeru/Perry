import CPerryFoundation
import FoundationEssentials
import Glibc
import PerryObjCInterop

// CFFileDescriptor: a file descriptor whose readiness to read or write is
// told to the program on a run loop. One thread polls every descriptor with
// a callback enabled; a ready one has that callback disabled, as on Darwin,
// where each is called once until enabled again, and its run loop source
// signalled, which calls the program's callout on the loop.

/// A context of { version, info, retain, release, copyDescription }:
/// CFFileDescriptorContext's and CFMachPortContext's.
struct InfoContext {
    typealias Retain = @convention(c) (UnsafeRawPointer?) -> UnsafeRawPointer?
    typealias Release = @convention(c) (UnsafeRawPointer?) -> Void

    var info: UnsafeMutableRawPointer?
    var retain: Retain?
    var release: Release?
    var copyDescription: UnsafeRawPointer?

    init() {}

    /// The program's context, its info retained.
    init(retaining pointer: UnsafeRawPointer?) {
        guard let pointer else { return }
        info = pointer.load(fromByteOffset: DarwinLayout.contextInfo, as: UnsafeMutableRawPointer?.self)
        retain = pointer.load(fromByteOffset: DarwinLayout.contextRetain, as: Retain?.self)
        release = pointer.load(fromByteOffset: DarwinLayout.contextRelease, as: Release?.self)
        copyDescription = pointer.load(fromByteOffset: 4 * DarwinLayout.word, as: UnsafeRawPointer?.self)
        if let info, let retain { self.info = retain(info).map { UnsafeMutableRawPointer(mutating: $0) } }
    }

    func released() {
        if let info, let release { release(info) }
    }

    func store(to pointer: UnsafeMutableRawPointer?) {
        guard let pointer else { return }
        pointer.storeBytes(of: 0, as: Int.self)
        pointer.storeBytes(of: info, toByteOffset: DarwinLayout.contextInfo, as: UnsafeMutableRawPointer?.self)
        pointer.storeBytes(of: retain, toByteOffset: DarwinLayout.contextRetain, as: Retain?.self)
        pointer.storeBytes(of: release, toByteOffset: DarwinLayout.contextRelease, as: Release?.self)
        pointer.storeBytes(of: copyDescription, toByteOffset: 4 * DarwinLayout.word, as: UnsafeRawPointer?.self)
    }
}

/// A run loop source whose perform calls `fire` on the loop: a version 0
/// source, its info the object it fires for, retained.
protocol FiringSource: AnyObject {
    func fire()
}

enum FiringSources {
    static let perform: CustomSourceStorage.Perform = { info in
        guard let info else { return }
        (Unmanaged<AnyObject>.fromOpaque(info).takeUnretainedValue() as? FiringSource)?.fire()
    }

    static let release: CustomSourceStorage.Release = { info in
        guard let info else { return }
        Unmanaged<AnyObject>.fromOpaque(info).release()
    }

    /// A new source (+1) and its storage.
    static func make(for target: FiringSource) -> (id, CustomSourceStorage)? {
        guard let object = Storage.allocate(UnsafeMutableRawPointer(Sockets.sourceClass)) else { return nil }
        let info = Unmanaged.passRetained(target as AnyObject).toOpaque()
        let storage = CustomSourceStorage(info: info, perform: perform, release: release)
        Storage.set(object, storage)
        return (object, storage)
    }
}

/// CFFileDescriptorCallBack: (descriptor, callback types, info).
public typealias CFFileDescriptorCallout = @convention(c) (UnsafeMutableRawPointer?, UInt, UnsafeMutableRawPointer?) -> Void

final class FileDescriptorStorage: FiringSource {
    typealias Callout = CFFileDescriptorCallout

    let descriptor: Int32
    let closeOnInvalidate: Bool
    let callout: Callout?
    let context: InfoContext
    /// The CFFileDescriptor, not retained: it owns this.
    var object: id?
    /// Guarded by FileDescriptors' lock.
    var enabled: UInt = 0
    var pending: UInt = 0
    var valid = true
    var source: (object: id, storage: CustomSourceStorage)?

    init(descriptor: Int32, closeOnInvalidate: Bool, callout: Callout?, context: InfoContext) {
        (self.descriptor, self.closeOnInvalidate, self.callout, self.context) = (descriptor, closeOnInvalidate, callout, context)
    }

    /// The callbacks that became ready since the last, on the loop.
    func fire() {
        let types = FileDescriptors.locked { () -> UInt in
            defer { pending = 0 }
            return valid ? pending : 0
        }
        guard types != 0, let object else { return }
        callout?(object, types, context.info)
    }
}

enum FileDescriptors {
    nonisolated(unsafe) static var descriptorClass: Class!

    static let read: UInt = 1, write: UInt = 2

    nonisolated(unsafe) private static let mutex: UnsafeMutablePointer<pthread_mutex_t> = {
        let mutex = UnsafeMutablePointer<pthread_mutex_t>.allocate(capacity: 1)
        pthread_mutex_init(mutex, nil)
        return mutex
    }()
    /// The valid descriptors, polled while they have callbacks enabled.
    nonisolated(unsafe) private static var watched: [FileDescriptorStorage] = []
    nonisolated(unsafe) private static var watching = false
    /// Written to when what the polling thread waits for has changed.
    private static let wake = eventfd(0, Int32(EFD_CLOEXEC | EFD_NONBLOCK))

    static func storage(_ descriptor: id?) -> FileDescriptorStorage? { Storage.get(descriptor, as: FileDescriptorStorage.self) }

    static func locked<T>(_ body: () -> T) -> T {
        pthread_mutex_lock(mutex)
        defer { pthread_mutex_unlock(mutex) }
        return body()
    }

    static func changed() { _ = eventfd_write(wake, 1) }

    static func watch(_ storage: FileDescriptorStorage) {
        locked {
            if !watched.contains(where: { $0 === storage }) { watched.append(storage) }
            guard !watching else { return }
            watching = true
            var thread = pthread_t()
            pthread_create(&thread, nil, { _ in FileDescriptors.poll(); return nil }, nil)
            pthread_detach(thread)
        }
        changed()
    }

    static func unwatch(_ storage: FileDescriptorStorage) {
        locked { watched.removeAll { $0 === storage } }
        changed()
    }

    /// Polls what's enabled until there's nothing left to.
    private static func poll() {
        while true {
            let polled = locked { watched.filter { $0.valid && $0.enabled != 0 } }
            var files = polled.map { storage in
                pollfd(fd: storage.descriptor, events: Int16((storage.enabled & read != 0 ? POLLIN : 0) | (storage.enabled & write != 0 ? POLLOUT : 0)),
                       revents: 0)
            }
            files.append(pollfd(fd: wake, events: Int16(POLLIN), revents: 0))
            guard Glibc.poll(&files, nfds_t(files.count), -1) >= 0 || errno == EINTR else { return }
            if files.last!.revents != 0 {
                var count: eventfd_t = 0
                _ = eventfd_read(wake, &count)
            }
            for (storage, file) in zip(polled, files) where file.revents != 0 {
                var ready: UInt = 0
                if file.revents & Int16(POLLIN | POLLHUP | POLLERR) != 0 { ready |= read }
                if file.revents & Int16(POLLOUT | POLLHUP | POLLERR) != 0 { ready |= write }
                let source = locked { () -> CustomSourceStorage? in
                    let fired = storage.enabled & ready
                    guard storage.valid, fired != 0 else { return nil }
                    storage.enabled &= ~fired
                    storage.pending |= fired
                    return storage.source?.storage
                }
                source?.signal()
            }
        }
    }

    /// Once: no more callouts, the source invalid, the descriptor closed if
    /// it was to be, and the info released.
    static func invalidate(_ storage: FileDescriptorStorage) {
        let source = locked { () -> (object: id, storage: CustomSourceStorage)?? in
            guard storage.valid else { return nil }
            storage.valid = false
            storage.enabled = 0
            defer { storage.source = nil }
            return .some(storage.source)
        }
        guard let source else { return }
        unwatch(storage)
        if let source {
            source.storage.remove(from: nil)
            ObjC.release(source.object)
        }
        storage.object = nil
        if storage.closeOnInvalidate { close(storage.descriptor) }
        storage.context.released()
    }
}

@ObjCClass("__NSCFFileDescriptor")
final class NSCFFileDescriptor: NSObject {
    override class func didDefineObjCClass(_ cls: ObjCClass) {
        NSObject.registerObjCCategoryStorageAllocated(cls)
        FileDescriptors.descriptorClass = cls.storage
    }

    @ObjCMethod("dealloc")
    func dealloc() {
        FileDescriptors.storage(objcObject).map(FileDescriptors.invalidate)
        Storage.set(objcObject, nil)
        ObjC.superDealloc(objcObject, from: FileDescriptors.descriptorClass)
    }

    @ObjCMethod("_cfTypeID") func cfTypeID() -> UInt { 60 }
}

@c(_CFFileDescriptorGetTypeID) public func CFFileDescriptorGetTypeID() -> UInt { 60 }

@c(_CFFileDescriptorCreate)
public func CFFileDescriptorCreate(_ allocator: UnsafeRawPointer?, _ descriptor: Int32, _ closeOnInvalidate: Bool,
                                   _ callout: CFFileDescriptorCallout?, _ context: UnsafeRawPointer?) -> id? {
    guard descriptor >= 0, let object = Storage.allocate(UnsafeMutableRawPointer(FileDescriptors.descriptorClass)) else { return nil }
    let storage = FileDescriptorStorage(descriptor: descriptor, closeOnInvalidate: closeOnInvalidate, callout: callout,
                                        context: InfoContext(retaining: context))
    storage.object = object
    Storage.set(object, storage)
    return object
}

/// -1 once invalid.
@c(_CFFileDescriptorGetNativeDescriptor)
public func CFFileDescriptorGetNativeDescriptor(_ descriptor: id?) -> Int32 {
    guard let storage = FileDescriptors.storage(descriptor), FileDescriptors.locked({ storage.valid }) else { return -1 }
    return storage.descriptor
}

@c(_CFFileDescriptorGetContext)
public func CFFileDescriptorGetContext(_ descriptor: id?, _ context: UnsafeMutableRawPointer?) {
    FileDescriptors.storage(descriptor)?.context.store(to: context)
}

/// kCFFileDescriptorReadCallBack (1) and kCFFileDescriptorWriteCallBack
/// (2), each called once when ready.
@c(_CFFileDescriptorEnableCallBacks)
public func CFFileDescriptorEnableCallBacks(_ descriptor: id?, _ types: UInt) {
    guard let storage = FileDescriptors.storage(descriptor) else { return }
    let enabled = FileDescriptors.locked { () -> Bool in
        guard storage.valid else { return false }
        storage.enabled |= types & (FileDescriptors.read | FileDescriptors.write)
        return true
    }
    if enabled { FileDescriptors.watch(storage) }
}

@c(_CFFileDescriptorDisableCallBacks)
public func CFFileDescriptorDisableCallBacks(_ descriptor: id?, _ types: UInt) {
    guard let storage = FileDescriptors.storage(descriptor) else { return }
    FileDescriptors.locked { storage.enabled &= ~types }
    FileDescriptors.changed()
}

@c(_CFFileDescriptorInvalidate)
public func CFFileDescriptorInvalidate(_ descriptor: id?) {
    FileDescriptors.storage(descriptor).map(FileDescriptors.invalidate)
}

@c(_CFFileDescriptorIsValid)
public func CFFileDescriptorIsValid(_ descriptor: id?) -> Bool {
    guard let storage = FileDescriptors.storage(descriptor) else { return false }
    return FileDescriptors.locked { storage.valid }
}

/// The descriptor's one source (+1), made the first time.
@c(_CFFileDescriptorCreateRunLoopSource)
public func CFFileDescriptorCreateRunLoopSource(_ allocator: UnsafeRawPointer?, _ descriptor: id?, _ order: Int) -> id? {
    guard let storage = FileDescriptors.storage(descriptor) else { return nil }
    let existing = FileDescriptors.locked { () -> id?? in
        guard storage.valid else { return .some(nil) }
        return storage.source.map { .some($0.object) }
    }
    if let existing { return existing.flatMap { ObjC.retain($0) } }
    guard let made = FiringSources.make(for: storage) else { return nil }
    let source = FileDescriptors.locked { () -> id in
        if let current = storage.source { return current.object }
        storage.source = made
        return made.0
    }
    if source != made.0 { ObjC.release(made.0) }
    // A callback that fired before the source was made is told now.
    if FileDescriptors.locked({ storage.pending != 0 }) { storage.source?.storage.signal() }
    return ObjC.retain(source)
}
