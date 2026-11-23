import Swift
import Darwin

// BNNS's layer classes: each owns a BNNSFilter it made with
// BNNSFilterCreateLayer..., applies it with BNNS's apply functions and
// destroys it when it goes.

/// The pointer a descriptor's data must have to be applied.
@available(macOS 11.0, iOS 14.0, tvOS 14.0, watchOS 7.0, *)
func _data(_ descriptor: BNNSNDArrayDescriptor) throws -> UnsafeMutableRawPointer {
    guard let data = descriptor.data else { throw BNNS.Error.arrayDescriptorInvalidData }
    return data
}

@available(macOS 11.0, iOS 14.0, tvOS 14.0, watchOS 7.0, *)
@available(*, deprecated, message: "Use the BNNSGraph API instead.")
extension Accelerate::BNNS {
    @_hasMissingDesignatedInitializers public class Layer {
        /// A layer over a filter, which it then owns.
        init(filter: BNNSFilter) {
            bnnsFilter = filter
        }

        deinit {
            BNNSFilterDestroy(bnnsFilter)
        }

        final public let bnnsFilter: Accelerate::BNNSFilter
    }

    @_inheritsConvenienceInitializers @_hasMissingDesignatedInitializers public class UnaryLayer: Accelerate::BNNS.Accelerate::Layer {
        public func apply(batchSize: Swift::Int, input: Accelerate::BNNSNDArrayDescriptor, output: Accelerate::BNNSNDArrayDescriptor) throws {
            try _check(BNNSFilterApplyBatch(bnnsFilter, batchSize, try _data(input), input.batchStride, try _data(output), output.batchStride))
        }

        public func applyBackward(batchSize: Swift::Int, input: Accelerate::BNNSNDArrayDescriptor, output: Accelerate::BNNSNDArrayDescriptor, outputGradient: Accelerate::BNNSNDArrayDescriptor, generatingInputGradient inputGradient: Accelerate::BNNSNDArrayDescriptor) throws {
            try _applyBackward(self, batchSize: batchSize, input: input, output: output, outputGradient: outputGradient,
                               inputGradient: inputGradient, weightsGradient: nil, biasGradient: nil)
        }

        deinit {}
    }

    @_inheritsConvenienceInitializers @_hasMissingDesignatedInitializers public class BinaryLayer: Accelerate::BNNS.Accelerate::Layer {
        public func apply(batchSize: Swift::Int, inputA: Accelerate::BNNSNDArrayDescriptor, inputB: Accelerate::BNNSNDArrayDescriptor, output: Accelerate::BNNSNDArrayDescriptor) throws {
            try _applyTwoInputs(self, batchSize: batchSize, inputA: inputA, inputB: inputB, output: output)
        }

        public func applyBackward(batchSize: Swift::Int, inputA: Accelerate::BNNSNDArrayDescriptor, inputB: Accelerate::BNNSNDArrayDescriptor, output: Accelerate::BNNSNDArrayDescriptor, outputGradient: Accelerate::BNNSNDArrayDescriptor, generatingInputAGradient inputAGradient: Accelerate::BNNSNDArrayDescriptor, generatingInputBGradient inputBGradient: Accelerate::BNNSNDArrayDescriptor) throws {
            try _applyTwoInputsBackward(self, batchSize: batchSize, inputA: inputA, inputB: inputB, output: output, outputGradient: outputGradient,
                                        inputAGradient: inputAGradient, inputBGradient: inputBGradient)
        }

        deinit {}
    }
}

@available(macOS 11.0, iOS 14.0, tvOS 14.0, watchOS 7.0, *)
func _applyBackward(_ layer: BNNS.Layer, batchSize: Int, input: BNNSNDArrayDescriptor, output: BNNSNDArrayDescriptor, outputGradient: BNNSNDArrayDescriptor,
                    inputGradient: BNNSNDArrayDescriptor, weightsGradient: BNNSNDArrayDescriptor?, biasGradient: BNNSNDArrayDescriptor?) throws {
    var inputGradient = inputGradient
    var outputGradient = outputGradient
    try _withDescriptorPointers([weightsGradient, biasGradient]) { deltas in
        try _check(BNNSFilterApplyBackwardBatch(layer.bnnsFilter, batchSize, input.data, input.batchStride, &inputGradient, inputGradient.batchStride,
                                                output.data, output.batchStride, &outputGradient, outputGradient.batchStride, deltas[0], deltas[1]))
    }
}

@available(macOS 11.0, iOS 14.0, tvOS 14.0, watchOS 7.0, *)
func _applyTwoInputs(_ layer: BNNS.Layer, batchSize: Int, inputA: BNNSNDArrayDescriptor, inputB: BNNSNDArrayDescriptor, output: BNNSNDArrayDescriptor) throws {
    try _check(BNNSFilterApplyTwoInputBatch(layer.bnnsFilter, batchSize, try _data(inputA), inputA.batchStride, try _data(inputB), inputB.batchStride,
                                            try _data(output), output.batchStride))
}

@available(macOS 11.0, iOS 14.0, tvOS 14.0, watchOS 7.0, *)
func _applyTwoInputsBackward(_ layer: BNNS.Layer, batchSize: Int, inputA: BNNSNDArrayDescriptor, inputB: BNNSNDArrayDescriptor, output: BNNSNDArrayDescriptor,
                             outputGradient: BNNSNDArrayDescriptor, inputAGradient: BNNSNDArrayDescriptor, inputBGradient: BNNSNDArrayDescriptor) throws {
    var aGradient = inputAGradient, bGradient = inputBGradient, outGradient = outputGradient
    try _check(BNNSFilterApplyBackwardTwoInputBatch(layer.bnnsFilter, batchSize, inputA.data, inputA.batchStride, &aGradient, aGradient.batchStride,
                                                    inputB.data, inputB.batchStride, &bGradient, bGradient.batchStride,
                                                    output.data, output.batchStride, &outGradient, outGradient.batchStride, nil, nil))
}

/// Makes a filter with a C layer parameters struct, nil if BNNS can't.
func _makeFilter<P>(_ parameters: P, _ filterParameters: BNNSFilterParameters?,
                    _ create: (UnsafePointer<P>, UnsafePointer<BNNSFilterParameters>?) -> BNNSFilter?) -> BNNSFilter? {
    var parameters = parameters
    return _withFilterParameters(filterParameters) { fp in
        withUnsafePointer(to: &parameters) { create($0, fp) }
    }
}

// MARK: - Activation

@available(macOS 11.0, iOS 14.0, tvOS 14.0, watchOS 7.0, *)
@available(*, deprecated, message: "Use the BNNSGraph API instead.")
extension Accelerate::BNNS {
    @_inheritsConvenienceInitializers @_hasMissingDesignatedInitializers public class ActivationLayer: Accelerate::BNNS.Accelerate::UnaryLayer {
        convenience public init?(function activationFunction: Accelerate::BNNS.Accelerate::ActivationFunction, input: Accelerate::BNNSNDArrayDescriptor, output: Accelerate::BNNSNDArrayDescriptor, filterParameters: Accelerate::BNNSFilterParameters? = nil) {
            let parameters = BNNSLayerParametersActivation(i_desc: input, o_desc: output, activation: activationFunction.bnnsActivation, axis_flags: 0)
            guard let filter = _makeFilter(parameters, filterParameters, BNNSFilterCreateLayerActivation) else { return nil }
            self.init(filter: filter)
        }
        deinit {}
    }

    public static func applyActivation(activation: Accelerate::BNNS.Accelerate::ActivationFunction, input: Accelerate::BNNSNDArrayDescriptor, output: Accelerate::BNNSNDArrayDescriptor, batchSize: Swift::Int, filterParameters: Accelerate::BNNSFilterParameters? = nil) throws {
        try _applyActivation(activation, axisFlags: 0, input: input, output: output, batchSize: batchSize, filterParameters: filterParameters)
    }
}

@available(macOS 11.0, iOS 14.0, tvOS 14.0, watchOS 7.0, *)
func _applyActivation(_ activation: BNNS.ActivationFunction, axisFlags: UInt32, input: BNNSNDArrayDescriptor, output: BNNSNDArrayDescriptor,
                      batchSize: Int, filterParameters: BNNSFilterParameters?) throws {
    var parameters = BNNSLayerParametersActivation(i_desc: input, o_desc: output, activation: activation.bnnsActivation, axis_flags: axisFlags)
    try _withFilterParameters(filterParameters) { fp in
        try _check(BNNSDirectApplyActivationBatch(&parameters, fp, batchSize, input.batchStride, output.batchStride))
    }
}

@available(macOS 12.0, iOS 15.0, tvOS 15.0, watchOS 8.0, *)
@available(*, deprecated, message: "Use the BNNSGraph API instead.")
extension Accelerate::BNNS.Accelerate::ActivationLayer {
    convenience public init?(function activationFunction: Accelerate::BNNS.Accelerate::ActivationFunction, axes: [Swift::Int], input: Accelerate::BNNSNDArrayDescriptor, output: Accelerate::BNNSNDArrayDescriptor, filterParameters: Accelerate::BNNSFilterParameters? = nil) {
        let parameters = BNNSLayerParametersActivation(i_desc: input, o_desc: output, activation: activationFunction.bnnsActivation, axis_flags: _axisFlags(axes))
        guard let filter = _makeFilter(parameters, filterParameters, BNNSFilterCreateLayerActivation) else { return nil }
        self.init(filter: filter)
    }
}

@available(macOS 12.0, iOS 15.0, tvOS 15.0, watchOS 8.0, *)
@available(*, deprecated, message: "Use the BNNSGraph API instead.")
extension Accelerate::BNNS {
    public static func applyActivation(activation: Accelerate::BNNS.Accelerate::ActivationFunction, axes: [Swift::Int], input: Accelerate::BNNSNDArrayDescriptor, output: Accelerate::BNNSNDArrayDescriptor, batchSize: Swift::Int, filterParameters: Accelerate::BNNSFilterParameters? = nil) throws {
        try _applyActivation(activation, axisFlags: _axisFlags(axes), input: input, output: output, batchSize: batchSize, filterParameters: filterParameters)
    }
}

// MARK: - Convolution, fully connected, pooling

@available(macOS 11.0, iOS 14.0, tvOS 14.0, watchOS 7.0, *)
@available(*, deprecated, message: "Use the BNNSGraph API instead.")
extension Accelerate::BNNS {
    @_inheritsConvenienceInitializers @_hasMissingDesignatedInitializers public class ConvolutionLayer: Accelerate::BNNS.Accelerate::UnaryLayer {
        convenience public init?(type convolutionType: Accelerate::BNNS.Accelerate::ConvolutionType, input: Accelerate::BNNSNDArrayDescriptor, weights: Accelerate::BNNSNDArrayDescriptor, output: Accelerate::BNNSNDArrayDescriptor, bias: Accelerate::BNNSNDArrayDescriptor?, padding: Accelerate::BNNS.Accelerate::ConvolutionPadding, activation: Accelerate::BNNS.Accelerate::ActivationFunction, groupCount: Swift::Int, stride: (x: Swift::Int, y: Swift::Int), dilationStride: (x: Swift::Int, y: Swift::Int), filterParameters: Accelerate::BNNSFilterParameters? = nil) {
            let parameters = _convolutionParameters(input: input, weights: weights, output: output, bias: bias, padding: padding, activation: activation,
                                                    groupCount: groupCount, stride: stride, dilationStride: dilationStride)
            let create = convolutionType == .standard ? BNNSFilterCreateLayerConvolution : BNNSFilterCreateLayerTransposedConvolution
            guard let filter = _makeFilter(parameters, filterParameters, create) else { return nil }
            self.init(filter: filter)
        }

        public func applyBackward(batchSize: Swift::Int, input: Accelerate::BNNSNDArrayDescriptor, output: Accelerate::BNNSNDArrayDescriptor, outputGradient: Accelerate::BNNSNDArrayDescriptor, generatingInputGradient inputGradient: Accelerate::BNNSNDArrayDescriptor, generatingWeightsGradient weightsGradient: Accelerate::BNNSNDArrayDescriptor? = nil, generatingBiasGradient biasGradient: Accelerate::BNNSNDArrayDescriptor? = nil) throws {
            try _applyBackward(self, batchSize: batchSize, input: input, output: output, outputGradient: outputGradient,
                               inputGradient: inputGradient, weightsGradient: weightsGradient, biasGradient: biasGradient)
        }

        deinit {}
    }

    @_inheritsConvenienceInitializers @_hasMissingDesignatedInitializers public class FullyConnectedLayer: Accelerate::BNNS.Accelerate::ConvolutionLayer {
        convenience public init?(input: Accelerate::BNNSNDArrayDescriptor, output: Accelerate::BNNSNDArrayDescriptor, weights: Accelerate::BNNSNDArrayDescriptor, bias: Accelerate::BNNSNDArrayDescriptor?, activation: Accelerate::BNNS.Accelerate::ActivationFunction, filterParameters: Accelerate::BNNSFilterParameters? = nil) {
            let parameters = BNNSLayerParametersFullyConnected(i_desc: input, w_desc: weights, o_desc: output, bias: bias ?? _emptyDescriptor(),
                                                               activation: activation.bnnsActivation)
            guard let filter = _makeFilter(parameters, filterParameters, BNNSFilterCreateLayerFullyConnected) else { return nil }
            self.init(filter: filter)
        }
        deinit {}
    }

    @_inheritsConvenienceInitializers @_hasMissingDesignatedInitializers public class PoolingLayer: Accelerate::BNNS.Accelerate::Layer {
        /// The pooling's type, which carries the indices max pooling
        /// records and unpooling reads.
        var poolingType: PoolingType = .l2Norm

        convenience public init?(type poolingType: Accelerate::BNNS.Accelerate::PoolingType, input: Accelerate::BNNSNDArrayDescriptor, output: Accelerate::BNNSNDArrayDescriptor, bias: Accelerate::BNNSNDArrayDescriptor?, activation: Accelerate::BNNS.Accelerate::ActivationFunction, kernelSize: (width: Swift::Int, height: Swift::Int), stride: (x: Swift::Int, y: Swift::Int), padding: Accelerate::BNNS.Accelerate::ConvolutionPadding, filterParameters: Accelerate::BNNSFilterParameters? = nil) {
            let (x, y, pad) = padding.parts
            let dilation = poolingType.dilation
            let parameters = BNNSLayerParametersPooling(i_desc: input, o_desc: output, bias: bias ?? _emptyDescriptor(), activation: activation.bnnsActivation,
                                                        pooling_function: poolingType.bnnsPoolingFunction, k_width: kernelSize.width, k_height: kernelSize.height,
                                                        x_stride: stride.x, y_stride: stride.y, x_dilation_stride: dilation.x, y_dilation_stride: dilation.y,
                                                        x_padding: x, y_padding: y, pad: pad)
            guard let filter = _makeFilter(parameters, filterParameters, BNNSFilterCreateLayerPooling) else { return nil }
            self.init(filter: filter)
            self.poolingType = poolingType
        }

        public func apply(batchSize: Swift::Int, input: Accelerate::BNNSNDArrayDescriptor, output: Accelerate::BNNSNDArrayDescriptor) throws {
            let inData = try _data(input), outData = try _data(output)
            switch poolingType {
            case let .max(indices, _, _), let .unMax(indices, _, _):
                try _check(BNNSPoolingFilterApplyBatch(bnnsFilter, batchSize, inData, input.batchStride, outData, output.batchStride,
                                                       indices?.baseAddress, indices == nil ? 0 : output.batchStride))
            case let .maxEx(indices, _, _):
                try _check(BNNSPoolingFilterApplyBatchEx(bnnsFilter, batchSize, inData, input.batchStride, outData, output.batchStride,
                                                         indices?.data_type ?? _BNNSConstant.int64, indices?.data, indices?.batchStride ?? 0))
            case let .unMaxEx(indices, _, _):
                try _check(BNNSPoolingFilterApplyBatchEx(bnnsFilter, batchSize, inData, input.batchStride, outData, output.batchStride,
                                                         indices.data_type, indices.data, indices.batchStride))
            default:
                try _check(BNNSFilterApplyBatch(bnnsFilter, batchSize, inData, input.batchStride, outData, output.batchStride))
            }
        }

        public func applyBackward(batchSize: Swift::Int, input: Accelerate::BNNSNDArrayDescriptor, output: Accelerate::BNNSNDArrayDescriptor, outputGradient: Accelerate::BNNSNDArrayDescriptor, generatingInputGradient inputGradient: Accelerate::BNNSNDArrayDescriptor, generatingBiasGradient biasGradient: Accelerate::BNNSNDArrayDescriptor? = nil) throws {
            var inGradient = inputGradient, outGradient = outputGradient
            try _withDescriptorPointers([biasGradient]) { bias in
                switch poolingType {
                case let .maxEx(indices, _, _):
                    try _check(BNNSPoolingFilterApplyBackwardBatchEx(bnnsFilter, batchSize, input.data, input.batchStride, &inGradient, inGradient.batchStride,
                                                                     output.data, output.batchStride, &outGradient, outGradient.batchStride, bias[0],
                                                                     indices?.data_type ?? _BNNSConstant.int64, indices?.data, indices?.batchStride ?? 0))
                case let .unMaxEx(indices, _, _):
                    try _check(BNNSPoolingFilterApplyBackwardBatchEx(bnnsFilter, batchSize, input.data, input.batchStride, &inGradient, inGradient.batchStride,
                                                                     output.data, output.batchStride, &outGradient, outGradient.batchStride, bias[0],
                                                                     indices.data_type, indices.data, indices.batchStride))
                case let .max(indices, _, _), let .unMax(indices, _, _):
                    try _check(BNNSPoolingFilterApplyBackwardBatch(bnnsFilter, batchSize, input.data, input.batchStride, &inGradient, inGradient.batchStride,
                                                                   output.data, output.batchStride, &outGradient, outGradient.batchStride, bias[0],
                                                                   indices.map { UnsafePointer($0.baseAddress!) }, indices == nil ? 0 : output.batchStride))
                default:
                    try _check(BNNSPoolingFilterApplyBackwardBatch(bnnsFilter, batchSize, input.data, input.batchStride, &inGradient, inGradient.batchStride,
                                                                   output.data, output.batchStride, &outGradient, outGradient.batchStride, bias[0], nil, 0))
                }
            }
        }

        deinit {}
    }
}

@available(macOS 11.0, iOS 14.0, tvOS 14.0, watchOS 7.0, *)
func _convolutionParameters(input: BNNSNDArrayDescriptor, weights: BNNSNDArrayDescriptor, output: BNNSNDArrayDescriptor, bias: BNNSNDArrayDescriptor?,
                            padding: BNNS.ConvolutionPadding, activation: BNNS.ActivationFunction, groupCount: Int,
                            stride: (x: Int, y: Int), dilationStride: (x: Int, y: Int)) -> BNNSLayerParametersConvolution {
    let (x, y, pad) = padding.parts
    return BNNSLayerParametersConvolution(i_desc: input, w_desc: weights, o_desc: output, bias: bias ?? _emptyDescriptor(),
                                          activation: activation.bnnsActivation, x_stride: stride.x, y_stride: stride.y,
                                          x_dilation_stride: dilationStride.x, y_dilation_stride: dilationStride.y,
                                          x_padding: x, y_padding: y, groups: groupCount, pad: pad)
}

// MARK: - Normalization and fused layers

@available(macOS 11.0, iOS 14.0, tvOS 14.0, watchOS 7.0, *)
@available(*, deprecated, message: "Use the BNNSGraph API instead.")
extension Accelerate::BNNS {
    @_inheritsConvenienceInitializers @_hasMissingDesignatedInitializers public class NormalizationLayer: Accelerate::BNNS.Accelerate::Layer {
        convenience public init?(type normalization: Accelerate::BNNS.Accelerate::NormalizationType, input: Accelerate::BNNSNDArrayDescriptor, output: Accelerate::BNNSNDArrayDescriptor, beta: Accelerate::BNNSNDArrayDescriptor, gamma: Accelerate::BNNSNDArrayDescriptor, momentum: Swift::Float = 0, epsilon: Swift::Float, activation: Accelerate::BNNS.Accelerate::ActivationFunction, filterParameters: Accelerate::BNNSFilterParameters? = nil) {
            var parameters = normalization.parameters(input: input, output: output, beta: beta, gamma: gamma, momentum: momentum, epsilon: epsilon, activation: activation)
            let filter = _withFilterParameters(filterParameters) { fp in
                BNNSFilterCreateLayerNormalization(normalization.filterType, &parameters, fp)
            }
            guard let filter else { return nil }
            self.init(filter: filter)
        }

        public func apply(batchSize: Swift::Int, input: Accelerate::BNNSNDArrayDescriptor, output: Accelerate::BNNSNDArrayDescriptor, for learningPhase: Accelerate::BNNS.Accelerate::LearningPhase) throws {
            try _check(BNNSNormalizationFilterApplyBatch(bnnsFilter, batchSize, try _data(input), input.batchStride, try _data(output), output.batchStride,
                                                         learningPhase == .training))
        }

        public func applyBackward(batchSize: Swift::Int, input: Accelerate::BNNSNDArrayDescriptor, output: Accelerate::BNNSNDArrayDescriptor, outputGradient: Accelerate::BNNSNDArrayDescriptor, generatingInputGradient inputGradient: Accelerate::BNNSNDArrayDescriptor, generatingBetaGradient betaGradient: Accelerate::BNNSNDArrayDescriptor? = nil, generatingGammaGradient gammaGradient: Accelerate::BNNSNDArrayDescriptor? = nil) throws {
            var inGradient = inputGradient, outGradient = outputGradient
            try _withDescriptorPointers([betaGradient, gammaGradient]) { deltas in
                try _check(BNNSNormalizationFilterApplyBackwardBatch(bnnsFilter, batchSize, &inGradient, inGradient.batchStride, output.data, output.batchStride,
                                                                     &outGradient, outGradient.batchStride, deltas[0], deltas[1]))
            }
        }

        deinit {}
    }

    @_inheritsConvenienceInitializers @_hasMissingDesignatedInitializers public class FusedLayer: Accelerate::BNNS.Accelerate::Layer {
        public func apply(batchSize: Swift::Int, input: Accelerate::BNNSNDArrayDescriptor, output: Accelerate::BNNSNDArrayDescriptor, for learningPhase: Accelerate::BNNS.Accelerate::LearningPhase) throws {
            try _check(BNNSFusedFilterApplyBatch(bnnsFilter, batchSize, try _data(input), input.batchStride, try _data(output), output.batchStride,
                                                 learningPhase == .training))
        }

        public func applyBackward(batchSize: Swift::Int, input: Accelerate::BNNSNDArrayDescriptor, output: Accelerate::BNNSNDArrayDescriptor, outputGradient: Accelerate::BNNSNDArrayDescriptor, generatingInputGradient inputGradient: Accelerate::BNNSNDArrayDescriptor, generatingParameterGradients parameterGradients: [Accelerate::BNNSNDArrayDescriptor]) throws {
            var inGradient = inputGradient, outGradient = outputGradient
            try _withDescriptorPointers(parameterGradients.map { Optional($0) }) { deltas in
                var deltas = deltas
                try deltas.withUnsafeMutableBufferPointer { deltas in
                    try _check(BNNSFusedFilterApplyBackwardBatch(bnnsFilter, batchSize, input.data, input.batchStride, &inGradient, inGradient.batchStride,
                                                                 output.data, output.batchStride, &outGradient, outGradient.batchStride,
                                                                 deltas.isEmpty ? nil : deltas.baseAddress))
                }
            }
        }

        deinit {}
    }

    @_inheritsConvenienceInitializers @_hasMissingDesignatedInitializers public class FusedConvolutionNormalizationLayer: Accelerate::BNNS.Accelerate::FusedLayer {
        convenience public init?(input: Accelerate::BNNSNDArrayDescriptor, output: Accelerate::BNNSNDArrayDescriptor, convolutionWeights: Accelerate::BNNSNDArrayDescriptor, convolutionBias: Accelerate::BNNSNDArrayDescriptor?, convolutionStride: (x: Swift::Int, y: Swift::Int), convolutionDilationStride: (x: Swift::Int, y: Swift::Int), convolutionPadding: Accelerate::BNNS.Accelerate::ConvolutionPadding, normalization: Accelerate::BNNS.Accelerate::NormalizationType, normalizationBeta: Accelerate::BNNSNDArrayDescriptor, normalizationGamma: Accelerate::BNNSNDArrayDescriptor, normalizationMomentum: Swift::Float, normalizationEpsilon: Swift::Float, normalizationActivation: Accelerate::BNNS.Accelerate::ActivationFunction, filterParameters: Accelerate::BNNSFilterParameters? = nil) {
            let convolution = _convolutionParameters(input: input, weights: convolutionWeights, output: output, bias: convolutionBias, padding: convolutionPadding,
                                                     activation: .identity, groupCount: 1, stride: convolutionStride, dilationStride: convolutionDilationStride)
            let norm = normalization.parameters(input: output, output: output, beta: normalizationBeta, gamma: normalizationGamma,
                                                momentum: normalizationMomentum, epsilon: normalizationEpsilon, activation: normalizationActivation)
            guard let filter = _makeFusedFilter([(BNNSFilterType(rawValue: 0), _FusedParameters(convolution)), (normalization.filterType, _FusedParameters(norm))],
                                                filterParameters) else { return nil }
            self.init(filter: filter)
        }
        deinit {}
    }

    @_inheritsConvenienceInitializers @_hasMissingDesignatedInitializers public class FusedFullyConnectedNormalizationLayer: Accelerate::BNNS.Accelerate::FusedLayer {
        convenience public init?(input: Accelerate::BNNSNDArrayDescriptor, output: Accelerate::BNNSNDArrayDescriptor, fullyConnectedWeights: Accelerate::BNNSNDArrayDescriptor, fullyConnectedBias: Accelerate::BNNSNDArrayDescriptor?, normalization: Accelerate::BNNS.Accelerate::NormalizationType, normalizationBeta: Accelerate::BNNSNDArrayDescriptor, normalizationGamma: Accelerate::BNNSNDArrayDescriptor, normalizationMomentum: Swift::Float, normalizationEpsilon: Swift::Float, normalizationActivation: Accelerate::BNNS.Accelerate::ActivationFunction, filterParameters: Accelerate::BNNSFilterParameters? = nil) {
            let fullyConnected = BNNSLayerParametersFullyConnected(i_desc: input, w_desc: fullyConnectedWeights, o_desc: output,
                                                                   bias: fullyConnectedBias ?? _emptyDescriptor(), activation: BNNS.ActivationFunction.identity.bnnsActivation)
            let norm = normalization.parameters(input: output, output: output, beta: normalizationBeta, gamma: normalizationGamma,
                                                momentum: normalizationMomentum, epsilon: normalizationEpsilon, activation: normalizationActivation)
            guard let filter = _makeFusedFilter([(BNNSFilterType(rawValue: 1), _FusedParameters(fullyConnected)), (normalization.filterType, _FusedParameters(norm))],
                                                filterParameters) else { return nil }
            self.init(filter: filter)
        }
        deinit {}
    }
}

/// A C layer parameters struct kept in memory of its own, for a fused filter.
final class _FusedParameters {
    let pointer: UnsafeMutableRawPointer
    let release: () -> Void
    /// Memory more parameters point into (arithmetic fields).
    var extra: [_FusedParameters] = []

    init<P>(_ parameters: P) {
        let typed = UnsafeMutablePointer<P>.allocate(capacity: 1)
        typed.initialize(to: parameters)
        pointer = UnsafeMutableRawPointer(typed)
        release = {
            typed.deinitialize(count: 1)
            typed.deallocate()
        }
    }

    deinit { release() }
}

func _makeFusedFilter(_ layers: [(BNNSFilterType, _FusedParameters)], _ filterParameters: BNNSFilterParameters?) -> BNNSFilter? {
    var types = layers.map { $0.0 }
    var pointers = layers.map { UnsafeRawPointer($0.1.pointer) }
    return withExtendedLifetime(layers) {
        _withFilterParameters(filterParameters) { fp in
            BNNSFilterCreateFusedLayer(layers.count, &types, &pointers, fp)
        }
    }
}

@available(macOS 12.0, iOS 15.0, tvOS 15.0, watchOS 8.0, *)
@available(*, deprecated, message: "Use the BNNSGraph API instead.")
public protocol FusableLayerParameters {
}

/// What a fusable layer's parameters make: a filter type and its C
/// parameters, given the layer's input(s) and output.
@available(macOS 12.0, iOS 15.0, tvOS 15.0, watchOS 8.0, *)
protocol _FusableLayerParameters {
    func _fused(inputs: [BNNSNDArrayDescriptor], output: BNNSNDArrayDescriptor) -> (BNNSFilterType, _FusedParameters)?
}

@available(macOS 12.0, iOS 15.0, tvOS 15.0, watchOS 8.0, *)
@available(*, deprecated, message: "Use the BNNSGraph API instead.")
extension Accelerate::BNNS {
    public struct FusedConvolutionParameters: Accelerate::FusableLayerParameters, _FusableLayerParameters {
        public init(type: Accelerate::BNNS.Accelerate::ConvolutionType, weights: Accelerate::BNNSNDArrayDescriptor, bias: Accelerate::BNNSNDArrayDescriptor?, stride: (x: Swift::Int, y: Swift::Int), dilationStride: (x: Swift::Int, y: Swift::Int), groupSize: Swift::Int, padding: Accelerate::BNNS.Accelerate::ConvolutionPadding) {
            self.type = type
            self.weights = weights
            self.bias = bias
            self.stride = stride
            self.dilationStride = dilationStride
            self.groupSize = groupSize
            self.padding = padding
        }
        public var type: Accelerate::BNNS.Accelerate::ConvolutionType
        public var weights: Accelerate::BNNSNDArrayDescriptor
        public var bias: Accelerate::BNNSNDArrayDescriptor?
        public var stride: (x: Swift::Int, y: Swift::Int)
        public var dilationStride: (x: Swift::Int, y: Swift::Int)
        public var groupSize: Swift::Int
        public var padding: Accelerate::BNNS.Accelerate::ConvolutionPadding

        func _fused(inputs: [BNNSNDArrayDescriptor], output: BNNSNDArrayDescriptor) -> (BNNSFilterType, _FusedParameters)? {
            let parameters = _convolutionParameters(input: inputs[0], weights: weights, output: output, bias: bias, padding: padding, activation: .identity,
                                                    groupCount: groupSize, stride: stride, dilationStride: dilationStride)
            return (BNNSFilterType(rawValue: type == .standard ? 0 : 6), _FusedParameters(parameters))
        }
    }

    public struct FusedFullyConnectedParameters: Accelerate::FusableLayerParameters, _FusableLayerParameters {
        public init(weights: Accelerate::BNNSNDArrayDescriptor, bias: Accelerate::BNNSNDArrayDescriptor?) {
            self.weights = weights
            self.bias = bias
        }
        public var weights: Accelerate::BNNSNDArrayDescriptor
        public var bias: Accelerate::BNNSNDArrayDescriptor?

        func _fused(inputs: [BNNSNDArrayDescriptor], output: BNNSNDArrayDescriptor) -> (BNNSFilterType, _FusedParameters)? {
            let parameters = BNNSLayerParametersFullyConnected(i_desc: inputs[0], w_desc: weights, o_desc: output, bias: bias ?? _emptyDescriptor(),
                                                               activation: BNNS.ActivationFunction.identity.bnnsActivation)
            return (BNNSFilterType(rawValue: 1), _FusedParameters(parameters))
        }
    }

    public struct FusedNormalizationParameters: Accelerate::FusableLayerParameters, _FusableLayerParameters {
        public init(type: Accelerate::BNNS.Accelerate::NormalizationType, beta: Accelerate::BNNSNDArrayDescriptor? = nil, gamma: Accelerate::BNNSNDArrayDescriptor? = nil, momentum: Swift::Float = 0, epsilon: Swift::Float, activation: Accelerate::BNNS.Accelerate::ActivationFunction) {
            self.type = type
            self.beta = beta
            self.gamma = gamma
            self.momentum = momentum
            self.epsilon = epsilon
            self.activation = activation
        }
        public var type: Accelerate::BNNS.Accelerate::NormalizationType
        public var beta: Accelerate::BNNSNDArrayDescriptor?
        public var gamma: Accelerate::BNNSNDArrayDescriptor?
        public var momentum: Swift::Float
        public var epsilon: Swift::Float
        public var activation: Accelerate::BNNS.Accelerate::ActivationFunction

        func _fused(inputs: [BNNSNDArrayDescriptor], output: BNNSNDArrayDescriptor) -> (BNNSFilterType, _FusedParameters)? {
            let parameters = type.parameters(input: inputs[0], output: output, beta: beta, gamma: gamma, momentum: momentum, epsilon: epsilon, activation: activation)
            return (type.filterType, _FusedParameters(parameters))
        }
    }

    public struct FusedQuantizationParameters: Accelerate::FusableLayerParameters, _FusableLayerParameters {
        public init(scale: Accelerate::BNNSNDArrayDescriptor?, bias: Accelerate::BNNSNDArrayDescriptor?) {
            self.axis = nil
            self.scale = scale
            self.bias = bias
        }
        public var axis: Swift::Int?
        public var scale: Accelerate::BNNSNDArrayDescriptor?
        public var bias: Accelerate::BNNSNDArrayDescriptor?

        func _fused(inputs: [BNNSNDArrayDescriptor], output: BNNSNDArrayDescriptor) -> (BNNSFilterType, _FusedParameters)? {
            let parameters = BNNSLayerParametersQuantization(axis_mask: axis.map { 1 << $0 } ?? 0, function: BNNSQuantizerFunction(rawValue: 0),
                                                             i_desc: inputs[0], o_desc: output, scale: scale ?? _emptyDescriptor(), bias: bias ?? _emptyDescriptor())
            return (BNNSFilterType(rawValue: 7), _FusedParameters(parameters))
        }
    }

    public struct FusedDequantizationParameters: Accelerate::FusableLayerParameters, _FusableLayerParameters {
        public init(scale: Accelerate::BNNSNDArrayDescriptor?, bias: Accelerate::BNNSNDArrayDescriptor?) {
            self.axis = nil
            self.scale = scale
            self.bias = bias
        }
        public var axis: Swift::Int?
        public var scale: Accelerate::BNNSNDArrayDescriptor?
        public var bias: Accelerate::BNNSNDArrayDescriptor?

        func _fused(inputs: [BNNSNDArrayDescriptor], output: BNNSNDArrayDescriptor) -> (BNNSFilterType, _FusedParameters)? {
            let parameters = BNNSLayerParametersQuantization(axis_mask: axis.map { 1 << $0 } ?? 0, function: BNNSQuantizerFunction(rawValue: 1),
                                                             i_desc: inputs[0], o_desc: output, scale: scale ?? _emptyDescriptor(), bias: bias ?? _emptyDescriptor())
            return (BNNSFilterType(rawValue: 7), _FusedParameters(parameters))
        }
    }

    public struct FusedUnaryArithmeticParameters: Accelerate::FusableLayerParameters, _FusableLayerParameters {
        public var inputDescriptorType: Accelerate::BNNS.Accelerate::DescriptorType
        public var outputDescriptorType: Accelerate::BNNS.Accelerate::DescriptorType
        public var function: Accelerate::BNNS.Accelerate::ArithmeticUnaryFunction
        public init(inputDescriptorType: Accelerate::BNNS.Accelerate::DescriptorType, outputDescriptorType: Accelerate::BNNS.Accelerate::DescriptorType, function: Accelerate::BNNS.Accelerate::ArithmeticUnaryFunction) {
            self.inputDescriptorType = inputDescriptorType
            self.outputDescriptorType = outputDescriptorType
            self.function = function
        }

        func _fused(inputs: [BNNSNDArrayDescriptor], output: BNNSNDArrayDescriptor) -> (BNNSFilterType, _FusedParameters)? {
            let fields = _FusedParameters(BNNSArithmeticUnary(in: inputs[0], in_type: inputDescriptorType.bnnsDescriptorType,
                                                              out: output, out_type: outputDescriptorType.bnnsDescriptorType))
            let parameters = _FusedParameters(BNNSLayerParametersArithmetic(arithmetic_function: function.bnnsArithmeticFunction,
                                                                            arithmetic_function_fields: fields.pointer,
                                                                            activation: BNNS.ActivationFunction.identity.bnnsActivation))
            parameters.extra = [fields]
            return (BNNSFilterType(rawValue: 8), parameters)
        }
    }

    public struct FusedBinaryArithmeticParameters: Accelerate::FusableLayerParameters, _FusableLayerParameters {
        public var inputADescriptorType: Accelerate::BNNS.Accelerate::DescriptorType
        public var inputBDescriptorType: Accelerate::BNNS.Accelerate::DescriptorType
        public var outputDescriptorType: Accelerate::BNNS.Accelerate::DescriptorType
        public var function: Accelerate::BNNS.Accelerate::ArithmeticBinaryFunction
        public init(inputADescriptorType: Accelerate::BNNS.Accelerate::DescriptorType, inputBDescriptorType: Accelerate::BNNS.Accelerate::DescriptorType, outputDescriptorType: Accelerate::BNNS.Accelerate::DescriptorType, function: Accelerate::BNNS.Accelerate::ArithmeticBinaryFunction) {
            self.inputADescriptorType = inputADescriptorType
            self.inputBDescriptorType = inputBDescriptorType
            self.outputDescriptorType = outputDescriptorType
            self.function = function
        }

        func _fused(inputs: [BNNSNDArrayDescriptor], output: BNNSNDArrayDescriptor) -> (BNNSFilterType, _FusedParameters)? {
            guard inputs.count >= 2 else { return nil }
            let fields = _FusedParameters(BNNSArithmeticBinary(in1: inputs[0], in1_type: inputADescriptorType.bnnsDescriptorType,
                                                               in2: inputs[1], in2_type: inputBDescriptorType.bnnsDescriptorType,
                                                               out: output, out_type: outputDescriptorType.bnnsDescriptorType))
            let parameters = _FusedParameters(BNNSLayerParametersArithmetic(arithmetic_function: function.bnnsArithmeticFunction,
                                                                            arithmetic_function_fields: fields.pointer,
                                                                            activation: BNNS.ActivationFunction.identity.bnnsActivation))
            parameters.extra = [fields]
            return (BNNSFilterType(rawValue: 8), parameters)
        }
    }

    public struct FusedTernaryArithmeticParameters: Accelerate::FusableLayerParameters, _FusableLayerParameters {
        public var inputADescriptorType: Accelerate::BNNS.Accelerate::DescriptorType
        public var inputBDescriptorType: Accelerate::BNNS.Accelerate::DescriptorType
        public var inputCDescriptorType: Accelerate::BNNS.Accelerate::DescriptorType
        public var outputDescriptorType: Accelerate::BNNS.Accelerate::DescriptorType
        public var function: Accelerate::BNNS.Accelerate::ArithmeticTernaryFunction
        public init(inputADescriptorType: Accelerate::BNNS.Accelerate::DescriptorType, inputBDescriptorType: Accelerate::BNNS.Accelerate::DescriptorType, inputCDescriptorType: Accelerate::BNNS.Accelerate::DescriptorType, outputDescriptorType: Accelerate::BNNS.Accelerate::DescriptorType, function: Accelerate::BNNS.Accelerate::ArithmeticTernaryFunction) {
            self.inputADescriptorType = inputADescriptorType
            self.inputBDescriptorType = inputBDescriptorType
            self.inputCDescriptorType = inputCDescriptorType
            self.outputDescriptorType = outputDescriptorType
            self.function = function
        }

        func _fused(inputs: [BNNSNDArrayDescriptor], output: BNNSNDArrayDescriptor) -> (BNNSFilterType, _FusedParameters)? {
            guard inputs.count >= 3 else { return nil }
            let fields = _FusedParameters(BNNSArithmeticTernary(in1: inputs[0], in1_type: inputADescriptorType.bnnsDescriptorType,
                                                                in2: inputs[1], in2_type: inputBDescriptorType.bnnsDescriptorType,
                                                                in3: inputs[2], in3_type: inputCDescriptorType.bnnsDescriptorType,
                                                                out: output, out_type: outputDescriptorType.bnnsDescriptorType))
            let parameters = _FusedParameters(BNNSLayerParametersArithmetic(arithmetic_function: function.bnnsArithmeticFunction,
                                                                            arithmetic_function_fields: fields.pointer,
                                                                            activation: BNNS.ActivationFunction.identity.bnnsActivation))
            parameters.extra = [fields]
            return (BNNSFilterType(rawValue: 8), parameters)
        }
    }

    @_inheritsConvenienceInitializers @_hasMissingDesignatedInitializers public class FusedParametersLayer: Accelerate::BNNS.Accelerate::FusedLayer {
        /// A fused layer over a filter, which it then owns.
        override init(filter: BNNSFilter) {
            super.init(filter: filter)
        }

        /// The number of inputs the fused layer's first layer takes.
        var inputCount: Int { 1 }

        convenience public init?(input: Accelerate::BNNSNDArrayDescriptor, output: Accelerate::BNNSNDArrayDescriptor, fusedLayerParameters: [any Accelerate::FusableLayerParameters], filterParameters: Accelerate::BNNSFilterParameters? = nil) {
            guard let filter = _makeFusedParametersFilter(inputs: [input], output: output, fusedLayerParameters, filterParameters) else { return nil }
            self.init(filter: filter)
        }

        deinit {}
    }
}

/// The filter of fused layers: the first takes the inputs, each next one
/// the previous one's output, which has the shape of the final output.
@available(macOS 12.0, iOS 15.0, tvOS 15.0, watchOS 8.0, *)
func _makeFusedParametersFilter(inputs: [BNNSNDArrayDescriptor], output: BNNSNDArrayDescriptor, _ layers: [any FusableLayerParameters],
                                _ filterParameters: BNNSFilterParameters?) -> BNNSFilter? {
    var made = [(BNNSFilterType, _FusedParameters)]()
    var layerInputs = inputs
    for layer in layers {
        guard let fusable = layer as? any _FusableLayerParameters,
              let fused = fusable._fused(inputs: layerInputs, output: output) else { return nil }
        made.append(fused)
        layerInputs = [output]
    }
    guard !made.isEmpty else { return nil }
    return _makeFusedFilter(made, filterParameters)
}

@available(macOS 12.0, iOS 15.0, tvOS 15.0, watchOS 8.0, *)
@available(*, deprecated, message: "Use the BNNSGraph API instead.")
extension Accelerate::BNNS.Accelerate::FusedParametersLayer {
    convenience public init?(inputA: Accelerate::BNNSNDArrayDescriptor, inputB: Accelerate::BNNSNDArrayDescriptor, output: Accelerate::BNNSNDArrayDescriptor, fusedLayerParameters: [any Accelerate::FusableLayerParameters], filterParameters: Accelerate::BNNSFilterParameters? = nil) {
        guard let filter = _makeFusedParametersFilter(inputs: [inputA, inputB], output: output, fusedLayerParameters, filterParameters) else { return nil }
        self.init(filter: filter)
    }

    public func apply(batchSize: Swift::Int, inputA: Accelerate::BNNSNDArrayDescriptor, inputB: Accelerate::BNNSNDArrayDescriptor, output: Accelerate::BNNSNDArrayDescriptor, for learningPhase: Accelerate::BNNS.Accelerate::LearningPhase) throws {
        try _applyFusedMultiInput(self, batchSize: batchSize, inputs: [inputA, inputB], output: output, learningPhase: learningPhase)
    }

    public func applyBackward(batchSize: Swift::Int, inputA: Accelerate::BNNSNDArrayDescriptor, inputB: Accelerate::BNNSNDArrayDescriptor, output: Accelerate::BNNSNDArrayDescriptor, outputGradient: Accelerate::BNNSNDArrayDescriptor, generatingInputAGradient inputAGradient: Accelerate::BNNSNDArrayDescriptor, generatingInputBGradient inputBGradient: Accelerate::BNNSNDArrayDescriptor, generatingParameterGradients parameterGradients: [Accelerate::BNNSNDArrayDescriptor]) throws {
        try _applyFusedMultiInputBackward(self, batchSize: batchSize, inputs: [inputA, inputB], output: output, outputGradient: outputGradient,
                                          inputGradients: [inputAGradient, inputBGradient], parameterGradients: parameterGradients)
    }

    convenience public init?(inputA: Accelerate::BNNSNDArrayDescriptor, inputB: Accelerate::BNNSNDArrayDescriptor, inputC: Accelerate::BNNSNDArrayDescriptor, output: Accelerate::BNNSNDArrayDescriptor, fusedLayerParameters: [any Accelerate::FusableLayerParameters], filterParameters: Accelerate::BNNSFilterParameters? = nil) {
        guard let filter = _makeFusedParametersFilter(inputs: [inputA, inputB, inputC], output: output, fusedLayerParameters, filterParameters) else { return nil }
        self.init(filter: filter)
    }

    public func apply(batchSize: Swift::Int, inputA: Accelerate::BNNSNDArrayDescriptor, inputB: Accelerate::BNNSNDArrayDescriptor, inputC: Accelerate::BNNSNDArrayDescriptor, output: Accelerate::BNNSNDArrayDescriptor, for learningPhase: Accelerate::BNNS.Accelerate::LearningPhase) throws {
        try _applyFusedMultiInput(self, batchSize: batchSize, inputs: [inputA, inputB, inputC], output: output, learningPhase: learningPhase)
    }

    public func applyBackward(batchSize: Swift::Int, inputA: Accelerate::BNNSNDArrayDescriptor, inputB: Accelerate::BNNSNDArrayDescriptor, inputC: Accelerate::BNNSNDArrayDescriptor, output: Accelerate::BNNSNDArrayDescriptor, outputGradient: Accelerate::BNNSNDArrayDescriptor, generatingInputAGradient inputAGradient: Accelerate::BNNSNDArrayDescriptor, generatingInputBGradient inputBGradient: Accelerate::BNNSNDArrayDescriptor, generatingInputCGradient inputCGradient: Accelerate::BNNSNDArrayDescriptor, generatingParameterGradients parameterGradients: [Accelerate::BNNSNDArrayDescriptor]) throws {
        try _applyFusedMultiInputBackward(self, batchSize: batchSize, inputs: [inputA, inputB, inputC], output: output, outputGradient: outputGradient,
                                          inputGradients: [inputAGradient, inputBGradient, inputCGradient], parameterGradients: parameterGradients)
    }
}

@available(macOS 11.0, iOS 14.0, tvOS 14.0, watchOS 7.0, *)
func _applyFusedMultiInput(_ layer: BNNS.Layer, batchSize: Int, inputs: [BNNSNDArrayDescriptor], output: BNNSNDArrayDescriptor,
                           learningPhase: BNNS.LearningPhase) throws {
    var pointers = try inputs.map { UnsafeRawPointer(try _data($0)) }
    var strides = inputs.map { $0.batchStride }
    try _check(BNNSFusedFilterApplyMultiInputBatch(layer.bnnsFilter, batchSize, inputs.count, &pointers, &strides, try _data(output),
                                                   output.batchStride, learningPhase == .training))
}

@available(macOS 11.0, iOS 14.0, tvOS 14.0, watchOS 7.0, *)
func _applyFusedMultiInputBackward(_ layer: BNNS.Layer, batchSize: Int, inputs: [BNNSNDArrayDescriptor], output: BNNSNDArrayDescriptor,
                                   outputGradient: BNNSNDArrayDescriptor, inputGradients: [BNNSNDArrayDescriptor],
                                   parameterGradients: [BNNSNDArrayDescriptor]) throws {
    var pointers: [UnsafeRawPointer?] = inputs.map { $0.data.map { UnsafeRawPointer($0) } }
    var strides = inputs.map { $0.batchStride }
    var deltaStrides = inputGradients.map { $0.batchStride }
    var outGradient = outputGradient
    try _withDescriptorPointers(inputGradients.map { Optional($0) }) { inDeltas in
        var inDeltas = inDeltas.map { $0! }
        try _withDescriptorPointers(parameterGradients.map { Optional($0) }) { parameterDeltas in
            var parameterDeltas = parameterDeltas
            try parameterDeltas.withUnsafeMutableBufferPointer { parameterDeltas in
                try _check(BNNSFusedFilterApplyBackwardMultiInputBatch(layer.bnnsFilter, batchSize, inputs.count, &pointers, &strides, &inDeltas, &deltaStrides,
                                                                       output.data, output.batchStride, &outGradient, outGradient.batchStride,
                                                                       parameterDeltas.isEmpty ? nil : parameterDeltas.baseAddress))
            }
        }
    }
}

// MARK: - Arithmetic

@available(macOS 11.0, iOS 14.0, tvOS 14.0, watchOS 7.0, *)
func _makeArithmeticFilter<Fields>(_ function: BNNSArithmeticFunction, _ fields: Fields, _ activation: BNNS.ActivationFunction,
                                   _ filterParameters: BNNSFilterParameters?) -> BNNSFilter? {
    var fields = fields
    return withUnsafeMutablePointer(to: &fields) { fieldsPointer in
        let parameters = BNNSLayerParametersArithmetic(arithmetic_function: function, arithmetic_function_fields: UnsafeMutableRawPointer(fieldsPointer),
                                                       activation: activation.bnnsActivation)
        return _makeFilter(parameters, filterParameters, BNNSFilterCreateLayerArithmetic)
    }
}

@available(macOS 11.0, iOS 14.0, tvOS 14.0, watchOS 7.0, *)
func _applyArithmetic(_ layer: BNNS.Layer, batchSize: Int, inputs: [BNNSNDArrayDescriptor], output: BNNSNDArrayDescriptor) throws {
    var pointers = try inputs.map { UnsafeRawPointer(try _data($0)) }
    var strides = inputs.map { $0.batchStride }
    try _check(BNNSArithmeticFilterApplyBatch(layer.bnnsFilter, batchSize, inputs.count, &pointers, &strides, try _data(output), output.batchStride))
}

@available(macOS 11.0, iOS 14.0, tvOS 14.0, watchOS 7.0, *)
func _applyArithmeticBackward(_ layer: BNNS.Layer, batchSize: Int, inputs: [BNNSNDArrayDescriptor], output: BNNSNDArrayDescriptor,
                              outputGradient: BNNSNDArrayDescriptor, inputGradients: [BNNSNDArrayDescriptor]) throws {
    var pointers: [UnsafeRawPointer?] = inputs.map { $0.data.map { UnsafeRawPointer($0) } }
    var strides = inputs.map { $0.batchStride }
    var deltaStrides = inputGradients.map { $0.batchStride }
    var outGradient = outputGradient
    try _withDescriptorPointers(inputGradients.map { Optional($0) }) { deltas in
        var deltas = deltas.map { $0! }
        try _check(BNNSArithmeticFilterApplyBackwardBatch(layer.bnnsFilter, batchSize, inputs.count, &pointers, &strides, &deltas, &deltaStrides,
                                                          output.data, output.batchStride, &outGradient, outGradient.batchStride))
    }
}

@available(macOS 11.0, iOS 14.0, tvOS 14.0, watchOS 7.0, *)
@available(*, deprecated, message: "Use the BNNSGraph API instead.")
extension Accelerate::BNNS {
    @_inheritsConvenienceInitializers @_hasMissingDesignatedInitializers public class UnaryArithmeticLayer: Accelerate::BNNS.Accelerate::Layer {
        convenience public init?(input: Accelerate::BNNSNDArrayDescriptor, inputDescriptorType: Accelerate::BNNS.Accelerate::DescriptorType, output: Accelerate::BNNSNDArrayDescriptor, outputDescriptorType: Accelerate::BNNS.Accelerate::DescriptorType, function: Accelerate::BNNS.Accelerate::ArithmeticUnaryFunction, activation: Accelerate::BNNS.Accelerate::ActivationFunction = .identity, filterParameters: Accelerate::BNNSFilterParameters? = nil) {
            let fields = BNNSArithmeticUnary(in: input, in_type: inputDescriptorType.bnnsDescriptorType, out: output, out_type: outputDescriptorType.bnnsDescriptorType)
            guard let filter = _makeArithmeticFilter(function.bnnsArithmeticFunction, fields, activation, filterParameters) else { return nil }
            self.init(filter: filter)
        }

        public func apply(batchSize: Swift::Int, input: Accelerate::BNNSNDArrayDescriptor, output: Accelerate::BNNSNDArrayDescriptor) throws {
            try _applyArithmetic(self, batchSize: batchSize, inputs: [input], output: output)
        }

        public func applyBackward(batchSize: Swift::Int, input: Accelerate::BNNSNDArrayDescriptor, output: Accelerate::BNNSNDArrayDescriptor, outputGradient: Accelerate::BNNSNDArrayDescriptor, generatingInputGradient inputGradient: Accelerate::BNNSNDArrayDescriptor) throws {
            try _applyArithmeticBackward(self, batchSize: batchSize, inputs: [input], output: output, outputGradient: outputGradient, inputGradients: [inputGradient])
        }

        deinit {}
    }

    @_inheritsConvenienceInitializers @_hasMissingDesignatedInitializers public class BinaryArithmeticLayer: Accelerate::BNNS.Accelerate::Layer {
        convenience public init?(inputA: Accelerate::BNNSNDArrayDescriptor, inputADescriptorType: Accelerate::BNNS.Accelerate::DescriptorType, inputB: Accelerate::BNNSNDArrayDescriptor, inputBDescriptorType: Accelerate::BNNS.Accelerate::DescriptorType, output: Accelerate::BNNSNDArrayDescriptor, outputDescriptorType: Accelerate::BNNS.Accelerate::DescriptorType, function: Accelerate::BNNS.Accelerate::ArithmeticBinaryFunction, activation: Accelerate::BNNS.Accelerate::ActivationFunction = .identity, filterParameters: Accelerate::BNNSFilterParameters? = nil) {
            let fields = BNNSArithmeticBinary(in1: inputA, in1_type: inputADescriptorType.bnnsDescriptorType, in2: inputB, in2_type: inputBDescriptorType.bnnsDescriptorType,
                                              out: output, out_type: outputDescriptorType.bnnsDescriptorType)
            guard let filter = _makeArithmeticFilter(function.bnnsArithmeticFunction, fields, activation, filterParameters) else { return nil }
            self.init(filter: filter)
        }

        public func apply(batchSize: Swift::Int, inputA: Accelerate::BNNSNDArrayDescriptor, inputB: Accelerate::BNNSNDArrayDescriptor, output: Accelerate::BNNSNDArrayDescriptor) throws {
            try _applyArithmetic(self, batchSize: batchSize, inputs: [inputA, inputB], output: output)
        }

        public func applyBackward(batchSize: Swift::Int, inputA: Accelerate::BNNSNDArrayDescriptor, inputB: Accelerate::BNNSNDArrayDescriptor, output: Accelerate::BNNSNDArrayDescriptor, outputGradient: Accelerate::BNNSNDArrayDescriptor, generatingInputAGradient inputAGradient: Accelerate::BNNSNDArrayDescriptor, generatingInputBGradient inputBGradient: Accelerate::BNNSNDArrayDescriptor) throws {
            try _applyArithmeticBackward(self, batchSize: batchSize, inputs: [inputA, inputB], output: output, outputGradient: outputGradient,
                                         inputGradients: [inputAGradient, inputBGradient])
        }

        deinit {}
    }
}

@available(macOS 12.0, iOS 15.0, tvOS 15.0, watchOS 8.0, *)
@available(*, deprecated, message: "Use the BNNSGraph API instead.")
extension Accelerate::BNNS {
    @_inheritsConvenienceInitializers @_hasMissingDesignatedInitializers public class TernaryArithmeticLayer: Accelerate::BNNS.Accelerate::Layer {
        convenience public init?(inputA: Accelerate::BNNSNDArrayDescriptor, inputADescriptorType: Accelerate::BNNS.Accelerate::DescriptorType, inputB: Accelerate::BNNSNDArrayDescriptor, inputBDescriptorType: Accelerate::BNNS.Accelerate::DescriptorType, inputC: Accelerate::BNNSNDArrayDescriptor, inputCDescriptorType: Accelerate::BNNS.Accelerate::DescriptorType, output: Accelerate::BNNSNDArrayDescriptor, outputDescriptorType: Accelerate::BNNS.Accelerate::DescriptorType, function: Accelerate::BNNS.Accelerate::ArithmeticTernaryFunction, activation: Accelerate::BNNS.Accelerate::ActivationFunction = .identity, filterParameters: Accelerate::BNNSFilterParameters? = nil) {
            let fields = BNNSArithmeticTernary(in1: inputA, in1_type: inputADescriptorType.bnnsDescriptorType, in2: inputB, in2_type: inputBDescriptorType.bnnsDescriptorType,
                                               in3: inputC, in3_type: inputCDescriptorType.bnnsDescriptorType, out: output, out_type: outputDescriptorType.bnnsDescriptorType)
            guard let filter = _makeArithmeticFilter(function.bnnsArithmeticFunction, fields, activation, filterParameters) else { return nil }
            self.init(filter: filter)
        }

        public func apply(batchSize: Swift::Int, inputA: Accelerate::BNNSNDArrayDescriptor, inputB: Accelerate::BNNSNDArrayDescriptor, inputC: Accelerate::BNNSNDArrayDescriptor, output: Accelerate::BNNSNDArrayDescriptor) throws {
            try _applyArithmetic(self, batchSize: batchSize, inputs: [inputA, inputB, inputC], output: output)
        }

        public func applyBackward(batchSize: Swift::Int, inputA: Accelerate::BNNSNDArrayDescriptor, inputB: Accelerate::BNNSNDArrayDescriptor, inputC: Accelerate::BNNSNDArrayDescriptor, output: Accelerate::BNNSNDArrayDescriptor, outputGradient: Accelerate::BNNSNDArrayDescriptor, generatingInputAGradient inputAGradient: Accelerate::BNNSNDArrayDescriptor, generatingInputBGradient inputBGradient: Accelerate::BNNSNDArrayDescriptor, generatingInputCGradient inputCGradient: Accelerate::BNNSNDArrayDescriptor) throws {
            try _applyArithmeticBackward(self, batchSize: batchSize, inputs: [inputA, inputB, inputC], output: output, outputGradient: outputGradient,
                                         inputGradients: [inputAGradient, inputBGradient, inputCGradient])
        }

        deinit {}
    }
}

// MARK: - Shape and data layers

@available(macOS 11.0, iOS 14.0, tvOS 14.0, watchOS 7.0, *)
@available(*, deprecated, message: "Use the BNNSGraph API instead.")
extension Accelerate::BNNS {
    @_inheritsConvenienceInitializers @_hasMissingDesignatedInitializers public class PermuteLayer: Accelerate::BNNS.Accelerate::UnaryLayer {
        convenience public init?(input: Accelerate::BNNSNDArrayDescriptor, output: Accelerate::BNNSNDArrayDescriptor, permutation: [Swift::Int], filterParameters: Accelerate::BNNSFilterParameters? = nil) {
            let parameters = BNNSLayerParametersPermute(i_desc: input, o_desc: output, permutation: _tuple8(permutation))
            guard let filter = _makeFilter(parameters, filterParameters, BNNSFilterCreateLayerPermute) else { return nil }
            self.init(filter: filter)
        }

        public override func applyBackward(batchSize: Swift::Int, input: Accelerate::BNNSNDArrayDescriptor, output: Accelerate::BNNSNDArrayDescriptor, outputGradient: Accelerate::BNNSNDArrayDescriptor, generatingInputGradient inputGradient: Accelerate::BNNSNDArrayDescriptor) throws {
            var inGradient = inputGradient, outGradient = outputGradient
            try _check(BNNSPermuteFilterApplyBackwardBatch(bnnsFilter, batchSize, &inGradient, inGradient.batchStride, &outGradient, outGradient.batchStride))
        }

        deinit {}
    }

    @_inheritsConvenienceInitializers @_hasMissingDesignatedInitializers public class DropoutLayer: Accelerate::BNNS.Accelerate::UnaryLayer {
        convenience public init?(input: Accelerate::BNNSNDArrayDescriptor, output: Accelerate::BNNSNDArrayDescriptor, rate: Swift::Float, seed: Swift::UInt32, control: Swift::UInt8, filterParameters: Accelerate::BNNSFilterParameters? = nil) {
            let parameters = BNNSLayerParametersDropout(i_desc: input, o_desc: output, rate: rate, seed: seed, control: control)
            guard let filter = _makeFilter(parameters, filterParameters, BNNSFilterCreateLayerDropout) else { return nil }
            self.init(filter: filter)
        }
        deinit {}
    }

    @_inheritsConvenienceInitializers @_hasMissingDesignatedInitializers public class GramLayer: Accelerate::BNNS.Accelerate::UnaryLayer {
        convenience public init?(input: Accelerate::BNNSNDArrayDescriptor, output: Accelerate::BNNSNDArrayDescriptor, alpha: Swift::Float, filterParameters: Accelerate::BNNSFilterParameters? = nil) {
            let parameters = BNNSLayerParametersGram(alpha: alpha, i_desc: input, o_desc: output)
            guard let filter = _makeFilter(parameters, filterParameters, BNNSFilterCreateLayerGram) else { return nil }
            self.init(filter: filter)
        }
        deinit {}
    }

    @_inheritsConvenienceInitializers @_hasMissingDesignatedInitializers public class ResizeLayer: Accelerate::BNNS.Accelerate::UnaryLayer {
        convenience public init?(interpolationMethod: Accelerate::BNNS.Accelerate::InterpolationMethod, input: Accelerate::BNNSNDArrayDescriptor, output: Accelerate::BNNSNDArrayDescriptor, alignsCorners: Swift::Bool, filterParameters: Accelerate::BNNSFilterParameters? = nil) {
            let parameters = BNNSLayerParametersResize(method: interpolationMethod.bnnsMethod, i_desc: input, o_desc: output, align_corners: alignsCorners)
            guard let filter = _makeFilter(parameters, filterParameters, BNNSFilterCreateLayerResize) else { return nil }
            self.init(filter: filter)
        }
        deinit {}
    }

    @_inheritsConvenienceInitializers @_hasMissingDesignatedInitializers public class ReductionLayer: Accelerate::BNNS.Accelerate::UnaryLayer {
        convenience public init?(function reductionFunction: Accelerate::BNNS.Accelerate::ReductionFunction, input: Accelerate::BNNSNDArrayDescriptor, output: Accelerate::BNNSNDArrayDescriptor, weights: Accelerate::BNNSNDArrayDescriptor?, filterParameters: Accelerate::BNNSFilterParameters? = nil) {
            let parameters = BNNSLayerParametersReduction(i_desc: input, o_desc: output, w_desc: weights ?? _emptyDescriptor(),
                                                          reduce_func: reductionFunction.bnnsReduceFunction, epsilon: reductionFunction.epsilon)
            guard let filter = _makeFilter(parameters, filterParameters, BNNSFilterCreateLayerReduction) else { return nil }
            self.init(filter: filter)
        }

        public func applyBackward(batchSize: Swift::Int, input: Accelerate::BNNSNDArrayDescriptor, output: Accelerate::BNNSNDArrayDescriptor, outputGradient: Accelerate::BNNSNDArrayDescriptor, generatingInputGradient inputGradient: Accelerate::BNNSNDArrayDescriptor, generatingWeightsGradient weightsGradient: Accelerate::BNNSNDArrayDescriptor? = nil) throws {
            try _applyBackward(self, batchSize: batchSize, input: input, output: output, outputGradient: outputGradient,
                               inputGradient: inputGradient, weightsGradient: weightsGradient, biasGradient: nil)
        }

        deinit {}
    }

    @_inheritsConvenienceInitializers @_hasMissingDesignatedInitializers public class PaddingLayer: Accelerate::BNNS.Accelerate::UnaryLayer {
        convenience public init?(input: Accelerate::BNNSNDArrayDescriptor, output: Accelerate::BNNSNDArrayDescriptor, mode: Accelerate::BNNS.Accelerate::PaddingMode, size: [(x: Swift::Int, y: Swift::Int)], filterParameters: Accelerate::BNNSFilterParameters? = nil) {
            let pairs = (0..<8).map { $0 < size.count ? (size[$0].x, size[$0].y) : (0, 0) }
            let parameters = BNNSLayerParametersPadding(i_desc: input, o_desc: output,
                                                        padding_size: (pairs[0], pairs[1], pairs[2], pairs[3], pairs[4], pairs[5], pairs[6], pairs[7]),
                                                        padding_mode: mode.bnnsPaddingMode, padding_value: mode.paddingBitPattern)
            guard let filter = _makeFilter(parameters, filterParameters, BNNSFilterCreateLayerPadding) else { return nil }
            self.init(filter: filter)
        }
        deinit {}
    }

    @_hasMissingDesignatedInitializers public class BroadcastMatrixMultiplyLayer: Accelerate::BNNS.Accelerate::Layer {
        convenience public init?(inputA: Accelerate::BNNSNDArrayDescriptor, transposed transposeA: Swift::Bool, isWeights aIsWeights: Swift::Bool, inputB: Accelerate::BNNSNDArrayDescriptor, transposed transposeB: Swift::Bool, isWeights bIsWeights: Swift::Bool, output: Accelerate::BNNSNDArrayDescriptor, alpha: Swift::Float, accumulatesToOutput: Swift::Bool, isQuadratic: Swift::Bool, filterParameters: Accelerate::BNNSFilterParameters? = nil) {
            let parameters = BNNSLayerParametersBroadcastMatMul(alpha: alpha, beta: accumulatesToOutput ? 1 : 0, transA: transposeA, transB: transposeB,
                                                                quadratic: isQuadratic, a_is_weights: aIsWeights, b_is_weights: bIsWeights,
                                                                iA_desc: inputA, iB_desc: inputB, o_desc: output)
            guard let filter = _makeFilter(parameters, filterParameters, BNNSFilterCreateLayerBroadcastMatMul) else { return nil }
            self.init(filter: filter)
        }

        @available(macOS 12.0, iOS 15.0, tvOS 15.0, watchOS 8.0, *)
        public func apply(batchSize: Swift::Int, inputA: Accelerate::BNNSNDArrayDescriptor, inputB: Accelerate::BNNSNDArrayDescriptor, output: Accelerate::BNNSNDArrayDescriptor) throws {
            try _applyTwoInputs(self, batchSize: batchSize, inputA: inputA, inputB: inputB, output: output)
        }

        public func applyBackward(batchSize: Swift::Int, inputA: Accelerate::BNNSNDArrayDescriptor, inputB: Accelerate::BNNSNDArrayDescriptor, output: Accelerate::BNNSNDArrayDescriptor, outputGradient: Accelerate::BNNSNDArrayDescriptor, generatingInputAGradient inputAGradient: Accelerate::BNNSNDArrayDescriptor, generatingInputBGradient inputBGradient: Accelerate::BNNSNDArrayDescriptor) throws {
            try _applyTwoInputsBackward(self, batchSize: batchSize, inputA: inputA, inputB: inputB, output: output, outputGradient: outputGradient,
                                        inputAGradient: inputAGradient, inputBGradient: inputBGradient)
        }

        deinit {}
    }

    @_inheritsConvenienceInitializers @_hasMissingDesignatedInitializers public class LossLayer: Accelerate::BNNS.Accelerate::Layer {
        convenience public init?(input: Accelerate::BNNSNDArrayDescriptor, output: Accelerate::BNNSNDArrayDescriptor, lossFunction: Accelerate::BNNS.Accelerate::LossFunction, lossReduction: Accelerate::BNNS.Accelerate::LossReduction, filterParameters: Accelerate::BNNSFilterParameters? = nil) {
            let function = lossFunction.bnnsLossFunction
            let reduction = lossReduction.bnnsLossReductionFunction
            let filter: BNNSFilter?
            func create<P>(_ parameters: P) -> BNNSFilter? {
                var parameters = parameters
                return _withFilterParameters(filterParameters) { fp in
                    withUnsafePointer(to: &parameters) { BNNSFilterCreateLayerLoss(UnsafeRawPointer($0), fp) }
                }
            }
            switch lossFunction {
            case let .softmaxCrossEntropy(smoothing):
                filter = create(BNNSLayerParametersLossSoftmaxCrossEntropy(function: function, i_desc: input, o_desc: output, reduction: reduction, label_smooth: smoothing))
            case let .sigmoidCrossEntropy(smoothing):
                filter = create(BNNSLayerParametersLossSigmoidCrossEntropy(function: function, i_desc: input, o_desc: output, reduction: reduction, label_smooth: smoothing))
            case let .huber(delta):
                filter = create(BNNSLayerParametersLossHuber(function: function, i_desc: input, o_desc: output, reduction: reduction, huber_delta: delta))
            case let .yolo(p):
                filter = create(BNNSLayerParametersLossYolo(function: function, i_desc: input, o_desc: output, reduction: reduction, huber_delta: p.huberDelta,
                                                            number_of_grid_columns: p.gridColumnCount, number_of_grid_rows: p.gridRowsCount,
                                                            number_of_anchor_boxes: p.anchorBoxCount, anchor_box_size: p.anchorBoxSize, rescore: p.rescore,
                                                            scale_xy: p.xyScale, scale_wh: p.whScale, scale_object: p.objectScale,
                                                            scale_no_object: p.noObjectScale, scale_classification: p.classificationScale,
                                                            object_minimum_iou: p.objectMinimumIoU, no_object_maximum_iou: p.noObjectMaximumIoU,
                                                            anchors_data: p.anchorsData))
            default:
                filter = create(BNNSLayerParametersLossBase(function: function, i_desc: input, o_desc: output, reduction: reduction))
            }
            guard let filter else { return nil }
            self.init(filter: filter)
        }

        public func apply(batchSize: Swift::Int, input: Accelerate::BNNSNDArrayDescriptor, labels: Accelerate::BNNSNDArrayDescriptor, output: Accelerate::BNNSNDArrayDescriptor, generatingInputGradient inputGradient: Accelerate::BNNSNDArrayDescriptor) throws {
            try apply(batchSize: batchSize, input: input, labels: labels, output: output, weights: nil, broadcastsWeights: false, generatingInputGradient: inputGradient)
        }

        deinit {}
    }
}

@available(macOS 12.0, iOS 15.0, tvOS 15.0, watchOS 8.0, *)
@available(*, deprecated, message: "Use the BNNSGraph API instead.")
extension Accelerate::BNNS.Accelerate::LossLayer {
    public func apply(batchSize: Swift::Int, input: Accelerate::BNNSNDArrayDescriptor, labels: Accelerate::BNNSNDArrayDescriptor, output: Accelerate::BNNSNDArrayDescriptor, weights: Accelerate::BNNSNDArrayDescriptor?, broadcastsWeights: Swift::Bool, generatingInputGradient inputGradient: Accelerate::BNNSNDArrayDescriptor) throws {
        var inGradient = inputGradient
        let weightsSize = weights?.data == nil ? 0 : (broadcastsWeights ? 1 : batchSize)
        let inData = try _data(input), labelData = try _data(labels), outData = try _data(output)
        let hasGradient = inGradient.data != nil
        try withUnsafeMutablePointer(to: &inGradient) { gradient in
            try _check(BNNSLossFilterApplyBatch(bnnsFilter, batchSize, inData, input.batchStride, labelData, labels.batchStride,
                                                weights?.data, weightsSize, outData, hasGradient ? gradient : nil, gradient.pointee.batchStride))
        }
    }
}

@available(macOS 12.0, iOS 15.0, tvOS 15.0, watchOS 8.0, *)
@available(*, deprecated, message: "Use the BNNSGraph API instead.")
extension Accelerate::BNNS {
    @_inheritsConvenienceInitializers @_hasMissingDesignatedInitializers public class EmbeddingLayer: Accelerate::BNNS.Accelerate::Layer {
        convenience public init?(input: Accelerate::BNNSNDArrayDescriptor, output: Accelerate::BNNSNDArrayDescriptor, dictionary: Accelerate::BNNSNDArrayDescriptor, paddingIndex: Swift::Int, maximumNorm: Swift::Float, normType: Accelerate::BNNS.Accelerate::Norm, scalesGradientByFrequency: Swift::Bool, filterParameters: Accelerate::BNNSFilterParameters? = nil) {
            let parameters = BNNSLayerParametersEmbedding(flags: BNNSEmbeddingFlags(rawValue: scalesGradientByFrequency ? 1 : 0), i_desc: input, o_desc: output,
                                                          dictionary: dictionary, padding_idx: paddingIndex, max_norm: maximumNorm, norm_type: normType.rawValue)
            guard let filter = _makeFilter(parameters, filterParameters, BNNSFilterCreateLayerEmbedding) else { return nil }
            self.init(filter: filter)
        }

        public func apply(batchSize: Swift::Int, input: Accelerate::BNNSNDArrayDescriptor, output: Accelerate::BNNSNDArrayDescriptor) throws {
            try _check(BNNSFilterApplyBatch(bnnsFilter, batchSize, try _data(input), input.batchStride, try _data(output), output.batchStride))
        }

        public func applyBackward(batchSize: Swift::Int, input: Accelerate::BNNSNDArrayDescriptor, output: Accelerate::BNNSNDArrayDescriptor, outputGradient: Accelerate::BNNSNDArrayDescriptor, generatingWeightsGradient weightsGradient: Accelerate::BNNSNDArrayDescriptor) throws {
            var outGradient = outputGradient, wGradient = weightsGradient
            try _check(BNNSFilterApplyBackwardBatch(bnnsFilter, batchSize, input.data, input.batchStride, nil, 0, output.data, output.batchStride,
                                                    &outGradient, outGradient.batchStride, &wGradient, nil))
        }

        deinit {}
    }
}

// MARK: - Crop and resize

@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
@available(*, deprecated, message: "Use the BNNSGraph API instead.")
extension Accelerate::BNNS {
    @available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
    public class CropResizeLayer {
        public enum BoxCoordinateMode: Swift::Hashable {
            case cornersHeightFirst
            case cornersWidthFirst
            case centerSizeHeightFirst
            case centerSizeWidthFirst
        }

        public enum LinearSamplingMode: Swift::Hashable {
            case `default`
            case alignCorners
            case unalignCorners
            case strictAlignCorners
            case offsetCorners
        }

        /// The C parameters the layer applies.
        var parameters: BNNSLayerParametersCropResize

        @available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
        public init(coordinatesAreNormalized: Swift::Bool, spatialScale: Swift::Float, extrapolationValue: Swift::Float = 0, samplingMode: Accelerate::BNNS.Accelerate::CropResizeLayer.Accelerate::LinearSamplingMode = .default, boxCoordinateMode: Accelerate::BNNS.Accelerate::CropResizeLayer.Accelerate::BoxCoordinateMode) {
            let sampling: UInt32
            switch samplingMode {
            case .default: sampling = 0
            case .alignCorners: sampling = 1
            case .unalignCorners: sampling = 2
            case .strictAlignCorners: sampling = 3
            case .offsetCorners: sampling = 4
            }
            let box: UInt32
            switch boxCoordinateMode {
            case .cornersHeightFirst: box = 0
            case .cornersWidthFirst: box = 1
            case .centerSizeHeightFirst: box = 2
            case .centerSizeWidthFirst: box = 3
            }
            parameters = BNNSLayerParametersCropResize(normalized_coordinates: coordinatesAreNormalized, spatial_scale: spatialScale,
                                                       extrapolation_value: extrapolationValue, sampling_mode: BNNSLinearSamplingMode(rawValue: sampling),
                                                       box_coordinate_mode: BNNSBoxCoordinateMode(rawValue: box), method: BNNSInterpolationMethod(rawValue: 1))
        }

        @available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
        public func apply(input: Accelerate::BNNSNDArrayDescriptor, regionOfInterest: Accelerate::BNNSNDArrayDescriptor, output: Accelerate::BNNSNDArrayDescriptor, filterParameters: Accelerate::BNNSFilterParameters? = nil) throws {
            var input = input, roi = regionOfInterest, output = output
            try _withFilterParameters(filterParameters) { fp in
                try _check(BNNSCropResize(&parameters, &input, &roi, &output, fp))
            }
        }

        @available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
        public func applyBackward(regionOfInterest: Accelerate::BNNSNDArrayDescriptor, outputGradient: Accelerate::BNNSNDArrayDescriptor, generatingInputGradient inputGradient: Accelerate::BNNSNDArrayDescriptor, filterParameters: Accelerate::BNNSFilterParameters? = nil) throws {
            var inGradient = inputGradient, roi = regionOfInterest, outGradient = outputGradient
            try _withFilterParameters(filterParameters) { fp in
                try _check(BNNSCropResizeBackward(&parameters, &inGradient, &roi, &outGradient, fp))
            }
        }

        deinit {}
    }
}
