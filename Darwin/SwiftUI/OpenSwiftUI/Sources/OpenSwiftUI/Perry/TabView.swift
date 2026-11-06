//
//  TabView.swift
//  OpenSwiftUI
//
//  Status: Perry's implementation
//
//  The tabs are the content's children, read as a variadic view: the shown
//  one is the child whose tag is the selection (or whose index is, for an
//  Int selection without tags), and each child's `tabItem` label becomes a
//  button along the bottom. The bar's backdrop is a UITabBar; the labels
//  over it are SwiftUI views, so they render like the rest of the app. In
//  the page style, the tabs are pages swiped between, with dots for them.

#if os(iOS) || os(visionOS)
public import OpenSwiftUICore
public import UIKit

// MARK: - TabView

/// A view that switches between multiple child views using interactive user
/// interface elements.
@available(OpenSwiftUI_v1_0, *)
public struct TabView<SelectionValue, Content>: View where SelectionValue: Hashable, Content: View {
    var selection: Binding<SelectionValue>?
    var content: Content
    /// The selection while no binding is given.
    @State private var internalSelection: AnyHashable?
    /// How the tabs are paged, when the style pages them.
    @Environment(\.tabViewPaging) private var paging
    /// Whether the shown tab hides the bar, with toolbar(.hidden, for: .tabBar).
    @State private var isBarHidden = false

    public init(selection: Binding<SelectionValue>?, @ViewBuilder content: () -> Content) {
        self.selection = selection
        self.content = content()
    }

    public var body: some View {
        let selected: Binding<AnyHashable?> = if let selection {
            Binding(
                get: { AnyHashable(selection.wrappedValue) },
                set: { if let value = $0?.base as? SelectionValue { selection.wrappedValue = value } }
            )
        } else {
            $internalSelection
        }
        if let paging {
            _VariadicView.Tree(PagedTabViewRoot<SelectionValue>(selection: selected, showsIndex: paging.showsIndex)) {
                content
            }
        } else {
            _VariadicView.Tree(TabViewRoot<SelectionValue>(selection: selected, isBarHidden: isBarHidden)) {
                content
            }
            .onPreferenceChange(TabBarHiddenKey.self) { hidden in
                isBarHidden = hidden ?? false
            }
        }
    }
}

@available(OpenSwiftUI_v1_0, *)
extension TabView where SelectionValue == Int {
    public init(@ViewBuilder content: () -> Content) {
        self.init(selection: nil, content: content)
    }
}

/// Lays out the selected tab above the tab bar.
struct TabViewRoot<SelectionValue: Hashable>: _VariadicView.UnaryViewRoot {
    var selection: Binding<AnyHashable?>
    var isBarHidden = false

    static var barHeight: CGFloat { 49 }

    /// The selection value of the child at `index`.
    func value(of child: _VariadicView.Children.Element, at index: Int) -> AnyHashable {
        if let tag = child.traits.tag(for: SelectionValue.self) {
            return AnyHashable(tag)
        }
        return AnyHashable(index)
    }

    func body(children: _VariadicView.Children) -> some View {
        let values = children.indices.map { value(of: children[$0], at: $0) }
        let current = selection.wrappedValue.flatMap { values.contains($0) ? $0 : nil } ?? values.first
        VStack(spacing: 0) {
            ZStack {
                ForEach(children.indices, id: \.self) { index in
                    if values[index] == current {
                        children[index]
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            if !isBarHidden {
                tabBar(children: children, values: values, current: current)
            }
        }
    }

    private func tabBar(children: _VariadicView.Children, values: [AnyHashable], current: AnyHashable?) -> some View {
        HStack(spacing: 0) {
            ForEach(children.indices, id: \.self) { index in
                let isSelected = values[index] == current
                Button {
                    selection.wrappedValue = values[index]
                } label: {
                    VStack(spacing: 2) {
                        children[index][TabItemTraitKey.self] ?? AnyView(EmptyView())
                    }
                    .labelStyle(TabItemLabelStyle())
                    .symbolVariant(isSelected ? .fill : .none)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(isSelected ? Color.accentColor : Color.gray)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .frame(height: Self.barHeight)
        .background(TabBarBackdrop())
    }
}

/// A tab item's label as an iPhone's tab bar shows it: its icon above its
/// title, which is small.
struct TabItemLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        VStack(spacing: 2) {
            configuration.icon
                .font(.system(size: 24))
                .frame(height: 30)
            configuration.title
                .font(.system(size: 10, weight: .medium))
                .lineLimit(1)
        }
    }
}

// MARK: - tabItem

/// A tab's label in its tab view's bar.
struct TabItemTraitKey: _ViewTraitKey {
    static var defaultValue: AnyView? { nil }
}

@available(OpenSwiftUI_v1_0, *)
extension View {
    /// Sets the tab bar item associated with this view.
    public func tabItem<V>(@ViewBuilder _ label: () -> V) -> some View where V: View {
        _trait(TabItemTraitKey.self, AnyView(label()))
    }
}

// MARK: - The bar

/// An empty UITabBar, for the bar's background and separator.
struct TabBarBackdrop: UIViewRepresentable {
    func makeUIView(context: Context) -> UITabBar { UITabBar() }
    func updateUIView(_ bar: UITabBar, context: Context) {}
}
#endif
