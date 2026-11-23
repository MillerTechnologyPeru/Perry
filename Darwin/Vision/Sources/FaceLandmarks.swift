import Foundation

// Vision's Swift API over the C arrays and NSNumbers of its face
// observations: points as Swift arrays, scores as Floats.

/// The selector-level getters these properties shadow, reached as an
/// Objective-C protocol the observations answer to.
@objc private protocol LandmarkRegionPoints {
    var normalizedPoints: UnsafePointer<CGPoint>? { get }
    @objc(pointsInImageOfSize:) func pointsInImage(ofSize imageSize: CGSize) -> UnsafePointer<CGPoint>?
    @objc optional var precisionEstimatesPerPoint: [NSNumber]? { get }
}

@objc private protocol FaceCaptureQuality {
    @objc optional var faceCaptureQuality: NSNumber? { get }
}

@available(macOS 10.13, iOS 11.0, tvOS 11.0, *)
@available(watchOS, unavailable)
extension VNFaceLandmarkRegion2D {
    private var points: LandmarkRegionPoints {
        unsafeBitCast(self, to: LandmarkRegionPoints.self)
    }

    /// The region's pointCount points from `start`, copied.
    private func array(_ start: UnsafePointer<CGPoint>?) -> [CGPoint] {
        guard let start else { return [] }
        return Array(UnsafeBufferPointer(start: start, count: pointCount))
    }

    @nonobjc public var normalizedPoints: [CGPoint] {
        array(points.normalizedPoints)
    }

    @nonobjc public func pointsInImage(imageSize: CGSize) -> [CGPoint] {
        array(points.pointsInImage(ofSize: imageSize))
    }

    @available(macOS 10.15, iOS 13.0, tvOS 13.0, *)
    @available(watchOS, unavailable)
    @nonobjc public var precisionEstimatesPerPoint: [Float]? {
        points.precisionEstimatesPerPoint??.map { $0.floatValue }
    }
}

@available(macOS 10.15, iOS 13.0, tvOS 13.0, *)
@available(watchOS, unavailable)
extension VNFaceObservation {
    @nonobjc public var faceCaptureQuality: Float? {
        unsafeBitCast(self, to: FaceCaptureQuality.self).faceCaptureQuality??.floatValue
    }
}
