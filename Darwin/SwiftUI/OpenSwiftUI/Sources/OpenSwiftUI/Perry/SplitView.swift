//
//  SplitView.swift
//  OpenSwiftUI
//
//  Status: Perry's implementation
//
//  NavigationSplitView as an iPhone shows it, collapsed: a navigation stack
//  of its sidebar, whose links push the views they lead to. DisclosureGroup:
//  its label with a chevron, which shows or hides its content. And the
//  modifiers of bar and status bar appearance, which Perry's bars draw in
//  their own colors.

#if os(iOS) || os(visionOS)
public import OpenSwiftUICore
public import UIKit

// MARK: - NavigationSplitView

/// The columns a split view shows; collapsed here, so its sidebar alone.
@available(OpenSwiftUI_v4_0, *)
public struct NavigationSplitViewVisibility: Equatable, Codable, Sendable {
    let rawValue: Int
    public static var detailOnly: NavigationSplitViewVisibility { NavigationSplitViewVisibility(rawValue: 0) }
    public static var doubleColumn: NavigationSplitViewVisibility { NavigationSplitViewVisibility(rawValue: 1) }
    public static var all: NavigationSplitViewVisibility { NavigationSplitViewVisibility(rawValue: 2) }
    public static var automatic: NavigationSplitViewVisibility { NavigationSplitViewVisibility(rawValue: 3) }
}

/// A view that presents views in two or three columns, where selections in
/// leading columns control presentations in subsequent columns.
@available(OpenSwiftUI_v4_0, *)
nonisolated public struct NavigationSplitView<Sidebar, Content, Detail>: View where Sidebar: View, Content: View, Detail: View {
    var sidebar: Sidebar
    var content: Content
    var detail: Detail

    public init(@ViewBuilder sidebar: () -> Sidebar, @ViewBuilder content: () -> Content, @ViewBuilder detail: () -> Detail) {
        self.sidebar = sidebar()
        self.content = content()
        self.detail = detail()
    }

    public init(
        columnVisibility: Binding<NavigationSplitViewVisibility>,
        @ViewBuilder sidebar: () -> Sidebar, @ViewBuilder content: () -> Content, @ViewBuilder detail: () -> Detail
    ) {
        self.init(sidebar: sidebar, content: content, detail: detail)
    }

    public init(@ViewBuilder sidebar: () -> Sidebar, @ViewBuilder detail: () -> Detail) where Content == EmptyView {
        self.sidebar = sidebar()
        self.content = EmptyView()
        self.detail = detail()
    }

    public init(
        columnVisibility: Binding<NavigationSplitViewVisibility>,
        @ViewBuilder sidebar: () -> Sidebar, @ViewBuilder detail: () -> Detail
    ) where Content == EmptyView {
        self.init(sidebar: sidebar, detail: detail)
    }

    /// Collapsed, as on an iPhone: the sidebar in a navigation stack.
    public var body: some View {
        NavigationStack { sidebar }
    }
}

// MARK: - DisclosureGroup

/// A view that shows or hides another content view, based on the state of
/// a disclosure control.
@available(OpenSwiftUI_v2_0, *)
nonisolated public struct DisclosureGroup<Label, Content>: View where Label: View, Content: View {
    var label: Label
    var content: () -> Content
    var isExpanded: Binding<Bool>?
    @State private var expanded = false

    public init(@ViewBuilder content: @escaping () -> Content, @ViewBuilder label: () -> Label) {
        self.label = label()
        self.content = content
    }

    public init(isExpanded: Binding<Bool>, @ViewBuilder content: @escaping () -> Content, @ViewBuilder label: () -> Label) {
        self.label = label()
        self.content = content
        self.isExpanded = isExpanded
    }

    private var shown: Bool { isExpanded?.wrappedValue ?? expanded }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation {
                    if let isExpanded { isExpanded.wrappedValue.toggle() } else { expanded.toggle() }
                }
            } label: {
                HStack {
                    label
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundColor(.accentColor)
                        .rotationEffect(.degrees(shown ? 90 : 0))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if shown {
                content()
            }
        }
    }
}

@available(OpenSwiftUI_v2_0, *)
extension DisclosureGroup where Label == Text {
    public init(_ titleKey: LocalizedStringKey, @ViewBuilder content: @escaping () -> Content) {
        self.init(content: content) { Text(titleKey) }
    }

    public init(_ titleKey: LocalizedStringKey, isExpanded: Binding<Bool>, @ViewBuilder content: @escaping () -> Content) {
        self.init(isExpanded: isExpanded, content: content) { Text(titleKey) }
    }

    @_disfavoredOverload
    public init<S>(_ label: S, @ViewBuilder content: @escaping () -> Content) where S: StringProtocol {
        self.init(content: content) { Text(label) }
    }
}

// MARK: - Bar and status bar appearance

@available(OpenSwiftUI_v4_0, *)
extension View {
    /// Shows or hides the bars' backgrounds; Perry's bars always draw theirs.
    nonisolated public func toolbarBackground(_ visibility: Visibility, for bars: ToolbarPlacement...) -> some View {
        self
    }

    /// Fills the bars' backgrounds with a style; Perry's bars keep their own.
    nonisolated public func toolbarBackground<S>(_ style: S, for bars: ToolbarPlacement...) -> some View where S: ShapeStyle {
        self
    }

    /// Sets the bars' color scheme; Perry's bars follow the app's.
    nonisolated public func toolbarColorScheme(_ colorScheme: ColorScheme?, for bars: ToolbarPlacement...) -> some View {
        self
    }

    /// Shows or hides the system's overlays, such as the home indicator,
    /// which there are none of here.
    @available(OpenSwiftUI_v4_0, *)
    nonisolated public func persistentSystemOverlays(_ visibility: Visibility) -> some View {
        self
    }
}

@available(OpenSwiftUI_v1_0, *)
extension View {
    /// Hides the status bar, which Perry's screen doesn't have.
    nonisolated public func statusBar(hidden: Bool) -> some View {
        self
    }
}
#endif
