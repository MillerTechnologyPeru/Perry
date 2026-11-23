import Foundation

// CLLocationCoordinate2D bridged to NSValue, the beacon constraint's
// numbers as UInt16s and CLError's alternate region.

extension CLLocationCoordinate2D: _ObjectiveCBridgeable {
    /// The Objective-C type encoding of a coordinate, two doubles.
    private static var encoding: UnsafePointer<CChar> {
        _getObjCTypeEncoding(CLLocationCoordinate2D.self)
    }

    public func _bridgeToObjectiveC() -> NSValue {
        var coordinate = self
        return NSValue(bytes: &coordinate, objCType: Self.encoding)
    }

    public static func _forceBridgeFromObjectiveC(_ source: NSValue, result: inout CLLocationCoordinate2D?) {
        result = coordinate(of: source)
    }

    public static func _conditionallyBridgeFromObjectiveC(_ source: NSValue, result: inout CLLocationCoordinate2D?) -> Bool {
        guard strcmp(source.objCType, encoding) == 0 else {
            result = nil
            return false
        }
        result = coordinate(of: source)
        return true
    }

    public static func _unconditionallyBridgeFromObjectiveC(_ source: NSValue?) -> CLLocationCoordinate2D {
        source.map(coordinate(of:)) ?? CLLocationCoordinate2D()
    }

    public typealias _ObjectiveCType = NSValue

    private static func coordinate(of value: NSValue) -> CLLocationCoordinate2D {
        var coordinate = CLLocationCoordinate2D()
        value.getValue(&coordinate, size: MemoryLayout<CLLocationCoordinate2D>.size)
        return coordinate
    }
}

@available(iOS 13.0, macOS 10.15, *)
@available(watchOS, unavailable)
@available(tvOS, unavailable)
@available(visionOS, unavailable)
extension CLBeaconIdentityConstraint {
    public var major: UInt16? {
        __major?.uint16Value
    }

    public var minor: UInt16? {
        __minor?.uint16Value
    }
}

extension CLError {
    @available(visionOS, unavailable)
    public var alternateRegion: CLRegion? {
        userInfo[kCLErrorUserInfoAlternateRegionKey] as? CLRegion
    }
}
