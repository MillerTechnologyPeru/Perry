import FoundationEssentials
import PerryObjCInterop

// Foundation's classes, as Security calls them; CoreFoundation's
// dictionaries, data, strings, numbers, dates and arrays are these.

@ObjCWrapper("NSNumber")
class NSNumber: NSObject {
    @ObjCClassMethod("numberWithLongLong:") static func make(int64: Int64) -> NSNumber
    @ObjCClassMethod("numberWithBool:") static func make(bool: Bool) -> NSNumber
    @ObjCClassMethod("numberWithDouble:") static func make(double: Double) -> NSNumber
    @ObjCMethod("longLongValue") func int64Value() -> Int64
    @ObjCMethod("doubleValue") func doubleValue() -> Double
    @ObjCMethod("boolValue") func boolValue() -> Bool
    @ObjCMethod("objCType") func objCType() -> UnsafePointer<CChar>?
}

@ObjCWrapper("NSDate")
class NSDate: NSObject {
    @ObjCClassMethod("dateWithTimeIntervalSinceReferenceDate:") static func make(sinceReferenceDate: Double) -> NSDate
    @ObjCMethod("timeIntervalSinceReferenceDate") func timeIntervalSinceReferenceDate() -> Double

    var date: Date { Date(timeIntervalSinceReferenceDate: timeIntervalSinceReferenceDate()) }
    static func of(_ date: Date) -> NSDate { make(sinceReferenceDate: date.timeIntervalSinceReferenceDate) }
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

@ObjCWrapper("NSDictionary")
class NSDictionary: NSObject {
    @ObjCMethod("objectForKey:") func object(forKey key: NSObject) -> NSObject?
    @ObjCMethod("allKeys") func allKeys() -> NSArray

    /// The value for a key, looked up first with the constants Security
    /// exports for that text (kSecAttrKeyType and the rest), as Darwin's
    /// Security looks up its own keys: a dictionary made with the
    /// program's own callbacks may compare keys by pointer.
    func object(_ key: String) -> NSObject? {
        for constant in ExportedKeys.objects(for: key) {
            if let value = object(forKey: NSObject(constant)) { return value }
        }
        return object(forKey: NSObject.string(key))
    }

    var entries: [(String, NSObject)] {
        allKeys().elements.compactMap { key in
            guard key.isString, let value = object(forKey: key) else { return nil }
            return (key.stringValue, value)
        }
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
}

@ObjCWrapper("NSBundle")
class NSBundle: NSObject {
    @ObjCClassMethod("mainBundle") static func main() -> NSBundle
    @ObjCMethod("bundleIdentifier") func bundleIdentifier() -> String?
    @ObjCMethod("bundlePath") func bundlePath() -> String
}

extension NSObject {
    @ObjCMethod("new") func newInstance() -> NSObject
    @ObjCMethod("isKindOfClass:") func isKind(of cls: ObjCClass) -> Bool
    @ObjCMethod("isEqual:") func isEqualTo(_ other: NSObject?) -> Bool

    var stringValue: String { String(objCArgument: objcObject) }
    var isString: Bool { isKind(of: ObjCClass(named: "NSString")) }
    var isData: Bool { isKind(of: ObjCClass(named: "NSData")) }
    var isNumber: Bool { isKind(of: ObjCClass(named: "NSNumber")) }
    var isDate: Bool { isKind(of: ObjCClass(named: "NSDate")) }
    var isDictionary: Bool { isKind(of: ObjCClass(named: "NSDictionary")) }
    var isArray: Bool { isKind(of: ObjCClass(named: "NSArray")) }

    static func string(_ value: String) -> NSObject { NSObject(objCReturnValue: value.objCArgument()) }

    /// A CFBoolean or number's truth, or a string's ("1", "true").
    var truth: Bool {
        if isNumber { return unsafeCast(to: NSNumber.self).boolValue() }
        if isString { return ["1", "true", "yes"].contains(stringValue.lowercased()) }
        return false
    }

    /// A number or numeric string's value.
    var integer: Int? {
        if isNumber { return Int(unsafeCast(to: NSNumber.self).int64Value()) }
        if isString { return Int(stringValue) }
        return nil
    }
}

extension ObjCClass {
    var object: NSObject { NSObject(pointer) }

    /// A new instance an autorelease pool also holds.
    func autoreleasedInstance() -> NSObject {
        let instance = object.newInstance()
        _ = ObjCRuntime.autorelease(ObjCRuntime.retain(instance.objcObject))
        return instance
    }

    /// A new instance at +1, for Create and Copy functions.
    func ownedInstance() -> UnsafeMutableRawPointer {
        let instance = object.newInstance()
        return withExtendedLifetime(instance) { ObjCRuntime.retain(instance.objcObject)! }
    }
}

/// Security's exported string constants, by their text.
enum ExportedKeys {
    nonisolated(unsafe) private static var byText: [String: [UnsafeMutableRawPointer]]?
    private static let lock = Lock()

    static func objects(for text: String) -> [UnsafeMutableRawPointer] {
        lock.withLock {
            if byText == nil {
                var table: [String: [UnsafeMutableRawPointer]] = [:]
                let tables: [any ObjCConstantTable.Type] = [ItemKeys.self, MoreItemKeys.self, KeyAlgorithms.self, CodeSigningKeys.self]
                for constants in tables {
                    for (name, value) in constants.objCConstants {
                        guard case .string(let string) = value, let object = ObjCConstantExports.shared.slot(name)?.pointee else { continue }
                        table[string, default: []].append(object)
                    }
                }
                byText = table
            }
            return byText?[text] ?? []
        }
    }
}
