import Darwin
import Foundation

// The Swift API of libcompression: OutputFilter and InputFilter, streams
// over compression_stream.

@available(macOS 10.15, iOS 13, watchOS 6, tvOS 13, *)
public enum Algorithm: CaseIterable, RawRepresentable {
    case lzfse
    case zlib
    case lz4
    case lzma
    case lzbitmap
    case brotli

    public init?(rawValue: compression_algorithm) {
        switch rawValue {
        case COMPRESSION_LZFSE: self = .lzfse
        case COMPRESSION_ZLIB: self = .zlib
        case COMPRESSION_LZ4: self = .lz4
        case COMPRESSION_LZMA: self = .lzma
        case COMPRESSION_LZBITMAP: self = .lzbitmap
        case COMPRESSION_BROTLI: self = .brotli
        default: return nil
        }
    }

    public var rawValue: compression_algorithm {
        switch self {
        case .lzfse: return COMPRESSION_LZFSE
        case .zlib: return COMPRESSION_ZLIB
        case .lz4: return COMPRESSION_LZ4
        case .lzma: return COMPRESSION_LZMA
        case .lzbitmap: return COMPRESSION_LZBITMAP
        case .brotli: return COMPRESSION_BROTLI
        }
    }

    public static var allCases: [Algorithm] { [.lzfse, .zlib, .lz4, .lzma, .lzbitmap, .brotli] }
}

@available(macOS 10.15, iOS 13, watchOS 6, tvOS 13, *)
public enum FilterOperation: RawRepresentable {
    case compress
    case decompress

    public init?(rawValue: compression_stream_operation) {
        switch rawValue {
        case COMPRESSION_STREAM_ENCODE: self = .compress
        case COMPRESSION_STREAM_DECODE: self = .decompress
        default: return nil
        }
    }

    public var rawValue: compression_stream_operation {
        switch self {
        case .compress: return COMPRESSION_STREAM_ENCODE
        case .decompress: return COMPRESSION_STREAM_DECODE
        }
    }
}

@available(macOS 10.15, iOS 13, watchOS 6, tvOS 13, *)
public enum FilterError: Error {
    /// The filter was used after it was finalized, or could not be made.
    case invalidState
    /// The data is not the algorithm's.
    case invalidData
}

/// A compression_stream and the buffer it writes to.
@available(macOS 10.15, iOS 13, watchOS 6, tvOS 13, *)
private final class Stream {
    private let pointer: UnsafeMutablePointer<compression_stream>
    private let buffer: UnsafeMutablePointer<UInt8>
    private let capacity: Int
    private(set) var ended = false

    init(_ operation: FilterOperation, _ algorithm: Algorithm, capacity: Int) throws {
        pointer = .allocate(capacity: 1)
        guard compression_stream_init(pointer, operation.rawValue, algorithm.rawValue) == COMPRESSION_STATUS_OK else {
            pointer.deallocate()
            throw FilterError.invalidState
        }
        self.capacity = max(capacity, 1)
        buffer = .allocate(capacity: self.capacity)
        pointer.pointee.src_size = 0
        pointer.pointee.dst_ptr = buffer
        pointer.pointee.dst_size = self.capacity
    }

    deinit {
        compression_stream_destroy(pointer)
        buffer.deallocate()
        pointer.deallocate()
    }

    /// Whether the stream has input left from the last bytes given.
    var hasInput: Bool { pointer.pointee.src_size > 0 }

    /// Runs the stream over `source` (none to go on with what it has, or to
    /// finish), handing each full or last buffer to `output`, until it has
    /// taken the bytes or, finishing, has ended.
    func process(_ source: UnsafeRawBufferPointer?, finish: Bool, output: (Data) throws -> Void) throws {
        if let source, let base = source.baseAddress {
            pointer.pointee.src_ptr = base.assumingMemoryBound(to: UInt8.self)
            pointer.pointee.src_size = source.count
        }
        let flags = finish ? Int32(COMPRESSION_STREAM_FINALIZE.rawValue) : 0
        while !ended {
            let status = compression_stream_process(pointer, flags)
            guard status != COMPRESSION_STATUS_ERROR else { throw FilterError.invalidData }
            if status == COMPRESSION_STATUS_END { ended = true }
            let produced = capacity - pointer.pointee.dst_size
            if produced > 0, ended || pointer.pointee.dst_size == 0 || !finish && pointer.pointee.src_size == 0 {
                try output(Data(bytes: buffer, count: produced))
                pointer.pointee.dst_ptr = buffer
                pointer.pointee.dst_size = capacity
            }
            if !ended, pointer.pointee.src_size == 0, !finish { break }
            if !ended, produced == 0, pointer.pointee.src_size == 0, finish, status == COMPRESSION_STATUS_OK,
               pointer.pointee.dst_size == capacity {
                // Nothing in, nothing out and no end: the stream waits for
                // input that will not come.
                throw FilterError.invalidData
            }
        }
    }
}

/// A filter that compresses or decompresses what is written to it, and
/// hands the result to a closure: nil after the last of it.
@available(macOS 10.15, iOS 13, watchOS 6, tvOS 13, *)
public class OutputFilter {
    private var stream: Stream?
    private let writeFunc: (Data?) throws -> Void

    public init(_ operation: FilterOperation, using algorithm: Algorithm, bufferCapacity: Int = 65536,
                writingTo writeFunc: @escaping (Data?) throws -> Void) throws {
        stream = try Stream(operation, algorithm, capacity: bufferCapacity)
        self.writeFunc = writeFunc
    }

    /// Writes data to the filter; nil or no bytes finalize it.
    public func write<D: DataProtocol>(_ data: D?) throws {
        guard let data, !data.isEmpty else { return try finalize() }
        guard let stream, !stream.ended else { throw FilterError.invalidState }
        for region in data.regions {
            try region.withUnsafeBytes { bytes in
                try stream.process(bytes, finish: false) { try writeFunc($0) }
            }
        }
    }

    /// Flushes what the stream holds and tells the closure the output has
    /// ended. A filter finalized already does nothing.
    public func finalize() throws {
        guard let stream else { return }
        self.stream = nil
        if !stream.ended {
            try stream.process(nil, finish: true) { try writeFunc($0) }
        }
        try writeFunc(nil)
    }

    deinit {
        try? finalize()
    }
}

/// A filter that compresses or decompresses what a closure supplies, as
/// it is read.
@available(macOS 10.15, iOS 13, watchOS 6, tvOS 13, *)
public class InputFilter<D: DataProtocol> {
    private let stream: Stream
    private let readFunc: (Int) throws -> D?
    private let capacity: Int
    /// Output made and not yet read.
    private var pending = Data()
    private var sourceEnded = false

    public init(_ operation: FilterOperation, using algorithm: Algorithm, bufferCapacity: Int = 65536,
                readingFrom readFunc: @escaping (Int) throws -> D?) throws {
        stream = try Stream(operation, algorithm, capacity: bufferCapacity)
        capacity = max(bufferCapacity, 1)
        self.readFunc = readFunc
    }

    /// Up to `count` bytes of the result, or nil once there are no more.
    public func readData(ofLength count: Int) throws -> Data? {
        while pending.count < count, !stream.ended {
            if !sourceEnded, let input = try readFunc(capacity), !input.isEmpty {
                for region in input.regions {
                    try region.withUnsafeBytes { bytes in
                        try stream.process(bytes, finish: false) { pending.append($0) }
                    }
                }
            } else {
                sourceEnded = true
                try stream.process(nil, finish: true) { pending.append($0) }
            }
        }
        guard !pending.isEmpty else { return nil }
        let result = pending.prefix(count)
        pending = Data(pending.dropFirst(result.count))
        return Data(result)
    }
}
