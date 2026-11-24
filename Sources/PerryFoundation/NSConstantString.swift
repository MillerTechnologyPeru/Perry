import CPerryFoundation
import PerryObjCInterop

// NSSimpleCString and NSConstantString: the string literals of compilers
// before CFString literals, and of clang with -fno-constant-cfstrings or
// GNU-style -fconstant-string-class: { isa, char *bytes, unsigned int
// length }, a word each but the length, emitted by the compiler and read
// in place, as __NSCFConstantString's are. Their bytes are UTF-8 and need
// not end at the length.

enum LegacyConstantStrings {
    nonisolated(unsafe) static var simpleClass: Class?
    nonisolated(unsafe) static var constantClass: Class?

    /// The characters of a literal of either class; nil for any other
    /// object.
    static func value(_ object: id, _ cls: Class?) -> String? {
        guard let cls, cls == constantClass || cls == simpleClass else { return nil }
        let word = MemoryLayout<UInt>.size
        let bytes = object.load(fromByteOffset: word, as: UnsafePointer<UInt8>?.self)
        let length = Int(object.load(fromByteOffset: 2 * word, as: UInt32.self))
        guard let bytes, length > 0 else { return "" }
        return String(decoding: UnsafeBufferPointer(start: bytes, count: length), as: UTF8.self)
    }
}

/// NSSimpleCString: a string over a program's C string, which only
/// compilers make, as literals; retain and release leave them be.
@ObjCClass("NSSimpleCString")
public class NSSimpleCString: NSString {
    override public class func didDefineObjCClass(_ cls: ObjCClass) {
        NSObject.registerObjCCategoryImmortal(cls)
        LegacyConstantStrings.simpleClass = cls.markingStatic().storage
    }
}

/// NSConstantString: the literal class of older compilers.
@ObjCClass("NSConstantString")
public final class NSConstantString: NSSimpleCString {
    override public class func didDefineObjCClass(_ cls: ObjCClass) {
        NSObject.registerObjCCategoryImmortal(cls)
        LegacyConstantStrings.constantClass = cls.markingStatic().storage
    }
}
