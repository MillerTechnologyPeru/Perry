//
//  ModifiersMore.swift
//  OpenSwiftUI
//
//  Status: Perry's implementation, mostly inert
//
//  More modifiers and the types they take. A safe area bar is a safe area
//  inset, and a glass effect container draws its content. The rest is
//  taken and ignored: accessibility attributes that can be switched off,
//  input labels, activation points and chart descriptors, which nothing
//  reads; badges; list row insets and section margins by edge; the order
//  and dismissal of menus; content that can be invalidated; continuous
//  hover, as there is no pointer; hinge changes, as no device here folds;
//  and transitions between glass effects.

#if os(iOS) || os(visionOS)
public import Foundation
public import OpenSwiftUICore

// MARK: - Accessibility attributes that can be switched off

@available(OpenSwiftUI_v1_0, *)
extension View {
    /// Adds a label to the view that describes its contents, when enabled.
    nonisolated public func accessibilityLabel(_ label: Text, isEnabled: Bool) -> ModifiedContent<Self, AccessibilityAttachmentModifier> {
        accessibility()
    }

    /// Adds a label to the view that describes its contents, when enabled.
    @_disfavoredOverload
    nonisolated public func accessibilityLabel<S>(_ label: S, isEnabled: Bool) -> ModifiedContent<Self, AccessibilityAttachmentModifier> where S: StringProtocol {
        accessibility()
    }

    /// Adds a textual description of the value the view contains, when
    /// enabled.
    nonisolated public func accessibilityValue(_ valueDescription: Text, isEnabled: Bool) -> ModifiedContent<Self, AccessibilityAttachmentModifier> {
        accessibility()
    }

    /// Tells what happens after performing the view's action, when enabled.
    nonisolated public func accessibilityHint(_ hint: Text, isEnabled: Bool) -> ModifiedContent<Self, AccessibilityAttachmentModifier> {
        accessibility()
    }

    /// Hides this view from accessibility features, when enabled.
    nonisolated public func accessibilityHidden(_ hidden: Bool, isEnabled: Bool) -> ModifiedContent<Self, AccessibilityAttachmentModifier> {
        accessibility()
    }

    /// Identifies the view by the given string, when enabled.
    nonisolated public func accessibilityIdentifier(_ identifier: String, isEnabled: Bool) -> ModifiedContent<Self, AccessibilityAttachmentModifier> {
        accessibility()
    }

    /// Sets alternative labels by which the user can refer to the view,
    /// when enabled.
    nonisolated public func accessibilityInputLabels(_ inputLabels: [Text], isEnabled: Bool) -> ModifiedContent<Self, AccessibilityAttachmentModifier> {
        accessibility()
    }
}

@available(OpenSwiftUI_v1_0, *)
extension ModifiedContent where Modifier == AccessibilityAttachmentModifier {
    /// Adds a textual description of the value the view contains, when
    /// enabled.
    nonisolated public func accessibilityValue(_ valueDescription: Text, isEnabled: Bool) -> ModifiedContent<Content, Modifier> {
        self
    }

    /// Tells what happens after performing the view's action, when enabled.
    nonisolated public func accessibilityHint(_ hint: Text, isEnabled: Bool) -> ModifiedContent<Content, Modifier> {
        self
    }

    /// Hides this view from accessibility features, when enabled.
    nonisolated public func accessibilityHidden(_ hidden: Bool, isEnabled: Bool) -> ModifiedContent<Content, Modifier> {
        self
    }

    /// Identifies the view by the given string, when enabled.
    nonisolated public func accessibilityIdentifier(_ identifier: String, isEnabled: Bool) -> ModifiedContent<Content, Modifier> {
        self
    }

    /// Sets alternative labels by which the user can refer to the view,
    /// when enabled.
    nonisolated public func accessibilityInputLabels(_ inputLabels: [Text], isEnabled: Bool) -> ModifiedContent<Content, Modifier> {
        self
    }
}

// MARK: - Further accessibility attributes

@available(OpenSwiftUI_v1_0, *)
extension View {
    /// Labels the view with the views the closure makes from the label the
    /// view already has. The closure isn't called.
    nonisolated public func accessibilityLabel<V>(@ViewBuilder content: (_ label: PlaceholderContentView<Self>) -> V) -> some View where V: View {
        self
    }

    /// Sets alternative labels by which the user can refer to the view.
    nonisolated public func accessibilityInputLabels(_ inputLabels: [Text]) -> ModifiedContent<Self, AccessibilityAttachmentModifier> {
        accessibility()
    }

    /// Sets alternative labels by which the user can refer to the view.
    @_disfavoredOverload
    nonisolated public func accessibilityInputLabels<S>(_ inputLabels: [S]) -> ModifiedContent<Self, AccessibilityAttachmentModifier> where S: StringProtocol {
        accessibility()
    }

    /// Says whether the view answers to the user's touches.
    nonisolated public func accessibilityRespondsToUserInteraction(_ respondsToUserInteraction: Bool = true) -> ModifiedContent<Self, AccessibilityAttachmentModifier> {
        accessibility()
    }

    /// Sets the point, in the view's unit space, that assistive
    /// technologies activate.
    nonisolated public func accessibilityActivationPoint(_ activationPoint: UnitPoint) -> ModifiedContent<Self, AccessibilityAttachmentModifier> {
        accessibility()
    }

    /// Describes the chart the view draws to assistive technologies. No
    /// descriptor is made.
    nonisolated public func accessibilityChartDescriptor<R>(_ representable: R) -> some View where R: AXChartDescriptorRepresentable {
        self
    }
}

@available(OpenSwiftUI_v1_0, *)
extension ModifiedContent where Modifier == AccessibilityAttachmentModifier {
    /// Sets alternative labels by which the user can refer to the view.
    nonisolated public func accessibilityInputLabels(_ inputLabels: [Text]) -> ModifiedContent<Content, Modifier> {
        self
    }

    /// Sets alternative labels by which the user can refer to the view.
    @_disfavoredOverload
    nonisolated public func accessibilityInputLabels<S>(_ inputLabels: [S]) -> ModifiedContent<Content, Modifier> where S: StringProtocol {
        self
    }

    /// Says whether the view answers to the user's touches.
    nonisolated public func accessibilityRespondsToUserInteraction(_ respondsToUserInteraction: Bool = true) -> ModifiedContent<Content, Modifier> {
        self
    }
}

// MARK: - Badges and lists

@available(OpenSwiftUI_v1_0, *)
extension View {
    /// Shows a count on the view's list row or tab; Perry's rows and tabs
    /// draw no badge.
    nonisolated public func badge(_ count: Int) -> some View {
        self
    }

    /// Insets the given edges of a list row by a length. Rows keep the
    /// insets of their list style.
    nonisolated public func listRowInsets(_ edges: Edge.Set = .all, _ length: CGFloat?) -> some View {
        self
    }

    /// Sets the margins of a list section on the given edges. Sections keep
    /// the margins of their list style.
    nonisolated public func listSectionMargins(_ edges: Edge.Set = .all, _ length: CGFloat?) -> some View {
        self
    }
}

// MARK: - Menus

/// The order in which a menu lists its items: as written, or with the first
/// ones nearest to where the user touched.
@available(OpenSwiftUI_v1_0, *)
public struct MenuOrder: Equatable, Hashable, Sendable {
    var rawValue: Int

    /// The first items are nearest to the touch.
    public static let priority = MenuOrder(rawValue: 1)

    /// The items are listed top to bottom as written.
    public static let fixed = MenuOrder(rawValue: 2)
}

/// Whether a menu closes once one of its actions is performed.
@available(OpenSwiftUI_v1_0, *)
public struct MenuActionDismissBehavior: Equatable {
    var rawValue: Int

    /// The menu always closes.
    public static let enabled = MenuActionDismissBehavior(rawValue: 1)
}

@available(*, unavailable)
extension MenuActionDismissBehavior: Sendable {}

@available(OpenSwiftUI_v1_0, *)
extension View {
    /// Sets the order of the items of menus in this view; Perry's menus
    /// list them as written.
    nonisolated public func menuOrder(_ order: MenuOrder) -> some View {
        self
    }

    /// Sets whether menus in this view close after an action; Perry's
    /// always do.
    nonisolated public func menuActionDismissBehavior(_ behavior: MenuActionDismissBehavior) -> some View {
        self
    }
}

// MARK: - Safe area bars

@available(OpenSwiftUI_v1_0, *)
extension View {
    /// Shows the content as a bar along the top or bottom of this view,
    /// which is inset to make room for it, as `safeAreaInset` does. The
    /// blur a bar gives the content scrolling under it isn't drawn.
    nonisolated public func safeAreaBar(
        edge: VerticalEdge,
        alignment: HorizontalAlignment = .center,
        spacing: CGFloat? = nil,
        @ViewBuilder content: () -> some View
    ) -> some View {
        safeAreaInset(edge: edge, alignment: alignment, spacing: spacing, content: content)
    }
}

// MARK: - Invalidatable content

@available(OpenSwiftUI_v1_0, *)
extension View {
    /// Marks the view's content as able to show that it is out of date.
    /// Nothing redacts it here.
    nonisolated public func invalidatableContent(_ invalidatable: Bool = true) -> some View {
        self
    }
}

// MARK: - Continuous hover

/// Where a pointer is as it hovers over a view.
@available(OpenSwiftUI_v1_0, *)
@frozen
public enum HoverPhase: Equatable {
    /// The pointer is over the view, at a point in a coordinate space.
    case active(CGPoint)
    /// The pointer left the view.
    case ended
}

@available(OpenSwiftUI_v1_0, *)
extension HoverPhase: Sendable {}

@available(OpenSwiftUI_v1_0, *)
extension View {
    /// Calls the action as a pointer moves over the view: never, as there
    /// is no pointer.
    nonisolated public func onContinuousHover(
        coordinateSpace: some CoordinateSpaceProtocol = .local,
        perform action: @escaping (HoverPhase) -> Void
    ) -> some View {
        self
    }
}

// MARK: - Device hinge

/// The hinge of a device that folds: how far it is open.
@available(OpenSwiftUI_v1_0, *)
public struct DeviceHinge: Hashable, Sendable {
    /// Whether the hinge is closed, partly open or fully open.
    public var status: DeviceHinge.Status

    /// The angle between the two halves of the device.
    public var angle: Angle
}

@available(OpenSwiftUI_v1_0, *)
extension DeviceHinge {
    /// How far a hinge is open.
    public struct Status: Hashable, Sendable {
        var rawValue: Int

        /// The device is folded shut.
        public static var closed: DeviceHinge.Status {
            DeviceHinge.Status(rawValue: 0)
        }

        /// The device is open at an angle.
        public static var partiallyOpen: DeviceHinge.Status {
            DeviceHinge.Status(rawValue: 1)
        }

        /// The device is open flat.
        public static var fullyOpen: DeviceHinge.Status {
            DeviceHinge.Status(rawValue: 2)
        }
    }
}

/// What a view learns about the hinge of the device it is on: nil where the
/// device has none.
@available(OpenSwiftUI_v1_0, *)
public struct DeviceHingeContext: Equatable, Sendable {
    /// The device's hinge, if it has one.
    public var hinge: DeviceHinge?
}

@available(OpenSwiftUI_v1_0, *)
extension View {
    /// Calls the action when the device's hinge opens or closes: never, as
    /// no device Perry runs on reports a hinge.
    nonisolated public func onHingeChange(
        isEnabled: Bool = true,
        _ action: @escaping (_ oldContext: DeviceHingeContext, _ newContext: DeviceHingeContext) -> Void
    ) -> some View {
        self
    }
}

// MARK: - Glass effects

/// A view whose glass effects blend with one another where they are close.
/// Here it draws its content as it is; the glass effects in it stay apart.
@available(OpenSwiftUI_v1_0, *)
@MainActor
@preconcurrency
public struct GlassEffectContainer<Content>: View where Content: View {
    var spacing: CGFloat?
    var content: Content

    /// Creates a container whose glass effects blend when nearer to each
    /// other than the spacing.
    @MainActor
    @preconcurrency
    public init(spacing: CGFloat? = nil, @ViewBuilder content: () -> Content) {
        self.spacing = spacing
        self.content = content()
    }

    @MainActor
    @preconcurrency
    public var body: some View {
        content
    }
}

/// How a glass effect appears and disappears in a container.
@available(OpenSwiftUI_v1_0, *)
public struct GlassEffectTransition: Sendable {
    var rawValue: Int

    /// The glass effect appears and disappears at once.
    public static var identity: GlassEffectTransition {
        GlassEffectTransition(rawValue: 0)
    }
}

@available(OpenSwiftUI_v1_0, *)
extension View {
    /// Sets how the view's glass effect appears and disappears; Perry's
    /// does both at once.
    @MainActor
    @preconcurrency
    public func glassEffectTransition(_ transition: GlassEffectTransition) -> some View {
        self
    }
}

#endif
