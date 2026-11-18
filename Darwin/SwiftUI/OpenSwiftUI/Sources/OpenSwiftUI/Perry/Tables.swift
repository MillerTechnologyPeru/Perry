//
//  Tables.swift
//  OpenSwiftUI
//
//  Status: Perry's implementation
//
//  The protocols a table's rows and columns conform to, for types that
//  declare such content. Perry has no Table view yet, so nothing reads
//  rows or columns: the graph-making requirements make nothing and count
//  nothing.

#if os(iOS) || os(visionOS)
public import Foundation
public import OpenSwiftUICore

// MARK: - TableColumnContent

/// A type used to represent columns within a table.
@available(OpenSwiftUI_v1_0, *)
@preconcurrency
@MainActor
public protocol TableColumnContent<TableRowValue, TableColumnSortComparator> {
    /// The type of value of rows presented by this column content.
    associatedtype TableRowValue: Identifiable = TableColumnBody.TableRowValue

    /// The type of sort comparator associated with this table column
    /// content.
    associatedtype TableColumnSortComparator: SortComparator = TableColumnBody.TableColumnSortComparator

    /// The type of content representing the body of this table column
    /// content.
    associatedtype TableColumnBody: TableColumnContent

    /// The composition of content that comprise the table column content.
    nonisolated var tableColumnBody: TableColumnBody { get }

    nonisolated static func _makeContent(content: _GraphValue<Self>, inputs: _TableColumnInputs) -> _TableColumnOutputs

    nonisolated static func _tableColumnCount(inputs: _TableColumnInputs) -> Int?
}

/// Inputs for making a table's columns; nothing makes them here.
@available(OpenSwiftUI_v1_0, *)
public struct _TableColumnInputs {}

@available(*, unavailable)
extension _TableColumnInputs: Sendable {}

/// Outputs of making a table's columns; empty here.
@available(OpenSwiftUI_v1_0, *)
public struct _TableColumnOutputs {}

@available(*, unavailable)
extension _TableColumnOutputs: Sendable {}

@available(OpenSwiftUI_v1_0, *)
extension TableColumnContent where TableColumnSortComparator == TableColumnBody.TableColumnSortComparator, TableRowValue == TableColumnBody.TableRowValue {
    /// Makes no columns.
    nonisolated public static func _makeContent(content: _GraphValue<Self>, inputs: _TableColumnInputs) -> _TableColumnOutputs {
        _TableColumnOutputs()
    }
}

@available(OpenSwiftUI_v1_0, *)
extension TableColumnContent {
    /// The number of columns, which isn't known without making them.
    nonisolated public static func _tableColumnCount(inputs: _TableColumnInputs) -> Int? {
        nil
    }
}

@available(OpenSwiftUI_v1_0, *)
extension Never: TableColumnContent {
    public typealias TableColumnSortComparator = Never
    public typealias TableColumnBody = Never

    nonisolated public var tableColumnBody: Never {
        switch self {}
    }

    nonisolated public static func _tableColumnCount(inputs: _TableColumnInputs) -> Int? {
        0
    }
}

// MARK: - TableRowContent

/// A type used to represent table rows.
@available(OpenSwiftUI_v1_0, *)
@preconcurrency
@MainActor
public protocol TableRowContent<TableRowValue> {
    /// The type of value represented by this table row content.
    associatedtype TableRowValue: Identifiable = TableRowBody.TableRowValue

    /// The type of content representing the body of this table row
    /// content.
    associatedtype TableRowBody: TableRowContent

    /// The composition of content that comprise the table row content.
    @MainActor
    @preconcurrency
    var tableRowBody: TableRowBody { get }

    nonisolated static func _makeRows(content: _GraphValue<Self>, inputs: _TableRowInputs) -> _TableRowOutputs

    nonisolated static func _tableRowCount(inputs: _TableRowInputs) -> Int?

    nonisolated static func _containsOutlineSymbol(inputs: _TableRowInputs) -> Bool
}

/// Inputs for making a table's rows; nothing makes them here.
@available(OpenSwiftUI_v1_0, *)
public struct _TableRowInputs {}

@available(*, unavailable)
extension _TableRowInputs: Sendable {}

/// Outputs of making a table's rows; empty here.
@available(OpenSwiftUI_v1_0, *)
public struct _TableRowOutputs {}

@available(*, unavailable)
extension _TableRowOutputs: Sendable {}

@available(OpenSwiftUI_v1_0, *)
extension TableRowContent {
    /// Makes no rows.
    nonisolated public static func _makeRows(content: _GraphValue<Self>, inputs: _TableRowInputs) -> _TableRowOutputs {
        _TableRowOutputs()
    }

    /// The number of rows, which isn't known without making them.
    nonisolated public static func _tableRowCount(inputs: _TableRowInputs) -> Int? {
        nil
    }

    /// Whether the rows show a disclosure indicator: none do.
    nonisolated public static func _containsOutlineSymbol(inputs: _TableRowInputs) -> Bool {
        false
    }
}

@available(OpenSwiftUI_v1_0, *)
extension Never {
    public typealias TableRowValue = Never
}

@available(OpenSwiftUI_v1_0, *)
extension Never: TableRowContent {
    public typealias TableRowBody = Never

    @MainActor
    @preconcurrency
    public var tableRowBody: Never {
        switch self {}
    }

    nonisolated public static func _tableRowCount(inputs: _TableRowInputs) -> Int? {
        0
    }

    nonisolated public static func _containsOutlineSymbol(inputs: _TableRowInputs) -> Bool {
        false
    }
}
#endif
