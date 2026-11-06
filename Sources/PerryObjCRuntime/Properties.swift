import CPerryObjC
import Glibc

// Declared properties (@property), as clang emits them: a list header, then
// property_t entries of a name and an attribute string ("Tq,N,D").

/// A property_t: its name and attributes, both C strings.
public typealias PropertyPointer = UnsafeRawPointer

public enum Properties {
    private static func entries(_ list: UnsafeRawPointer) -> [PropertyPointer] {
        let size = Int(list.load(as: UInt32.self) & ~3)
        let count = Int(list.load(fromByteOffset: 4, as: UInt32.self))
        return (0..<count).map { list + 8 + $0 * size }
    }

    public static func name(_ property: PropertyPointer) -> UnsafePointer<CChar>? {
        property.load(as: UnsafePointer<CChar>?.self)
    }

    public static func attributes(_ property: PropertyPointer) -> UnsafePointer<CChar>? {
        property.load(fromByteOffset: Layout.word, as: UnsafePointer<CChar>?.self)
    }

    /// Adds a property list to a class, as class_addProperty does.
    public static func add(_ list: UnsafeRawPointer, to info: ClassInfo) {
        Runtime.lock.withLock { info.propertyLists.append(list) }
    }

    /// A class's own properties, its categories' included.
    public static func list(_ info: ClassInfo) -> [PropertyPointer] {
        let lists = Runtime.lock.withLock { info.propertyLists }
        return lists.flatMap(entries)
    }

    /// class_getProperty: the class's property named `name`, or its
    /// superclasses'.
    public static func find(_ info: ClassInfo, _ name: UnsafePointer<CChar>) -> PropertyPointer? {
        var current: ClassInfo? = info
        while let cls = current {
            if let found = list(cls).first(where: { Properties.name($0).map { strcmp($0, name) == 0 } ?? false }) {
                return found
            }
            current = cls.superInfo
        }
        return nil
    }

    /// One attribute's value ("T" gives the type encoding), or nil.
    public static func attributeValue(_ property: PropertyPointer, _ attribute: UnsafePointer<CChar>) -> String? {
        guard let attributes = attributes(property) else { return nil }
        let wanted = String(cString: attribute)
        // Attributes are comma-separated; a quoted class name may not contain commas.
        for part in String(cString: attributes).split(separator: ",", omittingEmptySubsequences: false) {
            if part.hasPrefix(wanted) { return String(part.dropFirst(wanted.count)) }
        }
        return nil
    }
}
