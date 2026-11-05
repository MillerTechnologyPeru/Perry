// The protocols Swift errors bridge to NSError through, as Darwin's
// Foundation declares them: an error with a domain, code and user info
// (CustomNSError); an error that is an NSError of one domain kept as one
// (_BridgedStoredNSError, as CocoaError and URLError are); an error enum
// whose raw value is its code (_BridgedNSError); and one any NSError of its
// domain converts to (_ObjectiveCBridgeableError).

/// An error type that specifically provides a domain, code, and user-info
/// dictionary.
@available(macOS 10.10, iOS 8.0, watchOS 2.0, tvOS 9.0, *)
public protocol CustomNSError: Error {
    /// The domain of the error.
    static var errorDomain: String { get }

    /// The error code within the given domain.
    var errorCode: Int { get }

    /// The user-info dictionary.
    var errorUserInfo: [String: Any] { get }
}

@available(macOS 10.10, iOS 8.0, watchOS 2.0, tvOS 9.0, *)
extension CustomNSError {
    /// The domain of the error: the type's qualified name.
    public static var errorDomain: String {
        _typeName(self, qualified: true)
    }

    /// The error code within the given domain: an enum's case index.
    public var errorCode: Int {
        _getDefaultErrorCode(self)
    }

    /// The default user-info dictionary, which is empty.
    public var errorUserInfo: [String: Any] {
        [:]
    }
}

@available(macOS 10.10, iOS 8.0, watchOS 2.0, tvOS 9.0, *)
extension CustomNSError where Self: RawRepresentable, Self.RawValue: FixedWidthInteger {
    /// The error code: the raw value.
    public var errorCode: Int {
        numericCast(rawValue)
    }
}

@available(macOS 10.10, iOS 8.0, watchOS 2.0, tvOS 9.0, *)
extension Error where Self: CustomNSError {
    public var _domain: String { Self.errorDomain }
    public var _code: Int { errorCode }
}

@available(macOS 10.10, iOS 8.0, watchOS 2.0, tvOS 9.0, *)
extension Error where Self: CustomNSError, Self: RawRepresentable, Self.RawValue: FixedWidthInteger {
    public var _code: Int { errorCode }
}

@available(macOS 10.10, iOS 8.0, watchOS 2.0, tvOS 9.0, *)
extension Error {
    /// A localized message describing what error occurred: the NSError's.
    public var localizedDescription: String {
        _convertErrorToNSError(self).localizedDescription
    }
}

/// The user info an error bridges to NSError with: a CustomNSError's, and
/// the messages a LocalizedError gives. The Swift runtime looks this up by
/// name when it boxes an error as an NSError.
@available(macOS 10.10, iOS 8.0, watchOS 2.0, tvOS 9.0, *)
public func _getErrorDefaultUserInfo<T>(_ error: T) -> AnyObject? where T: Error {
    var info: [String: Any] = (error as? any CustomNSError)?.errorUserInfo ?? [:]
    if let localized = error as? any LocalizedError {
        if info[NSLocalizedDescriptionKey] == nil, let description = localized.errorDescription {
            info[NSLocalizedDescriptionKey] = description
        }
        if info[NSLocalizedFailureReasonErrorKey] == nil, let reason = localized.failureReason {
            info[NSLocalizedFailureReasonErrorKey] = reason
        }
        if info[NSLocalizedRecoverySuggestionErrorKey] == nil, let suggestion = localized.recoverySuggestion {
            info[NSLocalizedRecoverySuggestionErrorKey] = suggestion
        }
        if info[NSHelpAnchorErrorKey] == nil, let anchor = localized.helpAnchor {
            info[NSHelpAnchorErrorKey] = anchor
        }
    }
    return info.isEmpty ? nil : info as NSDictionary
}

// MARK: - Errors any NSError of a domain converts to

/// Describes an error type that can be created from an NSError.
@available(macOS 10.10, iOS 8.0, watchOS 2.0, tvOS 9.0, *)
public protocol _ObjectiveCBridgeableError: Error {
    /// Produce a value of the error type corresponding to the given NSError,
    /// or nil if it cannot be bridged.
    init?(_bridgedNSError: __shared NSError)
}

/// The runtime's conversion of an NSError to a Swift error type, when a
/// thrown NSError is caught as one: whether it converted.
@available(macOS 10.10, iOS 8.0, watchOS 2.0, tvOS 9.0, *)
public func _bridgeNSErrorToError<T>(_ error: NSError, out: UnsafeMutablePointer<T>) -> Bool where T: _ObjectiveCBridgeableError {
    guard let bridged = T(_bridgedNSError: error) else { return false }
    out.initialize(to: bridged)
    return true
}

// MARK: - Error enums whose raw value is the code

/// An error enum with raw values, bridged to NSErrors of one domain.
@available(macOS 10.10, iOS 8.0, watchOS 2.0, tvOS 9.0, *)
public protocol _BridgedNSError: _ObjectiveCBridgeableError, Hashable, RawRepresentable where Self.RawValue: FixedWidthInteger {
    static var _nsErrorDomain: String { get }
}

@available(macOS 10.10, iOS 8.0, watchOS 2.0, tvOS 9.0, *)
extension _BridgedNSError {
    public var _domain: String { Self._nsErrorDomain }
}

@available(macOS 10.10, iOS 8.0, watchOS 2.0, tvOS 9.0, *)
extension _BridgedNSError {
    public var _code: Int { numericCast(rawValue) }

    public init?(_bridgedNSError: __shared NSError) {
        guard _bridgedNSError.domain == Self._nsErrorDomain else { return nil }
        self.init(rawValue: RawValue(exactly: _bridgedNSError.code) ?? 0)
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(_code)
    }
}

// MARK: - Errors kept as an NSError

/// An error code of a _BridgedStoredNSError type.
@available(macOS 10.10, iOS 8.0, watchOS 2.0, tvOS 9.0, *)
public protocol _ErrorCodeProtocol: Equatable {
    /// The corresponding error code.
    associatedtype _ErrorType: _BridgedStoredNSError where _ErrorType.Code == Self
}

@available(macOS 10.10, iOS 8.0, watchOS 2.0, tvOS 9.0, *)
extension _ErrorCodeProtocol {
    /// Allows one to match an error code within a `catch` clause.
    public static func ~= (match: Self, error: any Error) -> Bool {
        guard let specificError = error as? Self._ErrorType else { return false }
        return match == specificError.code
    }
}

/// An error type stored as the NSError it bridges to.
@available(macOS 10.10, iOS 8.0, watchOS 2.0, tvOS 9.0, *)
public protocol _BridgedStoredNSError: CustomNSError, _ObjectiveCBridgeableError, Hashable {
    /// The type of the error code.
    associatedtype Code: _ErrorCodeProtocol, RawRepresentable where Self.Code.RawValue: FixedWidthInteger

    /// The error this value holds.
    var _nsError: NSError { get }

    /// Describes an error, from an NSError of its domain.
    init(_nsError error: NSError)
}

@available(macOS 10.10, iOS 8.0, watchOS 2.0, tvOS 9.0, *)
extension _BridgedStoredNSError {
    /// The error code.
    public var code: Code {
        Code(rawValue: Code.RawValue(exactly: _nsError.code) ?? 0)!
    }

    /// Initialize an error within this domain with the given code and
    /// user-info dictionary.
    public init(_ code: Code, userInfo: [String: Any] = [:]) {
        self.init(_nsError: NSError(domain: Self.errorDomain, code: numericCast(code.rawValue),
                                    userInfo: userInfo.isEmpty ? nil : userInfo))
    }

    /// The user-info dictionary for an error that was bridged from NSError.
    public var userInfo: [String: Any] { errorUserInfo }
}

@available(macOS 10.10, iOS 8.0, watchOS 2.0, tvOS 9.0, *)
extension _BridgedStoredNSError {
    public init?(_bridgedNSError error: NSError) {
        guard error.domain == Self.errorDomain else { return nil }
        self.init(_nsError: error)
    }
}

@available(macOS 10.10, iOS 8.0, watchOS 2.0, tvOS 9.0, *)
extension _BridgedStoredNSError {
    public var errorCode: Int { _nsError.code }

    public var errorUserInfo: [String: Any] {
        var result: [String: Any] = [:]
        for (key, value) in _nsError.userInfo {
            guard let key = key as? String else { continue }
            result[key] = value
        }
        return result
    }
}

@available(macOS 10.10, iOS 8.0, watchOS 2.0, tvOS 9.0, *)
extension _BridgedStoredNSError {
    public func hash(into hasher: inout Hasher) {
        hasher.combine(_nsError)
    }

    @_alwaysEmitIntoClient
    public var hashValue: Int { _nsError.hashValue }
}

@available(macOS 10.10, iOS 8.0, watchOS 2.0, tvOS 9.0, *)
extension _BridgedStoredNSError {
    public func _getEmbeddedNSError() -> AnyObject? { _nsError }

    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs._nsError.isEqual(rhs._nsError)
    }
}

// MARK: - CocoaError

// swift-foundation keeps a CocoaError's code and user info itself; here it
// also bridges as Darwin's does, to an NSError of the Cocoa domain.
@available(macOS 10.10, iOS 8.0, watchOS 2.0, tvOS 9.0, *)
extension CocoaError: _BridgedStoredNSError {
    public var _nsError: NSError {
        NSError(domain: NSCocoaErrorDomain, code: code.rawValue, userInfo: userInfo.isEmpty ? nil : userInfo)
    }

    public init(_nsError error: NSError) {
        var info: [String: Any] = [:]
        for (key, value) in error.userInfo {
            if let key = key as? String { info[key] = value }
        }
        self.init(Code(rawValue: error.code), userInfo: info)
    }

    public var errorCode: Int { code.rawValue }
    public var errorUserInfo: [String: Any] { userInfo }

    public static func == (lhs: CocoaError, rhs: CocoaError) -> Bool {
        lhs.code == rhs.code
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(code)
    }
}

@available(macOS 10.10, iOS 8.0, watchOS 2.0, tvOS 9.0, *)
extension CocoaError.Code: _ErrorCodeProtocol {
    public typealias _ErrorType = CocoaError
}

// The codes swift-foundation leaves to Darwin's build.
@available(macOS 10.10, iOS 8.0, watchOS 2.0, tvOS 9.0, *)
extension CocoaError.Code {
    public static var xpcConnectionInterrupted: CocoaError.Code { CocoaError.Code(rawValue: 4097) }
    public static var xpcConnectionInvalid: CocoaError.Code { CocoaError.Code(rawValue: 4099) }
    public static var xpcConnectionReplyInvalid: CocoaError.Code { CocoaError.Code(rawValue: 4101) }
    public static var ubiquitousFileUnavailable: CocoaError.Code { CocoaError.Code(rawValue: 4353) }
    public static var ubiquitousFileNotUploadedDueToQuota: CocoaError.Code { CocoaError.Code(rawValue: 4354) }
    public static var ubiquitousFileUbiquityServerNotAvailable: CocoaError.Code { CocoaError.Code(rawValue: 4355) }
    public static var userActivityHandoffFailed: CocoaError.Code { CocoaError.Code(rawValue: 4608) }
    public static var userActivityConnectionUnavailable: CocoaError.Code { CocoaError.Code(rawValue: 4609) }
    public static var userActivityRemoteApplicationTimedOut: CocoaError.Code { CocoaError.Code(rawValue: 4610) }
    public static var userActivityHandoffUserInfoTooLarge: CocoaError.Code { CocoaError.Code(rawValue: 4611) }
    public static var coderReadCorrupt: CocoaError.Code { CocoaError.Code(rawValue: 4864) }
    public static var coderValueNotFound: CocoaError.Code { CocoaError.Code(rawValue: 4865) }
    public static var coderInvalidValue: CocoaError.Code { CocoaError.Code(rawValue: 4866) }
}

// MARK: - CFError

extension CFError: Error, @unchecked Sendable {
    public var _domain: String { (self as AnyObject as! NSError).domain }
    public var _code: Int { (self as AnyObject as! NSError).code }
    public var _userInfo: AnyObject? { (self as AnyObject as! NSError).userInfo as NSDictionary }
    public func _getEmbeddedNSError() -> AnyObject? { self }
}
