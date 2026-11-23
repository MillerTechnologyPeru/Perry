// MLDecisionTreeClassifier: its parameters, data sources and options, which work in Perry,
// and its training, prediction and export, which need Apple's private
// engine and throw MLCreateError.generic saying so (see README.md). Its
// instance members are never reached: no instance can be made.

import CoreML
import Foundation
import TabularData

extension MLDecisionTreeClassifier.ModelParameters {
    @available(macOS 10.15, iOS 15.0, tvOS 16.0, *)
    public enum ValidationData {
        case split(strategy: MLSplitStrategy)
        @available(macOS, introduced: 10.15, deprecated: 14.0)
        @available(iOS, introduced: 15.0, deprecated: 17.0)
        @available(tvOS, introduced: 16.0, deprecated: 17.0)
        case table(MLDataTable)
        @available(macOS 12.0, iOS 15.0, tvOS 16.0, *)
        case dataFrame(DataFrame)
        case none
    }
}

@available(*, unavailable)
extension MLDecisionTreeClassifier.ModelParameters.ValidationData : Sendable {
}

@available(macOS 10.14, iOS 15.0, tvOS 16.0, *)
public struct MLDecisionTreeClassifier : @unchecked Sendable {
    public var model: MLModel {
        get {
            unreachableTrainer(Self.self)
        }
        set {
            _ = newValue
        }
    }
    public var targetColumn: String
    public var featureColumns: [String]
    public let modelParameters: MLDecisionTreeClassifier.ModelParameters
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
    @available(macOS 12.0, iOS 15.0, tvOS 16.0, *)
    public static var _defaultSessionParameters: MLTrainingSessionParameters { MLTrainingSessionParameters() }
    @available(macOS 12.0, iOS 15.0, tvOS 16.0, *)
    public init(trainingData: DataFrame, targetColumn: String, featureColumns: [String]? = nil, parameters: MLDecisionTreeClassifier.ModelParameters = ModelParameters(validation: .split(strategy: .automatic))) throws {
        throw trainingUnavailable(Self.self)
    }
    @available(macOS, introduced: 10.14, deprecated: 13.0, message: "Use DataFrame instead of MLDataTable when initializing.")
    @available(iOS, introduced: 15.0, deprecated: 16.0, message: "Use DataFrame instead of MLDataTable when initializing.")
    @available(tvOS, unavailable)
    public init(trainingData: MLDataTable, targetColumn: String, featureColumns: [String]? = nil, parameters: MLDecisionTreeClassifier.ModelParameters = ModelParameters(validationData: nil)) throws {
        throw trainingUnavailable(Self.self)
    }
    @available(macOS 12.0, iOS 15.0, tvOS 16.0, *)
    public init(checkpoint: MLCheckpoint) throws {
        throw trainingUnavailable(Self.self)
    }
    @available(macOS, introduced: 12.0, deprecated: 14.0)
    @available(iOS, introduced: 15.0, deprecated: 17.0)
    @available(tvOS, introduced: 16.0, deprecated: 17.0)
    public static func train(trainingData: MLDataTable, targetColumn: String, featureColumns: [String]? = nil, parameters: MLDecisionTreeClassifier.ModelParameters = ModelParameters(), sessionParameters: MLTrainingSessionParameters = _defaultSessionParameters) throws -> MLJob<MLDecisionTreeClassifier> {
        throw trainingUnavailable(Self.self)
    }
    @available(macOS 12.0, iOS 15.0, tvOS 16.0, *)
    public static func train(trainingData: DataFrame, targetColumn: String, featureColumns: [String]? = nil, parameters: MLDecisionTreeClassifier.ModelParameters = ModelParameters(), sessionParameters: MLTrainingSessionParameters = _defaultSessionParameters) throws -> MLJob<MLDecisionTreeClassifier> {
        throw trainingUnavailable(Self.self)
    }
    @available(macOS, introduced: 12.0, deprecated: 14.0)
    @available(iOS, introduced: 15.0, deprecated: 17.0)
    @available(tvOS, introduced: 16.0, deprecated: 17.0)
    public static func makeTrainingSession(trainingData: MLDataTable, targetColumn: String, featureColumns: [String]? = nil, parameters: MLDecisionTreeClassifier.ModelParameters = .init(), sessionParameters: MLTrainingSessionParameters = _defaultSessionParameters) throws -> MLTrainingSession<MLDecisionTreeClassifier> {
        throw trainingUnavailable(Self.self)
    }
    @available(macOS 12.0, iOS 15.0, tvOS 16.0, *)
    public static func makeTrainingSession(trainingData: DataFrame, targetColumn: String, featureColumns: [String]? = nil, parameters: MLDecisionTreeClassifier.ModelParameters = .init(), sessionParameters: MLTrainingSessionParameters = _defaultSessionParameters) throws -> MLTrainingSession<MLDecisionTreeClassifier> {
        throw trainingUnavailable(Self.self)
    }
    @available(macOS 12.0, iOS 15.0, tvOS 16.0, *)
    public static func restoreTrainingSession(sessionParameters: MLTrainingSessionParameters) throws -> MLTrainingSession<MLDecisionTreeClassifier> {
        throw trainingUnavailable(Self.self)
    }
    @available(macOS 12.0, iOS 15.0, tvOS 16.0, *)
    public static func resume(_ session: MLTrainingSession<MLDecisionTreeClassifier>) throws -> MLJob<MLDecisionTreeClassifier> {
        throw trainingUnavailable(Self.self)
    }
    @available(macOS 12.0, iOS 15.0, tvOS 16.0, *)
    public func predictions(from data: DataFrame) throws -> AnyColumn {
        throw unavailable("Running \(Self.self)")
    }
    @available(macOS, introduced: 10.14, deprecated: 13.0, message: "Use DataFrame instead of MLDataTable.")
    @available(iOS, introduced: 15.0, deprecated: 16.0, message: "Use DataFrame instead of MLDataTable.")
    @available(tvOS, unavailable)
    public func predictions(from data: MLDataTable) throws -> MLUntypedColumn {
        throw unavailable("Running \(Self.self)")
    }
    @available(macOS 12.0, iOS 15.0, tvOS 16.0, *)
    public func evaluation(on labeledData: DataFrame) -> MLClassifierMetrics {
        .init(error: unavailable("Evaluating \(Self.self)"))
    }
    @available(macOS, introduced: 10.14, deprecated: 13.0, message: "Use DataFrame instead of MLDataTable.")
    @available(iOS, introduced: 15.0, deprecated: 16.0, message: "Use DataFrame instead of MLDataTable.")
    @available(tvOS, unavailable)
    public func evaluation(on labeledData: MLDataTable) -> MLClassifierMetrics {
        .init(error: unavailable("Evaluating \(Self.self)"))
    }
    public func write(to fileURL: URL, metadata: MLModelMetadata? = nil) throws {
        throw unavailable("Exporting \(Self.self)")
    }
    public func write(toFile path: String, metadata: MLModelMetadata? = nil) throws {
        throw unavailable("Exporting \(Self.self)")
    }
}

@available(macOS 10.14, iOS 15.0, tvOS 16.0, *)
extension MLDecisionTreeClassifier : CustomStringConvertible, CustomDebugStringConvertible, CustomPlaygroundDisplayConvertible {
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

extension MLDecisionTreeClassifier {
    @available(macOS 10.14, iOS 15.0, tvOS 16.0, *)
    public struct ModelParameters {
        public var maxDepth: Int
        @available(macOS, introduced: 10.14, deprecated: 10.15, message: "Use the validation property instead.")
        @available(iOS, introduced: 15.0, deprecated: 16.0, message: "Use the validation property instead.")
        @available(tvOS, unavailable)
        public var validationData: MLDataTable? {
            get {
                if case .table(let table) = validation { return table }
                return nil
            }
            set {
                validation = newValue.map { .table($0) } ?? .none
            }
        }
        @available(macOS 10.15, iOS 15.0, tvOS 16.0, *)
        public var validation: MLDecisionTreeClassifier.ModelParameters.ValidationData {
            get {
                _validation
            }
            set {
                _validation = newValue
            }
        }
        public var minLossReduction: Double
        public var minChildWeight: Double
        public var randomSeed: Int
        @available(macOS 10.15, iOS 15.0, tvOS 16.0, *)
        public init(validation: MLDecisionTreeClassifier.ModelParameters.ValidationData = .split(strategy: .automatic), maxDepth: Int = 6, minLossReduction: Double = 0, minChildWeight: Double = 0.1, randomSeed: Int = 42) {
            self.maxDepth = maxDepth
            self.minLossReduction = minLossReduction
            self.minChildWeight = minChildWeight
            self.randomSeed = randomSeed
            self.validation = validation
        }
        @available(macOS, introduced: 10.14, deprecated: 10.15, message: "Use the validation property instead.")
        @available(iOS, introduced: 15.0, deprecated: 16.0, message: "Use the validation property instead.")
        @available(tvOS, unavailable)
        public init(validationData: MLDataTable?, maxDepth: Int = 6, minLossReduction: Double = 0, minChildWeight: Double = 0.1, randomSeed: Int = 42) {
            self.maxDepth = maxDepth
            self.minLossReduction = minLossReduction
            self.minChildWeight = minChildWeight
            self.randomSeed = randomSeed
            self.validationData = validationData
        }
        var _validation: MLDecisionTreeClassifier.ModelParameters.ValidationData = .split(strategy: .automatic)
    }
}

@available(*, unavailable)
extension MLDecisionTreeClassifier.ModelParameters : Sendable {
}

@available(macOS 10.14, iOS 15.0, tvOS 16.0, *)
extension MLDecisionTreeClassifier.ModelParameters : CustomStringConvertible, CustomDebugStringConvertible, CustomPlaygroundDisplayConvertible {
    public var description: String {
        get {
            "ModelParameters(maxDepth: \(String(describing: maxDepth)), minLossReduction: \(String(describing: minLossReduction)), minChildWeight: \(String(describing: minChildWeight)), randomSeed: \(String(describing: randomSeed)), validation: \(String(describing: validation)))"
        }
    }
    public var debugDescription: String {
        get {
            "ModelParameters(maxDepth: \(String(describing: maxDepth)), minLossReduction: \(String(describing: minLossReduction)), minChildWeight: \(String(describing: minChildWeight)), randomSeed: \(String(describing: randomSeed)), validation: \(String(describing: validation)))"
        }
    }
    public var playgroundDescription: Any {
        get {
            description
        }
    }
}
