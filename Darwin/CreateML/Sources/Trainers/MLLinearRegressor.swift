// MLLinearRegressor: its parameters, data sources and options, which work in Perry,
// and its training, prediction and export, which need Apple's private
// engine and throw MLCreateError.generic saying so (see README.md). Its
// instance members are never reached: no instance can be made.

import CoreML
import Foundation
import TabularData

extension MLLinearRegressor {
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
        public var validation: MLLinearRegressor.ModelParameters.ValidationData {
            get {
                _validation
            }
            set {
                _validation = newValue
            }
        }
        public var maxIterations: Int
        public var l1Penalty: Double
        public var l2Penalty: Double
        public var stepSize: Double
        public var convergenceThreshold: Double
        public var featureRescaling: Bool
        @available(macOS 11.0, iOS 15.0, tvOS 16.0, *)
        public init(validation: MLLinearRegressor.ModelParameters.ValidationData, maxIterations: Int = 10, l1Penalty: Double = 0, l2Penalty: Double = 0.01, stepSize: Double = 1.0, convergenceThreshold: Double = 0.01, featureRescaling: Bool = true) {
            self.maxIterations = maxIterations
            self.l1Penalty = l1Penalty
            self.l2Penalty = l2Penalty
            self.stepSize = stepSize
            self.convergenceThreshold = convergenceThreshold
            self.featureRescaling = featureRescaling
            self.validation = validation
        }
        @available(macOS, introduced: 10.14, deprecated: 11.0, message: "Use the validation property instead.")
        @available(iOS, introduced: 15.0, deprecated: 16.0, message: "Use the validation property instead.")
        @available(tvOS, unavailable)
        public init(validationData: MLDataTable? = nil, maxIterations: Int = 10, l1Penalty: Double = 0, l2Penalty: Double = 0.01, stepSize: Double = 1.0, convergenceThreshold: Double = 0.01, featureRescaling: Bool = true) {
            self.maxIterations = maxIterations
            self.l1Penalty = l1Penalty
            self.l2Penalty = l2Penalty
            self.stepSize = stepSize
            self.convergenceThreshold = convergenceThreshold
            self.featureRescaling = featureRescaling
            self.validationData = validationData
        }
        var _validation: MLLinearRegressor.ModelParameters.ValidationData = .split(strategy: .automatic)
    }
}

@available(*, unavailable)
extension MLLinearRegressor.ModelParameters : Sendable {
}

@available(macOS 10.14, iOS 15.0, tvOS 16.0, *)
extension MLLinearRegressor.ModelParameters : CustomStringConvertible {
    public var description: String {
        get {
            "ModelParameters(maxIterations: \(String(describing: maxIterations)), l1Penalty: \(String(describing: l1Penalty)), l2Penalty: \(String(describing: l2Penalty)), stepSize: \(String(describing: stepSize)), convergenceThreshold: \(String(describing: convergenceThreshold)), featureRescaling: \(String(describing: featureRescaling)), validation: \(String(describing: validation)))"
        }
    }
}

@available(macOS 10.14, iOS 15.0, tvOS 16.0, *)
extension MLLinearRegressor.ModelParameters : CustomDebugStringConvertible {
    public var debugDescription: String {
        get {
            "ModelParameters(maxIterations: \(String(describing: maxIterations)), l1Penalty: \(String(describing: l1Penalty)), l2Penalty: \(String(describing: l2Penalty)), stepSize: \(String(describing: stepSize)), convergenceThreshold: \(String(describing: convergenceThreshold)), featureRescaling: \(String(describing: featureRescaling)), validation: \(String(describing: validation)))"
        }
    }
}

@available(macOS 10.14, iOS 15.0, tvOS 16.0, *)
extension MLLinearRegressor.ModelParameters : CustomPlaygroundDisplayConvertible {
    public var playgroundDescription: Any {
        get {
            description
        }
    }
}

extension MLLinearRegressor.ModelParameters {
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

@available(macOS 10.14, iOS 15.0, tvOS 16.0, *)
public struct MLLinearRegressor : @unchecked Sendable {
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
    public let modelParameters: MLLinearRegressor.ModelParameters
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
    public init(trainingData: DataFrame, targetColumn: String, featureColumns: [String]? = nil, parameters: MLLinearRegressor.ModelParameters = ModelParameters(validation: .split(strategy: .automatic))) throws {
        throw trainingUnavailable(Self.self)
    }
    @available(macOS, introduced: 10.14, deprecated: 13.0, message: "Use DataFrame instead of MLDataTable when initializing.")
    @available(iOS, introduced: 15.0, deprecated: 16.0, message: "Use DataFrame instead of MLDataTable when initializing.")
    @available(tvOS, unavailable)
    public init(trainingData: MLDataTable, targetColumn: String, featureColumns: [String]? = nil, parameters: MLLinearRegressor.ModelParameters = ModelParameters(validationData: nil)) throws {
        throw trainingUnavailable(Self.self)
    }
    @available(macOS 12.0, iOS 15.0, tvOS 16.0, *)
    public init(checkpoint: MLCheckpoint) throws {
        throw trainingUnavailable(Self.self)
    }
    @available(macOS, introduced: 12.0, deprecated: 14.0)
    @available(iOS, introduced: 15.0, deprecated: 17.0)
    @available(tvOS, introduced: 16.0, deprecated: 17.0)
    public static func train(trainingData: MLDataTable, targetColumn: String, featureColumns: [String]? = nil, parameters: MLLinearRegressor.ModelParameters = ModelParameters(validation: .split(strategy: .automatic)), sessionParameters: MLTrainingSessionParameters = _defaultSessionParameters) throws -> MLJob<MLLinearRegressor> {
        throw trainingUnavailable(Self.self)
    }
    @available(macOS 12.0, iOS 15.0, tvOS 16.0, *)
    public static func train(trainingData: DataFrame, targetColumn: String, featureColumns: [String]? = nil, parameters: MLLinearRegressor.ModelParameters = .init(validation: .split(strategy: .automatic)), sessionParameters: MLTrainingSessionParameters = _defaultSessionParameters) throws -> MLJob<MLLinearRegressor> {
        throw trainingUnavailable(Self.self)
    }
    @available(macOS, introduced: 12.0, deprecated: 14.0)
    @available(iOS, introduced: 15.0, deprecated: 17.0)
    @available(tvOS, introduced: 16.0, deprecated: 17.0)
    public static func makeTrainingSession(trainingData: MLDataTable, targetColumn: String, featureColumns: [String]? = nil, parameters: MLLinearRegressor.ModelParameters = ModelParameters(validation: .split(strategy: .automatic)), sessionParameters: MLTrainingSessionParameters = _defaultSessionParameters) throws -> MLTrainingSession<MLLinearRegressor> {
        throw trainingUnavailable(Self.self)
    }
    @available(macOS 12.0, iOS 15.0, tvOS 16.0, *)
    public static func makeTrainingSession(trainingData: DataFrame, targetColumn: String, featureColumns: [String]? = nil, parameters: MLLinearRegressor.ModelParameters = .init(validation: .split(strategy: .automatic)), sessionParameters: MLTrainingSessionParameters = _defaultSessionParameters) throws -> MLTrainingSession<MLLinearRegressor> {
        throw trainingUnavailable(Self.self)
    }
    @available(macOS 12.0, iOS 15.0, tvOS 16.0, *)
    public static func restoreTrainingSession(sessionParameters: MLTrainingSessionParameters) throws -> MLTrainingSession<MLLinearRegressor> {
        throw trainingUnavailable(Self.self)
    }
    @available(macOS 12.0, iOS 15.0, tvOS 16.0, *)
    public static func resume(_ session: MLTrainingSession<MLLinearRegressor>) throws -> MLJob<MLLinearRegressor> {
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
extension MLLinearRegressor : CustomStringConvertible {
    public var description: String {
        get {
            "\(Self.self): not trained. \(trainingUnavailable(Self.self).failureReason ?? "")"
        }
    }
}

@available(macOS 10.14, iOS 15.0, tvOS 16.0, *)
extension MLLinearRegressor : CustomDebugStringConvertible {
    public var debugDescription: String {
        get {
            "\(Self.self): not trained. \(trainingUnavailable(Self.self).failureReason ?? "")"
        }
    }
}

@available(macOS 10.14, iOS 15.0, tvOS 16.0, *)
extension MLLinearRegressor : CustomPlaygroundDisplayConvertible {
    public var playgroundDescription: Any {
        get {
            description
        }
    }
}
