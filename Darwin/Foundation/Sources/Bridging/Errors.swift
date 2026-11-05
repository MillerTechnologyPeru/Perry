// NSError as a Swift Error, and the conversions the compiler calls at
// every throwing Objective-C method: an NSError ** out-parameter is thrown
// as the error it holds, and a Swift error passed back to Objective-C is an
// NSError.

@available(macOS 10.10, iOS 8.0, watchOS 2.0, tvOS 9.0, *)
extension NSError: Error {
    @nonobjc public var _domain: String { domain }
    @nonobjc public var _code: Int { code }
    @nonobjc public var _userInfo: AnyObject? { userInfo as NSDictionary }
    @nonobjc public func _getEmbeddedNSError() -> AnyObject? { self }
}

/// What a method that returned failure without an error throws.
enum _GenericObjCError: Error {
    case nilError
}

@available(macOS 10.10, iOS 8.0, watchOS 2.0, tvOS 9.0, *)
public func _convertNSErrorToError(_ error: NSError?) -> any Error {
    error ?? _GenericObjCError.nilError
}

@available(macOS 10.10, iOS 8.0, watchOS 2.0, tvOS 9.0, *)
public func _convertErrorToNSError(_ error: any Error) -> NSError {
    // The runtime's: an NSError as itself, any other error boxed in one.
    unsafeDowncast(_bridgeErrorToNSError(error), to: NSError.self)
}

// MARK: - The Swift runtime's bridging

// A CFError is an NSError, toll-free.
@available(macOS 10.10, iOS 8.0, watchOS 2.0, tvOS 9.0, *)
extension CFError: Error, @unchecked Sendable {
    private var nsError: NSError { unsafeBitCast(self, to: NSError.self) }
    public var _domain: String { nsError.domain }
    public var _code: Int { nsError.code }
    public var _userInfo: AnyObject? { nsError.userInfo as NSDictionary }
    public func _getEmbeddedNSError() -> AnyObject? { nsError }
}

/// An error that Swift's runtime can make from an NSError, when `as?` casts
/// one to it.
@available(macOS 10.10, iOS 8.0, watchOS 2.0, tvOS 9.0, *)
public protocol _ObjectiveCBridgeableError: Error {
    init?(_bridgedNSError: __shared NSError)
}

/// How the runtime casts an NSError to an error type that bridges it.
@available(macOS 10.10, iOS 8.0, watchOS 2.0, tvOS 9.0, *)
public func _bridgeNSErrorToError<T: _ObjectiveCBridgeableError>(_ error: NSError, out: UnsafeMutablePointer<T>) -> Bool {
    guard let bridged = T(_bridgedNSError: error) else { return false }
    out.initialize(to: bridged)
    return true
}

/// An error's domain, code and user info for its NSError.
@available(macOS 10.10, iOS 8.0, watchOS 2.0, tvOS 9.0, *)
public protocol CustomNSError: Error {
    static var errorDomain: String { get }
    var errorCode: Int { get }
    var errorUserInfo: [String: Any] { get }
}

@available(macOS 10.10, iOS 8.0, watchOS 2.0, tvOS 9.0, *)
extension CustomNSError {
    public static var errorDomain: String { _typeName(self, qualified: true) }
    public var errorCode: Int { _getDefaultErrorCode(self) }
    public var errorUserInfo: [String: Any] { [:] }
}

@available(macOS 10.10, iOS 8.0, watchOS 2.0, tvOS 9.0, *)
extension CustomNSError where Self: RawRepresentable, Self.RawValue: FixedWidthInteger {
    public var errorCode: Int { Int(truncatingIfNeeded: rawValue) }
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

/// The user info of a Swift error's NSError, which the runtime asks for: a
/// CustomNSError's own. A LocalizedError's messages come from its domain's
/// user info provider, which asks the error itself.
@available(macOS 10.10, iOS 8.0, watchOS 2.0, tvOS 9.0, *)
public func _getErrorDefaultUserInfo<T: Error>(_ error: T) -> AnyObject? {
    if error is LocalizedError || error is RecoverableError { LocalizedMessages.provide(for: error._domain) }
    return (error as? CustomNSError).map { $0.errorUserInfo as NSDictionary }
}

/// The user info values of the Swift errors in a domain that describe
/// themselves.
private enum LocalizedMessages {
    nonisolated(unsafe) static var domains: Set<String> = []
    static let lock = NSLock()

    static func provide(for domain: String) {
        lock.lock()
        defer { lock.unlock() }
        guard domains.insert(domain).inserted else { return }
        NSError.setUserInfoValueProvider(forDomain: domain) { error, key in
            let error = error as Error
            let localized = error as? LocalizedError
            switch key {
            case NSLocalizedDescriptionKey: return localized?.errorDescription
            case NSLocalizedFailureReasonErrorKey: return localized?.failureReason
            case NSLocalizedRecoverySuggestionErrorKey: return localized?.recoverySuggestion
            case NSHelpAnchorErrorKey: return localized?.helpAnchor
            case NSLocalizedRecoveryOptionsErrorKey: return (error as? RecoverableError)?.recoveryOptions
            default: return nil
            }
        }
    }
}

/// An error that offers ways to recover from it.
@available(macOS 10.10, iOS 8.0, watchOS 2.0, tvOS 9.0, *)
public protocol RecoverableError: Error {
    var recoveryOptions: [String] { get }
    func attemptRecovery(optionIndex recoveryOptionIndex: Int, resultHandler handler: @escaping (_ recovered: Bool) -> Void)
    func attemptRecovery(optionIndex recoveryOptionIndex: Int) -> Bool
}

@available(macOS 10.10, iOS 8.0, watchOS 2.0, tvOS 9.0, *)
extension RecoverableError {
    public func attemptRecovery(optionIndex recoveryOptionIndex: Int, resultHandler handler: @escaping (_ recovered: Bool) -> Void) {
        handler(attemptRecovery(optionIndex: recoveryOptionIndex))
    }
}

@available(macOS 10.10, iOS 8.0, watchOS 2.0, tvOS 9.0, *)
extension Error {
    /// Its NSError's description.
    public var localizedDescription: String { (self as NSError).localizedDescription }
}

// MARK: - Errors imported from Objective-C

// The compiler makes a struct of each NS_ERROR_ENUM a framework's headers
// declare (WKError, AVError…), in the module that imports it, over these.

/// The code of a bridged NSError, which matches errors of its type.
@available(macOS 10.10, iOS 8.0, watchOS 2.0, tvOS 9.0, *)
public protocol _ErrorCodeProtocol: Equatable {
    associatedtype _ErrorType: _BridgedStoredNSError where _ErrorType.Code == Self
}

@available(macOS 10.10, iOS 8.0, watchOS 2.0, tvOS 9.0, *)
extension _ErrorCodeProtocol {
    public static func ~= (match: Self, error: any Error) -> Bool {
        guard let error = error as? _ErrorType else { return false }
        return match == error.code
    }
}

/// An error enum whose raw value is an NSError's code in its domain.
@available(macOS 10.10, iOS 8.0, watchOS 2.0, tvOS 9.0, *)
public protocol _BridgedNSError: _ObjectiveCBridgeableError, Hashable, RawRepresentable
    where Self.RawValue: FixedWidthInteger {
    static var _nsErrorDomain: String { get }
}

@available(macOS 10.10, iOS 8.0, watchOS 2.0, tvOS 9.0, *)
extension _BridgedNSError {
    public var _domain: String { Self._nsErrorDomain }
}

@available(macOS 10.10, iOS 8.0, watchOS 2.0, tvOS 9.0, *)
extension _BridgedNSError {
    public var _code: Int { Int(truncatingIfNeeded: rawValue) }

    public init?(_bridgedNSError: __shared NSError) {
        guard _bridgedNSError.domain == Self._nsErrorDomain else { return nil }
        self.init(rawValue: RawValue(truncatingIfNeeded: _bridgedNSError.code))
    }

    public func hash(into hasher: inout Hasher) { hasher.combine(_code) }
}

/// An error that keeps the NSError it stands for, with a code in its domain.
@available(macOS 10.10, iOS 8.0, watchOS 2.0, tvOS 9.0, *)
public protocol _BridgedStoredNSError: CustomNSError, _ObjectiveCBridgeableError, Hashable {
    associatedtype Code: _ErrorCodeProtocol, RawRepresentable where Self.Code.RawValue: FixedWidthInteger
    var _nsError: NSError { get }
    init(_nsError error: NSError)
}

@available(macOS 10.10, iOS 8.0, watchOS 2.0, tvOS 9.0, *)
extension _BridgedStoredNSError {
    public var code: Code { Code(rawValue: Code.RawValue(truncatingIfNeeded: _nsError.code))! }

    public init(_ code: Code, userInfo: [String: Any] = [:]) {
        self.init(_nsError: NSError(domain: Self.errorDomain, code: Int(truncatingIfNeeded: code.rawValue),
                                    userInfo: userInfo))
    }

    public var userInfo: [String: Any] { _nsError.userInfo }
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
    public var errorUserInfo: [String: Any] { _nsError.userInfo }
}

@available(macOS 10.10, iOS 8.0, watchOS 2.0, tvOS 9.0, *)
extension _BridgedStoredNSError {
    public func hash(into hasher: inout Hasher) { _nsError.hash(into: &hasher) }
    @_alwaysEmitIntoClient public var hashValue: Int { _nsError.hashValue }
}

@available(macOS 10.10, iOS 8.0, watchOS 2.0, tvOS 9.0, *)
extension _BridgedStoredNSError {
    public func _getEmbeddedNSError() -> AnyObject? { _nsError }
    public static func == (lhs: Self, rhs: Self) -> Bool { lhs._nsError.isEqual(rhs._nsError) }
}
