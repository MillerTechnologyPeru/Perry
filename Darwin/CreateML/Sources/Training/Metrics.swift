import CoreGraphics
import Foundation
import TabularData

// The metrics of classifiers, regressors, taggers, detectors and
// recommenders. They hold an error instead of values when evaluating
// failed, which is how Perry's trainers report that they can't evaluate.

/// A table as a data frame, its columns of integers, doubles and strings
/// typed, other columns of MLDataValue.
func makeDataFrame(_ table: MLDataTable) -> DataFrame {
    var frame = DataFrame()
    guard let table = table.table else { return frame }
    for (name, column) in zip(table.names, table.columnList) {
        switch column.type {
        case .int64: frame.append(column: Column<Int>(name: name, contents: column.values.map(\.intValue)))
        case .double: frame.append(column: Column<Double>(name: name, contents: column.values.map { $0.number }))
        case .string: frame.append(column: Column<String>(name: name, contents: column.values.map(\.stringValue)))
        default: frame.append(column: Column<MLDataValue>(name: name, contents: column.values.map { $0.isValid ? $0 : nil }))
        }
    }
    return frame
}

/// A data frame as a table, each column's values as data values.
func makeDataTable(_ frame: DataFrame) -> MLDataTable {
    let table = CMLTable()
    for column in frame.columns {
        let values = column.map { element -> MLDataValue in
            guard let element else { return .invalid }
            return (try? MLDataValue(fromAny: element)) ?? .string(String(describing: element))
        }
        try? table.addColumn(name: column.name, CMLColumn(values: values))
    }
    return MLDataTable(table)
}

/// A confusion table: a row for each pair of true and predicted labels.
func confusionTable(truth: [MLDataValue], predicted: [MLDataValue]) -> MLDataTable {
    var counts: [[MLDataValue]: Int] = [:], order: [[MLDataValue]] = []
    for pair in zip(truth, predicted) {
        let key = [pair.0, pair.1]
        if counts[key] == nil { order.append(key) }
        counts[key, default: 0] += 1
    }
    order.sort { $0[0].compare($1[0]) == .orderedAscending || ($0[0] == $1[0] && $0[1].compare($1[1]) == .orderedAscending) }
    return MLDataTable(CMLTable(names: ["True Label", "Predicted", "Count"], columns: [
        CMLColumn(values: order.map { $0[0] }), CMLColumn(values: order.map { $0[1] }),
        CMLColumn(values: order.map { .int(counts[$0]!) }, type: .int64),
    ]))
}

/// A table of each class's precision and recall.
func precisionRecallTable(truth: [MLDataValue], predicted: [MLDataValue], classes: [MLDataValue]) -> MLDataTable {
    var precision: [MLDataValue] = [], recall: [MLDataValue] = []
    for label in classes {
        let truePositives = zip(truth, predicted).filter { $0 == label && $1 == label }.count
        let predictedCount = predicted.filter { $0 == label }.count
        let actualCount = truth.filter { $0 == label }.count
        precision.append(predictedCount == 0 ? .invalid : .double(Double(truePositives) / Double(predictedCount)))
        recall.append(actualCount == 0 ? .invalid : .double(Double(truePositives) / Double(actualCount)))
    }
    return MLDataTable(CMLTable(names: ["Class", "Precision", "Recall"], columns: [
        CMLColumn(values: classes), CMLColumn(values: precision, type: .double), CMLColumn(values: recall, type: .double),
    ]))
}

@available(macOS 10.14, iOS 15.0, tvOS 16.0, *)
public struct MLClassifierMetrics {
    private let result: _ResultType<(classificationError: Double, confusion: MLDataTable, precisionRecall: MLDataTable, examples: Int)>

    public init(classificationError: Double, confusion: MLDataTable, precisionRecall: MLDataTable) {
        let examples = confusion["Count"].ints?.sum() ?? 0
        self.init(classificationError: classificationError, confusion: confusion, precisionRecall: precisionRecall, numberOfExamples: examples)
    }

    @usableFromInline
    init(classificationError: Double, confusion: MLDataTable, precisionRecall: MLDataTable, numberOfExamples: Int) {
        result = .success((classificationError, confusion, precisionRecall, numberOfExamples))
    }

    @usableFromInline
    init(error: any Error) {
        result = .failure(error)
    }

    public var error: (any Error)? { result.error }
    public var isValid: Bool { error == nil }
    public var classificationError: Double { result.value?.classificationError ?? .nan }
    public var confusion: MLDataTable { result.value?.confusion ?? MLDataTable(error: error!) }
    public var confusionDataFrame: DataFrame { makeDataFrame(confusion) }
    public var precisionRecall: MLDataTable { result.value?.precisionRecall ?? MLDataTable(error: error!) }
    public var precisionRecallDataFrame: DataFrame { makeDataFrame(precisionRecall) }

    @usableFromInline
    var accuracyDescription: String {
        guard isValid else { return "Accuracy: unavailable" }
        return String(format: "Accuracy: %.2f%%", (1 - classificationError) * 100)
    }

    @usableFromInline
    var confusionMatrixDescription: String { "Confusion matrix:\n\(confusion)" }

    @usableFromInline
    var precisionRecallDescription: String { "Precision and recall:\n\(precisionRecall)" }

    @usableFromInline
    var playgroundTrainAccuracyDescription: String { "Training \(accuracyDescription.lowercased())" }

    @usableFromInline
    var playgroundValidationAccuracyDescription: String { "Validation \(accuracyDescription.lowercased())" }

    /// The metrics of predictions in a column of a table against the
    /// labels in another.
    public static func __evaluation(on table: MLDataTable, labelColumn: String, predictionColumn: String, classes: [String]) throws -> MLClassifierMetrics {
        let storage = try table.getImpl()
        let truth = try storage.column(name: labelColumn).values
        let predicted = try storage.column(name: predictionColumn).values
        guard !truth.isEmpty else { throw MLCreateError.generic(reason: "There are no examples to evaluate.") }
        let errors = zip(truth, predicted).filter { !$0.equals($1) }.count
        var labels = classes.map(MLDataValue.string)
        if labels.isEmpty { labels = Array(Set(truth + predicted).filter(\.isValid)).sorted { $0.compare($1) == .orderedAscending } }
        return MLClassifierMetrics(classificationError: Double(errors) / Double(truth.count),
                                   confusion: confusionTable(truth: truth, predicted: predicted),
                                   precisionRecall: precisionRecallTable(truth: truth, predicted: predicted, classes: labels),
                                   numberOfExamples: truth.count)
    }
}

@available(*, unavailable)
extension MLClassifierMetrics: Sendable {}

extension MLClassifierMetrics: CustomStringConvertible, CustomDebugStringConvertible, CustomPlaygroundDisplayConvertible {
    public var description: String {
        guard isValid else { return "Invalid metrics: \(error!)" }
        return "\(accuracyDescription)\n\(confusionMatrixDescription)\n\(precisionRecallDescription)"
    }

    public var debugDescription: String { description }
    public var playgroundDescription: Any { isValid ? accuracyDescription : description }
}

@available(macOS 10.14, iOS 15.0, tvOS 16.0, *)
public struct MLRegressorMetrics: Sendable {
    private let values: (maximumError: Double, rootMeanSquaredError: Double)?
    private let failure: String?

    public var error: (any Error)? { failure.map { MLCreateError.generic(reason: $0) } }
    public var isValid: Bool { failure == nil }
    public var maximumError: Double { values?.maximumError ?? .nan }
    public var rootMeanSquaredError: Double { values?.rootMeanSquaredError ?? .nan }

    public init(maximumError: Double, rootMeanSquaredError: Double) {
        values = (maximumError, rootMeanSquaredError)
        failure = nil
    }

    @usableFromInline
    init(error: any Error) {
        values = nil
        failure = (error as? LocalizedError)?.failureReason ?? error.localizedDescription
    }

    @usableFromInline
    var trainingDesc: String {
        isValid ? "Training RMSE: \(rootMeanSquaredError)\nTraining max error: \(maximumError)" : "Training metrics: unavailable"
    }

    @usableFromInline
    var validationDesc: String {
        isValid ? "Validation RMSE: \(rootMeanSquaredError)\nValidation max error: \(maximumError)" : "Validation metrics: unavailable"
    }

    /// The metrics of predictions in a column of a table against the
    /// targets in another.
    public static func __evaluation(on table: MLDataTable, targetColumn: String, predictionColumn: String) throws -> MLRegressorMetrics {
        let storage = try table.getImpl()
        let targets = try storage.column(name: targetColumn).values.map(\.number)
        let predictions = try storage.column(name: predictionColumn).values.map(\.number)
        let errors = zip(targets, predictions).compactMap { target, prediction -> Double? in
            guard let target, let prediction else { return nil }
            return abs(target - prediction)
        }
        guard !errors.isEmpty else { throw MLCreateError.generic(reason: "There are no examples to evaluate.") }
        return MLRegressorMetrics(maximumError: errors.max()!,
                                  rootMeanSquaredError: (errors.reduce(0) { $0 + $1 * $1 } / Double(errors.count)).squareRoot())
    }
}

extension MLRegressorMetrics: CustomStringConvertible, CustomDebugStringConvertible, CustomPlaygroundDisplayConvertible {
    public var description: String {
        guard isValid else { return "Invalid metrics: \(error!)" }
        return "Max error: \(maximumError)\nRMSE: \(rootMeanSquaredError)"
    }

    public var debugDescription: String { description }
    public var playgroundDescription: Any { description }
}

@available(macOS 10.14, iOS 15.0, tvOS 16.0, *)
public struct MLWordTaggerMetrics {
    private let result: _ResultType<(taggingError: Double, confusion: MLDataTable, precisionRecall: MLDataTable)>

    init(taggingError: Double, confusion: MLDataTable, precisionRecall: MLDataTable) {
        result = .success((taggingError, confusion, precisionRecall))
    }

    @usableFromInline
    init(error: any Error) {
        result = .failure(error)
    }

    public var error: (any Error)? { result.error }
    public var isValid: Bool { error == nil }
    public var taggingError: Double { result.value?.taggingError ?? .nan }
    public var confusion: MLDataTable { result.value?.confusion ?? MLDataTable(error: error!) }
    public var confusionDataFrame: DataFrame { makeDataFrame(confusion) }
    public var precisionRecall: MLDataTable { result.value?.precisionRecall ?? MLDataTable(error: error!) }
    public var precisionRecallDataFrame: DataFrame { makeDataFrame(precisionRecall) }
}

@available(*, unavailable)
extension MLWordTaggerMetrics: Sendable {}

extension MLWordTaggerMetrics: CustomStringConvertible, CustomDebugStringConvertible, CustomPlaygroundDisplayConvertible {
    public var description: String {
        guard isValid else { return "Invalid metrics: \(error!)" }
        return String(format: "Tagging accuracy: %.2f%%", (1 - taggingError) * 100) + "\nConfusion:\n\(confusion)\nPrecision and recall:\n\(precisionRecall)"
    }

    public var debugDescription: String { description }
    public var playgroundDescription: Any { description }
}

@available(macOS 10.15, iOS 15.0, tvOS 16.0, *)
public struct MLObjectDetectorMetrics: Sendable {
    private let values: (averagePrecision: (variedIoU: [String: Double], IoU50: [String: Double]),
                         meanAveragePrecision: (variedIoU: Double, IoU50: Double))?
    private let failure: String?

    public var averagePrecision: (variedIoU: [String: Double], IoU50: [String: Double]) {
        values?.averagePrecision ?? ([:], [:])
    }

    public var meanAveragePrecision: (variedIoU: Double, IoU50: Double) {
        values?.meanAveragePrecision ?? (.nan, .nan)
    }

    public init(averagePrecision: (variedIoU: [String: Double], IoU50: [String: Double]),
                meanAveragePrecision: (variedIoU: Double, IoU50: Double)) {
        values = (averagePrecision, meanAveragePrecision)
        failure = nil
    }

    init(error: any Error) {
        values = nil
        failure = (error as? LocalizedError)?.failureReason ?? error.localizedDescription
    }

    public var error: (any Error)? { failure.map { MLCreateError.generic(reason: $0) } }
    public var isValid: Bool { failure == nil }

    /// The average precisions of predicted boxes in a column of a table
    /// against the annotated ones in another: per class, at an IoU of 0.5
    /// and averaged over IoUs from 0.5 to 0.95.
    public static func __evaluation(on table: MLDataTable, imageColumn: String, annotationColumn: String,
                                    predictionColumn: String, classes: [String]) throws -> MLObjectDetectorMetrics {
        let storage = try table.getImpl()
        _ = try storage.column(name: imageColumn)
        let truth = try storage.column(name: annotationColumn).values.map(boxes)
        let predicted = try storage.column(name: predictionColumn).values.map(boxes)
        let labels = classes.isEmpty ? Array(Set(truth.flatMap { $0.map(\.label) })).sorted() : classes
        var varied: [String: Double] = [:], at50: [String: Double] = [:]
        for label in labels {
            let thresholds = stride(from: 0.5, through: 0.951, by: 0.05).map { $0 }
            let precisions = thresholds.map { averagePrecision(label: label, truth: truth, predicted: predicted, threshold: $0) }
            at50[label] = precisions[0]
            varied[label] = precisions.reduce(0, +) / Double(precisions.count)
        }
        func mean(_ values: [String: Double]) -> Double { values.isEmpty ? 0 : values.values.reduce(0, +) / Double(values.count) }
        return MLObjectDetectorMetrics(averagePrecision: (varied, at50), meanAveragePrecision: (mean(varied), mean(at50)))
    }

    /// The boxes an annotation value lists: dictionaries with a label,
    /// coordinates (x, y, width, height) and a confidence.
    static func boxes(_ value: MLDataValue) -> [(label: String, box: CGRect, confidence: Double)] {
        (value.sequenceValue ?? []).compactMap { element in
            guard let object = element.dictionaryValue, let label = object[.string("label")]?.stringValue,
                  let coordinates = object[.string("coordinates")]?.dictionaryValue else { return nil }
            func number(_ key: String) -> Double { coordinates[.string(key)]?.number ?? 0 }
            let box = CGRect(x: number("x") - number("width") / 2, y: number("y") - number("height") / 2,
                             width: number("width"), height: number("height"))
            return (label, box, object[.string("confidence")]?.number ?? 1)
        }
    }

    static func intersectionOverUnion(_ a: CGRect, _ b: CGRect) -> Double {
        let intersection = a.intersection(b)
        guard !intersection.isNull else { return 0 }
        let overlap = Double(intersection.width * intersection.height)
        let union = Double(a.width * a.height + b.width * b.height) - overlap
        return union > 0 ? overlap / union : 0
    }

    /// The area under the precision-recall curve of a class's predictions.
    static func averagePrecision(label: String, truth: [[(label: String, box: CGRect, confidence: Double)]],
                                 predicted: [[(label: String, box: CGRect, confidence: Double)]], threshold: Double) -> Double {
        var detections: [(image: Int, box: CGRect, confidence: Double)] = []
        for (image, boxes) in predicted.enumerated() {
            for box in boxes where box.label == label { detections.append((image, box.box, box.confidence)) }
        }
        detections.sort { $0.confidence > $1.confidence }
        let positives = truth.reduce(0) { $0 + $1.filter { $0.label == label }.count }
        guard positives > 0 else { return 0 }
        var matched = Set<[Int]>(), truePositives = 0, precisions: [Double] = [], recalls: [Double] = []
        for (rank, detection) in detections.enumerated() {
            let candidates = truth.indices.contains(detection.image) ? truth[detection.image] : []
            var best = -1, bestOverlap = threshold
            for (index, candidate) in candidates.enumerated() where candidate.label == label && !matched.contains([detection.image, index]) {
                let overlap = intersectionOverUnion(candidate.box, detection.box)
                if overlap >= bestOverlap { best = index; bestOverlap = overlap }
            }
            if best >= 0 { matched.insert([detection.image, best]); truePositives += 1 }
            precisions.append(Double(truePositives) / Double(rank + 1))
            recalls.append(Double(truePositives) / Double(positives))
        }
        var area = 0.0, previousRecall = 0.0
        for index in precisions.indices {
            let precision = precisions[index...].max() ?? 0
            area += (recalls[index] - previousRecall) * precision
            previousRecall = recalls[index]
        }
        return area
    }
}

extension MLObjectDetectorMetrics: CustomStringConvertible, CustomDebugStringConvertible, CustomPlaygroundDisplayConvertible {
    public var description: String {
        guard isValid else { return "Invalid metrics: \(error!)" }
        return "Mean average precision: \(meanAveragePrecision.variedIoU) (IoU 0.5: \(meanAveragePrecision.IoU50))"
    }

    public var debugDescription: String { description }
    public var playgroundDescription: Any { description }
}

@available(macOS 10.15, *)
public struct MLRecommenderMetrics {
    public let excludingObserved: Bool
    public let error: (any Error)?
    private let table: MLDataTable

    public var isValid: Bool { error == nil }
    public var precisionRecallDataFrame: DataFrame { makeDataFrame(table) }
    public var precisionRecall: MLDataTable { table }

    public init(precisionRecall: MLDataTable, excludingObserved: Bool) {
        self.table = precisionRecall
        self.excludingObserved = excludingObserved
        self.error = precisionRecall.error
    }

    init(error: any Error) {
        self.table = MLDataTable(error: error)
        self.excludingObserved = true
        self.error = error
    }
}

@available(*, unavailable)
extension MLRecommenderMetrics: Sendable {}
