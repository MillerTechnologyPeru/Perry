import FoundationEssentials
import Glibc
import PerryObjCInterop

// NSNetService and NSNetServiceBrowser: Bonjour over the dns_sd API —
// Darwin's own, which Avahi's compatibility library provides over
// avahi-daemon on Linux (libdns_sd.so.1, from avahi-compat-libdnssd) —
// opened at run time. Each search, registration or resolution runs a
// worker thread that waits on the daemon's socket; its replies are
// performed back onto the thread the operation started on, where Darwin's
// run loop would deliver them, and the delegate hears of them there.

/// The delegate of an NSNetService.
@ObjCProtocol("NSNetServiceDelegate")
protocol NSNetServiceDelegate {
    @ObjCOptional("netServiceWillPublish:")
    func netServiceWillPublish(_ service: NSNetService)

    @ObjCOptional("netServiceDidPublish:")
    func netServiceDidPublish(_ service: NSNetService)

    @ObjCOptional("netService:didNotPublish:")
    func netService(_ service: NSNetService, didNotPublish errorDict: ObjCObject)

    @ObjCOptional("netServiceWillResolve:")
    func netServiceWillResolve(_ service: NSNetService)

    @ObjCOptional("netServiceDidResolveAddress:")
    func netServiceDidResolveAddress(_ service: NSNetService)

    @ObjCOptional("netService:didNotResolve:")
    func netService(_ service: NSNetService, didNotResolve errorDict: ObjCObject)

    @ObjCOptional("netServiceDidStop:")
    func netServiceDidStop(_ service: NSNetService)
}

/// The delegate of an NSNetServiceBrowser.
@ObjCProtocol("NSNetServiceBrowserDelegate")
protocol NSNetServiceBrowserDelegate {
    @ObjCOptional("netServiceBrowserWillSearch:")
    func netServiceBrowserWillSearch(_ browser: NSNetServiceBrowser)

    @ObjCOptional("netServiceBrowserDidStopSearch:")
    func netServiceBrowserDidStopSearch(_ browser: NSNetServiceBrowser)

    @ObjCOptional("netServiceBrowser:didNotSearch:")
    func netServiceBrowser(_ browser: NSNetServiceBrowser, didNotSearch errorDict: ObjCObject)

    @ObjCOptional("netServiceBrowser:didFindService:moreComing:")
    func netServiceBrowser(_ browser: NSNetServiceBrowser, didFindService service: NSNetService, moreComing: Bool)

    @ObjCOptional("netServiceBrowser:didRemoveService:moreComing:")
    func netServiceBrowser(_ browser: NSNetServiceBrowser, didRemoveService service: NSNetService, moreComing: Bool)

    @ObjCOptional("netServiceBrowser:didFindDomain:moreComing:")
    func netServiceBrowser(_ browser: NSNetServiceBrowser, didFindDomain domain: String, moreComing: Bool)

    @ObjCOptional("netServiceBrowser:didRemoveDomain:moreComing:")
    func netServiceBrowser(_ browser: NSNetServiceBrowser, didRemoveDomain domain: String, moreComing: Bool)
}

/// The keys of the dictionary didNotSearch, didNotPublish and
/// didNotResolve report an error with.
@ObjCConstants
enum NetServiceConstants {
    static let NSNetServicesErrorCode = "NSNetServicesErrorCode"
    static let NSNetServicesErrorDomain = "NSNetServicesErrorDomain"
}

// MARK: - The dns_sd API

/// The dns_sd functions, from Avahi's Bonjour compatibility library,
/// bound on first use.
enum DNSSD {
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
    static let noAutoRename: UInt32 = 0x4000

    // Resource record types, and the Internet class.
    static let typeA: UInt16 = 1
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
    nonisolated(unsafe) static let socket = bind("DNSServiceRefSockFD", (@convention(c) (Ref?) -> Int32).self)
    nonisolated(unsafe) static let process = bind("DNSServiceProcessResult", (@convention(c) (Ref?) -> Int32).self)
    nonisolated(unsafe) static let deallocate = bind("DNSServiceRefDeallocate", (@convention(c) (Ref?) -> Void).self)
}

// MARK: - Common machinery

/// NSNetServices error codes, and other values the delegates hear.
enum NetServices {
    static let unknownError = -72000
    static let collisionError = -72001
    static let activityInProgress = -72003
    static let badArgumentError = -72004
    static let timeoutError = -72007

    /// An NSNetServices code for a dns_sd error.
    static func code(_ error: Int32) -> Int {
        switch error {
        case -65548: return collisionError     // kDNSServiceErr_NameConflict
        case -65540: return badArgumentError   // kDNSServiceErr_BadParam
        case -65554: return timeoutError       // kDNSServiceErr_Timeout
        default: return unknownError
        }
    }

    /// The dictionary an error is reported with: the code, in
    /// kCFStreamErrorDomainNetServices (10).
    static func errorDictionary(_ code: Int) -> id {
        Dictionaries.autoreleased([
            (key: NetServiceConstants.NSNetServicesErrorCodeObject, value: Numbers.make(nil, .signed(Int64(code)))!),
            (key: NetServiceConstants.NSNetServicesErrorDomainObject, value: Numbers.make(nil, .signed(10))!),
        ])
    }

    /// With a trailing dot, as Darwin reports types, domains and host names.
    static func dotted(_ name: String) -> String { name.hasSuffix(".") ? name : name + "." }

    /// Without one, as Avahi matches them.
    static func undotted(_ name: String) -> String { name.hasSuffix(".") ? String(name.dropLast()) : name }

    /// Whether a type names a service and protocol ("_music._tcp", with
    /// subtypes after a comma); Darwin reports others as bad arguments
    /// without searching.
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

    /// A Darwin sockaddr_in as its bytes: the length and family lead, and
    /// the port is in network byte order.
    static func socketAddress(ipv4 address: UnsafeRawPointer, port: Int) -> Data {
        var bytes = [UInt8](repeating: 0, count: 16)
        bytes[0] = 16
        bytes[1] = 2 // Darwin's AF_INET
        bytes[2] = UInt8((port >> 8) & 0xff)
        bytes[3] = UInt8(port & 0xff)
        for index in 0..<4 { bytes[4 + index] = address.load(fromByteOffset: index, as: UInt8.self) }
        return Data(bytes)
    }

    /// A Darwin sockaddr_in6, 28 bytes; a link-local address keeps the
    /// interface it arrived on as its scope.
    static func socketAddress(ipv6 address: UnsafeRawPointer, port: Int, interface: UInt32) -> Data {
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
        return Data(bytes)
    }
}

/// The operations whose events await delivery, by the service or browser
/// they belong to. An object's events can outlive the operation's place in
/// its storage (a stopped search still owes didStopSearch), so delivery
/// finds them here.
enum NetDeliveries {
    nonisolated(unsafe) private static var operations: [UnsafeMutableRawPointer: [NetOperation]] = [:]
    nonisolated(unsafe) private static let mutex: UnsafeMutablePointer<pthread_mutex_t> = {
        let mutex = UnsafeMutablePointer<pthread_mutex_t>.allocate(capacity: 1)
        pthread_mutex_init(mutex, nil)
        return mutex
    }()

    static func register(_ operation: NetOperation, for object: id) {
        pthread_mutex_lock(mutex)
        defer { pthread_mutex_unlock(mutex) }
        if operations[object, default: []].contains(where: { $0 === operation }) { return }
        operations[object, default: []].append(operation)
    }

    /// Runs the queued events of every operation of `object`, and lets go
    /// of operations that are over and drained.
    static func deliver(for object: id) {
        pthread_mutex_lock(mutex)
        let pending = operations[object] ?? []
        pthread_mutex_unlock(mutex)
        for operation in pending { operation.deliver() }
        pthread_mutex_lock(mutex)
        operations[object] = operations[object]?.filter { !$0.isDrained }
        if operations[object]?.isEmpty == true { operations[object] = nil }
        pthread_mutex_unlock(mutex)
    }

    /// Forgets an object's operations as it deallocates.
    static func forget(_ object: id) {
        pthread_mutex_lock(mutex)
        operations[object] = nil
        pthread_mutex_unlock(mutex)
    }
}

/// One search, registration or resolution: its dns_sd requests, the
/// worker thread waiting on their sockets, and the events it performs
/// back onto the thread the operation started on.
final class NetOperation {
    /// The NSNetService or NSNetServiceBrowser, kept alive while the
    /// operation runs.
    let object: id
    /// The thread events are delivered on.
    private let home: id
    private let mutex = UnsafeMutablePointer<pthread_mutex_t>.allocate(capacity: 1)
    private var pending: [() -> Void] = []
    private var stopFlag = false
    private var exited = false
    private var thread: pthread_t?

    /// The requests the worker waits on; the worker's own once it starts.
    var refs: [DNSSD.Ref] = []

    /// When a resolution gives up, and when its addresses are delivered.
    var deadline: Double?
    var grace: Double?
    /// A reply reported an error; the worker ends.
    var failed = false

    // A resolution's results, the worker's until delivered.
    var hostName: String?
    var port = 0
    var txt: Data?
    var addresses: [Data] = []
    var delivered = false

    /// A search's services by "name|type|domain", counting the interfaces
    /// each was found on: found at the first, removed after the last.
    var found: [String: Int] = [:]

    /// Processes one ready request; false ends the operation.
    var step: ((NetOperation, DNSSD.Ref) -> Bool)?
    /// Runs when the clock passes `deadline` or `grace`; false ends it.
    var timePassed: ((NetOperation) -> Bool)?

    init(object: id, home: id) {
        self.object = ObjC.retain(object)!
        self.home = ObjC.retain(home)!
        pthread_mutex_init(mutex, nil)
        NetDeliveries.register(self, for: object)
    }

    deinit {
        pthread_mutex_destroy(mutex)
        mutex.deallocate()
    }

    /// Queues an event and asks the home thread to deliver it. The perform
    /// request holds the object, so it outlives any release here.
    func enqueue(_ event: @escaping () -> Void) {
        pthread_mutex_lock(mutex)
        pending.append(event)
        pthread_mutex_unlock(mutex)
        Threads.perform(object, ObjC.selector("_perryDeliverNetEvents"), nil, on: home, wait: false)
    }

    /// Runs the queued events; on the home thread.
    func deliver() {
        pthread_mutex_lock(mutex)
        let events = pending
        pending = []
        pthread_mutex_unlock(mutex)
        for event in events { event() }
    }

    /// Over, with nothing left to deliver.
    var isDrained: Bool {
        pthread_mutex_lock(mutex)
        defer { pthread_mutex_unlock(mutex) }
        return exited && pending.isEmpty
    }

    /// Starts the worker thread.
    func start() {
        let context = Unmanaged.passRetained(self).toOpaque()
        var worker = pthread_t()
        if pthread_create(&worker, nil, { context in
            Unmanaged<NetOperation>.fromOpaque(context!).takeRetainedValue().run()
            return nil
        }, context) == 0 {
            thread = worker
        } else {
            Unmanaged<NetOperation>.fromOpaque(context).release()
            teardown()
        }
    }

    private var stopped: Bool {
        pthread_mutex_lock(mutex)
        defer { pthread_mutex_unlock(mutex) }
        return stopFlag
    }

    /// Ends the operation and waits for the worker, so its requests are
    /// gone before the caller goes on; events still queued stay queued.
    func stop() {
        pthread_mutex_lock(mutex)
        stopFlag = true
        let started = thread != nil
        pthread_mutex_unlock(mutex)
        if started {
            if let thread { pthread_join(thread, nil) }
            thread = nil
        } else if !exited {
            teardown()
        }
    }

    /// Releases what the operation holds; on the worker as it ends, or in
    /// stop() or start() when none ran.
    private func teardown() {
        for ref in refs { DNSSD.deallocate?(ref) }
        refs = []
        pthread_mutex_lock(mutex)
        exited = true
        pthread_mutex_unlock(mutex)
        ObjC.release(object)
        ObjC.release(home)
    }

    /// The worker: waits on every request's socket, processes the ready
    /// ones — their replies' callbacks run here — and watches the clock.
    private func run() {
        while !stopped {
            var files = refs.map { pollfd(fd: DNSSD.socket?($0) ?? -1, events: Int16(POLLIN), revents: 0) }
            let ready = files.withUnsafeMutableBufferPointer { poll($0.baseAddress, nfds_t($0.count), 50) }
            if stopped { break }
            var ended = false
            if ready > 0 {
                for (index, file) in files.enumerated() where file.revents & Int16(POLLIN) != 0 {
                    guard index < refs.count, let step else { continue }
                    if !step(self, refs[index]) || failed { ended = true }
                }
            }
            if let timePassed, let soonest = [deadline, grace].compactMap({ $0 }).min(),
               NetServices.now() >= soonest, !timePassed(self) {
                ended = true
            }
            if ended { break }
        }
        teardown()
    }
}

// MARK: - NSNetService

final class NetServiceStorage {
    var domain: String
    var type: String
    var name: String
    var port = -1
    var hostName: String?
    var addresses: [Data] = []
    var txtData: Data?
    /// The delegate; not retained.
    var delegate: UnsafeMutableRawPointer?
    var operation: NetOperation?

    init(domain: String, type: String, name: String) {
        self.domain = domain
        self.type = type
        self.name = name
    }
}

enum NetObjects {
    nonisolated(unsafe) static var serviceClass: Class!
    nonisolated(unsafe) static var browserClass: Class!

    static func storage(_ object: id?) -> NetServiceStorage? { Storage.get(object, as: NetServiceStorage.self) }

    /// A new NSNetService (autoreleased), as a browser's findings are made.
    static func makeService(domain: String, type: String, name: String) -> id {
        let object = Storage.allocate(UnsafeMutableRawPointer(serviceClass))!
        Storage.set(object, NetServiceStorage(domain: domain, type: type, name: name))
        return ObjC.autorelease(object)!
    }
}

/// NSNetService: one network service, published or discovered.
@ObjCClass("NSNetService")
public final class NSNetService: NSObject {
    override public class func didDefineObjCClass(_ cls: ObjCClass) {
        NSObject.registerObjCCategoryStorageAllocated(cls)
        NetObjects.serviceClass = cls.storage
    }

    var storage: NetServiceStorage {
        if let storage = NetObjects.storage(objcObject) { return storage }
        let storage = NetServiceStorage(domain: "", type: "", name: "")
        Storage.set(objcObject, storage)
        return storage
    }

    var delegateObject: AnyNSNetServiceDelegate? { storage.delegate.map { AnyNSNetServiceDelegate($0) } }

    @ObjCMethod("dealloc")
    func dealloc() {
        NetDeliveries.forget(objcObject)
        Storage.set(objcObject, nil)
        ObjC.superDealloc(objcObject, from: NetObjects.serviceClass)
    }

    @ObjCMethod("initWithDomain:type:name:port:")
    func initialize(domain: String, type: String, name: String, port: Int32) -> Self {
        let storage = NetServiceStorage(domain: domain, type: type, name: name)
        storage.port = Int(port)
        Storage.set(objcObject, storage)
        return self
    }

    @ObjCMethod("initWithDomain:type:name:")
    func initialize(domain: String, type: String, name: String) -> Self {
        Storage.set(objcObject, NetServiceStorage(domain: domain, type: type, name: name))
        return self
    }

    @ObjCMethod("domain") func domain() -> String { storage.domain }
    @ObjCMethod("type") func type() -> String { storage.type }
    @ObjCMethod("name") func name() -> String { storage.name }
    @ObjCMethod("port") func port() -> Int { storage.port }
    @ObjCMethod("hostName") func hostName() -> String? { storage.hostName }

    @ObjCMethod("addresses")
    func addresses() -> UnsafeMutableRawPointer? {
        Arrays.autoreleased(storage.addresses.compactMap { DataObjects.autoreleased($0) })
    }

    @ObjCMethod("delegate") func delegate() -> NSObject? { storage.delegate.map { NSObject(objCArgument: $0) } }
    @ObjCMethod("setDelegate:") func setDelegate(_ delegate: NSObject?) { storage.delegate = delegate?.objcObject }

    @ObjCMethod("TXTRecordData")
    func txtRecordData() -> UnsafeMutableRawPointer? { storage.txtData.flatMap { DataObjects.autoreleased($0) } }

    @ObjCMethod("setTXTRecordData:")
    func setTXTRecordData(_ data: ObjCObject?) -> Bool {
        storage.txtData = data.map { DataObjects.data($0.id) }
        return true
    }

    @ObjCMethod("includesPeerToPeer") func includesPeerToPeer() -> Bool { false }
    @ObjCMethod("setIncludesPeerToPeer:") func setIncludesPeerToPeer(_ value: Bool) {}

    // Replies already arrive on the thread the operation started on.
    @ObjCMethod("scheduleInRunLoop:forMode:") func schedule(in runLoop: ObjCObject?, forMode mode: ObjCObject?) {}
    @ObjCMethod("removeFromRunLoop:forMode:") func remove(from runLoop: ObjCObject?, forMode mode: ObjCObject?) {}
    @ObjCMethod("startMonitoring") func startMonitoring() {}
    @ObjCMethod("stopMonitoring") func stopMonitoring() {}

    @ObjCMethod("description")
    func description() -> String {
        "<NSNetService \(objcObject)> \(storage.domain) \(storage.type) \(storage.name)"
    }

    /// Reports a failure on the next run loop turn, as Darwin reports
    /// errors it finds without asking the daemon.
    private func fail(_ code: Int, _ event: @escaping (NSNetService, id) -> Void) {
        let operation = NetOperation(object: objcObject, home: Threads.current)
        let me = self
        operation.enqueue { me.storage.operation = nil; event(me, NetServices.errorDictionary(code)) }
        operation.stop()
    }

    @ObjCMethod("publish") func publish() { publish(options: 0) }

    /// Options: 1 is NSNetServiceNoAutoRename.
    @ObjCMethod("publishWithOptions:")
    func publish(options: Int) {
        let storage = storage
        let didNotPublish = { (service: NSNetService, error: id) in
            _ = service.delegateObject?.netService(service, didNotPublish: ObjCObject(error))
        }
        guard storage.operation == nil else { return fail(NetServices.activityInProgress, didNotPublish) }
        guard DNSSD.available, let register = DNSSD.register else { return fail(NetServices.unknownError, didNotPublish) }
        guard NetServices.isValidType(storage.type), storage.port >= 0 else {
            return fail(NetServices.badArgumentError, didNotPublish)
        }
        let operation = NetOperation(object: objcObject, home: Threads.current)
        storage.operation = operation
        let me = self
        operation.enqueue { _ = me.delegateObject?.netServiceWillPublish(me) }

        let context = Unmanaged.passUnretained(operation).toOpaque()
        var ref: DNSSD.Ref?
        let type = NetServices.undotted(storage.type)
        let domain = NetServices.undotted(storage.domain)
        let port = UInt16(truncatingIfNeeded: storage.port).bigEndian
        let flags: UInt32 = options & 1 != 0 ? DNSSD.noAutoRename : 0
        let txt = storage.txtData ?? Data()
        let error = storage.name.withCString { name in
            type.withCString { type in
                domain.withCString { domain in
                    txt.withUnsafeBytes { bytes in
                        register(&ref, flags, 0, storage.name.isEmpty ? nil : name, type,
                                 domain.pointee == 0 ? nil : domain, nil, port, UInt16(txt.count),
                                 bytes.count == 0 ? nil : bytes.baseAddress, registerReply, context)
                    }
                }
            }
        }
        guard error == 0, let made = ref else {
            storage.operation = nil
            operation.enqueue {
                _ = me.delegateObject?.netService(me, didNotPublish: ObjCObject(NetServices.errorDictionary(NetServices.code(error))))
            }
            operation.stop()
            return
        }
        operation.refs = [made]
        operation.step = { _, ref in DNSSD.process?(ref) == 0 }
        operation.start()
    }

    @ObjCMethod("resolve") func resolve() { resolve(withTimeout: 5) }

    /// Resolves the service's host, port, addresses and TXT record; a
    /// timeout of 0 keeps trying until stopped.
    @ObjCMethod("resolveWithTimeout:")
    func resolve(withTimeout timeout: Double) {
        let storage = storage
        let didNotResolve = { (service: NSNetService, error: id) in
            _ = service.delegateObject?.netService(service, didNotResolve: ObjCObject(error))
        }
        guard storage.operation == nil else { return fail(NetServices.activityInProgress, didNotResolve) }
        guard DNSSD.available, let resolve = DNSSD.resolve else { return fail(NetServices.unknownError, didNotResolve) }
        let operation = NetOperation(object: objcObject, home: Threads.current)
        storage.operation = operation
        let me = self
        operation.enqueue { _ = me.delegateObject?.netServiceWillResolve(me) }

        let context = Unmanaged.passUnretained(operation).toOpaque()
        var ref: DNSSD.Ref?
        let type = NetServices.undotted(storage.type)
        let domain = NetServices.undotted(storage.domain.isEmpty ? "local." : storage.domain)
        let error = storage.name.withCString { name in
            type.withCString { type in
                domain.withCString { domain in
                    resolve(&ref, 0, 0, name, type, domain, resolveReply, context)
                }
            }
        }
        guard error == 0, let made = ref else {
            storage.operation = nil
            operation.enqueue {
                _ = me.delegateObject?.netService(me, didNotResolve: ObjCObject(NetServices.errorDictionary(NetServices.code(error))))
            }
            operation.stop()
            return
        }
        if timeout > 0 { operation.deadline = NetServices.now() + timeout }
        operation.refs = [made]
        operation.step = { _, ref in DNSSD.process?(ref) == 0 }
        operation.timePassed = { operation in
            let time = NetServices.now()
            if let grace = operation.grace, time >= grace {
                // The addresses collected: one delivery with all of them.
                operation.grace = nil
                operation.delivered = true
                let (host, port, txt, addresses) = (operation.hostName, operation.port, operation.txt, operation.addresses)
                operation.enqueue {
                    me.storage.hostName = host
                    me.storage.port = port
                    if let txt { me.storage.txtData = txt }
                    me.storage.addresses = addresses
                    _ = me.delegateObject?.netServiceDidResolveAddress(me)
                }
                return false
            }
            if let deadline = operation.deadline, time >= deadline {
                if !operation.delivered {
                    operation.enqueue {
                        me.storage.operation = nil
                        _ = me.delegateObject?.netService(me, didNotResolve: ObjCObject(NetServices.errorDictionary(NetServices.timeoutError)))
                    }
                }
                return false
            }
            return true
        }
        operation.start()
    }

    @ObjCMethod("stop")
    func stop() {
        let storage = storage
        guard let operation = storage.operation else { return }
        storage.operation = nil
        operation.stop()
        let me = self
        operation.enqueue { _ = me.delegateObject?.netServiceDidStop(me) }
    }

    // MARK: TXT records

    /// The TXT record for a dictionary of data (or string) values:
    /// length-prefixed "key=value" entries, a bare key for an empty value.
    /// An empty dictionary has no data, as on Darwin.
    @ObjCClassMethod("dataFromTXTRecordDictionary:")
    static func data(fromTXTRecordDictionary dictionary: ObjCObject?) -> UnsafeMutableRawPointer? {
        guard let dictionary else { return nil }
        let entries = Dictionaries.entries(dictionary.id)
        guard !entries.isEmpty else { return nil }
        var bytes: [UInt8] = []
        for (key, value) in entries {
            guard let name = Strings.value(of: key) else { continue }
            var entry = Array(name.utf8)
            let data: [UInt8]
            if Nulls.isNull(value) {
                data = []
            } else if let string = Strings.value(of: value) {
                data = Array(string.utf8)
            } else if ObjC.isKind(value, of: DataObjects.dataClass) {
                data = Array(DataObjects.data(value))
            } else {
                continue
            }
            if !data.isEmpty { entry += [UInt8(ascii: "=")] + data }
            guard entry.count <= 255 else { continue }
            bytes += [UInt8(entry.count)] + entry
        }
        return DataObjects.autoreleased(Data(bytes))
    }

    /// The dictionary in a TXT record: data values, NSNull where an entry
    /// has no "=", the first of repeated keys. Empty data has no
    /// dictionary, as on Darwin.
    @ObjCClassMethod("dictionaryFromTXTRecordData:")
    static func dictionary(fromTXTRecordData data: ObjCObject?) -> UnsafeMutableRawPointer? {
        guard let data else { return nil }
        let bytes = Array(DataObjects.data(data.id))
        guard !bytes.isEmpty else { return nil }
        var entries: [(key: id, value: id)] = []
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
            let value: id
            if let equals = entry.firstIndex(of: UInt8(ascii: "=")) {
                key = entry[entry.startIndex..<equals]
                value = DataObjects.autoreleased(Data(entry[(equals + 1)...])) ?? Nulls.null
            } else {
                key = entry
                value = Nulls.null
            }
            guard !key.isEmpty else { continue }
            let name = String(decoding: key, as: UTF8.self)
            guard names.insert(name).inserted else { continue }
            entries.append((key: Strings.autoreleased(name), value: value))
        }
        return Dictionaries.autoreleased(entries)
    }

    /// Runs events the workers queued; performed onto the home thread.
    @ObjCMethod("_perryDeliverNetEvents")
    func deliverNetEvents() {
        NetDeliveries.deliver(for: objcObject)
    }
}

/// DNSServiceRegister's reply: the published (maybe renamed) name and
/// domain, or the error.
private let registerReply: DNSSD.RegisterReply = { _, _, error, name, _, domain, context in
    guard let context else { return }
    let operation = Unmanaged<NetOperation>.fromOpaque(context).takeUnretainedValue()
    let object = operation.object
    if error == 0 {
        let published = name.map { String(cString: $0) }
        let domain = domain.map { NetServices.dotted(String(cString: $0)) }
        operation.enqueue {
            let service = NSNetService(objCArgument: object)
            if let published { service.storage.name = published }
            if let domain { service.storage.domain = domain }
            _ = service.delegateObject?.netServiceDidPublish(service)
        }
    } else {
        operation.failed = true
        let code = NetServices.code(error)
        operation.enqueue {
            let service = NSNetService(objCArgument: object)
            service.storage.operation = nil
            _ = service.delegateObject?.netService(service, didNotPublish: ObjCObject(NetServices.errorDictionary(code)))
        }
    }
}

/// DNSServiceResolve's reply: the host, port and TXT record; address
/// queries follow, delivered together after a short wait.
private let resolveReply: DNSSD.ResolveReply = { _, _, interface, error, _, host, port, txtLength, txt, context in
    guard let context else { return }
    let operation = Unmanaged<NetOperation>.fromOpaque(context).takeUnretainedValue()
    if error != 0 {
        operation.failed = true
        guard !operation.delivered else { return }
        operation.delivered = true
        let code = NetServices.code(error)
        let object = operation.object
        operation.enqueue {
            let service = NSNetService(objCArgument: object)
            service.storage.operation = nil
            _ = service.delegateObject?.netService(service, didNotResolve: ObjCObject(NetServices.errorDictionary(code)))
        }
        return
    }
    guard operation.hostName == nil else { return }
    operation.hostName = host.map { NetServices.dotted(String(cString: $0)) }
    operation.port = Int(UInt16(bigEndian: port))
    if let txt, txtLength > 0 {
        operation.txt = Data(UnsafeBufferPointer(start: txt, count: Int(txtLength)))
    }
    operation.grace = NetServices.now() + 0.3
    // The host's addresses, over the same daemon.
    if let query = DNSSD.queryRecord, let host {
        let context = Unmanaged.passUnretained(operation).toOpaque()
        for type in [DNSSD.typeA, DNSSD.typeAAAA] {
            var ref: DNSSD.Ref?
            if query(&ref, 0, interface, host, type, DNSSD.classIN, queryReply, context) == 0, let ref {
                operation.refs.append(ref)
            }
        }
    }
}

/// DNSServiceQueryRecord's reply: one of the host's address records.
private let queryReply: DNSSD.QueryReply = { _, flags, interface, error, _, type, _, length, bytes, _, context in
    guard let context, error == 0, flags & DNSSD.add != 0, let bytes else { return }
    let operation = Unmanaged<NetOperation>.fromOpaque(context).takeUnretainedValue()
    var address: Data?
    if type == DNSSD.typeA, length == 4 {
        address = NetServices.socketAddress(ipv4: bytes, port: operation.port)
    } else if type == DNSSD.typeAAAA, length == 16 {
        address = NetServices.socketAddress(ipv6: bytes, port: operation.port, interface: interface)
    }
    if let address, !operation.addresses.contains(address) {
        operation.addresses.append(address)
    }
}

// MARK: - NSNetServiceBrowser

final class NetBrowserStorage {
    /// The delegate; not retained.
    var delegate: UnsafeMutableRawPointer?
    var operation: NetOperation?
    /// The services found, by "name|type|domain", alive until removed.
    var services: [String: id] = [:]

    func releaseServices() {
        services.values.forEach { ObjC.release($0) }
        services = [:]
    }
}

/// NSNetServiceBrowser: finds services of a type, or browsable domains.
@ObjCClass("NSNetServiceBrowser")
public final class NSNetServiceBrowser: NSObject {
    override public class func didDefineObjCClass(_ cls: ObjCClass) {
        NSObject.registerObjCCategoryStorageAllocated(cls)
        NetObjects.browserClass = cls.storage
    }

    var storage: NetBrowserStorage {
        if let storage = Storage.get(objcObject, as: NetBrowserStorage.self) { return storage }
        let storage = NetBrowserStorage()
        Storage.set(objcObject, storage)
        return storage
    }

    var delegateObject: AnyNSNetServiceBrowserDelegate? { storage.delegate.map { AnyNSNetServiceBrowserDelegate($0) } }

    @ObjCMethod("dealloc")
    func dealloc() {
        storage.releaseServices()
        NetDeliveries.forget(objcObject)
        Storage.set(objcObject, nil)
        ObjC.superDealloc(objcObject, from: NetObjects.browserClass)
    }

    @ObjCMethod("init")
    func initialize() -> Self {
        Storage.set(objcObject, NetBrowserStorage())
        return self
    }

    @ObjCMethod("delegate") func delegate() -> NSObject? { storage.delegate.map { NSObject(objCArgument: $0) } }
    @ObjCMethod("setDelegate:") func setDelegate(_ delegate: NSObject?) { storage.delegate = delegate?.objcObject }
    @ObjCMethod("includesPeerToPeer") func includesPeerToPeer() -> Bool { false }
    @ObjCMethod("setIncludesPeerToPeer:") func setIncludesPeerToPeer(_ value: Bool) {}
    @ObjCMethod("scheduleInRunLoop:forMode:") func schedule(in runLoop: ObjCObject?, forMode mode: ObjCObject?) {}
    @ObjCMethod("removeFromRunLoop:forMode:") func remove(from runLoop: ObjCObject?, forMode mode: ObjCObject?) {}

    /// Reports a failure on the next run loop turn.
    private func fail(_ code: Int) {
        let operation = NetOperation(object: objcObject, home: Threads.current)
        let me = self
        operation.enqueue {
            _ = me.delegateObject?.netServiceBrowser(me, didNotSearch: ObjCObject(NetServices.errorDictionary(code)))
        }
        operation.stop()
    }

    @ObjCMethod("searchForServicesOfType:inDomain:")
    func search(forServicesOfType type: String, inDomain domain: String) {
        let storage = storage
        guard storage.operation == nil else { return fail(NetServices.activityInProgress) }
        guard DNSSD.available, let browse = DNSSD.browse else { return fail(NetServices.unknownError) }
        guard NetServices.isValidType(type) else { return fail(NetServices.badArgumentError) }
        let me = self
        let operation = NetOperation(object: objcObject, home: Threads.current)
        storage.operation = operation
        operation.enqueue { _ = me.delegateObject?.netServiceBrowserWillSearch(me) }

        let context = Unmanaged.passUnretained(operation).toOpaque()
        var ref: DNSSD.Ref?
        let bare = NetServices.undotted(type)
        let bareDomain = NetServices.undotted(domain)
        let error = bare.withCString { type in
            bareDomain.withCString { domain in
                browse(&ref, 0, 0, type, domain.pointee == 0 ? nil : domain, browseReply, context)
            }
        }
        guard error == 0, let made = ref else {
            storage.operation = nil
            operation.enqueue {
                _ = me.delegateObject?.netServiceBrowser(me, didNotSearch: ObjCObject(NetServices.errorDictionary(NetServices.code(error))))
            }
            operation.stop()
            return
        }
        operation.refs = [made]
        operation.step = { _, ref in DNSSD.process?(ref) == 0 }
        operation.start()
    }

    /// The browsable domains: "local.", which mDNSResponder always finds,
    /// then any others Avahi enumerates (it leaves out "local.").
    @ObjCMethod("searchForBrowsableDomains")
    func searchForBrowsableDomains() {
        let storage = storage
        guard storage.operation == nil else { return fail(NetServices.activityInProgress) }
        guard DNSSD.available else { return fail(NetServices.unknownError) }
        let me = self
        let operation = NetOperation(object: objcObject, home: Threads.current)
        storage.operation = operation
        operation.enqueue {
            _ = me.delegateObject?.netServiceBrowserWillSearch(me)
            _ = me.delegateObject?.netServiceBrowser(me, didFindDomain: "local.", moreComing: false)
        }
        let context = Unmanaged.passUnretained(operation).toOpaque()
        var ref: DNSSD.Ref?
        guard let enumerate = DNSSD.enumerateDomains, enumerate(&ref, DNSSD.browseDomains, 0, domainReply, context) == 0, let made = ref else { return }
        operation.refs = [made]
        operation.step = { _, ref in DNSSD.process?(ref) == 0 }
        operation.start()
    }

    @ObjCMethod("stop")
    func stop() {
        let storage = storage
        guard let operation = storage.operation else { return }
        storage.operation = nil
        operation.stop()
        let me = self
        operation.enqueue {
            me.storage.releaseServices()
            _ = me.delegateObject?.netServiceBrowserDidStopSearch(me)
        }
    }

    @ObjCMethod("_perryDeliverNetEvents")
    func deliverNetEvents() {
        NetDeliveries.deliver(for: objcObject)
    }
}

/// DNSServiceBrowse's reply: a service appeared or went, on one
/// interface; the delegate hears of the first and the last only.
private let browseReply: DNSSD.BrowseReply = { _, flags, _, error, name, type, domain, context in
    guard let context else { return }
    let operation = Unmanaged<NetOperation>.fromOpaque(context).takeUnretainedValue()
    let object = operation.object
    if error != 0 {
        operation.failed = true
        let code = NetServices.code(error)
        operation.enqueue {
            let browser = NSNetServiceBrowser(objCArgument: object)
            browser.storage.operation = nil
            _ = browser.delegateObject?.netServiceBrowser(browser, didNotSearch: ObjCObject(NetServices.errorDictionary(code)))
        }
        return
    }
    guard let name, let type, let domain else { return }
    let service = String(cString: name)
    let dottedType = NetServices.dotted(String(cString: type))
    let dottedDomain = NetServices.dotted(String(cString: domain))
    let key = "\(service)|\(dottedType)|\(dottedDomain)"
    let more = flags & DNSSD.moreComing != 0
    if flags & DNSSD.add != 0 {
        let count = (operation.found[key] ?? 0) + 1
        operation.found[key] = count
        guard count == 1 else { return }
        operation.enqueue {
            let browser = NSNetServiceBrowser(objCArgument: object)
            let found = NetObjects.makeService(domain: dottedDomain, type: dottedType, name: service)
            browser.storage.services[key] = ObjC.retain(found)
            _ = browser.delegateObject?.netServiceBrowser(browser, didFindService: NSNetService(objCArgument: found),
                                                      moreComing: more)
        }
    } else {
        let count = (operation.found[key] ?? 1) - 1
        if count > 0 {
            operation.found[key] = count
            return
        }
        operation.found[key] = nil
        operation.enqueue {
            let browser = NSNetServiceBrowser(objCArgument: object)
            let going = browser.storage.services.removeValue(forKey: key)
                ?? ObjC.retain(NetObjects.makeService(domain: dottedDomain, type: dottedType, name: service))!
            _ = browser.delegateObject?.netServiceBrowser(browser, didRemoveService: NSNetService(objCArgument: going),
                                                      moreComing: more)
            ObjC.release(going)
        }
    }
}

/// DNSServiceEnumerateDomains' reply: a browsable domain.
private let domainReply: DNSSD.DomainReply = { _, flags, _, error, domain, context in
    guard let context, error == 0, let domain else { return }
    let operation = Unmanaged<NetOperation>.fromOpaque(context).takeUnretainedValue()
    let object = operation.object
    let name = NetServices.dotted(String(cString: domain))
    // "local." was reported when the search began.
    guard name != "local." else { return }
    let more = flags & DNSSD.moreComing != 0
    let added = flags & DNSSD.add != 0
    operation.enqueue {
        let browser = NSNetServiceBrowser(objCArgument: object)
        if added {
            _ = browser.delegateObject?.netServiceBrowser(browser, didFindDomain: name, moreComing: more)
        } else {
            _ = browser.delegateObject?.netServiceBrowser(browser, didRemoveDomain: name, moreComing: more)
        }
    }
}
