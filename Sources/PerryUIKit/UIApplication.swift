import PerryObjCInterop

/// UIApplicationState.
enum ApplicationState: Int {
    case active = 0
    case inactive = 1
    case background = 2
}

/// The one application and what it holds.
enum Application {
    nonisolated(unsafe) static var shared: UIApplication?
    nonisolated(unsafe) static var delegate: NSObject?
    nonisolated(unsafe) static var state = ApplicationState.background
    nonisolated(unsafe) static var connectedScenes: NSMutableSet?
    nonisolated(unsafe) static var openSessions: NSMutableSet?

    /// Posts a notification from the default center.
    static func post(_ name: String, object: NSObject?) {
        NSNotificationCenter.defaultCenter().post(name: name, object: object)
    }
}

/// UIApplication. UIApplicationMain makes the one instance.
@ObjCClass("UIApplication")
open class UIApplication: UIResponder {
    @ObjCClassMethod("sharedApplication")
    static func sharedApplication() -> UIApplication? { Application.shared }

    @ObjCMethod("delegate")
    func delegate() -> NSObject? { Application.delegate }

    @ObjCMethod("setDelegate:")
    func setDelegate(_ delegate: NSObject?) { Application.delegate = delegate }

    @ObjCMethod("applicationState")
    func applicationState() -> Int { Application.state.rawValue }

    @ObjCMethod("connectedScenes")
    func connectedScenes() -> NSObject { Application.connectedScenes ?? NSMutableSet.empty() }

    @ObjCMethod("openSessions")
    func openSessions() -> NSObject { Application.openSessions ?? NSMutableSet.empty() }

    /// The key window, of any scene.
    @ObjCMethod("keyWindow")
    func keyWindow() -> NSObject? { Windows.key.map(NSObject.init) }

    /// No other app can open URLs here: each request says so.
    @ObjCMethod("canOpenURL:") func canOpenURL(_ url: NSObject?) -> Bool { false }

    @ObjCMethod("openURL:")
    func openURL(_ url: NSObject?) -> Bool {
        uikitWarning("no app to open \(url?.describedByObject() ?? "a URL")")
        return false
    }

    @ObjCMethod("openURL:options:completionHandler:")
    func openURL(_ url: NSObject?, options: NSObject?, completionHandler: ObjCBlock?) {
        _ = openURL(url)
        completionHandler.map { Blocks.call($0, false) }
    }

    @ObjCMethod("isIdleTimerDisabled") func isIdleTimerDisabled() -> Bool { false }
    @ObjCMethod("setIdleTimerDisabled:") func setIdleTimerDisabled(_ disabled: Bool) {}
    @ObjCMethod("isNetworkActivityIndicatorVisible") func isNetworkActivityIndicatorVisible() -> Bool { false }
    @ObjCMethod("setNetworkActivityIndicatorVisible:") func setNetworkActivityIndicatorVisible(_ visible: Bool) {}
    @ObjCMethod("applicationIconBadgeNumber") func applicationIconBadgeNumber() -> Int { 0 }
    @ObjCMethod("setApplicationIconBadgeNumber:") func setApplicationIconBadgeNumber(_ number: Int) {}
    @ObjCMethod("beginIgnoringInteractionEvents") func beginIgnoringInteractionEvents() {}
    @ObjCMethod("endIgnoringInteractionEvents") func endIgnoringInteractionEvents() {}
    @ObjCMethod("registerForRemoteNotifications") func registerForRemoteNotifications() {}
    @ObjCMethod("windows") func windows() -> NSObject { NSMutableArray.of(Windows.all.map { NSObject($0) }) }

    @ObjCMethod("supportsMultipleScenes")
    func supportsMultipleScenes() -> Bool { false }

    /// The app delegate, when it is a responder.
    @ObjCMethod("nextResponder")
    override func nextResponder() -> NSObject? {
        guard let delegate = Application.delegate, delegate.is(UIResponder.self) else { return nil }
        return delegate
    }
}

/// The application's delegate.
@ObjCProtocol("UIApplicationDelegate")
protocol UIApplicationDelegate {
    @ObjCOptional("application:willFinishLaunchingWithOptions:")
    func application(_ application: UIApplication, willFinishLaunchingWithOptions options: NSDictionary?) -> Bool?

    @ObjCOptional("application:didFinishLaunchingWithOptions:")
    func application(_ application: UIApplication, didFinishLaunchingWithOptions options: NSDictionary?) -> Bool?

    @ObjCOptional("applicationDidBecomeActive:")
    func applicationDidBecomeActive(_ application: UIApplication)

    @ObjCOptional("applicationWillResignActive:")
    func applicationWillResignActive(_ application: UIApplication)

    @ObjCOptional("applicationDidEnterBackground:")
    func applicationDidEnterBackground(_ application: UIApplication)

    @ObjCOptional("applicationWillEnterForeground:")
    func applicationWillEnterForeground(_ application: UIApplication)

    @ObjCOptional("applicationWillTerminate:")
    func applicationWillTerminate(_ application: UIApplication)

    @ObjCOptional("application:configurationForConnectingSceneSession:options:")
    func application(_ application: UIApplication, configurationForConnecting session: UISceneSession,
                     options: UISceneConnectionOptions) -> UISceneConfiguration?
}
