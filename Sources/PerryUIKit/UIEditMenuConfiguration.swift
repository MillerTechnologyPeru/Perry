import CPerryGeometry
import PerryObjCInterop

// UIEditMenuConfiguration: where and how an edit menu is shown, kept for
// the app that asks; nothing here shows one.

@ObjCClass("UIEditMenuConfiguration")
open class UIEditMenuConfiguration: NSObject {
    /// Retained.
    var configurationIdentifier: NSObject?
    var point = CGPoint.zero
    var arrowDirection = 0

    @ObjCMethod("init") public required override init() { super.init() }

    deinit { if let configurationIdentifier { ObjCRuntime.release(configurationIdentifier.objcObject) } }

    private func keep(identifier: NSObject?, sourcePoint: CGPoint) {
        configurationIdentifier = ObjCRuntime.retain(identifier?.objcObject).map { NSObject($0) }
        point = sourcePoint
    }

    @ObjCMethod("initWithIdentifier:sourcePoint:")
    public required init(identifier: NSObject?, sourcePoint: CGPoint) {
        super.init()
        keep(identifier: identifier, sourcePoint: sourcePoint)
    }

    @ObjCClassMethod("configurationWithIdentifier:sourcePoint:")
    static func configuration(_ cls: ObjCClass, identifier: NSObject?, sourcePoint: CGPoint) -> UIEditMenuConfiguration {
        let made = cls.object.allocated().initialized().unsafeCast(to: UIEditMenuConfiguration.self)
        made.keep(identifier: identifier, sourcePoint: sourcePoint)
        return made
    }

    @ObjCMethod("identifier") func identifier() -> NSObject? { configurationIdentifier }
    @ObjCMethod("sourcePoint") func sourcePoint() -> CGPoint { point }
    @ObjCMethod("preferredArrowDirection") func preferredArrowDirection() -> Int { arrowDirection }
    @ObjCMethod("setPreferredArrowDirection:") func setPreferredArrowDirection(_ direction: Int) { arrowDirection = direction }
}
