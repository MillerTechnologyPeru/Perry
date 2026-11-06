import PerryObjCInterop

// The capture manager and its scopes, by which a program marks the frames
// Xcode's GPU debugger captures. Nothing captures here: scopes begin and
// end without effect, and a capture never starts.

@ObjCProtocol("MTLCaptureScope")
protocol MTLCaptureScopeProtocol {}

@ObjCClass("_MTLCaptureScope")
open class MTLCaptureScope: NSObject, MTLCaptureScopeProtocol {
    var owner: MTLDevice?
    var queue: MTLCommandQueue?
    var label: String?

    init(device: MTLDevice?, queue: MTLCommandQueue?) {
        owner = device
        self.queue = queue
        super.init()
    }

    @ObjCMethod("device") func device() -> MTLDevice? { owner }
    @ObjCMethod("commandQueue") func commandQueue() -> MTLCommandQueue? { queue }
    @ObjCMethod("label") func getLabel() -> String? { label }
    @ObjCMethod("setLabel:") func setLabel(_ label: String?) { self.label = label }
    @ObjCMethod("beginScope") func beginScope() {}
    @ObjCMethod("endScope") func endScope() {}
}

@ObjCClass("MTLCaptureManager")
open class MTLCaptureManager: NSObject {
    nonisolated(unsafe) static let shared = MTLCaptureManager()
    var defaultScope: MTLCaptureScope?

    @ObjCClassMethod("sharedCaptureManager") static func sharedCaptureManager() -> MTLCaptureManager { shared }

    @ObjCMethod("newCaptureScopeWithDevice:")
    func newCaptureScope(device: MTLDevice?) -> MTLCaptureScope? { MTLCaptureScope(device: device, queue: nil) }

    @ObjCMethod("newCaptureScopeWithCommandQueue:")
    func newCaptureScope(commandQueue: MTLCommandQueue?) -> MTLCaptureScope? {
        MTLCaptureScope(device: commandQueue?.owner, queue: commandQueue)
    }

    @ObjCMethod("defaultCaptureScope") func defaultCaptureScope() -> MTLCaptureScope? { defaultScope }
    @ObjCMethod("setDefaultCaptureScope:") func setDefaultCaptureScope(_ scope: MTLCaptureScope?) { defaultScope = scope }
    @ObjCMethod("isCapturing") func isCapturing() -> Bool { false }
    @ObjCMethod("supportsDestination:") func supportsDestination(_ destination: Int) -> Bool { false }
    @ObjCMethod("startCaptureWithDevice:") func startCapture(device: NSObject?) {}
    @ObjCMethod("startCaptureWithCommandQueue:") func startCapture(commandQueue: NSObject?) {}
    @ObjCMethod("startCaptureWithScope:") func startCapture(scope: NSObject?) {}
    @ObjCMethod("stopCapture") func stopCapture() {}
}
