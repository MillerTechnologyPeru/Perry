import os.log
import os.signpost

// os_log in Swift: the log handles and types, the printf-style os_log
// functions of the Swift 5 overlay, os_log with an OSLogMessage, and
// Logger. Everything is written through _os_log_impl.

// MARK: The C library's log calls and handles

@_silgen_name("_os_log_impl")
internal func osLogImpl(_ dso: UnsafeRawPointer?, _ log: OSLog, _ type: OSLogType, _ format: UnsafePointer<CChar>,
                        _ buffer: UnsafeMutablePointer<UInt8>, _ size: UInt32)

@_silgen_name("os_log_create")
private func createLog(_ subsystem: UnsafePointer<CChar>, _ category: UnsafePointer<CChar>) -> OSLog

@_silgen_name("os_signpost_enabled")
private func signpostsEnabledFor(_ log: OSLog) -> Bool

@_silgen_name("os_log_type_enabled")
internal func logTypeEnabled(_ log: OSLog, _ type: OSLogType) -> Bool

// OS_LOG_DEFAULT and OS_LOG_DISABLED, macros over the addresses of
// structures the headers leave incomplete.
@_silgen_name("_os_log_default") private func defaultLogSymbol()
@_silgen_name("_os_log_disabled") private func disabledLogSymbol()

private let defaultLog = unsafeBitCast(defaultLogSymbol as @convention(thin) () -> Void, to: OSLog.self)
private let disabledLog = unsafeBitCast(disabledLogSymbol as @convention(thin) () -> Void, to: OSLog.self)

/// The image this overlay is, for the calls a caller's own image can't be
/// named in.
internal var overlayHandle: UnsafeRawPointer {
    UnsafeRawPointer(#dsohandle)
}

// MARK: Types and handles

extension OSLogType {
    public static var `default`: OSLogType { OSLogType(rawValue: 0x00) }
    public static var info: OSLogType { OSLogType(rawValue: 0x01) }
    public static var debug: OSLogType { OSLogType(rawValue: 0x02) }
    public static var error: OSLogType { OSLogType(rawValue: 0x10) }
    public static var fault: OSLogType { OSLogType(rawValue: 0x11) }
}

public var OS_LOG_TYPE_DEFAULT: OSLogType { .default }
public var OS_LOG_TYPE_INFO: OSLogType { .info }
public var OS_LOG_TYPE_DEBUG: OSLogType { .debug }
public var OS_LOG_TYPE_ERROR: OSLogType { .error }
public var OS_LOG_TYPE_FAULT: OSLogType { .fault }

extension OSLog: @unchecked Sendable {
    public static var disabled: OSLog { disabledLog }

    public static var `default`: OSLog { defaultLog }

    public convenience init(subsystem: String, category: String) {
        self.init(__subsystem: subsystem, category: category)
    }

    /// A category with a meaning of its own to the system's tools.
    public struct Category: Sendable {
        public let rawValue: String

        fileprivate init(_ rawValue: String) {
            self.rawValue = rawValue
        }

        /// Signposts for Instruments' Points of Interest.
        public static var pointsOfInterest: Category { Category("PointsOfInterest") }

        public static var dynamicTracing: Category { Category("DynamicTracing") }

        public static var dynamicStackTracing: Category { Category("DynamicStackTracing") }
    }

    public convenience init(subsystem: String, category: Category) {
        self.init(__subsystem: subsystem, category: category.rawValue)
    }

    public var signpostsEnabled: Bool {
        signpostsEnabledFor(self)
    }
}

// MARK: printf-style logging

/// Logs a printf-style message, if the log has its type enabled.
private func logFormat(_ message: StaticString, dso: UnsafeRawPointer?, log: OSLog, type: OSLogType, _ args: [any CVarArg]) {
    guard logTypeEnabled(log, type) else { return }
    withCString(message) { format in
        LegacyArguments(format: format, arguments: args).withBuffer { buffer, size in
            osLogImpl(dso, log, type, format, buffer, size)
        }
    }
}

public func os_log(_ type: OSLogType, dso: UnsafeRawPointer = #dsohandle, log: OSLog = .default,
                   _ message: StaticString, _ args: any CVarArg...) {
    logFormat(message, dso: dso, log: log, type: type, args)
}

public func os_log(_ message: StaticString, dso: UnsafeRawPointer? = #dsohandle, log: OSLog = .default,
                   type: OSLogType = .default, _ args: any CVarArg...) {
    logFormat(message, dso: dso, log: log, type: type, args)
}

// MARK: OSLogMessage

/// Writes a message's buffer and logs it, if the log has the type enabled.
internal func log(_ message: OSLogMessage, to log: OSLog, type: OSLogType) {
    guard logTypeEnabled(log, type) else { return }
    message.withBuffer { format, buffer, size in
        osLogImpl(overlayHandle, log, type, format, buffer, size)
    }
}

@_disfavoredOverload
public func os_log(_ logLevel: OSLogType = .default, log logObject: OSLog = .default, _ message: OSLogMessage) {
    log(message, to: logObject, type: logLevel)
}

// MARK: Logger

/// A value that holds a log handle and logs OSLogMessages to it.
@available(macOS 11.0, iOS 14.0, watchOS 7.0, tvOS 14.0, *)
public struct Logger: @unchecked Sendable {
    @usableFromInline
    internal let logObject: OSLog

    public static var disabled: Logger { Logger(.disabled) }

    public init(subsystem: String, category: String) {
        logObject = subsystem.withCString { subsystem in
            category.withCString { createLog(subsystem, $0) }
        }
    }

    public init() {
        logObject = .default
    }

    public init(_ logObj: OSLog) {
        logObject = logObj
    }

    public func isEnabled(type: OSLogType) -> Bool {
        logTypeEnabled(logObject, type)
    }

    public func log(_ message: OSLogMessage) { os.log(message, to: logObject, type: .default) }
    public func log(level: OSLogType, _ message: OSLogMessage) { os.log(message, to: logObject, type: level) }
    public func trace(_ message: OSLogMessage) { os.log(message, to: logObject, type: .debug) }
    public func debug(_ message: OSLogMessage) { os.log(message, to: logObject, type: .debug) }
    public func info(_ message: OSLogMessage) { os.log(message, to: logObject, type: .info) }
    public func notice(_ message: OSLogMessage) { os.log(message, to: logObject, type: .default) }
    public func warning(_ message: OSLogMessage) { os.log(message, to: logObject, type: .error) }
    public func error(_ message: OSLogMessage) { os.log(message, to: logObject, type: .error) }
    public func critical(_ message: OSLogMessage) { os.log(message, to: logObject, type: .fault) }
    public func fault(_ message: OSLogMessage) { os.log(message, to: logObject, type: .fault) }
}
