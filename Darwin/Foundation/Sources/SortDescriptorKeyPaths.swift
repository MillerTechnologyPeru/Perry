// NSSortDescriptor made from a Swift key path, as Apple's Foundation
// overlay has it: the key is the key path's Objective-C name, and the key
// path is kept with the descriptor for its keyPath property.

import ObjectiveC

private nonisolated(unsafe) var keyPathAssociation: UInt8 = 0

extension NSSortDescriptor {
    private static func key(_ keyPath: AnyKeyPath) -> String {
        guard let key = keyPath._kvcKeyPathString else {
            fatalError("Could not extract a String from KeyPath \(keyPath)")
        }
        return key
    }

    public convenience init<Root, Value>(keyPath: KeyPath<Root, Value>, ascending: Bool) {
        self.init(key: NSSortDescriptor.key(keyPath), ascending: ascending)
        objc_setAssociatedObject(self, &keyPathAssociation, keyPath, .OBJC_ASSOCIATION_RETAIN)
    }

    public convenience init<Root, Value>(keyPath: KeyPath<Root, Value>, ascending: Bool, comparator cmptr: @escaping Comparator) {
        self.init(key: NSSortDescriptor.key(keyPath), ascending: ascending, comparator: cmptr)
        objc_setAssociatedObject(self, &keyPathAssociation, keyPath, .OBJC_ASSOCIATION_RETAIN)
    }

    /// The key path the descriptor was made from, if it was made from one.
    public var keyPath: AnyKeyPath? {
        objc_getAssociatedObject(self, &keyPathAssociation) as? AnyKeyPath
    }
}
