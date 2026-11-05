//
//  Modifiers.swift
//  OpenSwiftUI
//
//  Status: Perry's implementation, interim
//
//  Modifiers with a plainer effect than Apple's: Liquid Glass as a
//  translucent fill of its shape; and some with none yet: list row and
//  section separators, swipe actions, context menus, masks, scroll content
//  backgrounds' visibility, and accessibility labels, values, hints and
//  identifiers, which nothing reads.

#if os(iOS) || os(visionOS)
public import OpenSwiftUICore

// MARK: - Glass

/// The structure that defines a Liquid Glass material.
@available(OpenSwiftUI_v7_0, *)
public struct Glass: Equatable, Sendable {
    var tintColor: Color?
    var isInteractive: Bool
    var opacity: Double

    public static var regular: Glass { Glass(tintColor: nil, isInteractive: false, opacity: 0.7) }
    public static var clear: Glass { Glass(tintColor: nil, isInteractive: false, opacity: 0.3) }
    public static var identity: Glass { Glass(tintColor: nil, isInteractive: false, opacity: 0) }

    public func tint(_ color: Color?) -> Glass {
        var glass = self
        glass.tintColor = color
        return glass
    }

    public func interactive(_ isEnabled: Bool = true) -> Glass {
        var glass = self
        glass.isInteractive = isEnabled
        return glass
    }
}

@available(OpenSwiftUI_v7_0, *)
extension View {
    /// Applies the Liquid Glass effect to a view: a translucent fill of the
    /// shape behind it.
    nonisolated public func glassEffect(_ glass: Glass = .regular, in shape: some Shape) -> some View {
        background(shape.fill((glass.tintColor ?? Color.white).opacity(glass.opacity)))
    }
}

// MARK: - Visibility of lists' and scroll views' chrome

@available(OpenSwiftUI_v3_0, *)
extension View {
    /// Sets the display mode for the separator associated with this
    /// specific row.
    nonisolated public func listRowSeparator(_ visibility: Visibility, edges: VerticalEdge.Set = .all) -> some View {
        self
    }
}

@available(OpenSwiftUI_v4_0, *)
extension View {
    /// Specifies the visibility of the background for scrollable views
    /// within this view.
    nonisolated public func scrollContentBackground(_ visibility: Visibility) -> some View {
        self
    }
}

// MARK: - Accessibility

@available(OpenSwiftUI_v2_0, *)
extension View {
    /// Adds a label to the view that describes its contents.
    nonisolated public func accessibilityLabel(_ labelKey: LocalizedStringKey) -> ModifiedContent<Self, AccessibilityAttachmentModifier> {
        accessibility()
    }

    /// Uses the string you specify to identify the view.
    nonisolated public func accessibilityIdentifier(_ identifier: String) -> ModifiedContent<Self, AccessibilityAttachmentModifier> {
        accessibility()
    }

    /// Adds a label to the view that describes its contents.
    nonisolated public func accessibilityLabel(_ label: Text) -> ModifiedContent<Self, AccessibilityAttachmentModifier> {
        accessibility()
    }

    /// Adds a label to the view that describes its contents.
    @_disfavoredOverload
    nonisolated public func accessibilityLabel<S>(_ label: S) -> ModifiedContent<Self, AccessibilityAttachmentModifier> where S: StringProtocol {
        accessibility()
    }

    /// Adds a textual description of the value that the view contains.
    nonisolated public func accessibilityValue(_ valueDescription: Text) -> ModifiedContent<Self, AccessibilityAttachmentModifier> {
        accessibility()
    }

    /// Adds a textual description of the value that the view contains.
    nonisolated public func accessibilityValue(_ valueKey: LocalizedStringKey) -> ModifiedContent<Self, AccessibilityAttachmentModifier> {
        accessibility()
    }

    /// Adds a textual description of the value that the view contains.
    @_disfavoredOverload
    nonisolated public func accessibilityValue<S>(_ value: S) -> ModifiedContent<Self, AccessibilityAttachmentModifier> where S: StringProtocol {
        accessibility()
    }

    /// Communicates to the user what happens after performing the view's
    /// action.
    nonisolated public func accessibilityHint(_ hint: Text) -> ModifiedContent<Self, AccessibilityAttachmentModifier> {
        accessibility()
    }

    /// Communicates to the user what happens after performing the view's
    /// action.
    nonisolated public func accessibilityHint(_ hintKey: LocalizedStringKey) -> ModifiedContent<Self, AccessibilityAttachmentModifier> {
        accessibility()
    }

    /// Communicates to the user what happens after performing the view's
    /// action.
    @_disfavoredOverload
    nonisolated public func accessibilityHint<S>(_ hint: S) -> ModifiedContent<Self, AccessibilityAttachmentModifier> where S: StringProtocol {
        accessibility()
    }

    /// Specifies whether to hide this view from system accessibility
    /// features.
    nonisolated public func accessibilityHidden(_ hidden: Bool) -> ModifiedContent<Self, AccessibilityAttachmentModifier> {
        accessibility()
    }

    /// Adds an accessibility scroll action to the view.
    nonisolated public func accessibilityScrollAction(_ handler: @escaping (Edge) -> Void) -> ModifiedContent<Self, AccessibilityAttachmentModifier> {
        accessibility()
    }
}

@available(OpenSwiftUI_v1_0, *)
extension View {
    /// Creates a new accessibility element, or makes the view's children
    /// one.
    nonisolated public func accessibilityElement(children: AccessibilityChildBehavior = .ignore) -> some View {
        self
    }
}

@available(OpenSwiftUI_v2_0, *)
extension Text {
    /// Adds a label to the view that describes its contents.
    nonisolated public func accessibilityLabel(_ label: Text) -> Text { self }

    /// Adds a label to the view that describes its contents.
    nonisolated public func accessibilityLabel(_ labelKey: LocalizedStringKey) -> Text { self }

    /// Adds a label to the view that describes its contents.
    @_disfavoredOverload
    nonisolated public func accessibilityLabel<S>(_ label: S) -> Text where S: StringProtocol { self }
}

@available(OpenSwiftUI_v2_0, *)
extension ModifiedContent where Modifier == AccessibilityAttachmentModifier {
    /// Adds a textual description of the value that the view contains.
    nonisolated public func accessibilityValue(_ valueDescription: Text) -> ModifiedContent<Content, Modifier> {
        self
    }

    /// Uses the string you specify to identify the view.
    nonisolated public func accessibilityIdentifier(_ identifier: String) -> ModifiedContent<Content, Modifier> {
        self
    }

    /// Adds a textual description of the value that the view contains.
    nonisolated public func accessibilityValue(_ valueKey: LocalizedStringKey) -> ModifiedContent<Content, Modifier> {
        self
    }

    /// Adds a textual description of the value that the view contains.
    @_disfavoredOverload
    nonisolated public func accessibilityValue<S>(_ value: S) -> ModifiedContent<Content, Modifier> where S: StringProtocol {
        self
    }

    /// Adds a label to the view that describes its contents.
    nonisolated public func accessibilityLabel(_ label: Text) -> ModifiedContent<Content, Modifier> {
        self
    }

    /// Adds a label to the view that describes its contents.
    @_disfavoredOverload
    nonisolated public func accessibilityLabel<S>(_ label: S) -> ModifiedContent<Content, Modifier> where S: StringProtocol {
        self
    }

    /// Communicates to the user what happens after performing the view's
    /// action.
    nonisolated public func accessibilityHint(_ hint: Text) -> ModifiedContent<Content, Modifier> {
        self
    }

    /// Communicates to the user what happens after performing the view's
    /// action.
    @_disfavoredOverload
    nonisolated public func accessibilityHint<S>(_ hint: S) -> ModifiedContent<Content, Modifier> where S: StringProtocol {
        self
    }

    /// Specifies whether to hide this view from system accessibility
    /// features.
    nonisolated public func accessibilityHidden(_ hidden: Bool) -> ModifiedContent<Content, Modifier> {
        self
    }
}

// MARK: - Masks

/// A modifier that masks a view with another: here, the view is drawn whole
/// for now.
@available(OpenSwiftUI_v1_0, *)
@frozen
public struct _MaskEffect<Mask>: ViewModifier where Mask: View {
    public var mask: Mask

    @inlinable
    nonisolated public init(mask: Mask) {
        self.mask = mask
    }

    public func body(content: Content) -> some View {
        content
    }
}

// MARK: - Lists

/// The trait holding a list row's background.
@available(OpenSwiftUI_v1_0, *)
@usableFromInline
struct ListRowBackgroundTraitKey: _ViewTraitKey {
    @inlinable
    static var defaultValue: AnyView? { nil }
}

@available(OpenSwiftUI_v3_0, *)
extension View {
    /// Sets the tint color associated with a row's separators.
    nonisolated public func listRowSeparatorTint(_ color: Color?, edges: VerticalEdge.Set = .all) -> some View {
        self
    }

    /// Sets whether to hide the separator associated with a list section.
    nonisolated public func listSectionSeparator(_ visibility: Visibility, edges: VerticalEdge.Set = .all) -> some View {
        self
    }

    /// Sets the tint color associated with a section's separators.
    nonisolated public func listSectionSeparatorTint(_ color: Color?, edges: VerticalEdge.Set = .all) -> some View {
        self
    }

    /// Adds custom swipe actions to a row in a list; rows here are not
    /// swiped yet.
    nonisolated public func swipeActions<T>(edge: HorizontalEdge = .trailing, allowsFullSwipe: Bool = true, @ViewBuilder content: () -> T) -> some View where T: View {
        self
    }
}

// MARK: - Context menus

@available(OpenSwiftUI_v1_0, *)
extension View {
    /// Adds a context menu to a view; views here are not long-pressed yet.
    nonisolated public func contextMenu<MenuItems>(@ViewBuilder menuItems: () -> MenuItems) -> some View where MenuItems: View {
        self
    }
}

@available(OpenSwiftUI_v4_0, *)
extension View {
    /// Adds a context menu with a custom preview to a view.
    nonisolated public func contextMenu<M, P>(@ViewBuilder menuItems: () -> M, @ViewBuilder preview: () -> P) -> some View where M: View, P: View {
        self
    }
}

// MARK: - Materials

@available(OpenSwiftUI_v3_0, *)
extension Material {
    /// A material matching the style of system toolbars.
    public static var bar: Material { Material(id: .systemBars) }
}

// MARK: - Never

@available(OpenSwiftUI_v1_0, *)
extension Never {
    /// Never's body, for the content protocols it conforms to.
    public var body: Never { preconditionFailure("Never has no body") }
}
#endif
