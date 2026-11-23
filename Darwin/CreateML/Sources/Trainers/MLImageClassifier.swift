// MLImageClassifier: its parameters, data sources and options, which work in Perry,
// and its training, prediction and export, which need Apple's private
// engine and throw MLCreateError.generic saying so (see README.md). Its
// instance members are never reached: no instance can be made.

import CoreGraphics
import CoreML
import Foundation

extension MLImageClassifier {
    @available(macOS 10.14, iOS 15.0, *)
    @available(tvOS, unavailable)
    public enum FeatureExtractorType : Sendable {
        case scenePrint(revision: Int?)
        @available(macOS 10.15, iOS 15.0, *)
        @available(tvOS, unavailable)
        case custom(MLImageClassifier.CustomFeatureExtractor)
    }
    @available(macOS 10.15, iOS 15.0, *)
    @available(tvOS, unavailable)
    public struct CustomFeatureExtractor : Sendable {
        public var modelPath: URL
        public var outputName: String?
        public init(modelPath: URL, outputName: String? = nil) {
            self.modelPath = modelPath
            self.outputName = outputName
        }
    }
}

@available(macOS 10.14, iOS 15.0, *)
@available(tvOS, unavailable)
extension MLImageClassifier.FeatureExtractorType : CustomStringConvertible, CustomDebugStringConvertible, CustomPlaygroundDisplayConvertible {
    public var description: String {
        get {
            switch self {
            case .scenePrint(let v0): return "scenePrint(\(String(describing: v0)))"
            case .custom(let v0): return "custom(\(String(describing: v0)))"
            }
        }
    }
    public var debugDescription: String {
        get {
            switch self {
            case .scenePrint(let v0): return "scenePrint(\(String(describing: v0)))"
            case .custom(let v0): return "custom(\(String(describing: v0)))"
            }
        }
    }
    public var playgroundDescription: Any {
        get {
            description
        }
    }
}

extension MLImageClassifier.ModelParameters {
    @available(macOS 10.15, iOS 15.0, *)
    @available(tvOS, unavailable)
    public enum ValidationData : Sendable {
        case split(strategy: MLSplitStrategy)
        case dataSource(MLImageClassifier.DataSource)
        @available(macOS, introduced: 10.15, deprecated: 11.0, message: "Use DataSource.filesByLabel to provide dictionary validation data instead.")
        @available(iOS, introduced: 15.0, deprecated: 16.0, message: "Use DataSource.filesByLabel to provide dictionary validation data instead.")
        @available(tvOS, unavailable)
        case dictionary([String : [URL]])
        case none
    }
}

@available(macOS 10.14, iOS 15.0, *)
@available(tvOS, unavailable)
extension MLImageClassifier {
    public struct ModelParameters {
        public var maxIterations: Int
        public var augmentationOptions: MLImageClassifier.ImageAugmentationOptions
        @available(macOS 11.0, iOS 15.0, *)
        @available(tvOS, unavailable)
        public var algorithm: MLImageClassifier.ModelParameters.ModelAlgorithmType {
            get {
                _algorithm
            }
            set {
                _algorithm = newValue
            }
        }
        @available(macOS, introduced: 10.14, deprecated: 10.15, message: "Use the validation property instead.")
        @available(iOS, introduced: 15.0, deprecated: 16.0, message: "Use the validation property instead.")
        @available(tvOS, unavailable)
        public var validationData: [String : [URL]]? {
            get {
                switch validation {
                case .dictionary(let files): return files
                case .dataSource(let source): return try? source.labeledImages()
                default: return nil
                }
            }
            set {
                validation = newValue.map { .dictionary($0) } ?? .none
            }
        }
        @available(macOS 10.15, iOS 15.0, *)
        @available(tvOS, unavailable)
        public var validation: MLImageClassifier.ModelParameters.ValidationData {
            get {
                _validation
            }
            set {
                _validation = newValue
            }
        }
        @available(macOS, introduced: 10.14, deprecated: 11.0, message: "Use featureExtractor in ModelAlgorithmType instead.")
        @available(iOS, introduced: 15.0, deprecated: 16.0, message: "Use featureExtractor in ModelAlgorithmType instead.")
        @available(tvOS, unavailable)
        public var featureExtractor: MLImageClassifier.FeatureExtractorType {
            get {
                if case .transferLearning(let featureExtractor, _) = algorithm { return featureExtractor }
                return .scenePrint(revision: 1)
            }
            set {
                if case .transferLearning(_, let classifier) = algorithm {
                    algorithm = .transferLearning(featureExtractor: newValue, classifier: classifier)
                }
            }
        }
        @available(macOS 11.0, iOS 15.0, *)
        @available(tvOS, unavailable)
        public init(validation: MLImageClassifier.ModelParameters.ValidationData = __Defaults.validation, maxIterations: Int = __Defaults.maximumIterations, augmentation: MLImageClassifier.ImageAugmentationOptions, algorithm: MLImageClassifier.ModelParameters.ModelAlgorithmType = __Defaults.algorithm) {
            self.maxIterations = maxIterations
            self.augmentationOptions = augmentation
            self.validation = validation
            self.algorithm = algorithm
        }
        @available(macOS, introduced: 10.15, deprecated: 11.0, message: "Use featureExtractor in ModelAlgorithm Type instead.")
        @available(iOS, introduced: 15.0, deprecated: 16.0, message: "Use featureExtractor in ModelAlgorithm Type instead.")
        @available(tvOS, unavailable)
        public init(featureExtractor: MLImageClassifier.FeatureExtractorType = .scenePrint(revision: 1), validation: MLImageClassifier.ModelParameters.ValidationData = .split(strategy: .automatic), maxIterations: Int = 25, augmentationOptions: MLImageClassifier.ImageAugmentationOptions = []) {
            self.maxIterations = maxIterations
            self.augmentationOptions = augmentationOptions
            self.featureExtractor = featureExtractor
            self.validation = validation
        }
        @available(macOS, introduced: 10.14, deprecated: 10.15, message: "Use the validation property instead.")
        @available(iOS, introduced: 15.0, deprecated: 16.0, message: "Use the validation property instead.")
        @available(tvOS, unavailable)
        public init(featureExtractor: MLImageClassifier.FeatureExtractorType = .scenePrint(revision: 1), validationData: [String : [URL]]?, maxIterations: Int = 25, augmentationOptions: MLImageClassifier.ImageAugmentationOptions = []) {
            self.maxIterations = maxIterations
            self.augmentationOptions = augmentationOptions
            self.featureExtractor = featureExtractor
            self.validationData = validationData
        }
        @available(macOS, introduced: 10.14, deprecated: 10.15, message: "Use the validation property instead.")
        @available(iOS, introduced: 15.0, deprecated: 16.0, message: "Use the validation property instead.")
        @available(tvOS, unavailable)
        public init(featureExtractor: MLImageClassifier.FeatureExtractorType = .scenePrint(revision: 1), validationData: MLImageClassifier.DataSource, maxIterations: Int = 25, augmentationOptions: MLImageClassifier.ImageAugmentationOptions = []) {
            self.maxIterations = maxIterations
            self.augmentationOptions = augmentationOptions
            self.featureExtractor = featureExtractor
            self.validation = .dataSource(validationData)
        }
        var _algorithm: MLImageClassifier.ModelParameters.ModelAlgorithmType = .transferLearning(featureExtractor: .scenePrint(revision: 1), classifier: .logisticRegressor)
        var _validation: MLImageClassifier.ModelParameters.ValidationData = .split(strategy: .automatic)
    }
}

@available(*, unavailable)
extension MLImageClassifier.ModelParameters : Sendable {
}

@available(macOS 10.14, iOS 15.0, *)
@available(tvOS, unavailable)
extension MLImageClassifier.ModelParameters : CustomStringConvertible, CustomDebugStringConvertible, CustomPlaygroundDisplayConvertible {
    public var description: String {
        get {
            "ModelParameters(maxIterations: \(String(describing: maxIterations)), augmentationOptions: \(String(describing: augmentationOptions)), algorithm: \(String(describing: algorithm)), validationData: \(String(describing: validationData)), validation: \(String(describing: validation)), featureExtractor: \(String(describing: featureExtractor)))"
        }
    }
    public var debugDescription: String {
        get {
            "ModelParameters(maxIterations: \(String(describing: maxIterations)), augmentationOptions: \(String(describing: augmentationOptions)), algorithm: \(String(describing: algorithm)), validationData: \(String(describing: validationData)), validation: \(String(describing: validation)), featureExtractor: \(String(describing: featureExtractor)))"
        }
    }
    public var playgroundDescription: Any {
        get {
            description
        }
    }
}

extension MLImageClassifier {
    @available(macOS 10.14, iOS 15.0, *)
    @available(tvOS, unavailable)
    public func write(to fileURL: URL, metadata: MLModelMetadata? = nil) throws {
        throw unavailable("Exporting \(Self.self)")
    }
    @available(macOS 10.14, iOS 15.0, *)
    @available(tvOS, unavailable)
    public func write(toFile path: String, metadata: MLModelMetadata? = nil) throws {
        throw unavailable("Exporting \(Self.self)")
    }
}

@available(macOS 10.14, iOS 15.0, *)
@available(tvOS, unavailable)
extension MLImageClassifier {
    public struct ImageAugmentationOptions : OptionSet, Sendable {
        public let rawValue: Int
        public static var blur: MLImageClassifier.ImageAugmentationOptions { MLImageClassifier.ImageAugmentationOptions(rawValue: 1 << 0) }
        public static var flip: MLImageClassifier.ImageAugmentationOptions { MLImageClassifier.ImageAugmentationOptions(rawValue: 1 << 1) }
        public static var exposure: MLImageClassifier.ImageAugmentationOptions { MLImageClassifier.ImageAugmentationOptions(rawValue: 1 << 2) }
        public static var noise: MLImageClassifier.ImageAugmentationOptions { MLImageClassifier.ImageAugmentationOptions(rawValue: 1 << 3) }
        public static var rotation: MLImageClassifier.ImageAugmentationOptions { MLImageClassifier.ImageAugmentationOptions(rawValue: 1 << 4) }
        public static var crop: MLImageClassifier.ImageAugmentationOptions { MLImageClassifier.ImageAugmentationOptions(rawValue: 1 << 5) }
        public init(rawValue: Int) {
            self.rawValue = rawValue
        }
        @available(macOS 10.14, iOS 15.0, *)
        @available(tvOS, unavailable)
        public typealias ArrayLiteralElement = MLImageClassifier.ImageAugmentationOptions
        @available(macOS 10.14, iOS 15.0, *)
        @available(tvOS, unavailable)
        public typealias Element = MLImageClassifier.ImageAugmentationOptions
        @available(macOS 10.14, iOS 15.0, *)
        @available(tvOS, unavailable)
        public typealias RawValue = Int
    }
}

@available(macOS 10.14, iOS 15.0, *)
@available(tvOS, unavailable)
public struct MLImageClassifier : @unchecked Sendable {
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
    public let modelParameters: MLImageClassifier.ModelParameters
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
    @available(macOS 11.0, iOS 15.0, *)
    @available(tvOS, unavailable)
    public init(trainingData: MLImageClassifier.DataSource, parameters: MLImageClassifier.ModelParameters = ModelParameters( validation: .split(strategy: .automatic), augmentation: [], algorithm: .transferLearning( featureExtractor: .scenePrint(revision: 1), classifier: .logisticRegressor ) )) throws {
        throw trainingUnavailable(Self.self)
    }
    @available(macOS, introduced: 10.14, deprecated: 11.0, message: "Use DataSource.filesByLabel to provide dictionary training data instead.")
    @available(iOS, introduced: 15.0, deprecated: 16.0, message: "Use DataSource.filesByLabel to provide dictionary training data instead.")
    @available(tvOS, unavailable)
    public init(trainingData: [String : [URL]], parameters: MLImageClassifier.ModelParameters = ModelParameters(validationData: nil)) throws {
        throw trainingUnavailable(Self.self)
    }
}

@available(macOS 10.14, iOS 15.0, *)
@available(tvOS, unavailable)
extension MLImageClassifier : CustomStringConvertible {
    public var description: String {
        get {
            "\(Self.self): not trained. \(trainingUnavailable(Self.self).failureReason ?? "")"
        }
    }
}

@available(macOS 10.14, iOS 15.0, *)
@available(tvOS, unavailable)
extension MLImageClassifier : CustomDebugStringConvertible {
    public var debugDescription: String {
        get {
            "\(Self.self): not trained. \(trainingUnavailable(Self.self).failureReason ?? "")"
        }
    }
}

@available(macOS 10.14, iOS 15.0, *)
@available(tvOS, unavailable)
extension MLImageClassifier : CustomPlaygroundDisplayConvertible {
    public var playgroundDescription: Any {
        get {
            description
        }
    }
}

extension MLImageClassifier {
    @available(macOS 10.14, iOS 15.0, *)
    @available(tvOS, unavailable)
    public func evaluation(on labeledImages: MLImageClassifier.DataSource) -> MLClassifierMetrics {
        .init(error: unavailable("Evaluating \(Self.self)"))
    }
    @available(macOS, introduced: 10.14, deprecated: 11.0, message: "Use DataSource.filesByLabel to provide dictionary training data instead.")
    @available(iOS, introduced: 15.0, deprecated: 16.0, message: "Use DataSource.filesByLabel to provide dictionary training data instead.")
    @available(tvOS, unavailable)
    public func evaluation(on labeledImages: [String : [URL]]) -> MLClassifierMetrics {
        .init(error: unavailable("Evaluating \(Self.self)"))
    }
}

extension MLImageClassifier {
    @available(macOS 10.14, iOS 15.0, *)
    @available(tvOS, unavailable)
    public func prediction(from image: CGImage) throws -> String {
        throw unavailable("Running \(Self.self)")
    }
    @available(macOS 10.14, iOS 15.0, *)
    @available(tvOS, unavailable)
    public func prediction(from image: URL) throws -> String {
        throw unavailable("Running \(Self.self)")
    }
    @available(macOS 10.14, iOS 15.0, *)
    @available(tvOS, unavailable)
    public func predictions(from images: [URL]) throws -> [String] {
        throw unavailable("Running \(Self.self)")
    }
}

@available(macOS 11.0, iOS 15.0, *)
@available(tvOS, unavailable)
extension MLImageClassifier {
    @available(macOS 11.0, iOS 15.0, *)
    @available(tvOS, unavailable)
    public struct __Defaults {
        public static var batchSize: Int { 64 }
        public static var maximumIterations: Int { 25 }
        public static var validation: MLImageClassifier.ModelParameters.ValidationData { .split(strategy: .automatic) }
        public static var augmentationOptions: MLImageClassifier.ImageAugmentationOptions { [] }
        public static var classifier: MLImageClassifier.ModelParameters.ClassifierType { .logisticRegressor }
        public static var algorithm: MLImageClassifier.ModelParameters.ModelAlgorithmType { .transferLearning(featureExtractor: .scenePrint(revision: 1), classifier: .logisticRegressor) }
        public static var featureColumnName: String { "features" }
        public static var labelColumnName: String { "label" }
    }
}

extension MLImageClassifier.ModelParameters {
    @available(macOS 11.0, iOS 15.0, *)
    @available(tvOS, unavailable)
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

@available(macOS 10.14, iOS 15.0, *)
@available(tvOS, unavailable)
extension MLImageClassifier {
    public enum DataSource : Sendable {
        case labeledDirectories(at: URL)
        case labeledFiles(at: URL)
        @available(macOS 11.0, iOS 15.0, *)
        @available(tvOS, unavailable)
        case filesByLabel([String : [URL]])
        public func labeledImages() throws -> [String : [URL]] {
            try gatherLabeledImages()
        }
        public func stratifiedSplit(proportions: [Double], seed: Int = timestampSeed()) throws -> [[String : [URL]]] {
            var generator = SeededGenerator(seed: seed)
            return try stratifiedSplit(proportions: proportions, generator: &generator)
        }
        public func stratifiedSplit<RNG>(proportions: [Double], generator: inout RNG) throws -> [[String : [URL]]] where RNG : RandomNumberGenerator {
            Examples.split(try gatherLabeledImages(), proportions: proportions, generator: &generator)
        }
    }
}

extension MLImageClassifier {
    @available(macOS 11.0, iOS 15.0, *)
    @available(tvOS, unavailable)
    public init(checkpoint: MLCheckpoint) throws {
        throw trainingUnavailable(Self.self)
    }
    @available(macOS 11.0, iOS 15.0, *)
    @available(tvOS, unavailable)
    public static func train(trainingData: MLImageClassifier.DataSource, parameters: MLImageClassifier.ModelParameters = ModelParameters( validation: .split(strategy: .automatic), augmentation: [], algorithm: .transferLearning( featureExtractor: .scenePrint(revision: 1), classifier: .logisticRegressor ) ), sessionParameters: MLTrainingSessionParameters = _defaultSessionParameters) throws -> MLJob<MLImageClassifier> {
        throw trainingUnavailable(Self.self)
    }
    @available(macOS 11.0, iOS 15.0, *)
    @available(tvOS, unavailable)
    public static func makeTrainingSession(trainingData: MLImageClassifier.DataSource, parameters: MLImageClassifier.ModelParameters = ModelParameters( validation: .split(strategy: .automatic), augmentation: [], algorithm: .transferLearning( featureExtractor: .scenePrint(revision: 1), classifier: .logisticRegressor ) ), sessionParameters: MLTrainingSessionParameters = _defaultSessionParameters) throws -> MLTrainingSession<MLImageClassifier> {
        throw trainingUnavailable(Self.self)
    }
    @available(macOS 11.0, iOS 15.0, *)
    @available(tvOS, unavailable)
    public static func restoreTrainingSession(sessionParameters: MLTrainingSessionParameters) throws -> MLTrainingSession<MLImageClassifier> {
        throw trainingUnavailable(Self.self)
    }
    @available(macOS 11.0, iOS 15.0, *)
    @available(tvOS, unavailable)
    public static func resume(_ session: MLTrainingSession<MLImageClassifier>) throws -> MLJob<MLImageClassifier> {
        throw trainingUnavailable(Self.self)
    }
}

extension MLImageClassifier.ModelParameters {
    @available(macOS 11.0, iOS 15.0, *)
    @available(tvOS, unavailable)
    public enum ModelAlgorithmType : CustomStringConvertible, Sendable {
        case transferLearning(featureExtractor: MLImageClassifier.FeatureExtractorType, classifier: MLImageClassifier.ModelParameters.ClassifierType)
        public var description: String {
            get {
                switch self {
                case .transferLearning(let v0, let v1): return "transferLearning(\(String(describing: v0)), \(String(describing: v1)))"
                }
            }
        }
    }
}
