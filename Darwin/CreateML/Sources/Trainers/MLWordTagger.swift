// MLWordTagger: its parameters, data sources and options, which work in Perry,
// and its training, prediction and export, which need Apple's private
// engine and throw MLCreateError.generic saying so (see README.md). Its
// instance members are never reached: no instance can be made.

import CoreML
import Foundation
import NaturalLanguage
import TabularData

@available(macOS 10.14, *)
@available(iOS, unavailable)
@available(tvOS, unavailable)
extension MLWordTagger {
    public func evaluation(on labeledTokens: [(tokens: [MLWordTagger.Token], labels: [String])]) -> MLWordTaggerMetrics {
        .init(error: unavailable("Evaluating \(Self.self)"))
    }
    @available(macOS 13.0, *)
    @available(iOS, unavailable)
    @available(tvOS, unavailable)
    public func evaluation(on labeledTokens: DataFrame, tokenColumn: String, labelColumn: String) -> MLWordTaggerMetrics {
        .init(error: unavailable("Evaluating \(Self.self)"))
    }
    @available(macOS, introduced: 10.14, deprecated: 13.0)
    @available(iOS, unavailable)
    @available(tvOS, unavailable)
    public func evaluation(on labeledTokens: MLDataTable, tokenColumn: String, labelColumn: String) -> MLWordTaggerMetrics {
        .init(error: unavailable("Evaluating \(Self.self)"))
    }
}

@available(macOS 10.14, *)
@available(iOS, unavailable)
@available(tvOS, unavailable)
public struct MLWordTagger : @unchecked Sendable {
    public typealias Token = String
    public var model: MLModel {
        get {
            unreachableTrainer(Self.self)
        }
        set {
            _ = newValue
        }
    }
    public let modelParameters: MLWordTagger.ModelParameters
    public let trainingMetrics: MLWordTaggerMetrics
    public let validationMetrics: MLWordTaggerMetrics
    @available(macOS 10.15, *)
    @available(iOS, unavailable)
    @available(tvOS, unavailable)
    public init(trainingData: [(tokens: [MLWordTagger.Token], labels: [String])], parameters: MLWordTagger.ModelParameters = ModelParameters(validation: .split(strategy: .automatic))) throws {
        throw trainingUnavailable(Self.self)
    }
    @available(macOS 13.0, *)
    @available(iOS, unavailable)
    @available(tvOS, unavailable)
    public init(trainingData: DataFrame, tokenColumn: String, labelColumn: String, parameters: MLWordTagger.ModelParameters = ModelParameters(validation: .split(strategy: .automatic))) throws {
        throw trainingUnavailable(Self.self)
    }
    @available(macOS, introduced: 10.14, deprecated: 13.0, message: "Use DataFrame instead of MLDataTable when initializing.")
    @available(iOS, unavailable)
    @available(tvOS, unavailable)
    public init(trainingData: MLDataTable, tokenColumn: String, labelColumn: String, parameters: MLWordTagger.ModelParameters = ModelParameters(validationData: nil)) throws {
        throw trainingUnavailable(Self.self)
    }
}

@available(macOS 10.14, *)
@available(iOS, unavailable)
@available(tvOS, unavailable)
extension MLWordTagger : CustomStringConvertible, CustomDebugStringConvertible, CustomPlaygroundDisplayConvertible {
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

@available(macOS 10.14, *)
@available(iOS, unavailable)
@available(tvOS, unavailable)
extension MLWordTagger {
    public enum ModelAlgorithmType : Sendable {
        case crf(revision: Int?)
        @available(macOS 11.0, *)
        @available(iOS, unavailable)
        @available(tvOS, unavailable)
        case transferLearning(MLWordTagger.FeatureExtractorType, revision: Int = 1)
    }
}

@available(macOS 10.14, *)
@available(iOS, unavailable)
@available(tvOS, unavailable)
extension MLWordTagger.ModelAlgorithmType : CustomStringConvertible, CustomDebugStringConvertible, CustomPlaygroundDisplayConvertible {
    public var description: String {
        get {
            switch self {
            case .crf(let v0): return "crf(\(String(describing: v0)))"
            case .transferLearning(let v0, let v1): return "transferLearning(\(String(describing: v0)), \(String(describing: v1)))"
            }
        }
    }
    public var debugDescription: String {
        get {
            switch self {
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

@available(macOS 10.14, *)
@available(iOS, unavailable)
@available(tvOS, unavailable)
extension MLWordTagger.ModelParameters {
    @available(macOS 10.15, *)
    @available(iOS, unavailable)
    @available(tvOS, unavailable)
    public enum ValidationData {
        case split(strategy: MLSplitStrategy)
        @available(macOS, introduced: 10.15, deprecated: 14.0)
        @available(iOS, unavailable)
        @available(tvOS, unavailable)
        case table(MLDataTable, tokenColumn: String, labelColumn: String)
        @available(macOS 13.0, iOS 16.0, tvOS 16.0, *)
        case dataFrame(DataFrame, tokenColumn: String, labelColumn: String)
        case tuples([(tokens: [MLWordTagger.Token], labels: [String])])
        case none
    }
}

@available(*, unavailable)
extension MLWordTagger.ModelParameters.ValidationData : Sendable {
}

@available(macOS 10.14, *)
@available(iOS, unavailable)
@available(tvOS, unavailable)
extension MLWordTagger {
    public func write(to fileURL: URL, metadata: MLModelMetadata? = nil) throws {
        throw unavailable("Exporting \(Self.self)")
    }
    public func write(toFile path: String, metadata: MLModelMetadata? = nil) throws {
        throw unavailable("Exporting \(Self.self)")
    }
}

@available(macOS 10.14, *)
@available(iOS, unavailable)
@available(tvOS, unavailable)
extension MLWordTagger {
    public struct ModelParameters {
        public var algorithm: MLWordTagger.ModelAlgorithmType
        public var language: NLLanguage?
        @available(macOS, introduced: 10.14, deprecated: 10.15, message: "Use the validation property instead.")
        @available(iOS, introduced: 15.0, deprecated: 16.0, message: "Use the validation property instead.")
        @available(tvOS, unavailable)
        public var validationData: MLDataTable? {
            get {
                if case .table(let table, _, _) = validation { return table }
                return nil
            }
            set {
                validation = newValue.map { .table($0, tokenColumn: tokenColumnValidationData ?? "token", labelColumn: labelColumnValidationData ?? "label") } ?? .none
            }
        }
        @available(macOS, introduced: 10.14, deprecated: 10.15, message: "Use the validation property instead.")
        @available(iOS, introduced: 15.0, deprecated: 16.0, message: "Use the validation property instead.")
        @available(tvOS, unavailable)
        public var tokenColumnValidationData: String? {
            get {
                if case .table(_, let column, _) = validation { return column }
                return _tokenColumnValidationData
            }
            set {
                _tokenColumnValidationData = newValue
                if case .table(let table, _, let label) = validation { validation = .table(table, tokenColumn: newValue ?? "token", labelColumn: label) }
            }
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
                if case .table(let table, let column, _) = validation { validation = .table(table, tokenColumn: column, labelColumn: newValue ?? "label") }
            }
        }
        @available(macOS 11.0, *)
        @available(iOS, unavailable)
        @available(tvOS, unavailable)
        public var maxIterations: Int? {
            get {
                _maxIterations
            }
            set {
                _maxIterations = newValue
            }
        }
        @available(macOS 10.15, *)
        @available(iOS, unavailable)
        @available(tvOS, unavailable)
        public var validation: MLWordTagger.ModelParameters.ValidationData {
            get {
                _validation
            }
            set {
                _validation = newValue
            }
        }
        @available(macOS 10.15, *)
        @available(iOS, unavailable)
        @available(tvOS, unavailable)
        public init(validation: MLWordTagger.ModelParameters.ValidationData = .split(strategy: .automatic), algorithm: MLWordTagger.ModelAlgorithmType = .crf(revision: 1), language: NLLanguage? = nil) {
            self.algorithm = algorithm
            self.language = language
            self.validation = validation
        }
        @available(macOS, introduced: 10.14, deprecated: 10.15, message: "Use the validation property instead.")
        @available(iOS, introduced: 15.0, deprecated: 16.0, message: "Use the validation property instead.")
        @available(tvOS, unavailable)
        public init(validationData: MLDataTable?, algorithm: MLWordTagger.ModelAlgorithmType = .crf(revision: 1), language: NLLanguage? = nil, tokenColumnValidationData: String? = nil, labelColumnValidationData: String? = nil) {
            self.algorithm = algorithm
            self.language = language
            self.validationData = validationData
            self.tokenColumnValidationData = tokenColumnValidationData
            self.labelColumnValidationData = labelColumnValidationData
        }
        @available(macOS, introduced: 10.14, deprecated: 10.15, message: "Use the validation property instead.")
        @available(iOS, introduced: 15.0, deprecated: 16.0, message: "Use the validation property instead.")
        @available(tvOS, unavailable)
        public init(validationData: [(tokens: [MLWordTagger.Token], labels: [String])], algorithm: MLWordTagger.ModelAlgorithmType = .crf(revision: 1), language: NLLanguage? = nil) {
            self.algorithm = algorithm
            self.language = language
            self.validation = .tuples(validationData)
        }
        var _tokenColumnValidationData: String? = nil
        var _labelColumnValidationData: String? = nil
        var _maxIterations: Int? = nil
        var _validation: MLWordTagger.ModelParameters.ValidationData = .split(strategy: .automatic)
    }
}

@available(*, unavailable)
extension MLWordTagger.ModelParameters : Sendable {
}

@available(macOS 10.14, *)
@available(iOS, unavailable)
@available(tvOS, unavailable)
extension MLWordTagger.ModelParameters : CustomStringConvertible, CustomDebugStringConvertible, CustomPlaygroundDisplayConvertible {
    public var description: String {
        get {
            "ModelParameters(algorithm: \(String(describing: algorithm)), language: \(String(describing: language)), validationData: \(String(describing: validationData)), tokenColumnValidationData: \(String(describing: tokenColumnValidationData)), labelColumnValidationData: \(String(describing: labelColumnValidationData)), maxIterations: \(String(describing: maxIterations)), validation: \(String(describing: validation)))"
        }
    }
    public var debugDescription: String {
        get {
            "ModelParameters(algorithm: \(String(describing: algorithm)), language: \(String(describing: language)), validationData: \(String(describing: validationData)), tokenColumnValidationData: \(String(describing: tokenColumnValidationData)), labelColumnValidationData: \(String(describing: labelColumnValidationData)), maxIterations: \(String(describing: maxIterations)), validation: \(String(describing: validation)))"
        }
    }
    public var playgroundDescription: Any {
        get {
            description
        }
    }
}

@available(macOS 10.14, *)
@available(iOS, unavailable)
@available(tvOS, unavailable)
extension MLWordTagger {
    @available(macOS 11.0, *)
    @available(iOS, unavailable)
    @available(tvOS, unavailable)
    public enum FeatureExtractorType : Sendable {
        @available(macOS, introduced: 11.0, deprecated: 14.0, renamed: "elmoEmbedding")
        case dynamicEmbedding
        @available(macOS 14.0, *)
        case elmoEmbedding
        @available(macOS 14.0, *)
        case bertEmbedding
    }
}

@available(macOS 11.0, *)
@available(iOS, unavailable)
@available(tvOS, unavailable)
extension MLWordTagger.FeatureExtractorType : CustomStringConvertible, CustomDebugStringConvertible, CustomPlaygroundDisplayConvertible {
    public var description: String {
        get {
            switch self {
            case .dynamicEmbedding: return "dynamicEmbedding"
            case .elmoEmbedding: return "elmoEmbedding"
            case .bertEmbedding: return "bertEmbedding"
            }
        }
    }
    public var debugDescription: String {
        get {
            switch self {
            case .dynamicEmbedding: return "dynamicEmbedding"
            case .elmoEmbedding: return "elmoEmbedding"
            case .bertEmbedding: return "bertEmbedding"
            }
        }
    }
    public var playgroundDescription: Any {
        get {
            description
        }
    }
}

@available(macOS 10.14, *)
@available(iOS, unavailable)
@available(tvOS, unavailable)
extension MLWordTagger {
    public func prediction(from text: String) throws -> [String] {
        throw unavailable("Running \(Self.self)")
    }
    public func prediction(from tokens: [MLWordTagger.Token]) throws -> [String] {
        throw unavailable("Running \(Self.self)")
    }
    @available(macOS 13.0, *)
    @available(iOS, unavailable)
    @available(tvOS, unavailable)
    public func predictions<S>(from texts: S) throws -> DataFrame where S : Sequence, S.Element == String {
        throw unavailable("Running \(Self.self)")
    }
    @available(macOS, introduced: 10.14, deprecated: 13.0)
    @available(iOS, unavailable)
    @available(tvOS, unavailable)
    public func predictions(from texts: MLDataColumn<String>) throws -> MLDataTable {
        throw unavailable("Running \(Self.self)")
    }
    @available(macOS 11.0, *)
    @available(iOS, unavailable)
    @available(tvOS, unavailable)
    public func predictionWithConfidence(from text: String) throws -> [[String : Double]] {
        throw unavailable("Running \(Self.self)")
    }
    @available(macOS 11.0, *)
    @available(iOS, unavailable)
    @available(tvOS, unavailable)
    public func predictionWithConfidence(from tokens: [MLWordTagger.Token]) throws -> [[String : Double]] {
        throw unavailable("Running \(Self.self)")
    }
}

@available(macOS 11.0, *)
@available(iOS, unavailable)
@available(tvOS, unavailable)
extension MLWordTagger.FeatureExtractorType : Equatable {}

@available(macOS 11.0, *)
@available(iOS, unavailable)
@available(tvOS, unavailable)
extension MLWordTagger.FeatureExtractorType : Hashable {}
