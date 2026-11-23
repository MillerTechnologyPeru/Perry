// NSObject in Swift: equality and hashing through -isEqual: and -hash,
// and passing objects to C variadic functions as their pointers.

extension NSObject: Equatable, Hashable {
    public static func == (lhs: NSObject, rhs: NSObject) -> Bool {
        lhs.isEqual(rhs)
    }

    /// The object's -hash, so that objects -isEqual: says are equal hash
    /// alike.
    @nonobjc
    public var hashValue: Int {
        hash
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(hash)
    }

    public func _rawHashValue(seed: Int) -> Int {
        hash._rawHashValue(seed: seed)
    }
}

extension NSObject: CVarArg {
    /// The object's address, as a %@ argument reads it. The object is
    /// autoreleased as well, so it outlives the call it is passed to.
    public var _cVarArgEncoding: [Int] {
        let object = Unmanaged.passUnretained(self)
        _ = object.retain().autorelease()
        return [Int(bitPattern: object.toOpaque())]
    }
}
