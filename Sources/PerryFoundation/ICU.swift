import _FoundationICU

/// Calls into ICU's C API: the Swift toolchain's copy (swift-foundation's
/// build of Apple's ICU), which swift-foundation's calendars and locales
/// run on, so formatters and calendars share one ICU and one set of data.
enum ICU {
    static func failed(_ status: UErrorCode) -> Bool { status.rawValue > U_ZERO_ERROR.rawValue }

    /// A string an ICU function writes into a buffer, retried at the length
    /// it asks for.
    static func string(_ body: (UnsafeMutablePointer<UChar>?, Int32, UnsafeMutablePointer<UErrorCode>) -> Int32) -> String? {
        var status = U_ZERO_ERROR
        var buffer = [UChar](repeating: 0, count: 256)
        var length = body(&buffer, Int32(buffer.count), &status)
        if status == U_BUFFER_OVERFLOW_ERROR {
            status = U_ZERO_ERROR
            buffer = [UChar](repeating: 0, count: Int(length) + 1)
            length = body(&buffer, Int32(buffer.count), &status)
        }
        guard !failed(status), length >= 0 else { return nil }
        return String(decoding: buffer.prefix(Int(length)), as: UTF16.self)
    }

    /// Runs `body` with a string as UTF-16 and its length.
    static func withUChars<T>(_ string: String, _ body: (UnsafePointer<UChar>, Int32) -> T) -> T {
        let units = Array(string.utf16) + [0]
        return units.withUnsafeBufferPointer { body($0.baseAddress!, Int32(units.count - 1)) }
    }
}
