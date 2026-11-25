import GraphiteBase

// Carbon's C types are the names in this target: a Point or Rect in an
// export's signature is QuickDraw's C structure, as Darwin lays it out
// (@DarwinC passes them by value as Darwin's ppc words), and Graphite's are
// spelled GraphiteBase.Point and GraphiteBase.Rect.

public typealias Point = CPerryCarbon.Point
public typealias Rect = CPerryCarbon.Rect

extension MacError {

    /// The error as the OSStatus an export returns.
    var status: Int32 { code }

    /// The error as the OSErr an export returns.
    var osErr: Int16 { Int16(truncatingIfNeeded: code) }
}

/// The OSStatus of a throwing call: noErr, or the code it threw.
func status(_ body: () throws(MacError) -> Void) -> Int32 {
    do {
        try body()
        return 0
    } catch {
        return error.status
    }
}

/// A Pascal string at a Str255's address: its length byte and bytes.
func pascalString(at storage: UnsafeRawPointer) -> PascalString {
    let length = Int(storage.load(as: UInt8.self))
    return PascalString(bytes: UnsafeRawBufferPointer(start: storage + 1, count: length))
}

/// Writes a Pascal string as a Str255 holds it.
func store(_ string: PascalString, at storage: UnsafeMutableRawPointer) {
    let bytes = string.lengthPrefixed
    bytes.withUnsafeBytes { storage.copyMemory(from: $0.baseAddress!, byteCount: $0.count) }
}
