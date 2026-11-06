import PerryObjCInterop

// UIApplicationMain: makes the application and its delegate, launches,
// connects the first scene and runs the main run loop, which never returns.

/// int UIApplicationMain(int argc, char *argv[], NSString *principalClassName,
///                       NSString *delegateClassName)
@c(_UIApplicationMain)
public func UIApplicationMain(_ argc: Int32, _ argv: UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>?,
                              _ principalClassName: UnsafeMutableRawPointer?,
                              _ delegateClassName: UnsafeMutableRawPointer?) -> Int32 {
    ObjCRuntime.autoreleasepool {
        Launch.run(principalClassName: principalClassName.map { String(objCArgument: $0) },
                   delegateClassName: delegateClassName.map { String(objCArgument: $0) })
    }
    Lifecycle.installSignalHandlers()
    NSRunLoop.main().run()
    return 0
}

enum Launch {
    /// The fonts Info.plist lists under UIAppFonts, added to those text is
    /// drawn with and fonts are found by name among, as iOS adds them
    /// before the app starts.
    static func registerAppFonts() {
        let bundle = NSBundle.main()
        let names = bundle.infoObject(forKey: "UIAppFonts")?.as(NSArray.self)?.elements.map { $0.stringValue } ?? []
        for name in names {
            guard let url = NSURLObject.make(fileURLWithPath: bundle.bundlePath() + "/" + name),
                  let provider = CG.dataProviderCreateWithURL(url.objcObject) else { continue }
            defer { CG.dataProviderRelease(provider) }
            guard let font = CG.fontCreateWithDataProvider(provider) else {
                uikitWarning("UIAppFonts: \(name) could not be loaded")
                continue
            }
            _ = CG.fontRegister?(font)
            CG.fontRelease(font)
        }
    }

    static func run(principalClassName: String?, delegateClassName: String?) {
        registerAppFonts()
        let info = NSBundle.main()
        let principal = principalClassName ?? info.infoObject(forKey: "NSPrincipalClass")?.stringValue
        guard let applicationClass = Classes.named(principal ?? "UIApplication") else {
            uikitFatal("Unable to instantiate the UIApplication subclass instance. No class named \(principal ?? "") is loaded.")
        }
        // The application exists before its delegate is made.
        let application = applicationClass.object.newInstance().unsafeCast(to: UIApplication.self)
        Application.shared = application
        Application.state = .background
        Application.connectedScenes = NSMutableSet.empty()
        Application.openSessions = NSMutableSet.empty()

        if let delegateClassName {
            guard let delegateClass = Classes.named(delegateClassName) else {
                uikitFatal("Unable to instantiate the UIApplication delegate instance. No class named \(delegateClassName) is loaded.")
            }
            Application.delegate = delegateClass.object.newInstance()
        } else {
            loadMainNib(info, owner: application)
        }
        let delegate = Application.delegate?.unsafeCast(to: AnyUIApplicationDelegate.self)
        // Without scenes, the main storyboard's initial controller is the
        // root of a window the delegate is given before it hears of the
        // launch, and which shows once it has.
        // Scenes come from the Info.plist's manifest, or from an app
        // delegate that configures them, as SwiftUI's App lifecycle's does
        // in apps whose Info.plist names none.
        let configuresScenes = Application.delegate?.responds(to: "application:configurationForConnectingSceneSession:options:") ?? false
        let manifest = SceneManifest(info) ?? (configuresScenes ? SceneManifest.empty : nil)
        let window = manifest == nil ? mainStoryboardWindow(info) : nil
        _ = delegate?.application(application, willFinishLaunchingWithOptions: nil)
        if delegate?.application(application, didFinishLaunchingWithOptions: nil) == nil {
            delegate?.applicationDidFinishLaunching(application)
        }
        Application.post(Notifications.UIApplicationDidFinishLaunchingNotification, object: application)
        window?.makeKeyAndVisible()

        if let manifest {
            Scenes.connectFirstScene(application, manifest: manifest)
        } else {
            // Without a scene manifest, the application itself goes active.
            Application.state = .active
            delegate?.applicationDidBecomeActive(application)
            Application.post(Notifications.UIApplicationDidBecomeActiveNotification, object: application)
            Lifecycle.launched = true
        }
    }
}

extension Launch {
    /// The main nib's objects, kept for the life of the app.
    nonisolated(unsafe) static var mainNibObjects: [NSObject] = []

    /// The main nib, its File's Owner the application: it usually makes the
    /// delegate, connected through the application's delegate outlet, and
    /// the delegate's window.
    static func loadMainNib(_ info: NSBundle, owner application: UIApplication) {
        guard let name = (info.infoObject(forKey: "NSMainNibFile~iphone") ?? info.infoObject(forKey: "NSMainNibFile"))?.stringValue,
              let nib = UINib.nib(named: name, bundle: info) else { return }
        mainNibObjects = nib.instantiate(owner: application, external: [:])
    }

    /// A window with the main storyboard's initial controller, set as the
    /// delegate's window.
    static func mainStoryboardWindow(_ info: NSBundle) -> UIWindow? {
        guard let name = (info.infoObject(forKey: "UIMainStoryboardFile~iphone") ?? info.infoObject(forKey: "UIMainStoryboardFile"))?
                .stringValue,
              let storyboard = UIStoryboard.storyboard(name: name, bundle: info),
              let controller = storyboard.instantiateInitialViewController() else { return nil }
        let window = UIWindow.objCClass.object.allocated().initializeView(frame: Screen.bounds).unsafeCast(to: UIWindow.self)
        if let delegate = Application.delegate, delegate.responds(to: "setWindow:") {
            Outlets.set(delegate, "window", window)
        }
        window.setRootViewController(controller)
        return window
    }
}

/// The Info.plist's UIApplicationSceneManifest.
struct SceneManifest {
    struct Entry {
        let name: String?
        let delegateClassName: String?
        let sceneClassName: String?
    }

    /// Configurations by session role.
    let configurations: [String: [Entry]]

    /// No configurations: the app delegate gives them.
    static let empty = SceneManifest(configurations: [:])

    private init(configurations: [String: [Entry]]) {
        self.configurations = configurations
    }

    init?(_ bundle: NSBundle) {
        guard let manifest = bundle.infoObject(forKey: "UIApplicationSceneManifest")?.as(NSDictionary.self) else {
            return nil
        }
        var configurations: [String: [Entry]] = [:]
        let roles = [SessionRoles.UIWindowSceneSessionRoleApplication,
                     SessionRoles.UIWindowSceneSessionRoleExternalDisplayNonInteractive]
        if let byRole = manifest.object(forKey: "UISceneConfigurations")?.as(NSDictionary.self) {
            for role in roles {
                guard let entries = byRole.object(forKey: role)?.as(NSArray.self) else { continue }
                configurations[role] = entries.elements.compactMap { $0.as(NSDictionary.self) }.map { entry in
                    Entry(name: entry.object(forKey: "UISceneConfigurationName")?.stringValue,
                          delegateClassName: entry.object(forKey: "UISceneDelegateClassName")?.stringValue,
                          sceneClassName: entry.object(forKey: "UISceneClassName")?.stringValue)
                }
            }
        }
        self.configurations = configurations
    }

    /// The configuration named `name` for `role`, or the role's first.
    func entry(role: String, name: String?) -> Entry? {
        let entries = configurations[role] ?? []
        guard let name else { return entries.first }
        return entries.first { $0.name == name }
    }
}

enum Scenes {
    /// Connects the launch scene and brings it to the foreground, as UIKit
    /// does once the app has finished launching.
    static func connectFirstScene(_ application: UIApplication, manifest: SceneManifest) {
        let role = SessionRoles.UIWindowSceneSessionRoleApplication
        let delegate = Application.delegate?.unsafeCast(to: AnyUIApplicationDelegate.self)
        let options = UISceneConnectionOptions.objCClass.object.newInstance().unsafeCast(to: UISceneConnectionOptions.self)

        // The Info.plist's configuration, unless the app delegate picks one;
        // classes it leaves out come from the Info.plist entry of that name.
        let launchEntry = manifest.entry(role: role, name: nil)
        var configuration = UISceneConfiguration.make(name: launchEntry?.name, role: role)
        let session = UISceneSession.make(role: role, configuration: configuration)
        if let chosen = delegate?.application(application, configurationForConnecting: session, options: options) {
            configuration = chosen
        }
        let entry = manifest.entry(role: role, name: configuration.state.name)
        if configuration.state.delegateClass == nil {
            configuration.state.delegateClass = entry?.delegateClassName.flatMap(Classes.named)
        }
        if configuration.state.sceneClass == nil {
            configuration.state.sceneClass = entry?.sceneClassName.flatMap(Classes.named)
        }
        session.state.configuration = configuration.copied().unsafeCast(to: UISceneConfiguration.self)
        Application.openSessions?.add(session)

        let sceneClass = configuration.state.sceneClass ?? UIWindowScene.objCClass
        let scene = sceneClass.object.allocated().initializeScene(session: session, options: options)
            .unsafeCast(to: UIScene.self)
        if let delegateClass = configuration.state.delegateClass {
            scene.state.delegate = delegateClass.object.newInstance()
        }
        Application.connectedScenes?.add(scene)
        Lifecycle.scenes.append(scene)

        let sceneDelegate = scene.state.delegate?.unsafeCast(to: AnyUISceneDelegate.self)
        Application.post(Notifications.UISceneWillConnectNotification, object: scene)
        sceneDelegate?.scene(scene, willConnectTo: session, options: options)
        session.state.scene = scene.objcObject

        sceneDelegate?.sceneWillEnterForeground(scene)
        Application.post(Notifications.UISceneWillEnterForegroundNotification, object: scene)

        // The scene becomes active once the windows it showed have been
        // updated, as on iOS.
        Updates.afterPass {
            scene.state.activationState = .foregroundActive
            sceneDelegate?.sceneDidBecomeActive(scene)
            Application.post(Notifications.UISceneDidActivateNotification, object: scene)

            Application.state = .active
            Application.post(Notifications.UIApplicationDidBecomeActiveNotification, object: application)
            Lifecycle.launched = true
        }
    }
}
