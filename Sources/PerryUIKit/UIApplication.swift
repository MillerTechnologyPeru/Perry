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
    /// The quick actions the app set, kept for it to read back.
    nonisolated(unsafe) static var shortcutItems: NSObject?
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

    /// No local notifications are ever scheduled or delivered.
    @ObjCMethod("cancelAllLocalNotifications") func cancelAllLocalNotifications() {}
    @ObjCMethod("scheduledLocalNotifications") func scheduledLocalNotifications() -> NSObject { NSMutableArray.of([]) }
    @ObjCMethod("setScheduledLocalNotifications:") func setScheduledLocalNotifications(_ notifications: NSObject?) {}
    @ObjCMethod("cancelLocalNotification:") func cancelLocalNotification(_ notification: NSObject?) {}
    @ObjCMethod("scheduleLocalNotification:") func scheduleLocalNotification(_ notification: NSObject?) {}
    @ObjCMethod("presentLocalNotificationNow:") func presentLocalNotificationNow(_ notification: NSObject?) {}

    /// The text size the user prefers: the default, large.
    @ObjCMethod("preferredContentSizeCategory") func preferredContentSizeCategory() -> String { "UICTContentSizeCategoryL" }

    /// A finger another provider puts on the screen, at a point in the
    /// screen's coordinates (GameController's, for a gamepad's button that
    /// stands for a touch): phase 0 is down, 1 moved, 2 up.
    @ObjCMethod("_perryFinger:phase:x:y:")
    func finger(_ finger: UInt, phase: Int, x: Double, y: Double) {
        let point = CGPoint(x: CGFloat(x), y: CGFloat(y))
        switch phase {
        case 0: Touches.down(at: point, finger: UInt64(finger))
        case 1: Touches.move(to: point, finger: UInt64(finger))
        default: Touches.up(at: point, finger: UInt64(finger))
        }
    }

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

    /// The app opens its own URLs (IncomingURLs); no other app can open
    /// URLs here.
    @ObjCMethod("canOpenURL:") func canOpenURL(_ url: NSObject?) -> Bool { IncomingURLs.isOwn(url) }

    @ObjCMethod("openURL:")
    func openURL(_ url: NSObject?) -> Bool {
        if let url, IncomingURLs.isOwn(url) { return IncomingURLs.open(url) }
        uikitWarning("no app to open \(url?.describedByObject() ?? "a URL")")
        return false
    }

    @ObjCMethod("openURL:options:completionHandler:")
    func openURL(_ url: NSObject?, options: NSObject?, completionHandler: ObjCBlock?) {
        let opened = openURL(url)
        completionHandler.map { Blocks.call($0, opened) }
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
    /// Home screen quick actions, which have no home screen to show on.
    @ObjCMethod("shortcutItems") func shortcutItems() -> NSObject? { Application.shortcutItems }
    @ObjCMethod("setShortcutItems:") func setShortcutItems(_ items: NSObject?) {
        Application.shortcutItems = items
    }
    @ObjCMethod("beginIgnoringInteractionEvents") func beginIgnoringInteractionEvents() { Application.ignoringInteractionEvents += 1 }
    @ObjCMethod("endIgnoringInteractionEvents") func endIgnoringInteractionEvents() {
        Application.ignoringInteractionEvents = max(0, Application.ignoringInteractionEvents - 1)
    }
    /// There is no push service to register with: the delegate hears that
    /// registering failed, afterwards, as the iOS Simulator's did, so code
    /// awaiting a device token gets an answer.
    @ObjCMethod("registerForRemoteNotifications")
    func registerForRemoteNotifications() {
        Updates.afterPass {
            guard let delegate = Application.delegate,
                  delegate.responds(to: "application:didFailToRegisterForRemoteNotificationsWithError:") else { return }
            let info = NSMutableDictionary.empty()
            info.set(string: "remote notifications are not supported on this device", forKey: "NSLocalizedDescription")
            // REMOTE_NOTIFICATION_SIMULATOR_NOT_SUPPORTED_ERROR.
            let error = NSErrorObject.make(domain: "NSCocoaErrorDomain", code: 3010, userInfo: info)
            delegate.sendApplication(self, didFailToRegisterForRemoteNotificationsWithError: error)
        }
    }
    /// iOS 3's form, which names the kinds of notification wanted.
    @ObjCMethod("registerForRemoteNotificationTypes:") func registerForRemoteNotifications(types: UInt) {}
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
    @ObjCMethod("application:didFailToRegisterForRemoteNotificationsWithError:")
    func sendApplication(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: NSObject)

    @ObjCMethod("application:supportedInterfaceOrientationsForWindow:")
    func sendSupportedInterfaceOrientations(_ application: UIApplication, for window: UIWindow?) -> UInt
}

// MARK: - Quick actions

final class ShortcutIconState: ObjectState {
    /// UIApplicationShortcutIconType, for an icon of a standard type.
    var type = 0
    var templateImageName: String?
    var systemImageName: String?
}

/// A quick action's icon: a standard type, or an image by name.
@ObjCClass("UIApplicationShortcutIcon")
open class UIApplicationShortcutIcon: NSObject {
    static let states = StateTable<ShortcutIconState>()
    var iconState: ShortcutIconState { UIApplicationShortcutIcon.states[objcObject] }

    static func make(_ cls: ObjCClass, _ configure: (ShortcutIconState) -> Void) -> UIApplicationShortcutIcon {
        let icon = cls.object.allocated().unsafeCast(to: UIApplicationShortcutIcon.self)
        configure(icon.iconState)
        return icon
    }

    @ObjCClassMethod("iconWithType:")
    static func icon(_ cls: ObjCClass, type: Int) -> UIApplicationShortcutIcon { make(cls) { $0.type = type } }

    @ObjCClassMethod("iconWithTemplateImageName:")
    static func icon(_ cls: ObjCClass, templateImageName name: String) -> UIApplicationShortcutIcon {
        make(cls) { $0.templateImageName = name }
    }

    @ObjCClassMethod("iconWithSystemImageName:")
    static func icon(_ cls: ObjCClass, systemImageName name: String) -> UIApplicationShortcutIcon {
        make(cls) { $0.systemImageName = name }
    }

    /// Immutable: a copy is the icon itself.
    @ObjCMethod("copyWithZone:") func copy(zone: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer { ObjCRuntime.retain(objcObject)! }

    @ObjCMethod("dealloc")
    func dealloc() {
        UIApplicationShortcutIcon.states.remove(objcObject)
        ObjCRuntime.superDealloc(objcObject, definedOn: UIApplicationShortcutIcon.objCClass.pointer)
    }
}

final class ShortcutItemState: ObjectState {
    var type = ""
    var localizedTitle = ""
    var localizedSubtitle: String?
    var icon: UIApplicationShortcutIcon?
    var userInfo: NSObject?
    var targetContentIdentifier: NSObject?
}

/// A home screen quick action. There is no home screen here to show it;
/// apps set them and read them back.
@ObjCClass("UIApplicationShortcutItem")
open class UIApplicationShortcutItem: NSObject {
    static let states = StateTable<ShortcutItemState>()
    var itemState: ShortcutItemState { UIApplicationShortcutItem.states[objcObject] }

    @ObjCMethod("initWithType:localizedTitle:localizedSubtitle:icon:userInfo:")
    func initialize(type: String, localizedTitle title: String, localizedSubtitle subtitle: String?,
                    icon: UIApplicationShortcutIcon?, userInfo: NSObject?) -> Self {
        itemState.type = type
        itemState.localizedTitle = title
        itemState.localizedSubtitle = subtitle
        itemState.icon = icon
        itemState.userInfo = userInfo
        return self
    }

    @ObjCMethod("initWithType:localizedTitle:")
    func initialize(type: String, localizedTitle title: String) -> Self {
        initialize(type: type, localizedTitle: title, localizedSubtitle: nil, icon: nil, userInfo: nil)
    }

    @ObjCMethod("type") func type() -> String { itemState.type }
    @ObjCMethod("localizedTitle") func localizedTitle() -> String { itemState.localizedTitle }
    @ObjCMethod("localizedSubtitle") func localizedSubtitle() -> String? { itemState.localizedSubtitle }
    @ObjCMethod("icon") func icon() -> UIApplicationShortcutIcon? { itemState.icon }
    @ObjCMethod("userInfo") func userInfo() -> NSObject? { itemState.userInfo }
    @ObjCMethod("targetContentIdentifier") func targetContentIdentifier() -> NSObject? { itemState.targetContentIdentifier }

    /// A new item of `cls` with this one's values, +1.
    func copied(as cls: ObjCClass) -> UnsafeMutableRawPointer {
        let copy = cls.object.newInstance().unsafeCast(to: UIApplicationShortcutItem.self)
        let state = copy.itemState, source = itemState
        state.type = source.type
        state.localizedTitle = source.localizedTitle
        state.localizedSubtitle = source.localizedSubtitle
        state.icon = source.icon
        state.userInfo = source.userInfo
        state.targetContentIdentifier = source.targetContentIdentifier
        return copy.objcObject
    }

    @ObjCMethod("copyWithZone:")
    func copy(zone: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer { copied(as: UIApplicationShortcutItem.objCClass) }

    @ObjCMethod("mutableCopyWithZone:")
    func mutableCopy(zone: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer { copied(as: UIMutableApplicationShortcutItem.objCClass) }

    @ObjCMethod("isEqual:")
    func isEqual(_ other: NSObject?) -> Bool {
        guard let other = other?.as(UIApplicationShortcutItem.self) else { return false }
        return other.itemState.type == itemState.type && other.itemState.localizedTitle == itemState.localizedTitle
            && other.itemState.localizedSubtitle == itemState.localizedSubtitle
    }

    @ObjCMethod("hash") func hashValue() -> UInt { UInt(bitPattern: itemState.type.hashValue) }

    @ObjCMethod("dealloc")
    func dealloc() {
        UIApplicationShortcutItem.states.remove(objcObject)
        ObjCRuntime.superDealloc(objcObject, definedOn: UIApplicationShortcutItem.objCClass.pointer)
    }
}

@ObjCClass("UIMutableApplicationShortcutItem")
open class UIMutableApplicationShortcutItem: UIApplicationShortcutItem {
    @ObjCMethod("setType:") func setType(_ type: String) { itemState.type = type }
    @ObjCMethod("setLocalizedTitle:") func setLocalizedTitle(_ title: String) { itemState.localizedTitle = title }
    @ObjCMethod("setLocalizedSubtitle:") func setLocalizedSubtitle(_ subtitle: String?) { itemState.localizedSubtitle = subtitle }
    @ObjCMethod("setIcon:") func setIcon(_ icon: UIApplicationShortcutIcon?) { itemState.icon = icon }
    @ObjCMethod("setUserInfo:") func setUserInfo(_ userInfo: NSObject?) { itemState.userInfo = userInfo }
    @ObjCMethod("setTargetContentIdentifier:") func setTargetContentIdentifier(_ identifier: NSObject?) {
        itemState.targetContentIdentifier = identifier
    }
}
