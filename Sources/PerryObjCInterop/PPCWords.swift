/// Helpers for @DarwinC's ppc entries (DarwinCMacro.ppcEntry), which take a
/// structure Darwin passes in general registers as its words.
public enum PPCWords {
    /// A value of `type` from its words, as it is laid out in memory.
    @inline(__always)
    public static func load<T>(_ type: T.Type, _ words: [UInt32]) -> T {
        precondition(words.count * 4 >= MemoryLayout<T>.size)
        return words.withUnsafeBytes { $0.loadUnaligned(as: T.self) }
    }

    /// A type encoding the loader keeps, for perry_ppc_types_<name>.
    public static func cString(_ string: String) -> UnsafePointer<CChar>? {
        let bytes = Array(string.utf8CString)
        let copy = UnsafeMutablePointer<CChar>.allocate(capacity: bytes.count)
        copy.initialize(from: bytes, count: bytes.count)
        return UnsafePointer(copy)
    }
}
