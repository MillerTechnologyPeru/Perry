import CoreML
import Foundation
import NaturalLanguage
import TabularData

// The models that are kinds of other ones (MLClassifier and MLRegressor),
// and the two that need no training: gazetteers and word embeddings,
// which Natural Language compiles from their dictionaries.

/// What an instance member of a trainer does: none can run, since a
/// trainer can't be made (its initializers throw what training throws).
func unreachableTrainer(_ type: Any.Type) -> Never {
    fatalError("\(type) can't be made in Perry's CreateML: \(trainingUnavailable(type).failureReason ?? "")")
}

@available(macOS 10.14, *)
@available(iOS, unavailable)
@available(tvOS, unavailable)
public enum MLClassifier: Sendable {
    case boostedTree(MLBoostedTreeClassifier)
    case decisionTree(MLDecisionTreeClassifier)
    case randomForest(MLRandomForestClassifier)
    case logisticRegression(MLLogisticRegressionClassifier)
    @available(macOS, introduced: 10.14, deprecated: 14.0)
    case supportVector(MLSupportVectorClassifier)

    /// The best classifier for the data: training, which Perry can't do.
    @available(macOS 12.0, *)
    public init(trainingData: DataFrame, targetColumn: String, featureColumns: [String]? = nil) throws {
        throw trainingUnavailable(MLClassifier.self)
    }

    @available(macOS, introduced: 10.14, deprecated: 13.0, message: "Use DataFrame instead of MLDataTable when initializing.")
    public init(trainingData: MLDataTable, targetColumn: String, featureColumns: [String]? = nil) throws {
        throw trainingUnavailable(MLClassifier.self)
    }

    @available(macOS 12.0, *)
    public func predictions(from data: DataFrame) throws -> AnyColumn {
        switch self {
        case .boostedTree(let model): return try model.predictions(from: data)
        case .decisionTree(let model): return try model.predictions(from: data)
        case .randomForest(let model): return try model.predictions(from: data)
        case .logisticRegression(let model): return try model.predictions(from: data)
        case .supportVector(let model): return try model.predictions(from: data)
        }
    }

    @available(macOS, introduced: 10.14, deprecated: 13.0, message: "Use DataFrame instead of MLDataTable.")
    public func predictions(from data: MLDataTable) throws -> MLUntypedColumn {
        switch self {
        case .boostedTree(let model): return try model.predictions(from: data)
        case .decisionTree(let model): return try model.predictions(from: data)
        case .randomForest(let model): return try model.predictions(from: data)
        case .logisticRegression(let model): return try model.predictions(from: data)
        case .supportVector(let model): return try model.predictions(from: data)
        }
    }

    @available(macOS 12.0, *)
    public func evaluation(on labeledData: DataFrame) -> MLClassifierMetrics {
        switch self {
        case .boostedTree(let model): return model.evaluation(on: labeledData)
        case .decisionTree(let model): return model.evaluation(on: labeledData)
        case .randomForest(let model): return model.evaluation(on: labeledData)
        case .logisticRegression(let model): return model.evaluation(on: labeledData)
        case .supportVector(let model): return model.evaluation(on: labeledData)
        }
    }

    @available(macOS, introduced: 10.14, deprecated: 13.0, message: "Use DataFrame instead of MLDataTable.")
    public func evaluation(on labeledData: MLDataTable) -> MLClassifierMetrics {
        switch self {
        case .boostedTree(let model): return model.evaluation(on: labeledData)
        case .decisionTree(let model): return model.evaluation(on: labeledData)
        case .randomForest(let model): return model.evaluation(on: labeledData)
        case .logisticRegression(let model): return model.evaluation(on: labeledData)
        case .supportVector(let model): return model.evaluation(on: labeledData)
        }
    }

    public func write(to fileURL: URL, metadata: MLModelMetadata?) throws {
        switch self {
        case .boostedTree(let model): try model.write(to: fileURL, metadata: metadata)
        case .decisionTree(let model): try model.write(to: fileURL, metadata: metadata)
        case .randomForest(let model): try model.write(to: fileURL, metadata: metadata)
        case .logisticRegression(let model): try model.write(to: fileURL, metadata: metadata)
        case .supportVector(let model): try model.write(to: fileURL, metadata: metadata)
        }
    }

    public func write(toFile path: String, metadata: MLModelMetadata?) throws {
        try write(to: URL(fileURLWithPath: path), metadata: metadata)
    }
}

@available(macOS 10.14, *)
extension MLClassifier {
    public var model: MLModel {
        switch self {
        case .boostedTree(let model): return model.model
        case .decisionTree(let model): return model.model
        case .randomForest(let model): return model.model
        case .logisticRegression(let model): return model.model
        case .supportVector(let model): return model.model
        }
    }

    public var trainingMetrics: MLClassifierMetrics {
        switch self {
        case .boostedTree(let model): return model.trainingMetrics
        case .decisionTree(let model): return model.trainingMetrics
        case .randomForest(let model): return model.trainingMetrics
        case .logisticRegression(let model): return model.trainingMetrics
        case .supportVector(let model): return model.trainingMetrics
        }
    }

    public var validationMetrics: MLClassifierMetrics {
        switch self {
        case .boostedTree(let model): return model.validationMetrics
        case .decisionTree(let model): return model.validationMetrics
        case .randomForest(let model): return model.validationMetrics
        case .logisticRegression(let model): return model.validationMetrics
        case .supportVector(let model): return model.validationMetrics
        }
    }

    public var targetColumn: String {
        switch self {
        case .boostedTree(let model): return model.targetColumn
        case .decisionTree(let model): return model.targetColumn
        case .randomForest(let model): return model.targetColumn
        case .logisticRegression(let model): return model.targetColumn
        case .supportVector(let model): return model.targetColumn
        }
    }

    public var featureColumns: [String] {
        switch self {
        case .boostedTree(let model): return model.featureColumns
        case .decisionTree(let model): return model.featureColumns
        case .randomForest(let model): return model.featureColumns
        case .logisticRegression(let model): return model.featureColumns
        case .supportVector(let model): return model.featureColumns
        }
    }
}

@available(macOS 10.14, *)
extension MLClassifier: CustomStringConvertible {
    public var description: String {
        switch self {
        case .boostedTree(let model): return model.description
        case .decisionTree(let model): return model.description
        case .randomForest(let model): return model.description
        case .logisticRegression(let model): return model.description
        case .supportVector(let model): return model.description
        }
    }
}

@available(macOS 10.14, *)
extension MLClassifier: CustomDebugStringConvertible {
    public var debugDescription: String { description }
}

@available(macOS 10.14, *)
extension MLClassifier: CustomPlaygroundDisplayConvertible {
    public var playgroundDescription: Any { description }
}

@available(macOS 10.14, *)
@available(iOS, unavailable)
@available(tvOS, unavailable)
public enum MLRegressor: Sendable {
    case boostedTree(MLBoostedTreeRegressor)
    case decisionTree(MLDecisionTreeRegressor)
    case randomForest(MLRandomForestRegressor)
    case linear(MLLinearRegressor)

    /// The best regressor for the data: training, which Perry can't do.
    @available(macOS 12.0, *)
    public init(trainingData: DataFrame, targetColumn: String, featureColumns: [String]? = nil) throws {
        throw trainingUnavailable(MLRegressor.self)
    }

    @available(macOS, introduced: 10.14, deprecated: 13.0, message: "Use DataFrame instead of MLDataTable when initializing.")
    public init(trainingData: MLDataTable, targetColumn: String, featureColumns: [String]? = nil) throws {
        throw trainingUnavailable(MLRegressor.self)
    }

    @available(macOS 12.0, *)
    public func predictions(from data: DataFrame) throws -> AnyColumn {
        switch self {
        case .boostedTree(let model): return try model.predictions(from: data)
        case .decisionTree(let model): return try model.predictions(from: data)
        case .randomForest(let model): return try model.predictions(from: data)
        case .linear(let model): return try model.predictions(from: data)
        }
    }

    @available(macOS, introduced: 10.14, deprecated: 13.0, message: "Use DataFrame instead of MLDataTable.")
    public func predictions(from data: MLDataTable) throws -> MLUntypedColumn {
        switch self {
        case .boostedTree(let model): return try model.predictions(from: data)
        case .decisionTree(let model): return try model.predictions(from: data)
        case .randomForest(let model): return try model.predictions(from: data)
        case .linear(let model): return try model.predictions(from: data)
        }
    }

    @available(macOS 12.0, *)
    public func evaluation(on labeledData: DataFrame) -> MLRegressorMetrics {
        switch self {
        case .boostedTree(let model): return model.evaluation(on: labeledData)
        case .decisionTree(let model): return model.evaluation(on: labeledData)
        case .randomForest(let model): return model.evaluation(on: labeledData)
        case .linear(let model): return model.evaluation(on: labeledData)
        }
    }

    @available(macOS, introduced: 10.14, deprecated: 13.0, message: "Use DataFrame instead of MLDataTable.")
    public func evaluation(on labeledData: MLDataTable) -> MLRegressorMetrics {
        switch self {
        case .boostedTree(let model): return model.evaluation(on: labeledData)
        case .decisionTree(let model): return model.evaluation(on: labeledData)
        case .randomForest(let model): return model.evaluation(on: labeledData)
        case .linear(let model): return model.evaluation(on: labeledData)
        }
    }

    public func write(to fileURL: URL, metadata: MLModelMetadata?) throws {
        switch self {
        case .boostedTree(let model): try model.write(to: fileURL, metadata: metadata)
        case .decisionTree(let model): try model.write(to: fileURL, metadata: metadata)
        case .randomForest(let model): try model.write(to: fileURL, metadata: metadata)
        case .linear(let model): try model.write(to: fileURL, metadata: metadata)
        }
    }

    public func write(toFile path: String, metadata: MLModelMetadata?) throws {
        try write(to: URL(fileURLWithPath: path), metadata: metadata)
    }
}

@available(macOS 10.14, *)
extension MLRegressor {
    public var model: MLModel {
        switch self {
        case .boostedTree(let model): return model.model
        case .decisionTree(let model): return model.model
        case .randomForest(let model): return model.model
        case .linear(let model): return model.model
        }
    }

    public var trainingMetrics: MLRegressorMetrics {
        switch self {
        case .boostedTree(let model): return model.trainingMetrics
        case .decisionTree(let model): return model.trainingMetrics
        case .randomForest(let model): return model.trainingMetrics
        case .linear(let model): return model.trainingMetrics
        }
    }

    public var validationMetrics: MLRegressorMetrics {
        switch self {
        case .boostedTree(let model): return model.validationMetrics
        case .decisionTree(let model): return model.validationMetrics
        case .randomForest(let model): return model.validationMetrics
        case .linear(let model): return model.validationMetrics
        }
    }

    public var targetColumn: String {
        switch self {
        case .boostedTree(let model): return model.targetColumn
        case .decisionTree(let model): return model.targetColumn
        case .randomForest(let model): return model.targetColumn
        case .linear(let model): return model.targetColumn
        }
    }

    public var featureColumns: [String] {
        switch self {
        case .boostedTree(let model): return model.featureColumns
        case .decisionTree(let model): return model.featureColumns
        case .randomForest(let model): return model.featureColumns
        case .linear(let model): return model.featureColumns
        }
    }
}

@available(macOS 10.14, *)
extension MLRegressor: CustomStringConvertible {
    public var description: String {
        switch self {
        case .boostedTree(let model): return model.description
        case .decisionTree(let model): return model.description
        case .randomForest(let model): return model.description
        case .linear(let model): return model.description
        }
    }
}

@available(macOS 10.14, *)
extension MLRegressor: CustomDebugStringConvertible {
    public var debugDescription: String { description }
}

@available(macOS 10.14, *)
extension MLRegressor: CustomPlaygroundDisplayConvertible {
    public var playgroundDescription: Any { description }
}

/// The Core ML model of what Natural Language compiles to a file, loaded.
/// Natural Language writes its own model data, which Core ML can't load as
/// a model, so this throws where Apple's CreateML wraps that data in a
/// model of its making.
func compiledModel(_ what: String, writing write: (URL) throws -> Void) throws -> MLModel {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("CreateML-\(UUID().uuidString).mlmodel")
    defer { try? FileManager.default.removeItem(at: url) }
    try write(url)
    do {
        return try MLModel(contentsOf: url)
    } catch {
        do {
            return try MLModel(contentsOf: try MLModel.compileModel(at: url))
        } catch {
            throw MLCreateError.generic(reason: "Making the Core ML model of a \(what) isn't available in Perry's CreateML: "
                + "Core ML can't load the model data Natural Language compiles (\(error.localizedDescription)).")
        }
    }
}

// Gazetteers: labels for the words and phrases a dictionary lists.

@available(macOS 10.15, *)
@available(iOS, unavailable)
@available(tvOS, unavailable)
public struct MLGazetteer {
    private var _model: MLModel
    private let labels: [String: String]
    private let dictionary: [String: [String]]

    public var model: MLModel {
        get { _model }
        set { _model = newValue }
    }

    public let modelParameters: MLGazetteer.ModelParameters

    /// A gazetteer of the words and phrases of each label, which Natural
    /// Language compiles to a Core ML model.
    public init(dictionary: [String: [String]], parameters: MLGazetteer.ModelParameters = ModelParameters()) throws {
        self.dictionary = dictionary
        self.modelParameters = parameters
        var labels: [String: String] = [:]
        for (label, entries) in dictionary {
            for entry in entries { labels[entry.lowercased()] = label }
        }
        self.labels = labels
        _model = try compiledModel("gazetteer") { try NLGazetteer.write(dictionary, language: parameters.language, to: $0) }
    }

    @available(macOS, introduced: 10.15, deprecated: 14.0)
    public init(labeledData: MLDataTable, textColumn: String, labelColumn: String, parameters: MLGazetteer.ModelParameters = ModelParameters()) throws {
        let table = try labeledData.getImpl()
        let texts = try table.column(name: textColumn).values, labels = try table.column(name: labelColumn).values
        var dictionary: [String: [String]] = [:]
        for (text, label) in zip(texts, labels) {
            guard let text = text.stringValue, let label = label.stringValue else { continue }
            dictionary[label, default: []].append(text)
        }
        try self.init(dictionary: dictionary, parameters: parameters)
    }
}

@available(*, unavailable)
extension MLGazetteer: Sendable {}

@available(macOS 10.15, *)
extension MLGazetteer: CustomStringConvertible, CustomDebugStringConvertible, CustomPlaygroundDisplayConvertible {
    public var description: String {
        "MLGazetteer: \(dictionary.count) labels, \(labels.count) entries\nParameters: \(modelParameters)"
    }

    public var debugDescription: String { description }
    public var playgroundDescription: Any { description }
}

@available(macOS 10.15, *)
extension MLGazetteer {
    /// Writes the gazetteer's model, as Natural Language compiles it. The
    /// metadata isn't written: Natural Language's writer takes none.
    public func write(to fileURL: URL, metadata: MLModelMetadata? = nil) throws {
        try NLGazetteer.write(dictionary, language: modelParameters.language, to: fileURL)
    }

    public func write(toFile path: String, metadata: MLModelMetadata? = nil) throws {
        try write(to: URL(fileURLWithPath: path), metadata: metadata)
    }

    /// The label of a word or phrase, or "OTHER" for one it doesn't list.
    public func prediction(from text: String) throws -> String {
        labels[text.lowercased()] ?? "OTHER"
    }

    public func predictions(from texts: [String]) throws -> [String] {
        try texts.map(prediction(from:))
    }

    @available(macOS, introduced: 10.15, deprecated: 14.0)
    public func predictions(from texts: MLDataColumn<String>) throws -> MLDataColumn<String> {
        MLDataColumn(try predictions(from: Array(texts)))
    }

    public struct ModelParameters: Sendable {
        public var language: NLLanguage?

        public init(language: NLLanguage? = nil) {
            self.language = language
        }
    }
}

@available(macOS 10.15, *)
extension MLGazetteer.ModelParameters: CustomStringConvertible, CustomDebugStringConvertible, CustomPlaygroundDisplayConvertible {
    public var description: String { "ModelParameters(language: \(language?.rawValue ?? "automatic"))" }
    public var debugDescription: String { description }
    public var playgroundDescription: Any { description }
}

// Word embeddings: vectors for words, and the words nearest each other.

@available(macOS 10.15, *)
@available(iOS, unavailable)
@available(tvOS, unavailable)
public struct MLWordEmbedding {
    private var _model: MLModel
    private let vectors: [String: [Double]]

    public var model: MLModel {
        get { _model }
        set { _model = newValue }
    }

    public let modelParameters: MLWordEmbedding.ModelParameters
    public let dimension: Int
    public let vocabularySize: Int

    /// An embedding of each word's vector, which Natural Language compiles
    /// to a Core ML model; the vectors must all have the same dimension.
    public init(dictionary: [String: [Double]], parameters: MLWordEmbedding.ModelParameters = ModelParameters()) throws {
        let dimensions = Set(dictionary.values.map(\.count))
        guard dimensions.count <= 1 else {
            throw MLCreateError.generic(reason: "The word vectors have different dimensions: \(dimensions.sorted()).")
        }
        vectors = dictionary
        modelParameters = parameters
        dimension = dimensions.first ?? 0
        vocabularySize = dictionary.count
        _model = try compiledModel("word embedding") {
            try NLEmbedding.write(dictionary, language: parameters.language, revision: parameters.revision, to: $0)
        }
    }
}

@available(*, unavailable)
extension MLWordEmbedding: Sendable {}

@available(macOS 10.15, *)
extension MLWordEmbedding {
    public func contains(_ text: String) -> Bool {
        vectors[text] != nil
    }

    /// The cosine distance between two words' vectors, from 0 to 2; 2 when
    /// either has none.
    public func distance(between first: String, and second: String, distanceType: NLDistanceType = .cosine) -> Double {
        guard let a = vectors[first], let b = vectors[second] else { return 2 }
        return Self.cosineDistance(a, b)
    }

    public func vector(for text: String) -> [Double]? {
        vectors[text]
    }

    static func cosineDistance(_ a: [Double], _ b: [Double]) -> Double {
        let dot = zip(a, b).reduce(0) { $0 + $1.0 * $1.1 }
        let norms = (a.reduce(0) { $0 + $1 * $1 } * b.reduce(0) { $0 + $1 * $1 }).squareRoot()
        return norms == 0 ? 2 : 1 - dot / norms
    }

    /// The words nearest one, nearest first, within `maxDistance`.
    public func prediction(from text: String, maxCount: Int = 10, maxDistance: Double = 2.0,
                           distanceType: NLDistanceType = .cosine) throws -> [(text: String, distance: Double)] {
        guard let vector = vectors[text] else {
            throw MLCreateError.generic(reason: "The embedding has no vector for \"\(text)\".")
        }
        return vectors.compactMap { word, other -> (text: String, distance: Double)? in
            guard word != text else { return nil }
            let distance = Self.cosineDistance(vector, other)
            return distance <= maxDistance ? (word, distance) : nil
        }
        .sorted { $0.distance < $1.distance || ($0.distance == $1.distance && $0.text < $1.text) }
        .prefix(max(maxCount, 0)).map { $0 }
    }

    /// Writes the embedding's model, as Natural Language compiles it. The
    /// metadata isn't written: Natural Language's writer takes none.
    public func write(to fileURL: URL, metadata: MLModelMetadata? = nil) throws {
        try NLEmbedding.write(vectors, language: modelParameters.language, revision: modelParameters.revision, to: fileURL)
    }

    public func write(toFile path: String, metadata: MLModelMetadata? = nil) throws {
        try write(to: URL(fileURLWithPath: path), metadata: metadata)
    }

    public struct ModelParameters: Sendable {
        public var language: NLLanguage?
        public var revision: Int

        public init(language: NLLanguage? = nil, revision: Int = 1) {
            self.language = language
            self.revision = revision
        }
    }
}

@available(macOS 10.15, *)
extension MLWordEmbedding: CustomStringConvertible, CustomDebugStringConvertible, CustomPlaygroundDisplayConvertible {
    public var description: String {
        "MLWordEmbedding: \(vocabularySize) words of dimension \(dimension)\nParameters: \(modelParameters)"
    }

    public var debugDescription: String { description }
    public var playgroundDescription: Any { description }
}

@available(macOS 10.15, *)
extension MLWordEmbedding.ModelParameters: CustomStringConvertible, CustomDebugStringConvertible, CustomPlaygroundDisplayConvertible {
    public var description: String { "ModelParameters(language: \(language?.rawValue ?? "automatic"), revision: \(revision))" }
    public var debugDescription: String { description }
    public var playgroundDescription: Any { description }
}

// What the Swift 5.0 overlay's tabular trainers had: a model of its engine,
// which a trainer was made from and kept. Neither can be made in Perry.

extension MLBoostedTreeClassifier {
    @usableFromInline var _model: _Model { unreachableTrainer(Self.self) }
    @usableFromInline init(_ model: _Model) throws { throw trainingUnavailable(Self.self) }
}

extension MLBoostedTreeRegressor {
    @usableFromInline var _model: _Model { unreachableTrainer(Self.self) }
    @usableFromInline init(_ model: _Model) throws { throw trainingUnavailable(Self.self) }
}

extension MLDecisionTreeClassifier {
    @usableFromInline var _model: _Model { unreachableTrainer(Self.self) }
    @usableFromInline init(_ model: _Model) throws { throw trainingUnavailable(Self.self) }
}

extension MLDecisionTreeRegressor {
    @usableFromInline var _model: _Model { unreachableTrainer(Self.self) }
    @usableFromInline init(_ model: _Model) throws { throw trainingUnavailable(Self.self) }
}

extension MLRandomForestClassifier {
    @usableFromInline var _model: _Model { unreachableTrainer(Self.self) }
    @usableFromInline init(_ model: _Model) throws { throw trainingUnavailable(Self.self) }
}

extension MLRandomForestRegressor {
    @usableFromInline var _model: _Model { unreachableTrainer(Self.self) }
    @usableFromInline init(_ model: _Model) throws { throw trainingUnavailable(Self.self) }
}

extension MLLinearRegressor {
    @usableFromInline var _model: _Model { unreachableTrainer(Self.self) }
    @usableFromInline init(_ model: _Model) throws { throw trainingUnavailable(Self.self) }
}

extension MLLogisticRegressionClassifier {
    @usableFromInline var _model: _Model { unreachableTrainer(Self.self) }
    @usableFromInline init(_ model: _Model) throws { throw trainingUnavailable(Self.self) }
}

extension MLSupportVectorClassifier {
    @usableFromInline var _model: _Model { unreachableTrainer(Self.self) }
    @usableFromInline init(_ model: _Model) throws { throw trainingUnavailable(Self.self) }
}

extension MLImageClassifier {
    @usableFromInline var _model: _Model { unreachableTrainer(Self.self) }
    @usableFromInline init(_ model: _Model) throws { throw trainingUnavailable(Self.self) }
}

extension MLImageClassifier.ImageAugmentationOptions {
    /// Every augmentation.
    @usableFromInline
    static var allOptions: MLImageClassifier.ImageAugmentationOptions { [.blur, .flip, .exposure, .noise, .rotation, .crop] }
}

// The Swift 5.0 overlay's text classifier and word tagger evaluated tables
// of the columns their parameters named.

extension MLTextClassifier {
    @usableFromInline
    func evaluation(on labeledTexts: MLDataTable) -> MLClassifierMetrics {
        evaluation(on: labeledTexts, textColumn: modelParameters.textColumnValidationData ?? "text",
                   labelColumn: modelParameters.labelColumnValidationData ?? "label")
    }
}

extension MLTextClassifier.ModelParameters {
    @usableFromInline
    init(validationData: MLDataTable?, algorithm: MLTextClassifier.ModelAlgorithmType, language: NLLanguage?) {
        self.init(validationData: validationData, algorithm: algorithm, language: language,
                  textColumnValidationData: nil, labelColumnValidationData: nil)
    }
}

extension MLWordTagger {
    @usableFromInline
    func evaluation(on labeledTokens: MLDataTable) -> MLWordTaggerMetrics {
        evaluation(on: labeledTokens, tokenColumn: modelParameters.tokenColumnValidationData ?? "tokens",
                   labelColumn: modelParameters.labelColumnValidationData ?? "labels")
    }
}

extension MLWordTagger.ModelParameters {
    @usableFromInline
    init(validationData: MLDataTable?, algorithm: MLWordTagger.ModelAlgorithmType, language: NLLanguage?) {
        self.init(validationData: validationData, algorithm: algorithm, language: language,
                  tokenColumnValidationData: nil, labelColumnValidationData: nil)
    }
}

extension MLStyleTransfer {
    /// The sizes and ranges Apple's style transfer models have.
    @usableFromInline
    struct __Constants {
        @usableFromInline static var inferenceWidth: Int { 512 }
        @usableFromInline static var inferenceHeight: Int { 512 }
        @usableFromInline static var inferenceChannels: Int { 3 }
        @usableFromInline static var styleStrengthRange: Range<Int> { 1..<11 }
        @usableFromInline static var textelDensityRange: Range<Int> { 64..<1025 }
    }
}
