// Sorting frames by columns: stable, with missing values last in either order.

import Foundation

public enum Order: Sendable {
    case ascending
    case descending

    public func areOrdered<T>(_ lhs: T, _ rhs: T) -> Bool where T: Comparable {
        switch self {
        case .ascending: return lhs < rhs
        case .descending: return lhs > rhs
        }
    }
}

/// Compares two rows by one column: less (-1), equal (0) or greater (1),
/// missing values after all others.
internal typealias _RowComparison = (Int, Int) -> Int

internal func _comparison<T: Comparable>(_ column: Column<T>, _ order: Order) -> _RowComparison {
    return { i, j in
        switch (column[i], column[j]) {
        case (nil, nil): return 0
        case (nil, _): return 1
        case (_, nil): return -1
        case let (a?, b?):
            if order.areOrdered(a, b) { return -1 }
            if order.areOrdered(b, a) { return 1 }
            return 0
        }
    }
}

/// Row indices sorted stably by the comparisons, the first deciding first.
internal func _sortedIndices(_ indices: [Int], by comparisons: [_RowComparison]) -> [Int] {
    indices.enumerated().sorted { a, b in
        for comparison in comparisons {
            let result = comparison(a.element, b.element)
            if result != 0 { return result < 0 }
        }
        return a.offset < b.offset
    }.map(\.element)
}

/// A comparison by a column whose element type is only known to be comparable at run time.
internal func _dynamicComparison(_ column: AnyColumn, _ order: Order) -> _RowComparison {
    guard let type = column.wrappedElementType as? any Comparable.Type else {
        fatalError("Column '\(column.name)' of type \(column.wrappedElementType) isn't comparable.")
    }
    func typed<T: Comparable>(_ type: T.Type) -> _RowComparison {
        _comparison(column.assumingType(T.self), order)
    }
    return typed(type)
}

extension DataFrameProtocol {
    internal func _sorted(by comparisons: [_RowComparison]) -> DataFrame {
        base._gathering(_sortedIndices(_rowIndices, by: comparisons))
    }

    public func sorted(on columnName: String, order: Order = .ascending) -> DataFrame {
        _sorted(by: [_dynamicComparison(base[columnName], order)])
    }

    public func sorted<T>(on columnName: String, _ type: T.Type, order: Order = .ascending) -> DataFrame where T: Comparable {
        _sorted(by: [_comparison(base[columnName, T.self], order)])
    }

    public func sorted<T>(on columnID: ColumnID<T>, order: Order = .ascending) -> DataFrame where T: Comparable {
        _sorted(by: [_comparison(base[columnID], order)])
    }

    public func sorted<T0, T1>(on columnID0: ColumnID<T0>, _ columnID1: ColumnID<T1>, order: Order = .ascending) -> DataFrame
    where T0: Comparable, T1: Comparable {
        _sorted(by: [_comparison(base[columnID0], order), _comparison(base[columnID1], order)])
    }

    public func sorted<T0, T1, T2>(on columnID0: ColumnID<T0>, _ columnID1: ColumnID<T1>, _ columnID2: ColumnID<T2>,
                                   order: Order = .ascending) -> DataFrame
    where T0: Comparable, T1: Comparable, T2: Comparable {
        _sorted(by: [_comparison(base[columnID0], order), _comparison(base[columnID1], order), _comparison(base[columnID2], order)])
    }

    public func sorted<T>(on columnName: String, _ type: T.Type, by areInIncreasingOrder: (T, T) throws -> Bool) rethrows -> DataFrame {
        let column = base[columnName, T.self]
        let indices = _rowIndices
        let sorted = try indices.filter { !column.isNil(at: $0) }.enumerated().sorted { a, b in
            let x = column[a.element]!, y = column[b.element]!
            if try areInIncreasingOrder(x, y) { return true }
            if try areInIncreasingOrder(y, x) { return false }
            return a.offset < b.offset
        }.map(\.element)
        return base._gathering(sorted + indices.filter { column.isNil(at: $0) })
    }

    public func sorted<T>(on columnID: ColumnID<T>, by areInIncreasingOrder: (T, T) throws -> Bool) rethrows -> DataFrame {
        try sorted(on: columnID.name, T.self, by: areInIncreasingOrder)
    }
}

extension DataFrame {
    public mutating func sort(on columnName: String, order: Order = .ascending) {
        self = _keepingAliases(sorted(on: columnName, order: order))
    }

    public mutating func sort<T>(on columnName: String, _ type: T.Type, order: Order = .ascending) where T: Comparable {
        self = _keepingAliases(sorted(on: columnName, type, order: order))
    }

    public mutating func sort<T>(on columnID: ColumnID<T>, order: Order = .ascending) where T: Comparable {
        self = _keepingAliases(sorted(on: columnID, order: order))
    }

    public mutating func sort<T0, T1>(on columnID0: ColumnID<T0>, _ columnID1: ColumnID<T1>, order: Order = .ascending)
    where T0: Comparable, T1: Comparable {
        self = _keepingAliases(sorted(on: columnID0, columnID1, order: order))
    }

    public mutating func sort<T0, T1, T2>(on columnID0: ColumnID<T0>, _ columnID1: ColumnID<T1>, _ columnID2: ColumnID<T2>,
                                          order: Order = .ascending)
    where T0: Comparable, T1: Comparable, T2: Comparable {
        self = _keepingAliases(sorted(on: columnID0, columnID1, columnID2, order: order))
    }

    public mutating func sort<T>(on columnID: ColumnID<T>, by areInIncreasingOrder: (T, T) throws -> Bool) rethrows {
        self = _keepingAliases(try sorted(on: columnID, by: areInIncreasingOrder))
    }

    public mutating func sort<T>(on columnName: String, _ type: T.Type, by areInIncreasingOrder: (T, T) throws -> Bool) rethrows {
        self = _keepingAliases(try sorted(on: columnName, type, by: areInIncreasingOrder))
    }

    /// A frame with this one's column aliases.
    internal func _keepingAliases(_ frame: DataFrame) -> DataFrame {
        var result = frame
        result._aliases = _aliases
        return result
    }
}
