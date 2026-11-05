// Map controls, as mapControls places them over a map: a compass, a 3D
// toggle, a button for the user's location and a scale. The map here
// doesn't rotate or pitch and has no location, so the compass always
// points north and the buttons show without moving the map.

public import MapKit
public import OpenSwiftUI

/// The rounded square map controls are drawn on.
struct MapControlBackground<Content: View>: View {
    var content: Content

    var body: some View {
        content
            .font(.system(size: 15, weight: .semibold))
            .frame(width: 44, height: 44)
            .background(Color.white.opacity(0.9))
            .cornerRadius(8)
            .shadow(radius: 2)
    }
}

/// A compass that shows the map's heading.
@preconcurrency
@MainActor
public struct MapCompass: View {
    @preconcurrency
    @MainActor
    public init(scope: Namespace.ID? = nil) {}

    @preconcurrency
    @MainActor
    public var body: some View {
        MapControlBackground(content: Text("N").foregroundColor(.red))
    }
}

/// A button that switches the map between flat and pitched.
@preconcurrency
@MainActor
public struct MapPitchToggle: View {
    @preconcurrency
    @MainActor
    public init(scope: Namespace.ID? = nil) {}

    @preconcurrency
    @MainActor
    public var body: some View {
        MapControlBackground(content: Text("3D").foregroundColor(.blue))
    }
}

/// A button that centers the map on the user's location.
@preconcurrency
@MainActor
public struct MapUserLocationButton: View {
    @preconcurrency
    @MainActor
    public init(scope: Namespace.ID? = nil) {}

    @preconcurrency
    @MainActor
    public var body: some View {
        MapControlBackground(content: Image(systemName: "location").foregroundColor(.blue))
    }
}

/// A legend that shows a distance on the map.
@preconcurrency
@MainActor
public struct MapScaleView: View {
    var alignment: HorizontalAlignment
    @Environment(\.mapVisibleRegion) private var region

    @_disfavoredOverload
    @preconcurrency
    @MainActor
    public init(anchorEdge: HorizontalEdge = .leading, scope: Namespace.ID? = nil) {
        self.alignment = anchorEdge == .leading ? .leading : .trailing
    }

    @preconcurrency
    @MainActor
    public init(alignment: HorizontalAlignment = .leading, scope: Namespace.ID? = nil) {
        self.alignment = alignment
    }

    /// A round distance about a quarter of the visible region's height.
    var label: String {
        guard let region else { return "" }
        let meters = MapGeometry.meters(of: region) / 4
        let magnitude = pow(10, floor(log10(max(meters, 1))))
        let rounded = (meters / magnitude).rounded(.down) * magnitude
        return rounded >= 1000 ? "\(Int(rounded / 1000)) km" : "\(Int(rounded)) m"
    }

    @preconcurrency
    @MainActor
    public var body: some View {
        VStack(alignment: alignment, spacing: 2) {
            Text(label).font(.caption2)
            Rectangle().fill(Color.primary).frame(width: 60, height: 2)
        }
        .opacity(region == nil ? 0 : 1)
    }
}
