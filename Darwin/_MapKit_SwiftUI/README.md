# _MapKit_SwiftUI

Perry's `_MapKit_SwiftUI.framework`: SwiftUI's Map API (MapKit's
cross-import overlay with SwiftUI), written for Perry. `Scripts/build-mapkit-swiftui.sh`
builds it on a Mac, after `Scripts/build-swiftui.sh`, against Perry's SwiftUI
(the OpenSwiftUI module, whose ABI name is SwiftUI) into the Swift runtime
directory (`PERRY_SWIFT_RUNTIME`), where the loader finds it.

Its declarations follow the iOS SDK's `_MapKit_SwiftUI` interface (frozen
types, stored properties and generic signatures), so apps built against
Apple's bind to it by the same symbols.

- `Map` is an `MKMapView` (Perry's MapKit provider) with the map content's
  annotations drawn over it as SwiftUI views, positioned on the visible
  region's Mercator projection. A position binding moves the map; the map's
  moves are written back to it and reported to `onMapCameraChange`.
- Map content (`Annotation`, `UserAnnotation`, `ForEach`, the builder's
  tuples) resolves to a list of items read from the values, not through the
  attribute graph; the graph-making requirements exist for the ABI.
- Controls (`MapCompass`, `MapPitchToggle`, `MapUserLocationButton`,
  `MapScaleView`) are drawn over the map's trailing edge by `mapControls`.
  The map doesn't rotate, pitch or know the user's location yet, so the
  buttons don't move it, and the user's location isn't drawn.
