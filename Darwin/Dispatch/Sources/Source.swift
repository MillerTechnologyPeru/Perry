import Darwin

// Dispatch sources: the factory methods, the handlers and accessors every
// source has, and each kind's typed ones.

// Each source type is a structure in the library's data, which Swift can't
// import; declared as functions, their names give their addresses, as
// DISPATCH_SOURCE_TYPE_* take them.
@_silgen_name("_dispatch_source_type_data_add") private func typeDataAdd()
@_silgen_name("_dispatch_source_type_data_or") private func typeDataOr()
@_silgen_name("_dispatch_source_type_data_replace") private func typeDataReplace()
@_silgen_name("_dispatch_source_type_mach_send") private func typeMachSend()
@_silgen_name("_dispatch_source_type_mach_recv") private func typeMachReceive()
@_silgen_name("_dispatch_source_type_memorypressure") private func typeMemoryPressure()
@_silgen_name("_dispatch_source_type_proc") private func typeProcess()
@_silgen_name("_dispatch_source_type_read") private func typeRead()
@_silgen_name("_dispatch_source_type_signal") private func typeSignal()
@_silgen_name("_dispatch_source_type_timer") private func typeTimer()
@_silgen_name("_dispatch_source_type_vnode") private func typeFileSystemObject()
@_silgen_name("_dispatch_source_type_write") private func typeWrite()

@_silgen_name("dispatch_source_create")
private func dispatchSourceCreate(_ type: UnsafeRawPointer, _ handle: UInt, _ mask: UInt, _ queue: DispatchQueue?) -> DispatchSource

/// A source as the protocol of its kind. Darwin's sources conform to their
/// kind's Objective-C protocol; one in Perry is a plain dispatch source, so
/// it is taken as the protocol without a conformance check (an Objective-C
/// protocol's existential is the object's pointer).
private func typed<P>(_ source: DispatchSource, as type: P.Type) -> P {
    unsafeBitCast(source, to: type)
}

/// A new source of the type whose symbol `type` is.
private func makeSource(_ type: @convention(thin) () -> Void, handle: UInt = 0, mask: UInt = 0, queue: DispatchQueue?) -> DispatchSource {
    dispatchSourceCreate(unsafeBitCast(type, to: UnsafeRawPointer.self), handle, mask, queue)
}

extension DispatchSourceProtocol {
    public typealias DispatchSourceHandler = @convention(block) () -> Void

    private var source: DispatchSource { unsafeDowncast(self as AnyObject, to: DispatchSource.self) }

    /// A handler with QoS or flags, wrapped as a work item's block.
    private func block(qos: DispatchQoS, flags: DispatchWorkItemFlags, _ handler: DispatchSourceHandler?) -> DispatchSourceHandler? {
        guard let handler, qos != .unspecified || !flags.isEmpty else { return handler }
        return makeBlock(qos: qos, flags: flags, handler)
    }

    public func setEventHandler(qos: DispatchQoS = .unspecified, flags: DispatchWorkItemFlags = [], handler: DispatchSourceHandler?) {
        __dispatch_source_set_event_handler(source, block(qos: qos, flags: flags, handler))
    }

    @available(macOS 10.10, iOS 8.0, *)
    public func setEventHandler(handler: DispatchWorkItem) {
        __dispatch_source_set_event_handler(source, handler._block)
    }

    public func setCancelHandler(qos: DispatchQoS = .unspecified, flags: DispatchWorkItemFlags = [], handler: DispatchSourceHandler?) {
        __dispatch_source_set_cancel_handler(source, block(qos: qos, flags: flags, handler))
    }

    @available(macOS 10.10, iOS 8.0, *)
    public func setCancelHandler(handler: DispatchWorkItem) {
        __dispatch_source_set_cancel_handler(source, handler._block)
    }

    public func setRegistrationHandler(qos: DispatchQoS = .unspecified, flags: DispatchWorkItemFlags = [], handler: DispatchSourceHandler?) {
        __dispatch_source_set_registration_handler(source, block(qos: qos, flags: flags, handler))
    }

    @available(macOS 10.10, iOS 8.0, *)
    public func setRegistrationHandler(handler: DispatchWorkItem) {
        __dispatch_source_set_registration_handler(source, handler._block)
    }

    @available(macOS 10.12, iOS 10.0, tvOS 10.0, watchOS 3.0, *)
    public func activate() {
        source.activate()
    }

    public func cancel() {
        __dispatch_source_cancel(source)
    }

    public func resume() {
        source.resume()
    }

    public func suspend() {
        source.suspend()
    }

    public var handle: UInt { __dispatch_source_get_handle(source) }
    public var mask: UInt { __dispatch_source_get_mask(source) }
    public var data: UInt { __dispatch_source_get_data(source) }
    public var isCancelled: Bool { __dispatch_source_testcancel(source) != 0 }
}

extension DispatchSource {
    public struct MachSendEvent: OptionSet, RawRepresentable {
        public let rawValue: UInt
        public init(rawValue: UInt) { self.rawValue = rawValue }
        public static let dead = MachSendEvent(rawValue: 0x1)
    }

    public struct MemoryPressureEvent: OptionSet, RawRepresentable {
        public let rawValue: UInt
        public init(rawValue: UInt) { self.rawValue = rawValue }
        public static let normal = MemoryPressureEvent(rawValue: 0x1)
        public static let warning = MemoryPressureEvent(rawValue: 0x2)
        public static let critical = MemoryPressureEvent(rawValue: 0x4)
        public static let all: MemoryPressureEvent = [.normal, .warning, .critical]
        // Apple's private events, as libdispatch numbers them.
        @_spi(DispatchPrivate) public static let procLimitWarn = MemoryPressureEvent(rawValue: 0x10)
        @_spi(DispatchPrivate) public static let procLimitCritical = MemoryPressureEvent(rawValue: 0x20)
        @_spi(DispatchPrivate) public static let mslStatus = MemoryPressureEvent(rawValue: 0xf000_0000)
    }

    public struct ProcessEvent: OptionSet, RawRepresentable {
        public let rawValue: UInt
        public init(rawValue: UInt) { self.rawValue = rawValue }
        public static let exit = ProcessEvent(rawValue: 0x8000_0000)
        public static let fork = ProcessEvent(rawValue: 0x4000_0000)
        public static let exec = ProcessEvent(rawValue: 0x2000_0000)
        public static let signal = ProcessEvent(rawValue: 0x0800_0000)
        public static let all: ProcessEvent = [.exit, .fork, .exec, .signal]
    }

    public struct TimerFlags: OptionSet, RawRepresentable {
        public let rawValue: UInt
        public init(rawValue: UInt) { self.rawValue = rawValue }
        public static let strict = TimerFlags(rawValue: 0x1)
    }

    public struct FileSystemEvent: OptionSet, RawRepresentable {
        public let rawValue: UInt
        public init(rawValue: UInt) { self.rawValue = rawValue }
        public static let delete = FileSystemEvent(rawValue: 0x1)
        public static let write = FileSystemEvent(rawValue: 0x2)
        public static let extend = FileSystemEvent(rawValue: 0x4)
        public static let attrib = FileSystemEvent(rawValue: 0x8)
        public static let link = FileSystemEvent(rawValue: 0x10)
        public static let rename = FileSystemEvent(rawValue: 0x20)
        public static let revoke = FileSystemEvent(rawValue: 0x40)
        public static let funlock = FileSystemEvent(rawValue: 0x100)
        public static let all: FileSystemEvent = [.delete, .write, .extend, .attrib, .link, .rename, .revoke, .funlock]
    }

    public class func makeMachSendSource(port: mach_port_t, eventMask: MachSendEvent, queue: DispatchQueue? = nil) -> any DispatchSourceMachSend {
        typed(makeSource(typeMachSend, handle: UInt(port), mask: eventMask.rawValue, queue: queue), as: (any DispatchSourceMachSend).self)
    }

    public class func makeMachReceiveSource(port: mach_port_t, queue: DispatchQueue? = nil) -> any DispatchSourceMachReceive {
        typed(makeSource(typeMachReceive, handle: UInt(port), queue: queue), as: (any DispatchSourceMachReceive).self)
    }

    public class func makeMemoryPressureSource(eventMask: MemoryPressureEvent, queue: DispatchQueue? = nil) -> any DispatchSourceMemoryPressure {
        typed(makeSource(typeMemoryPressure, mask: eventMask.rawValue, queue: queue), as: (any DispatchSourceMemoryPressure).self)
    }

    public class func makeProcessSource(identifier: pid_t, eventMask: ProcessEvent, queue: DispatchQueue? = nil) -> any DispatchSourceProcess {
        typed(makeSource(typeProcess, handle: UInt(identifier), mask: eventMask.rawValue, queue: queue), as: (any DispatchSourceProcess).self)
    }

    public class func makeReadSource(fileDescriptor: Int32, queue: DispatchQueue? = nil) -> any DispatchSourceRead {
        typed(makeSource(typeRead, handle: UInt(fileDescriptor), queue: queue), as: (any DispatchSourceRead).self)
    }

    public class func makeSignalSource(signal: Int32, queue: DispatchQueue? = nil) -> any DispatchSourceSignal {
        typed(makeSource(typeSignal, handle: UInt(signal), queue: queue), as: (any DispatchSourceSignal).self)
    }

    public class func makeTimerSource(flags: TimerFlags = [], queue: DispatchQueue? = nil) -> any DispatchSourceTimer {
        typed(makeSource(typeTimer, mask: flags.rawValue, queue: queue), as: (any DispatchSourceTimer).self)
    }

    public class func makeUserDataAddSource(queue: DispatchQueue? = nil) -> any DispatchSourceUserDataAdd {
        typed(makeSource(typeDataAdd, queue: queue), as: (any DispatchSourceUserDataAdd).self)
    }

    public class func makeUserDataOrSource(queue: DispatchQueue? = nil) -> any DispatchSourceUserDataOr {
        typed(makeSource(typeDataOr, queue: queue), as: (any DispatchSourceUserDataOr).self)
    }

    public class func makeUserDataReplaceSource(queue: DispatchQueue? = nil) -> any DispatchSourceUserDataReplace {
        typed(makeSource(typeDataReplace, queue: queue), as: (any DispatchSourceUserDataReplace).self)
    }

    public class func makeFileSystemObjectSource(fileDescriptor: Int32, eventMask: FileSystemEvent, queue: DispatchQueue? = nil) -> any DispatchSourceFileSystemObject {
        typed(makeSource(typeFileSystemObject, handle: UInt(fileDescriptor), mask: eventMask.rawValue, queue: queue), as: (any DispatchSourceFileSystemObject).self)
    }

    public class func makeWriteSource(fileDescriptor: Int32, queue: DispatchQueue? = nil) -> any DispatchSourceWrite {
        typed(makeSource(typeWrite, handle: UInt(fileDescriptor), queue: queue), as: (any DispatchSourceWrite).self)
    }
}

@available(macOS 15.0, iOS 18.0, tvOS 18.0, watchOS 11.0, visionOS 2.0, *)
extension DispatchSource.MemoryPressureEvent: CustomStringConvertible {
    public var description: String {
        var names: [String] = []
        if contains(.normal) { names.append("normal") }
        if contains(.warning) { names.append("warning") }
        if contains(.critical) { names.append("critical") }
        return names.isEmpty ? "[]" : "[" + names.joined(separator: ", ") + "]"
    }
}

extension DispatchSourceMachSend {
    public var handle: mach_port_t { mach_port_t(__dispatch_source_get_handle(self as! DispatchSource)) }
    public var data: DispatchSource.MachSendEvent { .init(rawValue: __dispatch_source_get_data(self as! DispatchSource)) }
    public var mask: DispatchSource.MachSendEvent { .init(rawValue: __dispatch_source_get_mask(self as! DispatchSource)) }
}

extension DispatchSourceMachReceive {
    public var handle: mach_port_t { mach_port_t(__dispatch_source_get_handle(self as! DispatchSource)) }
}

extension DispatchSourceMemoryPressure {
    public var data: DispatchSource.MemoryPressureEvent { .init(rawValue: __dispatch_source_get_data(self as! DispatchSource)) }
    public var mask: DispatchSource.MemoryPressureEvent { .init(rawValue: __dispatch_source_get_mask(self as! DispatchSource)) }
}

extension DispatchSourceProcess {
    public var handle: pid_t { pid_t(__dispatch_source_get_handle(self as! DispatchSource)) }
    public var data: DispatchSource.ProcessEvent { .init(rawValue: __dispatch_source_get_data(self as! DispatchSource)) }
    public var mask: DispatchSource.ProcessEvent { .init(rawValue: __dispatch_source_get_mask(self as! DispatchSource)) }
}

/// A timer's interval or leeway in nanoseconds: never is forever.
private func timerNanoseconds(_ interval: DispatchTimeInterval) -> UInt64 {
    interval == .never ? dispatchTimeForever : UInt64(max(0, interval.rawValue))
}

private func timerNanoseconds(_ seconds: Double) -> UInt64 {
    seconds.isInfinite || seconds.isNaN ? dispatchTimeForever : UInt64(max(0, (seconds * 1e9).rounded()))
}

extension DispatchSourceTimer {
    private var timer: DispatchSource { self as! DispatchSource }

    @available(swift, deprecated: 4, renamed: "schedule(deadline:repeating:leeway:)")
    public func scheduleOneshot(deadline: DispatchTime, leeway: DispatchTimeInterval = .nanoseconds(0)) {
        __dispatch_source_set_timer(timer, deadline.rawValue, dispatchTimeForever, timerNanoseconds(leeway))
    }

    @available(swift, deprecated: 4, renamed: "schedule(wallDeadline:repeating:leeway:)")
    public func scheduleOneshot(wallDeadline: DispatchWallTime, leeway: DispatchTimeInterval = .nanoseconds(0)) {
        __dispatch_source_set_timer(timer, wallDeadline.rawValue, dispatchTimeForever, timerNanoseconds(leeway))
    }

    @available(swift, deprecated: 4, renamed: "schedule(deadline:repeating:leeway:)")
    public func scheduleRepeating(deadline: DispatchTime, interval: DispatchTimeInterval, leeway: DispatchTimeInterval = .nanoseconds(0)) {
        __dispatch_source_set_timer(timer, deadline.rawValue, timerNanoseconds(interval), timerNanoseconds(leeway))
    }

    @available(swift, deprecated: 4, renamed: "schedule(deadline:repeating:leeway:)")
    public func scheduleRepeating(deadline: DispatchTime, interval: Double, leeway: DispatchTimeInterval = .nanoseconds(0)) {
        __dispatch_source_set_timer(timer, deadline.rawValue, timerNanoseconds(interval), timerNanoseconds(leeway))
    }

    @available(swift, deprecated: 4, renamed: "schedule(wallDeadline:repeating:leeway:)")
    public func scheduleRepeating(wallDeadline: DispatchWallTime, interval: DispatchTimeInterval, leeway: DispatchTimeInterval = .nanoseconds(0)) {
        __dispatch_source_set_timer(timer, wallDeadline.rawValue, timerNanoseconds(interval), timerNanoseconds(leeway))
    }

    @available(swift, deprecated: 4, renamed: "schedule(wallDeadline:repeating:leeway:)")
    public func scheduleRepeating(wallDeadline: DispatchWallTime, interval: Double, leeway: DispatchTimeInterval = .nanoseconds(0)) {
        __dispatch_source_set_timer(timer, wallDeadline.rawValue, timerNanoseconds(interval), timerNanoseconds(leeway))
    }

    @available(swift 4)
    public func schedule(deadline: DispatchTime, repeating interval: DispatchTimeInterval = .never, leeway: DispatchTimeInterval = .nanoseconds(0)) {
        __dispatch_source_set_timer(timer, deadline.rawValue, timerNanoseconds(interval), timerNanoseconds(leeway))
    }

    @available(swift 4)
    public func schedule(deadline: DispatchTime, repeating interval: Double, leeway: DispatchTimeInterval = .nanoseconds(0)) {
        __dispatch_source_set_timer(timer, deadline.rawValue, timerNanoseconds(interval), timerNanoseconds(leeway))
    }

    @available(swift 4)
    public func schedule(wallDeadline: DispatchWallTime, repeating interval: DispatchTimeInterval = .never, leeway: DispatchTimeInterval = .nanoseconds(0)) {
        __dispatch_source_set_timer(timer, wallDeadline.rawValue, timerNanoseconds(interval), timerNanoseconds(leeway))
    }

    @available(swift 4)
    public func schedule(wallDeadline: DispatchWallTime, repeating interval: Double, leeway: DispatchTimeInterval = .nanoseconds(0)) {
        __dispatch_source_set_timer(timer, wallDeadline.rawValue, timerNanoseconds(interval), timerNanoseconds(leeway))
    }
}

extension DispatchSourceFileSystemObject {
    public var handle: Int32 { Int32(truncatingIfNeeded: __dispatch_source_get_handle(self as! DispatchSource)) }
    public var data: DispatchSource.FileSystemEvent { .init(rawValue: __dispatch_source_get_data(self as! DispatchSource)) }
    public var mask: DispatchSource.FileSystemEvent { .init(rawValue: __dispatch_source_get_mask(self as! DispatchSource)) }
}

extension DispatchSourceUserDataAdd {
    public func add(data: UInt) { __dispatch_source_merge_data(self as! DispatchSource, data) }
}

extension DispatchSourceUserDataOr {
    public func or(data: UInt) { __dispatch_source_merge_data(self as! DispatchSource, data) }
}

extension DispatchSourceUserDataReplace {
    public func replace(data: UInt) { __dispatch_source_merge_data(self as! DispatchSource, data) }
}
