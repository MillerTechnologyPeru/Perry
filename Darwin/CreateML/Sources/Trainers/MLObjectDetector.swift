// MLObjectDetector: its parameters, data sources and options, which work in Perry,
// and its training, prediction and export, which need Apple's private
// engine and throw MLCreateError.generic saying so (see README.md). Its
// instance members are never reached: no instance can be made.

import CoreGraphics
import CoreML
import Foundation
import TabularData

@available(macOS 10.15, *)
@available(iOS, unavailable)
@available(tvOS, unavailable)
extension MLObjectDetector {
    public func evaluation(on annotatedImages: MLObjectDetector.DataSource) -> MLObjectDetectorMetrics {
        .init(error: unavailable("Evaluating \(Self.self)"))
    }
    @available(macOS, introduced: 10.15, deprecated: 13.0, message: "Use DataSource instead of MLDataTable.")
    @available(iOS, unavailable)
    @available(tvOS, unavailable)
    public func evaluation(on annotatedImages: MLDataTable, imageColumn: String, annotationColumn: String) -> MLObjectDetectorMetrics {
        .init(error: unavailable("Evaluating \(Self.self)"))
    }
}

@available(macOS 10.15, *)
@available(iOS, unavailable)
@available(tvOS, unavailable)
extension MLObjectDetector {
    public func prediction(from image: URL) throws -> MLObjectDetector.DetectedObjects {
        throw unavailable("Running \(Self.self)")
    }
    public func predictions(from images: [URL]) throws -> [MLObjectDetector.DetectedObjects] {
        throw unavailable("Running \(Self.self)")
    }
}

@available(macOS 10.15, *)
@available(iOS, unavailable)
@available(tvOS, unavailable)
extension MLObjectDetector {
    public func write(to fileURL: URL, metadata: MLModelMetadata? = MLModelMetadata()) throws {
        throw unavailable("Exporting \(Self.self)")
    }
    public func write(toFile path: String, metadata: MLModelMetadata? = MLModelMetadata()) throws {
        throw unavailable("Exporting \(Self.self)")
    }
}

@available(macOS 10.15, *)
@available(iOS, unavailable)
@available(tvOS, unavailable)
public struct MLObjectDetector : @unchecked Sendable {
    public typealias DetectedObjects = [MLObjectDetector.ObjectAnnotation]
    public let modelParameters: MLObjectDetector.ModelParameters
    public var model: MLModel {
        get {
            unreachableTrainer(Self.self)
        }
    }
    public var trainingMetrics: MLObjectDetectorMetrics {
        get {
            .init(error: trainingUnavailable(Self.self))
        }
    }
    public var validationMetrics: MLObjectDetectorMetrics {
        get {
            .init(error: trainingUnavailable(Self.self))
        }
    }
    public init(trainingData: MLObjectDetector.DataSource, parameters: MLObjectDetector.ModelParameters = .init(), annotationType: MLObjectDetector.AnnotationType) throws {
        throw trainingUnavailable(Self.self)
    }
    @available(macOS, introduced: 10.15, deprecated: 13.0, message: "Use DataSource instead of MLDataTable when initializing.")
    @available(iOS, unavailable)
    @available(tvOS, unavailable)
    public init(trainingData: MLDataTable, imageColumn: String, annotationColumn: String, annotationType: MLObjectDetector.AnnotationType, parameters: MLObjectDetector.ModelParameters = ModelParameters()) throws {
        throw trainingUnavailable(Self.self)
    }
}

@available(macOS 10.15, *)
@available(iOS, unavailable)
@available(tvOS, unavailable)
extension MLObjectDetector : CustomStringConvertible, CustomDebugStringConvertible, CustomPlaygroundDisplayConvertible {
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

@available(macOS 10.15, *)
@available(iOS, unavailable)
@available(tvOS, unavailable)
extension MLObjectDetector {
    public enum AnnotationType : Sendable {
        case boundingBox(units: MLBoundingBoxUnits = .pixel, origin: MLBoundingBoxCoordinatesOrigin = .topLeft, anchor: MLBoundingBoxAnchor = .center)
    }
}

@available(macOS 10.15, *)
@available(iOS, unavailable)
@available(tvOS, unavailable)
extension MLObjectDetector {
    public enum DataSource {
        case directoryWithImagesAndJsonAnnotation(at: URL)
        case directoryWithImages(at: URL, annotationFile: URL)
        @available(macOS, introduced: 11.0, deprecated: 14.0)
        @available(iOS, unavailable)
        @available(tvOS, unavailable)
        case table(MLDataTable, imageColumn: String, annotationColumn: String)
        @available(macOS 12, *)
        @available(iOS, unavailable)
        @available(tvOS, unavailable)
        case frame(DataFrame, imageColumn: String, annotationColumn: String)
        @available(macOS 14.0, *)
        public func gatherAnnotatedFileNames() throws -> DataFrame {
            makeDataFrame(try annotatedImages().table)
        }
        @available(macOS, introduced: 10.15, deprecated: 14.0, message: "Use gatherAnnotatedFileNames()")
        @available(iOS, unavailable)
        @available(tvOS, unavailable)
        public func imagesWithObjectAnnotations() throws -> MLDataTable {
            try annotatedImages().table
        }
        @available(macOS, introduced: 10.15, deprecated: 14.0, message: "Use DataFrame.stratifiedSplit(on:by:)")
        @available(iOS, unavailable)
        @available(tvOS, unavailable)
        public func stratifiedSplit(proportions: [Double], seed: Int = timestampSeed(), annotationColumn: String) throws -> MLDataTable {
            // Stratified by each image's first label.
            let (table, _, column) = try annotatedImages()
            var labeled = table
            labeled.addColumn(table[column].map { value -> String in
                value.sequenceValue?.first?.dictionaryValue?[.string("label")]?.stringValue ?? ""
            }, named: "__label")
            var split = try labeled.stratifiedSplit(proportions: proportions, on: "__label", seed: seed)
            split.removeColumn(named: "__label")
            _ = annotationColumn
            return split
        }
    }
}

@available(*, unavailable)
extension MLObjectDetector.DataSource : Sendable {
}

@available(macOS 10.15, *)
@available(iOS, unavailable)
@available(tvOS, unavailable)
extension MLObjectDetector {
    public struct ObjectAnnotation : Sendable {
        public var label: String
        public var boundingBox: CGRect
        public var confidence: Double
        public init(label: String, boundingBox: CGRect, confidence: Double) {
            self.label = label
            self.boundingBox = boundingBox
            self.confidence = confidence
        }
    }
}

@available(macOS 10.15, *)
@available(iOS, unavailable)
@available(tvOS, unavailable)
extension MLObjectDetector.ObjectAnnotation : CustomStringConvertible, CustomDebugStringConvertible, CustomPlaygroundDisplayConvertible {
    public var description: String {
        get {
            "ObjectAnnotation(label: \(String(describing: label)), boundingBox: \(String(describing: boundingBox)), confidence: \(String(describing: confidence)))"
        }
    }
    public var debugDescription: String {
        get {
            "ObjectAnnotation(label: \(String(describing: label)), boundingBox: \(String(describing: boundingBox)), confidence: \(String(describing: confidence)))"
        }
    }
    public var playgroundDescription: Any {
        get {
            description
        }
    }
}

extension MLObjectDetector {
    @available(macOS 11.0, *)
    @available(iOS, unavailable)
    @available(tvOS, unavailable)
    public struct __Defaults : Sendable {
        public static var sessionParameters: MLTrainingSessionParameters { MLTrainingSessionParameters() }
    }
}

@available(macOS 10.15, *)
@available(iOS, unavailable)
@available(tvOS, unavailable)
extension MLObjectDetector {
    public struct ModelParameters {
        public var validation: MLObjectDetector.ModelParameters.ValidationData
        public var batchSize: Int?
        public var maxIterations: Int?
        @available(macOS 11.0, *)
        @available(iOS, unavailable)
        @available(tvOS, unavailable)
        public var gridSize: CGSize {
            get {
                _gridSize
            }
            set {
                _gridSize = newValue
            }
        }
        @available(macOS 11.0, *)
        @available(iOS, unavailable)
        @available(tvOS, unavailable)
        public var algorithm: MLObjectDetector.ModelParameters.ModelAlgorithmType {
            get {
                _algorithm
            }
            set {
                _algorithm = newValue
            }
        }
        @available(macOS 11.0, *)
        @available(iOS, unavailable)
        @available(tvOS, unavailable)
        public init(validation: MLObjectDetector.ModelParameters.ValidationData = .split(strategy: .automatic), batchSize: Int? = nil, maxIterations: Int? = nil, gridSize: CGSize = CGSize(width: 13, height: 13), algorithm: MLObjectDetector.ModelParameters.ModelAlgorithmType = .darknetYolo) {
            self.validation = validation
            self.batchSize = batchSize
            self.maxIterations = maxIterations
            self.gridSize = gridSize
            self.algorithm = algorithm
        }
        public init(validation: MLObjectDetector.ModelParameters.ValidationData = .split(strategy: .automatic), batchSize: Int? = nil, maxIterations: Int? = nil) {
            self.validation = validation
            self.batchSize = batchSize
            self.maxIterations = maxIterations
        }
        @available(macOS, introduced: 10.15, deprecated: 11.0)
        @available(iOS, unavailable)
        @available(tvOS, unavailable)
        public init(validationData: MLObjectDetector.DataSource, batchSize: Int? = nil, maxIterations: Int? = nil) throws {
            self.batchSize = batchSize
            self.maxIterations = maxIterations
            self.validation = .dataSource(validationData)
        }
        var _gridSize: CGSize = CGSize(width: 13, height: 13)
        var _algorithm: MLObjectDetector.ModelParameters.ModelAlgorithmType = .darknetYolo
    }
}

@available(*, unavailable)
extension MLObjectDetector.ModelParameters : Sendable {
}

@available(macOS 10.15, *)
@available(iOS, unavailable)
@available(tvOS, unavailable)
extension MLObjectDetector.ModelParameters : CustomStringConvertible, CustomDebugStringConvertible, CustomPlaygroundDisplayConvertible {
    public var description: String {
        get {
            "ModelParameters(validation: \(String(describing: validation)), batchSize: \(String(describing: batchSize)), maxIterations: \(String(describing: maxIterations)), gridSize: \(String(describing: gridSize)), algorithm: \(String(describing: algorithm)))"
        }
    }
    public var debugDescription: String {
        get {
            "ModelParameters(validation: \(String(describing: validation)), batchSize: \(String(describing: batchSize)), maxIterations: \(String(describing: maxIterations)), gridSize: \(String(describing: gridSize)), algorithm: \(String(describing: algorithm)))"
        }
    }
    public var playgroundDescription: Any {
        get {
            description
        }
    }
}

extension MLObjectDetector.ModelParameters {
    @available(macOS 11.0, *)
    @available(iOS, unavailable)
    @available(tvOS, unavailable)
    public enum FeatureExtractorType : Sendable {
        case objectPrint(revision: Int = 1)
    }
}

extension MLObjectDetector.ModelParameters {
    @available(macOS 11.0, *)
    @available(iOS, unavailable)
    @available(tvOS, unavailable)
    public enum ModelAlgorithmType : Equatable, Sendable {
        case darknetYolo
        case transferLearning(MLObjectDetector.ModelParameters.FeatureExtractorType)
        public static func == (lhs: MLObjectDetector.ModelParameters.ModelAlgorithmType, rhs: MLObjectDetector.ModelParameters.ModelAlgorithmType) -> Bool {
            switch (lhs, rhs) {
            case (.darknetYolo, .darknetYolo): return true
            case (.transferLearning(.objectPrint(let a)), .transferLearning(.objectPrint(let b))): return a == b
            default: return false
            }
        }
    }
}

@available(macOS 10.15, *)
@available(iOS, unavailable)
@available(tvOS, unavailable)
extension MLObjectDetector.ModelParameters {
    public enum ValidationData {
        case split(strategy: MLSplitStrategy)
        case dataSource(MLObjectDetector.DataSource)
        @available(macOS, introduced: 10.15, deprecated: 14.0)
        @available(iOS, unavailable)
        @available(tvOS, unavailable)
        case table(MLDataTable, imageColumn: String, annotationColumn: String)
        @available(macOS 13.0, *)
        @available(iOS, unavailable)
        @available(tvOS, unavailable)
        case dataFrame(DataFrame, imageColumn: String, annotationColumn: String)
        case none
    }
}

@available(*, unavailable)
extension MLObjectDetector.ModelParameters.ValidationData : Sendable {
}

extension MLObjectDetector {
    @available(macOS 11.0, *)
    @available(iOS, unavailable)
    @available(tvOS, unavailable)
    public init(checkpoint: MLCheckpoint) throws {
        throw trainingUnavailable(Self.self)
    }
    @available(macOS 11.0, *)
    @available(iOS, unavailable)
    @available(tvOS, unavailable)
    public static func train(trainingData: MLObjectDetector.DataSource, annotationType: MLObjectDetector.AnnotationType, parameters: MLObjectDetector.ModelParameters = ModelParameters(), sessionParameters: MLTrainingSessionParameters = __Defaults.sessionParameters) throws -> MLJob<MLObjectDetector> {
        throw trainingUnavailable(Self.self)
    }
    @available(macOS 11.0, *)
    @available(iOS, unavailable)
    @available(tvOS, unavailable)
    public static func makeTrainingSession(trainingData: MLObjectDetector.DataSource, annotationType: MLObjectDetector.AnnotationType, parameters: MLObjectDetector.ModelParameters = ModelParameters(), sessionParameters: MLTrainingSessionParameters = __Defaults.sessionParameters) throws -> MLTrainingSession<MLObjectDetector> {
        throw trainingUnavailable(Self.self)
    }
    @available(macOS 11.0, *)
    @available(iOS, unavailable)
    @available(tvOS, unavailable)
    public static func restoreTrainingSession(sessionParameters: MLTrainingSessionParameters) throws -> MLTrainingSession<MLObjectDetector> {
        throw trainingUnavailable(Self.self)
    }
    @available(macOS 11.0, *)
    @available(iOS, unavailable)
    @available(tvOS, unavailable)
    public static func resume(_ session: MLTrainingSession<MLObjectDetector>) throws -> MLJob<MLObjectDetector> {
        throw trainingUnavailable(Self.self)
    }
}
