// NSScanner's Swift API: the position as a string index, and scanning that
// answers in Swift types, as Apple's Foundation overlay has them. See
// FileHandleAdditions.swift for why the extension is unavailable.

@available(*, unavailable)
extension NSScanner {
    /// How scanInt reads a number.
    public enum NumberRepresentation: Sendable {
        case decimal
        case hexadecimal
    }

    /// The position in the string.
    public var currentIndex: String.Index {
        get { String.Index(utf16Offset: scanLocation, in: string) }
        set { scanLocation = newValue.utf16Offset(in: string) }
    }

    /// An integer at the position; nil when there is none.
    public func scanInt(representation: NumberRepresentation = .decimal) -> Int? {
        switch representation {
        case .decimal:
            var value = 0
            return scanInt(&value) ? value : nil
        case .hexadecimal:
            var value: UInt64 = 0
            return scanHexInt64(&value) ? Int(truncatingIfNeeded: value) : nil
        }
    }

    /// The string, if it comes next.
    public func scanString(_ searchString: String) -> String? {
        var found: NSString?
        return scanString(searchString, into: &found) ? found.map { String($0) } : nil
    }

    /// The characters of the set that come next; nil when there are none.
    public func scanCharacters(from set: CharacterSet) -> String? {
        var found: NSString?
        return scanCharacters(from: set, into: &found) ? found.map { String($0) } : nil
    }

    /// The characters up to one of the set; nil when there are none.
    public func scanUpToCharacters(from set: CharacterSet) -> String? {
        var found: NSString?
        return scanUpToCharacters(from: set, into: &found) ? found.map { String($0) } : nil
    }

    /// The next character, if there is one.
    public func scanCharacter() -> Character? {
        guard !isAtEnd else { return nil }
        let index = currentIndex
        let character = string[index]
        currentIndex = string.index(after: index)
        return character
    }
}
