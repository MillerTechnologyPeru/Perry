// Map: an MKMapView (Perry's MapKit provider, its map drawn by MapLibre)
// with the map content's annotations drawn over it as SwiftUI views where
// their coordinates fall in the visible region, and the controls
// mapControls gives along its trailing edge. The camera position binding moves the map, and the map's
// moves are written back to it, and reported to onMapCameraChange's
// actions.

public import CoreLocation
public import MapKit
public import OpenSwiftUI
import UIKit

// MARK: - Environment

/// What maps under a view read from it: their style, their controls and
/// the actions to run as their cameras move.
struct MapEnvironment {
    var style: MapStyle = .standard
    var controls: AnyView?
    var cameraActions: [(frequency: MapCameraUpdateFrequency, action: (MapCameraUpdateContext) -> Void)] = []
}

struct MapEnvironmentKey: EnvironmentKey {
    static let defaultValue = MapEnvironment()
}

/// The region a map shows, for the controls drawn over it.
struct MapVisibleRegionKey: EnvironmentKey {
    static let defaultValue: MKCoordinateRegion? = nil
}

extension EnvironmentValues {
    var mapEnvironment: MapEnvironment {
        get { self[MapEnvironmentKey.self] }
        set { self[MapEnvironmentKey.self] = newValue }
    }

    var mapVisibleRegion: MKCoordinateRegion? {
        get { self[MapVisibleRegionKey.self] }
        set { self[MapVisibleRegionKey.self] = newValue }
    }
}

extension View {
    /// Sets how maps in this view draw their tiles.
    @MainActor
    @preconcurrency
    public func mapStyle(_ value: MapStyle) -> some View {
        transformEnvironment(\.mapEnvironment) { $0.style = value }
    }

    /// Sets the controls maps in this view show.
    @MainActor
    @preconcurrency
    public func mapControls(@ViewBuilder _ content: () -> some View) -> some View {
        let controls = AnyView(content())
        return transformEnvironment(\.mapEnvironment) { $0.controls = controls }
    }

    /// Runs an action when the camera of a map in this view moves.
    @MainActor
    @preconcurrency
    public func onMapCameraChange(
        frequency: MapCameraUpdateFrequency = .onEnd,
        _ action: @escaping () -> Void
    ) -> some View {
        transformEnvironment(\.mapEnvironment) { $0.cameraActions.append((frequency, { _ in action() })) }
    }

    /// Runs an action, given where the camera is, when the camera of a map
    /// in this view moves.
    @MainActor
    @preconcurrency
    public func onMapCameraChange(
        frequency: MapCameraUpdateFrequency = .onEnd,
        _ action: @escaping (MapCameraUpdateContext) -> Void
    ) -> some View {
        transformEnvironment(\.mapEnvironment) { $0.cameraActions.append((frequency, action)) }
    }
}

// MARK: - Map

/// A view that displays an embedded map interface.
@preconcurrency
@MainActor
public struct Map<Content>: View where Content: View {
    var content: Content

    @preconcurrency
    @MainActor
    public var body: some View {
        content
    }
}

extension Map {
    @preconcurrency
    @MainActor
    public init(
        bounds: MapCameraBounds? = nil,
        interactionModes: MapInteractionModes = .all,
        scope: Namespace.ID? = nil
    ) where Content == MapContentView<Never, EmptyMapContent> {
        self.init(initialPosition: .automatic, bounds: bounds, interactionModes: interactionModes, scope: scope) {
            EmptyMapContent()
        }
    }

    @preconcurrency
    @MainActor
    public init<C>(
        bounds: MapCameraBounds? = nil,
        interactionModes: MapInteractionModes = .all,
        scope: Namespace.ID? = nil,
        @MapContentBuilder content: () -> C
    ) where Content == MapContentView<Never, C>, C: MapContent {
        self.init(initialPosition: .automatic, bounds: bounds, interactionModes: interactionModes, scope: scope, content: content)
    }

    @preconcurrency
    @MainActor
    public init(
        initialPosition: MapCameraPosition,
        bounds: MapCameraBounds? = nil,
        interactionModes: MapInteractionModes = .all,
        scope: Namespace.ID? = nil
    ) where Content == MapContentView<Never, EmptyMapContent> {
        self.init(initialPosition: initialPosition, bounds: bounds, interactionModes: interactionModes, scope: scope) {
            EmptyMapContent()
        }
    }

    @preconcurrency
    @MainActor
    public init<C>(
        initialPosition: MapCameraPosition,
        bounds: MapCameraBounds? = nil,
        interactionModes: MapInteractionModes = .all,
        scope: Namespace.ID? = nil,
        @MapContentBuilder content: () -> C
    ) where Content == MapContentView<Never, C>, C: MapContent {
        self.content = MapContentView(
            position: nil, initialPosition: initialPosition, bounds: bounds,
            interactionModes: interactionModes, content: content()
        )
    }

    @preconcurrency
    @MainActor
    public init(
        position: Binding<MapCameraPosition>,
        bounds: MapCameraBounds? = nil,
        interactionModes: MapInteractionModes = .all,
        scope: Namespace.ID? = nil
    ) where Content == MapContentView<Never, EmptyMapContent> {
        self.init(position: position, bounds: bounds, interactionModes: interactionModes, scope: scope) {
            EmptyMapContent()
        }
    }

    @preconcurrency
    @MainActor
    public init<C>(
        position: Binding<MapCameraPosition>,
        bounds: MapCameraBounds? = nil,
        interactionModes: MapInteractionModes = .all,
        scope: Namespace.ID? = nil,
        @MapContentBuilder content: () -> C
    ) where Content == MapContentView<Never, C>, C: MapContent {
        self.content = MapContentView(
            position: position, initialPosition: position.wrappedValue, bounds: bounds,
            interactionModes: interactionModes, content: content()
        )
    }
}

// MARK: - MapContentView

/// A map showing its content.
@preconcurrency
@MainActor
public struct MapContentView<SelectionValue, Content>: View where SelectionValue: Hashable, Content: MapContent {
    var position: Binding<MapCameraPosition>?
    var initialPosition: MapCameraPosition
    var bounds: MapCameraBounds?
    var interactionModes: MapInteractionModes
    var content: Content
    @State private var visibleRegion: MKCoordinateRegion?
    @State private var userCoordinate: CLLocationCoordinate2D?
    @Environment(\.mapEnvironment) private var environment

    @preconcurrency
    @MainActor
    public var body: some View {
        mapKitBody
    }

    @MainActor @ViewBuilder
    var mapKitBody: some View {
        let items = content.mapItems
        let showsUser = items.contains { if case .userLocation = $0 { return true } else { return false } }
        let target = (position?.wrappedValue ?? initialPosition)
        ZStack(alignment: .topTrailing) {
            MapViewRepresentable(
                position: target,
                followsBinding: position != nil,
                interactionModes: interactionModes,
                style: environment.style,
                showsUserLocation: showsUser,
                regionChanged: { region, user, finished in
                    visibleRegion = region
                    if userCoordinate?.latitude != user?.latitude || userCoordinate?.longitude != user?.longitude {
                        userCoordinate = user
                    }
                    if finished, let position, !position.wrappedValue.isPositionedByUser || position.wrappedValue.resolvedRegion == nil {
                        var moved = MapCameraPosition.region(region)
                        moved.isPositionedByUser = true
                        position.wrappedValue = moved
                    }
                    let context = MapCameraUpdateContext(region: region)
                    for entry in environment.cameraActions where finished || entry.frequency.isContinuous {
                        entry.action(context)
                    }
                }
            )
            GeometryReader { proxy in
                if let region = visibleRegion {
                    // The user's location under the annotations, as MapKit
                    // draws it.
                    ForEach(Self.drawingOrder(items), id: \.self) { index in
                        MapItemView(item: items[index], region: region, size: proxy.size, userCoordinate: userCoordinate)
                    }
                }
            }
            .allowsHitTesting(visibleRegion != nil)
            if let controls = environment.controls {
                VStack(spacing: 8) { controls }
                    .padding(8)
                    .environment(\.mapVisibleRegion, visibleRegion)
            }
        }
        .clipped()
    }
}

extension MapContentView {
    /// The items' indices, the user's location first, then the rest in
    /// their order.
    static func drawingOrder(_ items: [MapItem]) -> [Int] {
        func isUser(_ item: MapItem) -> Bool {
            if case .userLocation = item { return true }
            return false
        }
        return items.indices.filter { isUser(items[$0]) } + items.indices.filter { !isUser(items[$0]) }
    }
}

/// One item drawn where its coordinate falls in the visible region.
struct MapItemView: View {
    var item: MapItem
    var region: MKCoordinateRegion
    var size: CGSize
    /// Where the user is, as the map view knows it; nil if unknown.
    var userCoordinate: CLLocationCoordinate2D?

    /// Where a coordinate falls in the view, on the map's Mercator
    /// projection.
    func point(_ coordinate: CLLocationCoordinate2D) -> CGPoint {
        let rect = MapGeometry.rect(of: region)
        let mapPoint = MKMapPoint(coordinate)
        guard rect.width > 0, rect.height > 0 else { return CGPoint(x: -1000, y: -1000) }
        return CGPoint(x: (mapPoint.x - rect.minX) / rect.width * size.width,
                       y: (mapPoint.y - rect.minY) / rect.height * size.height)
    }

    var body: some View {
        switch item {
        case let .annotation(coordinate, anchor, content, label):
            // As MapKit draws them: the content with its anchor at the
            // coordinate, and the title on its own, centered under the
            // coordinate, in up to two lines haloed in white.
            let at = point(coordinate)
            ZStack(alignment: .topLeading) {
                AnchoredLayout(point: at, anchor: anchor) { content }
                if let label {
                    AnchoredLayout(point: CGPoint(x: at.x, y: at.y + 2), anchor: .top) {
                        MapTitle(label: label)
                    }
                    .allowsHitTesting(false)
                }
            }
        case let .userLocation(anchor, content):
            if let userCoordinate {
                AnchoredLayout(point: point(userCoordinate), anchor: anchor) { content }
            }
        }
    }
}

/// An annotation's title: semibold caption text in up to two centered
/// lines in a column 100 points wide, haloed in white so it reads over the map.
struct MapTitle: View {
    var label: AnyView

    var body: some View {
        let text = label
            .font(.caption.weight(.semibold))
            .multilineTextAlignment(.center)
            .lineLimit(2)
            .frame(width: 100)
            .fixedSize(horizontal: false, vertical: true)
        ZStack {
            ForEach(Self.halo.indices, id: \.self) { index in
                text.foregroundStyle(Color.white).offset(x: Self.halo[index].x, y: Self.halo[index].y)
            }
            text.foregroundStyle(Color.primary)
        }
    }

    /// The halo's offsets: the title drawn in white around itself.
    static let halo: [CGPoint] = [
        CGPoint(x: -1, y: 0), CGPoint(x: 1, y: 0), CGPoint(x: 0, y: -1), CGPoint(x: 0, y: 1),
        CGPoint(x: -1, y: -1), CGPoint(x: 1, y: 1), CGPoint(x: -1, y: 1), CGPoint(x: 1, y: -1),
    ]
}

/// Places its view at its ideal size with its anchor point at a point.
struct AnchoredLayout: Layout {
    var point: CGPoint
    var anchor: UnitPoint

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        proposal.replacingUnspecifiedDimensions()
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            subview.place(
                at: CGPoint(x: bounds.minX + point.x - size.width * anchor.x, y: bounds.minY + point.y - size.height * anchor.y),
                proposal: ProposedViewSize(size)
            )
        }
    }
}

// MARK: - The MKMapView

struct MapViewRepresentable: UIViewRepresentable {
    var position: MapCameraPosition
    var followsBinding: Bool
    var interactionModes: MapInteractionModes
    var style: MapStyle
    var showsUserLocation: Bool
    /// The region shown, where the user is if the map shows it, and
    /// whether the move has finished.
    var regionChanged: (MKCoordinateRegion, CLLocationCoordinate2D?, Bool) -> Void

    func makeUIView(context: Context) -> MKMapView {
        let view = MKMapView()
        view.delegate = context.coordinator
        view.showsUserLocation = showsUserLocation
        if let region = position.resolvedRegion {
            view.setRegion(region, animated: false)
        }
        context.coordinator.shown = position
        DispatchQueue.main.async { [weak view] in
            if let view { context.coordinator.report(view, finished: true) }
        }
        return view
    }

    func updateUIView(_ view: MKMapView, context: Context) {
        let coordinator = context.coordinator
        coordinator.regionChanged = regionChanged
        view.isScrollEnabled = interactionModes.contains(.pan)
        view.isZoomEnabled = interactionModes.contains(.zoom)
        view.isRotateEnabled = interactionModes.contains(.rotate)
        view.isPitchEnabled = interactionModes.contains(.pitch)
        if view.mapType != style.mapType {
            view.mapType = style.mapType
        }
        view.showsTraffic = style.showsTraffic
        if view.showsUserLocation != showsUserLocation {
            view.showsUserLocation = showsUserLocation
        }
        // A position set by the app, not one the map wrote back, moves it.
        if followsBinding, position != coordinator.shown, !position.isPositionedByUser,
           let region = position.resolvedRegion {
            coordinator.shown = position
            view.setRegion(region, animated: true)
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(regionChanged: regionChanged) }

    final class Coordinator: NSObject, MKMapViewDelegate {
        var regionChanged: (MKCoordinateRegion, CLLocationCoordinate2D?, Bool) -> Void
        var shown: MapCameraPosition?

        init(regionChanged: @escaping (MKCoordinateRegion, CLLocationCoordinate2D?, Bool) -> Void) {
            self.regionChanged = regionChanged
        }

        /// The region, and the user's location when the map shows it and
        /// knows it.
        func report(_ mapView: MKMapView, finished: Bool) {
            var user: CLLocationCoordinate2D?
            if mapView.showsUserLocation {
                let coordinate = mapView.userLocation.coordinate
                if CLLocationCoordinate2DIsValid(coordinate) { user = coordinate }
            }
            regionChanged(mapView.region, user, finished)
        }

        func mapViewDidChangeVisibleRegion(_ mapView: MKMapView) {
            report(mapView, finished: false)
        }

        func mapView(_ mapView: MKMapView, regionDidChangeAnimated animated: Bool) {
            report(mapView, finished: true)
        }
    }
}
