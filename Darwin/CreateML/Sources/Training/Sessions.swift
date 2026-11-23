import Combine
import CoreGraphics
import Foundation

// Training sessions, jobs, checkpoints and progress: the machinery
// CreateML's asynchronous training reports through. Perry's has these as
// values, but no session ever trains (see Trainers), so jobs it makes end
// in the error that says so.

@available(macOS 11.0, iOS 15.0, tvOS 16.0, *)
public enum MLPhase: String, Codable, Sendable, Hashable {
    case initialized
    case extractingFeatures
    case training
    case evaluating
    case inferencing
}

@available(macOS 10.14, iOS 15.0, tvOS 16.0, *)
public enum MLSplitStrategy: Sendable {
    case automatic
    case fixed(ratio: Double, seed: Int?)

    /// The proportion of examples to train on and the seed to split them
    /// with: all of them for fewer than 50, else 95%, for `automatic`.
    public func resolve(count: Int) -> (ratio: Double, seed: Int) {
        switch self {
        case .automatic: return (count < 50 ? 1.0 : 0.95, 42)
        case .fixed(let ratio, let seed): return (ratio, seed ?? timestampSeed())
        }
    }
}

@available(macOS 10.14, iOS 15.0, tvOS 16.0, *)
public struct MLModelMetadata: Sendable {
    public var author: String
    public var shortDescription: String
    public var license: String?
    public var version: String
    public var additional: [String: String]?

    public init(author: String = NSFullUserName(), shortDescription: String = "A model trained using CreateML for use with CoreML.",
                license: String? = nil, version: String = "1", additional: [String: String]? = nil) {
        self.author = author
        self.shortDescription = shortDescription
        self.license = license
        self.version = version
        self.additional = additional
    }
}

@available(macOS 11.0, iOS 15.0, tvOS 16.0, *)
public struct MLProgress: Codable {
    public var elapsedTime: TimeInterval
    public var phase: MLPhase
    public var itemCount: Int
    public var totalItemCount: Int?
    public var metrics: [MLProgress.Metric: Any]

    public init(phase: MLPhase) {
        self.elapsedTime = 0
        self.phase = phase
        self.itemCount = 0
        self.totalItemCount = nil
        self.metrics = [:]
    }

    /// The progress a Progress of a job reports in its user info.
    public init?(progress: Progress) {
        let info = progress.userInfo
        guard let phase = (info[MLProgress.phaseKey] as? String).flatMap(MLPhase.init(rawValue:)) ?? info[MLProgress.phaseKey] as? MLPhase
        else { return nil }
        self.init(phase: phase)
        elapsedTime = info[MLProgress.elapsedTimeKey] as? TimeInterval ?? 0
        itemCount = info[MLProgress.itemCountKey] as? Int ?? Int(progress.completedUnitCount)
        totalItemCount = info[MLProgress.totalItemCountKey] as? Int ?? (progress.totalUnitCount > 0 ? Int(progress.totalUnitCount) : nil)
        for metric in Metric.allCases {
            if let value = info[metric.key] { metrics[metric] = value }
        }
    }

    public enum Metric: String, Codable, Hashable, CaseIterable, Sendable {
        case loss
        case contentLoss
        case styleLoss
        case accuracy
        case validationLoss
        case validationAccuracy
        case stylizedImageURL
        case rootMeanSquaredError
        case maximumError
        case validationRootMeanSquaredError
        case validationMaximumError

        /// The user info key a job's Progress reports the metric under.
        var key: ProgressUserInfoKey {
            switch self {
            case .loss: return MLProgress.lossKey
            case .contentLoss: return MLProgress.contentLossKey
            case .styleLoss: return MLProgress.styleLossKey
            case .accuracy: return MLProgress.accuracyKey
            case .validationLoss: return MLProgress.validationLossKey
            case .validationAccuracy: return MLProgress.validationAccuracyKey
            case .stylizedImageURL: return MLProgress.stylizedImageKey
            case .rootMeanSquaredError: return MLProgress.rootMeanSquaredErrorKey
            case .maximumError: return MLProgress.maximumErrorKey
            case .validationRootMeanSquaredError: return MLProgress.validationRootMeanSquaredErrorKey
            case .validationMaximumError: return MLProgress.validationMaximumErrorKey
            }
        }
    }

    private enum CodingKeys: String, CodingKey {
        case elapsedTime, phase, itemCount, totalItemCount, metrics
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        elapsedTime = try container.decode(TimeInterval.self, forKey: .elapsedTime)
        phase = try container.decode(MLPhase.self, forKey: .phase)
        itemCount = try container.decode(Int.self, forKey: .itemCount)
        totalItemCount = try container.decodeIfPresent(Int.self, forKey: .totalItemCount)
        metrics = try decodeMetrics(container.decodeIfPresent([String: MetricValue].self, forKey: .metrics) ?? [:])
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(elapsedTime, forKey: .elapsedTime)
        try container.encode(phase, forKey: .phase)
        try container.encode(itemCount, forKey: .itemCount)
        try container.encodeIfPresent(totalItemCount, forKey: .totalItemCount)
        try container.encode(encodeMetrics(metrics), forKey: .metrics)
    }
}

@available(*, unavailable)
extension MLProgress: Sendable {}

@available(macOS 11.0, iOS 15.0, tvOS 16.0, *)
extension MLProgress {
    public static var elapsedTimeKey: ProgressUserInfoKey { ProgressUserInfoKey("com.apple.createml.progress.elapsedTime") }
    public static var phaseKey: ProgressUserInfoKey { ProgressUserInfoKey("com.apple.createml.progress.phase") }
    public static var itemCountKey: ProgressUserInfoKey { ProgressUserInfoKey("com.apple.createml.progress.itemCount") }
    public static var totalItemCountKey: ProgressUserInfoKey { ProgressUserInfoKey("com.apple.createml.progress.totalItemCount") }
    public static var lossKey: ProgressUserInfoKey { ProgressUserInfoKey("com.apple.createml.progress.loss") }
    public static var contentLossKey: ProgressUserInfoKey { ProgressUserInfoKey("com.apple.createml.progress.contentLoss") }
    public static var styleLossKey: ProgressUserInfoKey { ProgressUserInfoKey("com.apple.createml.progress.styleLoss") }
    public static var accuracyKey: ProgressUserInfoKey { ProgressUserInfoKey("com.apple.createml.progress.accuracy") }
    public static var validationLossKey: ProgressUserInfoKey { ProgressUserInfoKey("com.apple.createml.progress.validationLoss") }
    public static var validationAccuracyKey: ProgressUserInfoKey { ProgressUserInfoKey("com.apple.createml.progress.validationAccuracy") }
    public static var stylizedImageKey: ProgressUserInfoKey { ProgressUserInfoKey("com.apple.createml.progress.stylizedImage") }
    public static var rootMeanSquaredErrorKey: ProgressUserInfoKey { ProgressUserInfoKey("com.apple.createml.progress.rootMeanSquaredError") }
    public static var maximumErrorKey: ProgressUserInfoKey { ProgressUserInfoKey("com.apple.createml.progress.maximumError") }
    public static var validationRootMeanSquaredErrorKey: ProgressUserInfoKey { ProgressUserInfoKey("com.apple.createml.progress.validationRootMeanSquaredError") }
    public static var validationMaximumErrorKey: ProgressUserInfoKey { ProgressUserInfoKey("com.apple.createml.progress.validationMaximumError") }
}

/// A metric's value as it's encoded: a number or a URL.
enum MetricValue: Codable {
    case number(Double)
    case url(URL)

    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let number = try? container.decode(Double.self) { self = .number(number) } else { self = .url(try container.decode(URL.self)) }
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .number(let number): try container.encode(number)
        case .url(let url): try container.encode(url)
        }
    }
}

func encodeMetrics(_ metrics: [MLProgress.Metric: Any]) -> [String: MetricValue] {
    var encoded: [String: MetricValue] = [:]
    for (metric, value) in metrics {
        switch value {
        case let url as URL: encoded[metric.rawValue] = .url(url)
        case let number as Double: encoded[metric.rawValue] = .number(number)
        case let number as Float: encoded[metric.rawValue] = .number(Double(number))
        case let number as Int: encoded[metric.rawValue] = .number(Double(number))
        case let number as NSNumber: encoded[metric.rawValue] = .number(number.doubleValue)
        default: break
        }
    }
    return encoded
}

func decodeMetrics(_ encoded: [String: MetricValue]) -> [MLProgress.Metric: Any] {
    var metrics: [MLProgress.Metric: Any] = [:]
    for (name, value) in encoded {
        guard let metric = MLProgress.Metric(rawValue: name) else { continue }
        switch value {
        case .number(let number): metrics[metric] = number
        case .url(let url): metrics[metric] = url
        }
    }
    return metrics
}

@available(macOS 11.0, iOS 15.0, tvOS 16.0, *)
public struct MLCheckpoint: Codable {
    public var url: URL
    public var phase: MLPhase
    public var iteration: Int
    public var date: Date
    private var metricValues: [String: MetricValue]

    public var metrics: [MLProgress.Metric: Any] {
        get { decodeMetrics(metricValues) }
        set { metricValues = encodeMetrics(newValue) }
    }

    init(url: URL, phase: MLPhase, iteration: Int, date: Date = Date(), metrics: [MLProgress.Metric: Any] = [:]) {
        self.url = url
        self.phase = phase
        self.iteration = iteration
        self.date = date
        self.metricValues = encodeMetrics(metrics)
    }

    private enum CodingKeys: String, CodingKey {
        case url, phase, iteration, date, metrics
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        url = try container.decode(URL.self, forKey: .url)
        phase = try container.decode(MLPhase.self, forKey: .phase)
        iteration = try container.decode(Int.self, forKey: .iteration)
        date = try container.decode(Date.self, forKey: .date)
        metricValues = try container.decodeIfPresent([String: MetricValue].self, forKey: .metrics) ?? [:]
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(url, forKey: .url)
        try container.encode(phase, forKey: .phase)
        try container.encode(iteration, forKey: .iteration)
        try container.encode(date, forKey: .date)
        try container.encode(metricValues, forKey: .metrics)
    }
}

extension MLCheckpoint: Sendable {}

@available(macOS 11.0, iOS 15.0, tvOS 16.0, *)
public struct MLTrainingSessionParameters: Sendable {
    public let sessionDirectory: URL?
    public var reportInterval: Int
    public var checkpointInterval: Int
    public var iterations: Int

    public init(sessionDirectory: URL? = nil, reportInterval: Int = 5, checkpointInterval: Int = 10, iterations: Int = 1000) {
        self.sessionDirectory = sessionDirectory
        self.reportInterval = reportInterval
        self.checkpointInterval = checkpointInterval
        self.iterations = iterations
    }
}

/// A training session's state, which it keeps in its directory.
struct SessionState: Codable {
    var date: Date
    var phase: MLPhase
    var iteration: Int
    var checkpoints: [MLCheckpoint]
}

@available(macOS 11.0, iOS 15.0, tvOS 16.0, *)
public final class MLTrainingSession<Task> {
    public final let parameters: MLTrainingSessionParameters
    private var state: SessionState
    private let lock = NSLock()

    init(parameters: MLTrainingSessionParameters) {
        self.parameters = parameters
        self.state = SessionState(date: Date(), phase: .initialized, iteration: 0, checkpoints: [])
    }

    /// The session in a directory, as it was saved there.
    init(restoring parameters: MLTrainingSessionParameters) throws {
        self.parameters = parameters
        guard let directory = parameters.sessionDirectory else {
            throw MLCreateError.generic(reason: "Restoring a training session needs its session directory.")
        }
        let file = directory.appendingPathComponent("session.json")
        guard let data = try? Data(contentsOf: file) else {
            throw MLCreateError.io(reason: "There is no training session in \(directory.path).")
        }
        self.state = try JSONDecoder().decode(SessionState.self, from: data)
    }

    private func save() throws {
        guard let directory = parameters.sessionDirectory else { return }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try JSONEncoder().encode(state).write(to: directory.appendingPathComponent("session.json"))
    }

    public final var date: Date { lock.withLock { state.date } }
    public final var phase: MLPhase { lock.withLock { state.phase } }
    public final var iteration: Int { lock.withLock { state.iteration } }
    public final var checkpoints: [MLCheckpoint] { lock.withLock { state.checkpoints } }

    /// Removes the checkpoints `predicate` picks, and their files.
    public final func removeCheckpoints(_ predicate: (MLCheckpoint) -> Bool) throws {
        let removed: [MLCheckpoint] = try lock.withLock {
            let removed = state.checkpoints.filter(predicate)
            state.checkpoints.removeAll(where: predicate)
            try save()
            return removed
        }
        for checkpoint in removed { try? FileManager.default.removeItem(at: checkpoint.url) }
    }

    /// Uses another session's extracted features: Perry's sessions never
    /// extract any, so there are none to reuse.
    public final func reuseExtractedFeatures(from session: MLTrainingSession<Task>) throws {
        guard session.checkpoints.contains(where: { $0.phase == .extractingFeatures }) else {
            throw MLCreateError.generic(reason: "The other session has no extracted features.")
        }
        lock.withLock { state.checkpoints += session.checkpoints.filter { $0.phase == .extractingFeatures } }
        try lock.withLock { try save() }
    }
}

extension MLTrainingSession: @unchecked Sendable {}

@available(macOS 11.0, iOS 15.0, tvOS 16.0, *)
public final class MLJob<Result>: Cancellable {
    public final let startDate: Date
    public final let progress: Progress
    private let checkpointSubject = PassthroughSubject<MLCheckpoint, Never>()
    private let resultSubject = PassthroughSubject<Result, any Error>()
    private let phaseSubject = CurrentValueSubject<MLPhase, Never>(.initialized)
    private let lock = NSLock()
    private var canceled = false

    /// A job that runs `work` on a background queue, publishing its result
    /// or error.
    init(_ work: @escaping (MLJob<Result>) throws -> Result) {
        startDate = Date()
        progress = Progress(totalUnitCount: 1)
        progress.setUserInfoObject(MLPhase.initialized.rawValue, forKey: MLProgress.phaseKey)
        // The publishers must have subscribers before a result arrives.
        DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + .milliseconds(10)) { [self] in
            do {
                let result = try work(self)
                resultSubject.send(result)
                resultSubject.send(completion: .finished)
            } catch {
                resultSubject.send(completion: .failure(error))
            }
            phaseSubject.send(completion: .finished)
            checkpointSubject.send(completion: .finished)
        }
    }

    /// A job that fails with an error.
    convenience init(failing error: any Error) {
        self.init { _ in throw error }
    }

    public final var isCanceled: Bool { lock.withLock { canceled } }

    public final var checkpoints: AnyPublisher<MLCheckpoint, Never> { checkpointSubject.eraseToAnyPublisher() }
    public final var result: AnyPublisher<Result, any Error> { resultSubject.eraseToAnyPublisher() }
    public final var phase: AnyPublisher<MLPhase, Never> { phaseSubject.eraseToAnyPublisher() }

    public final func cancel() {
        lock.withLock { canceled = true }
        progress.cancel()
    }
}

@available(*, unavailable)
extension MLJob: Sendable {}

/// A value a metric has; Apple's CreateML declares it for its own use.
@usableFromInline
protocol MLMetricValue: CustomStringConvertible {}

extension Int: MLMetricValue {}
extension Float: MLMetricValue {}
extension Double: MLMetricValue {}
extension URL: MLMetricValue {}

// Visualization: what show(_:) gives a playground. Perry's are text.

public protocol MLVisualizable: CustomPlaygroundDisplayConvertible {
    var cgImage: CGImage? { get }
}

public protocol MLStreamingVisualizable: MLVisualizable {
    mutating func nextIteration()
    var hasFinishedStreaming: Bool { get }
}

/// A visualization that shows text: CreateML draws plots, Perry's describe
/// the values.
struct TextVisualization: MLStreamingVisualizable {
    var text: String
    var cgImage: CGImage? { nil }
    var hasFinishedStreaming: Bool { true }
    mutating func nextIteration() {}
    var playgroundDescription: Any { text }
}

public func show(_ x: MLUntypedColumn, _ y: MLUntypedColumn) -> any MLStreamingVisualizable {
    TextVisualization(text: zip(x.values, y.values).map { "(\($0), \($1))" }.joined(separator: "\n"))
}

public func show<ElementX, ElementY>(_ x: MLDataColumn<ElementX>, _ y: MLDataColumn<ElementY>) -> any MLStreamingVisualizable
    where ElementX: MLDataValueConvertible, ElementY: MLDataValueConvertible {
    show(x._untypedColumn, y._untypedColumn)
}

public func show(_ column: MLUntypedColumn) -> any MLStreamingVisualizable {
    column.show()
}

public func show<Element>(_ column: MLDataColumn<Element>) -> any MLStreamingVisualizable where Element: MLDataValueConvertible {
    column.show()
}

public func show(_ table: MLDataTable) -> any MLStreamingVisualizable {
    table.show()
}
