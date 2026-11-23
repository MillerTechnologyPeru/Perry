import Foundation
import CoreMedia
import CoreGraphics
import CoreVideo
import Dispatch

// AVFoundation's Swift API over its NSNumber, NSValue and dictionary
// arrays (the members its API notes make private to Swift), Core Media's
// times bridged to NSValue, AVError's userInfo and the notification names.

// MARK: - Core Media values as NSValues

extension CMTime: _ObjectiveCBridgeable {
    public func _bridgeToObjectiveC() -> NSValue { NSValue(time: self) }

    public static func _forceBridgeFromObjectiveC(_ source: NSValue, result: inout CMTime?) {
        result = source.timeValue
    }

    public static func _conditionallyBridgeFromObjectiveC(_ source: NSValue, result: inout CMTime?) -> Bool {
        guard holds(source, CMTime.self) else { result = nil; return false }
        result = source.timeValue
        return true
    }

    public static func _unconditionallyBridgeFromObjectiveC(_ source: NSValue?) -> CMTime {
        source?.timeValue ?? .invalid
    }

    public typealias _ObjectiveCType = NSValue
}

extension CMTimeRange: _ObjectiveCBridgeable {
    public func _bridgeToObjectiveC() -> NSValue { NSValue(timeRange: self) }

    public static func _forceBridgeFromObjectiveC(_ source: NSValue, result: inout CMTimeRange?) {
        result = source.timeRangeValue
    }

    public static func _conditionallyBridgeFromObjectiveC(_ source: NSValue, result: inout CMTimeRange?) -> Bool {
        guard holds(source, CMTimeRange.self) else { result = nil; return false }
        result = source.timeRangeValue
        return true
    }

    public static func _unconditionallyBridgeFromObjectiveC(_ source: NSValue?) -> CMTimeRange {
        source?.timeRangeValue ?? .invalid
    }

    public typealias _ObjectiveCType = NSValue
}

extension CMTimeMapping: _ObjectiveCBridgeable {
    public func _bridgeToObjectiveC() -> NSValue { NSValue(timeMapping: self) }

    public static func _forceBridgeFromObjectiveC(_ source: NSValue, result: inout CMTimeMapping?) {
        result = source.timeMappingValue
    }

    public static func _conditionallyBridgeFromObjectiveC(_ source: NSValue, result: inout CMTimeMapping?) -> Bool {
        guard holds(source, CMTimeMapping.self) else { result = nil; return false }
        result = source.timeMappingValue
        return true
    }

    public static func _unconditionallyBridgeFromObjectiveC(_ source: NSValue?) -> CMTimeMapping {
        source?.timeMappingValue ?? CMTimeMapping(source: .invalid, target: .invalid)
    }

    public typealias _ObjectiveCType = NSValue
}

/// Whether a value holds a T: its type encoding is T's.
private func holds<T>(_ value: NSValue, _ type: T.Type) -> Bool {
    strcmp(value.objCType, _getObjCTypeEncoding(T.self)) == 0
}

/// The time ranges in an array of NSValues.
func timeRanges(_ values: [NSValue]) -> [CMTimeRange] {
    values.map { $0.timeRangeValue }
}

// MARK: - Errors

@available(watchOS 6.0, *)
extension AVError {
    @available(swift, obsoleted: 4.2, message: "Use `device: AVCaptureDevice?` instead")
    public var device: String? {
        userInfo[AVErrorDeviceKey] as? String
    }

    @available(swift 4.2)
    @available(macCatalyst 14.0, tvOS 17.0, *)
    @available(visionOS, unavailable)
    @available(watchOS, unavailable)
    public var device: AVCaptureDevice? {
        userInfo[AVErrorDeviceKey] as? AVCaptureDevice
    }

    public var time: CMTime? {
        (userInfo[AVErrorTimeKey] as? NSValue)?.timeValue
    }

    public var fileSize: Int64? {
        (userInfo[AVErrorFileSizeKey] as? NSNumber)?.int64Value
    }

    public var processID: Int? {
        (userInfo[AVErrorPIDKey] as? NSNumber)?.intValue
    }

    public var recordingSuccessfullyFinished: Bool? {
        (userInfo[AVErrorRecordingSuccessfullyFinishedKey] as? NSNumber)?.boolValue
    }

    @available(swift, obsoleted: 4.2)
    public var mediaType: String? {
        userInfo[AVErrorMediaTypeKey] as? String
    }

    @available(swift 4.2)
    public var mediaType: AVMediaType? {
        (userInfo[AVErrorMediaTypeKey] as? String).map(AVMediaType.init(rawValue:))
    }

    public var mediaSubtypes: [Int]? {
        (userInfo[AVErrorMediaSubTypeKey] as? [NSNumber])?.map { $0.intValue }
    }

    @available(swift 4.2)
    @available(macOS 10.10, iOS 8.0, tvOS 9.0, watchOS 6.0, visionOS 1.0, *)
    public var presentationTimeStamp: CMTime? {
        (userInfo[AVErrorPresentationTimeStampKey] as? NSValue)?.timeValue
    }

    @available(swift 4.2)
    @available(macOS 10.10, iOS 8.0, tvOS 9.0, watchOS 6.0, visionOS 1.0, *)
    public var persistentTrackID: CMPersistentTrackID? {
        (userInfo[AVErrorPersistentTrackIDKey] as? NSNumber)?.int32Value
    }

    @available(swift 4.2)
    @available(macOS 10.10, iOS 8.0, tvOS 9.0, watchOS 6.0, visionOS 1.0, *)
    public var fileType: AVFileType? {
        (userInfo[AVErrorFileTypeKey] as? String).map(AVFileType.init(rawValue:))
    }
}

// MARK: - Notification names
// Clients inline these; the overlay keeps the symbols (and property
// descriptors) code built against older SDKs binds.

extension NSNotification.Name {
    public static var AVPlayerInterstitialEventMonitorAssetListResponseStatusDidChange: NSNotification.Name {
        Self("AVPlayerInterstitialEventMonitorAssetListResponseStatusDidChange")
    }

    public static var AVPlayerItemTimeJumped: NSNotification.Name { Self("AVPlayerItemTimeJumpedNotification") }
    public static var AVPlayerItemPlaybackStalled: NSNotification.Name { Self("AVPlayerItemPlaybackStalledNotification") }
    public static var AVPlayerItemNewErrorLogEntry: NSNotification.Name { Self("AVPlayerItemNewErrorLogEntry") }
    public static var AVPlayerItemNewAccessLogEntry: NSNotification.Name { Self("AVPlayerItemNewAccessLogEntry") }
    public static var AVPlayerItemDidPlayToEndTime: NSNotification.Name { Self("AVPlayerItemDidPlayToEndTimeNotification") }
    public static var AVPlayerItemFailedToPlayToEndTime: NSNotification.Name { Self("AVPlayerItemFailedToPlayToEndTimeNotification") }

    public static var AVCaptureSessionRuntimeError: NSNotification.Name { AVCaptureSession.runtimeErrorNotification }
    public static var AVCaptureSessionDidStartRunning: NSNotification.Name { AVCaptureSession.didStartRunningNotification }
    public static var AVCaptureSessionDidStopRunning: NSNotification.Name { AVCaptureSession.didStopRunningNotification }
    public static var AVCaptureSessionWasInterrupted: NSNotification.Name { AVCaptureSession.wasInterruptedNotification }
    public static var AVCaptureSessionInterruptionEnded: NSNotification.Name { AVCaptureSession.interruptionEndedNotification }
    public static var AVCaptureInputPortFormatDescriptionDidChange: NSNotification.Name { AVCaptureInput.Port.formatDescriptionDidChangeNotification }
    public static var AVCaptureDeviceWasConnected: NSNotification.Name { AVCaptureDevice.wasConnectedNotification }
    public static var AVCaptureDeviceWasDisconnected: NSNotification.Name { AVCaptureDevice.wasDisconnectedNotification }
    public static var AVCaptureDeviceSubjectAreaDidChange: NSNotification.Name { Self("AVCaptureDeviceSubjectAreaDidChangeNotification") }
}

// MARK: - Interstitial events

@available(macOS 12, iOS 15, tvOS 15, watchOS 8, visionOS 1, *)
extension AVPlayerInterstitialEvent {
    public convenience init(primaryItem: AVPlayerItem, identifier: String?, time: CMTime, templateItems: [AVPlayerItem], restrictions: AVPlayerInterstitialEvent.Restrictions = [], resumptionOffset: CMTime = .indefinite, playoutLimit: CMTime = .invalid, userDefinedAttributes: [String: Any] = [:]) {
        self.init(__primaryItem: primaryItem, identifier: identifier, time: time, templateItems: templateItems, restrictions: restrictions, resumptionOffset: resumptionOffset, playoutLimit: playoutLimit, userDefinedAttributes: userDefinedAttributes)
    }

    public convenience init(primaryItem: AVPlayerItem, identifier: String?, date: Date, templateItems: [AVPlayerItem], restrictions: AVPlayerInterstitialEvent.Restrictions = [], resumptionOffset: CMTime = .indefinite, playoutLimit: CMTime = .invalid, userDefinedAttributes: [String: Any] = [:]) {
        self.init(__primaryItem: primaryItem, identifier: identifier, date: date, templateItems: templateItems, restrictions: restrictions, resumptionOffset: resumptionOffset, playoutLimit: playoutLimit, userDefinedAttributes: userDefinedAttributes)
    }
}

@available(macOS 26.4, iOS 26.4, tvOS 26.4, watchOS 26.4, visionOS 26.4, *)
extension AVPlayerInterstitialEventMonitor {
    /// A schedule request's completion, the userInfo of
    /// AVPlayerInterstitialEventMonitorScheduleRequestCompletedNotification.
    public struct ScheduleRequestCompleted: NotificationCenter.AsyncMessage {
        public static var name: Notification.Name {
            Notification.Name("AVPlayerInterstitialEventMonitorScheduleRequestCompletedNotification")
        }

        public typealias Subject = AVPlayerInterstitialEventMonitor

        public let scheduleIdentifier: String
        public let result: Result<Data, any Error>

        init(scheduleIdentifier: String, result: Result<Data, any Error>) {
            self.scheduleIdentifier = scheduleIdentifier
            self.result = result
        }

        public static func makeMessage(_ notification: Notification) -> AVPlayerInterstitialEventMonitor.ScheduleRequestCompleted? {
            guard let info = notification.userInfo,
                  let identifier = info["AVPlayerInterstitialEventMonitorScheduleRequestIdentifierKey"] as? String else { return nil }
            if let data = info["AVPlayerInterstitialEventMonitorScheduleRequestResponseKey"] as? Data {
                return ScheduleRequestCompleted(scheduleIdentifier: identifier, result: .success(data))
            }
            let error = info["AVPlayerInterstitialEventMonitorScheduleRequestErrorKey"] as? NSError
                ?? NSError(domain: AVFoundationErrorDomain, code: AVError.Code.unknown.rawValue)
            return ScheduleRequestCompleted(scheduleIdentifier: identifier, result: .failure(error))
        }

        public static func makeNotification(_ message: AVPlayerInterstitialEventMonitor.ScheduleRequestCompleted) -> Notification {
            var info: [AnyHashable: Any] = ["AVPlayerInterstitialEventMonitorScheduleRequestIdentifierKey": message.scheduleIdentifier]
            switch message.result {
            case let .success(data): info["AVPlayerInterstitialEventMonitorScheduleRequestResponseKey"] = data
            case let .failure(error): info["AVPlayerInterstitialEventMonitorScheduleRequestErrorKey"] = error as NSError
            }
            return Notification(name: name, object: nil, userInfo: info)
        }
    }
}

// MARK: - Players and items

extension AVPlayerItem {
    @available(macOS 12, iOS 15, tvOS 15, watchOS 8, visionOS 1, *)
    @MainActor @preconcurrency
    public convenience init(asset: AVAsset, automaticallyLoadedAssetKeys: [AVPartialAsyncProperty<AVAsset>] = []) {
        self.init(asset: asset, automaticallyLoadedAssetKeys: automaticallyLoadedAssetKeys.map { $0.key })
    }

    @available(macOS 13, iOS 16, tvOS 16, watchOS 9, visionOS 1, *)
    nonisolated public func seek(to date: Date) async -> Bool {
        await withCheckedContinuation { continuation in
            if !seek(to: date, completionHandler: { continuation.resume(returning: $0) }) {
                // The item can't seek to a date: the handler isn't called.
                continuation.resume(returning: false)
            }
        }
    }
}

@available(iOS 27.0, tvOS 27.0, watchOS 27.0, visionOS 27.0, *)
@available(macOS, unavailable)
@available(macCatalyst, unavailable)
extension AVPlayer {
    nonisolated public func setDisconnectedFromSystemAudio(_ disconnected: Bool, completionHandler: (@Sendable () -> Void)? = nil) {
        __setDisconnectedFromSystemAudio(disconnected, completionHandler: completionHandler)
    }
}

@available(macOS 26.0, iOS 26.0, tvOS 26.0, visionOS 26.0, *)
@available(watchOS, unavailable)
extension AVPlayerLayer {
    public func displayedReadOnlyPixelBuffer() -> CVReadOnlyPixelBuffer? {
        guard let buffer = displayedPixelBuffer() else { return nil }
        return CVReadOnlyPixelBuffer(unsafeBuffer: buffer)
    }
}

@available(macOS 26.0, iOS 26.0, tvOS 26.0, visionOS 26.0, *)
@available(watchOS, unavailable)
extension AVPlayerItemVideoOutput {
    public convenience init(pixelBufferAttributes: CVPixelBufferAttributes) {
        self.init(pixelBufferAttributes: pixelBufferAttributes.rawAttributes as [String: Any])
    }

    public func pixelBufferAndDisplayTime(forItemTime itemTime: CMTime) -> (pixelBuffer: CVReadOnlyPixelBuffer?, itemTimeForDisplay: CMTime) {
        var displayTime = CMTime.invalid
        let buffer = copyPixelBuffer(forItemTime: itemTime, itemTimeForDisplay: &displayTime)
        return (buffer.map { CVReadOnlyPixelBuffer(unsafeBuffer: $0) }, displayTime)
    }
}

@available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2.0, *)
extension AVPlayerItemSegment {
    @nonobjc public var loadedTimeRanges: [CMTimeRange] { timeRanges(__loadedTimeRanges) }
}

@available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
extension AVMetricPlayerItemLikelyToKeepUpEvent {
    @nonobjc public var loadedTimeRanges: [CMTimeRange] { timeRanges(__loadedTimeRanges) }
}

@available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
extension AVMetricPlayerItemVariantSwitchEvent {
    @nonobjc public var loadedTimeRanges: [CMTimeRange] { timeRanges(__loadedTimeRanges) }
}

@available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
extension AVMetricPlayerItemVariantSwitchStartEvent {
    @nonobjc public var loadedTimeRanges: [CMTimeRange] { timeRanges(__loadedTimeRanges) }
}

// MARK: - Assets

extension AVAsset {
    @available(macOS 12, iOS 15, tvOS 15, watchOS 8, visionOS 1, *)
    public func loadChapterMetadataGroups(withTitleLocale locale: Locale, containingItemsWithCommonKeys commonKeys: [AVMetadataKey] = []) async throws -> [AVTimedMetadataGroup] {
        try await __loadChapterMetadataGroups(withTitleLocale: locale, containingItemsWithCommonKeys: commonKeys)
    }
}

extension AVMutableComposition {
    @available(macOS 12, iOS 15, tvOS 15, watchOS 8, visionOS 1, *)
    public final func insertTimeRange(_ timeRange: CMTimeRange, of asset: AVAsset, at time: CMTime, isolation: isolated (any Actor)? = #isolation) async throws {
        // Load what inserting reads first, so that it doesn't block.
        let tracks = try await asset.load(.tracks)
        for track in tracks {
            _ = try await track.load(.formatDescriptions)
        }
        // In a synchronous closure the call is the Objective-C method's.
        try { try insertTimeRange(timeRange, of: asset, at: time) }()
    }
}

@available(macOS 12, iOS 15, tvOS 15, watchOS 8, visionOS 1, *)
extension AVAssetVariant {
    /// The bit rate, nil where the variant gives none (zero).
    @nonobjc public var peakBitRate: Double? { positive(__peakBitRate) }
    @nonobjc public var averageBitRate: Double? { positive(__averageBitRate) }
}

@available(macOS 12, iOS 15, tvOS 15, watchOS 8, visionOS 1, *)
extension AVAssetVariant.VideoAttributes {
    @nonobjc public var nominalFrameRate: Double? { positive(__nominalFrameRate) }
    @nonobjc public var codecTypes: [CMVideoCodecType] { __codecTypes.map { $0.uint32Value } }
}

@available(macOS 12, iOS 15, tvOS 15, watchOS 8, visionOS 1, *)
extension AVAssetVariant.AudioAttributes {
    @nonobjc public var formatIDs: [AudioFormatID] { __formatIDs.map { $0.uint32Value } }
}

@available(macOS 12, iOS 15, tvOS 15, watchOS 8, visionOS 1, *)
extension AVAssetVariant.AudioAttributes.RenditionSpecificAttributes {
    @nonobjc public var channelCount: Int? { __channelCount > 0 ? __channelCount : nil }
}

private func positive(_ value: Double) -> Double? {
    value > 0 && value.isFinite ? value : nil
}

@available(macOS 26.0, iOS 26.0, tvOS 26.0, watchOS 26.0, visionOS 26.0, *)
extension AVTimedMetadataGroup {
    public convenience init?(sampleBuffer: CMReadySampleBuffer<CMSampleBuffer.DynamicContent>) {
        let buffer = sampleBuffer.withUnsafeSampleBuffer { $0 }
        self.init(sampleBuffer: buffer)
    }
}

@available(macOS 26.0, iOS 26.0, watchOS 26.0, visionOS 26.0, *)
@available(tvOS, unavailable)
extension AVMutableMovieTrack {
    public func append(_ sampleBuffer: CMReadySampleBuffer<CMSampleBuffer.DynamicContent>) throws -> (decodeTime: CMTime, presentationTime: CMTime) {
        var decodeTime = CMTime.invalid
        var presentationTime = CMTime.invalid
        let buffer = sampleBuffer.withUnsafeSampleBuffer { $0 }
        try append(buffer, decodeTime: &decodeTime, presentationTime: &presentationTime)
        return (decodeTime, presentationTime)
    }
}

// MARK: - Captions

@available(macOS 12.0, iOS 18.0, macCatalyst 15.0, *)
@available(tvOS, unavailable)
@available(watchOS, unavailable)
@available(visionOS, unavailable)
extension AVCaption {
    /// An index of the caption's text as the UTF-16 offset its methods take.
    private func offset(_ index: String.Index) -> Int { index.utf16Offset(in: text) }

    /// A UTF-16 range of the caption's text as a range of its indices.
    private func range(_ range: NSRange) -> Range<String.Index> {
        if let result = Range(range, in: text) { return result }
        return text.startIndex..<text.startIndex
    }

    @nonobjc public func textColor(at index: String.Index) -> (CGColor?, Range<String.Index>) {
        var found = NSRange(location: NSNotFound, length: 0)
        let color = __textColor(at: offset(index), range: &found)
        return (color, range(found))
    }

    @nonobjc public func backgroundColor(at index: String.Index) -> (CGColor?, Range<String.Index>) {
        var found = NSRange(location: NSNotFound, length: 0)
        let color = __backgroundColor(at: offset(index), range: &found)
        return (color, range(found))
    }

    @nonobjc public func fontWeight(at index: String.Index) -> (AVCaption.FontWeight, Range<String.Index>) {
        var found = NSRange(location: NSNotFound, length: 0)
        let weight = __fontWeight(at: offset(index), range: &found)
        return (weight, range(found))
    }

    @nonobjc public func fontStyle(at index: String.Index) -> (AVCaption.FontStyle, Range<String.Index>) {
        var found = NSRange(location: NSNotFound, length: 0)
        let style = __fontStyle(at: offset(index), range: &found)
        return (style, range(found))
    }

    @nonobjc public func decoration(at index: String.Index) -> (AVCaption.Decoration, Range<String.Index>) {
        var found = NSRange(location: NSNotFound, length: 0)
        let decoration = __decoration(at: offset(index), range: &found)
        return (decoration, range(found))
    }

    @nonobjc public func textCombine(at index: String.Index) -> (AVCaption.TextCombine, Range<String.Index>) {
        var found = NSRange(location: NSNotFound, length: 0)
        let combine = __textCombine(at: offset(index), range: &found)
        return (combine, range(found))
    }

    @nonobjc public func ruby(at index: String.Index) -> (AVCaption.Ruby?, Range<String.Index>) {
        var found = NSRange(location: NSNotFound, length: 0)
        let ruby = __ruby(at: offset(index), range: &found)
        return (ruby, range(found))
    }
}

@available(macOS 12.0, iOS 18.0, macCatalyst 15.0, *)
@available(tvOS, unavailable)
@available(watchOS, unavailable)
@available(visionOS, unavailable)
extension AVMutableCaption {
    @nonobjc public func setTextColor(_ textColor: CGColor, in range: NSRange) { __setTextColor(textColor, in: range) }
    @nonobjc public func setBackgroundColor(_ backgroundColor: CGColor, in range: NSRange) { __setBackgroundColor(backgroundColor, in: range) }
    @nonobjc public func setFontWeight(_ fontWeight: AVCaption.FontWeight, in range: NSRange) { __setFontWeight(fontWeight, in: range) }
    @nonobjc public func setFontStyle(_ fontStyle: AVCaption.FontStyle, in range: NSRange) { __setFontStyle(fontStyle, in: range) }
    @nonobjc public func setDecoration(_ decoration: AVCaption.Decoration, in range: NSRange) { __setDecoration(decoration, in: range) }
    @nonobjc public func setTextCombine(_ textCombine: AVCaption.TextCombine, in range: NSRange) { __setTextCombine(textCombine, in: range) }
    @nonobjc public func setRuby(_ rubyText: AVCaption.Ruby, in range: NSRange) { __setRuby(rubyText, in: range) }
    @nonobjc public func removeTextColor(in range: NSRange) { __removeTextColor(in: range) }
    @nonobjc public func removeBackgroundColor(in range: NSRange) { __removeBackgroundColor(in: range) }
    @nonobjc public func removeFontWeight(in range: NSRange) { __removeFontWeight(in: range) }
    @nonobjc public func removeFontStyle(in range: NSRange) { __removeFontStyle(in: range) }
    @nonobjc public func removeDecoration(in range: NSRange) { __removeDecoration(in: range) }
    @nonobjc public func removeTextCombine(in range: NSRange) { __removeTextCombine(in: range) }
    @nonobjc public func removeRuby(in range: NSRange) { __removeRuby(in: range) }
}

@available(macOS 26.0, iOS 26.0, *)
@available(tvOS, unavailable)
@available(watchOS, unavailable)
@available(visionOS, unavailable)
extension AVRenderedCaptionImage {
    public var readOnlyPixelBuffer: CVReadOnlyPixelBuffer {
        CVReadOnlyPixelBuffer(unsafeBuffer: pixelBuffer)
    }
}

// MARK: - Capture

@available(macOS 11.0, iOS 7.0, macCatalyst 14.0, tvOS 17.0, *)
@available(watchOS, unavailable)
@available(visionOS, unavailable)
extension AVMetadataMachineReadableCodeObject {
    /// The corners, each a CGPoint's dictionary representation.
    @nonobjc public var corners: [CGPoint] {
        __corners.compactMap { CGPoint(dictionaryRepresentation: $0 as CFDictionary) }
    }
}

@available(macOS 10.15, iOS 10.0, macCatalyst 14.0, tvOS 17.0, *)
@available(visionOS, unavailable)
@available(watchOS, unavailable)
extension AVCapturePhotoOutput {
    @available(macOS 13.0, *)
    @nonobjc public var supportedFlashModes: [AVCaptureDevice.FlashMode] {
        __supportedFlashModes.compactMap { AVCaptureDevice.FlashMode(rawValue: $0.intValue) }
    }

    @nonobjc public var availablePhotoPixelFormatTypes: [OSType] {
        __availablePhotoPixelFormatTypes.map { $0.uint32Value }
    }

    @available(macOS, unavailable)
    @nonobjc public var availableRawPhotoPixelFormatTypes: [OSType] {
        __availableRawPhotoPixelFormatTypes.map { $0.uint32Value }
    }

    @available(*, unavailable, message: "Use 'supportedPhotoPixelFormatTypes(for:) -> [OSType]' instead")
    @nonobjc public func supportedPhotoPixelFormatTypes(for fileType: AVFileType) -> [NSNumber] {
        __supportedPhotoPixelFormatTypes(forFileType: fileType)
    }

    @available(*, unavailable, message: "Use 'supportedRawPhotoPixelFormatTypes(for:) -> [OSType]' instead")
    @nonobjc public func supportedRawPhotoPixelFormatTypes(for fileType: AVFileType) -> [NSNumber] {
        __supportedRawPhotoPixelFormatTypes(forFileType: fileType)
    }
}

@available(macOS 10.15, iOS 10.0, macCatalyst 14.0, tvOS 17.0, *)
@available(visionOS, unavailable)
@available(watchOS, unavailable)
extension AVCapturePhotoSettings {
    @available(macOS, unavailable)
    @nonobjc public var availablePreviewPhotoPixelFormatTypes: [OSType] {
        __availablePreviewPhotoPixelFormatTypes.map { $0.uint32Value }
    }
}

@available(macOS 10.15, iOS 11.0, macCatalyst 14.0, tvOS 17.0, *)
@available(visionOS, unavailable)
@available(watchOS, unavailable)
extension AVCapturePhoto {
    @available(*, unavailable, message: "Use 'cgImageRepresentation() -> CGImage?' instead")
    @nonobjc public func cgImageRepresentation() -> Unmanaged<CGImage>? {
        let image: CGImage? = cgImageRepresentation()
        return image.map { Unmanaged.passUnretained($0) }
    }

    @available(*, unavailable, message: "Use 'previewCGImageRepresentation() -> CGImage?' instead")
    @nonobjc public func previewCGImageRepresentation() -> Unmanaged<CGImage>? {
        let image: CGImage? = previewCGImageRepresentation()
        return image.map { Unmanaged.passUnretained($0) }
    }
}

@available(macOS 10.7, iOS 4.0, macCatalyst 14.0, tvOS 17.0, *)
@available(visionOS, unavailable)
@available(watchOS, unavailable)
extension AVCaptureVideoDataOutput {
    @nonobjc public var availableVideoPixelFormatTypes: [OSType] {
        __availableVideoCVPixelFormatTypes.map { $0.uint32Value }
    }

    /// The Swift 3 name of availableVideoPixelFormatTypes.
    @nonobjc public var availableVideoCVPixelFormatTypes: [Any]! {
        __availableVideoCVPixelFormatTypes
    }
}

@available(macOS 10.7, iOS 7.0, macCatalyst 14.0, tvOS 17.0, *)
@available(visionOS, unavailable)
@available(watchOS, unavailable)
extension AVCaptureDevice.Format {
    @available(macOS 10.15, *)
    @nonobjc public var supportedColorSpaces: [AVCaptureColorSpace] {
        __supportedColorSpaces.compactMap { AVCaptureColorSpace(rawValue: $0.intValue) }
    }

    @available(macOS 13.0, iOS 16.0, *)
    @nonobjc public var supportedMaxPhotoDimensions: [CMVideoDimensions] {
        __supportedMaxPhotoDimensions.map { value in
            var dimensions = CMVideoDimensions(width: 0, height: 0)
            value.getValue(&dimensions, size: MemoryLayout<CMVideoDimensions>.size)
            return dimensions
        }
    }

    @available(macOS 13.0, iOS 16.0, *)
    @nonobjc public var secondaryNativeResolutionZoomFactors: [CGFloat] {
        __secondaryNativeResolutionZoomFactors.map { CGFloat($0.doubleValue) }
    }

    @available(macOS, unavailable)
    @available(iOS, introduced: 16.0, deprecated: 17.2)
    @nonobjc public var supportedVideoZoomFactorsForDepthDataDelivery: [CGFloat] {
        __supportedVideoZoomFactorsForDepthDataDelivery.map { CGFloat($0.doubleValue) }
    }

    @available(macOS 14.2, iOS 17.2, *)
    @nonobjc public var supportedVideoZoomRangesForDepthDataDelivery: [ClosedRange<CGFloat>] {
        __supportedVideoZoomRangesForDepthDataDelivery.map { $0.minZoomFactor...max($0.minZoomFactor, $0.maxZoomFactor) }
    }

    @available(macOS 15.0, iOS 18.0, macCatalyst 18.0, tvOS 18.0, *)
    @nonobjc public var systemRecommendedVideoZoomRange: ClosedRange<CGFloat>? {
        __systemRecommendedVideoZoomRange.map { $0.minZoomFactor...max($0.minZoomFactor, $0.maxZoomFactor) }
    }

    @available(macOS 15.0, iOS 18.0, macCatalyst 18.0, tvOS 18.0, *)
    @nonobjc public var systemRecommendedExposureBiasRange: ClosedRange<Float>? {
        __systemRecommendedExposureBiasRange.map { $0.minExposureBias...max($0.minExposureBias, $0.maxExposureBias) }
    }

    @available(iOS 27.0, macCatalyst 27.0, tvOS 27.0, *)
    @available(macOS, unavailable)
    @nonobjc public var recommendedLensApertureStops: [Float] {
        __recommendedLensApertureStops.map { $0.floatValue }
    }
}

@available(macOS 15.0, iOS 18.0, macCatalyst 18.0, tvOS 18.0, *)
@available(visionOS, unavailable)
@available(watchOS, unavailable)
extension AVCaptureSlider {
    @nonobjc public var prominentValues: [Float] {
        get { __prominentValues.map { $0.floatValue } }
        set { __prominentValues = newValue.map { NSNumber(value: $0) } }
    }

    @nonobjc public convenience init(_ localizedTitle: String, symbolName: String, in range: ClosedRange<Float>) {
        self.init(__localizedTitle: localizedTitle, symbolName: symbolName, minValue: range.lowerBound, maxValue: range.upperBound)
    }

    @nonobjc public convenience init(_ localizedTitle: String, symbolName: String, in range: ClosedRange<Float>, step: Float) {
        self.init(__localizedTitle: localizedTitle, symbolName: symbolName, minValue: range.lowerBound, maxValue: range.upperBound, step: step)
    }

    @nonobjc public convenience init(_ localizedTitle: String, symbolName: String, values: [Float]) {
        self.init(__localizedTitle: localizedTitle, symbolName: symbolName, values: values.map { NSNumber(value: $0) })
    }

    @nonobjc public func setActionQueue(_ actionQueue: DispatchQueue, action: @escaping (Float) -> ()) {
        __setActionQueue(actionQueue, action: action)
    }
}

@available(macOS 15.0, iOS 18.0, macCatalyst 18.0, tvOS 18.0, *)
@available(visionOS, unavailable)
@available(watchOS, unavailable)
extension AVCaptureIndexPicker {
    @nonobjc public func setActionQueue(_ actionQueue: DispatchQueue, action: @escaping (Int) -> ()) {
        __setActionQueue(actionQueue, action: action)
    }
}

@available(iOS 11.0, macCatalyst 18.0, tvOS 17.0, *)
@available(macOS, unavailable)
@available(visionOS, unavailable)
@available(watchOS, unavailable)
extension AVCaptureSynchronizedDataCollection: Sequence {
    public func makeIterator() -> AVCaptureSynchronizedDataCollection.Iterator {
        Iterator(enumerator: NSFastEnumerationIterator(self))
    }

    public struct Iterator: IteratorProtocol {
        var enumerator: NSFastEnumerationIterator

        public mutating func next() -> AVCaptureSynchronizedData? {
            enumerator.next() as? AVCaptureSynchronizedData
        }

        public typealias Element = AVCaptureSynchronizedData
    }

    public typealias Element = AVCaptureSynchronizedData
}
