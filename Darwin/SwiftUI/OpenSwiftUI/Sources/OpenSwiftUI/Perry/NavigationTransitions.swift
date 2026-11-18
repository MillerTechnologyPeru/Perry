//
//  NavigationTransitions.swift
//  OpenSwiftUI
//
//  Status: Perry's implementation, inert
//
//  Navigation transitions, the sources a zoom transition grows from, and
//  the navigation subtitle. Perry's navigation stack pushes and pops its
//  pages one way only, and its sheets are presented as UIKit presents view
//  controllers: a transition is taken and ignored, a source is drawn as the
//  view it marks, and no configuration of a source is ever read. The bar
//  has no place for a subtitle.

#if os(iOS) || os(visionOS)
public import OpenSwiftUICore

// MARK: - NavigationTransition

/// A type that says how a pushed page or a presented view comes into view.
@available(OpenSwiftUI_v1_0, *)
public protocol NavigationTransition {
    func _outputs(for inputs: _NavigationTransitionInputs) -> _NavigationTransitionOutputs
}

/// What a navigation transition is made from; nothing here.
@available(OpenSwiftUI_v1_0, *)
public struct _NavigationTransitionInputs: Sendable {
}

/// What a navigation transition makes; nothing here.
@available(OpenSwiftUI_v1_0, *)
public struct _NavigationTransitionOutputs: Sendable {
}

@available(OpenSwiftUI_v1_0, *)
extension View {
    /// Sets how this view comes into view when it is pushed or presented;
    /// Perry's pages and sheets keep their own transition.
    nonisolated public func navigationTransition(_ style: some NavigationTransition) -> some View {
        self
    }
}

/// A transition that grows the view from a source view marked with
/// `matchedTransitionSource`. The source is remembered but not looked up.
@available(OpenSwiftUI_v1_0, *)
public struct ZoomNavigationTransition: NavigationTransition {
    var sourceID: AnyHashable
    var namespace: Namespace.ID

    public func _outputs(for inputs: _NavigationTransitionInputs) -> _NavigationTransitionOutputs {
        _NavigationTransitionOutputs()
    }
}

@available(*, unavailable)
extension ZoomNavigationTransition: Sendable {}

@available(OpenSwiftUI_v1_0, *)
extension NavigationTransition where Self == ZoomNavigationTransition {
    /// A transition that zooms from the source view with the given
    /// identifier in a namespace.
    public static func zoom(sourceID: some Hashable, in namespace: Namespace.ID) -> ZoomNavigationTransition {
        ZoomNavigationTransition(sourceID: AnyHashable(sourceID), namespace: namespace)
    }
}

// MARK: - Matched transition sources

/// The look of a transition source, as its configurations have set it;
/// nothing is kept here.
@available(OpenSwiftUI_v1_0, *)
public struct _ResolvedMatchedTransitionSourceConfiguration: Sendable {
}

/// A type that sets the look of the source of a zoom transition.
@available(OpenSwiftUI_v1_0, *)
public protocol MatchedTransitionSourceConfiguration: Sendable {
    func _update(configuration: inout _ResolvedMatchedTransitionSourceConfiguration)
}

/// The configuration a source starts from, which changes nothing.
@available(OpenSwiftUI_v1_0, *)
public struct EmptyMatchedTransitionSourceConfiguration: MatchedTransitionSourceConfiguration {
    public func _update(configuration: inout _ResolvedMatchedTransitionSourceConfiguration) {}
}

@available(OpenSwiftUI_v1_0, *)
extension MatchedTransitionSourceConfiguration {
    /// Clips the source to a rounded rectangle while it zooms; the shape
    /// isn't kept, as no source zooms here.
    public func clipShape(_ shape: RoundedRectangle) -> some MatchedTransitionSourceConfiguration {
        self
    }
}

@available(OpenSwiftUI_v1_0, *)
extension View {
    /// Marks this view as the source a zoom transition grows from. The view
    /// is drawn as it is.
    nonisolated public func matchedTransitionSource(id: some Hashable, in namespace: Namespace.ID) -> some View {
        self
    }

    /// Marks this view as the source a zoom transition grows from, with a
    /// configuration of its look. The view is drawn as it is, and the
    /// configuration isn't asked for.
    nonisolated public func matchedTransitionSource(
        id: some Hashable,
        in namespace: Namespace.ID,
        configuration: (EmptyMatchedTransitionSourceConfiguration) -> some MatchedTransitionSourceConfiguration
    ) -> some View {
        self
    }
}

// MARK: - Subtitle

@available(OpenSwiftUI_v1_0, *)
extension View {
    /// Sets a subtitle for the navigation bar. Perry's bar shows a title
    /// only.
    nonisolated public func navigationSubtitle(_ subtitle: Text) -> some View {
        self
    }
}

#endif
