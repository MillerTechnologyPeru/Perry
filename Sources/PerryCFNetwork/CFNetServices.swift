import FoundationEssentials
import Glibc
import PerryObjCInterop

// CFNetService, CFNetServiceBrowser and CFNetServiceMonitor: CFNetwork's
// Bonjour, over the dns_sd API that Avahi's compatibility library provides
// on Linux (libdns_sd.so.1), opened at run time. Asynchronous operations —
// a client callback set and the object scheduled — run a worker thread
// that waits on the daemon's socket and performs the callbacks onto the
// scheduled run loop; without a client, registering and resolving block,
// as CFNetwork's do.

// MARK: - The dns_sd API

/// The dns_sd functions, bound on first use.
enum CFDNSSD {
    typealias Ref = UnsafeMutableRawPointer
    typealias BrowseReply = @convention(c) (
        Ref?, UInt32, UInt32, Int32, UnsafePointer<CChar>?, UnsafePointer<CChar>?, UnsafePointer<CChar>?,
        UnsafeMutableRawPointer?
    ) -> Void
    typealias ResolveReply = @convention(c) (
        Ref?, UInt32, UInt32, Int32, UnsafePointer<CChar>?, UnsafePointer<CChar>?, UInt16, UInt16,
        UnsafePointer<UInt8>?, UnsafeMutableRawPointer?
    ) -> Void
    typealias RegisterReply = @convention(c) (
        Ref?, UInt32, Int32, UnsafePointer<CChar>?, UnsafePointer<CChar>?, UnsafePointer<CChar>?,
        UnsafeMutableRawPointer?
    ) -> Void
    typealias QueryReply = @convention(c) (
        Ref?, UInt32, UInt32, Int32, UnsafePointer<CChar>?, UInt16, UInt16, UInt16, UnsafeRawPointer?, UInt32,
        UnsafeMutableRawPointer?
    ) -> Void
    typealias DomainReply = @convention(c) (
        Ref?, UInt32, UInt32, Int32, UnsafePointer<CChar>?, UnsafeMutableRawPointer?
    ) -> Void

    // DNSServiceFlags.
    static let moreComing: UInt32 = 0x1
    static let add: UInt32 = 0x2
    static let browseDomains: UInt32 = 0x40
    static let registrationDomains: UInt32 = 0x80
    static let noAutoRename: UInt32 = 0x4000

    // Resource record types, and the Internet class.
    static let typeA: UInt16 = 1
    static let typeTXT: UInt16 = 16
    static let typeAAAA: UInt16 = 28
    static let classIN: UInt16 = 1

    nonisolated(unsafe) private static let handle: UnsafeMutableRawPointer? =
        dlopen("libdns_sd.so.1", RTLD_NOW) ?? dlopen("libdns_sd.so", RTLD_NOW)

    static var available: Bool { handle != nil }

    private static func bind<T>(_ name: String, _ type: T.Type) -> T? {
        guard let handle, let symbol = dlsym(handle, name) else { return nil }
        return unsafeBitCast(symbol, to: T.self)
    }

    nonisolated(unsafe) static let browse = bind("DNSServiceBrowse", (@convention(c) (
        UnsafeMutablePointer<Ref?>, UInt32, UInt32, UnsafePointer<CChar>?, UnsafePointer<CChar>?, BrowseReply,
        UnsafeMutableRawPointer?
    ) -> Int32).self)
    nonisolated(unsafe) static let resolve = bind("DNSServiceResolve", (@convention(c) (
        UnsafeMutablePointer<Ref?>, UInt32, UInt32, UnsafePointer<CChar>?, UnsafePointer<CChar>?,
        UnsafePointer<CChar>?, ResolveReply, UnsafeMutableRawPointer?
    ) -> Int32).self)
    nonisolated(unsafe) static let register = bind("DNSServiceRegister", (@convention(c) (
        UnsafeMutablePointer<Ref?>, UInt32, UInt32, UnsafePointer<CChar>?, UnsafePointer<CChar>?,
        UnsafePointer<CChar>?, UnsafePointer<CChar>?, UInt16, UInt16, UnsafeRawPointer?, RegisterReply?,
        UnsafeMutableRawPointer?
    ) -> Int32).self)
    nonisolated(unsafe) static let queryRecord = bind("DNSServiceQueryRecord", (@convention(c) (
        UnsafeMutablePointer<Ref?>, UInt32, UInt32, UnsafePointer<CChar>?, UInt16, UInt16, QueryReply,
        UnsafeMutableRawPointer?
    ) -> Int32).self)
    nonisolated(unsafe) static let enumerateDomains = bind("DNSServiceEnumerateDomains", (@convention(c) (
        UnsafeMutablePointer<Ref?>, UInt32, UInt32, DomainReply, UnsafeMutableRawPointer?
    ) -> Int32).self)
    nonisolated(unsafe) static let constructFullName = bind("DNSServiceConstructFullName", (@convention(c) (
        UnsafeMutablePointer<CChar>?, UnsafePointer<CChar>?, UnsafePointer<CChar>?, UnsafePointer<CChar>?
    ) -> Int32).self)
    nonisolated(unsafe) static let socket = bind("DNSServiceRefSockFD", (@convention(c) (Ref?) -> Int32).self)
    nonisolated(unsafe) static let process = bind("DNSServiceProcessResult", (@convention(c) (Ref?) -> Int32).self)
    nonisolated(unsafe) static let deallocate = bind("DNSServiceRefDeallocate", (@convention(c) (Ref?) -> Void).self)
}

// MARK: - Common machinery

/// A CFStreamError written through its pointer: a CFIndex domain, then an
/// SInt32 code.
enum StreamError {
    /// kCFStreamErrorDomainNetServices.
    static let domain = 10

    static func write(_ pointer: UnsafeMutableRawPointer?, code: Int32) {
        guard let pointer else { return }
        pointer.storeBytes(of: code == 0 ? 0 : domain, as: Int.self)
        pointer.storeBytes(of: code, toByteOffset: 8, as: Int32.self)
    }
}

/// CFNetServices error codes, and other values the callbacks hear.
enum CFNetServices {
    static let unknownError: Int32 = -72000
    static let collisionError: Int32 = -72001
    static let activityInProgress: Int32 = -72003
    static let badArgumentError: Int32 = -72004
    static let cancelledError: Int32 = -72005
    static let timeoutError: Int32 = -72007

    // The browser callback's flags.
    static let flagMoreComing: UInt = 1
    static let flagIsDomain: UInt = 2
    static let flagRemove: UInt = 8

    /// A CFNetServices code for a dns_sd error.
    static func code(_ error: Int32) -> Int32 {
        switch error {
        case -65548: return collisionError     // kDNSServiceErr_NameConflict
        case -65540: return badArgumentError   // kDNSServiceErr_BadParam
        case -65554: return timeoutError       // kDNSServiceErr_Timeout
        default: return unknownError
        }
    }

    /// With a trailing dot, as Darwin reports types, domains and hosts.
    static func dotted(_ name: String) -> String { name.hasSuffix(".") ? name : name + "." }

    /// Without one, as Avahi matches them.
    static func undotted(_ name: String) -> String { name.hasSuffix(".") ? String(name.dropLast()) : name }

    /// Whether a type names a service and protocol ("_music._tcp").
    static func isValidType(_ type: String) -> Bool {
        let base = type.split(separator: ",", maxSplits: 1, omittingEmptySubsequences: false)[0]
        let labels = undotted(String(base)).split(separator: ".", omittingEmptySubsequences: false)
        guard labels.count >= 2 else { return false }
        let service = labels[labels.count - 2], proto = labels[labels.count - 1]
        return service.count > 1 && service.hasPrefix("_") && !service.contains(" ")
            && (proto == "_tcp" || proto == "_udp")
    }

    /// The time by the monotonic clock, in seconds.
    static func now() -> Double {
        var time = timespec()
        clock_gettime(CLOCK_MONOTONIC, &time)
        return Double(time.tv_sec) + Double(time.tv_nsec) / 1_000_000_000
    }

    /// A Darwin sockaddr_in: the length and family lead, the port is in
    /// network byte order.
    static func socketAddress(ipv4 address: UnsafeRawPointer, port: Int32) -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: 16)
        bytes[0] = 16
        bytes[1] = 2 // Darwin's AF_INET
        bytes[2] = UInt8((port >> 8) & 0xff)
        bytes[3] = UInt8(port & 0xff)
        for index in 0..<4 { bytes[4 + index] = address.load(fromByteOffset: index, as: UInt8.self) }
        return bytes
    }

    /// A Darwin sockaddr_in6, 28 bytes; a link-local address keeps the
    /// interface it arrived on as its scope.
    static func socketAddress(ipv6 address: UnsafeRawPointer, port: Int32, interface: UInt32) -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: 28)
        bytes[0] = 28
        bytes[1] = 30 // Darwin's AF_INET6
        bytes[2] = UInt8((port >> 8) & 0xff)
        bytes[3] = UInt8(port & 0xff)
        for index in 0..<16 { bytes[8 + index] = address.load(fromByteOffset: index, as: UInt8.self) }
        if bytes[8] == 0xfe, bytes[9] & 0xc0 == 0x80 {
            withUnsafeBytes(of: interface.littleEndian) { scope in
                for index in 0..<4 { bytes[24 + index] = scope[index] }
            }
        }
        return bytes
    }

    /// The full name a service's records live under, escaped as dns_sd
    /// escapes it.
    static func fullName(name: String, type: String, domain: String) -> String? {
        guard let construct = CFDNSSD.constructFullName else { return nil }
        var buffer = [CChar](repeating: 0, count: 1009)
        let made = name.withCString { name in
            type.withCString { type in
                domain.withCString { domain in
                    construct(&buffer, name, type, domain)
                }
            }
        }
        guard made == 0 else { return nil }
        return String(cString: buffer)
    }
}

/// A client's callback and context: the info pointer, retained and
/// released as the context asks.
struct NetClient {
    let callback: UnsafeRawPointer
    let info: UnsafeMutableRawPointer?
    let release: (@convention(c) (UnsafeMutableRawPointer?) -> Void)?

    /// Reads a CFNetServiceClientContext: version, info, retain, release,
    /// copyDescription.
    init?(callback: UnsafeRawPointer?, context: UnsafeRawPointer?) {
        guard let callback else { return nil }
        self.callback = callback
        var info = context?.load(fromByteOffset: 8, as: UnsafeMutableRawPointer?.self)
        if let retain = context?.load(fromByteOffset: 16, as: (@convention(c) (UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer?)?.self) {
            info = retain(info)
        }
        self.info = info
        release = context?.load(fromByteOffset: 24, as: (@convention(c) (UnsafeMutableRawPointer?) -> Void)?.self)
    }

    func releaseInfo() {
        release?(info)
    }
}

/// One registration, resolution, search or monitor: its dns_sd requests,
/// the worker thread waiting on their sockets (asynchronous operations
/// only), and the callbacks it performs onto the scheduled run loop.
final class CFNetOperation {
    /// The CFNetService, browser or monitor, kept alive while the
    /// operation runs.
    let object: UnsafeMutableRawPointer
    private let mutex = UnsafeMutablePointer<pthread_mutex_t>.allocate(capacity: 1)
    private var pending: [() -> Void] = []
    private var stopFlag = false
    private var exited = false
    private var thread: pthread_t?
    /// Where callbacks are delivered: the schedules of the owning object.
    var schedules: () -> [(loop: UnsafeMutableRawPointer, mode: UnsafeMutableRawPointer?)] = { [] }

    /// The requests the worker waits on.
    var refs: [CFDNSSD.Ref] = []

    /// When a resolution gives up, and when its addresses are delivered.
    var deadline: Double?
    var grace: Double?
    /// A reply reported this error; the worker ends when it is not 0.
    var failed: Int32 = 0

    // A resolution's results.
    var hostName: String?
    var port: Int32 = 0
    var txt: [UInt8]?
    var addresses: [[UInt8]] = []
    var delivered = false

    /// A search's services by "name|type|domain", counting the interfaces
    /// each was found on.
    var found: [String: Int] = [:]

    /// Processes one ready request; false ends the operation.
    var step: ((CFNetOperation, CFDNSSD.Ref) -> Bool)?
    /// Runs when the clock passes `deadline` or `grace`; false ends it.
    var timePassed: ((CFNetOperation) -> Bool)?

    init(object: UnsafeMutableRawPointer) {
        self.object = ObjCRuntime.retain(object)!
        pthread_mutex_init(mutex, nil)
    }

    deinit {
        pthread_mutex_destroy(mutex)
        mutex.deallocate()
    }

    /// Queues a callback and asks a scheduled run loop to deliver it; the
    /// events wait when nothing is scheduled yet.
    func enqueue(_ event: @escaping () -> Void) {
        pthread_mutex_lock(mutex)
        pending.append(event)
        pthread_mutex_unlock(mutex)
        deliverSoon()
    }

    /// Performs the queued events onto the first scheduled run loop.
    func deliverSoon() {
        guard let (loop, mode) = schedules().first else { return }
        let block = Closures.block { [self] in deliver() }
        RunLoopCalls.performBlock(loop, mode, block.objcObject)
        RunLoopCalls.wakeUp(loop)
    }

    /// Runs the queued events, in order.
    func deliver() {
        pthread_mutex_lock(mutex)
        let events = pending
        pending = []
        pthread_mutex_unlock(mutex)
        for event in events { event() }
    }

    var stopped: Bool {
        pthread_mutex_lock(mutex)
        defer { pthread_mutex_unlock(mutex) }
        return stopFlag
    }

    /// Starts the worker thread, for an asynchronous operation.
    func start() {
        let context = Unmanaged.passRetained(self).toOpaque()
        var worker = pthread_t()
        if pthread_create(&worker, nil, { context in
            let operation = Unmanaged<CFNetOperation>.fromOpaque(context!).takeRetainedValue()
            while operation.spin() {}
            operation.teardown()
            return nil
        }, context) == 0 {
            thread = worker
        } else {
            Unmanaged<CFNetOperation>.fromOpaque(context).release()
            teardown()
        }
    }

    /// One pass of the wait: at most 50 ms on every request's socket, the
    /// ready ones processed — their replies' callbacks run here — and the
    /// clock watched. False when the operation is over.
    func spin() -> Bool {
        if stopped { return false }
        var files = refs.map { pollfd(fd: CFDNSSD.socket?($0) ?? -1, events: Int16(POLLIN), revents: 0) }
        let ready = files.withUnsafeMutableBufferPointer { poll($0.baseAddress, nfds_t($0.count), 50) }
        if stopped { return false }
        if ready > 0 {
            for (index, file) in files.enumerated() where file.revents & Int16(POLLIN) != 0 {
                guard index < refs.count, let step else { continue }
                if !step(self, refs[index]) || failed != 0 { return false }
            }
        }
        if let timePassed, let soonest = [deadline, grace].compactMap({ $0 }).min(),
           CFNetServices.now() >= soonest, !timePassed(self) {
            return false
        }
        return true
    }

    /// Ends the operation and waits for the worker, so its requests are
    /// gone before the caller goes on.
    func stop() {
        pthread_mutex_lock(mutex)
        stopFlag = true
        let started = thread != nil
        let done = exited
        pthread_mutex_unlock(mutex)
        if started {
            if let thread { pthread_join(thread, nil) }
            thread = nil
        } else if !done {
            teardown()
        }
    }

    /// Releases what the operation holds; on the worker as it ends, or in
    /// stop() for an operation that ran inline.
    func teardown() {
        for ref in refs { CFDNSSD.deallocate?(ref) }
        refs = []
        pthread_mutex_lock(mutex)
        exited = true
        pthread_mutex_unlock(mutex)
        ObjCRuntime.release(object)
    }
}

/// The run loop functions callbacks are delivered through, bound from
/// CoreFoundation at startup.
enum RunLoopCalls {
    typealias PerformBlock = @convention(c) (UnsafeMutableRawPointer?, UnsafeMutableRawPointer?, UnsafeMutableRawPointer?) -> Void
    typealias WakeUp = @convention(c) (UnsafeMutableRawPointer?) -> Void
    nonisolated(unsafe) static var performBlock: PerformBlock!
    nonisolated(unsafe) static var wakeUp: WakeUp!

    static func load(_ lookup: (String, String) -> UnsafeMutableRawPointer?) -> Bool {
        let coreFoundation = "/System/Library/Frameworks/CoreFoundation.framework/CoreFoundation"
        guard let perform = lookup(coreFoundation, "_CFRunLoopPerformBlock"),
              let wake = lookup(coreFoundation, "_CFRunLoopWakeUp") else { return false }
        performBlock = unsafeBitCast(perform, to: PerformBlock.self)
        wakeUp = unsafeBitCast(wake, to: WakeUp.self)
        return true
    }
}

/// NSNull, for TXT entries that are bare keys.
@ObjCWrapper("NSNull")
class NSNull: NSObject {
    @ObjCClassMethod("null") static func null() -> NSObject
}

// MARK: - CFNetService

final class CFServiceState {
    var domain: String
    var type: String
    var name: String
    var port: Int32
    // Retained objects the Get functions return.
    var domainObject: UnsafeMutableRawPointer?
    var typeObject: UnsafeMutableRawPointer?
    var nameObject: UnsafeMutableRawPointer?
    var targetHost: UnsafeMutableRawPointer?
    var addressArray: UnsafeMutableRawPointer?
    var txtData: UnsafeMutableRawPointer?
    var client: NetClient?
    var schedules: [(loop: UnsafeMutableRawPointer, mode: UnsafeMutableRawPointer?)] = []
    var operation: CFNetOperation?

    init(domain: String, type: String, name: String, port: Int32) {
        self.domain = domain
        self.type = type
        self.name = name
        self.port = port
        domainObject = ObjCRuntime.retain(NSObject.string(domain).objcObject)
        typeObject = ObjCRuntime.retain(NSObject.string(type).objcObject)
        nameObject = ObjCRuntime.retain(NSObject.string(name).objcObject)
    }

    /// Renames after registration: the name and domain the daemon chose.
    func update(name: String?, domain: String?) {
        if let name {
            self.name = name
            ObjCRuntime.release(nameObject)
            nameObject = ObjCRuntime.retain(NSObject.string(name).objcObject)
        }
        if let domain {
            self.domain = domain
            ObjCRuntime.release(domainObject)
            domainObject = ObjCRuntime.retain(NSObject.string(domain).objcObject)
        }
    }

    func releaseObjects() {
        for object in [domainObject, typeObject, nameObject, targetHost, addressArray, txtData] {
            ObjCRuntime.release(object)
        }
        (domainObject, typeObject, nameObject, targetHost, addressArray, txtData) = (nil, nil, nil, nil, nil, nil)
        for (loop, mode) in schedules {
            ObjCRuntime.release(loop)
            ObjCRuntime.release(mode)
        }
        schedules = []
        client?.releaseInfo()
        client = nil
    }
}

/// The CFNetServiceRef type: a CF object of CFNetwork's own.
@ObjCClass("_PerryCFNetService")
final class CFNetService: NSObject {
    static let states = StateTable<CFServiceState>()

    var state: CFServiceState? { CFNetService.states.get(objcObject) }

    @ObjCMethod("dealloc")
    func dealloc() {
        state?.operation?.stop()
        state?.releaseObjects()
        CFNetService.states.remove(objcObject)
        ObjCRuntime.superDealloc(objcObject, definedOn: CFNetService.objCClass.pointer)
    }

    @ObjCMethod("_cfTypeID") func cfTypeID() -> UInt { 0x43_01 }

    /// A new service (+1).
    static func make(domain: String, type: String, name: String, port: Int32) -> UnsafeMutableRawPointer {
        let object = ObjCRuntime.retain(objCClass.autoreleasedInstance().objcObject)!
        states.set(object, CFServiceState(domain: domain, type: type, name: name, port: port))
        return object
    }

    static func state(_ object: UnsafeMutableRawPointer?) -> CFServiceState? {
        object.flatMap { states.get($0) }
    }
}

/// The service's callback, called on the scheduled run loop.
private func callClient(_ service: UnsafeMutableRawPointer, _ code: Int32) {
    guard let state = CFNetService.state(service), let client = state.client else { return }
    typealias Callback = @convention(c) (UnsafeMutableRawPointer?, UnsafeMutableRawPointer?, UnsafeMutableRawPointer?) -> Void
    var error: (Int, Int32) = (code == 0 ? 0 : StreamError.domain, code)
    withUnsafeMutableBytes(of: &error) { bytes in
        unsafeBitCast(client.callback, to: Callback.self)(service, bytes.baseAddress, client.info)
    }
}

@c(_CFNetServiceGetTypeID)
public func CFNetServiceGetTypeID() -> UInt { 0x43_01 }

@c(_CFNetServiceCreate)
public func CFNetServiceCreate(_ allocator: UnsafeMutableRawPointer?, _ domain: UnsafeMutableRawPointer?,
                               _ type: UnsafeMutableRawPointer?, _ name: UnsafeMutableRawPointer?,
                               _ port: Int32) -> UnsafeMutableRawPointer? {
    CFNetService.make(domain: domain.map { NSObject(objCArgument: $0).stringValue } ?? "",
                      type: type.map { NSObject(objCArgument: $0).stringValue } ?? "",
                      name: name.map { NSObject(objCArgument: $0).stringValue } ?? "", port: port)
}

@c(_CFNetServiceCreateCopy)
public func CFNetServiceCreateCopy(_ allocator: UnsafeMutableRawPointer?,
                                   _ service: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer? {
    guard let state = CFNetService.state(service) else { return nil }
    let copy = CFNetService.make(domain: state.domain, type: state.type, name: state.name, port: state.port)
    if let txt = state.txtData, let data = ObjCRuntime.retain(txt) {
        CFNetService.state(copy)?.txtData = data
    }
    return copy
}

@c(_CFNetServiceGetDomain)
public func CFNetServiceGetDomain(_ service: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer? {
    CFNetService.state(service)?.domainObject
}

@c(_CFNetServiceGetType)
public func CFNetServiceGetType(_ service: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer? {
    CFNetService.state(service)?.typeObject
}

@c(_CFNetServiceGetName)
public func CFNetServiceGetName(_ service: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer? {
    CFNetService.state(service)?.nameObject
}

@c(_CFNetServiceGetTargetHost)
public func CFNetServiceGetTargetHost(_ service: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer? {
    CFNetService.state(service)?.targetHost
}

@c(_CFNetServiceGetPortNumber)
public func CFNetServiceGetPortNumber(_ service: UnsafeMutableRawPointer?) -> Int32 {
    CFNetService.state(service)?.port ?? -1
}

@c(_CFNetServiceGetAddressing)
public func CFNetServiceGetAddressing(_ service: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer? {
    CFNetService.state(service)?.addressArray
}

@c(_CFNetServiceGetTXTData)
public func CFNetServiceGetTXTData(_ service: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer? {
    CFNetService.state(service)?.txtData
}

@c(_CFNetServiceSetTXTData)
public func CFNetServiceSetTXTData(_ service: UnsafeMutableRawPointer?, _ txtRecord: UnsafeMutableRawPointer?) -> Bool {
    guard let state = CFNetService.state(service) else { return false }
    ObjCRuntime.release(state.txtData)
    state.txtData = txtRecord.flatMap { data in
        let bytes = NSData(objCArgument: data).data
        return ObjCRuntime.retain(NSData.of(bytes).objcObject)
    }
    return true
}

@c(_CFNetServiceSetClient)
public func CFNetServiceSetClient(_ service: UnsafeMutableRawPointer?, _ callback: UnsafeRawPointer?,
                                  _ context: UnsafeRawPointer?) -> Bool {
    guard let state = CFNetService.state(service) else { return false }
    state.client?.releaseInfo()
    state.client = NetClient(callback: callback, context: context)
    return true
}

@c(_CFNetServiceScheduleWithRunLoop)
public func CFNetServiceScheduleWithRunLoop(_ service: UnsafeMutableRawPointer?, _ runLoop: UnsafeMutableRawPointer?,
                                            _ mode: UnsafeMutableRawPointer?) {
    guard let state = CFNetService.state(service), let runLoop else { return }
    state.schedules.append((loop: ObjCRuntime.retain(runLoop)!, mode: ObjCRuntime.retain(mode)))
    state.operation?.deliverSoon()
}

@c(_CFNetServiceUnscheduleFromRunLoop)
public func CFNetServiceUnscheduleFromRunLoop(_ service: UnsafeMutableRawPointer?, _ runLoop: UnsafeMutableRawPointer?,
                                              _ mode: UnsafeMutableRawPointer?) {
    guard let state = CFNetService.state(service), let runLoop else { return }
    if let index = state.schedules.firstIndex(where: { $0.loop == runLoop }) {
        let schedule = state.schedules.remove(at: index)
        ObjCRuntime.release(schedule.loop)
        ObjCRuntime.release(schedule.mode)
    }
}

/// Starts registering. With a client, asynchronous: the callback hears the
/// outcome. Without one, blocks until cancelled or failed, as CFNetwork's
/// does.
@c(_CFNetServiceRegisterWithOptions)
public func CFNetServiceRegisterWithOptions(_ service: UnsafeMutableRawPointer?, _ options: UInt,
                                            _ error: UnsafeMutableRawPointer?) -> Bool {
    guard let service, let state = CFNetService.state(service) else {
        StreamError.write(error, code: CFNetServices.badArgumentError)
        return false
    }
    guard state.operation == nil else {
        StreamError.write(error, code: CFNetServices.activityInProgress)
        return false
    }
    guard CFDNSSD.available, let register = CFDNSSD.register else {
        StreamError.write(error, code: CFNetServices.unknownError)
        return false
    }
    guard CFNetServices.isValidType(state.type), state.port >= 0 else {
        StreamError.write(error, code: CFNetServices.badArgumentError)
        return false
    }
    let operation = CFNetOperation(object: service)
    operation.schedules = { CFNetService.state(service)?.schedules ?? [] }
    let context = Unmanaged.passUnretained(operation).toOpaque()
    var ref: CFDNSSD.Ref?
    let type = CFNetServices.undotted(state.type)
    let domain = CFNetServices.undotted(state.domain)
    let port = UInt16(truncatingIfNeeded: state.port).bigEndian
    let flags: UInt32 = options & 1 != 0 ? CFDNSSD.noAutoRename : 0
    let txt = state.txtData.map { NSData(objCArgument: $0).data } ?? Data()
    let made = state.name.withCString { name in
        type.withCString { type in
            domain.withCString { domain in
                txt.withUnsafeBytes { bytes in
                    register(&ref, flags, 0, state.name.isEmpty ? nil : name, type,
                             domain.pointee == 0 ? nil : domain, nil, port, UInt16(txt.count),
                             bytes.count == 0 ? nil : bytes.baseAddress, cfRegisterReply, context)
                }
            }
        }
    }
    guard made == 0, let request = ref else {
        operation.stop()
        StreamError.write(error, code: CFNetServices.code(made))
        return false
    }
    operation.refs = [request]
    operation.step = { _, ref in CFDNSSD.process?(ref) == 0 }
    state.operation = operation
    StreamError.write(error, code: 0)
    if state.client != nil {
        operation.start()
        return true
    }
    // Synchronous: registered until cancelled from another thread.
    while operation.spin() {}
    operation.teardown()
    state.operation = nil
    StreamError.write(error, code: operation.failed != 0 ? CFNetServices.code(operation.failed) : CFNetServices.cancelledError)
    return false
}

@c(_CFNetServiceRegister)
public func CFNetServiceRegister(_ service: UnsafeMutableRawPointer?, _ error: UnsafeMutableRawPointer?) -> Bool {
    CFNetServiceRegisterWithOptions(service, 0, error)
}

/// Starts resolving. With a client, asynchronous; without one, blocks
/// until resolved, failed or out of time.
@c(_CFNetServiceResolveWithTimeout)
public func CFNetServiceResolveWithTimeout(_ service: UnsafeMutableRawPointer?, _ timeout: Double,
                                           _ error: UnsafeMutableRawPointer?) -> Bool {
    guard let service, let state = CFNetService.state(service) else {
        StreamError.write(error, code: CFNetServices.badArgumentError)
        return false
    }
    guard state.operation == nil else {
        StreamError.write(error, code: CFNetServices.activityInProgress)
        return false
    }
    guard CFDNSSD.available, let resolve = CFDNSSD.resolve else {
        StreamError.write(error, code: CFNetServices.unknownError)
        return false
    }
    let operation = CFNetOperation(object: service)
    operation.schedules = { CFNetService.state(service)?.schedules ?? [] }
    let context = Unmanaged.passUnretained(operation).toOpaque()
    var ref: CFDNSSD.Ref?
    let type = CFNetServices.undotted(state.type)
    let domain = CFNetServices.undotted(state.domain.isEmpty ? "local." : state.domain)
    let made = state.name.withCString { name in
        type.withCString { type in
            domain.withCString { domain in
                resolve(&ref, 0, 0, name, type, domain, cfResolveReply, context)
            }
        }
    }
    guard made == 0, let request = ref else {
        operation.stop()
        StreamError.write(error, code: CFNetServices.code(made))
        return false
    }
    if timeout > 0 { operation.deadline = CFNetServices.now() + timeout }
    operation.refs = [request]
    operation.step = { _, ref in CFDNSSD.process?(ref) == 0 }
    operation.timePassed = { operation in
        let time = CFNetServices.now()
        if let grace = operation.grace, time >= grace {
            operation.grace = nil
            operation.delivered = true
            let (host, port, txt, addresses) = (operation.hostName, operation.port, operation.txt, operation.addresses)
            operation.enqueue {
                let state = CFNetService.state(service)
                state?.adopt(host: host, port: port, txt: txt, addresses: addresses)
                callClient(service, 0)
            }
            return false
        }
        if let deadline = operation.deadline, time >= deadline {
            if !operation.delivered {
                operation.enqueue {
                    CFNetService.state(service)?.operation = nil
                    callClient(service, CFNetServices.timeoutError)
                }
            }
            return false
        }
        return true
    }
    state.operation = operation
    StreamError.write(error, code: 0)
    if state.client != nil {
        operation.start()
        return true
    }
    // Synchronous: the results land in the state right here.
    while operation.spin() {}
    operation.teardown()
    state.operation = nil
    if operation.delivered {
        state.adopt(host: operation.hostName, port: operation.port, txt: operation.txt, addresses: operation.addresses)
        StreamError.write(error, code: 0)
        return true
    }
    let code = operation.failed != 0 ? CFNetServices.code(operation.failed)
        : (operation.stopped ? CFNetServices.cancelledError : CFNetServices.timeoutError)
    StreamError.write(error, code: code)
    return false
}

@c(_CFNetServiceCancel)
public func CFNetServiceCancel(_ service: UnsafeMutableRawPointer?) {
    guard let service, let state = CFNetService.state(service), let operation = state.operation else { return }
    state.operation = nil
    operation.stop()
    if state.client != nil {
        operation.enqueue { callClient(service, CFNetServices.cancelledError) }
    }
}

extension CFServiceState {
    /// A resolution's results, as the Get functions hand them out.
    func adopt(host: String?, port: Int32, txt: [UInt8]?, addresses: [[UInt8]]) {
        if let host {
            ObjCRuntime.release(targetHost)
            targetHost = ObjCRuntime.retain(NSObject.string(host).objcObject)
        }
        self.port = port
        if let txt {
            ObjCRuntime.release(txtData)
            txtData = txt.withUnsafeBytes { bytes in
                ObjCRuntime.retain(NSData.make(bytes: bytes.baseAddress, length: UInt(bytes.count)).objcObject)
            }
        }
        ObjCRuntime.release(addressArray)
        let array = NSMutableArray.of(addresses.map { address in
            address.withUnsafeBytes { NSData.make(bytes: $0.baseAddress, length: UInt($0.count)) }
        })
        addressArray = ObjCRuntime.retain(array.objcObject)
    }
}

/// DNSServiceRegister's reply: the published (maybe renamed) name and
/// domain, or the error.
private let cfRegisterReply: CFDNSSD.RegisterReply = { _, _, error, name, _, domain, context in
    guard let context else { return }
    let operation = Unmanaged<CFNetOperation>.fromOpaque(context).takeUnretainedValue()
    let service = operation.object
    if error == 0 {
        let published = name.map { String(cString: $0) }
        let domain = domain.map { CFNetServices.dotted(String(cString: $0)) }
        operation.enqueue {
            CFNetService.state(service)?.update(name: published, domain: domain)
            callClient(service, 0)
        }
    } else {
        operation.failed = error
        let code = CFNetServices.code(error)
        operation.enqueue {
            CFNetService.state(service)?.operation = nil
            callClient(service, code)
        }
    }
}

/// DNSServiceResolve's reply: the host, port and TXT record; address
/// queries follow, delivered together after a short wait.
private let cfResolveReply: CFDNSSD.ResolveReply = { _, _, interface, error, _, host, port, txtLength, txt, context in
    guard let context else { return }
    let operation = Unmanaged<CFNetOperation>.fromOpaque(context).takeUnretainedValue()
    if error != 0 {
        guard !operation.delivered else { return }
        operation.delivered = true
        let code = CFNetServices.code(error)
        let service = operation.object
        operation.enqueue {
            CFNetService.state(service)?.operation = nil
            callClient(service, code)
        }
        operation.failed = error
        return
    }
    guard operation.hostName == nil else { return }
    operation.hostName = host.map { CFNetServices.dotted(String(cString: $0)) }
    operation.port = Int32(UInt16(bigEndian: port))
    if let txt, txtLength > 0 {
        operation.txt = Array(UnsafeBufferPointer(start: txt, count: Int(txtLength)))
    }
    operation.grace = CFNetServices.now() + 0.3
    if let query = CFDNSSD.queryRecord, let host {
        let context = Unmanaged.passUnretained(operation).toOpaque()
        for type in [CFDNSSD.typeA, CFDNSSD.typeAAAA] {
            var ref: CFDNSSD.Ref?
            if query(&ref, 0, interface, host, type, CFDNSSD.classIN, cfQueryReply, context) == 0, let ref {
                operation.refs.append(ref)
            }
        }
    }
}

/// DNSServiceQueryRecord's reply: one of the host's address records.
private let cfQueryReply: CFDNSSD.QueryReply = { _, flags, interface, error, _, type, _, length, bytes, _, context in
    guard let context, error == 0, flags & CFDNSSD.add != 0, let bytes else { return }
    let operation = Unmanaged<CFNetOperation>.fromOpaque(context).takeUnretainedValue()
    var address: [UInt8]?
    if type == CFDNSSD.typeA, length == 4 {
        address = CFNetServices.socketAddress(ipv4: bytes, port: operation.port)
    } else if type == CFDNSSD.typeAAAA, length == 16 {
        address = CFNetServices.socketAddress(ipv6: bytes, port: operation.port, interface: interface)
    }
    if let address, !operation.addresses.contains(address) {
        operation.addresses.append(address)
    }
}

// MARK: TXT records

/// The TXT record for a dictionary of data (or string) values:
/// length-prefixed "key=value" entries, a bare key for an empty value.
@c(_CFNetServiceCreateTXTDataWithDictionary)
public func CFNetServiceCreateTXTDataWithDictionary(_ allocator: UnsafeMutableRawPointer?,
                                                    _ keyValuePairs: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer? {
    guard let keyValuePairs else { return nil }
    let dictionary = NSDictionary(objCArgument: keyValuePairs)
    var bytes: [UInt8] = []
    for key in dictionary.allKeys().elements {
        guard key.isString, let value = dictionary.object(forKey: key) else { continue }
        var entry = Array(key.stringValue.utf8)
        let data: [UInt8]
        if value.isKind(of: ObjCClass(named: "NSNull")) {
            data = []
        } else if value.isString {
            data = Array(value.stringValue.utf8)
        } else if value.isKind(of: ObjCClass(named: "NSData")) {
            data = Array(NSData(objCArgument: value.objcObject).data)
        } else {
            continue
        }
        if !data.isEmpty { entry += [UInt8(ascii: "=")] + data }
        guard entry.count <= 255 else { continue }
        bytes += [UInt8(entry.count)] + entry
    }
    return bytes.withUnsafeBytes { buffer in
        ObjCRuntime.retain(NSData.make(bytes: buffer.baseAddress, length: UInt(buffer.count)).objcObject)
    }
}

/// The dictionary in a TXT record: data values, NSNull where an entry has
/// no "=", the first of repeated keys.
@c(_CFNetServiceCreateDictionaryWithTXTData)
public func CFNetServiceCreateDictionaryWithTXTData(_ allocator: UnsafeMutableRawPointer?,
                                                    _ txtRecord: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer? {
    guard let txtRecord else { return nil }
    let bytes = Array(NSData(objCArgument: txtRecord).data)
    guard !bytes.isEmpty else { return nil }
    let dictionary = NSMutableDictionary.empty()
    var names: Set<String> = []
    var index = 0
    while index < bytes.count {
        let length = Int(bytes[index])
        index += 1
        let end = min(index + length, bytes.count)
        let entry = bytes[index..<end]
        index = end
        guard !entry.isEmpty else { continue }
        let key: ArraySlice<UInt8>
        let value: NSObject
        if let equals = entry.firstIndex(of: UInt8(ascii: "=")) {
            key = entry[entry.startIndex..<equals]
            let data = Array(entry[(equals + 1)...])
            value = data.withUnsafeBytes { NSData.make(bytes: $0.baseAddress, length: UInt($0.count)) }
        } else {
            key = entry
            value = NSNull.null()
        }
        guard !key.isEmpty else { continue }
        let name = String(decoding: key, as: UTF8.self)
        guard names.insert(name).inserted else { continue }
        dictionary.set(value, forKey: NSObject.string(name))
    }
    return ObjCRuntime.retain(dictionary.objcObject)
}

// MARK: - CFNetServiceBrowser

final class CFBrowserState {
    var client: NetClient?
    var schedules: [(loop: UnsafeMutableRawPointer, mode: UnsafeMutableRawPointer?)] = []
    var operation: CFNetOperation?
    /// The services found, by "name|type|domain", alive until removed.
    var services: [String: UnsafeMutableRawPointer] = [:]

    func releaseServices() {
        services.values.forEach { ObjCRuntime.release($0) }
        services = [:]
    }

    func releaseObjects() {
        releaseServices()
        for (loop, mode) in schedules {
            ObjCRuntime.release(loop)
            ObjCRuntime.release(mode)
        }
        schedules = []
        client?.releaseInfo()
        client = nil
    }
}

/// The CFNetServiceBrowserRef type.
@ObjCClass("_PerryCFNetServiceBrowser")
final class CFNetServiceBrowser: NSObject {
    static let states = StateTable<CFBrowserState>()

    @ObjCMethod("dealloc")
    func dealloc() {
        if let state = CFNetServiceBrowser.states.get(objcObject) {
            state.operation?.stop()
            state.releaseObjects()
        }
        CFNetServiceBrowser.states.remove(objcObject)
        ObjCRuntime.superDealloc(objcObject, definedOn: CFNetServiceBrowser.objCClass.pointer)
    }

    @ObjCMethod("_cfTypeID") func cfTypeID() -> UInt { 0x43_02 }

    static func state(_ object: UnsafeMutableRawPointer?) -> CFBrowserState? {
        object.flatMap { states.get($0) }
    }
}

/// The browser's callback, called on the scheduled run loop.
private func callBrowser(_ browser: UnsafeMutableRawPointer, _ flags: UInt, _ domainOrService: UnsafeMutableRawPointer?,
                         _ code: Int32) {
    guard let state = CFNetServiceBrowser.state(browser), let client = state.client else { return }
    typealias Callback = @convention(c) (
        UnsafeMutableRawPointer?, UInt, UnsafeMutableRawPointer?, UnsafeMutableRawPointer?, UnsafeMutableRawPointer?
    ) -> Void
    var error: (Int, Int32) = (code == 0 ? 0 : StreamError.domain, code)
    withUnsafeMutableBytes(of: &error) { bytes in
        unsafeBitCast(client.callback, to: Callback.self)(browser, flags, domainOrService, bytes.baseAddress, client.info)
    }
}

@c(_CFNetServiceBrowserGetTypeID)
public func CFNetServiceBrowserGetTypeID() -> UInt { 0x43_02 }

@c(_CFNetServiceBrowserCreate)
public func CFNetServiceBrowserCreate(_ allocator: UnsafeMutableRawPointer?, _ callback: UnsafeRawPointer?,
                                      _ context: UnsafeRawPointer?) -> UnsafeMutableRawPointer? {
    let object = ObjCRuntime.retain(CFNetServiceBrowser.objCClass.autoreleasedInstance().objcObject)!
    let state = CFBrowserState()
    state.client = NetClient(callback: callback, context: context)
    CFNetServiceBrowser.states.set(object, state)
    return object
}

@c(_CFNetServiceBrowserScheduleWithRunLoop)
public func CFNetServiceBrowserScheduleWithRunLoop(_ browser: UnsafeMutableRawPointer?,
                                                   _ runLoop: UnsafeMutableRawPointer?,
                                                   _ mode: UnsafeMutableRawPointer?) {
    guard let state = CFNetServiceBrowser.state(browser), let runLoop else { return }
    state.schedules.append((loop: ObjCRuntime.retain(runLoop)!, mode: ObjCRuntime.retain(mode)))
    state.operation?.deliverSoon()
}

@c(_CFNetServiceBrowserUnscheduleFromRunLoop)
public func CFNetServiceBrowserUnscheduleFromRunLoop(_ browser: UnsafeMutableRawPointer?,
                                                     _ runLoop: UnsafeMutableRawPointer?,
                                                     _ mode: UnsafeMutableRawPointer?) {
    guard let state = CFNetServiceBrowser.state(browser), let runLoop else { return }
    if let index = state.schedules.firstIndex(where: { $0.loop == runLoop }) {
        let schedule = state.schedules.remove(at: index)
        ObjCRuntime.release(schedule.loop)
        ObjCRuntime.release(schedule.mode)
    }
}

@c(_CFNetServiceBrowserSearchForServices)
public func CFNetServiceBrowserSearchForServices(_ browser: UnsafeMutableRawPointer?, _ domain: UnsafeMutableRawPointer?,
                                                 _ serviceType: UnsafeMutableRawPointer?,
                                                 _ error: UnsafeMutableRawPointer?) -> Bool {
    guard let browser, let state = CFNetServiceBrowser.state(browser) else {
        StreamError.write(error, code: CFNetServices.badArgumentError)
        return false
    }
    guard state.operation == nil else {
        StreamError.write(error, code: CFNetServices.activityInProgress)
        return false
    }
    guard CFDNSSD.available, let browse = CFDNSSD.browse else {
        StreamError.write(error, code: CFNetServices.unknownError)
        return false
    }
    let type = serviceType.map { NSObject(objCArgument: $0).stringValue } ?? ""
    guard CFNetServices.isValidType(type) else {
        StreamError.write(error, code: CFNetServices.badArgumentError)
        return false
    }
    let operation = CFNetOperation(object: browser)
    operation.schedules = { CFNetServiceBrowser.state(browser)?.schedules ?? [] }
    let context = Unmanaged.passUnretained(operation).toOpaque()
    var ref: CFDNSSD.Ref?
    let bare = CFNetServices.undotted(type)
    let bareDomain = CFNetServices.undotted(domain.map { NSObject(objCArgument: $0).stringValue } ?? "")
    let made = bare.withCString { type in
        bareDomain.withCString { domain in
            browse(&ref, 0, 0, type, domain.pointee == 0 ? nil : domain, cfBrowseReply, context)
        }
    }
    guard made == 0, let request = ref else {
        operation.stop()
        StreamError.write(error, code: CFNetServices.code(made))
        return false
    }
    operation.refs = [request]
    operation.step = { _, ref in CFDNSSD.process?(ref) == 0 }
    state.operation = operation
    operation.start()
    StreamError.write(error, code: 0)
    return true
}

@c(_CFNetServiceBrowserSearchForDomains)
public func CFNetServiceBrowserSearchForDomains(_ browser: UnsafeMutableRawPointer?, _ registrationDomains: Bool,
                                                _ error: UnsafeMutableRawPointer?) -> Bool {
    guard let browser, let state = CFNetServiceBrowser.state(browser) else {
        StreamError.write(error, code: CFNetServices.badArgumentError)
        return false
    }
    guard state.operation == nil else {
        StreamError.write(error, code: CFNetServices.activityInProgress)
        return false
    }
    guard CFDNSSD.available, let enumerate = CFDNSSD.enumerateDomains else {
        StreamError.write(error, code: CFNetServices.unknownError)
        return false
    }
    let operation = CFNetOperation(object: browser)
    operation.schedules = { CFNetServiceBrowser.state(browser)?.schedules ?? [] }
    let context = Unmanaged.passUnretained(operation).toOpaque()
    var ref: CFDNSSD.Ref?
    let flags = registrationDomains ? CFDNSSD.registrationDomains : CFDNSSD.browseDomains
    guard enumerate(&ref, flags, 0, cfDomainReply, context) == 0, let request = ref else {
        operation.stop()
        StreamError.write(error, code: CFNetServices.unknownError)
        return false
    }
    operation.refs = [request]
    operation.step = { _, ref in CFDNSSD.process?(ref) == 0 }
    state.operation = operation
    operation.start()
    StreamError.write(error, code: 0)
    return true
}

@c(_CFNetServiceBrowserStopSearch)
public func CFNetServiceBrowserStopSearch(_ browser: UnsafeMutableRawPointer?, _ error: UnsafeMutableRawPointer?) {
    StreamError.write(error, code: 0)
    guard let browser, let state = CFNetServiceBrowser.state(browser), let operation = state.operation else { return }
    state.operation = nil
    operation.stop()
    // Darwin acknowledges the stop with one callback: no flags, no
    // service, no error.
    operation.enqueue {
        CFNetServiceBrowser.state(browser)?.releaseServices()
        callBrowser(browser, 0, nil, 0)
    }
}

@c(_CFNetServiceBrowserInvalidate)
public func CFNetServiceBrowserInvalidate(_ browser: UnsafeMutableRawPointer?) {
    guard let state = CFNetServiceBrowser.state(browser) else { return }
    if let operation = state.operation {
        state.operation = nil
        operation.stop()
    }
    state.releaseObjects()
}

/// DNSServiceBrowse's reply: a service appeared or went, on one
/// interface; the client hears of the first and the last only.
private let cfBrowseReply: CFDNSSD.BrowseReply = { _, flags, _, error, name, type, domain, context in
    guard let context else { return }
    let operation = Unmanaged<CFNetOperation>.fromOpaque(context).takeUnretainedValue()
    let browser = operation.object
    if error != 0 {
        operation.failed = error
        let code = CFNetServices.code(error)
        operation.enqueue {
            CFNetServiceBrowser.state(browser)?.operation = nil
            callBrowser(browser, 0, nil, code)
        }
        return
    }
    guard let name, let type, let domain else { return }
    let service = String(cString: name)
    let dottedType = CFNetServices.dotted(String(cString: type))
    let dottedDomain = CFNetServices.dotted(String(cString: domain))
    let key = "\(service)|\(dottedType)|\(dottedDomain)"
    let more: UInt = flags & CFDNSSD.moreComing != 0 ? CFNetServices.flagMoreComing : 0
    if flags & CFDNSSD.add != 0 {
        let count = (operation.found[key] ?? 0) + 1
        operation.found[key] = count
        guard count == 1 else { return }
        operation.enqueue {
            guard let state = CFNetServiceBrowser.state(browser) else { return }
            let found = CFNetService.make(domain: dottedDomain, type: dottedType, name: service, port: -1)
            state.services[key] = found
            callBrowser(browser, more, found, 0)
        }
    } else {
        let count = (operation.found[key] ?? 1) - 1
        if count > 0 {
            operation.found[key] = count
            return
        }
        operation.found[key] = nil
        operation.enqueue {
            guard let state = CFNetServiceBrowser.state(browser) else { return }
            let going = state.services.removeValue(forKey: key)
                ?? CFNetService.make(domain: dottedDomain, type: dottedType, name: service, port: -1)
            callBrowser(browser, more | CFNetServices.flagRemove, going, 0)
            ObjCRuntime.release(going)
        }
    }
}

/// DNSServiceEnumerateDomains' reply: a browsable or registration domain.
private let cfDomainReply: CFDNSSD.DomainReply = { _, flags, _, error, domain, context in
    guard let context, error == 0, let domain else { return }
    let operation = Unmanaged<CFNetOperation>.fromOpaque(context).takeUnretainedValue()
    let browser = operation.object
    let name = CFNetServices.dotted(String(cString: domain))
    var callbackFlags = CFNetServices.flagIsDomain
    if flags & CFDNSSD.moreComing != 0 { callbackFlags |= CFNetServices.flagMoreComing }
    if flags & CFDNSSD.add == 0 { callbackFlags |= CFNetServices.flagRemove }
    operation.enqueue {
        let string = ObjCRuntime.retain(NSObject.string(name).objcObject)
        callBrowser(browser, callbackFlags, string, 0)
        ObjCRuntime.release(string)
    }
}

// MARK: - CFNetServiceMonitor

final class CFMonitorState {
    /// The service monitored, retained.
    let service: UnsafeMutableRawPointer
    var client: NetClient?
    var schedules: [(loop: UnsafeMutableRawPointer, mode: UnsafeMutableRawPointer?)] = []
    var operation: CFNetOperation?

    init(service: UnsafeMutableRawPointer) {
        self.service = ObjCRuntime.retain(service)!
    }

    func releaseObjects() {
        ObjCRuntime.release(service)
        for (loop, mode) in schedules {
            ObjCRuntime.release(loop)
            ObjCRuntime.release(mode)
        }
        schedules = []
        client?.releaseInfo()
        client = nil
    }
}

/// The CFNetServiceMonitorRef type: watches a service's TXT record.
@ObjCClass("_PerryCFNetServiceMonitor")
final class CFNetServiceMonitor: NSObject {
    static let states = StateTable<CFMonitorState>()

    @ObjCMethod("dealloc")
    func dealloc() {
        if let state = CFNetServiceMonitor.states.get(objcObject) {
            state.operation?.stop()
            state.releaseObjects()
        }
        CFNetServiceMonitor.states.remove(objcObject)
        ObjCRuntime.superDealloc(objcObject, definedOn: CFNetServiceMonitor.objCClass.pointer)
    }

    @ObjCMethod("_cfTypeID") func cfTypeID() -> UInt { 0x43_03 }

    static func state(_ object: UnsafeMutableRawPointer?) -> CFMonitorState? {
        object.flatMap { states.get($0) }
    }
}

@c(_CFNetServiceMonitorGetTypeID)
public func CFNetServiceMonitorGetTypeID() -> UInt { 0x43_03 }

@c(_CFNetServiceMonitorCreate)
public func CFNetServiceMonitorCreate(_ allocator: UnsafeMutableRawPointer?, _ service: UnsafeMutableRawPointer?,
                                      _ callback: UnsafeRawPointer?,
                                      _ context: UnsafeRawPointer?) -> UnsafeMutableRawPointer? {
    guard let service else { return nil }
    let object = ObjCRuntime.retain(CFNetServiceMonitor.objCClass.autoreleasedInstance().objcObject)!
    let state = CFMonitorState(service: service)
    state.client = NetClient(callback: callback, context: context)
    CFNetServiceMonitor.states.set(object, state)
    return object
}

@c(_CFNetServiceMonitorScheduleWithRunLoop)
public func CFNetServiceMonitorScheduleWithRunLoop(_ monitor: UnsafeMutableRawPointer?,
                                                   _ runLoop: UnsafeMutableRawPointer?,
                                                   _ mode: UnsafeMutableRawPointer?) {
    guard let state = CFNetServiceMonitor.state(monitor), let runLoop else { return }
    state.schedules.append((loop: ObjCRuntime.retain(runLoop)!, mode: ObjCRuntime.retain(mode)))
    state.operation?.deliverSoon()
}

@c(_CFNetServiceMonitorUnscheduleFromRunLoop)
public func CFNetServiceMonitorUnscheduleFromRunLoop(_ monitor: UnsafeMutableRawPointer?,
                                                     _ runLoop: UnsafeMutableRawPointer?,
                                                     _ mode: UnsafeMutableRawPointer?) {
    guard let state = CFNetServiceMonitor.state(monitor), let runLoop else { return }
    if let index = state.schedules.firstIndex(where: { $0.loop == runLoop }) {
        let schedule = state.schedules.remove(at: index)
        ObjCRuntime.release(schedule.loop)
        ObjCRuntime.release(schedule.mode)
    }
}

/// Starts watching the service's TXT record (monitor type 1, the only one).
@c(_CFNetServiceMonitorStart)
public func CFNetServiceMonitorStart(_ monitor: UnsafeMutableRawPointer?, _ monitorType: Int,
                                     _ error: UnsafeMutableRawPointer?) -> Bool {
    guard let monitor, let state = CFNetServiceMonitor.state(monitor), monitorType == 1 else {
        StreamError.write(error, code: CFNetServices.badArgumentError)
        return false
    }
    guard state.operation == nil else {
        StreamError.write(error, code: CFNetServices.activityInProgress)
        return false
    }
    guard CFDNSSD.available, let query = CFDNSSD.queryRecord,
          let serviceState = CFNetService.state(state.service),
          let fullName = CFNetServices.fullName(name: serviceState.name,
                                                type: CFNetServices.undotted(serviceState.type),
                                                domain: CFNetServices.undotted(serviceState.domain.isEmpty ? "local."
                                                                               : serviceState.domain)) else {
        StreamError.write(error, code: CFNetServices.unknownError)
        return false
    }
    let operation = CFNetOperation(object: monitor)
    operation.schedules = { CFNetServiceMonitor.state(monitor)?.schedules ?? [] }
    let context = Unmanaged.passUnretained(operation).toOpaque()
    var ref: CFDNSSD.Ref?
    let made = fullName.withCString { name in
        query(&ref, 0, 0, name, CFDNSSD.typeTXT, CFDNSSD.classIN, cfMonitorReply, context)
    }
    guard made == 0, let request = ref else {
        operation.stop()
        StreamError.write(error, code: CFNetServices.code(made))
        return false
    }
    operation.refs = [request]
    operation.step = { _, ref in CFDNSSD.process?(ref) == 0 }
    state.operation = operation
    operation.start()
    StreamError.write(error, code: 0)
    return true
}

@c(_CFNetServiceMonitorStop)
public func CFNetServiceMonitorStop(_ monitor: UnsafeMutableRawPointer?, _ error: UnsafeMutableRawPointer?) {
    StreamError.write(error, code: 0)
    guard let state = CFNetServiceMonitor.state(monitor), let operation = state.operation else { return }
    state.operation = nil
    operation.stop()
}

@c(_CFNetServiceMonitorInvalidate)
public func CFNetServiceMonitorInvalidate(_ monitor: UnsafeMutableRawPointer?) {
    guard let state = CFNetServiceMonitor.state(monitor) else { return }
    if let operation = state.operation {
        state.operation = nil
        operation.stop()
    }
    state.releaseObjects()
}

/// DNSServiceQueryRecord's reply for the TXT record: the client hears
/// each new value.
private let cfMonitorReply: CFDNSSD.QueryReply = { _, flags, _, error, _, _, _, length, bytes, _, context in
    guard let context, error == 0, flags & CFDNSSD.add != 0 else { return }
    let operation = Unmanaged<CFNetOperation>.fromOpaque(context).takeUnretainedValue()
    let monitor = operation.object
    let record = bytes.map { Array(UnsafeRawBufferPointer(start: $0, count: Int(length))) } ?? []
    operation.enqueue {
        guard let state = CFNetServiceMonitor.state(monitor), let client = state.client else { return }
        typealias Callback = @convention(c) (
            UnsafeMutableRawPointer?, UnsafeMutableRawPointer?, Int, UnsafeMutableRawPointer?, UnsafeMutableRawPointer?
        ) -> Void
        let data = record.withUnsafeBytes {
            ObjCRuntime.retain(NSData.make(bytes: $0.baseAddress, length: UInt($0.count)).objcObject)
        }
        unsafeBitCast(client.callback, to: Callback.self)(monitor, state.service, 1, data, client.info)
        ObjCRuntime.release(data)
    }
}
