import PerryInterface
import PerryObjCInterop

// UIAppearance: +appearance and its variants give a proxy that apps style
// classes through, as in [[UINavigationBar appearance] setTintColor:…]. The
// proxy takes any message and does nothing with it, so apps style
// themselves without Perry applying the styles yet; views keep their own
// look.

/// An appearance proxy: each message it is sent becomes a method that
/// returns nothing (zero, nil).
@ObjCClass("_UIAppearance")
open class UIAppearanceProxy: NSObject {
    nonisolated(unsafe) static let ignore: @convention(c) (UnsafeMutableRawPointer?, UnsafeRawPointer?) -> UnsafeMutableRawPointer? = { _, _ in nil }

    /// The one proxy every class's appearance is.
    nonisolated(unsafe) static let shared: UnsafeMutableRawPointer = {
        let proxy = UIAppearanceProxy.objCClass.object.newInstance()
        return ObjCRuntime.retain(proxy.objcObject)!
    }()

    @ObjCClassMethod("resolveInstanceMethod:")
    static func resolveInstanceMethod(_ selector: ObjCSelector?) -> Bool {
        guard let selector else { return false }
        UIAppearanceProxy.objCClass.addMethod(selector.name, types: "@16@0:8",
                                              implementation: unsafeBitCast(ignore, to: UnsafeRawPointer.self),
                                              isClassMethod: false)
        return true
    }
}

/// UIView's and UIBarItem's class methods that give the proxy: one
/// implementation, which ignores its arguments (the container classes of
/// +appearanceWhenContainedIn:, which a nil ends, among them).
enum AppearanceProxies {
    nonisolated(unsafe) static let proxy: @convention(c) (UnsafeMutableRawPointer?, UnsafeRawPointer?) -> UnsafeMutableRawPointer? = { _, _ in
        UIAppearanceProxy.shared
    }

    static let selectors = [
        "appearance", "appearanceWhenContainedIn:", "appearanceWhenContainedInInstancesOfClasses:",
        "appearanceForTraitCollection:", "appearanceForTraitCollection:whenContainedIn:",
        "appearanceForTraitCollection:whenContainedInInstancesOfClasses:",
    ]

    static func install(on cls: ObjCClass) {
        for selector in selectors {
            cls.addMethod(selector, types: "@16@0:8", implementation: unsafeBitCast(proxy, to: UnsafeRawPointer.self), isClassMethod: true)
        }
    }
}

/// Once UIKit's classes are all defined: UIView and UIBarItem, and so their
/// subclasses, give the proxy.
func providerDidStart(_ info: perry_startup_info) {
    AppearanceProxies.install(on: UIView.objCClass)
    AppearanceProxies.install(on: UIBarItem.objCClass)
}
