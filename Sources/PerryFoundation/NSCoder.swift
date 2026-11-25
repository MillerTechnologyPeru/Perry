import CPerryFoundation
import CPerryGeometry
import FoundationEssentials
import Glibc
import PerryObjCInterop

/// NSCoder: the abstract coder that programs' own coders subclass
/// (Interface Builder's XML decoder does). A subclass supplies the
/// primitives, -encodeValueOfObjCType:at: and -decodeValueOfObjCType:at:,
/// and for keyed coding the typed -encode…:forKey: and -decode…ForKey:
/// methods; the rest here are made of them by sending them to the coder, as
/// Darwin's NSCoder makes its convenience methods, so they work for the
/// keyed archiver and unarchiver, NSArchiver and NSUnarchiver and a
/// program's own subclasses alike. A primitive the subclass doesn't
/// implement raises, as Darwin's abstract methods do.
@ObjCClass("NSCoder")
public class NSCoder: NSObject {
    private typealias Value = @convention(c) (id?, SEL, UnsafePointer<CChar>, UnsafeMutableRawPointer) -> Void

    private func value(_ selector: String, _ object: inout id?) {
        let send = unsafeBitCast(ObjC.msgSend, to: Value.self)
        withUnsafeMutablePointer(to: &object) { pointer in
            "@".withCString { send(objcObject, ObjC.selector(selector), $0, UnsafeMutableRawPointer(pointer)) }
        }
    }

    @ObjCMethod("allowsKeyedCoding") func allowsKeyedCoding() -> Bool { false }
    @ObjCMethod("requiresSecureCoding") func requiresSecureCoding() -> Bool { false }
    /// Darwin's coders report 1000.
    @ObjCMethod("systemVersion") func systemVersion() -> UInt32 { 1000 }
    @ObjCMethod("versionForClassName:") func version(forClassName name: String?) -> Int { 0 }
    @ObjCMethod("containsValueForKey:") func containsValue(forKey key: String?) -> Bool { false }
    @ObjCMethod("error") func coderError() -> UnsafeMutableRawPointer? { nil }

    /// The next object, as -decodeValueOfObjCType:at: gives it, autoreleased.
    @ObjCMethod("decodeObject")
    func decodeObject() -> UnsafeMutableRawPointer? {
        var object: id?
        value("decodeValueOfObjCType:at:", &object)
        return object.flatMap { ObjC.autorelease($0) }
    }

    @ObjCMethod("encodeObject:")
    func encode(object: UnsafeMutableRawPointer?) {
        var value: id? = object
        self.value("encodeValueOfObjCType:at:", &value)
    }
    // Keyed coding's derived values, made of the subclass's own keyed
    // primitives (Interface Builder's XML decoder has 64-bit integers and
    // objects): integers as 64-bit ones, geometry as strings of it.

    @ObjCMethod("decodeIntegerForKey:")
    func decodeInteger(forKey key: String?) -> Int {
        typealias F = @convention(c) (id?, SEL, id?) -> Int64
        return Int(unsafeBitCast(ObjC.msgSend, to: F.self)(objcObject, ObjC.selector("decodeInt64ForKey:"), Strings.autoreleased(key ?? "")))
    }
    @ObjCMethod("encodeInteger:forKey:")
    func encode(integer value: Int, forKey key: String?) {
        typealias F = @convention(c) (id?, SEL, Int64, id?) -> Void
        unsafeBitCast(ObjC.msgSend, to: F.self)(objcObject, ObjC.selector("encodeInt64:forKey:"), Int64(value), Strings.autoreleased(key ?? ""))
    }
    override public class func didDefineObjCClass(_ cls: ObjCClass) {
        Coders.coderClass = cls.storage
        CoderGeometry.add(to: cls)
        cls.addMethod("encodeValuesOfObjCTypes:", types: "v24@0:8r*16",
                      implementation: variadicEntry(perry_imp_encodeValuesOfObjCTypes), isClassMethod: false)
        cls.addMethod("decodeValuesOfObjCTypes:", types: "v24@0:8r*16",
                      implementation: variadicEntry(perry_imp_decodeValuesOfObjCTypes), isClassMethod: false)
    }

    @ObjCMethod("encodeRootObject:") func encodeRoot(object: UnsafeMutableRawPointer?) { encode(object: object) }
    @ObjCMethod("encodeBycopyObject:") func encodeBycopy(object: UnsafeMutableRawPointer?) { encode(object: object) }
    @ObjCMethod("encodeByrefObject:") func encodeByref(object: UnsafeMutableRawPointer?) { encode(object: object) }
    @ObjCMethod("encodeConditionalObject:") func encodeConditional(object: UnsafeMutableRawPointer?) { encode(object: object) }

    // MARK: Unkeyed primitives

    /// Whether the receiver's class implements `selector` itself, rather
    /// than with NSCoder's method.
    private func overrides(_ selector: String) -> Bool {
        ObjC.overrides(objcObject, ObjC.selector(selector), of: Coders.coderClass)
    }

    /// Abstract: a subclass encodes values.
    @ObjCMethod("encodeValueOfObjCType:at:")
    func coderEncodeValue(ofObjCType type: UnsafePointer<CChar>?, at address: UnsafeRawPointer?) {
        Coders.abstract(objcObject, "encodeValueOfObjCType:at:")
    }

    /// A subclass decodes values with this or with
    /// -decodeValueOfObjCType:at:size:, which it is made of then.
    @ObjCMethod("decodeValueOfObjCType:at:")
    func coderDecodeValue(ofObjCType type: UnsafePointer<CChar>?, at address: UnsafeMutableRawPointer?) {
        guard overrides("decodeValueOfObjCType:at:size:") else { Coders.abstract(objcObject, "decodeValueOfObjCType:at:") }
        let size = type.map { ArchiveTypes.layout(Array(UnsafeRawBufferPointer(start: $0, count: strlen($0)))).size } ?? 0
        typealias F = @convention(c) (id?, SEL, UnsafePointer<CChar>?, UnsafeMutableRawPointer?, UInt) -> Void
        unsafeBitCast(ObjC.msgSend, to: F.self)(objcObject, ObjC.selector("decodeValueOfObjCType:at:size:"), type, address, UInt(size))
    }

    /// -decodeValueOfObjCType:at:, which a subclass implements; the size is
    /// not checked.
    @ObjCMethod("decodeValueOfObjCType:at:size:")
    func coderDecodeValue(ofObjCType type: UnsafePointer<CChar>?, at address: UnsafeMutableRawPointer?, size: UInt) {
        guard overrides("decodeValueOfObjCType:at:") else { Coders.abstract(objcObject, "decodeValueOfObjCType:at:size:") }
        typealias F = @convention(c) (id?, SEL, UnsafePointer<CChar>?, UnsafeMutableRawPointer?) -> Void
        unsafeBitCast(ObjC.msgSend, to: F.self)(objcObject, ObjC.selector("decodeValueOfObjCType:at:"), type, address)
    }

    /// A C array, as one value of the array type ("[3s]").
    @ObjCMethod("encodeArrayOfObjCType:count:at:")
    func coderEncodeArray(ofObjCType type: UnsafePointer<CChar>?, count: UInt, at address: UnsafeRawPointer?) {
        guard let type else { return }
        typealias F = @convention(c) (id?, SEL, UnsafePointer<CChar>?, UnsafeRawPointer?) -> Void
        "[\(count)\(String(cString: type))]".withCString {
            unsafeBitCast(ObjC.msgSend, to: F.self)(objcObject, ObjC.selector("encodeValueOfObjCType:at:"), $0, address)
        }
    }

    @ObjCMethod("decodeArrayOfObjCType:count:at:")
    func coderDecodeArray(ofObjCType type: UnsafePointer<CChar>?, count: UInt, at address: UnsafeMutableRawPointer?) {
        guard let type else { return }
        typealias F = @convention(c) (id?, SEL, UnsafePointer<CChar>?, UnsafeMutableRawPointer?) -> Void
        "[\(count)\(String(cString: type))]".withCString {
            unsafeBitCast(ObjC.msgSend, to: F.self)(objcObject, ObjC.selector("decodeValueOfObjCType:at:"), $0, address)
        }
    }

    /// Bytes: their count as an unsigned int, then the bytes as an array
    /// of chars.
    @ObjCMethod("encodeBytes:length:")
    func coderEncodeBytes(_ address: UnsafeRawPointer?, length: UInt) {
        var count = UInt32(truncatingIfNeeded: length)
        typealias Value = @convention(c) (id?, SEL, UnsafePointer<CChar>?, UnsafeRawPointer?) -> Void
        typealias ArrayF = @convention(c) (id?, SEL, UnsafePointer<CChar>?, UInt, UnsafeRawPointer?) -> Void
        "I".withCString { unsafeBitCast(ObjC.msgSend, to: Value.self)(objcObject, ObjC.selector("encodeValueOfObjCType:at:"), $0, &count) }
        guard length > 0, let address else { return }
        "c".withCString {
            unsafeBitCast(ObjC.msgSend, to: ArrayF.self)(objcObject, ObjC.selector("encodeArrayOfObjCType:count:at:"), $0, length, address)
        }
    }

    /// Bytes as -encodeBytes:length: wrote them, in an autoreleased buffer.
    @ObjCMethod("decodeBytesWithReturnedLength:")
    func coderDecodeBytes(returnedLength length: UnsafeMutablePointer<UInt>?) -> UnsafeMutableRawPointer? {
        var count: UInt32 = 0
        typealias Value = @convention(c) (id?, SEL, UnsafePointer<CChar>?, UnsafeMutableRawPointer?) -> Void
        typealias ArrayF = @convention(c) (id?, SEL, UnsafePointer<CChar>?, UInt, UnsafeMutableRawPointer?) -> Void
        "I".withCString { unsafeBitCast(ObjC.msgSend, to: Value.self)(objcObject, ObjC.selector("decodeValueOfObjCType:at:"), $0, &count) }
        length?.pointee = UInt(count)
        guard count > 0, let data = DataObjects.autoreleased(Data(count: Int(count)), cls: UnsafeMutableRawPointer(DataObjects.mutableClass)),
              let bytes = ObjC.sendPointer(data, ObjC.selector("mutableBytes")) else { return nil }
        "c".withCString {
            unsafeBitCast(ObjC.msgSend, to: ArrayF.self)(objcObject, ObjC.selector("decodeArrayOfObjCType:count:at:"), $0, UInt(count),
                                                        UnsafeMutableRawPointer(mutating: bytes))
        }
        return UnsafeMutableRawPointer(mutating: bytes)
    }

    /// Abstract, as on Darwin: NSArchiver and the keyed archiver have
    /// their own.
    @ObjCMethod("encodeDataObject:")
    func coderEncodeDataObject(_ data: UnsafeMutableRawPointer?) { Coders.abstract(objcObject, "encodeDataObject:") }
    @ObjCMethod("decodeDataObject")
    func coderDecodeDataObject() -> UnsafeMutableRawPointer? { Coders.abstract(objcObject, "decodeDataObject") }

    /// An object, as -encodeObject: codes it.
    @ObjCMethod("encodePropertyList:")
    func coderEncodePropertyList(_ list: UnsafeMutableRawPointer?) { _ = ObjC.send(objcObject, ObjC.selector("encodeObject:"), list) }
    @ObjCMethod("decodePropertyList")
    func coderDecodePropertyList() -> UnsafeMutableRawPointer? { ObjC.send(objcObject, ObjC.selector("decodeObject")) }
    /// NeXTSTEP's objects, which are objects here: -encodeObject: and
    /// -decodeObject.
    @ObjCMethod("encodeNXObject:")
    func coderEncodeNXObject(_ object: UnsafeMutableRawPointer?) { _ = ObjC.send(objcObject, ObjC.selector("encodeObject:"), object) }
    @ObjCMethod("decodeNXObject")
    func coderDecodeNXObject() -> UnsafeMutableRawPointer? { ObjC.send(objcObject, ObjC.selector("decodeObject")) }

    /// Zones are gone: the default zone, and setting one does nothing.
    @ObjCMethod("objectZone") func coderObjectZone() -> UnsafeMutableRawPointer? { NSDefaultMallocZone() }
    @ObjCMethod("setObjectZone:") func coderSetObjectZone(_ zone: UnsafeMutableRawPointer?) {}

    /// The next object, or nil and the coder's error, which this hands
    /// on: Darwin's top-level decode.
    @ObjCMethod("decodeTopLevelObjectAndReturnError:")
    func coderDecodeTopLevelObject(error: UnsafeMutablePointer<UnsafeMutableRawPointer?>?) -> UnsafeMutableRawPointer? {
        let object = ObjC.send(objcObject, ObjC.selector("decodeObject"))
        if let failure = ObjC.send(objcObject, ObjC.selector("error")) {
            error?.pointee = failure
            return nil
        }
        return object
    }

    // MARK: Keyed primitives

    /// Abstract: a keyed subclass has these.
    @ObjCMethod("encodeInt64:forKey:")
    func coderEncode(int64 value: Int64, forKey key: UnsafeMutableRawPointer?) { Coders.abstract(objcObject, "encodeInt64:forKey:") }
    @ObjCMethod("decodeInt64ForKey:")
    func coderDecodeInt64(forKey key: UnsafeMutableRawPointer?) -> Int64 { Coders.abstract(objcObject, "decodeInt64ForKey:") }
    @ObjCMethod("encodeFloat:forKey:")
    func coderEncode(float value: Float, forKey key: UnsafeMutableRawPointer?) { Coders.abstract(objcObject, "encodeFloat:forKey:") }
    @ObjCMethod("encodeBytes:length:forKey:")
    func coderEncode(bytes: UnsafeRawPointer?, length: UInt, forKey key: UnsafeMutableRawPointer?) {
        Coders.abstract(objcObject, "encodeBytes:length:forKey:")
    }

    /// An int, as a 64-bit integer.
    @ObjCMethod("encodeInt:forKey:")
    func coderEncode(int value: Int32, forKey key: UnsafeMutableRawPointer?) { Coders.encodeInt64(objcObject, Int64(value), key) }
    @ObjCMethod("encodeInt32:forKey:")
    func coderEncode(int32 value: Int32, forKey key: UnsafeMutableRawPointer?) { Coders.encodeInt64(objcObject, Int64(value), key) }
    @ObjCMethod("decodeIntForKey:")
    func coderDecodeInt(forKey key: UnsafeMutableRawPointer?) -> Int32 { Int32(truncatingIfNeeded: Coders.decodeInt64(objcObject, key)) }
    @ObjCMethod("decodeInt32ForKey:")
    func coderDecodeInt32(forKey key: UnsafeMutableRawPointer?) -> Int32 { Int32(truncatingIfNeeded: Coders.decodeInt64(objcObject, key)) }

    /// Only an object encoded elsewhere should be: a coder that doesn't
    /// tell encodes it.
    @ObjCMethod("encodeConditionalObject:forKey:")
    func coderEncodeConditional(_ object: UnsafeMutableRawPointer?, forKey key: UnsafeMutableRawPointer?) {
        _ = ObjC.send(objcObject, ObjC.selector("encodeObject:forKey:"), object, key)
    }

    /// The bytes, when there are at least `minimum`; fewer fail the decode.
    @ObjCMethod("decodeBytesForKey:minimumLength:")
    func coderDecodeBytes(forKey key: UnsafeMutableRawPointer?, minimumLength minimum: UInt) -> UnsafeRawPointer? {
        var length: UInt = 0
        typealias F = @convention(c) (id?, SEL, id?, UnsafeMutablePointer<UInt>?) -> UnsafeRawPointer?
        guard let bytes = unsafeBitCast(ObjC.msgSend, to: F.self)(objcObject, ObjC.selector("decodeBytesForKey:returnedLength:"), key, &length)
        else { return nil }
        guard length >= minimum else {
            Coders.fail(objcObject, "The data for key \(Strings.value(of: key) ?? "") is \(length) bytes, fewer than \(minimum).")
            return nil
        }
        return bytes
    }

    @ObjCMethod("decodeBytesWithMinimumLength:")
    func coderDecodeBytes(minimumLength minimum: UInt) -> UnsafeMutableRawPointer? {
        var length: UInt = 0
        typealias F = @convention(c) (id?, SEL, UnsafeMutablePointer<UInt>?) -> UnsafeMutableRawPointer?
        guard let bytes = unsafeBitCast(ObjC.msgSend, to: F.self)(objcObject, ObjC.selector("decodeBytesWithReturnedLength:"), &length)
        else { return nil }
        guard length >= minimum else {
            Coders.fail(objcObject, "The data is \(length) bytes, fewer than \(minimum).")
            return nil
        }
        return bytes
    }

    // MARK: Secure coding

    /// The classes being decoded: none outside a decode of classes.
    @ObjCMethod("allowedClasses") func coderAllowedClasses() -> UnsafeMutableRawPointer? { nil }
    /// NSDecodingFailurePolicyRaiseException, which a coder that keeps no
    /// error has.
    @ObjCMethod("decodingFailurePolicy") func coderDecodingFailurePolicy() -> Int { 0 }

    /// With the raise policy, an NSInvalidUnarchiveOperationException of
    /// the error's description; a coder that keeps the error overrides this.
    @ObjCMethod("failWithError:")
    func coderFail(with error: UnsafeMutableRawPointer?) {
        Exceptions.raise(name: "NSInvalidUnarchiveOperationException", reason: Errors.localizedDescription(error))
    }

    /// -decodeObjectOfClasses:forKey: with the one class.
    @ObjCMethod("decodeObjectOfClass:forKey:")
    func coderDecodeObject(ofClass cls: UnsafeMutableRawPointer?, forKey key: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer? {
        ObjC.send(objcObject, ObjC.selector("decodeObjectOfClasses:forKey:"), Coders.set([cls]), key)
    }

    /// -decodeObjectForKey:: a coder that doesn't require secure coding
    /// checks no classes.
    @ObjCMethod("decodeObjectOfClasses:forKey:")
    func coderDecodeObject(ofClasses classes: UnsafeMutableRawPointer?, forKey key: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer? {
        ObjC.send(objcObject, ObjC.selector("decodeObjectForKey:"), key)
    }

    @ObjCMethod("decodeArrayOfObjectsOfClass:forKey:")
    func coderDecodeArray(ofClass cls: UnsafeMutableRawPointer?, forKey key: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer? {
        ObjC.send(objcObject, ObjC.selector("decodeArrayOfObjectsOfClasses:forKey:"), Coders.set([cls]), key)
    }

    /// An array of the classes; anything else fails the decode.
    @ObjCMethod("decodeArrayOfObjectsOfClasses:forKey:")
    func coderDecodeArray(ofClasses classes: UnsafeMutableRawPointer?, forKey key: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer? {
        let allowed = Sets.elements(classes).map { Optional($0) } + [UnsafeMutableRawPointer(Arrays.arrayClass)]
        guard let object = ObjC.send(objcObject, ObjC.selector("decodeObjectOfClasses:forKey:"), Coders.set(allowed), key) else { return nil }
        guard ObjC.isKind(object, of: Arrays.arrayClass) else {
            Coders.fail(objcObject, "The value for key \(Strings.value(of: key) ?? "") isn’t an array.")
            return nil
        }
        return object
    }

    @ObjCMethod("decodeDictionaryWithKeysOfClass:objectsOfClass:forKey:")
    func coderDecodeDictionary(keysOfClass keyClass: UnsafeMutableRawPointer?, objectsOfClass objectClass: UnsafeMutableRawPointer?,
                               forKey key: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer? {
        typealias F = @convention(c) (id?, SEL, id?, id?, id?) -> id?
        return unsafeBitCast(ObjC.msgSend, to: F.self)(objcObject, ObjC.selector("decodeDictionaryWithKeysOfClasses:objectsOfClasses:forKey:"),
                                                       Coders.set([keyClass]), Coders.set([objectClass]), key)
    }

    /// A dictionary whose every key is of the key classes and every object
    /// of the object classes; anything else fails the decode.
    @ObjCMethod("decodeDictionaryWithKeysOfClasses:objectsOfClasses:forKey:")
    func coderDecodeDictionary(keysOfClasses keyClasses: UnsafeMutableRawPointer?, objectsOfClasses objectClasses: UnsafeMutableRawPointer?,
                               forKey key: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer? {
        Coders.decodeDictionary(objcObject, keyClasses, objectClasses, key)
    }

    @ObjCMethod("decodeTopLevelObjectForKey:error:")
    func coderDecodeTopLevelObject(forKey key: UnsafeMutableRawPointer?,
                                   error: UnsafeMutablePointer<UnsafeMutableRawPointer?>?) -> UnsafeMutableRawPointer? {
        typealias F = @convention(c) (id?, SEL, id?, id?, UnsafeMutablePointer<UnsafeMutableRawPointer?>?) -> id?
        return unsafeBitCast(ObjC.msgSend, to: F.self)(objcObject, ObjC.selector("decodeTopLevelObjectOfClasses:forKey:error:"), nil, key, error)
    }

    @ObjCMethod("decodeTopLevelObjectOfClass:forKey:error:")
    func coderDecodeTopLevelObject(ofClass cls: UnsafeMutableRawPointer?, forKey key: UnsafeMutableRawPointer?,
                                   error: UnsafeMutablePointer<UnsafeMutableRawPointer?>?) -> UnsafeMutableRawPointer? {
        typealias F = @convention(c) (id?, SEL, id?, id?, UnsafeMutablePointer<UnsafeMutableRawPointer?>?) -> id?
        return unsafeBitCast(ObjC.msgSend, to: F.self)(objcObject, ObjC.selector("decodeTopLevelObjectOfClasses:forKey:error:"),
                                                       Coders.set([cls]), key, error)
    }

    /// The object, or nil and the coder's error: NSCocoaErrorDomain 4865
    /// when there is no value for the key.
    @ObjCMethod("decodeTopLevelObjectOfClasses:forKey:error:")
    func coderDecodeTopLevelObject(ofClasses classes: UnsafeMutableRawPointer?, forKey key: UnsafeMutableRawPointer?,
                                   error: UnsafeMutablePointer<UnsafeMutableRawPointer?>?) -> UnsafeMutableRawPointer? {
        let object = ObjC.send(objcObject, ObjC.selector("decodeObjectOfClasses:forKey:"), classes, key)
        if let failure = ObjC.send(objcObject, ObjC.selector("error")) {
            error?.pointee = failure
            return nil
        }
        if object == nil, !ObjC.sendBool(objcObject, ObjC.selector("containsValueForKey:"), key) {
            error?.pointee = Coders.missing()
        }
        return object
    }

    /// -decodeObjectOfClasses:forKey: with the property list classes.
    @ObjCMethod("decodePropertyListForKey:")
    func coderDecodePropertyList(forKey key: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer? {
        ObjC.send(objcObject, ObjC.selector("decodeObjectOfClasses:forKey:"), Coders.set(Coders.propertyListClasses), key)
    }
}

/// What NSCoder's methods share with the coders made of it.
enum Coders {
    nonisolated(unsafe) static var coderClass: Class!

    /// Darwin's exception for an abstract method a subclass lacks.
    static func abstract(_ coder: id, _ selector: String) -> Never {
        Exceptions.raise(name: "NSInvalidArgumentException",
                         reason: "*** -\(selector) only defined for abstract class.  Define -[\(ObjC.className(coder)) \(selector)]!")
    }

    /// An autoreleased set of the classes given.
    static func set(_ classes: [UnsafeMutableRawPointer?]) -> id {
        Sets.autoreleased(classes.compactMap { $0 })
    }

    /// NSArray, NSDictionary, NSString, NSData, NSDate and NSNumber.
    static var propertyListClasses: [UnsafeMutableRawPointer?] {
        [Arrays.arrayClass, Dictionaries.dictionaryClass, Strings.stringClass, DataObjects.dataClass, Dates.dateClass, Numbers.numberClass]
            .map { $0.map { UnsafeMutableRawPointer($0) } }
    }

    static func encodeInt64(_ coder: id, _ value: Int64, _ key: id?) {
        typealias F = @convention(c) (id?, SEL, Int64, id?) -> Void
        unsafeBitCast(ObjC.msgSend, to: F.self)(coder, ObjC.selector("encodeInt64:forKey:"), value, key)
    }

    static func decodeInt64(_ coder: id, _ key: id?) -> Int64 {
        typealias F = @convention(c) (id?, SEL, id?) -> Int64
        return unsafeBitCast(ObjC.msgSend, to: F.self)(coder, ObjC.selector("decodeInt64ForKey:"), key)
    }

    /// NSCoderReadCorruptError (4864), autoreleased.
    static func corrupt(_ debugDescription: String? = nil) -> id? {
        var entries: [(String, id)] = [("NSLocalizedDescription", Strings.autoreleased("The data couldn’t be read because it isn’t in the correct format."))]
        if let debugDescription { entries.append(("NSDebugDescription", Strings.autoreleased(debugDescription))) }
        return ObjC.autorelease(Errors.make(domain: Errors.cocoaDomain, code: 4864, entries: entries))
    }

    /// NSCoderValueNotFoundError (4865), autoreleased.
    static func missing() -> id? {
        Errors.autoreleased(domain: Errors.cocoaDomain, code: 4865, description: "The data couldn’t be read because it is missing.")
    }

    /// Fails the coder's decode with a 4864 error: -failWithError:.
    static func fail(_ coder: id, _ debugDescription: String) {
        _ = ObjC.send(coder, ObjC.selector("failWithError:"), corrupt(debugDescription))
    }

    /// Whether `object` is of one of `classes` or a subclass of one.
    static func isKind(_ object: id, of classes: [id]) -> Bool {
        classes.contains { ObjC.isKind(object, of: $0.assumingMemoryBound(to: perry_class_storage.self)) }
    }

    /// A dictionary of the key and object classes, checked after it is
    /// decoded, as Darwin checks each key and object.
    static func decodeDictionary(_ coder: id, _ keyClasses: id?, _ objectClasses: id?, _ key: id?) -> id? {
        let keys = Sets.elements(keyClasses), objects = Sets.elements(objectClasses)
        let allowed: [id] = keys + objects + [UnsafeMutableRawPointer(Dictionaries.dictionaryClass!)]
        guard let dictionary = ObjC.send(coder, ObjC.selector("decodeObjectOfClasses:forKey:"), set(allowed.map { Optional($0) }), key) else { return nil }
        guard ObjC.isKind(dictionary, of: Dictionaries.dictionaryClass),
              Dictionaries.entries(dictionary).allSatisfy({ isKind($0.key, of: keys) && isKind($0.value, of: objects) }) else {
            fail(coder, "The value for key \(Strings.value(of: key) ?? "") isn’t a dictionary of the expected classes.")
            return nil
        }
        return dictionary
    }
}

/// - (void)encodeValuesOfObjCTypes:(const char *)types, ...: each pointer
/// with -encodeValueOfObjCType:at: and its type, or for NSArchiver as one
/// group of them all, as Darwin's typedstream writes them.
@c
public func perry_foundation_encodeValuesOfObjCTypes(_ coder: id?, _ cmd: SEL?, _ types: UnsafePointer<CChar>?,
                                                     _ arguments: UnsafeRawPointer?) {
    guard let coder, let types, let arguments else { return }
    var darwin = DarwinArguments(arguments)
    let split = ArchiveTypes.split(Array(UnsafeRawBufferPointer(start: types, count: strlen(types))))
    let pointers = split.map { _ in UnsafeRawPointer(darwin.nextPointer()) }
    if LegacyArchivers.encodeGroup(coder, split, pointers) { return }
    typealias F = @convention(c) (id?, SEL, UnsafePointer<CChar>?, UnsafeRawPointer?) -> Void
    for (type, pointer) in zip(split, pointers) {
        (type + [0]).withUnsafeBufferPointer { buffer in
            buffer.baseAddress!.withMemoryRebound(to: CChar.self, capacity: buffer.count) {
                unsafeBitCast(ObjC.msgSend, to: F.self)(coder, ObjC.selector("encodeValueOfObjCType:at:"), $0, pointer)
            }
        }
    }
}

/// - (void)decodeValuesOfObjCTypes:(const char *)types, ...: each pointer
/// with -decodeValueOfObjCType:at: and its type.
@c
public func perry_foundation_decodeValuesOfObjCTypes(_ coder: id?, _ cmd: SEL?, _ types: UnsafePointer<CChar>?,
                                                     _ arguments: UnsafeRawPointer?) {
    guard let coder, let types, let arguments else { return }
    var darwin = DarwinArguments(arguments)
    typealias F = @convention(c) (id?, SEL, UnsafePointer<CChar>?, UnsafeMutableRawPointer?) -> Void
    for type in ArchiveTypes.split(Array(UnsafeRawBufferPointer(start: types, count: strlen(types)))) {
        let pointer = darwin.nextPointer()
        (type + [0]).withUnsafeBufferPointer { buffer in
            buffer.baseAddress!.withMemoryRebound(to: CChar.self, capacity: buffer.count) {
                unsafeBitCast(ObjC.msgSend, to: F.self)(coder, ObjC.selector("decodeValueOfObjCType:at:"), $0, pointer)
            }
        }
    }
}

/// A keyed coder's rectangles, points and sizes, as strings of them under
/// the key (as Foundation's coders keep them, and nibs hold "NSFrame"),
/// made of the coder's -decodeObjectForKey: and -encodeObject:forKey:: for
/// NSCoder and the keyed archiver and unarchiver, as C functions, since
/// this library's methods don't take them.
/// None on armv7: it runs only iOS apps, whose coders have no such methods
/// (UIKit's -decodeCGRectForKey: and the like are its own), and which this
/// library builds without Foundation's NSRect functions (see Geometry.swift).
enum CoderGeometry {
    static func add(to cls: ObjCClass) {
        #if !arch(arm)
        let rect: @convention(c) (id?, SEL, id?) -> CGRect = { coder, _, key in
            NSRectFromString(ObjC.send(coder, ObjC.selector("decodeObjectForKey:"), key))
        }
        let point: @convention(c) (id?, SEL, id?) -> CGPoint = { coder, _, key in
            NSPointFromString(ObjC.send(coder, ObjC.selector("decodeObjectForKey:"), key))
        }
        let size: @convention(c) (id?, SEL, id?) -> CGSize = { coder, _, key in
            NSSizeFromString(ObjC.send(coder, ObjC.selector("decodeObjectForKey:"), key))
        }
        let encodeRect: @convention(c) (id?, SEL, CGRect, id?) -> Void = { coder, _, value, key in
            _ = ObjC.send(coder, ObjC.selector("encodeObject:forKey:"), NSStringFromRect(value), key)
        }
        let encodePoint: @convention(c) (id?, SEL, CGPoint, id?) -> Void = { coder, _, value, key in
            _ = ObjC.send(coder, ObjC.selector("encodeObject:forKey:"), NSStringFromPoint(value), key)
        }
        let encodeSize: @convention(c) (id?, SEL, CGSize, id?) -> Void = { coder, _, value, key in
            _ = ObjC.send(coder, ObjC.selector("encodeObject:forKey:"), NSStringFromSize(value), key)
        }
        let rectType = "{CGRect={CGPoint=dd}{CGSize=dd}}", pointType = "{CGPoint=dd}", sizeType = "{CGSize=dd}"
        cls.addMethod("decodeRectForKey:", types: "\(rectType)24@0:8@16", implementation: unsafeBitCast(rect, to: UnsafeRawPointer.self),
                      isClassMethod: false)
        cls.addMethod("decodePointForKey:", types: "\(pointType)24@0:8@16", implementation: unsafeBitCast(point, to: UnsafeRawPointer.self),
                      isClassMethod: false)
        cls.addMethod("decodeSizeForKey:", types: "\(sizeType)24@0:8@16", implementation: unsafeBitCast(size, to: UnsafeRawPointer.self),
                      isClassMethod: false)
        cls.addMethod("encodeRect:forKey:", types: "v56@0:8\(rectType)16@48", implementation: unsafeBitCast(encodeRect, to: UnsafeRawPointer.self),
                      isClassMethod: false)
        cls.addMethod("encodePoint:forKey:", types: "v40@0:8\(pointType)16@32", implementation: unsafeBitCast(encodePoint, to: UnsafeRawPointer.self),
                      isClassMethod: false)
        cls.addMethod("encodeSize:forKey:", types: "v40@0:8\(sizeType)16@32", implementation: unsafeBitCast(encodeSize, to: UnsafeRawPointer.self),
                      isClassMethod: false)
        #endif
    }
}
