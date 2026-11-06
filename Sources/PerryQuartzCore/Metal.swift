import PerryObjCInterop

// Metal, on a system without it: there is no device, as on hardware Metal
// doesn't support, so apps that can draw with OpenGL ES do.

/// The system's Metal device: none.
@c(_MTLCreateSystemDefaultDevice)
public func MTLCreateSystemDefaultDevice() -> UnsafeMutableRawPointer? { nil }

/// Every Metal device: none, +1.
@c(_MTLCopyAllDevices)
public func MTLCopyAllDevices() -> UnsafeMutableRawPointer? { ObjCRuntime.retain(NSMutableArray.empty().objcObject) }

/// Every Metal device, and an observer token for devices added and
/// removed, which never are.
@c(_MTLCopyAllDevicesWithObserver)
public func MTLCopyAllDevicesWithObserver(_ observer: UnsafeMutablePointer<UnsafeMutableRawPointer?>?,
                                          _ handler: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer? {
    observer?.pointee = nil
    return MTLCopyAllDevices()
}

@c(_MTLRemoveDeviceObserver) public func MTLRemoveDeviceObserver(_ observer: UnsafeMutableRawPointer?) {}
