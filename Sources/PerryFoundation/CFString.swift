import CPerryFoundation
import PerryObjCInterop

// CoreFoundation's CFString functions. CFString is toll-free bridged: a
// CFStringRef is an NSString, and a CFMutableStringRef an NSMutableString.

/// The string transforms CFStringTransform knows by name.
@ObjCConstants
enum StringTransforms {
    static let kCFStringTransformToXMLHex = "Any-Hex/XML"
}

/// CFIndex CFStringGetLength(CFStringRef): UTF-16 units, as NSString counts.
@c(_CFStringGetLength)
public func CFStringGetLength(_ string: UnsafeMutableRawPointer?) -> Int {
    Strings.value(of: string)?.utf16.count ?? 0
}

// MARK: - Swift's bridging

// Swift's runtime makes its strings NSStrings with these, and hashes
// them as NSString does, so a bridged string finds its equal in an
// NSDictionary or NSSet.

/// Whether an object is an NSString, of any subclass.
@c(__NSIsNSString)
public func _NSIsNSString(_ object: UnsafeMutableRawPointer?) -> Bool {
    guard let object else { return false }
    return ObjC.isKind(object, of: Strings.stringClass)
}

/// NSString's hash of `length` ASCII bytes.
@c(_CFStringHashCString)
public func CFStringHashCString(_ bytes: UnsafePointer<UInt8>?, _ length: Int) -> UInt {
    guard let bytes, length > 0 else { return Strings.hash("") }
    return Strings.hash(String(decoding: UnsafeBufferPointer(start: bytes, count: length), as: UTF8.self))
}

/// NSString's hash of a string, from its characters: never its -hash,
/// which Swift's strings implement with this.
@c(_CFStringHashNSString)
public func CFStringHashNSString(_ string: UnsafeMutableRawPointer?) -> UInt {
    Strings.hash(Strings.value(of: string) ?? "")
}

/// Strings are never tagged pointers here: nil has Swift make an object.
@c(__CFStringCreateTaggedPointerString)
public func _CFStringCreateTaggedPointerString(_ bytes: UnsafePointer<UInt8>?, _ length: Int) -> UnsafeMutableRawPointer? {
    nil
}

/// void CFStringTrimWhitespace(CFMutableStringRef): removes whitespace and
/// newlines from both ends.
@c(_CFStringTrimWhitespace)
public func CFStringTrimWhitespace(_ string: UnsafeMutableRawPointer?) {
    let storage = MutableStrings.storage(string)
    let scalars = storage.value.unicodeScalars
    guard let first = scalars.firstIndex(where: { !$0.properties.isWhitespace }),
          let last = scalars.lastIndex(where: { !$0.properties.isWhitespace }) else {
        storage.value = ""
        return
    }
    storage.value = String(scalars[first...last])
}

/// Boolean CFStringTransform(CFMutableStringRef, CFRange *, CFStringRef
/// transform, Boolean reverse). Only kCFStringTransformToXMLHex: characters
/// outside ASCII to and from "&#xF3;". Other transforms report failure.
@c(_CFStringTransform)
public func CFStringTransform(_ string: UnsafeMutableRawPointer?, _ range: UnsafeMutablePointer<NSRange>?,
                              _ transform: UnsafeMutableRawPointer?, _ reverse: Bool) -> Bool {
    guard Strings.value(of: transform) == StringTransforms.kCFStringTransformToXMLHex else { return false }
    let storage = MutableStrings.storage(string)
    var units = Array(storage.value.utf16)
    let location = range.map { Int($0.pointee.location) } ?? 0
    let length = range.map { Int($0.pointee.length) } ?? units.count
    guard location >= 0, length >= 0, location + length <= units.count else { return false }
    let part = String(decoding: units[location..<location + length], as: UTF16.self)
    let transformed = reverse ? XMLHex.decode(part) : XMLHex.encode(part)
    let replacement = Array(transformed.utf16)
    units.replaceSubrange(location..<location + length, with: replacement)
    storage.value = String(decoding: units, as: UTF16.self)
    range?.pointee.length = UInt(replacement.count)
    return true
}

/// ICU's Any-Hex/XML transform.
enum XMLHex {
    static func encode(_ text: String) -> String {
        var result = ""
        for scalar in text.unicodeScalars {
            if scalar.isASCII {
                result.unicodeScalars.append(scalar)
            } else {
                result += "&#x" + String(scalar.value, radix: 16, uppercase: true) + ";"
            }
        }
        return result
    }

    /// Replaces each "&#xHEX;" with its character; anything else stays.
    static func decode(_ text: String) -> String {
        var result = ""
        var rest = Substring(text)
        while let start = rest.firstRange(of: "&#") {
            result += rest[..<start.lowerBound]
            var cursor = rest[start.upperBound...]
            if let marker = cursor.first, marker == "x" || marker == "X" {
                cursor = cursor.dropFirst()
                let digits = cursor.prefix { $0.isHexDigit }
                let afterDigits = cursor.dropFirst(digits.count)
                if !digits.isEmpty, afterDigits.first == ";",
                   let value = UInt32(digits, radix: 16), let scalar = Unicode.Scalar(value) {
                    result.unicodeScalars.append(scalar)
                    rest = afterDigits.dropFirst()
                    continue
                }
            }
            result += "&#"
            rest = rest[start.upperBound...]
        }
        return result + rest
    }
}
