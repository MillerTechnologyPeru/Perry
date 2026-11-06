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
    static let kCFStreamSSLPeerName = "kCFStreamSSLPeerName"
    static let kCFStreamSSLValidatesCertificateChain = "kCFStreamSSLValidatesCertificateChain"
    static let kCFStreamSocketSecurityLevelNegotiatedSSL = "kCFStreamSocketSecurityLevelNegotiatedSSL"
}
