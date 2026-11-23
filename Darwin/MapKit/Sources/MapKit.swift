import Foundation

// MapKit's Swift API that its Swift 5.0 overlay had, MKCoordinateSpan
// bridged to NSValue, and the thin parts of the framework's own Swift API
// over its NS_REFINED_FOR_SWIFT methods.

extension MKCoordinateSpan: _ObjectiveCBridgeable {
    public func _bridgeToObjectiveC() -> NSValue {
        NSValue(mkCoordinateSpan: self)
    }

    public static func _forceBridgeFromObjectiveC(_ source: NSValue, result: inout MKCoordinateSpan?) {
        result = source.mkCoordinateSpanValue
    }

    public static func _conditionallyBridgeFromObjectiveC(_ source: NSValue, result: inout MKCoordinateSpan?) -> Bool {
        // Only a value holding a span (two doubles) is one.
        let type = String(cString: source.objCType)
        guard type == String(cString: _getObjCTypeEncoding(MKCoordinateSpan.self)) || type.hasPrefix("{?=dd}") || type.hasPrefix("{MKCoordinateSpan=") else {
            result = nil
            return false
        }
        result = source.mkCoordinateSpanValue
        return true
    }

    public static func _unconditionallyBridgeFromObjectiveC(_ source: NSValue?) -> MKCoordinateSpan {
        source?.mkCoordinateSpanValue ?? MKCoordinateSpan()
    }

    public typealias _ObjectiveCType = NSValue
}

@available(iOS 14.0, tvOS 14.0, macOS 11.0, watchOS 7.0, *)
extension MKMultiPoint {
    public func locations(at indexes: IndexSet) -> [CGFloat] {
        __locations(atPointIndexes: indexes).map { CGFloat($0.doubleValue) }
    }
}

@available(iOS 14.0, tvOS 14.0, macOS 11.0, *)
extension MKGradientPolylineRenderer {
    public var locations: [CGFloat] {
        __locations.map { CGFloat($0.doubleValue) }
    }

    public func setColors(_ colors: [NSColor], locations: [CGFloat]) {
        __setColors(colors, atLocations: locations.map { NSNumber(value: Double($0)) })
    }
}
