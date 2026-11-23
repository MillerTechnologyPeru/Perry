import Foundation
import CoreMedia
import VideoToolbox

// Planned, resumable asset writing in Swift: the planner's throwing
// initializer, segment handlers as async functions, resumable writer
// inputs and compression sessions that throw.

@available(macOS 27.0, iOS 27.0, tvOS 27.0, visionOS 27.0, *)
@available(watchOS, unavailable)
extension AVPlannedVideoSegmentWritingRequest {
    public func makeResumableWriterInput(for mediaType: AVMediaType, outputSettings: [String: any Sendable]? = nil, sourceFormatHint: CMFormatDescription? = nil) throws -> AVAssetWriterInput {
        try __resumableAssetWriterInput(withMediaType: mediaType, outputSettings: outputSettings, sourceFormatHint: sourceFormatHint)
    }
}

/// The output handler of a compression session, called by its C callback.
private final class CompressionOutput {
    let handler: @Sendable (OSStatus, VTEncodeInfoFlags, CMSampleBuffer?) -> Void

    init(_ handler: @escaping @Sendable (OSStatus, VTEncodeInfoFlags, CMSampleBuffer?) -> Void) {
        self.handler = handler
    }
}

@available(macOS 27.0, iOS 27.0, tvOS 27.0, visionOS 27.0, *)
@available(watchOS, unavailable)
extension AVPlannedVideoSegmentWritingRequest {
    public func createResumableCompressionSession(width: Int32, height: Int32, codecType: CMVideoCodecType, encoderSpecification: [String: any Sendable]? = nil, sourceImageBufferAttributes: [String: any Sendable]? = nil, outputHandler: @escaping @Sendable (OSStatus, VTEncodeInfoFlags, CMSampleBuffer?) -> Void) throws -> VTCompressionSession {
        // The handler lives as long as the session: released when the
        // session is, through its retained reference constant.
        let output = Unmanaged.passRetained(CompressionOutput(outputHandler))
        let callback: VTCompressionOutputCallback = { refCon, _, status, flags, sampleBuffer in
            guard let refCon else { return }
            Unmanaged<CompressionOutput>.fromOpaque(refCon).takeUnretainedValue().handler(status, flags, sampleBuffer)
        }
        do {
            let session = try __createResumableCompressionSession(with: nil, width: width, height: height, codecType: codecType, encoderSpecification: encoderSpecification, sourceImageBufferAttributes: sourceImageBufferAttributes, compressedDataAllocator: nil, outputCallback: callback, outputCallbackRefCon: output.toOpaque())
            return session
        } catch {
            output.release()
            throw error
        }
    }
}

@available(macOS 27.0, iOS 27.0, tvOS 27.0, visionOS 27.0, *)
@available(watchOS, unavailable)
extension AVAssetWritingPlanner {
    public convenience init(directoryForTemporaryFiles: URL) throws {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: directoryForTemporaryFiles.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw NSError(domain: NSCocoaErrorDomain, code: NSFileNoSuchFileError, userInfo: [NSURLErrorKey: directoryForTemporaryFiles])
        }
        self.init(__directoryForTemporaryFiles: directoryForTemporaryFiles)
    }

    public static func segmentBoundaryGuidelinesForVideo(codecType: AVVideoCodecType, encoderSpecification: [String: any Sendable]) -> AVAssetWritingPlanner.SegmentBoundaryGuidelines {
        __segmentBoundaryGuidelines(forVideoCodecType: codecType, videoEncoderSpecification: encoderSpecification)
    }

    public enum SegmentResult {
        case success
        case successWithState(Data)
        case cancelled
    }

    /// Plans a track, each of its segments written by the handler, the
    /// request finished with the handler's result or error.
    public func plan(_ trackPlan: AVAssetTrackPlan, segmentHandler: @escaping @Sendable (_ request: AVPlannedSegmentWritingRequest) async throws -> AVAssetWritingPlanner.SegmentResult) {
        __planTrack(trackPlan) { request in
            let request = _AVUnsafeSendable(value: request)
            Task {
                do {
                    switch try await segmentHandler(request.value) {
                    case .success: request.value.__finish()
                    case let .successWithState(state): request.value.__finish(withClientState: state)
                    case .cancelled: request.value.__cancel()
                    }
                } catch {
                    request.value.__finishWithError(error)
                }
            }
        }
    }

    public func executePlan() async throws -> AVComposition {
        try await __executePlan()
    }
}

@available(macOS 27.0, iOS 27.0, tvOS 27.0, visionOS 27.0, *)
@available(watchOS, unavailable)
extension AVAssetVideoTrackPlan {
    public convenience init(videoCodecType: AVVideoCodecType, encoderSpecification: [String: any Sendable]? = nil, mediaType: AVMediaType, segmentConfigurations: [AVPlannedVideoSegmentConfiguration], assemblyTrackID: CMPersistentTrackID) {
        self.init(__videoCodecType: videoCodecType, encoderSpecification: encoderSpecification, mediaType: mediaType, segmentConfigurations: segmentConfigurations, assemblyTrackID: assemblyTrackID)
    }
}
