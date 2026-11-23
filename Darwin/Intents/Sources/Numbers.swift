import Foundation

// Intents' Swift API over the NSNumber parameters and properties the
// headers refine for Swift: optional Bools, Ints, Doubles and Floats.

extension Optional where Wrapped == Bool {
    var number: NSNumber? { map { NSNumber(value: $0) } }
}

extension Optional where Wrapped == Int {
    var number: NSNumber? { map { NSNumber(value: $0) } }
}

extension Optional where Wrapped == Double {
    var number: NSNumber? { map { NSNumber(value: $0) } }
}

extension Optional where Wrapped == Float {
    var number: NSNumber? { map { NSNumber(value: $0) } }
}

extension Optional where Wrapped == NSNumber {
    var bool: Bool? { map { $0.boolValue } }
    var int: Int? { map { $0.intValue } }
    var double: Double? { map { $0.doubleValue } }
    var float: Float? { map { $0.floatValue } }
}

@available(iOS 10.0, macOS 11.0, watchOS 3.2, tvOS 14.0, *)
extension INIntegerResolutionResult {
    @nonobjc public static func confirmationRequired(with valueToConfirm: Int?) -> Self {
        __confirmationRequiredWithValue(toConfirm:  valueToConfirm.number)
    }
}

@available(iOS 10.0, macOS 11.0, watchOS 3.2, tvOS 14.0, *)
extension INDoubleResolutionResult {
    @nonobjc public static func confirmationRequired(with valueToConfirm: Double?) -> Self {
        __confirmationRequiredWithValue(toConfirm:  valueToConfirm.number)
    }
}

@available(iOS 10.0, macOS 11.0, watchOS 3.2, tvOS 14.0, *)
extension INBooleanResolutionResult {
    @nonobjc public static func confirmationRequired(with valueToConfirm: Bool?) -> Self {
        __confirmationRequiredWithValue(toConfirm:  valueToConfirm.number)
    }
}

@available(macOS 10.15, iOS 11.0, watchOS 4.0, *)
@available(macOS, unavailable)
@available(tvOS, unavailable)
extension INNotebookItemTypeResolutionResult {
    @nonobjc public static func disambiguation(with notebookItemTypesToDisambiguate: [INNotebookItemType]) -> Self {
        __disambiguationWithNotebookItemTypes(toDisambiguate:  notebookItemTypesToDisambiguate.map { NSNumber(value: $0.rawValue) })
    }
}

@available(iOS 15.0, macOS 12.0, watchOS 8.0, *)
@available(tvOS, unavailable)
extension INFocusStatus {
    @nonobjc public convenience init(isFocused: Bool? = nil) {
        self.init(__isFocused: isFocused.number)
    }

    @nonobjc public final var isFocused: Bool? { __isFocused.bool }
}

extension NSString {
    @available(iOS 12.0, macOS 10.14, watchOS 5.0, tvOS 14.0, *)
    public class func deferredLocalizedIntentsString(with format: String, _ args: any CVarArg...) -> NSString {
        withVaList(args) { __deferredLocalizedIntentsString(withFormat: format, fromTable: nil, arguments: $0) as NSString }
    }

    @available(iOS 12.0, macOS 10.14, watchOS 5.0, *)
    public class func deferredLocalizedIntentsString(with format: String, table: String, _ args: any CVarArg...) -> NSString {
        withVaList(args) { __deferredLocalizedIntentsString(withFormat: format, fromTable: table, arguments: $0) as NSString }
    }

    @available(iOS 12.0, macOS 10.14, watchOS 5.0, *)
    public class func deferredLocalizedIntentsString(with format: String, table: String, arguments: CVaListPointer) -> NSString {
        __deferredLocalizedIntentsString(withFormat: format, fromTable: table, arguments: arguments) as NSString
    }
}

// Image parameters named by key path.

@available(iOS 10.0, macOS 11.0, watchOS 3.2, tvOS 14.0, *)
public protocol _INIntentSetImageKeyPath {}

extension _INIntentSetImageKeyPath {
    @available(iOS 12.0, watchOS 5.0, *)
    @available(macOS, unavailable)
    @available(tvOS, unavailable)
    public func setImage<Value>(_ image: INImage?, forParameterNamed parameterName: KeyPath<Self, Value>) {
        guard let intent = self as? INIntent, let name = parameterName._kvcKeyPathString else { return }
        intent.__setImage(image, forParameterNamed: name)
    }

    @available(iOS 12.0, watchOS 5.0, *)
    @available(macOS, unavailable)
    @available(tvOS, unavailable)
    public func image<Value>(forParameterNamed parameterName: KeyPath<Self, Value>) -> INImage? {
        guard let intent = self as? INIntent, let name = parameterName._kvcKeyPathString else { return nil }
        return intent.__image(forParameterNamed: name)
    }
}

@available(iOS 10.0, macOS 11.0, watchOS 3.2, tvOS 14.0, *)
extension INIntent: _INIntentSetImageKeyPath {}

@available(iOS 10.0, macOS 11.0, watchOS 3.2, tvOS 14.0, *)
public protocol INIntentSetImageKeyPath: _INIntentSetImageKeyPath {}

@available(iOS 10.0, macOS 11.0, watchOS 3.2, tvOS 14.0, *)
extension INIntent: INIntentSetImageKeyPath {}

@available(macOS 10.15, iOS 11.0, watchOS 5.0, *)
@available(macOS, unavailable)
@available(tvOS, unavailable)
extension INParameter {
    /// The parameter of a class's property at a key path; nil for a key
    /// path Objective-C can't name or a root that isn't a class.
    @nonobjc public convenience init?<Root, Value>(keyPath: KeyPath<Root, Value>) {
        guard let root = Root.self as? AnyClass, let path = keyPath._kvcKeyPathString else { return nil }
        self.init(for: root, keyPath: path)
    }
}
