// A column's storage: optional elements packed in one allocation, a header
// (capacity, count, nil count), a bitmap of which elements are present
// (a set bit is a value) and the elements, uninitialized where nil. Apple's
// interface exposes this layout to inlinable code, so it is kept as given:
// each part is rounded up to Alignment.bufferAlignment.

@usableFromInline
internal struct Alignment {
    @usableFromInline
    internal static let bufferAlignment: Int = 16

    @usableFromInline
    internal static func roundToAligment(_ size: Int) -> Int {
        bufferAlignment * ((size - 1) / bufferAlignment + 1)
    }
}

@usableFromInline
internal struct PackedOptionalsBuffer<Element> {
    @usableFromInline
    internal struct Header {
        @usableFromInline
        internal var capacity: Int
        @usableFromInline
        internal var count: Int
        @usableFromInline
        internal var nilCount: Int

        @usableFromInline
        internal init(capacity: Int, count: Int = 0, nilCount: Int = 0) {
            self.capacity = capacity
            self.count = count
            self.nilCount = nilCount
        }
    }

    @usableFromInline
    internal let rawBuffer: UnsafeMutableRawBufferPointer

    @usableFromInline
    internal init(rawBuffer: UnsafeMutableRawBufferPointer) {
        self.rawBuffer = rawBuffer
    }

    @usableFromInline
    internal static var headerSize: Int {
        Alignment.roundToAligment(MemoryLayout<Header>.stride)
    }

    @usableFromInline
    internal static func nilBitmapSize(capacity: Int) -> Int {
        Alignment.roundToAligment(Swift.max((capacity + 7) / 8, 1))
    }

    @usableFromInline
    internal var nilBitmapSize: Int {
        Self.nilBitmapSize(capacity: capacity)
    }

    @usableFromInline
    internal var headerAddress: UnsafeMutablePointer<Header> {
        rawBuffer.baseAddress!.assumingMemoryBound(to: Header.self)
    }

    @usableFromInline
    internal var nilBitmapBuffer: UnsafeMutableBufferPointer<UInt8> {
        let start = (rawBuffer.baseAddress! + Self.headerSize).assumingMemoryBound(to: UInt8.self)
        return UnsafeMutableBufferPointer(start: start, count: nilBitmapSize)
    }

    @usableFromInline
    internal var firstElementAddress: UnsafeMutablePointer<Element> {
        (rawBuffer.baseAddress! + Self.headerSize + nilBitmapSize).assumingMemoryBound(to: Element.self)
    }

    @usableFromInline
    internal var elementsBuffer: UnsafeMutableBufferPointer<Element> {
        UnsafeMutableBufferPointer(start: firstElementAddress, count: capacity)
    }

    @usableFromInline
    internal var capacity: Int {
        headerAddress.pointee.capacity
    }

    @usableFromInline
    internal var count: Int {
        get { headerAddress.pointee.count }
        nonmutating set { headerAddress.pointee.count = newValue }
    }

    @usableFromInline
    internal var nilCount: Int {
        get { headerAddress.pointee.nilCount }
        nonmutating set { headerAddress.pointee.nilCount = newValue }
    }

    /// Allocates room for the header, the bitmap and capacity elements.
    private static func allocateRaw(capacity: Int) -> UnsafeMutableRawBufferPointer {
        let size = headerSize + nilBitmapSize(capacity: capacity) + MemoryLayout<Element>.stride * capacity
        return UnsafeMutableRawBufferPointer.allocate(
            byteCount: size, alignment: Swift.max(Alignment.bufferAlignment, MemoryLayout<Element>.alignment))
    }

    /// Writes a header and a bitmap of all nil (zero) bits.
    private func initializeHeader(_ header: Header) {
        rawBuffer.baseAddress!.bindMemory(to: Header.self, capacity: 1).initialize(to: header)
        let bitmapSize = Self.nilBitmapSize(capacity: header.capacity)
        (rawBuffer.baseAddress! + Self.headerSize).bindMemory(to: UInt8.self, capacity: bitmapSize)
            .initialize(repeating: 0, count: bitmapSize)
        (rawBuffer.baseAddress! + Self.headerSize + bitmapSize).bindMemory(to: Element.self, capacity: header.capacity)
    }

    @usableFromInline
    internal static func allocate(capacity: Int) -> PackedOptionalsBuffer<Element> {
        let buffer = PackedOptionalsBuffer(rawBuffer: allocateRaw(capacity: capacity))
        buffer.initializeHeader(Header(capacity: capacity))
        return buffer
    }

    @usableFromInline
    internal init(copying other: PackedOptionalsBuffer<Element>, capacity: Int) {
        precondition(capacity >= other.count)
        self.init(rawBuffer: Self.allocateRaw(capacity: capacity))
        initializeHeader(Header(capacity: capacity, count: other.count, nilCount: other.nilCount))
        let bytes = Swift.min(other.nilBitmapSize, nilBitmapSize)
        for i in 0 ..< bytes { nilBitmapBuffer[i] = other.nilBitmapBuffer[i] }
        clearBits(from: other.count)
        let source = other.firstElementAddress, destination = firstElementAddress
        for i in 0 ..< other.count where !other.isNil(at: i) {
            (destination + i).initialize(to: source[i])
        }
    }

    @usableFromInline
    internal init(moving other: PackedOptionalsBuffer<Element>, capacity: Int) {
        precondition(capacity >= other.count)
        self.init(rawBuffer: Self.allocateRaw(capacity: capacity))
        initializeHeader(Header(capacity: capacity, count: other.count, nilCount: other.nilCount))
        let bytes = Swift.min(other.nilBitmapSize, nilBitmapSize)
        for i in 0 ..< bytes { nilBitmapBuffer[i] = other.nilBitmapBuffer[i] }
        clearBits(from: other.count)
        let source = other.firstElementAddress, destination = firstElementAddress
        for i in 0 ..< other.count where !other.isNil(at: i) {
            (destination + i).moveInitialize(from: source + i, count: 1)
        }
        // The other buffer no longer owns any element.
        for i in 0 ..< other.nilBitmapSize { other.nilBitmapBuffer[i] = 0 }
        other.nilCount = other.count
    }

    /// Clears the bits of the positions from index on, which hold no element.
    private func clearBits(from index: Int) {
        var i = index
        while i < nilBitmapSize * 8 && i % 8 != 0 {
            setNil(at: i)
            i += 1
        }
        var byte = i / 8
        while byte < nilBitmapSize {
            nilBitmapBuffer[byte] = 0
            byte += 1
        }
    }

    @usableFromInline
    internal func deallocate() {
        let elements = firstElementAddress
        for i in 0 ..< count where !isNil(at: i) {
            (elements + i).deinitialize(count: 1)
        }
        rawBuffer.deallocate()
    }

    @usableFromInline
    internal func isNil(at index: Int) -> Bool {
        nilBitmapBuffer[index >> 3] & (1 << UInt8(index & 7)) == 0
    }

    @usableFromInline
    internal func setNil(at index: Int) {
        nilBitmapBuffer[index >> 3] &= ~(1 << UInt8(index & 7))
    }

    @usableFromInline
    internal func setNonNil(at index: Int) {
        nilBitmapBuffer[index >> 3] |= 1 << UInt8(index & 7)
    }

    /// Grows (adding nils) or shrinks (destroying elements) the count.
    @usableFromInline
    internal func resize(by change: Int) {
        let newCount = count + change
        precondition(newCount >= 0 && newCount <= capacity)
        if change < 0 {
            for i in newCount ..< count {
                if isNil(at: i) {
                    nilCount -= 1
                } else {
                    (firstElementAddress + i).deinitialize(count: 1)
                    setNil(at: i)
                }
            }
        } else {
            nilCount += change
        }
        count = newCount
    }

    @usableFromInline
    internal func clear(at index: Int) {
        if isNil(at: index) { return }
        (firstElementAddress + index).deinitialize(count: 1)
        setNil(at: index)
        nilCount += 1
    }

    @usableFromInline
    internal func append(_ newElement: Element?) {
        precondition(count < capacity)
        if let newElement {
            (firstElementAddress + count).initialize(to: newElement)
            setNonNil(at: count)
        } else {
            nilCount += 1
        }
        count += 1
    }

    @usableFromInline
    internal func swapAt(_ i: Int, _ j: Int) {
        if i == j { return }
        let elements = firstElementAddress
        switch (isNil(at: i), isNil(at: j)) {
        case (true, true):
            break
        case (false, true):
            (elements + j).moveInitialize(from: elements + i, count: 1)
            setNil(at: i)
            setNonNil(at: j)
        case (true, false):
            (elements + i).moveInitialize(from: elements + j, count: 1)
            setNil(at: j)
            setNonNil(at: i)
        case (false, false):
            let element = (elements + i).move()
            (elements + i).moveInitialize(from: elements + j, count: 1)
            (elements + j).initialize(to: element)
        }
    }

    /// Moves the element at i to j, leaving nil at i.
    @usableFromInline
    internal func move(from i: Int, to j: Int) {
        if i == j { return }
        clear(at: j)
        if isNil(at: i) { return }
        (firstElementAddress + j).moveInitialize(from: firstElementAddress + i, count: 1)
        setNil(at: i)
        setNonNil(at: j)
    }
}

extension PackedOptionalsBuffer: MutableCollection, RandomAccessCollection {
    @usableFromInline
    internal typealias Index = Int
    @usableFromInline
    internal typealias Indices = Range<Int>
    @usableFromInline
    internal typealias Iterator = IndexingIterator<PackedOptionalsBuffer<Element>>
    @usableFromInline
    internal typealias SubSequence = Slice<PackedOptionalsBuffer<Element>>

    @usableFromInline
    internal var startIndex: Int { 0 }

    @usableFromInline
    internal var endIndex: Int { count }

    @usableFromInline
    internal func index(after i: Int) -> Int { i + 1 }

    @usableFromInline
    internal func index(before i: Int) -> Int { i - 1 }

    @usableFromInline
    internal func distance(from start: Int, to end: Int) -> Int { end - start }

    @usableFromInline
    internal var isEmpty: Bool { count == 0 }

    @usableFromInline
    internal var underestimatedCount: Int { count }

    @usableFromInline
    internal subscript(position: Int) -> Element? {
        get {
            isNil(at: position) ? nil : firstElementAddress[position]
        }
        nonmutating set {
            guard let newValue else {
                clear(at: position)
                return
            }
            if isNil(at: position) {
                (firstElementAddress + position).initialize(to: newValue)
                setNonNil(at: position)
                nilCount -= 1
            } else {
                firstElementAddress[position] = newValue
            }
        }
    }
}

extension PackedOptionalsBuffer: RangeReplaceableCollection {
    @usableFromInline
    internal init() {
        self = .allocate(capacity: 0)
    }

    @usableFromInline
    internal func replaceSubrange<C>(_ subrange: Range<Int>, with newValues: C)
    where C: Collection, C.Element == Element? {
        replaceSubrange(subrange, with: newValues.count, elementsOf: newValues)
    }

    /// Replaces the subrange in place; the buffer must have room for the new count.
    @usableFromInline
    internal func replaceSubrange<C>(_ subrange: Range<Int>, with newCount: Int, elementsOf newValues: C)
    where C: Collection, C.Element == Element? {
        let oldCount = count
        let growth = newCount - subrange.count
        precondition(oldCount + growth <= capacity, "PackedOptionalsBuffer has no room for the replacement")
        if growth > 0 {
            resize(by: growth)
            // Move the tail up, from its end.
            var i = oldCount - 1
            while i >= subrange.upperBound {
                swapAt(i, i + growth)
                i -= 1
            }
        } else if growth < 0 {
            // Destroy what is replaced beyond the new elements, then move the tail down.
            for i in subrange.lowerBound + newCount ..< subrange.upperBound { clear(at: i) }
            for i in subrange.upperBound ..< oldCount { move(from: i, to: i + growth) }
            resize(by: growth)
        }
        var position = subrange.lowerBound
        for value in newValues.prefix(newCount) {
            self[position] = value
            position += 1
        }
    }
}

extension PackedOptionalsBuffer: CustomReflectable {
    @usableFromInline
    internal var customMirror: Mirror {
        Mirror(self, unlabeledChildren: Array(self), displayStyle: .collection)
    }
}

@usableFromInline
internal final class PackedOptionalsStorage<Element> {
    @usableFromInline
    internal final var buffer: PackedOptionalsBuffer<Element>

    @usableFromInline
    internal final var capacity: Int { buffer.capacity }

    @usableFromInline
    internal final var count: Int { buffer.count }

    @usableFromInline
    internal final var nilCount: Int { buffer.nilCount }

    @usableFromInline
    internal init(capacity: Int) {
        buffer = .allocate(capacity: capacity)
    }

    @usableFromInline
    internal init(copying other: PackedOptionalsStorage<Element>, capacity: Int) {
        buffer = PackedOptionalsBuffer(copying: other.buffer, capacity: capacity)
    }

    deinit {
        buffer.deallocate()
    }

    @usableFromInline
    internal final func grow(minimumCapacity: Int, growForAppend: Bool) {
        let newBuffer = PackedOptionalsBuffer(moving: buffer, capacity: growCapacity(minimumCapacity: minimumCapacity, growForAppend: growForAppend))
        buffer.deallocate()
        buffer = newBuffer
    }

    @usableFromInline
    internal final func createNew(minimumCapacity: Int, growForAppend: Bool) -> PackedOptionalsStorage<Element> {
        PackedOptionalsStorage(copying: self, capacity: growCapacity(minimumCapacity: minimumCapacity, growForAppend: growForAppend))
    }

    /// The capacity to allocate for at least minimumCapacity elements:
    /// doubling when appending, so appends take amortized constant time.
    @usableFromInline
    internal final func growCapacity(minimumCapacity: Int, growForAppend: Bool) -> Int {
        let current = capacity
        if minimumCapacity <= current { return current }
        if growForAppend { return Swift.max(minimumCapacity, current * 2, 4) }
        return minimumCapacity
    }

    @usableFromInline
    internal final func resize(by change: Int) {
        buffer.resize(by: change)
    }

    @usableFromInline
    internal final func append(_ element: Element?) {
        buffer.append(element)
    }
}
