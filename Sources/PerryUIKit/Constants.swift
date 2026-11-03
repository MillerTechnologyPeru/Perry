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
    static let UIApplicationDidReceiveMemoryWarningNotification = "UIApplicationDidReceiveMemoryWarningNotification"
    static let UIApplicationSignificantTimeChangeNotification = "UIApplicationSignificantTimeChangeNotification"
    static let UIApplicationProtectedDataWillBecomeUnavailable = "UIApplicationProtectedDataWillBecomeUnavailable"
    static let UIApplicationProtectedDataDidBecomeAvailable = "UIApplicationProtectedDataDidBecomeAvailable"
    static let UIApplicationDidChangeStatusBarOrientationNotification = "UIApplicationDidChangeStatusBarOrientationNotification"
    static let UIApplicationWillChangeStatusBarOrientationNotification = "UIApplicationWillChangeStatusBarOrientationNotification"
    static let UIApplicationDidChangeStatusBarFrameNotification = "UIApplicationDidChangeStatusBarFrameNotification"
    static let UIApplicationLaunchOptionsURLKey = "UIApplicationLaunchOptionsURLKey"
    static let UIApplicationLaunchOptionsSourceApplicationKey = "UIApplicationLaunchOptionsSourceApplicationKey"
    static let UIApplicationLaunchOptionsRemoteNotificationKey = "UIApplicationLaunchOptionsRemoteNotificationKey"
    static let UIApplicationLaunchOptionsLocalNotificationKey = "UIApplicationLaunchOptionsLocalNotificationKey"
    static let UIApplicationLaunchOptionsAnnotationKey = "UIApplicationLaunchOptionsAnnotationKey"
    static let UIKeyboardAnimationCurveUserInfoKey = "UIKeyboardAnimationCurveUserInfoKey"
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

/// Font text styles.
@ObjCConstants
enum TextStyles {
    static let UIFontTextStyleLargeTitle = "UICTFontTextStyleLargeTitle"
    static let UIFontTextStyleTitle1 = "UICTFontTextStyleTitle1"
    static let UIFontTextStyleTitle2 = "UICTFontTextStyleTitle2"
    static let UIFontTextStyleTitle3 = "UICTFontTextStyleTitle3"
    static let UIFontTextStyleHeadline = "UICTFontTextStyleHeadline"
    static let UIFontTextStyleSubheadline = "UICTFontTextStyleSubhead"
    static let UIFontTextStyleBody = "UICTFontTextStyleBody"
    static let UIFontTextStyleCallout = "UICTFontTextStyleCallout"
    static let UIFontTextStyleFootnote = "UICTFontTextStyleFootnote"
    static let UIFontTextStyleCaption1 = "UICTFontTextStyleCaption1"
    static let UIFontTextStyleCaption2 = "UICTFontTextStyleCaption2"
}

/// More notification names, and Core Animation's transition action key.
@ObjCConstants
enum MoreNotifications {
    static let UIMenuControllerWillShowMenuNotification = "UIMenuControllerWillShowMenuNotification"
    static let UIMenuControllerDidShowMenuNotification = "UIMenuControllerDidShowMenuNotification"
    static let UIMenuControllerWillHideMenuNotification = "UIMenuControllerWillHideMenuNotification"
    static let UIMenuControllerDidHideMenuNotification = "UIMenuControllerDidHideMenuNotification"
    static let UIContentSizeCategoryDidChangeNotification = "UIContentSizeCategoryDidChangeNotification"
    static let UIKeyboardWillShowNotification = "UIKeyboardWillShowNotification"
    static let UIKeyboardWillChangeFrameNotification = "UIKeyboardWillChangeFrameNotification"
    static let UIKeyboardDidChangeFrameNotification = "UIKeyboardDidChangeFrameNotification"
    static let UILocalNotificationDefaultSoundName = "UILocalNotificationDefaultSoundName"
    static let UIKeyboardDidShowNotification = "UIKeyboardDidShowNotification"
    static let UIKeyboardWillHideNotification = "UIKeyboardWillHideNotification"
    static let UIKeyboardDidHideNotification = "UIKeyboardDidHideNotification"
    static let UIKeyboardFrameEndUserInfoKey = "UIKeyboardFrameEndUserInfoKey"
    static let UIKeyboardFrameBeginUserInfoKey = "UIKeyboardFrameBeginUserInfoKey"
    static let UIKeyboardAnimationDurationUserInfoKey = "UIKeyboardAnimationDurationUserInfoKey"
    static let UIDeviceOrientationDidChangeNotification = "UIDeviceOrientationDidChangeNotification"
    static let UITextViewTextDidChangeNotification = "UITextViewTextDidChangeNotification"
    static let UITextFieldTextDidChangeNotification = "UITextFieldTextDidChangeNotification"
    static let UITextFieldTextDidBeginEditingNotification = "UITextFieldTextDidBeginEditingNotification"
    static let UITextFieldTextDidEndEditingNotification = "UITextFieldTextDidEndEditingNotification"
}

/// NSAttributedString's attribute names, as UIKit adds them.
@ObjCConstants
enum AttributeNames {
    static let NSFontAttributeName = "NSFont"
    static let NSForegroundColorAttributeName = "NSColor"
    static let NSBackgroundColorAttributeName = "NSBackgroundColor"
    static let NSParagraphStyleAttributeName = "NSParagraphStyle"
    static let NSLinkAttributeName = "NSLink"
    static let NSKernAttributeName = "NSKern"
    static let NSUnderlineStyleAttributeName = "NSUnderline"
    static let NSStrikethroughStyleAttributeName = "NSStrikethrough"
}
