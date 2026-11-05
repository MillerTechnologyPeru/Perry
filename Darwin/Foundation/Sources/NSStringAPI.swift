// NSString's API on Swift strings: each member converts the string, and any
// range, to NSString's terms (UTF-16 offsets), calls NSString, and converts
// the result back.

extension StringProtocol {
    var _ns: NSString { String(self)._bridgeToObjectiveC() }

    /// `range` (the whole string if nil) as UTF-16 offsets from the start.
    func _nsRange(_ range: Range<Index>? = nil) -> NSRange {
        let range = range ?? startIndex..<endIndex
        let location = utf16.distance(from: startIndex, to: range.lowerBound)
        return NSRange(location: location, length: utf16.distance(from: range.lowerBound, to: range.upperBound))
    }

    /// A range of UTF-16 offsets from the start as a range of indices; nil
    /// for NSNotFound.
    func _range(_ range: NSRange) -> Range<Index>? {
        guard range.location != NSNotFound,
              let lower = utf16.index(startIndex, offsetBy: range.location, limitedBy: endIndex),
              let upper = utf16.index(lower, offsetBy: range.length, limitedBy: endIndex) else { return nil }
        return lower..<upper
    }
}

@available(macOS 10.10, iOS 8.0, watchOS 2.0, tvOS 9.0, *)
extension String {
    public init(_ cocoaString: NSString) {
        self = String._unconditionallyBridgeFromObjectiveC(cocoaString)
    }

    public init?(cString: UnsafePointer<CChar>, encoding enc: Encoding) {
        guard let string = NSString(cString: cString, encoding: enc.rawValue) else { return nil }
        self = String._unconditionallyBridgeFromObjectiveC(string)
    }

    public init(format: __shared String, _ arguments: any CVarArg...) {
        self.init(format: format, locale: nil, arguments: arguments)
    }

    public init(format: __shared String, arguments: __shared [any CVarArg]) {
        self.init(format: format, locale: nil, arguments: arguments)
    }

    public init(format: __shared String, locale: __shared Locale?, _ args: any CVarArg...) {
        self.init(format: format, locale: locale, arguments: args)
    }

    public init(format: __shared String, locale: __shared Locale?, arguments: __shared [any CVarArg]) {
        let string = withVaList(arguments) { list in
            NSString(format: format, locale: locale.map { $0._bridgeToObjectiveC() }, arguments: list)
        }
        self = String._unconditionallyBridgeFromObjectiveC(string)
    }

    /// A string made from a format and arguments, in the current locale.
    public static func localizedStringWithFormat(_ format: String, _ arguments: any CVarArg...) -> String {
        String(format: format, locale: Locale.current, arguments: arguments)
    }
}

@available(macOS 10.10, iOS 8.0, watchOS 2.0, tvOS 9.0, *)
extension StringProtocol {
    // MARK: Encodings

    public func canBeConverted(to encoding: String.Encoding) -> Bool {
        _ns.canBeConverted(to: encoding.rawValue)
    }

    public func cString(using encoding: String.Encoding) -> [CChar]? {
        guard let pointer = _ns.cString(using: encoding.rawValue) else { return nil }
        return Array(UnsafeBufferPointer(start: pointer, count: strlen(pointer) + 1))
    }

    public func getCString(_ buffer: inout [CChar], maxLength: Int, encoding: String.Encoding) -> Bool {
        _ns.getCString(&buffer, maxLength: Swift.min(buffer.count, maxLength), encoding: encoding.rawValue)
    }

    public var fastestEncoding: String.Encoding { String.Encoding(rawValue: _ns.fastestEncoding) }
    public var smallestEncoding: String.Encoding { String.Encoding(rawValue: _ns.smallestEncoding) }

    public func lengthOfBytes(using encoding: String.Encoding) -> Int {
        _ns.lengthOfBytes(using: encoding.rawValue)
    }

    public func maximumLengthOfBytes(using encoding: String.Encoding) -> Int {
        _ns.maximumLengthOfBytes(using: encoding.rawValue)
    }

    public var hash: Int { _ns.hash }

    // MARK: Comparing

    public func caseInsensitiveCompare<T: StringProtocol>(_ aString: T) -> ComparisonResult {
        _ns.caseInsensitiveCompare(String(aString))
    }

    public func commonPrefix<T: StringProtocol>(with aString: T, options: String.CompareOptions = []) -> String {
        _ns.commonPrefix(with: String(aString), options: options)
    }

    public func compare<T: StringProtocol>(_ aString: T, options mask: String.CompareOptions = [],
                                           range: Range<Index>? = nil, locale: Locale? = nil) -> ComparisonResult {
        _ns.compare(String(aString), options: mask, range: _nsRange(range), locale: locale.map { $0._bridgeToObjectiveC() })
    }

    public func localizedCaseInsensitiveCompare<T: StringProtocol>(_ aString: T) -> ComparisonResult {
        _ns.localizedCaseInsensitiveCompare(String(aString))
    }

    public func localizedCompare<T: StringProtocol>(_ aString: T) -> ComparisonResult {
        _ns.localizedCompare(String(aString))
    }

    public func localizedStandardCompare<T: StringProtocol>(_ string: T) -> ComparisonResult {
        _ns.localizedStandardCompare(String(string))
    }

    // MARK: Normalizing

    public var decomposedStringWithCanonicalMapping: String { _ns.decomposedStringWithCanonicalMapping }
    public var decomposedStringWithCompatibilityMapping: String { _ns.decomposedStringWithCompatibilityMapping }
    public var precomposedStringWithCanonicalMapping: String { _ns.precomposedStringWithCanonicalMapping }
    public var precomposedStringWithCompatibilityMapping: String { _ns.precomposedStringWithCompatibilityMapping }

    public func folding(options: String.CompareOptions = [], locale: Locale?) -> String {
        _ns.folding(options: options, locale: locale)
    }

    @available(macOS 10.11, iOS 9.0, watchOS 2.0, tvOS 9.0, *)
    public func applyingTransform(_ transform: StringTransform, reverse: Bool) -> String? {
        _ns.applyingTransform(transform, reverse: reverse)
    }

    // MARK: Splitting and enumerating

    public func components(separatedBy separator: CharacterSet) -> [String] {
        _ns.components(separatedBy: separator)
    }

    public func enumerateLines(invoking body: @escaping (_ line: String, _ stop: inout Bool) -> Void) {
        _ns.enumerateLines { line, stop in
            var stopped = false
            body(line, &stopped)
            if stopped { stop.pointee = true }
        }
    }

    public func enumerateSubstrings<R: RangeExpression>(
        in range: R, options opts: String.EnumerationOptions = [],
        _ body: @escaping (_ substring: String?, _ substringRange: Range<Index>, _ enclosingRange: Range<Index>, inout Bool) -> Void
    ) where R.Bound == String.Index {
        let range = range.relative(to: String(self))
        let lower = String.Index(range.lowerBound, within: self) ?? startIndex
        let upper = String.Index(range.upperBound, within: self) ?? endIndex
        _ns.enumerateSubstrings(in: _nsRange(lower..<upper), options: opts) { substring, substringRange, enclosingRange, stop in
            guard let substringIndices = self._range(substringRange), let enclosingIndices = self._range(enclosingRange) else { return }
            var stopped = false
            body(substring, substringIndices, enclosingIndices, &stopped)
            if stopped { stop.pointee = true }
        }
    }

    public func propertyList() -> Any { _ns.propertyList() }

    /// Called by selector: the compiler cannot lower NSString's method,
    /// whose result is a bridged dictionary, in the module defining the
    /// bridging.
    public func propertyListFromStringsFileFormat() -> [String: String] {
        let result = _ns.perform(NSSelectorFromString("propertyListFromStringsFileFormat"))?.takeUnretainedValue()
        return (result as? [String: String]) ?? [:]
    }

    // MARK: Building

    public func appendingFormat<T: StringProtocol>(_ format: T, _ arguments: any CVarArg...) -> String {
        String(self) + String(format: String(format), arguments: arguments)
    }

    public func padding<T: StringProtocol>(toLength newLength: Int, withPad padString: T, startingAt padIndex: Int) -> String {
        _ns.padding(toLength: newLength, withPad: String(padString), startingAt: padIndex)
    }

    public func replacingOccurrences<Target: StringProtocol, Replacement: StringProtocol>(
        of target: Target, with replacement: Replacement, options: String.CompareOptions = [],
        range searchRange: Range<Index>? = nil
    ) -> String {
        _ns.replacingOccurrences(of: String(target), with: String(replacement), options: options, range: _nsRange(searchRange))
    }

    public func trimmingCharacters(in set: CharacterSet) -> String {
        _ns.trimmingCharacters(in: set)
    }

    // MARK: Finding

    public func rangeOfComposedCharacterSequence(at anIndex: Index) -> Range<Index> {
        let offset = utf16.distance(from: startIndex, to: anIndex)
        return _range(_ns.rangeOfComposedCharacterSequence(at: offset)) ?? anIndex..<anIndex
    }

    public func rangeOfComposedCharacterSequences<R: RangeExpression>(for range: R) -> Range<Index> where R.Bound == String.Index {
        let range = range.relative(to: String(self))
        let lower = String.Index(range.lowerBound, within: self) ?? startIndex
        let upper = String.Index(range.upperBound, within: self) ?? endIndex
        return _range(_ns.rangeOfComposedCharacterSequences(for: _nsRange(lower..<upper))) ?? lower..<upper
    }

    public func rangeOfCharacter(from aSet: CharacterSet, options mask: String.CompareOptions = [],
                                 range aRange: Range<Index>? = nil) -> Range<Index>? {
        _range(_ns.rangeOfCharacter(from: aSet, options: mask, range: _nsRange(aRange)))
    }

    public func range<T: StringProtocol>(of aString: T, options mask: String.CompareOptions = [],
                                         range searchRange: Range<Index>? = nil, locale: Locale? = nil) -> Range<Index>? {
        _range(_ns.range(of: String(aString), options: mask, range: _nsRange(searchRange), locale: locale))
    }

    @available(macOS 10.11, iOS 9.0, watchOS 2.0, tvOS 9.0, *)
    public func localizedStandardRange<T: StringProtocol>(of string: T) -> Range<Index>? {
        _range(_ns.localizedStandardRange(of: String(string)))
    }

    public func contains<T: StringProtocol>(_ other: T) -> Bool {
        let other = String(other)
        return other.isEmpty || _ns.range(of: other).location != NSNotFound
    }

    public func localizedCaseInsensitiveContains<T: StringProtocol>(_ other: T) -> Bool {
        _ns.localizedCaseInsensitiveContains(String(other))
    }

    @available(macOS 10.11, iOS 9.0, watchOS 2.0, tvOS 9.0, *)
    public func localizedStandardContains<T: StringProtocol>(_ string: T) -> Bool {
        _ns.localizedStandardContains(String(string))
    }

    // MARK: Substrings

    public func substring(from index: Index) -> String { String(self[index...]) }
    public func substring(to index: Index) -> String { String(self[..<index]) }
    public func substring(with aRange: Range<Index>) -> String { String(self[aRange]) }
}
