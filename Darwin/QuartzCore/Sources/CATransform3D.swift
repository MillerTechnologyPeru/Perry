import Foundation

// CATransform3D bridges to NSValue, as Objective-C APIs (animation values,
// layer key paths) carry it.

/// The Objective-C type encoding of a CATransform3D in an NSValue.
private let transformEncoding: String = {
    var identity = CATransform3DIdentity
    return String(cString: NSValue(caTransform3D: identity).objCType)
}()

@available(macOS 10.9, iOS 7.0, tvOS 9.0, visionOS 1.0, *)
@available(watchOS, unavailable)
extension CATransform3D: _ObjectiveCBridgeable {
    public typealias _ObjectiveCType = NSValue

    public func _bridgeToObjectiveC() -> NSValue {
        NSValue(caTransform3D: self)
    }

    public static func _forceBridgeFromObjectiveC(_ source: NSValue, result: inout CATransform3D?) {
        if !_conditionallyBridgeFromObjectiveC(source, result: &result) {
            preconditionFailure("NSValue of type \(String(cString: source.objCType)) is not a CATransform3D")
        }
    }

    public static func _conditionallyBridgeFromObjectiveC(_ source: NSValue, result: inout CATransform3D?) -> Bool {
        guard String(cString: source.objCType) == transformEncoding else {
            result = nil
            return false
        }
        result = source.caTransform3DValue
        return true
    }

    public static func _unconditionallyBridgeFromObjectiveC(_ source: NSValue?) -> CATransform3D {
        // A nil value reads as Objective-C messaging nil would: all zero.
        guard let source else { return CATransform3D() }
        var result: CATransform3D?
        _forceBridgeFromObjectiveC(source, result: &result)
        return result!
    }
}
