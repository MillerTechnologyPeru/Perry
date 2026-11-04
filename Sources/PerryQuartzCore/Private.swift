import CPerryGeometry
import PerryObjCInterop

// Core Animation's private functions that SwiftUI calls, and the gradient
// layer, which keeps its properties but draws as a plain layer.

/// The layer's superlayer, not retained.
@c(_CALayerGetSuperlayer)
public func CALayerGetSuperlayer(_ layer: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer? {
    layer.flatMap { CALayer.state(of: $0).superlayer }
}

/// Maps geometry from `from` (an ancestor) down to `to`: calls `unmap` with
/// each layer's transform to its superlayer, from `to` up to `from`.
/// Without a common ancestor nothing is mapped.
@c(_CALayerMapGeometry)
public func CALayerMapGeometry(
    _ from: UnsafeMutableRawPointer?, _ to: UnsafeMutableRawPointer?,
    _ map: (@convention(c) (UnsafeMutableRawPointer?, UnsafePointer<CATransform3D>) -> Void)?,
    _ unmap: (@convention(c) (UnsafeMutableRawPointer?, UnsafePointer<CATransform3D>) -> Void)?,
    _ context: UnsafeMutableRawPointer?
) {
    var chain: [UnsafeMutableRawPointer] = []
    var current = to
    while let layer = current, layer != from {
        chain.append(layer)
        current = CALayer.state(of: layer).superlayer
    }
    guard current == from || from == nil else { return }
    for layer in chain {
        let state = CALayer.state(of: layer)
        var transform = CATransform3D(state.toSuperlayer(within: state.superlayer.map { CALayer.state(of: $0) }))
        withUnsafePointer(to: &transform) { unmap?(context, $0) }
    }
}

/// Whether two CAFrameRateRange values (three floats each, passed in
/// floating point registers) are the same.
@c(_CAFrameRateRangeIsEqualToRange)
public func CAFrameRateRangeIsEqualToRange(_ minimum: Float, _ maximum: Float, _ preferred: Float,
                                           _ otherMinimum: Float, _ otherMaximum: Float, _ otherPreferred: Float) -> Bool {
    minimum == otherMinimum && maximum == otherMaximum && preferred == otherPreferred
}

// MARK: - CAGradientLayer

final class GradientLayerState {
    var colors: NSObject?
    var locations: NSObject?
    var startPoint = CGPoint(x: 0.5, y: 0)
    var endPoint = CGPoint(x: 0.5, y: 1)
    var type = "axial"
}

/// CAGradientLayer: keeps its colors, locations and points; the gradient
/// is not drawn.
@ObjCClass("CAGradientLayer")
open class CAGradientLayer: CALayer {
    var gradient = GradientLayerState()

    @ObjCMethod("init")
    public required init() { super.init() }

    @ObjCMethod("initWithLayer:")
    public required init(layer: CALayer) { super.init(layer: layer) }

    @ObjCMethod("colors") func colors() -> NSObject? { gradient.colors }
    @ObjCMethod("setColors:") func setColors(_ colors: NSObject?) { changed { gradient.colors = colors } }
    @ObjCMethod("locations") func locations() -> NSObject? { gradient.locations }
    @ObjCMethod("setLocations:") func setLocations(_ locations: NSObject?) { changed { gradient.locations = locations } }
    @ObjCMethod("startPoint") func startPoint() -> CGPoint { gradient.startPoint }
    @ObjCMethod("setStartPoint:") func setStartPoint(_ point: CGPoint) { changed { gradient.startPoint = point } }
    @ObjCMethod("endPoint") func endPoint() -> CGPoint { gradient.endPoint }
    @ObjCMethod("setEndPoint:") func setEndPoint(_ point: CGPoint) { changed { gradient.endPoint = point } }
    @ObjCMethod("type") func type() -> String { gradient.type }
    @ObjCMethod("setType:") func setType(_ type: String) { changed { gradient.type = type } }
}
