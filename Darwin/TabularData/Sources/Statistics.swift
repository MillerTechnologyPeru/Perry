// Statistics of columns: minimums and maximums, sums, means, standard
// deviations, numeric and categorical summaries, and a frame's summary.

import Foundation

// MARK: - Helpers over (index, element) pairs

internal func _minimum<S: Sequence, T: Comparable>(_ pairs: S, maximum: Bool) -> (index: Int, value: T)?
where S.Element == (Int, T?) {
    var best: (index: Int, value: T)?
    for (index, element) in pairs {
        guard let element else { continue }
        if let current = best {
            if maximum ? element > current.value : element < current.value { best = (index, element) }
        } else {
            best = (index, element)
        }
    }
    return best
}

internal func _sum<S: Sequence, T: AdditiveArithmetic>(_ elements: S) -> T where S.Element == T? {
    var total = T.zero
    for case let element? in elements { total += element }
    return total
}

internal func _mean<T: FloatingPoint>(_ values: [T]) -> T? {
    guard !values.isEmpty else { return nil }
    return values.reduce(T.zero, +) / T(values.count)
}

/// The standard deviation, nil when there are no more values than degrees of freedom removed.
internal func _standardDeviation<T: FloatingPoint>(_ values: [T], deltaDegreesOfFreedom: Int) -> T? {
    guard values.count > deltaDegreesOfFreedom, let mean = _mean(values) else { return nil }
    let squares = values.reduce(T.zero) { $0 + ($1 - mean) * ($1 - mean) }
    return (squares / T(values.count - deltaDegreesOfFreedom)).squareRoot()
}

/// The quantile of sorted values, interpolating linearly between neighbors.
internal func _quantile<T: BinaryFloatingPoint>(_ sorted: [T], _ quantile: T) -> T {
    guard !sorted.isEmpty else { return .nan }
    let position = quantile * T(sorted.count - 1)
    let lower = Int(position.rounded(.down))
    let upper = Swift.min(lower + 1, sorted.count - 1)
    let fraction = position - T(lower)
    if fraction == 0 { return sorted[Swift.max(lower, 0)] }
    return sorted[lower] + (sorted[upper] - sorted[lower]) * fraction
}

internal func _numericSummary<T: BinaryFloatingPoint>(_ values: [T], noneCount: Int) -> NumericSummary<T> {
    guard !values.isEmpty else {
        var summary = NumericSummary<T>()
        summary.noneCount = noneCount
        return summary
    }
    let sorted = values.sorted()
    return NumericSummary(
        someCount: values.count, noneCount: noneCount,
        mean: _mean(values)!, standardDeviation: _standardDeviation(values, deltaDegreesOfFreedom: 1) ?? .nan,
        min: sorted.first!, max: sorted.last!,
        median: _quantile(sorted, 0.5), firstQuartile: _quantile(sorted, 0.25), thirdQuartile: _quantile(sorted, 0.75))
}

internal func _categoricalSummary<S: Sequence, T: Hashable>(_ elements: S) -> CategoricalSummary<T> where S.Element == T? {
    var counts: [T: Int] = [:]
    var order: [T] = []
    var someCount = 0, noneCount = 0
    for element in elements {
        guard let element else {
            noneCount += 1
            continue
        }
        someCount += 1
        if let count = counts[element] {
            counts[element] = count + 1
        } else {
            counts[element] = 1
            order.append(element)
        }
    }
    let highest = counts.values.max() ?? 0
    return CategoricalSummary(someCount: someCount, noneCount: noneCount,
                              uniqueCount: order.count + (noneCount > 0 ? 1 : 0),
                              mode: order.filter { counts[$0] == highest })
}

// MARK: - Summaries

public struct NumericSummary<Element>: Hashable, CustomDebugStringConvertible where Element: BinaryFloatingPoint {
    public var someCount: Int
    public var noneCount: Int

    public var totalCount: Int {
        someCount + noneCount
    }

    public var median: Element
    public var firstQuartile: Element
    public var thirdQuartile: Element
    public var mean: Element
    public var standardDeviation: Element
    public var min: Element
    public var max: Element

    public init() {
        self.init(someCount: 0, noneCount: 0, mean: .nan, standardDeviation: .nan, min: .nan, max: .nan,
                  median: .nan, firstQuartile: .nan, thirdQuartile: .nan)
    }

    public init(someCount: Int, noneCount: Int, mean: Element, standardDeviation: Element, min: Element, max: Element,
                median: Element, firstQuartile: Element, thirdQuartile: Element) {
        self.someCount = someCount
        self.noneCount = noneCount
        self.mean = mean
        self.standardDeviation = standardDeviation
        self.min = min
        self.max = max
        self.median = median
        self.firstQuartile = firstQuartile
        self.thirdQuartile = thirdQuartile
    }

    public var debugDescription: String {
        """
        Numeric Summary:
          someCount: \(someCount)
          noneCount: \(noneCount)
          mean: \(mean)
          std-dev: \(standardDeviation)
          min: \(min)
          max: \(max)
          25%: \(firstQuartile)
          median: \(median)
          75%: \(thirdQuartile)
        """
    }
}

extension NumericSummary: Sendable where Element: Sendable {}

public struct CategoricalSummary<Element>: Hashable, CustomDebugStringConvertible where Element: Hashable {
    public var someCount: Int
    public var noneCount: Int

    public var totalCount: Int {
        someCount + noneCount
    }

    public var uniqueCount: Int
    public var mode: [Element]

    public init() {
        self.init(someCount: 0, noneCount: 0, uniqueCount: 0, mode: [])
    }

    public init(someCount: Int, noneCount: Int, uniqueCount: Int, mode: [Element]) {
        self.someCount = someCount
        self.noneCount = noneCount
        self.uniqueCount = uniqueCount
        self.mode = mode
    }

    public var debugDescription: String {
        """
        Summary:
          someCount: \(someCount)
          noneCount: \(noneCount)
          unique: \(uniqueCount)
          mode: \(mode)
        """
    }
}

extension CategoricalSummary: Sendable where Element: Sendable {}

public struct AnyCategoricalSummary: Equatable {
    public var someCount: Int
    public var noneCount: Int

    public var totalCount: Int {
        someCount + noneCount
    }

    public var uniqueCount: Int
    public var mode: [Any]
    public var modeType: any Any.Type

    public init<T>(_ summary: CategoricalSummary<T>) where T: Hashable {
        someCount = summary.someCount
        noneCount = summary.noneCount
        uniqueCount = summary.uniqueCount
        mode = summary.mode.map { $0 as Any }
        modeType = T.self
    }

    public init(_ summary: CategoricalSummary<AnyHashable>) {
        someCount = summary.someCount
        noneCount = summary.noneCount
        uniqueCount = summary.uniqueCount
        mode = summary.mode.map(\.base)
        modeType = summary.mode.first.map { type(of: $0.base) } ?? AnyHashable.self
    }

    public static func == (lhs: AnyCategoricalSummary, rhs: AnyCategoricalSummary) -> Bool {
        lhs.someCount == rhs.someCount && lhs.noneCount == rhs.noneCount && lhs.uniqueCount == rhs.uniqueCount
            && lhs.modeType == rhs.modeType && lhs.mode.count == rhs.mode.count
            && zip(lhs.mode, rhs.mode).allSatisfy { _valuesEqual($0, $1) }
    }
}

// MARK: - Column statistics

extension Column where WrappedElement: Comparable {
    public func min() -> Element {
        _minimum(zip(indices, self), maximum: false)?.value
    }

    public func max() -> Element {
        _minimum(zip(indices, self), maximum: true)?.value
    }

    public func argmin() -> Int? {
        _minimum(zip(indices, self), maximum: false)?.index
    }

    public func argmax() -> Int? {
        _minimum(zip(indices, self), maximum: true)?.index
    }
}

extension DiscontiguousColumnSlice where WrappedElement: Comparable {
    public func min() -> Element {
        _minimum(zip(indices, self), maximum: false)?.value
    }

    public func max() -> Element {
        _minimum(zip(indices, self), maximum: true)?.value
    }

    public func argmin() -> Int? {
        _minimum(zip(indices, self), maximum: false)?.index
    }

    public func argmax() -> Int? {
        _minimum(zip(indices, self), maximum: true)?.index
    }
}

extension ColumnSlice where WrappedElement: Comparable {
    public func min() -> Element {
        _minimum(zip(indices, self), maximum: false)?.value
    }

    public func max() -> Element {
        _minimum(zip(indices, self), maximum: true)?.value
    }

    public func argmin() -> Int? {
        _minimum(zip(indices, self), maximum: false)?.index
    }

    public func argmax() -> Int? {
        _minimum(zip(indices, self), maximum: true)?.index
    }
}

extension Column where WrappedElement: AdditiveArithmetic {
    public func sum() -> WrappedElement {
        _sum(self)
    }
}

extension DiscontiguousColumnSlice where WrappedElement: AdditiveArithmetic {
    public func sum() -> WrappedElement {
        _sum(self)
    }
}

extension ColumnSlice where WrappedElement: AdditiveArithmetic {
    public func sum() -> WrappedElement {
        _sum(self)
    }
}

extension Column where WrappedElement: FloatingPoint {
    public func mean() -> Element {
        _mean(compactMap { $0 })
    }

    public func standardDeviation(deltaDegreesOfFreedom: Int = 1) -> Element {
        _standardDeviation(compactMap { $0 }, deltaDegreesOfFreedom: deltaDegreesOfFreedom)
    }
}

extension DiscontiguousColumnSlice where WrappedElement: FloatingPoint {
    public func mean() -> Element {
        _mean(compactMap { $0 })
    }

    public func standardDeviation(deltaDegreesOfFreedom: Int = 1) -> Element {
        _standardDeviation(compactMap { $0 }, deltaDegreesOfFreedom: deltaDegreesOfFreedom)
    }
}

extension ColumnSlice where WrappedElement: FloatingPoint {
    public func mean() -> Element {
        _mean(compactMap { $0 })
    }

    public func standardDeviation(deltaDegreesOfFreedom: Int = 1) -> Element {
        _standardDeviation(compactMap { $0 }, deltaDegreesOfFreedom: deltaDegreesOfFreedom)
    }
}

extension Column where WrappedElement: BinaryInteger {
    public func mean() -> Double? {
        _mean(compactMap { $0.map(Double.init) })
    }

    public func standardDeviation(deltaDegreesOfFreedom: Int = 1) -> Double? {
        _standardDeviation(compactMap { $0.map(Double.init) }, deltaDegreesOfFreedom: deltaDegreesOfFreedom)
    }
}

extension DiscontiguousColumnSlice where WrappedElement: BinaryInteger {
    public func mean() -> Double? {
        _mean(compactMap { $0.map(Double.init) })
    }

    public func standardDeviation(deltaDegreesOfFreedom: Int = 1) -> Double? {
        _standardDeviation(compactMap { $0.map(Double.init) }, deltaDegreesOfFreedom: deltaDegreesOfFreedom)
    }
}

extension ColumnSlice where WrappedElement: BinaryInteger {
    public func mean() -> Double? {
        _mean(compactMap { $0.map(Double.init) })
    }

    public func standardDeviation(deltaDegreesOfFreedom: Int = 1) -> Double? {
        _standardDeviation(compactMap { $0.map(Double.init) }, deltaDegreesOfFreedom: deltaDegreesOfFreedom)
    }
}

extension FilledColumn where Base.WrappedElement: Comparable {
    public func min() -> Element? {
        self.min(by: <)
    }

    public func max() -> Element? {
        self.max(by: <)
    }

    public func argmin() -> Base.Index? {
        var best: (Base.Index, Element)?
        for i in indices where best == nil || self[i] < best!.1 { best = (i, self[i]) }
        return best?.0
    }

    public func argmax() -> Index? {
        var best: (Base.Index, Element)?
        for i in indices where best == nil || self[i] > best!.1 { best = (i, self[i]) }
        return best?.0
    }
}

extension FilledColumn where Base.WrappedElement: BinaryInteger {
    public func sum() -> Element {
        reduce(.zero, +)
    }

    public func mean() -> Double? {
        _mean(map(Double.init))
    }

    public func standardDeviation(deltaDegreesOfFreedom: Int = 1) -> Double? {
        _standardDeviation(map(Double.init), deltaDegreesOfFreedom: deltaDegreesOfFreedom)
    }
}

extension FilledColumn where Base.WrappedElement: FloatingPoint {
    public func sum() -> Element {
        reduce(.zero, +)
    }

    public func mean() -> Element? {
        _mean(Array(self))
    }

    public func standardDeviation(deltaDegreesOfFreedom: Int = 1) -> Element? {
        _standardDeviation(Array(self), deltaDegreesOfFreedom: deltaDegreesOfFreedom)
    }
}

// MARK: - Numeric and categorical summaries

extension Column where WrappedElement: BinaryFloatingPoint {
    public func numericSummary() -> NumericSummary<WrappedElement> {
        _numericSummary(compactMap { $0 }, noneCount: missingCount)
    }
}

extension ColumnSlice where WrappedElement: BinaryFloatingPoint {
    public func numericSummary() -> NumericSummary<WrappedElement> {
        _numericSummary(compactMap { $0 }, noneCount: missingCount)
    }
}

extension DiscontiguousColumnSlice where WrappedElement: BinaryFloatingPoint {
    public func numericSummary() -> NumericSummary<WrappedElement> {
        _numericSummary(compactMap { $0 }, noneCount: missingCount)
    }
}

extension FilledColumn where Base.WrappedElement: BinaryFloatingPoint {
    public func numericSummary() -> NumericSummary<Base.WrappedElement> {
        _numericSummary(Array(self), noneCount: 0)
    }
}

extension FilledColumn where Base.WrappedElement: BinaryInteger {
    public func numericSummary() -> NumericSummary<Double> {
        _numericSummary(map(Double.init), noneCount: 0)
    }
}

extension Column where WrappedElement: BinaryInteger {
    public func numericSummary() -> NumericSummary<Double> {
        _numericSummary(compactMap { $0.map(Double.init) }, noneCount: missingCount)
    }
}

extension ColumnSlice where WrappedElement: BinaryInteger {
    public func numericSummary() -> NumericSummary<Double> {
        _numericSummary(compactMap { $0.map(Double.init) }, noneCount: missingCount)
    }
}

extension DiscontiguousColumnSlice where WrappedElement: BinaryInteger {
    public func numericSummary() -> NumericSummary<Double> {
        _numericSummary(compactMap { $0.map(Double.init) }, noneCount: missingCount)
    }
}

extension Column where WrappedElement: Hashable {
    public func summary() -> CategoricalSummary<WrappedElement> {
        _categoricalSummary(self)
    }
}

extension DiscontiguousColumnSlice where WrappedElement: Hashable {
    public func summary() -> CategoricalSummary<WrappedElement> {
        _categoricalSummary(self)
    }
}

extension ColumnSlice where WrappedElement: Hashable {
    public func summary() -> CategoricalSummary<WrappedElement> {
        _categoricalSummary(self)
    }
}

extension FilledColumn where Base.WrappedElement: Hashable {
    public func summary() -> CategoricalSummary<FilledColumn<Base>.WrappedElement> {
        _categoricalSummary(map { Optional($0) })
    }
}

extension AnyColumnSlice {
    public func summary() -> AnyCategoricalSummary {
        if let type = wrappedElementType as? any Hashable.Type {
            func typed<T: Hashable>(_ type: T.Type) -> AnyCategoricalSummary {
                AnyCategoricalSummary(assumingType(T.self).summary())
            }
            return typed(type)
        }
        // Values that aren't hashable are told apart by their descriptions.
        let summary: CategoricalSummary<String> = _categoricalSummary(map { $0.map { String(reflecting: $0) } })
        var result = AnyCategoricalSummary(summary)
        result.mode = []
        result.modeType = wrappedElementType
        return result
    }
}

// MARK: - A frame's summary

public enum SummaryColumnIDs: Sendable {
    public static let columnName = ColumnID("column", String.self)
    public static let mean = ColumnID("mean", Double.self)
    public static let standardDeviation = ColumnID("std", Double.self)
    public static let minimum = ColumnID("min", Double.self)
    public static let maximum = ColumnID("max", Double.self)
    public static let median = ColumnID("median", Double.self)
    public static let firstQuartile = ColumnID("Q1", Double.self)
    public static let thirdQuartile = ColumnID("Q3", Double.self)
    public static let mode = ColumnID("mode", [Any].self)
    public static let uniqueCount = ColumnID("uniqueCount", Int.self)
    public static let noneCount = ColumnID("noneCount", Int.self)
    public static let someCount = ColumnID("someCount", Int.self)
}

/// The values of a column at the indices given as Doubles, if its elements are numbers.
internal func _doubles(_ column: AnyColumn, _ indices: [Int]) -> [Double?]? {
    if let type = column.wrappedElementType as? any BinaryInteger.Type {
        func typed<T: BinaryInteger>(_ type: T.Type) -> [Double?] {
            let typed = column.assumingType(T.self)
            return indices.map { typed[$0].map(Double.init) }
        }
        return typed(type)
    }
    if let type = column.wrappedElementType as? any BinaryFloatingPoint.Type {
        func typed<T: BinaryFloatingPoint>(_ type: T.Type) -> [Double?] {
            let typed = column.assumingType(T.self)
            return indices.map { typed[$0].map(Double.init) }
        }
        return typed(type)
    }
    return nil
}

/// A frame of one row per column given: numeric statistics where the column
/// holds numbers, and categorical ones for all.
internal func _summary(of frame: DataFrame, columns columnIndices: [Int], rows: [Int]) -> DataFrame {
    var names = Column(SummaryColumnIDs.columnName, capacity: columnIndices.count)
    var means = Column(SummaryColumnIDs.mean, capacity: columnIndices.count)
    var deviations = Column(SummaryColumnIDs.standardDeviation, capacity: columnIndices.count)
    var minimums = Column(SummaryColumnIDs.minimum, capacity: columnIndices.count)
    var maximums = Column(SummaryColumnIDs.maximum, capacity: columnIndices.count)
    var medians = Column(SummaryColumnIDs.median, capacity: columnIndices.count)
    var firstQuartiles = Column(SummaryColumnIDs.firstQuartile, capacity: columnIndices.count)
    var thirdQuartiles = Column(SummaryColumnIDs.thirdQuartile, capacity: columnIndices.count)
    var modes = Column(SummaryColumnIDs.mode, capacity: columnIndices.count)
    var uniqueCounts = Column(SummaryColumnIDs.uniqueCount, capacity: columnIndices.count)
    var noneCounts = Column(SummaryColumnIDs.noneCount, capacity: columnIndices.count)
    var someCounts = Column(SummaryColumnIDs.someCount, capacity: columnIndices.count)
    let set = _RangeSet(sortedIndices: rows)
    for index in columnIndices {
        let column = frame._columns[index]
        names.append(column.name)
        if let values = _doubles(column, rows) {
            let summary = _numericSummary(values.compactMap { $0 }, noneCount: values.count { $0 == nil })
            means.append(summary.mean)
            deviations.append(summary.standardDeviation)
            minimums.append(summary.min)
            maximums.append(summary.max)
            medians.append(summary.median)
            firstQuartiles.append(summary.firstQuartile)
            thirdQuartiles.append(summary.thirdQuartile)
        } else {
            means.append(nil)
            deviations.append(nil)
            minimums.append(nil)
            maximums.append(nil)
            medians.append(nil)
            firstQuartiles.append(nil)
            thirdQuartiles.append(nil)
        }
        let categorical = AnyColumnSlice(column: column, set: set).summary()
        modes.append(categorical.mode)
        uniqueCounts.append(categorical.uniqueCount)
        noneCounts.append(categorical.noneCount)
        someCounts.append(categorical.someCount)
    }
    var result = DataFrame()
    result.append(column: names)
    result.append(column: means)
    result.append(column: deviations)
    result.append(column: minimums)
    result.append(column: maximums)
    result.append(column: medians)
    result.append(column: firstQuartiles)
    result.append(column: thirdQuartiles)
    result.append(column: modes)
    result.append(column: uniqueCounts)
    result.append(column: noneCounts)
    result.append(column: someCounts)
    return result
}

extension DataFrame {
    public func summary() -> DataFrame {
        _summary(of: self, columns: Array(_columns.indices), rows: Array(0 ..< _rowCount))
    }

    public func summary(of columnNames: String...) -> DataFrame {
        _summary(of: self, columns: columnNames.map(_requireColumn), rows: Array(0 ..< _rowCount))
    }

    public func summary(ofColumns columnIndices: Int...) -> DataFrame {
        _summary(of: self, columns: columnIndices, rows: Array(0 ..< _rowCount))
    }
}

extension DataFrame.Slice {
    public func summary() -> DataFrame {
        _summary(of: _base, columns: Array(_base._columns.indices), rows: _set.indices)
    }

    public func summary(of columnNames: String...) -> DataFrame {
        _summary(of: _base, columns: columnNames.map(_base._requireColumn), rows: _set.indices)
    }

    public func summary(ofColumns columnIndices: Int...) -> DataFrame {
        _summary(of: _base, columns: columnIndices, rows: _set.indices)
    }
}
