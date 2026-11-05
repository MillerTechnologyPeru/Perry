// Annotations: views a map draws at a coordinate, with their title under
// them, and at the user's location.

public import CoreLocation
public import MapKit
public import OpenSwiftUI

// MARK: - Annotation

/// A view a map shows at a coordinate.
@preconcurrency
@MainActor
public struct Annotation<Label, Content>: MapContent, PrimitiveMapContent where Label: View, Content: View {
    public typealias Body = Never

    var coordinate: CLLocationCoordinate2D
    var anchor: UnitPoint
    var content: Content
    var label: Label

    @preconcurrency
    @MainActor
    public init(
        coordinate: CLLocationCoordinate2D,
        anchor: UnitPoint = .center,
        accessoryAnchor: UnitPoint,
        @ViewBuilder content: () -> Content,
        @ViewBuilder label: () -> Label
    ) {
        self.init(coordinate: coordinate, anchor: anchor, content: content, label: label)
    }

    @preconcurrency
    @MainActor
    public init(
        coordinate: CLLocationCoordinate2D,
        anchor: UnitPoint = .center,
        @ViewBuilder content: () -> Content,
        @ViewBuilder label: () -> Label
    ) {
        self.coordinate = coordinate
        self.anchor = anchor
        self.content = content()
        self.label = label()
    }

    @preconcurrency
    @MainActor
    public init(
        _ titleKey: LocalizedStringKey,
        coordinate: CLLocationCoordinate2D,
        anchor: UnitPoint = .center,
        accessoryAnchor: UnitPoint,
        @ViewBuilder content: () -> Content
    ) where Label == Text {
        self.init(coordinate: coordinate, anchor: anchor, content: content) { Text(titleKey) }
    }

    @preconcurrency
    @MainActor
    public init(
        _ titleKey: LocalizedStringKey,
        coordinate: CLLocationCoordinate2D,
        anchor: UnitPoint = .center,
        @ViewBuilder content: () -> Content
    ) where Label == Text {
        self.init(coordinate: coordinate, anchor: anchor, content: content) { Text(titleKey) }
    }

    @preconcurrency
    @MainActor
    public init<S>(
        _ title: S,
        coordinate: CLLocationCoordinate2D,
        anchor: UnitPoint = .center,
        accessoryAnchor: UnitPoint,
        @ViewBuilder content: () -> Content
    ) where Label == Text, S: StringProtocol {
        self.init(coordinate: coordinate, anchor: anchor, content: content) { Text(title) }
    }

    @preconcurrency
    @MainActor
    public init<S>(
        _ title: S,
        coordinate: CLLocationCoordinate2D,
        anchor: UnitPoint = .center,
        @ViewBuilder content: () -> Content
    ) where Label == Text, S: StringProtocol {
        self.init(coordinate: coordinate, anchor: anchor, content: content) { Text(title) }
    }

    @MainActor
    @preconcurrency
    public static func _mapContentCount(inputs: _MapContentInputs) -> Int? { 1 }

    @MainActor
    @preconcurrency
    public static func _makeMapContent(content: _GraphValue<Annotation<Label, Content>>, inputs: _MapContentInputs) -> _MapContentOutputs {
        _MapContentOutputs()
    }

    var mapItems: [MapItem] {
        [.annotation(coordinate: coordinate, anchor: anchor, content: AnyView(content), label: AnyView(label))]
    }
}

// MARK: - The user's location

/// The user's location and heading, as user annotations are given them.
public struct UserLocation {
    var current: CLLocation?

    public var location: CLLocation? { current }
    public var heading: CLHeading? { nil }
}

/// The way the map follows the user's location.
public enum MapUserTrackingMode {
    case none
    case follow
    case followWithHeading
}

/// Content that shows the user's location.
@preconcurrency
@MainActor
public struct UserAnnotation<Content>: MapContent, PrimitiveMapContent where Content: View {
    public typealias Body = Never

    var anchor: UnitPoint
    var content: (UserLocation) -> Content

    @_disfavoredOverload
    @preconcurrency
    @MainActor
    public init(anchor: UnitPoint = .center) where Content == EmptyView {
        self.init(anchor: anchor) { EmptyView() }
    }

    @preconcurrency
    @MainActor
    public init() where Content == DefaultUserAnnotationContent {
        self.init(anchor: .center) { DefaultUserAnnotationContent() }
    }

    @preconcurrency
    @MainActor
    public init(anchor: UnitPoint = .center, @ViewBuilder content: @escaping () -> Content) {
        self.anchor = anchor
        self.content = { _ in content() }
    }

    @preconcurrency
    @MainActor
    public init(anchor: UnitPoint = .center, @ViewBuilder content: @escaping (UserLocation) -> Content) {
        self.anchor = anchor
        self.content = content
    }

    @MainActor
    @preconcurrency
    public static func _mapContentCount(inputs: _MapContentInputs) -> Int? { 1 }

    @MainActor
    @preconcurrency
    public static func _makeMapContent(content: _GraphValue<UserAnnotation<Content>>, inputs: _MapContentInputs) -> _MapContentOutputs {
        _MapContentOutputs()
    }

    var mapItems: [MapItem] {
        [.userLocation(anchor: anchor, content: AnyView(content(UserLocation())))]
    }
}

/// The user's location as maps show it: a blue dot ringed with white.
@preconcurrency
@MainActor
public struct DefaultUserAnnotationContent: View {
    @preconcurrency
    @MainActor
    public var body: some View {
        Circle()
            .fill(Color.blue)
            .frame(width: 16, height: 16)
            .padding(3)
            .background(Circle().fill(Color.white))
    }
}
