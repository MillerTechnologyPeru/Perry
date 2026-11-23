// MLSupportVectorClassifier: its parameters, data sources and options, which work in Perry,
// and its training, prediction and export, which need Apple's private
// engine and throw MLCreateError.generic saying so (see README.md). Its
// instance members are never reached: no instance can be made.

import CoreML
import Foundation
import TabularData

@available(macOS, introduced: 10.14, deprecated: 14.0)
@available(iOS, unavailable)
@available(tvOS, unavailable)
extension MLSupportVectorClassifier {
    @available(macOS, introduced: 10.14, deprecated: 14.0)
    @available(iOS, unavailable)
    @available(tvOS, unavailable)
    public struct ModelParameters {
        public var maxIterations: Int
        @available(macOS, introduced: 10.14, deprecated: 10.15, message: "Use the validation property instead.")
        @available(iOS, unavailable)
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
        @available(macOS, introduced: 10.15, deprecated: 14.0)
        @available(iOS, unavailable)
        @available(tvOS, unavailable)
        public var validation: MLSupportVectorClassifier.ModelParameters.ValidationData {
            get {
                _validation
            }
            set {
                _validation = newValue
            }
        }
        public var penalty: Double
        public var convergenceThreshold: Double
        public var featureRescaling: Bool
        @available(macOS, introduced: 10.15, deprecated: 14.0)
        @available(iOS, unavailable)
        @available(tvOS, unavailable)
        public init(validation: MLSupportVectorClassifier.ModelParameters.ValidationData = .split(strategy: .automatic), maxIterations: Int = 11, penalty: Double = 1.0, convergenceThreshold: Double = 0.01, featureRescaling: Bool = true) {
            self.maxIterations = maxIterations
            self.penalty = penalty
            self.convergenceThreshold = convergenceThreshold
            self.featureRescaling = featureRescaling
            self.validation = validation
        }
        @available(macOS, introduced: 10.14, deprecated: 10.15, message: "Use the validation property instead.")
        @available(iOS, unavailable)
        @available(tvOS, unavailable)
        public init(validationData: MLDataTable?, maxIterations: Int = 11, penalty: Double = 1.0, convergenceThreshold: Double = 0.01, featureRescaling: Bool = true) {
            self.maxIterations = maxIterations
            self.penalty = penalty
            self.convergenceThreshold = convergenceThreshold
            self.featureRescaling = featureRescaling
            self.validationData = validationData
        }
        var _validation: MLSupportVectorClassifier.ModelParameters.ValidationData = .split(strategy: .automatic)
    }
}

@available(*, unavailable)
extension MLSupportVectorClassifier.ModelParameters : Sendable {
}

@available(macOS, introduced: 10.14, deprecated: 14.0)
@available(iOS, unavailable)
@available(tvOS, unavailable)
extension MLSupportVectorClassifier.ModelParameters : CustomStringConvertible, CustomDebugStringConvertible, CustomPlaygroundDisplayConvertible {
    public var description: String {
        get {
            "ModelParameters(maxIterations: \(String(describing: maxIterations)), penalty: \(String(describing: penalty)), convergenceThreshold: \(String(describing: convergenceThreshold)), featureRescaling: \(String(describing: featureRescaling)), validation: \(String(describing: validation)))"
        }
    }
    public var debugDescription: String {
        get {
            "ModelParameters(maxIterations: \(String(describing: maxIterations)), penalty: \(String(describing: penalty)), convergenceThreshold: \(String(describing: convergenceThreshold)), featureRescaling: \(String(describing: featureRescaling)), validation: \(String(describing: validation)))"
        }
    }
    public var playgroundDescription: Any {
        get {
            description
        }
    }
}

@available(macOS, introduced: 10.14, deprecated: 14.0)
@available(iOS, unavailable)
@available(tvOS, unavailable)
public struct MLSupportVectorClassifier : @unchecked Sendable {
    public var model: MLModel
    public var targetColumn: String
    public var featureColumns: [String]
    public let modelParameters: MLSupportVectorClassifier.ModelParameters
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
    @available(macOS, introduced: 12.0, deprecated: 14.0)
    @available(iOS, unavailable)
    @available(tvOS, unavailable)
    public init(trainingData: DataFrame, targetColumn: String, featureColumns: [String]? = nil, parameters: MLSupportVectorClassifier.ModelParameters = ModelParameters(validation: .split(strategy: .automatic))) throws {
        throw trainingUnavailable(Self.self)
    }
    @available(macOS, introduced: 10.14, deprecated: 13.0, message: "Use DataFrame instead of MLDataTable when initializing.")
    @available(iOS, unavailable)
    @available(tvOS, unavailable)
    public init(trainingData: MLDataTable, targetColumn: String, featureColumns: [String]? = nil, parameters: MLSupportVectorClassifier.ModelParameters = ModelParameters(validationData: nil)) throws {
        throw trainingUnavailable(Self.self)
    }
    @available(macOS, introduced: 12.0, deprecated: 14.0)
    @available(iOS, unavailable)
    @available(tvOS, unavailable)
    public func predictions(from data: DataFrame) throws -> AnyColumn {
        throw unavailable("Running \(Self.self)")
    }
    @available(macOS, introduced: 10.14, deprecated: 13.0, message: "Use DataFrame instead of MLDataTable.")
    @available(iOS, unavailable)
    @available(tvOS, unavailable)
    public func predictions(from data: MLDataTable) throws -> MLUntypedColumn {
        throw unavailable("Running \(Self.self)")
    }
    @available(macOS, introduced: 12.0, deprecated: 14.0)
    @available(iOS, unavailable)
    @available(tvOS, unavailable)
    public func evaluation(on labeledData: DataFrame) -> MLClassifierMetrics {
        .init(error: unavailable("Evaluating \(Self.self)"))
    }
    @available(macOS, introduced: 10.14, deprecated: 13.0, message: "Use DataFrame instead of MLDataTable.")
    @available(iOS, unavailable)
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

@available(macOS, introduced: 10.14, deprecated: 14.0)
@available(iOS, unavailable)
@available(tvOS, unavailable)
extension MLSupportVectorClassifier : CustomStringConvertible {
    public var description: String {
        get {
            "\(Self.self): not trained. \(trainingUnavailable(Self.self).failureReason ?? "")"
        }
    }
}

@available(macOS, introduced: 10.14, deprecated: 14.0)
@available(iOS, unavailable)
@available(tvOS, unavailable)
extension MLSupportVectorClassifier : CustomDebugStringConvertible {
    public var debugDescription: String {
        get {
            "\(Self.self): not trained. \(trainingUnavailable(Self.self).failureReason ?? "")"
        }
    }
}

@available(macOS, introduced: 10.14, deprecated: 14.0)
@available(iOS, unavailable)
@available(tvOS, unavailable)
extension MLSupportVectorClassifier : CustomPlaygroundDisplayConvertible {
    public var playgroundDescription: Any {
        get {
            description
        }
    }
}

@available(macOS, introduced: 10.15, deprecated: 14.0)
@available(iOS, unavailable)
@available(tvOS, unavailable)
extension MLSupportVectorClassifier.ModelParameters {
    @available(macOS, introduced: 10.15, deprecated: 14.0)
    @available(iOS, unavailable)
    @available(tvOS, unavailable)
    public enum ValidationData {
        case split(strategy: MLSplitStrategy)
        @available(macOS, introduced: 10.15, deprecated: 14.0)
        @available(iOS, unavailable)
        @available(tvOS, unavailable)
        case table(MLDataTable)
        @available(macOS 12.0, *)
        case dataFrame(DataFrame)
        case none
    }
}

@available(*, unavailable)
extension MLSupportVectorClassifier.ModelParameters.ValidationData : Sendable {
}
