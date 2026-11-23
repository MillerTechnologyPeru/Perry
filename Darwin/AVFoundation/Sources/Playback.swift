import Foundation
import CoreMedia
import CoreVideo
import CoreGraphics
import ObjectiveC

// Playback and generation as async sequences and Swift values: the
// integrated timeline's times, image generation, export states, sample
// buffer and video outputs, metrics, and the sample buffer renderers'
// receivers.

// MARK: - Integrated timeline

@available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2.0, *)
extension AVPlayerItemIntegratedTimelineSnapshot {
    public func segmentAndOffsetIntoSegment(forTimelineTime: CMTime) -> (AVPlayerItemSegment, CMTime) {
        var offset = CMTime.invalid
        // The out-segment starts as the first, which mapping replaces.
        var segment: AVPlayerItemSegment = segments.first ?? currentSegment!
        __mapTime(forTimelineTime, to: &segment, atSegmentOffset: &offset)
        return (segment, offset)
    }
}

/// A timeline's time observer, removed when the iteration that added it ends.
@available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2.0, *)
final class TimelineObservation: @unchecked Sendable {
    let timeline: AVPlayerItemIntegratedTimeline
    var observer: (any AVPlayerItemIntegratedTimelineObserver)?
    var iterator: AsyncStream<CMTime>.Iterator

    init(timeline: AVPlayerItemIntegratedTimeline, add: (AVPlayerItemIntegratedTimeline, AsyncStream<CMTime>.Continuation) -> any AVPlayerItemIntegratedTimelineObserver) {
        self.timeline = timeline
        let (stream, continuation) = AsyncStream<CMTime>.makeStream()
        iterator = stream.makeAsyncIterator()
        observer = add(timeline, continuation)
    }

    deinit {
        if let observer { timeline.__removeTime(observer) }
    }
}

@available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2.0, *)
extension AVPlayerItemIntegratedTimeline {
    public struct PeriodicTimes: AsyncSequence, Sendable {
        public typealias Element = CMTime

        let timeline: _AVUnsafeSendable<AVPlayerItemIntegratedTimeline>
        let interval: CMTime

        public func makeAsyncIterator() -> AVPlayerItemIntegratedTimeline.PeriodicTimes.Iterator {
            let interval = interval
            return Iterator(observation: TimelineObservation(timeline: timeline.value) { timeline, continuation in
                timeline.__addPeriodicTimeObserver(forInterval: interval, queue: nil) { continuation.yield($0) }
            })
        }

        public struct Iterator: AsyncIteratorProtocol {
            let observation: TimelineObservation

            public mutating func next() async -> AVPlayerItemIntegratedTimeline.PeriodicTimes.Element? {
                await observation.iterator.next()
            }

            public typealias Element = AVPlayerItemIntegratedTimeline.PeriodicTimes.Element
        }

        public typealias AsyncIterator = AVPlayerItemIntegratedTimeline.PeriodicTimes.Iterator
    }

    public struct BoundaryTimes: AsyncSequence, Sendable {
        public typealias Element = CMTime

        let timeline: _AVUnsafeSendable<AVPlayerItemIntegratedTimeline>
        let segment: _AVUnsafeSendable<AVPlayerItemSegment>
        let offsets: [CMTime]

        public func makeAsyncIterator() -> AVPlayerItemIntegratedTimeline.BoundaryTimes.Iterator {
            let segment = segment.value, offsets = offsets
            return Iterator(observation: TimelineObservation(timeline: timeline.value) { timeline, continuation in
                let snapshotTimeline = timeline
                return timeline.__addBoundaryTimeObserver(for: segment, offsetsIntoSegment: offsets.map { NSValue(time: $0) }, queue: nil) { _ in
                    continuation.yield(snapshotTimeline.currentTime)
                }
            })
        }

        public struct Iterator: AsyncIteratorProtocol {
            let observation: TimelineObservation

            public mutating func next() async -> AVPlayerItemIntegratedTimeline.BoundaryTimes.Element? {
                await observation.iterator.next()
            }

            public typealias Element = AVPlayerItemIntegratedTimeline.BoundaryTimes.Element
        }

        public typealias AsyncIterator = AVPlayerItemIntegratedTimeline.BoundaryTimes.Iterator
    }

    public func periodicTimes(forInterval: CMTime) -> AVPlayerItemIntegratedTimeline.PeriodicTimes {
        PeriodicTimes(timeline: _AVUnsafeSendable(value: self), interval: forInterval)
    }

    public func boundaryTimes(for segment: AVPlayerItemSegment, offsetsIntoSegment: [CMTime]) -> AVPlayerItemIntegratedTimeline.BoundaryTimes {
        BoundaryTimes(timeline: _AVUnsafeSendable(value: self), segment: _AVUnsafeSendable(value: segment), offsets: offsetsIntoSegment)
    }
}

// MARK: - Image generation

@available(macOS 13, iOS 16, tvOS 16, visionOS 1, *)
@available(watchOS, unavailable)
extension AVAssetImageGenerator {
    public func image(at time: CMTime) async throws -> (image: CGImage, actualTime: CMTime) {
        try await withCheckedThrowingContinuation { continuation in
            generateCGImageAsynchronously(for: time) { image, actualTime, error in
                if let image {
                    continuation.resume(returning: (image, actualTime))
                } else {
                    continuation.resume(throwing: error ?? NSError(domain: AVFoundationErrorDomain, code: AVError.Code.unknown.rawValue))
                }
            }
        }
    }

    public func images(for times: [CMTime]) -> sending AVAssetImageGenerator.Images {
        Images(generator: _AVUnsafeSendable(value: self), times: times)
    }

    /// The images of the times, generated one after another.
    public struct Images: AsyncSequence, AsyncIteratorProtocol {
        @frozen public enum Element: Sendable {
            case success(requestedTime: CMTime, image: CGImage, actualTime: CMTime)
            case failure(requestedTime: CMTime, error: any Error)
        }

        let generator: _AVUnsafeSendable<AVAssetImageGenerator>
        var times: [CMTime]
        var index = 0

        init(generator: _AVUnsafeSendable<AVAssetImageGenerator>, times: [CMTime]) {
            self.generator = generator
            self.times = times
        }

        public func makeAsyncIterator() -> AVAssetImageGenerator.Images { self }

        public mutating func next() async -> AVAssetImageGenerator.Images.Element? {
            guard index < times.count, !Task.isCancelled else { return nil }
            let time = times[index]
            index += 1
            do {
                let (image, actualTime) = try await generator.value.image(at: time)
                return .success(requestedTime: time, image: image, actualTime: actualTime)
            } catch {
                return .failure(requestedTime: time, error: error)
            }
        }

        public typealias AsyncIterator = AVAssetImageGenerator.Images
    }
}

@available(macOS 13, iOS 16, tvOS 16, visionOS 1, *)
@available(watchOS, unavailable)
extension AVAssetImageGenerator.Images.Element {
    public var requestedTime: CMTime {
        switch self {
        case let .success(time, _, _): return time
        case let .failure(time, _): return time
        }
    }

    public var image: CGImage {
        get throws {
            switch self {
            case let .success(_, image, _): return image
            case let .failure(_, error): throw error
            }
        }
    }

    public var actualTime: CMTime {
        get throws {
            switch self {
            case let .success(_, _, time): return time
            case let .failure(_, error): throw error
            }
        }
    }
}

// MARK: - Export

@available(macOS 15, iOS 18, tvOS 18, visionOS 2, *)
@available(watchOS, unavailable)
extension AVAssetExportSession {
    public final func export(to url: URL, as fileType: AVFileType, isolation: isolated (any Actor)? = #isolation) async throws {
        let session = _AVUnsafeSendable(value: self)
        outputURL = url
        outputFileType = fileType
        try await withTaskCancellationHandler {
            guard session.value.status != .cancelled else { throw CancellationError() }
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                session.value.exportAsynchronously { continuation.resume() }
            }
            switch session.value.status {
            case .completed:
                return
            case .cancelled:
                throw CancellationError()
            default:
                throw session.value.error ?? NSError(domain: AVFoundationErrorDomain, code: AVError.Code.unknown.rawValue)
            }
        } onCancel: {
            session.value.cancelExport()
        }
    }

    public enum State: Sendable {
        case pending
        case waiting
        case exporting(progress: Progress)
    }

    /// The session's state each update interval while it changes, until the
    /// export ends; an infinite interval reports each change of status.
    public func states(updateInterval: TimeInterval = .infinity) -> some Sendable & AsyncSequence<AVAssetExportSession.State, Never> {
        let session = _AVUnsafeSendable(value: self)
        let interval = updateInterval.isFinite && updateInterval > 0 ? updateInterval : 0.1
        return AsyncStream<AVAssetExportSession.State> { continuation in
            let task = Task {
                let progress = Progress(totalUnitCount: 100)
                var last: Int?
                while !Task.isCancelled {
                    let status = session.value.status
                    switch status {
                    case .unknown:
                        if last != 0 || updateInterval.isFinite { continuation.yield(.pending) }
                    case .waiting:
                        if last != 1 || updateInterval.isFinite { continuation.yield(.waiting) }
                    case .exporting:
                        progress.completedUnitCount = Int64(session.value.progress * 100)
                        continuation.yield(.exporting(progress: progress))
                    default:
                        continuation.finish()
                        return
                    }
                    last = status.rawValue
                    try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}

@available(macOS 27.0, iOS 27.0, tvOS 27.0, visionOS 27.0, *)
@available(watchOS, unavailable)
extension AVAssetExportSession {
    public enum ResumptionState: Sendable {
        case resumable(isResumingFromPreviousState: Bool)
        case notResumable(failureReason: AVAssetExportSession.ResumptionFailureReason)
    }

    public func configureForResumableExport() async -> AVAssetExportSession.ResumptionState {
        await withCheckedContinuation { continuation in
            __configureForResumableExport { state in
                if state.isResumptionConfigured {
                    continuation.resume(returning: .resumable(isResumingFromPreviousState: state.isResumingFromPreviousState))
                } else {
                    continuation.resume(returning: .notResumable(failureReason: state.configurationFailureReason ?? AVAssetExportSession.ResumptionFailureReason(rawValue: "")))
                }
            }
        }
    }
}

// MARK: - Outputs

@available(macOS 27.0, iOS 27.0, tvOS 27.0, watchOS 27.0, visionOS 27.0, *)
extension AVPlayerItemSampleBufferOutput {
    public struct SampleBufferInSequence: Sendable {
        public var sampleBuffer: CMReadySampleBuffer<CMSampleBuffer.DynamicContent>
        public var sequenceWasRestarted: Bool

        public init(sampleBuffer: CMReadySampleBuffer<CMSampleBuffer.DynamicContent>, sequenceWasRestarted: Bool) {
            self.sampleBuffer = sampleBuffer
            self.sequenceWasRestarted = sequenceWasRestarted
        }
    }

    /// The output's delegate, which counts restarts of the sequence and
    /// wakes a waiting nextSampleBuffer().
    final class Watcher: NSObject, __AVPlayerItemSampleBufferOutputDelegate, @unchecked Sendable {
        let lock = NSLock()
        var restarted = false
        var waiters: [CheckedContinuation<Void, Never>] = []

        func outputMediaDataAvailable(_ output: AVPlayerItemSampleBufferOutput) { wake() }

        func outputSequenceWasRestarted(_ output: AVPlayerItemSampleBufferOutput) {
            lock.lock(); restarted = true; lock.unlock()
            wake()
        }

        func wake() {
            lock.lock()
            let waiting = waiters
            waiters = []
            lock.unlock()
            waiting.forEach { $0.resume() }
        }

        func takeRestarted() -> Bool {
            lock.lock(); defer { lock.unlock() }
            let value = restarted
            restarted = false
            return value
        }
    }

    private static var watcherKey: UInt8 = 0

    /// The output's watcher, set as its delegate the first time.
    var watcher: Watcher {
        if let watcher = objc_getAssociatedObject(self, &Self.watcherKey) as? Watcher { return watcher }
        let watcher = Watcher()
        objc_setAssociatedObject(self, &Self.watcherKey, watcher, .OBJC_ASSOCIATION_RETAIN)
        __setDelegate(watcher, queue: DispatchQueue(label: "AVPlayerItemSampleBufferOutput"))
        return watcher
    }

    public func nextAvailableSampleBuffer() -> AVPlayerItemSampleBufferOutput.SampleBufferInSequence? {
        let watcher = self.watcher
        guard let buffer = __copyNextSampleBuffer() else { return nil }
        return SampleBufferInSequence(sampleBuffer: CMReadySampleBuffer(unsafeBuffer: buffer), sequenceWasRestarted: watcher.takeRestarted())
    }

    nonisolated public func nextSampleBuffer() async -> AVPlayerItemSampleBufferOutput.SampleBufferInSequence? {
        let watcher = self.watcher
        while !Task.isCancelled {
            if let next = nextAvailableSampleBuffer() { return next }
            await withCheckedContinuation { continuation in
                watcher.lock.lock()
                watcher.waiters.append(continuation)
                watcher.lock.unlock()
                // Media may have arrived before the waiter was added.
                DispatchQueue.global().asyncAfter(deadline: .now() + 0.05) { watcher.wake() }
            }
        }
        return nil
    }
}

@available(macOS 14.2, iOS 17.2, tvOS 17.2, watchOS 10.2, visionOS 1.1, *)
extension AVPlayerVideoOutput {
    public func taggedBuffers(forHostTime hostTime: CMTime) -> (taggedBufferGroup: [CMTaggedBuffer], presentationTime: CMTime, activeConfiguration: AVPlayerVideoOutput.Configuration)? {
        var presentationTime = CMTime.invalid
        var configuration: AVPlayerVideoOutput.Configuration?
        guard let group = __copyTaggedBufferGroup(forHostTime: hostTime, presentationTimeStamp: &presentationTime, activeConfiguration: &configuration),
              let configuration else { return nil }
        return (AVFoundation.taggedBuffers(of: group), presentationTime, configuration)
    }

    @available(macOS 26.0, iOS 26.0, tvOS 26.0, watchOS 26.0, visionOS 26.0, *)
    public struct Sample: Sendable {
        public let taggedBuffers: [CMTaggedDynamicBuffer]
        public let presentationTime: CMTime
        public let activeConfiguration: AVPlayerVideoOutput.Configuration
    }

    @available(macOS 26.0, iOS 26.0, tvOS 26.0, watchOS 26.0, visionOS 26.0, *)
    public func sample(forHostTime hostTime: CMTime) -> AVPlayerVideoOutput.Sample? {
        var presentationTime = CMTime.invalid
        var configuration: AVPlayerVideoOutput.Configuration?
        guard let group = __copyTaggedBufferGroup(forHostTime: hostTime, presentationTimeStamp: &presentationTime, activeConfiguration: &configuration),
              let configuration else { return nil }
        return Sample(taggedBuffers: taggedDynamicBuffers(of: group), presentationTime: presentationTime, activeConfiguration: configuration)
    }
}

@available(macOS 14.2, iOS 17.2, tvOS 17.2, watchOS 10.2, visionOS 1.1, *)
extension AVVideoOutputSpecification {
    public convenience init(tagCollections: [[CMTag]]) {
        self.init(__tagCollections: AVFoundation.tagCollections(tagCollections))
    }

    public func setOutputPixelBufferAttributes(_ pixelBufferAttributes: [String: Any]?, for tagCollection: [CMTag]) {
        guard let collection = AVFoundation.tagCollection(tagCollection) else { return }
        __setOutputPixelBufferAttributes(pixelBufferAttributes, for: collection)
    }

    @available(macOS 15.0, iOS 18.0, visionOS 2.0, *)
    public func setOutputSettings(_ outputSettings: [String: any Sendable]?, for tagCollection: [CMTag]) {
        guard let collection = AVFoundation.tagCollection(tagCollection) else { return }
        __setOutputSettings(outputSettings, for: collection)
    }

    public var preferredTagCollections: [[CMTag]] {
        tagArrays(__preferredTagCollections)
    }
}

@available(macOS 14.2, iOS 17.2, tvOS 17.2, watchOS 10.2, visionOS 1.1, *)
extension AVPlayerVideoOutput.Configuration {
    public var dataChannelDescription: [[CMTag]] {
        tagArrays(__dataChannelDescriptions)
    }
}

@available(macOS 26.0, iOS 26.0, tvOS 26.0, watchOS 26.0, visionOS 26.0, *)
extension CMReadySampleBuffer {
    public mutating func attach(contentKey: AVContentKey) throws {
        var error: NSError?
        let attached = withUnsafeSampleBuffer { AVSampleBufferAttachContentKey($0, contentKey, &error) }
        if !attached {
            throw error ?? NSError(domain: AVFoundationErrorDomain, code: AVError.Code.unknown.rawValue)
        }
    }
}

@available(macOS 10.13, iOS 11.0, macCatalyst 14.0, tvOS 11.0, visionOS 1.0, *)
@available(watchOS, unavailable)
extension AVDepthData {
    @nonobjc public var availableDepthDataTypes: [OSType] {
        __availableDepthDataTypes.map { $0.uint32Value }
    }
}

// MARK: - Metrics

@available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
extension AVMetricEventStreamPublisher {
    public func metrics<MetricEvent>(forType metricType: MetricEvent.Type) -> AVMetrics<MetricEvent> where MetricEvent: AVMetricEvent {
        AVMetrics(publisher: self, types: [metricType])
    }

    public func allMetrics() -> AVMetrics<AVMetricEvent> {
        AVMetrics(publisher: self, types: nil)
    }
}

/// A metric event stream's subscriber, which hands each event and its
/// publisher to a continuation.
@available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
final class MetricSubscriber: NSObject, __AVMetricEventStreamSubscriber, @unchecked Sendable {
    let stream = __AVMetricEventStream()
    let events: AsyncStream<(AVMetricEvent, any AVMetricEventStreamPublisher)>
    let continuation: AsyncStream<(AVMetricEvent, any AVMetricEventStreamPublisher)>.Continuation

    init(publishers: [(any AVMetricEventStreamPublisher, [AnyClass]?)]) {
        (events, continuation) = AsyncStream.makeStream()
        super.init()
        for (publisher, types) in publishers {
            _ = stream.add(publisher)
            if let types {
                stream.subscribe(toMetricEvents: types)
            } else {
                stream.subscribeToAllMetricEvents()
            }
        }
        _ = stream.setSubscriber(self, queue: DispatchQueue(label: "AVMetrics"))
    }

    func publisher(_ publisher: any AVMetricEventStreamPublisher, didReceive event: AVMetricEvent) {
        continuation.yield((event, publisher))
    }
}

@available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
public struct AVMetrics<MetricEvent>: AsyncSequence, @unchecked Sendable where MetricEvent: AVMetricEvent {
    let publisher: any AVMetricEventStreamPublisher
    let types: [AnyClass]?

    init(publisher: any AVMetricEventStreamPublisher, types: [AnyClass]?) {
        self.publisher = publisher
        self.types = types
    }

    public func makeAsyncIterator() -> AVMetrics<MetricEvent>.AsyncIterator {
        AsyncIterator(subscriber: MetricSubscriber(publishers: [(publisher, types)]))
    }

    public typealias Element = MetricEvent

    public struct AsyncIterator: AsyncIteratorProtocol {
        let subscriber: MetricSubscriber
        var iterator: AsyncStream<(AVMetricEvent, any AVMetricEventStreamPublisher)>.Iterator

        init(subscriber: MetricSubscriber) {
            self.subscriber = subscriber
            iterator = subscriber.events.makeAsyncIterator()
        }

        public mutating func next() async throws -> MetricEvent? {
            while let (event, _) = await iterator.next() {
                if let event = event as? MetricEvent { return event }
            }
            return nil
        }

        public typealias Element = MetricEvent
    }

    public func chronologicalMerge<OtherSecondMetric, each MetricEventPack>(with secondMetric: AVMetrics<OtherSecondMetric>, _ metrics: repeat AVMetrics<each MetricEventPack>) -> AVMergedMetrics<MetricEvent, OtherSecondMetric, repeat each MetricEventPack> where OtherSecondMetric: AVMetricEvent, repeat each MetricEventPack: AVMetricEvent {
        var sources: [(any AVMetricEventStreamPublisher, [AnyClass]?)] = [(publisher, types), (secondMetric.publisher, secondMetric.types)]
        for metric in repeat each metrics {
            sources.append((metric.publisher, metric.types))
        }
        return AVMergedMetrics(sources: _AVUnsafeSendable(value: sources))
    }
}

@available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
public struct AVMergedMetrics<MetricEvent1, MetricEvent2, each MetricEventPack>: AsyncSequence where MetricEvent1: AVMetricEvent, MetricEvent2: AVMetricEvent, repeat each MetricEventPack: AVMetricEvent {
    let sources: _AVUnsafeSendable<[(any AVMetricEventStreamPublisher, [AnyClass]?)]>

    public func makeAsyncIterator() -> AVMergedMetrics<MetricEvent1, MetricEvent2, repeat each MetricEventPack>.AsyncIterator {
        AsyncIterator(subscriber: MetricSubscriber(publishers: sources.value))
    }

    public typealias Element = (AVMetricEvent, any AVMetricEventStreamPublisher)

    /// The events of all the sources, in the order one stream delivers them.
    public struct AsyncIterator: AsyncIteratorProtocol {
        let subscriber: MetricSubscriber
        var iterator: AsyncStream<(AVMetricEvent, any AVMetricEventStreamPublisher)>.Iterator

        init(subscriber: MetricSubscriber) {
            self.subscriber = subscriber
            iterator = subscriber.events.makeAsyncIterator()
        }

        public mutating func next() async throws -> (AVMetricEvent, any AVMetricEventStreamPublisher)? {
            await iterator.next()
        }

        public typealias Element = (AVMetricEvent, any AVMetricEventStreamPublisher)
    }
}
