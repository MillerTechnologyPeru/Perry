//
//  Modifiers.swift
//  OpenSwiftUI
//
//  Status: Perry's implementation, interim
//
//  Modifiers with a plainer effect than Apple's: Liquid Glass as a
//  translucent fill of its shape; and some with none yet: list row
//  separators' and scroll content backgrounds' visibility, and
//  accessibility labels, values and identifiers, which nothing reads.

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
}
#endif
