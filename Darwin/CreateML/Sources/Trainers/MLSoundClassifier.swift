// MLSoundClassifier: its parameters, data sources and options, which work in Perry,
// and its training, prediction and export, which need Apple's private
// engine and throw MLCreateError.generic saying so (see README.md). Its
// instance members are never reached: no instance can be made.

import CoreML
import Foundation
import TabularData

@available(macOS 10.15, iOS 15.0, *)
@available(tvOS, unavailable)
extension MLSoundClassifier {
    public struct ModelParameters {
        public var validation: MLSoundClassifier.ModelParameters.ValidationData
        public var maxIterations: Int
        public var overlapFactor: Double
        @available(macOS 11.0, iOS 15.0, *)
        @available(tvOS, unavailable)
        public var algorithm: MLSoundClassifier.ModelParameters.ModelAlgorithmType {
            get {
                _algorithm
            }
            set {
                _algorithm = newValue
            }
        }
        @available(macOS 12.0, iOS 15.0, *)
        @available(tvOS, unavailable)
        public var featureExtractionTimeWindowSize: TimeInterval {
            get {
                _featureExtractionTimeWindowSize
            }
            set {
                _featureExtractionTimeWindowSize = newValue
            }
        }
        @available(macOS 11.0, iOS 15.0, *)
        @available(tvOS, unavailable)
        public init(validation: MLSoundClassifier.ModelParameters.ValidationData = __Defaults.validation, maxIterations: Int = __Defaults.maximumIterations, overlapFactor: Double = __Defaults.overlapFactor, algorithm: MLSoundClassifier.ModelParameters.ModelAlgorithmType = __Defaults.algorithm) {
            self.validation = validation
            self.maxIterations = maxIterations
            self.overlapFactor = overlapFactor
            self.algorithm = algorithm
        }
        public init(validation: MLSoundClassifier.ModelParameters.ValidationData = .split(strategy: .automatic), maxIterations: Int = 25, overlapFactor: Double = 0.5) {
            self.validation = validation
            self.maxIterations = maxIterations
            self.overlapFactor = overlapFactor
        }
        @available(macOS 12.0, iOS 15.0, *)
        @available(tvOS, unavailable)
        public init(validation: MLSoundClassifier.ModelParameters.ValidationData = __Defaults.validation, maxIterations: Int = __Defaults.maximumIterations, overlapFactor: Double = __Defaults.overlapFactor, algorithm: MLSoundClassifier.ModelParameters.ModelAlgorithmType = __Defaults.algorithm, featureExtractionTimeWindowSize: TimeInterval = __Defaults.defaultVGGishTimeWindow) {
            self.validation = validation
            self.maxIterations = maxIterations
            self.overlapFactor = overlapFactor
            self.algorithm = algorithm
            self.featureExtractionTimeWindowSize = featureExtractionTimeWindowSize
        }
        @available(macOS 12.0, iOS 15.0, *)
        @available(tvOS, unavailable)
        public enum FeaturePrintType : Equatable, CustomStringConvertible, Sendable {
            case sound
            public var description: String {
                get {
                    switch self {
                    case .sound: return "sound"
                    }
                }
            }
        }
        var _algorithm: MLSoundClassifier.ModelParameters.ModelAlgorithmType = MLSoundClassifier.__Defaults.algorithm
        var _featureExtractionTimeWindowSize: TimeInterval = MLSoundClassifier.__Defaults.defaultVGGishTimeWindow
    }
}

@available(*, unavailable)
extension MLSoundClassifier.ModelParameters : Sendable {
}

@available(macOS 10.15, iOS 15.0, *)
@available(tvOS, unavailable)
extension MLSoundClassifier.ModelParameters : CustomStringConvertible {
    public var description: String {
        get {
            "ModelParameters(validation: \(String(describing: validation)), maxIterations: \(String(describing: maxIterations)), overlapFactor: \(String(describing: overlapFactor)), algorithm: \(String(describing: algorithm)), featureExtractionTimeWindowSize: \(String(describing: featureExtractionTimeWindowSize)))"
        }
    }
}

@available(macOS 10.15, iOS 15.0, *)
@available(tvOS, unavailable)
extension MLSoundClassifier.ModelParameters : CustomDebugStringConvertible {
    public var debugDescription: String {
        get {
            "ModelParameters(validation: \(String(describing: validation)), maxIterations: \(String(describing: maxIterations)), overlapFactor: \(String(describing: overlapFactor)), algorithm: \(String(describing: algorithm)), featureExtractionTimeWindowSize: \(String(describing: featureExtractionTimeWindowSize)))"
        }
    }
}

@available(macOS 10.15, iOS 15.0, *)
@available(tvOS, unavailable)
extension MLSoundClassifier.ModelParameters : CustomPlaygroundDisplayConvertible {
    public var playgroundDescription: Any {
        get {
            description
        }
    }
}

extension MLSoundClassifier.ModelParameters {
    @available(macOS 11.0, iOS 15.0, *)
    public enum ClassifierType : Equatable, Hashable, CustomStringConvertible, Sendable {
        case logisticRegressor
        @available(macOS 11.0, *)
        @available(iOS, unavailable)
        @available(tvOS, unavailable)
        case multilayerPerceptron(layerSizes: [Int])
        public var description: String {
            get {
                switch self {
                case .logisticRegressor: return "logisticRegressor"
                case .multilayerPerceptron(let v0): return "multilayerPerceptron(\(String(describing: v0)))"
                }
            }
        }
    }
}

extension MLSoundClassifier.ModelParameters {
    @available(macOS 11.0, iOS 15.0, *)
    @available(tvOS, unavailable)
    public enum FeatureExtractorType : Equatable, CustomStringConvertible, Sendable {
        case vggish(revision: Int = 1)
        @available(macOS 12.0, iOS 15.0, *)
        @available(tvOS, unavailable)
        case audioFeaturePrint(type: MLSoundClassifier.ModelParameters.FeaturePrintType = .sound, revision: Int = 1)
        public var description: String {
            get {
                switch self {
                case .vggish(let v0): return "vggish(\(String(describing: v0)))"
                case .audioFeaturePrint(let v0, let v1): return "audioFeaturePrint(\(String(describing: v0)), \(String(describing: v1)))"
                }
            }
        }
    }
}

@available(macOS 11.0, iOS 15.0, *)
@available(tvOS, unavailable)
extension MLSoundClassifier {
    @available(macOS 11.0, iOS 15.0, *)
    @available(tvOS, unavailable)
    public struct __Defaults : Sendable {
        public static var overlapFactor: Double { 0.5 }
        public static var batchSize: Int { 32 }
        public static var maximumIterations: Int { 25 }
        nonisolated(unsafe) public static var validation: MLSoundClassifier.ModelParameters.ValidationData { .split(strategy: .automatic) }
        @available(macOS 11.0, iOS 15.0, *)
        @available(tvOS, unavailable)
        public static var featureExtractor: MLSoundClassifier.ModelParameters.FeatureExtractorType {
            get {
                .audioFeaturePrint(type: .sound, revision: 1)
            }
        }
        @available(macOS 11.0, iOS 15.0, *)
        @available(tvOS, unavailable)
        public static var classifier: MLSoundClassifier.ModelParameters.ClassifierType { .logisticRegressor }
        @available(macOS 11.0, iOS 15.0, *)
        @available(tvOS, unavailable)
        public static var algorithm: MLSoundClassifier.ModelParameters.ModelAlgorithmType { .transferLearning(featureExtractor: .audioFeaturePrint(type: .sound, revision: 1), classifier: .logisticRegressor) }
        public static var featureColumnName: String { "features" }
        public static var labelColumnName: String { "label" }
        @available(macOS 12.0, iOS 15.0, *)
        @available(tvOS, unavailable)
        public static var defaultVGGishTimeWindow: Double { 0.975 }
    }
}

extension MLSoundClassifier.ModelParameters {
    @available(macOS 11.0, iOS 15.0, *)
    @available(tvOS, unavailable)
    public enum ModelAlgorithmType : Equatable, CustomStringConvertible, Sendable {
        case transferLearning(featureExtractor: MLSoundClassifier.ModelParameters.FeatureExtractorType, classifier: MLSoundClassifier.ModelParameters.ClassifierType)
        public var description: String {
            get {
                switch self {
                case .transferLearning(let v0, let v1): return "transferLearning(\(String(describing: v0)), \(String(describing: v1)))"
                }
            }
        }
    }
}

extension MLSoundClassifier.ModelParameters {
    @available(macOS 10.15, iOS 15.0, *)
    @available(tvOS, unavailable)
    public enum ValidationData {
        case split(strategy: MLSplitStrategy)
        @available(macOS 11.0, iOS 15.0, *)
        @available(tvOS, unavailable)
        case dataSource(MLSoundClassifier.DataSource)
        @available(macOS, introduced: 10.15, deprecated: 11.0, message: "Use DataSource.filesByLabel to provide dictionary validation data instead.")
        @available(iOS, introduced: 15.0, deprecated: 16.0, message: "Use DataSource.filesByLabel to provide dictionary validation data instead.")
        @available(tvOS, unavailable)
        case dictionary([String : [URL]])
        case none
    }
}

@available(*, unavailable)
extension MLSoundClassifier.ModelParameters.ValidationData : Sendable {
}

extension MLSoundClassifier {
    @available(macOS 11.0, iOS 15.0, *)
    @available(tvOS, unavailable)
    public struct FeatureExtractionParameters : Sendable {
        public var overlapFactor: Double
        @available(macOS 12.0, iOS 15.0, *)
        @available(tvOS, unavailable)
        public var featureExtractionTimeWindowSize: TimeInterval {
            get {
                _featureExtractionTimeWindowSize
            }
            set {
                _featureExtractionTimeWindowSize = newValue
            }
        }
        public var featureExtractor: MLSoundClassifier.ModelParameters.FeatureExtractorType
        public init(overlapFactor: Double = __Defaults.overlapFactor, featureExtractor: MLSoundClassifier.ModelParameters.FeatureExtractorType = __Defaults.featureExtractor) {
            self.overlapFactor = overlapFactor
            self.featureExtractor = featureExtractor
        }
        @available(macOS 12.0, iOS 15.0, *)
        @available(tvOS, unavailable)
        public init(overlapFactor: Double = __Defaults.overlapFactor, featureExtractor: MLSoundClassifier.ModelParameters.FeatureExtractorType = __Defaults.featureExtractor, featureExtractionTimeWindowSize: TimeInterval?) {
            self.overlapFactor = overlapFactor
            self.featureExtractor = featureExtractor
            self.featureExtractionTimeWindowSize = featureExtractionTimeWindowSize ?? MLSoundClassifier.__Defaults.defaultVGGishTimeWindow
        }
        var _featureExtractionTimeWindowSize: TimeInterval = MLSoundClassifier.__Defaults.defaultVGGishTimeWindow
    }
}

@available(macOS 10.15, iOS 15.0, *)
@available(tvOS, unavailable)
extension MLSoundClassifier {
    public enum DataSource {
        case labeledDirectories(at: URL)
        case labeledFiles(at: URL)
        @available(macOS 11.0, iOS 15.0, *)
        @available(tvOS, unavailable)
        case filesByLabel([String : [URL]])
        @available(macOS, introduced: 11.0, deprecated: 14.0)
        @available(iOS, introduced: 15.0, deprecated: 17.0)
        @available(tvOS, unavailable)
        case features(table: MLDataTable, featureColumn: String = __Defaults.featureColumnName, labelColumn: String = __Defaults.labelColumnName, parameters: MLSoundClassifier.FeatureExtractionParameters = FeatureExtractionParameters())
        @available(macOS 12.0, iOS 15.0, *)
        @available(tvOS, unavailable)
        case featuresDataFrame(DataFrame, featureColumn: String = __Defaults.featureColumnName, labelColumn: String = __Defaults.labelColumnName, parameters: MLSoundClassifier.FeatureExtractionParameters = FeatureExtractionParameters())
        public func labeledSounds() throws -> [String : [URL]] {
            try gatherLabeledSounds()
        }
        public func stratifiedSplit(proportions: [Double], seed: Int = timestampSeed()) throws -> [[String : [URL]]] {
            var generator = SeededGenerator(seed: seed)
            return try stratifiedSplit(proportions: proportions, generator: &generator)
        }
        public func stratifiedSplit<RNG>(proportions: [Double], generator: inout RNG) throws -> [[String : [URL]]] where RNG : RandomNumberGenerator {
            Examples.split(try gatherLabeledSounds(), proportions: proportions, generator: &generator)
        }
    }
}

@available(*, unavailable)
extension MLSoundClassifier.DataSource : Sendable {
}

@available(macOS 10.15, iOS 15.0, *)
@available(tvOS, unavailable)
public struct MLSoundClassifier : @unchecked Sendable {
    @available(macOS 11.0, iOS 15.0, *)
    @available(tvOS, unavailable)
    public static var _defaultSessionParameters: MLTrainingSessionParameters { MLTrainingSessionParameters() }
    public var model: MLModel {
        get {
            unreachableTrainer(Self.self)
        }
        set {
            _ = newValue
        }
    }
    public let modelParameters: MLSoundClassifier.ModelParameters
    public var trainingMetrics: MLClassifierMetrics {
        get {
            .init(error: trainingUnavailable(Self.self))
        }
    }
    public var validationMetrics: MLClassifierMetrics {
        get {
            .init(error: trainingUnavailable(Self.self))
        }
    }
    public init(trainingData: MLSoundClassifier.DataSource, parameters: MLSoundClassifier.ModelParameters = ModelParameters()) throws {
        throw trainingUnavailable(Self.self)
    }
    @available(macOS, introduced: 10.15, deprecated: 11.0, message: "Use DataSource.filesByLabel to provide dictionary training data instead.")
    @available(iOS, introduced: 15.0, deprecated: 16.0, message: "Use DataSource.filesByLabel to provide dictionary training data instead.")
    @available(tvOS, unavailable)
    public init(trainingData: [String : [URL]], parameters: MLSoundClassifier.ModelParameters = ModelParameters()) throws {
        throw trainingUnavailable(Self.self)
    }
    @available(macOS 11.0, iOS 15.0, *)
    @available(tvOS, unavailable)
    public init(checkpoint: MLCheckpoint) throws {
        throw trainingUnavailable(Self.self)
    }
    @available(macOS 11.0, iOS 15.0, *)
    @available(tvOS, unavailable)
    public static func train(trainingData: MLSoundClassifier.DataSource, parameters: MLSoundClassifier.ModelParameters = ModelParameters(), sessionParameters: MLTrainingSessionParameters = _defaultSessionParameters) throws -> MLJob<MLSoundClassifier> {
        throw trainingUnavailable(Self.self)
    }
    @available(macOS 11.0, iOS 15.0, *)
    @available(tvOS, unavailable)
    public static func train(trainingData: [String : [URL]], parameters: MLSoundClassifier.ModelParameters = .init(), sessionParameters: MLTrainingSessionParameters = _defaultSessionParameters) throws -> MLJob<MLSoundClassifier> {
        throw trainingUnavailable(Self.self)
    }
    @available(macOS 11.0, iOS 15.0, *)
    @available(tvOS, unavailable)
    public static func extractFeatures(trainingData: MLSoundClassifier.DataSource, parameters: MLSoundClassifier.FeatureExtractionParameters = FeatureExtractionParameters(), sessionParameters: MLTrainingSessionParameters = _defaultSessionParameters) throws -> MLJob<MLSoundClassifier.DataSource> {
        throw trainingUnavailable(Self.self)
    }
    @available(macOS 11.0, iOS 15.0, *)
    @available(tvOS, unavailable)
    public static func makeTrainingSession(trainingData: MLSoundClassifier.DataSource, parameters: MLSoundClassifier.ModelParameters = .init(), sessionParameters: MLTrainingSessionParameters = _defaultSessionParameters) throws -> MLTrainingSession<MLSoundClassifier> {
        throw trainingUnavailable(Self.self)
    }
    @available(macOS 11.0, iOS 15.0, *)
    @available(tvOS, unavailable)
    public static func restoreTrainingSession(sessionParameters: MLTrainingSessionParameters) throws -> MLTrainingSession<MLSoundClassifier> {
        throw trainingUnavailable(Self.self)
    }
    @available(macOS 11.0, iOS 15.0, *)
    @available(tvOS, unavailable)
    public static func resume(_ session: MLTrainingSession<MLSoundClassifier>) throws -> MLJob<MLSoundClassifier> {
        throw trainingUnavailable(Self.self)
    }
    public func evaluation(on testingData: MLSoundClassifier.DataSource) -> MLClassifierMetrics {
        .init(error: unavailable("Evaluating \(Self.self)"))
    }
    @available(macOS, introduced: 10.15, deprecated: 11.0, message: "Use DataSource.filesByLabel to provide dictionary testing data instead.")
    @available(iOS, introduced: 15.0, deprecated: 16.0, message: "Use DataSource.filesByLabel to provide dictionary testing data instead.")
    @available(tvOS, unavailable)
    public func evaluation(on testingData: [String : [URL]]) -> MLClassifierMetrics {
        .init(error: unavailable("Evaluating \(Self.self)"))
    }
    public func write(to fileURL: URL, metadata: MLModelMetadata? = nil) throws {
        throw unavailable("Exporting \(Self.self)")
    }
    public func write(toFile path: String, metadata: MLModelMetadata? = nil) throws {
        throw unavailable("Exporting \(Self.self)")
    }
    public func predictions(from audioFiles: [URL]) throws -> [String] {
        throw unavailable("Running \(Self.self)")
    }
    @available(macOS 12.0, iOS 15.0, *)
    @available(tvOS, unavailable)
    public func predictions(from audioFiles: [URL], overlapFactor: Double, predictionTimeWindowSize: TimeInterval) throws -> [String] {
        throw unavailable("Running \(Self.self)")
    }
}

@available(macOS 10.15, iOS 15.0, *)
@available(tvOS, unavailable)
extension MLSoundClassifier : CustomStringConvertible {
    public var description: String {
        get {
            "\(Self.self): not trained. \(trainingUnavailable(Self.self).failureReason ?? "")"
        }
    }
}

@available(macOS 10.15, iOS 15.0, *)
@available(tvOS, unavailable)
extension MLSoundClassifier : CustomDebugStringConvertible {
    public var debugDescription: String {
        get {
            "\(Self.self): not trained. \(trainingUnavailable(Self.self).failureReason ?? "")"
        }
    }
}

@available(macOS 10.15, iOS 15.0, *)
@available(tvOS, unavailable)
extension MLSoundClassifier : CustomPlaygroundDisplayConvertible {
    public var playgroundDescription: Any {
        get {
            description
        }
    }
}

@available(macOS 12.0, iOS 15.0, *)
@available(tvOS, unavailable)
extension MLSoundClassifier.ModelParameters.FeaturePrintType : Hashable {}
