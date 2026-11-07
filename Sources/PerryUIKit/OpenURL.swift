import PerryObjCInterop

// The app's own URLs: those of a scheme its Info.plist claims
// (CFBundleURLTypes' CFBundleURLSchemes). Opening one opens the app itself,
// as iOS does: its scene delegate hears -scene:openURLContexts: (SwiftUI's
// onOpenURL), else its app delegate -application:openURL:options: or
// iOS 2's -application:handleOpenURL:. OAuth sign-ins come back this way:
// the sign-in page redirects to the app's scheme, which the Safari view or
// web view showing it opens.

enum IncomingURLs {
    /// The schemes the app claims, lowercased.
    nonisolated(unsafe) static let schemes: Set<String> = {
        guard let types = NSBundle.main().infoObject(forKey: "CFBundleURLTypes")?.as(NSArray.self) else { return [] }
        var schemes: Set<String> = []
        for type in types.elements {
            guard let list = type.as(NSDictionary.self)?.object(forKey: "CFBundleURLSchemes")?.as(NSArray.self) else { continue }
            for scheme in list.elements { schemes.insert(scheme.stringValue.lowercased()) }
        }
        return schemes
    }()

    /// Whether a URL is one of the app's own.
    static func isOwn(_ url: NSObject?) -> Bool {
        guard let scheme = url?.sendScheme()?.lowercased() else { return false }
        return schemes.contains(scheme)
    }

    /// Whether a URL string is one of the app's own.
    static func isOwn(_ uri: String) -> Bool {
        guard let colon = uri.firstIndex(of: ":") else { return false }
        return schemes.contains(uri[..<colon].lowercased())
    }

    /// Opens a URL of the app's in the app, after the current pass; false
    /// when nothing in the app takes URLs.
    @discardableResult
    static func open(_ url: NSObject) -> Bool {
        let scenes = Lifecycle.scenes.filter { $0.state.delegate?.responds(to: "scene:openURLContexts:") == true }
        let delegate = Application.delegate
        let takesURLs = !scenes.isEmpty || delegate?.responds(to: "application:openURL:options:") == true
            || delegate?.responds(to: "application:handleOpenURL:") == true
        guard takesURLs else { return false }
        Updates.afterPass {
            if let scene = scenes.first, let sceneDelegate = scene.state.delegate {
                let contexts = NSMutableSet.empty()
                contexts.add(UIOpenURLContext.make(url))
                sceneDelegate.sendScene(scene, openURLContexts: contexts)
            } else if let delegate, let application = Application.shared, delegate.responds(to: "application:openURL:options:") {
                _ = delegate.sendApplication(application, open: url, options: NSDictionaryFactory.empty())
            } else if let delegate, let application = Application.shared {
                _ = delegate.sendApplication(application, handleOpen: url)
            }
        }
        return true
    }
}

@ObjCWrapper("NSDictionary")
class NSDictionaryFactory: NSObject {
    @ObjCClassMethod("dictionary") static func empty() -> NSObject
}

extension NSObject {
    @ObjCMethod("scene:openURLContexts:") func sendScene(_ scene: UIScene, openURLContexts contexts: NSObject)
    @ObjCMethod("application:openURL:options:")
    func sendApplication(_ application: UIApplication, open url: NSObject, options: NSObject) -> Bool
    @ObjCMethod("application:handleOpenURL:") func sendApplication(_ application: UIApplication, handleOpen url: NSObject) -> Bool
}
