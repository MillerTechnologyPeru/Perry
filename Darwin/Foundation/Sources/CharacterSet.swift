/// A set of Unicode scalars, held as an immutable `NSCharacterSet`; a
/// mutation works on a mutable copy and keeps the result.
@available(macOS 10.10, iOS 8.0, watchOS 2.0, tvOS 9.0, *)
public struct CharacterSet: Equatable, Hashable, SetAlgebra, @unchecked Sendable {
    public typealias ArrayLiteralElement = Unicode.Scalar
    public typealias Element = Unicode.Scalar

    var _set: NSCharacterSet

    init(_reference set: NSCharacterSet) {
        _set = set.copy() as! NSCharacterSet
    }

    private mutating func _mutate(_ body: (NSMutableCharacterSet) -> Void) {
        let set = _set.mutableCopy() as! NSMutableCharacterSet
        body(set)
        _set = set.copy() as! NSCharacterSet
    }

    private static func _range(_ range: Range<Unicode.Scalar>) -> NSRange {
        NSRange(location: Int(range.lowerBound.value), length: Int(range.upperBound.value - range.lowerBound.value))
    }

    private static func _range(_ range: ClosedRange<Unicode.Scalar>) -> NSRange {
        NSRange(location: Int(range.lowerBound.value), length: Int(range.upperBound.value - range.lowerBound.value) + 1)
    }

    // MARK: Creating

    public init() {
        _set = NSCharacterSet()
    }

    public init(charactersIn range: Range<Unicode.Scalar>) {
        _set = NSCharacterSet(range: CharacterSet._range(range))
    }

    public init(charactersIn range: ClosedRange<Unicode.Scalar>) {
        _set = NSCharacterSet(range: CharacterSet._range(range))
    }

    public init(charactersIn string: __shared String) {
        _set = NSCharacterSet(charactersIn: string)
    }

    public init(bitmapRepresentation data: __shared Data) {
        _set = NSCharacterSet(bitmapRepresentation: data)
    }

    public init?(contentsOfFile file: __shared String) {
        guard let set = NSCharacterSet(contentsOfFile: file) else { return nil }
        _set = set
    }

    public init(arrayLiteral elements: Unicode.Scalar...) {
        self.init()
        for scalar in elements { insert(scalar) }
    }

    // MARK: Standard sets

    public static var controlCharacters: CharacterSet { CharacterSet(_reference: NSCharacterSet.controlCharacters as NSCharacterSet) }
    public static var whitespaces: CharacterSet { CharacterSet(_reference: NSCharacterSet.whitespaces as NSCharacterSet) }
    public static var whitespacesAndNewlines: CharacterSet { CharacterSet(_reference: NSCharacterSet.whitespacesAndNewlines as NSCharacterSet) }
    public static var decimalDigits: CharacterSet { CharacterSet(_reference: NSCharacterSet.decimalDigits as NSCharacterSet) }
    public static var letters: CharacterSet { CharacterSet(_reference: NSCharacterSet.letters as NSCharacterSet) }
    public static var lowercaseLetters: CharacterSet { CharacterSet(_reference: NSCharacterSet.lowercaseLetters as NSCharacterSet) }
    public static var uppercaseLetters: CharacterSet { CharacterSet(_reference: NSCharacterSet.uppercaseLetters as NSCharacterSet) }
    public static var nonBaseCharacters: CharacterSet { CharacterSet(_reference: NSCharacterSet.nonBaseCharacters as NSCharacterSet) }
    public static var alphanumerics: CharacterSet { CharacterSet(_reference: NSCharacterSet.alphanumerics as NSCharacterSet) }
    public static var decomposables: CharacterSet { CharacterSet(_reference: NSCharacterSet.decomposables as NSCharacterSet) }
    public static var illegalCharacters: CharacterSet { CharacterSet(_reference: NSCharacterSet.illegalCharacters as NSCharacterSet) }
    public static var punctuationCharacters: CharacterSet { CharacterSet(_reference: NSCharacterSet.punctuationCharacters as NSCharacterSet) }
    public static var capitalizedLetters: CharacterSet { CharacterSet(_reference: NSCharacterSet.capitalizedLetters as NSCharacterSet) }
    public static var symbols: CharacterSet { CharacterSet(_reference: NSCharacterSet.symbols as NSCharacterSet) }
    public static var newlines: CharacterSet { CharacterSet(_reference: NSCharacterSet.newlines as NSCharacterSet) }

    // The URL component sets, as RFC 3986 allows each component's
    // characters unescaped.
    private static let _unreserved = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~"
    private static let _subDelimiters = "!$&'()*+,;="
    public static var urlUserAllowed: CharacterSet { CharacterSet(charactersIn: _unreserved + _subDelimiters) }
    public static var urlPasswordAllowed: CharacterSet { CharacterSet(charactersIn: _unreserved + _subDelimiters) }
    public static var urlHostAllowed: CharacterSet { CharacterSet(charactersIn: _unreserved + _subDelimiters + ":[]") }
    public static var urlPathAllowed: CharacterSet { CharacterSet(charactersIn: _unreserved + _subDelimiters + ":@/") }
    public static var urlQueryAllowed: CharacterSet { CharacterSet(charactersIn: _unreserved + _subDelimiters + ":@/?") }
    public static var urlFragmentAllowed: CharacterSet { CharacterSet(charactersIn: _unreserved + _subDelimiters + ":@/?") }

    // MARK: Inspecting

    @nonobjc public var bitmapRepresentation: Data { _set.bitmapRepresentation }

    @nonobjc public var inverted: CharacterSet { CharacterSet(_reference: _set.inverted as NSCharacterSet) }

    public func hasMember(inPlane plane: UInt8) -> Bool { _set.hasMemberInPlane(plane) }

    public func contains(_ member: Unicode.Scalar) -> Bool { _set.longCharacterIsMember(member.value) }

    public func isSuperset(of other: CharacterSet) -> Bool { _set.isSuperset(of: other._set as CharacterSet) }

    public var isEmpty: Bool { bitmapRepresentation.allSatisfy { $0 == 0 } }

    // MARK: Changing

    public mutating func insert(charactersIn range: Range<Unicode.Scalar>) {
        _mutate { $0.addCharacters(in: CharacterSet._range(range)) }
    }

    public mutating func insert(charactersIn range: ClosedRange<Unicode.Scalar>) {
        _mutate { $0.addCharacters(in: CharacterSet._range(range)) }
    }

    public mutating func remove(charactersIn range: Range<Unicode.Scalar>) {
        _mutate { $0.removeCharacters(in: CharacterSet._range(range)) }
    }

    public mutating func remove(charactersIn range: ClosedRange<Unicode.Scalar>) {
        _mutate { $0.removeCharacters(in: CharacterSet._range(range)) }
    }

    public mutating func insert(charactersIn string: String) {
        _mutate { $0.addCharacters(in: string) }
    }

    public mutating func remove(charactersIn string: String) {
        _mutate { $0.removeCharacters(in: string) }
    }

    public mutating func invert() {
        _mutate { $0.invert() }
    }

    @discardableResult
    public mutating func insert(_ character: Unicode.Scalar) -> (inserted: Bool, memberAfterInsert: Unicode.Scalar) {
        let inserted = !contains(character)
        if inserted { insert(charactersIn: character...character) }
        return (inserted, character)
    }

    @discardableResult
    public mutating func update(with character: Unicode.Scalar) -> Unicode.Scalar? {
        let present = contains(character)
        insert(charactersIn: character...character)
        return present ? character : nil
    }

    @discardableResult
    public mutating func remove(_ character: Unicode.Scalar) -> Unicode.Scalar? {
        guard contains(character) else { return nil }
        remove(charactersIn: character...character)
        return character
    }

    // MARK: Combining

    public func union(_ other: CharacterSet) -> CharacterSet {
        var result = self
        result.formUnion(other)
        return result
    }

    public mutating func formUnion(_ other: CharacterSet) {
        _mutate { $0.formUnion(with: other._set as CharacterSet) }
    }

    public func intersection(_ other: CharacterSet) -> CharacterSet {
        var result = self
        result.formIntersection(other)
        return result
    }

    public mutating func formIntersection(_ other: CharacterSet) {
        _mutate { $0.formIntersection(with: other._set as CharacterSet) }
    }

    public func subtracting(_ other: CharacterSet) -> CharacterSet {
        intersection(other.inverted)
    }

    public mutating func subtract(_ other: CharacterSet) {
        formIntersection(other.inverted)
    }

    public func symmetricDifference(_ other: CharacterSet) -> CharacterSet {
        union(other).subtracting(intersection(other))
    }

    public mutating func formSymmetricDifference(_ other: CharacterSet) {
        self = symmetricDifference(other)
    }

    // MARK: Equality

    public func hash(into hasher: inout Hasher) {
        hasher.combine(bitmapRepresentation)
    }

    public static func == (lhs: CharacterSet, rhs: CharacterSet) -> Bool {
        lhs._set === rhs._set || lhs.bitmapRepresentation == rhs.bitmapRepresentation
    }
}

@available(macOS 10.10, iOS 8.0, watchOS 2.0, tvOS 9.0, *)
extension CharacterSet: ReferenceConvertible, _ObjectiveCBridgeable {
    public typealias ReferenceType = NSCharacterSet
    public typealias _ObjectiveCType = NSCharacterSet

    public static func _getObjectiveCType() -> Any.Type { NSCharacterSet.self }

    @_semantics("convertToObjectiveC")
    public func _bridgeToObjectiveC() -> NSCharacterSet { _set }

    public static func _forceBridgeFromObjectiveC(_ input: NSCharacterSet, result: inout CharacterSet?) {
        result = CharacterSet(_reference: input)
    }

    @discardableResult
    public static func _conditionallyBridgeFromObjectiveC(_ input: NSCharacterSet, result: inout CharacterSet?) -> Bool {
        result = CharacterSet(_reference: input)
        return true
    }

    @_effects(readonly)
    public static func _unconditionallyBridgeFromObjectiveC(_ source: NSCharacterSet?) -> CharacterSet {
        source.map(CharacterSet.init(_reference:)) ?? CharacterSet()
    }
}

@available(macOS 10.10, iOS 8.0, watchOS 2.0, tvOS 9.0, *)
extension CharacterSet: CustomStringConvertible, CustomDebugStringConvertible {
    public var description: String { _set.description }
    public var debugDescription: String { _set.debugDescription }
}

@available(macOS 10.10, iOS 8.0, watchOS 2.0, tvOS 9.0, *)
extension CharacterSet: Codable {
    private enum CodingKeys: String, CodingKey { case bitmap }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(bitmapRepresentation: try container.decode(Data.self, forKey: .bitmap))
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(bitmapRepresentation, forKey: .bitmap)
    }
}
