import PerryObjCInterop

// Foundation's classes, as Core Data calls them, and the messages it sends
// to objects of any class.

@ObjCWrapper("NSString") class NSString: NSObject {}

@ObjCWrapper("NSNumber")
class NSNumber: NSObject {
    @ObjCClassMethod("numberWithLongLong:") static func make(int64: Int64) -> NSNumber
    @ObjCClassMethod("numberWithDouble:") static func make(double: Double) -> NSNumber
    @ObjCClassMethod("numberWithFloat:") static func make(float: Float) -> NSNumber
    @ObjCClassMethod("numberWithBool:") static func make(bool: Bool) -> NSNumber
    @ObjCMethod("longLongValue") func int64Value() -> Int64
    @ObjCMethod("doubleValue") func doubleValue() -> Double
    @ObjCMethod("boolValue") func boolValue() -> Bool
}

@ObjCWrapper("NSDate")
class NSDate: NSObject {
    @ObjCClassMethod("dateWithTimeIntervalSinceReferenceDate:") static func make(sinceReferenceDate: Double) -> NSDate
    @ObjCMethod("timeIntervalSinceReferenceDate") func timeIntervalSinceReferenceDate() -> Double
}

@ObjCWrapper("NSData")
class NSData: NSObject {
    @ObjCClassMethod("dataWithBytes:length:") static func make(bytes: UnsafeRawPointer?, length: UInt) -> NSData
    @ObjCClassMethod("dataWithContentsOfURL:") static func make(contentsOf url: NSURL) -> NSData?
    @ObjCMethod("bytes") func bytes() -> UnsafeRawPointer?
    @ObjCMethod("length") func length() -> UInt
}

@ObjCWrapper("NSUUID")
class NSUUID: NSObject {
    @ObjCClassMethod("UUID") static func make() -> NSUUID
    @ObjCMethod("UUIDString") func uuidString() -> String
}

@ObjCWrapper("NSURL")
class NSURL: NSObject {
    @ObjCClassMethod("URLWithString:") static func make(string: String) -> NSURL?
    @ObjCClassMethod("fileURLWithPath:") static func make(fileURLWithPath path: String) -> NSURL
    @ObjCMethod("absoluteString") func absoluteString() -> String?
    @ObjCMethod("path") func path() -> String?
    @ObjCMethod("isFileURL") func isFileURL() -> Bool
    @ObjCMethod("URLByAppendingPathComponent:") func appending(_ component: String) -> NSURL
    @ObjCMethod("lastPathComponent") func lastPathComponent() -> String?
}

@ObjCWrapper("NSArray")
class NSArray: NSObject {
    @ObjCMethod("count") func count() -> UInt
    @ObjCMethod("objectAtIndex:") func object(at index: UInt) -> NSObject

    var elements: [NSObject] { (0..<count()).map { object(at: $0) } }
}

@ObjCWrapper("NSMutableArray")
class NSMutableArray: NSArray {
    @ObjCClassMethod("array") static func empty() -> Self
    @ObjCMethod("addObject:") func add(_ object: NSObject)

    static func of(_ objects: [NSObject]) -> NSMutableArray {
        let array = empty()
        objects.forEach(array.add)
        return array
    }
}

@ObjCWrapper("NSSet")
class NSSet: NSObject {
    @ObjCMethod("allObjects") func allObjects() -> NSArray
    @ObjCMethod("count") func count() -> UInt
}

@ObjCWrapper("NSOrderedSet")
class NSOrderedSet: NSObject {
    @ObjCMethod("array") func array() -> NSArray
}

extension NSObject {
    /// The members of a set, an ordered set (in its order) or an array: what
    /// a to-many relationship is set to. Nil for anything else.
    var collectionMembers: [NSObject]? {
        if self.is(NSSet.self) { return unsafeCast(to: NSSet.self).allObjects().elements }
        if self.is(NSOrderedSet.self) { return unsafeCast(to: NSOrderedSet.self).array().elements }
        if self.is(NSArray.self) { return unsafeCast(to: NSArray.self).elements }
        return nil
    }
}

@ObjCWrapper("NSMutableSet")
class NSMutableSet: NSSet {
    @ObjCClassMethod("set") static func empty() -> Self
    @ObjCMethod("addObject:") func add(_ object: NSObject)

    static func of(_ objects: [NSObject]) -> NSMutableSet {
        let set = empty()
        objects.forEach(set.add)
        return set
    }
}

@ObjCWrapper("NSDictionary")
class NSDictionary: NSObject {
    @ObjCMethod("objectForKey:") func object(forKey key: NSObject) -> NSObject?
    @ObjCMethod("allKeys") func allKeys() -> NSArray
    @ObjCClassMethod("dictionaryWithContentsOfFile:") static func make(contentsOfFile path: String) -> NSDictionary?

    /// The value for a string key.
    func object(forKey key: String) -> NSObject? { object(forKey: NSObject(key.objCArgument()!)) }
}

@ObjCWrapper("NSMutableDictionary")
class NSMutableDictionary: NSDictionary {
    @ObjCClassMethod("dictionary") static func empty() -> Self
    @ObjCMethod("setObject:forKey:") func set(_ object: NSObject, forKey key: NSObject)

    static func of(_ entries: [(String, NSObject)]) -> NSMutableDictionary {
        let dictionary = empty()
        for (key, value) in entries { dictionary.set(value, forKey: NSObject(key.objCArgument()!)) }
        return dictionary
    }
}

@ObjCWrapper("NSError")
class NSError: NSObject {
    @ObjCClassMethod("errorWithDomain:code:userInfo:")
    static func make(domain: String, code: Int, userInfo: NSDictionary?) -> NSError
    @ObjCClassMethod("setUserInfoValueProviderForDomain:provider:")
    static func setUserInfoValueProvider(forDomain domain: String, provider: NSObject?)
    @ObjCMethod("domain") func domain() -> String
    @ObjCMethod("code") func code() -> Int
}

@ObjCWrapper("NSBundle")
class NSBundle: NSObject {
    @ObjCClassMethod("mainBundle") static func main() -> NSBundle
    @ObjCMethod("URLForResource:withExtension:") func url(forResource name: String?, withExtension ext: String?) -> NSURL?
    @ObjCMethod("resourcePath") func resourcePath() -> String?
}

@ObjCWrapper("NSFileManager")
class NSFileManager: NSObject {
    @ObjCClassMethod("defaultManager") static func defaultManager() -> NSFileManager
    @ObjCMethod("fileExistsAtPath:") func fileExists(atPath path: String) -> Bool
    @ObjCMethod("contentsOfDirectoryAtPath:error:")
    func contents(atPath path: String, error: UnsafeMutablePointer<UnsafeMutableRawPointer?>?) -> NSArray?
    @ObjCMethod("removeItemAtPath:error:")
    func removeItem(atPath path: String, error: UnsafeMutablePointer<UnsafeMutableRawPointer?>?) -> Bool
    @ObjCMethod("createDirectoryAtPath:withIntermediateDirectories:attributes:error:")
    func createDirectory(atPath path: String, intermediates: Bool, attributes: NSDictionary?,
                         error: UnsafeMutablePointer<UnsafeMutableRawPointer?>?) -> Bool
}

@ObjCWrapper("NSNotificationCenter")
class NSNotificationCenter: NSObject {
    @ObjCClassMethod("defaultCenter") static func defaultCenter() -> NSNotificationCenter
    @ObjCMethod("postNotificationName:object:userInfo:") func post(name: String, object: NSObject?, userInfo: NSDictionary?)
}

@ObjCWrapper("NSKeyedUnarchiver")
class NSKeyedUnarchiver: NSObject {
    @ObjCClassMethod("unarchiveObjectWithData:") static func unarchive(_ data: NSData) -> NSObject?
}

@ObjCWrapper("NSKeyedArchiver")
class NSKeyedArchiver: NSObject {
    @ObjCClassMethod("archivedDataWithRootObject:") static func archive(_ object: NSObject) -> NSData?
}

@ObjCWrapper("NSPredicate")
class NSPredicate: NSObject {
    @ObjCMethod("predicateFormat") func predicateFormat() -> String
}

@ObjCWrapper("NSComparisonPredicate")
class NSComparisonPredicate: NSPredicate {
    @ObjCMethod("leftExpression") func leftExpression() -> NSExpression
    @ObjCMethod("rightExpression") func rightExpression() -> NSExpression
    @ObjCMethod("predicateOperatorType") func predicateOperatorType() -> UInt
    @ObjCMethod("comparisonPredicateModifier") func comparisonPredicateModifier() -> UInt
    @ObjCMethod("options") func options() -> UInt
}

@ObjCWrapper("NSCompoundPredicate")
class NSCompoundPredicate: NSPredicate {
    @ObjCMethod("compoundPredicateType") func compoundPredicateType() -> UInt
    @ObjCMethod("subpredicates") func subpredicates() -> NSArray
}

@ObjCWrapper("NSExpression")
class NSExpression: NSObject {
    @ObjCMethod("expressionType") func expressionType() -> UInt
    @ObjCMethod("keyPath") func keyPath() -> String
    @ObjCMethod("constantValue") func constantValue() -> NSObject?
    @ObjCMethod("collection") func collection() -> NSObject?
}

@ObjCWrapper("NSSortDescriptor")
class NSSortDescriptor: NSObject {
    @ObjCMethod("key") func key() -> String?
    @ObjCMethod("ascending") func ascending() -> Bool
}

extension NSObject {
    @ObjCMethod("description") func describedByObject() -> String?

    /// +new, sent to a class object.
    @ObjCMethod("new") func newInstance() -> NSObject
    /// +alloc, sent to a class object.
    @ObjCMethod("alloc") func allocated() -> NSObject

    @ObjCMethod("isEqual:") func isEqualTo(_ other: NSObject?) -> Bool
    @ObjCMethod("isKindOfClass:") func isKind(of cls: ObjCClass) -> Bool

    @ObjCMethod("performSelectorOnMainThread:withObject:waitUntilDone:")
    func performOnMainThread(_ selector: ObjCSelector, with object: NSObject?, waitUntilDone wait: Bool)

    @ObjCMethod("initWithUUIDString:") func initializeUUID(string: String) -> NSObject?

    /// The text of an NSString.
    var stringValue: String { String(objCArgument: objcObject) }
}

extension ObjCClass {
    /// The class object, as an object to send class messages to.
    var object: NSObject { NSObject(pointer) }
}

/// Calls a block: its invoke function takes the block, then the arguments.
enum Blocks {
    static func call(_ block: ObjCBlock) {
        block.function(as: (@convention(c) (UnsafeMutableRawPointer?) -> Void).self)(block.object)
    }

    static func call(_ block: ObjCBlock, _ argument: NSObject?) {
        block.function(as: (@convention(c) (UnsafeMutableRawPointer?, UnsafeMutableRawPointer?) -> Void).self)(
            block.object, argument?.objcObject)
    }

    static func call(_ block: ObjCBlock, _ first: NSObject?, _ second: NSObject?) {
        block.function(as: (@convention(c) (UnsafeMutableRawPointer?, UnsafeMutableRawPointer?, UnsafeMutableRawPointer?) -> Void).self)(
            block.object, first?.objcObject, second?.objcObject)
    }
}
