//
//  GridContainers.swift
//  OpenSwiftUI
//
//  Status: Perry's implementation, interim
//
//  Grid and GridRow, as a vertical stack of horizontal stacks: each row
//  lays its cells out in a line by itself, so the cells of different rows
//  don't share column widths, and a child of the grid that isn't a row
//  takes a line of its own. The grid's alignment places the rows across
//  it and its vertical spacing separates them; its horizontal spacing
//  isn't passed to the rows, which space their cells as a stack does. The
//  cell modifiers (columns spanned, column alignment, unsized axes) are
//  taken and change nothing.

#if os(iOS) || os(visionOS)
public import Foundation
public import OpenSwiftUICore

// MARK: - Grid

/// A container view that arranges other views in a two dimensional
/// layout.
@available(OpenSwiftUI_v1_0, *)
@frozen
nonisolated public struct Grid<Content>: View, UnaryView, PrimitiveView where Content: View {
    @usableFromInline
    var _tree: _VariadicView.Tree<GridLayout, Content>

    /// Creates a grid with the given alignment of its cells, spacing
    /// between columns and between rows, and content.
    nonisolated public init(
        alignment: Alignment = .center,
        horizontalSpacing: CGFloat? = nil,
        verticalSpacing: CGFloat? = nil,
        @ViewBuilder content: () -> Content
    ) {
        let root = GridLayout(
            alignment: alignment,
            horizontalSpacing: horizontalSpacing,
            verticalSpacing: verticalSpacing
        )
        _tree = .init(root) { content() }
    }

    nonisolated public static func _makeView(
        view: _GraphValue<Grid<Content>>,
        inputs: _ViewInputs
    ) -> _ViewOutputs {
        _VariadicView.Tree<GridLayout, Content>.makeDebuggableView(
            view: view[\._tree],
            inputs: inputs
        )
    }
}

@available(*, unavailable)
extension Grid: Sendable {}

// MARK: - GridRow

/// A horizontal row in a two dimensional grid container. Its cells are
/// laid out as a horizontal stack's children, in a grid or out of one.
@available(OpenSwiftUI_v1_0, *)
@frozen
nonisolated public struct GridRow<Content>: View, UnaryView, PrimitiveView where Content: View {
    @usableFromInline
    var alignment: VerticalAlignment?

    @usableFromInline
    var content: Content

    /// Creates a horizontal row of child views, with the vertical
    /// alignment of its cells, or the grid's when `alignment` is nil
    /// (the center, here).
    nonisolated public init(alignment: VerticalAlignment? = nil, @ViewBuilder content: () -> Content) {
        self.alignment = alignment
        self.content = content()
    }

    /// The row as the stack that draws it.
    var stack: HStack<Content> {
        HStack(alignment: alignment ?? .center) { content }
    }

    nonisolated public static func _makeView(
        view: _GraphValue<GridRow<Content>>,
        inputs: _ViewInputs
    ) -> _ViewOutputs {
        HStack<Content>.makeDebuggableView(view: view[\.stack], inputs: inputs)
    }
}

@available(*, unavailable)
extension GridRow: Sendable {}

// MARK: - Cell modifiers

@available(OpenSwiftUI_v1_0, *)
extension View {
    /// Tells a view that acts as a cell in a grid to span the specified
    /// number of columns. Rows here have no columns to span: the cell is
    /// laid out as any other.
    nonisolated public func gridCellColumns(_ count: Int) -> some View {
        modifier(_GridCellSizeModifier(count: count, axis: .horizontal))
    }
}

/// A modifier that records how many columns or rows a grid cell spans:
/// kept with the view, and not read by the grid.
@available(OpenSwiftUI_v1_0, *)
@frozen
nonisolated public struct _GridCellSizeModifier: ViewModifier, PrimitiveViewModifier {
    @usableFromInline
    var count: Int

    @usableFromInline
    var axis: Axis

    @usableFromInline
    nonisolated init(count: Int, axis: Axis) {
        self.count = count
        self.axis = axis
    }

    nonisolated public static func _makeView(
        modifier: _GraphValue<_GridCellSizeModifier>,
        inputs: _ViewInputs,
        body: @escaping (_Graph, _ViewInputs) -> _ViewOutputs
    ) -> _ViewOutputs {
        body(_Graph(), inputs)
    }

    nonisolated public static func _makeViewList(
        modifier: _GraphValue<_GridCellSizeModifier>,
        inputs: _ViewListInputs,
        body: @escaping (_Graph, _ViewListInputs) -> _ViewListOutputs
    ) -> _ViewListOutputs {
        body(_Graph(), inputs)
    }

    public typealias Body = Never
}

/// A modifier that records the horizontal alignment of a grid cell's
/// column: kept with the view, and not read by the grid.
@available(OpenSwiftUI_v1_0, *)
@frozen
nonisolated public struct _GridAlignmentModifier: ViewModifier, PrimitiveViewModifier {
    @usableFromInline
    var alignment: AlignmentKey

    @usableFromInline
    nonisolated init(alignment: AlignmentKey) {
        self.alignment = alignment
    }

    nonisolated public static func _makeView(
        modifier: _GraphValue<_GridAlignmentModifier>,
        inputs: _ViewInputs,
        body: @escaping (_Graph, _ViewInputs) -> _ViewOutputs
    ) -> _ViewOutputs {
        body(_Graph(), inputs)
    }

    nonisolated public static func _makeViewList(
        modifier: _GraphValue<_GridAlignmentModifier>,
        inputs: _ViewListInputs,
        body: @escaping (_Graph, _ViewListInputs) -> _ViewListOutputs
    ) -> _ViewListOutputs {
        body(_Graph(), inputs)
    }

    public typealias Body = Never
}

/// A modifier that records the axes along which a grid cell asks for no
/// more room than the other cells of its row or column take: kept with
/// the view, and not read by the grid.
@available(OpenSwiftUI_v1_0, *)
@frozen
nonisolated public struct _GridUnsizedAxesModifier: ViewModifier, PrimitiveViewModifier {
    @usableFromInline
    var axes: Axis.Set

    @usableFromInline
    nonisolated init(axes: Axis.Set) {
        self.axes = axes
    }

    nonisolated public static func _makeView(
        modifier: _GraphValue<_GridUnsizedAxesModifier>,
        inputs: _ViewInputs,
        body: @escaping (_Graph, _ViewInputs) -> _ViewOutputs
    ) -> _ViewOutputs {
        body(_Graph(), inputs)
    }

    nonisolated public static func _makeViewList(
        modifier: _GraphValue<_GridUnsizedAxesModifier>,
        inputs: _ViewListInputs,
        body: @escaping (_Graph, _ViewListInputs) -> _ViewListOutputs
    ) -> _ViewListOutputs {
        body(_Graph(), inputs)
    }

    public typealias Body = Never
}

// MARK: - GridLayout

/// A grid that you can use in conditional layouts. Its subviews, a grid's
/// rows, are placed one under another as a vertical stack places them,
/// aligned by the horizontal guide of `alignment`.
@available(OpenSwiftUI_v1_0, *)
@frozen
nonisolated public struct GridLayout: _VariadicView.UnaryViewRoot {
    /// The alignment of subviews.
    public var alignment: Alignment

    /// The horizontal distance between each cell, given in points, or nil
    /// for the default. Not applied: each row spaces its own cells.
    public var horizontalSpacing: CGFloat?

    /// The vertical distance between each cell, given in points, or nil
    /// for the default.
    public var verticalSpacing: CGFloat?

    /// Creates a grid with the specified spacing and alignment.
    nonisolated public init(
        alignment: Alignment = .center,
        horizontalSpacing: CGFloat? = nil,
        verticalSpacing: CGFloat? = nil
    ) {
        self.alignment = alignment
        self.horizontalSpacing = horizontalSpacing
        self.verticalSpacing = verticalSpacing
    }

    nonisolated public static func _makeView(
        root: _GraphValue<GridLayout>,
        inputs: _ViewInputs,
        body: (_Graph, _ViewInputs) -> _ViewListOutputs
    ) -> _ViewOutputs {
        _makeLayoutView(root: root, inputs: inputs, body: body)
    }

    public typealias Body = Never
}

@available(OpenSwiftUI_v1_0, *)
extension GridLayout: Layout {
    /// The vertical stack that places the rows.
    private var rows: _VStackLayout {
        _VStackLayout(alignment: alignment.horizontal, spacing: verticalSpacing)
    }

    nonisolated public func makeCache(subviews: GridLayout.Subviews) -> GridLayout.Cache {
        Cache(stack: rows.makeCache(subviews: subviews))
    }

    nonisolated public func updateCache(_ cache: inout GridLayout.Cache, subviews: GridLayout.Subviews) {
        rows.updateCache(&cache.stack, subviews: subviews)
    }

    nonisolated public func spacing(subviews: GridLayout.Subviews, cache: inout GridLayout.Cache) -> ViewSpacing {
        rows.spacing(subviews: subviews, cache: &cache.stack)
    }

    nonisolated public func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: GridLayout.Subviews,
        cache: inout GridLayout.Cache
    ) -> CGSize {
        rows.sizeThatFits(proposal: proposal, subviews: subviews, cache: &cache.stack)
    }

    nonisolated public func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: GridLayout.Subviews,
        cache: inout GridLayout.Cache
    ) {
        rows.placeSubviews(in: bounds, proposal: proposal, subviews: subviews, cache: &cache.stack)
    }

    nonisolated public func explicitAlignment(
        of guide: HorizontalAlignment,
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: GridLayout.Subviews,
        cache: inout GridLayout.Cache
    ) -> CGFloat? {
        rows.explicitAlignment(of: guide, in: bounds, proposal: proposal, subviews: subviews, cache: &cache.stack)
    }

    nonisolated public func explicitAlignment(
        of guide: VerticalAlignment,
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: GridLayout.Subviews,
        cache: inout GridLayout.Cache
    ) -> CGFloat? {
        rows.explicitAlignment(of: guide, in: bounds, proposal: proposal, subviews: subviews, cache: &cache.stack)
    }

    public typealias AnimatableData = EmptyAnimatableData
}

@available(OpenSwiftUI_v1_0, *)
extension GridLayout {
    /// A stateful grid layout algorithm: here, the state of the vertical
    /// stack that places the rows.
    public struct Cache {
        var stack: _VStackLayout.Cache
    }
}

@available(*, unavailable)
extension GridLayout.Cache: Sendable {}
#endif
