import CPerryDispatch
import Glibc
import PerryObjCInterop

// The main queue runs on the main thread, drained by whoever runs it: the
// main run loop, through the hooks CoreFoundation's run loop uses on Darwin
// (_dispatch_get_main_queue_port_4CF and _dispatch_main_queue_callback_4CF),
// or dispatch_main. On Linux the port is an eventfd that becomes readable
// when the main queue has work.

enum MainQueue {
    nonisolated(unsafe) static var handle: Int32 = -1

    static func start() {
        handle = linux_dispatch_get_main_queue_handle_4CF()
    }

    /// Runs what the main queue holds. On the main thread only.
    static func drain() {
        var value: UInt64 = 0
        _ = read(handle, &value, MemoryLayout<UInt64>.size)
        ObjCRuntime.autoreleasepool { linux_dispatch_main_queue_callback_4CF(nil) }
    }
}

/// The main queue's port, which a run loop waits on: an eventfd here.
@c(__dispatch_get_main_queue_port_4CF)
public func _dispatch_get_main_queue_port_4CF() -> Int32 {
    MainQueue.handle
}

/// Drains the main queue, when its port is readable.
@c(__dispatch_main_queue_callback_4CF)
public func _dispatch_main_queue_callback_4CF(_ message: UnsafeMutableRawPointer?) {
    MainQueue.drain()
}

/// Runs the main queue forever on the main thread. Unlike Linux's, which
/// ends the main thread and drains the queue on another, so that blocks on
/// the main queue run on the main thread as they do on Darwin.
@c(_dispatch_main)
public func dispatch_main() -> Never {
    var poller = pollfd(fd: MainQueue.handle, events: Int16(POLLIN), revents: 0)
    while true {
        if poll(&poller, 1, -1) > 0 { MainQueue.drain() }
    }
}
