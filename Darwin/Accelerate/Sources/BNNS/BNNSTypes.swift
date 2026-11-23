import Swift
import Darwin

// The Swift enumerations of BNNS's functions (activations, arithmetic,
// reductions, losses, pooling, padding, normalization...), each with the C
// value it stands for.

@available(macOS 11.0, iOS 14.0, tvOS 14.0, watchOS 7.0, *)
extension Accelerate::BNNS {
    public enum Error: Swift::Error, Swift::Hashable {
        case layerApplyFail
        case unableToCreateLayer
        case arrayDescriptorInvalidData
        case optimizerStepFail
    }
}

@available(macOS 11.0, iOS 14.0, tvOS 14.0, watchOS 7.0, *)
@available(*, deprecated, message: "Use the BNNSGraph API instead.")
extension Accelerate::BNNS {
    public enum ActivationFunction {
        case identity
        case rectifiedLinear
        case leakyRectifiedLinear(alpha: Swift::Float)
        case sigmoid
        case logSigmoid
        case tanh
        case scaledTanh(alpha: Swift::Float, beta: Swift::Float)
        case abs
        case linear(alpha: Swift::Float)
        case clamp(bounds: Swift::ClosedRange<Swift::Float>)
        case softmax
        case geluApproximation(alpha: Swift::Float, beta: Swift::Float)
        case geluApproximation2(alpha: Swift::Float, beta: Swift::Float)
        case gumbel(alpha: Swift::Float, beta: Swift::Float)
        case gumbelMax(alpha: Swift::Float, beta: Swift::Float)
        case hardSigmoid(alpha: Swift::Float, beta: Swift::Float)
        case softplus(alpha: Swift::Float, beta: Swift::Float)
        case softsign
        case elu(alpha: Swift::Float)
        case selu
        case celu(alpha: Swift::Float)
        case clampedLeakyRectifiedLinear(alpha: Swift::Float, beta: Swift::Float)
        case linearWithBias(alpha: Swift::Float, beta: Swift::Float)
        case logSoftmax
        case hardShrink(alpha: Swift::Float)
        case softShrink(alpha: Swift::Float)
        case tanhShrink
        case threshold(alpha: Swift::Float, beta: Swift::Float)
        case hardSwish(alpha: Swift::Float, beta: Swift::Float)
        @available(macOS 12.0, iOS 15.0, tvOS 15.0, watchOS 8.0, *)
        case silu

        public var bnnsActivation: Accelerate::BNNSActivation {
            func make(_ function: UInt32, _ alpha: Float = .nan, _ beta: Float = .nan) -> BNNSActivation {
                BNNSActivation(function: BNNSActivationFunction(rawValue: function), alpha: alpha, beta: beta)
            }
            switch self {
            case .identity: return make(0)
            case .rectifiedLinear: return make(1)
            case let .leakyRectifiedLinear(alpha): return make(2, alpha)
            case .sigmoid: return make(3)
            case .logSigmoid: return make(22)
            case .tanh: return make(4)
            case let .scaledTanh(alpha, beta): return make(5, alpha, beta)
            case .abs: return make(6)
            case let .linear(alpha): return make(7, alpha)
            case let .clamp(bounds): return make(8, bounds.lowerBound, bounds.upperBound)
            case .softmax: return make(11)
            case let .geluApproximation(alpha, beta): return make(12, alpha, beta)
            case let .geluApproximation2(alpha, beta): return make(30, alpha, beta)
            case let .gumbel(alpha, beta): return make(13, alpha, beta)
            case let .gumbelMax(alpha, beta): return make(14, alpha, beta)
            case let .hardSigmoid(alpha, beta): return make(15, alpha, beta)
            case let .softplus(alpha, beta): return make(16, alpha, beta)
            case .softsign: return make(17)
            case let .elu(alpha): return make(18, alpha)
            case .selu: return make(23)
            case let .celu(alpha): return make(24, alpha)
            case let .clampedLeakyRectifiedLinear(alpha, beta): return make(19, alpha, beta)
            case let .linearWithBias(alpha, beta): return make(20, alpha, beta)
            case .logSoftmax: return make(21)
            case let .hardShrink(alpha): return make(25, alpha)
            case let .softShrink(alpha): return make(26, alpha)
            case .tanhShrink: return make(27)
            case let .threshold(alpha, beta): return make(28, alpha, beta)
            case let .hardSwish(alpha, beta): return make(30, alpha, beta)
            case .silu: return make(31)
            }
        }
    }

    public enum PoolingType {
        case max(indices: Swift::UnsafeMutableBufferPointer<Swift::Int>? = nil, xDilationStride: Swift::Int = 0, yDilationStride: Swift::Int = 0)
        case unMax(indices: Swift::UnsafeMutableBufferPointer<Swift::Int>? = nil, xDilationStride: Swift::Int = 0, yDilationStride: Swift::Int = 0)
        case average(countIncludesPadding: Swift::Bool)
        case l2Norm
        @available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
        case maxEx(indicesDescriptor: Accelerate::BNNSNDArrayDescriptor? = nil, xDilationStride: Swift::Int = 0, yDilationStride: Swift::Int = 0)
        @available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
        case unMaxEx(indicesDescriptor: Accelerate::BNNSNDArrayDescriptor, xDilationStride: Swift::Int = 0, yDilationStride: Swift::Int = 0)

        public var bnnsPoolingFunction: Accelerate::BNNSPoolingFunction {
            switch self {
            case .max, .maxEx: return BNNSPoolingFunction(rawValue: 0)
            case .unMax, .unMaxEx: return BNNSPoolingFunction(rawValue: 3)
            case let .average(countIncludesPadding): return BNNSPoolingFunction(rawValue: countIncludesPadding ? 1 : 2)
            case .l2Norm: return BNNSPoolingFunction(rawValue: 4)
            }
        }

        var dilation: (x: Int, y: Int) {
            switch self {
            case let .max(_, x, y), let .unMax(_, x, y): return (x, y)
            case let .maxEx(_, x, y): return (x, y)
            case let .unMaxEx(_, x, y): return (x, y)
            default: return (0, 0)
            }
        }
    }

    public enum ConvolutionPadding {
        case symmetric(x: Swift::Int, y: Swift::Int)
        case asymmetric(left: Swift::Int, right: Swift::Int, up: Swift::Int, down: Swift::Int)

        public static var zero: Accelerate::BNNS.Accelerate::ConvolutionPadding { .symmetric(x: 0, y: 0) }

        /// x_padding, y_padding and pad of the C parameters.
        var parts: (x: Int, y: Int, pad: (Int, Int, Int, Int)) {
            switch self {
            case let .symmetric(x, y): return (x, y, (0, 0, 0, 0))
            case let .asymmetric(left, right, up, down): return (0, 0, (left, right, up, down))
            }
        }
    }

    public enum ConvolutionType: Swift::Hashable {
        case standard
        case transposed
    }

    public enum NormalizationType {
        case batch(movingMean: Accelerate::BNNSNDArrayDescriptor?, movingVariance: Accelerate::BNNSNDArrayDescriptor?)
        case instance(movingMean: Accelerate::BNNSNDArrayDescriptor?, movingVariance: Accelerate::BNNSNDArrayDescriptor?)
        case layer(normalizationAxis: Swift::Int)
        case group(groupCount: Swift::Int)

        var filterType: BNNSFilterType {
            switch self {
            case .batch: return BNNSFilterType(rawValue: 2)
            case .instance: return BNNSFilterType(rawValue: 3)
            case .layer: return BNNSFilterType(rawValue: 4)
            case .group: return BNNSFilterType(rawValue: 5)
            }
        }

        func parameters(input: BNNSNDArrayDescriptor, output: BNNSNDArrayDescriptor, beta: BNNSNDArrayDescriptor?, gamma: BNNSNDArrayDescriptor?,
                        momentum: Float, epsilon: Float, activation: ActivationFunction) -> BNNSLayerParametersNormalization {
            var mean = _emptyDescriptor(), variance = _emptyDescriptor(), groups = 1, axis = 0
            switch self {
            case let .batch(m, v), let .instance(m, v):
                mean = m ?? mean
                variance = v ?? variance
            case let .layer(a): axis = a
            case let .group(g): groups = g
            }
            return BNNSLayerParametersNormalization(i_desc: input, o_desc: output, beta_desc: beta ?? _emptyDescriptor(), gamma_desc: gamma ?? _emptyDescriptor(),
                                                    moving_mean_desc: mean, moving_variance_desc: variance, momentum: momentum, epsilon: epsilon,
                                                    activation: activation.bnnsActivation, num_groups: groups, normalization_axis: axis)
        }
    }

    @frozen public enum LearningPhase: Swift::Hashable {
        case training
        case inference
    }

    public enum DescriptorType: Swift::Hashable {
        case constant
        case sample
        case parameter

        var bnnsDescriptorType: BNNSDescriptorType {
            switch self {
            case .constant: return BNNSDescriptorType(rawValue: 0)
            case .sample: return BNNSDescriptorType(rawValue: 1)
            case .parameter: return BNNSDescriptorType(rawValue: 2)
            }
        }
    }

    public enum ArithmeticUnaryFunction: Swift::CaseIterable, Swift::Hashable {
        case squareRoot
        case reciprocalSquareRoot
        case floor
        case ceil
        case round
        case sin
        case cos
        case tan
        case asin
        case acos
        case atan
        case sinh
        case cosh
        case tanh
        case asinh
        case acosh
        case atanh
        case exp
        case exp2
        case log
        case log2
        @available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
        case abs
        @available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
        case sign
        @available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
        case negate
        @available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
        case reciprocal
        @available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
        case square
        @available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
        case erf

        public var bnnsArithmeticFunction: Accelerate::BNNSArithmeticFunction {
            let value: UInt32
            switch self {
            case .squareRoot: value = 4
            case .reciprocalSquareRoot: value = 5
            case .floor: value = 7
            case .ceil: value = 6
            case .round: value = 8
            case .sin: value = 9
            case .cos: value = 10
            case .tan: value = 11
            case .asin: value = 12
            case .acos: value = 13
            case .atan: value = 14
            case .sinh: value = 15
            case .cosh: value = 16
            case .tanh: value = 17
            case .asinh: value = 18
            case .acosh: value = 19
            case .atanh: value = 20
            case .exp: value = 22
            case .exp2: value = 23
            case .log: value = 24
            case .log2: value = 25
            case .abs: value = 32
            case .sign: value = 33
            case .negate: value = 34
            case .reciprocal: value = 35
            case .square: value = 36
            case .erf: value = 40
            }
            return BNNSArithmeticFunction(rawValue: value)
        }

        public static var allCases: [Accelerate::BNNS.Accelerate::ArithmeticUnaryFunction] {
            [.squareRoot, .reciprocalSquareRoot, .floor, .ceil, .round, .sin, .cos, .tan, .asin, .acos, .atan,
             .sinh, .cosh, .tanh, .asinh, .acosh, .atanh, .exp, .exp2, .log, .log2,
             .abs, .sign, .negate, .reciprocal, .square, .erf]
        }

        @available(macOS 11.0, iOS 14.0, tvOS 14.0, watchOS 7.0, *)
        @available(*, deprecated, message: "Use the BNNSGraph API instead.")
        public typealias AllCases = [Accelerate::BNNS.Accelerate::ArithmeticUnaryFunction]
    }

    public enum ArithmeticBinaryFunction: Swift::CaseIterable, Swift::Hashable {
        case add
        case subtract
        case multiply
        case multiplyNoNaN
        case divide
        case divideNoNaN
        case pow
        @available(macOS 12.0, iOS 15.0, tvOS 15.0, watchOS 8.0, *)
        case max
        @available(macOS 12.0, iOS 15.0, tvOS 15.0, watchOS 8.0, *)
        case min
        @available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
        case flooringDivide
        @available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
        case truncatingDivide
        @available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
        case truncatingRemainder

        var bnnsArithmeticFunction: BNNSArithmeticFunction {
            let value: UInt32
            switch self {
            case .add: value = 0
            case .subtract: value = 1
            case .multiply: value = 2
            case .multiplyNoNaN: value = 26
            case .divide: value = 3
            case .divideNoNaN: value = 27
            case .pow: value = 21
            case .max: value = 30
            case .min: value = 29
            case .flooringDivide: value = 37
            case .truncatingDivide: value = 38
            case .truncatingRemainder: value = 39
            }
            return BNNSArithmeticFunction(rawValue: value)
        }

        public static var allCases: [Accelerate::BNNS.Accelerate::ArithmeticBinaryFunction] {
            [.add, .subtract, .multiply, .multiplyNoNaN, .divide, .divideNoNaN, .pow, .max, .min,
             .flooringDivide, .truncatingDivide, .truncatingRemainder]
        }

        @available(macOS 11.0, iOS 14.0, tvOS 14.0, watchOS 7.0, *)
        @available(*, deprecated, message: "Use the BNNSGraph API instead.")
        public typealias AllCases = [Accelerate::BNNS.Accelerate::ArithmeticBinaryFunction]
    }

    public enum InterpolationMethod: Swift::Hashable {
        case linear
        case nearestNeighbor

        var bnnsMethod: BNNSInterpolationMethod {
            BNNSInterpolationMethod(rawValue: self == .linear ? 1 : 0)
        }
    }

    public enum PaddingMode {
        case constantBitPattern(Swift::UInt32)
        case constantScalar(Swift::Float)
        case reflect
        case symmetric

        public var bnnsPaddingMode: Accelerate::BNNSPaddingMode {
            switch self {
            case .constantBitPattern, .constantScalar: return BNNSPaddingMode(rawValue: 0)
            case .reflect: return BNNSPaddingMode(rawValue: 1)
            case .symmetric: return BNNSPaddingMode(rawValue: 2)
            }
        }

        public var paddingBitPattern: Swift::UInt32 {
            switch self {
            case let .constantBitPattern(bits): return bits
            case let .constantScalar(value): return value.bitPattern
            case .reflect, .symmetric: return 0
            }
        }
    }

    public enum ReductionFunction {
        case max
        case min
        @available(macOS, deprecated, introduced: 11.0, message: "Use `argMax`.")
        @available(iOS, deprecated, introduced: 14.0, message: "Use `argMax`.")
        @available(watchOS, deprecated, introduced: 7.0, message: "Use `argMax`.")
        @available(tvOS, deprecated, introduced: 14.0, message: "Use `argMax`.")
        @available(*, deprecated, message: "Use `argMax`.")
        case maxIndex
        case argMax
        @available(macOS, deprecated, introduced: 11.0, message: "Use `argMin`.")
        @available(iOS, deprecated, introduced: 14.0, message: "Use `argMin`.")
        @available(watchOS, deprecated, introduced: 7.0, message: "Use `argMin`.")
        @available(tvOS, deprecated, introduced: 14.0, message: "Use `argMin`.")
        @available(*, deprecated, message: "Use `argMin`.")
        case minIndex
        case argMin
        case mean
        case meanNonZero
        case sum
        case sumOfSquares
        case sumOfLogs(epsilon: Swift::Float)
        case sumOfAbsolutes
        case logicalOr
        case any
        case logicalAnd
        case all
        @available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
        case l2Norm
        @available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
        case logSumExp
        @available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
        case product

        public var bnnsReduceFunction: Accelerate::BNNSReduceFunction {
            let value: UInt32
            switch self {
            case .max: value = 0
            case .min: value = 1
            case .maxIndex, .argMax: value = 2
            case .minIndex, .argMin: value = 3
            case .mean: value = 4
            case .meanNonZero: value = 5
            case .sum: value = 6
            case .sumOfSquares: value = 7
            case .sumOfLogs: value = 8
            case .sumOfAbsolutes: value = 9
            case .logicalOr, .any: value = 10
            case .logicalAnd, .all: value = 11
            case .l2Norm: value = 12
            case .logSumExp: value = 13
            case .product: value = 14
            }
            return BNNSReduceFunction(rawValue: value)
        }

        var epsilon: Float {
            if case let .sumOfLogs(epsilon) = self { return epsilon }
            return 0
        }
    }

    public enum LossFunction {
        public struct YoloParameters {
            @available(macOS 12.0, iOS 15.0, tvOS 15.0, watchOS 8.0, *)
            public init(huberDelta: Swift::Float, gridColumnCount: Swift::Int, gridRowsCount: Swift::Int, anchorBoxCount: Swift::Int, anchorBoxSize: Swift::Int, rescore: Swift::Bool, xyScale: Swift::Float, whScale: Swift::Float, objectScale: Swift::Float, noObjectScale: Swift::Float, classificationScale: Swift::Float, objectMinimumIoU: Swift::Float, noObjectMaximumIoU: Swift::Float, anchorsData: Swift::UnsafeMutablePointer<Swift::Float>) {
                self.huberDelta = huberDelta
                self.gridColumnCount = gridColumnCount
                self.gridRowsCount = gridRowsCount
                self.anchorBoxCount = anchorBoxCount
                self.anchorBoxSize = anchorBoxSize
                self.rescore = rescore
                self.xyScale = xyScale
                self.whScale = whScale
                self.objectScale = objectScale
                self.noObjectScale = noObjectScale
                self.classificationScale = classificationScale
                self.objectMinimumIoU = objectMinimumIoU
                self.noObjectMaximumIoU = noObjectMaximumIoU
                self.anchorsData = anchorsData
            }
            public let huberDelta: Swift::Float
            public let gridColumnCount: Swift::Int
            public let gridRowsCount: Swift::Int
            public let anchorBoxCount: Swift::Int
            public let anchorBoxSize: Swift::Int
            public let rescore: Swift::Bool
            public let xyScale: Swift::Float
            public let whScale: Swift::Float
            public let objectScale: Swift::Float
            public let noObjectScale: Swift::Float
            public let classificationScale: Swift::Float
            public let objectMinimumIoU: Swift::Float
            public let noObjectMaximumIoU: Swift::Float
            public let anchorsData: Swift::UnsafeMutablePointer<Swift::Float>
        }

        case softmaxCrossEntropy(labelSmoothing: Swift::Float)
        case sigmoidCrossEntropy(labelSmoothing: Swift::Float)
        case huber(huberDelta: Swift::Float)
        case yolo(parameters: Accelerate::BNNS.Accelerate::LossFunction.Accelerate::YoloParameters)
        case meanSquareError
        case log
        case cosineDistance
        case hinge
        case meanAbsoluteError
        case categoricalCrossEntropy

        public var bnnsLossFunction: Accelerate::BNNSLossFunction {
            let value: UInt32
            switch self {
            case .softmaxCrossEntropy: value = 1
            case .sigmoidCrossEntropy: value = 2
            case .meanSquareError: value = 3
            case .huber: value = 4
            case .yolo: value = 5
            case .log: value = 6
            case .cosineDistance: value = 7
            case .hinge: value = 8
            case .meanAbsoluteError: value = 9
            case .categoricalCrossEntropy: value = 10
            }
            return BNNSLossFunction(rawValue: value)
        }
    }

    public enum LossReduction: Swift::Hashable {
        case none
        case sum
        case weightedMean
        case reductionMean
        case zeroWeightMean

        public var bnnsLossReductionFunction: Accelerate::BNNSLossReductionFunction {
            let value: UInt32
            switch self {
            case .none: value = 0
            case .sum: value = 1
            case .weightedMean: value = 2
            case .reductionMean: value = 3
            case .zeroWeightMean: value = 4
            }
            return BNNSLossReductionFunction(rawValue: value)
        }
    }

    @frozen public struct RelationalOperator {
        @usableFromInline
        internal var value: Accelerate::BNNSRelationalOperator
        @usableFromInline
        @inline(__always) internal init(_ value: Accelerate::BNNSRelationalOperator) {
            self.value = value
        }
        @inlinable public static var equal: Accelerate::BNNS.Accelerate::RelationalOperator { .init(BNNSRelationalOperator(rawValue: 0)) }
        @inlinable public static var less: Accelerate::BNNS.Accelerate::RelationalOperator { .init(BNNSRelationalOperator(rawValue: 1)) }
        @inlinable public static var lessEqual: Accelerate::BNNS.Accelerate::RelationalOperator { .init(BNNSRelationalOperator(rawValue: 2)) }
        @inlinable public static var greater: Accelerate::BNNS.Accelerate::RelationalOperator { .init(BNNSRelationalOperator(rawValue: 3)) }
        @inlinable public static var greaterEqual: Accelerate::BNNS.Accelerate::RelationalOperator { .init(BNNSRelationalOperator(rawValue: 4)) }
        @inlinable public static var notEqual: Accelerate::BNNS.Accelerate::RelationalOperator { .init(BNNSRelationalOperator(rawValue: 5)) }
        @inlinable public static var and: Accelerate::BNNS.Accelerate::RelationalOperator { .init(BNNSRelationalOperator(rawValue: 6)) }
        @inlinable public static var or: Accelerate::BNNS.Accelerate::RelationalOperator { .init(BNNSRelationalOperator(rawValue: 7)) }
        @inlinable public static var not: Accelerate::BNNS.Accelerate::RelationalOperator { .init(BNNSRelationalOperator(rawValue: 8)) }
        @inlinable public static var nand: Accelerate::BNNS.Accelerate::RelationalOperator { .init(BNNSRelationalOperator(rawValue: 9)) }
        @inlinable public static var nor: Accelerate::BNNS.Accelerate::RelationalOperator { .init(BNNSRelationalOperator(rawValue: 10)) }
        @inlinable public static var xor: Accelerate::BNNS.Accelerate::RelationalOperator { .init(BNNSRelationalOperator(rawValue: 11)) }
    }
}

@available(macOS 12.0, iOS 15.0, tvOS 15.0, watchOS 8.0, *)
@available(*, deprecated, message: "Use the BNNSGraph API instead.")
extension Accelerate::BNNS {
    public enum ArithmeticTernaryFunction: Swift::Hashable {
        case multiplyAdd

        public var bnnsArithmeticFunction: Accelerate::BNNSArithmeticFunction {
            BNNSArithmeticFunction(rawValue: 28)
        }
    }

    /// A norm, the p of an L^p norm (L1, L2, L∞).
    @frozen public struct Norm: Swift::Equatable {
        @_alwaysEmitIntoClient public var rawValue: Swift::Float
        @_alwaysEmitIntoClient public init(rawValue: Swift::Float) {
            self.rawValue = rawValue
        }
        @_alwaysEmitIntoClient public static var l1: Accelerate::BNNS.Accelerate::Norm { Norm(rawValue: 1) }
        @_alwaysEmitIntoClient public static var taxicab: Accelerate::BNNS.Accelerate::Norm { Norm(rawValue: 1) }
        @_alwaysEmitIntoClient public static var l2: Accelerate::BNNS.Accelerate::Norm { Norm(rawValue: 2) }
        @_alwaysEmitIntoClient public static var euclidean: Accelerate::BNNS.Accelerate::Norm { Norm(rawValue: 2) }
        @_alwaysEmitIntoClient public static var lInfinity: Accelerate::BNNS.Accelerate::Norm { Norm(rawValue: .infinity) }
        @_alwaysEmitIntoClient public static var maximum: Accelerate::BNNS.Accelerate::Norm { Norm(rawValue: .infinity) }
        public static func == (a: Accelerate::BNNS.Accelerate::Norm, b: Accelerate::BNNS.Accelerate::Norm) -> Swift::Bool {
            a.rawValue == b.rawValue
        }
    }

    public enum GradientClipping {
        case none
        case byValue(bounds: Swift::ClosedRange<Swift::Float>)
        case byNorm(threshold: Swift::Float)
        case byGlobalNorm(threshold: Swift::Float, globalNorm: Swift::Float = 0)
    }

    public enum RandomGeneratorMethod: Swift::Hashable {
        case aesCtr
    }
}

@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
@available(*, deprecated, message: "Use the BNNSGraph API instead.")
extension Accelerate::BNNS {
    @available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
    public enum ShuffleType: Swift::Hashable {
        case depthToSpaceNCHW
        case spaceToDepthNCHW
    }

    @available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
    public enum SparsityType: Swift::Hashable {
        case unstructured
    }

    @available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
    public struct SparseParameters {
        public init(type: Accelerate::BNNS.Accelerate::SparsityType = .unstructured, ratio: (numerator: Swift::UInt32, denominator: Swift::UInt32), targetSystem: Accelerate::BNNSTargetSystem) {
            self.type = type
            self.ratio = ratio
            self.targetSystem = targetSystem
        }
        public let type: Accelerate::BNNS.Accelerate::SparsityType
        public let ratio: (numerator: Swift::UInt32, denominator: Swift::UInt32)
        public let targetSystem: Accelerate::BNNSTargetSystem
    }

    @available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
    public enum SparseLayout {
        case coo(indices: Accelerate::BNNSNDArrayDescriptor)
        case csr(columnIndices: Accelerate::BNNSNDArrayDescriptor, rowStarts: Accelerate::BNNSNDArrayDescriptor)
    }
}

@available(macOS 12.0, iOS 15.0, tvOS 15.0, watchOS 8.0, *)
@available(*, deprecated, message: "Use the BNNSGraph API instead.")
extension Accelerate::BNNS.Accelerate::Norm: Swift::Sendable {}
@available(macOS 12.0, iOS 15.0, tvOS 15.0, watchOS 8.0, *)
@available(*, deprecated, message: "Use the BNNSGraph API instead.")
extension Accelerate::BNNS.Accelerate::Norm: Swift::BitwiseCopyable {}
@available(macOS 11.0, iOS 14.0, tvOS 14.0, watchOS 7.0, *)
@available(*, deprecated, message: "Use the BNNSGraph API instead.")
extension Accelerate::BNNS.Accelerate::LearningPhase: Swift::Sendable {}
@available(macOS 11.0, iOS 14.0, tvOS 14.0, watchOS 7.0, *)
@available(*, deprecated, message: "Use the BNNSGraph API instead.")
extension Accelerate::BNNS.Accelerate::LearningPhase: Swift::BitwiseCopyable {}
@available(macOS 11.0, iOS 14.0, tvOS 14.0, watchOS 7.0, *)
@available(*, deprecated, message: "Use the BNNSGraph API instead.")
extension Accelerate::BNNS.Accelerate::RelationalOperator: Swift::Sendable {}
@available(macOS 11.0, iOS 14.0, tvOS 14.0, watchOS 7.0, *)
@available(*, deprecated, message: "Use the BNNSGraph API instead.")
extension Accelerate::BNNS.Accelerate::RelationalOperator: Swift::BitwiseCopyable {}
