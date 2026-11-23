import os.log
import os.signpost

// Signposts: their types and identifiers, the os_signpost functions of the
// Swift 5 overlay and their animation variants, and OSSignposter with the
// interval state its intervals hand from beginning to end.

@_silgen_name("_os_signpost_emit_with_name_impl")
private func emitSignpost(_ dso: UnsafeRawPointer?, _ log: OSLog, _ type: OSSignpostType, _ id: os_signpost_id_t,
                          _ name: UnsafePointer<CChar>, _ format: UnsafePointer<CChar>,
                          _ buffer: UnsafeMutablePointer<UInt8>, _ size: UInt32)

@_silgen_name("os_signpost_id_generate")
private func generateSignpostID(_ log: OSLog) -> os_signpost_id_t

@_silgen_name("os_signpost_id_make_with_pointer")
private func signpostID(_ log: OSLog, _ pointer: UnsafeRawPointer?) -> os_signpost_id_t

/// Emits a signpost whose format and arguments are already a buffer.
private func emit(dso: UnsafeRawPointer?, log: OSLog, type: OSSignpostType, id: OSSignpostID, name: StaticString,
                  format: UnsafePointer<CChar>, buffer: UnsafeMutablePointer<UInt8>, size: UInt32) {
    withCString(name) { name in
        emitSignpost(dso, log, type, id.rawValue, name, format, buffer, size)
    }
}

/// Emits a signpost with a printf format and its arguments.
private func emit(dso: UnsafeRawPointer?, log: OSLog, type: OSSignpostType, id: OSSignpostID, name: StaticString,
                  format: UnsafePointer<CChar>, arguments: [any CVarArg]) {
    guard log.signpostsEnabled else { return }
    LegacyArguments(format: format, arguments: arguments).withBuffer { buffer, size in
        emit(dso: dso, log: log, type: type, id: id, name: name, format: format, buffer: buffer, size: size)
    }
}

// MARK: Types and identifiers

extension OSSignpostType {
    public static var event: OSSignpostType { OSSignpostType(rawValue: 0) }
    public static var begin: OSSignpostType { OSSignpostType(rawValue: 1) }
    public static var end: OSSignpostType { OSSignpostType(rawValue: 2) }
}

@available(macOS 10.14, iOS 12.0, watchOS 5.0, tvOS 12.0, *)
public struct OSSignpostID: Sendable {
    public let rawValue: os_signpost_id_t

    /// OS_SIGNPOST_ID_EXCLUSIVE: the one interval of its name at a time.
    public static var exclusive: OSSignpostID { OSSignpostID(0xEEEE_B0B5_B2B2_EEEE) }

    /// OS_SIGNPOST_ID_INVALID.
    public static var invalid: OSSignpostID { OSSignpostID(~0) }

    /// OS_SIGNPOST_ID_NULL.
    public static var null: OSSignpostID { OSSignpostID(0) }

    /// A new identifier, unique in the log.
    public init(log: OSLog) {
        rawValue = generateSignpostID(log)
    }

    /// The identifier an object's address makes.
    public init(log: OSLog, object: AnyObject) {
        rawValue = signpostID(log, UnsafeRawPointer(Unmanaged.passUnretained(object).toOpaque()))
    }

    public init(_ value: UInt64) {
        rawValue = value
    }
}

extension OSSignpostID: Comparable {
    public static func < (a: OSSignpostID, b: OSSignpostID) -> Bool {
        a.rawValue < b.rawValue
    }

    public static func == (a: OSSignpostID, b: OSSignpostID) -> Bool {
        a.rawValue == b.rawValue
    }
}

// MARK: os_signpost

public func os_signpost(_ type: OSSignpostType, dso: UnsafeRawPointer = #dsohandle, log: OSLog, name: StaticString,
                        signpostID: OSSignpostID = .exclusive) {
    guard log.signpostsEnabled else { return }
    var buffer: [UInt8] = [0, 0]
    buffer.withUnsafeMutableBufferPointer { buffer in
        "".withCString { format in
            emit(dso: dso, log: log, type: type, id: signpostID, name: name, format: format,
                 buffer: buffer.baseAddress!, size: UInt32(buffer.count))
        }
    }
}

public func os_signpost(_ type: OSSignpostType, dso: UnsafeRawPointer = #dsohandle, log: OSLog, name: StaticString,
                        signpostID: OSSignpostID = .exclusive, _ format: StaticString, _ arguments: any CVarArg...) {
    withCString(format) { format in
        emit(dso: dso, log: log, type: type, id: signpostID, name: name, format: format, arguments: arguments)
    }
}

// MARK: Animation intervals

/// The beginning of an animation interval, which Instruments marks.
public enum OSSignpostAnimationBegin {
    case animationBegin
}

extension OSSignpostAnimationBegin: Equatable, Hashable {}

/// Interns format strings, which a signpost's caller may keep the address
/// of: each is copied once and never freed.
private let internedFormats = InternedStrings()

private final class InternedStrings: @unchecked Sendable {
    private var strings: [String: UnsafePointer<CChar>] = [:]
    private var lock = os_unfair_lock()

    func pointer(_ string: String) -> UnsafePointer<CChar> {
        os_unfair_lock_lock(&lock)
        defer { os_unfair_lock_unlock(&lock) }
        if let pointer = strings[string] { return pointer }
        let pointer = UnsafePointer(strdup(string)!)
        strings[string] = pointer
        return pointer
    }
}

internal func internedCString(_ string: String) -> UnsafePointer<CChar> {
    internedFormats.pointer(string)
}

public enum AnimationFormatString {
    /// A format string marked as an animation's.
    @usableFromInline
    internal static func constructOSLogInterpolation(_ formatString: String) -> OSLogInterpolation {
        var interpolation = OSLogInterpolation(literalCapacity: 1, interpolationCount: 0)
        interpolation.formatString += formatString
        interpolation.formatString += " isAnimation=YES"
        return interpolation
    }

    /// A literal format string, for os_signpost(.animationBegin, …).
    @frozen public struct OSLogMessage: ExpressibleByStringLiteral {
        @usableFromInline
        internal var formatStringPointer: UnsafePointer<CChar>

        public init(stringLiteral value: String) {
            formatStringPointer = internedCString(constructOSLogInterpolation(value).formatString)
        }

        public typealias ExtendedGraphemeClusterLiteralType = String
        public typealias StringLiteralType = String
        public typealias UnicodeScalarLiteralType = String
    }
}

extension AnimationFormatString.OSLogMessage: BitwiseCopyable {}

/// Begins an animation interval with a format string already marked.
@usableFromInline
internal func animationBeginSignpostHelper(dso: UnsafeRawPointer, log: OSLog, name: StaticString, signpostID: OSSignpostID,
                                           formatStringPointer: UnsafePointer<CChar>, arguments: [any CVarArg]) {
    emit(dso: dso, log: log, type: .begin, id: signpostID, name: name, format: formatStringPointer, arguments: arguments)
}

public func os_signpost(_ animationBegin: OSSignpostAnimationBegin, dso: UnsafeRawPointer = #dsohandle, log: OSLog,
                        name: StaticString, signpostID: OSSignpostID = .exclusive,
                        _ format: AnimationFormatString.OSLogMessage, _ arguments: any CVarArg...) {
    animationBeginSignpostHelper(dso: dso, log: log, name: name, signpostID: signpostID,
                                 formatStringPointer: format.formatStringPointer, arguments: arguments)
}

public func os_signpost(_ animationBegin: OSSignpostAnimationBegin, dso: UnsafeRawPointer = #dsohandle, log: OSLog,
                        name: StaticString, signpostID: OSSignpostID = .exclusive) {
    animationBeginSignpostHelper(dso: dso, log: log, name: name, signpostID: signpostID,
                                 formatStringPointer: internedCString("isAnimation=YES"), arguments: [])
}

// MARK: OSSignposter

public typealias SignpostMetadata = OSLogMessage

@available(macOS 12.0, iOS 15.0, watchOS 8.0, tvOS 15.0, *)
public struct OSSignposter: @unchecked Sendable {
    @usableFromInline
    internal let logHandle: OSLog

    public var isEnabled: Bool { logHandle.signpostsEnabled }

    public static var disabled: OSSignposter { OSSignposter(logHandle: .disabled) }

    public init(subsystem: String, category: String) {
        logHandle = OSLog(subsystem: subsystem, category: category)
    }

    public init(subsystem: String, category: OSLog.Category) {
        logHandle = OSLog(subsystem: subsystem, category: category)
    }

    public init() {
        logHandle = .default
    }

    public init(logHandle: OSLog) {
        self.logHandle = logHandle
    }

    public init(logger: Logger) {
        logHandle = logger.logObject
    }

    /// Emits a signpost with a message, unless it ends an interval that has
    /// ended already, when it emits the error in its place.
    private func signpost(_ message: SignpostMetadata?, name: StaticString, id: OSSignpostID, type: OSSignpostType,
                          state: OSSignpostIntervalState?, transform: (String) -> String = { $0 }) {
        guard logHandle.signpostsEnabled else { return }
        let message = message ?? ""
        if let state, checkForErrorAndConsumeState(state: state) == .doubleEnd {
            var buffer: [UInt8] = [0, 0]
            buffer.withUnsafeMutableBufferPointer { buffer in
                "[Error] Interval already ended".withCString { format in
                    emit(dso: overlayHandle, log: logHandle, type: type, id: id, name: name, format: format,
                         buffer: buffer.baseAddress!, size: UInt32(buffer.count))
                }
            }
            return
        }
        message.withBuffer(formatString: transform(message.interpolation.formatString)) { format, buffer, size in
            emit(dso: overlayHandle, log: logHandle, type: type, id: id, name: name, format: format, buffer: buffer, size: size)
        }
    }

    public func emitEvent(_ name: StaticString, id: OSSignpostID = .exclusive, _ message: SignpostMetadata) {
        signpost(message, name: name, id: id, type: .event, state: nil)
    }

    public func emitEvent(_ name: StaticString, id: OSSignpostID = .exclusive) {
        signpost(nil, name: name, id: id, type: .event, state: nil)
    }

    public func beginInterval(_ name: StaticString, id: OSSignpostID = .exclusive, _ message: SignpostMetadata) -> OSSignpostIntervalState {
        signpost(message, name: name, id: id, type: .begin, state: nil)
        return OSSignpostIntervalState(id: id)
    }

    public func beginInterval(_ name: StaticString, id: OSSignpostID = .exclusive) -> OSSignpostIntervalState {
        signpost(nil, name: name, id: id, type: .begin, state: nil)
        return OSSignpostIntervalState(id: id)
    }

    public func beginAnimationInterval(_ name: StaticString, id: OSSignpostID = .exclusive) -> OSSignpostIntervalState {
        signpost("isAnimation=YES", name: name, id: id, type: .begin, state: nil)
        return OSSignpostIntervalState(id: id)
    }

    public func beginAnimationInterval(_ name: StaticString, id: OSSignpostID = .exclusive,
                                       _ message: SignpostMetadata) -> OSSignpostIntervalState {
        signpost(message, name: name, id: id, type: .begin, state: nil) { $0 + " isAnimation=YES" }
        return OSSignpostIntervalState(id: id)
    }

    public func endInterval(_ name: StaticString, _ state: OSSignpostIntervalState, _ message: SignpostMetadata) {
        signpost(message, name: name, id: state.signpostID, type: .end, state: state)
    }

    public func endInterval(_ name: StaticString, _ state: OSSignpostIntervalState) {
        signpost(nil, name: name, id: state.signpostID, type: .end, state: state)
    }

    public func withIntervalSignpost<T>(_ name: StaticString, id: OSSignpostID = .exclusive, _ message: SignpostMetadata,
                                        around task: () throws -> T) rethrows -> T {
        signpost(message, name: name, id: id, type: .begin, state: nil)
        defer { signpost(message, name: name, id: id, type: .end, state: nil) }
        return try task()
    }

    public func withIntervalSignpost<T>(_ name: StaticString, id: OSSignpostID = .exclusive,
                                        around task: () throws -> T) rethrows -> T {
        signpost(nil, name: name, id: id, type: .begin, state: nil)
        defer { signpost(nil, name: name, id: id, type: .end, state: nil) }
        return try task()
    }

    public func makeSignpostID() -> OSSignpostID {
        OSSignpostID(log: logHandle)
    }

    public func makeSignpostID(from object: AnyObject) -> OSSignpostID {
        OSSignpostID(log: logHandle, object: object)
    }
}

// MARK: Interval state

@available(macOS 12.0, iOS 15.0, watchOS 8.0, tvOS 15.0, *)
@usableFromInline
internal enum OSSignpostError {
    case doubleEnd
    case none

    /// What a second end of an interval emits in its place.
    @_alwaysEmitIntoClient
    internal static var doubleEndErrorString: String {
        "[Error] Interval already ended"
    }
}

extension OSSignpostError: Equatable, Hashable {}

/// What an interval hands from its beginning to its end: its identifier,
/// and whether it is still open, so it ends once.
@available(macOS 12.0, iOS 15.0, watchOS 8.0, tvOS 15.0, *)
public class OSSignpostIntervalState: Codable, @unchecked Sendable {
    @usableFromInline
    internal final let signpostID: OSSignpostID
    private var isOpen: Bool
    private var lock = os_unfair_lock()

    @usableFromInline
    internal init(id: OSSignpostID, isOpen: Bool = true) {
        signpostID = id
        self.isOpen = isOpen
    }

    public static func beginState(id: OSSignpostID) -> OSSignpostIntervalState {
        OSSignpostIntervalState(id: id)
    }

    private enum CodingKeys: String, CodingKey {
        case signpostID
        case isOpen
    }

    public required init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        signpostID = OSSignpostID(try container.decode(UInt64.self, forKey: .signpostID))
        isOpen = try container.decode(Bool.self, forKey: .isOpen)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(signpostID.rawValue, forKey: .signpostID)
        try container.encode(isOpen, forKey: .isOpen)
    }

    public func _hasValue(id: OSSignpostID, isOpen: Bool) -> Bool {
        signpostID.rawValue == id.rawValue && self.isOpen == isOpen
    }

    /// Closes the interval, saying whether it was closed already.
    fileprivate func consume() -> OSSignpostError {
        os_unfair_lock_lock(&lock)
        defer { os_unfair_lock_unlock(&lock) }
        guard isOpen else { return .doubleEnd }
        isOpen = false
        return .none
    }
}

@available(macOS 12.0, iOS 15.0, watchOS 8.0, tvOS 15.0, *)
@usableFromInline
internal func checkForErrorAndConsumeState(state: OSSignpostIntervalState) -> OSSignpostError {
    state.consume()
}
