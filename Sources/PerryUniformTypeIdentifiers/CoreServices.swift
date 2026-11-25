import Glibc
import PerryObjCInterop

// Mac apps' alone: armv7 runs only iOS apps, so it has none of this.
#if !arch(arm)
// The rest of CoreServices that Mac apps call: UCKeyTranslate with the U.S.
// keyboard layout (the one AppKit's text input source names), Gestalt's
// system version (macOS 14), Launch Services, which finds no other apps
// and opens nothing, its long date-times, characters' Unicode
// properties and collation.

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

/// The system version NSProcessInfo reports ("Version 10.5.8 (Perry)"):
/// major, minor and patch; macOS 14.4 if there is none.
private func systemVersion() -> (Int32, Int32, Int32) {
    typealias Send = @convention(c) (UnsafeMutableRawPointer?, UnsafeRawPointer) -> UnsafeMutableRawPointer?
    let send = unsafeBitCast(ObjCRuntime.msgSend, to: Send.self)
    guard let info = send(ObjCRuntime.classObject("NSProcessInfo"), ObjCRuntime.selector("processInfo")),
          let text = send(info, ObjCRuntime.selector("operatingSystemVersionString")) else { return (14, 4, 0) }
    let words = NSObject(text).stringValue.split(separator: " ")
    let numbers = (words.count > 1 ? words[1] : "").split(separator: ".").compactMap { Int32($0) }
    guard let major = numbers.first else { return (14, 4, 0) }
    return (major, numbers.count > 1 ? numbers[1] : 0, numbers.count > 2 ? numbers[2] : 0)
}

/// OSErr Gestalt(OSType selector, SInt32 *response): the system version
/// NSProcessInfo reports (Mac OS X 10.5.8 to a program from before 10.7),
/// as 'sysv' (in BCD, capped at 10.9.3 as Apple's is) and 'sys1' to
/// 'sys3'; other selectors aren't known.
@c(_Gestalt)
public func Gestalt(_ selector: UInt32, _ response: UnsafeMutablePointer<Int32>?) -> Int16 {
    func code(_ text: String) -> UInt32 { text.utf8.reduce(0) { $0 << 8 | UInt32($1) } }
    let (major, minor, patch) = systemVersion()
    let bcd: Int32 = major == 10 && minor <= 9 ? 0x1000 | minor << 4 | min(patch, 9) : 0x1093
    let answers: [UInt32: Int32] = [code("sysv"): bcd, code("sys1"): major, code("sys2"): minor, code("sys3"): patch]
    guard let answer = answers[selector] else { return -5551 }    // gestaltUndefSelectorErr
    response?.pointee = answer
    return 0
}

/// cpu_type_t _CSGetProcessorArchitecture(void): the processor the program
/// runs on, as Mach names it: CPU_TYPE_X86_64 for a 64-bit Intel program,
/// CPU_TYPE_X86 for a 32-bit one (Xcode 3 names the native architecture by
/// it).
@c(__CSGetProcessorArchitecture)
public func CSGetProcessorArchitecture() -> Int32 {
    MemoryLayout<Int>.size == 8 ? 0x0100_0007 : 7
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
@DarwinC("_UCConvertCFAbsoluteTimeToLongDateTime")
public func UCConvertCFAbsoluteTimeToLongDateTime(_ time: Double, _ longDate: UnsafeMutablePointer<Int64>?) -> Int32 {
    longDate?.pointee = Int64((time + 3_061_152_000).rounded(.down))
    return 0
}

@DarwinC("_UCConvertLongDateTimeToCFAbsoluteTime")
public func UCConvertLongDateTimeToCFAbsoluteTime(_ longDate: Int64, _ time: UnsafeMutablePointer<Double>?) -> Int32 {
    time?.pointee = Double(longDate) - 3_061_152_000
    return 0
}

/// OSStatus UCGetCharProperty(const UniChar *, UniCharCount,
/// UCCharPropertyType, UCCharPropertyValue *): a property of the first
/// character (a surrogate pair is one), from Swift's Unicode tables. The
/// bidirectional class, which Swift has no table for, is read from the
/// general category and the right-to-left scripts' blocks.
@c(_UCGetCharProperty)
public func UCGetCharProperty(_ characters: UnsafePointer<UInt16>?, _ length: Int, _ type: Int32,
                              _ value: UnsafeMutablePointer<UInt32>?) -> Int32 {
    let paramErr: Int32 = -50
    guard let characters, length > 0, let value else { return paramErr }
    // A lone surrogate is kUCGenlCatOtherSurrogate, with no other property.
    guard let scalar = UnicodeCharacterProperties.scalar(UnsafeBufferPointer(start: characters, count: length)) else {
        guard (1...3).contains(type) else { return paramErr }
        value.pointee = type == 1 ? 3 : 0
        return 0
    }
    switch type {
    case 1: value.pointee = UnicodeCharacterProperties.category(scalar)
    case 2: value.pointee = UInt32(scalar.properties.canonicalCombiningClass.rawValue)
    case 3: value.pointee = UnicodeCharacterProperties.bidiCategory(scalar)
    case 4:
        guard scalar.properties.numericType == .decimal, let digit = scalar.properties.numericValue else { return paramErr }
        value.pointee = UInt32(digit)
    default: return paramErr
    }
    return 0
}

/// A CollatorRef: UCCollateOptions, kept for UCCompareText.
final class Collator {
    let options: UInt32
    init(options: UInt32) { self.options = options }

    /// kUCCollate options this compares by: case, diacritics and digits.
    static let caseInsensitive: UInt32 = 1 << 3, diacriticInsensitive: UInt32 = 1 << 4, digitsAsNumber: UInt32 = 1 << 17

    /// Folds what the options ignore: case, and diacritics (combining marks
    /// after a base character and the Latin letters that carry them).
    static func folded(_ text: String, _ options: UInt32) -> [Unicode.Scalar] {
        var scalars = Array((options & caseInsensitive != 0 ? text.lowercased() : text).unicodeScalars)
        if options & diacriticInsensitive != 0 {
            scalars = scalars.compactMap { scalar in
                if scalar.properties.canonicalCombiningClass.rawValue != 0 { return nil }
                // A precomposed letter's base: its name's first word after
                // "LATIN SMALL/CAPITAL LETTER".
                if let name = scalar.properties.name, name.hasPrefix("LATIN "), name.contains(" WITH "),
                   let letter = name.split(separator: " ").dropFirst(3).first, letter.count == 1, let base = letter.unicodeScalars.first {
                    let lower = Unicode.Scalar(base.value | 0x20) ?? base
                    return name.contains("SMALL") || options & caseInsensitive != 0 ? lower : base
                }
                return scalar
            }
        }
        return scalars
    }

    /// -1, 0 or 1: by code point, with runs of digits compared as numbers
    /// when asked.
    static func compare(_ a: String, _ b: String, _ options: UInt32) -> Int32 {
        let left = folded(a, options), right = folded(b, options)
        var i = 0, j = 0
        while i < left.count, j < right.count {
            if options & digitsAsNumber != 0, left[i].properties.numericType == .decimal, right[j].properties.numericType == .decimal {
                var x = i, y = j
                while x < left.count, left[x].properties.numericType == .decimal { x += 1 }
                while y < right.count, right[y].properties.numericType == .decimal { y += 1 }
                let first = left[i..<x].map { Int($0.properties.numericValue ?? 0) }, second = right[j..<y].map { Int($0.properties.numericValue ?? 0) }
                let trimmedFirst = Array(first.drop { $0 == 0 }), trimmedSecond = Array(second.drop { $0 == 0 })
                if trimmedFirst.count != trimmedSecond.count { return trimmedFirst.count < trimmedSecond.count ? -1 : 1 }
                if trimmedFirst != trimmedSecond { return trimmedFirst.lexicographicallyPrecedes(trimmedSecond) ? -1 : 1 }
                i = x
                j = y
                continue
            }
            if left[i] != right[j] { return left[i].value < right[j].value ? -1 : 1 }
            i += 1
            j += 1
        }
        return left.count - i == right.count - j ? 0 : (left.count - i < right.count - j ? -1 : 1)
    }

    static func compare(_ options: UInt32, _ first: UnsafePointer<UInt16>?, _ firstLength: Int, _ second: UnsafePointer<UInt16>?,
                        _ secondLength: Int, _ equivalent: UnsafeMutablePointer<UInt8>?, _ order: UnsafeMutablePointer<Int32>?) -> Int32 {
        guard firstLength >= 0, secondLength >= 0, firstLength == 0 || first != nil, secondLength == 0 || second != nil else { return -50 }
        let a = String(decoding: UnsafeBufferPointer(start: first, count: firstLength), as: UTF16.self)
        let b = String(decoding: UnsafeBufferPointer(start: second, count: secondLength), as: UTF16.self)
        let result = compare(a, b, options)
        equivalent?.pointee = result == 0 ? 1 : 0
        order?.pointee = result
        return 0
    }
}

/// OSStatus UCCreateCollator(LocaleRef, LocaleOperationVariant, UCCollateOptions,
/// CollatorRef *): any locale's collator is this one.
@c(_UCCreateCollator)
public func UCCreateCollator(_ locale: UnsafeRawPointer?, _ variant: UInt32, _ options: UInt32,
                             _ collator: UnsafeMutablePointer<UnsafeMutableRawPointer?>?) -> Int32 {
    guard let collator else { return -50 }
    collator.pointee = Unmanaged.passRetained(Collator(options: options)).toOpaque()
    return 0
}

@c(_UCDisposeCollator)
public func UCDisposeCollator(_ collator: UnsafeMutablePointer<UnsafeMutableRawPointer?>?) -> Int32 {
    guard let collator, let reference = collator.pointee else { return -50 }
    Unmanaged<Collator>.fromOpaque(reference).release()
    collator.pointee = nil
    return 0
}

/// OSStatus UCCompareText(CollatorRef, const UniChar *, UniCharCount, const
/// UniChar *, UniCharCount, Boolean *equivalent, SInt32 *order).
@c(_UCCompareText)
public func UCCompareText(_ collator: UnsafeMutableRawPointer?, _ first: UnsafePointer<UInt16>?, _ firstLength: Int,
                          _ second: UnsafePointer<UInt16>?, _ secondLength: Int, _ equivalent: UnsafeMutablePointer<UInt8>?,
                          _ order: UnsafeMutablePointer<Int32>?) -> Int32 {
    guard let collator else { return -50 }
    let options = Unmanaged<Collator>.fromOpaque(collator).takeUnretainedValue().options
    return Collator.compare(options, first, firstLength, second, secondLength, equivalent, order)
}

@c(_UCCompareTextDefault)
public func UCCompareTextDefault(_ options: UInt32, _ first: UnsafePointer<UInt16>?, _ firstLength: Int,
                                 _ second: UnsafePointer<UInt16>?, _ secondLength: Int, _ equivalent: UnsafeMutablePointer<UInt8>?,
                                 _ order: UnsafeMutablePointer<Int32>?) -> Int32 {
    Collator.compare(options, first, firstLength, second, secondLength, equivalent, order)
}

/// UCGetCharProperty's values: Carbon's general and bidirectional categories.
private enum UnicodeCharacterProperties {
    /// The first character: a surrogate pair's scalar; nil for a lone
    /// surrogate.
    static func scalar(_ units: UnsafeBufferPointer<UInt16>) -> Unicode.Scalar? {
        let first = units[0]
        if UTF16.isLeadSurrogate(first), units.count > 1, UTF16.isTrailSurrogate(units[1]) {
            return Unicode.Scalar(0x10000 + (UInt32(first - 0xD800) << 10) + UInt32(units[1] - 0xDC00))
        }
        return Unicode.Scalar(first)
    }

    /// kUCGenlCat*.
    static func category(_ scalar: Unicode.Scalar) -> UInt32 {
        switch scalar.properties.generalCategory {
        case .unassigned: 0
        case .control: 1
        case .format: 2
        case .surrogate: 3
        case .privateUse: 4
        case .nonspacingMark: 5
        case .spacingMark: 6
        case .enclosingMark: 7
        case .decimalNumber: 8
        case .letterNumber: 9
        case .otherNumber: 10
        case .spaceSeparator: 11
        case .lineSeparator: 12
        case .paragraphSeparator: 13
        case .uppercaseLetter: 14
        case .lowercaseLetter: 15
        case .titlecaseLetter: 16
        case .modifierLetter: 17
        case .otherLetter: 18
        case .connectorPunctuation: 20
        case .dashPunctuation: 21
        case .openPunctuation: 22
        case .closePunctuation: 23
        case .initialPunctuation: 24
        case .finalPunctuation: 25
        case .otherPunctuation: 26
        case .mathSymbol: 28
        case .currencySymbol: 29
        case .modifierSymbol: 30
        case .otherSymbol: 31
        @unknown default: 0
        }
    }

    /// kUCBidiCat*: the explicit formatting characters by code point,
    /// Hebrew's and Arabic's blocks right to left, and the rest by category.
    static func bidiCategory(_ scalar: Unicode.Scalar) -> UInt32 {
        let value = scalar.value
        switch value {
        case 0x202A: return 13    // LRE
        case 0x202B: return 14    // RLE
        case 0x202C: return 17    // PDF
        case 0x202D: return 15    // LRO
        case 0x202E: return 16    // RLO
        case 0x2066: return 20    // LRI
        case 0x2067: return 21    // RLI
        case 0x2068: return 22    // FSI
        case 0x2069: return 23    // PDI
        case 0x09, 0x0B, 0x1F: return 9    // S
        case 0x0A, 0x0D, 0x1C...0x1E, 0x85: return 8    // B
        case 0x0660...0x0669, 0x066B, 0x066C, 0x06DD, 0x0890, 0x0891, 0x08E2: return 6    // AN
        case 0x2B, 0x2D: return 4    // ES
        case 0x23...0x25, 0xA2...0xA5, 0xB0, 0xB1, 0x2030...0x2034: return 5    // ET
        case 0x2C, 0x2E, 0x2F, 0x3A, 0xA0: return 7    // CS
        default: break
        }
        let properties = scalar.properties
        switch properties.generalCategory {
        case .nonspacingMark, .enclosingMark: return 18    // NSM
        case .spaceSeparator: return 10    // WS
        case .lineSeparator: return 10
        case .paragraphSeparator: return 8
        case .control, .format: return 19    // BN
        case .decimalNumber: return 3    // EN
        case .currencySymbol: return 5
        default: break
        }
        switch value {
        case 0x0590...0x05FF, 0x07C0...0x085F, 0xFB1D...0xFB4F, 0x10800...0x10FFF, 0x1E800...0x1EDFF, 0x1EF00...0x1EFFF:
            return 2    // R
        case 0x0600...0x07BF, 0x0860...0x08FF, 0xFB50...0xFDFF, 0xFE70...0xFEFF, 0x1EE00...0x1EEFF:
            return 12    // AL
        default: break
        }
        switch properties.generalCategory {
        case .uppercaseLetter, .lowercaseLetter, .titlecaseLetter, .modifierLetter, .otherLetter, .spacingMark, .letterNumber,
             .privateUse, .unassigned:
            return 1    // L
        default:
            return 11    // ON
        }
    }
}

extension NSObject {
    @ObjCMethod("description") func describedByObject() -> String
}

// Multiprocessing Services' locks, over pthreads.
private typealias MPLock = UnsafeMutablePointer<pthread_mutex_t>

@c(_MPCreateCriticalRegion)
public func MPCreateCriticalRegion(_ region: UnsafeMutablePointer<UnsafeMutableRawPointer?>?) -> Int32 {
    let lock = MPLock.allocate(capacity: 1)
    var attributes = pthread_mutexattr_t()
    pthread_mutexattr_init(&attributes)
    pthread_mutexattr_settype(&attributes, Int32(PTHREAD_MUTEX_RECURSIVE))
    pthread_mutex_init(lock, &attributes)
    pthread_mutexattr_destroy(&attributes)
    region?.pointee = UnsafeMutableRawPointer(lock)
    return 0
}

@c(_MPDeleteCriticalRegion)
public func MPDeleteCriticalRegion(_ region: UnsafeMutableRawPointer?) -> Int32 {
    guard let region else { return 0 }
    let lock = region.assumingMemoryBound(to: pthread_mutex_t.self)
    pthread_mutex_destroy(lock)
    lock.deallocate()
    return 0
}

@c(_MPEnterCriticalRegion)
public func MPEnterCriticalRegion(_ region: UnsafeMutableRawPointer?, _ timeout: Int32) -> Int32 {
    guard let region else { return -50 }
    return pthread_mutex_lock(region.assumingMemoryBound(to: pthread_mutex_t.self)) == 0 ? 0 : -50
}

@c(_MPExitCriticalRegion)
public func MPExitCriticalRegion(_ region: UnsafeMutableRawPointer?) -> Int32 {
    guard let region else { return -50 }
    return pthread_mutex_unlock(region.assumingMemoryBound(to: pthread_mutex_t.self)) == 0 ? 0 : -50
}

@c(_MPCreateSemaphore)
public func MPCreateSemaphore(_ maximum: UInt32, _ initial: UInt32,
                              _ semaphore: UnsafeMutablePointer<UnsafeMutableRawPointer?>?) -> Int32 {
    let storage = UnsafeMutablePointer<sem_t>.allocate(capacity: 1)
    sem_init(storage, 0, initial)
    semaphore?.pointee = UnsafeMutableRawPointer(storage)
    return 0
}

@c(_MPDeleteSemaphore)
public func MPDeleteSemaphore(_ semaphore: UnsafeMutableRawPointer?) -> Int32 {
    guard let semaphore else { return 0 }
    let storage = semaphore.assumingMemoryBound(to: sem_t.self)
    sem_destroy(storage)
    storage.deallocate()
    return 0
}

@c(_MPSignalSemaphore)
public func MPSignalSemaphore(_ semaphore: UnsafeMutableRawPointer?) -> Int32 {
    guard let semaphore else { return -50 }
    return sem_post(semaphore.assumingMemoryBound(to: sem_t.self)) == 0 ? 0 : -50
}

/// The timeout is in milliseconds, with -1 for forever and 0 for not waiting.
@c(_MPWaitOnSemaphore)
public func MPWaitOnSemaphore(_ semaphore: UnsafeMutableRawPointer?, _ timeout: Int32) -> Int32 {
    guard let semaphore else { return -50 }
    let storage = semaphore.assumingMemoryBound(to: sem_t.self)
    if timeout == 0 { return sem_trywait(storage) == 0 ? 0 : -29296 }
    if timeout < 0 {
        while sem_wait(storage) != 0 { if errno != EINTR { return -50 } }
        return 0
    }
    var deadline = timespec()
    clock_gettime(CLOCK_REALTIME, &deadline)
    deadline.tv_sec += Int(timeout / 1000)
    deadline.tv_nsec += Int(timeout % 1000) * 1_000_000
    if deadline.tv_nsec >= 1_000_000_000 {
        deadline.tv_sec += 1
        deadline.tv_nsec -= 1_000_000_000
    }
    while sem_timedwait(storage, &deadline) != 0 {
        if errno != EINTR { return -29296 }
    }
    return 0
}

// The Component Manager, as programs from before AudioComponent find their
// audio units: the same descriptions and instances, under older names.
private let audioToolbox = "/System/Library/Frameworks/AudioToolbox.framework/AudioToolbox"

private func audioFunction<T>(_ name: String, as type: T.Type) -> T? {
    guard let lookup = providerSymbolLookup,
          let symbol = audioToolbox.withCString({ library in name.withCString { lookup(library, $0) } }) else { return nil }
    return unsafeBitCast(symbol, to: type)
}

@c(_FindNextComponent)
public func FindNextComponent(_ component: UnsafeMutableRawPointer?, _ description: UnsafeRawPointer?) -> UnsafeMutableRawPointer? {
    typealias F = @convention(c) (UnsafeMutableRawPointer?, UnsafeRawPointer?) -> UnsafeMutableRawPointer?
    return audioFunction("_AudioComponentFindNext", as: F.self)?(component, description)
}

@c(_OpenAComponent)
public func OpenAComponent(_ component: UnsafeMutableRawPointer?, _ instance: UnsafeMutablePointer<UnsafeMutableRawPointer?>?) -> Int32 {
    typealias F = @convention(c) (UnsafeMutableRawPointer?, UnsafeMutablePointer<UnsafeMutableRawPointer?>?) -> Int32
    return audioFunction("_AudioComponentInstanceNew", as: F.self)?(component, instance) ?? -192
}

@c(_OpenComponent)
public func OpenComponent(_ component: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer? {
    var instance: UnsafeMutableRawPointer?
    return OpenAComponent(component, &instance) == 0 ? instance : nil
}

@c(_CloseComponent)
public func CloseComponent(_ instance: UnsafeMutableRawPointer?) -> Int32 {
    typealias F = @convention(c) (UnsafeMutableRawPointer?) -> Int32
    return audioFunction("_AudioComponentInstanceDispose", as: F.self)?(instance) ?? -192
}

/// A component's version, given the component or an instance of it.
@c(_GetComponentVersion)
public func GetComponentVersion(_ component: UnsafeMutableRawPointer?) -> Int32 {
    typealias Component = @convention(c) (UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer?
    typealias Version = @convention(c) (UnsafeMutableRawPointer?, UnsafeMutablePointer<UInt32>?) -> Int32
    guard let version = audioFunction("_AudioComponentGetVersion", as: Version.self) else { return 0 }
    var result: UInt32 = 0
    if version(component, &result) == 0 { return Int32(bitPattern: result) }
    let owner = audioFunction("_AudioComponentInstanceGetComponent", as: Component.self)?(component)
    return version(owner, &result) == 0 ? Int32(bitPattern: result) : 0
}

@c(_CallComponentVersion)
public func CallComponentVersion(_ instance: UnsafeMutableRawPointer?) -> Int32 { 0x0001_0000 }

#endif
