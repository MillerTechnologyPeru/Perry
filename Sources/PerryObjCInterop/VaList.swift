/// `withVaList`, with a va_list C's v* functions read right on 32-bit
/// PowerPC Linux, where the standard library's is not: there a va_list is a
/// structure (the counts of general and floating-point registers used, then
/// pointers to the overflow and register save areas), and the standard
/// library hands C the arguments' words instead. This builds the structure
/// with both counts used up, so every argument comes from the overflow area,
/// laid out with 8-byte values aligned to 8 as that area takes them.
/// Elsewhere it is withVaList.
#if arch(powerpc) && os(Linux)
public func perryWithVaList<R>(_ arguments: [CVarArg], _ body: (CVaListPointer) -> R) -> R {
    var words: [Int] = []
    for argument in arguments {
        let encoding = argument._cVarArgEncoding
        if encoding.count == 2, words.count % 2 == 1 {
            words.append(0)
        }
        words += encoding
    }
    let storage = UnsafeMutableRawPointer.allocate(byteCount: max(words.count, 2) * 4, alignment: 8)
    defer { storage.deallocate() }
    words.withUnsafeBytes { storage.copyMemory(from: $0.baseAddress!, byteCount: $0.count) }
    let header = UnsafeMutablePointer<Int>.allocate(capacity: 3)
    defer { header.deallocate() }
    header[0] = 0x0808_0000
    header[1] = Int(bitPattern: storage)
    header[2] = 0
    return body(CVaListPointer(_fromUnsafeMutablePointer: UnsafeMutableRawPointer(header)))
}
#else
@inline(__always)
public func perryWithVaList<R>(_ arguments: [CVarArg], _ body: (CVaListPointer) -> R) -> R {
    withVaList(arguments, body)
}
#endif
