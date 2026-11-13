// String's initializers and members that read bytes, code units and files, as
// Apple's Foundation overlay has them.

import Darwin

extension String {
    /// A string made from bytes in an encoding; the bytes are freed, as the
    /// caller asks, when copied.
    public init?(bytesNoCopy bytes: UnsafeMutableRawPointer, length: Int, encoding: Encoding, freeWhenDone flag: Bool) {
        guard let string = NSString(bytesNoCopy: bytes, length: length, encoding: encoding.rawValue, freeWhenDone: flag) else {
            return nil
        }
        self = String._unconditionallyBridgeFromObjectiveC(string)
    }

    /// A string made from UTF-16 code units.
    public init(utf16CodeUnits: UnsafePointer<unichar>, count: Int) {
        self = String(decoding: UnsafeBufferPointer(start: utf16CodeUnits, count: count), as: UTF16.self)
    }

    /// A string made from the contents of a file, read as UTF-8.
    public init(contentsOf url: __shared URL) throws {
        let data = try Data(contentsOf: url)
        guard let string = String(data: data, encoding: .utf8) else {
            throw CocoaError(.fileReadInapplicableStringEncoding, userInfo: [NSURLErrorKey: url])
        }
        self = string
    }
}

extension StringProtocol {
    /// A string made by appending another to this one.
    public func appending<T: StringProtocol>(_ aString: T) -> String {
        String(self) + String(aString)
    }
}
