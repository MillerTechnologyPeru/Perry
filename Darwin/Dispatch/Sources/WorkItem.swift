import Darwin

// Quality of service, work item flags and DispatchWorkItem: a block made
// with dispatch_block_create, which queues, groups and sources take.

public struct DispatchQoS: Equatable, Sendable {
    public let qosClass: QoSClass
    public let relativePriority: Int

    @available(macOS 10.10, iOS 8.0, *)
    public static let background = DispatchQoS(qosClass: .background, relativePriority: 0)
    @available(macOS 10.10, iOS 8.0, *)
    public static let utility = DispatchQoS(qosClass: .utility, relativePriority: 0)
    @available(macOS 10.10, iOS 8.0, *)
    public static let `default` = DispatchQoS(qosClass: .default, relativePriority: 0)
    @available(macOS 10.10, iOS 8.0, *)
    public static let userInitiated = DispatchQoS(qosClass: .userInitiated, relativePriority: 0)
    @available(macOS 10.10, iOS 8.0, *)
    public static let userInteractive = DispatchQoS(qosClass: .userInteractive, relativePriority: 0)
    public static let unspecified = DispatchQoS(qosClass: .unspecified, relativePriority: 0)

    public enum QoSClass: Sendable {
        @available(macOS 10.10, iOS 8.0, *)
        case background
        @available(macOS 10.10, iOS 8.0, *)
        case utility
        @available(macOS 10.10, iOS 8.0, *)
        case `default`
        @available(macOS 10.10, iOS 8.0, *)
        case userInitiated
        @available(macOS 10.10, iOS 8.0, *)
        case userInteractive
        case unspecified

        @available(macOS 10.10, iOS 8.0, *)
        public init?(rawValue: qos_class_t) {
            switch rawValue {
            case QOS_CLASS_BACKGROUND: self = .background
            case QOS_CLASS_UTILITY: self = .utility
            case QOS_CLASS_DEFAULT: self = .default
            case QOS_CLASS_USER_INITIATED: self = .userInitiated
            case QOS_CLASS_USER_INTERACTIVE: self = .userInteractive
            case QOS_CLASS_UNSPECIFIED: self = .unspecified
            default: return nil
            }
        }

        @available(macOS 10.10, iOS 8.0, *)
        public var rawValue: qos_class_t {
            switch self {
            case .background: return QOS_CLASS_BACKGROUND
            case .utility: return QOS_CLASS_UTILITY
            case .default: return QOS_CLASS_DEFAULT
            case .userInitiated: return QOS_CLASS_USER_INITIATED
            case .userInteractive: return QOS_CLASS_USER_INTERACTIVE
            case .unspecified: return QOS_CLASS_UNSPECIFIED
            }
        }
    }

    public init(qosClass: QoSClass, relativePriority: Int) {
        self.qosClass = qosClass
        self.relativePriority = relativePriority
    }

    public static func == (a: DispatchQoS, b: DispatchQoS) -> Bool {
        a.qosClass == b.qosClass && a.relativePriority == b.relativePriority
    }
}

@frozen public enum DispatchTimeoutResult: Sendable {
    case success
    case timedOut
}

public struct DispatchWorkItemFlags: OptionSet, RawRepresentable, Sendable {
    public let rawValue: UInt

    public init(rawValue: UInt) {
        self.rawValue = rawValue
    }

    // dispatch_block_flags_t's bits.
    public static let barrier = DispatchWorkItemFlags(rawValue: 0x1)
    @available(macOS 10.10, iOS 8.0, *)
    public static let detached = DispatchWorkItemFlags(rawValue: 0x2)
    @available(macOS 10.10, iOS 8.0, *)
    public static let assignCurrentContext = DispatchWorkItemFlags(rawValue: 0x4)
    @available(macOS 10.10, iOS 8.0, *)
    public static let noQoS = DispatchWorkItemFlags(rawValue: 0x8)
    @available(macOS 10.10, iOS 8.0, *)
    public static let inheritQoS = DispatchWorkItemFlags(rawValue: 0x10)
    @available(macOS 10.10, iOS 8.0, *)
    public static let enforceQoS = DispatchWorkItemFlags(rawValue: 0x20)
}

public typealias _DispatchBlock = @convention(block) () -> Void

// The block functions, which Swift's import of the headers leaves out in
// favor of DispatchWorkItem.
@_silgen_name("dispatch_block_create")
private func dispatchBlockCreate(_ flags: UInt, _ block: _DispatchBlock) -> _DispatchBlock

@_silgen_name("dispatch_block_create_with_qos_class")
private func dispatchBlockCreate(_ flags: UInt, _ qos: UInt32, _ relativePriority: Int32, _ block: _DispatchBlock) -> _DispatchBlock

@_silgen_name("dispatch_block_wait")
private func dispatchBlockWait(_ block: _DispatchBlock, _ timeout: dispatch_time_t) -> Int

@_silgen_name("dispatch_block_notify")
private func dispatchBlockNotify(_ block: _DispatchBlock, _ queue: DispatchQueue, _ notification: _DispatchBlock)

@_silgen_name("dispatch_block_cancel")
private func dispatchBlockCancel(_ block: _DispatchBlock)

@_silgen_name("dispatch_block_testcancel")
private func dispatchBlockTestCancel(_ block: _DispatchBlock) -> Int

/// A block with flags, made with QoS when it has one.
func makeBlock(qos: DispatchQoS, flags: DispatchWorkItemFlags, _ block: @escaping _DispatchBlock) -> _DispatchBlock {
    if qos == .unspecified {
        return dispatchBlockCreate(flags.rawValue, block)
    }
    return dispatchBlockCreate(flags.rawValue, qos.qosClass.rawValue.rawValue, Int32(qos.relativePriority), block)
}

@available(macOS 10.10, iOS 8.0, *)
@_objcRuntimeName(_TtC8Dispatch17_DispatchWorkItem)
public class DispatchWorkItem {
    /// The block dispatch runs, as dispatch_block_create made it.
    internal var _block: _DispatchBlock

    public init(qos: DispatchQoS = .unspecified, flags: DispatchWorkItemFlags = [], block: @escaping @convention(block) () -> Void) {
        _block = makeBlock(qos: qos, flags: flags, block)
    }

    @available(macOS 11.3, iOS 14.5, watchOS 7.4, tvOS 14.5, *)
    public init(flags: DispatchWorkItemFlags = [], block: @escaping @convention(block) () -> Void) {
        _block = dispatchBlockCreate(flags.rawValue, block)
    }

    public func perform() {
        _block()
    }

    public func wait() {
        _ = dispatchBlockWait(_block, dispatchTimeForever)
    }

    public func wait(timeout: DispatchTime) -> DispatchTimeoutResult {
        dispatchBlockWait(_block, timeout.rawValue) == 0 ? .success : .timedOut
    }

    public func wait(wallTimeout: DispatchWallTime) -> DispatchTimeoutResult {
        dispatchBlockWait(_block, wallTimeout.rawValue) == 0 ? .success : .timedOut
    }

    public func notify(qos: DispatchQoS = .unspecified, flags: DispatchWorkItemFlags = [], queue: DispatchQueue,
                       execute: @escaping @convention(block) () -> Void) {
        let notification = qos == .unspecified && flags.isEmpty ? execute : makeBlock(qos: qos, flags: flags, execute)
        dispatchBlockNotify(_block, queue, notification)
    }

    public func notify(queue: DispatchQueue, execute: DispatchWorkItem) {
        dispatchBlockNotify(_block, queue, execute._block)
    }

    public func cancel() {
        dispatchBlockCancel(_block)
    }

    public var isCancelled: Bool {
        dispatchBlockTestCancel(_block) != 0
    }
}
