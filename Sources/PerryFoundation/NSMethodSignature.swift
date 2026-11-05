import FoundationEssentials
import Glibc
import PerryObjCInterop

// NSMethodSignature: a method's return and argument types, from the type
// encoding the runtime keeps for it ("v24@0:8@16": void, self, _cmd, an
// object), with each type's size as Darwin's arm64 lays it out.

final class MethodSignatureStorage {
    /// The encoding as given.
    let types: String
    /// The return type, then the arguments (self and _cmd first), each as
    /// its own C string, which -getArgumentTypeAtIndex: returns.
    let parts: [UnsafeMutablePointer<CChar>]
    let sizes: [Int]

    init?(_ types: String) {
        var parts: [UnsafeMutablePointer<CChar>] = []
        var sizes: [Int] = []
        let bytes = Array(types.utf8)
        var parser = TypeEncoding.Parser(bytes: bytes)
        while parser.index < bytes.count {
            let start = parser.index
            guard let (size, _) = parser.type() else {
                parts.forEach { free($0) }
                return nil
            }
            let encoding = String(decoding: bytes[start..<parser.index], as: UTF8.self)
            parts.append(strdup(encoding)!)
            sizes.append(size)
            // The frame offset after each type, which may be signed.
            while parser.index < bytes.count, bytes[parser.index] == UInt8(ascii: "-") || bytes[parser.index] == UInt8(ascii: "+")
                    || (UInt8(ascii: "0")...UInt8(ascii: "9")).contains(bytes[parser.index]) {
                parser.index += 1
            }
        }
        guard !parts.isEmpty else { return nil }
        self.types = types
        self.parts = parts
        self.sizes = sizes
    }

    deinit { parts.forEach { free($0) } }

    var argumentCount: Int { parts.count - 1 }

    /// The arguments' frame: each at least a register's 8 bytes, aligned.
    var frameLength: Int { sizes.dropFirst().reduce(0) { $0 + ($1 + 7) / 8 * 8 } }
}

enum MethodSignatures {
    nonisolated(unsafe) static var signatureClass: Class!

    static func storage(_ object: id?) -> MethodSignatureStorage? { Storage.get(object, as: MethodSignatureStorage.self) }

    /// A signature for the encoding, autoreleased; nil if it can't be read.
    static func make(_ types: String) -> id? {
        guard let storage = MethodSignatureStorage(types) else { return nil }
        let object = Storage.allocate(UnsafeMutableRawPointer(signatureClass))!
        Storage.set(object, storage)
        return ObjC.autorelease(object)
    }

    /// The signature of the method `selector` names on `cls` (a metaclass
    /// for class methods); nil without one.
    static func of(_ cls: Class?, _ selector: SEL?) -> id? {
        guard let cls, let selector, let method = ObjC.instanceMethod(cls, selector),
              let types = ObjC.methodTypes(method) else { return nil }
        return make(String(cString: types))
    }
}

@ObjCClass("NSMethodSignature")
public final class NSMethodSignature: NSObject {
    override public class func didDefineObjCClass(_ cls: ObjCClass) {
        NSObject.registerObjCCategoryStorageAllocated(cls)
        MethodSignatures.signatureClass = cls.storage
    }

    private var storage: MethodSignatureStorage? { MethodSignatures.storage(objcObject) }

    @ObjCClassMethod("signatureWithObjCTypes:")
    static func signature(objCTypes types: UnsafePointer<CChar>?) -> UnsafeMutableRawPointer? {
        guard let types else { return nil }
        return MethodSignatures.make(String(cString: types))
    }

    @ObjCMethod("dealloc")
    func dealloc() {
        Storage.set(objcObject, nil)
        ObjC.superDealloc(objcObject, from: MethodSignatures.signatureClass)
    }

    @ObjCMethod("copyWithZone:") func copy(zone: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer? { ObjC.retain(objcObject) }

    @ObjCMethod("numberOfArguments") func numberOfArguments() -> UInt { UInt(storage?.argumentCount ?? 0) }

    @ObjCMethod("getArgumentTypeAtIndex:")
    func argumentType(at index: UInt) -> UnsafePointer<CChar>? {
        guard let storage, Int(index) < storage.argumentCount else {
            foundationFatal("-[NSMethodSignature getArgumentTypeAtIndex:]: index (\(index)) out of bounds [0, \((storage?.argumentCount ?? 0) - 1)]")
        }
        return UnsafePointer(storage.parts[Int(index) + 1])
    }

    @ObjCMethod("methodReturnType") func methodReturnType() -> UnsafePointer<CChar>? { storage.map { UnsafePointer($0.parts[0]) } }
    @ObjCMethod("methodReturnLength") func methodReturnLength() -> UInt { UInt(storage?.sizes[0] ?? 0) }
    @ObjCMethod("frameLength") func frameLength() -> UInt { UInt(storage?.frameLength ?? 0) }

    /// Whether the return type is qualified oneway ("Vv").
    @ObjCMethod("isOneway") func isOneway() -> Bool { storage?.types.hasPrefix("V") ?? false }

    @ObjCMethod("isEqual:")
    func isEqual(_ other: ObjCObject?) -> Bool {
        guard let other, let theirs = MethodSignatures.storage(other.objcObject), let storage else { return false }
        return theirs.parts.map { String(cString: $0) } == storage.parts.map { String(cString: $0) }
    }

    @ObjCMethod("hash") func hash() -> UInt { Strings.hash(storage?.parts.map { String(cString: $0) }.joined() ?? "") }

    @ObjCMethod("description")
    func description() -> String { "<NSMethodSignature: \(objcObject)> \(storage?.types ?? "")" }
}

@ObjCCategory("MethodSignatures")
extension NSObject {
    /// The signature of the receiver's method: an instance's, or for a
    /// class, its class method's.
    @ObjCMethod("methodSignatureForSelector:")
    func methodSignature(for selector: ObjCSelector?) -> UnsafeMutableRawPointer? {
        MethodSignatures.of(ObjC.objectGetClass(objcObject), selector.map { $0.pointer.assumingMemoryBound(to: CChar.self) })
    }

    /// The signature of instances' method, sent to a class.
    @ObjCClassMethod("instanceMethodSignatureForSelector:")
    static func instanceMethodSignature(_ cls: ObjCClass, for selector: ObjCSelector?) -> UnsafeMutableRawPointer? {
        MethodSignatures.of(cls.storage, selector.map { $0.pointer.assumingMemoryBound(to: CChar.self) })
    }
}
