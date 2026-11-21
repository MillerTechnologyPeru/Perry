import CPerryFoundation
import FoundationEssentials
import PerryObjCInterop

/// An archived object's keyed fields, kept as they were decoded so the
/// object archives again as it was: for classes whose archives hold more
/// than the object here uses (a number formatter in a xib that Interface
/// Builder reads and compiles to a nib).
final class ArchivedFields {
    enum Kind {
        case object, bool, integer, bytes
    }

    typealias Field = (key: String, kind: Kind)

    private let fields: [Field]
    private var objects: [String: id] = [:]
    private var numbers: [String: Int] = [:]
    private var bytes: [String: [UInt8]] = [:]

    /// Decodes the fields the coder has.
    init(coder: id, fields: [Field]) {
        self.fields = fields
        for (key, kind) in fields {
            let name = Strings.autoreleased(key)
            guard ObjC.sendBool(coder, ObjC.selector("containsValueForKey:"), name) else { continue }
            switch kind {
            case .object:
                if let value = ObjC.send(coder, ObjC.selector("decodeObjectForKey:"), name) { objects[key] = ObjC.retain(value) }
            case .bool:
                numbers[key] = ObjC.sendBool(coder, ObjC.selector("decodeBoolForKey:"), name) ? 1 : 0
            case .integer:
                numbers[key] = ObjC.sendInt(coder, ObjC.selector("decodeIntegerForKey:"), name)
            case .bytes:
                typealias Decode = @convention(c) (id?, SEL, id?, UnsafeMutablePointer<UInt>?) -> UnsafeRawPointer?
                var length: UInt = 0
                let decode = unsafeBitCast(ObjC.msgSend, to: Decode.self)
                if let start = decode(coder, ObjC.selector("decodeBytesForKey:returnedLength:"), name, &length) {
                    bytes[key] = Array(UnsafeRawBufferPointer(start: start, count: Int(length)))
                }
            }
        }
    }

    deinit {
        objects.values.forEach { ObjC.release($0) }
    }

    func object(_ key: String) -> id? { objects[key] }
    func string(_ key: String) -> String? { objects[key].flatMap { ObjC.isKind($0, of: Strings.stringClass) ? Strings.value(of: $0) : nil } }
    func integer(_ key: String) -> Int? { numbers[key] }
    func bool(_ key: String) -> Bool? { numbers[key].map { $0 != 0 } }

    /// Encodes the fields that were decoded, under their keys.
    func encode(coder: id) {
        typealias EncodeObject = @convention(c) (id?, SEL, id?, id?) -> Void
        typealias EncodeInteger = @convention(c) (id?, SEL, Int, id?) -> Void
        typealias EncodeBool = @convention(c) (id?, SEL, Bool, id?) -> Void
        typealias EncodeBytes = @convention(c) (id?, SEL, UnsafeRawPointer?, UInt, id?) -> Void
        for (key, kind) in fields {
            let name = Strings.autoreleased(key)
            switch kind {
            case .object:
                guard let value = objects[key] else { continue }
                unsafeBitCast(ObjC.msgSend, to: EncodeObject.self)(coder, ObjC.selector("encodeObject:forKey:"), value, name)
            case .bool:
                guard let value = numbers[key] else { continue }
                unsafeBitCast(ObjC.msgSend, to: EncodeBool.self)(coder, ObjC.selector("encodeBool:forKey:"), value != 0, name)
            case .integer:
                guard let value = numbers[key] else { continue }
                unsafeBitCast(ObjC.msgSend, to: EncodeInteger.self)(coder, ObjC.selector("encodeInteger:forKey:"), value, name)
            case .bytes:
                guard let value = bytes[key] else { continue }
                value.withUnsafeBytes {
                    unsafeBitCast(ObjC.msgSend, to: EncodeBytes.self)(coder, ObjC.selector("encodeBytes:length:forKey:"), $0.baseAddress,
                                                                      UInt(value.count), name)
                }
            }
        }
    }
}

/// What a decimal number is archived as: its exponent, length, sign and
/// mantissa. Foundation's gives back an NSDecimalNumber; this one keeps
/// the fields and archives them again, which is all a nib's number
/// formatter needs of its minimum and maximum.
@ObjCClass("NSDecimalNumberPlaceholder")
public final class NSDecimalNumberPlaceholder: NSObject {
    override public class func didDefineObjCClass(_ cls: ObjCClass) {
        NSObject.registerObjCCategoryStorageAllocated(cls)
    }

    private static let fields: [ArchivedFields.Field] = [
        ("NS.exponent", .integer), ("NS.length", .integer), ("NS.negative", .bool), ("NS.compact", .bool), ("NS.mantissa.bo", .integer),
        ("NS.mantissa", .bytes),
    ]

    @ObjCMethod("initWithCoder:")
    func initialize(coder: ObjCObject) -> Self {
        Storage.set(objcObject, ArchivedFields(coder: coder.id, fields: Self.fields))
        return self
    }

    @ObjCMethod("encodeWithCoder:")
    func encode(coder: ObjCObject) {
        Storage.get(objcObject, as: ArchivedFields.self)?.encode(coder: coder.id)
    }
}
