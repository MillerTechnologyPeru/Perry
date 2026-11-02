import PerryObjCInterop

// Foundation's classes, as UIKit calls them, and the messages UIKit sends
// to objects of any class.

@ObjCWrapper("NSArray")
class NSArray: NSObject {
    @ObjCMethod("count")
    func count() -> UInt

    @ObjCMethod("objectAtIndex:")
    func object(at index: UInt) -> NSObject

    /// The elements, in order.
    var elements: [NSObject] { (0..<count()).map { object(at: $0) } }
}

@ObjCWrapper("NSMutableArray")
class NSMutableArray: NSArray {
    @ObjCClassMethod("array")
    static func empty() -> Self

    @ObjCMethod("addObject:")
    func add(_ object: NSObject)

    /// A new array of `objects`.
    static func of(_ objects: [NSObject]) -> NSMutableArray {
        let array = empty()
        objects.forEach(array.add)
        return array
    }
}

@ObjCWrapper("NSDictionary")
class NSDictionary: NSObject {
    @ObjCMethod("objectForKey:")
    func object(forKey key: String) -> NSObject?
}

@ObjCWrapper("NSSet")
class NSSet: NSObject {}

@ObjCWrapper("NSMutableSet")
class NSMutableSet: NSSet {
    @ObjCClassMethod("set")
    static func empty() -> Self

    @ObjCMethod("addObject:")
    func add(_ object: NSObject)
}

@ObjCWrapper("NSBundle")
class NSBundle: NSObject {
    @ObjCClassMethod("mainBundle")
    static func main() -> NSBundle

    @ObjCMethod("objectForInfoDictionaryKey:")
    func infoObject(forKey key: String) -> NSObject?
}

@ObjCWrapper("NSNotificationCenter")
class NSNotificationCenter: NSObject {
    @ObjCClassMethod("defaultCenter")
    static func defaultCenter() -> NSNotificationCenter

    @ObjCMethod("postNotificationName:object:")
    func post(name: String, object: NSObject?)
}

@ObjCWrapper("NSRunLoop")
class NSRunLoop: NSObject {
    @ObjCClassMethod("mainRunLoop")
    static func main() -> NSRunLoop

    @ObjCMethod("run")
    func run()
}

@ObjCWrapper("NSUUID")
class NSUUID: NSObject {
    @ObjCClassMethod("UUID")
    static func make() -> NSUUID

    @ObjCMethod("UUIDString")
    func uuidString() -> String
}

extension NSObject {
    @ObjCMethod("respondsToSelector:")
    func respondsTo(_ selector: ObjCSelector) -> Bool

    /// +new, sent to a class object.
    @ObjCMethod("new")
    func newInstance() -> NSObject

    /// +alloc, sent to a class object.
    @ObjCMethod("alloc")
    func allocated() -> NSObject

    @ObjCMethod("copy")
    func copied() -> NSObject

    /// The text of an NSString.
    var stringValue: String { String(objCArgument: objcObject) }

    /// Whether the object responds to `selector`.
    func responds(to selector: String) -> Bool { respondsTo(ObjCSelector(selector)) }
}

extension ObjCClass {
    /// The class object, as an object to send class messages to.
    var object: NSObject { NSObject(pointer) }
}
