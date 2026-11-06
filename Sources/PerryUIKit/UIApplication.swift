import CPerryGeometry
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
    /// The status bar, which is not drawn: what apps set, read back.
    nonisolated(unsafe) static var statusBarHidden = false
    nonisolated(unsafe) static var statusBarStyle = 0
    nonisolated(unsafe) static var ignoringInteractionEvents = 0
    nonisolated(unsafe) static var supportsShakeToEdit = true
    nonisolated(unsafe) static var userNotificationSettings: UIUserNotificationSettings?
    /// The last background task identifier given out;
    /// UIBackgroundTaskInvalid is 0.
    nonisolated(unsafe) static var lastBackgroundTask: UInt = 0

    static func nextBackgroundTask() -> UInt {
        lastBackgroundTask += 1
        return lastBackgroundTask
    }

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

    /// Perry's: ends the app as closing its window does, through the
    /// background and termination, for a controller's quit buttons.
    @ObjCMethod("_perryTerminate") func perryTerminate() { Lifecycle.terminate() }

    @ObjCMethod("delegate")
    func delegate() -> NSObject? { Application.delegate }

    @ObjCMethod("setDelegate:")
    func setDelegate(_ delegate: NSObject?) { Application.delegate = delegate }

    @ObjCMethod("applicationState")
    func applicationState() -> Int { Application.state.rawValue }

    // MARK: Background tasks

    /// Background tasks: the app is never suspended, so a task runs until
    /// it ends and its expiration handler is never called.
    @ObjCMethod("beginBackgroundTaskWithExpirationHandler:")
    func beginBackgroundTask(expirationHandler handler: UnsafeMutableRawPointer?) -> UInt { Application.nextBackgroundTask() }

    @ObjCMethod("beginBackgroundTaskWithName:expirationHandler:")
    func beginBackgroundTask(name: NSObject?, expirationHandler handler: UnsafeMutableRawPointer?) -> UInt {
        Application.nextBackgroundTask()
    }

    @ObjCMethod("endBackgroundTask:") func endBackgroundTask(_ identifier: UInt) {}
    @ObjCMethod("backgroundTimeRemaining") func backgroundTimeRemaining() -> Double { .greatestFiniteMagnitude }

    // MARK: The status bar

    @ObjCMethod("isStatusBarHidden") func isStatusBarHidden() -> Bool { Application.statusBarHidden }
    @ObjCMethod("setStatusBarHidden:") func setStatusBarHidden(_ hidden: Bool) { Application.statusBarHidden = hidden }
    @ObjCMethod("setStatusBarHidden:animated:") func setStatusBarHidden(_ hidden: Bool, animated: Bool) { Application.statusBarHidden = hidden }
    @ObjCMethod("setStatusBarHidden:withAnimation:") func setStatusBarHidden(_ hidden: Bool, withAnimation animation: Int) {
        Application.statusBarHidden = hidden
    }
    @ObjCMethod("statusBarStyle") func statusBarStyle() -> Int { Application.statusBarStyle }
    @ObjCMethod("setStatusBarStyle:") func setStatusBarStyle(_ style: Int) { Application.statusBarStyle = style }
    @ObjCMethod("setStatusBarStyle:animated:") func setStatusBarStyle(_ style: Int, animated: Bool) { Application.statusBarStyle = style }
    @ObjCMethod("statusBarOrientation") func statusBarOrientation() -> Int { Screen.orientation }

    /// The delegate's answer, else the orientations Info.plist lists, as a
    /// UIInterfaceOrientationMask (portrait 2, upside down 4, landscape
    /// left 16, landscape right 8).
    @ObjCMethod("supportedInterfaceOrientationsForWindow:")
    func supportedInterfaceOrientations(for window: UIWindow?) -> UInt {
        if let delegate = Application.delegate, delegate.responds(to: "application:supportedInterfaceOrientationsForWindow:") {
            return delegate.sendSupportedInterfaceOrientations(self, for: window)
        }
        let bundle = NSBundle.main()
        let names = (bundle.infoObject(forKey: "UISupportedInterfaceOrientations~iphone")
            ?? bundle.infoObject(forKey: "UISupportedInterfaceOrientations"))?.as(NSArray.self)?.elements.map { $0.stringValue } ?? []
        let masks: [String: UInt] = [
            "UIInterfaceOrientationPortrait": 2, "UIInterfaceOrientationPortraitUpsideDown": 4,
            "UIInterfaceOrientationLandscapeLeft": 16, "UIInterfaceOrientationLandscapeRight": 8,
        ]
        let mask = names.reduce(0) { $0 | (masks[$1] ?? 0) }
        return mask == 0 ? 26 : mask
    }
    @ObjCMethod("setStatusBarOrientation:") func setStatusBarOrientation(_ orientation: Int) {}
    @ObjCMethod("setStatusBarOrientation:animated:") func setStatusBarOrientation(_ orientation: Int, animated: Bool) {}
    @ObjCMethod("statusBarOrientationAnimationDuration") func statusBarOrientationAnimationDuration() -> Double { 0.3 }
    @ObjCMethod("statusBarFrame")
    func statusBarFrame() -> CGRect {
        CGRect(x: 0, y: 0, width: Screen.bounds.width, height: Application.statusBarHidden ? 0 : Screen.safeAreaInsets.top)
    }
    @ObjCMethod("isIgnoringInteractionEvents") func isIgnoringInteractionEvents() -> Bool { Application.ignoringInteractionEvents > 0 }

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

    /// Shaking undoes nothing here; what apps set is read back.
    @ObjCMethod("applicationSupportsShakeToEdit") func applicationSupportsShakeToEdit() -> Bool { Application.supportsShakeToEdit }
    @ObjCMethod("setApplicationSupportsShakeToEdit:") func setApplicationSupportsShakeToEdit(_ supports: Bool) {
        Application.supportsShakeToEdit = supports
    }

    @ObjCMethod("isIdleTimerDisabled") func isIdleTimerDisabled() -> Bool { false }
    /// UIBackgroundRefreshStatus: denied 1. Apps are never woken in the
    /// background here.
    @ObjCMethod("backgroundRefreshStatus") func backgroundRefreshStatus() -> Int { 1 }
    @ObjCMethod("setMinimumBackgroundFetchInterval:") func setMinimumBackgroundFetchInterval(_ interval: Double) {}
    @ObjCMethod("setIdleTimerDisabled:") func setIdleTimerDisabled(_ disabled: Bool) {}
    @ObjCMethod("isNetworkActivityIndicatorVisible") func isNetworkActivityIndicatorVisible() -> Bool { false }
    @ObjCMethod("setNetworkActivityIndicatorVisible:") func setNetworkActivityIndicatorVisible(_ visible: Bool) {}
    @ObjCMethod("applicationIconBadgeNumber") func applicationIconBadgeNumber() -> Int { 0 }
    @ObjCMethod("setApplicationIconBadgeNumber:") func setApplicationIconBadgeNumber(_ number: Int) {}
    @ObjCMethod("beginIgnoringInteractionEvents") func beginIgnoringInteractionEvents() { Application.ignoringInteractionEvents += 1 }
    @ObjCMethod("endIgnoringInteractionEvents") func endIgnoringInteractionEvents() {
        Application.ignoringInteractionEvents = max(0, Application.ignoringInteractionEvents - 1)
    }
    @ObjCMethod("registerForRemoteNotifications") func registerForRemoteNotifications() {}
    @ObjCMethod("isRegisteredForRemoteNotifications") func isRegisteredForRemoteNotifications() -> Bool { false }

    /// Notification settings are granted as asked, and the delegate hears
    /// so afterwards, as on iOS once the user has answered.
    @ObjCMethod("registerUserNotificationSettings:")
    func registerUserNotificationSettings(_ settings: UIUserNotificationSettings?) {
        Application.userNotificationSettings = settings
        Updates.afterPass {
            guard let delegate = Application.delegate, let settings,
                  delegate.responds(to: "application:didRegisterUserNotificationSettings:") else { return }
            delegate.sendApplication(self, didRegister: settings)
        }
    }

    @ObjCMethod("currentUserNotificationSettings")
    func currentUserNotificationSettings() -> UIUserNotificationSettings? {
        Application.userNotificationSettings
            ?? UIUserNotificationSettings.settings(UIUserNotificationSettings.objCClass, types: 0, categories: nil)
                .unsafeCast(to: UIUserNotificationSettings.self)
    }
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

    /// The launch as delegates heard of it before iOS 3, which those that
    /// don't take the options still do.
    @ObjCOptional("applicationDidFinishLaunching:")
    func applicationDidFinishLaunching(_ application: UIApplication)

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

extension NSObject {
    @ObjCMethod("application:didRegisterUserNotificationSettings:")
    func sendApplication(_ application: UIApplication, didRegister settings: UIUserNotificationSettings)
}

extension NSObject {
    @ObjCMethod("application:supportedInterfaceOrientationsForWindow:")
    func sendSupportedInterfaceOrientations(_ application: UIApplication, for window: UIWindow?) -> UInt
}
