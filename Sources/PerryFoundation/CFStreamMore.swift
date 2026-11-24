import CPerryFoundation
import FoundationEssentials
import Glibc
import PerryObjCInterop

// CFReadStream's and CFWriteStream's other functions: streams of data and
// of buffers, streams a program implements itself with callbacks
// (CoreFoundation's CFReadStreamCreate and CFWriteStreamCreate, which
// CFStreamAbstract.h in Swift's open-source CoreFoundation declares),
// events on a dispatch queue, errors as a CFStreamError, and property
// lists read from and written to streams.

/// Work run on a dispatch queue, through libdispatch's dispatch_async_f.
final class DispatchedWork {
    let body: () -> Void
    init(_ body: @escaping () -> Void) { self.body = body }

    /// Runs `body` on `queue`, in an autorelease pool; false when there is
    /// no libdispatch to run it.
    @discardableResult
    static func async(_ queue: id, _ body: @escaping () -> Void) -> Bool {
        guard let run = Dispatch.async else { return false }
        let context = Unmanaged.passRetained(DispatchedWork(body)).toOpaque()
        run(queue, context) { context in
            guard let context else { return }
            let work = Unmanaged<DispatchedWork>.fromOpaque(context).takeRetainedValue()
            ObjC.autoreleasepool { work.body() }
        }
        return true
    }
}

/// A stream whose callbacks the program gave: CFReadStreamCallBacks or
/// CFWriteStreamCallBacks. Version 2's callbacks report errors as a
/// CFErrorRef *, versions 0 and 1's as a CFStreamError *; version 0's info
/// is a CFStreamClientContext, whose retain and release keep its info.
final class CallbackStream {
    static let readTypeID: UInt = 38, writeTypeID: UInt = 39

    typealias Create = @convention(c) (id?, UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer?
    typealias Finalize = @convention(c) (id?, UnsafeMutableRawPointer?) -> Void
    typealias Open = @convention(c) (id?, UnsafeMutableRawPointer?, UnsafeMutablePointer<UInt8>?, UnsafeMutableRawPointer?) -> UInt8
    typealias OpenCompleted = @convention(c) (id?, UnsafeMutableRawPointer?, UnsafeMutableRawPointer?) -> UInt8
    typealias Read = @convention(c) (id?, UnsafeMutablePointer<UInt8>?, Int, UnsafeMutableRawPointer?, UnsafeMutablePointer<UInt8>?,
                                     UnsafeMutableRawPointer?) -> Int
    typealias GetBuffer = @convention(c) (id?, Int, UnsafeMutablePointer<Int>?, UnsafeMutableRawPointer?, UnsafeMutablePointer<UInt8>?,
                                          UnsafeMutableRawPointer?) -> UnsafePointer<UInt8>?
    typealias Write = @convention(c) (id?, UnsafePointer<UInt8>?, Int, UnsafeMutableRawPointer?, UnsafeMutableRawPointer?) -> Int
    /// canRead and canWrite: (stream, info) before version 2, (stream,
    /// error, info) from it.
    typealias Can = @convention(c) (id?, UnsafeMutableRawPointer?) -> UInt8
    typealias CanReporting = @convention(c) (id?, UnsafeMutableRawPointer?, UnsafeMutableRawPointer?) -> UInt8
    typealias CopyProperty = @convention(c) (id?, id?, UnsafeMutableRawPointer?) -> id?
    typealias SetProperty = @convention(c) (id?, id?, id?, UnsafeMutableRawPointer?) -> UInt8
    typealias RequestEvents = @convention(c) (id?, UInt, UnsafeMutableRawPointer?) -> Void
    typealias Schedule = @convention(c) (id?, id?, id?, UnsafeMutableRawPointer?) -> Void

    /// The callbacks, wherever their version puts them.
    struct Callbacks {
        var version = 0
        var create, finalize, copyDescription, open, openCompleted, transfer, getBuffer, can, close: UnsafeRawPointer?
        var copyProperty, setProperty, requestEvents, schedule, unschedule: UnsafeRawPointer?

        init?(_ pointer: UnsafeRawPointer, input: Bool) {
            version = pointer.load(as: Int.self)
            func slot(_ index: Int) -> UnsafeRawPointer? {
                pointer.load(fromByteOffset: index * DarwinLayout.word, as: UnsafeRawPointer?.self)
            }
            switch (version, input) {
            case (0, true):
                // { version, open, openCompleted, read, getBuffer, canRead,
                // close, copyProperty, schedule, unschedule }
                (open, openCompleted, transfer, getBuffer, can) = (slot(1), slot(2), slot(3), slot(4), slot(5))
                (close, copyProperty, schedule, unschedule) = (slot(6), slot(7), slot(8), slot(9))
            case (0, false):
                // { version, open, openCompleted, write, canWrite, close,
                // copyProperty, schedule, unschedule }
                (open, openCompleted, transfer, can) = (slot(1), slot(2), slot(3), slot(4))
                (close, copyProperty, schedule, unschedule) = (slot(5), slot(6), slot(7), slot(8))
            case (1 ... 2, true):
                // { version, create, finalize, copyDescription, open,
                // openCompleted, read, getBuffer, canRead, close,
                // copyProperty, setProperty, requestEvents, schedule,
                // unschedule }
                (create, finalize, copyDescription) = (slot(1), slot(2), slot(3))
                (open, openCompleted, transfer, getBuffer, can, close) = (slot(4), slot(5), slot(6), slot(7), slot(8), slot(9))
                (copyProperty, setProperty, requestEvents, schedule, unschedule) = (slot(10), slot(11), slot(12), slot(13), slot(14))
            case (1 ... 2, false):
                // The same, with write and canWrite for read, getBuffer and
                // canRead.
                (create, finalize, copyDescription) = (slot(1), slot(2), slot(3))
                (open, openCompleted, transfer, can, close) = (slot(4), slot(5), slot(6), slot(7), slot(8))
                (copyProperty, setProperty, requestEvents, schedule, unschedule) = (slot(9), slot(10), slot(11), slot(12), slot(13))
            default:
                return nil
            }
        }
    }

    let input: Bool
    let callbacks: Callbacks
    /// The stream, not retained: it owns this.
    let object: id
    var info: UnsafeMutableRawPointer?
    /// A version 0 stream's context's release of its info.
    var releaseInfo: InfoContext.Release?
    private var wasOpened = false
    private var closed = false

    init(input: Bool, callbacks: Callbacks, object: id) {
        (self.input, self.callbacks, self.object) = (input, callbacks, object)
    }

    /// As the stream goes: closed if it is open, as on Darwin, then
    /// finalized.
    deinit {
        close()
        if let finalize = callbacks.finalize {
            unsafeBitCast(finalize, to: Finalize.self)(object, info)
        } else if let releaseInfo, let info {
            releaseInfo(info)
        }
    }

    /// A new stream (+1) over the callbacks; NULL for a version there is
    /// none of.
    static func make(input: Bool, _ pointer: UnsafeRawPointer?, _ info: UnsafeMutableRawPointer?) -> id? {
        let cls: Class = input ? Streams.inputClass : Streams.outputClass
        guard let pointer, let callbacks = Callbacks(pointer, input: input),
              let object = Storage.allocate(UnsafeMutableRawPointer(cls)) else { return nil }
        let stream = CallbackStream(input: input, callbacks: callbacks, object: object)
        Storage.set(object, StreamStorage(.callbacks(stream)))
        if callbacks.version == 0 {
            let context = InfoContext(retaining: UnsafeRawPointer(info))
            stream.info = context.info
            stream.releaseInfo = context.release
        } else if let create = callbacks.create {
            stream.info = unsafeBitCast(create, to: Create.self)(object, info)
        } else {
            stream.info = info
        }
        return object
    }

    /// The stream's callbacks, if it has them.
    static func of(_ stream: id?) -> CallbackStream? {
        guard let stream, let storage = Storage.get(stream, as: StreamStorage.self), case .callbacks(let callbackStream) = storage.source else {
            return nil
        }
        return callbackStream
    }

    /// A stream's status, a callback stream that is opening asked first
    /// whether it has opened, as Darwin asks.
    static func status(_ storage: StreamStorage) -> UInt {
        if case .callbacks(let stream) = storage.source { stream.refresh(storage) }
        return storage.status
    }

    /// A CFStreamError's error (+1), or none for error 0: POSIX's domain
    /// (1) and Mac OS's (2) are NSError's; another is the domain Darwin
    /// gives errors it can't name.
    static func error(domain: Int, code: Int32) -> id? {
        guard code != 0 else { return nil }
        let name: id
        switch domain {
        case 1: name = ErrorConstants.NSPOSIXErrorDomainObject
        case 2: name = ErrorConstants.NSOSStatusErrorDomainObject
        default: name = Strings.autoreleased("BogusCFStreamErrorCompatibilityDomain")
        }
        return Errors.make(domain: name, code: Int(code), userInfo: nil)
    }

    /// Calls `body` with room for the error a callback may report; its
    /// result and that error (+1), if there is one.
    private func reporting<T>(_ body: (UnsafeMutableRawPointer) -> T) -> (T, id?) {
        let room = UnsafeMutableRawPointer.allocate(byteCount: 16, alignment: 16)
        room.initializeMemory(as: UInt8.self, repeating: 0, count: 16)
        defer { room.deallocate() }
        let result = body(room)
        if callbacks.version >= 2 { return (result, room.load(as: id?.self)) }
        return (result, Self.error(domain: room.load(as: Int.self), code: room.load(fromByteOffset: DarwinLayout.word, as: Int32.self)))
    }

    /// Fails with `error` (+1), or EIO's when the callback gave none.
    private func fail(_ storage: StreamStorage, _ error: id?) {
        storage.status = StreamStatus.error
        ObjC.release(storage.error)
        storage.error = error ?? Errors.make(domain: ErrorConstants.NSPOSIXErrorDomainObject, code: Int(EIO), userInfo: nil)
        Streams.post(object, storage, StreamEvent.errorOccurred)
    }

    private func didOpen(_ storage: StreamStorage) {
        storage.status = StreamStatus.open
        Streams.post(object, storage, StreamEvent.openCompleted)
    }

    /// Opening: open if the callback says it has, or opening until
    /// openCompleted or the stream's own event says so.
    func open(_ storage: StreamStorage) {
        wasOpened = true
        storage.status = StreamStatus.opening
        guard let open = callbacks.open else { return didOpen(storage) }
        var complete: UInt8 = 0
        let (succeeded, error) = reporting { unsafeBitCast(open, to: Open.self)(object, $0, &complete, info) }
        if succeeded == 0 || error != nil { return fail(storage, error) }
        if complete != 0 { didOpen(storage) }
    }

    /// Asks an opening stream whether it has opened.
    func refresh(_ storage: StreamStorage) {
        guard storage.status == StreamStatus.opening, let openCompleted = callbacks.openCompleted else { return }
        let (complete, error) = reporting { unsafeBitCast(openCompleted, to: OpenCompleted.self)(object, $0, info) }
        if error != nil { return fail(storage, error) }
        if complete != 0 { didOpen(storage) }
    }

    func read(_ storage: StreamStorage, _ buffer: UnsafeMutablePointer<UInt8>?, _ length: Int) -> Int {
        refresh(storage)
        if storage.status == StreamStatus.atEnd { return 0 }
        guard input, storage.status == StreamStatus.open, let read = callbacks.transfer else { return -1 }
        var atEnd: UInt8 = 0
        let (count, error) = reporting { unsafeBitCast(read, to: Read.self)(object, buffer, length, $0, &atEnd, info) }
        if error != nil || count < 0 {
            fail(storage, error)
            return -1
        }
        if atEnd != 0 {
            storage.status = StreamStatus.atEnd
            Streams.post(object, storage, StreamEvent.endEncountered)
        }
        return count
    }

    func write(_ storage: StreamStorage, _ buffer: UnsafePointer<UInt8>?, _ length: Int) -> Int {
        refresh(storage)
        guard !input, storage.status == StreamStatus.open, let write = callbacks.transfer else { return -1 }
        let (count, error) = reporting { unsafeBitCast(write, to: Write.self)(object, buffer, length, $0, info) }
        if error != nil || count < 0 {
            fail(storage, error)
            return -1
        }
        return count
    }

    /// The callback's buffer, for CFReadStreamGetBuffer; NULL, with a count
    /// of 0, from a stream without one.
    func buffer(_ storage: StreamStorage, _ maximum: Int, _ count: UnsafeMutablePointer<Int>?) -> UnsafePointer<UInt8>? {
        refresh(storage)
        if storage.status == StreamStatus.atEnd {
            count?.pointee = 0
            return nil
        }
        guard storage.status == StreamStatus.open else {
            count?.pointee = -1
            return nil
        }
        guard input, let getBuffer = callbacks.getBuffer else {
            count?.pointee = 0
            return nil
        }
        var length = 0
        var atEnd: UInt8 = 0
        let (pointer, error) = reporting { unsafeBitCast(getBuffer, to: GetBuffer.self)(object, maximum, &length, $0, &atEnd, info) }
        if error != nil {
            fail(storage, error)
            count?.pointee = -1
            return nil
        }
        count?.pointee = length
        if atEnd != 0 {
            storage.status = StreamStatus.atEnd
            Streams.post(object, storage, StreamEvent.endEncountered)
        }
        return pointer
    }

    /// canRead or canWrite; true without one, as Darwin can't know without
    /// trying.
    func canTransfer(_ storage: StreamStorage) -> Bool {
        refresh(storage)
        guard storage.status == StreamStatus.open else { return false }
        guard let can = callbacks.can else { return true }
        guard callbacks.version >= 2 else { return unsafeBitCast(can, to: Can.self)(object, info) != 0 }
        let (ready, error) = reporting { unsafeBitCast(can, to: CanReporting.self)(object, $0, info) }
        if error != nil {
            fail(storage, error)
            return false
        }
        return ready != 0
    }

    /// Once, if it was opened.
    func close() {
        guard wasOpened, !closed else { return }
        closed = true
        if let close = callbacks.close { unsafeBitCast(close, to: Finalize.self)(object, info) }
    }

    /// The callback's property, +1.
    func copyProperty(_ key: id?) -> id? {
        callbacks.copyProperty.flatMap { unsafeBitCast($0, to: CopyProperty.self)(object, key, info) }
    }

    func setProperty(_ key: id?, _ value: id?) -> Bool {
        guard let setProperty = callbacks.setProperty else { return false }
        return unsafeBitCast(setProperty, to: SetProperty.self)(object, key, value, info) != 0
    }

    /// The events the stream's client asked for.
    func requestEvents(_ events: UInt) {
        if let requestEvents = callbacks.requestEvents { unsafeBitCast(requestEvents, to: RequestEvents.self)(object, events, info) }
    }

    func schedule(_ runLoop: id?, _ mode: id?, adding: Bool) {
        guard let schedule = adding ? callbacks.schedule : callbacks.unschedule else { return }
        unsafeBitCast(schedule, to: Schedule.self)(object, runLoop, mode, info)
    }

    /// CFReadStreamSignalEvent and CFWriteStreamSignalEvent: the stream's
    /// status follows the events, an error's (a CFStreamError * for a
    /// stream of callbacks before version 2, else a CFErrorRef) becomes the
    /// stream's, and the client and delegate are told of each.
    static func signal(_ object: id?, _ event: UInt, _ error: UnsafeRawPointer?) {
        guard let object, let storage = Storage.get(object, as: StreamStorage.self) else { return }
        if event & StreamEvent.openCompleted != 0, storage.status == StreamStatus.opening { storage.status = StreamStatus.open }
        if event & StreamEvent.endEncountered != 0, storage.status == StreamStatus.open { storage.status = StreamStatus.atEnd }
        if event & StreamEvent.errorOccurred != 0 {
            storage.status = StreamStatus.error
            var made: id?
            if let error {
                if let stream = of(object), stream.callbacks.version < 2 {
                    made = Self.error(domain: error.load(as: Int.self), code: error.load(fromByteOffset: DarwinLayout.word, as: Int32.self))
                } else {
                    made = ObjC.retain(UnsafeMutableRawPointer(mutating: error))
                }
            }
            if let made {
                ObjC.release(storage.error)
                storage.error = made
            }
        }
        let events: [UInt] = [StreamEvent.openCompleted, StreamEvent.hasBytesAvailable, StreamEvent.hasSpaceAvailable,
                              StreamEvent.errorOccurred, StreamEvent.endEncountered]
        for each in events where event & each != 0 { Streams.post(object, storage, each) }
    }
}

// MARK: - Making streams

@c(_CFReadStreamGetTypeID) public func CFReadStreamGetTypeID() -> UInt { CallbackStream.readTypeID }
@c(_CFWriteStreamGetTypeID) public func CFWriteStreamGetTypeID() -> UInt { CallbackStream.writeTypeID }

/// A +1 stream of a copy of the data's bytes.
@c(_CFReadStreamCreateWithData)
public func CFReadStreamCreateWithData(_ allocator: UnsafeRawPointer?, _ data: id?) -> id? {
    guard let data, let object = Storage.allocate(UnsafeMutableRawPointer(Streams.inputClass)) else { return nil }
    Storage.set(object, StreamStorage(.data(DataObjects.data(data))))
    return object
}

/// A +1 stream writing into the caller's buffer, at its end once it is full.
@c(_CFWriteStreamCreateWithBuffer)
public func CFWriteStreamCreateWithBuffer(_ allocator: UnsafeRawPointer?, _ buffer: UnsafeMutablePointer<UInt8>?, _ capacity: Int) -> id? {
    guard let buffer, let object = Storage.allocate(UnsafeMutableRawPointer(Streams.outputClass)) else { return nil }
    Storage.set(object, StreamStorage(.buffer(buffer, max(capacity, 0))))
    return object
}

/// A +1 stream writing to memory, which kCFStreamPropertyDataWritten gives.
/// The buffers are Swift's, whatever allocator is named.
@c(_CFWriteStreamCreateWithAllocatedBuffers)
public func CFWriteStreamCreateWithAllocatedBuffers(_ allocator: UnsafeRawPointer?, _ bufferAllocator: UnsafeRawPointer?) -> id? {
    guard let object = Storage.allocate(UnsafeMutableRawPointer(Streams.outputClass)) else { return nil }
    Storage.set(object, StreamStorage(.memory))
    return object
}

/// A +1 stream the callbacks implement (CFStreamAbstract.h's
/// CFReadStreamCallBacks, of version 0, 1 or 2), its info as their create
/// gives it.
@c(_CFReadStreamCreate)
public func CFReadStreamCreate(_ allocator: UnsafeRawPointer?, _ callbacks: UnsafeRawPointer?, _ info: UnsafeMutableRawPointer?) -> id? {
    CallbackStream.make(input: true, callbacks, info)
}

/// A +1 stream the callbacks implement (CFWriteStreamCallBacks).
@c(_CFWriteStreamCreate)
public func CFWriteStreamCreate(_ allocator: UnsafeRawPointer?, _ callbacks: UnsafeRawPointer?, _ info: UnsafeMutableRawPointer?) -> id? {
    CallbackStream.make(input: false, callbacks, info)
}

/// The info a stream of callbacks passes them; NULL for another stream.
@c(_CFReadStreamGetInfoPointer)
public func CFReadStreamGetInfoPointer(_ stream: id?) -> UnsafeMutableRawPointer? { CallbackStream.of(stream)?.info }

@c(_CFWriteStreamGetInfoPointer)
public func CFWriteStreamGetInfoPointer(_ stream: id?) -> UnsafeMutableRawPointer? { CallbackStream.of(stream)?.info }

@c(_CFReadStreamSignalEvent)
public func CFReadStreamSignalEvent(_ stream: id?, _ event: UInt, _ error: UnsafeRawPointer?) {
    CallbackStream.signal(stream, event, error)
}

@c(_CFWriteStreamSignalEvent)
public func CFWriteStreamSignalEvent(_ stream: id?, _ event: UInt, _ error: UnsafeRawPointer?) {
    CallbackStream.signal(stream, event, error)
}

// MARK: - Reading a buffer

/// The next bytes of the stream's own buffer, up to `maximum` (all of them
/// when negative), which the stream moves past: a data stream's, or a
/// stream of callbacks' getBuffer's. NULL with a count of 0 from a stream
/// with no buffer to lend, or -1 from one that isn't open.
@c(_CFReadStreamGetBuffer)
public func CFReadStreamGetBuffer(_ stream: id?, _ maximum: Int, _ count: UnsafeMutablePointer<Int>?) -> UnsafePointer<UInt8>? {
    guard let stream else {
        count?.pointee = -1
        return nil
    }
    let storage = Streams.storage(stream)
    switch storage.source {
    case .callbacks(let callbackStream):
        return callbackStream.buffer(storage, maximum, count)
    case .data(let data):
        return dataBuffer(stream, storage, data, maximum, count)
    default:
        let readable = storage.status == StreamStatus.open || storage.status == StreamStatus.atEnd
        count?.pointee = readable ? 0 : -1
        return nil
    }
}

/// A data stream's bytes, from a CFData of them kept with the stream so
/// they stay where they are.
private func dataBuffer(_ stream: id, _ storage: StreamStorage, _ data: Data, _ maximum: Int,
                        _ count: UnsafeMutablePointer<Int>?) -> UnsafePointer<UInt8>? {
    if storage.status == StreamStatus.atEnd {
        count?.pointee = 0
        return nil
    }
    guard storage.status == StreamStatus.open else {
        count?.pointee = -1
        return nil
    }
    let key = "_PerryCFReadStreamGetBuffer"
    if storage.properties[key] == nil {
        storage.properties[key] = data.withUnsafeBytes { CFDataCreate(nil, $0.baseAddress?.assumingMemoryBound(to: UInt8.self), $0.count) }
    }
    let remaining = data.count - storage.offset
    let length = maximum < 0 ? remaining : min(maximum, remaining)
    guard length > 0, let base = CFDataGetBytePtr(storage.properties[key]) else {
        count?.pointee = 0
        return nil
    }
    let pointer = (base + storage.offset).assumingMemoryBound(to: UInt8.self)
    storage.offset += length
    count?.pointee = length
    if storage.offset >= data.count {
        storage.status = StreamStatus.atEnd
        Streams.post(stream, storage, StreamEvent.endEncountered)
    } else {
        Streams.post(stream, storage, StreamEvent.hasBytesAvailable)
    }
    return pointer
}

// MARK: - Errors

/// The stream's error as a CFStreamError { CFIndex domain; SInt32 error },
/// which is returned in the same two registers as a CFRange of the domain
/// and the error: POSIX's (1), Mac OS's (2) or, for any other, the custom
/// domain (-1). { 0, 0 } for no error.
private func streamError(_ stream: id?) -> CFRange {
    guard let stream, let parts = Errors.parts(ObjC.send(stream, ObjC.selector("streamError"))) else {
        return CFRange(location: 0, length: 0)
    }
    let name = Strings.value(of: parts.domain)
    let domain = name == ErrorConstants.NSPOSIXErrorDomain ? 1 : name == ErrorConstants.NSOSStatusErrorDomain ? 2 : -1
    return CFRange(location: domain, length: Int(Int32(truncatingIfNeeded: parts.code)))
}

@c(_CFReadStreamGetError) public func CFReadStreamGetError(_ stream: id?) -> CFRange { streamError(stream) }
@c(_CFWriteStreamGetError) public func CFWriteStreamGetError(_ stream: id?) -> CFRange { streamError(stream) }

// MARK: - Dispatch queues

/// Events go to the queue (retained) as well as to the run loops the
/// stream is scheduled on; NULL stops them going to one. A stream of
/// callbacks isn't told through its schedule callback, as Darwin's
/// private run loop for queues is not here.
private func setQueue(_ stream: id?, _ queue: id?) {
    guard let stream else { return }
    let storage = Streams.storage(stream)
    let old = storage.queue
    storage.queue = queue.flatMap { ObjC.retain($0) }
    ObjC.release(old)
}

/// The queue, +1, or NULL.
private func copyQueue(_ stream: id?) -> id? {
    guard let stream else { return nil }
    return ObjC.retain(Streams.storage(stream).queue)
}

@c(_CFReadStreamSetDispatchQueue) public func CFReadStreamSetDispatchQueue(_ stream: id?, _ queue: id?) { setQueue(stream, queue) }
@c(_CFWriteStreamSetDispatchQueue) public func CFWriteStreamSetDispatchQueue(_ stream: id?, _ queue: id?) { setQueue(stream, queue) }
@c(_CFReadStreamCopyDispatchQueue) public func CFReadStreamCopyDispatchQueue(_ stream: id?) -> id? { copyQueue(stream) }
@c(_CFWriteStreamCopyDispatchQueue) public func CFWriteStreamCopyDispatchQueue(_ stream: id?) -> id? { copyQueue(stream) }

// MARK: - Property lists

/// kCFPropertyListReadStreamError and kCFPropertyListWriteStreamError.
private let readStreamError = 3842, writeStreamError = 3851

/// Up to `length` bytes of an open stream, or all it has for 0; nil when
/// reading fails.
private func readAll(_ stream: id?, _ length: Int) -> [UInt8]? {
    guard let stream else { return nil }
    var bytes: [UInt8] = []
    var chunk = [UInt8](repeating: 0, count: 65536)
    while length <= 0 || bytes.count < length {
        let wanted = length > 0 ? min(chunk.count, length - bytes.count) : chunk.count
        let count = chunk.withUnsafeMutableBufferPointer { CFReadStreamRead(stream, $0.baseAddress, wanted) }
        if count < 0 { return nil }
        if count == 0 { break }
        bytes.append(contentsOf: chunk.prefix(count))
    }
    return bytes
}

/// Writes all of the data to an open stream.
private func writeAll(_ stream: id?, _ data: id) -> Bool {
    guard let stream else { return false }
    let length = CFDataGetLength(data)
    guard length > 0 else { return true }
    guard let base = CFDataGetBytePtr(data)?.assumingMemoryBound(to: UInt8.self) else { return false }
    var written = 0
    while written < length {
        let count = CFWriteStreamWrite(stream, base + written, length - written)
        if count <= 0 { return false }
        written += count
    }
    return true
}

/// A property list (+1) read from an open stream: `length` bytes of it, or
/// all it has for 0, read as CFPropertyListCreateWithData reads. The error,
/// +1, is kCFPropertyListReadStreamError's when the stream can't be read.
@c(_CFPropertyListCreateWithStream)
public func CFPropertyListCreateWithStream(_ allocator: UnsafeRawPointer?, _ stream: id?, _ length: Int, _ options: UInt,
                                           _ format: UnsafeMutablePointer<UInt>?, _ error: UnsafeMutablePointer<id?>?) -> id? {
    error?.pointee = nil
    guard let bytes = readAll(stream, length) else {
        error?.pointee = Errors.make(domain: Errors.cocoaDomain, code: readStreamError, userInfo: nil)
        return nil
    }
    guard let data = bytes.withUnsafeBufferPointer({ CFDataCreate(nil, $0.baseAddress, $0.count) }) else { return nil }
    defer { ObjC.release(data) }
    return CFPropertyListCreateWithData(nil, data, options, format, error)
}

/// The older form, reporting an error as a string, +1.
@c(_CFPropertyListCreateFromStream)
public func CFPropertyListCreateFromStream(_ allocator: UnsafeRawPointer?, _ stream: id?, _ length: Int, _ options: UInt,
                                           _ format: UnsafeMutablePointer<UInt>?, _ errorString: UnsafeMutablePointer<id?>?) -> id? {
    var error: id?
    let made = CFPropertyListCreateWithStream(allocator, stream, length, options, format, &error)
    if let errorString {
        errorString.pointee = error.flatMap { ObjC.retain(ObjC.send($0, ObjC.selector("localizedDescription"))) }
    }
    ObjC.release(error)
    return made
}

/// Writes the property list to an open stream in a format, as
/// CFPropertyListCreateData writes it: the bytes written, or 0 with the
/// error (+1), kCFPropertyListWriteStreamError's when the stream won't take
/// them.
@c(_CFPropertyListWrite)
public func CFPropertyListWrite(_ plist: id?, _ stream: id?, _ format: UInt, _ options: UInt, _ error: UnsafeMutablePointer<id?>?) -> Int {
    error?.pointee = nil
    guard let data = CFPropertyListCreateData(nil, plist, format, options, error) else { return 0 }
    defer { ObjC.release(data) }
    guard writeAll(stream, data) else {
        error?.pointee = Errors.make(domain: Errors.cocoaDomain, code: writeStreamError, userInfo: nil)
        return 0
    }
    return CFDataGetLength(data)
}

/// The older form, reporting an error as a string, +1.
@c(_CFPropertyListWriteToStream)
public func CFPropertyListWriteToStream(_ plist: id?, _ stream: id?, _ format: UInt, _ errorString: UnsafeMutablePointer<id?>?) -> Int {
    var error: id?
    let written = CFPropertyListWrite(plist, stream, format, 0, &error)
    if let errorString {
        errorString.pointee = error.flatMap { ObjC.retain(ObjC.send($0, ObjC.selector("localizedDescription"))) }
    }
    ObjC.release(error)
    return written
}
