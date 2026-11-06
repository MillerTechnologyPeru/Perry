// Swift API on Foundation's Objective-C classes and C types, as Darwin's
// Foundation declares it: iterating the collections, decoding with type
// checks, sort descriptors and predicates from Swift values, ranges between
// String's indices and UTF-16 offsets, NSDecimal's Swift members, and
// localized strings.

// MARK: - Fast enumeration

/// An iterator over an object's fast enumeration, a buffer at a time.
@available(macOS 10.10, iOS 8.0, watchOS 2.0, tvOS 9.0, *)
public struct NSFastEnumerationIterator: IteratorProtocol {
    let enumerable: any NSFastEnumeration
    /// Room for the objects an enumerable copies out, which it does not
    /// retain: unowned, so they are not released again here.
    var objects: [Unmanaged<AnyObject>?] = Array(repeating: nil, count: 16)
    var state = NSFastEnumerationState(state: 0, itemsPtr: nil, mutationsPtr: nil, extra: (0, 0, 0, 0, 0))
    var index = 0
    var count = 0

    public init(_ enumerable: any NSFastEnumeration) {
        self.enumerable = enumerable
    }

    @available(*, noasync)
    public mutating func next() -> Any? {
        if index >= count {
            let enumerable = enumerable
            count = objects.withUnsafeMutableBufferPointer { buffer in
                enumerable.countByEnumerating(with: &state,
                                              objects: AutoreleasingUnsafeMutablePointer<AnyObject?>(buffer.baseAddress!),
                                              count: buffer.count)
            }
            index = 0
            guard count > 0, state.itemsPtr != nil else { return nil }
        }
        let object = state.itemsPtr![index]
        index += 1
        return object.map { $0 as Any }
    }
}

@available(*, unavailable)
extension NSFastEnumerationIterator: Sendable {}

@available(macOS 10.10, iOS 8.0, watchOS 2.0, tvOS 9.0, *)
extension NSEnumerator: Sequence {
    @available(*, noasync)
    public func makeIterator() -> NSFastEnumerationIterator {
        NSFastEnumerationIterator(self)
    }
}

@available(macOS 10.10, iOS 8.0, watchOS 2.0, tvOS 9.0, *)
extension NSArray: Sequence {
    @available(*, noasync)
    public func makeIterator() -> NSFastEnumerationIterator {
        NSFastEnumerationIterator(self)
    }
}

@available(macOS 10.10, iOS 8.0, watchOS 2.0, tvOS 9.0, *)
extension NSSet: Sequence {
    @available(*, noasync)
    public func makeIterator() -> NSFastEnumerationIterator {
        NSFastEnumerationIterator(self)
    }
}

@available(macOS 10.10, iOS 8.0, watchOS 2.0, tvOS 9.0, *)
extension NSOrderedSet: Sequence {
    @available(*, noasync)
    public func makeIterator() -> NSFastEnumerationIterator {
        NSFastEnumerationIterator(self)
    }
}

@available(macOS 10.10, iOS 8.0, watchOS 2.0, tvOS 9.0, *)
extension NSDictionary: Sequence {
    /// An iterator over a dictionary's keys and their values.
    @_objcRuntimeName(_TtCE10FoundationCSo12NSDictionary9_Iterator)
    final public class Iterator: IteratorProtocol {
        let dictionary: NSDictionary
        var keys: NSFastEnumerationIterator

        init(_ dictionary: NSDictionary) {
            self.dictionary = dictionary
            keys = NSFastEnumerationIterator(dictionary)
        }

        final public func next() -> (key: Any, value: Any)? {
            while let key = keys.next() {
                if let value = dictionary.object(forKey: key) {
                    return (key, value)
                }
            }
            return nil
        }
    }

    public func makeIterator() -> NSDictionary.Iterator {
        Iterator(self)
    }

    @_alwaysEmitIntoClient @nonobjc
    public var underestimatedCount: Int { count }
}

@available(*, unavailable)
extension NSDictionary.Iterator: Sendable {}

// MARK: - Coding

/// Whether an object is of one of the classes.
private func isOfClasses(_ object: Any?, _ classes: [AnyClass]) -> Bool {
    guard let object = object.map({ $0 as AnyObject }) else { return true }
    return classes.contains { object.isKind(of: $0) }
}

// Objects are decoded, then checked against the classes asked for.
@available(macOS 10.10, iOS 8.0, watchOS 2.0, tvOS 9.0, *)
extension NSCoder {
    /// Decodes an object of the class, or nil if the object isn't one.
    public func decodeObject<DecodedObjectType>(of cls: DecodedObjectType.Type, forKey key: String) -> DecodedObjectType?
    where DecodedObjectType: NSObject, DecodedObjectType: NSCoding {
        decodeObject(forKey: key) as? DecodedObjectType
    }

    /// Decodes an object of one of the classes.
    @nonobjc
    public func decodeObject(of classes: [AnyClass]?, forKey key: String) -> Any? {
        let object = decodeObject(forKey: key)
        guard let classes else { return object }
        return isOfClasses(object, classes) ? object : nil
    }

    /// Decodes an array of objects of the class.
    @available(macOS 11.0, iOS 14.0, watchOS 7.0, tvOS 14.0, *)
    @nonobjc
    public func decodeArrayOfObjects<DecodedObject>(ofClass cls: DecodedObject.Type, forKey key: String) -> [DecodedObject]?
    where DecodedObject: NSObject, DecodedObject: NSSecureCoding {
        decodeObject(forKey: key) as? [DecodedObject]
    }

    /// Decodes an array of objects of the classes.
    @available(macOS 11.0, iOS 14.0, watchOS 7.0, tvOS 14.0, *)
    @nonobjc
    public func decodeArrayOfObjects(ofClasses classes: [AnyClass], forKey key: String) -> [Any]? {
        guard let array = decodeObject(forKey: key) as? [Any], array.allSatisfy({ isOfClasses($0, classes) }) else { return nil }
        return array
    }
}

@available(macOS 10.11, iOS 9.0, watchOS 2.0, tvOS 9.0, *)
extension NSKeyedUnarchiver {
    /// Decodes an archive's root object, which must be of the class.
    @nonobjc
    public static func unarchivedObject<DecodedObjectType>(ofClass cls: DecodedObjectType.Type, from data: Data) throws -> DecodedObjectType?
    where DecodedObjectType: NSObject, DecodedObjectType: NSCoding {
        try unarchivedObject(ofClasses: [cls], from: data) as? DecodedObjectType
    }

    /// Decodes an archive's root object, which must be of one of the
    /// classes.
    @nonobjc
    public static func unarchivedObject(ofClasses classes: [AnyClass], from data: Data) throws -> Any? {
        let unarchiver = try NSKeyedUnarchiver(forReadingFrom: data)
        unarchiver.requiresSecureCoding = false
        defer { unarchiver.finishDecoding() }
        let object = unarchiver.decodeObject(forKey: NSKeyedArchiveRootObjectKey)
        if let error = unarchiver.error { throw error }
        guard isOfClasses(object, classes) else {
            throw CocoaError(.coderReadCorrupt)
        }
        return object
    }
}

// MARK: - Sort descriptors and predicates

@available(iOS 15.0, macOS 12.0, tvOS 15.0, watchOS 8.0, *)
extension SortDescriptor {
    /// A sort descriptor of a key path's values from an NSSortDescriptor:
    /// one whose key names a property compared with `compare:` can't be
    /// made into a key path here, so none converts.
    public init?(_ descriptor: NSSortDescriptor, comparing comparedType: Compared.Type) where Compared: NSObject {
        return nil
    }
}

@available(iOS 15.0, macOS 12.0, tvOS 15.0, watchOS 8.0, *)
extension NSSortDescriptor {
    /// An NSSortDescriptor comparing the descriptor's key with `compare:`,
    /// in its order.
    public convenience init<Compared>(_ sortDescriptor: SortDescriptor<Compared>) where Compared: NSObject {
        self.init(_sortDescriptor: sortDescriptor)
    }

    @_alwaysEmitIntoClient
    public convenience init<Compared>(_sortDescriptor: SortDescriptor<Compared>) {
        self.init(_sortDescriptor)
    }

    @_disfavoredOverload
    public convenience init<Compared>(_ sortDescriptor: SortDescriptor<Compared>) {
        guard let key = sortDescriptor.keyString else {
            fatalError("\(sortDescriptor) cannot be converted to NSSortDescriptor: it has no key")
        }
        self.init(key: key, ascending: sortDescriptor.order == .forward)
    }
}

@available(macOS 10.10, iOS 8.0, watchOS 2.0, tvOS 9.0, *)
extension NSPredicate {
    /// A predicate from a format string and its arguments.
    public convenience init(format predicateFormat: __shared String, _ args: any CVarArg...) {
        self.init(format: predicateFormat, arguments: getVaList(args))
    }
}

// MARK: - Logging

/// Logs a formatted message, as the Objective-C NSLog does.
public func NSLog(_ format: String, _ args: any CVarArg...) {
    withVaList(args) { NSLogv(format, $0) }
}

// MARK: - Ranges

@available(macOS 10.10, iOS 8.0, watchOS 2.0, tvOS 9.0, *)
extension NSRange {
    /// The UTF-16 offsets of a range of a string's indices.
    public init<R, S>(_ region: R, in target: S) where R: RangeExpression, S: StringProtocol, R.Bound == String.Index {
        let range = region.relative(to: target)
        self = target._nsRange(range)
    }
}

@available(macOS 10.10, iOS 8.0, watchOS 2.0, tvOS 9.0, *)
extension Range where Bound == String.Index {
    /// The indices of a range of a string's UTF-16 offsets, or nil when
    /// they aren't in it.
    public init?(_ range: NSRange, in string: __shared String) {
        guard let indices = string._range(range) else { return nil }
        self = indices
    }

    @available(macOS 10.15, iOS 13, tvOS 13, watchOS 6, *)
    public init?<S>(_ range: NSRange, in string: __shared S) where S: StringProtocol {
        guard let indices = string._range(range) else { return nil }
        self = indices
    }
}

@available(macOS 12, iOS 15, tvOS 15, watchOS 8, *)
extension NSRange {
    /// The UTF-16 offsets of a range of an attributed string's indices.
    public init<R, S>(_ region: R, in target: S) where R: RangeExpression, S: AttributedStringProtocol, R.Bound == AttributedString.Index {
        let range = region.relative(to: target.characters)
        let utf16 = target.utf16
        self.init(location: utf16.distance(from: utf16.startIndex, to: range.lowerBound),
                  length: utf16.distance(from: range.lowerBound, to: range.upperBound))
    }
}

@available(macOS 12, iOS 15, tvOS 15, watchOS 8, *)
extension Range where Bound == AttributedString.Index {
    /// The indices of a range of an attributed string's UTF-16 offsets, or
    /// nil when they aren't in it.
    public init?<S>(_ range: NSRange, in string: S) where S: AttributedStringProtocol {
        let utf16 = string.utf16
        guard range.location != NSNotFound, range.location >= 0, range.length >= 0,
              range.location + range.length <= utf16.count else { return nil }
        let start = utf16.index(utf16.startIndex, offsetBy: range.location)
        self = start ..< utf16.index(start, offsetBy: range.length)
    }
}

// MARK: - Percent encoding

@available(macOS 10.10, iOS 8.0, watchOS 2.0, tvOS 9.0, *)
extension StringProtocol {
    /// The string with every character not in the set percent-encoded as
    /// UTF-8.
    public func addingPercentEncoding(withAllowedCharacters allowedCharacters: CharacterSet) -> String? {
        var result = ""
        for scalar in String(self).unicodeScalars {
            if allowedCharacters.contains(scalar) {
                result.unicodeScalars.append(scalar)
            } else {
                for byte in String(scalar).utf8 {
                    result += "%" + String(byte, radix: 16, uppercase: true).leftPadded
                }
            }
        }
        return result
    }
}

private extension String {
    var leftPadded: String { count == 1 ? "0" + self : self }
}

// MARK: - Localized strings

/// Returns a localized string from a table of a bundle, or the value (else
/// the key) when it has none.
@available(macOS 10.10, iOS 8.0, watchOS 2.0, tvOS 9.0, *)
public func NSLocalizedString(_ key: String, tableName: String? = nil, bundle: Bundle = Bundle.main,
                              value: String = "", comment: String) -> String {
    bundle.localizedString(forKey: key, value: value, table: tableName)
}

// MARK: - NSDecimal

// On Darwin, Decimal is NSDecimal, the C structure. Here swift-foundation's
// Decimal struct takes the Swift name, and these are NSDecimal's members,
// which apps built against Darwin's Foundation call: each converts to the
// struct and calls its own. Only an unavailable declaration may name the C
// structure by its C name; availability is the compiler's, and binds
// nothing.

@available(*, unavailable)
extension Decimal {
    init(_ decimal: NSDecimal) {
        self.init(_exponent: decimal._exponent, _length: decimal._length, _isNegative: decimal._isNegative,
                  _isCompact: decimal._isCompact, _reserved: decimal._reserved, _mantissa: decimal._mantissa)
    }

    var _c: NSDecimal {
        NSDecimal(_exponent: _exponent, _length: _length, _isNegative: _isNegative, _isCompact: _isCompact,
                  _reserved: _reserved, _mantissa: _mantissa)
    }
}

@available(*, unavailable)
extension NSDecimal {
    public init(_ value: Int64) {
        self = Decimal(value)._c
    }

    public init(_ value: Double) {
        self = Decimal(value)._c
    }

    public init?(string: __shared String, locale: __shared Locale? = nil) {
        guard let value = Decimal(string: string, locale: locale) else { return nil }
        self = value._c
    }
}

@available(*, unavailable)
extension NSDecimal: CustomStringConvertible {
    public var description: String { Decimal(self).description }
}

@available(*, unavailable)
extension NSDecimal: Hashable {
    public static func == (lhs: NSDecimal, rhs: NSDecimal) -> Bool {
        Decimal(lhs) == Decimal(rhs)
    }

    public func hash(into hasher: inout Hasher) {
        Decimal(self).hash(into: &hasher)
    }
}

@available(*, unavailable)
extension NSDecimal: Codable {
    public init(from decoder: any Decoder) throws {
        self = try Decimal(from: decoder)._c
    }

    public func encode(to encoder: any Encoder) throws {
        try Decimal(self).encode(to: encoder)
    }
}

@available(*, unavailable)
extension NSDecimal: _ObjectiveCBridgeable {
    public typealias _ObjectiveCType = NSDecimalNumber

    @_semantics("convertToObjectiveC")
    public func _bridgeToObjectiveC() -> NSDecimalNumber {
        NSDecimalNumber(string: description)
    }

    public static func _forceBridgeFromObjectiveC(_ x: NSDecimalNumber, result: inout NSDecimal?) {
        result = NSDecimal(string: x.stringValue)
    }

    public static func _conditionallyBridgeFromObjectiveC(_ input: NSDecimalNumber, result: inout NSDecimal?) -> Bool {
        result = NSDecimal(string: input.stringValue)
        return result != nil
    }

    @_effects(readonly)
    public static func _unconditionallyBridgeFromObjectiveC(_ source: NSDecimalNumber?) -> NSDecimal {
        source.flatMap { NSDecimal(string: $0.stringValue) } ?? Decimal()._c
    }
}
