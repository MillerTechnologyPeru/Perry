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

    /// A 32-bit integer at the position; nil when there is none.
    public func scanInt32(representation: NumberRepresentation = .decimal) -> Int32? {
        switch representation {
        case .decimal:
            var value: Int32 = 0
            return scanInt32(&value) ? value : nil
        case .hexadecimal:
            var value: UInt32 = 0
            return scanHexInt32(&value) ? Int32(truncatingIfNeeded: value) : nil
        }
    }

    /// A 64-bit integer at the position; nil when there is none.
    public func scanInt64(representation: NumberRepresentation = .decimal) -> Int64? {
        switch representation {
        case .decimal:
            var value: Int64 = 0
            return scanInt64(&value) ? value : nil
        case .hexadecimal:
            var value: UInt64 = 0
            return scanHexInt64(&value) ? Int64(truncatingIfNeeded: value) : nil
        }
    }

    /// An unsigned 64-bit integer at the position; nil when there is none.
    public func scanUInt64(representation: NumberRepresentation = .decimal) -> UInt64? {
        var value: UInt64 = 0
        switch representation {
        case .decimal: return scanUnsignedLongLong(&value) ? value : nil
        case .hexadecimal: return scanHexInt64(&value) ? value : nil
        }
    }

    /// A float at the position; nil when there is none.
    public func scanFloat(representation: NumberRepresentation = .decimal) -> Float? {
        var value: Float = 0
        switch representation {
        case .decimal: return scanFloat(&value) ? value : nil
        case .hexadecimal: return scanHexFloat(&value) ? value : nil
        }
    }

    /// A double at the position; nil when there is none.
    public func scanDouble(representation: NumberRepresentation = .decimal) -> Double? {
        var value: Double = 0
        switch representation {
        case .decimal: return scanDouble(&value) ? value : nil
        case .hexadecimal: return scanHexDouble(&value) ? value : nil
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
