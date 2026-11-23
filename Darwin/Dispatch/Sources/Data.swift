import Darwin

// DispatchData: a dispatch_data_t (__DispatchData), immutable and made of
// regions, as a collection of bytes.

// The empty data and the free and munmap destructors are in the library's
// data; declared as functions, their names give their addresses.
@_silgen_name("_dispatch_data_empty") private func emptyDataSymbol()
@_silgen_name("_dispatch_data_destructor_free") private func freeDestructorSymbol()
@_silgen_name("_dispatch_data_destructor_munmap") private func munmapDestructorSymbol()

/// The value stored at a symbol's address.
private func value<T>(at symbol: @convention(thin) () -> Void, as type: T.Type) -> T {
    unsafeBitCast(symbol, to: UnsafePointer<T>.self).pointee
}

private let emptyData = unsafeBitCast(emptyDataSymbol as @convention(thin) () -> Void, to: __DispatchData.self)

// The data functions take their destructors and appliers as blocks; called
// by name, without the refinements Swift's import gives them.
@_silgen_name("dispatch_data_create")
private func dispatchDataCreate(_ buffer: UnsafeRawPointer?, _ size: Int, _ queue: DispatchQueue?, _ destructor: _DispatchBlock?) -> __DispatchData

@_silgen_name("dispatch_data_apply")
private func dispatchDataApply(_ data: __DispatchData, _ applier: @convention(block) (__DispatchData, Int, UnsafeRawPointer, Int) -> Bool) -> Bool

public struct DispatchData: RandomAccessCollection, _ObjectiveCBridgeable, Sendable {
    public typealias Iterator = DispatchDataIterator
    public typealias Index = Int
    public typealias Indices = DefaultIndices<DispatchData>
    public typealias Element = UInt8
    public typealias SubSequence = Slice<DispatchData>
    public typealias _ObjectiveCType = __DispatchData

    internal var __wrapped: __DispatchData

    public static let empty = DispatchData(data: emptyData)

    public enum Deallocator: Sendable {
        case free
        case unmap
        @preconcurrency case custom(DispatchQueue?, @Sendable @convention(block) () -> Void)

        fileprivate var parameters: (queue: DispatchQueue?, destructor: _DispatchBlock) {
            switch self {
            case .free: return (nil, value(at: freeDestructorSymbol, as: _DispatchBlock.self))
            case .unmap: return (nil, value(at: munmapDestructorSymbol, as: _DispatchBlock.self))
            case .custom(let queue, let block): return (queue, block)
            }
        }
    }

    init(data: __DispatchData) {
        __wrapped = data
    }

    @available(swift, deprecated: 4, message: "Use init(bytes: UnsafeRawBufferPointer) instead")
    public init(bytes buffer: UnsafeBufferPointer<UInt8>) {
        self.init(bytes: UnsafeRawBufferPointer(buffer))
    }

    /// A copy of the bytes (the default destructor copies them).
    public init(bytes buffer: UnsafeRawBufferPointer) {
        __wrapped = buffer.baseAddress == nil || buffer.isEmpty ? emptyData : dispatchDataCreate(buffer.baseAddress, buffer.count, nil, nil)
    }

    @available(swift, deprecated: 4, message: "Use init(bytesNoCopy: UnsafeRawBufferPointer, deallocater: Deallocator) instead")
    public init(bytesNoCopy bytes: UnsafeBufferPointer<UInt8>, deallocator: Deallocator = .free) {
        self.init(bytesNoCopy: UnsafeRawBufferPointer(bytes), deallocator: deallocator)
    }

    public init(bytesNoCopy bytes: UnsafeRawBufferPointer, deallocator: Deallocator = .free) {
        let (queue, destructor) = deallocator.parameters
        __wrapped = dispatchDataCreate(bytes.baseAddress, bytes.count, queue, destructor)
    }

    public var count: Int {
        __dispatch_data_get_size(__wrapped)
    }

    /// The bytes, contiguous: the data mapped while `body` runs.
    public func withUnsafeBytes<Result, ContentType>(body: (UnsafePointer<ContentType>) throws -> Result) rethrows -> Result {
        var pointer: UnsafeRawPointer?
        var size = 0
        let mapped = __dispatch_data_create_map(__wrapped, &pointer, &size)
        return try withExtendedLifetime(mapped) {
            try body((pointer ?? UnsafeRawPointer(bitPattern: 1)!).assumingMemoryBound(to: ContentType.self))
        }
    }

    @available(swift 4.2)
    public func enumerateBytes(_ block: (_ buffer: UnsafeBufferPointer<UInt8>, _ byteIndex: Int, _ stop: inout Bool) -> Void) {
        _ = dispatchDataApply(__wrapped) { _, offset, pointer, size in
            var stop = false
            block(UnsafeBufferPointer(start: pointer.assumingMemoryBound(to: UInt8.self), count: size), offset, &stop)
            return !stop
        }
    }

    @available(swift, obsoleted: 4.2, renamed: "enumerateBytes(_:)")
    public func enumerateBytes(block: (_ buffer: UnsafeBufferPointer<UInt8>, _ byteIndex: Int, _ stop: inout Bool) -> Void) {
        enumerateBytes(block)
    }

    @available(swift, deprecated: 4, message: "Use append(_: UnsafeRawBufferPointer) instead")
    public mutating func append(_ bytes: UnsafePointer<UInt8>, count: Int) {
        append(UnsafeRawBufferPointer(start: bytes, count: count))
    }

    public mutating func append(_ bytes: UnsafeRawBufferPointer) {
        guard bytes.baseAddress != nil, !bytes.isEmpty else { return }
        append(DispatchData(bytes: bytes))
    }

    public mutating func append(_ other: DispatchData) {
        __wrapped = __dispatch_data_create_concat(__wrapped, other.__wrapped)
    }

    public mutating func append<SourceType>(_ buffer: UnsafeBufferPointer<SourceType>) {
        append(UnsafeRawBufferPointer(buffer))
    }

    /// Copies the bytes of `range` to `pointer`, region by region.
    private func copy(to pointer: UnsafeMutableRawPointer, range: Range<Int>) {
        guard !range.isEmpty else { return }
        _ = dispatchDataApply(__wrapped) { _, offset, bytes, size in
            let region = offset..<(offset + size)
            let overlap = region.clamped(to: range)
            if !overlap.isEmpty {
                (pointer + (overlap.lowerBound - range.lowerBound))
                    .copyMemory(from: bytes + (overlap.lowerBound - offset), byteCount: overlap.count)
            }
            return region.upperBound < range.upperBound
        }
    }

    @available(swift, deprecated: 4, message: "Use copyBytes(to: UnsafeMutableRawBufferPointer, count: Int) instead")
    public func copyBytes(to pointer: UnsafeMutablePointer<UInt8>, count: Int) {
        copy(to: UnsafeMutableRawPointer(pointer), range: 0..<count)
    }

    public func copyBytes(to pointer: UnsafeMutableRawBufferPointer, count: Int) {
        precondition(count <= pointer.count, "Destination buffer is too small")
        guard let base = pointer.baseAddress else { return }
        copy(to: base, range: 0..<count)
    }

    @available(swift, deprecated: 4, message: "Use copyBytes(to: UnsafeMutableRawBufferPointer, from: Range<Index>) instead")
    public func copyBytes(to pointer: UnsafeMutablePointer<UInt8>, from range: Range<Index>) {
        copy(to: UnsafeMutableRawPointer(pointer), range: range)
    }

    public func copyBytes(to pointer: UnsafeMutableRawBufferPointer, from range: Range<Index>) {
        precondition(range.count <= pointer.count, "Destination buffer is too small")
        guard let base = pointer.baseAddress else { return }
        copy(to: base, range: range)
    }

    /// As many whole elements as fit in the buffer, of the range or all the
    /// data; the number of bytes copied.
    public func copyBytes<DestinationType>(to buffer: UnsafeMutableBufferPointer<DestinationType>, from range: Range<Index>? = nil) -> Int {
        guard let base = buffer.baseAddress, !buffer.isEmpty else { return 0 }
        let wanted = range ?? 0..<count
        precondition(wanted.lowerBound >= 0 && wanted.upperBound <= count, "Range out of bounds")
        let capacity = buffer.count * MemoryLayout<DestinationType>.stride
        let copied = Swift.min(wanted.count, capacity)
        copy(to: UnsafeMutableRawPointer(base), range: wanted.lowerBound..<(wanted.lowerBound + copied))
        return copied
    }

    public subscript(index: Index) -> UInt8 {
        precondition(index >= 0 && index < count, "Index out of range")
        var byte: UInt8 = 0
        withUnsafeMutableBytes(of: &byte) { copy(to: $0.baseAddress!, range: index..<(index + 1)) }
        return byte
    }

    public subscript(bounds: Range<Int>) -> Slice<DispatchData> {
        Slice(base: self, bounds: bounds)
    }

    public func subdata(in range: Range<Index>) -> DispatchData {
        DispatchData(data: __dispatch_data_create_subrange(__wrapped, range.lowerBound, range.count))
    }

    public func region(location: Int) -> (data: DispatchData, offset: Int) {
        var offset = 0
        let region = __dispatch_data_copy_region(__wrapped, location, &offset)
        return (DispatchData(data: region), offset)
    }

    public var startIndex: Index { 0 }
    public var endIndex: Index { count }

    public func index(before i: Index) -> Index { i - 1 }
    public func index(after i: Index) -> Index { i + 1 }

    public func makeIterator() -> Iterator {
        DispatchDataIterator(_data: self)
    }
}

/// The bytes of data, from a contiguous map of it.
public struct DispatchDataIterator: IteratorProtocol, Sequence, @unchecked Sendable {
    public typealias Element = UInt8

    private let mapped: __DispatchData
    private let bytes: UnsafeRawPointer?
    private let count: Int
    private var position = 0

    public init(_data: DispatchData) {
        var pointer: UnsafeRawPointer?
        var size = 0
        mapped = __dispatch_data_create_map(_data.__wrapped, &pointer, &size)
        bytes = pointer
        count = size
    }

    public mutating func next() -> DispatchData.Element? {
        guard position < count, let bytes else { return nil }
        defer { position += 1 }
        return bytes.load(fromByteOffset: position, as: UInt8.self)
    }
}

extension DispatchData {
    @_semantics("convertToObjectiveC")
    public func _bridgeToObjectiveC() -> __DispatchData {
        __wrapped
    }

    public static func _forceBridgeFromObjectiveC(_ input: __DispatchData, result: inout DispatchData?) {
        result = DispatchData(data: input)
    }

    public static func _conditionallyBridgeFromObjectiveC(_ input: __DispatchData, result: inout DispatchData?) -> Bool {
        result = DispatchData(data: input)
        return true
    }

    @_effects(readonly)
    public static func _unconditionallyBridgeFromObjectiveC(_ source: __DispatchData?) -> DispatchData {
        source.map { DispatchData(data: $0) } ?? .empty
    }
}
