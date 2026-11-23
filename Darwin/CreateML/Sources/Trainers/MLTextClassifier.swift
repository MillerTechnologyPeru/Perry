// MLTextClassifier: its parameters, data sources and options, which work in Perry,
// and its training, prediction and export, which need Apple's private
// engine and throw MLCreateError.generic saying so (see README.md). Its
// instance members are never reached: no instance can be made.

import CoreML
import Foundation
import NaturalLanguage
import TabularData

@available(macOS 10.14, iOS 15.0, *)
@available(tvOS, unavailable)
extension MLTextClassifier {
    public func write(to fileURL: URL, metadata: MLModelMetadata? = nil) throws {
        throw unavailable("Exporting \(Self.self)")
    }
    public func write(toFile path: String, metadata: MLModelMetadata? = nil) throws {
        throw unavailable("Exporting \(Self.self)")
    }
}

@available(macOS 10.14, iOS 15.0, *)
@available(tvOS, unavailable)
extension MLTextClassifier {
    public enum DataSource {
        case labeledDirectories(at: URL)
        public func labeledTexts() throws -> [String : [String]] {
            try gatherLabeledTexts()
        }
    }
}

@available(*, unavailable)
extension MLTextClassifier.DataSource : Sendable {
}

@available(macOS 10.14, iOS 15.0, *)
@available(tvOS, unavailable)
extension MLTextClassifier.DataSource {
    @available(macOS, introduced: 10.14, deprecated: 14.0)
    @available(iOS, introduced: 15.0, deprecated: 17.0)
    @available(tvOS, unavailable)
    public func stratifiedSplit(proportions: [Double], seed: Int = timestampSeed(), labelColumn: String, textColumn: String) throws -> MLDataTable {
        var labels: [MLDataValue] = [], texts: [MLDataValue] = []
        for (label, items) in try labeledTexts().sorted(by: { $0.key < $1.key }) {
            for text in items { labels.append(.string(label)); texts.append(.string(text)) }
        }
        let table = MLDataTable(CMLTable(names: [labelColumn, textColumn],
                                         columns: [CMLColumn(values: labels, type: .string), CMLColumn(values: texts, type: .string)]))
        return try table.stratifiedSplit(proportions: proportions, on: labelColumn, seed: seed)
    }
}

@available(macOS 10.14, iOS 15.0, *)
@available(tvOS, unavailable)
extension MLTextClassifier {
    @available(macOS 10.15, iOS 15.0, *)
    @available(tvOS, unavailable)
    public enum FeatureExtractorType : Sendable {
        case staticEmbedding
        @available(macOS, introduced: 10.15, deprecated: 14.0, renamed: "elmoEmbedding")
        @available(iOS, introduced: 15.0, deprecated: 17.0, renamed: "elmoEmbedding")
        case dynamicEmbedding
        @available(macOS 14.0, iOS 17.0, *)
        case elmoEmbedding
        @available(macOS 14.0, iOS 17.0, *)
        case bertEmbedding
        case customEmbedding(URL)
    }
}

@available(macOS 10.15, iOS 15.0, *)
@available(tvOS, unavailable)
extension MLTextClassifier.FeatureExtractorType : CustomStringConvertible, CustomDebugStringConvertible, CustomPlaygroundDisplayConvertible {
    public var description: String {
        get {
            switch self {
            case .staticEmbedding: return "staticEmbedding"
            case .dynamicEmbedding: return "dynamicEmbedding"
            case .elmoEmbedding: return "elmoEmbedding"
            case .bertEmbedding: return "bertEmbedding"
            case .customEmbedding(let v0): return "customEmbedding(\(String(describing: v0)))"
            }
        }
    }
    public var debugDescription: String {
        get {
            switch self {
            case .staticEmbedding: return "staticEmbedding"
            case .dynamicEmbedding: return "dynamicEmbedding"
            case .elmoEmbedding: return "elmoEmbedding"
            case .bertEmbedding: return "bertEmbedding"
            case .customEmbedding(let v0): return "customEmbedding(\(String(describing: v0)))"
            }
        }
    }
    public var playgroundDescription: Any {
        get {
            description
        }
    }
}

@available(macOS 10.14, iOS 15.0, *)
@available(tvOS, unavailable)
extension MLTextClassifier {
    public enum ModelAlgorithmType : Sendable {
        case maxEnt(revision: Int?)
        case crf(revision: Int?)
        @available(macOS 10.15, iOS 15.0, *)
        @available(tvOS, unavailable)
        case transferLearning(MLTextClassifier.FeatureExtractorType, revision: Int?)
    }
}

@available(macOS 10.14, iOS 15.0, *)
@available(tvOS, unavailable)
extension MLTextClassifier.ModelAlgorithmType : CustomStringConvertible, CustomDebugStringConvertible, CustomPlaygroundDisplayConvertible {
    public var description: String {
        get {
            switch self {
            case .maxEnt(let v0): return "maxEnt(\(String(describing: v0)))"
            case .crf(let v0): return "crf(\(String(describing: v0)))"
            case .transferLearning(let v0, let v1): return "transferLearning(\(String(describing: v0)), \(String(describing: v1)))"
            }
        }
    }
    public var debugDescription: String {
        get {
            switch self {
            case .maxEnt(let v0): return "maxEnt(\(String(describing: v0)))"
            case .crf(let v0): return "crf(\(String(describing: v0)))"
            case .transferLearning(let v0, let v1): return "transferLearning(\(String(describing: v0)), \(String(describing: v1)))"
            }
        }
    }
    public var playgroundDescription: Any {
        get {
            description
        }
    }
}

@available(macOS 10.14, iOS 15.0, *)
@available(tvOS, unavailable)
extension MLTextClassifier {
    public func prediction(from text: String) throws -> String {
        throw unavailable("Running \(Self.self)")
    }
    public func predictions(from texts: [String]) throws -> [String] {
        throw unavailable("Running \(Self.self)")
    }
    @available(macOS 11.0, iOS 15.0, *)
    @available(tvOS, unavailable)
    public func predictionWithConfidence(from text: String) throws -> [String : Double] {
        throw unavailable("Running \(Self.self)")
    }
    @available(macOS 11.0, iOS 15.0, *)
    @available(tvOS, unavailable)
    public func predictionsWithConfidence(from texts: [String]) throws -> [[String : Double]] {
        throw unavailable("Running \(Self.self)")
    }
}

@available(macOS 10.14, iOS 15.0, *)
@available(tvOS, unavailable)
extension MLTextClassifier {
    @available(macOS, introduced: 10.14, deprecated: 13.0, message: "Use DataSource instead of MLDataTable.")
    @available(iOS, introduced: 15.0, deprecated: 16.0, message: "Use DataFrame instead of MLDataTable.")
    @available(tvOS, unavailable)
    public func predictions(from texts: MLDataColumn<String>) throws -> MLDataColumn<String> {
        throw unavailable("Running \(Self.self)")
    }
    @available(macOS, introduced: 11.0, deprecated: 13.0, message: "Use DataFrame instead of MLDataTable.")
    @available(iOS, introduced: 15.0, deprecated: 16.0, message: "Use DataFrame instead of MLDataTable.")
    @available(tvOS, unavailable)
    public func predictionsWithConfidence(from texts: MLDataColumn<String>) throws -> MLDataColumn<[String : Double]> {
        throw unavailable("Running \(Self.self)")
    }
}

@available(macOS 10.14, iOS 15.0, *)
@available(tvOS, unavailable)
public struct MLTextClassifier : @unchecked Sendable {
    public var model: MLModel {
        get {
            unreachableTrainer(Self.self)
        }
        set {
            _ = newValue
        }
    }
    public let modelParameters: MLTextClassifier.ModelParameters
    public let trainingMetrics: MLClassifierMetrics
    public let validationMetrics: MLClassifierMetrics
    @available(macOS 10.15, iOS 15.0, *)
    @available(tvOS, unavailable)
    public init(trainingData: MLTextClassifier.DataSource, parameters: MLTextClassifier.ModelParameters = ModelParameters(validation: .split(strategy: .automatic))) throws {
        throw trainingUnavailable(Self.self)
    }
    @available(macOS 10.15, iOS 15.0, *)
    @available(tvOS, unavailable)
    public init(trainingData: [String : [String]], parameters: MLTextClassifier.ModelParameters = ModelParameters(validation: .split(strategy: .automatic))) throws {
        throw trainingUnavailable(Self.self)
    }
    @available(macOS 13.0, iOS 16.0, *)
    @available(tvOS, unavailable)
    public init(trainingData: DataFrame, textColumn: String, labelColumn: String, parameters: MLTextClassifier.ModelParameters = ModelParameters(validation: .split(strategy: .automatic))) throws {
        throw trainingUnavailable(Self.self)
    }
    @available(macOS, introduced: 10.14, deprecated: 13.0, message: "Use DataSource instead of MLDataTable when initializing.")
    @available(iOS, introduced: 15.0, deprecated: 16.0, message: "Use DataFrame instead of MLDataTable when initializing.")
    @available(tvOS, unavailable)
    public init(trainingData: MLDataTable, textColumn: String, labelColumn: String, parameters: MLTextClassifier.ModelParameters = ModelParameters(validationData: nil)) throws {
        throw trainingUnavailable(Self.self)
    }
}

@available(macOS 10.14, iOS 15.0, *)
@available(tvOS, unavailable)
extension MLTextClassifier : CustomStringConvertible, CustomDebugStringConvertible, CustomPlaygroundDisplayConvertible {
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

@available(macOS 10.14, iOS 15.0, *)
@available(tvOS, unavailable)
extension MLTextClassifier.ModelParameters {
    @available(macOS 10.15, iOS 15.0, *)
    @available(tvOS, unavailable)
    public enum ValidationData {
        case split(strategy: MLSplitStrategy)
        @available(macOS, introduced: 10.15, deprecated: 14.0)
        @available(iOS, introduced: 15.0, deprecated: 17.0)
        @available(tvOS, unavailable)
        case table(MLDataTable, textColumn: String, labelColumn: String)
        @available(macOS 13.0, iOS 16.0, *)
        @available(tvOS, unavailable)
        case dataFrame(DataFrame, textColumn: String, labelColumn: String)
        case dataSource(MLTextClassifier.DataSource)
        case dictionary([String : [String]])
        case none
    }
}

@available(*, unavailable)
extension MLTextClassifier.ModelParameters.ValidationData : Sendable {
}

@available(macOS 10.14, iOS 15.0, *)
@available(tvOS, unavailable)
extension MLTextClassifier {
    public func evaluation(on labeledTexts: MLTextClassifier.DataSource) -> MLClassifierMetrics {
        .init(error: unavailable("Evaluating \(Self.self)"))
    }
    public func evaluation(on labeledTexts: [String : [String]]) -> MLClassifierMetrics {
        .init(error: unavailable("Evaluating \(Self.self)"))
    }
    @available(macOS 13.0, iOS 16.0, *)
    @available(tvOS, unavailable)
    public func evaluation(on dataFrame: DataFrame, textColumn: String, labelColumn: String) -> MLClassifierMetrics {
        .init(error: unavailable("Evaluating \(Self.self)"))
    }
}

@available(macOS 10.14, iOS 15.0, *)
@available(tvOS, unavailable)
extension MLTextClassifier {
    @available(macOS, introduced: 10.14, deprecated: 13.0, message: "Use DataFrame instead of MLDataTable.")
    @available(iOS, introduced: 15.0, deprecated: 16.0, message: "Use DataFrame instead of MLDataTable.")
    @available(tvOS, unavailable)
    public func evaluation(on labeledTexts: MLDataTable, textColumn: String, labelColumn: String) -> MLClassifierMetrics {
        .init(error: unavailable("Evaluating \(Self.self)"))
    }
}

@available(macOS 10.14, iOS 15.0, *)
@available(tvOS, unavailable)
extension MLTextClassifier {
    public struct ModelParameters {
        public var algorithm: MLTextClassifier.ModelAlgorithmType
        public var language: NLLanguage?
        @available(macOS 10.15, iOS 15.0, *)
        @available(tvOS, unavailable)
        public var validation: MLTextClassifier.ModelParameters.ValidationData {
            get {
                _validation
            }
            set {
                _validation = newValue
            }
        }
        @available(macOS 11.0, iOS 15.0, *)
        @available(tvOS, unavailable)
        public var maxIterations: Int? {
            get {
                _maxIterations
            }
            set {
                _maxIterations = newValue
            }
        }
        @available(macOS 10.15, iOS 15.0, *)
        @available(tvOS, unavailable)
        public init(validation: MLTextClassifier.ModelParameters.ValidationData = .split(strategy: .automatic), algorithm: MLTextClassifier.ModelAlgorithmType = .maxEnt(revision: 1), language: NLLanguage? = nil) {
            self.algorithm = algorithm
            self.language = language
            self.validation = validation
        }
        var _validation: MLTextClassifier.ModelParameters.ValidationData = .split(strategy: .automatic)
        var _maxIterations: Int? = nil
        var _textColumnValidationData: String? = nil
        var _labelColumnValidationData: String? = nil
    }
}

@available(*, unavailable)
extension MLTextClassifier.ModelParameters : Sendable {
}

@available(macOS 10.14, iOS 15.0, *)
@available(tvOS, unavailable)
extension MLTextClassifier.ModelParameters : CustomStringConvertible, CustomDebugStringConvertible, CustomPlaygroundDisplayConvertible {
    public var description: String {
        get {
            "ModelParameters(algorithm: \(String(describing: algorithm)), language: \(String(describing: language)), validation: \(String(describing: validation)), maxIterations: \(String(describing: maxIterations)), validationData: \(String(describing: validationData)), textColumnValidationData: \(String(describing: textColumnValidationData)), labelColumnValidationData: \(String(describing: labelColumnValidationData)))"
        }
    }
    public var debugDescription: String {
        get {
            "ModelParameters(algorithm: \(String(describing: algorithm)), language: \(String(describing: language)), validation: \(String(describing: validation)), maxIterations: \(String(describing: maxIterations)), validationData: \(String(describing: validationData)), textColumnValidationData: \(String(describing: textColumnValidationData)), labelColumnValidationData: \(String(describing: labelColumnValidationData)))"
        }
    }
    public var playgroundDescription: Any {
        get {
            description
        }
    }
}

@available(macOS 10.14, iOS 15.0, *)
@available(tvOS, unavailable)
extension MLTextClassifier.ModelParameters {
    @available(macOS, introduced: 10.14, deprecated: 10.15, message: "Use the validation property instead.")
    @available(iOS, introduced: 15.0, deprecated: 16.0, message: "Use the validation property instead.")
    @available(tvOS, unavailable)
    public var validationData: MLDataTable? {
        get {
            if case .table(let table, _, _) = validation { return table }
                return nil
        }
        set {
            validation = newValue.map { .table($0, textColumn: textColumnValidationData ?? "text", labelColumn: labelColumnValidationData ?? "label") } ?? .none
        }
    }
    @available(macOS, introduced: 10.14, deprecated: 10.15, message: "Use the validation property instead.")
    @available(iOS, introduced: 15.0, deprecated: 16.0, message: "Use the validation property instead.")
    @available(tvOS, unavailable)
    public var textColumnValidationData: String? {
        get {
            if case .table(_, let column, _) = validation { return column }
                return _textColumnValidationData
        }
        set {
            _textColumnValidationData = newValue
                if case .table(let table, _, let label) = validation { validation = .table(table, textColumn: newValue ?? "text", labelColumn: label) }
        }
    }
    @available(macOS, introduced: 10.14, deprecated: 10.15, message: "Use the validation property instead.")
    @available(iOS, introduced: 15.0, deprecated: 16.0, message: "Use the validation property instead.")
    @available(tvOS, unavailable)
    public init(validationData: MLTextClassifier.DataSource, algorithm: MLTextClassifier.ModelAlgorithmType = .maxEnt(revision: 1), language: NLLanguage? = nil) {
        self.algorithm = algorithm
        self.language = language
        self.validation = .dataSource(validationData)
    }
    @available(macOS, introduced: 10.14, deprecated: 10.15, message: "Use the validation property instead.")
    @available(iOS, introduced: 15.0, deprecated: 16.0, message: "Use the validation property instead.")
    @available(tvOS, unavailable)
    public init(validationData: [String : [String]], algorithm: MLTextClassifier.ModelAlgorithmType = .maxEnt(revision: 1), language: NLLanguage? = nil) {
        self.algorithm = algorithm
        self.language = language
        self.validation = .dictionary(validationData)
    }
    @available(macOS, introduced: 10.14, deprecated: 10.15, message: "Use the validation property instead.")
    @available(iOS, introduced: 15.0, deprecated: 16.0, message: "Use the validation property instead.")
    @available(tvOS, unavailable)
    public init(validationData: MLDataTable? = nil, algorithm: MLTextClassifier.ModelAlgorithmType = .maxEnt(revision: 1), language: NLLanguage? = nil, textColumnValidationData: String? = nil, labelColumnValidationData: String? = nil) {
        self.algorithm = algorithm
        self.language = language
        self.validationData = validationData
        self.textColumnValidationData = textColumnValidationData
        self.labelColumnValidationData = labelColumnValidationData
    }
    @available(macOS, introduced: 10.14, deprecated: 10.15, message: "Use the validation property instead.")
    @available(iOS, introduced: 15.0, deprecated: 16.0, message: "Use the validation property instead.")
    @available(tvOS, unavailable)
    public var labelColumnValidationData: String? {
        get {
            if case .table(_, _, let column) = validation { return column }
                return _labelColumnValidationData
        }
        set {
            _labelColumnValidationData = newValue
                if case .table(let table, let column, _) = validation { validation = .table(table, textColumn: column, labelColumn: newValue ?? "label") }
        }
    }
}
