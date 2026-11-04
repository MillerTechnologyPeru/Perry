// String bridges to NSString. A native string becomes the standard
// library's NSString subclass, which keeps its storage; an NSString becomes
// a string that reads it lazily until it is copied or mutated.

/// The standard library's `String.init(_cocoaString:)`, SPI for Foundation
/// that the SDK's interface leaves out. An initializer takes its argument
/// owned.
@_silgen_name("$sSS12_cocoaStringSSyXl_tcfC")
func _stringFromCocoa(_ string: __owned AnyObject) -> String

extension String: _ObjectiveCBridgeable {
    public typealias _ObjectiveCType = NSString

    @_semantics("convertToObjectiveC")
    public func _bridgeToObjectiveC() -> NSString {
        unsafeDowncast(_bridgeToObjectiveCImpl(), to: NSString.self)
    }

    public static func _forceBridgeFromObjectiveC(_ source: NSString, result: inout String?) {
        result = _stringFromCocoa(source)
    }

    @discardableResult
    public static func _conditionallyBridgeFromObjectiveC(_ source: NSString, result: inout String?) -> Bool {
        result = _stringFromCocoa(source)
        return true
    }

    @_effects(readonly)
    public static func _unconditionallyBridgeFromObjectiveC(_ source: NSString?) -> String {
        guard let source else { return "" }
        return _stringFromCocoa(source)
    }
}

extension Substring: _ObjectiveCBridgeable {
    public typealias _ObjectiveCType = NSString

    public func _bridgeToObjectiveC() -> NSString {
        String(self)._bridgeToObjectiveC()
    }

    public static func _forceBridgeFromObjectiveC(_ source: NSString, result: inout Substring?) {
        result = Substring(_stringFromCocoa(source))
    }

    @discardableResult
    public static func _conditionallyBridgeFromObjectiveC(_ source: NSString, result: inout Substring?) -> Bool {
        result = Substring(_stringFromCocoa(source))
        return true
    }

    public static func _unconditionallyBridgeFromObjectiveC(_ source: NSString?) -> Substring {
        Substring(String._unconditionallyBridgeFromObjectiveC(source))
    }
}
