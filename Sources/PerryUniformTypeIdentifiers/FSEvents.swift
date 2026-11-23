import Glibc
import PerryObjCInterop

// Mac apps' alone: armv7 runs only iOS apps, so it has none of this.
#if !arch(arm)
// FSEvents, CoreServices' file system event streams: a stream keeps the
// paths it watches and answers them back (Xcode 4's file watcher asserts
// that it watches every path it asked for), and is scheduled, started and
// stopped, but no event is ever delivered: a program sees no changes made
// outside it.

/// A stream's state, kept by the address of its handle.
private final class EventStream {
    var paths: [String]
    var references = 1
    var started = false

    init(paths: [String]) { self.paths = paths }
}

nonisolated(unsafe) private var streams: [UnsafeMutableRawPointer: EventStream] = [:]
nonisolated(unsafe) private let streamsLock: UnsafeMutablePointer<pthread_mutex_t> = {
    let lock = UnsafeMutablePointer<pthread_mutex_t>.allocate(capacity: 1)
    pthread_mutex_init(lock, nil)
    return lock
}()

private func withStreams<T>(_ body: (inout [UnsafeMutableRawPointer: EventStream]) -> T) -> T {
    pthread_mutex_lock(streamsLock)
    defer { pthread_mutex_unlock(streamsLock) }
    return body(&streams)
}

/// The strings of a CFArray of paths.
private func pathStrings(_ array: UnsafeMutableRawPointer?) -> [String] {
    guard let array else { return [] }
    return NSObject(objcObject: array, ownership: .retain).unsafeCast(to: NSArray.self).elements.map(\.stringValue)
}

private func makeStream(_ paths: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer? {
    let handle = UnsafeMutableRawPointer.allocate(byteCount: 16, alignment: 16)
    let stream = EventStream(paths: pathStrings(paths))
    withStreams { $0[handle] = stream }
    return handle
}

/// FSEventStreamRef FSEventStreamCreate(CFAllocatorRef, FSEventStreamCallback,
/// FSEventStreamContext *, CFArrayRef pathsToWatch, FSEventStreamEventId
/// sinceWhen, CFTimeInterval latency, FSEventStreamCreateFlags).
@c(_FSEventStreamCreate)
public func FSEventStreamCreate(_ allocator: UnsafeRawPointer?, _ callback: UnsafeRawPointer?, _ context: UnsafeRawPointer?,
                                _ paths: UnsafeMutableRawPointer?, _ since: UInt64, _ latency: Double, _ flags: UInt32)
    -> UnsafeMutableRawPointer? {
    makeStream(paths)
}

/// The same, for paths relative to a device's root.
@c(_FSEventStreamCreateRelativeToDevice)
public func FSEventStreamCreateRelativeToDevice(_ allocator: UnsafeRawPointer?, _ callback: UnsafeRawPointer?,
                                                _ context: UnsafeRawPointer?, _ device: Int32,
                                                _ paths: UnsafeMutableRawPointer?, _ since: UInt64, _ latency: Double,
                                                _ flags: UInt32) -> UnsafeMutableRawPointer? {
    makeStream(paths)
}

/// The paths the stream watches, as a new CFArray.
@c(_FSEventStreamCopyPathsBeingWatched)
public func FSEventStreamCopyPathsBeingWatched(_ stream: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer? {
    let paths = stream.flatMap { handle in withStreams { $0[handle]?.paths } } ?? []
    return ObjCRuntime.retain(NSMutableArray.of(paths.map(NSObject.string)).objcObject)
}

@c(_FSEventStreamRetain)
public func FSEventStreamRetain(_ stream: UnsafeMutableRawPointer?) {
    guard let stream else { return }
    withStreams { $0[stream]?.references += 1 }
}

@c(_FSEventStreamRelease)
public func FSEventStreamRelease(_ stream: UnsafeMutableRawPointer?) {
    guard let stream else { return }
    let freed = withStreams { streams -> Bool in
        guard let state = streams[stream] else { return false }
        state.references -= 1
        guard state.references <= 0 else { return false }
        streams[stream] = nil
        return true
    }
    if freed { stream.deallocate() }
}

@c(_FSEventStreamScheduleWithRunLoop)
public func FSEventStreamScheduleWithRunLoop(_ stream: UnsafeMutableRawPointer?, _ runLoop: UnsafeRawPointer?, _ mode: UnsafeRawPointer?) {}

@c(_FSEventStreamUnscheduleFromRunLoop)
public func FSEventStreamUnscheduleFromRunLoop(_ stream: UnsafeMutableRawPointer?, _ runLoop: UnsafeRawPointer?, _ mode: UnsafeRawPointer?) {}

@c(_FSEventStreamSetDispatchQueue)
public func FSEventStreamSetDispatchQueue(_ stream: UnsafeMutableRawPointer?, _ queue: UnsafeRawPointer?) {}

@c(_FSEventStreamStart)
public func FSEventStreamStart(_ stream: UnsafeMutableRawPointer?) -> Bool {
    guard let stream else { return false }
    return withStreams { streams -> Bool in
        guard let state = streams[stream] else { return false }
        state.started = true
        return true
    }
}

@c(_FSEventStreamStop)
public func FSEventStreamStop(_ stream: UnsafeMutableRawPointer?) {
    guard let stream else { return }
    withStreams { $0[stream]?.started = false }
}

@c(_FSEventStreamInvalidate)
public func FSEventStreamInvalidate(_ stream: UnsafeMutableRawPointer?) {}

/// Nothing is pending: the latest event is the one there always is.
@c(_FSEventStreamFlushAsync)
public func FSEventStreamFlushAsync(_ stream: UnsafeMutableRawPointer?) -> UInt64 { 0 }

@c(_FSEventStreamFlushSync)
public func FSEventStreamFlushSync(_ stream: UnsafeMutableRawPointer?) {}

@c(_FSEventStreamGetLatestEventId)
public func FSEventStreamGetLatestEventId(_ stream: UnsafeMutableRawPointer?) -> UInt64 { 0 }

@c(_FSEventsGetCurrentEventId)
public func FSEventsGetCurrentEventId() -> UInt64 { 0 }

@c(_FSEventStreamShow)
public func FSEventStreamShow(_ stream: UnsafeMutableRawPointer?) {}
#endif
