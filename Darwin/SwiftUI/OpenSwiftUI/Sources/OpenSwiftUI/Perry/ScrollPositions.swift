//
//  ScrollPositions.swift
//  OpenSwiftUI
//
//  Status: Perry's implementation
//
//  Scroll positions, scroll phases and what views ask of the scroll view
//  around them: default anchors, edge effects, scroll transitions, and
//  actions on geometry, phase and visibility changes. Perry's scroll views
//  scroll freely and report nothing back: a position remembers the edge or
//  point it was told and scrolls nowhere, the actions are never called, and
//  views with these modifiers draw as they are.

#if os(iOS) || os(visionOS)
public import Foundation
public import OpenSwiftUICore

// MARK: - Scroll position

// The scroll view's own offset is kept in a class of the same name in this
// module, so the position type is written with its module here.

@available(OpenSwiftUI_v1_0, *)
extension OpenSwiftUICore.ScrollPosition {
    /// Creates a position that leaves the scroll view where it is, for
    /// views identified by `idType`.
    public init(idType: (some Hashable & Sendable).Type = Never.self) {
        self.init()
    }

    /// Creates a position at an edge of the content, for views identified
    /// by `idType`.
    public init(idType: (some Hashable & Sendable).Type = Never.self, edge: Edge) {
        self.init()
        requestedEdge = edge
    }
}

@available(OpenSwiftUI_v1_0, *)
extension OpenSwiftUICore.ScrollPosition {
    /// Asks for the view with `id` to be scrolled to. Views aren't found by
    /// their identity yet, so the position only forgets its edge and point.
    public mutating func scrollTo(id: some Hashable & Sendable, anchor: UnitPoint? = nil) {
        requestedEdge = nil
        requestedPoint = nil
    }

    /// Asks for an edge of the content to be scrolled to.
    public mutating func scrollTo(edge: Edge) {
        requestedEdge = edge
        requestedPoint = nil
    }

    /// Asks for a point of the content to be scrolled to.
    public mutating func scrollTo(point: CGPoint) {
        requestedEdge = nil
        requestedPoint = point
    }

    /// Asks for a vertical offset to be scrolled to, keeping the horizontal
    /// one last asked for.
    public mutating func scrollTo(y: CGFloat) {
        requestedPoint = CGPoint(x: requestedPoint?.x ?? 0, y: y)
        requestedEdge = nil
    }
}

@available(OpenSwiftUI_v1_0, *)
extension OpenSwiftUICore.ScrollPosition {
    /// The edge the position was last told to scroll to, if that is how it
    /// was positioned.
    public var edge: Edge? { requestedEdge }

    /// The point the position was last told to scroll to, if that is how it
    /// was positioned.
    public var point: CGPoint? { requestedPoint }
}

@available(OpenSwiftUI_v1_0, *)
extension View {
    /// Ties a scroll view inside this view to a position: neither follows
    /// the other yet.
    nonisolated public func scrollPosition(_ position: Binding<OpenSwiftUICore.ScrollPosition>, anchor: UnitPoint? = nil) -> some View {
        self
    }
}

// MARK: - Default anchors

/// What a default scroll anchor is used for.
@available(OpenSwiftUI_v1_0, *)
public struct ScrollAnchorRole: Hashable, Sendable {
    enum Role: Hashable, Sendable { case initialOffset, sizeChanges, alignment }
    var role: Role

    /// The anchor that places the content when the scroll view first shows.
    public static var initialOffset: ScrollAnchorRole { ScrollAnchorRole(role: .initialOffset) }

    /// The anchor that keeps its place when the content or the scroll view
    /// changes size.
    public static var sizeChanges: ScrollAnchorRole { ScrollAnchorRole(role: .sizeChanges) }

    /// The anchor that aligns content smaller than the scroll view.
    public static var alignment: ScrollAnchorRole { ScrollAnchorRole(role: .alignment) }
}

@available(OpenSwiftUI_v1_0, *)
extension View {
    /// Sets where scroll views inside this view start and what they hold
    /// on to: they start at the top leading corner.
    nonisolated public func defaultScrollAnchor(_ anchor: UnitPoint?) -> some View {
        self
    }

    /// Sets the anchor scroll views inside this view use for one role:
    /// none of the roles has an effect yet.
    nonisolated public func defaultScrollAnchor(_ anchor: UnitPoint?, for role: ScrollAnchorRole) -> some View {
        self
    }
}

// MARK: - Edge effects

/// How a scroll view treats content passing under its edges.
@available(OpenSwiftUI_v1_0, *)
public struct ScrollEdgeEffectStyle: Hashable, Sendable {
    enum Role: Hashable, Sendable { case automatic, hard, soft }
    var role: Role

    /// The platform's choice of edge effect.
    public static var automatic: ScrollEdgeEffectStyle { ScrollEdgeEffectStyle(role: .automatic) }

    /// An edge effect with a sharp cutoff.
    public static var hard: ScrollEdgeEffectStyle { ScrollEdgeEffectStyle(role: .hard) }

    /// An edge effect that fades content out gradually.
    public static var soft: ScrollEdgeEffectStyle { ScrollEdgeEffectStyle(role: .soft) }
}

@available(OpenSwiftUI_v1_0, *)
extension View {
    /// Sets the edge effect of scroll views inside this view: Perry's
    /// scroll views draw none.
    nonisolated public func scrollEdgeEffectStyle(_ style: ScrollEdgeEffectStyle?, for edges: Edge.Set) -> some View {
        self
    }

    /// Hides the edge effect of scroll views inside this view: there is
    /// none to hide.
    nonisolated public func scrollEdgeEffectHidden(_ hidden: Bool = true, for edges: Edge.Set = .all) -> some View {
        self
    }
}

// MARK: - Scroll phases

/// What a scroll view is doing: at rest, following a finger, or moving on
/// its own.
@available(OpenSwiftUI_v1_0, *)
@frozen
public enum ScrollPhase: Hashable, Sendable {
    /// Nothing is scrolling.
    case idle
    /// A finger is down and may begin to scroll.
    case tracking
    /// A finger is scrolling the content.
    case interacting
    /// The content is coasting after a finger let go.
    case decelerating
    /// The content is animating to a position it was sent to.
    case animating
}

/// What a scroll view was like when its phase changed.
@available(OpenSwiftUI_v1_0, *)
public struct ScrollPhaseChangeContext {
    var scrollGeometry: ScrollGeometry

    /// The scroll view's geometry at the change.
    public var geometry: ScrollGeometry { scrollGeometry }
}

@available(*, unavailable)
extension ScrollPhaseChangeContext: Sendable {}

@available(OpenSwiftUI_v1_0, *)
extension View {
    /// Adds an action for when a scroll view's phase changes. Perry's
    /// scroll views report no phases, so the action isn't called.
    nonisolated public func onScrollPhaseChange(_ action: @escaping (_ oldPhase: ScrollPhase, _ newPhase: ScrollPhase) -> Void) -> some View {
        self
    }

    /// Adds an action for when a scroll view's phase changes, with the
    /// scroll view's state at the change: not called, as above.
    nonisolated public func onScrollPhaseChange(_ action: @escaping (_ oldPhase: ScrollPhase, _ newPhase: ScrollPhase, _ context: ScrollPhaseChangeContext) -> Void) -> some View {
        self
    }

    /// Adds an action for when a value made from a scroll view's geometry
    /// changes. The geometry isn't reported, so neither closure is called.
    nonisolated public func onScrollGeometryChange<T>(for type: T.Type, of transform: @escaping (ScrollGeometry) -> T, action: @escaping (_ oldValue: T, _ newValue: T) -> Void) -> some View where T: Equatable {
        self
    }

    /// Adds an action for when this view scrolls into or out of sight by
    /// `threshold` of its area. What a scroll view shows isn't tracked, so
    /// the action isn't called.
    nonisolated public func onScrollVisibilityChange(threshold: Double = 0.5, _ action: @escaping (Bool) -> Void) -> some View {
        self
    }
}

// MARK: - Scroll transitions

/// How a scroll transition moves between its phases.
@available(OpenSwiftUI_v1_0, *)
public struct ScrollTransitionConfiguration {
    enum Mode { case interactive, animated, identity }
    var mode: Mode

    /// A transition that follows the scroll offset as the view crosses the
    /// scroll view's edge.
    public static var interactive: ScrollTransitionConfiguration { ScrollTransitionConfiguration(mode: .interactive) }
}

@available(*, unavailable)
extension ScrollTransitionConfiguration: Sendable {}

/// Where a view is in a scroll view's visible region.
@available(OpenSwiftUI_v1_0, *)
@frozen
public enum ScrollTransitionPhase: Hashable {
    /// The view is coming in from, or going out at, the top or leading edge.
    case topLeading
    /// The view is fully inside the visible region.
    case identity
    /// The view is coming in from, or going out at, the bottom or trailing
    /// edge.
    case bottomTrailing

    /// Whether the view is fully inside the visible region.
    public var isIdentity: Bool { self == .identity }
}

@available(OpenSwiftUI_v1_0, *)
extension View {
    /// Applies an effect that changes as this view scrolls through the
    /// visible region. Views aren't told where they are in a scroll view,
    /// so `transition` isn't called and the view draws without an effect,
    /// as it does in the identity phase of a transition that leaves it be.
    nonisolated public func scrollTransition(_ configuration: ScrollTransitionConfiguration = .interactive, axis: Axis? = nil, transition: @escaping @Sendable (EmptyVisualEffect, ScrollTransitionPhase) -> some VisualEffect) -> some View {
        self
    }
}

// MARK: - Tab bars and accessibility

@available(OpenSwiftUI_v1_0, *)
extension TabBarMinimizeBehavior {
    /// Minimize the tab bar when content scrolls down. Perry's tab bar
    /// keeps its size.
    public static var onScrollDown: TabBarMinimizeBehavior { TabBarMinimizeBehavior(rawValue: 1) }

    /// Minimize the tab bar when content scrolls up. Perry's tab bar keeps
    /// its size.
    public static var onScrollUp: TabBarMinimizeBehavior { TabBarMinimizeBehavior(rawValue: 2) }
}

@available(OpenSwiftUI_v1_0, *)
extension View {
    /// Describes where a scroll view is scrolled to for assistive
    /// technologies: nothing reads it here.
    nonisolated public func accessibilityScrollStatus(_ status: Text, isEnabled: Bool = true) -> ModifiedContent<Self, AccessibilityAttachmentModifier> {
        accessibility()
    }
}
#endif
