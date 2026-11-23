import CPerryDispatch
import Glibc
import PerryObjCInterop

// Workgroups (os/workgroup.h): threads that work toward one deadline join a
// workgroup so the scheduler can see them together. Linux has no such
// scheduler, so a workgroup here keeps what programs ask of it (its name,
// whether it was cancelled, the working arena and which thread has which
// index in it, an interval's start and deadline) and answers from that.
// Errors are Darwin's errno values, which programs compare with.

private let EINVAL_DARWIN: Int32 = 22
private let EBUSY_DARWIN: Int32 = 16
private let ENOTSUP_DARWIN: Int32 = 45

/// A workgroup's state.
final class WorkgroupState {
    let name: String
    let isInterval: Bool
    let lock = Lock()
    var cancelled = false
    /// How many threads have joined and not left.
    var joined = 0
    /// The working arena, its destructor and how many workers it has slots
    /// for; the index each joined thread was given in it.
    var arena: UnsafeMutableRawPointer?
    var arenaDestructor: (@convention(c) (UnsafeMutableRawPointer?) -> Void)?
    var arenaWorkers: UInt32 = 0
    var workerIndices: [pthread_t: UInt32] = [:]
    /// An interval workgroup's current interval: started, and its deadline.
    var intervalStarted = false
    var intervalDeadline: UInt64 = 0

    init(name: String, isInterval: Bool) {
        self.name = name
        self.isInterval = isInterval
    }
}

@ObjCClass("OS_os_workgroup")
open class OSWorkgroup: OSObject {
    @ObjCMethod("dealloc")
    func dealloc() {
        if let state = Objects.state(objcObject, as: WorkgroupState.self), let arena = state.arena {
            state.arenaDestructor?(arena)
        }
        Objects.destroy(objcObject, keepsState: true)
        ObjCRuntime.superDealloc(objcObject, definedOn: OSWorkgroup.objCClass.pointer)
    }
}

@ObjCClass("OS_os_workgroup_interval")
open class OSWorkgroupInterval: OSWorkgroup {}

@ObjCClass("OS_os_workgroup_parallel")
open class OSWorkgroupParallel: OSWorkgroup {}

enum Workgroups {
    static func state(_ workgroup: Object?) -> WorkgroupState? { Objects.state(workgroup, as: WorkgroupState.self) }

    static func make(_ cls: Object, name: UnsafePointer<CChar>?, isInterval: Bool = false) -> Object {
        Objects.make(cls, linux: nil, state: WorkgroupState(name: name.map { String(cString: $0) } ?? "", isInterval: isInterval))
    }
}

// MARK: - Making workgroups

/// A workgroup for a Mach port another process sent: there are no such
/// ports here, so it is a workgroup of its own.
@c(_os_workgroup_create_with_port)
public func os_workgroup_create_with_port(_ name: UnsafePointer<CChar>?, _ port: UInt32) -> Object? {
    Workgroups.make(OSWorkgroup.objCClass.pointer, name: name)
}

/// A workgroup joined with the same threads as another: a copy of it here.
@c(_os_workgroup_create_with_workgroup)
public func os_workgroup_create_with_workgroup(_ name: UnsafePointer<CChar>?, _ workgroup: Object?) -> Object? {
    let isInterval = Workgroups.state(workgroup)?.isInterval ?? false
    let cls = isInterval ? OSWorkgroupInterval.objCClass.pointer : OSWorkgroup.objCClass.pointer
    return Workgroups.make(cls, name: name, isInterval: isInterval)
}

@c(_os_workgroup_parallel_create)
public func os_workgroup_parallel_create(_ name: UnsafePointer<CChar>?, _ attributes: UnsafeRawPointer?) -> Object? {
    Workgroups.make(OSWorkgroupParallel.objCClass.pointer, name: name)
}

@c(_os_workgroup_interval_create)
public func os_workgroup_interval_create(_ name: UnsafePointer<CChar>?, _ clock: UInt32, _ attributes: UnsafeRawPointer?) -> Object? {
    Workgroups.make(OSWorkgroupInterval.objCClass.pointer, name: name, isInterval: true)
}

/// There are no Mach ports to give another process.
@c(_os_workgroup_copy_port)
public func os_workgroup_copy_port(_ workgroup: Object?, _ port: UnsafeMutablePointer<UInt32>?) -> Int32 {
    port?.pointee = 0
    return ENOTSUP_DARWIN
}

// MARK: - Joining

/// A thread joins; a cancelled workgroup can't be joined. The token is the
/// caller's; nothing needs keeping in it.
@c(_os_workgroup_join)
public func os_workgroup_join(_ workgroup: Object?, _ token: UnsafeMutableRawPointer?) -> Int32 {
    guard let state = Workgroups.state(workgroup) else { return EINVAL_DARWIN }
    return state.lock.withLock {
        if state.cancelled { return EINVAL_DARWIN }
        state.joined += 1
        return 0
    }
}

/// A thread leaves, and gives up its index in the working arena.
@c(_os_workgroup_leave)
public func os_workgroup_leave(_ workgroup: Object?, _ token: UnsafeMutableRawPointer?) {
    guard let state = Workgroups.state(workgroup) else { return }
    state.lock.withLock {
        state.joined = max(0, state.joined - 1)
        _ = state.workerIndices.removeValue(forKey: pthread_self())
    }
}

@c(_os_workgroup_cancel)
public func os_workgroup_cancel(_ workgroup: Object?) {
    guard let state = Workgroups.state(workgroup) else { return }
    state.lock.withLock { state.cancelled = true }
}

@c(_os_workgroup_testcancel)
public func os_workgroup_testcancel(_ workgroup: Object?) -> Bool {
    guard let state = Workgroups.state(workgroup) else { return false }
    return state.lock.withLock { state.cancelled }
}

/// As many threads as the machine has processors online.
@c(_os_workgroup_max_parallel_threads)
public func os_workgroup_max_parallel_threads(_ workgroup: Object?, _ attributes: UnsafeRawPointer?) -> Int32 {
    Int32(max(1, sysconf(Int32(_SC_NPROCESSORS_ONLN))))
}

// MARK: - The working arena

/// Sets the arena once, before any thread joins; another can't replace it.
@c(_os_workgroup_set_working_arena)
public func os_workgroup_set_working_arena(_ workgroup: Object?, _ arena: UnsafeMutableRawPointer?, _ maxWorkers: UInt32,
                                           _ destructor: (@convention(c) (UnsafeMutableRawPointer?) -> Void)?) -> Int32 {
    guard let state = Workgroups.state(workgroup) else { return EINVAL_DARWIN }
    return state.lock.withLock {
        if state.arena != nil || state.joined > 0 { return EBUSY_DARWIN }
        state.arena = arena
        state.arenaDestructor = destructor
        state.arenaWorkers = maxWorkers
        return 0
    }
}

/// The arena, and this thread's index in it: the first index no other
/// joined thread has, given on the thread's first request.
@c(_os_workgroup_get_working_arena)
public func os_workgroup_get_working_arena(_ workgroup: Object?, _ index: UnsafeMutablePointer<UInt32>?) -> UnsafeMutableRawPointer? {
    guard let state = Workgroups.state(workgroup) else { return nil }
    return state.lock.withLock {
        let thread = pthread_self()
        let assigned: UInt32
        if let known = state.workerIndices[thread] {
            assigned = known
        } else {
            let taken = Set(state.workerIndices.values)
            var free: UInt32 = 0
            while taken.contains(free) { free += 1 }
            assigned = state.arenaWorkers > 0 ? min(free, state.arenaWorkers - 1) : free
            state.workerIndices[thread] = assigned
        }
        index?.pointee = assigned
        return state.arena
    }
}

// MARK: - Intervals

@c(_os_workgroup_interval_start)
public func os_workgroup_interval_start(_ workgroup: Object?, _ start: UInt64, _ deadline: UInt64, _ data: UnsafeMutableRawPointer?) -> Int32 {
    guard let state = Workgroups.state(workgroup), state.isInterval else { return EINVAL_DARWIN }
    return state.lock.withLock {
        if state.cancelled || state.intervalStarted { return EINVAL_DARWIN }
        state.intervalStarted = true
        state.intervalDeadline = deadline
        return 0
    }
}

@c(_os_workgroup_interval_update)
public func os_workgroup_interval_update(_ workgroup: Object?, _ deadline: UInt64, _ data: UnsafeMutableRawPointer?) -> Int32 {
    guard let state = Workgroups.state(workgroup), state.isInterval else { return EINVAL_DARWIN }
    return state.lock.withLock {
        guard state.intervalStarted else { return EINVAL_DARWIN }
        state.intervalDeadline = deadline
        return 0
    }
}

@c(_os_workgroup_interval_finish)
public func os_workgroup_interval_finish(_ workgroup: Object?, _ data: UnsafeMutableRawPointer?) -> Int32 {
    guard let state = Workgroups.state(workgroup), state.isInterval else { return EINVAL_DARWIN }
    return state.lock.withLock {
        guard state.intervalStarted else { return EINVAL_DARWIN }
        state.intervalStarted = false
        return 0
    }
}
