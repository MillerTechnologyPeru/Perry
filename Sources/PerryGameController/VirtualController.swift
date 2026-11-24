import PerryObjCInterop

// Virtual controllers, the on-screen controls GameController draws over a
// touch screen: none is drawn here, so making one gives nil, as it does on
// a device without the support. Their configuration holds what it is set
// to. GCKeyCode's keys are the USB HID keyboard usages.

@ObjCClass("GCVirtualControllerConfiguration")
open class GCVirtualControllerConfiguration: NSObject {
    var elementsObject: NSObject?
    var hidden = false

    @ObjCMethod("init") public required override init() { super.init() }

    @ObjCMethod("elements") func elements() -> NSObject? { elementsObject }
    @ObjCMethod("setElements:") func setElements(_ elements: NSObject?) { elementsObject = elements }
    @ObjCMethod("isHidden") func isHidden() -> Bool { hidden }
    @ObjCMethod("setHidden:") func setHidden(_ hidden: Bool) { self.hidden = hidden }
}

@ObjCClass("GCVirtualController")
open class GCVirtualController: NSObject {
    @ObjCMethod("init") public required override init() { super.init() }

    @ObjCClassMethod("virtualControllerWithConfiguration:")
    static func virtualController(configuration: NSObject?) -> GCVirtualController? { nil }

    @ObjCMethod("initWithConfiguration:") public init?(configuration: NSObject?) { nil }

    @ObjCMethod("controller") func controller() -> NSObject? { nil }
    @ObjCMethod("disconnect") func disconnect() {}
}

@ObjCConstants
enum KeyCodes {
    static let GCKeyCodeKeyA: Int = 0x04
    static let GCKeyCodeKeyD: Int = 0x07
    static let GCKeyCodeKeyS: Int = 0x16
    static let GCKeyCodeKeyW: Int = 0x1A
    static let GCKeyCodeReturnOrEnter: Int = 0x28
    static let GCKeyCodeEscape: Int = 0x29
    static let GCKeyCodeDeleteOrBackspace: Int = 0x2A
    static let GCKeyCodeTab: Int = 0x2B
    static let GCKeyCodeSpacebar: Int = 0x2C
    static let GCKeyCodeRightArrow: Int = 0x4F
    static let GCKeyCodeLeftArrow: Int = 0x50
    static let GCKeyCodeDownArrow: Int = 0x51
    static let GCKeyCodeUpArrow: Int = 0x52
    static let GCKeyCodeLeftControl: Int = 0xE0
    static let GCKeyCodeLeftShift: Int = 0xE1
    static let GCKeyCodeLeftAlt: Int = 0xE2
    static let GCKeyCodeLeftGUI: Int = 0xE3
    static let GCKeyCodeRightControl: Int = 0xE4
    static let GCKeyCodeRightShift: Int = 0xE5
    static let GCKeyCodeRightAlt: Int = 0xE6
    static let GCKeyCodeRightGUI: Int = 0xE7
}
