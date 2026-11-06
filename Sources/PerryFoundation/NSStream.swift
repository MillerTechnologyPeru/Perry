import FoundationEssentials
import Glibc
import PerryObjCInterop

// NSStream, and its input and output streams over data, files and memory.
// Programs subclass NSInputStream for request bodies, overriding all of
// it, so its -init makes a stream with no source, as Apple's does. A
// stream scheduled on a run loop tells its delegate what happened on the
// loop's next pass: that it opened, that bytes or space are there, that
// it ended or failed.

/// NSStreamStatus and NSStreamEvent values.
private enum StreamStatus {
    static let notOpen: UInt = 0, opening: UInt = 1, open: UInt = 2, reading: UInt = 3, writing: UInt = 4
    static let atEnd: UInt = 5, closed: UInt = 6, error: UInt = 7
}

private enum StreamEvent {
    static let openCompleted: UInt = 1, hasBytesAvailable: UInt = 2, hasSpaceAvailable: UInt = 4
    static let errorOccurred: UInt = 8, endEncountered: UInt = 16
}

final class StreamStorage {
    enum Source {
        case none
        case data(Data)
        case file(String)
        case memory                                     // output to memory
        case buffer(UnsafeMutablePointer<UInt8>, Int)   // output to a caller's buffer
        case fileOutput(String, append: Bool)
    }

    let source: Source
    var status = StreamStatus.notOpen
    var error: id?
    /// The delegate, not retained; nil is the stream itself.
    var delegate: id?
    var properties: [String: id] = [:]
    var runLoops: [RunLoopState] = []

    var offset = 0              // into data, or into the caller's buffer
    var descriptor: Int32 = -1
    var written = Data()

    init(_ source: Source) { self.source = source }

    deinit {
        if descriptor >= 0 { close(descriptor) }
        ObjC.release(error)
        for value in properties.values { ObjC.release(value) }
    }
}

enum Streams {
    nonisolated(unsafe) static var streamClass: Class!
    nonisolated(unsafe) static var inputClass: Class!
    nonisolated(unsafe) static var outputClass: Class!
    private static let creation = Monitor()

    /// The stream's storage, made if its initializer did not run: a
    /// subclass's -init.
    static func storage(_ object: id) -> StreamStorage {
        creation.locked {
            if let storage = Storage.get(object, as: StreamStorage.self) { return storage }
            let storage = StreamStorage(.none)
            Storage.set(object, storage)
            return storage
        }
    }

    static func initialize(_ object: id?, _ source: StreamStorage.Source) -> id? {
        guard let object else { return nil }
        Storage.set(object, StreamStorage(source))
        return object
    }

    static func make(_ cls: id?, fallback: Class, _ source: StreamStorage.Source) -> id? {
        guard let object = Storage.allocate(cls ?? UnsafeMutableRawPointer(fallback)) else { return nil }
        Storage.set(object, StreamStorage(source))
        return ObjC.autorelease(object)
    }

    static func fail(_ object: id, _ storage: StreamStorage, code: Int32) {
        storage.status = StreamStatus.error
        ObjC.release(storage.error)
        storage.error = ObjC.retain(Errors.autoreleased(domain: ErrorConstants.NSPOSIXErrorDomainObject, code: Int(code), description: nil))
        post(object, storage, StreamEvent.errorOccurred)
    }

    /// Tells the delegate of `event` on each run loop the stream is
    /// scheduled on, if the stream is still open then.
    static func post(_ object: id, _ storage: StreamStorage, _ event: UInt) {
        guard !storage.runLoops.isEmpty else { return }
        for runLoop in storage.runLoops {
            _ = ObjC.retain(object)
            runLoop.perform {
                defer { ObjC.release(object) }
                guard storage.status != StreamStatus.closed, storage.status != StreamStatus.notOpen || event == StreamEvent.errorOccurred else { return }
                let delegate = storage.delegate ?? object
                typealias Responds = @convention(c) (id, SEL, SEL) -> Bool
                typealias Handle = @convention(c) (id, SEL, id, UInt) -> Void
                let selector = ObjC.selector("stream:handleEvent:")
                guard unsafeBitCast(ObjC.msgSend, to: Responds.self)(delegate, ObjC.selector("respondsToSelector:"), selector) else { return }
                unsafeBitCast(ObjC.msgSend, to: Handle.self)(delegate, selector, object, event)
            }
        }
    }

    /// Opens a stream that has a source.
    static func open(_ object: id, input: Bool) {
        let storage = storage(object)
        guard storage.status == StreamStatus.notOpen else { return }
        switch storage.source {
        case .file(let path):
            storage.descriptor = Glibc.open(path, O_RDONLY | O_CLOEXEC)
        case .fileOutput(let path, let append):
            storage.descriptor = Glibc.open(path, O_WRONLY | O_CREAT | O_CLOEXEC | (append ? O_APPEND : O_TRUNC), 0o644)
        default:
            break
        }
        switch storage.source {
        case .file, .fileOutput:
            if storage.descriptor < 0 { return fail(object, storage, code: errno) }
        default:
            break
        }
        storage.status = StreamStatus.open
        post(object, storage, StreamEvent.openCompleted)
        if input {
            post(object, storage, hasBytes(storage) ? StreamEvent.hasBytesAvailable : StreamEvent.endEncountered)
        } else {
            post(object, storage, StreamEvent.hasSpaceAvailable)
        }
    }

    static func close(_ object: id) {
        let storage = storage(object)
        if storage.descriptor >= 0 {
            Glibc.close(storage.descriptor)
            storage.descriptor = -1
        }
        storage.status = StreamStatus.closed
    }

    static func hasBytes(_ storage: StreamStorage) -> Bool {
        switch storage.source {
        case .data(let data): return storage.offset < data.count
        case .file: return storage.status == StreamStatus.open
        default: return false
        }
    }

    static func read(_ object: id, _ buffer: UnsafeMutablePointer<UInt8>?, _ length: Int) -> Int {
        let storage = storage(object)
        guard let buffer, storage.status == StreamStatus.open else {
            return storage.status == StreamStatus.atEnd ? 0 : -1
        }
        var count = 0
        switch storage.source {
        case .data(let data):
            count = min(length, data.count - storage.offset)
            if count > 0 {
                data.withUnsafeBytes { bytes in
                    memcpy(buffer, bytes.baseAddress! + storage.offset, count)
                }
                storage.offset += count
            }
            if storage.offset >= data.count { storage.status = StreamStatus.atEnd }
        case .file:
            repeat { count = Glibc.read(storage.descriptor, buffer, length) } while count < 0 && errno == EINTR
            if count < 0 {
                fail(object, storage, code: errno)
                return -1
            }
            storage.offset += count
            if count == 0 { storage.status = StreamStatus.atEnd }
        default:
            storage.status = StreamStatus.atEnd
        }
        post(object, storage, storage.status == StreamStatus.atEnd ? StreamEvent.endEncountered : StreamEvent.hasBytesAvailable)
        return count
    }

    static func write(_ object: id, _ buffer: UnsafePointer<UInt8>?, _ length: Int) -> Int {
        let storage = storage(object)
        guard let buffer, storage.status == StreamStatus.open else { return -1 }
        var count = 0
        switch storage.source {
        case .memory:
            storage.written.append(buffer, count: length)
            count = length
        case .buffer(let target, let capacity):
            count = min(length, capacity - storage.offset)
            if count > 0 { memcpy(target + storage.offset, buffer, count) }
            storage.offset += count
            if storage.offset >= capacity { storage.status = StreamStatus.atEnd }
        case .fileOutput:
            repeat { count = Glibc.write(storage.descriptor, buffer, length) } while count < 0 && errno == EINTR
            if count < 0 {
                fail(object, storage, code: errno)
                return -1
            }
        default:
            return -1
        }
        post(object, storage, storage.status == StreamStatus.atEnd ? StreamEvent.endEncountered : StreamEvent.hasSpaceAvailable)
        return count
    }

    static func hasSpace(_ storage: StreamStorage) -> Bool {
        guard storage.status == StreamStatus.open else { return false }
        if case .buffer(_, let capacity) = storage.source { return storage.offset < capacity }
        return true
    }

    /// A property: the bytes written to memory, a file's offset, or one
    /// that was set.
    static func property(_ object: id, _ key: id?) -> id? {
        guard let name = Strings.value(of: key) else { return nil }
        let storage = storage(object)
        switch name {
        case "kCFStreamPropertyDataWritten":
            if case .memory = storage.source { return DataObjects.autoreleased(storage.written) }
        case "kCFStreamPropertyFileCurrentOffset":
            switch storage.source {
            case .file, .fileOutput:
                let offset = storage.descriptor >= 0 ? lseek(storage.descriptor, 0, SEEK_CUR) : 0
                return Numbers.make(nil, .signed(Int64(offset)))
            case .data:
                return Numbers.make(nil, .signed(Int64(storage.offset)))
            default:
                break
            }
        default:
            break
        }
        return storage.properties[name]
    }

    /// Sets a property; a file's offset seeks.
    static func setProperty(_ object: id, _ value: id?, _ key: id?) -> Bool {
        guard let name = Strings.value(of: key) else { return false }
        let storage = storage(object)
        if name == "kCFStreamPropertyFileCurrentOffset" {
            typealias Get = @convention(c) (id, SEL) -> Int64
            let offset = value.map { unsafeBitCast(ObjC.msgSend, to: Get.self)($0, ObjC.selector("longLongValue")) } ?? 0
            switch storage.source {
            case .file, .fileOutput:
                return storage.descriptor >= 0 && lseek(storage.descriptor, off_t(offset), SEEK_SET) >= 0
            case .data(let data):
                guard offset >= 0, offset <= data.count else { return false }
                storage.offset = Int(offset)
                if storage.status == StreamStatus.atEnd, storage.offset < data.count { storage.status = StreamStatus.open }
                return true
            default:
                return false
            }
        }
        let old = storage.properties[name]
        storage.properties[name] = ObjC.retain(value)
        ObjC.release(old)
        return true
    }

    static func schedule(_ object: id, _ runLoop: id?) {
        guard let state = RunLoops.state(runLoop) else { return }
        let storage = storage(object)
        guard !storage.runLoops.contains(where: { $0 === state }) else { return }
        storage.runLoops.append(state)
    }

    static func unschedule(_ object: id, _ runLoop: id?) {
        guard let state = RunLoops.state(runLoop) else { return }
        storage(object).runLoops.removeAll { $0 === state }
    }

    static func path(_ url: id?) -> String? {
        guard let url = URLs.url(url), url.isFileURL else { return nil }
        return url.path(percentEncoded: false)
    }
}

@ObjCClass("NSStream")
public class NSStream: NSObject {
    override public class func didDefineObjCClass(_ cls: ObjCClass) {
        NSObject.registerObjCCategoryStorageAllocated(cls)
        Streams.streamClass = cls.storage
    }

    var storage: StreamStorage { Streams.storage(objcObject) }

    @ObjCMethod("init")
    func initialize() -> Self {
        _ = storage
        return self
    }

    @ObjCMethod("dealloc")
    func dealloc() {
        Storage.set(objcObject, nil)
        ObjC.superDealloc(objcObject, from: Streams.streamClass)
    }

    @ObjCMethod("open") func open() { Streams.open(objcObject, input: ObjC.isKind(objcObject, of: Streams.inputClass)) }
    @ObjCMethod("close") func close() { Streams.close(objcObject) }

    @ObjCMethod("delegate")
    func delegate() -> UnsafeMutableRawPointer? { storage.delegate ?? objcObject }

    @ObjCMethod("setDelegate:")
    func setDelegate(_ delegate: UnsafeMutableRawPointer?) { storage.delegate = delegate == objcObject ? nil : delegate }

    @ObjCMethod("streamStatus") func streamStatus() -> UInt { storage.status }
    @ObjCMethod("streamError") func streamError() -> UnsafeMutableRawPointer? { storage.error }

    @ObjCMethod("propertyForKey:")
    func property(forKey key: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer? { Streams.property(objcObject, key) }

    @ObjCMethod("setProperty:forKey:")
    func setProperty(_ value: UnsafeMutableRawPointer?, forKey key: UnsafeMutableRawPointer?) -> Bool {
        Streams.setProperty(objcObject, value, key)
    }

    @ObjCMethod("scheduleInRunLoop:forMode:")
    func schedule(in runLoop: UnsafeMutableRawPointer?, forMode mode: UnsafeMutableRawPointer?) { Streams.schedule(objcObject, runLoop) }

    @ObjCMethod("removeFromRunLoop:forMode:")
    func remove(from runLoop: UnsafeMutableRawPointer?, forMode mode: UnsafeMutableRawPointer?) { Streams.unschedule(objcObject, runLoop) }
}

@ObjCClass("NSInputStream")
public class NSInputStream: NSStream {
    override public class func didDefineObjCClass(_ cls: ObjCClass) {
        Streams.inputClass = cls.storage
    }

    @ObjCClassMethod("inputStreamWithData:")
    static func stream(_ cls: ObjCClass, data: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer? {
        guard data != nil else { return nil }
        return Streams.make(cls.pointer, fallback: Streams.inputClass, .data(DataObjects.data(data)))
    }

    @ObjCClassMethod("inputStreamWithFileAtPath:")
    static func stream(_ cls: ObjCClass, fileAtPath path: String?) -> UnsafeMutableRawPointer? {
        guard let path else { return nil }
        return Streams.make(cls.pointer, fallback: Streams.inputClass, .file(path))
    }

    @ObjCClassMethod("inputStreamWithURL:")
    static func stream(_ cls: ObjCClass, url: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer? {
        guard let path = Streams.path(url) else { return nil }
        return Streams.make(cls.pointer, fallback: Streams.inputClass, .file(path))
    }

    @ObjCMethod("initWithData:")
    func initialize(data: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer? {
        Streams.initialize(objcObject, .data(DataObjects.data(data)))
    }

    @ObjCMethod("initWithFileAtPath:")
    func initialize(fileAtPath path: String?) -> UnsafeMutableRawPointer? {
        guard let path else {
            ObjC.release(objcObject)
            return nil
        }
        return Streams.initialize(objcObject, .file(path))
    }

    @ObjCMethod("initWithURL:")
    func initialize(url: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer? {
        guard let path = Streams.path(url) else {
            ObjC.release(objcObject)
            return nil
        }
        return Streams.initialize(objcObject, .file(path))
    }

    @ObjCMethod("read:maxLength:")
    func read(_ buffer: UnsafeMutablePointer<UInt8>?, maxLength length: UInt) -> Int {
        Streams.read(objcObject, buffer, Int(min(length, UInt(Int.max))))
    }

    /// Only a data stream's bytes are in memory to lend.
    @ObjCMethod("getBuffer:length:")
    func getBuffer(_ buffer: UnsafeMutablePointer<UnsafeMutablePointer<UInt8>?>?, length: UnsafeMutablePointer<UInt>?) -> Bool { false }

    @ObjCMethod("hasBytesAvailable") func hasBytesAvailable() -> Bool { Streams.hasBytes(storage) }
}

@ObjCClass("NSOutputStream")
public class NSOutputStream: NSStream {
    override public class func didDefineObjCClass(_ cls: ObjCClass) {
        Streams.outputClass = cls.storage
    }

    @ObjCClassMethod("outputStreamToMemory")
    static func toMemory(_ cls: ObjCClass) -> UnsafeMutableRawPointer? {
        Streams.make(cls.pointer, fallback: Streams.outputClass, .memory)
    }

    @ObjCClassMethod("outputStreamToBuffer:capacity:")
    static func toBuffer(_ cls: ObjCClass, buffer: UnsafeMutablePointer<UInt8>?, capacity: UInt) -> UnsafeMutableRawPointer? {
        guard let buffer else { return nil }
        return Streams.make(cls.pointer, fallback: Streams.outputClass, .buffer(buffer, Int(min(capacity, UInt(Int.max)))))
    }

    @ObjCClassMethod("outputStreamToFileAtPath:append:")
    static func toFile(_ cls: ObjCClass, path: String?, append: Bool) -> UnsafeMutableRawPointer? {
        guard let path else { return nil }
        return Streams.make(cls.pointer, fallback: Streams.outputClass, .fileOutput(path, append: append))
    }

    @ObjCClassMethod("outputStreamWithURL:append:")
    static func toURL(_ cls: ObjCClass, url: UnsafeMutableRawPointer?, append: Bool) -> UnsafeMutableRawPointer? {
        guard let path = Streams.path(url) else { return nil }
        return Streams.make(cls.pointer, fallback: Streams.outputClass, .fileOutput(path, append: append))
    }

    @ObjCMethod("initToMemory")
    func initializeToMemory() -> UnsafeMutableRawPointer? { Streams.initialize(objcObject, .memory) }

    @ObjCMethod("initToBuffer:capacity:")
    func initialize(toBuffer buffer: UnsafeMutablePointer<UInt8>?, capacity: UInt) -> UnsafeMutableRawPointer? {
        guard let buffer else {
            ObjC.release(objcObject)
            return nil
        }
        return Streams.initialize(objcObject, .buffer(buffer, Int(min(capacity, UInt(Int.max)))))
    }

    @ObjCMethod("initToFileAtPath:append:")
    func initialize(toFileAtPath path: String?, append: Bool) -> UnsafeMutableRawPointer? {
        guard let path else {
            ObjC.release(objcObject)
            return nil
        }
        return Streams.initialize(objcObject, .fileOutput(path, append: append))
    }

    @ObjCMethod("initWithURL:append:")
    func initialize(url: UnsafeMutableRawPointer?, append: Bool) -> UnsafeMutableRawPointer? {
        guard let path = Streams.path(url) else {
            ObjC.release(objcObject)
            return nil
        }
        return Streams.initialize(objcObject, .fileOutput(path, append: append))
    }

    @ObjCMethod("write:maxLength:")
    func write(_ buffer: UnsafePointer<UInt8>?, maxLength length: UInt) -> Int {
        Streams.write(objcObject, buffer, Int(min(length, UInt(Int.max))))
    }

    @ObjCMethod("hasSpaceAvailable") func hasSpaceAvailable() -> Bool { Streams.hasSpace(storage) }
}
