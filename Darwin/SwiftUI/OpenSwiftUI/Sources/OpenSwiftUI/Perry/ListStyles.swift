//
//  ListStyles.swift
//  OpenSwiftUI
//
//  Status: Perry's implementation
//
//  List styles. A style says how a list's rows are drawn: on inset cards
//  (the default), on full-width cards, or plainly; listStyle puts it in the
//  environment, where the list reads it. Styles' view-making requirements
//  are there for the ABI; lists never call them.

#if os(iOS) || os(visionOS)
public import OpenSwiftUICore

// MARK: - ListStyle

/// A protocol that describes the behavior and appearance of a list.
@available(OpenSwiftUI_v1_0, *)
public protocol ListStyle {
    static func _makeView<SelectionValue>(value: _GraphValue<_ListValue<Self, SelectionValue>>, inputs: _ViewInputs) -> _ViewOutputs where SelectionValue: Hashable
    static func _makeViewList<SelectionValue>(value: _GraphValue<_ListValue<Self, SelectionValue>>, inputs: _ViewListInputs) -> _ViewListOutputs where SelectionValue: Hashable
}

@available(OpenSwiftUI_v1_0, *)
public struct _ListValue<Style, SelectionValue> where Style: ListStyle, SelectionValue: Hashable {}

@available(OpenSwiftUI_v1_0, *)
extension View {
    /// Sets the style for lists within this view.
    nonisolated public func listStyle<S>(_ style: S) -> some View where S: ListStyle {
        environment(\.listRowsStyle, (S.self as? RowsStyleProviding.Type)?.rowsStyle ?? .insetGrouped)
    }
}

// MARK: - How rows are drawn

/// How a list's rows are drawn.
enum RowsStyle: Equatable {
    /// Each section's rows on a rounded card inset from the edges, on a
    /// gray background.
    case insetGrouped
    /// Each section's rows on a card the list's width, on a gray background.
    case grouped
    /// Rows the list's width, on white, with section headers on gray bands.
    case plain

    var cardInset: CGFloat { self == .insetGrouped ? GroupedRowsRoot.inset : 0 }
    var cornerRadius: CGFloat { self == .insetGrouped ? 10 : 0 }
    var isPlain: Bool { self == .plain }
}

/// The styles of rows the list styles draw.
protocol RowsStyleProviding {
    static var rowsStyle: RowsStyle { get }
}

struct ListRowsStyleKey: EnvironmentKey {
    static let defaultValue: RowsStyle = .insetGrouped
}

extension EnvironmentValues {
    var listRowsStyle: RowsStyle {
        get { self[ListRowsStyleKey.self] }
        set { self[ListRowsStyleKey.self] = newValue }
    }
}

// MARK: - The styles

/// Generates a style's requirements, which no list calls.
private func unusedListMakeView() -> Never {
    preconditionFailure("List styles' views are made by the list")
}

/// The list style that describes a platform's default behavior and
/// appearance for a list.
@available(OpenSwiftUI_v1_0, *)
public struct DefaultListStyle: ListStyle, RowsStyleProviding {
    public init() {}
    static var rowsStyle: RowsStyle { .insetGrouped }
    nonisolated public static func _makeView<SelectionValue>(value: _GraphValue<_ListValue<DefaultListStyle, SelectionValue>>, inputs: _ViewInputs) -> _ViewOutputs where SelectionValue: Hashable { unusedListMakeView() }
    nonisolated public static func _makeViewList<SelectionValue>(value: _GraphValue<_ListValue<DefaultListStyle, SelectionValue>>, inputs: _ViewListInputs) -> _ViewListOutputs where SelectionValue: Hashable { unusedListMakeView() }
}

@available(OpenSwiftUI_v1_0, *)
extension ListStyle where Self == DefaultListStyle {
    @_alwaysEmitIntoClient
    public static var automatic: DefaultListStyle { .init() }
}

/// The list style that describes the behavior and appearance of a plain
/// list.
@available(OpenSwiftUI_v1_0, *)
public struct PlainListStyle: ListStyle, RowsStyleProviding {
    public init() {}
    static var rowsStyle: RowsStyle { .plain }
    nonisolated public static func _makeView<SelectionValue>(value: _GraphValue<_ListValue<PlainListStyle, SelectionValue>>, inputs: _ViewInputs) -> _ViewOutputs where SelectionValue: Hashable { unusedListMakeView() }
    nonisolated public static func _makeViewList<SelectionValue>(value: _GraphValue<_ListValue<PlainListStyle, SelectionValue>>, inputs: _ViewListInputs) -> _ViewListOutputs where SelectionValue: Hashable { unusedListMakeView() }
}

@available(OpenSwiftUI_v1_0, *)
extension ListStyle where Self == PlainListStyle {
    @_alwaysEmitIntoClient
    public static var plain: PlainListStyle { .init() }
}

/// The list style that describes the behavior and appearance of a grouped
/// list.
@available(OpenSwiftUI_v1_0, *)
public struct GroupedListStyle: ListStyle, RowsStyleProviding {
    public init() {}
    static var rowsStyle: RowsStyle { .grouped }
    nonisolated public static func _makeView<SelectionValue>(value: _GraphValue<_ListValue<GroupedListStyle, SelectionValue>>, inputs: _ViewInputs) -> _ViewOutputs where SelectionValue: Hashable { unusedListMakeView() }
    nonisolated public static func _makeViewList<SelectionValue>(value: _GraphValue<_ListValue<GroupedListStyle, SelectionValue>>, inputs: _ViewListInputs) -> _ViewListOutputs where SelectionValue: Hashable { unusedListMakeView() }
}

@available(OpenSwiftUI_v1_0, *)
extension ListStyle where Self == GroupedListStyle {
    @_alwaysEmitIntoClient
    public static var grouped: GroupedListStyle { .init() }
}

/// The list style that describes the behavior and appearance of an inset
/// grouped list.
@available(OpenSwiftUI_v2_0, *)
public struct InsetGroupedListStyle: ListStyle, RowsStyleProviding {
    public init() {}
    static var rowsStyle: RowsStyle { .insetGrouped }
    nonisolated public static func _makeView<SelectionValue>(value: _GraphValue<_ListValue<InsetGroupedListStyle, SelectionValue>>, inputs: _ViewInputs) -> _ViewOutputs where SelectionValue: Hashable { unusedListMakeView() }
    nonisolated public static func _makeViewList<SelectionValue>(value: _GraphValue<_ListValue<InsetGroupedListStyle, SelectionValue>>, inputs: _ViewListInputs) -> _ViewListOutputs where SelectionValue: Hashable { unusedListMakeView() }
}

@available(OpenSwiftUI_v2_0, *)
extension ListStyle where Self == InsetGroupedListStyle {
    @_alwaysEmitIntoClient
    public static var insetGrouped: InsetGroupedListStyle { .init() }
}

/// The list style that describes the behavior and appearance of an inset
/// list.
@available(OpenSwiftUI_v2_0, *)
public struct InsetListStyle: ListStyle, RowsStyleProviding {
    public init() {}
    static var rowsStyle: RowsStyle { .plain }
    nonisolated public static func _makeView<SelectionValue>(value: _GraphValue<_ListValue<InsetListStyle, SelectionValue>>, inputs: _ViewInputs) -> _ViewOutputs where SelectionValue: Hashable { unusedListMakeView() }
    nonisolated public static func _makeViewList<SelectionValue>(value: _GraphValue<_ListValue<InsetListStyle, SelectionValue>>, inputs: _ViewListInputs) -> _ViewListOutputs where SelectionValue: Hashable { unusedListMakeView() }
}

@available(OpenSwiftUI_v2_0, *)
extension ListStyle where Self == InsetListStyle {
    @_alwaysEmitIntoClient
    public static var inset: InsetListStyle { .init() }
}

/// The list style that describes the behavior and appearance of a sidebar
/// list.
@available(OpenSwiftUI_v2_0, *)
public struct SidebarListStyle: ListStyle, RowsStyleProviding {
    public init() {}
    static var rowsStyle: RowsStyle { .insetGrouped }
    nonisolated public static func _makeView<SelectionValue>(value: _GraphValue<_ListValue<SidebarListStyle, SelectionValue>>, inputs: _ViewInputs) -> _ViewOutputs where SelectionValue: Hashable { unusedListMakeView() }
    nonisolated public static func _makeViewList<SelectionValue>(value: _GraphValue<_ListValue<SidebarListStyle, SelectionValue>>, inputs: _ViewListInputs) -> _ViewListOutputs where SelectionValue: Hashable { unusedListMakeView() }
}

@available(OpenSwiftUI_v2_0, *)
extension ListStyle where Self == SidebarListStyle {
    @_alwaysEmitIntoClient
    public static var sidebar: SidebarListStyle { .init() }
}
#endif
