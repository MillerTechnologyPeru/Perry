// URLSession's async methods, over its tasks' completion handlers, and the
// asynchronous byte sequences of a response's and a URL's contents, read a
// chunk at a time into a buffer the frozen iterators step through inline.
// A response's bytes come once the whole body has loaded.

// MARK: - URLSession

@available(macOS 12.0, iOS 15.0, watchOS 8.0, tvOS 15.0, *)
extension URLSession {
    /// Runs a task the session makes with a completion handler, cancelling
    /// it if the calling task is cancelled. The delegate is the task's own,
    /// told of it before the session's delegate, metrics included.
    private func load<T: Sendable>(
        delegate: (any URLSessionTaskDelegate)? = nil,
        _ make: (@escaping @Sendable (T?, URLResponse?, (any Error)?) -> Void) -> URLSessionTask
    ) async throws -> (T, URLResponse) {
        let box = _TaskBox()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<(T, URLResponse), any Error>) in
                let task = make { value, response, error in
                    if let error {
                        continuation.resume(throwing: error)
                    } else if let value, let response {
                        continuation.resume(returning: (value, response))
                    } else {
                        continuation.resume(throwing: URLError(.badServerResponse))
                    }
                }
                box.task = task
                if let delegate { task.delegate = delegate }
                task.resume()
            }
        } onCancel: {
            box.task?.cancel()
        }
    }

    /// Downloads the contents of a URL based on the specified URL request
    /// and delivers the data asynchronously.
    public func data(for request: URLRequest, delegate: (any URLSessionTaskDelegate)? = nil) async throws -> (Data, URLResponse) {
        try await load(delegate: delegate) { handler in
            dataTask(with: request) { data, response, error in handler(data ?? Data(), response, error) }
        }
    }

    /// Retrieves the contents of a URL and delivers the data asynchronously.
    public func data(from url: URL, delegate: (any URLSessionTaskDelegate)? = nil) async throws -> (Data, URLResponse) {
        try await data(for: URLRequest(url: url), delegate: delegate)
    }

    /// Uploads data to a URL based on the specified URL request and delivers
    /// the result asynchronously.
    public func upload(for request: URLRequest, fromFile fileURL: URL, delegate: (any URLSessionTaskDelegate)? = nil) async throws -> (Data, URLResponse) {
        try await load(delegate: delegate) { handler in
            uploadTask(with: request, fromFile: fileURL) { data, response, error in handler(data ?? Data(), response, error) }
        }
    }

    /// Uploads data to a URL based on the specified URL request and delivers
    /// the result asynchronously.
    public func upload(for request: URLRequest, from bodyData: Data, delegate: (any URLSessionTaskDelegate)? = nil) async throws -> (Data, URLResponse) {
        try await load(delegate: delegate) { handler in
            uploadTask(with: request, from: bodyData) { data, response, error in handler(data ?? Data(), response, error) }
        }
    }

    /// Downloads the contents of a URL based on the specified URL request
    /// to a file, delivering its location asynchronously. The file is moved
    /// out of the way of the task's own clean-up first.
    public func download(for request: URLRequest, delegate: (any URLSessionTaskDelegate)? = nil) async throws -> (URL, URLResponse) {
        try await load(delegate: delegate) { handler in
            downloadTask(with: request) { location, response, error in
                handler(location.flatMap(URLSession.keep), response, error)
            }
        }
    }

    /// Retrieves the contents of a URL to a file, delivering its location
    /// asynchronously.
    public func download(from url: URL, delegate: (any URLSessionTaskDelegate)? = nil) async throws -> (URL, URLResponse) {
        try await download(for: URLRequest(url: url), delegate: delegate)
    }

    /// Resumes a previously paused download.
    public func download(resumeFrom resumeData: Data, delegate: (any URLSessionTaskDelegate)? = nil) async throws -> (URL, URLResponse) {
        try await load(delegate: delegate) { handler in
            downloadTask(withResumeData: resumeData) { location, response, error in
                handler(location.flatMap(URLSession.keep), response, error)
            }
        }
    }

    /// A downloaded file's new location, where the task won't remove it.
    private static func keep(_ location: URL) -> URL? {
        let kept = FileManager.default.temporaryDirectory.appendingPathComponent("CFNetworkDownload_\(UUID().uuidString).tmp")
        return (try? FileManager.default.moveItem(at: location, to: kept)) != nil ? kept : location
    }

    /// An asynchronous sequence of bytes of a response's body.
    public struct AsyncBytes: AsyncSequence, Sendable {
        public typealias Element = UInt8
        public typealias AsyncIterator = Iterator

        let _task: URLSessionDataTask
        let data: Data

        /// The task that loaded the bytes.
        public var task: URLSessionDataTask { _task }

        /// An iterator over the bytes, stepping through a buffer inline.
        @frozen
        public struct Iterator: AsyncIteratorProtocol, Sendable {
            public typealias Element = UInt8

            @usableFromInline
            internal var buffer: _AsyncBytesBuffer

            @inlinable @inline(__always)
            public mutating func next() async throws -> UInt8? {
                try await buffer.next()
            }
        }

        public __consuming func makeAsyncIterator() -> Iterator {
            Iterator(buffer: _AsyncBytesBuffer(chunks: _AsyncBytesChunks.once(data)))
        }
    }

    /// Starts a data task for a request and delivers its bytes, once
    /// they have loaded, with the response.
    public func bytes(for request: URLRequest, delegate: (any URLSessionTaskDelegate)? = nil) async throws -> (AsyncBytes, URLResponse) {
        let box = _TaskBox()
        let (data, response): (Data, URLResponse) = try await load(delegate: delegate) { handler in
            let task = dataTask(with: request) { data, response, error in handler(data ?? Data(), response, error) }
            box.task = task
            return task
        }
        return (AsyncBytes(_task: box.task as! URLSessionDataTask, data: data), response)
    }

    /// Delivers a URL's bytes, once they have loaded, with the response.
    public func bytes(from url: URL, delegate: (any URLSessionTaskDelegate)? = nil) async throws -> (AsyncBytes, URLResponse) {
        try await bytes(for: URLRequest(url: url), delegate: delegate)
    }
}

/// The task an async load made, for cancelling it.
final class _TaskBox: @unchecked Sendable {
    var task: URLSessionTask?
}

// MARK: - Buffers

/// Where an asynchronous byte sequence's chunks come from.
final class _AsyncBytesChunks: @unchecked Sendable {
    let nextChunk: () async throws -> Data?

    init(_ nextChunk: @escaping () async throws -> Data?) {
        self.nextChunk = nextChunk
    }

    /// One chunk, then the end.
    static func once(_ data: Data) -> _AsyncBytesChunks {
        var sent = false
        return _AsyncBytesChunks {
            defer { sent = true }
            return sent || data.isEmpty ? nil : data
        }
    }

    /// The chunk the buffer points into, kept until the next.
    var current: UnsafeMutableRawBufferPointer?

    deinit {
        current?.deallocate()
    }
}

/// The bytes the frozen iterators step through: from the next pointer to
/// the end pointer, in the storage's current chunk; past the end, the next
/// chunk is read.
@usableFromInline
@frozen
internal struct _AsyncBytesBuffer: @unchecked Sendable {
    internal var storage: AnyObject? = nil
    @usableFromInline
    internal var nextPointer: UnsafeMutableRawPointer
    @usableFromInline
    internal var endPointer: UnsafeMutableRawPointer

    /// Where an empty buffer points: a byte no buffer reads.
    nonisolated(unsafe) static let empty = UnsafeMutableRawPointer.allocate(byteCount: 1, alignment: 1)

    /// An empty buffer, whose first read loads the first chunk.
    @usableFromInline
    internal init(capacity: Int) {
        nextPointer = _AsyncBytesBuffer.empty
        endPointer = _AsyncBytesBuffer.empty
    }

    init(chunks: _AsyncBytesChunks) {
        self.init(capacity: 0)
        storage = chunks
    }

    @usableFromInline
    @inline(never)
    internal mutating func reloadBufferAndNext() async throws -> UInt8? {
        guard let chunks = storage as? _AsyncBytesChunks else { return nil }
        while let data = try await chunks.nextChunk() {
            guard !data.isEmpty else { continue }
            chunks.current?.deallocate()
            let chunk = UnsafeMutableRawBufferPointer.allocate(byteCount: data.count, alignment: 1)
            chunk.copyBytes(from: data)
            chunks.current = chunk
            nextPointer = chunk.baseAddress! + 1
            endPointer = chunk.baseAddress! + chunk.count
            return chunk[0]
        }
        storage = nil
        return nil
    }

    @inlinable @inline(__always)
    internal mutating func next() async throws -> UInt8? {
        if _fastPath(nextPointer != endPointer) {
            let byte = nextPointer.load(fromByteOffset: 0, as: UInt8.self)
            nextPointer = nextPointer + 1
            return byte
        }
        return try await reloadBufferAndNext()
    }
}

// MARK: - URL.AsyncBytes

@available(macOS 12.0, iOS 15.0, watchOS 8.0, tvOS 15.0, *)
extension URL {
    /// An asynchronous sequence of a URL's bytes: a file's, read a chunk at
    /// a time, or a loaded resource's.
    public struct AsyncBytes: AsyncSequence, Sendable {
        public typealias Element = UInt8

        let url: URL

        @frozen
        public struct AsyncIterator: AsyncIteratorProtocol, Sendable {
            @usableFromInline
            internal var buffer: _AsyncBytesBuffer = _AsyncBytesBuffer(capacity: 0)

            @inlinable @inline(__always)
            public mutating func next() async throws -> UInt8? {
                try await buffer.next()
            }

            public typealias Element = UInt8
        }

        public func makeAsyncIterator() -> AsyncIterator {
            var iterator = AsyncIterator()
            iterator.buffer = _AsyncBytesBuffer(chunks: AsyncBytes.chunks(of: url))
            return iterator
        }

        static func chunks(of url: URL) -> _AsyncBytesChunks {
            if url.isFileURL {
                var handle: FileHandle?
                var opened = false
                return _AsyncBytesChunks {
                    if !opened {
                        opened = true
                        handle = try FileHandle(forReadingFrom: url)
                    }
                    guard let file = handle else { return nil }
                    let data = file.readData(ofLength: 64 * 1024)
                    if data.isEmpty {
                        file.closeFile()
                        handle = nil
                        return nil
                    }
                    return data
                }
            }
            var done = false
            return _AsyncBytesChunks {
                guard !done else { return nil }
                done = true
                return try await URLSession.shared.data(from: url).0
            }
        }
    }

    /// The URL's resource data, as an asynchronous sequence of bytes.
    public var resourceBytes: URL.AsyncBytes {
        AsyncBytes(url: self)
    }

    /// The URL's resource data, as an asynchronous sequence of lines of
    /// text.
    public var lines: AsyncLineSequence<URL.AsyncBytes> {
        AsyncLineSequence(base: resourceBytes)
    }
}

// MARK: - AsyncLineSequence

/// An asynchronous sequence of lines of text, from a sequence of UTF-8
/// bytes: each ends at a line feed, carriage return, CRLF, or the Unicode
/// line and paragraph separators, which aren't part of it.
@available(macOS 12.0, iOS 15.0, watchOS 8.0, tvOS 15.0, *)
public struct AsyncLineSequence<Base>: AsyncSequence where Base: AsyncSequence, Base.Element == UInt8 {
    public typealias Element = String

    let base: Base

    public struct AsyncIterator: AsyncIteratorProtocol {
        public typealias Element = String

        var byteSource: Base.AsyncIterator
        var buffer: [UInt8] = []
        var leftover: UInt8? = nil

        init(_ byteSource: Base.AsyncIterator) {
            self.byteSource = byteSource
        }

        public mutating func next() async rethrows -> String? {
            func yield(_ buffer: inout [UInt8]) -> String {
                defer { buffer.removeAll(keepingCapacity: true) }
                return String(decoding: buffer, as: UTF8.self)
            }
            var sawAny = false
            while true {
                let byte: UInt8
                if let leftover {
                    byte = leftover
                    self.leftover = nil
                } else if let next = try await byteSource.next() {
                    byte = next
                } else {
                    return sawAny || !buffer.isEmpty ? yield(&buffer) : nil
                }
                sawAny = true
                switch byte {
                case 0x0A:
                    return yield(&buffer)
                case 0x0D:
                    // CRLF is one ending.
                    if let next = try await byteSource.next(), next != 0x0A { leftover = next }
                    return yield(&buffer)
                default:
                    buffer.append(byte)
                    // U+2028 and U+2029 end lines too: E2 80 A8 and E2 80 A9.
                    if buffer.count >= 3, buffer[buffer.count - 3] == 0xE2, buffer[buffer.count - 2] == 0x80,
                       buffer[buffer.count - 1] == 0xA8 || buffer[buffer.count - 1] == 0xA9 {
                        buffer.removeLast(3)
                        return yield(&buffer)
                    }
                }
            }
        }
    }

    public func makeAsyncIterator() -> AsyncIterator {
        AsyncIterator(base.makeAsyncIterator())
    }
}

@available(macOS 12.0, iOS 15.0, watchOS 8.0, tvOS 15.0, *)
extension AsyncLineSequence: Sendable where Base: Sendable {}

@available(macOS 12.0, iOS 15.0, watchOS 8.0, tvOS 15.0, *)
extension AsyncLineSequence.AsyncIterator: Sendable where Base.AsyncIterator: Sendable {}

@available(macOS 12.0, iOS 15.0, watchOS 8.0, tvOS 15.0, *)
extension AsyncSequence where Self.Element == UInt8 {
    /// The sequence's bytes as lines of UTF-8 text.
    public var lines: AsyncLineSequence<Self> {
        AsyncLineSequence(base: self)
    }
}
