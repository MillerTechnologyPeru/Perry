//
//  MacCatalystModifiers.swift
//  OpenSwiftUI
//
//  Status: Perry's implementation, interim
//
//  Modifiers that Mac Catalyst apps (Swift Playgrounds) use, declared as
//  SwiftUI declares them, so the app's views resolve: layouts are always
//  left to right here, so a right-to-left flip changes nothing; there is
//  no pointer to hover; and a color multiply is not drawn yet. Each leaves
//  its content as it is.

#if os(iOS) || os(visionOS)
public import OpenSwiftUICore

// MARK: - Right-to-left flip

@available(OpenSwiftUI_v1_0, *)
@frozen
public struct _FlipForRTLEffect: ViewModifier, PrimitiveViewModifier, Equatable {
    public var isEnabled: Bool

    @inlinable
    public init(isEnabled: Bool) {
        self.isEnabled = isEnabled
    }

    nonisolated public static func _makeView(
        modifier: _GraphValue<Self>,
        inputs: _ViewInputs,
        body: @escaping (_Graph, _ViewInputs) -> _ViewOutputs
    ) -> _ViewOutputs {
        body(_Graph(), inputs)
    }

    nonisolated public static func _makeViewList(
        modifier: _GraphValue<Self>,
        inputs: _ViewListInputs,
        body: @escaping (_Graph, _ViewListInputs) -> _ViewListOutputs
    ) -> _ViewListOutputs {
        body(_Graph(), inputs)
    }

    nonisolated public static func _viewListCount(
        inputs: _ViewListCountInputs,
        body: (_ViewListCountInputs) -> Int?
    ) -> Int? {
        body(inputs)
    }
}

@available(OpenSwiftUI_v1_0, *)
extension View {
    /// Whether the view flips its contents horizontally when the layout
    /// direction is right to left.
    @inlinable
    nonisolated public func flipsForRightToLeftLayoutDirection(_ enabled: Bool) -> some View {
        modifier(_FlipForRTLEffect(isEnabled: enabled))
    }
}

// MARK: - Hover

@available(OpenSwiftUI_v1_0, *)
@frozen
public struct _HoverRegionModifier: ViewModifier, PrimitiveViewModifier {
    public let callback: (Bool) -> Void

    @inlinable
    public init(_ callback: @escaping (Bool) -> Void) {
        self.callback = callback
    }

    nonisolated public static func _makeView(
        modifier: _GraphValue<Self>,
        inputs: _ViewInputs,
        body: @escaping (_Graph, _ViewInputs) -> _ViewOutputs
    ) -> _ViewOutputs {
        body(_Graph(), inputs)
    }

    nonisolated public static func _makeViewList(
        modifier: _GraphValue<Self>,
        inputs: _ViewListInputs,
        body: @escaping (_Graph, _ViewListInputs) -> _ViewListOutputs
    ) -> _ViewListOutputs {
        body(_Graph(), inputs)
    }

    nonisolated public static func _viewListCount(
        inputs: _ViewListCountInputs,
        body: (_ViewListCountInputs) -> Int?
    ) -> Int? {
        body(inputs)
    }
}

@available(OpenSwiftUI_v1_0, *)
extension View {
    /// Adds an action to perform when the pointer moves onto or away from
    /// the view: never, as there is no pointer.
    @inlinable
    nonisolated public func onHover(perform action: @escaping (Bool) -> Void) -> some View {
        modifier(_HoverRegionModifier(action))
    }
}

// MARK: - Color multiply

@available(OpenSwiftUI_v1_0, *)
@frozen
public struct _ColorMultiplyEffect: EnvironmentalModifier, Equatable {
    public var color: Color

    @inlinable
    public init(color: Color) {
        self.color = color
    }

    public func resolve(in environment: EnvironmentValues) -> _Resolved {
        _Resolved()
    }

    public struct _Resolved: ViewModifier, PrimitiveViewModifier, Animatable {
        public typealias AnimatableData = AnimatablePair<Float, AnimatablePair<Float, AnimatablePair<Float, Float>>>

        public var animatableData: AnimatableData {
            get { AnimatablePair(0, AnimatablePair(0, AnimatablePair(0, 0))) }
            set {}
        }

        nonisolated public static func _makeView(
            modifier: _GraphValue<Self>,
            inputs: _ViewInputs,
            body: @escaping (_Graph, _ViewInputs) -> _ViewOutputs
        ) -> _ViewOutputs {
            body(_Graph(), inputs)
        }

        nonisolated public static func _makeViewList(
            modifier: _GraphValue<Self>,
            inputs: _ViewListInputs,
            body: @escaping (_Graph, _ViewListInputs) -> _ViewListOutputs
        ) -> _ViewListOutputs {
            body(_Graph(), inputs)
        }

        nonisolated public static func _viewListCount(
            inputs: _ViewListCountInputs,
            body: (_ViewListCountInputs) -> Int?
        ) -> Int? {
            body(inputs)
        }
    }
}

@available(OpenSwiftUI_v1_0, *)
extension View {
    /// Multiplies the view's colors by the given color: not drawn yet.
    @inlinable
    nonisolated public func colorMultiply(_ color: Color) -> some View {
        modifier(_ColorMultiplyEffect(color: color))
    }
}

// MARK: - Fill shape style

/// The style a shape is filled with by default: the foreground style.
@available(OpenSwiftUI_v1_0, *)
@frozen
public struct FillShapeStyle: ShapeStyle {
    @inlinable
    public init() {}

    public func _apply(to shape: inout _ShapeStyle_Shape) {
        ForegroundStyle()._apply(to: &shape)
    }

    public static func _apply(to type: inout _ShapeStyle_ShapeType) {
        ForegroundStyle._apply(to: &type)
    }
}

// MARK: - List row separators' alignment

@available(OpenSwiftUI_v4_0, *)
extension HorizontalAlignment {
    /// Where a list row's separator starts: the row's leading edge here.
    public static var listRowSeparatorLeading: HorizontalAlignment { .leading }

    /// Where a list row's separator ends: the row's trailing edge here.
    public static var listRowSeparatorTrailing: HorizontalAlignment { .trailing }
}

// MARK: - Scrolling

@available(OpenSwiftUI_v4_0, *)
extension View {
    /// Disables or enables scrolling in scrollable views: they scroll here.
    nonisolated public func scrollDisabled(_ disabled: Bool) -> some View {
        self
    }
}

@available(OpenSwiftUI_v5_0, *)
extension View {
    /// Whether scrollable views clip their content to their bounds.
    nonisolated public func scrollClipDisabled(_ disabled: Bool = true) -> some View {
        self
    }
}

// MARK: - Accessibility sort priority

@available(OpenSwiftUI_v2_0, *)
extension View {
    /// The order VoiceOver reads the view in: nothing reads it here.
    nonisolated public func accessibilitySortPriority(_ sortPriority: Double) -> ModifiedContent<Self, AccessibilityAttachmentModifier> {
        accessibility()
    }
}

@available(OpenSwiftUI_v2_0, *)
extension ModifiedContent where Modifier == AccessibilityAttachmentModifier {
    /// The order VoiceOver reads the view in: nothing reads it here.
    nonisolated public func accessibilitySortPriority(_ sortPriority: Double) -> ModifiedContent<Content, Modifier> {
        self
    }
}
#endif
