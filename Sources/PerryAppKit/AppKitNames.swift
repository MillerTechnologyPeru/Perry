import PerryObjCInterop

// AppKit's string constants that name things Perry doesn't do yet, or
// does without them: pasteboard types, notifications, bindings and their
// markers, attributes and options, as Mac OS X 10.6 spelled them. Programs
// pass them as they are, so a missing one would bind to something that
// isn't a string.

@ObjCConstants
enum AppKitNames {
    // Pasteboard types, before UTIs.
    static let NSColorPboardType = "NSColor pasteboard type"
    static let NSFileContentsPboardType = "NXFileContentsPboardType"
    static let NSFilesPromisePboardType = "Apple files promise pasteboard type"
    static let NSFontPboardType = "NeXT font pasteboard type"
    static let NSHTMLPboardType = "Apple HTML pasteboard type"
    static let NSPDFPboardType = "Apple PDF pasteboard type"
    static let NSPICTPboardType = "Apple PICT pasteboard type"
    static let NSRTFPboardType = "NeXT Rich Text Format v1.0 pasteboard type"
    static let NSRTFDPboardType = "NeXT RTFD pasteboard type"
    static let NSTabularTextPboardType = "NeXT tabular text pasteboard type"
    static let NSTIFFPboardType = "NeXT TIFF v4.0 pasteboard type"

    // Notifications.
    static let NSDrawerDidCloseNotification = "NSDrawerDidCloseNotification"
    static let NSOutlineViewColumnDidResizeNotification = "NSOutlineViewColumnDidResizeNotification"
    static let NSTextStorageDidProcessEditingNotification = "NSTextStorageDidProcessEditingNotification"
    static let NSTextViewDidChangeSelectionNotification = "NSTextViewDidChangeSelectionNotification"
    static let NSToolbarWillAddItemNotification = "NSToolbarWillAddItemNotification"
    static let NSToolbarDidRemoveItemNotification = "NSToolbarDidRemoveItemNotification"
    static let NSWindowWillBeginSheetNotification = "NSWindowWillBeginSheetNotification"
    static let NSWindowDidEndSheetNotification = "NSWindowDidEndSheetNotification"

    // Bindings, and the markers a controller answers in place of a value.
    static let NSFontBoldBinding = "fontBold"
    static let NSFontItalicBinding = "fontItalic"
    static let NSIsControllerMarker = "NSIsControllerMarker"
    static let NSMultipleValuesMarker = "NSMultipleValuesMarker"
    static let NSNoSelectionMarker = "NSNoSelectionMarker"
    static let NSNotApplicableMarker = "NSNotApplicableMarker"

    // Accessibility.
    static let NSAccessibilityRoleAttribute = "AXRole"
    static let NSAccessibilityTitleAttribute = "AXTitle"
    static let NSAccessibilityValueAttribute = "AXValue"
    static let NSAccessibilityTextFieldRole = "AXTextField"

    // Color spaces.
    static let NSCalibratedWhiteColorSpace = "NSCalibratedWhiteColorSpace"
    static let NSDeviceWhiteColorSpace = "NSDeviceWhiteColorSpace"
    static let NSPatternColorSpace = "NSPatternColorSpace"

    // Text: document options and types, attributes, font features.
    static let NSCharacterEncodingDocumentOption = "CharacterEncoding"
    static let NSDocumentTypeDocumentOption = "DocumentType"
    static let NSRTFDTextDocumentType = "NSRTFD"
    static let NSStrikethroughColorAttributeName = "NSStrikethroughColor"
    static let NSFontFeatureSettingsAttribute = "NSCTFontFeatureSettingsAttribute"
    static let NSFontFeatureTypeIdentifierKey = "CTFeatureTypeIdentifier"
    static let NSFontFeatureSelectorIdentifierKey = "CTFeatureSelectorIdentifier"

    // Images by name.
    static let NSImageNameLeftFacingTriangleTemplate = "NSLeftFacingTriangleTemplate"
    static let NSImageNameRightFacingTriangleTemplate = "NSRightFacingTriangleTemplate"
    static let NSImageNameUser = "NSUser"

    // View animations, printing and the workspace.
    static let NSViewAnimationTargetKey = "NSViewAnimationTargetKey"
    static let NSViewAnimationEffectKey = "NSViewAnimationEffectKey"
    static let NSViewAnimationFadeOutEffect = "NSViewAnimationFadeOutEffect"
    static let NSPrintScalingFactor = "NSScalingFactor"
    static let NSWorkspaceRecycleOperation = "recycle"
}
