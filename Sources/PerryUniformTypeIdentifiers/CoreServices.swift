import Glibc
import PerryObjCInterop

// Mac apps' alone: armv7 runs only iOS apps, so it has none of this.
#if !arch(arm)
// The rest of CoreServices that Mac apps call: UCKeyTranslate with the U.S.
// keyboard layout (the one AppKit's text input source names), Gestalt's
// system version (macOS 14), Launch Services, which finds no other apps
// and opens nothing, and its long date-times.

/// The characters the U.S. layout types for a Mac virtual key code: plain
/// and with shift.
private let usLayout: [UInt16: (String, String)] = {
    var keys: [UInt16: (String, String)] = [:]
    let letters: [(UInt16, Character)] = [(0x00, "a"), (0x01, "s"), (0x02, "d"), (0x03, "f"), (0x04, "h"), (0x05, "g"), (0x06, "z"),
                                         (0x07, "x"), (0x08, "c"), (0x09, "v"), (0x0B, "b"), (0x0C, "q"), (0x0D, "w"), (0x0E, "e"),
                                         (0x0F, "r"), (0x10, "y"), (0x11, "t"), (0x1F, "o"), (0x20, "u"), (0x22, "i"), (0x23, "p"),
                                         (0x25, "l"), (0x26, "j"), (0x28, "k"), (0x2D, "n"), (0x2E, "m")]
    for (code, letter) in letters { keys[code] = (String(letter), String(letter).uppercased()) }
    let others: [(UInt16, String, String)] = [
        (0x12, "1", "!"), (0x13, "2", "@"), (0x14, "3", "#"), (0x15, "4", "$"), (0x16, "6", "^"), (0x17, "5", "%"), (0x18, "=", "+"),
        (0x19, "9", "("), (0x1A, "7", "&"), (0x1B, "-", "_"), (0x1C, "8", "*"), (0x1D, "0", ")"), (0x1E, "]", "}"), (0x21, "[", "{"),
        (0x27, "'", "\""), (0x29, ";", ":"), (0x2A, "\\", "|"), (0x2B, ",", "<"), (0x2C, "/", "?"), (0x2F, ".", ">"), (0x32, "`", "~"),
        (0x0A, "§", "±"), (0x31, " ", " "), (0x24, "\r", "\r"), (0x30, "\t", "\t"), (0x33, "\u{08}", "\u{08}"), (0x35, "\u{1B}", "\u{1B}"),
        (0x41, ".", "."), (0x43, "*", "*"), (0x45, "+", "+"), (0x4B, "/", "/"), (0x4C, "\u{03}", "\u{03}"), (0x4E, "-", "-"),
        (0x51, "=", "="), (0x52, "0", "0"), (0x53, "1", "1"), (0x54, "2", "2"), (0x55, "3", "3"), (0x56, "4", "4"), (0x57, "5", "5"),
        (0x58, "6", "6"), (0x59, "7", "7"), (0x5B, "8", "8"), (0x5C, "9", "9"), (0x47, "\u{1B}", "\u{1B}"),
        // Arrows, Home, End, page keys, forward delete and help, as Carbon's char codes.
        (0x7B, "\u{1C}", "\u{1C}"), (0x7C, "\u{1D}", "\u{1D}"), (0x7E, "\u{1E}", "\u{1E}"), (0x7D, "\u{1F}", "\u{1F}"),
        (0x73, "\u{01}", "\u{01}"), (0x77, "\u{04}", "\u{04}"), (0x74, "\u{0B}", "\u{0B}"), (0x79, "\u{0C}", "\u{0C}"),
        (0x75, "\u{7F}", "\u{7F}"), (0x72, "\u{05}", "\u{05}"),
    ]
    for (code, plain, shifted) in others { keys[code] = (plain, shifted) }
    // Function keys type kFunctionKeyCharCode.
    for code: UInt16 in [0x7A, 0x78, 0x63, 0x76, 0x60, 0x61, 0x62, 0x64, 0x65, 0x6D, 0x67, 0x6F, 0x69, 0x6B, 0x71, 0x6A, 0x40, 0x4F, 0x50] {
        keys[code] = ("\u{10}", "\u{10}")
    }
    return keys
}()

/// OSStatus UCKeyTranslate(const UCKeyboardLayout *, UInt16 virtualKeyCode,
/// UInt16 keyAction, UInt32 modifierKeyState, UInt32 keyboardType,
/// OptionBits options, UInt32 *deadKeyState, UniCharCount maxLength,
/// UniCharCount *actualLength, UniChar *string). The modifiers are
/// EventModifiers shifted right by 8: shift 0x02, caps lock 0x04. There are
/// no dead keys in the U.S. layout.
@c(_UCKeyTranslate)
public func UCKeyTranslate(_ layout: UnsafeRawPointer?, _ keyCode: UInt16, _ action: UInt16, _ modifiers: UInt32, _ keyboardType: UInt32,
                           _ options: UInt32, _ deadKeyState: UnsafeMutablePointer<UInt32>?, _ maxLength: Int,
                           _ actualLength: UnsafeMutablePointer<Int>?, _ string: UnsafeMutablePointer<UInt16>?) -> Int32 {
    deadKeyState?.pointee = 0
    guard layout != nil else { return -50 }   // paramErr
    guard let (plain, shifted) = usLayout[keyCode] else {
        actualLength?.pointee = 0
        return 0
    }
    let shift = modifiers & 0x02 != 0
    let capsLock = modifiers & 0x04 != 0
    var text = shift ? shifted : plain
    if capsLock, !shift, plain.count == 1, plain.first?.isLetter == true { text = shifted }
    let units = Array(text.utf16)
    let count = min(units.count, max(maxLength, 0))
    for index in 0..<count { string?[index] = units[index] }
    actualLength?.pointee = count
    return 0
}

/// OSErr Gestalt(OSType selector, SInt32 *response): the system version,
/// macOS 14.4, as 'sysv' (capped at 10.9.3 as Apple's is) and 'sys1' to
/// 'sys3'; other selectors aren't known.
@c(_Gestalt)
public func Gestalt(_ selector: UInt32, _ response: UnsafeMutablePointer<Int32>?) -> Int16 {
    func code(_ text: String) -> UInt32 { text.utf8.reduce(0) { $0 << 8 | UInt32($1) } }
    let answers: [UInt32: Int32] = [code("sysv"): 0x1093, code("sys1"): 14, code("sys2"): 4, code("sys3"): 0]
    guard let answer = answers[selector] else { return -5551 }    // gestaltUndefSelectorErr
    response?.pointee = answer
    return 0
}

/// No other app can be found or opened here: kLSApplicationNotFoundErr.
@c(_LSCopyApplicationURLsForBundleIdentifier)
public func LSCopyApplicationURLsForBundleIdentifier(_ identifier: UnsafeMutableRawPointer?,
                                                     _ error: UnsafeMutablePointer<UnsafeMutableRawPointer?>?) -> UnsafeMutableRawPointer? {
    error?.pointee = nil
    return nil
}

@c(_LSOpenCFURLRef)
public func LSOpenCFURLRef(_ url: UnsafeMutableRawPointer?, _ launched: UnsafeMutablePointer<UnsafeMutableRawPointer?>?) -> Int32 {
    launched?.pointee = nil
    let text = url.map { NSObject($0).describedByObject() } ?? "a URL"
    let line = "perry: CoreServices: no app here to open \(text)\n"
    line.withCString { _ = write(2, $0, strlen($0)) }
    return -10814
}

/// LongDateTime: seconds since 1904, as an Int64; CFAbsoluteTime counts
/// from 2001, 3,061,152,000 seconds later.
@c(_UCConvertCFAbsoluteTimeToLongDateTime)
public func UCConvertCFAbsoluteTimeToLongDateTime(_ time: Double, _ longDate: UnsafeMutablePointer<Int64>?) -> Int32 {
    longDate?.pointee = Int64((time + 3_061_152_000).rounded(.down))
    return 0
}

@c(_UCConvertLongDateTimeToCFAbsoluteTime)
public func UCConvertLongDateTimeToCFAbsoluteTime(_ longDate: Int64, _ time: UnsafeMutablePointer<Double>?) -> Int32 {
    time?.pointee = Double(longDate) - 3_061_152_000
    return 0
}

extension NSObject {
    @ObjCMethod("description") func describedByObject() -> String
}

#endif
