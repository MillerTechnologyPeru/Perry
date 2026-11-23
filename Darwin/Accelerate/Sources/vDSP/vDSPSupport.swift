import Swift

// Helpers of Perry's vDSP and vForce: buffers' base addresses for the C
// calls, and arrays the inout variants fill.

/// A pointer for an empty buffer, which the C functions never read (they
/// are given a count of 0).
@inline(__always)
internal func _vdspEmptyMutable<E>() -> UnsafeMutablePointer<E> {
    UnsafeMutablePointer(bitPattern: 0x40)!
}

@inline(__always)
internal func _vdspEmpty<E>() -> UnsafePointer<E> {
    UnsafePointer(_vdspEmptyMutable() as UnsafeMutablePointer<E>)
}

/// Calls `body` with the base address of a buffer's elements.
@inline(__always)
internal func _rd<B: AccelerateBuffer, R>(_ buffer: B, _ body: (UnsafePointer<B.Element>) throws -> R) rethrows -> R {
    try buffer.withUnsafeBufferPointer { try body($0.baseAddress ?? _vdspEmpty()) }
}

/// Calls `body` with the base address of a mutable buffer's elements.
@inline(__always)
internal func _wr<B: AccelerateMutableBuffer, R>(_ buffer: inout B, _ body: (UnsafeMutablePointer<B.Element>) throws -> R) rethrows -> R {
    try buffer.withUnsafeMutableBufferPointer { try body($0.baseAddress ?? _vdspEmptyMutable()) }
}

/// An array of `count` elements (of a trivial type), zeroed, then filled
/// by `fill`.
internal func _make<E>(_ count: Int, _ fill: (inout UnsafeMutableBufferPointer<E>) throws -> Void) rethrows -> [E] {
    let count = Swift.max(count, 0)
    return try [E](unsafeUninitializedCapacity: count) { buffer, initialized in
        if let base = buffer.baseAddress {
            UnsafeMutableRawPointer(base).initializeMemory(as: UInt8.self, repeating: 0, count: count * MemoryLayout<E>.stride)
        }
        try fill(&buffer)
        initialized = count
    }
}

/// A biquad filter's setup and, for a single channel, its delay values,
/// shared by copies of a vDSP.Biquad and destroyed with the last of them.
@available(macOS 10.15, iOS 13.0, tvOS 13.0, watchOS 6.0, *)
internal final class _vDSPBiquadState<T: vDSP_FloatingPointBiquadFilterable> {
    let setup: OpaquePointer
    let channelCount: vDSP_Length
    let sectionCount: vDSP_Length
    let delays: UnsafeMutablePointer<T.BiquadFunctions.Scalar>

    init(setup: OpaquePointer, channelCount: vDSP_Length, sectionCount: vDSP_Length) {
        self.setup = setup
        self.channelCount = channelCount
        self.sectionCount = sectionCount
        let count = 2 * Int(sectionCount) + 2
        delays = .allocate(capacity: count)
        UnsafeMutableRawPointer(delays).initializeMemory(as: UInt8.self, repeating: 0, count: count * MemoryLayout<T.BiquadFunctions.Scalar>.stride)
    }

    deinit {
        T.BiquadFunctions.destroySetup(channelCount: UInt(channelCount), biquadSetup: setup)
        delays.deallocate()
    }
}
