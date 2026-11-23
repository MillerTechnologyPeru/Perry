import Darwin

// DispatchQueue's Swift API: creating queues, running work on them
// synchronously and asynchronously, and the values set on them.

/// A key for a value set on a queue, the address of an instance.
public final class DispatchSpecificKey<T> {
    public init() {}
}

extension DispatchSpecificKey: Sendable where T: Sendable {}

/// What a queue keeps for a key: the value, boxed.
private final class SpecificBox<T> {
    let value: T
    init(_ value: T) { self.value = value }
}

// The synchronous submissions, which Swift's import of the headers makes
// methods that the overlay's own overload.
@_silgen_name("dispatch_sync")
private func dispatchSync(_ queue: DispatchQueue, _ block: _DispatchBlock)

@_silgen_name("dispatch_barrier_sync")
private func dispatchBarrierSync(_ queue: DispatchQueue, _ block: _DispatchBlock)

@_silgen_name("dispatch_async_and_wait")
private func dispatchAsyncAndWait(_ queue: DispatchQueue, _ block: _DispatchBlock)

/// Releases a value set on a queue when it is replaced or the queue goes.
private let releaseSpecific: @convention(c) (UnsafeMutableRawPointer?) -> Void = { context in
    if let context { Unmanaged<AnyObject>.fromOpaque(context).release() }
}

extension DispatchQueue {
    public struct Attributes: OptionSet, Sendable {
        public let rawValue: UInt64

        public init(rawValue: UInt64) {
            self.rawValue = rawValue
        }

        public static let concurrent = Attributes(rawValue: 1 << 1)
        @available(macOS 10.12, iOS 10.0, tvOS 10.0, watchOS 3.0, *)
        public static let initiallyInactive = Attributes(rawValue: 1 << 2)

        /// The C attribute these attributes make, from `base`.
        func attribute(_ base: __OS_dispatch_queue_attr?) -> __OS_dispatch_queue_attr? {
            var attribute = base
            if contains(.initiallyInactive) { attribute = __dispatch_queue_attr_make_initially_inactive(attribute) }
            return attribute
        }
    }

    public enum GlobalQueuePriority: Sendable {
        @available(macOS, deprecated: 10.10, message: "Use qos attributes instead")
        @available(iOS, deprecated: 8.0, message: "Use qos attributes instead")
        @available(tvOS, deprecated, message: "Use qos attributes instead")
        @available(watchOS, deprecated, message: "Use qos attributes instead")
        case high
        @available(macOS, deprecated: 10.10, message: "Use qos attributes instead")
        @available(iOS, deprecated: 8.0, message: "Use qos attributes instead")
        @available(tvOS, deprecated, message: "Use qos attributes instead")
        @available(watchOS, deprecated, message: "Use qos attributes instead")
        case `default`
        @available(macOS, deprecated: 10.10, message: "Use qos attributes instead")
        @available(iOS, deprecated: 8.0, message: "Use qos attributes instead")
        @available(tvOS, deprecated, message: "Use qos attributes instead")
        @available(watchOS, deprecated, message: "Use qos attributes instead")
        case low
        @available(macOS, deprecated: 10.10, message: "Use qos attributes instead")
        @available(iOS, deprecated: 8.0, message: "Use qos attributes instead")
        @available(tvOS, deprecated, message: "Use qos attributes instead")
        @available(watchOS, deprecated, message: "Use qos attributes instead")
        case background

        /// DISPATCH_QUEUE_PRIORITY_HIGH, DEFAULT, LOW and BACKGROUND.
        var identifier: Int {
            switch self {
            case .high: return 2
            case .default: return 0
            case .low: return -2
            case .background: return Int(Int16.min)
            }
        }
    }

    public enum AutoreleaseFrequency: Sendable {
        case inherit
        @available(macOS 10.12, iOS 10.0, tvOS 10.0, watchOS 3.0, *)
        case workItem
        @available(macOS 10.12, iOS 10.0, tvOS 10.0, watchOS 3.0, *)
        case never

        /// The C attribute with this frequency, from `base`.
        func attribute(_ base: __OS_dispatch_queue_attr?) -> __OS_dispatch_queue_attr? {
            switch self {
            case .inherit: return base
            // DISPATCH_AUTORELEASE_FREQUENCY_WORK_ITEM and _NEVER, which Swift's
            // import of the headers doesn't name.
            case .workItem: return __dispatch_queue_attr_make_with_autorelease_frequency(base, __dispatch_autorelease_frequency_t(rawValue: 1)!)
            case .never: return __dispatch_queue_attr_make_with_autorelease_frequency(base, __dispatch_autorelease_frequency_t(rawValue: 2)!)
            }
        }
    }

    @preconcurrency
    public class func concurrentPerform(iterations: Int, execute work: @Sendable (Int) -> Void) {
        withoutActuallyEscaping(work) { work in
            __dispatch_apply(iterations, nil, work)
        }
    }

    public class var main: DispatchQueue {
        mainQueue()
    }

    @available(macOS, deprecated: 10.10)
    @available(iOS, deprecated: 8.0)
    @available(tvOS, deprecated)
    @available(watchOS, deprecated)
    public class func global(priority: GlobalQueuePriority) -> DispatchQueue {
        __dispatch_get_global_queue(priority.identifier, 0)
    }

    @available(macOS 10.10, iOS 8.0, *)
    public class func global(qos: DispatchQoS.QoSClass = .default) -> DispatchQueue {
        __dispatch_get_global_queue(Int(qos.rawValue.rawValue), 0)
    }

    @preconcurrency
    public class func getSpecific<T>(key: DispatchSpecificKey<T>) -> T? where T: Sendable {
        let address = Unmanaged.passUnretained(key).toOpaque()
        guard let context = __dispatch_get_specific(address) else { return nil }
        return Unmanaged<SpecificBox<T>>.fromOpaque(context).takeUnretainedValue().value
    }

    public convenience init(label: String, qos: DispatchQoS = .unspecified, attributes: Attributes = [],
                            autoreleaseFrequency: AutoreleaseFrequency = .inherit, target: DispatchQueue? = nil) {
        var attribute: __OS_dispatch_queue_attr? = attributes.contains(.concurrent) ? concurrentAttribute() : nil
        attribute = attributes.attribute(attribute)
        attribute = autoreleaseFrequency.attribute(attribute)
        if qos != .unspecified {
            attribute = __dispatch_queue_attr_make_with_qos_class(attribute, qos.qosClass.rawValue, Int32(qos.relativePriority))
        }
        self.init(__label: label, attr: attribute, queue: target)
    }

    public var label: String {
        String(cString: __dispatch_queue_get_label(self))
    }

    @available(macOS 10.10, iOS 8.0, *)
    public func sync(execute workItem: DispatchWorkItem) {
        dispatchSync(self, workItem._block)
    }

    @available(macOS 10.10, iOS 8.0, *)
    public func async(execute workItem: DispatchWorkItem) {
        __dispatch_async(self, workItem._block)
    }

    @available(macOS 10.14, iOS 12.0, *)
    public func asyncAndWait(execute workItem: DispatchWorkItem) {
        dispatchAsyncAndWait(self, workItem._block)
    }

    @available(macOS 10.10, iOS 8.0, *)
    public func async(group: DispatchGroup, execute workItem: DispatchWorkItem) {
        __dispatch_group_async(group, self, workItem._block)
    }

    @available(macOS 14.0, iOS 17.0, tvOS 17.0, watchOS 10.0, *)
    public func asyncUnsafe(group: DispatchGroup? = nil, qos: DispatchQoS = .unspecified, flags: DispatchWorkItemFlags = [],
                            execute work: @escaping @convention(block) () -> Void) {
        submit(group: group, qos: qos, flags: flags, work)
    }

    @preconcurrency
    public func async(group: DispatchGroup? = nil, qos: DispatchQoS = .unspecified, flags: DispatchWorkItemFlags = [],
                      execute work: @escaping @Sendable @convention(block) () -> Void) {
        submit(group: group, qos: qos, flags: flags, work)
    }

    /// Runs `work` asynchronously, in the group when there is one; a block
    /// with QoS or flags is wrapped as a work item's.
    private func submit(group: DispatchGroup?, qos: DispatchQoS, flags: DispatchWorkItemFlags, _ work: @escaping _DispatchBlock) {
        let block = qos == .unspecified && flags.isEmpty ? work : makeBlock(qos: qos, flags: flags, work)
        if let group {
            __dispatch_group_async(group, self, block)
        } else {
            __dispatch_async(self, block)
        }
    }

    @available(macOS 10.14, iOS 12.0, tvOS 12.0, watchOS 5.0, *)
    public func asyncAndWait<T>(execute work: () throws -> T) rethrows -> T {
        try runAndWait(flags: [], work, using: dispatchAsyncAndWait)
    }

    @available(macOS 10.14, iOS 12.0, tvOS 12.0, watchOS 5.0, *)
    public func asyncAndWait<T>(flags: DispatchWorkItemFlags, execute work: () throws -> T) rethrows -> T {
        try runAndWait(flags: flags, work, using: dispatchAsyncAndWait)
    }

    public func sync<T>(execute work: () throws -> T) rethrows -> T {
        try runAndWait(flags: [], work, using: dispatchSync)
    }

    public func sync<T>(flags: DispatchWorkItemFlags, execute work: () throws -> T) rethrows -> T {
        try runAndWait(flags: flags, work, using: flags == .barrier ? dispatchBarrierSync : dispatchSync)
    }

    /// Runs `work` on the queue and waits for it, with its result or error.
    private func runAndWait<T>(flags: DispatchWorkItemFlags, _ work: () throws -> T,
                               using submit: (DispatchQueue, @escaping _DispatchBlock) -> Void) rethrows -> T {
        var result: Result<T, Error>?
        return try withoutActuallyEscaping(work) { work in
            let run: _DispatchBlock = { result = Result { try work() } }
            let block = flags.isEmpty || flags == .barrier ? run : makeBlock(qos: .unspecified, flags: flags, run)
            submit(self, block)
            return try result!.get()
        }
    }

    @available(macOS 14.0, iOS 17.0, tvOS 17.0, watchOS 10.0, *)
    public func asyncAfterUnsafe(deadline: DispatchTime, qos: DispatchQoS = .unspecified, flags: DispatchWorkItemFlags = [],
                                 execute work: @escaping @convention(block) () -> Void) {
        after(deadline.rawValue, qos: qos, flags: flags, work)
    }

    @preconcurrency
    public func asyncAfter(deadline: DispatchTime, qos: DispatchQoS = .unspecified, flags: DispatchWorkItemFlags = [],
                           execute work: @escaping @Sendable @convention(block) () -> Void) {
        after(deadline.rawValue, qos: qos, flags: flags, work)
    }

    @available(macOS 14.0, iOS 17.0, tvOS 17.0, watchOS 10.0, *)
    public func asyncAfterUnsafe(wallDeadline: DispatchWallTime, qos: DispatchQoS = .unspecified, flags: DispatchWorkItemFlags = [],
                                 execute work: @escaping @convention(block) () -> Void) {
        after(wallDeadline.rawValue, qos: qos, flags: flags, work)
    }

    @preconcurrency
    public func asyncAfter(wallDeadline: DispatchWallTime, qos: DispatchQoS = .unspecified, flags: DispatchWorkItemFlags = [],
                           execute work: @escaping @Sendable @convention(block) () -> Void) {
        after(wallDeadline.rawValue, qos: qos, flags: flags, work)
    }

    private func after(_ time: dispatch_time_t, qos: DispatchQoS, flags: DispatchWorkItemFlags, _ work: @escaping _DispatchBlock) {
        let block = qos == .unspecified && flags.isEmpty ? work : makeBlock(qos: qos, flags: flags, work)
        __dispatch_after(time, self, block)
    }

    @available(macOS 10.10, iOS 8.0, *)
    public func asyncAfter(deadline: DispatchTime, execute: DispatchWorkItem) {
        __dispatch_after(deadline.rawValue, self, execute._block)
    }

    @available(macOS 10.10, iOS 8.0, *)
    public func asyncAfter(wallDeadline: DispatchWallTime, execute: DispatchWorkItem) {
        __dispatch_after(wallDeadline.rawValue, self, execute._block)
    }

    @available(macOS 10.10, iOS 8.0, *)
    public var qos: DispatchQoS {
        var relative: Int32 = 0
        let cls = __dispatch_queue_get_qos_class(self, &relative)
        return DispatchQoS(qosClass: DispatchQoS.QoSClass(rawValue: cls) ?? .unspecified, relativePriority: Int(relative))
    }

    @preconcurrency
    public func getSpecific<T>(key: DispatchSpecificKey<T>) -> T? where T: Sendable {
        let address = Unmanaged.passUnretained(key).toOpaque()
        guard let context = __dispatch_queue_get_specific(self, address) else { return nil }
        return Unmanaged<SpecificBox<T>>.fromOpaque(context).takeUnretainedValue().value
    }

    @preconcurrency
    public func setSpecific<T>(key: DispatchSpecificKey<T>, value: T?) where T: Sendable {
        let address = Unmanaged.passUnretained(key).toOpaque()
        let context = value.map { Unmanaged.passRetained(SpecificBox($0) as AnyObject).toOpaque() }
        __dispatch_queue_set_specific(self, address, context, releaseSpecific)
    }
}

@available(macOS 14.0, iOS 17.0, tvOS 17.0, watchOS 10.0, *)
extension DispatchSerialQueue {
    public struct Attributes: OptionSet, Sendable {
        public let rawValue: UInt64

        public init(rawValue: UInt64) {
            self.rawValue = rawValue
        }

        public static let initiallyInactive = Attributes(rawValue: 1 << 2)
    }

    public convenience init(label: String, qos: DispatchQoS = .unspecified, attributes: Attributes = [],
                            autoreleaseFrequency: DispatchQueue.AutoreleaseFrequency = .workItem, target: DispatchQueue? = nil) {
        var attribute = DispatchQueue.Attributes(rawValue: attributes.rawValue).attribute(nil)
        attribute = autoreleaseFrequency.attribute(attribute)
        if qos != .unspecified {
            attribute = __dispatch_queue_attr_make_with_qos_class(attribute, qos.qosClass.rawValue, Int32(qos.relativePriority))
        }
        self.init(__label: label, attr: attribute, queue: target)
    }
}

@available(macOS 14.0, iOS 17.0, tvOS 17.0, watchOS 10.0, *)
extension DispatchConcurrentQueue {
    public struct Attributes: OptionSet, Sendable {
        public let rawValue: UInt64

        public init(rawValue: UInt64) {
            self.rawValue = rawValue
        }

        public static let initiallyInactive = Attributes(rawValue: 1 << 2)
    }

    public convenience init(label: String, qos: DispatchQoS = .unspecified, attributes: Attributes = [],
                            autoreleaseFrequency: DispatchQueue.AutoreleaseFrequency = .workItem, target: DispatchQueue? = nil) {
        var attribute = DispatchQueue.Attributes(rawValue: attributes.rawValue).attribute(concurrentAttribute())
        attribute = autoreleaseFrequency.attribute(attribute)
        if qos != .unspecified {
            attribute = __dispatch_queue_attr_make_with_qos_class(attribute, qos.qosClass.rawValue, Int32(qos.relativePriority))
        }
        self.init(__label: label, attr: attribute, queue: target)
    }
}

@available(macOS 14.0, iOS 17.0, tvOS 17.0, watchOS 10.0, *)
extension DispatchWorkloop {
    public struct Attributes: OptionSet, Sendable {
        public let rawValue: UInt64

        public init(rawValue: UInt64) {
            self.rawValue = rawValue
        }
    }

    public convenience init(label: String, attributes: Attributes = [],
                            autoreleaseFrequency: DispatchQueue.AutoreleaseFrequency = .workItem, osWorkgroup: WorkGroup? = nil) {
        self.init(__label: label)
        _ = attributes
        if let attribute = autoreleaseFrequency.attribute(nil) {
            _ = attribute
        }
        if let osWorkgroup { __dispatch_workloop_set_os_workgroup(self, osWorkgroup) }
    }
}

// The library's main queue and concurrent attribute are structures in its
// data, which Swift can't import; declared as functions, their names give
// their addresses, as dispatch_get_main_queue() and
// DISPATCH_QUEUE_CONCURRENT take them.
@_silgen_name("_dispatch_main_q")
private func mainQueueSymbol()

@_silgen_name("_dispatch_queue_attr_concurrent")
private func concurrentAttributeSymbol()

/// The main queue, dispatch_get_main_queue().
func mainQueue() -> DispatchQueue {
    let address: @convention(thin) () -> Void = mainQueueSymbol
    return unsafeBitCast(address, to: DispatchQueue.self)
}

/// DISPATCH_QUEUE_CONCURRENT.
func concurrentAttribute() -> __OS_dispatch_queue_attr {
    let address: @convention(thin) () -> Void = concurrentAttributeSymbol
    return unsafeBitCast(address, to: __OS_dispatch_queue_attr.self)
}
