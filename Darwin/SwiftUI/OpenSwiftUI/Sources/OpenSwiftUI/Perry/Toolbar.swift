//
//  Toolbar.swift
//  OpenSwiftUI
//
//  Status: Perry's implementation
//
//  Toolbar content: items with a placement, which `toolbar` draws over the
//  enclosing navigation stack's bar, leading, centered or trailing, as
//  `navigationBarItems` does. Items for the keyboard or the bottom bar
//  aren't shown. Toolbar content's graph-making requirements are there for
//  the ABI; toolbars read the items' values instead.

#if os(iOS) || os(visionOS)
public import OpenSwiftUICore

// MARK: - ToolbarContent

/// Inputs for making toolbar content; toolbars here read items directly.
@available(OpenSwiftUI_v4_0, *)
public struct _ToolbarInputs {}

/// Outputs of making toolbar content.
@available(OpenSwiftUI_v4_0, *)
public struct _ToolbarOutputs {}

/// The items toolbar content resolves to.
@available(OpenSwiftUI_v2_0, *)
public struct _ToolbarItemList {}

/// Conforming types represent items that can be placed in various locations
/// in a toolbar.
@available(OpenSwiftUI_v2_0, *)
@preconcurrency
@MainActor
public protocol ToolbarContent {
    associatedtype Body: ToolbarContent

    @ToolbarContentBuilder
    @MainActor
    @preconcurrency
    var body: Body { get }

    @available(OpenSwiftUI_v4_0, *)
    nonisolated static func _makeToolbar(content: _GraphValue<Self>, inputs: _ToolbarInputs) -> _ToolbarOutputs

    nonisolated static func _makeContent(content: _GraphValue<Self>, inputs: _GraphInputs, resolved: inout _ToolbarItemList)
}

@available(OpenSwiftUI_v2_0, *)
extension ToolbarContent {
    @available(OpenSwiftUI_v4_0, *)
    nonisolated public static func _makeToolbar(content: _GraphValue<Self>, inputs: _ToolbarInputs) -> _ToolbarOutputs {
        _ToolbarOutputs()
    }

    nonisolated public static func _makeContent(content: _GraphValue<Self>, inputs: _GraphInputs, resolved: inout _ToolbarItemList) {}
}

@available(OpenSwiftUI_v2_0, *)
extension Never: ToolbarContent {}

@available(OpenSwiftUI_v2_0, *)
extension ToolbarContent where Body == Never {
    public var body: Never {
        preconditionFailure("\(Self.self) is primitive toolbar content")
    }
}

/// Toolbar content that lists its items: ToolbarItem, ToolbarItemGroup
/// and the builder's tuples.
protocol ResolvedToolbarContent {
    var resolvedItems: [ResolvedToolbarItem] { get }
}

struct ResolvedToolbarItem {
    var placement: ToolbarItemPlacement
    var view: AnyView
}

extension ToolbarContent {
    /// The items this content shows, through its body when it isn't an
    /// item itself.
    @MainActor
    var resolvedItems: [ResolvedToolbarItem] {
        if let content = self as? ResolvedToolbarContent {
            return content.resolvedItems
        }
        if Body.self == Never.self {
            return []
        }
        return body.resolvedItems
    }
}

// MARK: - ToolbarContentBuilder

/// Constructs a toolbar item set from multi-expression closures.
@available(OpenSwiftUI_v2_0, *)
@resultBuilder
public struct ToolbarContentBuilder {
    @_alwaysEmitIntoClient
    public static func buildExpression<Content>(_ content: Content) -> Content where Content: ToolbarContent {
        content
    }

    public static func buildBlock<Content>(_ content: Content) -> some ToolbarContent where Content: ToolbarContent {
        content
    }
}

@available(OpenSwiftUI_v2_0, *)
extension ToolbarContentBuilder {
    public static func buildBlock<C0, C1>(_ c0: C0, _ c1: C1) -> some ToolbarContent
    where C0: ToolbarContent, C1: ToolbarContent {
        TupleToolbarContent<(C0, C1)>((c0, c1))
    }

    public static func buildBlock<C0, C1, C2>(_ c0: C0, _ c1: C1, _ c2: C2) -> some ToolbarContent
    where C0: ToolbarContent, C1: ToolbarContent, C2: ToolbarContent {
        TupleToolbarContent<(C0, C1, C2)>((c0, c1, c2))
    }

    public static func buildBlock<C0, C1, C2, C3>(_ c0: C0, _ c1: C1, _ c2: C2, _ c3: C3) -> some ToolbarContent
    where C0: ToolbarContent, C1: ToolbarContent, C2: ToolbarContent, C3: ToolbarContent {
        TupleToolbarContent<(C0, C1, C2, C3)>((c0, c1, c2, c3))
    }
}

/// Several toolbar contents together, as the builder makes them: a tuple
/// of them, which apps' inlined builders make too.
@available(OpenSwiftUI_v2_0, *)
@usableFromInline
nonisolated struct TupleToolbarContent<T>: ToolbarContent, ResolvedToolbarContent {
    @usableFromInline
    typealias Body = Never
    var value: T

    @usableFromInline
    nonisolated init(_ value: T) {
        self.value = value
    }

    /// The tuple's contents' items, in order.
    var resolvedItems: [ResolvedToolbarItem] {
        MainActor.assumeIsolated {
            Mirror(reflecting: value).children.flatMap { child -> [ResolvedToolbarItem] in
                (child.value as? any ToolbarContent)?.resolvedItems ?? []
            }
        }
    }
}

// MARK: - Placements

/// A structure that defines the placement of a toolbar item.
@available(OpenSwiftUI_v2_0, *)
public struct ToolbarItemPlacement {
    enum Role: Equatable {
        case automatic, principal, navigation, primaryAction, secondaryAction, status
        case confirmationAction, cancellationAction, destructiveAction, keyboard
        case navigationBarLeading, navigationBarTrailing, bottomBar
    }

    var role: Role

    public static let automatic = ToolbarItemPlacement(role: .automatic)
    public static let principal = ToolbarItemPlacement(role: .principal)
    public static let navigation = ToolbarItemPlacement(role: .navigation)
    public static let primaryAction = ToolbarItemPlacement(role: .primaryAction)
    public static let secondaryAction = ToolbarItemPlacement(role: .secondaryAction)
    public static let status = ToolbarItemPlacement(role: .status)
    public static let confirmationAction = ToolbarItemPlacement(role: .confirmationAction)
    public static let cancellationAction = ToolbarItemPlacement(role: .cancellationAction)
    public static let destructiveAction = ToolbarItemPlacement(role: .destructiveAction)
    public static let keyboard = ToolbarItemPlacement(role: .keyboard)
    public static let navigationBarLeading = ToolbarItemPlacement(role: .navigationBarLeading)
    public static let navigationBarTrailing = ToolbarItemPlacement(role: .navigationBarTrailing)
    public static let bottomBar = ToolbarItemPlacement(role: .bottomBar)

    public static var topBarLeading: ToolbarItemPlacement { .navigationBarLeading }
    public static var topBarTrailing: ToolbarItemPlacement { .navigationBarTrailing }

    /// Where in the navigation bar the item goes, or nil where it isn't
    /// shown.
    var barSlot: BarSlot? {
        switch role {
        case .navigation, .navigationBarLeading, .cancellationAction: .leading
        case .principal: .principal
        case .keyboard, .bottomBar, .status: nil
        default: .trailing
        }
    }

    enum BarSlot { case leading, principal, trailing }
}

/// The placement of a bar that a toolbar modifier affects.
@available(OpenSwiftUI_v4_0, *)
public struct ToolbarPlacement {
    enum Bar: Equatable { case automatic, bottomBar, navigationBar, tabBar }

    var bar: Bar

    public static var automatic: ToolbarPlacement { ToolbarPlacement(bar: .automatic) }
    public static var bottomBar: ToolbarPlacement { ToolbarPlacement(bar: .bottomBar) }
    public static var navigationBar: ToolbarPlacement { ToolbarPlacement(bar: .navigationBar) }
    public static var tabBar: ToolbarPlacement { ToolbarPlacement(bar: .tabBar) }
}

// MARK: - Items

/// A model that represents an item which can be placed in the toolbar or
/// navigation bar.
@available(OpenSwiftUI_v2_0, *)
nonisolated public struct ToolbarItem<ID, Content>: ToolbarContent, ResolvedToolbarContent where Content: View {
    public typealias Body = Never
    var placement: ToolbarItemPlacement
    var content: Content

    var resolvedItems: [ResolvedToolbarItem] {
        [ResolvedToolbarItem(placement: placement, view: AnyView(content))]
    }
}

@available(OpenSwiftUI_v2_0, *)
extension ToolbarItem where ID == () {
    nonisolated public init(placement: ToolbarItemPlacement = .automatic, @ViewBuilder content: () -> Content) {
        self.placement = placement
        self.content = content()
    }
}

/// A model that represents a group of `ToolbarItem`s which can be placed in
/// the toolbar or navigation bar.
@available(OpenSwiftUI_v2_0, *)
nonisolated public struct ToolbarItemGroup<Content>: ToolbarContent, ResolvedToolbarContent where Content: View {
    public typealias Body = Never
    var placement: ToolbarItemPlacement
    var content: Content

    nonisolated public init(placement: ToolbarItemPlacement = .automatic, @ViewBuilder content: () -> Content) {
        self.placement = placement
        self.content = content()
    }

    var resolvedItems: [ResolvedToolbarItem] {
        [ResolvedToolbarItem(placement: placement, view: AnyView(HStack(spacing: 16) { content }))]
    }
}

// MARK: - Modifiers

@available(OpenSwiftUI_v2_0, *)
extension View {
    /// Populates the toolbar or navigation bar with the specified items.
    nonisolated public func toolbar<Content>(@ToolbarContentBuilder content: () -> Content) -> some View where Content: ToolbarContent {
        let items = MainActor.assumeIsolated { content().resolvedItems }
        func views(_ slot: ToolbarItemPlacement.BarSlot) -> [AnyView] {
            items.filter { $0.placement.barSlot == slot }.map(\.view)
        }
        return modifier(NavigationBarItemsModifier(
            leading: HStack(spacing: 16) { ForEach(views(.leading).indices, id: \.self) { views(.leading)[$0] } },
            trailing: HStack(spacing: 16) { ForEach(views(.trailing).indices, id: \.self) { views(.trailing)[$0] } },
            principal: views(.principal).first
        ))
    }
}

@available(OpenSwiftUI_v4_0, *)
extension View {
    /// Specifies the visibility of a bar managed by OpenSwiftUI: the
    /// navigation stack's bar, or the tab view's.
    nonisolated public func toolbar(_ visibility: Visibility, for bars: ToolbarPlacement...) -> some View {
        let hidden = visibility == .hidden
        let navigation = bars.contains { $0.bar == .navigationBar || $0.bar == .automatic }
        let tabs = bars.contains { $0.bar == .tabBar }
        return self
            .transformPreference(StackBarHiddenKey.self) { if navigation { $0 = $0 ?? hidden } }
            .transformPreference(TabBarHiddenKey.self) { if tabs { $0 = $0 ?? hidden } }
    }
}

/// Whether the shown page hides the navigation bar.
struct StackBarHiddenKey: PreferenceKey {
    static let defaultValue: Bool? = nil
    static func reduce(value: inout Bool?, nextValue: () -> Bool?) {
        value = value ?? nextValue()
    }
}

/// Whether the shown tab hides the tab bar.
struct TabBarHiddenKey: PreferenceKey {
    static let defaultValue: Bool? = nil
    static func reduce(value: inout Bool?, nextValue: () -> Bool?) {
        value = value ?? nextValue()
    }
}

/// Whether the shown page hides the bar's back button.
struct StackBackButtonHiddenKey: PreferenceKey {
    static let defaultValue: Bool? = nil
    static func reduce(value: inout Bool?, nextValue: () -> Bool?) {
        value = value ?? nextValue()
    }
}

// MARK: - NavigationBarItem

/// A configuration for a navigation bar that represents a view at the top
/// of a navigation stack.
@available(OpenSwiftUI_v1_0, *)
public struct NavigationBarItem: Sendable {
    /// A style for displaying the title of a navigation bar.
    public enum TitleDisplayMode: Sendable {
        case automatic
        case inline
        case large
    }
}

@available(OpenSwiftUI_v1_0, *)
extension View {
    /// Hides the navigation bar for this view.
    nonisolated public func navigationBarHidden(_ hidden: Bool) -> some View {
        transformPreference(StackBarHiddenKey.self) { $0 = $0 ?? hidden }
    }

    /// Hides the navigation bar back button for the view.
    nonisolated public func navigationBarBackButtonHidden(_ hidesBackButton: Bool = true) -> some View {
        transformPreference(StackBackButtonHiddenKey.self) { $0 = $0 ?? hidesBackButton }
    }

    /// Configures the title display mode for this view. Titles are always
    /// shown inline in the bar here.
    nonisolated public func navigationBarTitleDisplayMode(_ displayMode: NavigationBarItem.TitleDisplayMode) -> some View {
        self
    }
}
// MARK: - Conditional toolbar content

@available(OpenSwiftUI_v2_0, *)
extension ToolbarContentBuilder {
    public static func buildEither<TrueContent, FalseContent>(first: TrueContent) -> _ConditionalContent<TrueContent, FalseContent>
    where TrueContent: ToolbarContent, FalseContent: ToolbarContent {
        _ConditionalContent(__storage: .trueContent(first))
    }

    public static func buildEither<TrueContent, FalseContent>(second: FalseContent) -> _ConditionalContent<TrueContent, FalseContent>
    where TrueContent: ToolbarContent, FalseContent: ToolbarContent {
        _ConditionalContent(__storage: .falseContent(second))
    }
}

/// The branch an `if` in a toolbar builder chose.
@available(OpenSwiftUI_v2_0, *)
extension _ConditionalContent: ToolbarContent where TrueContent: ToolbarContent, FalseContent: ToolbarContent {}

extension _ConditionalContent: ResolvedToolbarContent where TrueContent: ToolbarContent, FalseContent: ToolbarContent {
    var resolvedItems: [ResolvedToolbarItem] {
        MainActor.assumeIsolated {
            switch storage {
            case let .trueContent(content): content.resolvedItems
            case let .falseContent(content): content.resolvedItems
            }
        }
    }
}

// MARK: - Limited availability

/// Toolbar content an `if #available` in a builder erases, its type
/// unknown to older systems.
@available(OpenSwiftUI_v5_0, *)
@usableFromInline
@frozen
nonisolated struct LimitedAvailabilityToolbarContent: ToolbarContent, ResolvedToolbarContent {
    @usableFromInline
    typealias Body = Never
    let storage: LimitedAvailabilityToolbarContentStorageBase

    @usableFromInline
    nonisolated init(erasing content: some ToolbarContent) {
        storage = LimitedAvailabilityToolbarContentStorage(content)
    }

    var resolvedItems: [ResolvedToolbarItem] { storage.resolvedItems }
}

@available(OpenSwiftUI_v5_0, *)
@usableFromInline
class LimitedAvailabilityToolbarContentStorageBase {
    var resolvedItems: [ResolvedToolbarItem] { [] }
}

@available(OpenSwiftUI_v5_0, *)
final class LimitedAvailabilityToolbarContentStorage<Content: ToolbarContent>: LimitedAvailabilityToolbarContentStorageBase {
    let content: Content
    init(_ content: Content) { self.content = content }
    override var resolvedItems: [ResolvedToolbarItem] { MainActor.assumeIsolated { content.resolvedItems } }
}

// MARK: - Newer toolbar modifiers

/// How a toolbar item lays out along the bar.
@available(OpenSwiftUI_v6_0, *)
public struct ToolbarItemAxisBehavior: Hashable, Sendable {
    let rawValue: Int
    public static var automatic: ToolbarItemAxisBehavior { ToolbarItemAxisBehavior(rawValue: 0) }
    public static var horizontalOnly: ToolbarItemAxisBehavior { ToolbarItemAxisBehavior(rawValue: 1) }
    public static var verticalPreferred: ToolbarItemAxisBehavior { ToolbarItemAxisBehavior(rawValue: 2) }
}

@available(OpenSwiftUI_v6_0, *)
extension ToolbarContent {
    /// Sets how the content lays out along the bar; Perry's bars are
    /// horizontal.
    nonisolated public func axisBehavior(_ behavior: ToolbarItemAxisBehavior) -> some ToolbarContent {
        self
    }

    /// Sets whether the items share a background; Perry draws none.
    nonisolated public func sharedBackgroundVisibility(_ visibility: Visibility) -> some ToolbarContent {
        self
    }
}

@available(OpenSwiftUI_v6_0, *)
extension EnvironmentValues {
    /// The edge of a vertical toolbar the view is in; Perry's toolbars are
    /// horizontal.
    public var toolbarVerticalEdge: HorizontalEdge? { nil }
}

#endif
