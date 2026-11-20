import CPerryGeometry
import PerryObjCInterop

// The objects a nib keeps in place of the objects it makes: a view or an
// object of a class the program names, an image or color resource by name,
// and a window's settings. Loading a nib makes the real objects from the
// archive directly (Nib.swift); these classes are for the programs that
// make, decode and encode the placeholders themselves, as Interface
// Builder's compiler does, and subclass them. They code the keys AppKit's
// do, which loading a nib reads.

/// Sends a keyed coder's encode messages.
struct Encoder {
    let coder: NSObject

    private func key(_ name: String) -> UnsafeMutableRawPointer? { name.objCArgument() }

    func object(_ value: NSObject?, _ name: String) {
        guard let value else { return }
        Send.void(coder.objcObject, "encodeObject:forKey:", value.objcObject, key(name))
    }
    func string(_ value: String?, _ name: String) {
        guard let value else { return }
        object(NSObject(objCReturnValue: value.objCReturnValue()), name)
    }
    func integer(_ value: Int, _ name: String) {
        typealias F = @convention(c) (UnsafeMutableRawPointer, UnsafeRawPointer, Int64, UnsafeMutableRawPointer?) -> Void
        unsafeBitCast(ObjCRuntime.msgSend, to: F.self)(coder.objcObject, ObjCRuntime.selector("encodeInt64:forKey:"), Int64(value), key(name))
    }
    func bool(_ value: Bool, _ name: String) {
        typealias F = @convention(c) (UnsafeMutableRawPointer, UnsafeRawPointer, Bool, UnsafeMutableRawPointer?) -> Void
        unsafeBitCast(ObjCRuntime.msgSend, to: F.self)(coder.objcObject, ObjCRuntime.selector("encodeBool:forKey:"), value, key(name))
    }
    func rect(_ value: CGRect, _ name: String) {
        typealias F = @convention(c) (UnsafeMutableRawPointer, UnsafeRawPointer, CGRect, UnsafeMutableRawPointer?) -> Void
        unsafeBitCast(ObjCRuntime.msgSend, to: F.self)(coder.objcObject, ObjCRuntime.selector("encodeRect:forKey:"), value, key(name))
    }
    func size(_ value: CGSize, _ name: String) {
        typealias F = @convention(c) (UnsafeMutableRawPointer, UnsafeRawPointer, CGSize, UnsafeMutableRawPointer?) -> Void
        unsafeBitCast(ObjCRuntime.msgSend, to: F.self)(coder.objcObject, ObjCRuntime.selector("encodeSize:forKey:"), value, key(name))
    }
}

@ObjCClass("NSCustomObject")
open class NSCustomObject: NSObject {
    var className: String?
    var object: NSObject?

    public required override init() { super.init() }

    /// "NSClassName": the class of the object the nib makes.
    @ObjCMethod("initWithCoder:")
    public required init(coder: NSObject?) {
        super.init()
        guard let coder else { return }
        let decoded = Coder(coder: coder)
        className = decoded.string("NSClassName")
        object = decoded.object("NSObject")
    }

    @ObjCMethod("encodeWithCoder:")
    func encode(with coder: NSObject?) {
        guard let coder else { return }
        let encoder = Encoder(coder: coder)
        encoder.string(className, "NSClassName")
        encoder.object(object, "NSObject")
    }

    @ObjCMethod("className") func customClassName() -> String? { className }
    @ObjCMethod("setClassName:") func setClassName(_ value: String?) { className = value }
    @ObjCMethod("object") func customObject() -> NSObject? { object }
    @ObjCMethod("setObject:") func setObject(_ value: NSObject?) { object = value }
}

@ObjCClass("NSCustomView")
open class NSCustomView: NSView {
    var className: String?
    var extensionObject: NSObject?

    public required init() { super.init() }
    @ObjCMethod("initWithFrame:")
    public required init(frame: CGRect) { super.init(frame: frame) }

    /// A view's keys, and "NSClassName", the class of the view the nib makes.
    @ObjCMethod("initWithCoder:")
    public required init(coder: NSObject?) {
        super.init(coder: coder)
        guard let coder else { return }
        let decoded = Coder(coder: coder)
        className = decoded.string("NSClassName")
        extensionObject = decoded.object("NSExtension")
    }

    @ObjCMethod("encodeWithCoder:")
    func encode(with coder: NSObject?) {
        guard let coder else { return }
        let encoder = Encoder(coder: coder)
        encoder.string(className, "NSClassName")
        encoder.object(extensionObject, "NSExtension")
        encoder.rect(frame, "NSFrame")
        encoder.integer(Int(autoresizingMask) | (hidden ? Int(bitPattern: 0x8000_0000) : 0), "NSvFlags")
        if !subviews.isEmpty { encoder.object(NSMutableArray.of(subviews), "NSSubviews") }
    }

    @ObjCMethod("className") func customClassName() -> String? { className }
    @ObjCMethod("setClassName:") func setClassName(_ value: String?) { className = value }
    @ObjCMethod("extension") func customExtension() -> NSObject? { extensionObject }
    @ObjCMethod("setExtension:") func setExtension(_ value: NSObject?) { extensionObject = value }
}

@ObjCClass("NSCustomResource")
open class NSCustomResource: NSObject {
    var className: String?
    var resourceName: String?

    public required override init() { super.init() }

    /// "NSClassName" (NSImage, NSSound, NSColor) and "NSResourceName".
    @ObjCMethod("initWithCoder:")
    public required init(coder: NSObject?) {
        super.init()
        guard let coder else { return }
        let decoded = Coder(coder: coder)
        className = decoded.string("NSClassName")
        resourceName = decoded.string("NSResourceName")
    }

    @ObjCMethod("encodeWithCoder:")
    func encode(with coder: NSObject?) {
        guard let coder else { return }
        let encoder = Encoder(coder: coder)
        encoder.string(className, "NSClassName")
        encoder.string(resourceName, "NSResourceName")
    }

    @ObjCMethod("className") func customClassName() -> String? { className }
    @ObjCMethod("setClassName:") func setClassName(_ value: String?) { className = value }
    @ObjCMethod("resourceName") func customResourceName() -> String? { resourceName }
    @ObjCMethod("setResourceName:") func setResourceName(_ value: String?) { resourceName = value }
}

/// A window's settings, from which loading the nib makes the window.
@ObjCClass("NSWindowTemplate")
open class NSWindowTemplate: NSObject {
    var windowClass = "NSWindow"
    var title = ""
    var frame = CGRect.zero
    var styleMask: UInt = 0
    var backingType: UInt = 2
    var view: NSView?
    var minSize = CGSize.zero
    var maxSize = CGSize(width: 10_000_000, height: 10_000_000)
    var contentMinSize = CGSize.zero
    var contentMaxSize = CGSize(width: 10_000_000, height: 10_000_000)
    var autosaveName = ""
    var flags = 0
    var screenRect = CGRect.zero
    var viewClass: String?

    public required override init() { super.init() }

    @ObjCMethod("initWithCoder:")
    public required init(coder: NSObject?) {
        super.init()
        guard let coder else { return }
        let decoded = Coder(coder: coder)
        windowClass = decoded.string("NSWindowClass") ?? windowClass
        title = decoded.string("NSWindowTitle") ?? ""
        frame = decoded.rect("NSWindowRect")
        styleMask = UInt(decoded.integer("NSWindowStyleMask"))
        if decoded.has("NSWindowBacking") { backingType = UInt(decoded.integer("NSWindowBacking")) }
        view = decoded.object("NSWindowView")?.as(NSView.self)
        if decoded.has("NSMinSize") { minSize = decoded.size("NSMinSize") }
        if decoded.has("NSMaxSize") { maxSize = decoded.size("NSMaxSize") }
        if decoded.has("NSWindowContentMinSize") { contentMinSize = decoded.size("NSWindowContentMinSize") }
        if decoded.has("NSWindowContentMaxSize") { contentMaxSize = decoded.size("NSWindowContentMaxSize") }
        autosaveName = decoded.string("NSFrameAutosaveName") ?? ""
        flags = decoded.integer("NSWTFlags")
        screenRect = decoded.rect("NSScreenRect")
        viewClass = decoded.string("NSViewClass")
    }

    @ObjCMethod("encodeWithCoder:")
    func encode(with coder: NSObject?) {
        guard let coder else { return }
        let encoder = Encoder(coder: coder)
        encoder.integer(Int(styleMask), "NSWindowStyleMask")
        encoder.integer(Int(backingType), "NSWindowBacking")
        encoder.rect(frame, "NSWindowRect")
        encoder.rect(screenRect, "NSScreenRect")
        encoder.size(maxSize, "NSMaxSize")
        encoder.size(minSize, "NSMinSize")
        encoder.size(contentMinSize, "NSWindowContentMinSize")
        encoder.size(contentMaxSize, "NSWindowContentMaxSize")
        encoder.integer(flags, "NSWTFlags")
        encoder.string(title, "NSWindowTitle")
        encoder.string(windowClass, "NSWindowClass")
        encoder.string(viewClass, "NSViewClass")
        encoder.object(view, "NSWindowView")
        if !autosaveName.isEmpty { encoder.string(autosaveName, "NSFrameAutosaveName") }
    }

    @ObjCMethod("className") func templateClassName() -> String { windowClass }
    @ObjCMethod("setClassName:") func setClassName(_ value: String?) { windowClass = value ?? "NSWindow" }
    @ObjCMethod("title") func templateTitle() -> String { title }
    @ObjCMethod("setTitle:") func setTitle(_ value: String?) { title = value ?? "" }
    @ObjCMethod("windowRect") func windowRect() -> CGRect { frame }
    @ObjCMethod("setWindowRect:") func setWindowRect(_ value: CGRect) { frame = value }
    @ObjCMethod("styleMask") func templateStyleMask() -> UInt { styleMask }
    @ObjCMethod("setStyleMask:") func setStyleMask(_ value: UInt) { styleMask = value }
    @ObjCMethod("backingType") func templateBackingType() -> UInt { backingType }
    @ObjCMethod("setBackingType:") func setBackingType(_ value: UInt) { backingType = value }
    @ObjCMethod("windowView") func windowView() -> NSView? { view }
    @ObjCMethod("setWindowView:") func setWindowView(_ value: NSView?) { view = value }
    @ObjCMethod("minSize") func templateMinSize() -> CGSize { minSize }
    @ObjCMethod("setMinSize:") func setMinSize(_ value: CGSize) { minSize = value }
    @ObjCMethod("maxSize") func templateMaxSize() -> CGSize { maxSize }
    @ObjCMethod("setMaxSize:") func setMaxSize(_ value: CGSize) { maxSize = value }
    @ObjCMethod("contentMinSize") func templateContentMinSize() -> CGSize { contentMinSize }
    @ObjCMethod("setContentMinSize:") func setContentMinSize(_ value: CGSize) { contentMinSize = value }
    @ObjCMethod("contentMaxSize") func templateContentMaxSize() -> CGSize { contentMaxSize }
    @ObjCMethod("setContentMaxSize:") func setContentMaxSize(_ value: CGSize) { contentMaxSize = value }
    @ObjCMethod("frameAutosaveName") func frameAutosaveName() -> String { autosaveName }
    @ObjCMethod("setFrameAutosaveName:") func setFrameAutosaveName(_ value: String?) { autosaveName = value ?? "" }
    @ObjCMethod("screenRect") func templateScreenRect() -> CGRect { screenRect }
    @ObjCMethod("setScreenRect:") func setScreenRect(_ value: CGRect) { screenRect = value }
}
