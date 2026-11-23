import Swift
import Darwin

// BNNS's direct functions (copy, transpose, reductions, gathers and
// scatters, top-k, comparisons, quantization, norms and clipping, matrix
// multiplication, sparsification), its random generators and nearest
// neighbors, each a call to the C function it stands for.

@available(macOS 11.0, iOS 14.0, tvOS 14.0, watchOS 7.0, *)
extension Accelerate::BNNS {
    public static func transpose(input: Accelerate::BNNSNDArrayDescriptor, output: Accelerate::BNNSNDArrayDescriptor, firstTransposeAxis: Swift::Int, secondTransposeAxis: Swift::Int, filterParameters: Accelerate::BNNSFilterParameters? = nil) throws {
        var input = input, output = output
        try _withFilterParameters(filterParameters) { fp in
            try _check(BNNSTranspose(&output, &input, firstTransposeAxis, secondTransposeAxis, fp))
        }
    }

    public static func copy(_ source: Accelerate::BNNSNDArrayDescriptor, to destination: Accelerate::BNNSNDArrayDescriptor, filterParameters: Accelerate::BNNSFilterParameters? = nil) throws {
        var source = source, destination = destination
        try _withFilterParameters(filterParameters) { fp in
            try _check(BNNSCopy(&destination, &source, fp))
        }
    }

    public static func applyReduction(_ reductionFunction: Accelerate::BNNS.Accelerate::ReductionFunction, input: Accelerate::BNNSNDArrayDescriptor, output: Accelerate::BNNSNDArrayDescriptor, weights: Accelerate::BNNSNDArrayDescriptor?, filterParameters: Accelerate::BNNSFilterParameters? = nil) throws {
        var parameters = BNNSLayerParametersReduction(i_desc: input, o_desc: output, w_desc: weights ?? _emptyDescriptor(),
                                                      reduce_func: reductionFunction.bnnsReduceFunction, epsilon: reductionFunction.epsilon)
        try _withFilterParameters(filterParameters) { fp in
            try _check(BNNSDirectApplyReduction(&parameters, fp))
        }
    }

    public static func applyTopK(k: Swift::Int, input: Accelerate::BNNSNDArrayDescriptor, bestValues: Accelerate::BNNSNDArrayDescriptor, bestIndices: Accelerate::BNNSNDArrayDescriptor, axis: Swift::Int, batchSize: Swift::Int, filterParameters: Accelerate::BNNSFilterParameters? = nil) throws {
        var input = input, values = bestValues, indices = bestIndices
        try _withFilterParameters(filterParameters) { fp in
            try _check(BNNSDirectApplyTopK(k, axis, batchSize, &input, input.batchStride, &values, values.batchStride, &indices, indices.batchStride, fp))
        }
    }

    public static func applyInTopK(k: Swift::Int, input: Accelerate::BNNSNDArrayDescriptor, testIndices: Accelerate::BNNSNDArrayDescriptor, output: Accelerate::BNNSNDArrayDescriptor, axis: Swift::Int, batchSize: Swift::Int, filterParameters: Accelerate::BNNSFilterParameters? = nil) throws {
        var input = input, test = testIndices, output = output
        try _withFilterParameters(filterParameters) { fp in
            try _check(BNNSDirectApplyInTopK(k, axis, batchSize, &input, input.batchStride, &test, test.batchStride, &output, output.batchStride, fp))
        }
    }
}

@available(macOS 11.0, iOS 14.0, tvOS 14.0, watchOS 7.0, *)
@available(*, deprecated, message: "Use the BNNSGraph API instead.")
extension Accelerate::BNNS {
    public static func compare(_ inputA: Accelerate::BNNSNDArrayDescriptor, _ inputB: Accelerate::BNNSNDArrayDescriptor, using relationalOperator: Accelerate::BNNS.Accelerate::RelationalOperator, output: Accelerate::BNNSNDArrayDescriptor) throws {
        var a = inputA, b = inputB, output = output
        try _check(BNNSCompareTensor(&a, &b, relationalOperator.value, &output))
    }
}

@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
@available(*, deprecated, message: "Use the BNNSGraph API instead.")
extension Accelerate::BNNS {
    @available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
    public static func tile(input: Accelerate::BNNSNDArrayDescriptor, output: Accelerate::BNNSNDArrayDescriptor, filterParameters: Accelerate::BNNSFilterParameters? = nil) throws {
        var input = input, output = output
        try _withFilterParameters(filterParameters) { fp in
            try _check(BNNSTile(&input, &output, fp))
        }
    }

    @available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
    public static func tileBackward(outputGradient: Accelerate::BNNSNDArrayDescriptor, generatingInputGradient inputGradient: Accelerate::BNNSNDArrayDescriptor, filterParameters: Accelerate::BNNSFilterParameters? = nil) throws {
        var outGradient = outputGradient, inGradient = inputGradient
        try _withFilterParameters(filterParameters) { fp in
            try _check(BNNSTileBackward(&inGradient, &outGradient, fp))
        }
    }

    /// Copies the band of the last two dimensions: lowerBandCount
    /// subdiagonals and upperBandCount superdiagonals, nil for all of them.
    @available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
    public static func copyBandPart(_ source: Accelerate::BNNSNDArrayDescriptor, to destination: Accelerate::BNNSNDArrayDescriptor, lowerBandCount: Swift::Int?, upperBandCount: Swift::Int?, filterParameters: Accelerate::BNNSFilterParameters? = nil) throws {
        var source = source, destination = destination
        try _withFilterParameters(filterParameters) { fp in
            try _check(BNNSBandPart(Int32(lowerBandCount ?? -1), Int32(upperBandCount ?? -1), &source, &destination, fp))
        }
    }

    @available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
    public static func shuffle(_ shuffleType: Accelerate::BNNS.Accelerate::ShuffleType, input: Accelerate::BNNSNDArrayDescriptor, output: Accelerate::BNNSNDArrayDescriptor, filterParameters: Accelerate::BNNSFilterParameters? = nil) throws {
        var input = input, output = output
        let type = BNNSShuffleType(rawValue: shuffleType == .depthToSpaceNCHW ? 2 : 3)
        try _withFilterParameters(filterParameters) { fp in
            try _check(BNNSShuffle(type, &input, &output, fp))
        }
    }

    @available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
    public static func gather(input: Accelerate::BNNSNDArrayDescriptor, indices: Accelerate::BNNSNDArrayDescriptor, output: Accelerate::BNNSNDArrayDescriptor, axis: Swift::Int, filterParameters: Accelerate::BNNSFilterParameters? = nil) throws {
        var input = input, indices = indices, output = output
        try _withFilterParameters(filterParameters) { fp in
            try _check(BNNSGather(axis, &input, &indices, &output, fp))
        }
    }

    @available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
    public static func gatherND(input: Accelerate::BNNSNDArrayDescriptor, indices: Accelerate::BNNSNDArrayDescriptor, output: Accelerate::BNNSNDArrayDescriptor, filterParameters: Accelerate::BNNSFilterParameters? = nil) throws {
        var input = input, indices = indices, output = output
        try _withFilterParameters(filterParameters) { fp in
            try _check(BNNSGatherND(&input, &indices, &output, fp))
        }
    }

    @available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
    public static func scatter(input: Accelerate::BNNSNDArrayDescriptor, indices: Accelerate::BNNSNDArrayDescriptor, output: Accelerate::BNNSNDArrayDescriptor, axis: Swift::Int, reductionFunction: Accelerate::BNNS.Accelerate::ReductionFunction, filterParameters: Accelerate::BNNSFilterParameters? = nil) throws {
        try _scatter(input: input, indices: indices, output: output, axis: axis, function: reductionFunction.bnnsReduceFunction, filterParameters: filterParameters)
    }

    @available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
    public static func scatterND(input: Accelerate::BNNSNDArrayDescriptor, indices: Accelerate::BNNSNDArrayDescriptor, output: Accelerate::BNNSNDArrayDescriptor, reductionFunction: Accelerate::BNNS.Accelerate::ReductionFunction, filterParameters: Accelerate::BNNSFilterParameters? = nil) throws {
        try _scatterND(input: input, indices: indices, output: output, function: reductionFunction.bnnsReduceFunction, filterParameters: filterParameters)
    }
}

@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
func _scatter(input: BNNSNDArrayDescriptor, indices: BNNSNDArrayDescriptor, output: BNNSNDArrayDescriptor, axis: Int, function: BNNSReduceFunction,
              filterParameters: BNNSFilterParameters?) throws {
    var input = input, indices = indices, output = output
    try _withFilterParameters(filterParameters) { fp in
        try _check(BNNSScatter(axis, function, &input, &indices, &output, fp))
    }
}

@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
func _scatterND(input: BNNSNDArrayDescriptor, indices: BNNSNDArrayDescriptor, output: BNNSNDArrayDescriptor, function: BNNSReduceFunction,
                filterParameters: BNNSFilterParameters?) throws {
    var input = input, indices = indices, output = output
    try _withFilterParameters(filterParameters) { fp in
        try _check(BNNSScatterND(function, &input, &indices, &output, fp))
    }
}

@available(macOS 15.0, iOS 18.0, tvOS 18.0, watchOS 11.0, *)
extension Accelerate::BNNS {
    /// Scatters, replacing the output's values (no reduction).
    public static func scatter(input: Accelerate::BNNSNDArrayDescriptor, indices: Accelerate::BNNSNDArrayDescriptor, output: Accelerate::BNNSNDArrayDescriptor, axis: Swift::Int, filterParameters: Accelerate::BNNSFilterParameters? = nil) throws {
        try _scatter(input: input, indices: indices, output: output, axis: axis, function: BNNSReduceFunction(rawValue: 15), filterParameters: filterParameters)
    }

    public static func scatterND(input: Accelerate::BNNSNDArrayDescriptor, indices: Accelerate::BNNSNDArrayDescriptor, output: Accelerate::BNNSNDArrayDescriptor, filterParameters: Accelerate::BNNSFilterParameters? = nil) throws {
        try _scatterND(input: input, indices: indices, output: output, function: BNNSReduceFunction(rawValue: 15), filterParameters: filterParameters)
    }
}

@available(macOS 12.0, iOS 15.0, tvOS 15.0, watchOS 8.0, *)
@available(*, deprecated, message: "Use the BNNSGraph API instead.")
extension Accelerate::BNNS {
    public static func quantize(batchSize: Swift::Int, input: Accelerate::BNNSNDArrayDescriptor, output: Accelerate::BNNSNDArrayDescriptor, axis: Swift::Int? = nil, scale: Accelerate::BNNSNDArrayDescriptor?, bias: Accelerate::BNNSNDArrayDescriptor?, filterParameters: Accelerate::BNNSFilterParameters? = nil) throws {
        try _quantize(0, batchSize: batchSize, input: input, output: output, axis: axis, scale: scale, bias: bias, filterParameters: filterParameters)
    }

    public static func dequantize(batchSize: Swift::Int, input: Accelerate::BNNSNDArrayDescriptor, output: Accelerate::BNNSNDArrayDescriptor, axis: Swift::Int? = nil, scale: Accelerate::BNNSNDArrayDescriptor?, bias: Accelerate::BNNSNDArrayDescriptor?, filterParameters: Accelerate::BNNSFilterParameters? = nil) throws {
        try _quantize(1, batchSize: batchSize, input: input, output: output, axis: axis, scale: scale, bias: bias, filterParameters: filterParameters)
    }

    static func _quantize(_ function: UInt32, batchSize: Int, input: BNNSNDArrayDescriptor, output: BNNSNDArrayDescriptor, axis: Int?,
                          scale: BNNSNDArrayDescriptor?, bias: BNNSNDArrayDescriptor?, filterParameters: BNNSFilterParameters?) throws {
        var parameters = BNNSLayerParametersQuantization(axis_mask: axis.map { 1 << $0 } ?? 0, function: BNNSQuantizerFunction(rawValue: function),
                                                         i_desc: input, o_desc: output, scale: scale ?? _emptyDescriptor(), bias: bias ?? _emptyDescriptor())
        try _withFilterParameters(filterParameters) { fp in
            try _check(BNNSDirectApplyQuantizer(&parameters, fp, batchSize, input.batchStride, output.batchStride))
        }
    }

    /// The L2 norm over the axes (all of them when nil).
    public static func computeNorm(input: Accelerate::BNNSNDArrayDescriptor, output: Accelerate::BNNSNDArrayDescriptor, axes: [Swift::Int]? = nil) throws {
        var input = input, output = output
        try _check(BNNSComputeNorm(&output, &input, BNNSNormType(rawValue: 1), _axisFlags(axes)))
    }

    public static func computeNormBackward(input: Accelerate::BNNSNDArrayDescriptor, output: Accelerate::BNNSNDArrayDescriptor, axes: [Swift::Int]? = nil, outputGradient: Accelerate::BNNSNDArrayDescriptor, generatingInputGradient inputGradient: Accelerate::BNNSNDArrayDescriptor) throws {
        var inGradient = inputGradient, outGradient = outputGradient
        try _check(BNNSComputeNormBackward(try _data(input), &inGradient, try _data(output), &outGradient, BNNSNormType(rawValue: 1), _axisFlags(axes)))
    }

    public static func clipByGlobalNorm(threshold: Swift::Float, inputs: [Accelerate::BNNSNDArrayDescriptor], outputs: [Accelerate::BNNSNDArrayDescriptor], globalNorm: Swift::Float = 0) throws {
        try _withDescriptorPointers(outputs.map { Optional($0) }) { destinations in
            try _withDescriptorPointers(inputs.map { Optional($0) }) { sources in
                var destinations = destinations.map { $0! }
                var sources = sources.map { UnsafePointer($0!) }
                try _check(BNNSClipByGlobalNorm(&destinations, &sources, inputs.count, threshold, globalNorm))
            }
        }
    }

    public static func clip(to bounds: Swift::ClosedRange<Swift::Float>, input: Accelerate::BNNSNDArrayDescriptor, output: Accelerate::BNNSNDArrayDescriptor) throws {
        var input = input, output = output
        try _check(BNNSClipByValue(&output, &input, bounds.lowerBound, bounds.upperBound))
    }

    public static func clipByNorm(threshold: Swift::Float, input: Accelerate::BNNSNDArrayDescriptor, output: Accelerate::BNNSNDArrayDescriptor, axes: [Swift::Int]? = nil) throws {
        var input = input, output = output
        try _check(BNNSClipByNorm(&output, &input, threshold, _axisFlags(axes)))
    }
}

@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
@available(*, deprecated, message: "Use the BNNSGraph API instead.")
extension Accelerate::BNNS {
    public static func matrixMultiplicationWorkspaceSize(inputA: Accelerate::BNNSNDArrayDescriptor, transposed transposeA: Swift::Bool, inputB: Accelerate::BNNSNDArrayDescriptor, transposed transposeB: Swift::Bool, output: Accelerate::BNNSNDArrayDescriptor, alpha: Swift::Float, filterParameters: Accelerate::BNNSFilterParameters? = nil) -> Swift::Int? {
        var a = inputA, b = inputB, output = output
        let size = _withFilterParameters(filterParameters) { fp in
            BNNSMatMulWorkspaceSize(transposeA, transposeB, alpha, &a, &b, &output, fp)
        }
        return size < 0 ? nil : size
    }

    public static func applyMatrixMultiplication(inputA: Accelerate::BNNSNDArrayDescriptor, transposed transposeA: Swift::Bool, inputB: Accelerate::BNNSNDArrayDescriptor, transposed transposeB: Swift::Bool, output: Accelerate::BNNSNDArrayDescriptor, alpha: Swift::Float, workspace: Swift::UnsafeMutableRawBufferPointer?, filterParameters: Accelerate::BNNSFilterParameters? = nil) throws {
        var a = inputA, b = inputB, output = output
        try _withFilterParameters(filterParameters) { fp in
            try _check(BNNSMatMul(transposeA, transposeB, alpha, &a, &b, &output, workspace?.baseAddress, fp))
        }
    }
}

@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
@available(*, deprecated, message: "Use the BNNSGraph API instead.")
extension Accelerate::BNNS.Accelerate::FullyConnectedLayer {
    @available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
    public static func sparsify(batchSize: Swift::Int = 1, inputLayout layout: Accelerate::BNNS.Accelerate::SparseLayout, inputDenseShape: Accelerate::BNNSNDArrayDescriptor, inputValues: Accelerate::BNNSNDArrayDescriptor, output: inout Accelerate::BNNSNDArrayDescriptor, sparseParameters: Accelerate::BNNS.Accelerate::SparseParameters? = nil, workspace: Swift::UnsafeMutableRawBufferPointer? = nil, filterParameters: Accelerate::BNNSFilterParameters? = nil) throws {
        var dense = inputDenseShape, values = inputValues
        var sparse = sparseParameters.map {
            BNNSSparsityParameters(flags: 0, sparsity_ratio: ($0.ratio.numerator, $0.ratio.denominator),
                                   sparsity_type: BNNSSparsityType(rawValue: 0), target_system: $0.targetSystem)
        }
        func call(_ sp: UnsafePointer<BNNSSparsityParameters>?) throws {
            try _withFilterParameters(filterParameters) { fp in
                switch layout {
                case let .coo(indices):
                    var indices = indices
                    try _check(BNNSNDArrayFullyConnectedSparsifySparseCOO(&dense, &indices, &values, &output, sp, batchSize,
                                                                          workspace?.baseAddress, workspace?.count ?? 0, fp))
                case let .csr(columns, rows):
                    var columns = columns, rows = rows
                    try _check(BNNSNDArrayFullyConnectedSparsifySparseCSR(&dense, &columns, &rows, &values, &output, sp, batchSize,
                                                                          workspace?.baseAddress, workspace?.count ?? 0, fp))
                }
            }
        }
        if sparse != nil {
            try withUnsafePointer(to: &sparse!) { try call($0) }
        } else {
            try call(nil)
        }
    }
}

// MARK: - Random numbers

@available(macOS 12.0, iOS 15.0, tvOS 15.0, watchOS 8.0, *)
extension Accelerate::BNNS {
    /// A snapshot of a random generator's state.
    @_hasMissingDesignatedInitializers public class RandomGeneratorState {
        let bytes: [UInt8]

        init(bytes: [UInt8]) {
            self.bytes = bytes
        }

        deinit {}
    }

    public class RandomGenerator {
        let generator: BNNSRandomGenerator

        public init?(method: Accelerate::BNNS.Accelerate::RandomGeneratorMethod, seed: Swift::UInt64? = nil, filterParameters: Accelerate::BNNSFilterParameters? = nil) {
            let made = _withFilterParameters(filterParameters) { fp -> BNNSRandomGenerator? in
                if let seed {
                    return BNNSCreateRandomGeneratorWithSeed(BNNSRandomGeneratorMethod(rawValue: 0), seed, fp)
                }
                return BNNSCreateRandomGenerator(BNNSRandomGeneratorMethod(rawValue: 0), fp)
            }
            guard let made else { return nil }
            generator = made
        }

        deinit {
            BNNSDestroyRandomGenerator(generator)
        }

        public var state: Accelerate::BNNS.Accelerate::RandomGeneratorState {
            get {
                let size = BNNSRandomGeneratorStateSize(generator)
                var bytes = [UInt8](repeating: 0, count: Swift.max(size, 0))
                _ = bytes.withUnsafeMutableBytes { BNNSRandomGeneratorGetState(generator, size, $0.baseAddress!) }
                return RandomGeneratorState(bytes: bytes)
            }
            set {
                var bytes = newValue.bytes
                _ = bytes.withUnsafeMutableBytes { BNNSRandomGeneratorSetState(generator, $0.count, $0.baseAddress!) }
            }
        }
    }
}

@available(macOS 12.0, iOS 15.0, tvOS 15.0, watchOS 8.0, *)
extension Accelerate::BNNSNDArrayDescriptor {
    public static func allocate<Scalar>(randomUniformUsing: Accelerate::BNNS.Accelerate::RandomGenerator, range: Swift::ClosedRange<Scalar>, shape: Accelerate::BNNS.Accelerate::Shape, batchSize: Swift::Int = 1) -> Accelerate::BNNSNDArrayDescriptor? where Scalar: Accelerate::BNNSScalar, Scalar: Swift::BinaryFloatingPoint {
        var descriptor = allocateUninitialized(scalarType: Scalar.self, shape: _batched(shape, batchSize))
        guard BNNSRandomFillUniformFloat(randomUniformUsing.generator, &descriptor, Float(range.lowerBound), Float(range.upperBound)) == 0 else {
            descriptor.deallocate()
            return nil
        }
        return _unbatched(descriptor, shape)
    }

    public static func allocate<Scalar>(randomUniformUsing: Accelerate::BNNS.Accelerate::RandomGenerator, range: Swift::ClosedRange<Scalar>, shape: Accelerate::BNNS.Accelerate::Shape, batchSize: Swift::Int = 1) -> Accelerate::BNNSNDArrayDescriptor? where Scalar: Accelerate::BNNSScalar, Scalar: Swift::FixedWidthInteger {
        var descriptor = allocateUninitialized(scalarType: Scalar.self, shape: _batched(shape, batchSize))
        guard BNNSRandomFillUniformInt(randomUniformUsing.generator, &descriptor, Int64(range.lowerBound), Int64(range.upperBound)) == 0 else {
            descriptor.deallocate()
            return nil
        }
        return _unbatched(descriptor, shape)
    }
}

@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
extension Accelerate::BNNSNDArrayDescriptor {
    @available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
    public static func allocate<Scalar>(randomNormalUsing: Accelerate::BNNS.Accelerate::RandomGenerator, mean: Scalar, standardDeviation: Scalar, shape: Accelerate::BNNS.Accelerate::Shape, batchSize: Swift::Int = 1) -> Accelerate::BNNSNDArrayDescriptor? where Scalar: Accelerate::BNNSScalar, Scalar: Swift::BinaryFloatingPoint {
        var descriptor = allocateUninitialized(scalarType: Scalar.self, shape: _batched(shape, batchSize))
        guard BNNSRandomFillNormalFloat(randomNormalUsing.generator, &descriptor, Float(mean), Float(standardDeviation)) == 0 else {
            descriptor.deallocate()
            return nil
        }
        return _unbatched(descriptor, shape)
    }
}

/// A vector holding batchSize items of a shape, for filling at once.
@available(macOS 11.0, iOS 14.0, tvOS 14.0, watchOS 7.0, *)
func _batched(_ shape: BNNS.Shape, _ batchSize: Int) -> BNNS.Shape {
    .vector(shape.batchStride * Swift.max(batchSize, 1))
}

/// The descriptor of the shape over a batched vector's data.
@available(macOS 11.0, iOS 14.0, tvOS 14.0, watchOS 7.0, *)
func _unbatched(_ descriptor: BNNSNDArrayDescriptor, _ shape: BNNS.Shape) -> BNNSNDArrayDescriptor {
    var result = BNNSNDArrayDescriptor(dataType: descriptor.data_type, shape: shape)
    result.data = descriptor.data
    return result
}

// MARK: - Nearest neighbors

@available(macOS 14.0, iOS 17, tvOS 17, watchOS 10, *)
extension Accelerate::BNNS {
    public struct NearestNeighbors {
        /// Owns the C object.
        final class Storage {
            let knn: BNNSNearestNeighbors?
            let dimensionCount: Int
            init(_ knn: BNNSNearestNeighbors?, _ dimensionCount: Int) {
                self.knn = knn
                self.dimensionCount = dimensionCount
            }
            deinit {
                if let knn { BNNSDestroyNearestNeighbors(knn) }
            }
        }

        let storage: Storage

        public init(capacity: Swift::Int, dimensionCount: Swift::Int, neighborCount: Swift::Int, dataType: Accelerate::BNNSDataType) {
            let knn = BNNSCreateNearestNeighbors(UInt32(capacity), UInt32(dimensionCount), UInt32(neighborCount), dataType, nil)
            storage = Storage(knn, dimensionCount)
        }

        /// Adds the samples, dimensionCount values each.
        public func append(samples: Accelerate::BNNSNDArrayDescriptor) {
            guard let data = samples.data, storage.dimensionCount > 0 else { return }
            let count = samples.shape.elementCount / storage.dimensionCount
            _ = BNNSNearestNeighborsLoad(storage.knn, UInt32(count), data)
        }

        /// The neighbors of one sample, or of all of them when index is nil.
        public func apply(index: Swift::Int?, outputIndices: Accelerate::BNNSNDArrayDescriptor, outputDistances: Accelerate::BNNSNDArrayDescriptor) {
            _ = BNNSNearestNeighborsGetInfo(storage.knn, Int32(index ?? -1),
                                            outputIndices.data?.assumingMemoryBound(to: Int32.self), outputDistances.data)
        }
    }
}
