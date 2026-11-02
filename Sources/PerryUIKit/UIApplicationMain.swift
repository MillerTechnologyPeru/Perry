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
    NSRunLoop.main().run()
    return 0
}

enum Launch {
    static func run(principalClassName: String?, delegateClassName: String?) {
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
        }
        let delegate = Application.delegate?.unsafeCast(to: AnyUIApplicationDelegate.self)
        _ = delegate?.application(application, willFinishLaunchingWithOptions: nil)
        _ = delegate?.application(application, didFinishLaunchingWithOptions: nil)
        Application.post(Notifications.UIApplicationDidFinishLaunchingNotification, object: application)

        if let manifest = SceneManifest(info) {
            Scenes.connectFirstScene(application, manifest: manifest)
        } else {
            // Without a scene manifest, the application itself goes active.
            Application.state = .active
            delegate?.applicationDidBecomeActive(application)
            Application.post(Notifications.UIApplicationDidBecomeActiveNotification, object: application)
        }
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
        }
    }
}
