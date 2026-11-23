// vDSP's conversions between Float and Float16, which the SDK exports only
// on arm64 (Swift has no Float16 on x86_64 macOS): one-row vImage buffers
// through vImageConvert_Planar16FtoPlanarF and vImageConvert_PlanarFtoPlanar16F.

#if arch(arm64)

@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
private func convertHalves<U, V>(_ source: U, _ destination: inout V,
                                 _ convert: (UnsafePointer<vImage_Buffer>, UnsafePointer<vImage_Buffer>) -> vImage_Error)
    where U: Accelerate::AccelerateBuffer, V: Accelerate::AccelerateMutableBuffer {
    precondition(source.count == destination.count, "the source and destination must have the same number of elements")
    let count = source.count
    guard count > 0 else { return }
    source.withUnsafeBufferPointer { src in
        destination.withUnsafeMutableBufferPointer { dst in
            var from = vImage_Buffer(data: UnsafeMutableRawPointer(mutating: src.baseAddress!), height: 1, width: vImagePixelCount(count),
                                     rowBytes: count * MemoryLayout<U.Element>.stride)
            var to = vImage_Buffer(data: UnsafeMutableRawPointer(dst.baseAddress!), height: 1, width: vImagePixelCount(count),
                                   rowBytes: count * MemoryLayout<V.Element>.stride)
            _ = convert(&from, &to)
        }
    }
}

extension Accelerate::vDSP {
    @available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
    public static func float16ToFloat<U>(_ source: U) -> [Swift::Float] where U: Accelerate::AccelerateBuffer, U.Element == Swift::Float16 {
        var result = [Float](repeating: 0, count: source.count)
        convertElements(of: source, to: &result)
        return result
    }

    @available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
    public static func convertElements<U, V>(of source: U, to destination: inout V) where U: Accelerate::AccelerateBuffer, V: Accelerate::AccelerateMutableBuffer, U.Element == Swift::Float16, V.Element == Swift::Float {
        convertHalves(source, &destination) { vImageConvert_Planar16FtoPlanarF($0, $1, vImage_Flags(kvImageNoFlags)) }
    }

    @available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
    public static func floatToFloat16<U>(_ source: U) -> [Swift::Float16] where U: Accelerate::AccelerateBuffer, U.Element == Swift::Float {
        var result = [Float16](repeating: 0, count: source.count)
        convertElements(of: source, to: &result)
        return result
    }

    @available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
    public static func convertElements<U, V>(of source: U, to destination: inout V) where U: Accelerate::AccelerateBuffer, V: Accelerate::AccelerateMutableBuffer, U.Element == Swift::Float, V.Element == Swift::Float16 {
        convertHalves(source, &destination) { vImageConvert_PlanarFtoPlanar16F($0, $1, vImage_Flags(kvImageNoFlags)) }
    }
}

#endif
