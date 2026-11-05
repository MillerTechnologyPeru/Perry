/// Offsets into structures Darwin programs and their compiler lay out,
/// which Foundation reads: literals, callbacks and contexts, blocks and the
/// fast enumeration state. Their fields are words, so each offset is a
/// count of words: 8 bytes on arm64, 4 on armv7.
enum DarwinLayout {
    static let word = MemoryLayout<UInt>.size

    /// String literals (CFConstantString): isa, flags, characters, length.
    static let stringFlags = word
    static let stringCharacters = 2 * word
    static let stringLength = 3 * word

    /// Array literals (NSConstantArray): isa, count, objects.
    static let arrayCount = word
    static let arrayObjects = 2 * word

    /// Dictionary literals (NSConstantDictionary): isa, options, count, keys,
    /// objects.
    static let dictionaryCount = 2 * word
    static let dictionaryKeys = 3 * word
    static let dictionaryObjects = 4 * word

    /// Number literals: isa, then the encoding and the value
    /// (NSConstantIntegerNumber), or the value (NSConstantDoubleNumber and
    /// NSConstantFloatNumber). A 64-bit value is only 4-byte aligned on armv7.
    static let numberEncoding = word
    static let integerNumberValue = 2 * word
    static let floatingNumberValue = word

    /// A block: isa, then 32-bit flags and reserved, then invoke.
    static let blockInvoke = word + 8

    /// protocol_t: isa, then the name.
    static let protocolName = word

    /// NSFastEnumerationState: state, itemsPtr, mutationsPtr, extra.
    static let enumerationItems = word
    static let enumerationMutations = 2 * word

    /// CFArrayCallBacks, CFSetCallBacks and CFDictionaryKeyCallBacks:
    /// version, retain, release, copyDescription, equal, then hash.
    static let callbackRetain = word
    static let callbackRelease = 2 * word
    static let callbackEqual = 4 * word
    static let callbackHash = 5 * word

    /// Contexts such as CFRunLoopObserverContext: version, info, retain,
    /// release, copyDescription.
    static let contextInfo = word
    static let contextRetain = 2 * word
    static let contextRelease = 3 * word

    /// mach_header's size, before the load commands: 28 bytes, or 32 for
    /// mach_header_64.
    static func machHeaderSize(_ header: UnsafeRawPointer) -> Int {
        header.load(as: UInt32.self) == 0xfeed_facf ? 32 : 28
    }
}
