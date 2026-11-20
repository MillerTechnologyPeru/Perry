import FoundationEssentials
import Glibc
import PerryObjCInterop

// NSFileHandle, over a file descriptor; and NSPort and NSMachPort, which
// carry no messages but keep a run loop running when added to it.

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
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 65_536)
        while data.count < length {
            let count = Glibc.read(descriptor, &buffer, min(buffer.count, length - data.count))
            if count < 0 && errno == EINTR { continue }
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
    enum Kind { case read, readToEnd, waitForData }

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
            }
            close(descriptor)
            loop.perform(work: { [self] in
                post(data: data, failure: failure)
                loop.removeSource()
                ObjC.release(handle)
            })
        }

        private func post(data: Data, failure: Int32) {
            let name: String
            var entries: [(key: id, value: id)] = []
            switch kind {
            case .read: name = "NSFileHandleReadCompletionNotification"
            case .readToEnd: name = "NSFileHandleReadToEndOfFileCompletionNotification"
            case .waitForData: name = "NSFileHandleDataAvailableNotification"
            }
            if kind != .waitForData, let object = DataObjects.autoreleased(data) {
                entries.append((Strings.autoreleased("NSFileHandleNotificationDataItem"), object))
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

@ObjCClass("NSPort")
public class NSPort: NSObject {
    @ObjCClassMethod("port")
    static func port(_ cls: ObjCClass) -> ObjCObject? {
        ObjC.send(ObjC.send(cls.pointer, ObjC.selector("alloc")), ObjC.selector("init")).map { ObjCObject(ObjC.autorelease($0)!) }
    }

    @ObjCMethod("isValid") func isValid() -> Bool { true }
    @ObjCMethod("invalidate") func invalidate() {}
    @ObjCMethod("delegate") func delegate() -> ObjCObject? { nil }
    @ObjCMethod("setDelegate:") func setDelegate(_ delegate: ObjCObject?) {}
    @ObjCMethod("scheduleInRunLoop:forMode:")
    func schedule(in runLoop: ObjCObject?, forMode mode: ObjCObject?) {
        _ = ObjC.send(runLoop?.id, ObjC.selector("addPort:forMode:"), objcObject, mode?.id)
    }
    @ObjCMethod("removeFromRunLoop:forMode:")
    func remove(from runLoop: ObjCObject?, forMode mode: ObjCObject?) {
        _ = ObjC.send(runLoop?.id, ObjC.selector("removePort:forMode:"), objcObject, mode?.id)
    }
}

@ObjCClass("NSMachPort")
public final class NSMachPort: NSPort {
    @ObjCMethod("machPort") func machPort() -> UInt32 { 0 }
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
