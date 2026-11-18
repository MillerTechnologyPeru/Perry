import PerryObjCInterop

// UIGlassEffect and UIGlassContainerEffect (iOS 26): the liquid glass an
// effect view can show. Here glass is a blur of the system material, as
// the effect's style, clear or regular, says; the tint and the
// interactive flag are kept for the app that asks.

@ObjCClass("UIGlassEffect")
open class UIGlassEffect: UIVisualEffect {
    var glassStyleValue = 0
    var interactive = false
    /// Retained.
    var glassTint: NSObject?

    @ObjCMethod("init") public required override init() {
        super.init()
        effect.style = 8
    }

    deinit { if let glassTint { ObjCRuntime.release(glassTint.objcObject) } }

    @ObjCMethod("initWithStyle:")
    public required init(style: Int) {
        super.init()
        glassStyleValue = style
        // Clear glass is thinner than regular.
        effect.style = style == 1 ? 6 : 8
    }

    @ObjCClassMethod("effectWithStyle:")
    static func effect(_ cls: ObjCClass, style: Int) -> UIGlassEffect {
        let made = cls.object.allocated().unsafeCast(to: UIGlassEffect.self)
        made.glassStyleValue = style
        made.effect.style = style == 1 ? 6 : 8
        return made
    }

    @ObjCMethod("style") func glassStyle() -> Int { glassStyleValue }
    @ObjCMethod("isInteractive") func isInteractive() -> Bool { interactive }
    @ObjCMethod("setInteractive:") func setInteractive(_ interactive: Bool) { self.interactive = interactive }
    @ObjCMethod("tintColor") func tintColor() -> NSObject? { glassTint }

    @ObjCMethod("setTintColor:")
    func setTintColor(_ color: NSObject?) {
        let retained = ObjCRuntime.retain(color?.objcObject)
        if let old = glassTint { ObjCRuntime.release(old.objcObject) }
        glassTint = retained.map { NSObject($0) }
    }
}

@ObjCClass("UIGlassContainerEffect")
open class UIGlassContainerEffect: UIVisualEffect {
    var spacingValue = 0.0

    @ObjCMethod("init") public required override init() { super.init() }

    @ObjCMethod("spacing") func spacing() -> Double { spacingValue }
    @ObjCMethod("setSpacing:") func setSpacing(_ spacing: Double) { spacingValue = spacing }
}
