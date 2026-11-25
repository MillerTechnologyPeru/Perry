import GraphiteBase
import GraphiteTasks
import PerryObjCInterop
import Synchronization

// Multiprocessing Services' tasks, queues and events over Graphite's. An ID
// a program holds is the Graphite object's address, kept here while the
// object is valid, so an ID that was deleted or never made is
// kMPInvalidIDErr rather than a crash. Critical regions and semaphores are
// CoreServices'.

/// Live objects by their IDs.
private final class Registry<Object: AnyObject & Sendable>: Sendable {

    private let objects = Mutex<[UInt: Object]>([:])

    func add(_ object: Object) -> UnsafeMutableRawPointer {
        let id = Unmanaged.passUnretained(object).toOpaque()
        objects.withLock { $0[UInt(bitPattern: id)] = object }
        return id
    }

    func object(_ id: UnsafeMutableRawPointer?) -> Object? {
        guard let id else { return nil }
        return objects.withLock { $0[UInt(bitPattern: id)] }
    }

    func remove(_ id: UnsafeMutableRawPointer?) -> Object? {
        guard let id else { return nil }
        return objects.withLock { $0.removeValue(forKey: UInt(bitPattern: id)) }
    }
}

private let queues = Registry<MPQueue>()
private let events = Registry<MPEvent>()
private let tasks = Registry<MPTask>()

private func word(_ pointer: UnsafeMutableRawPointer?) -> UInt {
    UInt(bitPattern: pointer)
}

private func pointer(_ word: UInt) -> UnsafeMutableRawPointer? {
    UnsafeMutableRawPointer(bitPattern: word)
}

// MARK: - Queues

/// OSStatus MPCreateQueue(MPQueueID *).
@c(_MPCreateQueue)
public func MPCreateQueue(_ out: UnsafeMutablePointer<UnsafeMutableRawPointer?>?) -> Int32 {
    guard let out else { return MacError.parameter.status }
    out.pointee = queues.add(MPQueue())
    return 0
}

/// OSStatus MPDeleteQueue(MPQueueID): its waiters are told kMPDeletedErr.
@c(_MPDeleteQueue)
public func MPDeleteQueue(_ id: UnsafeMutableRawPointer?) -> Int32 {
    guard let queue = queues.remove(id) else { return MacError.mpInvalidID.status }
    return status { () throws(MacError) in try queue.delete() }
}

/// OSStatus MPSetQueueReserve(MPQueueID, ItemCount).
@c(_MPSetQueueReserve)
public func MPSetQueueReserve(_ id: UnsafeMutableRawPointer?, _ count: UInt) -> Int32 {
    guard let queue = queues.object(id) else { return MacError.mpInvalidID.status }
    return status { () throws(MacError) in try queue.setReserve(Int(count)) }
}

/// OSStatus MPNotifyQueue(MPQueueID, void *, void *, void *).
@c(_MPNotifyQueue)
public func MPNotifyQueue(_ id: UnsafeMutableRawPointer?, _ first: UnsafeMutableRawPointer?,
                          _ second: UnsafeMutableRawPointer?, _ third: UnsafeMutableRawPointer?) -> Int32 {
    guard let queue = queues.object(id) else { return MacError.mpInvalidID.status }
    return status { () throws(MacError) in try queue.notify(word(first), word(second), word(third)) }
}

/// OSStatus MPWaitOnQueue(MPQueueID, void **, void **, void **, Duration).
@c(_MPWaitOnQueue)
public func MPWaitOnQueue(_ id: UnsafeMutableRawPointer?, _ first: UnsafeMutablePointer<UnsafeMutableRawPointer?>?,
                          _ second: UnsafeMutablePointer<UnsafeMutableRawPointer?>?,
                          _ third: UnsafeMutablePointer<UnsafeMutableRawPointer?>?, _ timeout: Int32) -> Int32 {
    guard let queue = queues.object(id) else { return MacError.mpInvalidID.status }
    do throws(MacError) {
        let message = try queue.wait(timeout: MacDuration(rawValue: timeout))
        first?.pointee = pointer(message.first)
        second?.pointee = pointer(message.second)
        third?.pointee = pointer(message.third)
        return 0
    } catch {
        return error.status
    }
}

// MARK: - Events

/// OSStatus MPCreateEvent(MPEventID *).
@c(_MPCreateEvent)
public func MPCreateEvent(_ out: UnsafeMutablePointer<UnsafeMutableRawPointer?>?) -> Int32 {
    guard let out else { return MacError.parameter.status }
    out.pointee = events.add(MPEvent())
    return 0
}

/// OSStatus MPDeleteEvent(MPEventID).
@c(_MPDeleteEvent)
public func MPDeleteEvent(_ id: UnsafeMutableRawPointer?) -> Int32 {
    guard let event = events.remove(id) else { return MacError.mpInvalidID.status }
    return status { () throws(MacError) in try event.delete() }
}

/// OSStatus MPSetEvent(MPEventID, MPEventFlags).
@c(_MPSetEvent)
public func MPSetEvent(_ id: UnsafeMutableRawPointer?, _ flags: UInt32) -> Int32 {
    guard let event = events.object(id) else { return MacError.mpInvalidID.status }
    return status { () throws(MacError) in try event.set(flags) }
}

/// OSStatus MPWaitForEvent(MPEventID, MPEventFlags *, Duration): every flag
/// set, taken; none when the wait fails.
@c(_MPWaitForEvent)
public func MPWaitForEvent(_ id: UnsafeMutableRawPointer?, _ flags: UnsafeMutablePointer<UInt32>?, _ timeout: Int32) -> Int32 {
    guard let event = events.object(id) else { return MacError.mpInvalidID.status }
    do throws(MacError) {
        flags?.pointee = try event.wait(timeout: MacDuration(rawValue: timeout))
        return 0
    } catch {
        flags?.pointee = 0
        return error.status
    }
}

// MARK: - Tasks

/// A task's entry, OSStatus (*)(void *), as Darwin's code is called.
private typealias TaskEntry = @convention(c) (UnsafeMutableRawPointer?) -> Int32

/// libSystem's pthread_create, which readies a thread for the program's
/// code, as its own threads are.
private typealias ThreadCreate = @convention(c) (UnsafeMutablePointer<UnsafeMutableRawPointer?>?, UnsafeRawPointer?,
                                                 @convention(c) (UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer?,
                                                 UnsafeMutableRawPointer?) -> Int32

private final class ThreadBody {
    let body: @Sendable () -> Void
    init(_ body: @escaping @Sendable () -> Void) { self.body = body }
}

/// Task threads, started through the program's libSystem; through the C
/// library's when there is none.
private let programThreads = ThreadStarter { body in
    guard let symbol = carbon_function("/usr/lib/libSystem.B.dylib", "_pthread_create") else {
        return ThreadStarter.posix.start(body)
    }
    let create = unsafeBitCast(symbol, to: ThreadCreate.self)
    let context = Unmanaged.passRetained(ThreadBody(body)).toOpaque()
    var thread: UnsafeMutableRawPointer?
    let error = create(&thread, nil, { context in
        Unmanaged<ThreadBody>.fromOpaque(context!).takeRetainedValue().body()
        return nil
    }, context)
    if error != 0 { Unmanaged<ThreadBody>.fromOpaque(context).release() }
    return error == 0
}

/// OSStatus MPCreateTask(TaskProc, void *parameter, ByteCount stackSize,
/// MPQueueID notifyQueue, void *terminationParameter1, void
/// *terminationParameter2, MPTaskOptions, MPTaskID *): the task's ID is
/// written before it runs, as a task may look for itself where the
/// program keeps it.
@c(_MPCreateTask)
public func MPCreateTask(_ entry: UnsafeMutableRawPointer?, _ parameter: UnsafeMutableRawPointer?, _ stackSize: UInt,
                         _ queue: UnsafeMutableRawPointer?, _ first: UnsafeMutableRawPointer?,
                         _ second: UnsafeMutableRawPointer?, _ options: UInt32,
                         _ out: UnsafeMutablePointer<UnsafeMutableRawPointer?>?) -> Int32 {
    guard let entry else { return MacError.parameter.status }
    let function = darwinCallable(unsafeBitCast(entry, to: TaskEntry.self))
    let argument = word(parameter)
    // The thread waits for the ID to be written and kept.
    let gate = try? MPSemaphore(maximum: 1, initial: 0)
    let starter = ThreadStarter { body in
        programThreads.start {
            if let gate { try? gate.wait() }
            body()
        }
    }
    do throws(MacError) {
        let task = try MPTask.create(queue: queues.object(queue), terminationWords: (word(first), word(second)),
                                     starter: starter) { function(pointer(argument)) }
        out?.pointee = tasks.add(task)
        try? gate?.signal()
        return 0
    } catch {
        out?.pointee = nil
        return error.status
    }
}

/// OSStatus MPTerminateTask(MPTaskID, OSStatus): its queue is told now,
/// with the status; the task ends at its next wait.
@c(_MPTerminateTask)
public func MPTerminateTask(_ id: UnsafeMutableRawPointer?, _ terminationStatus: Int32) -> Int32 {
    guard let task = tasks.object(id) else { return MacError.mpInvalidID.status }
    return status { () throws(MacError) in try task.terminate(status: terminationStatus) }
}

/// OSStatus MPSetTaskWeight(MPTaskID, MPTaskWeight).
@c(_MPSetTaskWeight)
public func MPSetTaskWeight(_ id: UnsafeMutableRawPointer?, _ weight: UInt32) -> Int32 {
    tasks.object(id)?.weight = weight
    return 0
}

/// void MPExit(OSStatus): ends the calling task with its result.
@c(_MPExit)
public func MPExit(_ terminationStatus: Int32) {
    MPTask.exit(status: terminationStatus)
}

/// void MPYield(void).
@c(_MPYield)
public func MPYield() {
    MPTask.yield()
}

/// MPTaskID MPCurrentTaskID(void): the running task's ID; a thread that is
/// no task has one of its own all the same.
@c(_MPCurrentTaskID)
public func MPCurrentTaskID() -> UnsafeMutableRawPointer? {
    if let task = MPTask.current { return Unmanaged.passUnretained(task).toOpaque() }
    return pointer(MPTask.currentID.rawValue)
}
