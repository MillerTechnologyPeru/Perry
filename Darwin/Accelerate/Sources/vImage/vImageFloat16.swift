// The Float16 member of the withUnsafePixelBuffer family, which exists
// where Swift has Float16 (arm64; not on x86_64 macOS).

#if arch(arm64)
@available(macOS 15.0, iOS 18.0, tvOS 18.0, watchOS 11.0, *)
extension AccelerateMutableBuffer where Self.Element == Float16 {
    public mutating func withUnsafePixelBuffer<R>(body: (vImage.PixelBuffer<vImage.Planar16F>) throws -> R) rethrows -> R {
        try withUnsafeMutableBufferPointer { pointer in
            try _vImageWithRawBuffer(pointer) {
                try body(vImage.PixelBuffer<vImage.Planar16F>(data: $0, width: pointer.count, height: 1, byteCountPerRow: $1))
            }
        }
    }
}
#endif
