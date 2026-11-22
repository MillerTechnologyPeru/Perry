import os.log
import os.signpost
import os.lock

/// OSAllocatedUnfairLock: a lock and the state it guards in one
/// allocation. Its methods are compiled into callers; the type is here.
@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
@frozen public struct OSAllocatedUnfairLock<State>: @unchecked Sendable {
    @usableFromInline
    internal let __lock: ManagedBuffer<State, os_unfair_lock>

    public init(uncheckedState initialState: State) {
        __lock = .create(minimumCapacity: 1) { buffer in
            buffer.withUnsafeMutablePointerToElements { $0.initialize(to: .init()) }
            return initialState
        }
    }
}
