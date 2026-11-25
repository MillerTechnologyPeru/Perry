import GraphiteBase
import GraphiteTasks
import PerryObjCInterop
import Synchronization

// The Time Manager over Graphite's TimeManagerTask. A program's TMTask
// record (qLink, qType, then tmAddr, tmCount and, for an extended task,
// tmWakeUp and tmReserved, packed to two bytes) stays the program's: each
// installed record has a Graphite task, which runs the record's tmAddr with
// the record on the Time Manager's thread.

private enum TMTaskRecord {
    static let pointer = MemoryLayout<UnsafeRawPointer>.size
    static let address = pointer + 2
    static let count = 2 * pointer + 2
}

/// A procedure that takes a TMTaskPtr, as Darwin's code is called.
private typealias TimerProcedure = @convention(c) (UnsafeMutableRawPointer?) -> Void

/// Each installed record's task, by the record's address.
private let timeTasks = Mutex<[UInt: TimeManagerTask]>([:])

private func install(_ record: UnsafeMutableRawPointer?, extended: Bool) -> Int16 {
    guard let record else { return MacError.parameter.osErr }
    let address = UInt(bitPattern: record)
    let task = TimeManagerTask(extended: extended) { _ in
        guard let record = UnsafeMutableRawPointer(bitPattern: address),
              let procedure = record.loadUnaligned(fromByteOffset: TMTaskRecord.address, as: UnsafeMutableRawPointer?.self)
        else { return }
        darwinCallable(unsafeBitCast(procedure, to: TimerProcedure.self))(record)
    }
    task.install()
    let previous = timeTasks.withLock { tasks in
        defer { tasks[address] = task }
        return tasks[address]
    }
    previous?.remove()
    record.storeBytes(of: Int32(0), toByteOffset: TMTaskRecord.count, as: Int32.self)
    return 0
}

/// OSErr InstallTimeTask(QElemPtr): readies the task, which runs once
/// primed.
@c(_InstallTimeTask)
public func InstallTimeTask(_ record: UnsafeMutableRawPointer?) -> Int16 {
    install(record, extended: false)
}

/// OSErr InstallXTimeTask(QElemPtr): an extended task, which, primed again,
/// counts from when it was last due.
@c(_InstallXTimeTask)
public func InstallXTimeTask(_ record: UnsafeMutableRawPointer?) -> Int16 {
    install(record, extended: true)
}

@c(_InsTime)
public func InsTime(_ record: UnsafeMutableRawPointer?) -> Int16 {
    install(record, extended: false)
}

@c(_InsXTime)
public func InsXTime(_ record: UnsafeMutableRawPointer?) -> Int16 {
    install(record, extended: true)
}

/// OSErr PrimeTime(QElemPtr, long count): runs the task after `count`
/// milliseconds, or -`count` microseconds. A record that wasn't installed
/// is installed as a plain task.
@c(_PrimeTime)
public func PrimeTime(_ record: UnsafeMutableRawPointer?, _ count: Int32) -> Int16 {
    guard let record else { return MacError.parameter.osErr }
    var task = timeTasks.withLock { $0[UInt(bitPattern: record)] }
    if task == nil {
        _ = install(record, extended: false)
        task = timeTasks.withLock { $0[UInt(bitPattern: record)] }
    }
    task?.prime(count)
    return 0
}

/// OSErr RemoveTimeTask(QElemPtr): takes the task out, with what was left
/// of its time in tmCount: milliseconds, or negative microseconds.
@c(_RemoveTimeTask)
public func RemoveTimeTask(_ record: UnsafeMutableRawPointer?) -> Int16 {
    guard let record else { return MacError.parameter.osErr }
    let task = timeTasks.withLock { $0.removeValue(forKey: UInt(bitPattern: record)) }
    let left = task?.remove() ?? 0
    record.storeBytes(of: left, toByteOffset: TMTaskRecord.count, as: Int32.self)
    return 0
}

@c(_RmvTime)
public func RmvTime(_ record: UnsafeMutableRawPointer?) -> Int16 {
    RemoveTimeTask(record)
}

/// TimerUPP NewTimerUPP(TimerProcPtr): the procedure itself.
@c(_NewTimerUPP)
public func NewTimerUPP(_ procedure: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer? {
    procedure
}

@c(_DisposeTimerUPP)
public func DisposeTimerUPP(_ procedure: UnsafeMutableRawPointer?) {}

/// void InvokeTimerUPP(TMTaskPtr, TimerUPP).
@c(_InvokeTimerUPP)
public func InvokeTimerUPP(_ record: UnsafeMutableRawPointer?, _ procedure: UnsafeMutableRawPointer?) {
    guard let procedure else { return }
    darwinCallable(unsafeBitCast(procedure, to: TimerProcedure.self))(record)
}
