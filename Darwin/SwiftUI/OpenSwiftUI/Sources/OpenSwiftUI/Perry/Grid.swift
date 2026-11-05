//
//  Grid.swift
//  OpenSwiftUI
//
//  Status: Perry's implementation
//
//  LazyVGrid: its children in rows, a column each, laid out by a Layout.
//  Fixed columns take their width; flexible ones share what's left; an
//  adaptive one fits as many columns of at least its minimum width in its
//  share as it can. Each row is as tall as its tallest child. Every child
//  is made, not only those its scroll view shows.

#if os(iOS) || os(visionOS)
public import OpenSwiftUICore

// MARK: - GridItem

/// A description of a row or a column in a lazy grid.
@available(OpenSwiftUI_v2_0, *)
public struct GridItem: Sendable {
    /// The size in the minor axis of one or more rows or columns in a grid
    /// layout.
    public enum Size: Sendable {
        case fixed(CGFloat)
        case flexible(minimum: CGFloat = 10, maximum: CGFloat = .infinity)
        case adaptive(minimum: CGFloat, maximum: CGFloat = .infinity)
    }

    public var size: GridItem.Size
    public var spacing: CGFloat?
    public var alignment: Alignment?

    public init(_ size: GridItem.Size = .flexible(), spacing: CGFloat? = nil, alignment: Alignment? = nil) {
        self.size = size
        self.spacing = spacing
        self.alignment = alignment
    }
}

// MARK: - LazyVGrid

/// A container view that arranges its child views in a grid that grows
/// vertically.
@available(OpenSwiftUI_v2_0, *)
public struct LazyVGrid<Content>: View where Content: View {
    var columns: [GridItem]
    var alignment: HorizontalAlignment
    var spacing: CGFloat?
    var content: Content

    public init(
        columns: [GridItem],
        alignment: HorizontalAlignment = .center,
        spacing: CGFloat? = nil,
        pinnedViews: PinnedScrollableViews = .init(),
        @ViewBuilder content: () -> Content
    ) {
        self.columns = columns
        self.alignment = alignment
        self.spacing = spacing
        self.content = content()
    }

    public var body: some View {
        VerticalGridLayout(columns: columns, rowSpacing: spacing ?? 8) { content }
    }
}

/// One column of the grid as laid out: its width and its item.
struct GridColumn {
    var width: CGFloat
    var item: GridItem
}

struct VerticalGridLayout: Layout {
    var columns: [GridItem]
    var rowSpacing: CGFloat

    static var defaultSpacing: CGFloat { 8 }

    /// The columns for a width: fixed ones at their width, flexible ones
    /// sharing the rest, adaptive ones repeated within their share.
    func resolve(width: CGFloat) -> [GridColumn] {
        guard !columns.isEmpty else { return [] }
        let spacings = columns.dropLast().reduce(0) { $0 + ($1.spacing ?? Self.defaultSpacing) }
        let fixed = columns.reduce(0) { total, item in
            if case let .fixed(width) = item.size { return total + width }
            return total
        }
        let flexibleCount = columns.filter { if case .fixed = $0.size { false } else { true } }.count
        let share = flexibleCount > 0 ? max(0, (width - fixed - spacings) / CGFloat(flexibleCount)) : 0
        var resolved: [GridColumn] = []
        for item in columns {
            switch item.size {
            case let .fixed(width):
                resolved.append(GridColumn(width: width, item: item))
            case let .flexible(minimum, maximum):
                resolved.append(GridColumn(width: min(max(share, minimum), maximum), item: item))
            case let .adaptive(minimum, maximum):
                let spacing = item.spacing ?? Self.defaultSpacing
                let count = max(1, Int((share + spacing) / (max(minimum, 1) + spacing)))
                let columnWidth = min(maximum, (share - spacing * CGFloat(count - 1)) / CGFloat(count))
                for _ in 0 ..< count {
                    resolved.append(GridColumn(width: max(columnWidth, 0), item: item))
                }
            }
        }
        return resolved
    }

    func rows(_ subviews: Subviews, columns: [GridColumn]) -> [(range: Range<Int>, height: CGFloat)] {
        guard !columns.isEmpty else { return [] }
        var rows: [(Range<Int>, CGFloat)] = []
        var start = 0
        while start < subviews.count {
            let end = min(start + columns.count, subviews.count)
            var height: CGFloat = 0
            for index in start ..< end {
                let size = subviews[index].sizeThatFits(ProposedViewSize(width: columns[index - start].width, height: nil))
                height = max(height, size.height)
            }
            rows.append((start ..< end, height))
            start = end
        }
        return rows
    }

    private func totalWidth(_ columns: [GridColumn]) -> CGFloat {
        columns.reduce(0) { $0 + $1.width } + columns.dropLast().reduce(0) { $0 + ($1.item.spacing ?? Self.defaultSpacing) }
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 320
        let columns = resolve(width: width)
        let rows = rows(subviews, columns: columns)
        let height = rows.reduce(0) { $0 + $1.height } + rowSpacing * CGFloat(max(rows.count - 1, 0))
        return CGSize(width: proposal.width ?? totalWidth(columns), height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let columns = resolve(width: bounds.width)
        let used = totalWidth(columns)
        var y = bounds.minY
        for row in rows(subviews, columns: columns) {
            var x = bounds.minX + max(0, (bounds.width - used) / 2)
            for index in row.range {
                let column = columns[index - row.range.lowerBound]
                let size = subviews[index].sizeThatFits(ProposedViewSize(width: column.width, height: nil))
                let alignment = column.item.alignment ?? .center
                let dx: CGFloat = switch alignment.horizontal {
                case .leading: 0
                case .trailing: column.width - size.width
                default: (column.width - size.width) / 2
                }
                let dy: CGFloat = switch alignment.vertical {
                case .top: 0
                case .bottom: row.height - size.height
                default: (row.height - size.height) / 2
                }
                subviews[index].place(at: CGPoint(x: x + dx, y: y + dy), proposal: ProposedViewSize(width: column.width, height: nil))
                x += column.width + (column.item.spacing ?? Self.defaultSpacing)
            }
            y += row.height + rowSpacing
        }
    }
}
#endif
