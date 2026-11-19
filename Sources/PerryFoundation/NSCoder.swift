import PerryObjCInterop

/// NSCoder: the abstract coder that programs' own coders subclass
/// (Interface Builder's XML decoder does). A subclass supplies the
/// primitives, -encodeValueOfObjCType:at: and -decodeValueOfObjCType:at:;
/// the object methods here are made of them, and the rest answer as
/// NSCoder's do for a coder that isn't keyed.
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
    @ObjCMethod("encodeRootObject:") func encodeRoot(object: UnsafeMutableRawPointer?) { encode(object: object) }
    @ObjCMethod("encodeBycopyObject:") func encodeBycopy(object: UnsafeMutableRawPointer?) { encode(object: object) }
    @ObjCMethod("encodeByrefObject:") func encodeByref(object: UnsafeMutableRawPointer?) { encode(object: object) }
    @ObjCMethod("encodeConditionalObject:") func encodeConditional(object: UnsafeMutableRawPointer?) { encode(object: object) }
}
