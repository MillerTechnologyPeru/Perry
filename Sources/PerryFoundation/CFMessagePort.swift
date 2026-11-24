import CPerryFoundation
import FoundationEssentials
import Glibc
import PerryObjCInterop

// CFMessagePort within one process. A local port is listed under its name,
// and a remote port made with that name sends to it; there are no other
// processes to reach, so a name no local port here has gives no remote
// port, as on Darwin when nothing has registered the name. A request waits
// on the local port until its run loop source, or its dispatch queue,
// gives it to the callout; a sender that wants the reply runs its own run
// loop meanwhile, as Darwin's does in the reply mode, so a local port on
// the sender's own run loop answers too.

/// CFMessagePortCallBack: (local port, message ID, data, info), returning
/// the reply, which the port releases.
public typealias CFMessagePortCallout = @convention(c) (UnsafeMutableRawPointer?, Int32, UnsafeMutableRawPointer?,
                                                        UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer?

/// CFMessagePortInvalidationCallBack: (port, info).
public typealias CFMessagePortInvalidation = @convention(c) (UnsafeMutableRawPointer?, UnsafeMutableRawPointer?) -> Void

/// CFMessagePortSendRequest's results.
enum MessagePortResult {
    static let success: Int32 = 0, sendTimeout: Int32 = -1, receiveTimeout: Int32 = -2, isInvalid: Int32 = -3
    static let transportError: Int32 = -4, becameInvalid: Int32 = -5
}

/// A message sent to a local port. Guarded by MessagePorts' lock.
final class MessagePortRequest {
    let messageID: Int32
    /// +1.
    let data: id?
    let wantsReply: Bool
    /// The sender's run loop, woken when the reply comes.
    let loop: RunLoopState?
    var finished = false
    /// The sender stopped waiting.
    var abandoned = false
    var status = MessagePortResult.success
    /// +1.
    var reply: id?

    init(messageID: Int32, data: id?, wantsReply: Bool, loop: RunLoopState?) {
        (self.messageID, self.data, self.wantsReply, self.loop) = (messageID, data, wantsReply, loop)
    }

    deinit {
        ObjC.release(data)
        ObjC.release(reply)
    }
}

final class MessagePortStorage: FiringSource {
    let isRemote: Bool
    let callout: CFMessagePortCallout?
    let context: InfoContext
    /// The CFMessagePort, not retained: it owns this.
    var object: id?
    /// Guarded by MessagePorts' lock from here.
    var name: String?
    /// The name as a CFString, +1, for CFMessagePortGetName.
    var nameObject: id?
    /// A port made per process, listed under its process's ID too.
    let perProcess: Bool
    var valid = true
    var invalidation: CFMessagePortInvalidation?
    /// A remote port's local port, and a local port's remote ports.
    var local: MessagePortStorage?
    var remotes: [MessagePortStorage] = []
    var pending: [MessagePortRequest] = []
    var source: (object: id, storage: CustomSourceStorage)?
    /// Retained.
    var queue: id?

    init(isRemote: Bool, perProcess: Bool, name: String?, callout: CFMessagePortCallout?, context: InfoContext) {
        (self.isRemote, self.perProcess, self.name, self.callout, self.context) = (isRemote, perProcess, name, callout, context)
        nameObject = name.map { Strings.make($0) }
    }

    deinit {
        ObjC.release(nameObject)
        ObjC.release(queue)
    }

    /// The requests that came, on the source's run loop.
    func fire() { MessagePorts.deliver(self) }
}

enum MessagePorts {
    nonisolated(unsafe) static var portClass: Class!
    static let typeID: UInt = 35

    nonisolated(unsafe) private static let mutex: UnsafeMutablePointer<pthread_mutex_t> = {
        let mutex = UnsafeMutablePointer<pthread_mutex_t>.allocate(capacity: 1)
        pthread_mutex_init(mutex, nil)
        return mutex
    }()
    /// The valid local ports, by their key.
    nonisolated(unsafe) private static var locals: [String: MessagePortStorage] = [:]

    static func storage(_ port: id?) -> MessagePortStorage? { Storage.get(port, as: MessagePortStorage.self) }

    static func locked<T>(_ body: () -> T) -> T {
        pthread_mutex_lock(mutex)
        defer { pthread_mutex_unlock(mutex) }
        return body()
    }

    /// Where a local port is listed: a per-process one under this process's
    /// ID as well.
    static func key(_ name: String, perProcess: Bool, pid: Int = Int(getpid())) -> String {
        perProcess ? "\(pid)/\(name)" : name
    }

    private static func make(_ storage: MessagePortStorage) -> id? {
        guard let object = Storage.allocate(UnsafeMutableRawPointer(portClass)) else { return nil }
        storage.object = object
        Storage.set(object, storage)
        return object
    }

    /// A local port (+1) listed under its name; the one already listed,
    /// retained, with `shouldFreeInfo` set, as Darwin gives it.
    static func createLocal(_ name: id?, perProcess: Bool, _ callout: CFMessagePortCallout?, _ context: UnsafeRawPointer?,
                            _ shouldFreeInfo: UnsafeMutablePointer<UInt8>?) -> id? {
        shouldFreeInfo?.pointee = 0
        let text = Strings.value(of: name)
        if let text, let existing = locked({ locals[key(text, perProcess: perProcess)].flatMap { $0.valid ? $0.object : nil } }) {
            shouldFreeInfo?.pointee = 1
            return ObjC.retain(existing)
        }
        let storage = MessagePortStorage(isRemote: false, perProcess: perProcess, name: text, callout: callout,
                                         context: InfoContext(retaining: context))
        guard let object = make(storage) else {
            storage.context.released()
            shouldFreeInfo?.pointee = 1
            return nil
        }
        if let text { locked { locals[key(text, perProcess: perProcess)] = storage } }
        return object
    }

    /// A remote port (+1) that sends to the local port listed where `listing`
    /// says; NULL when there is none.
    static func createRemote(_ name: id?, listing: (String) -> String) -> id? {
        guard let text = Strings.value(of: name) else { return nil }
        let listed = listing(text)
        let storage = MessagePortStorage(isRemote: true, perProcess: false, name: text, callout: nil, context: InfoContext())
        let found = locked { () -> Bool in
            guard let local = locals[listed], local.valid else { return false }
            storage.local = local
            local.remotes.append(storage)
            return true
        }
        guard found else { return nil }
        guard let object = make(storage) else {
            invalidate(storage)
            return nil
        }
        return object
    }

    /// Lists a valid local port under a new name, unless another has it.
    static func rename(_ port: MessagePortStorage, _ text: String) -> Bool {
        let newName = Strings.make(text)
        let old = locked { () -> id?? in
            guard port.valid else { return nil }
            let listed = key(text, perProcess: port.perProcess)
            if let other = locals[listed], other !== port { return nil }
            if let current = port.name {
                let previous = key(current, perProcess: port.perProcess)
                if locals[previous] === port { locals[previous] = nil }
            }
            locals[listed] = port
            port.name = text
            defer { port.nameObject = newName }
            return .some(port.nameObject)
        }
        guard let old else {
            ObjC.release(newName)
            return false
        }
        ObjC.release(old)
        return true
    }

    /// Gives the local port's requests, one by one, to its callout, and
    /// each reply to its sender.
    static func deliver(_ port: MessagePortStorage) {
        while true {
            let next = locked { () -> (MessagePortRequest, id)? in
                guard port.valid, let object = port.object, !port.pending.isEmpty else { return nil }
                return (port.pending.removeFirst(), object)
            }
            guard let (request, object) = next else { return }
            let reply = ObjC.autoreleasepool { () -> id? in
                let answer = port.callout?(object, request.messageID, request.data, port.context.info)
                // A copy, so the callout can't change it after.
                defer { ObjC.release(answer) }
                return answer.flatMap { CFDataCreateCopy(nil, $0) }
            }
            complete(request, reply: reply, status: MessagePortResult.success)
        }
    }

    /// Finishes a request with its reply (+1, taken), waking its sender.
    static func complete(_ request: MessagePortRequest, reply: id?, status: Int32) {
        let kept = locked { () -> Bool in
            guard !request.finished, !request.abandoned, request.wantsReply else { return false }
            request.finished = true
            request.status = status
            request.reply = reply
            return true
        }
        if !kept {
            locked { request.finished = true }
            ObjC.release(reply)
        }
        request.loop?.perform(work: {})
    }

    /// Puts a request on the local port and has its source or queue give
    /// it; false when the port is invalid.
    static func enqueue(_ request: MessagePortRequest, on port: MessagePortStorage) -> Bool {
        let target = locked { () -> (source: CustomSourceStorage?, queue: id?)? in
            guard port.valid else { return nil }
            port.pending.append(request)
            return (port.source?.storage, port.queue.flatMap { ObjC.retain($0) })
        }
        guard let target else { return false }
        target.source?.signal()
        if let queue = target.queue {
            drain(port, on: queue)
            ObjC.release(queue)
        }
        return true
    }

    /// Gives the port's requests to its callout on `queue`.
    static func drain(_ port: MessagePortStorage, on queue: id) {
        DispatchedWork.async(queue) { deliver(port) }
    }

    /// Once: the port unlisted, its waiting senders told it became invalid,
    /// a local port's remote ports invalid too, the invalidation callout,
    /// the source invalid and the info released. A remote port's callout
    /// is made here, on the thread that invalidated its local port, rather
    /// than when its run loop hears of it.
    static func invalidate(_ port: MessagePortStorage) {
        typealias State = (pending: [MessagePortRequest], remotes: [MessagePortStorage],
                           source: (object: id, storage: CustomSourceStorage)?, invalidation: CFMessagePortInvalidation?)
        let state = locked { () -> State? in
            guard port.valid else { return nil }
            port.valid = false
            if !port.isRemote, let name = port.name {
                let listed = key(name, perProcess: port.perProcess)
                if locals[listed] === port { locals[listed] = nil }
            }
            port.local?.remotes.removeAll { $0 === port }
            port.local = nil
            defer {
                port.pending = []
                port.remotes = []
                port.source = nil
            }
            return (port.pending, port.remotes, port.source, port.invalidation)
        }
        guard let state else { return }
        for request in state.pending { complete(request, reply: nil, status: MessagePortResult.becameInvalid) }
        for remote in state.remotes { invalidate(remote) }
        if let object = port.object { state.invalidation?(object, port.context.info) }
        if let source = state.source {
            source.storage.remove(from: nil)
            ObjC.release(source.object)
        }
        port.object = nil
        port.context.released()
    }
}

@ObjCClass("__NSCFMessagePort")
final class NSCFMessagePort: NSObject {
    override class func didDefineObjCClass(_ cls: ObjCClass) {
        NSObject.registerObjCCategoryStorageAllocated(cls)
        MessagePorts.portClass = cls.storage
    }

    @ObjCMethod("dealloc")
    func dealloc() {
        MessagePorts.storage(objcObject).map(MessagePorts.invalidate)
        Storage.set(objcObject, nil)
        ObjC.superDealloc(objcObject, from: MessagePorts.portClass)
    }

    @ObjCMethod("_cfTypeID") func cfTypeID() -> UInt { MessagePorts.typeID }
}

@c(_CFMessagePortGetTypeID) public func CFMessagePortGetTypeID() -> UInt { MessagePorts.typeID }

/// A local port (+1) under the name (none for NULL), its context's info
/// retained. A name a local port here already has gives that port,
/// retained, with `shouldFreeInfo` set, as on Darwin.
@c(_CFMessagePortCreateLocal)
public func CFMessagePortCreateLocal(_ allocator: UnsafeRawPointer?, _ name: id?, _ callout: CFMessagePortCallout?,
                                     _ context: UnsafeRawPointer?, _ shouldFreeInfo: UnsafeMutablePointer<UInt8>?) -> id? {
    MessagePorts.createLocal(name, perProcess: false, callout, context, shouldFreeInfo)
}

/// A local port (+1) that CFMessagePortCreatePerProcessRemote finds by the
/// name and this process's ID.
@c(_CFMessagePortCreatePerProcessLocal)
public func CFMessagePortCreatePerProcessLocal(_ allocator: UnsafeRawPointer?, _ name: id?, _ callout: CFMessagePortCallout?,
                                               _ context: UnsafeRawPointer?, _ shouldFreeInfo: UnsafeMutablePointer<UInt8>?) -> id? {
    MessagePorts.createLocal(name, perProcess: true, callout, context, shouldFreeInfo)
}

/// A remote port (+1) to the local port of that name in this process; NULL
/// when there is none, as for a name nothing has registered: no other
/// process can be reached here.
@c(_CFMessagePortCreateRemote)
public func CFMessagePortCreateRemote(_ allocator: UnsafeRawPointer?, _ name: id?) -> id? {
    MessagePorts.createRemote(name) { MessagePorts.key($0, perProcess: false) }
}

/// A remote port (+1) to a per-process local port: one of this process's,
/// as another process's can't be reached.
@c(_CFMessagePortCreatePerProcessRemote)
public func CFMessagePortCreatePerProcessRemote(_ allocator: UnsafeRawPointer?, _ name: id?, _ pid: Int) -> id? {
    guard pid == Int(getpid()) else { return nil }
    return MessagePorts.createRemote(name) { MessagePorts.key($0, perProcess: true, pid: pid) }
}

@c(_CFMessagePortIsRemote) public func CFMessagePortIsRemote(_ port: id?) -> Bool { MessagePorts.storage(port)?.isRemote ?? false }

@c(_CFMessagePortIsValid)
public func CFMessagePortIsValid(_ port: id?) -> Bool {
    guard let storage = MessagePorts.storage(port) else { return false }
    return MessagePorts.locked { storage.valid }
}

/// The name, +0.
@c(_CFMessagePortGetName)
public func CFMessagePortGetName(_ port: id?) -> id? {
    guard let storage = MessagePorts.storage(port) else { return nil }
    return MessagePorts.locked { storage.nameObject }
}

/// Lists a valid local port under a new name: false for a remote port, or
/// a name another local port has.
@c(_CFMessagePortSetName)
public func CFMessagePortSetName(_ port: id?, _ name: id?) -> Bool {
    guard let storage = MessagePorts.storage(port), !storage.isRemote, let text = Strings.value(of: name) else { return false }
    return MessagePorts.rename(storage, text)
}

/// The context the port was made with: { version, info, retain, release,
/// copyDescription }, the info as retained.
@c(_CFMessagePortGetContext)
public func CFMessagePortGetContext(_ port: id?, _ context: UnsafeMutableRawPointer?) {
    MessagePorts.storage(port)?.context.store(to: context)
}

@c(_CFMessagePortInvalidate) public func CFMessagePortInvalidate(_ port: id?) { MessagePorts.storage(port).map(MessagePorts.invalidate) }

@c(_CFMessagePortGetInvalidationCallBack)
public func CFMessagePortGetInvalidationCallBack(_ port: id?) -> CFMessagePortInvalidation? {
    guard let storage = MessagePorts.storage(port) else { return nil }
    return MessagePorts.locked { storage.invalidation }
}

/// Called at once on a port already invalid, as on Darwin.
@c(_CFMessagePortSetInvalidationCallBack)
public func CFMessagePortSetInvalidationCallBack(_ port: id?, _ callout: CFMessagePortInvalidation?) {
    guard let port, let storage = MessagePorts.storage(port) else { return }
    let valid = MessagePorts.locked { () -> Bool in
        storage.invalidation = callout
        return storage.valid
    }
    if !valid { callout?(port, storage.context.info) }
}

/// A local port's one source (+1), made the first time; NULL for a remote
/// port, or one whose requests go to a dispatch queue.
@c(_CFMessagePortCreateRunLoopSource)
public func CFMessagePortCreateRunLoopSource(_ allocator: UnsafeRawPointer?, _ port: id?, _ order: Int) -> id? {
    guard let storage = MessagePorts.storage(port), !storage.isRemote else { return nil }
    let existing = MessagePorts.locked { () -> id?? in
        guard storage.valid, storage.queue == nil else { return .some(nil) }
        return storage.source.map { .some($0.object) }
    }
    if let existing { return existing.flatMap { ObjC.retain($0) } }
    guard let made = FiringSources.make(for: storage) else { return nil }
    let source = MessagePorts.locked { () -> (object: id, waiting: Bool) in
        if let current = storage.source { return (current.object, false) }
        storage.source = made
        return (made.0, !storage.pending.isEmpty)
    }
    if source.object != made.0 { ObjC.release(made.0) }
    // Requests sent before there was a source.
    if source.waiting { made.1.signal() }
    return ObjC.retain(source.object)
}

/// A local port's requests go to the queue (retained) rather than a run
/// loop; NULL stops them. Not for a port that has a run loop source, as on
/// Darwin. A remote port keeps the queue, but its invalidation callout is
/// made where its local port was invalidated.
@c(_CFMessagePortSetDispatchQueue)
public func CFMessagePortSetDispatchQueue(_ port: id?, _ queue: id?) {
    guard let storage = MessagePorts.storage(port) else { return }
    let retained = queue.flatMap { ObjC.retain($0) }
    let state = MessagePorts.locked { () -> (old: id?, drain: Bool)? in
        guard storage.valid, storage.source == nil else { return nil }
        defer { storage.queue = retained }
        return (storage.queue, !storage.isRemote && !storage.pending.isEmpty)
    }
    guard let state else {
        ObjC.release(retained)
        return
    }
    ObjC.release(state.old)
    if state.drain, let retained { MessagePorts.drain(storage, on: retained) }
}

/// Sends a request to the remote port's local port. With a reply mode, the
/// sender runs its run loop until the reply comes or `receiveTimeout`
/// seconds pass, and the reply is +1 in `returnData`; without one, it
/// returns once the request is queued. The queue is never full, so
/// `sendTimeout` never runs out. A CFMessagePortSendRequest result: 0,
/// -2 for no reply in time, -3 for a port that is invalid or not remote,
/// -5 for a local port invalidated before it answered.
@c(_CFMessagePortSendRequest)
public func CFMessagePortSendRequest(_ remote: id?, _ messageID: Int32, _ data: id?, _ sendTimeout: Double.ObjCType,
                                     _ receiveTimeout: Double.ObjCType, _ replyMode: id?,
                                     _ returnData: UnsafeMutablePointer<id?>?) -> Int32 {
    guard let storage = MessagePorts.storage(remote), storage.isRemote,
          let local = MessagePorts.locked({ storage.valid ? storage.local : nil }) else { return MessagePortResult.isInvalid }
    let copy = data.flatMap { CFDataCreateCopy(nil, $0) } ?? CFDataCreate(nil, nil, 0)
    let wantsReply = replyMode != nil
    let loop = wantsReply ? RunLoops.current : nil
    let request = MessagePortRequest(messageID: messageID, data: copy, wantsReply: wantsReply, loop: loop)
    guard MessagePorts.enqueue(request, on: local) else {
        MessagePorts.invalidate(storage)
        return MessagePortResult.isInvalid
    }
    guard let loop else { return MessagePortResult.success }
    let deadline = absoluteTimeNow() + max(Double(objCArgument: receiveTimeout), 0)
    var ran = false
    while true {
        let outcome = MessagePorts.locked { () -> (status: Int32, reply: id?)? in
            if request.finished {
                defer { request.reply = nil }
                return (request.status, request.reply)
            }
            guard ran, absoluteTimeNow() >= deadline else { return nil }
            request.abandoned = true
            return (MessagePortResult.receiveTimeout, nil)
        }
        if let outcome {
            if outcome.status == MessagePortResult.success, let returnData {
                returnData.pointee = outcome.reply
            } else {
                ObjC.release(outcome.reply)
            }
            return outcome.status
        }
        _ = loop.run(until: deadline, returnAfterSourceHandled: true, waitWhenEmpty: true)
        ran = true
    }
}
