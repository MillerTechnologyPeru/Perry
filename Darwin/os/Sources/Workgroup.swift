import os.workgroup
import Darwin

// Workgroups in Swift: the C functions the headers refine for Swift, as
// methods of WorkGroup and initializers of it and WorkGroupParallel.

@_silgen_name("os_workgroup_copy_port")
private func copyPort(_ workgroup: UnsafeMutableRawPointer, _ port: UnsafeMutablePointer<mach_port_t>) -> Int32

@_silgen_name("os_workgroup_create_with_workgroup")
private func createWithWorkgroup(_ name: UnsafePointer<CChar>?, _ workgroup: UnsafeMutableRawPointer) -> UnsafeMutableRawPointer?

@_silgen_name("os_workgroup_join")
private func joinWorkgroup(_ workgroup: UnsafeMutableRawPointer, _ token: UnsafeMutableRawPointer) -> Int32

@_silgen_name("os_workgroup_leave")
private func leaveWorkgroup(_ workgroup: UnsafeMutableRawPointer, _ token: UnsafeMutableRawPointer)

@_silgen_name("os_workgroup_cancel")
private func cancelWorkgroup(_ workgroup: UnsafeMutableRawPointer)

@_silgen_name("os_workgroup_testcancel")
private func testCancelWorkgroup(_ workgroup: UnsafeMutableRawPointer) -> Bool

@_silgen_name("os_workgroup_max_parallel_threads")
private func maxThreads(_ workgroup: UnsafeMutableRawPointer, _ attributes: UnsafeMutableRawPointer?) -> Int32

@_silgen_name("os_workgroup_set_working_arena")
private func setArena(_ workgroup: UnsafeMutableRawPointer, _ arena: UnsafeMutableRawPointer?, _ maxWorkers: UInt32,
                      _ destructor: @convention(c) (UnsafeMutableRawPointer?) -> Void) -> Int32

@_silgen_name("os_workgroup_get_working_arena")
private func getArena(_ workgroup: UnsafeMutableRawPointer, _ index: UnsafeMutablePointer<UInt32>?) -> UnsafeMutableRawPointer?

@_silgen_name("os_workgroup_interval_start")
private func intervalStart(_ workgroup: UnsafeMutableRawPointer, _ start: UInt64, _ deadline: UInt64, _ data: UnsafeMutableRawPointer?) -> Int32

@_silgen_name("os_workgroup_interval_update")
private func intervalUpdate(_ workgroup: UnsafeMutableRawPointer, _ deadline: UInt64, _ data: UnsafeMutableRawPointer?) -> Int32

@_silgen_name("os_workgroup_interval_finish")
private func intervalFinish(_ workgroup: UnsafeMutableRawPointer, _ data: UnsafeMutableRawPointer?) -> Int32

/// The size of os_workgroup_join_token_s, a signature and 36 bytes, with
/// room to spare.
private let joinTokenSize = 64

extension WorkGroup {
    /// The object, as the C functions take it.
    private var handle: UnsafeMutableRawPointer {
        Unmanaged.passUnretained(self).toOpaque()
    }

    public func copyPort() -> mach_port_t {
        var port: mach_port_t = 0
        _ = os.copyPort(handle, &port)
        return port
    }

    public convenience init?(port: mach_port_t, name: String? = nil) {
        let cName = name.map { strdup($0)! }
        defer { free(cName) }
        self.init(__name: cName, port: port)
    }

    public func copy(name: String? = nil) -> WorkGroup? {
        let copied = name.withOptionalCString { createWithWorkgroup($0, handle) }
        return copied.map { Unmanaged<WorkGroup>.fromOpaque($0).takeRetainedValue() }
    }

    /// What join() hands to leave(token:): the C library's join token.
    public struct JoinToken {
        fileprivate let storage: TokenStorage
    }

    public func join() -> JoinToken {
        let token = JoinToken(storage: TokenStorage())
        _ = joinWorkgroup(handle, token.storage.bytes)
        return token
    }

    public func leave(token: JoinToken) {
        leaveWorkgroup(handle, token.storage.bytes)
    }

    public func cancel() {
        cancelWorkgroup(handle)
    }

    public var isCancelled: Bool {
        testCancelWorkgroup(handle)
    }

    public var maxParallelThreads: Int {
        Int(maxThreads(handle, nil))
    }

    public func setWorkingArena(arena: UnsafeMutableRawPointer?, max_workers: UInt32,
                                destruct: @convention(c) (UnsafeMutableRawPointer?) -> Void) {
        _ = setArena(handle, arena, max_workers, destruct)
    }

    public typealias Index = UInt32

    public var workingArena: (UnsafeMutableRawPointer?, Index) {
        var index: UInt32 = 0
        let arena = getArena(handle, &index)
        return (arena, index)
    }
}

/// A join token's bytes, freed with it.
private final class TokenStorage {
    let bytes = UnsafeMutableRawPointer.allocate(byteCount: joinTokenSize, alignment: 8)

    init() {
        bytes.initializeMemory(as: UInt8.self, repeating: 0, count: joinTokenSize)
    }

    deinit {
        bytes.deallocate()
    }
}

extension WorkGroup: Repeatable {
    public func start(at timestamp: UInt64, deadline: UInt64) {
        _ = intervalStart(handle, timestamp, deadline, nil)
    }

    public func updateDeadline(deadline: UInt64) {
        _ = intervalUpdate(handle, deadline, nil)
    }

    public func finish() {
        _ = intervalFinish(handle, nil)
    }
}

extension WorkGroupParallel {
    public convenience init?(name: String? = nil) {
        let cName = name.map { strdup($0)! }
        defer { free(cName) }
        self.init(__name: cName, attr: nil)
    }
}

extension Optional where Wrapped == String {
    /// Calls `body` with the string's C string, or nil.
    fileprivate func withOptionalCString<R>(_ body: (UnsafePointer<CChar>?) throws -> R) rethrows -> R {
        switch self {
        case .some(let string): return try string.withCString(body)
        case .none: return try body(nil)
        }
    }
}
