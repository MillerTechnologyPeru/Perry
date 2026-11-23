import Darwin

// DispatchIO's Swift API: channels and the one-shot read and write.

extension DispatchIO {
    public enum StreamType: UInt, Sendable {
        case stream = 0
        case random = 1
    }

    public struct CloseFlags: OptionSet, RawRepresentable, Sendable {
        public let rawValue: UInt
        public init(rawValue: UInt) { self.rawValue = rawValue }
        public static let stop = CloseFlags(rawValue: 1)
    }

    public struct IntervalFlags: OptionSet, RawRepresentable, Sendable {
        public let rawValue: UInt
        public init(rawValue: UInt) { self.rawValue = rawValue }
        public init(nilLiteral: ()) { self.rawValue = 0 }
        public static let strictInterval = IntervalFlags(rawValue: 1)
    }

    public class func read(fromFileDescriptor: Int32, maxLength: Int, runningHandlerOn queue: DispatchQueue,
                           handler: @escaping (_ data: DispatchData, _ error: Int32) -> Void) {
        __dispatch_read(fromFileDescriptor, maxLength, queue) { data, error in
            handler(DispatchData(data: data), error)
        }
    }

    public class func write(toFileDescriptor: Int32, data: DispatchData, runningHandlerOn queue: DispatchQueue,
                            handler: @escaping (_ data: DispatchData?, _ error: Int32) -> Void) {
        __dispatch_write(toFileDescriptor, data.__wrapped, queue) { data, error in
            handler(data.map { DispatchData(data: $0) }, error)
        }
    }

    public convenience init(type: StreamType, fileDescriptor: Int32, queue: DispatchQueue,
                            cleanupHandler: @escaping (_ error: Int32) -> Void) {
        self.init(__type: type.rawValue, fd: fileDescriptor, queue: queue, handler: cleanupHandler)
    }

    @available(swift, obsoleted: 4)
    public convenience init(type: StreamType, path: UnsafePointer<Int8>, oflag: Int32, mode: mode_t, queue: DispatchQueue,
                            cleanupHandler: @escaping (_ error: Int32) -> Void) {
        self.init(__type: type.rawValue, path: path, oflag: oflag, mode: mode, queue: queue, handler: cleanupHandler)
    }

    @available(swift 4)
    public convenience init?(type: StreamType, path: UnsafePointer<Int8>, oflag: Int32, mode: mode_t, queue: DispatchQueue,
                             cleanupHandler: @escaping (_ error: Int32) -> Void) {
        self.init(__type: type.rawValue, path: path, oflag: oflag, mode: mode, queue: queue, handler: cleanupHandler)
    }

    public convenience init(type: StreamType, io: DispatchIO, queue: DispatchQueue,
                            cleanupHandler: @escaping (_ error: Int32) -> Void) {
        self.init(__type: type.rawValue, io: io, queue: queue, handler: cleanupHandler)
    }

    public func read(offset: off_t, length: Int, queue: DispatchQueue,
                     ioHandler: @escaping (_ done: Bool, _ data: DispatchData?, _ error: Int32) -> Void) {
        __dispatch_io_read(self, offset, length, queue) { done, data, error in
            ioHandler(done, data.map { DispatchData(data: $0) }, error)
        }
    }

    public func write(offset: off_t, data: DispatchData, queue: DispatchQueue,
                      ioHandler: @escaping (_ done: Bool, _ data: DispatchData?, _ error: Int32) -> Void) {
        __dispatch_io_write(self, offset, data.__wrapped, queue) { done, data, error in
            ioHandler(done, data.map { DispatchData(data: $0) }, error)
        }
    }

    public func setInterval(interval: DispatchTimeInterval, flags: IntervalFlags = []) {
        __dispatch_io_set_interval(self, UInt64(max(0, interval.rawValue)), flags.rawValue)
    }

    public func close(flags: CloseFlags = []) {
        __dispatch_io_close(self, flags.rawValue)
    }
}
