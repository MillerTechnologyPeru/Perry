import os.lock

/// OSAllocatedUnfairLock: a lock and the state it guards in one
/// allocation. Its methods are compiled into callers; the type, its
/// ownership test's enumeration and the lock flags are here.
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

    /// What precondition(_:) asserts of the calling thread.
    @frozen public enum Ownership: Hashable, Sendable, BitwiseCopyable {
        case owner
        case notOwner
    }
}

/// Options for taking an OSAllocatedUnfairLock.
@available(macOS 14.0, iOS 17.0, tvOS 17.0, watchOS 10.0, *)
public struct OSAllocatedUnfairLockFlags: OptionSet, RawRepresentable {
    public let rawValue: UInt32

    public init(rawValue: UInt32) {
        self.rawValue = rawValue
    }

    /// Spin while the owner runs, rather than block at once.
    public static let adaptiveSpin = OSAllocatedUnfairLockFlags(rawValue: 1 << 0)

    /// The os_unfair_lock flags these options make:
    /// OS_UNFAIR_LOCK_ADAPTIVE_SPIN is 0x40000.
    @usableFromInline
    internal var _translatedValue: __os_unfair_lock_flags_t {
        __os_unfair_lock_flags_t(rawValue: contains(.adaptiveSpin) ? 0x0004_0000 : 0)
    }
}
