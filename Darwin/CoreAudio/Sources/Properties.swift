import Foundation

// The audio hardware's API is macOS's alone.
#if os(macOS)

// Property addresses, the audio hardware's errors and the reading and
// writing of objects' properties that the AudioHardware classes share.

public func PropertyAddress(_ selector: AudioObjectPropertySelector, scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal, element: AudioObjectPropertyElement = kAudioObjectPropertyElementMain) -> AudioObjectPropertyAddress {
    AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: element)
}

public protocol PropertyListenerDelegate {
    func propertiesChanged(properties: [AudioObjectPropertyAddress])
}

public struct AudioHardwareError: LocalizedError, Sendable {
    public let error: OSStatus

    public init(_ err: OSStatus) {
        error = err
    }

    /// The status's name in AudioHardware.h, else its four characters or
    /// number.
    public var errorDescription: String? {
        let names: [OSStatus: String] = [
            OSStatus(kAudioHardwareNotRunningError): "the audio hardware isn't running",
            OSStatus(kAudioHardwareUnspecifiedError): "unspecified audio hardware error",
            OSStatus(kAudioHardwareUnknownPropertyError): "unknown property",
            OSStatus(kAudioHardwareBadPropertySizeError): "bad property size",
            OSStatus(kAudioHardwareIllegalOperationError): "illegal operation",
            OSStatus(kAudioHardwareBadObjectError): "bad audio object",
            OSStatus(kAudioHardwareBadDeviceError): "bad audio device",
            OSStatus(kAudioHardwareBadStreamError): "bad audio stream",
            OSStatus(kAudioHardwareUnsupportedOperationError): "unsupported operation",
            OSStatus(kAudioHardwareNotReadyError): "the audio hardware isn't ready",
            OSStatus(kAudioDeviceUnsupportedFormatError): "unsupported format",
            OSStatus(kAudioDevicePermissionsError): "permission denied",
        ]
        if let name = names[error] {
            return name
        }
        let bytes = withUnsafeBytes(of: UInt32(bitPattern: error).bigEndian) { Array($0) }
        if bytes.allSatisfy({ $0 >= 0x20 && $0 < 0x7F }) {
            return "audio hardware error '\(String(decoding: bytes, as: UTF8.self))'"
        }
        return "audio hardware error \(error)"
    }
}

public enum AudioHardwareDirection: UInt32, Sendable {
    case output
    case input
}

extension AudioObjectPropertyAddress: Hashable {
    public static func == (lhs: AudioObjectPropertyAddress, rhs: AudioObjectPropertyAddress) -> Bool {
        lhs.mSelector == rhs.mSelector && lhs.mScope == rhs.mScope && lhs.mElement == rhs.mElement
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(mSelector)
        hasher.combine(mScope)
        hasher.combine(mElement)
    }

    public var hashValue: Int {
        var hasher = Hasher()
        hash(into: &hasher)
        return hasher.finalize()
    }
}

/// Throws a failed status as an AudioHardwareError.
func check(_ status: OSStatus) throws {
    if status != noErr {
        throw AudioHardwareError(status)
    }
}

/// The bytes of a qualifier, nil for none.
private func withQualifier<Result>(_ qualifier: Data?, _ body: (UnsafeRawPointer?, UInt32) throws -> Result) rethrows -> Result {
    guard let qualifier, !qualifier.isEmpty else { return try body(nil, 0) }
    return try qualifier.withUnsafeBytes { try body($0.baseAddress, UInt32($0.count)) }
}

/// A value's bytes as a qualifier.
func qualifier<T>(_ value: T) -> Data {
    withUnsafeBytes(of: value) { Data($0) }
}

/// The audio object `id`'s properties, read and written as Swift values.
struct Properties {
    let id: AudioObjectID

    func has(_ address: AudioObjectPropertyAddress) -> Bool {
        var address = address
        return AudioObjectHasProperty(id, &address)
    }

    func size(_ address: AudioObjectPropertyAddress, qualifier: Data? = nil) throws -> Int {
        var address = address
        var size: UInt32 = 0
        try withQualifier(qualifier) { try check(AudioObjectGetPropertyDataSize(id, &address, $1, $0, &size)) }
        return Int(size)
    }

    func data(_ address: AudioObjectPropertyAddress, qualifier: Data? = nil) throws -> Data {
        var address = address
        var size = UInt32(try self.size(address, qualifier: qualifier))
        var data = Data(count: Int(size))
        try data.withUnsafeMutableBytes { bytes in
            try withQualifier(qualifier) { try check(AudioObjectGetPropertyData(id, &address, $1, $0, &size, bytes.baseAddress!)) }
        }
        data.count = Int(size)
        return data
    }

    func setData(_ address: AudioObjectPropertyAddress, qualifier: Data? = nil, _ data: Data) throws {
        var address = address
        try data.withUnsafeBytes { bytes in
            try withQualifier(qualifier) { try check(AudioObjectSetPropertyData(id, &address, $1, $0, UInt32(bytes.count), bytes.baseAddress!)) }
        }
    }

    /// A fixed-size value; `value` is what's passed in, for properties that
    /// translate it in place.
    func get<T>(_ address: AudioObjectPropertyAddress, qualifier: Data? = nil, _ value: T) throws -> T {
        var address = address
        var value = value
        var size = UInt32(MemoryLayout<T>.size)
        try withUnsafeMutableBytes(of: &value) { bytes in
            try withQualifier(qualifier) { try check(AudioObjectGetPropertyData(id, &address, $1, $0, &size, bytes.baseAddress!)) }
        }
        return value
    }

    func set<T>(_ address: AudioObjectPropertyAddress, qualifier: Data? = nil, _ value: T) throws {
        var address = address
        try withUnsafeBytes(of: value) { bytes in
            try withQualifier(qualifier) { try check(AudioObjectSetPropertyData(id, &address, $1, $0, UInt32(bytes.count), bytes.baseAddress!)) }
        }
    }

    func array<T>(_ address: AudioObjectPropertyAddress, qualifier: Data? = nil, of type: T.Type) throws -> [T] {
        let data = try self.data(address, qualifier: qualifier)
        let count = data.count / MemoryLayout<T>.stride
        return data.withUnsafeBytes { bytes in
            (0..<count).map { bytes.loadUnaligned(fromByteOffset: $0 * MemoryLayout<T>.stride, as: T.self) }
        }
    }

    func setArray<T>(_ address: AudioObjectPropertyAddress, _ values: [T]) throws {
        try setData(address, values.withUnsafeBytes { Data($0) })
    }

    /// A Core Foundation object the property returns retained.
    func object(_ address: AudioObjectPropertyAddress, qualifier: Data? = nil) throws -> AnyObject? {
        let value: Unmanaged<AnyObject>? = try get(address, qualifier: qualifier, nil)
        return value?.takeRetainedValue()
    }

    func setObject(_ address: AudioObjectPropertyAddress, _ object: AnyObject) throws {
        try withExtendedLifetime(object) {
            try set(address, Unmanaged.passUnretained(object))
        }
    }

    func string(_ address: AudioObjectPropertyAddress, qualifier: Data? = nil) throws -> String {
        guard let string = try object(address, qualifier: qualifier) as? String else { return "" }
        return string
    }

    func bool(_ address: AudioObjectPropertyAddress) throws -> Bool {
        try get(address, UInt32(0)) != 0
    }

    func setBool(_ address: AudioObjectPropertyAddress, _ value: Bool) throws {
        try set(address, UInt32(value ? 1 : 0))
    }

    func int(_ address: AudioObjectPropertyAddress) throws -> Int {
        Int(try get(address, UInt32(0)))
    }

    func ids(_ address: AudioObjectPropertyAddress, qualifier: Data? = nil) throws -> [AudioObjectID] {
        try array(address, qualifier: qualifier, of: AudioObjectID.self)
    }

    /// The object a translation property finds for a string (a UID or
    /// bundle ID), nil when it finds none.
    func translate(_ address: AudioObjectPropertyAddress, _ string: String) throws -> AudioObjectID? {
        let cfString = string as CFString
        let id: AudioObjectID = try withExtendedLifetime(cfString) {
            try get(address, qualifier: qualifier(Unmanaged.passUnretained(cfString)), AudioObjectID(kAudioObjectUnknown))
        }
        return id == kAudioObjectUnknown ? nil : id
    }
}

/// A global, input or output address of this selector.
func global(_ selector: AudioObjectPropertySelector) -> AudioObjectPropertyAddress {
    PropertyAddress(selector)
}

func input(_ selector: AudioObjectPropertySelector) -> AudioObjectPropertyAddress {
    PropertyAddress(selector, scope: kAudioObjectPropertyScopeInput)
}

func output(_ selector: AudioObjectPropertySelector) -> AudioObjectPropertyAddress {
    PropertyAddress(selector, scope: kAudioObjectPropertyScopeOutput)
}

#endif
