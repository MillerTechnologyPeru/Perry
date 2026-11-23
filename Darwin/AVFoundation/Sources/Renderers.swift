import Foundation
import CoreMedia
import CoreVideo
import ObjectiveC

// Sample buffer renderers' Swift API: the expectation of upcoming
// presentation times, recommended pixel buffer attributes, and receivers
// that enqueue ready sample buffers (waiting for the renderer when
// asynchronous) and report the renderer's events as async sequences.

private var presentationTimeExpectationKey: UInt8 = 0

@available(macOS 14.4, iOS 17.4, tvOS 17.4, macCatalyst 17.4, visionOS 1.1, *)
@available(watchOS, unavailable)
extension AVSampleBufferVideoRenderer {
    public enum PresentationTimeExpectation: Sendable {
        case none
        case monotonicallyIncreasing
        case minimumUpcoming(CMTime)
    }

    /// What the renderer is told of upcoming presentation times; the
    /// renderer keeps no value to read, so the last one set is kept here.
    public var presentationTimeExpectation: AVSampleBufferVideoRenderer.PresentationTimeExpectation {
        @available(*, unavailable)
        get {
            (objc_getAssociatedObject(self, &presentationTimeExpectationKey) as? _AVBox<PresentationTimeExpectation>)?.value ?? .none
        }
        set {
            objc_setAssociatedObject(self, &presentationTimeExpectationKey, _AVBox(newValue), .OBJC_ASSOCIATION_RETAIN)
            switch newValue {
            case .none: __resetUpcomingSampleBufferPresentationTimeExpectations()
            case .monotonicallyIncreasing: __expectMonotonicallyIncreasingUpcomingSampleBufferPresentationTimes()
            case let .minimumUpcoming(time): __expectMinimumUpcomingSampleBufferPresentationTime(time)
            }
        }
    }

    @available(macOS 26.0, iOS 26.0, tvOS 26.0, visionOS 26.0, *)
    @available(watchOS, unavailable)
    public var recommendedPixelBufferAttributes: CVPixelBufferAttributes {
        CVPixelBufferAttributes(rawAttributes: __recommendedPixelBufferAttributes.mapValues(sendablePropertyList))
    }
}

/// A value kept as an Objective-C object.
final class _AVBox<Value>: NSObject {
    let value: Value

    init(_ value: Value) {
        self.value = value
    }
}

/// Waits until a renderer is ready for more media data.
private func waitUntilReady(_ isReady: () -> Bool) async throws {
    while !isReady() {
        try Task.checkCancellation()
        try await Task.sleep(nanoseconds: 2_000_000)
    }
}

/// Notifications a renderer posts, observed while a receiver lives, into a
/// stream of events.
final class _AVNotificationObservations: @unchecked Sendable {
    var tokens: [any NSObjectProtocol] = []

    func observe(_ name: Notification.Name, of object: AnyObject, using block: @escaping @Sendable (Notification) -> Void) {
        tokens.append(NotificationCenter.default.addObserver(forName: name, object: object, queue: nil, using: block))
    }

    deinit {
        tokens.forEach(NotificationCenter.default.removeObserver)
    }
}

@available(macOS 27, iOS 27, tvOS 27, visionOS 27, *)
@available(watchOS, unavailable)
extension AVSampleBufferVideoRenderer {
    @_hasMissingDesignatedInitializers
    public class Receiver {
        let renderer: AVSampleBufferVideoRenderer
        private let observations = _AVNotificationObservations()
        private let lock = NSLock()
        private var decodeFailures: [any Error] = []
        private var events: AsyncStream<RenderingEvent>.Continuation?
        private lazy var eventStream: AsyncStream<RenderingEvent> = {
            let (stream, continuation) = AsyncStream<RenderingEvent>.makeStream()
            events = continuation
            return stream
        }()

        init(renderer: AVSampleBufferVideoRenderer) {
            self.renderer = renderer
            observations.observe(AVSampleBufferVideoRenderer.didFailToDecodeNotification, of: renderer) { [weak self] notification in
                let error = notification.userInfo?[AVSampleBufferVideoRenderer.didFailToDecodeNotificationErrorKey] as? NSError
                    ?? NSError(domain: AVFoundationErrorDomain, code: AVError.Code.decodeFailed.rawValue)
                self?.record(decodeFailure: error)
            }
            observations.observe(AVSampleBufferVideoRenderer.requiresFlushToResumeDecodingDidChangeNotification, of: renderer) { [weak self] _ in
                guard let self, self.renderer.requiresFlushToResumeDecoding else { return }
                self.lock.lock(); let events = self.events; self.lock.unlock()
                events?.yield(.requiresFlushToResumeDecoding(self.renderer.error ?? NSError(domain: AVFoundationErrorDomain, code: AVError.Code.decodeFailed.rawValue)))
            }
        }

        deinit {
            events?.finish()
        }

        private func record(decodeFailure error: any Error) {
            lock.lock()
            decodeFailures.append(error)
            let events = self.events
            lock.unlock()
            events?.yield(.didFailToDecode([error]))
        }

        /// The source of the legacy case of the enqueue result, whose error
        /// was optional.
        @_silgen_name("$sSo27AVSampleBufferVideoRendererC12AVFoundationE8ReceiverC13EnqueueResultO027cancelledDueToFlushRequiredK6ResumeyAGs5Error_pSgcAGmFWC")
        @usableFromInline
        static func __abi_only_cancelledDueToFlushRequiredToResume_legacy(_ error: (any Error)?) -> AVSampleBufferVideoRenderer.Receiver.EnqueueResult {
            .cancelledDueToFlushRequiredToResume(error ?? NSError(domain: AVFoundationErrorDomain, code: AVError.Code.decodeFailed.rawValue))
        }

        public enum EnqueueResult: Sendable {
            case enqueued
            case enqueuedWithDecodeFailures([any Error])
            case cancelledDueToFlush
            case cancelledDueToFlushRequiredToResume(any Error)
            case cancelledDueToError(any Error)
        }

        nonisolated(nonsending) public func enqueue(_ sampleBuffer: CMReadySampleBuffer<CMSampleBuffer.DynamicContent>) async throws -> AVSampleBufferVideoRenderer.Receiver.EnqueueResult {
            let renderer = self.renderer
            try await waitUntilReady { renderer.isReadyForMoreMediaData || renderer.status == .failed || renderer.requiresFlushToResumeDecoding }
            return enqueueImmediately(sampleBuffer)
        }

        public func enqueueImmediately(_ sampleBuffer: CMReadySampleBuffer<CMSampleBuffer.DynamicContent>) -> AVSampleBufferVideoRenderer.Receiver.EnqueueResult {
            if renderer.status == .failed {
                return .cancelledDueToError(renderer.error ?? NSError(domain: AVFoundationErrorDomain, code: AVError.Code.unknown.rawValue))
            }
            if renderer.requiresFlushToResumeDecoding {
                return .cancelledDueToFlushRequiredToResume(renderer.error ?? NSError(domain: AVFoundationErrorDomain, code: AVError.Code.decodeFailed.rawValue))
            }
            sampleBuffer.withUnsafeSampleBuffer { renderer.enqueue($0) }
            lock.lock()
            let failures = decodeFailures
            decodeFailures = []
            lock.unlock()
            return failures.isEmpty ? .enqueued : .enqueuedWithDecodeFailures(failures)
        }

        public func flush() {
            renderer.flush()
        }

        nonisolated(nonsending) public func flush(removingDisplayedImage removeDisplayedImage: Bool) async {
            let renderer = _AVUnsafeSendable(value: self.renderer)
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                renderer.value.flush(removingDisplayedImage: removeDisplayedImage) { continuation.resume() }
            }
        }

        public enum RenderingEvent: Sendable {
            case didFailToDecode([any Error])
            case requiresFlushToResumeDecoding(any Error)
            case failed(any Error)
        }

        /// The renderer's events from now on, until the receiver goes away.
        public var renderingEventsAfterFinishedEnqueuing: some Sendable & AsyncSequence<AVSampleBufferVideoRenderer.Receiver.RenderingEvent, Never> {
            lock.lock(); defer { lock.unlock() }
            return eventStream
        }
    }
}

@available(macOS 27, iOS 27, tvOS 27, visionOS 27, *)
@available(watchOS, unavailable)
extension AVSampleBufferRenderSynchronizer {
    public func sampleBufferReceiver(adding renderer: AVSampleBufferVideoRenderer) -> sending AVSampleBufferVideoRenderer.Receiver {
        addRenderer(renderer)
        return AVSampleBufferVideoRenderer.Receiver(renderer: renderer)
    }

    public func removeReceiver(_ receiver: sending AVSampleBufferVideoRenderer.Receiver, at time: CMTime) async -> Bool {
        let renderer = _AVUnsafeSendable(value: receiver.renderer)
        return await withCheckedContinuation { continuation in
            removeRenderer(renderer.value, at: time) { continuation.resume(returning: $0) }
        }
    }
}

@available(macOS 27, iOS 27, tvOS 27, watchOS 27, visionOS 27, *)
extension AVSampleBufferRenderSynchronizer {
    public func sampleBufferReceiver(adding renderer: AVSampleBufferAudioRenderer) -> sending AVSampleBufferAudioRenderer.Receiver {
        addRenderer(renderer)
        return AVSampleBufferAudioRenderer.Receiver(renderer: renderer)
    }

    public func removeReceiver(_ receiver: sending AVSampleBufferAudioRenderer.Receiver, at time: CMTime) async -> Bool {
        let renderer = _AVUnsafeSendable(value: receiver.renderer)
        return await withCheckedContinuation { continuation in
            removeRenderer(renderer.value, at: time) { continuation.resume(returning: $0) }
        }
    }
}

@available(macOS 27, iOS 27, tvOS 27, watchOS 27, visionOS 27, *)
extension AVSampleBufferAudioRenderer {
    @_hasMissingDesignatedInitializers
    public class Receiver {
        let renderer: AVSampleBufferAudioRenderer
        private let observations = _AVNotificationObservations()
        private let lock = NSLock()
        private var suggestedFlushes: [SuggestedFlushReason] = []
        private var events: AsyncStream<RenderingEvent>.Continuation?
        private lazy var eventStream: AsyncStream<RenderingEvent> = {
            let (stream, continuation) = AsyncStream<RenderingEvent>.makeStream()
            events = continuation
            return stream
        }()

        init(renderer: AVSampleBufferAudioRenderer) {
            self.renderer = renderer
            observations.observe(.AVSampleBufferAudioRendererWasFlushedAutomatically, of: renderer) { [weak self] notification in
                let time = (notification.userInfo?[AVSampleBufferAudioRendererFlushTimeKey] as? NSValue)?.timeValue ?? .invalid
                self?.record(.wasFlushedAutomatically(at: time), event: .wasFlushedAutomatically(at: time))
            }
            observations.observe(.AVSampleBufferAudioRendererOutputConfigurationDidChange, of: renderer) { [weak self] _ in
                self?.record(.outputConfigurationChanged, event: .outputConfigurationChanged)
            }
        }

        deinit {
            events?.finish()
        }

        private func record(_ reason: SuggestedFlushReason, event: RenderingEvent) {
            lock.lock()
            suggestedFlushes.append(reason)
            let events = self.events
            lock.unlock()
            events?.yield(event)
        }

        public enum SuggestedFlushReason: Sendable {
            case wasFlushedAutomatically(at: CMTime)
            case outputConfigurationChanged
        }

        public enum EnqueueResult: Sendable {
            case enqueued
            case enqueuedWithSuggestedFlush([AVSampleBufferAudioRenderer.Receiver.SuggestedFlushReason])
            case cancelledDueToFlush
            case cancelledDueToError(any Error)
        }

        nonisolated(nonsending) public func enqueue(_ sampleBuffer: CMReadySampleBuffer<CMSampleBuffer.DynamicContent>) async throws -> AVSampleBufferAudioRenderer.Receiver.EnqueueResult {
            let renderer = self.renderer
            try await waitUntilReady { renderer.isReadyForMoreMediaData || renderer.status == .failed }
            return enqueueImmediately(sampleBuffer)
        }

        public func enqueueImmediately(_ sampleBuffer: CMReadySampleBuffer<CMSampleBuffer.DynamicContent>) -> AVSampleBufferAudioRenderer.Receiver.EnqueueResult {
            if renderer.status == .failed {
                return .cancelledDueToError(renderer.error ?? NSError(domain: AVFoundationErrorDomain, code: AVError.Code.unknown.rawValue))
            }
            sampleBuffer.withUnsafeSampleBuffer { renderer.enqueue($0) }
            lock.lock()
            let flushes = suggestedFlushes
            suggestedFlushes = []
            lock.unlock()
            return flushes.isEmpty ? .enqueued : .enqueuedWithSuggestedFlush(flushes)
        }

        public func flush() {
            renderer.flush()
        }

        nonisolated(nonsending) public func flush(fromSourceTime sourceTime: CMTime) async -> Bool {
            let renderer = _AVUnsafeSendable(value: self.renderer)
            return await withCheckedContinuation { continuation in
                renderer.value.flush(fromSourceTime: sourceTime) { continuation.resume(returning: $0) }
            }
        }

        public enum RenderingEvent: Sendable {
            case wasFlushedAutomatically(at: CMTime)
            case outputConfigurationChanged
            case failed(any Error)
        }

        /// The renderer's events from now on, until the receiver goes away.
        public var renderingEventsAfterFinishedEnqueuing: some Sendable & AsyncSequence<AVSampleBufferAudioRenderer.Receiver.RenderingEvent, Never> {
            lock.lock(); defer { lock.unlock() }
            return eventStream
        }
    }
}
