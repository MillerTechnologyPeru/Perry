// The graph builder's Float16 API, which the SDK exports only on arm64
// (Swift has no Float16 on x86_64 macOS).

#if arch(arm64)

@available(macOS 26.0, iOS 26.0, tvOS 26.0, watchOS 26.0, visionOS 26.0, *)
extension Accelerate::BNNSGraph.Accelerate::Builder {
    /// A half-precision matrix from rows (rowMajor) or columns.
    public func constant(values: Swift::Array<Swift::Array<Swift::Float16>>, rowMajor: Swift::Bool = false) -> Accelerate::BNNSGraph.Accelerate::Builder.Accelerate::Tensor<Swift::Float16> {
        let outer = values.count, inner = values.first?.count ?? 0
        var flat = [Float16]()
        if rowMajor {
            flat = values.flatMap { $0 }
            return constant(values: flat, shape: [outer, inner])
        }
        for r in 0..<inner {
            for c in 0..<outer { flat.append(r < values[c].count ? values[c][r] : 0) }
        }
        return constant(values: flat, shape: [inner, outer])
    }
}

@available(macOS 26.0, iOS 26.0, tvOS 26.0, watchOS 26.0, visionOS 26.0, *)
extension Swift::Float16: Accelerate::BNNSGraph.Accelerate::Builder.Accelerate::OperationParameter {
    public typealias Element = Swift::Float16
    public func graphBuilderTensor(_ builder: Accelerate::BNNSGraph.Accelerate::Builder) -> Accelerate::BNNSGraph.Accelerate::Builder.Accelerate::Tensor<Swift::Float16> {
        builder.constant(value: self)
    }
}

#endif
