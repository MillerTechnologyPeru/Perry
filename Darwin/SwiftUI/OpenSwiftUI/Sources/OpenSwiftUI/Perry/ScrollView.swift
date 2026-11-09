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

/// With PERRY_SWIFTUI_TRACE set, what scroll views do, on standard error.
func scrollTrace(_ message: @autoclosure () -> String) {
    guard getenv("PERRY_SWIFTUI_TRACE") != nil else { return }
    fputs("perry: SwiftUI: scroll: \(message())\n", stderr)
}

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
    @State private var position = ScrollPosition()
    /// How far the content is pulled past its top.
    @State private var pulled: CGFloat = 0
    @State private var metrics = ScrollMetrics()
    /// Whether the refresh action a pull started is running.
    @State private var refreshing = false
    @Environment(\.refreshAction) private var refresh
    /// The reader the scroll view is in, and its way to scroll for it.
    @Environment(\.scrollRegistry) private var registry
    @State private var scroller = ScrollTargetScroller()
    /// Counts scrolls, so an indicator fade only follows the last one.
    @State private var scrollCount = 0
    @State private var viewport = ScrollViewportSource()

    var body: some View {
        ScrollLayout(axes: axes, metrics: metrics) {
            Group {
                if axes == .horizontal {
                    HStack { content }
                } else {
                    VStack { content }
                }
            }
            .coordinateSpace(name: ScrollViewportInfo.contentSpace)
            .modifier(ScrollOffsetModifier(axes: axes, position: position, refreshing: refreshing, metrics: metrics, viewport: viewport))
        }
        .environment(\.scrollViewport, viewport)
        .environment(\.scrollTargetScroller, prepareScroller())
        .overlay(alignment: .top) { refreshIndicator }
        .overlay(alignment: .topLeading) {
            if showsIndicators {
                ScrollIndicators(axes: axes, metrics: metrics, position: position)
            }
        }
        .clipped()
        .background(
            ScrollPanRecognizer(
                axes: axes,
                changed: { panChanged($0) },
                ended: { panEnded($0, velocity: $1) }
            )
        )
    }

    // MARK: Scrolling

    /// The scroller targets are found through, kept up to date with the
    /// viewport, and in the reader the scroll view is in.
    func prepareScroller() -> ScrollTargetScroller {
        let scroller = scroller
        let position = position, metrics = metrics
        scroller.axes = axes
        scroller.current = { (metrics.viewport, position.offset) }
        scroller.move = { target in
            position.offset = clamp(target)
            showIndicators()
        }
        registry?.register(scroller)
        return scroller
    }

    /// Shows the indicators, and fades them out once scrolling stops.
    func showIndicators() {
        position.indicatorOpacity = 1
        scrollCount &+= 1
        let count = scrollCount, current = $scrollCount, position = position
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 800_000_000)
            guard current.wrappedValue == count else { return }
            withAnimation(.easeOut(duration: 0.3)) { position.indicatorOpacity = 0 }
        }
    }

    /// Moves the content, and what shows how far it's pulled past its top.
    func move(to offset: CGSize) {
        position.offset = offset
        let pull = max(-offset.height, 0)
        if pulled != pull { pulled = pull }
    }

    /// The pan's translation moves the content from where it was as the
    /// pan began, stretching past the ends.
    func panChanged(_ translation: CGSize) {
        scrollTrace("pan changed \(translation) limit \(metrics.limit(axes)) viewport \(metrics.viewport) content \(metrics.content)")
        position.indicatorOpacity = 1
        let origin = position.dragOrigin ?? position.offset
        position.dragOrigin = origin
        move(to: stretched(CGSize(width: origin.width - translation.width, height: origin.height - translation.height)))
    }

    /// On release the content glides as far as the pan's velocity carries
    /// it, within the content; pulled down far enough, in a scroll view
    /// with a refresh action, it holds below its top while the action runs.
    func panEnded(_ translation: CGSize, velocity: CGSize) {
        let offset = position.offset
        if let refresh, axes.contains(.vertical), !refreshing, offset.height <= -Self.refreshPull {
            refreshing = true
            withAnimation(.easeOut(duration: 0.25)) {
                move(to: CGSize(width: 0, height: -Self.refreshHold))
                position.dragOrigin = nil
            }
            Task { @MainActor in
                await refresh()
                refreshing = false
                withAnimation(.easeOut(duration: 0.3)) { move(to: .zero) }
            }
            return
        }
        // Let go past an end, the content springs back; otherwise it
        // coasts as far as the flick carries it, slowing as UIKit's scroll
        // views (the shared physics) do, and stops at the content's ends.
        let limit = metrics.limit(axes)
        let rest = clamp(offset)
        if rest != offset {
            withAnimation(.spring(response: SpringBack.response, dampingFraction: 1)) {
                move(to: rest)
                position.dragOrigin = nil
            }
            showIndicators()
            return
        }
        var target = offset, duration = 0.0
        for axis in [Axis.horizontal, .vertical] where axes.contains(axis) {
            let horizontal = axis == .horizontal
            let speed = Double(horizontal ? velocity.width : velocity.height)
            // The content moves against the finger.
            guard let glide = Deceleration.glide(velocity: -speed) else { continue }
            let from = horizontal ? offset.width : offset.height, end = horizontal ? limit.width : limit.height
            let to = min(max(from + CGFloat(glide.distance), 0), end)
            let share = glide.distance == 0 ? 0 : Double((to - from) / CGFloat(glide.distance))
            duration = max(duration, glide.duration * max(share, 0.2))
            if horizontal { target.width = to } else { target.height = to }
        }
        if duration > 0 {
            withAnimation(.timingCurve(0.12, 0.5, 0.2, 1, duration: duration)) {
                move(to: target)
                position.dragOrigin = nil
            }
        } else {
            position.dragOrigin = nil
        }
        showIndicators()
    }

    /// How far past its top the content is pulled to refresh, and where it
    /// holds while refreshing.
    static var refreshPull: CGFloat { 50 }
    static var refreshHold: CGFloat { 56 }

    /// A spinner above the content while it's pulled down or refreshing.
    @ViewBuilder
    var refreshIndicator: some View {
        if refresh != nil, axes.contains(.vertical), refreshing || pulled > 0 {
            ProgressView()
                .frame(height: pulled)
                .opacity(refreshing ? 1 : min(Double(pulled / Self.refreshPull), 1))
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
        let limit = metrics.limit(axes), size = metrics.viewport
        func axis(_ value: CGFloat, _ limit: CGFloat, _ dimension: CGFloat) -> CGFloat {
            CGFloat(rubberBand(Double(value), low: 0, high: Double(limit), dimension: Double(dimension)))
        }
        return CGSize(width: axes.contains(.horizontal) ? axis(proposed.width, limit.width, size.width) : 0,
                      height: axes.contains(.vertical) ? axis(proposed.height, limit.height, size.height) : 0)
    }

}

// MARK: - What follows the offset

// The offset changes every frame of a drag, and a binding's reader has the
// view with the state update too. So it's kept in an object, and each view
// that shows it has its own copy as state: only they update as it moves, and
// not the scroll view and all it holds.

/// How far a scroll view's content is scrolled, and who follows it.
final class ScrollPosition {
    var offset: CGSize = .zero {
        didSet { if offset != oldValue { notify() } }
    }
    /// The scroll bars' opacity: shown while scrolling, then faded out.
    var indicatorOpacity: Double = 0 {
        didSet { if indicatorOpacity != oldValue { notify() } }
    }
    /// The offset when the drag under way began.
    var dragOrigin: CGSize?

    private func notify() {
        for follower in followers.values { follower(self) }
    }

    private var followers: [Int: (ScrollPosition) -> Void] = [:]
    private var nextFollower = 0

    func follow(_ follower: @escaping (ScrollPosition) -> Void) -> Int {
        nextFollower += 1
        followers[nextFollower] = follower
        return nextFollower
    }

    func unfollow(_ follower: Int?) {
        if let follower { followers[follower] = nil }
    }
}

/// Keeps `offset`, a view's state, with the position while it shows.
struct ScrollPositionFollower: ViewModifier {
    var position: ScrollPosition
    @Binding var offset: CGSize
    var opacity: Binding<Double>?
    @State private var follower: Int?

    func body(content: Content) -> some View {
        content
            .onAppear {
                let offset = $offset, opacity = opacity
                let follow = { (position: ScrollPosition) in
                    offset.wrappedValue = position.offset
                    opacity?.wrappedValue = position.indicatorOpacity
                }
                follower = position.follow(follow)
                follow(position)
            }
            .onDisappear {
                position.unfollow(follower)
                follower = nil
            }
    }
}

/// Moves the content by the offset.
struct ScrollOffsetModifier: ViewModifier {
    var axes: Axis.Set
    var position: ScrollPosition
    var refreshing: Bool
    var metrics: ScrollMetrics
    var viewport: ScrollViewportSource
    @State private var offset: CGSize = .zero

    func body(content: Content) -> some View {
        let effect = ScrollOffsetEffect(axes: axes, offset: offset, position: position, refreshing: refreshing, metrics: metrics, viewport: viewport)
        // Lazy stacks need to know what shows before the first layout.
        let _ = viewport.begin(effect.info(at: effect.offset))
        content.modifier(effect).modifier(ScrollPositionFollower(position: position, offset: $offset))
    }
}

/// While scrolling, a bar along each scrolling axis whose length and place
/// show the viewport's in the content; they fade once it stops.
struct ScrollIndicators: View {
    var axes: Axis.Set
    var metrics: ScrollMetrics
    var position: ScrollPosition
    @State private var offset: CGSize = .zero
    @State private var opacity: Double = 0

    static var thickness: CGFloat { 3 }

    var body: some View {
        let size = metrics.viewport, content = metrics.content, limit = metrics.limit(axes)
        ZStack(alignment: .topLeading) {
            if axes.contains(.vertical), content.height > size.height {
                let length = max(size.height * size.height / content.height, 24)
                let position = (size.height - length) * min(max(offset.height / max(limit.height, 1), 0), 1)
                Capsule()
                    .fill(Color.gray.opacity(0.6))
                    .frame(width: Self.thickness, height: length)
                    .modifier(_OffsetEffect(offset: CGSize(width: size.width - Self.thickness - 3, height: position)))
            }
            if axes.contains(.horizontal), content.width > size.width {
                let length = max(size.width * size.width / content.width, 24)
                let position = (size.width - length) * min(max(offset.width / max(limit.width, 1), 0), 1)
                Capsule()
                    .fill(Color.gray.opacity(0.6))
                    .frame(width: length, height: Self.thickness)
                    .modifier(_OffsetEffect(offset: CGSize(width: position, height: size.height - Self.thickness - 3)))
            }
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
        .opacity(opacity)
        .allowsHitTesting(false)
        .modifier(ScrollPositionFollower(position: position, offset: $offset, opacity: $opacity))
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

    /// The region that shows, and what showed as a drag under way began.
    var visible: CGRect
    /// How far the content is scrolled.
    var offset: CGSize
    /// The viewport's size.
    var size: CGSize
}

/// Where a scroll view's viewport is, for lazy stacks. It is one object
/// through the scroll view's life, as a value that changed with each scrolled
/// frame would change the environment of every view in the content.
final class ScrollViewportSource {
    private(set) var info: ScrollViewportInfo?
    private var stacks: [ObjectIdentifier: LazyStackMeasurements] = [:]

    /// The first report, before anything is laid out.
    func begin(_ info: ScrollViewportInfo) {
        if self.info == nil { self.info = info }
    }

    func update(_ info: ScrollViewportInfo) {
        guard info != self.info else { return }
        self.info = info
        for stack in stacks.values { stack.viewportMoved(info) }
    }

    func add(_ stack: LazyStackMeasurements) { stacks[ObjectIdentifier(stack)] = stack }
    func remove(_ stack: LazyStackMeasurements) { stacks[ObjectIdentifier(stack)] = nil }
}

struct ScrollViewportKey: EnvironmentKey {
    static let defaultValue: ScrollViewportSource? = nil
}

extension EnvironmentValues {
    var scrollViewport: ScrollViewportSource? {
        get { self[ScrollViewportKey.self] }
        set { self[ScrollViewportKey.self] = newValue }
    }
}

// MARK: - Layout

/// Moves the content back by the offset. An effect, not part of the
/// layout, as an offset that changed the layout would have every view above
/// the scroll view laid out again, and the content measured, each frame. It
/// is worked out each frame an animation moves the content, so lazy stacks
/// hear from it where the content really is.
struct ScrollOffsetEffect: GeometryEffect {
    var axes: Axis.Set
    var offset: CGSize
    var position: ScrollPosition
    var refreshing: Bool
    var metrics: ScrollMetrics
    var viewport: ScrollViewportSource

    var animatableData: CGSize.AnimatableData {
        get { offset.animatableData }
        set { offset.animatableData = newValue }
    }

    func info(at offset: CGSize) -> ScrollViewportInfo {
        var size = metrics.viewport
        if size == .zero { size = ScrollViewportInfo.fallbackSize }
        // Also what showed as a drag under way began: a lazy stack keeps
        // the views the touch began on.
        let offsets = [offset] + (position.dragOrigin.map { [$0] } ?? [])
        let low = CGSize(width: offsets.map(\.width).min()!, height: offsets.map(\.height).min()!)
        let high = CGSize(width: offsets.map(\.width).max()!, height: offsets.map(\.height).max()!)
        return ScrollViewportInfo(
            visible: CGRect(x: low.width, y: low.height,
                            width: high.width - low.width + size.width, height: high.height - low.height + size.height),
            offset: offset,
            size: size
        )
    }

    func effectValue(size: CGSize) -> ProjectionTransform {
        var offset = offset
        // A drag or a refresh may hold it past the ends.
        if position.dragOrigin == nil, !refreshing {
            let limit = metrics.limit(axes)
            offset = CGSize(width: min(max(offset.width, 0), limit.width), height: min(max(offset.height, 0), limit.height))
        }
        viewport.update(info(at: offset))
        return ProjectionTransform(CGAffineTransform(translationX: -offset.width, y: -offset.height))
    }
}

/// Takes the space offered, and places its content, sized to the space
/// across the scrolling axes and ideally along them; centered across a
/// vertical scroll when narrower than it.
struct ScrollLayout: Layout {
    var axes: Axis.Set
    var metrics: ScrollMetrics

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

    // The content's alignment guides stay in the scroll view, as they move
    // with it. Answering would place it for each query, at sizes that aren't
    // the viewport's.
    func explicitAlignment(of guide: HorizontalAlignment, in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGFloat? { nil }
    func explicitAlignment(of guide: VerticalAlignment, in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGFloat? { nil }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard let content = subviews.first else { return }
        let size = content.sizeThatFits(contentProposal(bounds.size))
        metrics.viewport = bounds.size
        metrics.content = size
        scrollTrace("placed viewport \(bounds.size) content \(size)")
        var origin = bounds.origin
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
