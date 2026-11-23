import CoreML
import Foundation

// The model side of the Swift 5.0 overlay's bridge to its C engine:
// models, the parameters and results of calls to the engine, and the class
// its trainers kept their model in. Perry has no engine to train or run
// models, so making or calling one throws the error that says so; the
// parameters and results themselves are plain values.

/// What a call to the engine returns or takes: a value, a column, a
/// table, a model or more parameters.
@usableFromInline
final class CMLVariant {
    enum Content {
        case featureValue(CMLFeatureValue)
        case column(CMLColumn)
        case table(CMLTable)
        case model(CMLModel)
        case parameters(CMLParameters)
    }

    let content: Content

    init(_ content: Content) {
        self.content = content
    }

    private func mismatch(_ wanted: String) -> MLCreateError {
        .type(reason: "The engine's result is not \(wanted).")
    }

    @usableFromInline
    func isFeatureValue() -> Bool { if case .featureValue = content { return true }; return false }
    @usableFromInline
    func isColumn() -> Bool { if case .column = content { return true }; return false }
    @usableFromInline
    func isTable() -> Bool { if case .table = content { return true }; return false }
    @usableFromInline
    func isModel() -> Bool { if case .model = content { return true }; return false }
    @usableFromInline
    func isParameters() -> Bool { if case .parameters = content { return true }; return false }

    @usableFromInline
    func featureValue() throws -> CMLFeatureValue {
        guard case .featureValue(let value) = content else { throw mismatch("a value") }
        return value
    }

    @usableFromInline
    func column() throws -> CMLColumn {
        guard case .column(let value) = content else { throw mismatch("a column") }
        return value
    }

    @usableFromInline
    func table() throws -> CMLTable {
        guard case .table(let value) = content else { throw mismatch("a table") }
        return value
    }

    @usableFromInline
    func model() throws -> CMLModel {
        guard case .model(let value) = content else { throw mismatch("a model") }
        return value
    }

    @usableFromInline
    func parameters() throws -> CMLParameters {
        guard case .parameters(let value) = content else { throw mismatch("parameters") }
        return value
    }
}

/// Named arguments of a call to the engine.
@usableFromInline
final class CMLParameters {
    var values: [String: CMLVariant] = [:]

    @usableFromInline
    init() {}

    @usableFromInline
    func add(key: String, featureValue: CMLFeatureValue) throws { values[key] = CMLVariant(.featureValue(featureValue)) }
    @usableFromInline
    func add(key: String, column: CMLColumn) throws { values[key] = CMLVariant(.column(column)) }
    @usableFromInline
    func add(key: String, table: CMLTable) throws { values[key] = CMLVariant(.table(table)) }

    @usableFromInline
    func contains(key: String) throws -> Bool { values[key] != nil }

    @usableFromInline
    func variant(for key: String) throws -> CMLVariant {
        guard let value = values[key] else { throw MLCreateError.generic(reason: "There is no parameter \(key).") }
        return value
    }

    @usableFromInline
    func featureValue(for key: String) throws -> CMLFeatureValue { try variant(for: key).featureValue() }
    @usableFromInline
    func column(for key: String) throws -> CMLColumn { try variant(for: key).column() }
    @usableFromInline
    func table(for key: String) throws -> CMLTable { try variant(for: key).table() }
}

/// A model of the engine's.
@usableFromInline
final class CMLModel {
    let modelName: String

    /// The engine's model of a name: Perry has none.
    @usableFromInline
    init(name: String) throws {
        throw unavailable("The model \(name)")
    }

    /// A model the engine saved at a URL: Perry can't load one.
    @usableFromInline
    init(url: URL) throws {
        throw unavailable("Loading the model at \(url.path)")
    }

    @usableFromInline
    func name() throws -> String { modelName }

    @usableFromInline
    func callFunction(name: String, arguments: CMLParameters) throws -> CMLVariant {
        throw unavailable("Calling \(name) on a model")
    }
}

/// Calls a function of the engine: Perry has none.
@usableFromInline
func CMLCallFunction(name: String, arguments: CMLParameters) throws -> CMLVariant {
    throw unavailable("The engine function \(name)")
}

/// The model a tabular trainer of the Swift 5.0 overlay kept: the engine's
/// model, its kind and the Core ML model it exported. Making one throws in
/// Perry, as training does.
@usableFromInline @_fixed_layout
class _Model {
    @usableFromInline
    enum ModelType: Hashable, CustomStringConvertible, CustomDebugStringConvertible, CustomPlaygroundDisplayConvertible {
        case boostedTreeClassifier, boostedTreeRegressor
        case decisionTreeClassifier, decisionTreeRegressor
        case randomForestClassifier, randomForestRegressor
        case linearRegressor, logisticRegressionClassifier, supportVectorClassifier
        case automaticClassifier, automaticRegressor

        @usableFromInline
        static func modelType(fromName name: String) -> ModelType {
            switch name {
            case "btc": return .boostedTreeClassifier
            case "btr": return .boostedTreeRegressor
            case "dtc": return .decisionTreeClassifier
            case "dtr": return .decisionTreeRegressor
            case "rfc": return .randomForestClassifier
            case "rfr": return .randomForestRegressor
            case "lr": return .linearRegressor
            case "lrc": return .logisticRegressionClassifier
            case "svc": return .supportVectorClassifier
            case "automaticRegressor": return .automaticRegressor
            default: return .automaticClassifier
            }
        }

        @usableFromInline
        var description: String {
            switch self {
            case .boostedTreeClassifier: return "Boosted Tree Classifier"
            case .boostedTreeRegressor: return "Boosted Tree Regressor"
            case .decisionTreeClassifier: return "Decision Tree Classifier"
            case .decisionTreeRegressor: return "Decision Tree Regressor"
            case .randomForestClassifier: return "Random Forest Classifier"
            case .randomForestRegressor: return "Random Forest Regressor"
            case .linearRegressor: return "Linear Regressor"
            case .logisticRegressionClassifier: return "Logistic Regression Classifier"
            case .supportVectorClassifier: return "Support Vector Classifier"
            case .automaticClassifier: return "Classifier"
            case .automaticRegressor: return "Regressor"
            }
        }

        @usableFromInline var debugDescription: String { description }
        @usableFromInline var playgroundDescription: Any { description }
    }

    /// A training parameter, by its engine key.
    @usableFromInline
    enum Parameters {
        case value(key: String, MLDataValue)
        case table(key: String, MLDataTable)
    }

    /// What a call to a model returns.
    @usableFromInline
    enum Output {
        case variant(CMLVariant)
        case error(any Error)
    }

    @usableFromInline let impl: CMLModel
    @usableFromInline var type: ModelType
    @usableFromInline var model: MLModel
    var storedAttributes: [String: Any] = [:]

    @usableFromInline
    init(impl: CMLModel) throws {
        throw unavailable("Loading a trained model")
    }

    @usableFromInline
    init(type: ModelType, table: MLDataTable, target: String, features: [String]? = nil, parameters: [Parameters]) throws {
        throw unavailable("Training a \(type)")
    }

    @usableFromInline
    static func make(regressor: Bool? = nil, classifier: Bool? = nil, with table: MLDataTable, targetColumn: String,
                     featureColumns: [String]? = nil) throws -> _Model {
        throw unavailable("Training a model")
    }

    @usableFromInline
    var attributes: [String: Any] {
        get { storedAttributes }
        set { storedAttributes = newValue }
    }

    @usableFromInline
    func getAttributes() -> [String: Any] { storedAttributes }

    @usableFromInline
    var targetColumn: String { storedAttributes["target"] as? String ?? "" }

    @usableFromInline
    var featureColumns: [String] { storedAttributes["featureColumns"] as? [String] ?? [] }

    @usableFromInline
    func callFunction(name: String, arguments: CMLParameters) throws -> Output {
        .variant(try impl.callFunction(name: name, arguments: arguments))
    }

    @usableFromInline
    func altPrediction(from table: MLDataTable) -> Output {
        .error(unavailable("Predicting with a model"))
    }

    @usableFromInline
    func predictions(from table: MLDataTable, for columns: [String]) throws -> MLUntypedColumn {
        throw unavailable("Predicting with a model")
    }

    @usableFromInline
    func evaluation(from table: MLDataTable) throws -> CMLVariant {
        throw unavailable("Evaluating a model")
    }

    @usableFromInline
    func regressorEvaluation(_ table: MLDataTable) -> MLRegressorMetrics {
        MLRegressorMetrics(error: unavailable("Evaluating a model"))
    }

    @usableFromInline
    func classifierEvaluation(_ table: MLDataTable?) -> MLClassifierMetrics {
        MLClassifierMetrics(error: unavailable("Evaluating a model"))
    }

    @usableFromInline
    func makeRegressorMetrics(onTraining: Bool) -> MLRegressorMetrics {
        MLRegressorMetrics(error: unavailable("Evaluating a model"))
    }

    @usableFromInline
    func makeClassifierMetrics(onTraining: Bool? = nil, onValidation: Bool? = nil) -> MLClassifierMetrics {
        MLClassifierMetrics(error: unavailable("Evaluating a model"))
    }

    @usableFromInline
    func write(to url: URL, metadata: MLModelMetadata? = nil) throws {
        throw unavailable("Exporting a model")
    }

    @usableFromInline
    func write(toFile path: String, metadata: MLModelMetadata? = nil) throws {
        try write(to: URL(fileURLWithPath: path), metadata: metadata)
    }

    @usableFromInline
    static func descriptions(type: String, parameters: String, trainingMetrics: String,
                             validationMetrics: (isValid: Bool, description: String)) -> String {
        var text = "\(type)\n\nParameters\n\(parameters)\n\nPerformance on Training Data\n\(trainingMetrics)"
        if validationMetrics.isValid { text += "\n\nPerformance on Validation Data\n\(validationMetrics.description)" }
        return text
    }

    @usableFromInline
    static func debugDescriptions(type: String, parameters: String, trainingMetrics: String,
                                  validationMetrics: (isValid: Bool, description: String)) -> String {
        descriptions(type: type, parameters: parameters, trainingMetrics: trainingMetrics, validationMetrics: validationMetrics)
    }

    @usableFromInline
    static func playgroundDescriptions(type: String, trainingMetrics: String, validationMetrics: (isValid: Bool, desc: String)) -> Any {
        validationMetrics.isValid ? "\(type)\n\(trainingMetrics)\n\(validationMetrics.desc)" : "\(type)\n\(trainingMetrics)"
    }
}

// File and data helpers of the Swift 5.0 overlay's trainers.

@usableFromInline
struct _FileUtilities {
    @usableFromInline
    init() {}

    static let imageExtensions: Set<String> = ["jpg", "jpeg", "png", "heic", "heif", "tif", "tiff", "bmp", "gif"]
    static let textExtensions: Set<String> = ["txt", "text", "md", "csv", "json", "html", "rtf"]

    static func contents(of directory: URL) throws -> [URL] {
        try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.isDirectoryKey, .isReadableKey],
                                                    options: [.skipsHiddenFiles])
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    static func isDirectory(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
    }

    @usableFromInline
    static func getReadableSubdirectoriesOfDirectory(at url: URL) throws -> [URL] {
        try contents(of: url).filter(isDirectory)
    }

    @usableFromInline
    static func getReadableImageFilesInDirectory(at url: URL) throws -> [URL] {
        try contents(of: url).filter { !isDirectory($0) && imageExtensions.contains($0.pathExtension.lowercased()) }
    }

    @usableFromInline
    static func getReadableTextFilesInDirectory(at url: URL) throws -> [URL] {
        try contents(of: url).filter { !isDirectory($0) && FileManager.default.isReadableFile(atPath: $0.path) }
    }

    /// Makes the directory a file is to be written in, or the directory to
    /// be written.
    @usableFromInline
    static func prepareForWriting(to url: URL, isDirectory: Bool) throws {
        let directory = isDirectory ? url : url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }
}

@usableFromInline
struct _FeatureUtilities {
    @usableFromInline
    init() {}

    /// The features to use: those selected, or all of them.
    @usableFromInline
    static func selectFeatures(from features: [String], select: [String]?) -> [String] {
        guard let select else { return features }
        return features.filter(select.contains)
    }
}

@usableFromInline
struct _ImageUtilities {
    @usableFromInline
    init() {}

    @usableFromInline
    static func getImageURLsAndLabels(from source: MLImageClassifier.DataSource) throws -> [String: [URL]] {
        try source.labeledImages()
    }

    @usableFromInline
    static func validateImageURLs(from urls: [URL]) -> [URL] {
        urls.filter { FileManager.default.isReadableFile(atPath: $0.path) && _FileUtilities.imageExtensions.contains($0.pathExtension.lowercased()) }
    }
}

@usableFromInline
struct _TextUtilities {
    @usableFromInline
    init() {}

    @usableFromInline
    static func getTextLabeledDictionary(from source: MLTextClassifier.DataSource) throws -> [String: [String]] {
        try source.labeledTexts()
    }

    @usableFromInline
    static func getTextLabels(from source: MLTextClassifier.DataSource) throws -> (data: MLDataTable, labelKey: String, textKey: String) {
        let texts = try source.labeledTexts()
        var labels: [MLDataValue] = [], bodies: [MLDataValue] = []
        for (label, items) in texts.sorted(by: { $0.key < $1.key }) {
            for text in items { labels.append(.string(label)); bodies.append(.string(text)) }
        }
        let table = CMLTable(names: ["label", "text"], columns: [CMLColumn(values: labels, type: .string), CMLColumn(values: bodies, type: .string)])
        return (MLDataTable(table), "label", "text")
    }
}

// The default arguments of _Model's methods, which the Swift 5.0 overlay's
// compiler exported as functions and today's emits into callers instead.

@_spi(Swift50) @_silgen_name("$s8CreateML6_ModelC21makeClassifierMetrics10onTraining0G10ValidationAA012MLClassifierF0VSbSg_AItFfA_")
public func _makeClassifierMetricsDefault0() -> Bool? { nil }

@_spi(Swift50) @_silgen_name("$s8CreateML6_ModelC21makeClassifierMetrics10onTraining0G10ValidationAA012MLClassifierF0VSbSg_AItFfA0_")
public func _makeClassifierMetricsDefault1() -> Bool? { nil }

@_spi(Swift50) @_silgen_name("$s8CreateML6_ModelC4make9regressor10classifier4with12targetColumn14featureColumnsACSbSg_AjA11MLDataTableVSSSaySSGSgtKFZfA_")
public func _makeDefault0() -> Bool? { nil }

@_spi(Swift50) @_silgen_name("$s8CreateML6_ModelC4make9regressor10classifier4with12targetColumn14featureColumnsACSbSg_AjA11MLDataTableVSSSaySSGSgtKFZfA0_")
public func _makeDefault1() -> Bool? { nil }

@_spi(Swift50) @_silgen_name("$s8CreateML6_ModelC4make9regressor10classifier4with12targetColumn14featureColumnsACSbSg_AjA11MLDataTableVSSSaySSGSgtKFZfA3_")
public func _makeDefault4() -> [String]? { nil }

@_spi(Swift50) @_silgen_name("$s8CreateML6_ModelC4type5table6target8features10parametersA2C0C4TypeO_AA11MLDataTableVSSSaySSGSgSayAC10ParametersOGtKcfcfA2_")
public func _initDefault3() -> [String]? { nil }

@_spi(Swift50) @_silgen_name("$s8CreateML6_ModelC5write2to8metadatay10Foundation3URLV_AA15MLModelMetadataVSgtKFfA0_")
public func _writeToDefault1() -> MLModelMetadata? { nil }

@_spi(Swift50) @_silgen_name("$s8CreateML6_ModelC5write6toFile8metadataySS_AA15MLModelMetadataVSgtKFfA0_")
public func _writeToFileDefault1() -> MLModelMetadata? { nil }
