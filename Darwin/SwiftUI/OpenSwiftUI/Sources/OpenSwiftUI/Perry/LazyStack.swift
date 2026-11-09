//
//  LazyStack.swift
//  OpenSwiftUI
//
//  Status: Perry's implementation
//
//  LazyVStack and LazyHStack: stacks that make only the children near what
//  their scroll view shows. Each child takes the length it was last
//  measured at, or the average of those measured, so the stack's length and
//  the places of children not made are estimates until they show. Outside
//  a scroll view every child is made. Pinned section headers (and footers)
//  stay at the viewport's edge while their section passes under it.

#if os(iOS) || os(visionOS)
public import OpenSwiftUICore
import Foundation

// MARK: - PinnedScrollableViews

/// Kinds of views that can be pinned to the bounds of a scroll view.
@available(OpenSwiftUI_v2_0, *)
public struct PinnedScrollableViews: OptionSet, Sendable {
    public let rawValue: UInt32

    public init(rawValue: UInt32) { self.rawValue = rawValue }

    /// The header view of each `Section` will be pinned.
    public static let sectionHeaders = PinnedScrollableViews(rawValue: 1 << 0)

    /// The footer view of each `Section` will be pinned.
    public static let sectionFooters = PinnedScrollableViews(rawValue: 1 << 1)
}

// MARK: - LazyVStack

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
        _VariadicView.Tree(LazyStackRoot(
            axis: .vertical,
            crossAlignment: LazyStackRoot.CrossAlignment(alignment),
            spacing: spacing ?? LazyStackRoot.defaultSpacing,
            pinnedViews: pinnedViews
        )) { content }
    }
}

// MARK: - LazyHStack

/// A view that arranges its children in a line that grows horizontally,
/// creating items only as needed.
@available(OpenSwiftUI_v2_0, *)
public struct LazyHStack<Content>: View where Content: View {
    var alignment: VerticalAlignment
    var spacing: CGFloat?
    var pinnedViews: PinnedScrollableViews
    var content: Content

    public init(
        alignment: VerticalAlignment = .center,
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
        _VariadicView.Tree(LazyStackRoot(
            axis: .horizontal,
            crossAlignment: LazyStackRoot.CrossAlignment(alignment),
            spacing: spacing ?? LazyStackRoot.defaultSpacing,
            pinnedViews: pinnedViews
        )) { content }
    }
}

// MARK: - Root

struct LazyStackRoot: _VariadicView.UnaryViewRoot {
    /// Where children narrower than the stack sit across it.
    enum CrossAlignment {
        case leading, center, trailing

        init(_ alignment: HorizontalAlignment) {
            self = alignment == .leading ? .leading : alignment == .trailing ? .trailing : .center
        }

        init(_ alignment: VerticalAlignment) {
            self = alignment == .top ? .leading : alignment == .bottom ? .trailing : .center
        }
    }

    static var defaultSpacing: CGFloat { 8 }

    /// Sections' headers and footers marked, for pinning.
    static var _viewListOptions: Int {
        Int(_ViewListInputs.Options([.requiresDepthAndSections, .requiresNonEmptyGroupParent]).rawValue)
    }

    var axis: Axis
    var crossAlignment: CrossAlignment
    var spacing: CGFloat
    var pinnedViews: PinnedScrollableViews

    func body(children: _VariadicView.Children) -> some View {
        LazyStackBody(root: self, children: children)
    }
}

// MARK: - Measurements

/// The lengths children were last laid out at, by identity. Written by the
/// layout as it places them; a change asks the stack to place again with
/// it, as an estimate it replaces may have put others in the wrong place.
final class LazyStackMeasurements: ScrollTargetSource {
    private(set) var lengths: [AnyHashable: CGFloat] = [:]
    /// The children, and where the last plan put each along the stack;
    /// with the stack's origin in its scroll view's content, and its axis.
    var children: [_VariadicView.Children.Element] = []
    var starts: [CGFloat] = []
    var origin: CGPoint = .zero
    var axis: Axis = .vertical
    var crossLength: CGFloat = 0

    func frame<ID: Hashable>(of id: ID) -> CGRect? {
        guard let index = children.firstIndex(where: { $0.id(as: ID.self) == id }), index < starts.count else { return nil }
        let length = self.length(of: children[index].id)
        return axis == .vertical
            ? CGRect(x: origin.x, y: origin.y + starts[index], width: crossLength, height: length)
            : CGRect(x: origin.x + starts[index], y: origin.y, width: length, height: crossLength)
    }
    var onChange: (() -> Void)?
    private var changePending = false

    /// The children the last plan made, what they cover along the stack
    /// (without limit at an end of the stack that has been reached), and
    /// the viewport's size and the pinning it was made with.
    var made: Set<AnyHashable> = []
    var madeExtent: ClosedRange<CGFloat>?
    var plannedSize: CGSize?
    var pinned = false

    /// Plans again when what shows has come within half the overscan of
    /// the end of the views made, or pinned views have to follow it.
    func viewportMoved(_ info: ScrollViewportInfo) {
        if !pinned, info.size == plannedSize, let extent = madeExtent {
            let (low, high) = axis == .vertical
                ? (info.visible.minY - origin.y, info.visible.maxY - origin.y)
                : (info.visible.minX - origin.x, info.visible.maxX - origin.x)
            let margin = LazyStackBody.overscan / 2
            guard low - margin < extent.lowerBound || high + margin > extent.upperBound else { return }
        }
        notifyChange()
    }

    private func notifyChange() {
        guard !changePending else { return }
        changePending = true
        DispatchQueue.main.async { [self] in
            changePending = false
            onChange?()
        }
    }

    /// The length a child not yet measured is taken to have.
    var estimate: CGFloat {
        lengths.isEmpty ? 44 : lengths.values.reduce(0, +) / CGFloat(lengths.count)
    }

    func length(of id: AnyHashable) -> CGFloat { lengths[id] ?? estimate }

    func record(_ length: CGFloat, for id: AnyHashable) {
        guard lengths[id] != length else { return }
        lengths[id] = length
        notifyChange()
    }
}

/// The stack's origin in its scroll view's content.
struct LazyStackOriginKey: PreferenceKey {
    static let defaultValue: CGPoint = .zero
    static func reduce(value: inout CGPoint, nextValue: () -> CGPoint) { value = nextValue() }
}

// MARK: - Body

struct LazyStackBody: View {
    var root: LazyStackRoot
    var children: _VariadicView.Children

    @Environment(\.scrollViewport) private var source
    @Environment(\.scrollTargetScroller) private var scroller
    @State private var measurements = LazyStackMeasurements()
    @State private var remeasured = 0
    @State private var origin: CGPoint = .zero

    /// How far beyond what shows children are made, and how much further
    /// those made are kept, so content moving back and forth doesn't make
    /// the same views again.
    static var overscan: CGFloat { 300 }
    static var keepDistance: CGFloat { 600 }

    private var viewport: ScrollViewportInfo? { source?.info }

    var body: some View {
        let _ = remeasured
        let plan = LazyStackPlan(root: root, children: children, measurements: measurements,
                                 window: window, edge: edge)
        let _ = remember(plan)
        LazyStackLayout(axis: root.axis, crossAlignment: root.crossAlignment, positions: plan.positions,
                        ids: plan.shown.map(\.id), length: plan.length, measurements: measurements) {
            ForEach(plan.shown) { $0 }
        }
        .background(
            GeometryReader { proxy in
                Color.clear.modifier(_PreferenceWritingModifier<LazyStackOriginKey>(
                    value: proxy.frame(in: .named(ScrollViewportInfo.contentSpace)).origin
                ))
            }
        )
        .onPreferenceChange(LazyStackOriginKey.self) { origin = $0 }
        .onAppear {
            let remeasured = $remeasured
            measurements.onChange = { remeasured.wrappedValue &+= 1 }
            source?.add(measurements)
        }
        .onDisappear { source?.remove(measurements) }
    }

    /// Keeps where the plan puts children, for scrolling to one.
    func remember(_ plan: LazyStackPlan) {
        measurements.children = plan.all
        measurements.starts = plan.starts
        measurements.origin = origin
        measurements.axis = root.axis
        measurements.made = Set(plan.shown.map(\.id))
        measurements.madeExtent = plan.extent
        measurements.plannedSize = viewport?.size
        measurements.pinned = !root.pinnedViews.isEmpty
        measurements.crossLength = root.axis == .vertical ? (viewport?.size.width ?? 0) : (viewport?.size.height ?? 0)
        scroller?.add(measurements)
    }

    /// What shows or may soon, along the stack, in its own coordinates; nil
    /// outside a scroll view, when everything is made.
    var window: ClosedRange<CGFloat>? {
        guard let viewport else { return nil }
        let (low, high) = root.axis == .vertical
            ? (viewport.visible.minY - origin.y, viewport.visible.maxY - origin.y)
            : (viewport.visible.minX - origin.x, viewport.visible.maxX - origin.x)
        return (low - Self.overscan)...(high + Self.overscan)
    }

    /// The viewport's leading and trailing edges along the stack, in its
    /// own coordinates, where pinned views stay.
    var edge: ClosedRange<CGFloat>? {
        guard let viewport else { return nil }
        let (start, length) = root.axis == .vertical
            ? (viewport.offset.height - origin.y, viewport.size.height)
            : (viewport.offset.width - origin.x, viewport.size.width)
        return start...(start + length)
    }
}

/// Which children are made, and where they go along the stack.
struct LazyStackPlan {
    var shown: [_VariadicView.Children.Element] = []
    var positions: [CGFloat] = []
    var length: CGFloat = 0
    /// Every child, and where each starts along the stack.
    var all: [_VariadicView.Children.Element] = []
    var starts: [CGFloat] = []
    /// What the children made cover along the stack, without limit at an
    /// end of the stack they reach; nil when there's no window.
    var extent: ClosedRange<CGFloat>?

    init(root: LazyStackRoot, children: _VariadicView.Children, measurements: LazyStackMeasurements,
         window: ClosedRange<CGFloat>?, edge: ClosedRange<CGFloat>?) {
        let count = children.count
        guard count > 0 else { return }
        let elements = children.map { $0 }
        var starts: [CGFloat] = []
        var lengths: [CGFloat] = []
        starts.reserveCapacity(count)
        lengths.reserveCapacity(count)
        var position: CGFloat = 0
        for (index, element) in elements.enumerated() {
            let length = measurements.length(of: element.id)
            starts.append(position)
            lengths.append(length)
            position += length + (index + 1 < count ? root.spacing : 0)
        }
        length = position
        all = elements
        self.starts = starts

        func overlaps(_ index: Int, _ range: ClosedRange<CGFloat>) -> Bool {
            starts[index] + lengths[index] >= range.lowerBound && starts[index] <= range.upperBound
        }
        var visible: [Int] = []
        let kept = window.map { ($0.lowerBound - LazyStackBody.keepDistance)...($0.upperBound + LazyStackBody.keepDistance) }
        for index in 0..<count {
            guard let window, let kept else {
                visible.append(index)
                continue
            }
            if overlaps(index, window) || (overlaps(index, kept) && measurements.made.contains(elements[index].id)) {
                visible.append(index)
            }
        }
        if window != nil, let first = visible.first, let last = visible.last {
            extent = (first == 0 ? -CGFloat.infinity : starts[first])...(last == count - 1 ? CGFloat.infinity : starts[last] + lengths[last])
        }
        var placed = visible.map { starts[$0] }

        // Pinned headers and footers, made while their section is, placed
        // within it at the viewport's edge, and above the rows.
        var pinnedIndices: [Int] = []
        var pinnedPositions: [CGFloat] = []
        if let edge, !root.pinnedViews.isEmpty {
            for section in RowSection.sections(of: children) {
                let members = [section.header].compactMap { $0 } + section.rows + [section.footer].compactMap { $0 }
                guard let first = members.min(), let last = members.max() else { continue }
                let sectionStart = starts[first], sectionEnd = starts[last] + lengths[last]
                        guard sectionEnd > edge.lowerBound, sectionStart < edge.upperBound else { continue }
                if root.pinnedViews.contains(.sectionHeaders), let header = section.header {
                    let limit = sectionEnd - lengths[header]
                    pinnedIndices.append(header)
                    pinnedPositions.append(min(max(starts[header], edge.lowerBound), limit))
                }
                if root.pinnedViews.contains(.sectionFooters), let footer = section.footer {
                    let floor = sectionStart + (section.header.map { lengths[$0] } ?? 0)
                    pinnedIndices.append(footer)
                    pinnedPositions.append(max(min(starts[footer], edge.upperBound - lengths[footer]), floor))
                }
            }
        }
        for (index, pinned) in zip(pinnedIndices, pinnedPositions) {
            if let found = visible.firstIndex(of: index) {
                visible.remove(at: found)
                placed.remove(at: found)
            }
            visible.append(index)
            placed.append(pinned)
        }
        shown = visible.map { elements[$0] }
        positions = placed
    }
}

// MARK: - Layout

/// Places each child made at its position along the stack, sized to the
/// stack across it and ideally along it, measuring it as it goes.
struct LazyStackLayout: Layout {
    var axis: Axis
    var crossAlignment: LazyStackRoot.CrossAlignment
    var positions: [CGFloat]
    var ids: [AnyHashable]
    var length: CGFloat
    var measurements: LazyStackMeasurements

    func proposal(across: CGFloat?) -> ProposedViewSize {
        axis == .vertical ? ProposedViewSize(width: across, height: nil) : ProposedViewSize(width: nil, height: across)
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let across = axis == .vertical ? proposal.width : proposal.height
        let widest = across ?? subviews.map {
            let size = $0.sizeThatFits(self.proposal(across: nil))
            return axis == .vertical ? size.width : size.height
        }.max() ?? 0
        return axis == .vertical ? CGSize(width: widest, height: length) : CGSize(width: length, height: widest)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        // Bounds unbounded across, as an alignment query may give, leave
        // each child its ideal size there, placed at the leading edge.
        let bounded = axis == .vertical ? bounds.width : bounds.height
        let across: CGFloat? = bounded.isFinite ? bounded : nil
        for (index, subview) in subviews.enumerated() where index < positions.count {
            // A child without a finite size, as one that grows without
            // bound gives with nothing proposed along the stack, counts as
            // none in that direction.
            var size = subview.sizeThatFits(self.proposal(across: across))
            if !size.width.isFinite || !size.height.isFinite {
                size = CGSize(width: size.width.isFinite ? size.width : 0, height: size.height.isFinite ? size.height : 0)
            }
            let along = axis == .vertical ? size.height : size.width
            measurements.record(along, for: ids[index])
            let extent = axis == .vertical ? size.width : size.height
            let cross: CGFloat = if let across, extent.isFinite { switch crossAlignment {
            case .leading: 0
            case .center: (across - extent) / 2
            case .trailing: across - extent
            } } else { 0 }
            let point = axis == .vertical
                ? CGPoint(x: bounds.minX + cross, y: bounds.minY + positions[index])
                : CGPoint(x: bounds.minX + positions[index], y: bounds.minY + cross)
            subview.place(at: point, anchor: .topLeading, proposal: ProposedViewSize(size))
        }
    }
}
#endif
