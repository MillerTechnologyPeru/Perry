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

    public var body: some View {
        GroupedRows(content: content)
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
        GroupedRows(content: content)
    }
}

/// Rows in iOS's inset grouped style, which lists and forms take by
/// default: each section's rows on a rounded card, with separators between
/// them, its header above and footer below, on a gray background; all
/// scrolling.
struct GroupedRows<Content: View>: View {
    var content: Content

    static var background: Color { Color(red: 242 / 255, green: 242 / 255, blue: 247 / 255) }

    var body: some View {
        ScrollView {
            // The style is set on the content, as the inputs of rows a
            // ForEach makes are its own, not where they are placed.
            _VariadicView.Tree(GroupedRowsRoot()) { content.buttonStyle(ListRowButtonStyle()) }
                .padding(.vertical, 16)
        }
        .background(Self.background)
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
    @Environment(\.scrollTargetScroller) private var scroller
    @State private var frames = RowFrames()

    var body: some View {
        let _ = { frames.children = children.map { $0 }; scroller?.add(frames) }()
        GroupedRowsLayout(children: children, frames: frames)
    }
}

struct GroupedRowsRoot: _VariadicView.UnaryViewRoot {
    static var inset: CGFloat { 16 }

    /// Sections' headers and footers marked, and their rows' depth.
    static var _viewListOptions: Int {
        Int(_ViewListInputs.Options([.requiresDepthAndSections, .requiresNonEmptyGroupParent]).rawValue)
    }

    func body(children: _VariadicView.Children) -> some View {
        GroupedRowsBody(children: children)
    }
}

/// The sections and their rows.
struct GroupedRowsLayout: View {
    var children: _VariadicView.Children
    var frames: RowFrames
    static var inset: CGFloat { GroupedRowsRoot.inset }

    var body: some View {
        let sections = RowSection.sections(of: children)
        VStack(alignment: .leading, spacing: 0) {
            ForEach(sections.indices, id: \.self) { index in
                let section = sections[index]
                VStack(alignment: .leading, spacing: 0) {
                    if let header = section.header {
                        children[header]
                            .font(.footnote)
                            .foregroundColor(Color.secondary)
                            .padding(.horizontal, Self.inset * 2)
                            .padding(.bottom, 6)
                    }
                    if !section.rows.isEmpty {
                        VStack(alignment: .leading, spacing: 0) {
                            ForEach(section.rows, id: \.self) { row in
                                children[row]
                                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                                    .padding(.horizontal, Self.inset)
                                    .background(RowFrameRecorder(frames: frames, index: row))
                                if row != section.rows.last {
                                    Divider().padding(.leading, Self.inset)
                                }
                            }
                        }
                        .background(Color.white)
                        .cornerRadius(10)
                        .padding(.horizontal, Self.inset)
                    }
                    if let footer = section.footer {
                        children[footer]
                            .font(.footnote)
                            .foregroundColor(Color.secondary)
                            .padding(.horizontal, Self.inset * 2)
                            .padding(.top, 6)
                    }
                }
                .padding(.bottom, 24)
            }
        }
    }
}

/// A button in a row: the whole row, in the accent color, dimmed while
/// pressed, as list rows' buttons are.
struct ListRowButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundColor(Color.accentColor)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .contentShape(Rectangle())
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
