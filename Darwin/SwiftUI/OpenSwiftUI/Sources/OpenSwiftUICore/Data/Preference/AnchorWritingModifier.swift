//
//  AnchorWritingModifier.swift
//  OpenSwiftUICore
//
//  Status: Perry's implementation

import Foundation
import OpenAttributeGraphShims

// MARK: - _AnchorWritingModifier

/// Sets a preference from an anchor of the view: its bounds, or a point of
/// them, which whoever reads the preference resolves in its own space.
@available(OpenSwiftUI_v1_0, *)
@frozen
public struct _AnchorWritingModifier<AnchorValue, Key>: ViewModifier, MultiViewModifier, PrimitiveViewModifier where Key: PreferenceKey {
    public var anchor: Anchor<AnchorValue>.Source

    public var transform: (Anchor<AnchorValue>) -> Key.Value

    @inlinable
    nonisolated public init(anchor: Anchor<AnchorValue>.Source, transform: @escaping (Anchor<AnchorValue>) -> Key.Value) {
        self.anchor = anchor
        self.transform = transform
    }

    nonisolated public static func _makeView(
        modifier: _GraphValue<Self>,
        inputs: _ViewInputs,
        body: @escaping (_Graph, _ViewInputs) -> _ViewOutputs
    ) -> _ViewOutputs {
        var newInputs = inputs
        newInputs.preferences.remove(Key.self)
        var outputs = body(_Graph(), newInputs)
        outputs.preferences.makePreferenceWriter(
            inputs: inputs.preferences,
            key: Key.self,
            value: Attribute(AnchorPreferenceValue<AnchorValue, Key>(
                modifier: modifier.value,
                position: inputs.position,
                size: inputs.size.cgSize,
                transform: inputs.transform
            ))
        )
        return outputs
    }
}

@available(*, unavailable)
extension _AnchorWritingModifier: Sendable {}

/// The preference's value: the anchor in the view's geometry, transformed.
private struct AnchorPreferenceValue<AnchorValue, Key>: Rule where Key: PreferenceKey {
    @Attribute var modifier: _AnchorWritingModifier<AnchorValue, Key>
    @Attribute var position: ViewOrigin
    @Attribute var size: CGSize
    @Attribute var transform: ViewTransform

    var value: Key.Value {
        let anchor = modifier.anchor.prepare(
            geometry: AnchorGeometry(position: $position, size: $size, transform: $transform)
        )
        return modifier.transform(anchor)
    }
}

// MARK: - View + anchorPreference

@available(OpenSwiftUI_v1_0, *)
extension View {
    /// Sets a value for the specified preference key, the value is a
    /// function of a geometry value tied to the current coordinate space,
    /// allowing readers of the value to convert the geometry to their local
    /// coordinates.
    @inlinable
    nonisolated public func anchorPreference<A, K>(
        key _: K.Type = K.self,
        value: Anchor<A>.Source,
        transform: @escaping (Anchor<A>) -> K.Value
    ) -> some View where K: PreferenceKey {
        return modifier(_AnchorWritingModifier<A, K>(anchor: value, transform: transform))
    }
}
