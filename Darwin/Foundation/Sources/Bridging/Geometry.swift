// CoreGraphics' points, sizes and rectangles bridge to NSValue, as Apple's
// Foundation overlay has them: a value of the structure's own Objective-C
// type, and back from any NSValue that holds one.

private func boxed<T>(_ value: T, _ type: String) -> NSValue {
    withUnsafeBytes(of: value) { bytes in type.withCString { NSValue(bytes: bytes.baseAddress!, objCType: $0) } }
}

private func unboxed<T>(_ value: NSValue, _ type: String, as _: T.Type) -> T? {
    guard String(cString: value.objCType) == type else { return nil }
    return withUnsafeTemporaryAllocation(of: T.self, capacity: 1) { buffer in
        value.getValue(UnsafeMutableRawPointer(buffer.baseAddress!), size: MemoryLayout<T>.size)
        return buffer[0]
    }
}

extension CGPoint: @retroactive _ObjectiveCBridgeable {
    public typealias _ObjectiveCType = NSValue
    private static var encoding: String { "{CGPoint=dd}" }

    @_semantics("convertToObjectiveC")
    public func _bridgeToObjectiveC() -> NSValue { boxed(self, CGPoint.encoding) }

    public static func _forceBridgeFromObjectiveC(_ source: NSValue, result: inout CGPoint?) {
        result = unboxed(source, encoding, as: CGPoint.self)
    }

    @discardableResult
    public static func _conditionallyBridgeFromObjectiveC(_ source: NSValue, result: inout CGPoint?) -> Bool {
        result = unboxed(source, encoding, as: CGPoint.self)
        return result != nil
    }

    @_effects(readonly)
    public static func _unconditionallyBridgeFromObjectiveC(_ source: NSValue?) -> CGPoint {
        guard let source, let value = unboxed(source, encoding, as: CGPoint.self) else { return CGPoint() }
        return value
    }
}

extension CGSize: @retroactive _ObjectiveCBridgeable {
    public typealias _ObjectiveCType = NSValue
    private static var encoding: String { "{CGSize=dd}" }

    @_semantics("convertToObjectiveC")
    public func _bridgeToObjectiveC() -> NSValue { boxed(self, CGSize.encoding) }

    public static func _forceBridgeFromObjectiveC(_ source: NSValue, result: inout CGSize?) {
        result = unboxed(source, encoding, as: CGSize.self)
    }

    @discardableResult
    public static func _conditionallyBridgeFromObjectiveC(_ source: NSValue, result: inout CGSize?) -> Bool {
        result = unboxed(source, encoding, as: CGSize.self)
        return result != nil
    }

    @_effects(readonly)
    public static func _unconditionallyBridgeFromObjectiveC(_ source: NSValue?) -> CGSize {
        guard let source, let value = unboxed(source, encoding, as: CGSize.self) else { return CGSize() }
        return value
    }
}

extension CGRect: @retroactive _ObjectiveCBridgeable {
    public typealias _ObjectiveCType = NSValue
    private static var encoding: String { "{CGRect={CGPoint=dd}{CGSize=dd}}" }

    @_semantics("convertToObjectiveC")
    public func _bridgeToObjectiveC() -> NSValue { boxed(self, CGRect.encoding) }

    public static func _forceBridgeFromObjectiveC(_ source: NSValue, result: inout CGRect?) {
        result = unboxed(source, encoding, as: CGRect.self)
    }

    @discardableResult
    public static func _conditionallyBridgeFromObjectiveC(_ source: NSValue, result: inout CGRect?) -> Bool {
        result = unboxed(source, encoding, as: CGRect.self)
        return result != nil
    }

    @_effects(readonly)
    public static func _unconditionallyBridgeFromObjectiveC(_ source: NSValue?) -> CGRect {
        guard let source, let value = unboxed(source, encoding, as: CGRect.self) else { return CGRect() }
        return value
    }
}

// MARK: - Collections made from their own kind

extension NSArray {
    /// An array of another's objects.
    @nonobjc
    public convenience init(array anArray: __shared NSArray) {
        self.init(array: anArray as! [Any])
    }
}

extension NSDictionary {
    /// A dictionary of another's entries.
    @nonobjc
    public convenience init(dictionary otherDictionary: __shared NSDictionary) {
        self.init(dictionary: otherDictionary as! [AnyHashable: Any])
    }
}

// MARK: - Security-scoped resources

extension URL {
    /// Every file an app is given is its to read here: there is no scope to open.
    public func startAccessingSecurityScopedResource() -> Bool { true }
    public func stopAccessingSecurityScopedResource() {}
}
