// MLHandActionClassifier: its parameters, data sources and options, which work in Perry,
// and its training, prediction and export, which need Apple's private
// engine and throw MLCreateError.generic saying so (see README.md). Its
// instance members are never reached: no instance can be made.

import CoreML
import Foundation
import TabularData

@available(macOS 12.0, iOS 15.0, *)
@available(tvOS, unavailable)
extension MLHandActionClassifier {
    public struct ModelParameters {
        public var validation: MLHandActionClassifier.ModelParameters.ValidationData
        public var batchSize: Int
        public var maximumIterations: Int
        public var predictionWindowSize: Int
        public var augmentationOptions: MLHandActionClassifier.VideoAugmentationOptions
        public var algorithm: MLHandActionClassifier.ModelParameters.ModelAlgorithmType
        public var targetFrameRate: Double
        public init(validation: MLHandActionClassifier.ModelParameters.ValidationData = .split(strategy: .automatic), batchSize: Int = MLHandActionClassifier.__Defaults.batchSize, maximumIterations: Int = MLHandActionClassifier.__Defaults.maximumIterations, predictionWindowSize: Int = MLHandActionClassifier.__Defaults.predictionWindowSize, augmentationOptions: MLHandActionClassifier.VideoAugmentationOptions = [], algorithm: MLHandActionClassifier.ModelParameters.ModelAlgorithmType = .gcn, targetFrameRate: Double = MLHandActionClassifier.__Defaults.targetFrameRate) {
            self.validation = validation
            self.batchSize = batchSize
            self.maximumIterations = maximumIterations
            self.predictionWindowSize = predictionWindowSize
            self.augmentationOptions = augmentationOptions
            self.algorithm = algorithm
            self.targetFrameRate = targetFrameRate
        }
        public enum ModelAlgorithmType : Equatable, Sendable {
            case gcn
        }
        public enum ValidationData {
            case split(strategy: MLSplitStrategy)
            case dataSource(MLHandActionClassifier.DataSource)
            case none
        }
    }
}

@available(*, unavailable)
extension MLHandActionClassifier.ModelParameters : Sendable {
}

@available(*, unavailable)
extension MLHandActionClassifier.ModelParameters.ValidationData : Sendable {
}

@available(macOS 12.0, iOS 15.0, *)
@available(tvOS, unavailable)
extension MLHandActionClassifier.ModelParameters : CustomStringConvertible, CustomDebugStringConvertible, CustomPlaygroundDisplayConvertible {
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

@available(macOS 12.0, iOS 15.0, *)
@available(tvOS, unavailable)
extension MLHandActionClassifier {
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

@available(macOS 12.0, iOS 15.0, *)
@available(tvOS, unavailable)
public struct MLHandActionClassifier {
    public static var _defaultSessionParameters: MLTrainingSessionParameters { MLTrainingSessionParameters() }
    public var model: MLModel
    public let modelParameters: MLHandActionClassifier.ModelParameters
    public var trainingMetrics: MLClassifierMetrics
    public var validationMetrics: MLClassifierMetrics
    public struct Prediction : Sendable {
        public var frameRange: Range<Int>
        public var results: [(label: String, confidence: Double)]
    }
    public init(trainingData: MLHandActionClassifier.DataSource, parameters: MLHandActionClassifier.ModelParameters = ModelParameters()) throws {
        throw trainingUnavailable(Self.self)
    }
    public init(checkpoint: MLCheckpoint) throws {
        throw trainingUnavailable(Self.self)
    }
    public static func train(trainingData: MLHandActionClassifier.DataSource, parameters: MLHandActionClassifier.ModelParameters = ModelParameters(), sessionParameters: MLTrainingSessionParameters = _defaultSessionParameters) throws -> MLJob<MLHandActionClassifier> {
        throw trainingUnavailable(Self.self)
    }
    public static func makeTrainingSession(trainingData: MLHandActionClassifier.DataSource, parameters: MLHandActionClassifier.ModelParameters = .init(), sessionParameters: MLTrainingSessionParameters = _defaultSessionParameters) throws -> MLTrainingSession<MLHandActionClassifier> {
        throw trainingUnavailable(Self.self)
    }
    public static func restoreTrainingSession(sessionParameters: MLTrainingSessionParameters) throws -> MLTrainingSession<MLHandActionClassifier> {
        throw trainingUnavailable(Self.self)
    }
    public static func resume(_ session: MLTrainingSession<MLHandActionClassifier>) throws -> MLJob<MLHandActionClassifier> {
        throw trainingUnavailable(Self.self)
    }
    public func prediction(from video: URL) throws -> [MLHandActionClassifier.Prediction] {
        throw unavailable("Running \(Self.self)")
    }
    public func predictions(from videos: [URL]) throws -> [[MLHandActionClassifier.Prediction]] {
        throw unavailable("Running \(Self.self)")
    }
    public func evaluation(on annotatedVideos: MLHandActionClassifier.DataSource) throws -> MLClassifierMetrics {
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
extension MLHandActionClassifier : Sendable {
}

@available(macOS 12.0, iOS 15.0, *)
@available(tvOS, unavailable)
extension MLHandActionClassifier : CustomStringConvertible, CustomDebugStringConvertible, CustomPlaygroundDisplayConvertible {
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
extension MLHandActionClassifier {
    public struct VideoAugmentationOptions : OptionSet, Codable, Sendable {
        public let rawValue: Int
        public static var horizontallyFlip: MLHandActionClassifier.VideoAugmentationOptions { MLHandActionClassifier.VideoAugmentationOptions(rawValue: 1 << 0) }
        public static var rotate: MLHandActionClassifier.VideoAugmentationOptions { MLHandActionClassifier.VideoAugmentationOptions(rawValue: 1 << 1) }
        public static var translate: MLHandActionClassifier.VideoAugmentationOptions { MLHandActionClassifier.VideoAugmentationOptions(rawValue: 1 << 2) }
        public static var scale: MLHandActionClassifier.VideoAugmentationOptions { MLHandActionClassifier.VideoAugmentationOptions(rawValue: 1 << 3) }
        public static var interpolateFrames: MLHandActionClassifier.VideoAugmentationOptions { MLHandActionClassifier.VideoAugmentationOptions(rawValue: 1 << 4) }
        public static var dropFrames: MLHandActionClassifier.VideoAugmentationOptions { MLHandActionClassifier.VideoAugmentationOptions(rawValue: 1 << 5) }
        public init(rawValue: Int) {
            self.rawValue = rawValue
        }
        @available(macOS 12.0, iOS 15.0, *)
        @available(tvOS, unavailable)
        public typealias ArrayLiteralElement = MLHandActionClassifier.VideoAugmentationOptions
        @available(macOS 12.0, iOS 15.0, *)
        @available(tvOS, unavailable)
        public typealias Element = MLHandActionClassifier.VideoAugmentationOptions
        @available(macOS 12.0, iOS 15.0, *)
        @available(tvOS, unavailable)
        public typealias RawValue = Int
    }
}

@available(macOS 12.0, iOS 15.0, *)
@available(tvOS, unavailable)
extension MLHandActionClassifier {
    public enum DataSource {
        case directoryWithVideosAndAnnotation(at: URL, annotationFile: URL, videoColumn: String, labelColumn: String, startTimeColumn: String? = nil, endTimeColumn: String? = nil)
        case labeledDirectories(at: URL)
        case labeledFiles(at: URL)
        @available(macOS, introduced: 12.0, deprecated: 14.0)
        @available(iOS, introduced: 15.0, deprecated: 17.0)
        @available(tvOS, unavailable)
        case labeledKeypointsData(table: MLDataTable, sessionIdColumn: String = __Defaults.sessionIdColumnName, labelColumn: String = __Defaults.labelColumnName, featureColumn: String = __Defaults.featureColumnName)
        @available(macOS, introduced: 12.0, deprecated: 14.0)
        @available(iOS, introduced: 15.0, deprecated: 17.0)
        @available(tvOS, unavailable)
        case labeledVideoData(table: MLDataTable, videoColumn: String = __Defaults.videoColumnName, labelColumn: String = __Defaults.labelColumnName, startTimeColumn: String? = nil, endTimeColumn: String? = nil)
        case labeledKeypointsDataFrame(DataFrame, sessionIdColumn: String = __Defaults.sessionIdColumnName, labelColumn: String = __Defaults.labelColumnName, featureColumn: String = __Defaults.featureColumnName)
        case labeledVideoDataFrame(DataFrame, videoColumn: String = __Defaults.videoColumnName, labelColumn: String = __Defaults.labelColumnName, startTimeColumn: String? = nil, endTimeColumn: String? = nil)
        @available(macOS 14.0, iOS 17.0, *)
        @available(tvOS, unavailable)
        public func gatherAnnotatedFileNames() throws -> DataFrame? {
            try media.annotatedTable().map(makeDataFrame)
        }
        @available(macOS, introduced: 12.0, deprecated: 14.0, message: "Use gatherAnnotatedFileNames()")
        @available(iOS, introduced: 15.0, deprecated: 17.0, message: "Use gatherAnnotatedFileNames()")
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
            throw Examples.featuresUnavailable("hand pose keypoints from videos")
        }
        @available(macOS, introduced: 12.0, deprecated: 14.0, message: "Use extractKeypoints(targetFrameRate:)")
        @available(iOS, introduced: 15.0, deprecated: 17.0, message: "Use extractKeypoints(targetFrameRate:)")
        @available(tvOS, unavailable)
        public func keypointsWithAnnotations(targetFrameRate: Double = MLHandActionClassifier.__Defaults.targetFrameRate) throws -> MLDataTable {
            throw Examples.featuresUnavailable("hand pose keypoints from videos")
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
extension MLHandActionClassifier.DataSource : Sendable {
}

@available(macOS 12.0, iOS 15.0, *)
@available(tvOS, unavailable)
extension MLHandActionClassifier.DataSource {
    public func labeledMedia() throws -> [String : [URL]] {
        try media.labeledMedia()
    }
}

@available(macOS 12.0, iOS 15.0, *)
@available(tvOS, unavailable)
extension MLHandActionClassifier.ModelParameters.ModelAlgorithmType : Hashable {}
