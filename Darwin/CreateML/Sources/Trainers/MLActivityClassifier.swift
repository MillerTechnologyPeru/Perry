// MLActivityClassifier: its parameters, data sources and options, which work in Perry,
// and its training, prediction and export, which need Apple's private
// engine and throw MLCreateError.generic saying so (see README.md). Its
// instance members are never reached: no instance can be made.

import CoreML
import Foundation
import TabularData

@available(macOS 10.15, *)
@available(iOS, unavailable)
@available(tvOS, unavailable)
public struct MLActivityClassifier : Sendable {
    @available(macOS 11.0, *)
    @available(iOS, unavailable)
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
    nonisolated(unsafe) public let modelParameters: MLActivityClassifier.ModelParameters
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
    public var labelColumn: String
    public var featureColumns: [String]
    public var recordingFileColumn: String
    public init(trainingData: MLActivityClassifier.DataSource, featureColumns: [String], labelColumn: String? = nil, recordingFileColumn: String? = nil, parameters: MLActivityClassifier.ModelParameters = ModelParameters(validationData: nil)) throws {
        throw trainingUnavailable(Self.self)
    }
    @available(macOS, introduced: 10.15, deprecated: 14.0, message: "Use init(trainingData:parameters:)")
    public init(trainingData: MLDataTable, featureColumns: [String], labelColumn: String, recordingFileColumn: String, parameters: MLActivityClassifier.ModelParameters = ModelParameters(validationData: nil)) throws {
        throw trainingUnavailable(Self.self)
    }
    @available(macOS 11.0, *)
    @available(iOS, unavailable)
    @available(tvOS, unavailable)
    public init(checkpoint: MLCheckpoint) throws {
        throw trainingUnavailable(Self.self)
    }
    @available(macOS 11.0, *)
    @available(iOS, unavailable)
    @available(tvOS, unavailable)
    public static func train(trainingData: MLActivityClassifier.DataSource, featureColumns: [String], labelColumn: String, recordingFileColumn: String, parameters: MLActivityClassifier.ModelParameters = ModelParameters(validationData: nil), sessionParameters: MLTrainingSessionParameters = _defaultSessionParameters) throws -> MLJob<MLActivityClassifier> {
        throw trainingUnavailable(Self.self)
    }
    @available(macOS, introduced: 11.0, deprecated: 14.0, message: "Use train(trainingData:parameters:sessionParameters:)")
    @available(iOS, unavailable)
    @available(tvOS, unavailable)
    public static func train(trainingData: MLDataTable, featureColumns: [String], labelColumn: String, recordingFileColumn: String, parameters: MLActivityClassifier.ModelParameters = ModelParameters(validationData: nil), sessionParameters: MLTrainingSessionParameters = _defaultSessionParameters) throws -> MLJob<MLActivityClassifier> {
        throw trainingUnavailable(Self.self)
    }
    @available(macOS 14.0, *)
    @available(iOS, unavailable)
    @available(tvOS, unavailable)
    public static func makeTrainingSession(trainingData: MLActivityClassifier.DataSource, featureColumns: [String], labelColumn: String, recordingFileColumn: String, parameters: MLActivityClassifier.ModelParameters = .init(), sessionParameters: MLTrainingSessionParameters = _defaultSessionParameters) throws -> MLTrainingSession<MLActivityClassifier> {
        throw trainingUnavailable(Self.self)
    }
    @available(macOS, introduced: 11.0, deprecated: 14.0, message: "Use makeTrainingSession(trainingData:parameters:sessionParameters:")
    @available(iOS, unavailable)
    @available(tvOS, unavailable)
    public static func makeTrainingSession(trainingData: MLDataTable, featureColumns: [String], labelColumn: String, recordingFileColumn: String, parameters: MLActivityClassifier.ModelParameters = ModelParameters(validationData: nil), sessionParameters: MLTrainingSessionParameters = _defaultSessionParameters) throws -> MLTrainingSession<MLActivityClassifier> {
        throw trainingUnavailable(Self.self)
    }
    @available(macOS 11.0, *)
    @available(iOS, unavailable)
    @available(tvOS, unavailable)
    public static func restoreTrainingSession(sessionParameters: MLTrainingSessionParameters) throws -> MLTrainingSession<MLActivityClassifier> {
        throw trainingUnavailable(Self.self)
    }
    @available(macOS 11.0, *)
    @available(iOS, unavailable)
    @available(tvOS, unavailable)
    public static func resume(_ session: MLTrainingSession<MLActivityClassifier>) throws -> MLJob<MLActivityClassifier> {
        throw trainingUnavailable(Self.self)
    }
}

@available(macOS 10.15, *)
@available(iOS, unavailable)
@available(tvOS, unavailable)
extension MLActivityClassifier : CustomStringConvertible {
    public var description: String {
        get {
            "\(Self.self): not trained. \(trainingUnavailable(Self.self).failureReason ?? "")"
        }
    }
}

@available(macOS 10.15, *)
@available(iOS, unavailable)
@available(tvOS, unavailable)
extension MLActivityClassifier : CustomDebugStringConvertible {
    public var debugDescription: String {
        get {
            "\(Self.self): not trained. \(trainingUnavailable(Self.self).failureReason ?? "")"
        }
    }
}

@available(macOS 10.15, *)
@available(iOS, unavailable)
@available(tvOS, unavailable)
extension MLActivityClassifier : CustomPlaygroundDisplayConvertible {
    public var playgroundDescription: Any {
        get {
            description
        }
    }
}

@available(macOS 10.15, *)
@available(iOS, unavailable)
@available(tvOS, unavailable)
extension MLActivityClassifier {
    @available(macOS 13.0, *)
    @available(iOS, unavailable)
    @available(tvOS, unavailable)
    public func predictions(from data: DataFrame, perWindowPrediction: Bool? = false) throws -> [String] {
        throw unavailable("Running \(Self.self)")
    }
    @available(macOS, introduced: 10.15, deprecated: 14.0)
    public func predictions(from data: MLDataTable, perWindowPrediction: Bool? = false) throws -> [String] {
        throw unavailable("Running \(Self.self)")
    }
}

@available(macOS 10.15, *)
@available(iOS, unavailable)
@available(tvOS, unavailable)
extension MLActivityClassifier {
    public enum DataSource {
        case labeledDirectories(at: URL)
        case directoryWithDataAndAnnotation(at: URL, annotationFileName: String, timeStampColumn: String, labelStartTimeColumn: String, labelEndTimeColumn: String)
        @available(macOS 14.0, *)
        case dataFrame(DataFrame)
        @available(macOS 14.0, *)
        public func gatherAnnotatedFeatures(featureColumns: [String], labelColumn: String = "label", recordingFileColumn: String? = nil) throws -> DataFrame {
            makeDataFrame(try sensorTable(featureColumns: featureColumns, labelColumn: labelColumn, recordingFileColumn: recordingFileColumn ?? "recording"))
        }
        @available(macOS, introduced: 10.15, deprecated: 14.0, message: "Use gatherAnnotatedFeatures(featureColumns:labelColumn:recordingFileColumn:)")
        public func labeledSensorData(featureColumns: [String], labelColumn: String? = nil, recordingFileColumn: String? = nil) throws -> MLDataTable {
            try sensorTable(featureColumns: featureColumns, labelColumn: labelColumn ?? "label", recordingFileColumn: recordingFileColumn ?? "recording")
        }
        @available(macOS, introduced: 10.15, deprecated: 14.0, message: "Use DataFrame.stratifiedSplit(on:by:).")
        public func stratifiedSplit(proportions: [Double], seed: Int = timestampSeed(), featureColumns: [String], labelColumn: String, recordingFileColumn: String) throws -> MLDataTable {
            let table = try sensorTable(featureColumns: featureColumns, labelColumn: labelColumn, recordingFileColumn: recordingFileColumn)
            return try table.stratifiedSplitBySequence(proportions: proportions, by: recordingFileColumn, on: labelColumn, seed: seed)
        }
    }
}

@available(*, unavailable)
extension MLActivityClassifier.DataSource : Sendable {
}

@available(macOS 10.15, *)
@available(iOS, unavailable)
@available(tvOS, unavailable)
extension MLActivityClassifier {
    public struct ModelParameters {
        @available(macOS, introduced: 10.15, deprecated: 14.0, message: "Use validationDataSource")
        public var validationData: MLDataTable?
        @available(macOS 14.0, *)
        public var validation: MLActivityClassifier.ModelParameters.Validation {
            get {
                _validation
            }
            set {
                _validation = newValue
            }
        }
        public var maximumIterations: Int?
        public var batchSize: Int?
        public var predictionWindowSize: Int?
        @available(macOS 14.0, *)
        public init(validation: MLActivityClassifier.ModelParameters.Validation = .split(strategy: .automatic), batchSize: Int? = 32, maximumIterations: Int? = 10, predictionWindowSize: Int? = 100) {
            self.batchSize = batchSize
            self.maximumIterations = maximumIterations
            self.predictionWindowSize = predictionWindowSize
            self.validation = validation
        }
        public init(validationData: MLActivityClassifier.DataSource, batchSize: Int? = 32, maximumIterations: Int? = 10, predictionWindowSize: Int? = 100) {
            self.validationData = nil
            self.batchSize = batchSize
            self.maximumIterations = maximumIterations
            self.predictionWindowSize = predictionWindowSize
            self.validation = .dataSource(validationData)
        }
        @available(macOS, introduced: 10.15, deprecated: 14.0)
        public init(validationData: MLDataTable?, batchSize: Int? = 32, maximumIterations: Int? = 10, predictionWindowSize: Int? = 100) {
            self.validationData = validationData
            self.batchSize = batchSize
            self.maximumIterations = maximumIterations
            self.predictionWindowSize = predictionWindowSize
        }
        var _validation: MLActivityClassifier.ModelParameters.Validation = .split(strategy: .automatic)
    }
}

@available(macOS 10.15, *)
@available(iOS, unavailable)
@available(tvOS, unavailable)
extension MLActivityClassifier.ModelParameters : CustomStringConvertible, CustomDebugStringConvertible, CustomPlaygroundDisplayConvertible {
    public var description: String {
        get {
            "ModelParameters(validationData: \(String(describing: validationData)), maximumIterations: \(String(describing: maximumIterations)), batchSize: \(String(describing: batchSize)), predictionWindowSize: \(String(describing: predictionWindowSize)), validation: \(String(describing: validation)))"
        }
    }
    public var debugDescription: String {
        get {
            "ModelParameters(validationData: \(String(describing: validationData)), maximumIterations: \(String(describing: maximumIterations)), batchSize: \(String(describing: batchSize)), predictionWindowSize: \(String(describing: predictionWindowSize)), validation: \(String(describing: validation)))"
        }
    }
    public var playgroundDescription: Any {
        get {
            description
        }
    }
}

@available(*, unavailable)
extension MLActivityClassifier.ModelParameters : Sendable {
}

@available(macOS 14.0, *)
@available(iOS, unavailable)
@available(tvOS, unavailable)
extension MLActivityClassifier.ModelParameters {
    public enum Validation {
        case split(strategy: MLSplitStrategy)
        case dataSource(MLActivityClassifier.DataSource)
        case none
    }
}

@available(*, unavailable)
extension MLActivityClassifier.ModelParameters.Validation : Sendable {
}

@available(macOS 10.15, *)
@available(iOS, unavailable)
@available(tvOS, unavailable)
extension MLActivityClassifier {
    @available(macOS, introduced: 10.15, deprecated: 14.0)
    public func evaluation(on testingData: MLDataTable, featureColumns: [String], labelColumn: String, recordingFileColumn: String) -> MLClassifierMetrics {
        .init(error: unavailable("Evaluating \(Self.self)"))
    }
    public func evaluation(on testingData: MLActivityClassifier.DataSource, featureColumns: [String], labelColumn: String? = nil, recordingFileColumn: String? = nil) -> MLClassifierMetrics {
        .init(error: unavailable("Evaluating \(Self.self)"))
    }
}

@available(macOS 10.15, *)
@available(iOS, unavailable)
@available(tvOS, unavailable)
extension MLActivityClassifier {
    public func write(to fileURL: URL, metadata: MLModelMetadata? = MLModelMetadata()) throws {
        throw unavailable("Exporting \(Self.self)")
    }
    public func write(toFile path: String, metadata: MLModelMetadata? = MLModelMetadata()) throws {
        throw unavailable("Exporting \(Self.self)")
    }
}
