//
//  Containers.swift
//  OpenSwiftUI
//
//  Status: Perry's implementation, interim
//
//  ScrollView, LazyVStack, List and Form as plain stacks, laid out from the
//  top and clipped to their frame. They don't scroll yet: that comes from a
//  UIScrollView through the display list's platform groups.

#if os(iOS) || os(visionOS)
public import OpenSwiftUICore

// MARK: - ScrollView

/// A scrollable view.
@available(OpenSwiftUI_v1_0, *)
public struct ScrollView<Content>: View where Content: View {
    /// The scroll view's content.
    public var content: Content

    /// The scrollable axes of the scroll view.
    public var axes: Axis.Set

    /// A value that indicates whether the scroll view displays the scrollable
    /// component of the content offset.
    public var showsIndicators: Bool

    public init(_ axes: Axis.Set = .vertical, showsIndicators: Bool = true, @ViewBuilder content: () -> Content) {
        self.axes = axes
        self.showsIndicators = showsIndicators
        self.content = content()
    }

    public var body: some View {
        content
            .fixedSize(horizontal: axes.contains(.horizontal), vertical: axes.contains(.vertical))
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .clipped()
    }
}

// MARK: - LazyVStack

/// Kinds of views that can be pinned to the bounds of a scroll view.
@available(OpenSwiftUI_v2_0, *)
@frozen
public struct PinnedScrollableViews: OptionSet, Sendable {
    public let rawValue: UInt32

    public init(rawValue: UInt32) { self.rawValue = rawValue }

    /// The header view of each `Section` will be pinned.
    public static let sectionHeaders = PinnedScrollableViews(rawValue: 1 << 0)

    /// The footer view of each `Section` will be pinned.
    public static let sectionFooters = PinnedScrollableViews(rawValue: 1 << 1)
}

/// A view that arranges its children in a line that grows vertically,
/// creating items only as needed.
@available(OpenSwiftUI_v2_0, *)
public struct LazyVStack<Content>: View where Content: View {
    var alignment: HorizontalAlignment
    var spacing: CGFloat?
    var pinnedViews: PinnedScrollableViews
    var content: Content

    public init(
        alignment: HorizontalAlignment = .center,
        spacing: CGFloat? = nil,
        pinnedViews: PinnedScrollableViews = .init(),
        @ViewBuilder content: () -> Content
    ) {
        self.alignment = alignment
        self.spacing = spacing
        self.pinnedViews = pinnedViews
        self.content = content()
    }

    public var body: some View {
        VStack(alignment: alignment, spacing: spacing) { content }
    }
}

// MARK: - List and Form

/// A container that presents rows of data arranged in a single column.
@available(OpenSwiftUI_v1_0, *)
public struct List<SelectionValue, Content>: View where SelectionValue: Hashable, Content: View {
    var content: Content

    public var body: some View {
        ScrollView {
            _VariadicView.Tree(RowsRoot(inset: false)) { content }
        }
    }
}

@available(OpenSwiftUI_v1_0, *)
extension List where SelectionValue == Never {
    public init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }
}

/// A container for grouping controls used for data entry.
@available(OpenSwiftUI_v1_0, *)
public struct Form<Content>: View where Content: View {
    var content: Content

    public init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    public var body: some View {
        ScrollView {
            _VariadicView.Tree(RowsRoot(inset: true)) { content }
        }
        .background(Color.gray.opacity(0.12))
    }
}

/// Lays out each child as a row, with separators between them.
struct RowsRoot: _VariadicView.UnaryViewRoot {
    /// Whether the rows sit on cards inset from the sides, as in a form.
    var inset: Bool

    func body(children: _VariadicView.Children) -> some View {
        let last = children.last?.id
        VStack(alignment: .leading, spacing: 0) {
            ForEach(children) { child in
                VStack(alignment: .leading, spacing: 0) {
                    child
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                        .padding(.horizontal, 16)
                    if child.id != last {
                        Divider().padding(.leading, 16)
                    }
                }
            }
        }
        .background(inset ? Color.white : Color.clear)
        .cornerRadius(inset ? 10 : 0)
        .padding(inset ? 16 : 0)
    }
}

// MARK: - Section

@available(OpenSwiftUI_v1_0, *)
extension Section {
    @usableFromInline
    static func create(isExpanded: Binding<Bool>? = nil, content: Content, header: Parent, footer: Footer) -> Section<Parent, Content, Footer> {
        var section = Section(header: header, content: content, footer: footer)
        section.isExpanded = isExpanded
        return section
    }
}

// MARK: - ForEach

@available(OpenSwiftUI_v1_0, *)
extension ForEach where ID == Data.Element.ID, Data.Element: Identifiable {
    @usableFromInline
    static func create(_ data: Data, content: @escaping (Data.Element) -> Content) -> ForEach<Data, ID, Content> {
        ForEach(data, idGenerator: .keyPath(\.id), content: content)
    }
}

@available(OpenSwiftUI_v1_0, *)
extension ForEach {
    @usableFromInline
    static func create(_ data: Data, id: KeyPath<Data.Element, ID>, content: @escaping (Data.Element) -> Content) -> ForEach<Data, ID, Content> {
        ForEach(data, idGenerator: .keyPath(id), content: content)
    }
}
#endif
