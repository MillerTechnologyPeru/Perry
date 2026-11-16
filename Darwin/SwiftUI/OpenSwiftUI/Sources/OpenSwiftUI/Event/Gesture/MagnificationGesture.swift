//
//  MagnificationGesture.swift
//  OpenSwiftUI
//
//  Status: Perry's implementation

public import Foundation
import OpenAttributeGraphShims
@_spi(ForOpenSwiftUIOnly)
public import OpenSwiftUICore

/// A gesture that recognizes a magnification motion and tracks the amount
/// of magnification.
///
/// Perry delivers one touch at a time, so the gesture never begins.
@available(OpenSwiftUI_v1_0, *)
public struct MagnificationGesture: PrimitiveGesture, Gesture {
    /// The minimum required delta before the gesture starts.
    public var minimumScaleDelta: CGFloat

    nonisolated public init(minimumScaleDelta: CGFloat = 0.01) {
        self.minimumScaleDelta = minimumScaleDelta
    }

    nonisolated public static func _makeGesture(
        gesture: _GraphValue<MagnificationGesture>,
        inputs: _GestureInputs
    ) -> _GestureOutputs<CGFloat> {
        EmptyGesture<CGFloat>._makeGesture(gesture: _GraphValue(Attribute(value: EmptyGesture<CGFloat>())), inputs: inputs)
    }

    public typealias Value = CGFloat
}

@available(*, unavailable)
extension MagnificationGesture: Sendable {}
