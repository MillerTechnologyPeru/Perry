// Reshaping frames: exploding collections into rows, combining columns,
// and shaped (multidimensional) data.

import Foundation

extension DataFrame {
    public mutating func explodeColumn<T>(_ id: ColumnID<T>) where T: Collection {
        self = explodingColumn(id)
    }

    public mutating func explodeColumn<T>(_ name: String, _ type: T.Type) where T: Collection {
        self = explodingColumn(name, type)
    }

    /// A frame with a row for each element of the column's collections (none
    /// for a missing or empty collection), the other columns repeated.
    public func explodingColumn<T>(_ name: String, _ type: T.Type) -> DataFrame where T: Collection {
        let index = _requireColumn(name)
        let column = _columns[index].assumingType(T.self)
        var rows: [Int] = []
        var elements = Column<T.Element>(name: column.name, capacity: column.count)
        for row in 0 ..< column.count {
            guard let collection = column[row] else { continue }
            for element in collection {
                rows.append(row)
                elements.append(element)
            }
        }
        var result = _keepingAliases(_gathering(rows))
        result._columns[index] = elements.eraseToAnyColumn()
        return result
    }

    public func explodingColumn<T>(_ id: ColumnID<T>) -> DataFrame where T: Collection {
        explodingColumn(id.name, T.self)
    }

    public mutating func combineColumns<E1, E2, R>(_ columnName1: String, _ columnName2: String, into newColumnName: String,
                                                   transform: (E1?, E2?) throws -> R?) rethrows {
        let first = self[columnName1, E1.self], second = self[columnName2, E2.self]
        var combined = Column<R>(name: newColumnName, capacity: _rowCount)
        for row in 0 ..< _rowCount { combined.append(try transform(first[row], second[row])) }
        _replaceCombined(columnName1, with: combined, removing: [columnName2])
    }

    /// Puts a combined column in the first one's place and removes the others.
    private mutating func _replaceCombined<R>(_ first: String, with combined: Column<R>, removing others: [String]) {
        let index = _requireColumn(first)
        removeColumn(first)
        _columns.insert(combined.eraseToAnyColumn(), at: index)
        for name in others { removeColumn(name) }
    }

    public mutating func combineColumns<E1, E2, R>(_ columnID1: ColumnID<E1>, _ columnID2: ColumnID<E2>, into newColumnName: String,
                                                   transform: (E1?, E2?) throws -> R?) rethrows {
        try combineColumns(columnID1.name, columnID2.name, into: newColumnName, transform: transform)
    }

    public mutating func combineColumns<E1, E2, E3, R>(_ columnName1: String, _ columnName2: String, _ columnName3: String,
                                                       into newColumnName: String, transform: (E1?, E2?, E3?) throws -> R?) rethrows {
        let first = self[columnName1, E1.self], second = self[columnName2, E2.self], third = self[columnName3, E3.self]
        var combined = Column<R>(name: newColumnName, capacity: _rowCount)
        for row in 0 ..< _rowCount { combined.append(try transform(first[row], second[row], third[row])) }
        _replaceCombined(columnName1, with: combined, removing: [columnName2, columnName3])
    }

    public mutating func combineColumns<E1, E2, E3, R>(_ columnID1: ColumnID<E1>, _ columnID2: ColumnID<E2>, _ columnID3: ColumnID<E3>,
                                                       into newColumnName: String, transform: (E1?, E2?, E3?) throws -> R?) rethrows {
        try combineColumns(columnID1.name, columnID2.name, columnID3.name, into: newColumnName, transform: transform)
    }
}

/// Elements of a multidimensional array: a shape, the strides of its
/// dimensions in the contents, and the contents.
public struct ShapedData<Element> {
    public let shape: [Int]
    public let strides: [Int]
    public let contents: [Element]

    public init(shape: [Int], strides: [Int], contents: [Element]) {
        precondition(shape.count == strides.count, "The shape and the strides must have the same number of dimensions.")
        self.shape = shape
        self.strides = strides
        self.contents = contents
    }

    public subscript(indices: Int...) -> Element {
        precondition(indices.count == shape.count, "Expected \(shape.count) indices.")
        var offset = 0
        for (dimension, index) in indices.enumerated() {
            precondition(index >= 0 && index < shape[dimension], "Index out of range")
            offset += index * strides[dimension]
        }
        return contents[offset]
    }
}

extension ShapedData: Equatable where Element: Equatable {}
extension ShapedData: Hashable where Element: Hashable {}
extension ShapedData: Sendable where Element: Sendable {}
