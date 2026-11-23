// MLHandPoseClassifier: its parameters, data sources and options, which work in Perry,
// and its training, prediction and export, which need Apple's private
// engine and throw MLCreateError.generic saying so (see README.md). Its
// instance members are never reached: no instance can be made.

import CoreML
import Foundation
import TabularData

@available(macOS 12.0, iOS 15.0, *)
@available(tvOS, unavailable)
public struct MLHandPoseClassifier {
    public static var _defaultSessionParameters: MLTrainingSessionParameters { MLTrainingSessionParameters() }
    public var model: MLModel
    public let modelParameters: MLHandPoseClassifier.ModelParameters
    public var trainingMetrics: MLClassifierMetrics
    public var validationMetrics: MLClassifierMetrics
    public init(trainingData: MLHandPoseClassifier.DataSource, parameters: MLHandPoseClassifier.ModelParameters = ModelParameters()) throws {
        throw trainingUnavailable(Self.self)
    }
    public init(checkpoint: MLCheckpoint) throws {
        throw trainingUnavailable(Self.self)
    }
    public static func train(trainingData: MLHandPoseClassifier.DataSource, parameters: MLHandPoseClassifier.ModelParameters = ModelParameters(), sessionParameters: MLTrainingSessionParameters = _defaultSessionParameters) throws -> MLJob<MLHandPoseClassifier> {
        throw trainingUnavailable(Self.self)
    }
    public static func makeTrainingSession(trainingData: MLHandPoseClassifier.DataSource, parameters: MLHandPoseClassifier.ModelParameters = .init(), sessionParameters: MLTrainingSessionParameters = _defaultSessionParameters) throws -> MLTrainingSession<MLHandPoseClassifier> {
        throw trainingUnavailable(Self.self)
    }
    public static func restoreTrainingSession(sessionParameters: MLTrainingSessionParameters) throws -> MLTrainingSession<MLHandPoseClassifier> {
        throw trainingUnavailable(Self.self)
    }
    public static func resume(_ session: MLTrainingSession<MLHandPoseClassifier>) throws -> MLJob<MLHandPoseClassifier> {
        throw trainingUnavailable(Self.self)
    }
    public func prediction(from image: URL) throws -> [(label: String, confidence: Double)] {
        throw unavailable("Running \(Self.self)")
    }
    public func predictions(from images: [URL]) throws -> [[(label: String, confidence: Double)]] {
        throw unavailable("Running \(Self.self)")
    }
    public func evaluation(on annotatedImages: MLHandPoseClassifier.DataSource) throws -> MLClassifierMetrics {
        throw unavailable("Running \(Self.self)")
    }
    public func write(to fileURL: URL, metadata: MLModelMetadata? = nil) throws {
        throw unavailable("Exporting \(Self.self)")
    }
    public func write(toFile path: String, metadata: MLModelMetadata? = nil) throws {
        throw unavailable("Exporting \(Self.self)")
    }
}

@available(*, unavailable)
extension MLHandPoseClassifier : Sendable {
}

@available(macOS 12.0, iOS 15.0, *)
@available(tvOS, unavailable)
extension MLHandPoseClassifier : CustomStringConvertible, CustomDebugStringConvertible, CustomPlaygroundDisplayConvertible {
    public var description: String {
        get {
            "\(Self.self): not trained. \(trainingUnavailable(Self.self).failureReason ?? "")"
        }
    }
    public var debugDescription: String {
        get {
            "\(Self.self): not trained. \(trainingUnavailable(Self.self).failureReason ?? "")"
        }
    }
    public var playgroundDescription: Any {
        get {
            description
        }
    }
}

@available(macOS 12.0, iOS 15.0, *)
@available(tvOS, unavailable)
extension MLHandPoseClassifier {
    public struct ModelParameters {
        public var validation: MLHandPoseClassifier.ModelParameters.ValidationData
        public var batchSize: Int
        public var maximumIterations: Int
        public var augmentationOptions: MLHandPoseClassifier.ImageAugmentationOptions
        public var algorithm: MLHandPoseClassifier.ModelParameters.ModelAlgorithmType
        public init(validation: MLHandPoseClassifier.ModelParameters.ValidationData = .split(strategy: .automatic), batchSize: Int = MLHandPoseClassifier.__Defaults.batchSize, maximumIterations: Int = MLHandPoseClassifier.__Defaults.maximumIterations, augmentationOptions: MLHandPoseClassifier.ImageAugmentationOptions = [], algorithm: MLHandPoseClassifier.ModelParameters.ModelAlgorithmType = .gcn) {
            self.validation = validation
            self.batchSize = batchSize
            self.maximumIterations = maximumIterations
            self.augmentationOptions = augmentationOptions
            self.algorithm = algorithm
        }
        public enum ModelAlgorithmType : Equatable, Sendable {
            case gcn
        }
        public enum ValidationData {
            case split(strategy: MLSplitStrategy)
            case dataSource(MLHandPoseClassifier.DataSource)
            case none
        }
    }
}

@available(*, unavailable)
extension MLHandPoseClassifier.ModelParameters : Sendable {
}

@available(*, unavailable)
extension MLHandPoseClassifier.ModelParameters.ValidationData : Sendable {
}

@available(macOS 12.0, iOS 15.0, *)
@available(tvOS, unavailable)
extension MLHandPoseClassifier.ModelParameters : CustomStringConvertible, CustomDebugStringConvertible, CustomPlaygroundDisplayConvertible {
    public var description: String {
        get {
            "ModelParameters(validation: \(String(describing: validation)), batchSize: \(String(describing: batchSize)), maximumIterations: \(String(describing: maximumIterations)), augmentationOptions: \(String(describing: augmentationOptions)), algorithm: \(String(describing: algorithm)))"
        }
    }
    public var debugDescription: String {
        get {
            "ModelParameters(validation: \(String(describing: validation)), batchSize: \(String(describing: batchSize)), maximumIterations: \(String(describing: maximumIterations)), augmentationOptions: \(String(describing: augmentationOptions)), algorithm: \(String(describing: algorithm)))"
        }
    }
    public var playgroundDescription: Any {
        get {
            description
        }
    }
}

@available(macOS 12.0, iOS 15.0, *)
@available(tvOS, unavailable)
extension MLHandPoseClassifier {
    public struct __Defaults : Sendable {
        public static var batchSize: Int { 32 }
        public static var maximumIterations: Int { 80 }
        public static var sessionIdColumnName: String { "sessionId" }
        public static var featureColumnName: String { "pose" }
        public static var labelColumnName: String { "label" }
        public static var imageColumnName: String { "image" }
    }
}

@available(macOS 12.0, iOS 15.0, *)
@available(tvOS, unavailable)
extension MLHandPoseClassifier {
    public enum DataSource {
        case directoryWithImagesAndAnnotation(at: URL, annotationFile: URL, imageColumn: String, labelColumn: String)
        case labeledDirectories(at: URL)
        case labeledFiles(at: URL)
        @available(macOS, introduced: 12.0, deprecated: 14.0)
        @available(iOS, introduced: 15.0, deprecated: 17.0)
        @available(tvOS, unavailable)
        case labeledKeypointsData(table: MLDataTable, sessionIdColumn: String = __Defaults.sessionIdColumnName, labelColumn: String = __Defaults.labelColumnName, featureColumn: String = __Defaults.featureColumnName)
        @available(macOS, introduced: 12.0, deprecated: 14.0)
        @available(iOS, introduced: 15.0, deprecated: 17.0)
        @available(tvOS, unavailable)
        case labeledImageData(table: MLDataTable, imageColumn: String = __Defaults.imageColumnName, labelColumn: String = __Defaults.labelColumnName)
        case labeledKeypointsDataFrame(DataFrame, sessionIdColumn: String = __Defaults.sessionIdColumnName, labelColumn: String = __Defaults.labelColumnName, featureColumn: String = __Defaults.featureColumnName)
        case labeledImageDataFrame(DataFrame, imageColumn: String = __Defaults.imageColumnName, labelColumn: String = __Defaults.labelColumnName)
        @available(macOS 14.0, iOS 17.0, *)
        @available(tvOS, unavailable)
        public func gatherAnnotatedFileNames() throws -> DataFrame? {
            try media.annotatedTable().map(makeDataFrame)
        }
        @available(macOS, introduced: 12.0, deprecated: 14.0, message: "Use gatherAnnotatedFileNames()")
        @available(iOS, introduced: 15.0, deprecated: 17.0, message: "Use gatherAnnotatedFileNames()")
        @available(tvOS, unavailable)
        public func imagesWithAnnotations() throws -> MLDataTable {
            guard let table = try media.annotatedTable() else {
                throw MLCreateError.generic(reason: "A data source of keypoints has no images.")
            }
            return table
        }
        @available(macOS 14.0, iOS 17.0, *)
        @available(tvOS, unavailable)
        public func extractKeypoints() throws -> DataFrame {
            throw Examples.featuresUnavailable("hand pose keypoints from images")
        }
        @available(macOS, introduced: 12.0, deprecated: 14.0, message: "Use extractKeypoints()")
        @available(iOS, introduced: 15.0, deprecated: 17.0, message: "Use extractKeypoints()")
        @available(tvOS, unavailable)
        public func keypointsWithAnnotations() throws -> MLDataTable {
            throw Examples.featuresUnavailable("hand pose keypoints from images")
        }
        @available(macOS, introduced: 12.0, deprecated: 14.0, message: "Use DataFrame.stratifiedSplit(on:by:)")
        @available(iOS, introduced: 15.0, deprecated: 17.0, message: "Use DataFrame.stratifiedSplit(on:by:)")
        @available(tvOS, unavailable)
        public func stratifiedSplit(proportions: [Double], seed: Int = timestampSeed(), labelColumn: String) throws -> MLDataTable {
            try media.stratifiedSplit(proportions: proportions, seed: seed, labelColumn: labelColumn)
        }
    }
}

@available(*, unavailable)
extension MLHandPoseClassifier.DataSource : Sendable {
}

@available(macOS 12.0, iOS 15.0, *)
@available(tvOS, unavailable)
extension MLHandPoseClassifier.DataSource {
    public func labeledMedia() throws -> [String : [URL]] {
        try media.labeledMedia()
    }
}

@available(macOS 12.0, iOS 15.0, *)
@available(tvOS, unavailable)
extension MLHandPoseClassifier {
    public struct ImageAugmentationOptions : OptionSet, Codable, Sendable {
        public let rawValue: Int
        public static var horizontallyFlip: MLHandPoseClassifier.ImageAugmentationOptions { MLHandPoseClassifier.ImageAugmentationOptions(rawValue: 1 << 0) }
        public static var rotate: MLHandPoseClassifier.ImageAugmentationOptions { MLHandPoseClassifier.ImageAugmentationOptions(rawValue: 1 << 1) }
        public static var translate: MLHandPoseClassifier.ImageAugmentationOptions { MLHandPoseClassifier.ImageAugmentationOptions(rawValue: 1 << 2) }
        public static var scale: MLHandPoseClassifier.ImageAugmentationOptions { MLHandPoseClassifier.ImageAugmentationOptions(rawValue: 1 << 3) }
        public init(rawValue: Int) {
            self.rawValue = rawValue
        }
        @available(macOS 12.0, iOS 15.0, *)
        @available(tvOS, unavailable)
        public typealias ArrayLiteralElement = MLHandPoseClassifier.ImageAugmentationOptions
        @available(macOS 12.0, iOS 15.0, *)
        @available(tvOS, unavailable)
        public typealias Element = MLHandPoseClassifier.ImageAugmentationOptions
        @available(macOS 12.0, iOS 15.0, *)
        @available(tvOS, unavailable)
        public typealias RawValue = Int
    }
}

@available(macOS 12.0, iOS 15.0, *)
@available(tvOS, unavailable)
extension MLHandPoseClassifier.ModelParameters.ModelAlgorithmType : Hashable {}
