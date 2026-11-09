import CPerryGeometry
import Glibc
import PerryObjCInterop

// QuartzCore, as UIKit calls it: each view is backed by one of its layers
// (libPerryQuartzCore), whose delegate the view is. A view's geometry,
// visibility and opacity are its layer's, read and set through messages,
// so changing them inside an animation block animates them: the layer
// asks the view for the action (UIView's -actionForLayer:forKey:). The
// live view has QuartzCore composite the windows' layers.

private let quartzCore = "/System/Library/Frameworks/QuartzCore.framework/QuartzCore"

@ObjCWrapper("CALayer")
class CALayer: NSObject {
    @ObjCClassMethod("layer") static func make() -> CALayer
    @ObjCMethod("bounds") func bounds() -> CGRect
    @ObjCMethod("setBounds:") func setBounds(_ bounds: CGRect)
    @ObjCMethod("position") func position() -> CGPoint
    @ObjCMethod("setPosition:") func setPosition(_ position: CGPoint)
    @ObjCMethod("frame") func frame() -> CGRect
    @ObjCMethod("setFrame:") func setFrame(_ frame: CGRect)
    @ObjCMethod("affineTransform") func affineTransform() -> CGAffineTransform
    @ObjCMethod("setAffineTransform:") func setAffineTransform(_ transform: CGAffineTransform)
    @ObjCMethod("isHidden") func isHidden() -> Bool
    @ObjCMethod("setHidden:") func setHidden(_ hidden: Bool)
    @ObjCMethod("opacity") func opacity() -> Float
    @ObjCMethod("setOpacity:") func setOpacity(_ opacity: Float)
    @ObjCMethod("masksToBounds") func masksToBounds() -> Bool
    @ObjCMethod("setMasksToBounds:") func setMasksToBounds(_ masks: Bool)
    @ObjCMethod("cornerRadius") func cornerRadius() -> CGFloat
    @ObjCMethod("mask") func mask() -> NSObject?
    @ObjCMethod("presentationLayer") func presentationLayer() -> CALayer?
    @ObjCMethod("setCornerRadius:") func setCornerRadius(_ radius: CGFloat)
    @ObjCMethod("setZPosition:") func setZPosition(_ z: CGFloat)
    @ObjCMethod("backgroundColor") func backgroundColor() -> UnsafeMutableRawPointer?
    @ObjCMethod("setBackgroundColor:") func setBackgroundColor(_ color: UnsafeMutableRawPointer?)
    @ObjCMethod("contents") func contents() -> NSObject?
    @ObjCMethod("setContents:") func setContents(_ contents: NSObject?)
    /// QuartzCore's: shows RGBA rows, bottom first, without an image.
    @ObjCMethod("_perrySetPixels:width:height:opaque:")
    func setPerryPixels(_ pixels: UnsafeRawPointer?, width: Int, height: Int, opaque: Bool)
    /// QuartzCore's: whether the last of those has been on the screen.
    @ObjCMethod("_perryPixelsShown") func pixelsShown() -> Bool
    /// QuartzCore's: GL frames shared as dma-bufs: the buffers, as records
    /// of seven 64-bit values each; the one getting a new frame, with the
    /// fence that signals when it is finished (given up to the layer; -1
    /// for none); and a mask of the ones in use (-1 when they can't be
    /// imported).
    @ObjCMethod("_perrySetSharedBuffers:count:") func setSharedBuffers(_ records: UnsafeRawPointer?, count: Int)
    @ObjCMethod("_perryPublishSharedSlot:opaque:fence:") func publishSharedSlot(_ slot: Int, opaque: Bool, fence: Int)
    @ObjCMethod("_perrySharedSlotsInUse") func sharedSlotsInUse() -> Int
    @ObjCMethod("contentsScale") func contentsScale() -> CGFloat
    @ObjCMethod("setContentsScale:") func setContentsScale(_ scale: CGFloat)
    @ObjCMethod("contentsGravity") func contentsGravity() -> String
    @ObjCMethod("setContentsGravity:") func setContentsGravity(_ gravity: String)
    @ObjCMethod("isOpaque") func isOpaque() -> Bool
    @ObjCMethod("setOpaque:") func setOpaque(_ opaque: Bool)
    @ObjCMethod("setNeedsDisplay") func setNeedsDisplay()
    @ObjCMethod("setDelegate:") func setDelegate(_ delegate: NSObject?)
    @ObjCMethod("sublayers") func sublayers() -> NSArray?
    @ObjCMethod("addSublayer:") func addSublayer(_ layer: CALayer)
    @ObjCMethod("insertSublayer:below:") func insertSublayer(_ layer: CALayer, below sibling: CALayer?)
    @ObjCMethod("removeFromSuperlayer") func removeFromSuperlayer()
    @ObjCMethod("renderInContext:") func render(in context: UnsafeMutableRawPointer?)
    @ObjCMethod("_perryTransformToSuperlayer") func transformToSuperlayer() -> CGAffineTransform
    @ObjCMethod("addAnimation:forKey:") func addAnimation(_ animation: NSObject, forKey key: String?)
    @ObjCMethod("removeAnimationForKey:") func removeAnimation(forKey key: String)

    /// The position of `layer` among the sublayers.
    func index(of layer: CALayer) -> Int? { sublayers()?.elements.firstIndex { $0.objcObject == layer.objcObject } }
}

@ObjCWrapper("CAEAGLLayer")
class CAEAGLLayer: CALayer {
    @ObjCMethod("drawableProperties") func drawableProperties() -> NSObject?
}

/// The animation a view's layer runs for a change in an animation block.
@ObjCWrapper("CABasicAnimation")
class CABasicAnimation: NSObject {
    @ObjCClassMethod("animationWithKeyPath:") static func make(keyPath: String) -> CABasicAnimation
    @ObjCMethod("setDuration:") func setDuration(_ duration: Double)
    @ObjCMethod("setBeginTime:") func setBeginTime(_ time: Double)
    @ObjCMethod("setTimingFunction:") func setTimingFunction(_ function: NSObject?)
    @ObjCMethod("setFillMode:") func setFillMode(_ mode: String)
    @ObjCMethod("setRepeatCount:") func setRepeatCount(_ count: Float)
    @ObjCMethod("setAutoreverses:") func setAutoreverses(_ autoreverses: Bool)
}

/// Steps through values, as an activity indicator turns.
@ObjCWrapper("CAKeyframeAnimation")
class CAKeyframeAnimation: NSObject {
    @ObjCClassMethod("animationWithKeyPath:") static func make(keyPath: String) -> CAKeyframeAnimation
    @ObjCMethod("setValues:") func setValues(_ values: NSObject?)
    @ObjCMethod("setCalculationMode:") func setCalculationMode(_ mode: String)
    @ObjCMethod("setDuration:") func setDuration(_ duration: Double)
    @ObjCMethod("setRepeatCount:") func setRepeatCount(_ count: Float)
}

@ObjCWrapper("CAMediaTimingFunction")
class CAMediaTimingFunction: NSObject {
    @ObjCClassMethod("functionWithName:") static func named(_ name: String) -> CAMediaTimingFunction
}

@ObjCWrapper("CADisplayLink")
class CADisplayLink: NSObject {
    @ObjCClassMethod("displayLinkWithTarget:selector:") static func make(target: NSObject, selector: ObjCSelector) -> CADisplayLink
}

/// A view's layer, as UIKit's code reads and sets its properties.
final class LayerGeometry {
    let layer: CALayer

    init(_ layer: CALayer) { self.layer = layer }

    var bounds: CGRect {
        get { layer.bounds() }
        set { layer.setBounds(newValue) }
    }

    var position: CGPoint {
        get { layer.position() }
        set { layer.setPosition(newValue) }
    }

    var frame: CGRect {
        get { layer.frame() }
        set { layer.setFrame(newValue) }
    }

    var transform: CGAffineTransform {
        get { layer.affineTransform() }
        set { layer.setAffineTransform(newValue) }
    }

    var hidden: Bool {
        get { layer.isHidden() }
        set { layer.setHidden(newValue) }
    }

    var opacity: Float {
        get { layer.opacity() }
        set { layer.setOpacity(newValue) }
    }

    var masksToBounds: Bool {
        get { layer.masksToBounds() }
        set { layer.setMasksToBounds(newValue) }
    }

    var cornerRadius: CGFloat {
        get { layer.cornerRadius() }
        set { layer.setCornerRadius(newValue) }
    }

    var backgroundColor: UnsafeMutableRawPointer? {
        get { layer.backgroundColor() }
        set { layer.setBackgroundColor(newValue) }
    }

    var contents: NSObject? {
        get { layer.contents() }
        set { layer.setContents(newValue) }
    }

    var contentsScale: CGFloat {
        get { layer.contentsScale() }
        set { layer.setContentsScale(newValue) }
    }

    var contentsGravity: String {
        get { layer.contentsGravity() }
        set { layer.setContentsGravity(newValue) }
    }

    var isOpaque: Bool {
        get { layer.isOpaque() }
        set { layer.setOpaque(newValue) }
    }

    /// Setting it asks the layer to display again.
    var needsDisplay: Bool {
        get { false }
        set { if newValue { layer.setNeedsDisplay() } }
    }

    /// From the layer's coordinates to its superlayer's.
    var toSuperlayer: CGAffineTransform { layer.transformToSuperlayer() }
}

/// QuartzCore's functions for UIKit's live view, bound when UIKit starts.
enum QuartzCore {
    typealias Roots = UnsafePointer<UnsafeMutableRawPointer?>?
    nonisolated(unsafe) static var displayLayers: (@convention(c) (Roots, Int) -> Void)?
    nonisolated(unsafe) static var composite: (@convention(c) (UnsafeMutableRawPointer?, Double, Roots, Int) -> Bool)?
    nonisolated(unsafe) static var needsDisplay: (@convention(c) () -> Bool)?
    nonisolated(unsafe) static var setChangeHandler: (@convention(c) ((@convention(c) () -> Void)?) -> Void)?

    static func load(_ lookup: (String, String) -> UnsafeMutableRawPointer?) -> Bool {
        func bind<T>(_ name: String, _ type: T.Type) -> T? { lookup(quartzCore, name).map { unsafeBitCast($0, to: T.self) } }
        displayLayers = bind("_PerryCADisplayLayers", (@convention(c) (Roots, Int) -> Void).self)
        composite = bind("_PerryCAComposite", (@convention(c) (UnsafeMutableRawPointer?, Double, Roots, Int) -> Bool).self)
        needsDisplay = bind("_PerryCANeedsDisplay", (@convention(c) () -> Bool).self)
        setChangeHandler = bind("_PerryCASetChangeHandler", (@convention(c) ((@convention(c) () -> Void)?) -> Void).self)
        // A change to layers draws the live view and the snapshot again.
        setChangeHandler?({ Display.layersChanged() })
        return displayLayers != nil && composite != nil && needsDisplay != nil
    }

    /// Calls `body` with the windows' layers, as the functions take them.
    static func withRoots<T>(_ windows: [UIWindow], _ body: (Roots, Int) -> T) -> T {
        let roots: [UnsafeMutableRawPointer?] = windows.map { $0.state.layer.objcObject }
        return roots.withUnsafeBufferPointer { body($0.baseAddress, $0.count) }
    }
}

/// Method lookups, to tell whether a class overrides a method.
enum Methods {
    typealias Implementation = @convention(c) (UnsafeMutableRawPointer?, UnsafeRawPointer?) -> UnsafeRawPointer?
    nonisolated(unsafe) static var implementation: Implementation!

    /// Whether `object`'s class implements `selector` other than as `base`
    /// does.
    static func overrides(_ object: UnsafeMutableRawPointer, _ selector: String, of base: UnsafeMutableRawPointer) -> Bool {
        let sel = ObjCRuntime.selector(selector)
        return implementation(ObjCRuntime.objectClass(object), sel) != implementation(base, sel)
    }
}

/// A rounded rectangle path, +1 and owned, for UIKit's drawing. Corners as
/// UIRectCorner: top left 1, top right 2, bottom left 4, bottom right 8.
func roundedRectPath(_ rect: CGRect, radius: CGFloat, corners: UInt) -> Owned? {
    guard let path = CG.pathCreateMutable() else { return nil }
    UIBezierPath.addRoundedRect(path, rect, corners: corners, radii: CGSize(width: radius, height: radius))
    return Owned(path)
}

/// CALayer's messages to its delegate and subclasses, sent from UIKit.
extension NSObject {
    @ObjCMethod("init") func initializeLayer() -> NSObject
}
