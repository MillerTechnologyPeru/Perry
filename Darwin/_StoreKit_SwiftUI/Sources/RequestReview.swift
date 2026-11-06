// SwiftUI's StoreKit API: the action that asks the user to rate the app,
// which here asks nothing, as there is no App Store to rate it in.

public import OpenSwiftUI

/// An action that asks the user for a review of the app.
@available(iOS 16.0, *)
@MainActor
public struct RequestReviewAction: Sendable {
    nonisolated init() {}

    /// Asks for a review: nothing is shown here.
    @MainActor
    public func callAsFunction() {}
}

@available(iOS 16.0, *)
extension EnvironmentValues {
    /// The action that asks the user for a review of the app.
    public var requestReview: RequestReviewAction { RequestReviewAction() }
}
