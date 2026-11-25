import Foundation

// UIKit's Swift API over Foundation's and its own values: index paths' rows
// and sections, URL resource thumbnails, content size categories in order,
// focus, font metrics by text style, color and image literals, playground
// views, and the drag, drop and paste API taking Swift types that bridge to
// item provider classes.

// MARK: - Index paths

extension IndexPath {
    /// An index path of a section and a row in it.
    public init(row: Int, section: Int) {
        self.init(indexes: [section, row])
    }

    /// An index path of a section and an item in it.
    public init(item: Int, section: Int) {
        self.init(indexes: [section, item])
    }

    /// The first index: the section of a table's or a collection's.
    public var section: Int {
        get {
            precondition(count == 2, "Invalid index path for use with UITableView. This index path must contain exactly two indices specifying the section and row.")
            return self[0]
        }
        set {
            precondition(count == 2, "Invalid index path for use with UITableView. This index path must contain exactly two indices specifying the section and row.")
            self[0] = newValue
        }
    }

    /// The second index: a table's row.
    public var row: Int {
        get {
            precondition(count == 2, "Invalid index path for use with UITableView. This index path must contain exactly two indices specifying the section and row.")
            return self[1]
        }
        set {
            precondition(count == 2, "Invalid index path for use with UITableView. This index path must contain exactly two indices specifying the section and row.")
            self[1] = newValue
        }
    }

    /// The second index: a collection view's item.
    public var item: Int {
        get {
            precondition(count == 2, "Invalid index path for use with UICollectionView. This index path must contain exactly two indices specifying the section and item.")
            return self[1]
        }
        set {
            precondition(count == 2, "Invalid index path for use with UICollectionView. This index path must contain exactly two indices specifying the section and item.")
            self[1] = newValue
        }
    }
}

// MARK: - URL resources

extension URLResourceValues {
    @available(iOS, introduced: 8.0, deprecated: 15.0, message: "Use the QuickLookThumbnailing framework and extension point instead")
    @available(watchOS, introduced: 2.0, deprecated: 8.0, message: "Use the QuickLookThumbnailing framework and extension point instead")
    @available(visionOS, introduced: 1.0, deprecated: 1.0, message: "Use the QuickLookThumbnailing framework and extension point instead")
    public var thumbnailDictionary: [URLThumbnailDictionaryItem: UIImage]? {
        allValues[.thumbnailDictionaryKey] as? [URLThumbnailDictionaryItem: UIImage]
    }
}

// MARK: - Content size categories

@available(iOS 11.0, tvOS 11.0, *)
extension UIContentSizeCategory {
    /// Whether the category is one of the accessibility sizes.
    public var isAccessibilityCategory: Bool {
        __UIContentSizeCategoryIsAccessibilityCategory(self)
    }

    public static func < (left: UIContentSizeCategory, right: UIContentSizeCategory) -> Bool {
        __UIContentSizeCategoryCompareToCategory(left, right) == .orderedAscending
    }

    public static func <= (left: UIContentSizeCategory, right: UIContentSizeCategory) -> Bool {
        __UIContentSizeCategoryCompareToCategory(left, right) != .orderedDescending
    }

    public static func > (left: UIContentSizeCategory, right: UIContentSizeCategory) -> Bool {
        __UIContentSizeCategoryCompareToCategory(left, right) == .orderedDescending
    }

    public static func >= (left: UIContentSizeCategory, right: UIContentSizeCategory) -> Bool {
        __UIContentSizeCategoryCompareToCategory(left, right) != .orderedAscending
    }
}

// MARK: - Focus

@available(iOS 11.0, tvOS 11.0, visionOS 1.0, *)
@available(watchOS, unavailable)
extension UIFocusEnvironment {
    /// Whether this environment is the one given or contains it.
    @MainActor @preconcurrency
    public func contains(_ environment: any UIFocusEnvironment) -> Bool {
        UIFocusSystem.__environment(self, contains: environment)
    }
}

@available(iOS 11.0, tvOS 11.0, visionOS 1.0, *)
@available(watchOS, unavailable)
extension UIFocusItem {
    /// Whether the focus system of the item's window has it focused.
    @MainActor @preconcurrency
    public var isFocused: Bool {
        guard let focusSystem = UIFocusSystem.focusSystem(for: self) else { return false }
        return focusSystem.focusedItem === self
    }
}

// MARK: - Fonts

extension UIFont.TextStyle {
    /// The metrics that scale fonts of this style.
    @available(iOS 11.0, watchOS 4.0, tvOS 11.0, *)
    public var metrics: UIFontMetrics {
        UIFontMetrics(forTextStyle: self)
    }
}

// MARK: - Literals and playgrounds

@available(iOS 7.0, *)
extension UIColor: _ExpressibleByColorLiteral {
    @nonobjc
    public required convenience init(_colorLiteralRed red: Float, green: Float, blue: Float, alpha: Float) {
        self.init(red: CGFloat(red), green: CGFloat(green), blue: CGFloat(blue), alpha: CGFloat(alpha))
    }
}

public typealias _ColorLiteralType = UIColor

@available(iOS 2.0, *)
extension UIImage: _ExpressibleByImageLiteral {
    /// The image named in the main bundle; a literal naming none stops the
    /// program.
    public required convenience init(imageLiteralResourceName name: String) {
        self.init(named: name)!
    }
}

public typealias _ImageLiteralType = UIImage

@available(iOS 7.0, *)
extension UIView: __DefaultCustomPlaygroundQuickLookable {
    @available(*, deprecated, message: "UIView._defaultCustomPlaygroundQuickLook will be removed in a future Swift version")
    @MainActor @preconcurrency
    public var _defaultCustomPlaygroundQuickLook: _PlaygroundQuickLook {
        .view(self)
    }
}

// MARK: - Drag, drop and paste

@available(iOS 11.0, *)
extension UIDragDropSession {
    /// Whether the session's items can be loaded as the Swift type, by the
    /// class it bridges to.
    @available(iOS 11.0, *)
    @MainActor @preconcurrency
    public func canLoadObjects<T: _ObjectiveCBridgeable>(ofClass: T.Type) -> Bool where T._ObjectiveCType: NSItemProviderReading {
        canLoadObjects(ofClass: T._ObjectiveCType.self as any NSItemProviderReading.Type)
    }
}

@available(iOS 11.0, *)
extension UIDropSession {
    /// The session's items loaded as the Swift type.
    @available(iOS 11.0, *)
    @MainActor @preconcurrency
    public func loadObjects<T: _ObjectiveCBridgeable>(ofClass: T.Type, completion: @escaping ([T]) -> Void) -> Progress
        where T._ObjectiveCType: NSItemProviderReading {
        loadObjects(ofClass: T._ObjectiveCType.self as any NSItemProviderReading.Type) { objects in
            completion(objects.map { T._unconditionallyBridgeFromObjectiveC($0 as? T._ObjectiveCType) })
        }
    }
}

@available(iOS 11.0, *)
extension UIPasteConfiguration {
    @available(iOS 11.0, *)
    @MainActor @preconcurrency
    public convenience init<T: _ObjectiveCBridgeable>(forAccepting _: T.Type) where T._ObjectiveCType: NSItemProviderReading {
        self.init(forAccepting: T._ObjectiveCType.self as any NSItemProviderReading.Type)
    }

    @available(iOS 11.0, *)
    @MainActor @preconcurrency
    public func addTypeIdentifiers<T: _ObjectiveCBridgeable>(forAccepting aClass: T.Type) where T._ObjectiveCType: NSItemProviderReading {
        addTypeIdentifiers(forAccepting: T._ObjectiveCType.self as any NSItemProviderReading.Type)
    }
}

extension UIPasteboard {
    /// Puts the values on the pasteboard as the classes they bridge to.
    @available(iOS 11.0, *)
    public func setObjects<T: _ObjectiveCBridgeable>(_ objects: [T]) where T._ObjectiveCType: NSItemProviderWriting {
        setObjects(objects.map { $0._bridgeToObjectiveC() as any NSItemProviderWriting })
    }

    @available(iOS 11.0, *)
    public func setObjects<T: _ObjectiveCBridgeable>(_ objects: [T], localOnly: Bool, expirationDate: Date?)
        where T._ObjectiveCType: NSItemProviderWriting {
        setObjects(objects.map { $0._bridgeToObjectiveC() as any NSItemProviderWriting }, localOnly: localOnly,
                   expirationDate: expirationDate)
    }
}
