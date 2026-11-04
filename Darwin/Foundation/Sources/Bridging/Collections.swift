// Array, Dictionary and Set bridge to NSArray, NSDictionary and NSSet.
//
// To Objective-C, the standard library wraps a collection's own storage.
// From Objective-C, a collection the standard library made gives its storage
// back; one of objects whose types bridge verbatim (classes) wraps an
// immutable copy and checks elements as they are read; any other has each
// element bridged now.

// MARK: Array

extension Array: _ObjectiveCBridgeable {
    public typealias _ObjectiveCType = NSArray

    @_semantics("convertToObjectiveC")
    public func _bridgeToObjectiveC() -> NSArray {
        unsafeDowncast(_bridgeToObjectiveCImpl(), to: NSArray.self)
    }

    public static func _forceBridgeFromObjectiveC(_ source: NSArray, result: inout Array?) {
        if let native = Array._bridgeFromObjectiveCAdoptingNativeStorageOf(source) {
            result = native
            return
        }
        if _isBridgedVerbatimToObjectiveC(Element.self) {
            result = Array(_immutableCocoaArray: source.copy() as AnyObject)
            return
        }
        var elements: [Element] = []
        elements.reserveCapacity(source.count)
        for index in 0..<source.count {
            elements.append(Swift._forceBridgeFromObjectiveC(source.object(at: index) as AnyObject, Element.self))
        }
        result = elements
    }

    @discardableResult
    public static func _conditionallyBridgeFromObjectiveC(_ source: NSArray, result: inout Array?) -> Bool {
        if let native = Array._bridgeFromObjectiveCAdoptingNativeStorageOf(source) {
            result = native
            return true
        }
        var elements: [Element] = []
        elements.reserveCapacity(source.count)
        for index in 0..<source.count {
            guard let element = Swift._conditionallyBridgeFromObjectiveC(source.object(at: index) as AnyObject, Element.self) else {
                result = nil
                return false
            }
            elements.append(element)
        }
        result = elements
        return true
    }

    @_effects(readonly)
    public static func _unconditionallyBridgeFromObjectiveC(_ source: NSArray?) -> Array {
        guard let source else { return [] }
        var result: Array?
        _forceBridgeFromObjectiveC(source, result: &result)
        return result!
    }
}

// MARK: Dictionary

extension Dictionary: _ObjectiveCBridgeable {
    public typealias _ObjectiveCType = NSDictionary

    @_semantics("convertToObjectiveC")
    public func _bridgeToObjectiveC() -> NSDictionary {
        unsafeDowncast(_bridgeToObjectiveCImpl(), to: NSDictionary.self)
    }

    /// Each key and value, bridged by `bridge`; nil if one does not bridge.
    private static func _bridgeEntries(
        of source: NSDictionary,
        key bridgeKey: (AnyObject) -> Key?,
        value bridgeValue: (AnyObject) -> Value?
    ) -> Dictionary? {
        var entries = Dictionary(minimumCapacity: source.count)
        let keys = source.keyEnumerator()
        while let key = keys.nextObject() {
            let keyObject = key as AnyObject
            guard let value = source.object(forKey: key),
                  let bridgedKey = bridgeKey(keyObject),
                  let bridgedValue = bridgeValue(value as AnyObject) else { return nil }
            entries[bridgedKey] = bridgedValue
        }
        return entries
    }

    public static func _forceBridgeFromObjectiveC(_ source: NSDictionary, result: inout Dictionary?) {
        if let native = Dictionary._bridgeFromObjectiveCAdoptingNativeStorageOf(source) {
            result = native
            return
        }
        if _isBridgedVerbatimToObjectiveC(Key.self) && _isBridgedVerbatimToObjectiveC(Value.self) {
            result = Dictionary(_immutableCocoaDictionary: source.copy() as AnyObject)
            return
        }
        result = _bridgeEntries(
            of: source,
            key: { Swift._forceBridgeFromObjectiveC($0, Key.self) },
            value: { Swift._forceBridgeFromObjectiveC($0, Value.self) })
    }

    @discardableResult
    public static func _conditionallyBridgeFromObjectiveC(_ source: NSDictionary, result: inout Dictionary?) -> Bool {
        if let native = Dictionary._bridgeFromObjectiveCAdoptingNativeStorageOf(source) {
            result = native
            return true
        }
        result = _bridgeEntries(
            of: source,
            key: { Swift._conditionallyBridgeFromObjectiveC($0, Key.self) },
            value: { Swift._conditionallyBridgeFromObjectiveC($0, Value.self) })
        return result != nil
    }

    @_effects(readonly)
    public static func _unconditionallyBridgeFromObjectiveC(_ source: NSDictionary?) -> Dictionary {
        guard let source else { return [:] }
        var result: Dictionary?
        _forceBridgeFromObjectiveC(source, result: &result)
        return result!
    }
}

// MARK: Set

extension Set: _ObjectiveCBridgeable {
    public typealias _ObjectiveCType = NSSet

    @_semantics("convertToObjectiveC")
    public func _bridgeToObjectiveC() -> NSSet {
        unsafeDowncast(_bridgeToObjectiveCImpl(), to: NSSet.self)
    }

    private static func _bridgeElements(of source: NSSet, _ bridge: (AnyObject) -> Element?) -> Set? {
        var elements = Set(minimumCapacity: source.count)
        let objects = source.objectEnumerator()
        while let object = objects.nextObject() {
            guard let element = bridge(object as AnyObject) else { return nil }
            elements.insert(element)
        }
        return elements
    }

    public static func _forceBridgeFromObjectiveC(_ source: NSSet, result: inout Set?) {
        if let native = Set._bridgeFromObjectiveCAdoptingNativeStorageOf(source) {
            result = native
            return
        }
        if _isBridgedVerbatimToObjectiveC(Element.self) {
            result = Set(_immutableCocoaSet: source.copy() as AnyObject)
            return
        }
        result = _bridgeElements(of: source) { Swift._forceBridgeFromObjectiveC($0, Element.self) }
    }

    @discardableResult
    public static func _conditionallyBridgeFromObjectiveC(_ source: NSSet, result: inout Set?) -> Bool {
        if let native = Set._bridgeFromObjectiveCAdoptingNativeStorageOf(source) {
            result = native
            return true
        }
        result = _bridgeElements(of: source) { Swift._conditionallyBridgeFromObjectiveC($0, Element.self) }
        return result != nil
    }

    @_effects(readonly)
    public static func _unconditionallyBridgeFromObjectiveC(_ source: NSSet?) -> Set {
        guard let source else { return [] }
        var result: Set?
        _forceBridgeFromObjectiveC(source, result: &result)
        return result!
    }
}
