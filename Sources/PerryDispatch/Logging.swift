import CPerryDispatch
import Glibc
import PerryObjCInterop

// Unified logging (libsystem_trace, which libSystem re-exports): os_log_t
// and os_activity_t are OS objects, as dispatch's are. Logs live as long as
// the process, one per subsystem and category. A message's arguments come
// in the buffer clang builds for _os_log_impl, which this reads against the
// format string; Linux has no unified log, so messages at the levels Darwin
// keeps by default (all but debug) go to standard error, NSLog-style.

@ObjCProtocol("OS_os_log")
protocol OSLogProtocol: OSObjectProtocol {}

@ObjCProtocol("OS_os_activity")
protocol OSActivityProtocol: OSObjectProtocol {}

/// A log: its subsystem and category, or neither for OS_LOG_DEFAULT.
final class LogState {
    let subsystem: String?
    let category: String?
    let disabled: Bool

    init(subsystem: String?, category: String?, disabled: Bool = false) {
        self.subsystem = subsystem
        self.category = category
        self.disabled = disabled
    }
}

@ObjCClass("OS_os_log")
open class OSLog: OSObject, OSLogProtocol {
    @ObjCMethod("retain") func retain() -> UnsafeMutableRawPointer { objcObject }
    @ObjCMethod("release", types: "Vv16@0:8") func release() {}
    @ObjCMethod("autorelease") func autorelease() -> UnsafeMutableRawPointer { objcObject }
    @ObjCMethod("retainCount") func retainCount() -> UInt { UInt.max }
}

@ObjCClass("OS_os_activity")
open class OSActivity: OSObject, OSActivityProtocol {
    @ObjCMethod("dealloc")
    func dealloc() {
        Objects.destroy(objcObject, keepsState: true)
        ObjCRuntime.superDealloc(objcObject, definedOn: OSActivity.objCClass.pointer)
    }
}

/// An activity's identifier.
final class ActivityState {
    let identifier: UInt64
    let name: String

    init(identifier: UInt64, name: String) {
        self.identifier = identifier
        self.name = name
    }
}

enum Logging {
    static let lock = Lock()
    nonisolated(unsafe) static var logs: [String: Object] = [:]
    nonisolated(unsafe) static var nextIdentifier: UInt64 = 0
    /// The app's name, as NSLog's lines give it.
    nonisolated(unsafe) static var programName: String?

    /// os_log_type_t: default 0, info 1, debug 2, error 16, fault 17.
    static let info: UInt8 = 1, debug: UInt8 = 2, error: UInt8 = 16, fault: UInt8 = 17

    static func setUp() {
        let cls = OSLog.objCClass.pointer
        Objects.setUpStatic(perry_log_default(), cls, linux: nil)
        perry_log_default().storeBytes(of: Unmanaged.passRetained(LogState(subsystem: nil, category: nil)).toOpaque(),
                                       toByteOffset: 16, as: UnsafeMutableRawPointer.self)
        Objects.setUpStatic(perry_log_disabled(), cls, linux: nil)
        perry_log_disabled().storeBytes(of: Unmanaged.passRetained(LogState(subsystem: nil, category: nil, disabled: true)).toOpaque(),
                                        toByteOffset: 16, as: UnsafeMutableRawPointer.self)
        let activity = OSActivity.objCClass.pointer
        Objects.setUpStatic(perry_activity_current(), activity, linux: nil)
        Objects.setUpStatic(perry_activity_none(), activity, linux: nil)
    }

    static func state(_ log: Object?) -> LogState? { Objects.state(log, as: LogState.self) }

    static func next() -> UInt64 {
        lock.withLock {
            nextIdentifier += 1
            return nextIdentifier
        }
    }

    /// Darwin keeps info and above; debug only when configured to.
    static func isEnabled(_ log: Object?, _ type: UInt8) -> Bool {
        guard let state = state(log), !state.disabled else { return false }
        return type != debug
    }

    // MARK: Messages

    /// The arguments of an _os_log_impl buffer: a summary byte, a count,
    /// then per argument a descriptor (kind in the high nibble, privacy in
    /// the low), a size, and the bytes.
    struct Argument {
        let kind: UInt8
        let bytes: [UInt8]

        var integer: Int64 {
            var value: UInt64 = 0
            for (index, byte) in bytes.prefix(8).enumerated() { value |= UInt64(byte) << (8 * index) }
            if bytes.count < 8, bytes.count > 0, bytes.last! & 0x80 != 0 { value |= ~0 << (8 * bytes.count) }
            return Int64(bitPattern: value)
        }

        var pointer: UnsafeRawPointer? { UnsafeRawPointer(bitPattern: UInt(bitPattern: Int(integer))) }
    }

    static func arguments(_ buffer: UnsafePointer<UInt8>?, _ size: UInt32) -> [Argument] {
        guard let buffer, size >= 2 else { return [] }
        var arguments: [Argument] = []
        var offset = 2
        for _ in 0..<Int(buffer[1]) {
            guard offset + 2 <= Int(size) else { break }
            let descriptor = buffer[offset], length = Int(buffer[offset + 1])
            offset += 2
            guard offset + length <= Int(size) else { break }
            arguments.append(Argument(kind: descriptor >> 4, bytes: Array(UnsafeBufferPointer(start: buffer + offset, count: length))))
            offset += length
        }
        return arguments
    }

    /// An object's -description.
    static func describe(_ object: UnsafeRawPointer?) -> String {
        guard let object else { return "(null)" }
        typealias Send = @convention(c) (UnsafeRawPointer?, UnsafeRawPointer) -> UnsafeRawPointer?
        let send = unsafeBitCast(ObjCRuntime.msgSend, to: Send.self)
        guard let description = send(object, ObjCRuntime.selector("description")),
              let utf8 = send(description, ObjCRuntime.selector("UTF8String")) else { return "(null)" }
        return String(cString: utf8.assumingMemoryBound(to: CChar.self))
    }

    /// The message: the format with each conversion filled from the
    /// arguments in order. %{public}, %{private} and the like only qualify
    /// a conversion; %{BOOL}d, %{bool}d and %{errno}d change how it reads.
    static func message(_ format: UnsafePointer<CChar>?, _ arguments: [Argument]) -> String {
        guard let format else { return "" }
        let characters = Array(String(cString: format).unicodeScalars)
        var output = ""
        var queue = arguments[...]
        var index = 0
        func take() -> Argument? { queue.popFirst() }
        while index < characters.count {
            let character = characters[index]
            guard character == "%" else {
                output.unicodeScalars.append(character)
                index += 1
                continue
            }
            index += 1
            guard index < characters.count else { break }
            if characters[index] == "%" {
                output += "%"
                index += 1
                continue
            }
            var annotation = ""
            if characters[index] == "{" {
                index += 1
                while index < characters.count, characters[index] != "}" {
                    annotation.unicodeScalars.append(characters[index])
                    index += 1
                }
                index += 1
            }
            var flags = "", width = "", precision: String?
            while index < characters.count, "-+ #0'".unicodeScalars.contains(characters[index]) {
                flags.unicodeScalars.append(characters[index])
                index += 1
            }
            if index < characters.count, characters[index] == "*" {
                width = String(take()?.integer ?? 0)
                index += 1
            }
            while index < characters.count, ("0"..."9").contains(characters[index]) {
                width.unicodeScalars.append(characters[index])
                index += 1
            }
            if index < characters.count, characters[index] == "." {
                index += 1
                var digits = ""
                if index < characters.count, characters[index] == "*" {
                    digits = String(take()?.integer ?? 0)
                    index += 1
                }
                while index < characters.count, ("0"..."9").contains(characters[index]) {
                    digits.unicodeScalars.append(characters[index])
                    index += 1
                }
                precision = digits
            }
            while index < characters.count, "hlqjztL".unicodeScalars.contains(characters[index]) { index += 1 }
            guard index < characters.count else { break }
            let conversion = characters[index]
            index += 1
            let argument = take()
            let names = annotation.split(separator: ",").map { String($0).trimmingCharacters(in: " ") }
            let spec = "%" + flags + width + (precision.map { "." + $0 } ?? "")
            switch conversion {
            case "@":
                output += describe(argument?.pointer)
            case "s":
                let text = argument?.pointer.map { String(cString: $0.assumingMemoryBound(to: CChar.self)) } ?? "(null)"
                output += precision.flatMap(Int.init).map { String(text.prefix($0)) } ?? text
            case "p":
                output += "0x" + String(UInt(bitPattern: Int(argument?.integer ?? 0)), radix: 16)
            case "d", "i", "u", "x", "X", "o", "c":
                let value = argument?.integer ?? 0
                if names.contains("BOOL") { output += value != 0 ? "YES" : "NO"; continue }
                if names.contains("bool") { output += value != 0 ? "true" : "false"; continue }
                if names.contains("errno") || names.contains("darwin.errno") {
                    output += "[\(value): " + String(cString: strerror(Int32(truncatingIfNeeded: value))) + "]"
                    continue
                }
                var buffer = [CChar](repeating: 0, count: 128)
                let full = conversion == "c" ? spec + "c" : spec + "ll" + String(conversion)
                _ = perry_format_integer(&buffer, 128, full, value)
                output += String(cString: buffer)
            case "f", "F", "e", "E", "g", "G", "a", "A":
                var value = 0.0
                if let bytes = argument?.bytes, bytes.count == 8 {
                    value = bytes.withUnsafeBytes { $0.load(as: Double.self) }
                } else if let bytes = argument?.bytes, bytes.count == 4 {
                    value = Double(bytes.withUnsafeBytes { $0.load(as: Float.self) })
                }
                var buffer = [CChar](repeating: 0, count: 512)
                _ = perry_format_double(&buffer, 512, spec + String(conversion), value)
                output += String(cString: buffer)
            default:
                output.unicodeScalars.append(conversion)
            }
        }
        return output
    }

    /// Writes the message to standard error, as NSLog writes its lines.
    static func emit(_ log: Object?, _ type: UInt8, _ text: String) {
        guard isEnabled(log, type) else { return }
        var now = timespec()
        clock_gettime(CLOCK_REALTIME, &now)
        var seconds = now.tv_sec
        var parts = tm()
        localtime_r(&seconds, &parts)
        var stamp = [CChar](repeating: 0, count: 64)
        _ = strftime(&stamp, 64, "%Y-%m-%d %H:%M:%S", &parts)
        let micros = String(now.tv_nsec / 1000)
        let name = programName ?? String(cString: perry_dispatch_program_name())
        var scope = ""
        if let state = state(log), let subsystem = state.subsystem {
            scope = " [\(subsystem):\(state.category ?? "")]"
        }
        let level: String
        switch type {
        case info: level = " <Info>"
        case error: level = " <Error>"
        case fault: level = " <Fault>"
        default: level = ""
        }
        let line = "\(String(cString: stamp)).\(String(repeating: "0", count: max(0, 6 - micros.count)) + micros) "
            + "\(name)[\(getpid()):\(perry_dispatch_thread_id())]\(level)\(scope) \(text)\n"
        line.withCString { _ = write(2, $0, strlen($0)) }
    }
}

extension String {
    func trimmingCharacters(in set: String) -> String {
        let characters = Set(set)
        return String(drop { characters.contains($0) }.reversed().drop { characters.contains($0) }.reversed())
    }
}

// MARK: - Logs

@c(_os_log_create)
public func os_log_create(_ subsystem: UnsafePointer<CChar>?, _ category: UnsafePointer<CChar>?) -> Object? {
    let subsystem = subsystem.map { String(cString: $0) } ?? "", category = category.map { String(cString: $0) } ?? ""
    let key = subsystem + "\u{0}" + category
    return Logging.lock.withLock {
        if let log = Logging.logs[key] { return log }
        let log = Objects.make(OSLog.objCClass.pointer, linux: nil, state: LogState(subsystem: subsystem, category: category))
        Logging.logs[key] = log
        return log
    }
}

@c(_os_log_type_enabled)
public func os_log_type_enabled(_ log: Object?, _ type: UInt8) -> Bool { Logging.isEnabled(log, type) }

@c(__os_log_impl)
public func _os_log_impl(_ dso: UnsafeRawPointer?, _ log: Object?, _ type: UInt8, _ format: UnsafePointer<CChar>?,
                         _ buffer: UnsafePointer<UInt8>?, _ size: UInt32) {
    guard Logging.isEnabled(log, type) else { return }
    Logging.emit(log, type, Logging.message(format, Logging.arguments(buffer, size)))
}

@c(__os_log_debug_impl)
public func _os_log_debug_impl(_ dso: UnsafeRawPointer?, _ log: Object?, _ type: UInt8, _ format: UnsafePointer<CChar>?,
                               _ buffer: UnsafePointer<UInt8>?, _ size: UInt32) {
    _os_log_impl(dso, log, type, format, buffer, size)
}

@c(__os_log_error_impl)
public func _os_log_error_impl(_ dso: UnsafeRawPointer?, _ log: Object?, _ type: UInt8, _ format: UnsafePointer<CChar>?,
                               _ buffer: UnsafePointer<UInt8>?, _ size: UInt32) {
    _os_log_impl(dso, log, type, format, buffer, size)
}

@c(__os_log_fault_impl)
public func _os_log_fault_impl(_ dso: UnsafeRawPointer?, _ log: Object?, _ type: UInt8, _ format: UnsafePointer<CChar>?,
                               _ buffer: UnsafePointer<UInt8>?, _ size: UInt32) {
    _os_log_impl(dso, log, type, format, buffer, size)
}

/// os_log_with_type's older entry point, without a buffer to read: the
/// format alone.
@c(__os_log_internal)
public func _os_log_internal(_ dso: UnsafeRawPointer?, _ log: Object?, _ type: UInt8, _ format: UnsafePointer<CChar>?) {
    guard let format else { return }
    Logging.emit(log, type, String(cString: format))
}

// MARK: - Signposts

/// Identifiers: ids made from pointers are the pointers, as on Darwin;
/// generated ones count up from there.
@c(_os_signpost_id_generate)
public func os_signpost_id_generate(_ log: Object?) -> UInt64 { 0x1000_0000_0000 + Logging.next() }

@c(_os_signpost_id_make_with_pointer)
public func os_signpost_id_make_with_pointer(_ log: Object?, _ pointer: UnsafeRawPointer?) -> UInt64 {
    UInt64(UInt(bitPattern: pointer))
}

@c(_os_signpost_enabled)
public func os_signpost_enabled(_ log: Object?) -> Bool { !(Logging.state(log)?.disabled ?? true) }

/// Signposts mark intervals for Instruments, which Linux lacks.
@c(__os_signpost_emit_with_name_impl)
public func _os_signpost_emit_with_name_impl(_ dso: UnsafeRawPointer?, _ log: Object?, _ type: UInt8,
                                             _ identifier: UInt64.ObjCType, _ name: UnsafePointer<CChar>?, _ format: UnsafePointer<CChar>?,
                                             _ buffer: UnsafePointer<UInt8>?, _ size: UInt32) {}

// MARK: - Activities

@c(__os_activity_create)
public func _os_activity_create(_ dso: UnsafeRawPointer?, _ description: UnsafePointer<CChar>?, _ parent: Object?,
                                _ flags: UInt32) -> Object? {
    let state = ActivityState(identifier: Logging.next(), name: description.map { String(cString: $0) } ?? "")
    return Objects.make(OSActivity.objCClass.pointer, linux: nil, state: state)
}

@c(_os_activity_apply)
public func os_activity_apply(_ activity: Object?, _ block: Object?) {
    guard let block else { return }
    Blocks.invoke(block)
}

@c(_os_activity_apply_f)
public func os_activity_apply_f(_ activity: Object?, _ context: UnsafeMutableRawPointer?, _ function: Function?) {
    function?(context)
}

@c(_os_activity_scope_enter)
public func os_activity_scope_enter(_ activity: Object?, _ state: UnsafeMutableRawPointer?) {}

@c(_os_activity_scope_leave)
public func os_activity_scope_leave(_ state: UnsafeMutableRawPointer?) {}

@c(_os_activity_get_identifier)
public func os_activity_get_identifier(_ activity: Object?, _ parent: UnsafeMutablePointer<UInt64>?) -> UInt64 {
    parent?.pointee = 0
    return Objects.state(activity, as: ActivityState.self)?.identifier ?? 0
}

@c(_os_activity_get_active)
public func os_activity_get_active(_ entries: UnsafeMutablePointer<UInt64>?, _ count: UnsafeMutablePointer<UInt32>?) -> UInt32 {
    count?.pointee = 0
    return 0
}

@c(__os_activity_label_useraction)
public func _os_activity_label_useraction(_ dso: UnsafeRawPointer?, _ name: UnsafePointer<CChar>?) {}

@c(__os_activity_initiate)
public func _os_activity_initiate(_ dso: UnsafeRawPointer?, _ description: UnsafePointer<CChar>?, _ flags: UInt32, _ block: Object?) {
    guard let block else { return }
    Blocks.invoke(block)
}

@c(__os_activity_initiate_f)
public func _os_activity_initiate_f(_ dso: UnsafeRawPointer?, _ description: UnsafePointer<CChar>?, _ flags: UInt32,
                                    _ context: UnsafeMutableRawPointer?, _ function: Function?) {
    function?(context)
}
