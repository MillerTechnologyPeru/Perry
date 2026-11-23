import ObjectiveC

// OSLogMessage: a string interpolation that collects, rather than a
// string, an os_log format string and what writes each argument into the
// log's argument buffer. Programs compile most of it into themselves (the
// compiler folds a message's format string and buffer layout to
// constants); the members here are what they call when it is not inlined,
// and they lay out the buffer as the compiled code does.
//
// The buffer: a summary byte (bit 0: some argument is private, bit 1:
// some is not a scalar), the number of arguments, then each argument as a
// descriptor byte (its kind in the high nibble, its privacy in the low),
// its size in bytes, and its bytes.

@usableFromInline
internal typealias StringStorageType = Any

@usableFromInline
internal typealias ObjectType = NSObject

@usableFromInline
internal typealias ByteBufferPointer = UnsafeMutablePointer<UInt8>

@usableFromInline
internal typealias ObjectStorage<T> = UnsafeMutablePointer<T>?

@usableFromInline
internal typealias ArgumentClosures = [(inout ByteBufferPointer, inout ObjectStorage<ObjectType?>, inout ObjectStorage<Any>) -> ()]

/// The most arguments one message holds; os_log reads no more.
public var maxOSLogArgumentCount: UInt8 {
    48
}

// MARK: The interpolation

@frozen public struct OSLogInterpolation: StringInterpolationProtocol {
    @usableFromInline
    internal var formatString: String

    @usableFromInline
    internal var arguments: OSLogArguments

    /// What an argument is, as its descriptor's high nibble says.
    @usableFromInline
    internal enum ArgumentType {
        case scalar, count, string, pointer, object, mask

        @usableFromInline
        internal var rawValue: UInt8 {
            switch self {
            case .scalar: return 0
            case .count: return 1
            case .string: return 2
            case .pointer: return 3
            case .object: return 4
            case .mask: return 7
            }
        }
    }

    @usableFromInline
    internal var preamble: UInt8

    @usableFromInline
    internal var privateBitMask: UInt8 { 0x1 }

    @usableFromInline
    internal var nonScalarBitMask: UInt8 { 0x2 }

    @usableFromInline
    internal var argumentCount: UInt8

    @usableFromInline
    internal var totalBytesForSerializingArguments: Int

    @usableFromInline
    internal var stringArgumentCount: Int

    @usableFromInline
    internal var objectArgumentCount: Int

    public init(literalCapacity: Int, interpolationCount: Int) {
        formatString = ""
        arguments = OSLogArguments()
        preamble = 0
        argumentCount = 0
        totalBytesForSerializingArguments = 0
        stringArgumentCount = 0
        objectArgumentCount = 0
    }

    /// Literal text, its percent signs doubled so os_log prints them.
    public mutating func appendLiteral(_ literal: String) {
        formatString += literal.percentEscapedString
    }

    /// The descriptor byte of an argument.
    @usableFromInline
    internal func getArgumentHeader(privacy: OSLogPrivacy, type: ArgumentType) -> UInt8 {
        (type.rawValue << 4) | privacy.argumentFlag
    }

    /// The summary byte with an argument of this privacy and kind added.
    @usableFromInline
    internal func getUpdatedPreamble(privacy: OSLogPrivacy, isScalar: Bool) -> UInt8 {
        var summary = preamble
        if privacy.isAtleastPrivate { summary |= privateBitMask }
        if !isScalar || privacy.hasMask { summary |= nonScalarBitMask }
        return summary
    }

    public typealias StringLiteralType = String
}

extension OSLogInterpolation.ArgumentType: Equatable, Hashable {}

extension String {
    /// The string with each % written %%.
    @usableFromInline
    internal var percentEscapedString: String {
        var escaped = ""
        escaped.reserveCapacity(utf8.count)
        for character in self {
            if character == "%" { escaped += "%%" } else { escaped.append(character) }
        }
        return escaped
    }
}

// MARK: The message

@frozen public struct OSLogMessage: ExpressibleByStringInterpolation, ExpressibleByStringLiteral {
    public let interpolation: OSLogInterpolation

    public init(stringInterpolation: OSLogInterpolation) {
        interpolation = stringInterpolation
    }

    public init(stringLiteral value: String) {
        var interpolation = OSLogInterpolation(literalCapacity: 1, interpolationCount: 0)
        interpolation.appendLiteral(value)
        self.interpolation = interpolation
    }

    /// The bytes of the argument buffer: the two header bytes and the
    /// arguments.
    public var bufferSize: Int {
        interpolation.totalBytesForSerializingArguments + 2
    }

    public typealias ExtendedGraphemeClusterLiteralType = String
    public typealias StringInterpolation = OSLogInterpolation
    public typealias UnicodeScalarLiteralType = String
}

// MARK: Arguments

/// What writes each argument's bytes, in order.
@usableFromInline
@frozen internal struct OSLogArguments {
    @usableFromInline
    internal var argumentClosures: ArgumentClosures

    @usableFromInline
    internal init() {
        argumentClosures = []
    }

    /// A descriptor or size byte.
    @usableFromInline
    internal mutating func append(_ header: UInt8) {
        argumentClosures.append { position, _, _ in
            writeBytes(of: header, at: &position)
        }
    }

    @usableFromInline
    internal mutating func append(_ value: @escaping () -> Double) {
        argumentClosures.append { position, _, _ in
            writeBytes(of: value(), at: &position)
        }
    }

    @usableFromInline
    internal mutating func append<T: FixedWidthInteger>(_ value: @escaping () -> T) {
        argumentClosures.append { position, _, _ in
            writeBytes(of: value(), at: &position)
        }
    }

    /// An object, by address; it is kept in the object storage until the
    /// message is written.
    @usableFromInline
    internal mutating func append(_ value: @escaping () -> ObjectType?) {
        argumentClosures.append { position, objects, _ in
            let object = value()
            let address = object.map { Int(bitPattern: Unmanaged.passUnretained($0).toOpaque()) } ?? 0
            writeBytes(of: address, at: &position)
            keep(object, in: &objects)
        }
    }

    @usableFromInline
    internal mutating func append(_ value: @escaping () -> UnsafeRawPointer) {
        argumentClosures.append { position, _, _ in
            writeBytes(of: value(), at: &position)
        }
    }

    /// A string, by the address of its UTF-8, whose owner is kept in the
    /// string storage until the message is written.
    @usableFromInline
    internal mutating func append(_ value: @escaping () -> String) {
        argumentClosures.append { position, _, owners in
            serialize(value(), at: &position, using: &owners)
        }
    }
}

/// A value's bytes, written at a buffer position that then moves past
/// them.
private func writeBytes<T>(of value: T, at position: inout ByteBufferPointer) {
    withUnsafeBytes(of: value) { bytes in
        UnsafeMutableRawPointer(position).copyMemory(from: bytes.baseAddress!, byteCount: bytes.count)
        position += bytes.count
    }
}

/// Stores a value in the next slot of a storage, if it has slots.
private func keep<T>(_ value: T, in storage: inout ObjectStorage<T>) {
    guard let slot = storage else { return }
    slot.initialize(to: value)
    storage = slot + 1
}

/// The null-terminated UTF-8 of a string, valid while the owner stored for
/// it lives.
@usableFromInline
internal func getNullTerminatedUTF8Pointer(_ stringValue: String, using stringStorage: inout ObjectStorage<Any>) -> UnsafeRawPointer {
    // A copy of the bytes, owned by a buffer kept with the arguments.
    let owner = StringBytes(stringValue)
    keep(owner as Any, in: &stringStorage)
    return UnsafeRawPointer(owner.bytes)
}

/// The address of a string's UTF-8, written as a pointer argument.
@usableFromInline
internal func serialize(_ stringValue: String, at bufferPosition: inout UnsafeMutablePointer<UInt8>, using stringStorage: inout ObjectStorage<Any>) {
    let pointer = getNullTerminatedUTF8Pointer(stringValue, using: &stringStorage)
    writeBytes(of: pointer, at: &bufferPosition)
}

/// A string's null-terminated UTF-8, freed with the instance.
private final class StringBytes {
    let bytes: UnsafeMutablePointer<CChar>

    init(_ string: String) {
        let utf8 = Array(string.utf8CString)
        bytes = .allocate(capacity: utf8.count)
        bytes.initialize(from: utf8, count: utf8.count)
    }

    deinit {
        bytes.deallocate()
    }
}

// MARK: Headers and counts

extension OSLogInterpolation {
    @usableFromInline
    internal mutating func addDoubleHeaders(_ privacy: OSLogPrivacy) {
        addHeaders(privacy, .scalar, MemoryLayout<Double>.size)
    }

    @usableFromInline
    internal mutating func addIntHeaders(_ privacy: OSLogPrivacy, _ byteCount: Int) {
        addHeaders(privacy, .scalar, byteCount)
    }

    @usableFromInline
    internal mutating func addNSObjectHeaders(_ privacy: OSLogPrivacy) {
        addHeaders(privacy, .object, MemoryLayout<UnsafeRawPointer>.size)
    }

    @usableFromInline
    internal mutating func addPointerHeaders(_ privacy: OSLogPrivacy) {
        addHeaders(privacy, .pointer, MemoryLayout<UnsafeRawPointer>.size)
    }

    @usableFromInline
    internal mutating func addStringHeaders(_ privacy: OSLogPrivacy) {
        addHeaders(privacy, .string, MemoryLayout<UnsafeRawPointer>.size)
    }

    /// An argument's descriptor and size, its room in the buffer, and the
    /// summary byte updated for it.
    private mutating func addHeaders(_ privacy: OSLogPrivacy, _ type: ArgumentType, _ byteCount: Int) {
        arguments.append(getArgumentHeader(privacy: privacy, type: type))
        arguments.append(UInt8(byteCount))
        totalBytesForSerializingArguments += byteCount + 2
        preamble = getUpdatedPreamble(privacy: privacy, isScalar: type == .scalar)
    }

    /// The precision a "%.*" reads, a count argument.
    @usableFromInline
    internal mutating func appendPrecisionArgument(_ count: @escaping () -> Int) {
        appendPrecisionAlignCount(count, getArgumentHeader(privacy: .auto, type: .count))
    }

    /// The width a "%*" reads, a scalar argument.
    @usableFromInline
    internal mutating func appendAlignmentArgument(_ count: @escaping () -> Int) {
        appendPrecisionAlignCount(count, getArgumentHeader(privacy: .auto, type: .scalar))
    }

    /// A four-byte int argument under the descriptor given.
    @usableFromInline
    internal mutating func appendPrecisionAlignCount(_ count: @escaping () -> Int, _ argumentHeader: UInt8) {
        arguments.append(argumentHeader)
        arguments.append(UInt8(MemoryLayout<CInt>.size))
        totalBytesForSerializingArguments += MemoryLayout<CInt>.size + 2
        arguments.append { CInt(count()) }
        argumentCount += 1
    }

    /// The eight-byte mask argument that precedes a masked one.
    @usableFromInline
    internal mutating func appendMaskArgument(_ privacy: OSLogPrivacy) {
        arguments.append(getArgumentHeader(privacy: .auto, type: .mask))
        arguments.append(UInt8(MemoryLayout<UInt64>.size))
        totalBytesForSerializingArguments += MemoryLayout<UInt64>.size + 2
        let value = privacy.maskValue
        arguments.append { value }
        argumentCount += 1
    }
}

// MARK: Format specifiers

/// The "{…}" contents of a specifier: its attributes and privacy, or nil
/// when it has neither.
private func privacyAndAttributes(_ privacy: OSLogPrivacy, _ attributes: String) -> String? {
    var tag = attributes
    if let specifier = privacy.privacySpecifier {
        if !tag.isEmpty, privacy.needsPrivacySpecifier { tag += "," }
        tag += specifier
    }
    return tag.isEmpty ? nil : tag
}

/// "{tag}" for a tag, nothing for none.
private func braced(_ tag: String?) -> String {
    tag.map { "{" + $0 + "}" } ?? ""
}

extension OSLogInterpolation {
    @usableFromInline
    internal func getNSObjectFormatSpecifier(_ privacy: OSLogPrivacy) -> String {
        "%" + braced(privacyAndAttributes(privacy, "")) + "@"
    }

    @usableFromInline
    internal func getPointerFormatSpecifier(_ format: OSLogPointerFormat, _ privacy: OSLogPrivacy) -> String {
        var tags: [String] = []
        switch format {
        case .ipv6Address: tags.append("network:in6_addr")
        case .timeval: tags.append("timeval")
        case .timespec: tags.append("timespec")
        case .uuid: tags.append("uuid_t")
        case .sockaddr: tags.append("network:sockaddr")
        case .none: break
        }
        if let privacy = privacyAndAttributes(privacy, "") { tags.append(privacy) }
        return "%" + braced(tags.isEmpty ? nil : tags.joined(separator: ",")) + ".*P"
    }

    @usableFromInline
    internal func getStringFormatSpecifier(_ align: OSLogStringAlignment, _ privacy: OSLogPrivacy) -> String {
        var specifier = "%" + braced(privacyAndAttributes(privacy, ""))
        if case .start = align.anchor { specifier += "-" }
        if align.minimumColumnWidth != nil { specifier += "*" }
        return specifier + "s"
    }

    @usableFromInline
    internal func getExtendedFormatSpecifier(_ format: OSLogInt32ExtendedFormat, _ privacy: OSLogPrivacy) -> String {
        var specifier = "%{" + format.tag
        if let privacy = privacyAndAttributes(privacy, "") { specifier += "," + privacy }
        return specifier + "}d"
    }

    @usableFromInline
    internal func getInt32BoolFormat(_ format: OSLogBoolFormat) -> OSLogInt32ExtendedFormat {
        format == .answer ? .answer : .truth
    }
}

extension OSLogIntegerFormatting {
    @usableFromInline
    internal func formatSpecifier<I: FixedWidthInteger>(for type: I.Type, align: OSLogStringAlignment, privacy: OSLogPrivacy) -> String {
        precondition(!type.isSigned || radix == 10, "Signed integers must be formatted using .decimal")
        var specifier = "%" + braced(privacyAndAttributes(privacy, ""))
        var prefix = _prefix
        if explicitPositiveSign {
            // A signed value's sign is printf's; an unsigned one is never
            // negative, so its plus is literal text.
            if type.isSigned { specifier += "+" } else { prefix = "+" + prefix }
        }
        if case .start = align.anchor { specifier += "-" }
        if align.minimumColumnWidth != nil { specifier += "*" }
        if minDigits != nil { specifier += ".*" }
        guard let length = OSLogIntegerFormatting.formatSpecifierLengthModifier(type) else {
            fatalError("Integer type has unknown byte length")
        }
        specifier += length
        switch radix {
        case 10: specifier += type.isSigned ? "d" : "u"
        case 8: specifier += "o"
        case 16: specifier += uppercase ? "X" : "x"
        default: fatalError("radix must be 10, 8 or 16")
        }
        return prefix + specifier
    }

    /// printf's length modifier for an integer type of C's.
    @usableFromInline
    internal static func formatSpecifierLengthModifier<I: FixedWidthInteger>(_ type: I.Type) -> String? {
        switch type.bitWidth {
        case 8: return "hh"
        case 16: return "h"
        case 32: return ""
        case 64: return type == Int.self || type == UInt.self ? "l" : "ll"
        default: return nil
        }
    }

    /// The prefix printed before the number: 0b, 0o or 0x.
    @usableFromInline
    internal var _prefix: String {
        guard includePrefix else { return "" }
        switch radix {
        case 2: return "0b"
        case 8: return "0o"
        case 16: return "0x"
        default: return ""
        }
    }
}

extension OSLogFloatFormatting {
    @usableFromInline
    internal func formatSpecifier<I: FloatingPoint>(for type: I.Type, align: OSLogStringAlignment, privacy: OSLogPrivacy) -> String {
        var specifier = "%" + braced(privacyAndAttributes(privacy, ""))
        if explicitPositiveSign { specifier += "+" }
        if case .start = align.anchor { specifier += "-" }
        if align.minimumColumnWidth != nil { specifier += "*" }
        if precision != nil { specifier += ".*" }
        guard let length = OSLogFloatFormatting._formatStringLengthModifier(type) else {
            fatalError("Float type has unknown length")
        }
        specifier += length
        switch notation {
        case .fixed: specifier += uppercase ? "F" : "f"
        case .exponential: specifier += uppercase ? "E" : "e"
        case .hybrid: specifier += uppercase ? "G" : "g"
        case .hex: specifier += uppercase ? "A" : "a"
        }
        return specifier
    }

    /// printf's length modifier for a floating-point type: L for a long
    /// double.
    @usableFromInline
    internal static func _formatStringLengthModifier<I: FloatingPoint>(_ type: I.Type) -> String? {
        if type == Float.self || type == Double.self { return "" }
#if arch(x86_64) || arch(i386)
        if type == Float80.self { return "L" }
#endif
        return nil
    }
}

// MARK: Interpolations

extension OSLogInterpolation {
    /// Whether another argument fits.
    private var hasRoom: Bool {
        argumentCount < maxOSLogArgumentCount
    }

    @usableFromInline
    internal mutating func appendInteger<T: FixedWidthInteger>(_ number: @escaping () -> T, format: OSLogIntegerFormatting,
                                                               align: OSLogStringAlignment, privacy: OSLogPrivacy) {
        guard hasRoom else { return }
        formatString += format.formatSpecifier(for: T.self, align: align, privacy: privacy)
        if let columns = align.minimumColumnWidth { appendAlignmentArgument(columns) }
        if privacy.hasMask { appendMaskArgument(privacy) }
        if let digits = format.minDigits { appendPrecisionArgument(digits) }
        addIntHeaders(privacy, T.bitWidth / 8)
        arguments.append(number)
        argumentCount += 1
    }

    public mutating func appendInterpolation(_ number: @autoclosure @escaping () -> Int, format: OSLogIntegerFormatting = .decimal,
                                             align: OSLogStringAlignment = .none, privacy: OSLogPrivacy = .auto) {
        appendInteger(number, format: format, align: align, privacy: privacy)
    }

    public mutating func appendInterpolation(_ number: @autoclosure @escaping () -> Int8, format: OSLogIntegerFormatting = .decimal,
                                             align: OSLogStringAlignment = .none, privacy: OSLogPrivacy = .auto) {
        appendInteger(number, format: format, align: align, privacy: privacy)
    }

    public mutating func appendInterpolation(_ number: @autoclosure @escaping () -> Int16, format: OSLogIntegerFormatting = .decimal,
                                             align: OSLogStringAlignment = .none, privacy: OSLogPrivacy = .auto) {
        appendInteger(number, format: format, align: align, privacy: privacy)
    }

    public mutating func appendInterpolation(_ number: @autoclosure @escaping () -> Int32, format: OSLogIntegerFormatting = .decimal,
                                             align: OSLogStringAlignment = .none, privacy: OSLogPrivacy = .auto) {
        appendInteger(number, format: format, align: align, privacy: privacy)
    }

    public mutating func appendInterpolation(_ number: @autoclosure @escaping () -> Int64, format: OSLogIntegerFormatting = .decimal,
                                             align: OSLogStringAlignment = .none, privacy: OSLogPrivacy = .auto) {
        appendInteger(number, format: format, align: align, privacy: privacy)
    }

    public mutating func appendInterpolation(_ number: @autoclosure @escaping () -> UInt, format: OSLogIntegerFormatting = .decimal,
                                             align: OSLogStringAlignment = .none, privacy: OSLogPrivacy = .auto) {
        appendInteger(number, format: format, align: align, privacy: privacy)
    }

    public mutating func appendInterpolation(_ number: @autoclosure @escaping () -> UInt8, format: OSLogIntegerFormatting = .decimal,
                                             align: OSLogStringAlignment = .none, privacy: OSLogPrivacy = .auto) {
        appendInteger(number, format: format, align: align, privacy: privacy)
    }

    public mutating func appendInterpolation(_ number: @autoclosure @escaping () -> UInt16, format: OSLogIntegerFormatting = .decimal,
                                             align: OSLogStringAlignment = .none, privacy: OSLogPrivacy = .auto) {
        appendInteger(number, format: format, align: align, privacy: privacy)
    }

    public mutating func appendInterpolation(_ number: @autoclosure @escaping () -> UInt32, format: OSLogIntegerFormatting = .decimal,
                                             align: OSLogStringAlignment = .none, privacy: OSLogPrivacy = .auto) {
        appendInteger(number, format: format, align: align, privacy: privacy)
    }

    public mutating func appendInterpolation(_ number: @autoclosure @escaping () -> UInt64, format: OSLogIntegerFormatting = .decimal,
                                             align: OSLogStringAlignment = .none, privacy: OSLogPrivacy = .auto) {
        appendInteger(number, format: format, align: align, privacy: privacy)
    }

    public mutating func appendInterpolation(_ number: @autoclosure @escaping () -> Float, format: OSLogFloatFormatting = .fixed,
                                             align: OSLogStringAlignment = .none, privacy: OSLogPrivacy = .auto) {
        appendInterpolation(Double(number()), format: format, align: align, privacy: privacy)
    }

    public mutating func appendInterpolation(_ number: @autoclosure @escaping () -> Double, format: OSLogFloatFormatting = .fixed,
                                             align: OSLogStringAlignment = .none, privacy: OSLogPrivacy = .auto) {
        guard hasRoom else { return }
        formatString += format.formatSpecifier(for: Double.self, align: align, privacy: privacy)
        if let columns = align.minimumColumnWidth { appendAlignmentArgument(columns) }
        if privacy.hasMask { appendMaskArgument(privacy) }
        if let precision = format.precision { appendPrecisionArgument(precision) }
        addDoubleHeaders(privacy)
        arguments.append(number)
        argumentCount += 1
    }

    public mutating func appendInterpolation(_ number: @autoclosure @escaping () -> Int32, format: OSLogInt32ExtendedFormat,
                                             privacy: OSLogPrivacy = .auto) {
        guard hasRoom else { return }
        formatString += getExtendedFormatSpecifier(format, privacy)
        if privacy.hasMask { appendMaskArgument(privacy) }
        addIntHeaders(privacy, MemoryLayout<Int32>.size)
        arguments.append(number)
        argumentCount += 1
    }

    public mutating func appendInterpolation(_ boolean: @autoclosure @escaping () -> Bool, format: OSLogBoolFormat = .truth,
                                             privacy: OSLogPrivacy = .auto) {
        appendInterpolation(boolean() ? Int32(1) : Int32(0), format: getInt32BoolFormat(format), privacy: privacy)
    }

    public mutating func appendInterpolation(_ argumentString: @autoclosure @escaping () -> String,
                                             align: OSLogStringAlignment = .none, privacy: OSLogPrivacy = .auto) {
        guard hasRoom else { return }
        formatString += getStringFormatSpecifier(align, privacy)
        if let columns = align.minimumColumnWidth { appendAlignmentArgument(columns) }
        if privacy.hasMask { appendMaskArgument(privacy) }
        addStringHeaders(privacy)
        arguments.append(argumentString)
        argumentCount += 1
        stringArgumentCount += 1
    }

    @_disfavoredOverload
    public mutating func appendInterpolation<T: CustomStringConvertible>(_ value: @autoclosure @escaping () -> T,
                                                                         align: OSLogStringAlignment = .none,
                                                                         privacy: OSLogPrivacy = .auto) {
        appendInterpolation(value().description, align: align, privacy: privacy)
    }

    public mutating func appendInterpolation(_ value: @autoclosure @escaping () -> any Any.Type,
                                             align: OSLogStringAlignment = .none, privacy: OSLogPrivacy = .auto) {
        appendInterpolation(_typeName(value(), qualified: false), align: align, privacy: privacy)
    }

    public mutating func appendInterpolation(_ argumentObject: @autoclosure @escaping () -> NSObject, privacy: OSLogPrivacy = .auto) {
        guard hasRoom else { return }
        formatString += getNSObjectFormatSpecifier(privacy)
        if privacy.hasMask { appendMaskArgument(privacy) }
        addNSObjectHeaders(privacy)
        arguments.append { argumentObject() as NSObject? }
        argumentCount += 1
        objectArgumentCount += 1
    }

    public mutating func appendInterpolation(_ pointer: @autoclosure @escaping () -> UnsafeRawBufferPointer,
                                             format: OSLogPointerFormat = .none, privacy: OSLogPrivacy = .auto) {
        appendInterpolation(pointer().baseAddress!, bytes: pointer().count, format: format, privacy: privacy)
    }

    public mutating func appendInterpolation(_ pointer: @autoclosure @escaping () -> UnsafeRawPointer,
                                             bytes: @autoclosure @escaping () -> Int,
                                             format: OSLogPointerFormat = .none, privacy: OSLogPrivacy = .auto) {
        guard hasRoom else { return }
        formatString += getPointerFormatSpecifier(format, privacy)
        if privacy.hasMask { appendMaskArgument(privacy) }
        appendPrecisionArgument(bytes)
        addPointerHeaders(privacy)
        arguments.append(pointer)
        argumentCount += 1
    }
}

// MARK: Writing a message

extension OSLogMessage {
    /// Writes the argument buffer, calls `body` with the format string
    /// and the buffer, and releases what the arguments kept.
    internal func withBuffer<R>(formatString: String? = nil,
                                _ body: (UnsafePointer<CChar>, UnsafeMutablePointer<UInt8>, UInt32) throws -> R) rethrows -> R {
        let size = bufferSize
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: size)
        defer { buffer.deallocate() }
        let objectCount = interpolation.objectArgumentCount
        let stringCount = interpolation.stringArgumentCount
        let objects: ObjectStorage<ObjectType?> = objectCount == 0 ? nil : .allocate(capacity: objectCount)
        let strings: ObjectStorage<Any> = stringCount == 0 ? nil : .allocate(capacity: stringCount)
        var objectPosition = objects
        var stringPosition = strings
        var position = buffer
        writeBytes(of: interpolation.preamble, at: &position)
        writeBytes(of: interpolation.argumentCount, at: &position)
        for closure in interpolation.arguments.argumentClosures {
            closure(&position, &objectPosition, &stringPosition)
        }
        defer {
            if let objects {
                objects.deinitialize(count: objects.distance(to: objectPosition ?? objects))
                objects.deallocate()
            }
            if let strings {
                strings.deinitialize(count: strings.distance(to: stringPosition ?? strings))
                strings.deallocate()
            }
        }
        return try (formatString ?? interpolation.formatString).withCString { format in
            try body(format, buffer, UInt32(size))
        }
    }
}

/// Hands a message's format string and buffer to `assertion`, as the
/// tests of os_log's compiler optimization do.
public func _checkFormatStringAndBuffer(_ message: OSLogMessage, with assertion: (String, UnsafeBufferPointer<UInt8>) -> Void) {
    message.withBuffer { _, buffer, size in
        assertion(message.interpolation.formatString, UnsafeBufferPointer(start: buffer, count: Int(size)))
    }
}
