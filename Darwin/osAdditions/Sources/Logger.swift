import os.log
import os.signpost
import os.lock
import Darwin

// Logger and OSSignposter: values that hold an os_log handle. Their
// logging methods are transparent in the SDK, compiled into callers, and
// read the handle through the getters here.

@available(macOS 11.0, iOS 14.0, watchOS 7.0, tvOS 14.0, *)
public struct Logger: @unchecked Sendable {
    @usableFromInline
    internal let logObject: OSLog

    public static var disabled: Logger { Logger(disabledLog) }

    public init(subsystem: String, category: String) {
        logObject = createLog(subsystem, category)
    }

    public init() {
        logObject = defaultLog
    }

    public init(_ logObj: OSLog) {
        logObject = logObj
    }

    public func isEnabled(type: OSLogType) -> Bool {
        logObject.isEnabled(type: type)
    }
}

@available(macOS 12.0, iOS 15.0, watchOS 8.0, tvOS 15.0, *)
public struct OSSignposter: @unchecked Sendable {
    @usableFromInline
    internal let logHandle: OSLog

    public var isEnabled: Bool { signpostsEnabled(logHandle) }

    public static var disabled: OSSignposter { OSSignposter(logHandle: disabledLog) }

    public init(subsystem: String, category: String) {
        logHandle = createLog(subsystem, category)
    }

    public init() {
        logHandle = defaultLog
    }

    public init(logHandle: OSLog) {
        self.logHandle = logHandle
    }

    public init(logger: Logger) {
        logHandle = logger.logObject
    }
}

/// OS_LOG_DEFAULT and OS_LOG_DISABLED, which are macros over the addresses
/// of structures the headers leave incomplete.
private let defaultLog = unsafeBitCast(dlsym(UnsafeMutableRawPointer(bitPattern: -2), "_os_log_default"), to: OSLog.self)
private let disabledLog = unsafeBitCast(dlsym(UnsafeMutableRawPointer(bitPattern: -2), "_os_log_disabled"), to: OSLog.self)

/// os_log_create and os_signpost_enabled, which the headers give Swift
/// under other names or not at all.
@_silgen_name("os_log_create")
private func createLog(_ subsystem: UnsafePointer<CChar>, _ category: UnsafePointer<CChar>) -> OSLog

@_silgen_name("os_signpost_enabled")
private func signpostsEnabled(_ log: OSLog) -> Bool
