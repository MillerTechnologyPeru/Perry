import PerryInterface
import PerryObjCInterop

// UIAppearance: +appearance and its variants give a proxy that apps style
// classes through, as in [[UINavigationBar appearance] setTintColor:…].
// Each class has a proxy of its own, which keeps the colors, images and
// fonts it is given (setters whose names end in Color:, Image: or Font:,
// whose values are objects) and gives them back from the matching getters,
// for code that reads a class's appearance, as SwiftUI's page dots read
// UIPageControl's. Other messages do nothing; views keep their own look.

/// An appearance proxy: each message it is sent becomes a method that
/// returns nothing (zero, nil), but for the styles it keeps.
@ObjCClass("_UIAppearance")
open class UIAppearanceProxy: NSObject {
    nonisolated(unsafe) static let ignore: @convention(c) (UnsafeMutableRawPointer?, UnsafeRawPointer?) -> UnsafeMutableRawPointer? = { _, _ in nil }

    /// The styles each proxy keeps, by proxy and getter name.
    nonisolated(unsafe) static var styles: [UnsafeMutableRawPointer: [String: UnsafeMutableRawPointer]] = [:]
    static let lock = Lock()

    nonisolated(unsafe) static let set: @convention(c) (UnsafeMutableRawPointer?, UnsafePointer<CChar>?, UnsafeMutableRawPointer?) -> Void = { proxy, selector, value in
        guard let proxy, let selector, let key = styleKey(setter: String(cString: selector)) else { return }
        let retained = value.flatMap { ObjCRuntime.retain($0) }
        let old = lock.withLock { () -> UnsafeMutableRawPointer? in
            defer { styles[proxy, default: [:]][key] = retained }
            return styles[proxy]?[key]
        }
        if let old { ObjCRuntime.release(old) }
    }

    nonisolated(unsafe) static let get: @convention(c) (UnsafeMutableRawPointer?, UnsafePointer<CChar>?) -> UnsafeMutableRawPointer? = { proxy, selector in
        guard let proxy, let selector else { return nil }
        let key = String(cString: selector)
        return lock.withLock { styles[proxy]?[key] }
    }

    /// The getter a style's setter sets: "setTintColor:" sets "tintColor".
    static func styleKey(setter: String) -> String? {
        guard setter.hasPrefix("set"), setter.hasSuffix(":"), setter.filter({ $0 == ":" }).count == 1 else { return nil }
        let name = setter.dropFirst(3).dropLast()
        guard let first = name.first, isStyle(String(name)) else { return nil }
        return first.lowercased() + name.dropFirst()
    }

    static func isStyle(_ name: String) -> Bool {
        name.hasSuffix("Color") || name.hasSuffix("Image") || name.hasSuffix("Font")
    }

    @ObjCClassMethod("resolveInstanceMethod:")
    static func resolveInstanceMethod(_ selector: ObjCSelector?) -> Bool {
        guard let selector else { return false }
        let name = selector.name
        if styleKey(setter: name) != nil {
            UIAppearanceProxy.objCClass.addMethod(name, types: "v24@0:8@16",
                                                  implementation: unsafeBitCast(set, to: UnsafeRawPointer.self),
                                                  isClassMethod: false)
        } else if !name.contains(":"), isStyle(name) {
            UIAppearanceProxy.objCClass.addMethod(name, types: "@16@0:8",
                                                  implementation: unsafeBitCast(get, to: UnsafeRawPointer.self),
                                                  isClassMethod: false)
        } else {
            UIAppearanceProxy.objCClass.addMethod(name, types: "@16@0:8",
                                                  implementation: unsafeBitCast(ignore, to: UnsafeRawPointer.self),
                                                  isClassMethod: false)
        }
        return true
    }
}

/// UIView's and UIBarItem's class methods that give a class's proxy: one
/// implementation, which ignores its arguments (the container classes of
/// +appearanceWhenContainedIn:, which a nil ends, among them), so every
/// variant is the class's one proxy.
enum AppearanceProxies {
    nonisolated(unsafe) static var proxies: [UnsafeMutableRawPointer: UnsafeMutableRawPointer] = [:]

    nonisolated(unsafe) static let proxy: @convention(c) (UnsafeMutableRawPointer?, UnsafeRawPointer?) -> UnsafeMutableRawPointer? = { cls, _ in
        guard let cls else { return nil }
        return UIAppearanceProxy.lock.withLock {
            if let proxy = proxies[cls] { return proxy }
            // +alloc and -init, raw: a proxy has no Swift side to wrap it in.
            typealias New = @convention(c) (UnsafeMutableRawPointer?, UnsafeRawPointer) -> UnsafeMutableRawPointer?
            let send = unsafeBitCast(ObjCRuntime.msgSend, to: New.self)
            let allocated = send(UIAppearanceProxy.objCClass.pointer, ObjCRuntime.selector("alloc"))
            let initialized = send(allocated, ObjCRuntime.selector("init"))
            guard let proxy = initialized else { return nil }
            proxies[cls] = proxy
            return proxy
        }
    }

    /// The style a class's proxy keeps for `key`, its getter's name.
    static func style(_ key: String, of cls: UnsafeMutableRawPointer?) -> NSObject? {
        guard let cls else { return nil }
        return UIAppearanceProxy.lock.withLock {
            proxies[cls].flatMap { UIAppearanceProxy.styles[$0]?[key] }
        }.map { NSObject(objCArgument: $0) }
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
    RendererContexts.install()
}
