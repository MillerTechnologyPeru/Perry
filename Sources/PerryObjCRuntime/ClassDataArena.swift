import Glibc
import Synchronization

/// Memory for the class data objc_class.bits points at (class_rw_t, and the
/// class_ro_t of classes the runtime makes), below 2^39 as iOS's addresses
/// are. Code that reads Darwin's structures masks objc_class.bits with
/// iOS's FAST_DATA_MASK for a 39-bit address space (0x7ffffffff8: Pangle's
/// method lookup does), which cuts a pointer into Linux's heap, far above.
/// The data lives as long as its class, so it is never freed.
enum ClassDataArena {
    // 64-bit only: a 32-bit process's heap is below the limit already, and
    // its UInt cannot hold these addresses.
#if _pointerBitWidth(_64)
    /// The highest address the data may end at.
    private static let limit: UInt = 1 << 39
    /// Where to ask for space: above where images are mapped (4 GB up), and
    /// well below the limit.
    private static let firstHint: UInt = 0x40_0000_0000
    private static let chunkSize = 1 << 20

    private struct Chunk {
        var next: UInt = 0
        var end: UInt = 0
        var hint: UInt = ClassDataArena.firstHint
        var unavailable = false
    }

    private static let chunk = Mutex(Chunk())
#endif

    /// `size` bytes aligned to 8, zeroed; from the heap when no space is to
    /// be had below the limit (32-bit processes, whose heap is below it).
    static func allocate(byteCount size: Int) -> UnsafeMutableRawPointer {
#if _pointerBitWidth(_64)
        let bytes = UInt((size + 7) & ~7)
        let address: UInt? = chunk.withLock { chunk in
            if chunk.next + bytes > chunk.end {
                guard !chunk.unavailable, let fresh = mapChunk(&chunk) else { return nil }
                chunk.next = fresh
                chunk.end = fresh + UInt(chunkSize)
            }
            defer { chunk.next += bytes }
            return chunk.next
        }
        if let address, let pointer = UnsafeMutableRawPointer(bitPattern: address) { return pointer }
#endif
        let pointer = UnsafeMutableRawPointer.allocate(byteCount: size, alignment: 8)
        pointer.initializeMemory(as: UInt8.self, repeating: 0, count: size)
        return pointer
    }

#if _pointerBitWidth(_64)
    /// A fresh chunk below the limit, asked for at the hint and a gigabyte
    /// on each time it is taken; nil when there is none.
    private static func mapChunk(_ chunk: inout Chunk) -> UInt? {
        while chunk.hint + UInt(chunkSize) <= limit {
            let hint = chunk.hint
            let mapped = mmap(UnsafeMutableRawPointer(bitPattern: hint), chunkSize, PROT_READ | PROT_WRITE,
                              MAP_PRIVATE | MAP_ANONYMOUS, -1, 0)
            guard let mapped, mapped != MAP_FAILED else { break }
            let address = UInt(bitPattern: mapped)
            if address + UInt(chunkSize) <= limit {
                chunk.hint = address + UInt(chunkSize)
                return address
            }
            // Placed elsewhere: the hint was taken; try a gigabyte on.
            munmap(mapped, chunkSize)
            chunk.hint = hint + (1 << 30)
        }
        chunk.unavailable = true
        return nil
    }
#endif
}
