//
//  MacCatalystControls.swift
//  OpenSwiftUI
//
//  Status: Perry's implementation, interim
//
//  Styles, hover effects, text input settings and a few view modifiers
//  that Mac Catalyst apps (Swift Playgrounds) use, declared as SwiftUI
//  declares them so the app's views resolve. Those with an effect nothing
//  here shows leave their content as it is: there is no pointer to hover,
//  no assistive technology to read an identifier, and the styles' own
//  views are never made, as controls draw themselves.

#if os(iOS) || os(visionOS)
public import OpenSwiftUICore
public import Foundation

// MARK: - Hover effects

/// The effect a view has when the pointer is over it.
@available(OpenSwiftUI_v1_0, *)
public struct HoverEffect {
    var kind: Int

    init(kind: Int) {
        self.kind = kind
    }

    public init<E>(_ effect: E) where E: CustomHoverEffect {
        self.init(kind: 0)
    }

    public static var automatic: HoverEffect { HoverEffect(kind: 0) }
    public static var highlight: HoverEffect { HoverEffect(kind: 1) }
    public static var lift: HoverEffect { HoverEffect(kind: 2) }
}

/// An effect that changes a view as the system chooses.
@available(OpenSwiftUI_v6_0, *)
public struct AutomaticHoverEffect: CustomHoverEffect, PrimitiveCustomHoverEffect {
    public static func _makeCustomHoverEffect(
        effect: _GraphValue<Self>,
        inputs: _CustomHoverEffectInputs,
        body: @escaping (_CustomHoverEffectInputs) -> _CustomHoverEffectOutputs
    ) -> _CustomHoverEffectOutputs {
        body(inputs)
    }

    public init() {}

    package var systemHoverEffect: SystemHoverEffect { SystemHoverEffect() }

    public typealias Body = Never

    package typealias WrappedEffectType = AutomaticHoverEffect
}

/// An effect that highlights a view as the pointer moves over it.
@available(OpenSwiftUI_v6_0, *)
public struct HighlightHoverEffect: CustomHoverEffect, PrimitiveCustomHoverEffect {
    public static func _makeCustomHoverEffect(
        effect: _GraphValue<Self>,
        inputs: _CustomHoverEffectInputs,
        body: @escaping (_CustomHoverEffectInputs) -> _CustomHoverEffectOutputs
    ) -> _CustomHoverEffectOutputs {
        body(inputs)
    }

    public init() {}

    package var systemHoverEffect: SystemHoverEffect { SystemHoverEffect() }

    public typealias Body = Never

    package typealias WrappedEffectType = HighlightHoverEffect
}

/// An effect that lifts a view as the pointer moves over it.
@available(OpenSwiftUI_v6_0, *)
public struct LiftHoverEffect: CustomHoverEffect, PrimitiveCustomHoverEffect {
    public static func _makeCustomHoverEffect(
        effect: _GraphValue<Self>,
        inputs: _CustomHoverEffectInputs,
        body: @escaping (_CustomHoverEffectInputs) -> _CustomHoverEffectOutputs
    ) -> _CustomHoverEffectOutputs {
        body(inputs)
    }

    public init() {}

    package var systemHoverEffect: SystemHoverEffect { SystemHoverEffect() }

    public typealias Body = Never

    package typealias WrappedEffectType = LiftHoverEffect
}

@available(OpenSwiftUI_v6_0, *)
extension CustomHoverEffect where Self == AutomaticHoverEffect {
    public static var automatic: AutomaticHoverEffect { AutomaticHoverEffect() }
}

@available(OpenSwiftUI_v6_0, *)
extension CustomHoverEffect where Self == HighlightHoverEffect {
    public static var highlight: HighlightHoverEffect { HighlightHoverEffect() }
}

@available(OpenSwiftUI_v6_0, *)
extension CustomHoverEffect where Self == LiftHoverEffect {
    public static var lift: LiftHoverEffect { LiftHoverEffect() }
}

@available(OpenSwiftUI_v1_0, *)
extension View {
    /// Applies a hover effect to the view: none is shown, as there is no pointer.
    nonisolated public func hoverEffect(_ effect: some CustomHoverEffect = AutomaticHoverEffect(), isEnabled: Bool = true) -> some View {
        self
    }

    @_disfavoredOverload
    nonisolated public func hoverEffect(_ effect: HoverEffect = .automatic) -> some View {
        self
    }

    @_disfavoredOverload
    nonisolated public func hoverEffect(_ effect: HoverEffect = .automatic, isEnabled: Bool = true) -> some View {
        self
    }
}

// MARK: - Text field styles

/// A specification for the appearance and interaction of a text field.
@available(OpenSwiftUI_v1_0, *)
public protocol TextFieldStyle {
    associatedtype _Body: View

    @ViewBuilder
    func _body(configuration: TextField<Self._Label>) -> _Body

    typealias _Label = _TextFieldStyleLabel
}

/// The label a text field style's configuration has.
@available(OpenSwiftUI_v1_0, *)
public struct _TextFieldStyleLabel: View {
    public typealias Body = Never
    public var body: Never { fatalError("_TextFieldStyleLabel has no body") }
}

/// A text field style with no decoration.
@available(OpenSwiftUI_v1_0, *)
public struct PlainTextFieldStyle: TextFieldStyle {
    public init() {}

    public func _body(configuration: TextField<_Label>) -> some View {
        configuration
    }
}

@available(OpenSwiftUI_v1_0, *)
extension TextFieldStyle where Self == PlainTextFieldStyle {
    public static var plain: PlainTextFieldStyle { PlainTextFieldStyle() }
}

@available(OpenSwiftUI_v1_0, *)
extension View {
    /// Sets the style for text fields within this view: text fields draw themselves.
    nonisolated public func textFieldStyle<S>(_ style: S) -> some View where S: TextFieldStyle {
        self
    }
}

@available(OpenSwiftUI_v1_0, *)
extension TextField {
    /// Creates a text field with a label view and a prompt.
    nonisolated public init(text: Binding<String>, prompt: Text? = nil, @ViewBuilder label: () -> Label) {
        self.text = text
        self.prompt = prompt
        self.label = label()
    }
}

// MARK: - Menu styles

/// A type that applies standard interaction behavior and a custom
/// appearance to all menus within a view hierarchy.
@available(OpenSwiftUI_v2_0, *)
@MainActor
public protocol MenuStyle {
    associatedtype Body: View

    @ViewBuilder
    func makeBody(configuration: Configuration) -> Body

    typealias Configuration = MenuStyleConfiguration
}

/// A configuration of a menu.
@available(OpenSwiftUI_v2_0, *)
public struct MenuStyleConfiguration {
    @MainActor
    public struct Label: View {
        public typealias Body = Never
        public var body: Never { fatalError("MenuStyleConfiguration.Label has no body") }
    }

    @MainActor
    public struct Content: View {
        public typealias Body = Never
        public var body: Never { fatalError("MenuStyleConfiguration.Content has no body") }
    }

    public var label: MenuStyleConfiguration.Label { MainActor.assumeIsolated { Label() } }

    public var content: MenuStyleConfiguration.Content { MainActor.assumeIsolated { Content() } }
}

/// A menu style that displays a button as its label.
@available(OpenSwiftUI_v4_0, *)
nonisolated public struct ButtonMenuStyle: MenuStyle {
    nonisolated public init() {}

    nonisolated public func makeBody(configuration: Configuration) -> some View {
        configuration.label
    }
}

@available(OpenSwiftUI_v2_0, *)
extension View {
    /// Sets the style for menus within this view: menus draw themselves.
    nonisolated public func menuStyle<S>(_ style: S) -> some View where S: MenuStyle {
        self
    }
}

// MARK: - Picker styles

/// A picker style that presents the options in an inline list.
@available(OpenSwiftUI_v3_0, *)
public struct InlinePickerStyle: PickerStyle {
    public init() {}
    public static func _makeView<SelectionValue>(value: _GraphValue<_PickerValue<InlinePickerStyle, SelectionValue>>, inputs: _ViewInputs) -> _ViewOutputs where SelectionValue: Hashable {
        preconditionFailure("Picker styles' views are made by the picker")
    }
    public static func _makeViewList<SelectionValue>(value: _GraphValue<_PickerValue<InlinePickerStyle, SelectionValue>>, inputs: _ViewListInputs) -> _ViewListOutputs where SelectionValue: Hashable {
        preconditionFailure("Picker styles' views are made by the picker")
    }
}

// MARK: - Text input

/// The kinds of text a keyboard capitalizes on its own.
@available(OpenSwiftUI_v3_0, *)
public struct TextInputAutocapitalization: Sendable {
    var kind: Int

    public static var never: TextInputAutocapitalization { TextInputAutocapitalization(kind: 0) }
    public static var words: TextInputAutocapitalization { TextInputAutocapitalization(kind: 1) }
    public static var sentences: TextInputAutocapitalization { TextInputAutocapitalization(kind: 2) }
    public static var characters: TextInputAutocapitalization { TextInputAutocapitalization(kind: 3) }
}

/// What a text field's submission is triggered by.
@available(OpenSwiftUI_v3_0, *)
public struct SubmitTriggers: OptionSet, Sendable {
    public typealias RawValue = Int

    public let rawValue: Int

    public init(rawValue: Int) {
        self.rawValue = rawValue
    }

    public static let text = SubmitTriggers(rawValue: 1 << 0)
    public static let search = SubmitTriggers(rawValue: 1 << 1)
}

@available(OpenSwiftUI_v3_0, *)
extension View {
    /// Sets the kind of text the keyboard capitalizes.
    nonisolated public func textInputAutocapitalization(_ autocapitalization: TextInputAutocapitalization?) -> some View {
        self
    }

    /// Adds an action to perform when a text field is submitted: not yet.
    nonisolated public func onSubmit(of triggers: SubmitTriggers = .text, _ action: @escaping () -> Void) -> some View {
        self
    }

    /// Whether speech reads out punctuation.
    nonisolated public func speechAlwaysIncludesPunctuation(_ value: Bool = true) -> some View {
        self
    }

    /// Adds an action to perform when the view is dragged: not yet.
    nonisolated public func onDrag(_ data: @escaping () -> NSItemProvider) -> some View {
        self
    }
}

// MARK: - Accessibility

@available(OpenSwiftUI_v2_0, *)
extension View {
    /// Uses the string to identify the view: nothing reads it here.
    nonisolated public func accessibility(identifier: String) -> ModifiedContent<Self, AccessibilityAttachmentModifier> {
        accessibility()
    }
}

@available(OpenSwiftUI_v2_0, *)
extension ModifiedContent where Modifier == AccessibilityAttachmentModifier {
    nonisolated public func accessibility(identifier: String) -> ModifiedContent<Content, Modifier> {
        self
    }

    nonisolated public func accessibilityTextContentType(_ textContentType: AccessibilityTextContentType) -> ModifiedContent<Content, Modifier> {
        self
    }
}

// MARK: - Drawing and backgrounds

@available(OpenSwiftUI_v1_0, *)
extension View {
    /// Flattens the view into one image: it draws as it is.
    nonisolated public func drawingGroup(opaque: Bool = false, colorMode: ColorRenderingMode = .nonLinear) -> some View {
        self
    }

    /// Places a view behind a list row: not yet.
    @inlinable
    nonisolated public func listRowBackground<V>(_ view: V?) -> some View where V: View {
        self
    }
}

/// Where a container background goes.
@available(OpenSwiftUI_v5_0, *)
public struct ContainerBackgroundPlacement: Equatable, Sendable {
    var kind: Int

    public static var tabView: ContainerBackgroundPlacement { ContainerBackgroundPlacement(kind: 0) }
    public static var navigation: ContainerBackgroundPlacement { ContainerBackgroundPlacement(kind: 1) }
    public static var navigationSplitView: ContainerBackgroundPlacement { ContainerBackgroundPlacement(kind: 2) }
    public static var window: ContainerBackgroundPlacement { ContainerBackgroundPlacement(kind: 3) }
}

/// The trait a container background is kept in.
@available(OpenSwiftUI_v5_0, *)
public struct ContainerBackgroundTraitKey: _ViewTraitKey {
    public static var defaultValue: AnyView? { nil }
    public typealias Value = AnyView?
}

@available(OpenSwiftUI_v5_0, *)
extension View {
    /// Sets the container background: not drawn yet.
    nonisolated public func containerBackground<S>(_ style: S, for container: ContainerBackgroundPlacement) -> some View where S: ShapeStyle {
        self
    }

    nonisolated public func containerBackground<V>(for container: ContainerBackgroundPlacement, alignment: Alignment = .center, @ViewBuilder content: () -> V) -> some View where V: View {
        self
    }
}

// MARK: - Alignment

@available(OpenSwiftUI_v4_0, *)
extension VerticalAlignment {
    /// The center of the first line of text.
    public static var firstTextLineCenter: VerticalAlignment { _firstTextLineCenter }
}

// MARK: - Masks

/// A modifier that masks a view with another, placed by an alignment: the
/// mask is not applied yet.
@available(OpenSwiftUI_v3_0, *)
@frozen
public struct _MaskAlignmentEffect<Mask>: ViewModifier, PrimitiveViewModifier where Mask: View {
    public var alignment: Alignment
    public var mask: Mask

    @inlinable
    public init(alignment: Alignment, mask: Mask) {
        self.mask = mask
        self.alignment = alignment
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

@available(OpenSwiftUI_v3_0, *)
extension View {
    /// Masks the view with another view.
    @inlinable
    nonisolated public func mask<Mask>(alignment: Alignment = .center, @ViewBuilder _ mask: () -> Mask) -> some View where Mask: View {
        modifier(_MaskAlignmentEffect(alignment: alignment, mask: mask()))
    }
}

// MARK: - Preferences and scrolling

/// A modifier that overlays a view made from a preference's value: not
/// drawn yet.
@available(OpenSwiftUI_v4_0, *)
@frozen
public struct _OverlayPreferenceModifier<Key, Overlay>: ViewModifier, PrimitiveViewModifier where Key: PreferenceKey, Overlay: View {
    public var transform: (Key.Value) -> Overlay
    public var alignment: Alignment

    @inlinable
    public init(alignment: Alignment, @ViewBuilder transform: @escaping (Key.Value) -> Overlay) {
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

/// A modifier made from a scroll view's size and visible bounds: not applied yet.
@available(OpenSwiftUI_v3_0, *)
@frozen
public struct _ScrollViewBoundsModifier2<Result>: ViewModifier, PrimitiveViewModifier where Result: ViewModifier {
    public var transform: (CGSize, CGRect?) -> Result

    @inlinable
    public init(transform: @escaping (CGSize, CGRect?) -> Result) {
        self.transform = transform
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

@available(OpenSwiftUI_v3_0, *)
extension View {
    /// Applies a modifier made from the enclosing scroll view's size and bounds.
    nonisolated public func scrollViewBoundsModifier<M>(transform: @escaping (CGSize, CGRect?) -> M) -> some View where M: ViewModifier {
        modifier(_ScrollViewBoundsModifier2(transform: transform))
    }
}

@available(OpenSwiftUI_v3_0, *)
extension ScrollView {
    /// The axes along which the scroll view always bounces: it bounces as
    /// the platform's scroll view does.
    nonisolated public var _alwaysBounceAxes: Axis.Set {
        get { [] }
        set {}
    }
}

// MARK: - Toolbars

@available(OpenSwiftUI_v2_0, *)
extension ToolbarContentBuilder {
    public static func buildIf<Content>(_ content: Content?) -> Content? where Content: ToolbarContent {
        content
    }
}
#endif
