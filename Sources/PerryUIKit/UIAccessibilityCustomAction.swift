import PerryObjCInterop

// UIAccessibilityCustomAction and UIAccessibilityCustomRotor: what an app
// offers an assistive technology beside an element's own activation. There
// is no assistive technology here to offer them to, so they are kept as made
// and never performed.

@ObjCClass("UIAccessibilityCustomAction")
open class UIAccessibilityCustomAction: NSObject {
    var actionName: NSObject?
    var attributedActionName: NSObject?
    var actionImage: NSObject?
    /// Not retained, as UIKit's.
    var actionTarget: NSObject?
    var actionSelector: ObjCSelector?
    var handler: NSObject?
    var category: NSObject?

    @ObjCMethod("init") public required override init() { super.init() }

    deinit {
        for kept in [actionName, attributedActionName, actionImage, handler, category] {
            if let kept { ObjCRuntime.release(kept.objcObject) }
        }
    }

    private static func kept(_ object: NSObject?) -> NSObject? {
        ObjCRuntime.retain(object?.objcObject).map { NSObject($0) }
    }

    private func replace(_ slot: inout NSObject?, with object: NSObject?, block: Bool = false) {
        let new = block ? object.flatMap { ObjCRuntime.functions.retainBlock($0.objcObject) }.map { NSObject($0) }
            : UIAccessibilityCustomAction.kept(object)
        if let old = slot { ObjCRuntime.release(old.objcObject) }
        slot = new
    }

    @ObjCMethod("initWithName:target:selector:")
    public required init(name: NSObject?, target: NSObject?, selector: ObjCSelector?) {
        super.init()
        actionName = UIAccessibilityCustomAction.kept(name)
        (actionTarget, actionSelector) = (target, selector)
    }

    @ObjCMethod("initWithAttributedName:target:selector:")
    public required init(attributedName: NSObject?, target: NSObject?, selector: ObjCSelector?) {
        super.init()
        attributedActionName = UIAccessibilityCustomAction.kept(attributedName)
        (actionTarget, actionSelector) = (target, selector)
    }

    @ObjCMethod("initWithName:image:target:selector:")
    public required init(name: NSObject?, image: NSObject?, target: NSObject?, selector: ObjCSelector?) {
        super.init()
        actionName = UIAccessibilityCustomAction.kept(name)
        actionImage = UIAccessibilityCustomAction.kept(image)
        (actionTarget, actionSelector) = (target, selector)
    }

    @ObjCMethod("initWithName:actionHandler:")
    public required init(name: NSObject?, actionHandler: NSObject?) {
        super.init()
        actionName = UIAccessibilityCustomAction.kept(name)
        handler = actionHandler.flatMap { ObjCRuntime.functions.retainBlock($0.objcObject) }.map { NSObject($0) }
    }

    @ObjCMethod("initWithName:image:actionHandler:")
    public required init(name: NSObject?, image: NSObject?, actionHandler: NSObject?) {
        super.init()
        actionName = UIAccessibilityCustomAction.kept(name)
        actionImage = UIAccessibilityCustomAction.kept(image)
        handler = actionHandler.flatMap { ObjCRuntime.functions.retainBlock($0.objcObject) }.map { NSObject($0) }
    }

    @ObjCMethod("name") func name() -> NSObject? { actionName }
    @ObjCMethod("setName:") func setName(_ name: NSObject?) { replace(&actionName, with: name) }
    @ObjCMethod("attributedName") func attributedName() -> NSObject? { attributedActionName }
    @ObjCMethod("setAttributedName:") func setAttributedName(_ name: NSObject?) { replace(&attributedActionName, with: name) }
    @ObjCMethod("image") func image() -> NSObject? { actionImage }
    @ObjCMethod("setImage:") func setImage(_ image: NSObject?) { replace(&actionImage, with: image) }
    @ObjCMethod("target") func target() -> NSObject? { actionTarget }
    @ObjCMethod("setTarget:") func setTarget(_ target: NSObject?) { actionTarget = target }
    @ObjCMethod("selector") func selector() -> ObjCSelector? { actionSelector }
    @ObjCMethod("setSelector:") func setSelector(_ selector: ObjCSelector?) { actionSelector = selector }
    @ObjCMethod("actionHandler") func actionHandler() -> NSObject? { handler }
    @ObjCMethod("setActionHandler:") func setActionHandler(_ block: NSObject?) { replace(&handler, with: block, block: true) }
    @ObjCMethod("category") func actionCategory() -> NSObject? { category }
    @ObjCMethod("setCategory:") func setActionCategory(_ category: NSObject?) { replace(&self.category, with: category) }
}

@ObjCClass("UIAccessibilityCustomRotor")
open class UIAccessibilityCustomRotor: NSObject {
    var rotorName: NSObject?
    var search: NSObject?
    var systemType = 0

    @ObjCMethod("init") public required override init() { super.init() }

    deinit {
        for kept in [rotorName, search] { if let kept { ObjCRuntime.release(kept.objcObject) } }
    }

    @ObjCMethod("initWithName:itemSearchBlock:")
    public required init(name: NSObject?, itemSearchBlock: NSObject?) {
        super.init()
        rotorName = ObjCRuntime.retain(name?.objcObject).map { NSObject($0) }
        search = itemSearchBlock.flatMap { ObjCRuntime.functions.retainBlock($0.objcObject) }.map { NSObject($0) }
    }

    @ObjCMethod("initWithSystemType:itemSearchBlock:")
    public required init(systemType: Int, itemSearchBlock: NSObject?) {
        super.init()
        self.systemType = systemType
        search = itemSearchBlock.flatMap { ObjCRuntime.functions.retainBlock($0.objcObject) }.map { NSObject($0) }
    }

    @ObjCMethod("name") func name() -> NSObject? { rotorName }
    @ObjCMethod("itemSearchBlock") func itemSearchBlock() -> NSObject? { search }
    @ObjCMethod("systemRotorType") func systemRotorType() -> Int { systemType }
}
