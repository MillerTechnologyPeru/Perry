import PerryObjCInterop

// More of AppKit's string constants, with the values macOS 14's AppKit
// gives them: some are not their names. They are keys and names of
// things Perry keeps or doesn't do (find panel options, print panel
// summaries, text checking options), here so a program that names them
// links and compares equal strings.

@ObjCConstants
enum AppKitNamesMore {
    // Accessibility: Darwin's values are HIServices' kAX… strings.
    static let NSAccessibilityAnnouncementKey = "AXAnnouncementKey"
    static let NSAccessibilityAnnouncementRequestedNotification = "AXAnnouncementRequested"
    static let NSAccessibilityCheckBoxRole = "AXCheckBox"
    static let NSAccessibilityDisclosureTriangleRole = "AXDisclosureTriangle"
    static let NSAccessibilityLayoutAreaRole = "AXLayoutArea"
    static let NSAccessibilityLayoutChangedNotification = "AXLayoutChanged"
    static let NSAccessibilityMovedNotification = "AXMoved"
    static let NSAccessibilityOutlineRole = "AXOutline"
    static let NSAccessibilityPopUpButtonRole = "AXPopUpButton"
    static let NSAccessibilityPriorityKey = "AXPriorityKey"
    static let NSAccessibilityResizedNotification = "AXResized"
    static let NSAccessibilityRowCountChangedNotification = "AXRowCountChanged"
    static let NSAccessibilityRowRole = "AXRow"
    static let NSAccessibilityScrollAreaRole = "AXScrollArea"
    static let NSAccessibilitySelectedRowsChangedNotification = "AXSelectedRowsChanged"
    static let NSAccessibilityStaticTextRole = "AXStaticText"
    static let NSAccessibilityTableRole = "AXTable"
    static let NSAccessibilityTitleChangedNotification = "AXTitleChanged"
    static let NSAccessibilityUIElementDestroyedNotification = "AXUIElementDestroyed"
    static let NSAccessibilityUIElementsKey = "AXUIElementsKey"
    static let NSAccessibilityUnknownRole = "AXUnknown"

    // Text: a document attribute, and NSSpellChecker's option key.
    static let NSBackgroundColorDocumentAttribute = "BackgroundColor"
    static let NSTextCheckingOrthographyKey = "Orthography"

    // Notifications. A combo box here has no pop-up list, so its two are
    // never posted.
    static let NSComboBoxWillDismissNotification = "NSComboBoxWillDismissNotification"
    static let NSComboBoxWillPopUpNotification = "NSComboBoxWillPopUpNotification"
    static let NSWorkspaceAccessibilityDisplayOptionsDidChangeNotification = "NSWorkspaceAccessibilityDisplayOptionsDidChangeNotification"

    // The find panel's shared options: the pasteboard type before UTIs,
    // and two of its dictionary's keys.
    static let NSFindPanelSearchOptionsPboardType = "NSFindPanel search options pasteboard type"
    static let NSFindPanelCaseInsensitiveSearch = "NSFindPanelCaseInsensitiveSearch"
    static let NSFindPanelSubstringMatch = "NSFindPanelSubstringMatch"

    // Reading URLs from a pasteboard, and the print panel's summary items.
    static let NSPasteboardURLReadingFileURLsOnlyKey = "NSPasteboardURLReadingFileURLsOnlyKey"
    static let NSPrintPanelAccessorySummaryItemNameKey = "name"
    static let NSPrintPanelAccessorySummaryItemDescriptionKey = "description"
}
