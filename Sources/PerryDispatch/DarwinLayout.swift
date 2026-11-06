/// Offsets into the Darwin structures libdispatch's provider reads and
/// writes: its objects (an isa, then the Linux object and a word of state),
/// blocks (isa, 32-bit flags and reserved, invoke, descriptor, then the
/// captured values), block descriptors (reserved, size, copy, dispose) and
/// Swift's dispatch class metadata. Their fields are words, 8 bytes on arm64
/// and 4 on armv7.
enum DarwinLayout {
    static let word = MemoryLayout<UInt>.size

    static let objectLinux = word
    static let objectState = 2 * word

    static let blockFlags = word
    static let blockReserved = word + 4
    static let blockInvoke = word + 8
    static let blockDescriptor = 2 * word + 8
    static let blockCaptures = 3 * word + 8

    static let descriptorSize = word
    static let descriptorCopy = 2 * word
    static let descriptorDispose = 3 * word
    static let descriptorBytes = 4 * word

    /// DispatchClassMetadata's invoke function.
    static let metadataInvoke = 6 * word
}
