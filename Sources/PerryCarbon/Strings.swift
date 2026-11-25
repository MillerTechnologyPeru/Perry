import GraphiteBase

// Pascal strings: Str255s, a length byte and up to 255 MacRoman bytes,
// through Graphite's PascalString.

/// void c2pstrcpy(Str255 dst, const char *src): the C string's first 255
/// bytes after a length byte. The two may be the same buffer.
@c(_c2pstrcpy)
public func c2pstrcpy(_ pascal: UnsafeMutableRawPointer?, _ c: UnsafePointer<CChar>?) {
    guard let pascal, let c else { return }
    var bytes: [UInt8] = []
    var index = 0
    while bytes.count < PascalString.maximumLength, c[index] != 0 {
        bytes.append(UInt8(bitPattern: c[index]))
        index += 1
    }
    store(PascalString(bytes: bytes), at: pascal)
}

/// void p2cstrcpy(char *dst, ConstStr255Param src). The two may be the same
/// buffer.
@c(_p2cstrcpy)
public func p2cstrcpy(_ c: UnsafeMutableRawPointer?, _ pascal: UnsafeRawPointer?) {
    guard let c, let pascal else { return }
    let bytes = pascalString(at: pascal).cString
    bytes.withUnsafeBytes { c.copyMemory(from: $0.baseAddress!, byteCount: $0.count) }
}

/// short IdenticalString(ConstStr255Param, ConstStr255Param, Handle table):
/// 0 when the two are the same but for case, as a Roman script compares.
@c(_IdenticalString)
public func IdenticalString(_ a: UnsafeRawPointer?, _ b: UnsafeRawPointer?, _ table: UnsafeMutableRawPointer?) -> Int16 {
    guard let a, let b else { return 1 }
    return pascalString(at: a).isEqualIgnoringCase(pascalString(at: b)) ? 0 : 1
}

/// void NumToString(long, Str255).
@c(_NumToString)
public func NumToString(_ number: Int, _ text: UnsafeMutableRawPointer?) {
    guard let text else { return }
    store(PascalString(number), at: text)
}

/// void StringToNum(ConstStr255Param, long *): the number the text starts
/// with.
@c(_StringToNum)
public func StringToNum(_ text: UnsafeRawPointer?, _ number: UnsafeMutablePointer<Int>?) {
    guard let number else { return }
    number.pointee = text.map { Int(pascalString(at: $0).integerValue) } ?? 0
}
