//
//  ScrollView.swift
//  OpenSwiftUI
//
//  Status: Perry's implementation
//
//  A scroll view in the view graph. A layout proposes the content its
//  viewport's length across the scrolling axes and leaves it its ideal
//  length along them, then places it moved back by the scroll offset; the
//  viewport clips it. A drag moves it, stretching past the ends, and on
//  release it glides to where the drag's velocity carries it, within the
//  content. Being SwiftUI throughout, the content's buttons and gestures are
//  hit where they are drawn.

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
        ScrollViewport(axes: axes, showsIndicators: showsIndicators, content: content)
    }
}

// MARK: - Viewport

/// The sizes the last layout found: the viewport's and the content's.
/// Written by the layout as it places the content, for the drag to scroll
/// within; not state, as a change to it needs no update of its own.
final class ScrollMetrics {
    var viewport: CGSize = .zero
    var content: CGSize = .zero

    /// The furthest the content scrolls along each of `axes`.
    func limit(_ axes: Axis.Set) -> CGSize {
        CGSize(width: axes.contains(.horizontal) ? max(content.width - viewport.width, 0) : 0,
               height: axes.contains(.vertical) ? max(content.height - viewport.height, 0) : 0)
    }
}

struct ScrollViewport<Content: View>: View {
    var axes: Axis.Set
    var showsIndicators: Bool
    var content: Content

    /// How far the content is scrolled: the viewport's origin in it.
    @State private var offset: CGSize = .zero
    /// The offset when the drag under way began.
    @State private var dragOrigin: CGSize?
    @State private var metrics = ScrollMetrics()
    /// Where the content was before it last moved to `offset`, which an
    /// animation may still be carrying it from.
    @State private var previousOffset: CGSize = .zero

    /// How much of a drag past the content's end moves it.
    static var stretch: CGFloat { 0.4 }
    static var indicatorThickness: CGFloat { 3 }

    var body: some View {
        ScrollLayout(axes: axes, offset: offset, clamps: dragOrigin == nil, metrics: metrics) {
            Group {
                if axes == .horizontal {
                    HStack { content }
                } else {
                    VStack { content }
                }
            }
            .coordinateSpace(name: ScrollViewportInfo.contentSpace)
        }
        .environment(\.scrollViewport, viewportInfo)
        .overlay(alignment: .topLeading) { indicators }
        .clipped()
        .contentShape(Rectangle())
        .simultaneousGesture(drag)
    }

    /// The part of the content that shows, or may while an animation moves
    /// it: from where it was to where it is going, and while a drag is under
    /// way, where it was as the drag began.
    var viewportInfo: ScrollViewportInfo {
        var size = metrics.viewport
        if size == .zero { size = ScrollViewportInfo.fallbackSize }
        // While a drag is under way, also what showed as it began: a lazy
        // stack keeps the views the touch began on.
        let offsets = [previousOffset, offset] + (dragOrigin.map { [$0] } ?? [])
        let low = CGSize(width: offsets.map(\.width).min()!, height: offsets.map(\.height).min()!)
        let high = CGSize(width: offsets.map(\.width).max()!, height: offsets.map(\.height).max()!)
        return ScrollViewportInfo(
            visible: CGRect(x: low.width, y: low.height,
                            width: high.width - low.width + size.width, height: high.height - low.height + size.height),
            offset: offset,
            size: size
        )
    }

    // MARK: Scrolling

    var drag: some Gesture {
        DragGesture(minimumDistance: 8)
            .onChanged { value in
                let origin = dragOrigin ?? offset
                if dragOrigin == nil { dragOrigin = offset }
                previousOffset = offset
                offset = stretched(CGSize(width: origin.width - value.translation.width,
                                          height: origin.height - value.translation.height))
            }
            .onEnded { value in
                let origin = dragOrigin ?? offset
                let target = clamp(CGSize(width: origin.width - value.predictedEndTranslation.width,
                                          height: origin.height - value.predictedEndTranslation.height))
                previousOffset = offset
                withAnimation(.easeOut(duration: 0.4)) {
                    offset = target
                    dragOrigin = nil
                }
            }
    }

    /// The offset along the scrolling axes, within the content.
    func clamp(_ proposed: CGSize) -> CGSize {
        let limit = metrics.limit(axes)
        return CGSize(width: min(max(proposed.width, 0), limit.width),
                      height: min(max(proposed.height, 0), limit.height))
    }

    /// The offset along the scrolling axes, moving a fraction of the way
    /// past the content's ends.
    func stretched(_ proposed: CGSize) -> CGSize {
        let limit = metrics.limit(axes)
        func axis(_ value: CGFloat, _ limit: CGFloat) -> CGFloat {
            if value < 0 { return value * Self.stretch }
            if value > limit { return limit + (value - limit) * Self.stretch }
            return value
        }
        return CGSize(width: axes.contains(.horizontal) ? axis(proposed.width, limit.width) : 0,
                      height: axes.contains(.vertical) ? axis(proposed.height, limit.height) : 0)
    }

    // MARK: Indicators

    /// While dragging, a bar along each scrolling axis whose length and
    /// place show the viewport's in the content.
    @ViewBuilder
    var indicators: some View {
        if showsIndicators, dragOrigin != nil {
            let size = metrics.viewport, content = metrics.content, limit = metrics.limit(axes)
            ZStack(alignment: .topLeading) {
                if axes.contains(.vertical), content.height > size.height {
                    let length = max(size.height * size.height / content.height, 24)
                    let position = (size.height - length) * min(max(offset.height / max(limit.height, 1), 0), 1)
                    Capsule()
                        .fill(Color.gray.opacity(0.6))
                        .frame(width: Self.indicatorThickness, height: length)
                        .modifier(_OffsetEffect(offset: CGSize(width: size.width - Self.indicatorThickness - 3, height: position)))
                }
                if axes.contains(.horizontal), content.width > size.width {
                    let length = max(size.width * size.width / content.width, 24)
                    let position = (size.width - length) * min(max(offset.width / max(limit.width, 1), 0), 1)
                    Capsule()
                        .fill(Color.gray.opacity(0.6))
                        .frame(width: length, height: Self.indicatorThickness)
                        .modifier(_OffsetEffect(offset: CGSize(width: position, height: size.height - Self.indicatorThickness - 3)))
                }
            }
            .frame(width: size.width, height: size.height, alignment: .topLeading)
            .allowsHitTesting(false)
        }
    }
}

// MARK: - Viewport

/// What of a scroll view's content shows, in the content's coordinate space,
/// for lazy stacks to make only what is near it.
struct ScrollViewportInfo: Equatable {
    /// The content's coordinate space's name.
    static let contentSpace = "org.perry.ScrollView.content"
    /// An iPhone's screen, until the viewport is first laid out.
    static let fallbackSize = CGSize(width: 390, height: 844)

    /// The region that shows, or will while the content moves.
    var visible: CGRect
    /// How far the content is scrolled.
    var offset: CGSize
    /// The viewport's size.
    var size: CGSize
}

struct ScrollViewportKey: EnvironmentKey {
    static let defaultValue: ScrollViewportInfo? = nil
}

extension EnvironmentValues {
    var scrollViewport: ScrollViewportInfo? {
        get { self[ScrollViewportKey.self] }
        set { self[ScrollViewportKey.self] = newValue }
    }
}

// MARK: - Layout

/// Takes the space offered, and places its content — sized to the space
/// across the scrolling axes and ideally along them — moved back by the
/// offset; centered across a vertical scroll when narrower than it.
struct ScrollLayout: Layout {
    var axes: Axis.Set
    var offset: CGSize
    /// Whether to keep the offset within the content, as when no drag is
    /// stretching it past the ends.
    var clamps: Bool
    var metrics: ScrollMetrics

    var animatableData: CGSize.AnimatableData {
        get { offset.animatableData }
        set { offset.animatableData = newValue }
    }

    func contentProposal(_ viewport: CGSize) -> ProposedViewSize {
        ProposedViewSize(width: axes.contains(.horizontal) ? nil : viewport.width,
                         height: axes.contains(.vertical) ? nil : viewport.height)
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard proposal.width == nil || proposal.height == nil else {
            return CGSize(width: proposal.width!, height: proposal.height!)
        }
        let ideal = subviews.first?.sizeThatFits(ProposedViewSize(width: proposal.width, height: proposal.height)) ?? .zero
        return CGSize(width: proposal.width ?? ideal.width, height: proposal.height ?? ideal.height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard let content = subviews.first else { return }
        let size = content.sizeThatFits(contentProposal(bounds.size))
        metrics.viewport = bounds.size
        metrics.content = size
        var offset = offset
        if clamps {
            let limit = metrics.limit(axes)
            offset = CGSize(width: min(max(offset.width, 0), limit.width), height: min(max(offset.height, 0), limit.height))
        }
        var origin = CGPoint(x: bounds.minX - offset.width, y: bounds.minY - offset.height)
        if !axes.contains(.horizontal), size.width < bounds.width {
            origin.x += (bounds.width - size.width) / 2
        }
        content.place(at: origin, anchor: .topLeading, proposal: ProposedViewSize(size))
    }
}
#endif
