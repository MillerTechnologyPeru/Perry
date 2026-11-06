import CPerryGeometry
import PerryObjCInterop

// QuartzCore, as AppKit calls it: the layers views are backed by, and the
// functions that display and composite a window's layer tree into its SDL
// renderer, which UIKit's live view uses too.

@ObjCWrapper("CALayer")
class CALayer: NSObject {
    @ObjCClassMethod("layer") static func make() -> CALayer
    @ObjCMethod("frame") func frame() -> CGRect
    @ObjCMethod("setFrame:") func setFrame(_ frame: CGRect)
    @ObjCMethod("bounds") func bounds() -> CGRect
    @ObjCMethod("setBounds:") func setBounds(_ bounds: CGRect)
    @ObjCMethod("setPosition:") func setPosition(_ position: CGPoint)
    @ObjCMethod("setAnchorPoint:") func setAnchorPoint(_ point: CGPoint)
    @ObjCMethod("addSublayer:") func addSublayer(_ layer: NSObject)
    @ObjCMethod("insertSublayer:atIndex:") func insertSublayer(_ layer: NSObject, at index: UInt32)
    @ObjCMethod("removeFromSuperlayer") func removeFromSuperlayer()
    @ObjCMethod("superlayer") func superlayer() -> NSObject?
    @ObjCMethod("setContents:") func setContents(_ contents: NSObject?)
    @ObjCMethod("setContentsScale:") func setContentsScale(_ scale: CGFloat)
    @ObjCMethod("setHidden:") func setHidden(_ hidden: Bool)
    @ObjCMethod("setNeedsDisplay") func setNeedsDisplay()
    @ObjCMethod("setMasksToBounds:") func setMasksToBounds(_ masks: Bool)
    @ObjCMethod("setDelegate:") func setDelegate(_ delegate: NSObject?)
    @ObjCMethod("setBackgroundColor:") func setBackgroundColor(_ color: UnsafeMutableRawPointer?)
}

@ObjCWrapper("CATransaction")
class CATransaction: NSObject {
    @ObjCClassMethod("begin") static func begin()
    @ObjCClassMethod("commit") static func commit()
    @ObjCClassMethod("setDisableActions:") static func setDisableActions(_ disable: Bool)

    /// Changes layers without implicit animations, as AppKit's own layout does.
    static func withoutActions(_ body: () -> Void) {
        begin()
        setDisableActions(true)
        body()
        commit()
    }
}

/// QuartzCore's functions for compositing, bound when AppKit starts.
enum QuartzCore {
    typealias Roots = UnsafePointer<UnsafeMutableRawPointer?>?
    nonisolated(unsafe) static var displayLayers: (@convention(c) (Roots, Int) -> Void)?
    nonisolated(unsafe) static var composite: (@convention(c) (UnsafeMutableRawPointer?, Double, Roots, Int) -> Bool)?
    nonisolated(unsafe) static var needsDisplay: (@convention(c) () -> Bool)?
    nonisolated(unsafe) static var setChangeHandler: (@convention(c) ((@convention(c) () -> Void)?) -> Void)?

    static func load(_ lookup: (String) -> UnsafeMutableRawPointer?) -> Bool {
        func bind<T>(_ name: String, _ type: T.Type) -> T? { lookup(name).map { unsafeBitCast($0, to: T.self) } }
        displayLayers = bind("_PerryCADisplayLayers", (@convention(c) (Roots, Int) -> Void).self)
        composite = bind("_PerryCAComposite", (@convention(c) (UnsafeMutableRawPointer?, Double, Roots, Int) -> Bool).self)
        needsDisplay = bind("_PerryCANeedsDisplay", (@convention(c) () -> Bool).self)
        setChangeHandler = bind("_PerryCASetChangeHandler", (@convention(c) ((@convention(c) () -> Void)?) -> Void).self)
        // A change to layers draws the windows again.
        setChangeHandler?({ Windows.layersChanged() })
        return displayLayers != nil && composite != nil && needsDisplay != nil
    }

    /// Displays and composites `root` into `renderer`, and shows the frame.
    static func draw(_ root: CALayer, renderer: UnsafeMutableRawPointer, scale: CGFloat) {
        let roots: [UnsafeMutableRawPointer?] = [root.objcObject]
        roots.withUnsafeBufferPointer { buffer in
            displayLayers?(buffer.baseAddress, buffer.count)
            _ = composite?(renderer, Double(scale), buffer.baseAddress, buffer.count)
        }
    }
}
