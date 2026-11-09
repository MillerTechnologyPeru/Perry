//
//  Containers.swift
//  OpenSwiftUI
//
//  Status: Perry's implementation
//
//  List and Form: sections of rows in a ScrollView.

#if os(iOS) || os(visionOS)
public import OpenSwiftUICore

// MARK: - List and Form

/// A container that presents rows of data arranged in a single column.
@available(OpenSwiftUI_v1_0, *)
public struct List<SelectionValue, Content>: View where SelectionValue: Hashable, Content: View {
    var content: Content
    var selection: ListSelection?
    @Environment(\.listRowsStyle) private var style

    public var body: some View {
        GroupedRows(content: content, selection: selection, style: style)
    }
}

@available(OpenSwiftUI_v1_0, *)
extension List where SelectionValue == Never {
    public init(@ViewBuilder content: () -> Content) {
        self.content = content()
        self.selection = nil
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
        GroupedRows(content: content, selection: nil, style: .insetGrouped)
    }
}

/// Rows in one of iOS's list styles: by default inset grouped, which
/// forms take too, each section's rows on a rounded card, with separators
/// between them, its header above and footer below, on a gray background;
/// all scrolling.
struct GroupedRows<Content: View>: View {
    var content: Content
    var selection: ListSelection?
    var style: RowsStyle

    static var background: Color { Color(red: 242 / 255, green: 242 / 255, blue: 247 / 255) }

    var body: some View {
        ScrollView {
            // The style is set on the content, as the inputs of rows a
            // ForEach makes are its own, not where they are placed.
            _VariadicView.Tree(GroupedRowsRoot(selection: selection, style: style)) { content.buttonStyle(ListRowButtonStyle()) }
                .padding(.vertical, style.isPlain ? 0 : 16)
        }
        // A plain list is transparent between and below its rows, which are
        // white, as iOS's: what is behind it shows.
        .background(style.isPlain ? Color.clear : Self.background)
    }
}

/// A section's children: offsets of its header, rows and footer.
struct RowSection {
    var header: Int?
    var rows: [Int] = []
    var footer: Int?
    /// Whether a `Section` made it, rather than rows outside any.
    var explicit: Bool

    /// The sections of the children, by the traits `Section` gives its
    /// header, content and footer; rows outside any section form sections
    /// of their own.
    static func sections(of children: _VariadicView.Children) -> [RowSection] {
        var sections: [RowSection] = []
        for index in children.indices {
            let traits = children[index].traits
            if traits.isSectionFooter {
                if sections.isEmpty { sections.append(RowSection(explicit: true)) }
                sections[sections.count - 1].footer = index
            } else if traits.groupDepth == 0, traits.isSectioned {
                sections.append(RowSection(header: traits.isEmptyView ? nil : index, explicit: true))
            } else {
                // A row: in the open section, unless it is outside any
                // section and the open one is a Section's, or that has ended.
                let outside = traits.groupDepth == 0
                if let last = sections.last, last.footer == nil, last.explicit == !outside {
                    sections[sections.count - 1].rows.append(index)
                } else {
                    sections.append(RowSection(rows: [index], explicit: !outside))
                }
            }
        }
        return sections
    }
}

/// A row's offset among the children, and its child's identifier, which
/// keeps its state with it as rows before it come and go.
struct RowReference: Identifiable {
    var index: Int
    var id: AnyHashable
}

/// Records a row's frame in its scroll view's content, for scrolling to it.
struct RowFrameRecorder: View {
    var frames: RowFrames
    var index: Int

    var body: some View {
        GeometryReader { proxy in
            let _ = { frames.frames[index] = proxy.frame(in: .named(ScrollViewportInfo.contentSpace)) }()
            Color.clear
        }
    }
}

/// The rows' frames, kept for the scroll view they're in.
struct GroupedRowsBody: View {
    var children: _VariadicView.Children
    var selection: ListSelection?
    var style: RowsStyle
    @Environment(\.scrollTargetScroller) private var scroller
    @State private var frames = RowFrames()

    var body: some View {
        let _ = { frames.children = children.map { $0 }; scroller?.add(frames) }()
        GroupedRowsLayout(children: children, frames: frames, selection: selection, style: style)
    }
}

struct GroupedRowsRoot: _VariadicView.UnaryViewRoot {
    var selection: ListSelection?
    var style: RowsStyle

    static var inset: CGFloat { 16 }

    /// Sections' headers and footers marked, and their rows' depth.
    static var _viewListOptions: Int {
        Int(_ViewListInputs.Options([.requiresDepthAndSections, .requiresNonEmptyGroupParent]).rawValue)
    }

    func body(children: _VariadicView.Children) -> some View {
        GroupedRowsBody(children: children, selection: selection, style: style)
    }
}

/// The sections and their rows.
struct GroupedRowsLayout: View {
    var children: _VariadicView.Children
    var frames: RowFrames
    var selection: ListSelection?
    var style: RowsStyle
    static var inset: CGFloat { GroupedRowsRoot.inset }

    /// Headers' and footers' inset: under the card's rows' text.
    var textInset: CGFloat { style.cardInset + Self.inset }

    var body: some View {
        let sections = RowSection.sections(of: children)
        VStack(alignment: .leading, spacing: 0) {
            ForEach(sections.indices, id: \.self) { index in
                let section = sections[index]
                VStack(alignment: .leading, spacing: 0) {
                    if let header = section.header {
                        if style.isPlain {
                            children[header]
                                .font(.headline)
                                .padding(.horizontal, Self.inset)
                                .padding(.vertical, 6)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(GroupedRows<EmptyView>.background)
                        } else {
                            children[header]
                                .font(.footnote)
                                .foregroundColor(Color.secondary)
                                .padding(.horizontal, textInset)
                                .padding(.bottom, 6)
                        }
                    }
                    if !section.rows.isEmpty {
                        let rows = section.rows.map { RowReference(index: $0, id: children[$0].id) }
                        // Only the rows near the viewport are built, as a
                        // list's cells are.
                        LazyVStack(alignment: .leading, spacing: 0) {
                            ForEach(rows) { row in
                                RowAndSeparator(inset: Self.inset) {
                                    ListRow(child: children[row.index], selection: selection, inset: Self.inset)
                                        .background(RowFrameRecorder(frames: frames, index: row.index))
                                    if style.isPlain || row.index != section.rows.last {
                                        Divider()
                                    }
                                }
                            }
                        }
                        .background(Color.white)
                        .modifier(CardCorners(radius: style.cornerRadius))
                        .padding(.horizontal, style.cardInset)
                    }
                    if let footer = section.footer {
                        children[footer]
                            .font(.footnote)
                            .foregroundColor(Color.secondary)
                            .padding(.horizontal, textInset)
                            .padding(.top, 6)
                    }
                }
                .padding(.bottom, style.isPlain ? 0 : 24)
            }
        }
    }
}

/// A row and the separator below it, which starts under the row's first
/// text, or at the row's inset when it has none.
struct RowAndSeparator: Layout {
    var inset: CGFloat

    /// Where the row's text starts at a width. Finding it walks the row's
    /// views, and a scrolling list places each row every frame.
    struct Cache {
        var width = CGFloat.nan
        var leading: CGFloat?
    }

    func makeCache(subviews: Subviews) -> Cache { Cache() }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Cache) -> CGSize {
        var size = subviews[0].sizeThatFits(ProposedViewSize(width: proposal.width, height: nil))
        if subviews.count > 1 {
            size.height += subviews[1].sizeThatFits(ProposedViewSize(width: size.width, height: nil)).height
        }
        return size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Cache) {
        let across = ProposedViewSize(width: bounds.width, height: nil)
        let row = subviews[0].dimensions(in: across)
        subviews[0].place(at: bounds.origin, proposal: across)
        guard subviews.count > 1 else { return }
        if cache.width != bounds.width {
            cache = Cache(width: bounds.width, leading: row[explicit: HorizontalAlignment.leadingText])
        }
        let leading = cache.leading ?? inset
        subviews[1].place(
            at: CGPoint(x: bounds.minX + leading, y: bounds.minY + row.height),
            proposal: ProposedViewSize(width: max(bounds.width - leading - ListRowMetrics.separatorTrailingInset, 0), height: nil))
    }
}

/// An inset grouped list's rounded card. Other lists' rows are not
/// clipped: a clip, even with no radius, puts each row the lazy stack makes
/// in a clipping view the length of the whole list.
struct CardCorners: ViewModifier {
    var radius: CGFloat

    func body(content: Content) -> some View {
        if radius > 0 {
            content.cornerRadius(radius)
        } else {
            content
        }
    }
}

/// A button in a row: the whole row, dimmed while pressed, as list rows'
/// buttons are. Its label is in the accent color for apps built before the
/// iOS 26 SDK, whose list buttons show their labels as any content, in the
/// primary color.
struct ListRowButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundColor(isLinkedOnOrAfter(.v7) ? nil : Color.accentColor)
            .frame(maxWidth: .infinity, alignment: .leading)
            // The whole row is tapped, the spacing around the label too.
            .padding(.vertical, ListRowMetrics.verticalInset)
            .contentShape(Rectangle())
            .padding(.vertical, -ListRowMetrics.verticalInset)
            .opacity(configuration.isPressed ? 0.5 : 1)
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
