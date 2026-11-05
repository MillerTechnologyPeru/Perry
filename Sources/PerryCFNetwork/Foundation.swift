import FoundationEssentials
import Glibc
import PerryObjCInterop

// Foundation's classes, as CFNetwork calls them, and conversions between
// their objects and FoundationEssentials' values.

@ObjCWrapper("NSString") class NSString: NSObject {}

@ObjCWrapper("NSNumber")
class NSNumber: NSObject {
    @ObjCClassMethod("numberWithLongLong:") static func make(int64: Int64) -> NSNumber
    @ObjCClassMethod("numberWithBool:") static func make(bool: Bool) -> NSNumber
    @ObjCMethod("longLongValue") func int64Value() -> Int64
    @ObjCMethod("boolValue") func boolValue() -> Bool
}

@ObjCWrapper("NSDate")
class NSDate: NSObject {
    @ObjCClassMethod("dateWithTimeIntervalSinceReferenceDate:") static func make(sinceReferenceDate: Double) -> NSDate
    @ObjCMethod("timeIntervalSinceReferenceDate") func timeIntervalSinceReferenceDate() -> Double

    var date: Date { Date(timeIntervalSinceReferenceDate: timeIntervalSinceReferenceDate()) }
    static func of(_ date: Date) -> NSDate { make(sinceReferenceDate: date.timeIntervalSinceReferenceDate) }
}

@ObjCWrapper("NSDateInterval")
class NSDateInterval: NSObject {
    @ObjCClassMethod("alloc") static func allocate() -> NSDateInterval
    @ObjCMethod("initWithStartDate:endDate:") func initialize(start: NSDate, end: NSDate) -> NSDateInterval

    static func make(start: NSDate, end: NSDate) -> NSDateInterval { allocate().initialize(start: start, end: end) }
}

@ObjCWrapper("NSData")
class NSData: NSObject {
    @ObjCClassMethod("dataWithBytes:length:") static func make(bytes: UnsafeRawPointer?, length: UInt) -> NSData
    @ObjCMethod("bytes") func bytes() -> UnsafeRawPointer?
    @ObjCMethod("length") func length() -> UInt

    var data: Data {
        let count = Int(length())
        guard count > 0, let bytes = bytes() else { return Data() }
        return Data(bytes: bytes, count: count)
    }

    static func of(_ data: Data) -> NSData {
        data.withUnsafeBytes { make(bytes: $0.baseAddress, length: UInt($0.count)) }
    }
}

/// Loaded bodies are mutable, as CFNetwork's are, which apps that call
/// -mutableBytes on them depend on.
@ObjCWrapper("NSMutableData")
class NSMutableData: NSData {
    @ObjCClassMethod("dataWithBytes:length:") static func makeMutable(bytes: UnsafeRawPointer?, length: UInt) -> NSMutableData

    static func mutable(_ data: Data) -> NSMutableData {
        data.withUnsafeBytes { makeMutable(bytes: $0.baseAddress, length: UInt($0.count)) }
    }
}

@ObjCWrapper("NSURL")
class NSURL: NSObject {
    @ObjCClassMethod("URLWithString:") static func make(string: String) -> NSURL?
    @ObjCClassMethod("fileURLWithPath:") static func make(fileURLWithPath path: String) -> NSURL
    @ObjCMethod("absoluteString") func absoluteString() -> String?

    var url: URL? { absoluteString().flatMap { URL(string: $0) } }

    static func of(_ url: URL) -> NSURL? {
        url.isFileURL ? make(fileURLWithPath: url.path(percentEncoded: false)) : make(string: url.absoluteString)
    }
}

@ObjCWrapper("NSArray")
class NSArray: NSObject {
    @ObjCClassMethod("arrayWithObjects:count:") static func make(objects: UnsafeRawPointer?, count: UInt) -> NSArray
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

@ObjCWrapper("NSDictionary")
class NSDictionary: NSObject {
    @ObjCMethod("objectForKey:") func object(forKey key: NSObject) -> NSObject?
    @ObjCMethod("allKeys") func allKeys() -> NSArray

    /// Entries whose keys and values are strings.
    var strings: [String: String] {
        var entries: [String: String] = [:]
        for key in allKeys().elements where key.isString {
            if let value = object(forKey: key), value.isString { entries[key.stringValue] = value.stringValue }
        }
        return entries
    }
}

@ObjCWrapper("NSMutableDictionary")
class NSMutableDictionary: NSDictionary {
    @ObjCClassMethod("dictionary") static func empty() -> Self
    @ObjCMethod("setObject:forKey:") func set(_ object: NSObject, forKey key: NSObject)

    static func of(_ entries: [(String, NSObject)]) -> NSMutableDictionary {
        let dictionary = empty()
        for (key, value) in entries { dictionary.set(value, forKey: NSObject.string(key)) }
        return dictionary
    }
}

@ObjCWrapper("NSError")
class NSError: NSObject {
    @ObjCClassMethod("errorWithDomain:code:userInfo:")
    static func make(domain: String, code: Int, userInfo: NSDictionary?) -> NSError
    @ObjCMethod("domain") func domain() -> String
    @ObjCMethod("code") func code() -> Int
    @ObjCMethod("localizedDescription") func localizedDescription() -> String?
}

@ObjCWrapper("NSOperationQueue")
class NSOperationQueue: NSObject {
    @ObjCClassMethod("currentQueue") static func current() -> NSOperationQueue?
    @ObjCMethod("setMaxConcurrentOperationCount:") func setMaxConcurrentOperationCount(_ count: Int)
    @ObjCMethod("addOperationWithBlock:") func addOperation(block: NSObject)
}

extension NSObject {
    /// +new, sent to a class object.
    @ObjCMethod("new") func newInstance() -> NSObject
    @ObjCMethod("isKindOfClass:") func isKind(of cls: ObjCClass) -> Bool
    @ObjCMethod("description") func describedByObject() -> String?

    var stringValue: String { String(objCArgument: objcObject) }
    var isString: Bool { isKind(of: ObjCClass(named: "NSString")) }

    static func string(_ value: String) -> NSObject { NSObject(objCReturnValue: value.objCArgument()) }
}

extension ObjCClass {
    /// The class object, as an object to send class messages to.
    var object: NSObject { NSObject(pointer) }

    /// A new instance that an autorelease pool also holds, so its raw
    /// pointer outlives the wrapper, as a +0 result does.
    func autoreleasedInstance() -> NSObject {
        let instance = object.newInstance()
        _ = ObjCRuntime.autorelease(ObjCRuntime.retain(instance.objcObject))
        return instance
    }
}
