// MLRecommender: its parameters, data sources and options, which work in Perry,
// and its training, prediction and export, which need Apple's private
// engine and throw MLCreateError.generic saying so (see README.md). Its
// instance members are never reached: no instance can be made.

import CoreML
import Foundation
import TabularData

extension MLRecommender {
    @available(macOS 10.15, *)
    @available(iOS, unavailable)
    @available(tvOS, unavailable)
    public func write(to fileURL: URL, metadata: MLModelMetadata? = nil) throws {
        throw unavailable("Exporting \(Self.self)")
    }
    @available(macOS 10.15, *)
    @available(iOS, unavailable)
    @available(tvOS, unavailable)
    public func write(toFile path: String, metadata: MLModelMetadata? = nil) throws {
        throw unavailable("Exporting \(Self.self)")
    }
}

@available(macOS 10.15, *)
@available(iOS, unavailable)
@available(tvOS, unavailable)
public struct MLRecommender {
    public var model: MLModel {
        get {
            unreachableTrainer(Self.self)
        }
        set {
            _ = newValue
        }
    }
    public var userIdentifierColumn: String
    public var itemIdentifierColumn: String
    public var ratingColumn: String?
    public let modelParameters: MLRecommender.ModelParameters
    @available(macOS 13.0, *)
    @available(iOS, unavailable)
    @available(tvOS, unavailable)
    public init(trainingData: DataFrame, userColumn: String, itemColumn: String, ratingColumn: String? = nil, parameters: MLRecommender.ModelParameters = ModelParameters(nearestItems: nil)) throws {
        throw trainingUnavailable(Self.self)
    }
    @available(macOS, introduced: 10.15, deprecated: 13.0, message: "Use DataFrame instead of MLDataTable when initializing.")
    @available(iOS, unavailable)
    @available(tvOS, unavailable)
    public init(trainingData: MLDataTable, userColumn: String, itemColumn: String, ratingColumn: String? = nil, parameters: MLRecommender.ModelParameters = ModelParameters(nearestItems: nil)) throws {
        throw trainingUnavailable(Self.self)
    }
    @available(macOS, introduced: 10.15, deprecated: 14.0)
    @available(iOS, unavailable)
    @available(tvOS, unavailable)
    public func recommendations(fromUsers: [any MLIdentifier], maxCount: Int = 10, restrictingToItems: [any MLIdentifier]? = nil, excluding userItemObservations: MLDataTable? = nil, excludingObserved: Bool = true) throws -> MLDataTable {
        throw unavailable("Running \(Self.self)")
    }
    @available(macOS, introduced: 10.15, deprecated: 14.0)
    @available(iOS, unavailable)
    @available(tvOS, unavailable)
    public func recommendations<T>(fromUsers: MLDataColumn<T>, maxCount: Int = 10, restrictingToItems: MLDataColumn<T>? = nil, excluding userItemObservations: MLDataTable? = nil, excludingObserved: Bool = true) throws -> MLDataTable where T : MLDataValueConvertible, T : MLIdentifier {
        throw unavailable("Running \(Self.self)")
    }
    @available(macOS 13.0, *)
    @available(iOS, unavailable)
    @available(tvOS, unavailable)
    public func evaluation(on testingData: DataFrame, userColumn: String, itemColumn: String, ratingColumn: String? = nil, cutoffs: [Int] = [1, 2, 3, 4, 5], excludingObserved: Bool = true) -> MLRecommenderMetrics {
        .init(error: unavailable("Evaluating \(Self.self)"))
    }
    @available(macOS, introduced: 10.15, deprecated: 13.0, message: "Use DataFrame instead of MLDataTable.")
    @available(iOS, unavailable)
    @available(tvOS, unavailable)
    public func evaluation(on testingData: MLDataTable, userColumn: String, itemColumn: String, ratingColumn: String? = nil, cutoffs: [Int] = [1, 2, 3, 4, 5], excludingObserved: Bool = true) -> MLRecommenderMetrics {
        .init(error: unavailable("Evaluating \(Self.self)"))
    }
}

extension MLRecommender {
    @available(macOS, introduced: 10.15, deprecated: 14.0)
    @available(iOS, unavailable)
    @available(tvOS, unavailable)
    public func getSimilarItems(fromItems: [any MLIdentifier], maxCount: Int = 10) throws -> MLDataTable {
        throw unavailable("Running \(Self.self)")
    }
    @available(macOS, introduced: 10.15, deprecated: 14.0)
    @available(iOS, unavailable)
    @available(tvOS, unavailable)
    public func getSimilarItems<T>(fromItems: MLDataColumn<T>, maxCount: Int = 10) throws -> MLDataTable where T : MLDataValueConvertible {
        throw unavailable("Running \(Self.self)")
    }
}

@available(*, unavailable)
extension MLRecommender : Sendable {
}

@available(macOS 10.15, *)
@available(iOS, unavailable)
@available(tvOS, unavailable)
extension MLRecommender.ModelAlgorithmType : CustomStringConvertible, CustomDebugStringConvertible, CustomPlaygroundDisplayConvertible {
    public var description: String {
        get {
            switch self {
            case .itemSimilarity(let v0): return "itemSimilarity(\(String(describing: v0)))"
            }
        }
    }
    public var debugDescription: String {
        get {
            switch self {
            case .itemSimilarity(let v0): return "itemSimilarity(\(String(describing: v0)))"
            }
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
extension MLRecommender.SimilarityType : CustomStringConvertible, CustomDebugStringConvertible {
    public var description: String {
        get {
            switch self {
            case .cosine: return "cosine"
            case .jaccard: return "jaccard"
            case .pearson: return "pearson"
            }
        }
    }
    public var debugDescription: String {
        get {
            switch self {
            case .cosine: return "cosine"
            case .jaccard: return "jaccard"
            case .pearson: return "pearson"
            }
        }
    }
}

@available(macOS 10.15, *)
@available(iOS, unavailable)
@available(tvOS, unavailable)
extension MLRecommender.SimilarityType : CustomPlaygroundDisplayConvertible {
    public var playgroundDescription: Any {
        get {
            description
        }
    }
}

extension MLRecommender {
    @available(macOS 10.15, *)
    @available(iOS, unavailable)
    @available(tvOS, unavailable)
    public struct ModelParameters {
        public var algorithm: MLRecommender.ModelAlgorithmType
        public var threshold: Double
        public var maxCount: Int
        @available(macOS 14.0, *)
        public var nearestItemsDataFrame: DataFrame?
        @available(macOS, introduced: 10.15, deprecated: 14.0, message: "Use nearestItemsDataFrame.")
        public var nearestItems: MLDataTable?
        public var maxSimilarityIterations: Int
        @available(macOS 14.0, *)
        public init(algorithm: MLRecommender.ModelAlgorithmType = .itemSimilarity(.cosine), threshold: Double = 0.001, maxCount: Int = 64, nearestItemsDataFrame: DataFrame?, maxSimilarityIterations: Int = 1024) {
            self.algorithm = algorithm
            self.threshold = threshold
            self.maxCount = maxCount
            self.nearestItemsDataFrame = nearestItemsDataFrame
            self.maxSimilarityIterations = maxSimilarityIterations
        }
        @available(macOS, introduced: 10.15, deprecated: 14.0)
        public init(algorithm: MLRecommender.ModelAlgorithmType = .itemSimilarity(.cosine), threshold: Double = 0.001, maxCount: Int = 64, nearestItems: MLDataTable?, maxSimilarityIterations: Int = 1024) {
            self.algorithm = algorithm
            self.threshold = threshold
            self.maxCount = maxCount
            self.nearestItems = nearestItems
            self.maxSimilarityIterations = maxSimilarityIterations
        }
    }
}

extension MLRecommender {
    @available(macOS 10.15, *)
    @available(iOS, unavailable)
    @available(tvOS, unavailable)
    public enum ModelAlgorithmType : Sendable {
        case itemSimilarity(MLRecommender.SimilarityType)
    }
    @available(macOS 10.15, *)
    @available(iOS, unavailable)
    @available(tvOS, unavailable)
    public enum SimilarityType : Sendable {
        case cosine
        case jaccard
        case pearson
    }
}

@available(*, unavailable)
extension MLRecommender.ModelParameters : Sendable {
}

@available(macOS 10.15, *)
@available(iOS, unavailable)
@available(tvOS, unavailable)
extension MLRecommender.SimilarityType : Equatable {}

@available(macOS 10.15, *)
@available(iOS, unavailable)
@available(tvOS, unavailable)
extension MLRecommender.SimilarityType : Hashable {}
