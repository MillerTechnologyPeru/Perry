//
//  TabViewStyles.swift
//  OpenSwiftUI
//
//  Status: Perry's implementation
//
//  Tab view and index view styles. The page style makes a tab view show
//  its tabs as pages, swiped between, with a dot for each along the bottom
//  unless the style hides them. Styles' view-making requirements are there
//  for the ABI; tab views never call them.

#if os(iOS) || os(visionOS)
public import OpenSwiftUICore

// MARK: - TabViewStyle

/// A specification for the appearance and interaction of a tab view.
@available(OpenSwiftUI_v2_0, *)
@preconcurrency
@MainActor
public protocol TabViewStyle {
    nonisolated static func _makeView<SelectionValue>(value: _GraphValue<_TabViewValue<Self, SelectionValue>>, inputs: _ViewInputs) -> _ViewOutputs where SelectionValue: Hashable
    nonisolated static func _makeViewList<SelectionValue>(value: _GraphValue<_TabViewValue<Self, SelectionValue>>, inputs: _ViewListInputs) -> _ViewListOutputs where SelectionValue: Hashable
}

@available(OpenSwiftUI_v2_0, *)
public struct _TabViewValue<Style, SelectionValue> where Style: TabViewStyle, SelectionValue: Hashable {}

/// How a paged tab view shows its pages.
struct TabViewPaging {
    var showsIndex: Bool
}

struct TabViewPagingKey: EnvironmentKey {
    static let defaultValue: TabViewPaging? = nil
}

extension EnvironmentValues {
    var tabViewPaging: TabViewPaging? {
        get { self[TabViewPagingKey.self] }
        set { self[TabViewPagingKey.self] = newValue }
    }
}

/// Styles that page their tabs.
protocol TabViewPagingProviding {
    var paging: TabViewPaging { get }
}

@available(OpenSwiftUI_v2_0, *)
extension View {
    /// Sets the style for the tab view within the current environment.
    nonisolated public func tabViewStyle<S>(_ style: S) -> some View where S: TabViewStyle {
        environment(\.tabViewPaging, (style as? TabViewPagingProviding)?.paging)
    }
}

private func unusedTabViewMakeView() -> Never {
    preconditionFailure("Tab view styles' views are made by the tab view")
}

/// The default tab view style.
@available(OpenSwiftUI_v2_0, *)
public struct DefaultTabViewStyle: TabViewStyle {
    nonisolated public init() {}
    nonisolated public static func _makeView<SelectionValue>(value: _GraphValue<_TabViewValue<DefaultTabViewStyle, SelectionValue>>, inputs: _ViewInputs) -> _ViewOutputs where SelectionValue: Hashable { unusedTabViewMakeView() }
    nonisolated public static func _makeViewList<SelectionValue>(value: _GraphValue<_TabViewValue<DefaultTabViewStyle, SelectionValue>>, inputs: _ViewListInputs) -> _ViewListOutputs where SelectionValue: Hashable { unusedTabViewMakeView() }
}

/// A tab view style that implements a paged scrolling tab view.
@available(OpenSwiftUI_v2_0, *)
public struct PageTabViewStyle: TabViewStyle, TabViewPagingProviding {
    /// A style for displaying the page index view.
    public struct IndexDisplayMode: Sendable {
        var shows: Bool

        public static let automatic = IndexDisplayMode(shows: true)
        public static let always = IndexDisplayMode(shows: true)
        public static let never = IndexDisplayMode(shows: false)
    }

    var indexDisplayMode: IndexDisplayMode

    nonisolated public init(indexDisplayMode: PageTabViewStyle.IndexDisplayMode = .automatic) {
        self.indexDisplayMode = indexDisplayMode
    }

    var paging: TabViewPaging { TabViewPaging(showsIndex: indexDisplayMode.shows) }

    nonisolated public static func _makeView<SelectionValue>(value: _GraphValue<_TabViewValue<PageTabViewStyle, SelectionValue>>, inputs: _ViewInputs) -> _ViewOutputs where SelectionValue: Hashable { unusedTabViewMakeView() }
    nonisolated public static func _makeViewList<SelectionValue>(value: _GraphValue<_TabViewValue<PageTabViewStyle, SelectionValue>>, inputs: _ViewListInputs) -> _ViewListOutputs where SelectionValue: Hashable { unusedTabViewMakeView() }
}

// MARK: - IndexViewStyle

/// The configuration an index view style makes its body from.
@available(OpenSwiftUI_v2_0, *)
public struct _IndexViewStyleConfiguration {}

/// Defines the implementation of all `IndexView` instances within a view
/// hierarchy.
@available(OpenSwiftUI_v2_0, *)
public protocol IndexViewStyle {
    associatedtype _Body: View

    @ViewBuilder
    func _makeBody(configuration: _Configuration) -> _Body

    typealias _Configuration = _IndexViewStyleConfiguration
}

/// An index view style that places a page index view over its content.
@available(OpenSwiftUI_v2_0, *)
public struct PageIndexViewStyle: IndexViewStyle {
    /// The background style for the page index view.
    public struct BackgroundDisplayMode: Sendable {
        public static let automatic = BackgroundDisplayMode()
        public static let interactive = BackgroundDisplayMode()
        public static let always = BackgroundDisplayMode()
        public static let never = BackgroundDisplayMode()
    }

    public init(backgroundDisplayMode: PageIndexViewStyle.BackgroundDisplayMode = .automatic) {}

    public func _makeBody(configuration: PageIndexViewStyle._Configuration) -> some View {
        EmptyView()
    }
}

@available(OpenSwiftUI_v2_0, *)
extension View {
    /// Sets the style for the index view within the current environment;
    /// paged tab views' dots look the same whatever the style.
    nonisolated public func indexViewStyle<S>(_ style: S) -> some View where S: IndexViewStyle {
        self
    }
}

// MARK: - Paged tab views

/// Shows the selected tab, a swipe away from the next and previous ones,
/// with a dot for each.
struct PagedTabViewRoot<SelectionValue: Hashable>: _VariadicView.UnaryViewRoot {
    var selection: Binding<AnyHashable?>
    var showsIndex: Bool

    func value(of child: _VariadicView.Children.Element, at index: Int) -> AnyHashable {
        if let tag = child.traits.tag(for: SelectionValue.self) {
            return AnyHashable(tag)
        }
        return AnyHashable(index)
    }

    func body(children: _VariadicView.Children) -> some View {
        let values = children.indices.map { value(of: children[$0], at: $0) }
        let index = selection.wrappedValue.flatMap { values.firstIndex(of: $0) } ?? 0
        ZStack(alignment: .bottom) {
            ZStack {
                ForEach(children.indices, id: \.self) { i in
                    if i == index {
                        children[i]
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 20).onEnded { drag in
                let next = drag.translation.width < -40 ? index + 1 : drag.translation.width > 40 ? index - 1 : index
                if values.indices.contains(next) {
                    selection.wrappedValue = values[next]
                }
            })
            if showsIndex, children.count > 1 {
                HStack(spacing: 8) {
                    ForEach(children.indices, id: \.self) { i in
                        Circle()
                            .fill(i == index ? Color.primary : Color.secondary.opacity(0.4))
                            .frame(width: 7, height: 7)
                    }
                }
                .padding(.bottom, 12)
            }
        }
    }
}
#endif
