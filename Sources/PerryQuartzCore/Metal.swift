// Metal, on a system without it: there is no device, as on hardware Metal
// doesn't support, so apps that can draw with OpenGL ES do.

/// The system's Metal device: none.
@c(_MTLCreateSystemDefaultDevice)
public func MTLCreateSystemDefaultDevice() -> UnsafeMutableRawPointer? { nil }
