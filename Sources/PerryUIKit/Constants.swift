import PerryObjCInterop

/// Notification names.
@ObjCConstants
enum Notifications {
    static let UIApplicationDidFinishLaunchingNotification = "UIApplicationDidFinishLaunchingNotification"
    static let UIApplicationDidBecomeActiveNotification = "UIApplicationDidBecomeActiveNotification"
    static let UIApplicationWillResignActiveNotification = "UIApplicationWillResignActiveNotification"
    static let UIApplicationDidEnterBackgroundNotification = "UIApplicationDidEnterBackgroundNotification"
    static let UIApplicationWillEnterForegroundNotification = "UIApplicationWillEnterForegroundNotification"
    static let UIApplicationWillTerminateNotification = "UIApplicationWillTerminateNotification"
    static let UISceneWillConnectNotification = "UISceneWillConnectNotification"
    static let UISceneWillEnterForegroundNotification = "UISceneWillEnterForegroundNotification"
    static let UISceneDidActivateNotification = "UISceneDidActivateNotification"
}

/// Scene session roles.
@ObjCConstants
enum SessionRoles {
    static let UIWindowSceneSessionRoleApplication = "UIWindowSceneSessionRoleApplication"
    static let UIWindowSceneSessionRoleExternalDisplayNonInteractive = "UIWindowSceneSessionRoleExternalDisplayNonInteractive"
}
