import PerryObjCInterop

// UIScreenEdgePanGestureRecognizer: a pan that begins at a screen edge. A
// handheld's panel has no edge gesture to tell from a touch on the content,
// so the recognizer keeps the edges it is given and never begins: a drag
// from an edge reaches the view under it, as it does on a device whose
// edge belongs to the system.

@ObjCClass("UIScreenEdgePanGestureRecognizer")
open class UIScreenEdgePanGestureRecognizer: UIPanGestureRecognizer {
    nonisolated(unsafe) static var edgeValues: [UnsafeMutableRawPointer: UInt] = [:]

    @ObjCMethod("dealloc")
    override func dealloc() {
        UIScreenEdgePanGestureRecognizer.edgeValues[objcObject] = nil
        super.dealloc()
    }

    /// UIRectEdge: the edges the gesture may begin at.
    @ObjCMethod("edges") func edges() -> UInt { UIScreenEdgePanGestureRecognizer.edgeValues[objcObject] ?? 0 }
    @ObjCMethod("setEdges:") func setEdges(_ edges: UInt) { UIScreenEdgePanGestureRecognizer.edgeValues[objcObject] = edges }

    @ObjCMethod("touchesBegan:withEvent:")
    override func touchesBegan(_ touches: NSObject?, with event: NSObject?) {}
    @ObjCMethod("touchesMoved:withEvent:")
    override func touchesMoved(_ touches: NSObject?, with event: NSObject?) {}
    @ObjCMethod("touchesEnded:withEvent:")
    override func touchesEnded(_ touches: NSObject?, with event: NSObject?) {}
    @ObjCMethod("touchesCancelled:withEvent:")
    override func touchesCancelled(_ touches: NSObject?, with event: NSObject?) {}
}
