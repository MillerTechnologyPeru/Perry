//
//  ObservationThreadLocal.swift
//  OpenSwiftUICore

#if canImport(Darwin)
import Darwin

/// The current thread's observation access list, which Swift's Observation
/// records `ObservationRegistrar.access` calls into while it is set.
///
/// Observation keeps it in Darwin's reserved thread-specific key
/// `__PTK_FRAMEWORK_SWIFT_KEY6` and does not export its accessors, so it is
/// read and written through that key here.
package enum _ThreadLocal {
    private static let key = pthread_key_t(106)

    package static var value: UnsafeMutableRawPointer? {
        get { pthread_getspecific(key) }
        set { pthread_setspecific(key, newValue) }
    }
}
#endif
