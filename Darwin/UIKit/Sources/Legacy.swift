import Foundation

// UIKit's Swift API from before Swift 4.2 that programs built then still
// call: the orientation macros as functions, the printing error codes as
// globals, UIApplicationMain with Swift 4's argv, and alert views' and
// action sheets' variadic initializers, which Swift can't import.

// MARK: - Orientations

@available(swift, obsoleted: 4.2, renamed: "getter:UIDeviceOrientation.isLandscape(self:)")
public func UIDeviceOrientationIsLandscape(_ orientation: UIDeviceOrientation) -> Bool {
    orientation.isLandscape
}

@available(swift, obsoleted: 4.2, renamed: "getter:UIDeviceOrientation.isPortrait(self:)")
public func UIDeviceOrientationIsPortrait(_ orientation: UIDeviceOrientation) -> Bool {
    orientation.isPortrait
}

@available(swift, obsoleted: 4.2, renamed: "getter:UIDeviceOrientation.isValidInterfaceOrientation(self:)")
public func UIDeviceOrientationIsValidInterfaceOrientation(_ orientation: UIDeviceOrientation) -> Bool {
    orientation.isValidInterfaceOrientation
}

@available(swift, obsoleted: 4.2, renamed: "getter:UIInterfaceOrientation.isPortrait(self:)")
public func UIInterfaceOrientationIsPortrait(_ orientation: UIInterfaceOrientation) -> Bool {
    orientation.isPortrait
}

@available(swift, obsoleted: 4.2, renamed: "getter:UIInterfaceOrientation.isLandscape(self:)")
public func UIInterfaceOrientationIsLandscape(_ orientation: UIInterfaceOrientation) -> Bool {
    orientation.isLandscape
}

// MARK: - Printing errors

@available(swift, obsoleted: 4.2, renamed: "UIPrintError.Code.notAvailable.rawValue")
public var UIPrintingNotAvailableError: Int { UIPrintError.Code.notAvailable.rawValue }

@available(swift, obsoleted: 4.2, renamed: "UIPrintError.Code.noContent.rawValue")
public var UIPrintNoContentError: Int { UIPrintError.Code.noContent.rawValue }

@available(swift, obsoleted: 4.2, renamed: "UIPrintError.Code.unknownImageFormat.rawValue")
public var UIPrintUnknownImageFormatError: Int { UIPrintError.Code.unknownImageFormat.rawValue }

@available(swift, obsoleted: 4.2, renamed: "UIPrintError.Code.jobFailed.rawValue")
public var UIPrintJobFailedError: Int { UIPrintError.Code.jobFailed.rawValue }

// MARK: - UIApplicationMain

/// UIApplicationMain with argv as Swift 4's CommandLine.unsafeArgv was
/// typed: the same pointers.
@available(swift, deprecated: 4.2, message: "Use the overload of UIApplicationMain where the type of the second parameter is UnsafeMutablePointer<UnsafeMutablePointer<Int8>?>, which is the same as the type of CommandLine.unsafeArgv.")
@available(watchOS, unavailable)
public func UIApplicationMain(_ argc: Int32, _ argv: UnsafeMutablePointer<UnsafeMutablePointer<Int8>>!,
                              _ principalClassName: String?, _ delegateClassName: String?) -> Int32 {
    let arguments = UnsafeMutableRawPointer(argv!).assumingMemoryBound(to: UnsafeMutablePointer<Int8>?.self)
    return UIApplicationMain(argc, arguments, principalClassName, delegateClassName)
}

// MARK: - Alert views and action sheets

@available(iOS, introduced: 2.0, deprecated: 8.3, message: "UIActionSheet is deprecated. Use UIAlertController with a preferredStyle of UIAlertControllerStyleActionSheet instead")
@available(visionOS, unavailable)
extension UIActionSheet {
    /// An action sheet with the destructive button first, then the others,
    /// then the cancel button, as the Objective-C initializer lays them out.
    @MainActor @preconcurrency
    public convenience init(title: String?, delegate: (any UIActionSheetDelegate)?, cancelButtonTitle: String?,
                            destructiveButtonTitle: String?, otherButtonTitles firstButtonTitle: String,
                            _ moreButtonTitles: String...) {
        self.init(frame: .zero)
        self.title = title ?? ""
        self.delegate = delegate
        if let destructiveButtonTitle {
            destructiveButtonIndex = addButton(withTitle: destructiveButtonTitle)
        }
        addButton(withTitle: firstButtonTitle)
        for buttonTitle in moreButtonTitles {
            addButton(withTitle: buttonTitle)
        }
        if let cancelButtonTitle {
            cancelButtonIndex = addButton(withTitle: cancelButtonTitle)
        }
    }
}

@available(iOS, introduced: 2.0, deprecated: 9.0, message: "UIAlertView is deprecated. Use UIAlertController with a preferredStyle of UIAlertControllerStyleAlert instead")
@available(visionOS, unavailable)
extension UIAlertView {
    /// An alert with the cancel button first, then the others, as the
    /// Objective-C initializer lays them out.
    @MainActor @preconcurrency
    public convenience init(title: String, message: String, delegate: (any UIAlertViewDelegate)?,
                            cancelButtonTitle: String?, otherButtonTitles firstButtonTitle: String,
                            _ moreButtonTitles: String...) {
        self.init(frame: .zero)
        self.title = title
        self.message = message
        self.delegate = delegate
        if let cancelButtonTitle {
            cancelButtonIndex = addButton(withTitle: cancelButtonTitle)
        }
        addButton(withTitle: firstButtonTitle)
        for buttonTitle in moreButtonTitles {
            addButton(withTitle: buttonTitle)
        }
    }
}

// MARK: - Text directions

@available(iOS 7.0, *)
extension UITextDirection {
    public static func storage(_ direction: UITextStorageDirection) -> UITextDirection {
        UITextDirection(rawValue: direction.rawValue)
    }

    public static func layout(_ direction: UITextLayoutDirection) -> UITextDirection {
        UITextDirection(rawValue: direction.rawValue)
    }
}
