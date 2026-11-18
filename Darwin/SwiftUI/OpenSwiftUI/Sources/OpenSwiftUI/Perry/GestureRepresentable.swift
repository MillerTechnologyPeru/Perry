//
//  GestureRepresentable.swift
//  OpenSwiftUI
//
//  Status: Perry's implementation
//
//  UIKit gesture recognizers as gestures of a view. Perry doesn't attach
//  such recognizers yet: a view takes the gesture and stays as it is, the
//  representable is never asked for its coordinator or its recognizer, and
//  its action is never called. A coordinate space converter, which only a
//  recognizer's context would hand out, answers with the origin.

#if os(iOS) || os(visionOS)
public import Foundation
public import OpenSwiftUICore
public import UIKit

// MARK: - UIGestureRecognizerRepresentable

/// A wrapper for a `UIGestureRecognizer` that you use to integrate that
/// gesture recognizer into your view hierarchy.
@available(OpenSwiftUI_v1_0, *)
@preconcurrency
@MainActor
public protocol UIGestureRecognizerRepresentable {
    /// The type of gesture recognizer to present.
    associatedtype UIGestureRecognizerType: UIGestureRecognizer

    /// A type to coordinate with the gesture recognizer.
    associatedtype Coordinator = Void

    typealias Context = UIGestureRecognizerRepresentableContext<Self>

    typealias CoordinateSpaceConverter = UIGestureRecognizerRepresentableCoordinateSpaceConverter

    /// Creates the custom instance that you use to communicate changes
    /// from your gesture recognizer to other parts of your interface.
    @MainActor
    @preconcurrency
    func makeCoordinator(converter: CoordinateSpaceConverter) -> Coordinator

    /// Creates the gesture recognizer and configures its initial state.
    @MainActor
    @preconcurrency
    func makeUIGestureRecognizer(context: Context) -> UIGestureRecognizerType

    /// Updates the gesture recognizer's state with new information.
    @MainActor
    @preconcurrency
    func updateUIGestureRecognizer(_ recognizer: UIGestureRecognizerType, context: Context)

    /// Responds to the gesture recognizer's action.
    @MainActor
    @preconcurrency
    func handleUIGestureRecognizerAction(_ recognizer: UIGestureRecognizerType, context: Context)
}

@available(OpenSwiftUI_v1_0, *)
extension UIGestureRecognizerRepresentable {
    @MainActor
    @preconcurrency
    public func updateUIGestureRecognizer(_ recognizer: UIGestureRecognizerType, context: Context) {}

    @MainActor
    @preconcurrency
    public func handleUIGestureRecognizerAction(_ recognizer: UIGestureRecognizerType, context: Context) {}
}

@available(OpenSwiftUI_v1_0, *)
extension UIGestureRecognizerRepresentable where Coordinator == () {
    @MainActor
    @preconcurrency
    public func makeCoordinator(converter: CoordinateSpaceConverter) {}
}

// MARK: - Context

/// Contextual information about the state of the system that you use to
/// create and update a represented gesture recognizer.
@available(OpenSwiftUI_v1_0, *)
public struct UIGestureRecognizerRepresentableContext<Representable> where Representable: UIGestureRecognizerRepresentable {
    /// The gesture's coordinator.
    public let coordinator: Representable.Coordinator

    /// A converter of locations between the gesture's coordinate spaces.
    public let converter: UIGestureRecognizerRepresentableCoordinateSpaceConverter
}

@available(*, unavailable)
extension UIGestureRecognizerRepresentableContext: Sendable {}

/// A proxy that converts a gesture's locations to coordinate spaces. With
/// no recognizer attached there is no location to convert.
@available(OpenSwiftUI_v1_0, *)
public struct UIGestureRecognizerRepresentableCoordinateSpaceConverter {
    /// The location of the gesture in the coordinate space: the origin,
    /// as no gesture is tracked.
    public func location(in coordinateSpace: some CoordinateSpaceProtocol) -> CGPoint {
        .zero
    }
}

@available(*, unavailable)
extension UIGestureRecognizerRepresentableCoordinateSpaceConverter: Sendable {}

// MARK: - View

@available(OpenSwiftUI_v1_0, *)
extension View {
    /// Attaches a gesture recognizer representable to the view. The
    /// recognizer isn't made or attached: the view is returned as it is.
    nonisolated public func gesture(_ representable: some UIGestureRecognizerRepresentable) -> some View {
        self
    }
}
#endif
