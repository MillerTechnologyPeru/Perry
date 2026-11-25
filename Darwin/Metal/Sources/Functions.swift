import Foundation

// Device notifications are macOS's alone.
#if os(macOS)
@available(swift 4)
@available(macOS 10.13, *)
public func MTLCopyAllDevicesWithObserver(handler: @escaping (MTLDevice, MTLDeviceNotificationName) -> Void)
    -> (devices: [MTLDevice], observer: NSObject) {
    var observer: NSObjectProtocol?
    let devices = __MTLCopyAllDevicesWithObserver(&observer, handler)
    // Metal always gives an observer; an empty object stands in otherwise,
    // which MTLRemoveDeviceObserver ignores.
    return (devices, observer as? NSObject ?? NSObject())
}
#endif

@available(macOS 13.0, macCatalyst 16.0, iOS 16.0, tvOS 16.0, *)
public func MTLIOCreateCompressionContext(_ path: String, _ type: MTLIOCompressionMethod, _ chunkSize: Int) -> MTLIOCompressionContext? {
    __MTLIOCreateCompressionContext(path, type, chunkSize)
}

/// The Objective-C protocol the inlinable async waits of MTLCommandBuffer
/// send their messages through.
@available(macOS 10.15, iOS 13.0, tvOS 13.0, *)
@usableFromInline
@objc internal protocol __MTLObjCProxy: NSObjectProtocol {
    @available(macOS 26.0, iOS 26.0, tvOS 26.0, visionOS 26.0, *)
    @objc(__waitUntilScheduledAsync:) func __waitUntilScheduledAsync(_: @escaping (MTLCommandBuffer) -> Void)
    @available(macOS 26.0, iOS 26.0, tvOS 26.0, visionOS 26.0, *)
    @objc(__waitUntilCompletedAsync:) func __waitUntilCompletedAsync(_: @escaping (MTLCommandBuffer) -> Void)
    @objc(waitUntilScheduled) func __waitUntilScheduledSync()
    @objc(waitUntilCompleted) func __waitUntilCompletedSync()
}
