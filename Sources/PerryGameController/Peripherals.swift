import PerryObjCInterop

// Keyboards and mice as GameController sees them: none is ever connected,
// so their connect notifications never post. GCColor is a light bar's
// colour, which no controller here has.

@ObjCClass("GCKeyboard")
open class GCKeyboard: NSObject {
    @ObjCClassMethod("coalescedKeyboard") static func coalescedKeyboard() -> GCKeyboard? { nil }
    @ObjCMethod("keyboardInput") func keyboardInput() -> NSObject? { nil }
    @ObjCMethod("handlerQueue") func handlerQueue() -> NSObject? { nil }
    @ObjCMethod("setHandlerQueue:") func setHandlerQueue(_ queue: NSObject?) {}
    @ObjCMethod("vendorName") func vendorName() -> String? { nil }
    @ObjCMethod("productCategory") func productCategory() -> String { "Keyboard" }
}

@ObjCClass("GCMouse")
open class GCMouse: NSObject {
    @ObjCClassMethod("current") static func current() -> GCMouse? { nil }
    @ObjCClassMethod("mice") static func mice() -> NSObject { NSObject(ObjCClass(named: "NSArray").pointer).newInstance() }
    @ObjCMethod("mouseInput") func mouseInput() -> NSObject? { nil }
    @ObjCMethod("handlerQueue") func handlerQueue() -> NSObject? { nil }
    @ObjCMethod("setHandlerQueue:") func setHandlerQueue(_ queue: NSObject?) {}
    @ObjCMethod("vendorName") func vendorName() -> String? { nil }
    @ObjCMethod("productCategory") func productCategory() -> String { "Mouse" }
}

final class ColorState {
    var red: Float = 0, green: Float = 0, blue: Float = 0
}

@ObjCClass("GCColor")
open class GCColor: NSObject {
    var color = ColorState()

    @ObjCMethod("initWithRed:green:blue:")
    public required init(red: Float, green: Float, blue: Float) {
        super.init()
        (color.red, color.green, color.blue) = (red, green, blue)
    }

    @ObjCMethod("red") func red() -> Float { color.red }
    @ObjCMethod("green") func green() -> Float { color.green }
    @ObjCMethod("blue") func blue() -> Float { color.blue }
}
