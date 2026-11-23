// _CFObject: what the import of Core Foundation's types makes each CF
// class conform to, so that CF values compare and hash with CFEqual and
// CFHash.

public protocol _CFObject: AnyObject, Hashable {}

extension _CFObject {
    public var hashValue: Int {
        Int(bitPattern: CFHash(self))
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(CFHash(self))
    }

    public static func == (left: Self, right: Self) -> Bool {
        CFEqual(left, right)
    }
}
