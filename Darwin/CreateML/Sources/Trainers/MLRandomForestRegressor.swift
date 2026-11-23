// MLRandomForestRegressor: its parameters, data sources and options, which work in Perry,
// and its training, prediction and export, which need Apple's private
// engine and throw MLCreateError.generic saying so (see README.md). Its
// instance members are never reached: no instance can be made.

import CoreML
import Foundation
import TabularData

@available(macOS 10.14, iOS 15.0, tvOS 16.0, *)
public struct MLRandomForestRegressor : @unchecked Sendable {
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
    public let modelParameters: MLRandomForestRegressor.ModelParameters
    public var trainingMetrics: MLRegressorMetrics {
        get {
            .init(error: trainingUnavailable(Self.self))
        }
    }
    public var validationMetrics: MLRegressorMetrics {
        get {
            .init(error: trainingUnavailable(Self.self))
        }
    }
    @available(macOS 12.0, iOS 15.0, tvOS 16.0, *)
    public static var _defaultSessionParameters: MLTrainingSessionParameters { MLTrainingSessionParameters() }
    @available(macOS 12.0, iOS 15.0, tvOS 16.0, *)
    public init(trainingData: DataFrame, targetColumn: String, featureColumns: [String]? = nil, parameters: MLRandomForestRegressor.ModelParameters = ModelParameters(validation: .split(strategy: .automatic))) throws {
        throw trainingUnavailable(Self.self)
    }
    @available(macOS, introduced: 10.14, deprecated: 13.0, message: "Use DataFrame instead of MLDataTable when initializing.")
    @available(iOS, introduced: 15.0, deprecated: 16.0, message: "Use DataFrame instead of MLDataTable when initializing.")
    @available(tvOS, unavailable)
    public init(trainingData: MLDataTable, targetColumn: String, featureColumns: [String]? = nil, parameters: MLRandomForestRegressor.ModelParameters = ModelParameters(validationData: nil)) throws {
        throw trainingUnavailable(Self.self)
    }
    @available(macOS 12.0, iOS 15.0, tvOS 16.0, *)
    public init(checkpoint: MLCheckpoint) throws {
        throw trainingUnavailable(Self.self)
    }
    @available(macOS, introduced: 12.0, deprecated: 14.0)
    @available(iOS, introduced: 15.0, deprecated: 17.0)
    @available(tvOS, introduced: 16.0, deprecated: 17.0)
    public static func train(trainingData: MLDataTable, targetColumn: String, featureColumns: [String]? = nil, parameters: MLRandomForestRegressor.ModelParameters = ModelParameters(validation: .split(strategy: .automatic)), sessionParameters: MLTrainingSessionParameters = _defaultSessionParameters) throws -> MLJob<MLRandomForestRegressor> {
        throw trainingUnavailable(Self.self)
    }
    @available(macOS 12.0, iOS 15.0, tvOS 16.0, *)
    public static func train(trainingData: DataFrame, targetColumn: String, featureColumns: [String]? = nil, parameters: MLRandomForestRegressor.ModelParameters = .init(validation: .split(strategy: .automatic)), sessionParameters: MLTrainingSessionParameters = _defaultSessionParameters) throws -> MLJob<MLRandomForestRegressor> {
        throw trainingUnavailable(Self.self)
    }
    @available(macOS, introduced: 12.0, deprecated: 14.0)
    @available(iOS, introduced: 15.0, deprecated: 17.0)
    @available(tvOS, introduced: 16.0, deprecated: 17.0)
    public static func makeTrainingSession(trainingData: MLDataTable, targetColumn: String, featureColumns: [String]? = nil, parameters: MLRandomForestRegressor.ModelParameters = ModelParameters(validation: .split(strategy: .automatic)), sessionParameters: MLTrainingSessionParameters = _defaultSessionParameters) throws -> MLTrainingSession<MLRandomForestRegressor> {
        throw trainingUnavailable(Self.self)
    }
    @available(macOS 12.0, iOS 15.0, tvOS 16.0, *)
    public static func makeTrainingSession(trainingData: DataFrame, targetColumn: String, featureColumns: [String]? = nil, parameters: MLRandomForestRegressor.ModelParameters = .init(validation: .split(strategy: .automatic)), sessionParameters: MLTrainingSessionParameters = _defaultSessionParameters) throws -> MLTrainingSession<MLRandomForestRegressor> {
        throw trainingUnavailable(Self.self)
    }
    @available(macOS 12.0, iOS 15.0, tvOS 16.0, *)
    public static func restoreTrainingSession(sessionParameters: MLTrainingSessionParameters) throws -> MLTrainingSession<MLRandomForestRegressor> {
        throw trainingUnavailable(Self.self)
    }
    @available(macOS 12.0, iOS 15.0, tvOS 16.0, *)
    public static func resume(_ session: MLTrainingSession<MLRandomForestRegressor>) throws -> MLJob<MLRandomForestRegressor> {
        throw trainingUnavailable(Self.self)
    }
    @available(macOS 12.0, iOS 15.0, tvOS 16.0, *)
    public func predictions(from data: DataFrame) throws -> AnyColumn {
        throw unavailable("Running \(Self.self)")
    }
    @available(macOS, deprecated: 13.0, message: "Use DataFrame instead of MLDataTable.")
    @available(iOS, deprecated: 16.0, message: "Use DataFrame instead of MLDataTable.")
    @available(tvOS, deprecated: 16.0, message: "Use DataFrame instead of MLDataTable.")
    public func predictions(from data: MLDataTable) throws -> MLUntypedColumn {
        throw unavailable("Running \(Self.self)")
    }
    @available(macOS 12.0, iOS 15.0, tvOS 16.0, *)
    public func evaluation(on labeledData: DataFrame) -> MLRegressorMetrics {
        .init(error: unavailable("Evaluating \(Self.self)"))
    }
    @available(macOS, introduced: 10.14, deprecated: 13.0, message: "Use DataFrame instead of MLDataTable.")
    @available(iOS, introduced: 15.0, deprecated: 16.0, message: "Use DataFrame instead of MLDataTable.")
    @available(tvOS, unavailable)
    public func evaluation(on labeledData: MLDataTable) -> MLRegressorMetrics {
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
extension MLRandomForestRegressor : CustomStringConvertible, CustomDebugStringConvertible, CustomPlaygroundDisplayConvertible {
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

extension MLRandomForestRegressor {
    @available(macOS 10.14, iOS 15.0, tvOS 16.0, *)
    public struct ModelParameters {
        @available(macOS, introduced: 10.14, deprecated: 11.0, message: "Use the validation property instead.")
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
        @available(macOS 11.0, iOS 15.0, tvOS 16.0, *)
        public var validation: MLRandomForestRegressor.ModelParameters.ValidationData {
            get {
                _validation
            }
            set {
                _validation = newValue
            }
        }
        public var maxDepth: Int
        public var maxIterations: Int
        public var minLossReduction: Double
        public var minChildWeight: Double
        public var randomSeed: Int
        public var rowSubsample: Double
        public var columnSubsample: Double
        @available(macOS 11.0, iOS 15.0, tvOS 16.0, *)
        public init(validation: MLRandomForestRegressor.ModelParameters.ValidationData, maxDepth: Int = 6, maxIterations: Int = 10, minLossReduction: Double = 0, minChildWeight: Double = 0.1, randomSeed: Int = 42, rowSubsample: Double = 0.8, columnSubsample: Double = 0.8) {
            self.maxDepth = maxDepth
            self.maxIterations = maxIterations
            self.minLossReduction = minLossReduction
            self.minChildWeight = minChildWeight
            self.randomSeed = randomSeed
            self.rowSubsample = rowSubsample
            self.columnSubsample = columnSubsample
            self.validation = validation
        }
        @available(macOS, introduced: 10.14, deprecated: 11.0, message: "Use the validation property instead.")
        @available(iOS, introduced: 15.0, deprecated: 16.0, message: "Use the validation property instead.")
        @available(tvOS, unavailable)
        public init(validationData: MLDataTable? = nil, maxDepth: Int = 6, maxIterations: Int = 10, minLossReduction: Double = 0, minChildWeight: Double = 0.1, randomSeed: Int = 42, rowSubsample: Double = 0.8, columnSubsample: Double = 0.8) {
            self.maxDepth = maxDepth
            self.maxIterations = maxIterations
            self.minLossReduction = minLossReduction
            self.minChildWeight = minChildWeight
            self.randomSeed = randomSeed
            self.rowSubsample = rowSubsample
            self.columnSubsample = columnSubsample
            self.validationData = validationData
        }
        var _validation: MLRandomForestRegressor.ModelParameters.ValidationData = .split(strategy: .automatic)
    }
}

@available(*, unavailable)
extension MLRandomForestRegressor.ModelParameters : Sendable {
}

@available(macOS 10.14, iOS 15.0, tvOS 16.0, *)
extension MLRandomForestRegressor.ModelParameters : CustomStringConvertible, CustomDebugStringConvertible, CustomPlaygroundDisplayConvertible {
    public var description: String {
        get {
            "ModelParameters(maxDepth: \(String(describing: maxDepth)), maxIterations: \(String(describing: maxIterations)), minLossReduction: \(String(describing: minLossReduction)), minChildWeight: \(String(describing: minChildWeight)), randomSeed: \(String(describing: randomSeed)), rowSubsample: \(String(describing: rowSubsample)), columnSubsample: \(String(describing: columnSubsample)), validation: \(String(describing: validation)))"
        }
    }
    public var debugDescription: String {
        get {
            "ModelParameters(maxDepth: \(String(describing: maxDepth)), maxIterations: \(String(describing: maxIterations)), minLossReduction: \(String(describing: minLossReduction)), minChildWeight: \(String(describing: minChildWeight)), randomSeed: \(String(describing: randomSeed)), rowSubsample: \(String(describing: rowSubsample)), columnSubsample: \(String(describing: columnSubsample)), validation: \(String(describing: validation)))"
        }
    }
    public var playgroundDescription: Any {
        get {
            description
        }
    }
}

extension MLRandomForestRegressor.ModelParameters {
    @available(macOS 11.0, iOS 15.0, tvOS 16.0, *)
    public enum ValidationData {
        case split(strategy: MLSplitStrategy)
        @available(macOS, introduced: 11.0, deprecated: 14.0)
        @available(iOS, introduced: 15.0, deprecated: 17.0)
        @available(tvOS, introduced: 16.0, deprecated: 17.0)
        case table(MLDataTable)
        @available(macOS 13.0, iOS 16.0, tvOS 16.0, *)
        case dataFrame(DataFrame)
        case none
    }
}

@available(*, unavailable)
extension MLRandomForestRegressor.ModelParameters.ValidationData : Sendable {
}
