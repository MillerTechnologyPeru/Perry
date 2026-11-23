// MLActionClassifier: its parameters, data sources and options, which work in Perry,
// and its training, prediction and export, which need Apple's private
// engine and throw MLCreateError.generic saying so (see README.md). Its
// instance members are never reached: no instance can be made.

import CoreML
import Foundation
import TabularData

@available(macOS 11.0, *)
@available(iOS, unavailable)
@available(tvOS, unavailable)
extension MLActionClassifier {
    public struct VideoAugmentationOptions : OptionSet, Codable, Sendable {
        public let rawValue: Int
        public static var horizontalFlip: MLActionClassifier.VideoAugmentationOptions { MLActionClassifier.VideoAugmentationOptions(rawValue: 1 << 0) }
        public init(rawValue: Int) {
            self.rawValue = rawValue
        }
        @available(macOS 11.0, *)
        @available(iOS, unavailable)
        @available(tvOS, unavailable)
        public typealias ArrayLiteralElement = MLActionClassifier.VideoAugmentationOptions
        @available(macOS 11.0, *)
        @available(iOS, unavailable)
        @available(tvOS, unavailable)
        public typealias Element = MLActionClassifier.VideoAugmentationOptions
        @available(macOS 11.0, *)
        @available(iOS, unavailable)
        @available(tvOS, unavailable)
        public typealias RawValue = Int
    }
}

@available(macOS 11.0, *)
@available(iOS, unavailable)
@available(tvOS, unavailable)
public struct MLActionClassifier : Sendable {
    @available(macOS 11.0, *)
    @available(iOS, unavailable)
    @available(tvOS, unavailable)
    public static var _defaultSessionParameters: MLTrainingSessionParameters { MLTrainingSessionParameters() }
    public var model: MLModel {
        get {
            unreachableTrainer(Self.self)
        }
    }
    nonisolated(unsafe) public let modelParameters: MLActionClassifier.ModelParameters
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
    public struct Prediction : Sendable {
        public var frameRange: Range<Int>
        public var results: [(label: String, confidence: Double)]
    }
    public init(trainingData: MLActionClassifier.DataSource, parameters: MLActionClassifier.ModelParameters = ModelParameters()) throws {
        throw trainingUnavailable(Self.self)
    }
    public init(checkpoint: MLCheckpoint) throws {
        throw trainingUnavailable(Self.self)
    }
    public static func train(trainingData: MLActionClassifier.DataSource, parameters: MLActionClassifier.ModelParameters = ModelParameters(), sessionParameters: MLTrainingSessionParameters = _defaultSessionParameters) throws -> MLJob<MLActionClassifier> {
        throw trainingUnavailable(Self.self)
    }
    public static func makeTrainingSession(trainingData: MLActionClassifier.DataSource, parameters: MLActionClassifier.ModelParameters = .init(), sessionParameters: MLTrainingSessionParameters = _defaultSessionParameters) throws -> MLTrainingSession<MLActionClassifier> {
        throw trainingUnavailable(Self.self)
    }
    public static func restoreTrainingSession(sessionParameters: MLTrainingSessionParameters) throws -> MLTrainingSession<MLActionClassifier> {
        throw trainingUnavailable(Self.self)
    }
    public static func resume(_ session: MLTrainingSession<MLActionClassifier>) throws -> MLJob<MLActionClassifier> {
        throw trainingUnavailable(Self.self)
    }
    public func prediction(from video: URL) throws -> [MLActionClassifier.Prediction] {
        throw unavailable("Running \(Self.self)")
    }
    public func predictions(from videos: [URL]) throws -> [[MLActionClassifier.Prediction]] {
        throw unavailable("Running \(Self.self)")
    }
    public func evaluation(on annotatedVideos: MLActionClassifier.DataSource) throws -> MLClassifierMetrics {
        throw unavailable("Running \(Self.self)")
    }
    public func write(to fileURL: URL, metadata: MLModelMetadata? = nil) throws {
        throw unavailable("Exporting \(Self.self)")
    }
    public func write(toFile path: String, metadata: MLModelMetadata? = nil) throws {
        throw unavailable("Exporting \(Self.self)")
    }
}

@available(macOS 11.0, *)
@available(iOS, unavailable)
@available(tvOS, unavailable)
extension MLActionClassifier : CustomStringConvertible, CustomDebugStringConvertible, CustomPlaygroundDisplayConvertible {
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

@available(macOS 11.0, *)
@available(iOS, unavailable)
@available(tvOS, unavailable)
extension MLActionClassifier {
    public struct __Defaults : Sendable {
        public static var batchSize: Int { 32 }
        public static var maximumIterations: Int { 80 }
        public static var predictionWindowSize: Int { 60 }
        public static var sessionIdColumnName: String { "sessionId" }
        public static var featureColumnName: String { "poses" }
        public static var labelColumnName: String { "label" }
        public static var videoColumnName: String { "video" }
        public static var startTimeColumnName: String { "startTime" }
        public static var endTimeColumnName: String { "endTime" }
        public static var targetFrameRate: Double { 30 }
    }
}

@available(macOS 11.0, *)
@available(iOS, unavailable)
@available(tvOS, unavailable)
extension MLActionClassifier {
    public struct ModelParameters {
        public var validation: MLActionClassifier.ModelParameters.ValidationData
        public var batchSize: Int
        public var maximumIterations: Int
        public var predictionWindowSize: Int
        public var augmentationOptions: MLActionClassifier.VideoAugmentationOptions
        public var algorithm: MLActionClassifier.ModelParameters.ModelAlgorithmType
        public var targetFrameRate: Double
        public init(validation: MLActionClassifier.ModelParameters.ValidationData = .split(strategy: .automatic), batchSize: Int = MLActionClassifier.__Defaults.batchSize, maximumIterations: Int = MLActionClassifier.__Defaults.maximumIterations, predictionWindowSize: Int = MLActionClassifier.__Defaults.predictionWindowSize, augmentationOptions: MLActionClassifier.VideoAugmentationOptions = [.horizontalFlip], algorithm: MLActionClassifier.ModelParameters.ModelAlgorithmType = .stgcn, targetFrameRate: Double = MLActionClassifier.__Defaults.targetFrameRate) {
            self.validation = validation
            self.batchSize = batchSize
            self.maximumIterations = maximumIterations
            self.predictionWindowSize = predictionWindowSize
            self.augmentationOptions = augmentationOptions
            self.algorithm = algorithm
            self.targetFrameRate = targetFrameRate
        }
        public enum ModelAlgorithmType : Equatable, Sendable {
            case stgcn
        }
        public enum ValidationData {
            case split(strategy: MLSplitStrategy)
            case dataSource(MLActionClassifier.DataSource)
            case none
        }
    }
}

@available(*, unavailable)
extension MLActionClassifier.ModelParameters : Sendable {
}

@available(*, unavailable)
extension MLActionClassifier.ModelParameters.ValidationData : Sendable {
}

@available(macOS 11.0, *)
@available(iOS, unavailable)
@available(tvOS, unavailable)
extension MLActionClassifier.ModelParameters : CustomStringConvertible, CustomDebugStringConvertible, CustomPlaygroundDisplayConvertible {
    public var description: String {
        get {
            "ModelParameters(validation: \(String(describing: validation)), batchSize: \(String(describing: batchSize)), maximumIterations: \(String(describing: maximumIterations)), predictionWindowSize: \(String(describing: predictionWindowSize)), augmentationOptions: \(String(describing: augmentationOptions)), algorithm: \(String(describing: algorithm)), targetFrameRate: \(String(describing: targetFrameRate)))"
        }
    }
    public var debugDescription: String {
        get {
            "ModelParameters(validation: \(String(describing: validation)), batchSize: \(String(describing: batchSize)), maximumIterations: \(String(describing: maximumIterations)), predictionWindowSize: \(String(describing: predictionWindowSize)), augmentationOptions: \(String(describing: augmentationOptions)), algorithm: \(String(describing: algorithm)), targetFrameRate: \(String(describing: targetFrameRate)))"
        }
    }
    public var playgroundDescription: Any {
        get {
            description
        }
    }
}

@available(macOS 11.0, *)
@available(iOS, unavailable)
@available(tvOS, unavailable)
extension MLActionClassifier {
    public enum DataSource {
        case directoryWithVideosAndAnnotation(at: URL, annotationFile: URL, videoColumn: String, labelColumn: String, startTimeColumn: String? = nil, endTimeColumn: String? = nil)
        case labeledDirectories(at: URL)
        case labeledFiles(at: URL)
        @available(macOS, introduced: 11.0, deprecated: 14.0)
        @available(iOS, unavailable)
        @available(tvOS, unavailable)
        case labeledKeypointsData(table: MLDataTable, sessionIdColumn: String = __Defaults.sessionIdColumnName, labelColumn: String = __Defaults.labelColumnName, featureColumn: String = __Defaults.featureColumnName)
        @available(macOS, introduced: 11.0, deprecated: 14.0)
        @available(iOS, unavailable)
        @available(tvOS, unavailable)
        case labeledVideoData(table: MLDataTable, videoColumn: String = __Defaults.videoColumnName, labelColumn: String = __Defaults.labelColumnName, startTimeColumn: String? = nil, endTimeColumn: String? = nil)
        @available(macOS 12, *)
        @available(iOS, unavailable)
        @available(tvOS, unavailable)
        case labeledKeypointsDataFrame(DataFrame, sessionIdColumn: String = __Defaults.sessionIdColumnName, labelColumn: String = __Defaults.labelColumnName, featureColumn: String = __Defaults.featureColumnName)
        @available(macOS 12, *)
        @available(iOS, unavailable)
        @available(tvOS, unavailable)
        case labeledVideoDataFrame(DataFrame, videoColumn: String = __Defaults.videoColumnName, labelColumn: String = __Defaults.labelColumnName, startTimeColumn: String? = nil, endTimeColumn: String? = nil)
        @available(macOS 14.0, iOS 17.0, *)
        @available(tvOS, unavailable)
        public func gatherAnnotatedFileNames() throws -> DataFrame? {
            try media.annotatedTable().map(makeDataFrame)
        }
        @available(macOS, introduced: 11.0, deprecated: 14.0, message: "Use gatherAnnotatedFileNames()")
        @available(iOS, unavailable)
        @available(tvOS, unavailable)
        public func videosWithAnnotations() throws -> MLDataTable {
            guard let table = try media.annotatedTable() else {
                throw MLCreateError.generic(reason: "A data source of keypoints has no videos.")
            }
            return table
        }
        @available(macOS 14.0, iOS 17.0, *)
        @available(tvOS, unavailable)
        public func extractKeypoints(targetFrameRate: Double = MLHandActionClassifier.__Defaults.targetFrameRate) throws -> DataFrame {
            throw Examples.featuresUnavailable("body pose keypoints from videos")
        }
        @available(macOS, introduced: 11.0, deprecated: 14.0, message: "Use extractKeypoints(targetFrameRate:)")
        @available(iOS, unavailable)
        @available(tvOS, unavailable)
        public func keypointsWithAnnotations(targetFrameRate: Double = MLActionClassifier.__Defaults.targetFrameRate) throws -> MLDataTable {
            throw Examples.featuresUnavailable("body pose keypoints from videos")
        }
        @available(macOS, introduced: 11.0, deprecated: 14.0, message: "Use DataFrame.stratifiedSplit(on:by:)")
        @available(iOS, unavailable)
        @available(tvOS, unavailable)
        public func stratifiedSplit(proportions: [Double], seed: Int = timestampSeed(), labelColumn: String) throws -> MLDataTable {
            try media.stratifiedSplit(proportions: proportions, seed: seed, labelColumn: labelColumn)
        }
    }
}

@available(*, unavailable)
extension MLActionClassifier.DataSource : Sendable {
}

@available(macOS 11.0, *)
@available(iOS, unavailable)
@available(tvOS, unavailable)
extension MLActionClassifier.ModelParameters.ModelAlgorithmType : Hashable {}
