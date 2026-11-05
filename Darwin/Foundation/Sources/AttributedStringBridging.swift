// AttributedString and NSAttributedString, each made from the other, and
// attribute containers and dictionaries likewise: an attribute scope says
// which keys carry over, by name, and how each value converts (an
// ObjectiveCConvertibleAttributedStringKey's own conversion, else Swift's
// bridging). SwiftUI draws attributed text this way, through its scope.
// swift-foundation leaves these to Apple's build, whose scope tables come
// from reflection that only that build has; here the Swift runtime's field
// reflection reads them.

@available(macOS 12, iOS 15, tvOS 15, watchOS 8, *)
enum _AttributeScopeTable {
    private static let cache = LockedState<[ObjectIdentifier: [String: any AttributedStringKey.Type]]>(initialState: [:])

    /// A scope's attributes by name: the attributes it stores and those of
    /// the scopes it stores. Foundation's own scope adds those this library
    /// declares outside the struct.
    static func keys(_ scope: any AttributeScope.Type) -> [String: any AttributedStringKey.Type] {
        if let cached = cache.withLock({ $0[ObjectIdentifier(scope)] }) { return cached }
        var keys: [String: any AttributedStringKey.Type] = [:]
        if scope == AttributeScopes.FoundationAttributes.self {
            for key in foundationDeclared { keys[key.name] = key }
        }
        for index in 0..<_markdownFieldCount(scope) {
            var field = _MarkdownFieldMetadata()
            let type = _markdownFieldType(scope, index: index, fieldMetadata: &field)
            field.freeName?(field.name)
            if let key = type as? any AttributedStringKey.Type {
                keys[key.name] = key
            } else if let inner = type as? any AttributeScope.Type {
                keys.merge(Self.keys(inner)) { current, _ in current }
            }
        }
        let table = keys
        cache.withLock { $0[ObjectIdentifier(scope)] = table }
        return table
    }

    private static var foundationDeclared: [any AttributedStringKey.Type] {
        typealias Keys = AttributeScopes.FoundationAttributes
        var keys: [any AttributedStringKey.Type] = [
            Keys.MorphologyAttribute.self, Keys.InflectionRuleAttribute.self, Keys.InlinePresentationIntentAttribute.self,
            Keys.PresentationIntentAttribute.self, Keys.MarkdownSourcePositionAttribute.self,
        ]
        if #available(macOS 26, iOS 26, tvOS 26, watchOS 26, visionOS 26, *) { keys.append(Keys.ListItemDelimiterAttribute.self) }
        return keys
    }

    /// The scope used when none is given.
    static var defaults: [String: any AttributedStringKey.Type] { keys(AttributeScopes.FoundationAttributes.self) }
}

@available(macOS 12, iOS 15, tvOS 15, watchOS 8, *)
extension AttributedStringKey {
    /// NSCoderInvalidValueError: a value that is not one of the attribute's.
    static var _invalidValue: CocoaError.Code { CocoaError.Code(rawValue: 4866) }

    static func _objectiveCObject(for value: Value) throws -> AnyObject {
        if let convertible = Self.self as? any ObjectiveCConvertibleAttributedStringKey.Type {
            func convert<K: ObjectiveCConvertibleAttributedStringKey>(_: K.Type) throws -> AnyObject {
                try K.objectiveCValue(for: value as! K.Value)
            }
            return try convert(convertible)
        }
        return value as AnyObject
    }

    static func _value(forObjectiveC object: AnyObject) throws -> Value {
        if let convertible = Self.self as? any ObjectiveCConvertibleAttributedStringKey.Type {
            func convert<K: ObjectiveCConvertibleAttributedStringKey>(_: K.Type) throws -> Value {
                guard let object = object as? K.ObjectiveCValue else { throw CocoaError(Self._invalidValue) }
                return try K.value(for: object) as! Value
            }
            return try convert(convertible)
        }
        guard let value = object as? Value else { throw CocoaError(Self._invalidValue) }
        return value
    }
}

@available(macOS 12, iOS 15, tvOS 15, watchOS 8, *)
extension AttributeContainer {
    /// Attributes whose values do not convert are left out.
    public init(_ dictionary: [NSAttributedString.Key: Any]) {
        self = (try? Self(dictionary, attributeTable: _AttributeScopeTable.defaults, droppingInvalid: true)) ?? Self()
    }

    public init<S: AttributeScope>(_ dictionary: [NSAttributedString.Key: Any],
                                   including scope: KeyPath<AttributeScopes, S.Type>) throws {
        try self.init(dictionary, including: S.self)
    }

    public init<S: AttributeScope>(_ dictionary: [NSAttributedString.Key: Any], including scope: S.Type) throws {
        try self.init(dictionary, attributeTable: _AttributeScopeTable.keys(S.self), droppingInvalid: false)
    }

    init(_ dictionary: [NSAttributedString.Key: Any], attributeTable: [String: any AttributedStringKey.Type],
         droppingInvalid: Bool) throws {
        self.init()
        for (name, value) in dictionary {
            guard let key = attributeTable[name.rawValue] else { continue }
            func set<K: AttributedStringKey>(_: K.Type) throws {
                self[K.self] = try K._value(forObjectiveC: value as AnyObject)
            }
            do {
                try set(key)
            } catch where droppingInvalid {
                continue
            }
        }
    }
}

@available(macOS 12, iOS 15, tvOS 15, watchOS 8, *)
extension Dictionary where Key == NSAttributedString.Key, Value == Any {
    /// Attributes whose values do not convert are left out.
    public init(_ container: AttributeContainer) {
        self = (try? Self(container, attributeTable: _AttributeScopeTable.defaults, droppingInvalid: true)) ?? [:]
    }

    public init<S: AttributeScope>(_ container: AttributeContainer, including scope: KeyPath<AttributeScopes, S.Type>) throws {
        try self.init(container, including: S.self)
    }

    public init<S: AttributeScope>(_ container: AttributeContainer, including scope: S.Type) throws {
        try self.init(container, attributeTable: _AttributeScopeTable.keys(S.self), droppingInvalid: false)
    }

    init(_ container: AttributeContainer, attributeTable: [String: any AttributedStringKey.Type],
         droppingInvalid: Bool) throws {
        self.init()
        for name in container.storage.keys {
            guard let key = attributeTable[name] else { continue }
            func get<K: AttributedStringKey>(_: K.Type) throws {
                guard let value = container[K.self] else { return }
                self[NSAttributedString.Key(rawValue: name)] = try K._objectiveCObject(for: value)
            }
            do {
                try get(key)
            } catch where droppingInvalid {
                continue
            }
        }
    }
}

@available(macOS 12, iOS 15, tvOS 15, watchOS 8, *)
extension NSAttributedString {
    /// Attributes whose values do not convert are left out.
    public convenience init(_ attrStr: AttributedString) {
        let made = try? NSAttributedString(attrStr, attributeTable: _AttributeScopeTable.defaults, droppingInvalid: true)
        self.init(attributedString: made ?? NSAttributedString(string: String(attrStr.characters)))
    }

    public convenience init<S: AttributeScope>(_ attrStr: AttributedString, including scope: KeyPath<AttributeScopes, S.Type>) throws {
        try self.init(attrStr, including: S.self)
    }

    public convenience init<S: AttributeScope>(_ attrStr: AttributedString, including scope: S.Type) throws {
        let made = try NSAttributedString(attrStr, attributeTable: _AttributeScopeTable.keys(S.self), droppingInvalid: false)
        self.init(attributedString: made)
    }

    /// Each run's attributes over its UTF-16 range.
    convenience init(_ attrStr: AttributedString, attributeTable: [String: any AttributedStringKey.Type],
                     droppingInvalid: Bool) throws {
        let result = NSMutableAttributedString(string: String(attrStr.characters))
        var location = 0
        for run in attrStr.runs {
            let length = attrStr.utf16.distance(from: run.range.lowerBound, to: run.range.upperBound)
            let attributes = try [NSAttributedString.Key: Any](run.attributes, attributeTable: attributeTable,
                                                                droppingInvalid: droppingInvalid)
            if !attributes.isEmpty {
                result.setAttributes(attributes, range: NSRange(location: location, length: length))
            }
            location += length
        }
        self.init(attributedString: result)
    }
}

@available(macOS 12, iOS 15, tvOS 15, watchOS 8, *)
extension AttributedString {
    /// Attributes whose values do not convert are left out.
    public init(_ nsStr: NSAttributedString) {
        self = (try? Self(nsStr, attributeTable: _AttributeScopeTable.defaults, droppingInvalid: true))
            ?? AttributedString(nsStr.string)
    }

    public init<S: AttributeScope>(_ nsStr: NSAttributedString, including scope: KeyPath<AttributeScopes, S.Type>) throws {
        try self.init(nsStr, including: S.self)
    }

    public init<S: AttributeScope>(_ nsStr: NSAttributedString, including scope: S.Type) throws {
        try self.init(nsStr, attributeTable: _AttributeScopeTable.keys(S.self), droppingInvalid: false)
    }

    init(_ nsStr: NSAttributedString, attributeTable: [String: any AttributedStringKey.Type], droppingInvalid: Bool) throws {
        var result = AttributedString()
        var failure: (any Error)?
        nsStr.enumerateAttributes(in: NSRange(location: 0, length: nsStr.length), options: []) { attributes, range, stop in
            do {
                let container = try AttributeContainer(attributes, attributeTable: attributeTable,
                                                       droppingInvalid: droppingInvalid)
                result.append(AttributedString(nsStr.attributedSubstring(from: range).string, attributes: container))
            } catch {
                failure = error
                stop.pointee = true
            }
        }
        if let failure { throw failure }
        self = result
    }
}
