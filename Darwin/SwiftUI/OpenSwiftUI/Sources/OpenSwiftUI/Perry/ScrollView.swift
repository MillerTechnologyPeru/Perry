//
//  ScrollView.swift
//  OpenSwiftUI
//
//  Status: Perry's implementation
//
//  A scroll view in the view graph. A layout proposes the content its
//  viewport's length across the scrolling axes and leaves it its ideal
//  length along them, then places it moved back by the scroll offset; the
//  viewport clips it. A pan moves it, stretching past the ends, and on
//  release it glides to where the pan's velocity carries it, within the
//  content. The pan is UIKit's, on the hosting view, as a scroll view's is:
//  once it begins, the content's SwiftUI gestures (a button's press, say)
//  are cancelled. The content stays in the view graph, so its buttons and
//  gestures are hit where they are drawn.

#if os(iOS) || os(visionOS)
public import OpenSwiftUICore
import UIKit

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
    /// Whether the refresh action a pull started is running.
    @State private var refreshing = false
    @Environment(\.refreshAction) private var refresh
    /// The reader the scroll view is in, and its way to scroll for it.
    @Environment(\.scrollRegistry) private var registry
    @State private var scroller = ScrollTargetScroller()
    /// The indicators' opacity: shown while scrolling, then faded out.
    @State private var indicatorOpacity: Double = 0
    /// Counts scrolls, so an indicator fade only follows the last one.
    @State private var scrollCount = 0
    /// Where the content was before it last moved to `offset`, which an
    /// animation may still be carrying it from.
    @State private var previousOffset: CGSize = .zero

    /// How much of a drag past the content's end moves it.
    static var stretch: CGFloat { 0.4 }
    static var indicatorThickness: CGFloat { 3 }

    var body: some View {
        ScrollLayout(axes: axes, offset: offset, clamps: dragOrigin == nil && !refreshing, metrics: metrics) {
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
        .environment(\.scrollTargetScroller, prepareScroller())
        .overlay(alignment: .top) { refreshIndicator }
        .overlay(alignment: .topLeading) { indicators }
        .clipped()
        .background(
            ScrollPanRecognizer(
                axes: axes,
                changed: { panChanged($0) },
                ended: { panEnded($0, velocity: $1) }
            )
        )
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

    /// The scroller targets are found through, kept up to date with the
    /// viewport, and in the reader the scroll view is in.
    func prepareScroller() -> ScrollTargetScroller {
        let scroller = scroller
        let offset = $offset, previous = $previousOffset, metrics = metrics
        scroller.axes = axes
        scroller.current = { (metrics.viewport, offset.wrappedValue) }
        scroller.move = { target in
            previous.wrappedValue = offset.wrappedValue
            offset.wrappedValue = clamp(target)
            showIndicators()
        }
        registry?.register(scroller)
        return scroller
    }

    /// Shows the indicators, and fades them out once scrolling stops.
    func showIndicators() {
        indicatorOpacity = 1
        scrollCount &+= 1
        let count = scrollCount, current = $scrollCount, opacity = $indicatorOpacity
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 800_000_000)
            guard current.wrappedValue == count else { return }
            withAnimation(.easeOut(duration: 0.3)) { opacity.wrappedValue = 0 }
        }
    }

    /// The pan's translation moves the content from where it was as the
    /// pan began, stretching past the ends.
    func panChanged(_ translation: CGSize) {
        if indicatorOpacity != 1 { indicatorOpacity = 1 }
        let origin = dragOrigin ?? offset
        if dragOrigin == nil { dragOrigin = offset }
        previousOffset = offset
        offset = stretched(CGSize(width: origin.width - translation.width, height: origin.height - translation.height))
    }

    /// On release the content glides as far as the pan's velocity carries
    /// it, within the content; pulled down far enough, in a scroll view
    /// with a refresh action, it holds below its top while the action runs.
    func panEnded(_ translation: CGSize, velocity: CGSize) {
        let origin = dragOrigin ?? offset
        if let refresh, axes.contains(.vertical), !refreshing, offset.height <= -Self.refreshPull {
            refreshing = true
            previousOffset = offset
            withAnimation(.easeOut(duration: 0.25)) {
                offset = CGSize(width: 0, height: -Self.refreshHold)
                dragOrigin = nil
            }
            Task { @MainActor in
                await refresh()
                refreshing = false
                withAnimation(.easeOut(duration: 0.3)) { offset = .zero }
            }
            return
        }
        let carry = Self.carry
        let target = clamp(CGSize(width: origin.width - translation.width - velocity.width * carry,
                                  height: origin.height - translation.height - velocity.height * carry))
        previousOffset = offset
        withAnimation(.easeOut(duration: 0.5)) {
            offset = target
            dragOrigin = nil
        }
        showIndicators()
    }

    /// Seconds of release velocity the content glides on for.
    static var carry: CGFloat { 0.3 }

    /// How far past its top the content is pulled to refresh, and where it
    /// holds while refreshing.
    static var refreshPull: CGFloat { 50 }
    static var refreshHold: CGFloat { 56 }

    /// A spinner above the content while it's pulled down or refreshing.
    @ViewBuilder
    var refreshIndicator: some View {
        if refresh != nil, axes.contains(.vertical), refreshing || offset.height < 0 {
            ProgressView()
                .frame(height: max(-offset.height, 0))
                .opacity(refreshing ? 1 : min(Double(-offset.height / Self.refreshPull), 1))
                .allowsHitTesting(false)
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

    /// While scrolling, a bar along each scrolling axis whose length and
    /// place show the viewport's in the content; they fade once it stops.
    @ViewBuilder
    var indicators: some View {
        if showsIndicators {
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
            .opacity(indicatorOpacity)
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
// MARK: - Pan

/// Installs a pan recognizer on the hosting view for the viewport it's the
/// background of. The pan begins for a touch in the viewport moving along
/// its axes, unless a smaller scroll viewport holds the touch too.
struct ScrollPanRecognizer: UIViewRepresentable {
    var axes: Axis.Set
    var changed: (CGSize) -> Void
    var ended: (CGSize, CGSize) -> Void

    func makeUIView(context: Context) -> ScrollPanAnchor {
        let anchor = ScrollPanAnchor()
        anchor.isUserInteractionEnabled = false
        anchor.coordinator = context.coordinator
        context.coordinator.anchor = anchor
        return anchor
    }

    func updateUIView(_ anchor: ScrollPanAnchor, context: Context) {
        let coordinator = context.coordinator
        (coordinator.axes, coordinator.changed, coordinator.ended) = (axes, changed, ended)
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        weak var anchor: UIView?
        var axes: Axis.Set = .vertical
        var changed: (CGSize) -> Void = { _ in }
        var ended: (CGSize, CGSize) -> Void = { _, _ in }
        private(set) lazy var recognizer: UIPanGestureRecognizer = {
            let recognizer = UIPanGestureRecognizer(target: self, action: #selector(pan(_:)))
            recognizer.delegate = self
            made = true
            return recognizer
        }()
        private var made = false

        /// The recognizer goes with its coordinator: it doesn't retain its
        /// target, and left on the hosting view it would send its action
        /// to the freed coordinator.
        deinit {
            guard made else { return }
            let recognizer = recognizer
            recognizer.removeTarget(nil, action: nil)
            recognizer.view?.removeGestureRecognizer(recognizer)
            Coordinator.installed[ObjectIdentifier(self)] = nil
        }

        /// The coordinators whose viewports are in a window.
        nonisolated(unsafe) static var installed: [ObjectIdentifier: Weak] = [:]

        struct Weak { weak var coordinator: Coordinator? }

        func install(on host: UIView?) {
            recognizer.view?.removeGestureRecognizer(recognizer)
            Coordinator.installed[ObjectIdentifier(self)] = nil
            guard let host else { return }
            host.addGestureRecognizer(recognizer)
            Coordinator.installed[ObjectIdentifier(self)] = Weak(coordinator: self)
        }

        /// Whether this viewport holds the window point and scrolls the way
        /// the pan moves.
        func accepts(_ point: CGPoint, horizontal: Bool) -> Bool {
            guard let anchor, anchor.window != nil else { return false }
            guard anchor.bounds.contains(anchor.convert(point, from: nil)) else { return false }
            return axes.contains(horizontal ? .horizontal : .vertical)
        }

        var area: CGFloat { (anchor?.bounds.width ?? 0) * (anchor?.bounds.height ?? 0) }

        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            guard let pan = gestureRecognizer as? UIPanGestureRecognizer else { return false }
            let point = pan.location(in: nil)
            let moved = pan.translation(in: nil)
            let horizontal = abs(moved.x) > abs(moved.y)
            guard accepts(point, horizontal: horizontal) else { return false }
            // The innermost scroll view that scrolls this way takes the pan.
            let area = self.area
            for entry in Coordinator.installed.values {
                guard let other = entry.coordinator, other !== self, other.accepts(point, horizontal: horizontal) else { continue }
                if other.area < area { return false }
            }
            return true
        }

        @objc func pan(_ recognizer: UIPanGestureRecognizer) {
            let translation = recognizer.translation(in: nil)
            let moved = CGSize(width: axes.contains(.horizontal) ? translation.x : 0,
                               height: axes.contains(.vertical) ? translation.y : 0)
            switch recognizer.state {
            case .began, .changed:
                changed(moved)
            case .ended:
                let velocity = recognizer.velocity(in: nil)
                ended(moved, CGSize(width: axes.contains(.horizontal) ? velocity.x : 0,
                                    height: axes.contains(.vertical) ? velocity.y : 0))
            case .cancelled, .failed:
                ended(moved, .zero)
            default:
                break
            }
        }
    }
}

/// The viewport's stand-in in UIKit, which puts its coordinator's pan on
/// the hosting view while it's in a window.
final class ScrollPanAnchor: UIView {
    weak var coordinator: ScrollPanRecognizer.Coordinator?

    override func didMoveToWindow() {
        super.didMoveToWindow()
        guard window != nil else {
            coordinator?.install(on: nil)
            return
        }
        var host: UIView? = superview
        while let view = host, !(view is AnyUIHostingView) { host = view.superview }
        coordinator?.install(on: host)
    }
}
#endif
