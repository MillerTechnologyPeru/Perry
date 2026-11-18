//
//  TextAndPreferencesMore.swift
//  OpenSwiftUI
//
//  Status: Perry's implementation
//
//  Views made from preference values with an alignment, anchor preferences
//  transformed in place, Text's speech and accessibility modifiers, the
//  time data source text initializer, and the symbol content transition.
//  Perry has no speech or accessibility output, so those modifiers return
//  the text as it is; preference overlays are not drawn yet, as with the
//  overlay modifier.

#if os(iOS) || os(visionOS)
public import Foundation
public import OpenSwiftUICore
@_spi(Private) public import Symbols

// MARK: - Preference values as views

/// A modifier that puts a view made from a preference's value behind the
/// view: not drawn yet.
@available(OpenSwiftUI_v1_0, *)
@frozen
public struct _BackgroundPreferenceModifier<Key, Overlay>: ViewModifier, PrimitiveViewModifier where Key: PreferenceKey, Overlay: View {
    public var transform: (Key.Value) -> Overlay
    public var alignment: Alignment

    @inlinable
    nonisolated public init(alignment: Alignment, @ViewBuilder transform: @escaping (Key.Value) -> Overlay) {
        self.transform = transform
        self.alignment = alignment
    }

    nonisolated public static func _makeView(
        modifier: _GraphValue<Self>,
        inputs: _ViewInputs,
        body: @escaping (_Graph, _ViewInputs) -> _ViewOutputs
    ) -> _ViewOutputs {
        body(_Graph(), inputs)
    }
}

@available(*, unavailable)
extension _BackgroundPreferenceModifier: Sendable {}

@available(OpenSwiftUI_v1_0, *)
extension View {
    /// Overlays a view made from a preference's value.
    nonisolated public func overlayPreferenceValue<K, V>(
        _ key: K.Type,
        alignment: Alignment = .center,
        @ViewBuilder _ transform: @escaping (K.Value) -> V
    ) -> some View where K: PreferenceKey, V: View {
        modifier(_OverlayPreferenceModifier<K, V>(alignment: alignment, transform: transform))
    }

    /// Puts a view made from a preference's value behind this one.
    nonisolated public func backgroundPreferenceValue<K, V>(
        _ key: K.Type,
        alignment: Alignment = .center,
        @ViewBuilder _ transform: @escaping (K.Value) -> V
    ) -> some View where K: PreferenceKey, V: View {
        modifier(_BackgroundPreferenceModifier<K, V>(alignment: alignment, transform: transform))
    }
}

// MARK: - Anchor preferences transformed

/// A modifier that changes a preference's value with an anchor of the
/// view. The preference is passed on as it is: the anchor is not applied.
@available(OpenSwiftUI_v1_0, *)
@frozen
public struct _AnchorTransformModifier<AnchorValue, Key>: ViewModifier, PrimitiveViewModifier where Key: PreferenceKey {
    public var anchor: Anchor<AnchorValue>.Source
    public var transform: (inout Key.Value, Anchor<AnchorValue>) -> Void

    @inlinable
    nonisolated public init(anchor: Anchor<AnchorValue>.Source, transform: @escaping (inout Key.Value, Anchor<AnchorValue>) -> Void) {
        self.anchor = anchor
        self.transform = transform
    }

    nonisolated public static func _makeView(
        modifier: _GraphValue<Self>,
        inputs: _ViewInputs,
        body: @escaping (_Graph, _ViewInputs) -> _ViewOutputs
    ) -> _ViewOutputs {
        body(_Graph(), inputs)
    }
}

@available(*, unavailable)
extension _AnchorTransformModifier: Sendable {}

@available(OpenSwiftUI_v1_0, *)
extension View {
    /// Changes a preference's value with an anchor of this view.
    nonisolated public func transformAnchorPreference<A, K>(
        key _: K.Type = K.self,
        value: Anchor<A>.Source,
        transform: @escaping (inout K.Value, Anchor<A>) -> Void
    ) -> some View where K: PreferenceKey {
        modifier(_AnchorTransformModifier<A, K>(anchor: value, transform: transform))
    }
}

// MARK: - Text

@available(OpenSwiftUI_v1_0, *)
extension Text {
    /// Speech always reads punctuation; there is no speech here.
    public func speechAlwaysIncludesPunctuation(_ value: Bool = true) -> Text { self }
    /// Speech spells out the characters; there is no speech here.
    public func speechSpellsOutCharacters(_ value: Bool = true) -> Text { self }
    /// Speech reads at a raised or lowered pitch; there is no speech here.
    public func speechAdjustedPitch(_ value: Double) -> Text { self }
    /// Speech queues the text behind what it is saying; there is no speech here.
    public func speechAnnouncementsQueued(_ value: Bool = true) -> Text { self }

    /// Marks the kind of text for accessibility, which Perry has none of.
    nonisolated public func accessibilityTextContentType(_ value: AccessibilityTextContentType) -> Text { self }
    /// Marks the text as a heading for accessibility, which Perry has none of.
    nonisolated public func accessibilityHeading(_ level: AccessibilityHeadingLevel) -> Text { self }

    /// Text that shows a time-dependent value in a format with string
    /// output, as the core module makes it.
    @_disfavoredOverload
    public init<V, F>(_ source: TimeDataSource<V>, format: F) where V == F.FormatInput, F: DiscreteFormatStyle, F.FormatOutput == String {
        self.init(timeDataSource: source, stringFormat: format)
    }
}

// MARK: - Container corners

// Declared in this module, as apps bind them as its extension members.
@available(OpenSwiftUI_v1_0, *)
extension GeometryProxy {
    /// How the container's corners cut into the view: Perry's containers
    /// have square corners, so not at all.
    public var containerCornerInsets: RectangleCornerInsets { RectangleCornerInsets() }

    /// The radii that keep a rectangle's corners concentric with its
    /// container's: none, as Perry's containers have square corners.
    public func concentricCornerRadii(in frame: CGRect) -> RectangleCornerRadii? { nil }
}

// MARK: - Symbol content transition

@available(OpenSwiftUI_v1_0, *)
extension ContentTransition {
    /// A transition that animates a symbol image with an effect; Perry
    /// changes the content without one.
    public static func symbolEffect<T>(_ effect: T, options: Symbols.SymbolEffectOptions = .default) -> ContentTransition
        where T: Symbols.ContentTransitionSymbolEffect, T: Symbols.SymbolEffect {
        .identity
    }
}
#endif
