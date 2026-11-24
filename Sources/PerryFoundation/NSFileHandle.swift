import FoundationEssentials
import Glibc
import PerryObjCInterop

// NSFileHandle, over a file descriptor; and NSPort and NSMachPort, which
// keep a run loop running when added to it and carry messages between the
// ports of this process.

final class FileHandleStorage {
    let descriptor: Int32
    let closeOnDealloc: Bool
    var closed = false

    init(_ descriptor: Int32, closeOnDealloc: Bool) {
        self.descriptor = descriptor
        self.closeOnDealloc = closeOnDealloc
    }

    deinit { if closeOnDealloc && !closed { close(descriptor) } }

    func read(upTo length: Int) -> Data {
        var failure: Int32 = 0
        return read(upTo: length, failure: &failure)
    }

    /// Reads until `length` bytes or the end; `failure` is the errno of a
    /// read that failed.
    func read(upTo length: Int, failure: inout Int32) -> Data {
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 65_536)
        while data.count < length {
            let count = Glibc.read(descriptor, &buffer, min(buffer.count, length - data.count))
            if count < 0 && errno == EINTR { continue }
            if count < 0 { failure = errno }
            guard count > 0 else { break }
            data.append(contentsOf: buffer[0..<count])
        }
        return data
    }

    func write(_ data: Data) {
        data.withUnsafeBytes { bytes in
            var offset = 0
            while offset < bytes.count {
                let count = Glibc.write(descriptor, bytes.baseAddress! + offset, bytes.count - offset)
                if count < 0 && errno == EINTR { continue }
                guard count > 0 else { return }
                offset += count
            }
        }
    }
}

enum FileHandles {
    nonisolated(unsafe) static var handleClass: Class!

    static func make(_ cls: id?, descriptor: Int32, closeOnDealloc: Bool) -> id? {
        guard descriptor >= 0, let handle = Storage.allocate(cls ?? UnsafeMutableRawPointer(handleClass)) else { return nil }
        Storage.set(handle, FileHandleStorage(descriptor, closeOnDealloc: closeOnDealloc))
        return ObjC.autorelease(handle)
    }

    static func open(_ cls: id?, _ path: String?, _ flags: Int32) -> id? {
        guard let path else { return nil }
        return make(cls, descriptor: Glibc.open(path, flags | O_CLOEXEC), closeOnDealloc: true)
    }
}

@ObjCClass("NSFileHandle")
public final class NSFileHandle: NSObject {
    override public class func didDefineObjCClass(_ cls: ObjCClass) {
        NSObject.registerObjCCategoryStorageAllocated(cls)
        FileHandles.handleClass = cls.storage
    }

    private var storage: FileHandleStorage? { Storage.get(objcObject, as: FileHandleStorage.self) }

    @ObjCClassMethod("fileHandleForReadingAtPath:")
    static func reading(_ cls: ObjCClass, path: String?) -> ObjCObject? {
        FileHandles.open(cls.pointer, path, O_RDONLY).map(ObjCObject.init)
    }

    @ObjCClassMethod("fileHandleForWritingAtPath:")
    static func writing(_ cls: ObjCClass, path: String?) -> ObjCObject? {
        FileHandles.open(cls.pointer, path, O_WRONLY).map(ObjCObject.init)
    }

    @ObjCClassMethod("fileHandleForUpdatingAtPath:")
    static func updating(_ cls: ObjCClass, path: String?) -> ObjCObject? {
        FileHandles.open(cls.pointer, path, O_RDWR).map(ObjCObject.init)
    }

    /// The URL forms, which say why a file can't be opened.
    private static func open(_ cls: ObjCClass, _ url: NSURL?, _ flags: Int32, _ error: UnsafeMutablePointer<id?>?) -> ObjCObject? {
        let path = url.flatMap { $0.url.isFileURL ? $0.url.path : nil }
        if let handle = FileHandles.open(cls.pointer, path, flags) { return ObjCObject(handle) }
        error?.pointee = Errors.autoreleased(domain: ErrorConstants.NSPOSIXErrorDomainObject, code: Int(errno == 0 ? ENOENT : errno),
                                             description: nil)
        return nil
    }

    @ObjCClassMethod("fileHandleForReadingFromURL:error:")
    static func reading(_ cls: ObjCClass, url: NSURL?, error: UnsafeMutablePointer<id?>?) -> ObjCObject? {
        open(cls, url, O_RDONLY, error)
    }

    @ObjCClassMethod("fileHandleForWritingToURL:error:")
    static func writing(_ cls: ObjCClass, url: NSURL?, error: UnsafeMutablePointer<id?>?) -> ObjCObject? {
        open(cls, url, O_WRONLY, error)
    }

    @ObjCClassMethod("fileHandleForUpdatingURL:error:")
    static func updating(_ cls: ObjCClass, url: NSURL?, error: UnsafeMutablePointer<id?>?) -> ObjCObject? {
        open(cls, url, O_RDWR, error)
    }

    @ObjCClassMethod("fileHandleWithStandardInput")
    static func standardInput(_ cls: ObjCClass) -> ObjCObject? { FileHandles.make(cls.pointer, descriptor: 0, closeOnDealloc: false).map(ObjCObject.init) }
    @ObjCClassMethod("fileHandleWithStandardOutput")
    static func standardOutput(_ cls: ObjCClass) -> ObjCObject? { FileHandles.make(cls.pointer, descriptor: 1, closeOnDealloc: false).map(ObjCObject.init) }
    @ObjCClassMethod("fileHandleWithStandardError")
    static func standardError(_ cls: ObjCClass) -> ObjCObject? { FileHandles.make(cls.pointer, descriptor: 2, closeOnDealloc: false).map(ObjCObject.init) }
    @ObjCClassMethod("fileHandleWithNullDevice")
    static func nullDevice(_ cls: ObjCClass) -> ObjCObject? { FileHandles.open(cls.pointer, "/dev/null", O_RDWR).map(ObjCObject.init) }

    @ObjCMethod("initWithFileDescriptor:")
    func initialize(fileDescriptor: Int32) -> Self { initialize(fileDescriptor: fileDescriptor, closeOnDealloc: false) }

    @ObjCMethod("initWithFileDescriptor:closeOnDealloc:")
    func initialize(fileDescriptor: Int32, closeOnDealloc: Bool) -> Self {
        Storage.set(objcObject, FileHandleStorage(fileDescriptor, closeOnDealloc: closeOnDealloc))
        return self
    }

    @ObjCMethod("dealloc")
    func dealloc() {
        Storage.set(objcObject, nil)
        ObjC.superDealloc(objcObject, from: FileHandles.handleClass)
    }

    @ObjCMethod("fileDescriptor") func fileDescriptor() -> Int32 { storage?.descriptor ?? -1 }

    @ObjCMethod("readDataToEndOfFile")
    func readDataToEndOfFile() -> ObjCObject? { DataObjects.autoreleased(storage?.read(upTo: .max) ?? Data()).map(ObjCObject.init) }

    @ObjCMethod("readDataOfLength:")
    func readData(ofLength length: UInt) -> ObjCObject? {
        DataObjects.autoreleased(storage?.read(upTo: Int(min(length, UInt(Int.max)))) ?? Data()).map(ObjCObject.init)
    }

    /// What can be read now, waiting for some when there is none.
    @ObjCMethod("availableData")
    func availableData() -> ObjCObject? {
        var data = Data()
        if let storage {
            var buffer = [UInt8](repeating: 0, count: 65_536)
            let count = read(storage.descriptor, &buffer, buffer.count)
            if count > 0 { data.append(contentsOf: buffer[0..<count]) }
        }
        return DataObjects.autoreleased(data).map(ObjCObject.init)
    }

    @ObjCMethod("writeData:") func write(_ data: ObjCObject?) { storage?.write(DataObjects.data(data?.id)) }

    @ObjCMethod("offsetInFile") func offsetInFile() -> UInt64 { UInt64(max(0, lseek(storage?.descriptor ?? -1, 0, SEEK_CUR))) }
    @ObjCMethod("seekToEndOfFile") func seekToEndOfFile() -> UInt64 { UInt64(max(0, lseek(storage?.descriptor ?? -1, 0, SEEK_END))) }
    @ObjCMethod("seekToFileOffset:") func seek(toFileOffset offset: UInt64) { _ = lseek(storage?.descriptor ?? -1, off_t(offset), SEEK_SET) }

    // MARK: Throwing

    /// Reports errno as a POSIX error, for the methods that throw in Swift.
    private func fail(_ error: UnsafeMutablePointer<id?>?) -> Bool {
        error?.pointee = Errors.autoreleased(domain: ErrorConstants.NSPOSIXErrorDomainObject, code: Int(errno), description: nil)
        return false
    }

    /// The reads that report failure rather than raise.
    private func readReporting(upTo length: Int, error: UnsafeMutablePointer<id?>?) -> ObjCObject? {
        guard let storage, !storage.closed else {
            errno = EBADF
            _ = fail(error)
            return nil
        }
        var failure: Int32 = 0
        let data = storage.read(upTo: length, failure: &failure)
        guard failure == 0 else {
            errno = failure
            _ = fail(error)
            return nil
        }
        return DataObjects.autoreleased(data).map(ObjCObject.init)
    }

    @ObjCMethod("readDataToEndOfFileAndReturnError:")
    func readDataToEndOfFile(error: UnsafeMutablePointer<id?>?) -> ObjCObject? { readReporting(upTo: .max, error: error) }

    @ObjCMethod("readDataUpToLength:error:")
    func readData(upToLength length: UInt, error: UnsafeMutablePointer<id?>?) -> ObjCObject? {
        readReporting(upTo: Int(min(length, UInt(Int.max))), error: error)
    }

    @ObjCMethod("writeData:error:")
    func write(_ data: ObjCObject?, error: UnsafeMutablePointer<id?>?) -> Bool {
        guard let storage, !storage.closed else { errno = EBADF; return fail(error) }
        storage.write(DataObjects.data(data?.id))
        return true
    }

    @ObjCMethod("getOffset:error:")
    func getOffset(_ offset: UnsafeMutablePointer<UInt64>?, error: UnsafeMutablePointer<id?>?) -> Bool {
        let position = lseek(storage?.descriptor ?? -1, 0, SEEK_CUR)
        guard position >= 0 else { return fail(error) }
        offset?.pointee = UInt64(position)
        return true
    }

    @ObjCMethod("seekToEndReturningOffset:error:")
    func seekToEnd(offset: UnsafeMutablePointer<UInt64>?, error: UnsafeMutablePointer<id?>?) -> Bool {
        let position = lseek(storage?.descriptor ?? -1, 0, SEEK_END)
        guard position >= 0 else { return fail(error) }
        offset?.pointee = UInt64(position)
        return true
    }

    @ObjCMethod("seekToOffset:error:")
    func seekReturningError(toOffset offset: UInt64, error: UnsafeMutablePointer<id?>?) -> Bool {
        lseek(storage?.descriptor ?? -1, off_t(offset), SEEK_SET) >= 0 || fail(error)
    }

    @ObjCMethod("truncateAtOffset:error:")
    func truncateReturningError(atOffset offset: UInt64, error: UnsafeMutablePointer<id?>?) -> Bool {
        guard let descriptor = storage?.descriptor, ftruncate(descriptor, off_t(offset)) == 0 else { return fail(error) }
        return lseek(descriptor, off_t(offset), SEEK_SET) >= 0 || fail(error)
    }

    @ObjCMethod("synchronizeAndReturnError:")
    func synchronize(error: UnsafeMutablePointer<id?>?) -> Bool { fsync(storage?.descriptor ?? -1) == 0 || fail(error) }

    @ObjCMethod("closeAndReturnError:")
    func closeReturningError(_ error: UnsafeMutablePointer<id?>?) -> Bool {
        closeFile()
        return true
    }
    @ObjCMethod("truncateFileAtOffset:")
    func truncateFile(atOffset offset: UInt64) {
        guard let descriptor = storage?.descriptor else { return }
        _ = ftruncate(descriptor, off_t(offset))
        _ = lseek(descriptor, off_t(offset), SEEK_SET)
    }
    @ObjCMethod("synchronizeFile") func synchronizeFile() { _ = fsync(storage?.descriptor ?? -1) }

    @ObjCMethod("closeFile")
    func closeFile() {
        guard let storage, !storage.closed else { return }
        storage.closed = true
        close(storage.descriptor)
    }

    // MARK: In the background

    @ObjCMethod("readInBackgroundAndNotify")
    func readInBackgroundAndNotify() { background(.read) }
    @ObjCMethod("readInBackgroundAndNotifyForModes:")
    func readInBackgroundAndNotify(forModes modes: ObjCObject?) { background(.read) }
    @ObjCMethod("readToEndOfFileInBackgroundAndNotify")
    func readToEndOfFileInBackgroundAndNotify() { background(.readToEnd) }
    @ObjCMethod("readToEndOfFileInBackgroundAndNotifyForModes:")
    func readToEndOfFileInBackgroundAndNotify(forModes modes: ObjCObject?) { background(.readToEnd) }
    @ObjCMethod("waitForDataInBackgroundAndNotify")
    func waitForDataInBackgroundAndNotify() { background(.waitForData) }
    @ObjCMethod("waitForDataInBackgroundAndNotifyForModes:")
    func waitForDataInBackgroundAndNotify(forModes modes: ObjCObject?) { background(.waitForData) }
    /// A listening socket's next connection, as a new handle that closes
    /// it, in NSFileHandleConnectionAcceptedNotification.
    @ObjCMethod("acceptConnectionInBackgroundAndNotify")
    func acceptConnectionInBackgroundAndNotify() { background(.accept) }
    @ObjCMethod("acceptConnectionInBackgroundAndNotifyForModes:")
    func acceptConnectionInBackgroundAndNotify(forModes modes: ObjCObject?) { background(.accept) }

    private func background(_ kind: FileHandleBackground.Kind) {
        guard let storage, !storage.closed else { return }
        FileHandleBackground.start(objcObject, descriptor: storage.descriptor, kind: kind)
    }
}

/// A file handle's reading in the background: on a thread of its own, its
/// notification then posted on the run loop of the thread that asked, in
/// any mode (perry's run loops run everything in every mode). The thread
/// reads a duplicate of the descriptor, so closing the handle meanwhile
/// can't leave it reading another file given the same number.
enum FileHandleBackground {
    enum Kind { case read, readToEnd, waitForData, accept }

    private final class Request {
        let handle: id
        let descriptor: Int32
        let kind: Kind
        let loop: RunLoopState

        init(handle: id, descriptor: Int32, kind: Kind, loop: RunLoopState) {
            self.handle = handle
            self.descriptor = descriptor
            self.kind = kind
            self.loop = loop
        }

        func run() {
            var data = Data()
            var failure: Int32 = 0
            var accepted: Int32 = -1
            var buffer = [UInt8](repeating: 0, count: 65_536)
            switch kind {
            case .read, .readToEnd:
                while true {
                    let count = Glibc.read(descriptor, &buffer, buffer.count)
                    if count < 0 && errno == EINTR { continue }
                    if count < 0 { failure = errno }
                    guard count > 0 else { break }
                    data.append(contentsOf: buffer[0..<count])
                    if kind == .read { break }
                }
            case .waitForData:
                var file = pollfd(fd: descriptor, events: Int16(POLLIN), revents: 0)
                while poll(&file, 1, -1) < 0 && errno == EINTR {}
            case .accept:
                repeat { accepted = Glibc.accept(descriptor, nil, nil) } while accepted < 0 && errno == EINTR
                if accepted < 0 { failure = errno }
            }
            close(descriptor)
            loop.perform(work: { [self] in
                post(data: data, failure: failure, accepted: accepted)
                loop.removeSource()
                ObjC.release(handle)
            })
        }

        private func post(data: Data, failure: Int32, accepted: Int32) {
            let name: String
            var entries: [(key: id, value: id)] = []
            switch kind {
            case .read: name = "NSFileHandleReadCompletionNotification"
            case .readToEnd: name = "NSFileHandleReadToEndOfFileCompletionNotification"
            case .waitForData: name = "NSFileHandleDataAvailableNotification"
            case .accept: name = "NSFileHandleConnectionAcceptedNotification"
            }
            if kind == .read || kind == .readToEnd, let object = DataObjects.autoreleased(data) {
                entries.append((Strings.autoreleased("NSFileHandleNotificationDataItem"), object))
            }
            if kind == .accept, accepted >= 0, let connection = FileHandles.make(nil, descriptor: accepted, closeOnDealloc: true) {
                entries.append((Strings.autoreleased("NSFileHandleNotificationFileHandleItem"), connection))
            }
            if failure != 0, let number = Numbers.make(nil, .signed(Int64(failure))) {
                entries.append((Strings.autoreleased("NSFileHandleError"), number))
            }
            guard let centerClass = "NSNotificationCenter".withCString({ ObjC.getClass($0) }),
                  let center = ObjC.send(UnsafeMutableRawPointer(centerClass), ObjC.selector("defaultCenter")) else { return }
            typealias Post = @convention(c) (id?, SEL, id?, id?, id?) -> Void
            unsafeBitCast(ObjC.msgSend, to: Post.self)(center, ObjC.selector("postNotificationName:object:userInfo:"),
                                                        Strings.autoreleased(name), handle, Dictionaries.autoreleased(entries))
        }
    }

    static func start(_ handle: id, descriptor: Int32, kind: Kind) {
        let copy = dup(descriptor)
        guard copy >= 0 else { return }
        let loop = RunLoops.current
        loop.addSource()
        _ = ObjC.retain(handle)
        let request = Request(handle: handle, descriptor: copy, kind: kind, loop: loop)
        var thread = pthread_t()
        let context = Unmanaged.passRetained(request).toOpaque()
        if pthread_create(&thread, nil, { context in
            Unmanaged<Request>.fromOpaque(context!).takeRetainedValue().run()
            return nil
        }, context) == 0 {
            pthread_detach(thread)
        } else {
            Unmanaged<Request>.fromOpaque(context).release()
            close(copy)
            loop.removeSource()
            ObjC.release(handle)
        }
    }
}

/// A port's state: its delegate (not retained, as Darwin's isn't), whether
/// it is valid, a Mach port's name and rights, and the run loop its
/// messages come in on: the one it was scheduled in, else the one of the
/// thread that made it.
final class PortStorage {
    var delegate: id?
    var valid = true
    var machPort: UInt32 = 0
    /// NSMachPortOptions: the rights to give up when it becomes invalid.
    var options: UInt = 0
    var loop: RunLoopState?

    init(loop: RunLoopState?) { self.loop = loop }
}

enum Ports {
    nonisolated(unsafe) static var portClass: Class!
    nonisolated(unsafe) static var machPortClass: Class!

    /// The port's state, made the first time a port that came from
    /// elsewhere than -init is asked.
    static func storage(_ object: id) -> PortStorage {
        if let storage = Storage.get(object, as: PortStorage.self) { return storage }
        let storage = PortStorage(loop: RunLoops.current)
        Storage.set(object, storage)
        return storage
    }

    /// NSMachPortDeallocateReceiveRight: the port's name goes with it.
    static func release(_ storage: PortStorage) {
        guard storage.options & 2 != 0, storage.machPort != 0 else { return }
        _ = MachPorts.destruct?(0, storage.machPort, 0, 0)
        storage.machPort = 0
    }
}

/// NSPort: a channel messages come in on, on the run loop it's in. +port
/// and +alloc of NSPort itself make NSMachPorts, as on Darwin. Messages go
/// between the ports of this process (see NSMessagePort.swift).
@ObjCClass("NSPort")
public class NSPort: NSObject {
    override public class func didDefineObjCClass(_ cls: ObjCClass) {
        Ports.portClass = cls.storage
    }

    private static func concrete(_ cls: ObjCClass) -> id? {
        cls.storage == Ports.portClass ? UnsafeMutableRawPointer(Ports.machPortClass) : cls.pointer
    }

    @ObjCClassMethod("alloc")
    static func allocate(_ cls: ObjCClass) -> UnsafeMutableRawPointer? { Storage.allocate(concrete(cls)) }

    @ObjCClassMethod("allocWithZone:")
    static func allocate(_ cls: ObjCClass, zone: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer? {
        Storage.allocate(concrete(cls))
    }

    @ObjCClassMethod("port")
    static func port(_ cls: ObjCClass) -> ObjCObject? {
        ObjC.send(ObjC.send(cls.pointer, ObjC.selector("alloc")), ObjC.selector("init")).map { ObjCObject(ObjC.autorelease($0)!) }
    }

    @ObjCMethod("init")
    func initialize() -> Self {
        _ = Ports.storage(objcObject)
        return self
    }

    @ObjCMethod("dealloc")
    func dealloc() {
        if let storage = Storage.get(objcObject, as: PortStorage.self) { Ports.release(storage) }
        Storage.set(objcObject, nil)
        ObjC.superDealloc(objcObject, from: Ports.portClass)
    }

    @ObjCMethod("isValid") func isValid() -> Bool { Ports.storage(objcObject).valid }

    /// Once: the port stops taking messages, gives up its rights, and
    /// NSPortDidBecomeInvalidNotification is posted for it.
    @ObjCMethod("invalidate")
    func invalidate() {
        let storage = Ports.storage(objcObject)
        guard storage.valid else { return }
        storage.valid = false
        Ports.release(storage)
        guard let centerClass = "NSNotificationCenter".withCString({ ObjC.getClass($0) }),
              let center = ObjC.send(UnsafeMutableRawPointer(centerClass), ObjC.selector("defaultCenter")) else { return }
        _ = ObjC.send(center, ObjC.selector("postNotificationName:object:"),
                      Strings.autoreleased("NSPortDidBecomeInvalidNotification"), objcObject)
    }

    @ObjCMethod("delegate") func delegate() -> UnsafeMutableRawPointer? { Ports.storage(objcObject).delegate }
    @ObjCMethod("setDelegate:") func setDelegate(_ delegate: UnsafeMutableRawPointer?) { Ports.storage(objcObject).delegate = delegate }

    /// Ports are kept, not copied.
    @ObjCMethod("copyWithZone:") func copy(zone: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer? { ObjC.retain(objcObject) }

    /// The run loop is where the port's messages come in.
    @ObjCMethod("scheduleInRunLoop:forMode:")
    func schedule(in runLoop: ObjCObject?, forMode mode: ObjCObject?) {
        if let state = RunLoops.state(runLoop?.id) { Ports.storage(objcObject).loop = state }
        _ = ObjC.send(runLoop?.id, ObjC.selector("addPort:forMode:"), objcObject, mode?.id)
    }

    @ObjCMethod("removeFromRunLoop:forMode:")
    func remove(from runLoop: ObjCObject?, forMode mode: ObjCObject?) {
        _ = ObjC.send(runLoop?.id, ObjC.selector("removePort:forMode:"), objcObject, mode?.id)
    }

    /// No header space is needed: messages don't leave the process.
    @ObjCMethod("reservedSpaceLength") func reservedSpaceLength() -> UInt { 0 }

    @ObjCMethod("sendBeforeDate:components:from:reserved:")
    func send(beforeDate date: ObjCObject?, components: ObjCObject?, from receivePort: ObjCObject?, reserved: UInt) -> Bool {
        send(beforeDate: date, msgid: 0, components: components, from: receivePort, reserved: reserved)
    }

    /// The message goes to this port's delegate on the port's run loop.
    @ObjCMethod("sendBeforeDate:msgid:components:from:reserved:")
    func send(beforeDate date: ObjCObject?, msgid: UInt, components: ObjCObject?, from receivePort: ObjCObject?, reserved: UInt) -> Bool {
        PortMessages.send(to: objcObject, msgid: UInt32(truncatingIfNeeded: msgid), components: components?.id, from: receivePort?.id)
    }

    /// Distributed Objects' connections, which macOS 10.13 retired: there
    /// are none to add.
    @ObjCMethod("addConnection:toRunLoop:forMode:")
    func add(connection: ObjCObject?, toRunLoop runLoop: ObjCObject?, forMode mode: ObjCObject?) {}

    @ObjCMethod("removeConnection:fromRunLoop:forMode:")
    func remove(connection: ObjCObject?, fromRunLoop runLoop: ObjCObject?, forMode mode: ObjCObject?) {}
}

/// NSMachPort: a port with a Mach port's name, which PerrySystem's ports
/// stand for. -init makes a new port, whose receive right goes when the
/// NSMachPort becomes invalid or goes; a name given is the caller's, kept
/// unless the options say to give its receive right up (send rights aren't
/// counted here). MACH_PORT_NULL makes no port, as on Darwin.
@ObjCClass("NSMachPort")
public final class NSMachPort: NSPort {
    override public class func didDefineObjCClass(_ cls: ObjCClass) {
        Ports.machPortClass = cls.storage
    }

    @ObjCMethod("init")
    override func initialize() -> Self {
        let storage = Ports.storage(objcObject)
        var port: UInt32 = 0
        if let allocate = MachPorts.allocate, allocate(0, 1, &port) == 0 {   // MACH_PORT_RIGHT_RECEIVE
            storage.machPort = port
            storage.options = 3
        }
        return self
    }

    private func set(machPort port: UInt32, options: UInt) -> Self? {
        guard port != 0 else { return nil }
        let storage = Ports.storage(objcObject)
        (storage.machPort, storage.options) = (port, options)
        return self
    }

    @ObjCMethod("initWithMachPort:")
    func initialize(machPort port: UInt32) -> Self? { set(machPort: port, options: 0) }

    @ObjCMethod("initWithMachPort:options:")
    func initialize(machPort port: UInt32, options: UInt) -> Self? { set(machPort: port, options: options) }

    @ObjCClassMethod("portWithMachPort:")
    static func port(_ cls: ObjCClass, machPort name: UInt32) -> UnsafeMutableRawPointer? {
        made(cls, name, options: 0)
    }

    @ObjCClassMethod("portWithMachPort:options:")
    static func port(_ cls: ObjCClass, machPort name: UInt32, options: UInt) -> UnsafeMutableRawPointer? {
        made(cls, name, options: options)
    }

    /// A port (autoreleased) for a name; none for MACH_PORT_NULL.
    private static func made(_ cls: ObjCClass, _ name: UInt32, options: UInt) -> UnsafeMutableRawPointer? {
        guard name != 0, let object = Storage.allocate(cls.pointer) else { return nil }
        let storage = Ports.storage(object)
        (storage.machPort, storage.options) = (name, options)
        return ObjC.autorelease(object)
    }

    @ObjCMethod("machPort") func machPort() -> UInt32 { Ports.storage(objcObject).machPort }
}

/// NSStream's property keys and network service types, and CFStream's
/// SSL settings, with Darwin's values.
@ObjCConstants
enum StreamConstants {
    static let NSStreamDataWrittenToMemoryStreamKey = "kCFStreamPropertyDataWritten"
    static let NSStreamNetworkServiceType = "kCFStreamNetworkServiceType"
    static let NSStreamNetworkServiceTypeVoIP = "kCFStreamNetworkServiceTypeVoIP"
    static let NSStreamNetworkServiceTypeVideo = "kCFStreamNetworkServiceTypeVideo"
    static let NSStreamNetworkServiceTypeBackground = "kCFStreamNetworkServiceTypeBackground"
    static let NSStreamNetworkServiceTypeVoice = "kCFStreamNetworkServiceTypeVoice"
    static let kCFStreamPropertySSLPeerTrust = "kCFStreamPropertySSLPeerTrust"
    static let kCFStreamPropertySSLSettings = "kCFStreamPropertySSLSettings"
    static let kCFStreamPropertySocketSecurityLevel = "kCFStreamPropertySocketSecurityLevel"
    static let kCFStreamSSLCertificates = "kCFStreamSSLCertificates"
    static let kCFStreamSSLLevel = "kCFStreamSSLLevel"
    static let kCFStreamSSLIsServer = "kCFStreamSSLIsServer"
    static let kCFStreamPropertyAppendToFile = "kCFStreamPropertyAppendToFile"
    static let kCFStreamSSLPeerName = "kCFStreamSSLPeerName"
    static let kCFStreamSSLValidatesCertificateChain = "kCFStreamSSLValidatesCertificateChain"
    static let kCFStreamSocketSecurityLevelNegotiatedSSL = "kCFStreamSocketSecurityLevelNegotiatedSSL"
    static let kCFStreamSocketSecurityLevelNone = "kCFStreamSocketSecurityLevelNone"
    static let kCFStreamSocketSecurityLevelTLSv1 = "kCFStreamSocketSecurityLevelTLSv1"
    static let kCFStreamPropertyShouldCloseNativeSocket = "kCFStreamPropertyShouldCloseNativeSocket"
    static let kCFStreamPropertySocketNativeHandle = "kCFStreamPropertySocketNativeHandle"
}
