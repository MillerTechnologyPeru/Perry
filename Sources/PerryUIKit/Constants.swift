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
    static let UISceneWillDeactivateNotification = "UISceneWillDeactivateNotification"
    static let UISceneDidEnterBackgroundNotification = "UISceneDidEnterBackgroundNotification"
    static let UISceneDidDisconnectNotification = "UISceneDidDisconnectNotification"
    static let UIScreenCapturedDidChangeNotification = "UIScreenCapturedDidChangeNotification"
    static let UITextViewTextDidBeginEditingNotification = "UITextViewTextDidBeginEditingNotification"
    static let UITextViewTextDidEndEditingNotification = "UITextViewTextDidEndEditingNotification"
    static let UIApplicationOpenURLOptionsAnnotationKey = "UIApplicationOpenURLOptionsAnnotationKey"
    static let UIApplicationOpenURLOptionsSourceApplicationKey = "UIApplicationOpenURLOptionsSourceApplicationKey"
    static let UIApplicationOpenSettingsURLString = "app-settings:"
    static let UITransitionContextFromViewControllerKey = "UITransitionContextFromViewControllerKey"
    static let UITransitionContextToViewControllerKey = "UITransitionContextToViewControllerKey"
    static let UICollectionElementKindSectionHeader = "UICollectionElementKindSectionHeader"
    static let UICollectionElementKindSectionFooter = "UICollectionElementKindSectionFooter"
    static let UIImagePickerControllerOriginalImage = "UIImagePickerControllerOriginalImage"
    static let UIImagePickerControllerEditedImage = "UIImagePickerControllerEditedImage"
    static let UIActivityTypeSaveToCameraRoll = "com.apple.UIKit.activity.SaveToCameraRoll"
    static let UIPasteboardNameGeneral = "com.apple.UIKit.pboard.general"
    static let NSDocumentTypeDocumentOption = "DocumentType"
    static let NSHTMLTextDocumentType = "NSHTML"
}

/// Content size categories, as UIKit names them.
@ObjCConstants
enum ContentSizeCategories {
    static let UIContentSizeCategoryUnspecified = "_UICTContentSizeCategoryUnspecified"
    static let UIContentSizeCategoryExtraSmall = "UICTContentSizeCategoryXS"
    static let UIContentSizeCategorySmall = "UICTContentSizeCategoryS"
    static let UIContentSizeCategoryMedium = "UICTContentSizeCategoryM"
    static let UIContentSizeCategoryLarge = "UICTContentSizeCategoryL"
    static let UIContentSizeCategoryExtraLarge = "UICTContentSizeCategoryXL"
    static let UIContentSizeCategoryExtraExtraLarge = "UICTContentSizeCategoryXXL"
    static let UIContentSizeCategoryExtraExtraExtraLarge = "UICTContentSizeCategoryXXXL"
    static let UIContentSizeCategoryAccessibilityMedium = "UICTContentSizeCategoryAccessibilityM"
    static let UIContentSizeCategoryAccessibilityLarge = "UICTContentSizeCategoryAccessibilityL"
    static let UIContentSizeCategoryAccessibilityExtraLarge = "UICTContentSizeCategoryAccessibilityXL"
    static let UIContentSizeCategoryAccessibilityExtraExtraLarge = "UICTContentSizeCategoryAccessibilityXXL"
    static let UIContentSizeCategoryAccessibilityExtraExtraExtraLarge = "UICTContentSizeCategoryAccessibilityXXXL"
}

/// Font descriptor attributes and traits.
@ObjCConstants
enum FontDescriptorKeys {
    static let UIFontDescriptorFamilyAttribute = "NSFontFamilyAttribute"
    static let UIFontDescriptorNameAttribute = "NSFontNameAttribute"
    static let UIFontDescriptorFaceAttribute = "NSFontFaceAttribute"
    static let UIFontDescriptorSizeAttribute = "NSFontSizeAttribute"
    static let UIFontDescriptorTraitsAttribute = "NSCTFontTraitsAttribute"
    static let UIFontWeightTrait = "NSCTFontWeightTrait"
    static let UIFontWidthTrait = "NSCTFontProportionTrait"
    static let UIFontSlantTrait = "NSCTFontSlantTrait"
}

/// Text content types, the autofill hints.
@ObjCConstants
enum TextContentTypes {
    static let UITextContentTypeGivenName = "given-name"
    static let UITextContentTypeFamilyName = "family-name"
    static let UITextContentTypeEmailAddress = "email"
    static let UITextContentTypeTelephoneNumber = "tel"
    static let UITextContentTypeStreetAddressLine1 = "address-line1"
    static let UITextContentTypeAddressCity = "address-level2"
    static let UITextContentTypeAddressState = "address-level1"
    static let UITextContentTypePostalCode = "postal-code"
    static let UITextContentTypeOneTimeCode = "one-time-code"
    static let UITextContentTypeDateTime = "date-time"
    static let UITextContentTypeBirthdateDay = "bday-day"
    static let UITextContentTypeBirthdateMonth = "bday-month"
}

/// Content size categories in order, for comparing them.
private let sizeCategoryOrder = [
    "UICTContentSizeCategoryXS", "UICTContentSizeCategoryS", "UICTContentSizeCategoryM", "UICTContentSizeCategoryL",
    "UICTContentSizeCategoryXL", "UICTContentSizeCategoryXXL", "UICTContentSizeCategoryXXXL",
    "UICTContentSizeCategoryAccessibilityM", "UICTContentSizeCategoryAccessibilityL",
    "UICTContentSizeCategoryAccessibilityXL", "UICTContentSizeCategoryAccessibilityXXL",
    "UICTContentSizeCategoryAccessibilityXXXL",
]

/// NSComparisonResult of two content size categories.
@c(_UIContentSizeCategoryCompareToCategory)
public func UIContentSizeCategoryCompareToCategory(_ lhs: UnsafeMutableRawPointer?, _ rhs: UnsafeMutableRawPointer?) -> Int {
    func rank(_ category: UnsafeMutableRawPointer?) -> Int {
        category.flatMap { sizeCategoryOrder.firstIndex(of: NSObject($0).stringValue) } ?? 3
    }
    let (a, b) = (rank(lhs), rank(rhs))
    return a < b ? -1 : a > b ? 1 : 0
}

@c(_UIContentSizeCategoryIsAccessibilityCategory)
public func UIContentSizeCategoryIsAccessibilityCategory(_ category: UnsafeMutableRawPointer?) -> Bool {
    category.map { NSObject($0).stringValue.hasPrefix("UICTContentSizeCategoryAccessibility") } ?? false
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
    static let UIDeviceBatteryLevelDidChangeNotification = "UIDeviceBatteryLevelDidChangeNotification"
    static let UIDeviceBatteryStateDidChangeNotification = "UIDeviceBatteryStateDidChangeNotification"
    static let UIWindowDidResignKeyNotification = "UIWindowDidResignKeyNotification"
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

/// Activity types, and the services and text attributes of frameworks
/// UIKit stands in for: Social's, and CoreText's.
@ObjCConstants
enum ActivityConstants {
    static let UIActivityTypeAirDrop = "com.apple.UIKit.activity.AirDrop"
    static let UIActivityTypeAssignToContact = "com.apple.UIKit.activity.AssignToContact"
    static let UIActivityTypePostToFacebook = "com.apple.UIKit.activity.PostToFacebook"
    static let UIActivityTypePostToTwitter = "com.apple.UIKit.activity.PostToTwitter"
    static let UIActivityTypePostToWeibo = "com.apple.UIKit.activity.PostToWeibo"
    static let UIActivityTypePostToTencentWeibo = "com.apple.UIKit.activity.TencentWeibo"
    static let UIActivityTypeMail = "com.apple.UIKit.activity.Mail"
    static let UIActivityTypeMessage = "com.apple.UIKit.activity.Message"
    static let UIActivityTypeCopyToPasteboard = "com.apple.UIKit.activity.CopyToPasteboard"
    static let UIActivityTypePrint = "com.apple.UIKit.activity.Print"
    static let SLServiceTypeFacebook = "com.apple.social.facebook"
    static let SLServiceTypeTwitter = "com.apple.social.twitter"
    static let SLServiceTypeSinaWeibo = "com.apple.social.sinaweibo"
    static let SLServiceTypeTencentWeibo = "com.apple.social.tencentweibo"
    static let kCTForegroundColorAttributeName = "CTForegroundColor"
    static let kCTFontAttributeName = "NSFont"
}
