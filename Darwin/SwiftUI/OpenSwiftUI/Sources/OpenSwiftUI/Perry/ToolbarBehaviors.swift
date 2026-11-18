//
//  ToolbarBehaviors.swift
//  OpenSwiftUI
//
//  Status: Perry's implementation, mostly inert
//
//  More toolbar content and the options that tune bars: customizable
//  content, the system's default items, spacers, overflow menus, further
//  placements, and how bars minimize, hide or lay out, for toolbars, search
//  fields and tab bars. Perry's bars are a navigation bar with leading,
//  centered and trailing items and a tab bar; they don't minimize, can't be
//  customized and have no subtitle, so most of what is here is taken and
//  ignored. What does have an effect: an overflow menu shows as a menu in
//  the bar, pinned trailing and title placements put items trailing and in
//  the middle, and `toolbarVisibility` hides bars as `toolbar(_:for:)` does.

#if os(iOS) || os(visionOS)
public import OpenSwiftUICore

// MARK: - CustomizableToolbarContent

/// Toolbar content the user may rearrange, add or remove where the system
/// offers toolbar customization. Nothing here does: such content is shown
/// as any other toolbar content is.
@available(OpenSwiftUI_v1_0, *)
public protocol CustomizableToolbarContent: ToolbarContent where Self.Body: CustomizableToolbarContent {
}

@available(OpenSwiftUI_v1_0, *)
extension Never: CustomizableToolbarContent {}

@available(OpenSwiftUI_v1_0, *)
extension ToolbarItem: CustomizableToolbarContent where ID == String {
    /// Creates an item the user can customize, known by a string. The
    /// identifier isn't kept. An item that isn't shown by default stays
    /// out of the bar, as there is no way here for the user to add it.
    nonisolated public init(
        id: String,
        placement: ToolbarItemPlacement = .automatic,
        showsByDefault: Bool,
        @ViewBuilder content: () -> Content
    ) {
        self.placement = showsByDefault ? placement : ToolbarItemPlacement(role: .hidden)
        self.content = content()
    }
}

// MARK: - Content that shows nothing

/// Toolbar content with no items, the body of content Perry's bars have no
/// place for.
nonisolated struct InertToolbarContent: ToolbarContent, ResolvedToolbarContent {
    typealias Body = Never

    nonisolated init() {}

    var resolvedItems: [ResolvedToolbarItem] { [] }
}

// MARK: - Default items

/// A kind of item the system puts in a toolbar by itself.
@available(OpenSwiftUI_v1_0, *)
public struct ToolbarDefaultItemKind {
    enum Kind { case title, search }

    var kind: Kind

    /// The title of the navigation bar.
    public static let title = ToolbarDefaultItemKind(kind: .title)

    /// The search field or button a searchable view adds.
    public static let search = ToolbarDefaultItemKind(kind: .search)
}

@available(*, unavailable)
extension ToolbarDefaultItemKind: Sendable {}

/// Stands for one of the system's own toolbar items, to give it another
/// placement. Perry's bars place the title and the search field
/// themselves, so this adds no item and moves none.
@available(OpenSwiftUI_v1_0, *)
nonisolated public struct DefaultToolbarItem: ToolbarContent, ResolvedToolbarContent {
    var kind: ToolbarDefaultItemKind
    var placement: ToolbarItemPlacement

    /// Creates the stand-in for the system item of the given kind.
    nonisolated public init(kind: ToolbarDefaultItemKind, placement: ToolbarItemPlacement = .automatic) {
        self.kind = kind
        self.placement = placement
    }

    nonisolated public var body: some ToolbarContent {
        InertToolbarContent()
    }

    var resolvedItems: [ResolvedToolbarItem] { [] }
}

@available(*, unavailable)
extension DefaultToolbarItem: Sendable {}

// MARK: - Spacers

/// How much room a spacer takes: as much as there is, or a set amount.
@available(OpenSwiftUI_v1_0, *)
public struct SpacerSizing: Sendable {
    var isFixed: Bool

    /// The spacer grows to fill the room between its neighbours.
    public static let flexible = SpacerSizing(isFixed: false)

    /// The spacer keeps a standard width.
    public static let fixed = SpacerSizing(isFixed: true)
}

/// Space between the items of a toolbar. Perry's bars lay their items out
/// in three groups with a set spacing, so a spacer adds nothing to them.
@available(OpenSwiftUI_v1_0, *)
nonisolated public struct ToolbarSpacer: ToolbarContent, CustomizableToolbarContent, ResolvedToolbarContent {
    public typealias Body = Never

    var sizing: SpacerSizing
    var placement: ToolbarItemPlacement

    /// Creates a spacer of the given sizing in a part of the toolbar.
    nonisolated public init(_ sizing: SpacerSizing = .flexible, placement: ToolbarItemPlacement = .automatic) {
        self.sizing = sizing
        self.placement = placement
    }

    nonisolated public static func _makeToolbar(content: _GraphValue<ToolbarSpacer>, inputs: _ToolbarInputs) -> _ToolbarOutputs {
        _ToolbarOutputs()
    }

    var resolvedItems: [ResolvedToolbarItem] { [] }
}

@available(*, unavailable)
extension ToolbarSpacer: Sendable {}

// MARK: - Overflow menu

/// Actions kept in the toolbar's "more" menu. Here they are the items of a
/// menu at the trailing end of the navigation bar, under a label of three
/// dots.
@available(OpenSwiftUI_v1_0, *)
nonisolated public struct ToolbarOverflowMenu<Content>: ToolbarContent, CustomizableToolbarContent, ResolvedToolbarContent where Content: View {
    public typealias Body = Never

    var content: Content

    /// Creates an overflow menu holding the given actions.
    nonisolated public init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    nonisolated public static func _makeToolbar(content: _GraphValue<ToolbarOverflowMenu<Content>>, inputs: _ToolbarInputs) -> _ToolbarOutputs {
        _ToolbarOutputs()
    }

    var resolvedItems: [ResolvedToolbarItem] {
        MainActor.assumeIsolated {
            let menu = Menu {
                content
            } label: {
                Text(verbatim: "\u{2022}\u{2022}\u{2022}")
            }
            return [ResolvedToolbarItem(placement: .primaryAction, view: AnyView(menu))]
        }
    }
}

@available(*, unavailable)
extension ToolbarOverflowMenu: Sendable {}

// MARK: - Visibility priority and margins

/// How readily an item stays in the bar when room runs out. Perry's bars
/// never move items to an overflow menu, so the priority changes nothing.
@available(OpenSwiftUI_v1_0, *)
public struct ToolbarItemVisibilityPriority: Hashable, Sendable {
    var level: Int

    /// The system decides when the item leaves the bar.
    public static let automatic = ToolbarItemVisibilityPriority(level: 0)

    /// The item is among the last to leave the bar.
    public static let high = ToolbarItemVisibilityPriority(level: 1)
}

@available(OpenSwiftUI_v1_0, *)
extension ToolbarContent {
    /// Sets how readily the content stays visible when the bar is short of
    /// room; all of Perry's items stay.
    @MainActor
    @preconcurrency
    public func visibilityPriority(_ priority: ToolbarItemVisibilityPriority) -> some ToolbarContent {
        self
    }

    /// Removes the margins the bar keeps around the content; Perry's bars
    /// keep their spacing.
    nonisolated public func contentMarginsRemoved(_ removed: Bool = true) -> some ToolbarContent {
        self
    }
}

// MARK: - Placements

@available(OpenSwiftUI_v1_0, *)
extension ToolbarItemPlacement {
    /// The trailing edge of the top bar, for items that stay there rather
    /// than moving to an overflow menu: the bar's trailing items here.
    public static let topBarPinnedTrailing = ToolbarItemPlacement(role: .navigationBarTrailing)

    /// The place of the bar's title, which `title` resolves to: the middle
    /// of the bar here, as `principal`.
    @usableFromInline
    static let _title = ToolbarItemPlacement(role: .principal)

    /// The place of the bar's subtitle. Perry's bar has none, and items
    /// placed there are not shown.
    public static let subtitle = ToolbarItemPlacement(role: .subtitle)
}

// MARK: - How bars minimize and lay out

/// When a bar shrinks out of the way as content scrolls. Perry's bars keep
/// their size.
@available(OpenSwiftUI_v1_0, *)
public struct ToolbarMinimizationBehavior: Hashable, Sendable {
    var rawValue: Int

    /// The system's choice for the bar.
    public static var automatic: ToolbarMinimizationBehavior {
        ToolbarMinimizationBehavior(rawValue: 0)
    }

    /// The bar never minimizes.
    public static let never = ToolbarMinimizationBehavior(rawValue: 3)
}

/// Whether a toolbar may stand along a vertical edge. Perry's toolbars are
/// horizontal.
@available(OpenSwiftUI_v1_0, *)
public struct ToolbarVerticalBehavior: Hashable, Sendable {
    var rawValue: Int

    /// The system's choice for the toolbar.
    public static let automatic = ToolbarVerticalBehavior(rawValue: 0)

    /// The toolbar stays horizontal.
    public static let disabled = ToolbarVerticalBehavior(rawValue: 1)
}

@available(OpenSwiftUI_v1_0, *)
extension View {
    /// Takes one of the system's own items out of the toolbar. Perry's bars
    /// keep showing their title and search field.
    nonisolated public func toolbar(removing defaultItemKind: ToolbarDefaultItemKind?) -> some View {
        self
    }

    /// Shows or hides the bars' backgrounds; Perry's bars always draw
    /// theirs.
    nonisolated public func toolbarBackgroundVisibility(_ visibility: Visibility, for bars: ToolbarPlacement...) -> some View {
        self
    }

    /// Sets when the given bars minimize; Perry's bars don't.
    nonisolated public func toolbarMinimizationBehavior(_ behavior: ToolbarMinimizationBehavior, for bars: ToolbarPlacement...) -> some View {
        self
    }

    /// Gives the navigation title a menu of the given actions. Perry's
    /// title can't be tapped, and the menu isn't shown.
    nonisolated public func toolbarTitleMenu<C>(@ViewBuilder content: () -> C) -> some View where C: View {
        self
    }

    /// Sets whether the toolbar may stand along a vertical edge; Perry's
    /// toolbars are horizontal.
    nonisolated public func toolbarVerticalBehavior(_ behavior: ToolbarVerticalBehavior) -> some View {
        self
    }

    /// Shows or hides bars: the navigation stack's bar, or the tab view's,
    /// as `toolbar(_:for:)` does.
    nonisolated public func toolbarVisibility(_ visibility: Visibility, for bars: ToolbarPlacement...) -> some View {
        let hidden = visibility == .hidden
        let navigation = bars.contains { $0.bar == .navigationBar || $0.bar == .automatic }
        let tabs = bars.contains { $0.bar == .tabBar }
        return self
            .transformPreference(StackBarHiddenKey.self) { if navigation { $0 = $0 ?? hidden } }
            .transformPreference(TabBarHiddenKey.self) { if tabs { $0 = $0 ?? hidden } }
    }
}

// MARK: - Search

/// What the toolbar does while a search is presented.
@available(OpenSwiftUI_v1_0, *)
public struct SearchPresentationToolbarBehavior {
    var avoidsHidingContent: Bool

    /// The system's choice.
    public static var automatic: SearchPresentationToolbarBehavior {
        SearchPresentationToolbarBehavior(avoidsHidingContent: false)
    }

    /// The bar keeps its title and items while searching.
    public static var avoidHidingContent: SearchPresentationToolbarBehavior {
        SearchPresentationToolbarBehavior(avoidsHidingContent: true)
    }
}

@available(*, unavailable)
extension SearchPresentationToolbarBehavior: Sendable {}

/// How a search field in a toolbar shows itself.
@available(OpenSwiftUI_v1_0, *)
public struct SearchToolbarBehavior: Hashable, Sendable {
    var rawValue: Int

    /// The search field may shrink to a button.
    public static var minimize: SearchToolbarBehavior {
        SearchToolbarBehavior(rawValue: 1)
    }
}

@available(OpenSwiftUI_v1_0, *)
extension View {
    /// Sets what the toolbar does while a search is presented. Perry's
    /// search field sits above the content and leaves the bar as it is.
    nonisolated public func searchPresentationToolbarBehavior(_ behavior: SearchPresentationToolbarBehavior) -> some View {
        self
    }

    /// Sets how the search field shows itself in the toolbar; Perry's is
    /// always a whole field.
    nonisolated public func searchToolbarBehavior(_ behavior: SearchToolbarBehavior) -> some View {
        self
    }
}

// MARK: - Tab bar

/// When a tab bar shrinks out of the way as content scrolls. Perry's tab
/// bar keeps its size.
@available(OpenSwiftUI_v1_0, *)
public struct TabBarMinimizeBehavior: Hashable, Sendable {
    var rawValue: Int

    /// The system's choice for the tab bar.
    public static let automatic = TabBarMinimizeBehavior(rawValue: 0)
}

@available(OpenSwiftUI_v1_0, *)
extension View {
    /// Sets when the tab bar minimizes; Perry's doesn't.
    nonisolated public func tabBarMinimizeBehavior(_ behavior: TabBarMinimizeBehavior) -> some View {
        self
    }
}

#endif
