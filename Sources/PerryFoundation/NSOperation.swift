import CPerryFoundation
import Glibc
import PerryObjCInterop

// NSOperation and NSOperationQueue, over libdispatch as Darwin's are.
//
// An operation's state is read through its messages (-isReady, -isFinished,
// -isCancelled), so subclasses' overrides apply. An asynchronous operation
// reports finishing as on Darwin, through key-value observing's
// -didChangeValueForKey:@"isFinished", which Foundation's NSObject sends on
// to the operation machinery; other objects' change notices go nowhere, as
// Perry has no key-value observing yet. Queues start operations on
// libdispatch's global queues, or on the main queue for +mainQueue.

/// libdispatch, which libSystem re-exports.
enum Dispatch {
    typealias Function = @convention(c) (UnsafeMutableRawPointer?) -> Void
    typealias Async = @convention(c) (UnsafeMutableRawPointer?, UnsafeMutableRawPointer?, Function) -> Void
    typealias GlobalQueue = @convention(c) (Int, UInt) -> UnsafeMutableRawPointer?
    nonisolated(unsafe) static var async: Async!
    nonisolated(unsafe) static var globalQueue: GlobalQueue!
    nonisolated(unsafe) static var mainQueue: UnsafeMutableRawPointer?
    /// Global blocks' isa, _NSConcreteGlobalBlock.
    nonisolated(unsafe) static var globalBlockClass: UnsafeMutableRawPointer?

    static func load(_ lookup: (String) -> UnsafeMutableRawPointer?) {
        globalBlockClass = lookup("__NSConcreteGlobalBlock")
        async = lookup("_dispatch_async_f").map { unsafeBitCast($0, to: Async.self) }
        globalQueue = lookup("_dispatch_get_global_queue").map { unsafeBitCast($0, to: GlobalQueue.self) }
        mainQueue = lookup("__dispatch_main_q")
    }
}

/// NSQualityOfService values, as dispatch's QoS classes.
private func dispatchQoS(_ quality: Int) -> Int {
    switch quality {
    case 0x21, 0x19, 0x11, 0x09: return quality
    default: return 0x15        // NSQualityOfServiceDefault: QOS_CLASS_DEFAULT
    }
}

private enum Messages {
    typealias Getter = @convention(c) (id, SEL) -> Bool
    typealias Action = @convention(c) (id, SEL) -> Void

    static func bool(_ object: id, _ name: String) -> Bool {
        unsafeBitCast(ObjC.msgSend, to: Getter.self)(object, ObjC.selector(name))
    }

    static func send(_ object: id, _ name: String) {
        unsafeBitCast(ObjC.msgSend, to: Action.self)(object, ObjC.selector(name))
    }
}

/// A mutex and condition variable.
final class Monitor: @unchecked Sendable {
    private let mutex = UnsafeMutablePointer<pthread_mutex_t>.allocate(capacity: 1)
    private let condition = UnsafeMutablePointer<pthread_cond_t>.allocate(capacity: 1)

    init() {
        var attributes = pthread_mutexattr_t()
        pthread_mutexattr_init(&attributes)
        pthread_mutexattr_settype(&attributes, Int32(PTHREAD_MUTEX_RECURSIVE))
        pthread_mutex_init(mutex, &attributes)
        pthread_mutexattr_destroy(&attributes)
        pthread_cond_init(condition, nil)
    }

    deinit {
        pthread_mutex_destroy(mutex)
        pthread_cond_destroy(condition)
        mutex.deallocate()
        condition.deallocate()
    }

    func locked<T>(_ body: () -> T) -> T {
        pthread_mutex_lock(mutex)
        defer { pthread_mutex_unlock(mutex) }
        return body()
    }

    func broadcast() {
        pthread_mutex_lock(mutex)
        pthread_cond_broadcast(condition)
        pthread_mutex_unlock(mutex)
    }

    /// Waits, under the lock, until `done` holds.
    func wait(until done: () -> Bool) {
        pthread_mutex_lock(mutex)
        while !done() { pthread_cond_wait(condition, mutex) }
        pthread_mutex_unlock(mutex)
    }
}

// MARK: - Operations

struct Dependent {
    weak var storage: OperationStorage?
}

final class OperationStorage {
    let monitor = Monitor()
    var cancelled = false
    var executing = false
    var finished = false
    /// Whether finishing has been handled: completion, waiters, dependents.
    var completed = false
    var dependencies: [id] = []
    /// The state of operations depending on this one, which each hold this
    /// one; weak, as a dependent may be freed first.
    var dependents: [Dependent] = []
    var completionBlock: id?
    var name: id?
    var queuePriority = 0
    var qualityOfService = -1
    /// The queue the operation was added to; queues outlive their operations.
    var queue: QueueStorage?
    /// NSBlockOperation's blocks.
    var blocks: [id] = []
    /// NSInvocationOperation's message: the target and argument, held,
    /// and the selector; and what it returned.
    var invocation: (target: id, selector: SEL, argument: id?)?
    var result: id?

    deinit {
        dependencies.forEach { ObjC.release($0) }
        blocks.forEach { ObjC.release($0) }
        if let invocation {
            ObjC.release(invocation.target)
            ObjC.release(invocation.argument)
        }
        ObjC.release(result)
        ObjC.release(completionBlock)
        ObjC.release(name)
    }
}

enum Operations {
    nonisolated(unsafe) static var operationClass: Class!
    nonisolated(unsafe) static var blockOperationClass: Class!
    private static let creation = Monitor()

    /// The operation's storage, made if its initializer did not run.
    static func storage(_ object: id) -> OperationStorage {
        creation.locked {
            if let storage = Storage.get(object, as: OperationStorage.self) { return storage }
            let storage = OperationStorage()
            Storage.set(object, storage)
            return storage
        }
    }

    static func isOperation(_ object: id) -> Bool {
        ObjC.isKind(object, of: operationClass)
    }

    /// -start's default: -main unless cancelled, then finished.
    static func start(_ object: id) {
        let storage = storage(object)
        let cancelled = storage.monitor.locked { () -> Bool in
            if !storage.cancelled { storage.executing = true }
            return storage.cancelled
        }
        if !cancelled { Messages.send(object, "main") }
        storage.monitor.locked {
            storage.executing = false
            storage.finished = true
        }
        didFinish(object)
    }

    /// Handles an operation's finishing once: its completion block, its
    /// waiters, its dependents and its queue.
    static func didFinish(_ object: id) {
        let storage = storage(object)
        let handled: (completion: id?, dependents: [Dependent], queue: QueueStorage?)? = storage.monitor.locked {
            guard !storage.completed else { return nil }
            storage.completed = true
            defer { storage.completionBlock = nil }
            return (storage.completionBlock, storage.dependents, storage.queue)
        }
        guard let handled else { return }
        storage.monitor.broadcast()
        if let completion = handled.completion {
            // On a secondary thread, as Darwin runs it; this takes over the
            // operation's reference.
            Dispatch.async(Dispatch.globalQueue(0x15, 0), completion, runBlockOnce)
        }
        handled.queue?.operationDidFinish(object)
        for dependent in handled.dependents { dependent.storage?.queue?.schedule() }
    }

    /// A ready operation's dependencies have finished; a cancelled one is
    /// always ready. A dependency has finished when it has been seen to
    /// finish (its -start returned finished, or it told of finishing with a
    /// change notice), as Darwin tracks it, rather than when its -isFinished
    /// says so now: an asynchronous operation's -isFinished may answer YES
    /// before it has started (Vungle's, "not running"), and its dependents
    /// then ran before it.
    static func isReady(_ object: id) -> Bool {
        let storage = storage(object)
        let (cancelled, dependencies) = storage.monitor.locked { (storage.cancelled, storage.dependencies) }
        return cancelled || dependencies.allSatisfy { isFinished($0) }
    }

    static func isFinished(_ object: id) -> Bool {
        let storage = storage(object)
        return storage.monitor.locked { storage.completed }
    }

    static func addDependency(_ object: id, _ dependency: id) {
        let storage = storage(object)
        let added = storage.monitor.locked { () -> Bool in
            guard !storage.dependencies.contains(dependency) else { return false }
            storage.dependencies.append(ObjC.retain(dependency)!)
            return true
        }
        guard added else { return }
        let other = self.storage(dependency)
        other.monitor.locked { other.dependents.append(Dependent(storage: storage)) }
    }

    /// Runs a block and releases it.
    static let runBlockOnce: Dispatch.Function = { block in
        guard let block else { return }
        ObjC.autoreleasepool { Blocks.invoke(block, as: (@convention(c) (id) -> Void).self)(block) }
        ObjC.release(block)
    }
}

/// NSOperation.
@ObjCClass("NSOperation")
public class NSOperation: NSObject {
    override public class func didDefineObjCClass(_ cls: ObjCClass) {
        NSObject.registerObjCCategoryStorageAllocated(cls)
        Operations.operationClass = cls.storage
    }

    var storage: OperationStorage { Operations.storage(objcObject) }

    @ObjCMethod("init")
    func initialize() -> Self {
        _ = storage
        return self
    }

    @ObjCMethod("dealloc")
    func dealloc() {
        Storage.set(objcObject, nil)
        ObjC.superDealloc(objcObject, from: Operations.operationClass)
    }

    @ObjCMethod("start") func start() { Operations.start(objcObject) }
    @ObjCMethod("main") func main() {}

    @ObjCMethod("cancel")
    func cancel() {
        let storage = self.storage
        storage.monitor.locked { storage.cancelled = true }
        // A cancelled operation is ready to run, to finish.
        storage.queue?.schedule()
    }

    @ObjCMethod("isCancelled") func isCancelled() -> Bool { storage.monitor.locked { storage.cancelled } }
    @ObjCMethod("isExecuting") func isExecuting() -> Bool { storage.monitor.locked { storage.executing } }
    @ObjCMethod("isFinished") func isFinished() -> Bool { storage.monitor.locked { storage.finished } }
    @ObjCMethod("isReady") func isReady() -> Bool { Operations.isReady(objcObject) }
    @ObjCMethod("isConcurrent") func isConcurrent() -> Bool { Messages.bool(objcObject, "isAsynchronous") }
    @ObjCMethod("isAsynchronous") func isAsynchronous() -> Bool { false }

    @ObjCMethod("addDependency:")
    func addDependency(_ operation: ObjCObject) { Operations.addDependency(objcObject, operation.id) }

    @ObjCMethod("removeDependency:")
    func removeDependency(_ operation: ObjCObject) {
        let storage = self.storage
        let removed = storage.monitor.locked { () -> Bool in
            guard let index = storage.dependencies.firstIndex(of: operation.id) else { return false }
            storage.dependencies.remove(at: index)
            return true
        }
        guard removed else { return }
        let other = Operations.storage(operation.id)
        other.monitor.locked { other.dependents.removeAll { $0.storage === storage || $0.storage == nil } }
        ObjC.release(operation.id)
        storage.queue?.schedule()
    }

    @ObjCMethod("dependencies")
    func dependencies() -> ObjCObject { ObjCObject(Arrays.autoreleased(storage.monitor.locked { storage.dependencies })) }

    @ObjCMethod("completionBlock")
    func completionBlock() -> ObjCObject? { storage.monitor.locked { storage.completionBlock }.map(ObjCObject.init) }

    @ObjCMethod("setCompletionBlock:")
    func setCompletionBlock(_ block: ObjCObject?) {
        let copy = block.flatMap { ObjC.retainBlock($0.id) }
        let old = storage.monitor.locked { () -> id? in
            defer { storage.completionBlock = copy }
            return storage.completionBlock
        }
        ObjC.release(old)
    }

    /// Waits until the operation finishes, as its queue or -start sees it.
    @ObjCMethod("waitUntilFinished")
    func waitUntilFinished() {
        let storage = self.storage
        storage.monitor.wait { storage.completed }
    }

    @ObjCMethod("name") func name() -> ObjCObject? { storage.monitor.locked { storage.name }.map(ObjCObject.init) }

    @ObjCMethod("setName:")
    func setName(_ name: ObjCObject?) {
        let copy = name.flatMap { ObjC.send($0.id, Selectors.copyWithZone, nil) }
        let old = storage.monitor.locked { () -> id? in
            defer { storage.name = copy }
            return storage.name
        }
        ObjC.release(old)
    }

    @ObjCMethod("queuePriority") func queuePriority() -> Int { storage.monitor.locked { storage.queuePriority } }

    /// Darwin keeps the nearest of its five levels.
    @ObjCMethod("setQueuePriority:")
    func setQueuePriority(_ priority: Int) {
        let level = [-8, -4, 0, 4, 8].min { abs($0 - priority) < abs($1 - priority) } ?? 0
        storage.monitor.locked { storage.queuePriority = level }
    }

    @ObjCMethod("qualityOfService") func qualityOfService() -> Int { storage.monitor.locked { storage.qualityOfService } }
    @ObjCMethod("setQualityOfService:")
    func setQualityOfService(_ quality: Int) { storage.monitor.locked { storage.qualityOfService = quality } }
}

/// NSBlockOperation.
@ObjCClass("NSBlockOperation")
public final class NSBlockOperation: NSOperation {
    override public class func didDefineObjCClass(_ cls: ObjCClass) {
        Operations.blockOperationClass = cls.storage
    }

    @ObjCClassMethod("blockOperationWithBlock:")
    static func make(_ cls: ObjCClass, block: ObjCObject) -> NSBlockOperation? {
        guard let object = Storage.allocate(cls.pointer) else { return nil }
        let storage = Operations.storage(object)
        storage.blocks.append(ObjC.retainBlock(block.id)!)
        return NSBlockOperation(objCOwned: object)
    }

    @ObjCMethod("addExecutionBlock:")
    func addExecutionBlock(_ block: ObjCObject) {
        let copy = ObjC.retainBlock(block.id)!
        storage.monitor.locked { storage.blocks.append(copy) }
    }

    @ObjCMethod("executionBlocks")
    func executionBlocks() -> ObjCObject { ObjCObject(Arrays.autoreleased(storage.monitor.locked { storage.blocks })) }

    /// Runs the blocks in turn.
    @ObjCMethod("main")
    func runBlocks() {
        for block in storage.monitor.locked({ storage.blocks }) {
            Blocks.invoke(block, as: (@convention(c) (id) -> Void).self)(block)
        }
    }
}

/// NSInvocationOperation: an operation that sends its target a message
/// with one object argument, keeping what it returns.
@ObjCClass("NSInvocationOperation")
public final class NSInvocationOperation: NSOperation {
    @ObjCMethod("initWithTarget:selector:object:")
    func initialize(target: ObjCObject?, selector: ObjCSelector?, object: ObjCObject?) -> Self? {
        guard let target, let selector else { return nil }
        let invocation = (target: ObjC.retain(target.id)!, selector: selector.pointer.assumingMemoryBound(to: CChar.self) as SEL,
                          argument: object.flatMap { ObjC.retain($0.id) })
        storage.monitor.locked { storage.invocation = invocation }
        return self
    }

    /// Sends the message, unless the operation was cancelled first.
    @ObjCMethod("main")
    func sendMessage() {
        guard let invocation = storage.monitor.locked({ storage.invocation }) else { return }
        // Only a method returning an object has a result.
        let method = ObjC.instanceMethod(ObjC.objectGetClass(invocation.target), invocation.selector)
        let returnsObject = ObjC.methodTypes(method).map { $0.pointee == UInt8(ascii: "@") } ?? false
        let returned = ObjC.send(invocation.target, invocation.selector, invocation.argument)
        let result = returnsObject ? returned.flatMap { ObjC.retain($0) } : nil
        let old = storage.monitor.locked { () -> id? in
            defer { storage.result = result }
            return storage.result
        }
        ObjC.release(old)
    }

    @ObjCMethod("result")
    func result() -> ObjCObject? {
        storage.monitor.locked { storage.result }.flatMap { ObjC.autorelease($0) }.map(ObjCObject.init)
    }
}

extension Operations {
    /// An operation's change notices say it has become finished or ready,
    /// which its queue acts on; -didChangeValueForKey: passes them here.
    static func didChangeValue(_ object: id, forKey key: String) {
        guard isOperation(object) else { return }
        switch key {
        case "isFinished", "finished":
            if Messages.bool(object, "isFinished") { didFinish(object) }
        case "isReady", "ready":
            storage(object).queue?.schedule()
        default:
            break
        }
    }
}

// MARK: - Queues

final class QueueStorage: @unchecked Sendable {
    let monitor = Monitor()
    /// The queue object, which lives as long as its storage.
    let objectPointer: id
    let isMain: Bool
    /// Queued operations, in the order added; each holds a reference.
    var operations: [id] = []
    var started: Set<id> = []
    var maxConcurrent = -1
    var suspended = false
    var name: id?
    var qualityOfService = -1
    /// The dispatch queue operations run on, if the app set one.
    var underlying: id?
    /// The last barrier added, which later operations wait for.
    var barrier: id?

    init(_ object: id, isMain: Bool = false) {
        objectPointer = object
        self.isMain = isMain
    }

    deinit {
        ObjC.release(name)
        ObjC.release(barrier)
        ObjC.release(underlying)
    }

    func add(_ operation: id) {
        let storage = Operations.storage(operation)
        if let barrier = monitor.locked({ barrier }), barrier != operation, !Operations.isFinished(barrier) {
            Operations.addDependency(operation, barrier)
        }
        storage.monitor.locked { storage.queue = self }
        monitor.locked { operations.append(ObjC.retain(operation)!) }
        schedule()
    }

    /// Starts ready operations, highest priority first, up to the limit.
    func schedule() {
        // Held while they are asked, outside the lock: another thread may
        // finish one meanwhile, and the queue then lets it go.
        let pending: [id] = monitor.locked {
            suspended ? [] : operations.filter { !started.contains($0) }.map { ObjC.retain($0)! }
        }
        defer { pending.forEach { ObjC.release($0) } }
        guard !pending.isEmpty else { return }
        // Asked outside the lock: subclasses' -isReady may do anything.
        let ready = pending.enumerated()
            .filter { Messages.bool($0.element, "isReady") }
            .sorted { a, b in
                let first = Operations.storage(a.element).queuePriority
                let second = Operations.storage(b.element).queuePriority
                return first != second ? first > second : a.offset < b.offset
            }
            .map(\.element)
        let toStart: [id] = monitor.locked {
            guard !suspended else { return [] }
            let limit = isMain ? 1 : (maxConcurrent < 0 ? 64 : maxConcurrent)
            var running = started.count
            var chosen: [id] = []
            for operation in ready where running < limit && operations.contains(operation)
                && !started.contains(operation) {
                started.insert(operation)
                chosen.append(operation)
                running += 1
            }
            return chosen
        }
        for operation in toStart { run(operation) }
    }

    private func run(_ operation: id) {
        let context = UnsafeMutablePointer<(QueueStorage, id)>.allocate(capacity: 1)
        context.initialize(to: (self, ObjC.retain(operation)!))
        let target = isMain ? Dispatch.mainQueue : underlying ?? Dispatch.globalQueue(dispatchQoS(qualityOfService), 0)
        Dispatch.async(target, UnsafeMutableRawPointer(context), QueueStorage.runOperation)
    }

    private static let runOperation: Dispatch.Function = { pointer in
        guard let context = pointer?.assumingMemoryBound(to: (QueueStorage, id).self) else { return }
        let (queue, operation) = context.move()
        context.deallocate()
        let previous = pthread_getspecific(OperationQueues.currentKey)
        pthread_setspecific(OperationQueues.currentKey, queue.objectPointer)
        ObjC.autoreleasepool { Messages.send(operation, "start") }
        pthread_setspecific(OperationQueues.currentKey, previous)
        // An operation that finished without a change notice.
        if Messages.bool(operation, "isFinished") { Operations.didFinish(operation) }
        ObjC.release(operation)
    }

    func operationDidFinish(_ operation: id) {
        let removed = monitor.locked { () -> Bool in
            started.remove(operation)
            guard let index = operations.firstIndex(of: operation) else { return false }
            operations.remove(at: index)
            if barrier == operation {
                barrier = nil
                ObjC.release(operation)
            }
            return true
        }
        monitor.broadcast()
        if removed { ObjC.release(operation) }
        schedule()
    }

    func waitUntilEmpty() {
        monitor.wait { operations.isEmpty }
    }
}

enum OperationQueues {
    nonisolated(unsafe) static var queueClass: Class!
    nonisolated(unsafe) static var main: id?

    /// The queue running the current thread's operation.
    static let currentKey: pthread_key_t = {
        var key = pthread_key_t()
        pthread_key_create(&key, nil)
        return key
    }()

    static func storage(_ object: id) -> QueueStorage {
        if let storage = Storage.get(object, as: QueueStorage.self) { return storage }
        let storage = QueueStorage(object)
        Storage.set(object, storage)
        return storage
    }

    static var mainQueue: id {
        if let main { return main }
        let object = Storage.allocate(UnsafeMutableRawPointer(queueClass))!
        let storage = QueueStorage(object, isMain: true)
        storage.name = Strings.make("NSOperationQueue Main Queue")
        storage.maxConcurrent = 1
        Storage.set(object, storage)
        main = object
        return object
    }
}

/// NSOperationQueue.
@ObjCClass("NSOperationQueue")
public final class NSOperationQueue: NSObject {
    override public class func didDefineObjCClass(_ cls: ObjCClass) {
        NSObject.registerObjCCategoryStorageAllocated(cls)
        OperationQueues.queueClass = cls.storage
    }

    var storage: QueueStorage { OperationQueues.storage(objcObject) }

    @ObjCMethod("init")
    func initialize() -> Self {
        _ = storage
        return self
    }

    @ObjCMethod("dealloc")
    func dealloc() {
        Storage.set(objcObject, nil)
        ObjC.superDealloc(objcObject, from: OperationQueues.queueClass)
    }

    @ObjCClassMethod("mainQueue")
    static func mainQueue() -> UnsafeMutableRawPointer { OperationQueues.mainQueue }

    /// The queue running the calling operation; on the main thread, the
    /// main queue.
    @ObjCClassMethod("currentQueue")
    static func currentQueue() -> UnsafeMutableRawPointer? {
        if let queue = pthread_getspecific(OperationQueues.currentKey) { return queue }
        return Threads.isMainThread ? OperationQueues.mainQueue : nil
    }

    @ObjCMethod("addOperation:")
    func addOperation(_ operation: ObjCObject) { storage.add(operation.id) }

    @ObjCMethod("addOperations:waitUntilFinished:")
    func addOperations(_ operations: ObjCObject, waitUntilFinished wait: Bool) {
        let list = Arrays.elements(operations.id)
        list.forEach(storage.add)
        if wait {
            for operation in list {
                let storage = Operations.storage(operation)
                storage.monitor.wait { storage.completed }
            }
        }
    }

    /// A nil block adds nothing.
    @ObjCMethod("addOperationWithBlock:")
    func addOperation(block: ObjCObject?) {
        guard let block, let copied = ObjC.retainBlock(block.id),
              let operation = Storage.allocate(UnsafeMutableRawPointer(Operations.blockOperationClass)) else { return }
        Operations.storage(operation).blocks.append(copied)
        storage.add(operation)
        ObjC.release(operation)
    }

    /// A block that runs once every operation added before it has finished,
    /// and before any added after it starts.
    @ObjCMethod("addBarrierBlock:")
    func addBarrierBlock(_ block: ObjCObject) {
        guard let barrier = Storage.allocate(UnsafeMutableRawPointer(Operations.blockOperationClass)) else { return }
        Operations.storage(barrier).blocks.append(ObjC.retainBlock(block.id)!)
        let queue = storage
        for operation in queue.monitor.locked({ queue.operations }) { Operations.addDependency(barrier, operation) }
        let old = queue.monitor.locked { () -> id? in
            defer { queue.barrier = ObjC.retain(barrier) }
            return queue.barrier
        }
        ObjC.release(old)
        queue.add(barrier)
        ObjC.release(barrier)
    }

    @ObjCMethod("operations")
    func operations() -> ObjCObject { ObjCObject(Arrays.autoreleased(storage.monitor.locked { storage.operations })) }

    @ObjCMethod("operationCount")
    func operationCount() -> Int { storage.monitor.locked { storage.operations.count } }

    @ObjCMethod("cancelAllOperations")
    func cancelAllOperations() {
        for operation in storage.monitor.locked({ storage.operations }) {
            Messages.send(operation, "cancel")
        }
    }

    @ObjCMethod("waitUntilAllOperationsAreFinished")
    func waitUntilAllOperationsAreFinished() { storage.waitUntilEmpty() }

    @ObjCMethod("maxConcurrentOperationCount")
    func maxConcurrentOperationCount() -> Int { storage.monitor.locked { storage.maxConcurrent } }

    @ObjCMethod("setMaxConcurrentOperationCount:")
    func setMaxConcurrentOperationCount(_ count: Int) {
        guard !storage.isMain else { return }
        storage.monitor.locked { storage.maxConcurrent = count }
        storage.schedule()
    }

    @ObjCMethod("isSuspended") func isSuspended() -> Bool { storage.monitor.locked { storage.suspended } }

    @ObjCMethod("setSuspended:")
    func setSuspended(_ suspended: Bool) {
        storage.monitor.locked { storage.suspended = suspended }
        if !suspended { storage.schedule() }
    }

    /// "NSOperationQueue 0x…" until named.
    @ObjCMethod("name")
    func name() -> ObjCObject {
        if let name = storage.monitor.locked({ storage.name }) { return ObjCObject(name) }
        return ObjCObject(Strings.autoreleased("NSOperationQueue \(objcObject)"))
    }

    @ObjCMethod("setName:")
    func setName(_ name: ObjCObject?) {
        let copy = name.flatMap { ObjC.send($0.id, Selectors.copyWithZone, nil) }
        let old = storage.monitor.locked { () -> id? in
            defer { storage.name = copy }
            return storage.name
        }
        ObjC.release(old)
    }

    @ObjCMethod("qualityOfService") func qualityOfService() -> Int { storage.monitor.locked { storage.qualityOfService } }
    @ObjCMethod("setQualityOfService:")
    func setQualityOfService(_ quality: Int) { storage.monitor.locked { storage.qualityOfService = quality } }

    /// The dispatch queue the operations run on; the main queue's is the
    /// main dispatch queue and can't be changed.
    @ObjCMethod("underlyingQueue")
    func underlyingQueue() -> UnsafeMutableRawPointer? {
        storage.isMain ? Dispatch.mainQueue : storage.monitor.locked { storage.underlying }
    }

    @ObjCMethod("setUnderlyingQueue:")
    func setUnderlyingQueue(_ queue: UnsafeMutableRawPointer?) {
        guard !storage.isMain else { return }
        let old = storage.monitor.locked { () -> id? in
            defer { storage.underlying = ObjC.retain(queue) }
            return storage.underlying
        }
        ObjC.release(old)
    }
}
