//
//  LongPressGesture.swift
//  OpenSwiftUI
//
//  Audited for 6.5.4
//  Status: WIP
//  ID: 95296CADE4B1B6231918FF94A8E7AAD1 (SwiftUI)

public import Foundation
import OpenAttributeGraphShims
@_spi(ForOpenSwiftUIOnly)
public import OpenSwiftUICore

// MARK: - Gesture + longPressPhase [TBA]

extension Gesture {
    func longPressPhase() -> ModifierGesture<MapGesture<Value, Bool>, Self> {
        mapPhase { phase in
            if case .active = phase {
                .ended(true)
            } else {
                phase.withValue(false)
            }
        }
    }
}

// MARK: - Bool + PressableEventValue [TBA]

extension Bool: PressableEventValue {
    static func isPressing(_ phase: GesturePhase<Bool>) -> Bool {
        phase.unwrapped ?? false
    }
}

// MARK: - LongPressGesture

/// A gesture that succeeds when the user performs a long press: a touch
/// held for the minimum duration without moving past the maximum distance.
@available(OpenSwiftUI_v1_0, *)
public struct LongPressGesture: PrimitiveGesture, Gesture {
    private struct Child: Rule {
        @Attribute var gesture: LongPressGesture

        var value: some Gesture<Bool> {
            EventListener<TappableEvent>()
                .duration(minimum: gesture.minimumDuration)
                .gated(by: DistanceGesture(maximumDistance: gesture.maximumDistance).coordinateSpace(.global))
                .longPressPhase()
        }
    }

    /// The minimum duration of the long press that must elapse before the
    /// gesture succeeds.
    public var minimumDuration: Double

    /// The maximum distance that the long press can move before the gesture
    /// fails.
    nonisolated public var maximumDistance: CGFloat

    nonisolated public init(minimumDuration: Double = 0.5, maximumDistance: CGFloat = 10) {
        self.minimumDuration = minimumDuration
        self.maximumDistance = maximumDistance
    }

    nonisolated public static func _makeGesture(
        gesture: _GraphValue<LongPressGesture>,
        inputs: _GestureInputs
    ) -> _GestureOutputs<Bool> {
        let child = Attribute(Child(gesture: gesture.value))
        return Child.Value.makeDebuggableGesture(gesture: _GraphValue(child), inputs: inputs)
    }

    public typealias Value = Bool
}

@available(*, unavailable)
extension LongPressGesture: Sendable {}

// MARK: - View + onLongPressGesture

@available(OpenSwiftUI_v1_0, *)
extension View {
    /// Adds an action to perform when this view recognizes a long press
    /// gesture.
    nonisolated public func onLongPressGesture(
        minimumDuration: Double = 0.5,
        maximumDistance: CGFloat = 10,
        perform action: @escaping () -> Void,
        onPressingChanged: ((Bool) -> Void)? = nil
    ) -> some View {
        gesture(
            LongPressGesture(minimumDuration: minimumDuration, maximumDistance: maximumDistance)
                .callbacks(pressing: onPressingChanged, pressed: action),
            including: .all
        )
    }

    /// Adds an action to perform when this view recognizes a long press
    /// gesture.
    @_disfavoredOverload
    nonisolated public func onLongPressGesture(
        minimumDuration: Double = 0.5,
        maximumDistance: CGFloat = 10,
        pressing: ((Bool) -> Void)? = nil,
        perform action: @escaping () -> Void
    ) -> some View {
        gesture(
            LongPressGesture(minimumDuration: minimumDuration, maximumDistance: maximumDistance)
                .callbacks(pressing: pressing, pressed: action),
            including: .all
        )
    }
}
