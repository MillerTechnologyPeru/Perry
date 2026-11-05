//
//  Scrolling.swift
//  OpenSwiftUI
//
//  Status: Perry's implementation, interim
//
//  Scroll views' configuration: indicators, bouncing, content margins,
//  keyboard dismissal, scroll targets and positions. Perry's scroll views
//  scroll freely: these are accepted but have no effect yet. Frames
//  relative to a container are relative to the screen.

#if os(iOS) || os(visionOS)
public import Foundation
public import OpenSwiftUICore
import UIKit

// MARK: - Indicators

/// The visibility of scroll indicators within a UI.
@available(OpenSwiftUI_v4_0, *)
public struct ScrollIndicatorVisibility {
    enum Role { case automatic, visible, hidden, never }
    let role: Role

    public static var automatic: ScrollIndicatorVisibility { .init(role: .automatic) }
    public static var visible: ScrollIndicatorVisibility { .init(role: .visible) }
    public static var hidden: ScrollIndicatorVisibility { .init(role: .hidden) }
    public static var never: ScrollIndicatorVisibility { .init(role: .never) }
}

@available(OpenSwiftUI_v4_0, *)
extension ScrollIndicatorVisibility: Equatable {}

@available(OpenSwiftUI_v4_0, *)
extension View {
    /// Sets the visibility of scroll indicators within this view.
    nonisolated public func scrollIndicators(_ visibility: ScrollIndicatorVisibility, axes: Axis.Set = [.vertical, .horizontal]) -> some View {
        self
    }
}

@available(OpenSwiftUI_v5_0, *)
extension View {
    /// Flashes the scroll indicators when a value changes.
    nonisolated public func scrollIndicatorsFlash(trigger value: some Equatable) -> some View {
        self
    }

    /// Flashes the scroll indicators when they first appear.
    nonisolated public func scrollIndicatorsFlash(onAppear: Bool) -> some View {
        self
    }
}

// MARK: - Bouncing

/// The ways that a scrollable view can bounce when it reaches the end of
/// its content.
@available(OpenSwiftUI_v4_0, *)
public struct ScrollBounceBehavior: Sendable {
    enum Role { case automatic, always, basedOnSize }
    let role: Role

    public static var automatic: ScrollBounceBehavior { .init(role: .automatic) }
    public static var always: ScrollBounceBehavior { .init(role: .always) }
    public static var basedOnSize: ScrollBounceBehavior { .init(role: .basedOnSize) }
}

@available(OpenSwiftUI_v4_0, *)
extension View {
    /// Configures the bounce behavior of scrollable views along the
    /// specified axis.
    nonisolated public func scrollBounceBehavior(_ behavior: ScrollBounceBehavior, axes: Axis.Set = [.vertical]) -> some View {
        self
    }
}

// MARK: - Keyboard dismissal

/// The ways that scrollable content can interact with the software keyboard.
@available(OpenSwiftUI_v4_0, *)
public struct ScrollDismissesKeyboardMode: Sendable {
    enum Role { case automatic, immediately, interactively, never }
    let role: Role

    public static var automatic: ScrollDismissesKeyboardMode { .init(role: .automatic) }
    public static var immediately: ScrollDismissesKeyboardMode { .init(role: .immediately) }
    public static var interactively: ScrollDismissesKeyboardMode { .init(role: .interactively) }
    public static var never: ScrollDismissesKeyboardMode { .init(role: .never) }
}

@available(OpenSwiftUI_v6_0, *)
extension ScrollDismissesKeyboardMode: Equatable, Hashable {}

@available(OpenSwiftUI_v4_0, *)
extension View {
    /// Configures the behavior in which scrollable content interacts with
    /// the software keyboard.
    nonisolated public func scrollDismissesKeyboard(_ mode: ScrollDismissesKeyboardMode) -> some View {
        self
    }
}

// MARK: - Content margins

/// The placement of margins.
@available(OpenSwiftUI_v5_0, *)
public struct ContentMarginPlacement {
    enum Role { case automatic, scrollContent, scrollIndicators }
    let role: Role

    public static var automatic: ContentMarginPlacement { .init(role: .automatic) }
    public static var scrollContent: ContentMarginPlacement { .init(role: .scrollContent) }
    public static var scrollIndicators: ContentMarginPlacement { .init(role: .scrollIndicators) }
}

@available(OpenSwiftUI_v5_0, *)
extension View {
    /// Configures the content margin for a provided placement.
    nonisolated public func contentMargins(_ edges: Edge.Set = .all, _ insets: EdgeInsets, for placement: ContentMarginPlacement = .automatic) -> some View {
        self
    }

    /// Configures the content margin for a provided placement.
    nonisolated public func contentMargins(_ edges: Edge.Set = .all, _ length: CGFloat?, for placement: ContentMarginPlacement = .automatic) -> some View {
        self
    }

    /// Configures the content margin for a provided placement.
    nonisolated public func contentMargins(_ length: CGFloat, for placement: ContentMarginPlacement = .automatic) -> some View {
        self
    }
}

// MARK: - Scroll targets

/// A type that defines the scroll behavior of a scrollable view.
@available(OpenSwiftUI_v5_0, *)
public protocol ScrollTargetBehavior {
    /// Updates the proposed target that a scrollable view should scroll to.
    func updateTarget(_ target: inout ScrollTarget, context: Self.TargetContext)

    typealias TargetContext = ScrollTargetBehaviorContext

    static func _makeInputs(_ behavior: _GraphValue<Self>, inputs: inout _ViewInputs)
}

@available(OpenSwiftUI_v5_0, *)
extension ScrollTargetBehavior {
    public static func _makeInputs(_ behavior: _GraphValue<Self>, inputs: inout _ViewInputs) {}
}

/// The context in which a scroll target behavior updates its scroll target.
@available(OpenSwiftUI_v5_0, *)
@dynamicMemberLookup
public struct ScrollTargetBehaviorContext {
    public var originalTarget: ScrollTarget { target }
    public var velocity: CGVector { .zero }
    public var contentSize: CGSize { size }
    public var containerSize: CGSize { container }
    public var axes: Axis.Set { scrollAxes }

    var target: ScrollTarget
    var size: CGSize
    var container: CGSize
    var scrollAxes: Axis.Set
    var environment: EnvironmentValues

    public subscript<T>(dynamicMember keyPath: KeyPath<EnvironmentValues, T>) -> T {
        environment[keyPath: keyPath]
    }
}

/// The scroll behavior that aligns scroll targets to container-based
/// geometry.
@available(OpenSwiftUI_v5_0, *)
public struct PagingScrollTargetBehavior: ScrollTargetBehavior {
    public init() {}

    public func updateTarget(_ target: inout ScrollTarget, context: PagingScrollTargetBehavior.TargetContext) {
        guard context.containerSize.width > 0, context.containerSize.height > 0 else { return }
        if context.axes.contains(.horizontal) {
            let page = (target.rect.minX / context.containerSize.width).rounded()
            target.rect.origin.x = page * context.containerSize.width
        }
        if context.axes.contains(.vertical) {
            let page = (target.rect.minY / context.containerSize.height).rounded()
            target.rect.origin.y = page * context.containerSize.height
        }
    }
}

/// The scroll behavior that aligns scroll targets to view-based geometry.
@available(OpenSwiftUI_v5_0, *)
public struct ViewAlignedScrollTargetBehavior: ScrollTargetBehavior {
    /// A type that defines the amount of views that can be scrolled at a
    /// time.
    public struct LimitBehavior {
        enum Role { case automatic, always, alwaysByFew, alwaysByOne, never }
        let role: Role

        public static var automatic: LimitBehavior { .init(role: .automatic) }
        public static var always: LimitBehavior { .init(role: .always) }
        @available(OpenSwiftUI_v6_0, *)
        public static var alwaysByFew: LimitBehavior { .init(role: .alwaysByFew) }
        @available(OpenSwiftUI_v6_0, *)
        public static var alwaysByOne: LimitBehavior { .init(role: .alwaysByOne) }
        public static var never: LimitBehavior { .init(role: .never) }
    }

    var limitBehavior: LimitBehavior
    var anchor: UnitPoint?

    public init(limitBehavior: LimitBehavior = .automatic) {
        self.limitBehavior = limitBehavior
    }

    @available(OpenSwiftUI_v7_0, *)
    public init(limitBehavior: LimitBehavior, anchor: UnitPoint?) {
        self.limitBehavior = limitBehavior
        self.anchor = anchor
    }

    public func updateTarget(_ target: inout ScrollTarget, context: ViewAlignedScrollTargetBehavior.TargetContext) {}
}

@available(OpenSwiftUI_v5_0, *)
extension View {
    /// Sets the scroll behavior of views scrollable in the provided axes.
    nonisolated public func scrollTargetBehavior(_ behavior: some ScrollTargetBehavior) -> some View {
        self
    }

    /// Configures the outermost layout as a scroll target layout.
    nonisolated public func scrollTargetLayout(isEnabled: Bool = true) -> some View {
        self
    }

    /// Associates a binding to be updated when a scroll view within this
    /// view scrolls.
    nonisolated public func scrollPosition<ID>(id: Binding<ID?>, anchor: UnitPoint? = nil) -> some View where ID: Hashable {
        self
    }
}

// MARK: - Container-relative frames

@available(OpenSwiftUI_v5_0, *)
extension View {
    /// Positions this view within an invisible frame with a size relative to
    /// the nearest container: here, the screen.
    nonisolated public func containerRelativeFrame(_ axes: Axis.Set, alignment: Alignment = .center) -> some View {
        containerRelativeFrame(axes, alignment: alignment) { length, _ in length }
    }

    /// Positions this view within an invisible frame with a size relative to
    /// the nearest container: `count` columns or rows of it, of which this
    /// view takes `span`.
    nonisolated public func containerRelativeFrame(_ axes: Axis.Set, count: Int, span: Int = 1, spacing: CGFloat, alignment: Alignment = .center) -> some View {
        containerRelativeFrame(axes, alignment: alignment) { length, _ in
            let count = CGFloat(max(count, 1)), span = CGFloat(max(span, 1))
            let column = (length - spacing * (count - 1)) / count
            return column * span + spacing * (span - 1)
        }
    }

    /// Positions this view within an invisible frame with a size relative to
    /// the nearest container, as `length` makes it from the container's.
    nonisolated public func containerRelativeFrame(_ axes: Axis.Set, alignment: Alignment = .center, _ length: @escaping (CGFloat, Axis) -> CGFloat) -> some View {
        let container = MainActor.assumeIsolated { UIScreen.main.bounds.size }
        return frame(
            width: axes.contains(.horizontal) ? max(length(container.width, .horizontal), 0) : nil,
            height: axes.contains(.vertical) ? max(length(container.height, .vertical), 0) : nil,
            alignment: alignment
        )
    }
}
#endif
