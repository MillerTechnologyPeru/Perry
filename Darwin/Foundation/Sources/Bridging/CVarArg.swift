// Strings and collections as C variadic arguments: their bridged
// Objective-C objects, for %@ in a format.

extension CVarArg where Self: _ObjectiveCBridgeable {
    /// The bridged object's pointer, the object autoreleased so it lives
    /// while the format is used.
    public var _cVarArgEncoding: [Int] {
        let object = _bridgeToObjectiveC() as AnyObject
        return [Int(bitPattern: Unmanaged.passRetained(object).autorelease().toOpaque())]
    }
}

extension String: CVarArg {}

extension Array: CVarArg {}

extension Set: CVarArg {}

extension Dictionary: CVarArg {}
