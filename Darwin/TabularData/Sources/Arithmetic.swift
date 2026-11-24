// Element-wise arithmetic and comparisons on columns. A missing element
// on either side gives a missing result.

import Foundation

/// Combines two sequences of optionals element by element.
internal func _combine<A: Sequence, B: Sequence, T>(_ name: String, _ a: A, _ b: B, _ operation: (T, T) -> T) -> Column<T>
where A.Element == T?, B.Element == T? {
    Column(name: name, contents: zip(a, b).map { lhs, rhs -> T? in
        guard let lhs, let rhs else { return nil }
        return operation(lhs, rhs)
    })
}

/// Applies an operation with a scalar to each element present.
internal func _apply<A: Sequence, T>(_ name: String, _ a: A, _ operation: (T) -> T) -> Column<T> where A.Element == T? {
    Column(name: name, contents: a.map { $0.map(operation) })
}

// MARK: - Mixed optional and non-optional columns

public func + <L, R>(lhs: L, rhs: R) -> Column<R.Element>
where L: OptionalColumnProtocol, R: ColumnProtocol, L.WrappedElement: AdditiveArithmetic, L.WrappedElement == R.Element {
    _combine("\(lhs.name)+\(rhs.name)", lhs, rhs.lazy.map { Optional($0) }, +)
}

public func + <L, R>(lhs: L, rhs: R) -> Column<L.Element>
where L: ColumnProtocol, R: OptionalColumnProtocol, L.Element: AdditiveArithmetic, L.Element == R.WrappedElement {
    _combine("\(lhs.name)+\(rhs.name)", lhs.lazy.map { Optional($0) }, rhs, +)
}

public func - <L, R>(lhs: L, rhs: R) -> Column<R.Element>
where L: OptionalColumnProtocol, R: ColumnProtocol, L.WrappedElement: AdditiveArithmetic, L.WrappedElement == R.Element {
    _combine("\(lhs.name)-\(rhs.name)", lhs, rhs.lazy.map { Optional($0) }, -)
}

public func - <L, R>(lhs: L, rhs: R) -> Column<L.Element>
where L: ColumnProtocol, R: OptionalColumnProtocol, L.Element: AdditiveArithmetic, L.Element == R.WrappedElement {
    _combine("\(lhs.name)-\(rhs.name)", lhs.lazy.map { Optional($0) }, rhs, -)
}

public func * <L, R>(lhs: L, rhs: R) -> Column<R.Element>
where L: OptionalColumnProtocol, R: ColumnProtocol, L.WrappedElement: Numeric, L.WrappedElement == R.Element {
    _combine("\(lhs.name)*\(rhs.name)", lhs, rhs.lazy.map { Optional($0) }, *)
}

public func * <L, R>(lhs: L, rhs: R) -> Column<L.Element>
where L: ColumnProtocol, R: OptionalColumnProtocol, L.Element: Numeric, L.Element == R.WrappedElement {
    _combine("\(lhs.name)*\(rhs.name)", lhs.lazy.map { Optional($0) }, rhs, *)
}

public func / <L, R>(lhs: L, rhs: R) -> Column<R.Element>
where L: OptionalColumnProtocol, R: ColumnProtocol, L.WrappedElement: BinaryInteger, L.WrappedElement == R.Element {
    _combine("\(lhs.name)/\(rhs.name)", lhs, rhs.lazy.map { Optional($0) }, /)
}

public func / <L, R>(lhs: L, rhs: R) -> Column<L.Element>
where L: ColumnProtocol, R: OptionalColumnProtocol, L.Element: BinaryInteger, L.Element == R.WrappedElement {
    _combine("\(lhs.name)/\(rhs.name)", lhs.lazy.map { Optional($0) }, rhs, /)
}

public func / <L, R>(lhs: L, rhs: R) -> Column<R.Element>
where L: OptionalColumnProtocol, R: ColumnProtocol, L.WrappedElement: FloatingPoint, L.WrappedElement == R.Element {
    _combine("\(lhs.name)/\(rhs.name)", lhs, rhs.lazy.map { Optional($0) }, /)
}

public func / <L, R>(lhs: L, rhs: R) -> Column<L.Element>
where L: ColumnProtocol, R: OptionalColumnProtocol, L.Element: FloatingPoint, L.Element == R.WrappedElement {
    _combine("\(lhs.name)/\(rhs.name)", lhs.lazy.map { Optional($0) }, rhs, /)
}

// MARK: - Columns of non-optional elements

extension ColumnProtocol where Element: AdditiveArithmetic {
    public static func + (lhs: Self, rhs: Self) -> Column<Element> {
        _combine("\(lhs.name)+\(rhs.name)", lhs.lazy.map { Optional($0) }, rhs.lazy.map { Optional($0) }, +)
    }

    public static func - (lhs: Self, rhs: Self) -> Column<Element> {
        _combine("\(lhs.name)-\(rhs.name)", lhs.lazy.map { Optional($0) }, rhs.lazy.map { Optional($0) }, -)
    }
}

extension ColumnProtocol where Element: Numeric {
    public static func * (lhs: Self, rhs: Self) -> Column<Element> {
        _combine("\(lhs.name)*\(rhs.name)", lhs.lazy.map { Optional($0) }, rhs.lazy.map { Optional($0) }, *)
    }
}

extension ColumnProtocol where Element: BinaryInteger {
    public static func / (lhs: Self, rhs: Self) -> Column<Element> {
        _combine("\(lhs.name)/\(rhs.name)", lhs.lazy.map { Optional($0) }, rhs.lazy.map { Optional($0) }, /)
    }
}

extension ColumnProtocol where Element: FloatingPoint {
    public static func / (lhs: Self, rhs: Self) -> Column<Element> {
        _combine("\(lhs.name)/\(rhs.name)", lhs.lazy.map { Optional($0) }, rhs.lazy.map { Optional($0) }, /)
    }
}

extension ColumnProtocol {
    public static func + (lhs: Self, rhs: Element) -> Column<Element> where Element: AdditiveArithmetic {
        _apply("\(lhs.name)+\(rhs)", lhs.lazy.map { Optional($0) }) { $0 + rhs }
    }

    public static func + (lhs: Element, rhs: Self) -> Column<Element> where Element: AdditiveArithmetic {
        _apply("\(lhs)+\(rhs.name)", rhs.lazy.map { Optional($0) }) { lhs + $0 }
    }

    public static func - (lhs: Self, rhs: Element) -> Column<Element> where Element: AdditiveArithmetic {
        _apply("\(lhs.name)-\(rhs)", lhs.lazy.map { Optional($0) }) { $0 - rhs }
    }

    public static func - (lhs: Element, rhs: Self) -> Column<Element> where Element: AdditiveArithmetic {
        _apply("\(lhs)-\(rhs.name)", rhs.lazy.map { Optional($0) }) { lhs - $0 }
    }
}

extension ColumnProtocol where Element: Numeric {
    public static func * (lhs: Self, rhs: Element) -> Column<Element> {
        _apply("\(lhs.name)*\(rhs)", lhs.lazy.map { Optional($0) }) { $0 * rhs }
    }

    public static func * (lhs: Element, rhs: Self) -> Column<Element> {
        _apply("\(lhs)*\(rhs.name)", rhs.lazy.map { Optional($0) }) { lhs * $0 }
    }
}

extension ColumnProtocol where Element: BinaryInteger {
    public static func / (lhs: Self, rhs: Element) -> Column<Element> {
        _apply("\(lhs.name)/\(rhs)", lhs.lazy.map { Optional($0) }) { $0 / rhs }
    }

    public static func / (lhs: Element, rhs: Self) -> Column<Element> {
        _apply("\(lhs)/\(rhs.name)", rhs.lazy.map { Optional($0) }) { lhs / $0 }
    }
}

extension ColumnProtocol where Element: FloatingPoint {
    public static func / (lhs: Self, rhs: Element) -> Column<Element> {
        _apply("\(lhs.name)/\(rhs)", lhs.lazy.map { Optional($0) }) { $0 / rhs }
    }

    public static func / (lhs: Element, rhs: Self) -> Column<Element> {
        _apply("\(lhs)/\(rhs.name)", rhs.lazy.map { Optional($0) }) { lhs / $0 }
    }
}

extension ColumnProtocol where Element: Comparable {
    public static func < (lhs: Self, rhs: Element) -> [Bool] { lhs.map { $0 < rhs } }
    public static func < (lhs: Element, rhs: Self) -> [Bool] { rhs.map { lhs < $0 } }
    public static func <= (lhs: Self, rhs: Element) -> [Bool] { lhs.map { $0 <= rhs } }
    public static func <= (lhs: Element, rhs: Self) -> [Bool] { rhs.map { lhs <= $0 } }
    public static func > (lhs: Self, rhs: Element) -> [Bool] { lhs.map { $0 > rhs } }
    public static func > (lhs: Element, rhs: Self) -> [Bool] { rhs.map { lhs > $0 } }
    public static func >= (lhs: Self, rhs: Element) -> [Bool] { lhs.map { $0 >= rhs } }
    public static func >= (lhs: Element, rhs: Self) -> [Bool] { rhs.map { lhs >= $0 } }
    public static func == (lhs: Self, rhs: Element) -> [Bool] { lhs.map { $0 == rhs } }
    public static func == (lhs: Element, rhs: Self) -> [Bool] { rhs.map { lhs == $0 } }
    public static func != (lhs: Self, rhs: Element) -> [Bool] { lhs.map { $0 != rhs } }
    public static func != (lhs: Element, rhs: Self) -> [Bool] { rhs.map { lhs != $0 } }
}

// MARK: - Columns of optional elements

extension OptionalColumnProtocol where WrappedElement: AdditiveArithmetic {
    public static func + (lhs: Self, rhs: Self) -> Column<WrappedElement> {
        _combine("\(lhs.name)+\(rhs.name)", lhs, rhs, +)
    }

    public static func - (lhs: Self, rhs: Self) -> Column<WrappedElement> {
        _combine("\(lhs.name)-\(rhs.name)", lhs, rhs, -)
    }
}

extension OptionalColumnProtocol where WrappedElement: Numeric {
    public static func * (lhs: Self, rhs: Self) -> Column<WrappedElement> {
        _combine("\(lhs.name)*\(rhs.name)", lhs, rhs, *)
    }
}

extension OptionalColumnProtocol where WrappedElement: BinaryInteger {
    public static func / (lhs: Self, rhs: Self) -> Column<WrappedElement> {
        _combine("\(lhs.name)/\(rhs.name)", lhs, rhs, /)
    }
}

extension OptionalColumnProtocol where WrappedElement: FloatingPoint {
    public static func / (lhs: Self, rhs: Self) -> Column<WrappedElement> {
        _combine("\(lhs.name)/\(rhs.name)", lhs, rhs, /)
    }
}

extension OptionalColumnProtocol {
    public static func + (lhs: Self, rhs: WrappedElement) -> Column<WrappedElement> where WrappedElement: AdditiveArithmetic {
        _apply("\(lhs.name)+\(rhs)", lhs) { $0 + rhs }
    }

    public static func + (lhs: WrappedElement, rhs: Self) -> Column<WrappedElement> where WrappedElement: AdditiveArithmetic {
        _apply("\(lhs)+\(rhs.name)", rhs) { lhs + $0 }
    }

    public static func - (lhs: Self, rhs: WrappedElement) -> Column<WrappedElement> where WrappedElement: AdditiveArithmetic {
        _apply("\(lhs.name)-\(rhs)", lhs) { $0 - rhs }
    }

    public static func - (lhs: WrappedElement, rhs: Self) -> Column<WrappedElement> where WrappedElement: AdditiveArithmetic {
        _apply("\(lhs)-\(rhs.name)", rhs) { lhs - $0 }
    }
}

extension OptionalColumnProtocol where WrappedElement: Numeric {
    public static func * (lhs: Self, rhs: WrappedElement) -> Column<WrappedElement> {
        _apply("\(lhs.name)*\(rhs)", lhs) { $0 * rhs }
    }

    public static func * (lhs: WrappedElement, rhs: Self) -> Column<WrappedElement> {
        _apply("\(lhs)*\(rhs.name)", rhs) { lhs * $0 }
    }
}

extension OptionalColumnProtocol where WrappedElement: BinaryInteger {
    public static func / (lhs: Self, rhs: WrappedElement) -> Column<WrappedElement> {
        _apply("\(lhs.name)/\(rhs)", lhs) { $0 / rhs }
    }

    public static func / (lhs: WrappedElement, rhs: Self) -> Column<WrappedElement> {
        _apply("\(lhs)/\(rhs.name)", rhs) { lhs / $0 }
    }
}

extension OptionalColumnProtocol where WrappedElement: FloatingPoint {
    public static func / (lhs: Self, rhs: WrappedElement) -> Column<WrappedElement> {
        _apply("\(lhs.name)/\(rhs)", lhs) { $0 / rhs }
    }

    public static func / (lhs: WrappedElement, rhs: Self) -> Column<WrappedElement> {
        _apply("\(lhs)/\(rhs.name)", rhs) { lhs / $0 }
    }
}

// MARK: - Compound assignment

/// Updates each element present at the positions of a mutable column.
internal func _update<C: MutableCollection, T>(_ column: inout C, _ operation: (T) -> T) where C.Element == T? {
    var i = column.startIndex
    while i != column.endIndex {
        if let value = column[i] { column[i] = operation(value) }
        i = column.index(after: i)
    }
}

/// Updates each element of a mutable column with the other collection's element at the same position.
internal func _update<C: MutableCollection, O: Collection, T>(_ column: inout C, _ other: O, _ operation: (T, T) -> T)
where C.Element == T?, O.Element == T? {
    var i = column.startIndex
    var j = other.startIndex
    while i != column.endIndex && j != other.endIndex {
        if let lhs = column[i], let rhs = other[j] {
            column[i] = operation(lhs, rhs)
        } else {
            column[i] = nil
        }
        i = column.index(after: i)
        j = other.index(after: j)
    }
}

extension Column {
    public static func += (lhs: inout Column<WrappedElement>, rhs: WrappedElement) where WrappedElement: AdditiveArithmetic {
        lhs.transform { $0 + rhs }
    }

    public static func -= (lhs: inout Column<WrappedElement>, rhs: WrappedElement) where WrappedElement: AdditiveArithmetic {
        lhs.transform { $0 - rhs }
    }

    public static func *= (lhs: inout Column<WrappedElement>, rhs: WrappedElement) where WrappedElement: Numeric {
        lhs.transform { $0 * rhs }
    }

    public static func /= (lhs: inout Column<WrappedElement>, rhs: WrappedElement) where WrappedElement: BinaryInteger {
        lhs.transform { $0 / rhs }
    }

    public static func /= (lhs: inout Column<WrappedElement>, rhs: WrappedElement) where WrappedElement: FloatingPoint {
        lhs.transform { $0 / rhs }
    }

    public static func += <C>(lhs: inout Column<WrappedElement>, rhs: C) where WrappedElement: AdditiveArithmetic, WrappedElement == C.Element, C: Collection {
        _update(&lhs, rhs.lazy.map { Optional($0) }, +)
    }

    public static func += <C>(lhs: inout Column<WrappedElement>, rhs: C) where WrappedElement: AdditiveArithmetic, C: Collection, C.Element == WrappedElement? {
        _update(&lhs, rhs, +)
    }

    public static func -= <C>(lhs: inout Column<WrappedElement>, rhs: C) where WrappedElement: AdditiveArithmetic, WrappedElement == C.Element, C: Collection {
        _update(&lhs, rhs.lazy.map { Optional($0) }, -)
    }

    public static func -= <C>(lhs: inout Column<WrappedElement>, rhs: C) where WrappedElement: AdditiveArithmetic, C: Collection, C.Element == WrappedElement? {
        _update(&lhs, rhs, -)
    }

    public static func *= <C>(lhs: inout Column<WrappedElement>, rhs: C) where WrappedElement: Numeric, WrappedElement == C.Element, C: Collection {
        _update(&lhs, rhs.lazy.map { Optional($0) }, *)
    }

    public static func *= <C>(lhs: inout Column<WrappedElement>, rhs: C) where WrappedElement: Numeric, C: Collection, C.Element == WrappedElement? {
        _update(&lhs, rhs, *)
    }

    public static func /= <C>(lhs: inout Column<WrappedElement>, rhs: C) where WrappedElement: BinaryInteger, WrappedElement == C.Element, C: Collection {
        _update(&lhs, rhs.lazy.map { Optional($0) }, /)
    }

    public static func /= <C>(lhs: inout Column<WrappedElement>, rhs: C) where WrappedElement: BinaryInteger, C: Collection, C.Element == WrappedElement? {
        _update(&lhs, rhs, /)
    }

    public static func /= <C>(lhs: inout Column<WrappedElement>, rhs: C) where WrappedElement: FloatingPoint, WrappedElement == C.Element, C: Collection {
        _update(&lhs, rhs.lazy.map { Optional($0) }, /)
    }

    public static func /= <C>(lhs: inout Column<WrappedElement>, rhs: C) where WrappedElement: FloatingPoint, C: Collection, C.Element == WrappedElement? {
        _update(&lhs, rhs, /)
    }
}

extension ColumnSlice {
    public static func += (lhs: inout ColumnSlice<WrappedElement>, rhs: WrappedElement) where WrappedElement: AdditiveArithmetic {
        _update(&lhs) { $0 + rhs }
    }

    public static func -= (lhs: inout ColumnSlice<WrappedElement>, rhs: WrappedElement) where WrappedElement: AdditiveArithmetic {
        _update(&lhs) { $0 - rhs }
    }

    public static func *= (lhs: inout ColumnSlice<WrappedElement>, rhs: WrappedElement) where WrappedElement: Numeric {
        _update(&lhs) { $0 * rhs }
    }

    public static func /= (lhs: inout ColumnSlice<WrappedElement>, rhs: WrappedElement) where WrappedElement: BinaryInteger {
        _update(&lhs) { $0 / rhs }
    }

    public static func /= (lhs: inout ColumnSlice<WrappedElement>, rhs: WrappedElement) where WrappedElement: FloatingPoint {
        _update(&lhs) { $0 / rhs }
    }

    public static func += <C>(lhs: inout ColumnSlice<WrappedElement>, rhs: C) where WrappedElement: AdditiveArithmetic, WrappedElement == C.Element, C: Collection {
        _update(&lhs, rhs.lazy.map { Optional($0) }, +)
    }

    public static func += <C>(lhs: inout ColumnSlice<WrappedElement>, rhs: C) where WrappedElement: AdditiveArithmetic, C: Collection, C.Element == WrappedElement? {
        _update(&lhs, rhs, +)
    }

    public static func -= <C>(lhs: inout ColumnSlice<WrappedElement>, rhs: C) where WrappedElement: AdditiveArithmetic, WrappedElement == C.Element, C: Collection {
        _update(&lhs, rhs.lazy.map { Optional($0) }, -)
    }

    public static func -= <C>(lhs: inout ColumnSlice<WrappedElement>, rhs: C) where WrappedElement: AdditiveArithmetic, C: Collection, C.Element == WrappedElement? {
        _update(&lhs, rhs, -)
    }

    public static func *= <C>(lhs: inout ColumnSlice<WrappedElement>, rhs: C) where WrappedElement: Numeric, WrappedElement == C.Element, C: Collection {
        _update(&lhs, rhs.lazy.map { Optional($0) }, *)
    }

    public static func *= <C>(lhs: inout ColumnSlice<WrappedElement>, rhs: C) where WrappedElement: Numeric, C: Collection, C.Element == WrappedElement? {
        _update(&lhs, rhs, *)
    }

    public static func /= <C>(lhs: inout ColumnSlice<WrappedElement>, rhs: C) where WrappedElement: BinaryInteger, WrappedElement == C.Element, C: Collection {
        _update(&lhs, rhs.lazy.map { Optional($0) }, /)
    }

    public static func /= <C>(lhs: inout ColumnSlice<WrappedElement>, rhs: C) where WrappedElement: BinaryInteger, C: Collection, C.Element == WrappedElement? {
        _update(&lhs, rhs, /)
    }

    public static func /= <C>(lhs: inout ColumnSlice<WrappedElement>, rhs: C) where WrappedElement: FloatingPoint, WrappedElement == C.Element, C: Collection {
        _update(&lhs, rhs.lazy.map { Optional($0) }, /)
    }

    public static func /= <C>(lhs: inout ColumnSlice<WrappedElement>, rhs: C) where WrappedElement: FloatingPoint, C: Collection, C.Element == WrappedElement? {
        _update(&lhs, rhs, /)
    }
}

extension DiscontiguousColumnSlice {
    public static func += (lhs: inout DiscontiguousColumnSlice<WrappedElement>, rhs: WrappedElement) where WrappedElement: AdditiveArithmetic {
        _update(&lhs) { $0 + rhs }
    }

    public static func -= (lhs: inout DiscontiguousColumnSlice<WrappedElement>, rhs: WrappedElement) where WrappedElement: AdditiveArithmetic {
        _update(&lhs) { $0 - rhs }
    }

    public static func *= (lhs: inout DiscontiguousColumnSlice<WrappedElement>, rhs: WrappedElement) where WrappedElement: Numeric {
        _update(&lhs) { $0 * rhs }
    }

    public static func /= (lhs: inout DiscontiguousColumnSlice<WrappedElement>, rhs: WrappedElement) where WrappedElement: BinaryInteger {
        _update(&lhs) { $0 / rhs }
    }

    public static func /= (lhs: inout DiscontiguousColumnSlice<WrappedElement>, rhs: WrappedElement) where WrappedElement: FloatingPoint {
        _update(&lhs) { $0 / rhs }
    }

    public static func += <C>(lhs: inout DiscontiguousColumnSlice<WrappedElement>, rhs: C) where WrappedElement: AdditiveArithmetic, WrappedElement == C.Element, C: Collection {
        _update(&lhs, rhs.lazy.map { Optional($0) }, +)
    }

    public static func += <C>(lhs: inout DiscontiguousColumnSlice<WrappedElement>, rhs: C) where WrappedElement: AdditiveArithmetic, C: Collection, C.Element == WrappedElement? {
        _update(&lhs, rhs, +)
    }

    public static func -= <C>(lhs: inout DiscontiguousColumnSlice<WrappedElement>, rhs: C) where WrappedElement: AdditiveArithmetic, WrappedElement == C.Element, C: Collection {
        _update(&lhs, rhs.lazy.map { Optional($0) }, -)
    }

    public static func -= <C>(lhs: inout DiscontiguousColumnSlice<WrappedElement>, rhs: C) where WrappedElement: AdditiveArithmetic, C: Collection, C.Element == WrappedElement? {
        _update(&lhs, rhs, -)
    }

    public static func *= <C>(lhs: inout DiscontiguousColumnSlice<WrappedElement>, rhs: C) where WrappedElement: Numeric, WrappedElement == C.Element, C: Collection {
        _update(&lhs, rhs.lazy.map { Optional($0) }, *)
    }

    public static func *= <C>(lhs: inout DiscontiguousColumnSlice<WrappedElement>, rhs: C) where WrappedElement: Numeric, C: Collection, C.Element == WrappedElement? {
        _update(&lhs, rhs, *)
    }

    public static func /= <C>(lhs: inout DiscontiguousColumnSlice<WrappedElement>, rhs: C) where WrappedElement: BinaryInteger, WrappedElement == C.Element, C: Collection {
        _update(&lhs, rhs.lazy.map { Optional($0) }, /)
    }

    public static func /= <C>(lhs: inout DiscontiguousColumnSlice<WrappedElement>, rhs: C) where WrappedElement: BinaryInteger, C: Collection, C.Element == WrappedElement? {
        _update(&lhs, rhs, /)
    }

    public static func /= <C>(lhs: inout DiscontiguousColumnSlice<WrappedElement>, rhs: C) where WrappedElement: FloatingPoint, WrappedElement == C.Element, C: Collection {
        _update(&lhs, rhs.lazy.map { Optional($0) }, /)
    }

    public static func /= <C>(lhs: inout DiscontiguousColumnSlice<WrappedElement>, rhs: C) where WrappedElement: FloatingPoint, C: Collection, C.Element == WrappedElement? {
        _update(&lhs, rhs, /)
    }
}
