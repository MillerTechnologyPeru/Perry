// Joining frames on key columns. The result has the key column, named as
// the left one, then the left frame's other columns prefixed "left." and
// the right frame's prefixed "right.".

import Foundation

public enum JoinKind: Sendable {
    case inner
    case left
    case right
    case full
}

/// Pairs of matching left and right rows (nil where a row has no match).
private func _joinPairs<T: Hashable>(_ left: Column<T>, _ leftRows: [Int], _ right: Column<T>, _ rightRows: [Int],
                                      kind: JoinKind) -> [(Int?, Int?)] {
    var pairs: [(Int?, Int?)] = []
    if kind == .right {
        var leftByKey: [T: [Int]] = [:]
        for row in leftRows { if let key = left[row] { leftByKey[key, default: []].append(row) } }
        for row in rightRows {
            let matches = right[row].flatMap { leftByKey[$0] } ?? []
            if matches.isEmpty {
                pairs.append((nil, row))
            } else {
                for match in matches { pairs.append((match, row)) }
            }
        }
        return pairs
    }
    var rightByKey: [T: [Int]] = [:]
    for row in rightRows { if let key = right[row] { rightByKey[key, default: []].append(row) } }
    var matched = Set<Int>()
    for row in leftRows {
        let matches = left[row].flatMap { rightByKey[$0] } ?? []
        if matches.isEmpty {
            if kind != .inner { pairs.append((row, nil)) }
        } else {
            for match in matches {
                pairs.append((row, match))
                matched.insert(match)
            }
        }
    }
    if kind == .full {
        for row in rightRows where !matched.contains(row) { pairs.append((nil, row)) }
    }
    return pairs
}

private func _join<T: Hashable>(_ type: T.Type, left: DataFrame, leftRows: [Int], leftKey: String,
                                right: DataFrame, rightRows: [Int], rightKey: String, kind: JoinKind) -> DataFrame {
    let leftColumn = left[leftKey, T.self], rightColumn = right[rightKey, T.self]
    let pairs = _joinPairs(leftColumn, leftRows, rightColumn, rightRows, kind: kind)
    var result = DataFrame()
    result.append(column: Column<T>(name: leftColumn.name, contents: pairs.map { pair -> T? in
        if let row = pair.0, let key = leftColumn[row] { return key }
        return pair.1.flatMap { rightColumn[$0] }
    }))
    let leftIndices = pairs.map(\.0), rightIndices = pairs.map(\.1)
    for column in left._columns where column.name != leftColumn.name {
        var gathered = column._gathering(leftIndices)
        gathered.name = "left." + column.name
        result.append(column: gathered)
    }
    for column in right._columns where column.name != rightColumn.name {
        var gathered = column._gathering(rightIndices)
        gathered.name = "right." + column.name
        result.append(column: gathered)
    }
    return result
}

extension DataFrameProtocol {
    public func joined<R>(_ other: R, on columnName: String, kind: JoinKind = .inner) -> DataFrame where R: DataFrameProtocol {
        joined(other, on: (left: columnName, right: columnName), kind: kind)
    }

    public func joined<R, T>(_ other: R, on columnID: ColumnID<T>, kind: JoinKind = .inner) -> DataFrame
    where R: DataFrameProtocol, T: Hashable {
        _join(T.self, left: base, leftRows: _rowIndices, leftKey: columnID.name,
              right: other.base, rightRows: other._rowIndices, rightKey: columnID.name, kind: kind)
    }

    public func joined<R>(_ other: R, on columnNames: (left: String, right: String), kind: JoinKind = .inner) -> DataFrame
    where R: DataFrameProtocol {
        let leftColumn = base[columnNames.left]
        guard let type = leftColumn.wrappedElementType as? any Hashable.Type else {
            fatalError("Column '\(leftColumn.name)' of type \(leftColumn.wrappedElementType) isn't hashable.")
        }
        func typed<T: Hashable>(_ type: T.Type) -> DataFrame {
            _join(T.self, left: base, leftRows: _rowIndices, leftKey: columnNames.left,
                  right: other.base, rightRows: other._rowIndices, rightKey: columnNames.right, kind: kind)
        }
        return typed(type)
    }

    public func joined<R, T>(_ other: R, on columnIDs: (left: ColumnID<T>, right: ColumnID<T>), kind: JoinKind = .inner) -> DataFrame
    where R: DataFrameProtocol, T: Hashable {
        _join(T.self, left: base, leftRows: _rowIndices, leftKey: columnIDs.left.name,
              right: other.base, rightRows: other._rowIndices, rightKey: columnIDs.right.name, kind: kind)
    }
}
