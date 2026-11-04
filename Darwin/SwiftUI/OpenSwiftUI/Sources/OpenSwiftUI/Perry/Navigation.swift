//
//  Navigation.swift
//  OpenSwiftUI
//
//  Status: Perry's implementation
//
//  NavigationStack keeps its pages in SwiftUI state and shows the top one
//  under a UINavigationBar. The pages are one view graph with the stack;
//  only the bar is UIKit's. Titles come up from the shown page through a
//  preference; bar items are drawn where they are declared, over the bar.

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

/// Pushes a page onto the enclosing navigation stack.
struct NavigationPushKey: EnvironmentKey {
    static let defaultValue: ((AnyView) -> Void)? = nil
}

/// The height of the enclosing navigation stack's bar, which bar items are
/// drawn up into.
struct NavigationBarHeightKey: EnvironmentKey {
    static let defaultValue: CGFloat = 0
}

extension EnvironmentValues {
    var navigationPush: ((AnyView) -> Void)? {
        get { self[NavigationPushKey.self] }
        set { self[NavigationPushKey.self] = newValue }
    }

    var navigationBarHeight: CGFloat {
        get { self[NavigationBarHeightKey.self] }
        set { self[NavigationBarHeightKey.self] = newValue }
    }
}

// MARK: - NavigationStack

/// A view that displays a root view and enables you to present additional
/// views over the root view.
@available(OpenSwiftUI_v4_0, *)
public struct NavigationStack<Data, Root>: View where Root: View {
    var root: Root
    @State private var pages: [AnyView] = []
    @State private var titles: [Int: Text] = [:]

    static var barHeight: CGFloat { 44 }

    public init(@ViewBuilder root: () -> Root) where Data == NavigationPath {
        self.root = root()
    }

    public init(path: Binding<NavigationPath>, @ViewBuilder root: () -> Root) where Data == NavigationPath {
        self.root = root()
    }

    public var body: some View {
        let depth = pages.count
        VStack(spacing: 0) {
            NavigationBarRepresentable(
                titles: (0...depth).map { titles[$0] },
                onBack: { if !pages.isEmpty { pages.removeLast() } }
            )
            .frame(height: Self.barHeight)
            ZStack(alignment: .top) {
                if let top = pages.last {
                    top
                } else {
                    root
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .onPreferenceChange(StackTitleKey.self) { title in
                titles[depth] = title
            }
        }
        .environment(\.navigationPush, { (page: AnyView) in pages.append(page) })
        .environment(\.navigationBarHeight, Self.barHeight)
        // An edit button in the bar and the page's list share an edit mode.
        .modifier(EditModeScopeModifier(isActive: true))
    }
}

// MARK: - NavigationLink

/// A view that controls a navigation presentation.
@available(OpenSwiftUI_v1_0, *)
public struct NavigationLink<Label, Destination>: View where Label: View, Destination: View {
    var destination: Destination
    var label: Label
    @Environment(\.navigationPush) private var push

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
            push?(AnyView(destination))
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
    @Environment(\.navigationBarHeight) private var barHeight

    func body(content: Content) -> some View {
        content.overlay(alignment: .top) {
            if barHeight > 0 {
                HStack(spacing: 16) {
                    leading
                    Spacer(minLength: 0)
                    trailing
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
        guard strings != context.coordinator.shown else { return }
        context.coordinator.shown = strings
        bar.setItems(strings.map { UINavigationItem(title: $0) }, animated: false)
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator: NSObject, UINavigationBarDelegate {
        var onBack: () -> Void = {}
        var shown: [String] = []

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

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard (items?.count ?? 0) > 1, point.x < Self.backButtonWidth else { return nil }
        return super.hitTest(point, with: event)
    }
}
#endif
