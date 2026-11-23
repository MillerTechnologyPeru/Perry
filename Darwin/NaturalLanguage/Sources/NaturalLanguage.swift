import Foundation

// The Swift API over Natural Language's NSRange and NSNumber methods (those
// the headers mark NS_REFINED_FOR_SWIFT): ranges of a String's indices in
// the string the object holds, and vectors and scores as Swift numbers.

/// The UTF-16 range of `range` in `string`, as Foundation's methods take it.
private func utf16Range(_ range: Range<String.Index>, in string: String?) -> NSRange {
    guard let string else {
        return NSRange(location: range.lowerBound.utf16Offset(in: ""), length: 0)
    }
    return NSRange(range, in: string)
}

/// The UTF-16 offset of `index` in `string`.
private func utf16Offset(_ index: String.Index, in string: String?) -> Int {
    index.utf16Offset(in: string ?? "")
}

/// A Foundation range in `string` as a range of its indices; an empty range
/// at its start when it doesn't fall on the string's characters.
private func stringRange(_ range: NSRange, in string: String?) -> Range<String.Index> {
    let string = string ?? ""
    if let result = Range(range, in: string) {
        return result
    }
    // A range past the end (NSNotFound) or splitting a character: clamp to
    // the nearest indices of the string's UTF-16 view.
    let utf16 = string.utf16
    let count = utf16.count
    let lower = range.location == NSNotFound ? count : max(0, min(range.location, count))
    let upper = range.location == NSNotFound ? count : max(lower, min(range.location + range.length, count))
    let start = utf16.index(utf16.startIndex, offsetBy: lower)
    let end = utf16.index(utf16.startIndex, offsetBy: upper)
    return start..<end
}

@available(macOS 10.14, iOS 12.0, watchOS 5.0, tvOS 12.0, *)
extension NLTokenizer {
    @nonobjc public func tokenRange(at index: String.Index) -> Range<String.Index> {
        let string = self.string
        return stringRange(__tokenRange(at: utf16Offset(index, in: string)), in: string)
    }

    @available(macOS 11.0, iOS 14.0, watchOS 7.0, tvOS 14.0, *)
    @nonobjc public func tokenRange(for range: Range<String.Index>) -> Range<String.Index> {
        let string = self.string
        return stringRange(__tokenRange(for: utf16Range(range, in: string)), in: string)
    }

    @nonobjc public func enumerateTokens(in range: Range<String.Index>, using block: (Range<String.Index>, NLTokenizer.Attributes) -> Bool) {
        let string = self.string
        __enumerateTokens(in: utf16Range(range, in: string)) { tokenRange, attributes, stop in
            if !block(stringRange(tokenRange, in: string), attributes) {
                stop.pointee = true
            }
        }
    }

    @nonobjc public func tokens(for range: Range<String.Index>) -> [Range<String.Index>] {
        let string = self.string
        return __tokens(for: utf16Range(range, in: string)).map { stringRange($0.rangeValue, in: string) }
    }
}

@available(macOS 14.0, iOS 17.0, watchOS 10.0, tvOS 17.0, *)
extension NLContextualEmbeddingResult {
    @nonobjc public func tokenVector(at index: String.Index) -> ([Double], Range<String.Index>)? {
        let string = self.string
        var tokenRange = NSRange(location: NSNotFound, length: 0)
        guard let vector = __tokenVector(at: utf16Offset(index, in: string), tokenRange: &tokenRange) else {
            return nil
        }
        return (vector.map { $0.doubleValue }, stringRange(tokenRange, in: string))
    }

    @nonobjc public func enumerateTokenVectors(in range: Range<String.Index>, using block: ([Double], Range<String.Index>) -> Bool) {
        let string = self.string
        __enumerateTokenVectors(in: utf16Range(range, in: string)) { vector, tokenRange, stop in
            if !block(vector.map { $0.doubleValue }, stringRange(tokenRange, in: string)) {
                stop.pointee = true
            }
        }
    }
}

@available(macOS 10.14, iOS 12.0, watchOS 5.0, tvOS 12.0, *)
extension NLTagger {
    @nonobjc public func tokenRange(at index: String.Index, unit: NLTokenUnit) -> Range<String.Index> {
        let string = self.string
        return stringRange(__tokenRange(at: utf16Offset(index, in: string), unit: unit), in: string)
    }

    @available(macOS 11.0, iOS 14.0, watchOS 7.0, tvOS 14.0, *)
    @nonobjc public func tokenRange(for range: Range<String.Index>, unit: NLTokenUnit) -> Range<String.Index> {
        let string = self.string
        return stringRange(__tokenRange(for: utf16Range(range, in: string), unit: unit), in: string)
    }

    @nonobjc public func tag(at index: String.Index, unit: NLTokenUnit, scheme: NLTagScheme) -> (NLTag?, Range<String.Index>) {
        let string = self.string
        var tokenRange = NSRange(location: NSNotFound, length: 0)
        let tag = __tag(at: utf16Offset(index, in: string), unit: unit, scheme: scheme, tokenRange: &tokenRange)
        return (tag, stringRange(tokenRange, in: string))
    }

    @available(macOS 11.0, iOS 14.0, watchOS 7.0, tvOS 14.0, *)
    @nonobjc public func tagHypotheses(at index: String.Index, unit: NLTokenUnit, scheme: NLTagScheme, maximumCount: Int) -> ([String: Double], Range<String.Index>) {
        let string = self.string
        var tokenRange = NSRange(location: NSNotFound, length: 0)
        let hypotheses = __tagHypotheses(at: utf16Offset(index, in: string), unit: unit, scheme: scheme, maximumCount: maximumCount, tokenRange: &tokenRange)
        var result: [String: Double] = [:]
        for (tag, score) in hypotheses {
            result[tag.rawValue] = score.doubleValue
        }
        return (result, stringRange(tokenRange, in: string))
    }

    @nonobjc public func enumerateTags(in range: Range<String.Index>, unit: NLTokenUnit, scheme: NLTagScheme, options: NLTagger.Options = [], using block: (NLTag?, Range<String.Index>) -> Bool) {
        let string = self.string
        __enumerateTags(in: utf16Range(range, in: string), unit: unit, scheme: scheme, options: options) { tag, tokenRange, stop in
            if !block(tag, stringRange(tokenRange, in: string)) {
                stop.pointee = true
            }
        }
    }

    @nonobjc public func tags(in range: Range<String.Index>, unit: NLTokenUnit, scheme: NLTagScheme, options: NLTagger.Options = []) -> [(NLTag?, Range<String.Index>)] {
        // Each token with its tag, or none, in order.
        var result: [(NLTag?, Range<String.Index>)] = []
        enumerateTags(in: range, unit: unit, scheme: scheme, options: options) { tag, tokenRange in
            result.append((tag, tokenRange))
            return true
        }
        return result
    }

    @nonobjc public func setLanguage(_ language: NLLanguage, range: Range<String.Index>) {
        __setLanguage(language, range: utf16Range(range, in: string))
    }

    @nonobjc public func setOrthography(_ orthography: NSOrthography, range: Range<String.Index>) {
        __setOrthography(orthography, range: utf16Range(range, in: string))
    }
}

/// A dictionary of NSNumber values as Doubles.
private func doubles<Key>(_ dictionary: [Key: NSNumber]) -> [Key: Double] {
    dictionary.mapValues { $0.doubleValue }
}

@available(macOS 11.0, iOS 14.0, watchOS 7.0, tvOS 14.0, *)
extension NLModel {
    @nonobjc public func predictedLabelHypotheses(for string: String, maximumCount maxCount: Int) -> [String: Double] {
        doubles(__predictedLabelHypotheses(for: string, maximumCount: maxCount))
    }

    @nonobjc public func predictedLabelHypotheses(forTokens tokens: [String], maximumCount maxCount: Int) -> [[String: Double]] {
        __predictedLabelHypotheses(forTokens: tokens, maximumCount: maxCount).map(doubles)
    }
}

@available(macOS 10.15, iOS 13.0, watchOS 6.0, tvOS 13.0, *)
extension NLEmbedding {
    @nonobjc public func distance(between firstString: String, and secondString: String, distanceType: NLDistanceType = .cosine) -> NLDistance {
        __distanceBetweenString(firstString, andString: secondString, distanceType: distanceType)
    }

    @nonobjc public func enumerateNeighbors(for string: String, maximumCount maxCount: Int, distanceType: NLDistanceType = .cosine, using block: (String, NLDistance) -> Bool) {
        __enumerateNeighbors(for: string, maximumCount: maxCount, distanceType: distanceType) { neighbor, distance, stop in
            if !block(neighbor, distance) {
                stop.pointee = true
            }
        }
    }

    @nonobjc public func neighbors(for string: String, maximumCount maxCount: Int, distanceType: NLDistanceType = .cosine) -> [(String, NLDistance)] {
        var result: [(String, NLDistance)] = []
        enumerateNeighbors(for: string, maximumCount: maxCount, distanceType: distanceType) { neighbor, distance in
            result.append((neighbor, distance))
            return true
        }
        return result
    }

    @nonobjc public func enumerateNeighbors(for vector: [Double], maximumCount maxCount: Int, distanceType: NLDistanceType = .cosine, using block: (String, NLDistance) -> Bool) {
        __enumerateNeighbors(forVector: vector.map { NSNumber(value: $0) }, maximumCount: maxCount, distanceType: distanceType) { neighbor, distance, stop in
            if !block(neighbor, distance) {
                stop.pointee = true
            }
        }
    }

    @nonobjc public func neighbors(for vector: [Double], maximumCount maxCount: Int, distanceType: NLDistanceType = .cosine) -> [(String, NLDistance)] {
        var result: [(String, NLDistance)] = []
        enumerateNeighbors(for: vector, maximumCount: maxCount, distanceType: distanceType) { neighbor, distance in
            result.append((neighbor, distance))
            return true
        }
        return result
    }

    @nonobjc public func vector(for string: String) -> [Double]? {
        __vector(for: string)?.map { $0.doubleValue }
    }

    @nonobjc public class func write(_ dictionary: [String: [Double]], language: NLLanguage?, revision: Int, to url: URL) throws {
        let vectors = dictionary.mapValues { $0.map { NSNumber(value: $0) } }
        try __write(for: vectors, language: language, revision: revision, to: url)
    }
}

@available(macOS 10.14, iOS 12.0, watchOS 5.0, tvOS 12.0, *)
extension NLLanguageRecognizer {
    @nonobjc public var languageHints: [NLLanguage: Double] {
        get { doubles(__languageHints) }
        set(newHints) { __languageHints = newHints.mapValues { NSNumber(value: $0) } }
    }

    @nonobjc public func languageHypotheses(withMaximum maxHypotheses: Int) -> [NLLanguage: Double] {
        doubles(__languageHypotheses(withMaximum: maxHypotheses))
    }
}
