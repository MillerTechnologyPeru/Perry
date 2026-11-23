import Glibc

#if arch(powerpc)
/// Calls to Darwin methods and blocks by type encoding, with each argument
/// as its bytes in memory, for NSInvocation and key-value coding. Every IMP
/// on ppc is Darwin code, or a provider's Darwin entry, so the loader lays
/// the arguments out as Darwin's ABI has them (perry_ppc_call_darwin_values):
/// doubles and floats in f1-f13 as well as their words, long longs in two
/// words, structures in their words.
enum DarwinCalls {
    private typealias Values = @convention(c) (UnsafeRawPointer, UnsafePointer<CChar>, UnsafePointer<UnsafeRawPointer?>,
                                               UnsafeMutableRawPointer?, UnsafeMutableRawPointer) -> Void

    // The loader's, which perry exports: RTLD_DEFAULT finds it.
    nonisolated(unsafe) private static let values: Values? =
        dlsym(nil, "perry_ppc_call_darwin_values").map { unsafeBitCast($0, to: Values.self) }

    /// Calls `function` with `arguments`, the bytes of each, by `types`: the
    /// result's, then each argument's. The result's bytes go to `result`,
    /// which has room for them.
    static func call(_ function: UnsafeRawPointer, types: [String], arguments: [[UInt8]], result: UnsafeMutableRawPointer?) {
        guard let values else { foundationFatal("perry_ppc_call_darwin_values is missing from the loader") }
        // A block's own type, @?, is one word.
        let encoding = types.map { $0.hasPrefix("@?") ? "@" : $0 }.joined()
        // Each argument's bytes, 8-aligned, in one buffer the call reads.
        let offsets = arguments.reduce(into: [0]) { $0.append($0.last! + (max($1.count, 1) + 7) & ~7) }
        let buffer = UnsafeMutableRawPointer.allocate(byteCount: max(offsets.last!, 8), alignment: 8)
        defer { buffer.deallocate() }
        buffer.initializeMemory(as: UInt8.self, repeating: 0, count: max(offsets.last!, 8))
        for (index, bytes) in arguments.enumerated() {
            bytes.withUnsafeBytes { if let base = $0.baseAddress { (buffer + offsets[index]).copyMemory(from: base, byteCount: $0.count) } }
        }
        let pointers = arguments.indices.map { UnsafeRawPointer(buffer + offsets[$0]) as UnsafeRawPointer? }
        let returnType = types.first ?? "v"
        let structure = returnType.hasPrefix("{") || returnType.hasPrefix("(")
        // r3, r4, then f1: the result registers, the same in both ABIs.
        var registers = (UInt32(0), UInt32(0), 0.0)
        withUnsafeMutableBytes(of: &registers) { registers in
            pointers.withUnsafeBufferPointer { pointers in
                encoding.withCString { values(function, $0, pointers.baseAddress!, structure ? result : nil, registers.baseAddress!) }
            }
        }
        guard let result, !structure, let size = TypeEncoding.size(of: returnType), size > 0 else { return }
        switch returnType.first {
        case "d":
            withUnsafeBytes(of: registers.2) { result.copyMemory(from: $0.baseAddress!, byteCount: 8) }
        case "f":
            withUnsafeBytes(of: Float(registers.2)) { result.copyMemory(from: $0.baseAddress!, byteCount: 4) }
        default:
            // r3, or r3:r4 for 8 bytes; a smaller value is the word's last
            // bytes, big-endian.
            withUnsafeBytes(of: (registers.0, registers.1)) { words in
                let start = size >= 4 ? 0 : 4 - size
                result.copyMemory(from: words.baseAddress! + start, byteCount: min(size, 8))
            }
        }
    }
}
#endif
