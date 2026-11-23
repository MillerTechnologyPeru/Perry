import Foundation

// AudioBuffer, AudioBufferList and AudioChannelLayout as Swift collections:
// buffers as buffer pointers, a buffer list's and a channel layout's
// variable-length arrays through pointers to them, and a channel layout
// that owns its memory.

extension UnsafeBufferPointer {
    /// The buffer's bytes as elements of this type.
    public init(_ audioBuffer: AudioBuffer) {
        self.init(start: audioBuffer.mData?.assumingMemoryBound(to: Element.self),
                  count: Int(audioBuffer.mDataByteSize) / MemoryLayout<Element>.stride)
    }
}

extension UnsafeMutableBufferPointer {
    public init(_ audioBuffer: AudioBuffer) {
        self.init(start: audioBuffer.mData?.assumingMemoryBound(to: Element.self),
                  count: Int(audioBuffer.mDataByteSize) / MemoryLayout<Element>.stride)
    }
}

extension AudioBuffer {
    public init<Element>(_ typedBuffer: UnsafeMutableBufferPointer<Element>, numberOfChannels: Int) {
        self.init(mNumberChannels: UInt32(numberOfChannels),
                  mDataByteSize: UInt32(typedBuffer.count * MemoryLayout<Element>.stride),
                  mData: UnsafeMutableRawPointer(typedBuffer.baseAddress))
    }
}

/// Where the buffers of an AudioBufferList start: after its count, aligned
/// for an AudioBuffer.
private let buffersOffset = MemoryLayout<AudioBufferList>.size - MemoryLayout<AudioBuffer>.stride

extension AudioBufferList {
    public static func sizeInBytes(maximumBuffers: Int) -> Int {
        precondition(maximumBuffers >= 1, "AudioBufferList should contain at least one AudioBuffer")
        return buffersOffset + maximumBuffers * MemoryLayout<AudioBuffer>.stride
    }

    /// A zeroed buffer list of this many buffers, which the caller frees
    /// (free(_:) of its unsafeMutablePointer).
    public static func allocate(maximumBuffers: Int) -> UnsafeMutableAudioBufferListPointer {
        let memory = calloc(sizeInBytes(maximumBuffers: maximumBuffers), 1)!
        let list = memory.bindMemory(to: AudioBufferList.self, capacity: 1)
        list.pointee.mNumberBuffers = UInt32(maximumBuffers)
        return UnsafeMutableAudioBufferListPointer(list)
    }
}

public struct UnsafeMutableAudioBufferListPointer {
    public init(_ p: UnsafeMutablePointer<AudioBufferList>) {
        unsafeMutablePointer = p
    }

    public init?(_ p: UnsafeMutablePointer<AudioBufferList>?) {
        guard let p else { return nil }
        self.init(p)
    }

    public var count: Int {
        get { Int(unsafeMutablePointer.pointee.mNumberBuffers) }
        nonmutating set(newValue) { unsafeMutablePointer.pointee.mNumberBuffers = UInt32(newValue) }
    }

    public var unsafePointer: UnsafePointer<AudioBufferList> {
        UnsafePointer(unsafeMutablePointer)
    }

    public var unsafeMutablePointer: UnsafeMutablePointer<AudioBufferList>

    /// The list's buffers, past its count.
    fileprivate var buffers: UnsafeMutablePointer<AudioBuffer> {
        (UnsafeMutableRawPointer(unsafeMutablePointer) + buffersOffset).assumingMemoryBound(to: AudioBuffer.self)
    }
}

extension UnsafeMutableAudioBufferListPointer: MutableCollection, RandomAccessCollection {
    public typealias Element = AudioBuffer
    public typealias Index = Int
    public typealias Indices = Range<Int>

    public var startIndex: Int { 0 }
    public var endIndex: Int { count }

    public subscript(index: UnsafeMutableAudioBufferListPointer.Index) -> UnsafeMutableAudioBufferListPointer.Element {
        _read {
            precondition(index >= 0 && index < count, "subscript index out of range")
            yield buffers[index]
        }
        nonmutating _modify {
            precondition(index >= 0 && index < count, "subscript index out of range")
            yield &buffers[index]
        }
    }

    public typealias Iterator = IndexingIterator<UnsafeMutableAudioBufferListPointer>
    public typealias SubSequence = Slice<UnsafeMutableAudioBufferListPointer>
}

/// Where the descriptions of an AudioChannelLayout start: after its tag,
/// bitmap and count.
private let descriptionsOffset = MemoryLayout<AudioChannelLayout>.size - MemoryLayout<AudioChannelDescription>.stride

/// The bytes of a channel layout of this many descriptions.
private func layoutSize(_ descriptions: Int) -> Int {
    descriptionsOffset + max(descriptions, 1) * MemoryLayout<AudioChannelDescription>.stride
}

private func descriptions(of layout: UnsafeMutablePointer<AudioChannelLayout>) -> UnsafeMutablePointer<AudioChannelDescription> {
    (UnsafeMutableRawPointer(layout) + descriptionsOffset).assumingMemoryBound(to: AudioChannelDescription.self)
}

extension AudioChannelLayout {
    public static func sizeInBytes(maximumDescriptions: Int) -> Int {
        layoutSize(maximumDescriptions)
    }

    /// A zeroed layout of this many descriptions, which the caller frees.
    public static func allocate(maximumDescriptions: Int) -> AudioChannelLayout.UnsafeMutablePointer {
        let memory = calloc(sizeInBytes(maximumDescriptions: maximumDescriptions), 1)!
        let layout = memory.bindMemory(to: AudioChannelLayout.self, capacity: 1)
        layout.pointee.mNumberChannelDescriptions = UInt32(maximumDescriptions)
        return AudioChannelLayout.UnsafeMutablePointer(layout)
    }
}

extension AudioChannelLayout {
    public struct UnsafeMutablePointer {
        public init(_ p: Swift.UnsafeMutablePointer<AudioChannelLayout>) {
            unsafeMutablePointer = p
        }

        public init?(_ p: Swift.UnsafeMutablePointer<AudioChannelLayout>?) {
            guard let p else { return nil }
            self.init(p)
        }

        public var count: Int {
            get { Int(unsafeMutablePointer.pointee.mNumberChannelDescriptions) }
            nonmutating set(newValue) { unsafeMutablePointer.pointee.mNumberChannelDescriptions = UInt32(newValue) }
        }

        public var unsafePointer: Swift.UnsafePointer<AudioChannelLayout> {
            Swift.UnsafePointer(unsafeMutablePointer)
        }

        public var unsafeMutablePointer: Swift.UnsafeMutablePointer<AudioChannelLayout>
    }
}

extension AudioChannelLayout.UnsafeMutablePointer: MutableCollection, RandomAccessCollection {
    public typealias Element = AudioChannelDescription
    public typealias Index = Int
    public typealias Indices = Range<Int>

    public var startIndex: Int { 0 }
    public var endIndex: Int { count }

    public subscript(index: AudioChannelLayout.UnsafeMutablePointer.Index) -> AudioChannelLayout.UnsafeMutablePointer.Element {
        _read {
            precondition(index >= 0 && index < count, "subscript index out of range")
            yield descriptions(of: unsafeMutablePointer)[index]
        }
        nonmutating _modify {
            precondition(index >= 0 && index < count, "subscript index out of range")
            yield &descriptions(of: unsafeMutablePointer)[index]
        }
    }

    public typealias Iterator = IndexingIterator<AudioChannelLayout.UnsafeMutablePointer>
    public typealias SubSequence = Slice<AudioChannelLayout.UnsafeMutablePointer>
}

extension AudioChannelLayout {
    public struct UnsafePointer {
        public init(_ p: Swift.UnsafePointer<AudioChannelLayout>) {
            unsafePointer = p
        }

        public init?(_ p: Swift.UnsafePointer<AudioChannelLayout>?) {
            guard let p else { return nil }
            self.init(p)
        }

        public var count: Int {
            Int(unsafePointer.pointee.mNumberChannelDescriptions)
        }

        public var unsafePointer: Swift.UnsafePointer<AudioChannelLayout>
    }
}

extension AudioChannelLayout.UnsafePointer: Collection, RandomAccessCollection {
    public typealias Element = AudioChannelDescription
    public typealias Index = Int
    public typealias Indices = Range<Int>

    public var startIndex: Int { 0 }
    public var endIndex: Int { count }

    public subscript(index: AudioChannelLayout.UnsafePointer.Index) -> AudioChannelLayout.UnsafePointer.Element {
        _read {
            precondition(index >= 0 && index < count, "subscript index out of range")
            yield descriptions(of: Swift.UnsafeMutablePointer(mutating: unsafePointer))[index]
        }
    }

    public typealias Iterator = IndexingIterator<AudioChannelLayout.UnsafePointer>
    public typealias SubSequence = Slice<AudioChannelLayout.UnsafePointer>
}

/// A channel layout's memory and what frees it, shared by copies of a
/// ManagedAudioChannelLayout until one of them changes.
private final class LayoutStorage {
    let layout: Swift.UnsafeMutablePointer<AudioChannelLayout>
    private let deallocator: (AudioChannelLayout.UnsafePointer) -> Void

    init(_ layout: Swift.UnsafeMutablePointer<AudioChannelLayout>, deallocator: @escaping (AudioChannelLayout.UnsafePointer) -> Void) {
        self.layout = layout
        self.deallocator = deallocator
    }

    /// A zeroed layout of this many descriptions, freed with free().
    convenience init(descriptions count: Int) {
        let memory = calloc(layoutSize(count), 1)!.bindMemory(to: AudioChannelLayout.self, capacity: 1)
        memory.pointee.mNumberChannelDescriptions = UInt32(count)
        self.init(memory) { free(Swift.UnsafeMutablePointer(mutating: $0.unsafePointer)) }
    }

    var count: Int { Int(layout.pointee.mNumberChannelDescriptions) }
    var size: Int { layoutSize(count) }

    func copy() -> LayoutStorage {
        let copy = LayoutStorage(descriptions: count)
        memcpy(copy.layout, layout, size)
        return copy
    }

    deinit {
        deallocator(AudioChannelLayout.UnsafePointer(Swift.UnsafePointer(layout)))
    }

    /// The storage a layout holds while its descriptions are yielded.
    static let placeholder = LayoutStorage(descriptions: 0)
}

public struct ManagedAudioChannelLayout {
    fileprivate var storage: LayoutStorage

    /// Takes over a layout; `deallocator` frees it when no copy uses it.
    public init(audioChannelLayoutPointer: AudioChannelLayout.UnsafePointer, deallocator: @escaping (AudioChannelLayout.UnsafePointer) -> Void) {
        storage = LayoutStorage(Swift.UnsafeMutablePointer(mutating: audioChannelLayoutPointer.unsafePointer), deallocator: deallocator)
    }

    public init(tag: AudioChannelLayoutTag) {
        storage = LayoutStorage(descriptions: 0)
        storage.layout.pointee.mChannelLayoutTag = tag
    }

    public init(maximumDescriptions: Int) {
        storage = LayoutStorage(descriptions: maximumDescriptions)
        storage.layout.pointee.mChannelLayoutTag = kAudioChannelLayoutTag_UseChannelDescriptions
    }

    public init(channelDescriptions: [AudioChannelDescription]) {
        self.init(maximumDescriptions: channelDescriptions.count)
        let target = descriptions(of: storage.layout)
        for (index, description) in channelDescriptions.enumerated() {
            target[index] = description
        }
    }

    private mutating func makeUnique() {
        if !isKnownUniquelyReferenced(&storage) {
            storage = storage.copy()
        }
    }

    public var tag: AudioChannelLayoutTag {
        get { storage.layout.pointee.mChannelLayoutTag }
        set(newValue) {
            makeUnique()
            storage.layout.pointee.mChannelLayoutTag = newValue
        }
    }

    public var bitmap: AudioChannelBitmap {
        get { storage.layout.pointee.mChannelBitmap }
        set(newValue) {
            makeUnique()
            storage.layout.pointee.mChannelBitmap = newValue
        }
    }

    /// Every channel's description unknown: the layout described channel
    /// by channel, each of them with no label, flags or coordinates.
    public mutating func setAllToUnknown() {
        makeUnique()
        storage.layout.pointee.mChannelLayoutTag = kAudioChannelLayoutTag_UseChannelDescriptions
        storage.layout.pointee.mChannelBitmap = []
        let target = descriptions(of: storage.layout)
        for index in 0..<storage.count {
            target[index] = AudioChannelDescription(mChannelLabel: kAudioChannelLabel_Unknown, mChannelFlags: [], mCoordinates: (0, 0, 0))
        }
    }

    public var channelDescriptions: ManagedAudioChannelLayout.ChannelDescriptions {
        _read {
            yield ChannelDescriptions(storage: storage)
        }
        _modify {
            makeUnique()
            var descriptions = ChannelDescriptions(storage: storage)
            storage = LayoutStorage.placeholder
            defer { storage = descriptions.storage }
            yield &descriptions
        }
    }

    public var sizeInBytes: Int { storage.size }

    /// The channels the layout has: those its tag implies, its bitmap's,
    /// or its descriptions'.
    public var numberOfChannels: Int {
        let layout = storage.layout.pointee
        switch layout.mChannelLayoutTag {
        case kAudioChannelLayoutTag_UseChannelDescriptions:
            return Int(layout.mNumberChannelDescriptions)
        case kAudioChannelLayoutTag_UseChannelBitmap:
            return layout.mChannelBitmap.rawValue.nonzeroBitCount
        default:
            return Int(layout.mChannelLayoutTag & 0xFFFF)
        }
    }

    public func withUnsafePointer<Result>(_ body: (Swift.UnsafePointer<AudioChannelLayout>) throws -> Result) rethrows -> Result {
        try withExtendedLifetime(storage) { try body(Swift.UnsafePointer(storage.layout)) }
    }

    public mutating func withUnsafeMutablePointer<Result>(_ body: (Swift.UnsafeMutablePointer<AudioChannelLayout>) throws -> Result) rethrows -> Result {
        makeUnique()
        return try withExtendedLifetime(storage) { try body(storage.layout) }
    }

    public struct ChannelDescriptions: MutableCollection, RandomAccessCollection {
        public typealias Element = AudioChannelDescription
        public typealias Index = Int
        public typealias Indices = Range<Int>

        fileprivate var storage: LayoutStorage

        public var startIndex: Int { 0 }
        public var endIndex: Int { storage.count }
        public var count: Int { storage.count }

        public subscript(index: ManagedAudioChannelLayout.ChannelDescriptions.Index) -> ManagedAudioChannelLayout.ChannelDescriptions.Element {
            _read {
                precondition(index >= 0 && index < count, "subscript index out of range")
                yield descriptions(of: storage.layout)[index]
            }
            _modify {
                precondition(index >= 0 && index < count, "subscript index out of range")
                if !isKnownUniquelyReferenced(&storage) {
                    storage = storage.copy()
                }
                yield &descriptions(of: storage.layout)[index]
            }
        }

        public typealias Iterator = IndexingIterator<ManagedAudioChannelLayout.ChannelDescriptions>
        public typealias SubSequence = Slice<ManagedAudioChannelLayout.ChannelDescriptions>
    }
}

extension AudioChannelDescription {
    public static func == (lhs: AudioChannelDescription, rhs: AudioChannelDescription) -> Bool {
        lhs.mChannelLabel == rhs.mChannelLabel && lhs.mChannelFlags == rhs.mChannelFlags
            && lhs.mCoordinates.0 == rhs.mCoordinates.0 && lhs.mCoordinates.1 == rhs.mCoordinates.1
            && lhs.mCoordinates.2 == rhs.mCoordinates.2
    }
}

extension ManagedAudioChannelLayout.ChannelDescriptions: Equatable {
    public static func == (lhs: ManagedAudioChannelLayout.ChannelDescriptions, rhs: ManagedAudioChannelLayout.ChannelDescriptions) -> Bool {
        lhs.elementsEqual(rhs, by: ==)
    }
}

extension ManagedAudioChannelLayout: Equatable {
    public static func == (lhs: ManagedAudioChannelLayout, rhs: ManagedAudioChannelLayout) -> Bool {
        lhs.tag == rhs.tag && lhs.bitmap == rhs.bitmap && lhs.channelDescriptions == rhs.channelDescriptions
    }
}
