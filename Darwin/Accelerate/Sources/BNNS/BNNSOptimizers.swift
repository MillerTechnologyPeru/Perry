import Swift
import Darwin

// BNNS's optimizers: each keeps the C "with clipping" fields struct of its
// algorithm and steps with BNNSOptimizerStep.

@available(macOS 11.0, iOS 14.0, tvOS 14.0, watchOS 7.0, *)
@available(*, deprecated, message: "Use the BNNSGraph API instead.")
public protocol BNNSOptimizer {
    func step(parameters: [Accelerate::BNNSNDArrayDescriptor], gradients: [Accelerate::BNNSNDArrayDescriptor], accumulators: [Accelerate::BNNSNDArrayDescriptor], filterParameters: Accelerate::BNNSFilterParameters?) throws
    var bnnsOptimizerFunction: Accelerate::BNNSOptimizerFunction { get }
    var accumulatorCountMultiplier: Swift::Int { get }
}

/// An optimizer whose C fields the default step passes.
protocol _BNNSOptimizerFields {
    func _withFields<R>(_ body: (UnsafeRawPointer) throws -> R) rethrows -> R
}

@available(macOS 11.0, iOS 14.0, tvOS 14.0, watchOS 7.0, *)
@available(*, deprecated, message: "Use the BNNSGraph API instead.")
extension Accelerate::BNNSOptimizer {
    public func step(parameters: [Accelerate::BNNSNDArrayDescriptor], gradients: [Accelerate::BNNSNDArrayDescriptor], accumulators: [Accelerate::BNNSNDArrayDescriptor], filterParameters: Accelerate::BNNSFilterParameters? = nil) throws {
        guard let fields = self as? any _BNNSOptimizerFields,
              parameters.count == gradients.count,
              accumulators.count >= parameters.count * accumulatorCountMultiplier else { throw BNNS.Error.optimizerStepFail }
        let function = bnnsOptimizerFunction
        try fields._withFields { fieldsPointer in
            try _withDescriptorPointers(parameters.map { Optional($0) }) { params in
                try _withDescriptorPointers(gradients.map { Optional($0) }) { grads in
                    try _withDescriptorPointers(accumulators.map { Optional($0) }) { accs in
                        var params = params.map { $0! }
                        var grads = grads.map { UnsafePointer($0!) }
                        var accs = accs
                        try _withFilterParameters(filterParameters) { fp in
                            let status = accs.isEmpty
                                ? BNNSOptimizerStep(function, fieldsPointer, params.count, &params, &grads, nil, fp)
                                : BNNSOptimizerStep(function, fieldsPointer, params.count, &params, &grads, &accs, fp)
                            try _check(status, .optimizerStepFail)
                        }
                    }
                }
            }
        }
    }
}

// Clipping functions: none 0, by value 1, by norm 2, by global norm 3.

@available(macOS 12.0, iOS 15.0, tvOS 15.0, watchOS 8.0, *)
func _clipping(_ function: BNNSOptimizerClippingFunction, _ min: Float, _ max: Float, _ maxNorm: Float, _ useNorm: Float) -> BNNS.GradientClipping {
    switch function.rawValue {
    case 1: return .byValue(bounds: min...Swift.max(min, max))
    case 2: return .byNorm(threshold: maxNorm)
    case 3: return .byGlobalNorm(threshold: maxNorm, globalNorm: useNorm)
    default: return .none
    }
}

@available(macOS 12.0, iOS 15.0, tvOS 15.0, watchOS 8.0, *)
func _clippingFields(_ clipping: BNNS.GradientClipping) -> (function: BNNSOptimizerClippingFunction, min: Float, max: Float, maxNorm: Float, useNorm: Float) {
    switch clipping {
    case .none: return (BNNSOptimizerClippingFunction(rawValue: 0), 0, 0, 0, 0)
    case let .byValue(bounds): return (BNNSOptimizerClippingFunction(rawValue: 1), bounds.lowerBound, bounds.upperBound, 0, 0)
    case let .byNorm(threshold): return (BNNSOptimizerClippingFunction(rawValue: 2), 0, 0, threshold, 0)
    case let .byGlobalNorm(threshold, globalNorm): return (BNNSOptimizerClippingFunction(rawValue: 3), 0, 0, threshold, globalNorm)
    }
}

func _bounds(_ function: BNNSOptimizerClippingFunction, _ min: Float, _ max: Float) -> ClosedRange<Float>? {
    function.rawValue == 1 ? min...Swift.max(min, max) : nil
}

@available(macOS 11.0, iOS 14.0, tvOS 14.0, watchOS 7.0, *)
@available(*, deprecated, message: "Use the BNNSGraph API instead.")
extension Accelerate::BNNS {
    public struct AdamOptimizer: Accelerate::BNNSOptimizer, _BNNSOptimizerFields {
        var fields: BNNSOptimizerAdamWithClippingFields
        var amsGrad = false

        public var accumulatorCountMultiplier: Swift::Int { amsGrad ? 3 : 2 }

        public var learningRate: Swift::Float {
            get { fields.learning_rate }
            set { fields.learning_rate = newValue }
        }
        public var beta1: Swift::Float {
            get { fields.beta1 }
            set { fields.beta1 = newValue }
        }
        public var beta2: Swift::Float {
            get { fields.beta2 }
            set { fields.beta2 = newValue }
        }
        public var timeStep: Swift::Float {
            get { fields.time_step }
            set { fields.time_step = newValue }
        }
        public var epsilon: Swift::Float {
            get { fields.epsilon }
            set { fields.epsilon = newValue }
        }
        public var gradientScale: Swift::Float {
            get { fields.gradient_scale }
            set { fields.gradient_scale = newValue }
        }
        public var regularizationScale: Swift::Float {
            get { fields.regularization_scale }
            set { fields.regularization_scale = newValue }
        }
        public var gradientBounds: Swift::ClosedRange<Swift::Float>? {
            get { _bounds(fields.clipping_func, fields.clip_gradients_min, fields.clip_gradients_max) }
            set {
                fields.clipping_func = BNNSOptimizerClippingFunction(rawValue: newValue == nil ? 0 : 1)
                fields.clip_gradients_min = newValue?.lowerBound ?? 0
                fields.clip_gradients_max = newValue?.upperBound ?? 0
            }
        }
        public var regularizationFunction: Accelerate::BNNSOptimizerRegularizationFunction {
            get { fields.regularization_func }
            set { fields.regularization_func = newValue }
        }

        public init(learningRate: Swift::Float, beta1: Swift::Float, beta2: Swift::Float, timeStep: Swift::Float, epsilon: Swift::Float, gradientScale: Swift::Float, regularizationScale: Swift::Float, clipsGradientsTo gradientBounds: Swift::ClosedRange<Swift::Float>? = nil, regularizationFunction: Accelerate::BNNSOptimizerRegularizationFunction) {
            fields = BNNSOptimizerAdamWithClippingFields(learning_rate: learningRate, beta1: beta1, beta2: beta2, time_step: timeStep, epsilon: epsilon,
                                                         gradient_scale: gradientScale, regularization_scale: regularizationScale,
                                                         regularization_func: regularizationFunction, clipping_func: BNNSOptimizerClippingFunction(rawValue: 0),
                                                         clip_gradients_min: 0, clip_gradients_max: 0, clip_gradients_max_norm: 0, clip_gradients_use_norm: 0)
            self.gradientBounds = gradientBounds
        }

        public var bnnsOptimizerFunction: Accelerate::BNNSOptimizerFunction {
            BNNSOptimizerFunction(rawValue: amsGrad ? 11 : 8)
        }

        func _withFields<R>(_ body: (UnsafeRawPointer) throws -> R) rethrows -> R {
            var fields = fields
            return try withUnsafePointer(to: &fields) { try body(UnsafeRawPointer($0)) }
        }
    }

    public struct RMSPropOptimizer: Accelerate::BNNSOptimizer, _BNNSOptimizerFields {
        var fields: BNNSOptimizerRMSPropWithClippingFields

        /// One accumulator, one more when centered, one more with momentum.
        public var accumulatorCountMultiplier: Swift::Int {
            1 + (fields.centered ? 1 : 0) + (fields.momentum != 0 ? 1 : 0)
        }

        public var learningRate: Swift::Float {
            get { fields.learning_rate }
            set { fields.learning_rate = newValue }
        }
        public var alpha: Swift::Float {
            get { fields.alpha }
            set { fields.alpha = newValue }
        }
        public var epsilon: Swift::Float {
            get { fields.epsilon }
            set { fields.epsilon = newValue }
        }
        public var centered: Swift::Bool {
            get { fields.centered }
            set { fields.centered = newValue }
        }
        public var momentum: Swift::Float {
            get { fields.momentum }
            set { fields.momentum = newValue }
        }
        public var gradientScale: Swift::Float {
            get { fields.gradient_scale }
            set { fields.gradient_scale = newValue }
        }
        public var regularizationScale: Swift::Float {
            get { fields.regularization_scale }
            set { fields.regularization_scale = newValue }
        }
        public var gradientBounds: Swift::ClosedRange<Swift::Float>? {
            get { _bounds(fields.clipping_func, fields.clip_gradients_min, fields.clip_gradients_max) }
            set {
                fields.clipping_func = BNNSOptimizerClippingFunction(rawValue: newValue == nil ? 0 : 1)
                fields.clip_gradients_min = newValue?.lowerBound ?? 0
                fields.clip_gradients_max = newValue?.upperBound ?? 0
            }
        }
        public var regularizationFunction: Accelerate::BNNSOptimizerRegularizationFunction {
            get { fields.regularization_func }
            set { fields.regularization_func = newValue }
        }

        public init(learningRate: Swift::Float, alpha: Swift::Float, epsilon: Swift::Float, centered: Swift::Bool, momentum: Swift::Float, gradientScale: Swift::Float, regularizationScale: Swift::Float, clipsGradientsTo gradientBounds: Swift::ClosedRange<Swift::Float>? = nil, regularizationFunction: Accelerate::BNNSOptimizerRegularizationFunction) {
            fields = BNNSOptimizerRMSPropWithClippingFields(learning_rate: learningRate, alpha: alpha, epsilon: epsilon, centered: centered, momentum: momentum,
                                                            gradient_scale: gradientScale, regularization_scale: regularizationScale,
                                                            regularization_func: regularizationFunction, clipping_func: BNNSOptimizerClippingFunction(rawValue: 0),
                                                            clip_gradients_min: 0, clip_gradients_max: 0, clip_gradients_max_norm: 0, clip_gradients_use_norm: 0)
            self.gradientBounds = gradientBounds
        }

        public var bnnsOptimizerFunction: Accelerate::BNNSOptimizerFunction { BNNSOptimizerFunction(rawValue: 9) }

        func _withFields<R>(_ body: (UnsafeRawPointer) throws -> R) rethrows -> R {
            var fields = fields
            return try withUnsafePointer(to: &fields) { try body(UnsafeRawPointer($0)) }
        }
    }

    public struct SGDMomentumOptimizer: Accelerate::BNNSOptimizer, _BNNSOptimizerFields {
        var fields: BNNSOptimizerSGDMomentumWithClippingFields

        /// One accumulator with momentum, none without.
        public var accumulatorCountMultiplier: Swift::Int { fields.momentum != 0 ? 1 : 0 }

        public var learningRate: Swift::Float {
            get { fields.learning_rate }
            set { fields.learning_rate = newValue }
        }
        public var momentum: Swift::Float {
            get { fields.momentum }
            set { fields.momentum = newValue }
        }
        public var gradientScale: Swift::Float {
            get { fields.gradient_scale }
            set { fields.gradient_scale = newValue }
        }
        public var regularizationScale: Swift::Float {
            get { fields.regularization_scale }
            set { fields.regularization_scale = newValue }
        }
        public var gradientBounds: Swift::ClosedRange<Swift::Float>? {
            get { _bounds(fields.clipping_func, fields.clip_gradients_min, fields.clip_gradients_max) }
            set {
                fields.clipping_func = BNNSOptimizerClippingFunction(rawValue: newValue == nil ? 0 : 1)
                fields.clip_gradients_min = newValue?.lowerBound ?? 0
                fields.clip_gradients_max = newValue?.upperBound ?? 0
            }
        }
        @available(macOS, introduced: 11.0, deprecated: 12.0, renamed: "getter:usesNesterovMomentum(self:)")
        @available(iOS, introduced: 14.0, deprecated: 15.0, renamed: "getter:usesNesterovMomentum(self:)")
        @available(tvOS, introduced: 14.0, deprecated: 15.0, renamed: "getter:usesNesterovMomentum(self:)")
        @available(watchOS, introduced: 7.0, deprecated: 8.0, renamed: "getter:usesNesterovMomentum(self:)")
        @available(*, deprecated, renamed: "getter:usesNesterovMomentum(self:)")
        public var usesNestrovMomentum: Swift::Bool {
            get { fields.nesterov }
            set { fields.nesterov = newValue }
        }
        @available(macOS 12.0, iOS 15.0, tvOS 15.0, watchOS 8.0, *)
        public var usesNesterovMomentum: Swift::Bool {
            get { fields.nesterov }
            set { fields.nesterov = newValue }
        }
        public var regularizationFunction: Accelerate::BNNSOptimizerRegularizationFunction {
            get { fields.regularization_func }
            set { fields.regularization_func = newValue }
        }
        public var sgdMomentumVariant: Accelerate::BNNSOptimizerSGDMomentumVariant {
            get { fields.sgd_momentum_variant }
            set { fields.sgd_momentum_variant = newValue }
        }

        @available(macOS, introduced: 11.0, deprecated: 12.0, renamed: "init(learningRate:momentum:gradientScale:regularizationScale:clipsGradientsTo:usesNesterovMomentum:regularizationFunction:sgdMomentumVariant:)")
        @available(iOS, introduced: 14.0, deprecated: 15.0, renamed: "init(learningRate:momentum:gradientScale:regularizationScale:clipsGradientsTo:usesNesterovMomentum:regularizationFunction:sgdMomentumVariant:)")
        @available(tvOS, introduced: 14.0, deprecated: 15.0, renamed: "init(learningRate:momentum:gradientScale:regularizationScale:clipsGradientsTo:usesNesterovMomentum:regularizationFunction:sgdMomentumVariant:)")
        @available(watchOS, introduced: 7.0, deprecated: 8.0, renamed: "init(learningRate:momentum:gradientScale:regularizationScale:clipsGradientsTo:usesNesterovMomentum:regularizationFunction:sgdMomentumVariant:)")
        @available(*, deprecated, renamed: "init(learningRate:momentum:gradientScale:regularizationScale:clipsGradientsTo:usesNesterovMomentum:regularizationFunction:sgdMomentumVariant:)")
        public init(learningRate: Swift::Float, momentum: Swift::Float, gradientScale: Swift::Float, regularizationScale: Swift::Float, clipsGradientsTo gradientBounds: Swift::ClosedRange<Swift::Float>? = nil, usesNestrovMomentum: Swift::Bool, regularizationFunction: Accelerate::BNNSOptimizerRegularizationFunction, sgdMomentumVariant: Accelerate::BNNSOptimizerSGDMomentumVariant) {
            self.init(learningRate: learningRate, momentum: momentum, gradientScale: gradientScale, regularizationScale: regularizationScale,
                      clipsGradientsTo: gradientBounds, usesNesterovMomentum: usesNestrovMomentum, regularizationFunction: regularizationFunction,
                      sgdMomentumVariant: sgdMomentumVariant)
        }

        @available(macOS 12.0, iOS 15.0, tvOS 15.0, watchOS 8.0, *)
        public init(learningRate: Swift::Float, momentum: Swift::Float, gradientScale: Swift::Float, regularizationScale: Swift::Float, clipsGradientsTo gradientBounds: Swift::ClosedRange<Swift::Float>? = nil, usesNesterovMomentum: Swift::Bool, regularizationFunction: Accelerate::BNNSOptimizerRegularizationFunction, sgdMomentumVariant: Accelerate::BNNSOptimizerSGDMomentumVariant) {
            fields = BNNSOptimizerSGDMomentumWithClippingFields(learning_rate: learningRate, momentum: momentum, gradient_scale: gradientScale,
                                                                regularization_scale: regularizationScale, nesterov: usesNesterovMomentum,
                                                                regularization_func: regularizationFunction, sgd_momentum_variant: sgdMomentumVariant,
                                                                clipping_func: BNNSOptimizerClippingFunction(rawValue: 0),
                                                                clip_gradients_min: 0, clip_gradients_max: 0, clip_gradients_max_norm: 0, clip_gradients_use_norm: 0)
            self.gradientBounds = gradientBounds
        }

        public var bnnsOptimizerFunction: Accelerate::BNNSOptimizerFunction { BNNSOptimizerFunction(rawValue: 7) }

        func _withFields<R>(_ body: (UnsafeRawPointer) throws -> R) rethrows -> R {
            var fields = fields
            return try withUnsafePointer(to: &fields) { try body(UnsafeRawPointer($0)) }
        }
    }
}

@available(macOS 12.0, iOS 15.0, tvOS 15.0, watchOS 8.0, *)
@available(*, deprecated, message: "Use the BNNSGraph API instead.")
extension Accelerate::BNNS {
    /// Adam with decoupled weight decay (the C fields' regularization scale).
    public struct AdamWOptimizer: Accelerate::BNNSOptimizer, _BNNSOptimizerFields {
        var fields: BNNSOptimizerAdamWithClippingFields
        var amsGrad: Bool

        public var accumulatorCountMultiplier: Swift::Int { amsGrad ? 3 : 2 }

        public var learningRate: Swift::Float {
            get { fields.learning_rate }
            set { fields.learning_rate = newValue }
        }
        public var beta1: Swift::Float {
            get { fields.beta1 }
            set { fields.beta1 = newValue }
        }
        public var beta2: Swift::Float {
            get { fields.beta2 }
            set { fields.beta2 = newValue }
        }
        public var timeStep: Swift::Float {
            get { fields.time_step }
            set { fields.time_step = newValue }
        }
        public var epsilon: Swift::Float {
            get { fields.epsilon }
            set { fields.epsilon = newValue }
        }
        public var gradientScale: Swift::Float {
            get { fields.gradient_scale }
            set { fields.gradient_scale = newValue }
        }
        public var weightDecay: Swift::Float {
            get { fields.regularization_scale }
            set { fields.regularization_scale = newValue }
        }
        public var gradientClipping: Accelerate::BNNS.Accelerate::GradientClipping {
            get { _clipping(fields.clipping_func, fields.clip_gradients_min, fields.clip_gradients_max, fields.clip_gradients_max_norm, fields.clip_gradients_use_norm) }
            set {
                let c = _clippingFields(newValue)
                fields.clipping_func = c.function
                fields.clip_gradients_min = c.min
                fields.clip_gradients_max = c.max
                fields.clip_gradients_max_norm = c.maxNorm
                fields.clip_gradients_use_norm = c.useNorm
            }
        }

        public init(learningRate: Swift::Float = 0.001, beta1: Swift::Float = 0.9, beta2: Swift::Float = 0.999, timeStep: Swift::Float = 1, epsilon: Swift::Float = 1e-8, gradientScale: Swift::Float, weightDecay: Swift::Float = 1e-2, gradientClipping: Accelerate::BNNS.Accelerate::GradientClipping, usesAMSGrad: Swift::Bool = false) {
            fields = BNNSOptimizerAdamWithClippingFields(learning_rate: learningRate, beta1: beta1, beta2: beta2, time_step: timeStep, epsilon: epsilon,
                                                         gradient_scale: gradientScale, regularization_scale: weightDecay,
                                                         regularization_func: BNNSOptimizerRegularizationFunction(rawValue: 0),
                                                         clipping_func: BNNSOptimizerClippingFunction(rawValue: 0),
                                                         clip_gradients_min: 0, clip_gradients_max: 0, clip_gradients_max_norm: 0, clip_gradients_use_norm: 0)
            amsGrad = usesAMSGrad
            self.gradientClipping = gradientClipping
        }

        public var bnnsOptimizerFunction: Accelerate::BNNSOptimizerFunction {
            BNNSOptimizerFunction(rawValue: amsGrad ? 12 : 10)
        }

        func _withFields<R>(_ body: (UnsafeRawPointer) throws -> R) rethrows -> R {
            var fields = fields
            return try withUnsafePointer(to: &fields) { try body(UnsafeRawPointer($0)) }
        }
    }
}

@available(macOS 12.0, iOS 15.0, tvOS 15.0, watchOS 8.0, *)
@available(*, deprecated, message: "Use the BNNSGraph API instead.")
extension Accelerate::BNNS.Accelerate::AdamOptimizer {
    public init(learningRate: Swift::Float = 0.001, beta1: Swift::Float = 0.9, beta2: Swift::Float = 0.999, timeStep: Swift::Float, epsilon: Swift::Float = 1e-8, gradientScale: Swift::Float, regularizationScale: Swift::Float, gradientClipping: Accelerate::BNNS.Accelerate::GradientClipping, regularizationFunction: Accelerate::BNNSOptimizerRegularizationFunction, usesAMSGrad: Swift::Bool = false) {
        self.init(learningRate: learningRate, beta1: beta1, beta2: beta2, timeStep: timeStep, epsilon: epsilon, gradientScale: gradientScale,
                  regularizationScale: regularizationScale, clipsGradientsTo: nil, regularizationFunction: regularizationFunction)
        self.gradientClipping = gradientClipping
        self.usesAMSGrad = usesAMSGrad
    }

    public var usesAMSGrad: Swift::Bool {
        get { amsGrad }
        set { amsGrad = newValue }
    }

    public var gradientClipping: Accelerate::BNNS.Accelerate::GradientClipping {
        get { _clipping(fields.clipping_func, fields.clip_gradients_min, fields.clip_gradients_max, fields.clip_gradients_max_norm, fields.clip_gradients_use_norm) }
        set {
            let c = _clippingFields(newValue)
            fields.clipping_func = c.function
            fields.clip_gradients_min = c.min
            fields.clip_gradients_max = c.max
            fields.clip_gradients_max_norm = c.maxNorm
            fields.clip_gradients_use_norm = c.useNorm
        }
    }
}

@available(macOS 12.0, iOS 15.0, tvOS 15.0, watchOS 8.0, *)
extension Accelerate::BNNS.Accelerate::SGDMomentumOptimizer {
    public init(learningRate: Swift::Float, momentum: Swift::Float = 0, gradientScale: Swift::Float, regularizationScale: Swift::Float, gradientClipping: Accelerate::BNNS.Accelerate::GradientClipping, usesNesterovMomentum: Swift::Bool = false, regularizationFunction: Accelerate::BNNSOptimizerRegularizationFunction, sgdMomentumVariant: Accelerate::BNNSOptimizerSGDMomentumVariant) {
        self.init(learningRate: learningRate, momentum: momentum, gradientScale: gradientScale, regularizationScale: regularizationScale,
                  clipsGradientsTo: nil, usesNesterovMomentum: usesNesterovMomentum, regularizationFunction: regularizationFunction,
                  sgdMomentumVariant: sgdMomentumVariant)
        self.gradientClipping = gradientClipping
    }

    public var gradientClipping: Accelerate::BNNS.Accelerate::GradientClipping {
        get { _clipping(fields.clipping_func, fields.clip_gradients_min, fields.clip_gradients_max, fields.clip_gradients_max_norm, fields.clip_gradients_use_norm) }
        set {
            let c = _clippingFields(newValue)
            fields.clipping_func = c.function
            fields.clip_gradients_min = c.min
            fields.clip_gradients_max = c.max
            fields.clip_gradients_max_norm = c.maxNorm
            fields.clip_gradients_use_norm = c.useNorm
        }
    }
}

@available(macOS 12.0, iOS 15.0, tvOS 15.0, watchOS 8.0, *)
extension Accelerate::BNNS.Accelerate::RMSPropOptimizer {
    public init(learningRate: Swift::Float = 1e-2, alpha: Swift::Float = 0.99, epsilon: Swift::Float = 1e-8, centered: Swift::Bool, momentum: Swift::Float = 0, gradientScale: Swift::Float, regularizationScale: Swift::Float, gradientClipping: Accelerate::BNNS.Accelerate::GradientClipping, regularizationFunction: Accelerate::BNNSOptimizerRegularizationFunction) {
        self.init(learningRate: learningRate, alpha: alpha, epsilon: epsilon, centered: centered, momentum: momentum, gradientScale: gradientScale,
                  regularizationScale: regularizationScale, clipsGradientsTo: nil, regularizationFunction: regularizationFunction)
        self.gradientClipping = gradientClipping
    }

    public var gradientClipping: Accelerate::BNNS.Accelerate::GradientClipping {
        get { _clipping(fields.clipping_func, fields.clip_gradients_min, fields.clip_gradients_max, fields.clip_gradients_max_norm, fields.clip_gradients_use_norm) }
        set {
            let c = _clippingFields(newValue)
            fields.clipping_func = c.function
            fields.clip_gradients_min = c.min
            fields.clip_gradients_max = c.max
            fields.clip_gradients_max_norm = c.maxNorm
            fields.clip_gradients_use_norm = c.useNorm
        }
    }
}
