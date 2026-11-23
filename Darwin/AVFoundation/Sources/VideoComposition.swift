import Foundation
import CoreMedia
import CoreVideo
import CoreGraphics
import CoreImage
import QuartzCore

// Video compositions described by Swift values: AVVideoComposition and
// its instructions made from configurations (over the mutable classes,
// whose copies the initializers hand back), spatial video, Core Image
// filtering with async appliers, and the compositor request's tagged and
// read-only buffers.

/// Lets a convenience initializer hand back another object than the one
/// allocated: an initializer of a protocol extension may assign self.
protocol _AVReplacingInitializable {}

extension _AVReplacingInitializable {
    /// Self as the given object, which must be of Self's class.
    init(_replacing object: AnyObject) {
        self = object as! Self
    }
}

extension AVVideoComposition: _AVReplacingInitializable {}
extension AVVideoCompositionInstruction: _AVReplacingInitializable {}
extension AVVideoCompositionLayerInstruction: _AVReplacingInitializable {}
extension AVVideoCompositionCoreAnimationTool: _AVReplacingInitializable {}

// MARK: - Spatial video

@available(macOS 26.0, iOS 26.0, tvOS 26.0, visionOS 26.0, *)
@available(watchOS, unavailable)
public struct AVSpatialVideoConfiguration: Sendable {
    public var cameraCalibrationDataLensCollection: CMFormatDescription.Extensions.Value.CameraCalibrationDataLensCollection?
    public var horizontalFieldOfView: UInt32?
    public var cameraSystemBaseline: UInt32?
    public var disparityAdjustment: Int32?

    public init() {}

    public init(formatDescription: CMFormatDescription) {
        self.init(__AVSpatialVideoConfiguration(formatDescription: formatDescription))
    }

    /// The values of the Objective-C configuration.
    init(_ object: __AVSpatialVideoConfiguration) {
        if let lenses = object.cameraCalibrationDataLensCollection {
            cameraCalibrationDataLensCollection = .init(rawValue: lenses as CFArray)
        }
        horizontalFieldOfView = object.horizontalFieldOfView?.uint32Value
        cameraSystemBaseline = object.cameraSystemBaseline?.uint32Value
        disparityAdjustment = object.disparityAdjustment?.int32Value
    }

    /// The configuration as Objective-C's.
    var object: __AVSpatialVideoConfiguration {
        let object = __AVSpatialVideoConfiguration()
        object.cameraCalibrationDataLensCollection = cameraCalibrationDataLensCollection.map { $0.rawValue as! [[String: Any]] }
        object.horizontalFieldOfView = horizontalFieldOfView.map { NSNumber(value: $0) }
        object.cameraSystemBaseline = cameraSystemBaseline.map { NSNumber(value: $0) }
        object.disparityAdjustment = disparityAdjustment.map { NSNumber(value: $0) }
        return object
    }
}

@available(macOS 26.0, iOS 26.0, tvOS 26.0, visionOS 26.0, *)
@available(watchOS, unavailable)
extension AVSpatialVideoConfiguration {
    /// A configuration of no spatial values: the video isn't spatial.
    public static var nonSpatial: AVSpatialVideoConfiguration { AVSpatialVideoConfiguration() }
}

// MARK: - Compositions

@available(macOS 12.0, iOS 15.0, tvOS 15.0, visionOS 1, *)
@available(watchOS, unavailable)
extension AVVideoComposition {
    @objc(_sourceSampleDataTrackIDs)
    public dynamic var sourceSampleDataTrackIDs: [CMPersistentTrackID] {
        __sourceSampleDataTrackIDs.map { $0.int32Value }
    }

    @available(macOS 26.0, iOS 26.0, tvOS 26.0, visionOS 26.0, *)
    public var outputBufferDescription: [[CMTag]]? {
        __outputBufferDescription.map(tagArrays)
    }

    @available(macOS 26.0, iOS 26.0, tvOS 26.0, visionOS 26.0, *)
    public var spatialVideoConfigurations: [AVSpatialVideoConfiguration] {
        __spatialVideoConfigurations.map(AVSpatialVideoConfiguration.init)
    }
}

@available(macOS 12.0, iOS 15.0, tvOS 15.0, visionOS 1, *)
@available(watchOS, unavailable)
extension AVMutableVideoComposition {
    @objc(_sourceSampleDataTrackIDs)
    public override dynamic var sourceSampleDataTrackIDs: [CMPersistentTrackID] {
        @objc get { __sourceSampleDataTrackIDs.map { $0.int32Value } }
        @objc set { __sourceSampleDataTrackIDs = newValue.map { NSNumber(value: $0) } }
    }
}

@available(macOS 26.0, iOS 26.0, tvOS 26.0, visionOS 26.0, *)
@available(watchOS, unavailable)
public struct AVCIImageFilteringParameters {
    public let sourceImage: CIImage
    public let compositionTime: CMTime
    public let renderSize: CGSize
}

@available(macOS 26.0, iOS 26.0, tvOS 26.0, visionOS 26.0, *)
@available(watchOS, unavailable)
public struct AVCIImageFilteringResult {
    public let resultImage: CIImage
    public let ciContext: CIContext?

    public init(resultImage: CIImage, ciContext: CIContext? = nil) {
        self.resultImage = resultImage
        self.ciContext = ciContext
    }
}

/// A value carried across a Sendable boundary that AVFoundation makes safe.
struct _AVUnsafeSendable<Value>: @unchecked Sendable {
    let value: Value
}

@available(macOS 26.0, iOS 26.0, tvOS 26.0, visionOS 26.0, *)
@available(watchOS, unavailable)
extension AVVideoComposition {
    /// A composition filtering each frame of the asset's video with an async
    /// applier, each request answered when its task finishes.
    nonisolated(nonsending) public convenience init(applyingFiltersTo asset: AVAsset, applier: @escaping @Sendable (AVCIImageFilteringParameters) async throws -> AVCIImageFilteringResult) async throws {
        let composition: AVVideoComposition = try await withCheckedThrowingContinuation { continuation in
            AVVideoComposition.videoComposition(with: asset, applyingCIFiltersWithHandler: { request in
                let parameters = AVCIImageFilteringParameters(sourceImage: request.sourceImage, compositionTime: request.compositionTime, renderSize: request.renderSize)
                let sendable = _AVUnsafeSendable(value: request)
                Task {
                    do {
                        let result = try await applier(parameters)
                        sendable.value.finish(with: result.resultImage, context: result.ciContext)
                    } catch {
                        sendable.value.finish(with: error)
                    }
                }
            }, completionHandler: { composition, error in
                if let composition {
                    continuation.resume(returning: composition)
                } else {
                    continuation.resume(throwing: error ?? NSError(domain: AVFoundationErrorDomain, code: AVError.Code.unknown.rawValue))
                }
            })
        }
        self.init(_replacing: Self.isMutable ? composition.mutableCopy() as AnyObject : composition)
    }

    /// Whether this class is the mutable one, whose initializers hand back
    /// mutable copies.
    static var isMutable: Bool { self is AVMutableVideoComposition.Type }

    public struct Configuration: Sendable {
        private var animationToolValue: _AVUnsafeSendable<AVVideoCompositionCoreAnimationTool?>
        private var instructionsValue: _AVUnsafeSendable<[any AVVideoCompositionInstructionProtocol]>
        private var compositorValue: _AVUnsafeSendable<(any AVVideoCompositing.Type)?>

        public var animationTool: AVVideoCompositionCoreAnimationTool? {
            get { animationToolValue.value }
            set { animationToolValue = _AVUnsafeSendable(value: newValue) }
        }

        public var colorPrimaries: String?
        public var colorTransferFunction: String?
        public var colorYCbCrMatrix: String?

        public var customVideoCompositorClass: (any AVVideoCompositing.Type)? {
            get { compositorValue.value }
            set { compositorValue = _AVUnsafeSendable(value: newValue) }
        }

        public var frameDuration: CMTime

        public var instructions: [any AVVideoCompositionInstructionProtocol] {
            get { instructionsValue.value }
            set { instructionsValue = _AVUnsafeSendable(value: newValue) }
        }

        public var outputBufferDescription: [[CMTag]]?
        public var spatialVideoConfigurations: [AVSpatialVideoConfiguration]
        public var perFrameHDRDisplayMetadataPolicy: AVVideoComposition.PerFrameHDRDisplayMetadataPolicy
        public var renderScale: Float
        public var renderSize: CGSize
        public var sourceSampleDataTrackIDs: [CMPersistentTrackID]
        public var sourceTrackIDForFrameTiming: CMPersistentTrackID

        /// The configuration of a composition of the asset's video tracks.
        nonisolated(nonsending) public init(for asset: AVAsset, prototypeInstruction: AVVideoCompositionInstruction? = nil) async throws {
            let composition: AVVideoComposition
            if let prototypeInstruction {
                composition = try await AVMutableVideoComposition.videoComposition(withPropertiesOf: asset, prototypeInstruction: prototypeInstruction)
            } else {
                composition = try await AVMutableVideoComposition.videoComposition(withPropertiesOf: asset)
            }
            self.init(composition)
        }

        public init(animationTool: AVVideoCompositionCoreAnimationTool? = nil, colorPrimaries: String? = nil, colorTransferFunction: String? = nil, colorYCbCrMatrix: String? = nil, customVideoCompositorClass: (any AVVideoCompositing.Type)? = nil, frameDuration: CMTime = CMTime.zero, instructions: [any AVVideoCompositionInstructionProtocol] = [any AVVideoCompositionInstructionProtocol](), outputBufferDescription: [[CMTag]]? = nil, perFrameHDRDisplayMetadataPolicy: AVVideoComposition.PerFrameHDRDisplayMetadataPolicy = .propagate, renderScale: Float = 1.0, renderSize: CGSize = .zero, sourceSampleDataTrackIDs: [CMPersistentTrackID] = [CMPersistentTrackID](), sourceTrackIDForFrameTiming: Int32 = CMPersistentTrackID.zero, spatialVideoConfigurations: [AVSpatialVideoConfiguration] = []) {
            animationToolValue = _AVUnsafeSendable(value: animationTool)
            instructionsValue = _AVUnsafeSendable(value: instructions)
            compositorValue = _AVUnsafeSendable(value: customVideoCompositorClass)
            self.colorPrimaries = colorPrimaries
            self.colorTransferFunction = colorTransferFunction
            self.colorYCbCrMatrix = colorYCbCrMatrix
            self.frameDuration = frameDuration
            self.outputBufferDescription = outputBufferDescription
            self.perFrameHDRDisplayMetadataPolicy = perFrameHDRDisplayMetadataPolicy
            self.renderScale = renderScale
            self.renderSize = renderSize
            self.sourceSampleDataTrackIDs = sourceSampleDataTrackIDs
            self.sourceTrackIDForFrameTiming = sourceTrackIDForFrameTiming
            self.spatialVideoConfigurations = spatialVideoConfigurations
        }

        /// The configuration of an existing composition.
        init(_ composition: AVVideoComposition) {
            self.init(animationTool: composition.animationTool, colorPrimaries: composition.colorPrimaries, colorTransferFunction: composition.colorTransferFunction, colorYCbCrMatrix: composition.colorYCbCrMatrix, customVideoCompositorClass: composition.customVideoCompositorClass, frameDuration: composition.frameDuration, instructions: composition.instructions, outputBufferDescription: composition.outputBufferDescription, perFrameHDRDisplayMetadataPolicy: composition.perFrameHDRDisplayMetadataPolicy, renderScale: composition.renderScale, renderSize: composition.renderSize, sourceSampleDataTrackIDs: composition.sourceSampleDataTrackIDs, sourceTrackIDForFrameTiming: composition.sourceTrackIDForFrameTiming, spatialVideoConfigurations: composition.spatialVideoConfigurations)
        }

        /// A mutable composition of the configuration.
        func makeComposition() -> AVMutableVideoComposition {
            let composition = AVMutableVideoComposition()
            composition.animationTool = animationTool
            composition.colorPrimaries = colorPrimaries
            composition.colorTransferFunction = colorTransferFunction
            composition.colorYCbCrMatrix = colorYCbCrMatrix
            composition.customVideoCompositorClass = customVideoCompositorClass
            composition.frameDuration = frameDuration
            composition.instructions = instructions
            composition.__outputBufferDescription = outputBufferDescription.map(tagCollections)
            composition.perFrameHDRDisplayMetadataPolicy = perFrameHDRDisplayMetadataPolicy
            composition.renderScale = renderScale
            composition.renderSize = renderSize
            composition.sourceSampleDataTrackIDs = sourceSampleDataTrackIDs
            composition.sourceTrackIDForFrameTiming = sourceTrackIDForFrameTiming
            if !spatialVideoConfigurations.isEmpty {
                composition.setValue(spatialVideoConfigurations.map { $0.object }, forKey: "spatialVideoConfigurations")
            }
            return composition
        }
    }

    public convenience init(configuration: AVVideoComposition.Configuration) {
        let composition = configuration.makeComposition()
        self.init(_replacing: Self.isMutable ? composition : composition.copy() as AnyObject)
    }
}

// MARK: - Instructions

@available(macOS 26.0, iOS 26.0, tvOS 26.0, visionOS 26.0, *)
@available(watchOS, unavailable)
extension AVVideoCompositionInstruction {
    public struct Configuration: Sendable {
        private var background: _AVUnsafeSendable<CGColor?>
        private var layers: _AVUnsafeSendable<[AVVideoCompositionLayerInstruction]>

        public var backgroundColor: CGColor? {
            get { background.value }
            set { background = _AVUnsafeSendable(value: newValue) }
        }

        public var enablePostProcessing: Bool

        public var layerInstructions: [AVVideoCompositionLayerInstruction] {
            get { layers.value }
            set { layers = _AVUnsafeSendable(value: newValue) }
        }

        public var requiredSourceSampleDataTrackIDs: [CMPersistentTrackID]
        public var timeRange: CMTimeRange

        public init(backgroundColor: CGColor? = nil, enablePostProcessing: Bool = true, layerInstructions: [AVVideoCompositionLayerInstruction] = [], requiredSourceSampleDataTrackIDs: [CMPersistentTrackID] = [], timeRange: CMTimeRange = .zero) {
            background = _AVUnsafeSendable(value: backgroundColor)
            layers = _AVUnsafeSendable(value: layerInstructions)
            self.enablePostProcessing = enablePostProcessing
            self.requiredSourceSampleDataTrackIDs = requiredSourceSampleDataTrackIDs
            self.timeRange = timeRange
        }
    }

    public convenience init(configuration: AVVideoCompositionInstruction.Configuration) {
        let instruction = AVMutableVideoCompositionInstruction()
        instruction.backgroundColor = configuration.backgroundColor
        instruction.enablePostProcessing = configuration.enablePostProcessing
        instruction.layerInstructions = configuration.layerInstructions
        instruction.requiredSourceSampleDataTrackIDs = configuration.requiredSourceSampleDataTrackIDs.map { NSNumber(value: $0) }
        instruction.timeRange = configuration.timeRange
        self.init(_replacing: Self.self is AVMutableVideoCompositionInstruction.Type ? instruction : instruction.copy() as AnyObject)
    }
}

@available(macOS 26.0, iOS 26.0, tvOS 26.0, visionOS 26.0, *)
@available(watchOS, unavailable)
extension AVVideoCompositionLayerInstruction {
    public struct CropRectangleRamp: Equatable, Sendable {
        public var timeRange: CMTimeRange
        public var start: CGRect
        public var end: CGRect

        public init(timeRange: CMTimeRange, start: CGRect, end: CGRect) {
            self.timeRange = timeRange
            self.start = start
            self.end = end
        }

        public static func == (a: CropRectangleRamp, b: CropRectangleRamp) -> Bool {
            a.timeRange == b.timeRange && a.start == b.start && a.end == b.end
        }
    }

    public struct OpacityRamp: Equatable, Sendable {
        public var timeRange: CMTimeRange
        public var start: Float
        public var end: Float

        public init(timeRange: CMTimeRange, start: Float, end: Float) {
            self.timeRange = timeRange
            self.start = start
            self.end = end
        }

        public static func == (a: OpacityRamp, b: OpacityRamp) -> Bool {
            a.timeRange == b.timeRange && a.start == b.start && a.end == b.end
        }
    }

    public struct TransformRamp: Equatable, Sendable {
        public var timeRange: CMTimeRange
        public var start: CGAffineTransform
        public var end: CGAffineTransform

        public init(timeRange: CMTimeRange, start: CGAffineTransform, end: CGAffineTransform) {
            self.timeRange = timeRange
            self.start = start
            self.end = end
        }

        public static func == (a: TransformRamp, b: TransformRamp) -> Bool {
            a.timeRange == b.timeRange && a.start == b.start && a.end == b.end
        }
    }

    public func cropRectangleRamp(at time: CMTime) -> AVVideoCompositionLayerInstruction.CropRectangleRamp? {
        var start = CGRect.zero, end = CGRect.zero, range = CMTimeRange.invalid
        guard getCropRectangleRamp(for: time, startCropRectangle: &start, endCropRectangle: &end, timeRange: &range) else { return nil }
        return CropRectangleRamp(timeRange: range, start: start, end: end)
    }

    public func opacityRamp(at time: CMTime) -> AVVideoCompositionLayerInstruction.OpacityRamp? {
        var start: Float = 0, end: Float = 0, range = CMTimeRange.invalid
        guard getOpacityRamp(for: time, startOpacity: &start, endOpacity: &end, timeRange: &range) else { return nil }
        return OpacityRamp(timeRange: range, start: start, end: end)
    }

    public func transformRamp(at time: CMTime) -> AVVideoCompositionLayerInstruction.TransformRamp? {
        var start = CGAffineTransform.identity, end = CGAffineTransform.identity, range = CMTimeRange.invalid
        guard getTransformRamp(for: time, start: &start, end: &end, timeRange: &range) else { return nil }
        return TransformRamp(timeRange: range, start: start, end: end)
    }

    /// A layer instruction's track and its ramps, set at a time (a ramp
    /// from a value to itself, held until the next) or over a range.
    public struct Configuration: Sendable {
        public var trackID: CMPersistentTrackID {
            get { track }
            set { track = newValue }
        }

        private var track: CMPersistentTrackID
        private var opacityRamps: [OpacityRamp] = []
        private var transformRamps: [TransformRamp] = []
        private var cropRamps: [CropRectangleRamp] = []

        public init(trackID: CMPersistentTrackID = .zero) {
            track = trackID
        }

        public init(assetTrack: AVAssetTrack) {
            track = assetTrack.trackID
        }

        /// The ramp in effect at a time: the last that starts at or before it.
        private static func ramp<Ramp>(_ ramps: [Ramp], at time: CMTime, range: (Ramp) -> CMTimeRange) -> Ramp? {
            ramps.filter { range($0).start <= time }.max { range($0).start < range($1).start }
        }

        public func cropRectangleRamp(at time: CMTime) -> AVVideoCompositionLayerInstruction.CropRectangleRamp? {
            Self.ramp(cropRamps, at: time) { $0.timeRange }
        }

        public func opacityRamp(at time: CMTime) -> AVVideoCompositionLayerInstruction.OpacityRamp? {
            Self.ramp(opacityRamps, at: time) { $0.timeRange }
        }

        public func transformRamp(at time: CMTime) -> AVVideoCompositionLayerInstruction.TransformRamp? {
            Self.ramp(transformRamps, at: time) { $0.timeRange }
        }

        /// A value set at a time: held from it on.
        private static func held(at time: CMTime) -> CMTimeRange {
            CMTimeRange(start: time, duration: .positiveInfinity)
        }

        public mutating func setOpacity(_ opacity: Float, at time: CMTime) {
            opacityRamps.append(OpacityRamp(timeRange: Self.held(at: time), start: opacity, end: opacity))
        }

        public mutating func addOpacityRamp(_ ramp: AVVideoCompositionLayerInstruction.OpacityRamp) {
            opacityRamps.append(ramp)
        }

        public mutating func setTransform(_ transform: CGAffineTransform, at time: CMTime) {
            transformRamps.append(TransformRamp(timeRange: Self.held(at: time), start: transform, end: transform))
        }

        public mutating func addTransformRamp(_ ramp: AVVideoCompositionLayerInstruction.TransformRamp) {
            transformRamps.append(ramp)
        }

        public mutating func setCropRectangle(_ rect: CGRect, at time: CMTime) {
            cropRamps.append(CropRectangleRamp(timeRange: Self.held(at: time), start: rect, end: rect))
        }

        public mutating func addCropRectangleRamp(_ ramp: AVVideoCompositionLayerInstruction.CropRectangleRamp) {
            cropRamps.append(ramp)
        }

        /// A mutable layer instruction of the configuration.
        func makeInstruction() -> AVMutableVideoCompositionLayerInstruction {
            let instruction = AVMutableVideoCompositionLayerInstruction()
            instruction.trackID = track
            for ramp in opacityRamps {
                if ramp.timeRange.duration.isPositiveInfinity {
                    instruction.setOpacity(ramp.start, at: ramp.timeRange.start)
                } else {
                    instruction.setOpacityRamp(fromStartOpacity: ramp.start, toEndOpacity: ramp.end, timeRange: ramp.timeRange)
                }
            }
            for ramp in transformRamps {
                if ramp.timeRange.duration.isPositiveInfinity {
                    instruction.setTransform(ramp.start, at: ramp.timeRange.start)
                } else {
                    instruction.setTransformRamp(fromStart: ramp.start, toEnd: ramp.end, timeRange: ramp.timeRange)
                }
            }
            for ramp in cropRamps {
                if ramp.timeRange.duration.isPositiveInfinity {
                    instruction.setCropRectangle(ramp.start, at: ramp.timeRange.start)
                } else {
                    instruction.setCropRectangleRamp(fromStartCropRectangle: ramp.start, toEndCropRectangle: ramp.end, timeRange: ramp.timeRange)
                }
            }
            return instruction
        }
    }

    public convenience init(configuration: AVVideoCompositionLayerInstruction.Configuration) {
        let instruction = configuration.makeInstruction()
        self.init(_replacing: Self.self is AVMutableVideoCompositionLayerInstruction.Type ? instruction : instruction.copy() as AnyObject)
    }
}

@available(macOS 26.0, iOS 26.0, tvOS 26.0, visionOS 26.0, *)
@available(watchOS, unavailable)
extension AVVideoCompositionCoreAnimationTool {
    public struct Configuration {
        public var layers: [CALayer]
        public var containingLayer: CALayer

        public init(postProcessingAsVideoLayers layers: [CALayer], containingLayer: CALayer) {
            self.layers = layers
            self.containingLayer = containingLayer
        }

        public init(postProcessingAsVideoLayer layer: CALayer, containingLayer: CALayer) {
            self.init(postProcessingAsVideoLayers: [layer], containingLayer: containingLayer)
        }
    }

    public convenience init(configuration: sending AVVideoCompositionCoreAnimationTool.Configuration) {
        self.init(_replacing: AVVideoCompositionCoreAnimationTool(postProcessingAsVideoLayers: configuration.layers, in: configuration.containingLayer))
    }
}

// MARK: - Compositor requests

@available(macOS 12.0, iOS 15.0, tvOS 15.0, visionOS 1, *)
@available(watchOS, unavailable)
extension AVAsynchronousVideoCompositionRequest {
    @nonobjc public var sourceSampleDataTrackIDs: [CMPersistentTrackID] {
        __sourceSampleDataTrackIDs.map { $0.int32Value }
    }
}

@available(macOS 26.0, iOS 26.0, tvOS 26.0, visionOS 26.0, *)
@available(watchOS, unavailable)
extension AVAsynchronousVideoCompositionRequest {
    public func sourceTaggedDynamicBuffers(byTrackID trackID: CMPersistentTrackID) -> [CMTaggedDynamicBuffer]? {
        __sourceTaggedBufferGroup(byTrackID: trackID).map(taggedDynamicBuffers)
    }

    public func sourceReadOnlyPixelBuffer(byTrackID trackID: CMPersistentTrackID) -> CVReadOnlyPixelBuffer? {
        sourceFrame(byTrackID: trackID).map { CVReadOnlyPixelBuffer(unsafeBuffer: $0) }
    }

    public func sourceReadySampleBuffer(byTrackID trackID: CMPersistentTrackID) -> CMReadySampleBuffer<CMSampleBuffer.DynamicContent>? {
        sourceSampleBuffer(byTrackID: trackID).map { CMReadySampleBuffer(unsafeBuffer: $0) }
    }

    public func finish(withComposedPixelBuffer readOnlyPixelBuffer: CVReadOnlyPixelBuffer) {
        readOnlyPixelBuffer.withUnsafeBuffer { finish(withComposedVideoFrame: $0) }
    }

    public func finish(withComposedTaggedBuffers taggedBuffers: [CMTaggedDynamicBuffer]) {
        if let group = taggedBufferGroup(taggedBuffers) {
            __finish(withComposedTaggedBufferGroup: group)
        } else {
            finish(with: NSError(domain: AVFoundationErrorDomain, code: AVError.Code.unknown.rawValue))
        }
    }

    public func attach(_ spatialVideoConfiguration: AVSpatialVideoConfiguration, to pixelBuffer: inout CVMutablePixelBuffer) throws {
        let object = spatialVideoConfiguration.object
        pixelBuffer.withUnsafeBuffer { __attach(object, to: $0) }
    }
}

@available(macOS 26.0, iOS 26.0, tvOS 26.0, visionOS 26.0, *)
@available(watchOS, unavailable)
extension AVVideoCompositionRenderContext {
    public func makeMutablePixelBuffer() throws -> CVMutablePixelBuffer {
        guard let buffer = newPixelBuffer() else {
            throw NSError(domain: AVFoundationErrorDomain, code: AVError.Code.outOfMemory.rawValue)
        }
        return CVMutablePixelBuffer(unsafeBuffer: buffer)
    }
}

@available(macOS 14, iOS 17, visionOS 1, *)
@available(tvOS, unavailable)
@available(watchOS, unavailable)
extension AVAssetWriterInputTaggedPixelBufferGroupAdaptor {
    public func appendTaggedBuffers(_ taggedBuffers: [CMTaggedBuffer], withPresentationTime: CMTime) -> Bool {
        guard let group = taggedBufferGroup(taggedBuffers) else { return false }
        return appendTaggedPixelBufferGroup(group, withPresentationTime: withPresentationTime)
    }
}
