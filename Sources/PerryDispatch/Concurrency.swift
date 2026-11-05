import CPerryDispatch
import Glibc
import PerryObjCInterop

// Workloops, and what Swift's concurrency runtime asks of libdispatch:
// enqueueing its jobs, and priority overrides, which Linux's scheduler has
// no use for and which therefore do nothing. Vouchers carry no state here.

// MARK: - Workloops

@c(_dispatch_workloop_create)
public func dispatch_workloop_create(_ label: UnsafePointer<CChar>?) -> Object? {
    linux_dispatch_workloop_create(label).map(Workloops.wrap)
}

@c(_dispatch_workloop_create_inactive)
public func dispatch_workloop_create_inactive(_ label: UnsafePointer<CChar>?) -> Object? {
    linux_dispatch_workloop_create_inactive(label).map(Workloops.wrap)
}

@c(_dispatch_workloop_set_autorelease_frequency)
public func dispatch_workloop_set_autorelease_frequency(_ workloop: Object?, _ frequency: UInt) {
    linux_dispatch_workloop_set_autorelease_frequency(Objects.linux(workloop), frequency)
}

/// Workgroups schedule threads together on Darwin; there are none here.
@c(_dispatch_workloop_set_os_workgroup)
public func dispatch_workloop_set_os_workgroup(_ workloop: Object?, _ workgroup: Object?) {}

enum Workloops {
    /// A Darwin workloop (+1) for a Linux one, found again as a queue.
    static func wrap(_ linux: Object) -> Object {
        let workloop = Objects.make(Classes.workloop, linux: linux)
        linux_dispatch_queue_set_specific(linux, Queues.wrapperKey, workloop, nil)
        return workloop
    }
}

// MARK: - Swift's jobs

/// Runs a Swift job as its metadata's dispatch invoke function does:
/// DispatchClassMetadata keeps it 48 bytes into the metadata.
private let runSwiftJob: Function = { job in
    guard let job, let metadata = job.load(as: UnsafeRawPointer?.self) else { return }
    typealias Invoke = @convention(c) (UnsafeMutableRawPointer, UnsafeMutableRawPointer?, UInt32) -> Void
    unsafeBitCast(metadata.load(fromByteOffset: 48, as: UnsafeRawPointer.self), to: Invoke.self)(job, nil, 0)
}

/// Enqueues a Swift job, whatever its priority.
@c(_dispatch_async_swift_job)
public func dispatch_async_swift_job(_ queue: Object?, _ job: UnsafeMutableRawPointer?, _ qos: UInt32) {
    linux_dispatch_async_f(Objects.linux(queue), job, runSwiftJob)
}

// MARK: - Priorities

/// QOS_CLASS_USER_INTERACTIVE on the main thread, QOS_CLASS_DEFAULT on others.
@c(_qos_class_self)
public func qos_class_self() -> UInt32 { perry_dispatch_is_main_thread() ? 0x21 : 0x15 }

@c(_qos_class_main)
public func qos_class_main() -> UInt32 { 0x21 }

/// dispatch_thread_override_info_s: nothing can be overridden.
@c(_dispatch_thread_get_current_override_qos_floor)
public func dispatch_thread_get_current_override_qos_floor() -> UInt64 { 0 }

@c(_dispatch_thread_override_self)
public func dispatch_thread_override_self(_ qos: UInt32) -> Int32 { 0 }

@c(_dispatch_thread_override_self_with_base)
public func dispatch_thread_override_self_with_base(_ qos: UInt32, _ base: UInt32) -> UInt32 { 0 }

@c(_dispatch_thread_reset_override_self)
public func dispatch_thread_reset_override_self(_ opaque: UInt32) {}

@c(_dispatch_lock_override_start_with_debounce)
public func dispatch_lock_override_start_with_debounce(_ lock: UnsafeMutableRawPointer?, _ thread: UInt32,
                                                       _ qos: UInt32) -> Int32 { 0 }

@c(_dispatch_lock_override_end)
public func dispatch_lock_override_end(_ qos: UInt32) -> Int32 { 0 }

// MARK: - Vouchers

/// There is never a voucher to adopt or copy. Adopting takes ownership of
/// an object; Swift's concurrency also adopts sentinels that aren't objects
/// (VOUCHER_INVALID, all ones), which are left alone.
@c(_voucher_copy)
public func voucher_copy() -> Object? { nil }

@c(_voucher_adopt)
public func voucher_adopt(_ voucher: Object?) -> Object? {
    if let voucher, Int(bitPattern: voucher) & 7 == 0 { ObjCRuntime.release(voucher) }
    return nil
}

// MARK: - OS objects

/// os_retain and os_release: OS objects are Objective-C objects.
@c(_os_retain)
public func os_retain(_ object: Object?) -> Object? { object.flatMap(ObjCRuntime.retain) }

@c(_os_release)
public func os_release(_ object: Object?) {
    if let object { ObjCRuntime.release(object) }
}
