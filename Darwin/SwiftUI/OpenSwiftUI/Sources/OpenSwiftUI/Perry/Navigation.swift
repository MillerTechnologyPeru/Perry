//
//  Navigation.swift
//  OpenSwiftUI
//
//  Status: Perry's implementation
//
//  NavigationStack keeps its pages in SwiftUI state and shows the top one
//  under a UINavigationBar. The pages are one view graph with the stack;
//  only the bar is UIKit's. Pages are values of the stack's path, shown by
//  the destinations `navigationDestination` registers for their types, and
//  then views pushed by links and presented destinations. Titles, whether
//  the bar and its back button show, and destinations come up from the
//  shown page through preferences; bar items are drawn where they are
//  declared, over the bar.

#if os(iOS) || os(visionOS)
public import OpenSwiftUICore
public import UIKit

// MARK: - NavigationPath

/// A type-erased list of data representing the content of a navigation
/// stack.
@available(OpenSwiftUI_v4_0, *)
public struct NavigationPath {
    var elements: [AnyHashable]

    public var count: Int { elements.count }
    public var isEmpty: Bool { elements.isEmpty }

    public init() { elements = [] }

    public init<S>(_ elements: S) where S: Sequence, S.Element: Hashable {
        self.elements = elements.map { AnyHashable($0) }
    }

    public mutating func append<V>(_ value: V) where V: Hashable {
        elements.append(AnyHashable(value))
    }

    public mutating func removeLast(_ k: Int = 1) {
        elements.removeLast(k)
    }
}

@available(OpenSwiftUI_v4_0, *)
extension NavigationPath: Equatable {
    public static func == (lhs: NavigationPath, rhs: NavigationPath) -> Bool { lhs.elements == rhs.elements }
}

// MARK: - Environment

/// What views in a navigation stack can do to it.
struct NavigationActions {
    /// Pushes a view, returning its page's identity; the action runs when
    /// the page is popped from the bar.
    var push: (AnyView, (() -> Void)?) -> Int
    /// Appends a value to the stack's path.
    var pushValue: (AnyHashable) -> Void
    /// Pops the page with this identity, and those above it.
    var pop: (Int) -> Void
}

struct NavigationActionsKey: EnvironmentKey {
    static let defaultValue: NavigationActions? = nil
}

/// The height of the enclosing navigation stack's bar, which bar items are
/// drawn up into; 0 while the bar is hidden.
struct NavigationBarHeightKey: EnvironmentKey {
    static let defaultValue: CGFloat = 0
}

extension EnvironmentValues {
    var navigationActions: NavigationActions? {
        get { self[NavigationActionsKey.self] }
        set { self[NavigationActionsKey.self] = newValue }
    }

    var navigationBarHeight: CGFloat {
        get { self[NavigationBarHeightKey.self] }
        set { self[NavigationBarHeightKey.self] = newValue }
    }
}

// MARK: - Destinations

/// The views that show path values, by the values' type.
struct NavigationDestinations: Equatable {
    var views: [ObjectIdentifier: (AnyHashable) -> AnyView] = [:]

    func view(for value: AnyHashable) -> AnyView {
        views[ObjectIdentifier(type(of: value.base))].map { $0(value) } ?? AnyView(EmptyView())
    }

    mutating func merge(_ other: NavigationDestinations) {
        views.merge(other.views) { _, new in new }
    }

    static func == (lhs: NavigationDestinations, rhs: NavigationDestinations) -> Bool {
        Set(lhs.views.keys) == Set(rhs.views.keys)
    }
}

struct NavigationDestinationsKey: PreferenceKey {
    static let defaultValue = NavigationDestinations()
    static func reduce(value: inout NavigationDestinations, nextValue: () -> NavigationDestinations) {
        value.merge(nextValue())
    }
}

// MARK: - NavigationStack

/// A view that displays a root view and enables you to present additional
/// views over the root view.
@available(OpenSwiftUI_v4_0, *)
public struct NavigationStack<Data, Root>: View where Root: View {
    /// The path given, read and written as values.
    struct Path {
        var get: () -> [AnyHashable]
        var set: ([AnyHashable]) -> Void
    }

    /// A view pushed after the path's pages.
    struct ViewPage {
        var id: Int
        var view: AnyView
        var onPop: (() -> Void)?
    }

    var root: Root
    var path: Path?
    @State private var localValues: [AnyHashable] = []
    @State private var viewPages: [ViewPage] = []
    @State private var nextPageID = 0
    @State private var destinations = NavigationDestinations()
    @State private var titles: [Int: Text] = [:]
    @State private var barHidden: [Int: Bool] = [:]
    @State private var backHidden: [Int: Bool] = [:]

    static var barHeight: CGFloat { 44 }

    public init(@ViewBuilder root: () -> Root) where Data == NavigationPath {
        self.root = root()
    }

    public init(path: Binding<NavigationPath>, @ViewBuilder root: () -> Root) where Data == NavigationPath {
        self.root = root()
        self.path = Path(get: { path.wrappedValue.elements }, set: { path.wrappedValue.elements = $0 })
    }

    public init(path: Binding<Data>, @ViewBuilder root: () -> Root)
    where Data: MutableCollection, Data: RandomAccessCollection, Data: RangeReplaceableCollection, Data.Element: Hashable {
        self.root = root()
        self.path = Path(
            get: { path.wrappedValue.map { AnyHashable($0) } },
            set: { path.wrappedValue = Data($0.compactMap { $0.base as? Data.Element }) }
        )
    }

    private var values: [AnyHashable] { path?.get() ?? localValues }

    private func setValues(_ values: [AnyHashable]) {
        if let path { path.set(values) } else { localValues = values }
    }

    /// Pops the top page, as the bar's back button does.
    private func popTop() {
        if let page = viewPages.popLast() {
            page.onPop?()
        } else if !values.isEmpty {
            setValues(Array(values.dropLast()))
        }
        forget(above: values.count + viewPages.count)
    }

    /// Forgets what pages above this depth said about the bar.
    private func forget(above depth: Int) {
        titles = titles.filter { $0.key <= depth }
        barHidden = barHidden.filter { $0.key <= depth }
        backHidden = backHidden.filter { $0.key <= depth }
    }

    private var actions: NavigationActions {
        NavigationActions(
            push: { view, onPop in
                let id = nextPageID
                nextPageID += 1
                viewPages.append(ViewPage(id: id, view: view, onPop: onPop))
                return id
            },
            pushValue: { value in
                // A value pushed above views is shown as a view.
                if viewPages.isEmpty {
                    setValues(values + [value])
                } else {
                    let id = nextPageID
                    nextPageID += 1
                    viewPages.append(ViewPage(id: id, view: destinations.view(for: value), onPop: nil))
                }
            },
            pop: { id in
                guard let index = viewPages.firstIndex(where: { $0.id == id }) else { return }
                let popped = viewPages[(index + 1)...]
                viewPages.removeSubrange(index...)
                popped.reversed().forEach { $0.onPop?() }
                forget(above: values.count + viewPages.count)
            }
        )
    }

    public var body: some View {
        let pages = values.map { destinations.view(for: $0) } + viewPages.map(\.view)
        let depth = pages.count
        let isBarHidden = barHidden[depth] ?? false
        VStack(spacing: 0) {
            if !isBarHidden {
                NavigationBarRepresentable(
                    titles: (0...depth).map { titles[$0] },
                    hidesBackButton: backHidden[depth] ?? false,
                    onBack: popTop
                )
                .frame(height: Self.barHeight)
            }
            ZStack(alignment: .top) {
                if let top = pages.last {
                    top
                        .id(depth)
                        .environment(\.dismissAction, DismissAction { popTop() })
                } else {
                    root
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .onPreferenceChange(StackTitleKey.self) { title in
                titles[depth] = title
            }
            .onPreferenceChange(StackBarHiddenKey.self) { hidden in
                barHidden[depth] = hidden
            }
            .onPreferenceChange(StackBackButtonHiddenKey.self) { hidden in
                backHidden[depth] = hidden
            }
            .onPreferenceChange(NavigationDestinationsKey.self) { found in
                var merged = destinations
                merged.merge(found)
                destinations = merged
            }
        }
        .environment(\.navigationActions, actions)
        .environment(\.navigationBarHeight, isBarHidden ? 0 : Self.barHeight)
        // An edit button in the bar and the page's list share an edit mode.
        .modifier(EditModeScopeModifier(isActive: true))
    }
}

// MARK: - NavigationLink

/// A view that controls a navigation presentation.
@available(OpenSwiftUI_v1_0, *)
public struct NavigationLink<Label, Destination>: View where Label: View, Destination: View {
    var destination: Destination?
    var value: AnyHashable?
    var label: Label
    @Environment(\.navigationActions) private var actions

    public init(destination: Destination, @ViewBuilder label: () -> Label) {
        self.destination = destination
        self.label = label()
    }

    @inlinable
    public init(@ViewBuilder destination: () -> Destination, @ViewBuilder label: () -> Label) {
        self.init(destination: destination(), label: label)
    }

    public var body: some View {
        Button {
            if let value {
                actions?.pushValue(value)
            } else if let destination {
                _ = actions?.push(AnyView(destination), nil)
            }
        } label: {
            HStack {
                label
                Spacer(minLength: 0)
                Text("›").foregroundColor(Color.secondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

@available(OpenSwiftUI_v4_0, *)
extension NavigationLink where Destination == Never {
    /// Creates a navigation link that presents the view the stack's
    /// destination for the value's type shows.
    public init<P>(value: P?, @ViewBuilder label: () -> Label) where P: Hashable {
        self.label = label()
        self.value = value.map { AnyHashable($0) }
    }

    public init<P>(_ titleKey: LocalizedStringKey, value: P?) where Label == Text, P: Hashable {
        self.init(value: value) { Text(titleKey) }
    }
}

// MARK: - navigationDestination

@available(OpenSwiftUI_v4_0, *)
extension View {
    /// Associates a destination view with a presented data type for use
    /// within a navigation stack.
    nonisolated public func navigationDestination<D, C>(
        for data: D.Type,
        @ViewBuilder destination: @escaping (D) -> C
    ) -> some View where D: Hashable, C: View {
        transformPreference(NavigationDestinationsKey.self) { destinations in
            destinations.views[ObjectIdentifier(D.self)] = { value in
                (value.base as? D).map { AnyView(destination($0)) } ?? AnyView(EmptyView())
            }
        }
    }

    /// Associates a destination view with a binding that can be used to
    /// push the view onto a navigation stack.
    nonisolated public func navigationDestination<V>(
        isPresented: Binding<Bool>,
        @ViewBuilder destination: () -> V
    ) -> some View where V: View {
        modifier(PresentedDestinationModifier(isPresented: isPresented.wrappedValue, destination: AnyView(destination())) {
            isPresented.wrappedValue = false
        })
    }

    /// Associates a destination view with a bound value for use within a
    /// navigation stack.
    nonisolated public func navigationDestination<D, C>(
        item: Binding<D?>,
        @ViewBuilder destination: @escaping (D) -> C
    ) -> some View where D: Hashable, C: View {
        modifier(PresentedDestinationModifier(
            isPresented: item.wrappedValue != nil,
            destination: item.wrappedValue.map { AnyView(destination($0)) } ?? AnyView(EmptyView())
        ) {
            item.wrappedValue = nil
        })
    }
}

/// Pushes a destination while it's presented, and pops it when it no longer
/// is; popping it from the bar says it's no longer presented.
struct PresentedDestinationModifier: ViewModifier {
    var isPresented: Bool
    var destination: AnyView
    var dismiss: () -> Void
    @Environment(\.navigationActions) private var actions
    @State private var pageID: Int?

    func body(content: Content) -> some View {
        content.onChange(of: isPresented, initial: true) { _, presented in
            if presented, pageID == nil, let actions {
                pageID = actions.push(destination) {
                    pageID = nil
                    dismiss()
                }
            } else if !presented, let id = pageID {
                pageID = nil
                actions?.pop(id)
            }
        }
    }
}

// MARK: - NavigationView

/// A view for presenting a stack of views that represents a visible path
/// in a navigation hierarchy: here, a navigation stack.
@available(OpenSwiftUI_v1_0, *)
public struct NavigationView<Content>: View where Content: View {
    var content: Content

    public init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    public var body: some View {
        NavigationStack { content }
    }
}

/// The configuration a navigation view style makes its body from.
@available(OpenSwiftUI_v1_0, *)
public struct _NavigationViewStyleConfiguration {}

/// A specification for the appearance and interaction of a navigation view.
@available(OpenSwiftUI_v1_0, *)
public protocol NavigationViewStyle {
    associatedtype _Body: View

    @ViewBuilder
    func _body(configuration: _NavigationViewStyleConfiguration) -> _Body

    associatedtype _Body2: View = EmptyView

    @available(OpenSwiftUI_v3_0, *)
    @ViewBuilder
    func _columnBasedBody(configuration: _NavigationViewStyleConfiguration) -> _Body2
}

@available(OpenSwiftUI_v3_0, *)
extension NavigationViewStyle where _Body2 == EmptyView {
    public func _columnBasedBody(configuration: _NavigationViewStyleConfiguration) -> EmptyView {
        EmptyView()
    }
}

/// A navigation view style represented by a view stack that only shows a
/// single top view at a time: the only style navigation views have here.
@available(OpenSwiftUI_v1_0, *)
public struct StackNavigationViewStyle: NavigationViewStyle {
    public init() {}

    public func _body(configuration: _NavigationViewStyleConfiguration) -> some View {
        EmptyView()
    }

    @available(OpenSwiftUI_v3_0, *)
    public func _columnBasedBody(configuration: _NavigationViewStyleConfiguration) -> some View {
        EmptyView()
    }
}

@available(OpenSwiftUI_v1_0, *)
extension View {
    /// Sets the style for navigation views within this view; navigation
    /// views are stacks whatever the style.
    nonisolated public func navigationViewStyle<S>(_ style: S) -> some View where S: NavigationViewStyle {
        self
    }
}

// MARK: - Titles and bar items

/// The shown page's title.
struct StackTitleKey: PreferenceKey {
    static let defaultValue: Text? = nil
    static func reduce(value: inout Text?, nextValue: () -> Text?) {
        value = value ?? nextValue()
    }
}

@available(OpenSwiftUI_v1_0, *)
extension View {
    public func navigationTitle(_ title: Text) -> some View {
        modifier(_PreferenceWritingModifier<StackTitleKey>(value: title))
    }

    public func navigationTitle(_ titleKey: LocalizedStringKey) -> some View {
        navigationTitle(Text(titleKey))
    }

    @_disfavoredOverload
    public func navigationTitle<S>(_ title: S) -> some View where S: StringProtocol {
        navigationTitle(Text(title))
    }

    /// Items at the bar's leading and trailing edges, drawn over the bar
    /// from the page.
    public func navigationBarItems<L, T>(leading: L, trailing: T) -> some View where L: View, T: View {
        modifier(NavigationBarItemsModifier(leading: leading, trailing: trailing))
    }

    public func navigationBarItems<T>(trailing: T) -> some View where T: View {
        modifier(NavigationBarItemsModifier(leading: EmptyView(), trailing: trailing))
    }

    /// Toolbar content, as items at the bar's trailing edge.
    public func toolbar<Content>(@ViewBuilder content: () -> Content) -> some View where Content: View {
        modifier(NavigationBarItemsModifier(leading: EmptyView(), trailing: content()))
    }
}

struct NavigationBarItemsModifier<Leading: View, Trailing: View>: ViewModifier {
    var leading: Leading
    var trailing: Trailing
    /// A view in place of the bar's title.
    var principal: AnyView? = nil
    @Environment(\.navigationBarHeight) private var barHeight

    func body(content: Content) -> some View {
        content.overlay(alignment: .top) {
            if barHeight > 0 {
                ZStack {
                    if let principal {
                        principal
                    }
                    HStack(spacing: 16) {
                        leading
                        Spacer(minLength: 0)
                        trailing
                    }
                }
                .padding(.horizontal, 16)
                .frame(height: barHeight)
                .modifier(_OffsetEffect(offset: CGSize(width: 0, height: -barHeight)))
            }
        }
    }
}

// MARK: - The bar

/// A UINavigationBar with an item per page: the shown page's title, and a
/// back button titled with the page below's.
struct NavigationBarRepresentable: UIViewRepresentable {
    var titles: [Text?]
    var hidesBackButton: Bool
    var onBack: () -> Void
    @Environment(\.self) private var environment

    func makeUIView(context: Context) -> PassthroughNavigationBar {
        let bar = PassthroughNavigationBar()
        bar.delegate = context.coordinator
        return bar
    }

    func updateUIView(_ bar: PassthroughNavigationBar, context: Context) {
        context.coordinator.onBack = onBack
        let strings = titles.map { $0?._resolveText(in: environment) ?? "" }
        bar.hidesBackButton = hidesBackButton
        guard strings != context.coordinator.shown || hidesBackButton != context.coordinator.hidesBackButton else { return }
        context.coordinator.shown = strings
        context.coordinator.hidesBackButton = hidesBackButton
        let items = strings.map { UINavigationItem(title: $0) }
        items.last?.hidesBackButton = hidesBackButton
        bar.setItems(items, animated: false)
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator: NSObject, UINavigationBarDelegate {
        var onBack: () -> Void = {}
        var shown: [String] = []
        var hidesBackButton = false

        func navigationBar(_ navigationBar: UINavigationBar, shouldPop item: UINavigationItem) -> Bool {
            shown.removeLast()
            onBack()
            return true
        }
    }
}
/// A navigation bar that takes touches only on its back button, leaving
/// the rest to the bar items drawn over it.
final class PassthroughNavigationBar: UINavigationBar {
    static var backButtonWidth: CGFloat { 100 }
    var hidesBackButton = false

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard !hidesBackButton, (items?.count ?? 0) > 1, point.x < Self.backButtonWidth else { return nil }
        return super.hitTest(point, with: event)
    }
}
#endif
