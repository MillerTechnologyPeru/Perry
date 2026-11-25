// CarPlay's Swift API: route segments' and waypoints' coordinates as Swift
// arrays. Their getters are emitted into the programs that call them, so
// the library holds only the properties' descriptors.

@available(iOS 26.4, *)
extension CPNavigationWaypoint {
    @_alwaysEmitIntoClient
    public var entryPoints: [CPLocationCoordinate3D] {
        Array(UnsafeBufferPointer(start: __entryPoints, count: __entryPointsCount))
    }
}

@available(iOS 26.4, *)
extension CPRouteSegment {
    @_alwaysEmitIntoClient
    public var coordinates: [CPLocationCoordinate3D] {
        Array(UnsafeBufferPointer(start: __coordinates, count: __coordinatesCount))
    }
}
