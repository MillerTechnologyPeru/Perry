import PerryObjCInterop

// Fences, which a program puts between a command buffer's encoders to say
// in what order they touch a heap's resources. Encoders here are encoded
// one after another, in the order they were made, so a fence has nothing
// to order: one is made, updated and waited for without effect.

@ObjCProtocol("MTLFence")
protocol MTLFenceProtocol {}

@ObjCClass("_MTLFence")
open class MTLFence: NSObject, MTLFenceProtocol {
    var owner: MTLDevice?
    var label: String?

    init(device: MTLDevice) {
        owner = device
        super.init()
    }

    @ObjCMethod("device") func device() -> MTLDevice? { owner }
    @ObjCMethod("label") func getLabel() -> String? { label }
    @ObjCMethod("setLabel:") func setLabel(_ label: String?) { self.label = label }
}
