import CPerryGeometry
import Glibc
import PerryObjCInterop

// AppKit's reading of a file into an attributed string: plain text, in the
// encoding the options give (NSCharacterEncodingDocumentOption) or UTF-8,
// with ISO Latin 1 to fall back on as any bytes decode in it. Xcode's
// editor loads its text storage with it.

@ObjCWrapper("NSMutableAttributedString")
class NSMutableAttributedString: NSObject {}

@ObjCCategory("NSMutableAttributedStringKitAdditions")
extension NSMutableAttributedString {
    @ObjCMethod("readFromURL:options:documentAttributes:")
    func read(from url: NSObject?, options: NSObject?, documentAttributes: UnsafeMutablePointer<UnsafeMutableRawPointer?>?) -> Bool {
        AttributedStringReading.read(into: objcObject, from: url, options: options, documentAttributes: documentAttributes)
    }

    @ObjCMethod("readFromURL:options:documentAttributes:error:")
    func read(from url: NSObject?, options: NSObject?, documentAttributes: UnsafeMutablePointer<UnsafeMutableRawPointer?>?,
              error: UnsafeMutablePointer<UnsafeMutableRawPointer?>?) -> Bool {
        AttributedStringReading.read(into: objcObject, from: url, options: options, documentAttributes: documentAttributes)
    }
}

enum AttributedStringReading {
    /// Reads the file at `url` into `object`, an attributed string or a text
    /// storage, replacing its text through its -replaceCharactersInRange:
    /// withString: (a storage subclass keeping its own text gets it so).
    static func read(into object: UnsafeMutableRawPointer, from url: NSObject?, options: NSObject?,
                     documentAttributes: UnsafeMutablePointer<UnsafeMutableRawPointer?>?) -> Bool {
        guard let url, let path = Send.object(url.objcObject, "path").map({ String(objCArgument: $0) }),
              let dataClass = Classes.named("NSData")?.pointer,
              let data = Send.object(dataClass, "dataWithContentsOfFile:", path.objCArgument()) else { return false }
        // NSUTF8StringEncoding 4; NSISOLatin1StringEncoding 5.
        let requested = options.flatMap { Send.object($0.objcObject, "objectForKey:", "CharacterEncoding".objCArgument()) }
            .map { UInt(Send.integer($0, "unsignedIntegerValue")) }
        var encoding = requested ?? 4
        var text = decode(data, encoding)
        if text == nil, requested == nil {
            encoding = 5
            text = decode(data, encoding)
        }
        guard let text else { return false }
        let length = Send.integer(object, "length")
        typealias Replace = @convention(c) (UnsafeMutableRawPointer, UnsafeRawPointer, NSRange, UnsafeMutableRawPointer?) -> Void
        unsafeBitCast(ObjCRuntime.msgSend, to: Replace.self)(object, ObjCRuntime.selector("replaceCharactersInRange:withString:"),
                                                              NSRange(location: 0, length: UInt(length)), text)
        if let documentAttributes {
            let attributes = NSMutableDictionary.empty()
            attributes.set(NSObject(objCReturnValue: "NSPlainText".objCArgument()), forKey: "DocumentType")
            attributes.set(NSNumber.make(integer: Int(encoding)), forKey: "CharacterEncoding")
            documentAttributes.pointee = ObjCRuntime.autorelease(ObjCRuntime.retain(attributes.objcObject))
        }
        return true
    }

    /// The data as a string in `encoding`, or nil if it isn't text in it.
    private static func decode(_ data: UnsafeMutableRawPointer, _ encoding: UInt) -> UnsafeMutableRawPointer? {
        guard let stringClass = Classes.named("NSString")?.pointer, let allocated = Send.object(stringClass, "alloc") else { return nil }
        typealias Make = @convention(c) (UnsafeMutableRawPointer, UnsafeRawPointer, UnsafeMutableRawPointer, UInt) -> UnsafeMutableRawPointer?
        let made = unsafeBitCast(ObjCRuntime.msgSend, to: Make.self)(allocated, ObjCRuntime.selector("initWithData:encoding:"), data, encoding)
        return made.flatMap { ObjCRuntime.autorelease($0) }
    }
}
