//
//  TabContent.swift
//  OpenSwiftUI
//
//  Status: Perry's implementation
//
//  Tabs declared as `Tab` values: each is its content with its label as
//  the tab item and its value as the tag, which is how TabView reads the
//  children it is given.

#if os(iOS) || os(visionOS)
public import OpenSwiftUICore

// MARK: - TabContent

/// A type that provides content for programmatically selectable tabs in a
/// tab view.
@available(OpenSwiftUI_v6_0, *)
@preconcurrency
@MainActor
public protocol TabContent<TabValue> {
    /// The type used to drive selection for the tab.
    associatedtype TabValue: Hashable where TabValue == Body.TabValue

    associatedtype _IdentifiedView: View = _TabContentBodyAdaptor<Self>

    var _identifiedView: _IdentifiedView { get }

    /// The type of content representing the body of this tab content.
    associatedtype Body: TabContent

    /// The content and behavior of this tab content.
    @TabContentBuilder<TabValue> var body: Body { get }
}

@available(OpenSwiftUI_v6_0, *)
extension TabContent where _IdentifiedView == _TabContentBodyAdaptor<Self> {
    public var _identifiedView: _TabContentBodyAdaptor<Self> {
        _TabContentBodyAdaptor(content: self)
    }
}

/// The views of a tab content made of other tab content: its body's.
@available(OpenSwiftUI_v6_0, *)
public struct _TabContentBodyAdaptor<C>: View where C: TabContent {
    var content: C

    nonisolated public var body: C.Body._IdentifiedView {
        MainActor.assumeIsolated { content.body._identifiedView }
    }
}

@available(*, unavailable)
extension _TabContentBodyAdaptor: Sendable {}

// MARK: - Tab

/// The content for a tab and the tab's associated tab item in a tab view.
@available(OpenSwiftUI_v6_0, *)
public struct Tab<Value, Content, Label> {
    var value: Value
    var content: Content
    var label: Label
}

@available(*, unavailable)
extension Tab: Sendable {}

@available(OpenSwiftUI_v6_0, *)
extension Tab: TabContent where Value: Hashable, Content: View, Label: View {
    public typealias TabValue = Value

    /// Creates a tab that the tab view presents when the tab view's
    /// selection matches the tab's value, with no label.
    nonisolated public init(value: Value, @ViewBuilder content: () -> Content) where Label == EmptyView {
        self.value = value
        self.content = content()
        self.label = EmptyView()
    }

    /// Creates a tab that the tab view presents when the tab view's
    /// selection matches the tab's value.
    nonisolated public init(value: Value, @ViewBuilder content: () -> Content, @ViewBuilder label: () -> Label) {
        self.value = value
        self.content = content()
        self.label = label()
    }

    public var _identifiedView: some View {
        content.tabItem { label }.tag(value)
    }

    public var body: Tab<Value, Content, Label> { return self }
}

// MARK: - _TupleTabContent

/// Tabs given together: their views, as a tuple.
@available(OpenSwiftUI_v6_0, *)
@usableFromInline
@frozen
@preconcurrency
@MainActor
internal struct _TupleTabContent<T, U>: TabContent where T: Hashable {
    @usableFromInline
    internal typealias TabValue = T

    @usableFromInline
    internal let _identifiedView: TupleView<U>

    @inlinable
    internal init(_ content: U) { _identifiedView = .init(content) }

    @usableFromInline
    internal var body: _TupleTabContent<T, U> { return self }
}

// MARK: - TabContentBuilder

/// A result builder that constructs tabs for a tab view that supports
/// programmatic selection.
@available(OpenSwiftUI_v6_0, *)
@resultBuilder
public struct TabContentBuilder<TabValue> where TabValue: Hashable {
    /// A view representation of the content of a builder-based tab view
    /// with selection.
    public struct Content<C>: View where C: TabContent {
        var content: C

        nonisolated public var body: some View {
            MainActor.assumeIsolated { content._identifiedView }
        }
    }

    @_alwaysEmitIntoClient
    @MainActor
    public static func buildExpression(_ content: some TabContent<TabValue>) -> some TabContent<TabValue> {
        content
    }

    @_alwaysEmitIntoClient
    @MainActor
    public static func buildBlock(_ content: some TabContent<TabValue>) -> some TabContent<TabValue> {
        content
    }

    @_alwaysEmitIntoClient
    @MainActor
    public static func buildBlock<C0, C1>(_ c0: C0, _ c1: C1) -> some TabContent<TabValue>
    where TabValue == C0.TabValue, C0: TabContent, C1: TabContent, C0.TabValue == C1.TabValue {
        _TupleTabContent<TabValue, (C0._IdentifiedView, C1._IdentifiedView)>((c0._identifiedView, c1._identifiedView))
    }

    @_alwaysEmitIntoClient
    @MainActor
    public static func buildBlock<C0, C1, C2>(_ c0: C0, _ c1: C1, _ c2: C2) -> some TabContent<TabValue>
    where TabValue == C0.TabValue, C0: TabContent, C1: TabContent, C2: TabContent,
          C0.TabValue == C1.TabValue, C1.TabValue == C2.TabValue {
        _TupleTabContent<TabValue, (C0._IdentifiedView, C1._IdentifiedView, C2._IdentifiedView)>(
            (c0._identifiedView, c1._identifiedView, c2._identifiedView))
    }
}

@available(*, unavailable)
extension TabContentBuilder: Sendable {}

@available(*, unavailable)
extension TabContentBuilder.Content: Sendable {}

// MARK: - TabView

@available(OpenSwiftUI_v6_0, *)
extension TabView {
    /// Creates a tab view that uses a builder to create and specify
    /// selection values for its tabs.
    nonisolated public init<C>(
        selection: Binding<SelectionValue>,
        @TabContentBuilder<SelectionValue> content: () -> C
    ) where Content == TabContentBuilder<SelectionValue>.Content<C>, C: TabContent {
        self.init(selection: Optional(selection)) { TabContentBuilder<SelectionValue>.Content(content: content()) }
    }
}
#endif
