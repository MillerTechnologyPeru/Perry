import Foundation
import CoreMedia
import CoreVideo

// Asset writing and reading with Swift values: receivers that append
// ready sample buffers, pixel buffers, tagged buffers, metadata and
// captions to a writer input (waiting for it when asynchronous), the
// multi-pass controller, and providers that read an output's payloads.

/// The error of a writer that failed, or a generic one.
private func writerError(_ writer: AVAssetWriter?) -> any Error {
    writer?.error ?? NSError(domain: AVFoundationErrorDomain, code: AVError.Code.unknown.rawValue)
}

/// Waits until the input is ready for more media data, or its writer is
/// done with writing.
private func waitUntilReady(_ input: AVAssetWriterInput, writer: AVAssetWriter?) async throws {
    while !input.isReadyForMoreMediaData {
        if let writer, writer.status == .failed || writer.status == .cancelled || writer.status == .completed {
            throw writerError(writer)
        }
        try Task.checkCancellation()
        try await Task.sleep(nanoseconds: 2_000_000)
    }
}

/// Appends with a function that answers whether it did, throwing the
/// writer's error when it didn't.
private func appended(_ success: Bool, writer: AVAssetWriter?) throws -> Bool {
    if !success, let writer, writer.status == .failed {
        throw writerError(writer)
    }
    return success
}

@available(macOS 26.0, iOS 26.0, tvOS 26.0, visionOS 26.0, *)
@available(watchOS, unavailable)
extension AVAssetWriterInput {
    @_hasMissingDesignatedInitializers
    public class SampleBufferReceiver {
        let input: AVAssetWriterInput
        weak var writer: AVAssetWriter?

        init(input: AVAssetWriterInput, writer: AVAssetWriter) {
            self.input = input
            self.writer = writer
        }

        nonisolated(nonsending) public func append(_ sampleBuffer: CMReadySampleBuffer<CMSampleBuffer.DynamicContent>) async throws {
            try await waitUntilReady(input, writer: writer)
            guard try appendImmediately(sampleBuffer) else { throw writerError(writer) }
        }

        public func appendImmediately(_ sampleBuffer: CMReadySampleBuffer<CMSampleBuffer.DynamicContent>) throws -> Bool {
            guard input.isReadyForMoreMediaData else { return false }
            return try appended(sampleBuffer.withUnsafeSampleBuffer { input.append($0) }, writer: writer)
        }

        public func finish() {
            input.markAsFinished()
        }
    }

    @_hasMissingDesignatedInitializers
    public class MultiPassController {
        let input: AVAssetWriterInput

        init(input: AVAssetWriterInput) {
            self.input = input
            input.performsMultiPassEncodingIfSupported = true
        }

        /// The description of each pass the input asks for, nil when it
        /// can't encode in multiple passes; the sequence ends after the
        /// last pass.
        public var passDescriptions: (some AsyncSequence<AVAssetWriterInputPassDescription, Never>)? {
            guard input.canPerformMultiplePasses else { return Optional<AsyncStream<AVAssetWriterInputPassDescription>>.none }
            let (stream, continuation) = AsyncStream<AVAssetWriterInputPassDescription>.makeStream()
            let input = _AVUnsafeSendable(value: input)
            input.value.respondToEachPassDescription(on: DispatchQueue(label: "AVAssetWriterInput.MultiPassController")) {
                if let pass = input.value.currentPassDescription {
                    continuation.yield(pass)
                } else {
                    continuation.finish()
                }
            }
            return stream
        }
    }
}

@available(macOS 26.0, iOS 26.0, tvOS 26.0, visionOS 26.0, *)
@available(watchOS, unavailable)
extension AVAssetWriter {
    public func inputReceiver(for input: AVAssetWriterInput) -> sending AVAssetWriterInput.SampleBufferReceiver {
        AVAssetWriterInput.SampleBufferReceiver(input: input, writer: self)
    }

    public func inputReceiverRequestingMultiPass(for input: AVAssetWriterInput) -> sending (AVAssetWriterInput.SampleBufferReceiver, AVAssetWriterInput.MultiPassController) {
        (AVAssetWriterInput.SampleBufferReceiver(input: input, writer: self), AVAssetWriterInput.MultiPassController(input: input))
    }

    public func start() throws {
        guard startWriting() else { throw writerError(self) }
    }
}

@available(macOS 26.0, iOS 26.0, *)
@available(tvOS, unavailable)
@available(watchOS, unavailable)
@available(visionOS, unavailable)
extension AVAssetWriterInput {
    @_hasMissingDesignatedInitializers
    public class MetadataReceiver {
        let adaptor: AVAssetWriterInputMetadataAdaptor
        weak var writer: AVAssetWriter?

        init(input: AVAssetWriterInput, writer: AVAssetWriter) {
            adaptor = AVAssetWriterInputMetadataAdaptor(assetWriterInput: input)
            self.writer = writer
        }

        nonisolated(nonsending) public func append(_ timedMetadataGroup: AVTimedMetadataGroup) async throws {
            try await waitUntilReady(adaptor.assetWriterInput, writer: writer)
            guard try appendImmediately(timedMetadataGroup) else { throw writerError(writer) }
        }

        public func appendImmediately(_ timedMetadataGroup: AVTimedMetadataGroup) throws -> Bool {
            guard adaptor.assetWriterInput.isReadyForMoreMediaData else { return false }
            return try appended(adaptor.append(timedMetadataGroup), writer: writer)
        }

        public func finish() {
            adaptor.assetWriterInput.markAsFinished()
        }
    }

    @_hasMissingDesignatedInitializers
    public class CaptionReceiver {
        let adaptor: AVAssetWriterInputCaptionAdaptor
        weak var writer: AVAssetWriter?

        init(input: AVAssetWriterInput, writer: AVAssetWriter) {
            adaptor = AVAssetWriterInputCaptionAdaptor(assetWriterInput: input)
            self.writer = writer
        }

        nonisolated(nonsending) public func append(_ caption: AVCaption) async throws {
            try await waitUntilReady(adaptor.assetWriterInput, writer: writer)
            guard try appendImmediately(caption) else { throw writerError(writer) }
        }

        nonisolated(nonsending) public func append(_ captionGroup: AVCaptionGroup) async throws {
            try await waitUntilReady(adaptor.assetWriterInput, writer: writer)
            guard try appendImmediately(captionGroup) else { throw writerError(writer) }
        }

        public func appendImmediately(_ caption: AVCaption) throws -> Bool {
            guard adaptor.assetWriterInput.isReadyForMoreMediaData else { return false }
            return try appended(adaptor.append(caption), writer: writer)
        }

        public func appendImmediately(_ captionGroup: AVCaptionGroup) throws -> Bool {
            guard adaptor.assetWriterInput.isReadyForMoreMediaData else { return false }
            return try appended(adaptor.append(captionGroup), writer: writer)
        }

        public func finish() {
            adaptor.assetWriterInput.markAsFinished()
        }
    }
}

@available(macOS 26.0, iOS 26.0, *)
@available(tvOS, unavailable)
@available(watchOS, unavailable)
@available(visionOS, unavailable)
extension AVAssetWriter {
    public func inputMetadataReceiver(for input: AVAssetWriterInput) -> sending AVAssetWriterInput.MetadataReceiver {
        AVAssetWriterInput.MetadataReceiver(input: input, writer: self)
    }

    public func inputMetadataReceiverRequestingMultiPass(for input: AVAssetWriterInput) -> sending (AVAssetWriterInput.MetadataReceiver, AVAssetWriterInput.MultiPassController) {
        (AVAssetWriterInput.MetadataReceiver(input: input, writer: self), AVAssetWriterInput.MultiPassController(input: input))
    }

    public func inputCaptionReceiver(for input: AVAssetWriterInput) -> sending AVAssetWriterInput.CaptionReceiver {
        AVAssetWriterInput.CaptionReceiver(input: input, writer: self)
    }

    public func inputCaptionReceiverRequestingMultiPass(for input: AVAssetWriterInput) -> sending (AVAssetWriterInput.CaptionReceiver, AVAssetWriterInput.MultiPassController) {
        (AVAssetWriterInput.CaptionReceiver(input: input, writer: self), AVAssetWriterInput.MultiPassController(input: input))
    }
}

/// Pixel buffer attributes as the dictionary Core Video takes.
@available(macOS 26.0, iOS 26.0, tvOS 26.0, watchOS 26.0, visionOS 26.0, *)
private func attributesDictionary(_ attributes: CVPixelBufferCreationAttributes?) -> [String: Any]? {
    attributes.map { CVPixelBufferAttributes($0).rawAttributes as [String: Any] }
}

/// A property list value as a Sendable one: numbers, strings, data and
/// dates as they are, arrays and dictionaries of such values.
func sendablePropertyList(_ value: Any) -> any Sendable {
    switch value {
    case let number as NSNumber: return number
    case let string as String: return string
    case let data as Data: return data
    case let date as Date: return date
    case let array as [Any]: return array.map(sendablePropertyList)
    case let dictionary as [String: Any]: return dictionary.mapValues(sendablePropertyList)
    default: return _AVUnsafeSendable(value: value)
    }
}

/// A dictionary of pixel buffer attributes as creation attributes.
@available(macOS 26.0, iOS 26.0, tvOS 26.0, watchOS 26.0, visionOS 26.0, *)
private func creationAttributes(_ dictionary: [String: Any]?) -> CVPixelBufferCreationAttributes? {
    guard let dictionary else { return nil }
    return CVPixelBufferCreationAttributes(CVPixelBufferAttributes(rawAttributes: dictionary.mapValues(sendablePropertyList)))
}

@available(macOS 26.0, iOS 26.0, visionOS 26.0, *)
@available(tvOS, unavailable)
@available(watchOS, unavailable)
extension AVAssetWriterInput {
    @_hasMissingDesignatedInitializers
    public class PixelBufferReceiver {
        let adaptor: AVAssetWriterInputPixelBufferAdaptor
        weak var writer: AVAssetWriter?

        init(input: AVAssetWriterInput, writer: AVAssetWriter, attributes: CVPixelBufferCreationAttributes?) {
            adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: attributesDictionary(attributes))
            self.writer = writer
        }

        public var sourcePixelBufferAttributes: CVPixelBufferCreationAttributes? {
            creationAttributes(adaptor.sourcePixelBufferAttributes)
        }

        public var pixelBufferPool: CVMutablePixelBuffer.Pool? {
            adaptor.pixelBufferPool.map { CVMutablePixelBuffer.Pool(unsafePool: $0) }
        }

        nonisolated(nonsending) public func append(_ pixelBuffer: CVReadOnlyPixelBuffer, with presentationTime: CMTime) async throws {
            try await waitUntilReady(adaptor.assetWriterInput, writer: writer)
            guard try appendImmediately(pixelBuffer, with: presentationTime) else { throw writerError(writer) }
        }

        public func appendImmediately(_ pixelBuffer: CVReadOnlyPixelBuffer, with presentationTime: CMTime) throws -> Bool {
            guard adaptor.assetWriterInput.isReadyForMoreMediaData else { return false }
            return try appended(pixelBuffer.withUnsafeBuffer { adaptor.append($0, withPresentationTime: presentationTime) }, writer: writer)
        }

        public func finish() {
            adaptor.assetWriterInput.markAsFinished()
        }
    }

    @_hasMissingDesignatedInitializers
    public class TaggedPixelBufferGroupReceiver {
        let adaptor: AVAssetWriterInputTaggedPixelBufferGroupAdaptor
        weak var writer: AVAssetWriter?

        init(input: AVAssetWriterInput, writer: AVAssetWriter, attributes: CVPixelBufferCreationAttributes?) {
            adaptor = AVAssetWriterInputTaggedPixelBufferGroupAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: attributesDictionary(attributes))
            self.writer = writer
        }

        public var sourcePixelBufferAttributes: CVPixelBufferCreationAttributes? {
            creationAttributes(adaptor.sourcePixelBufferAttributes)
        }

        public var pixelBufferPool: CVMutablePixelBuffer.Pool? {
            adaptor.pixelBufferPool.map { CVMutablePixelBuffer.Pool(unsafePool: $0) }
        }

        nonisolated(nonsending) public func append(_ taggedPixelBufferGroup: [CMTaggedDynamicBuffer], with presentationTime: CMTime) async throws {
            try await waitUntilReady(adaptor.assetWriterInput, writer: writer)
            guard try appendImmediately(taggedPixelBufferGroup, with: presentationTime) else { throw writerError(writer) }
        }

        public func appendImmediately(_ taggedPixelBufferGroup: [CMTaggedDynamicBuffer], with presentationTime: CMTime) throws -> Bool {
            guard adaptor.assetWriterInput.isReadyForMoreMediaData else { return false }
            guard let group = taggedBufferGroup(taggedPixelBufferGroup) else { return false }
            return try appended(adaptor.appendTaggedPixelBufferGroup(group, withPresentationTime: presentationTime), writer: writer)
        }

        public func finish() {
            adaptor.assetWriterInput.markAsFinished()
        }
    }
}

@available(macOS 26.0, iOS 26.0, visionOS 26.0, *)
@available(tvOS, unavailable)
@available(watchOS, unavailable)
extension AVAssetWriter {
    public func inputPixelBufferReceiver(for input: AVAssetWriterInput, pixelBufferAttributes attributes: CVPixelBufferCreationAttributes?) -> sending AVAssetWriterInput.PixelBufferReceiver {
        AVAssetWriterInput.PixelBufferReceiver(input: input, writer: self, attributes: attributes)
    }

    public func inputPixelBufferReceiverRequestingMultiPass(for input: AVAssetWriterInput, pixelBufferAttributes attributes: CVPixelBufferCreationAttributes?) -> sending (AVAssetWriterInput.PixelBufferReceiver, AVAssetWriterInput.MultiPassController) {
        (AVAssetWriterInput.PixelBufferReceiver(input: input, writer: self, attributes: attributes), AVAssetWriterInput.MultiPassController(input: input))
    }

    public func inputTaggedPixelBufferGroupReceiver(for input: AVAssetWriterInput, pixelBufferAttributes attributes: CVPixelBufferCreationAttributes?) -> sending AVAssetWriterInput.TaggedPixelBufferGroupReceiver {
        AVAssetWriterInput.TaggedPixelBufferGroupReceiver(input: input, writer: self, attributes: attributes)
    }

    public func inputTaggedPixelBufferGroupReceiverRequestingMultiPass(for input: AVAssetWriterInput, pixelBufferAttributes attributes: CVPixelBufferCreationAttributes?) -> sending (AVAssetWriterInput.TaggedPixelBufferGroupReceiver, AVAssetWriterInput.MultiPassController) {
        (AVAssetWriterInput.TaggedPixelBufferGroupReceiver(input: input, writer: self, attributes: attributes), AVAssetWriterInput.MultiPassController(input: input))
    }
}

// MARK: - Reading

@available(macOS 26.0, iOS 26.0, tvOS 26.0, visionOS 26.0, *)
@available(watchOS, unavailable)
extension AVAssetReaderOutput {
    @_hasMissingDesignatedInitializers
    public class RandomAccessController {
        let output: AVAssetReaderOutput

        init(output: AVAssetReaderOutput) {
            self.output = output
        }

        public func resetForReading(timeRanges: [CMTimeRange]) {
            output.reset(forReadingTimeRanges: timeRanges.map { NSValue(timeRange: $0) })
        }

        public func markConfigurationAsFinal() {
            output.markConfigurationAsFinal()
        }
    }
}

@available(macOS 26.0, iOS 26.0, tvOS 26.0, visionOS 26.0, *)
@available(watchOS, unavailable)
extension AVAssetReaderOutput {
    /// What a provider reads: ready sample buffers, timed metadata groups,
    /// caption groups.
    public protocol SupportedPayload {}

    @_hasMissingDesignatedInitializers
    public class Provider<Payload> where Payload: AVAssetReaderOutput.SupportedPayload {
        /// Reads the next payload; nil when there are no more.
        let read: () -> Payload?
        weak var reader: AVAssetReader?
        /// The caption adaptor of a caption provider.
        var captionAdaptor: AVAssetReaderOutputCaptionAdaptor?

        init(reader: AVAssetReader, read: @escaping () -> Payload?) {
            self.reader = reader
            self.read = read
        }

        /// The next payload, read off the caller's task; nil after the last,
        /// or the reader's error if it failed.
        nonisolated(nonsending) public func next() async throws -> Payload? {
            try Task.checkCancellation()
            let read = _AVUnsafeSendable(value: self.read)
            let payload = await Task.detached { _AVUnsafeSendable(value: read.value()) }.value.value
            if payload == nil, let reader, reader.status == .failed {
                throw reader.error ?? NSError(domain: AVFoundationErrorDomain, code: AVError.Code.unknown.rawValue)
            }
            return payload
        }
    }
}

@available(macOS 26.0, iOS 26.0, tvOS 26.0, visionOS 26.0, *)
@available(watchOS, unavailable)
extension CMReadySampleBuffer: AVAssetReaderOutput.SupportedPayload where Content == CMSampleBuffer.DynamicContent {}

@available(macOS 26.0, iOS 26.0, tvOS 26.0, visionOS 26.0, *)
@available(watchOS, unavailable)
extension AVTimedMetadataGroup: AVAssetReaderOutput.SupportedPayload {}

@available(macOS 26.0, iOS 26.0, *)
@available(tvOS, unavailable)
@available(watchOS, unavailable)
@available(visionOS, unavailable)
extension AVCaptionGroup: AVAssetReaderOutput.SupportedPayload {}

@available(macOS 26.0, iOS 26.0, tvOS 26.0, visionOS 26.0, *)
@available(watchOS, unavailable)
extension AVAssetReader {
    private func sampleProvider(for output: AVAssetReaderOutput) -> AVAssetReaderOutput.Provider<CMReadySampleBuffer<CMSampleBuffer.DynamicContent>> {
        AVAssetReaderOutput.Provider(reader: self) {
            output.copyNextSampleBuffer().map { CMReadySampleBuffer(unsafeBuffer: $0) }
        }
    }

    public func outputProvider(for output: AVAssetReaderOutput) -> sending AVAssetReaderOutput.Provider<CMReadySampleBuffer<CMSampleBuffer.DynamicContent>> {
        sampleProvider(for: output)
    }

    public func outputProviderWithRandomAccess(for output: AVAssetReaderOutput) -> sending (AVAssetReaderOutput.Provider<CMReadySampleBuffer<CMSampleBuffer.DynamicContent>>, AVAssetReaderOutput.RandomAccessController) {
        output.supportsRandomAccess = true
        return (sampleProvider(for: output), AVAssetReaderOutput.RandomAccessController(output: output))
    }

    private func metadataProvider(for output: AVAssetReaderTrackOutput) -> AVAssetReaderOutput.Provider<AVTimedMetadataGroup> {
        let adaptor = AVAssetReaderOutputMetadataAdaptor(assetReaderTrackOutput: output)
        return AVAssetReaderOutput.Provider(reader: self) { adaptor.nextTimedMetadataGroup() }
    }

    public func outputMetadataProvider(for output: AVAssetReaderTrackOutput) -> sending AVAssetReaderOutput.Provider<AVTimedMetadataGroup> {
        metadataProvider(for: output)
    }

    public func outputMetadataProviderWithRandomAccess(for output: AVAssetReaderTrackOutput) -> sending (AVAssetReaderOutput.Provider<AVTimedMetadataGroup>, AVAssetReaderOutput.RandomAccessController) {
        output.supportsRandomAccess = true
        return (metadataProvider(for: output), AVAssetReaderOutput.RandomAccessController(output: output))
    }

    public func start() throws {
        guard startReading() else {
            throw error ?? NSError(domain: AVFoundationErrorDomain, code: AVError.Code.unknown.rawValue)
        }
    }
}

@available(macOS 26.0, iOS 26.0, *)
@available(tvOS, unavailable)
@available(watchOS, unavailable)
@available(visionOS, unavailable)
extension AVAssetReader {
    private func captionProvider(for output: AVAssetReaderTrackOutput, validationDelegate: (any AVAssetReaderCaptionValidationHandling)?) -> AVAssetReaderOutput.Provider<AVCaptionGroup> {
        let adaptor = AVAssetReaderOutputCaptionAdaptor(assetReaderTrackOutput: output)
        adaptor.validationDelegate = validationDelegate
        let provider = AVAssetReaderOutput.Provider<AVCaptionGroup>(reader: self) { adaptor.nextCaptionGroup() }
        provider.captionAdaptor = adaptor
        return provider
    }

    public func outputCaptionProvider(for output: AVAssetReaderTrackOutput, validationDelegate: (any AVAssetReaderCaptionValidationHandling)? = nil) -> sending AVAssetReaderOutput.Provider<AVCaptionGroup> {
        captionProvider(for: output, validationDelegate: validationDelegate)
    }

    public func outputCaptionProviderWithRandomAccess(for output: AVAssetReaderTrackOutput, validationDelegate: (any AVAssetReaderCaptionValidationHandling)? = nil) -> sending (AVAssetReaderOutput.Provider<AVCaptionGroup>, AVAssetReaderOutput.RandomAccessController) {
        output.supportsRandomAccess = true
        return (captionProvider(for: output, validationDelegate: validationDelegate), AVAssetReaderOutput.RandomAccessController(output: output))
    }
}

@available(macOS 26.0, iOS 26.0, *)
@available(tvOS, unavailable)
@available(watchOS, unavailable)
@available(visionOS, unavailable)
extension AVAssetReaderOutput.Provider where Payload == AVCaptionGroup {
    public func captionsNotPresentInPreviousGroups(in captionGroup: AVCaptionGroup) -> [AVCaption] {
        captionAdaptor?.captionsNotPresentInPreviousGroups(in: captionGroup) ?? captionGroup.captions
    }
}
