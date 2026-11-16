//
//  SequenceGesture.swift
//  OpenSwiftUICore
//
//  Status: Perry's implementation

import OpenAttributeGraphShims

@available(OpenSwiftUI_v1_0, *)
extension Gesture {
    /// Sequences a gesture with another one to create a new gesture, which
    /// results in the second gesture only receiving events after the first
    /// gesture succeeds.
    @inlinable
    public func sequenced<Other>(before other: Other) -> SequenceGesture<Self, Other> where Other: Gesture {
        return SequenceGesture(self, other)
    }
}

/// A gesture that's a sequence of two gestures.
///
/// Both gestures follow the events from their start; the second's phases
/// count once the first has ended.
@available(OpenSwiftUI_v1_0, *)
@frozen
public struct SequenceGesture<First, Second>: PrimitiveGesture, Gesture where First: Gesture, Second: Gesture {
    /// The value of a sequence gesture that helps to detect whether the
    /// first gesture succeeded, so the second gesture can start.
    @frozen
    public enum Value {
        /// The first gesture hasn't ended.
        case first(First.Value)
        /// The first gesture has ended.
        case second(First.Value, Second.Value?)
    }

    public var first: First

    public var second: Second

    @inlinable
    public init(_ first: First, _ second: Second) {
        (self.first, self.second) = (first, second)
    }

    nonisolated public static func _makeGesture(
        gesture: _GraphValue<Self>,
        inputs: _GestureInputs
    ) -> _GestureOutputs<Value> {
        let outputs1 = First.makeDebuggableGesture(
            gesture: gesture[offset: { .of(&$0.first) }],
            inputs: inputs
        )
        let outputs2 = Second.makeDebuggableGesture(
            gesture: gesture[offset: { .of(&$0.second) }],
            inputs: inputs
        )
        let phase = Attribute(SequencePhase<First, Second>(
            phase1: outputs1.phase,
            phase2: outputs2.phase
        ))
        return _GestureOutputs(phase: phase)
    }
}

@available(OpenSwiftUI_v1_0, *)
extension SequenceGesture.Value: Sendable where First.Value: Sendable, Second.Value: Sendable {}

@available(*, unavailable)
extension SequenceGesture: Sendable {}

@available(OpenSwiftUI_v1_0, *)
extension SequenceGesture.Value: Equatable where First.Value: Equatable, Second.Value: Equatable {}

private struct SequencePhase<First, Second>: Rule where First: Gesture, Second: Gesture {
    @Attribute var phase1: GesturePhase<First.Value>
    @Attribute var phase2: GesturePhase<Second.Value>

    typealias Value = GesturePhase<SequenceGesture<First, Second>.Value>

    var value: Value {
        switch phase1 {
        case let .possible(value): .possible(value.map { .first($0) })
        case let .active(value): .active(.first(value))
        case .failed: .failed
        case let .ended(first):
            switch phase2 {
            case let .possible(second): .active(.second(first, second))
            case let .active(second): .active(.second(first, second))
            case let .ended(second): .ended(.second(first, second))
            case .failed: .failed
            }
        }
    }
}
