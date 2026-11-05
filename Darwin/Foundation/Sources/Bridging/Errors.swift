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
    // An NSError thrown as itself; any other error by its domain and code.
    if let embedded = error._getEmbeddedNSError(), let error = embedded as? NSError { return error }
    return NSError(domain: error._domain, code: error._code, userInfo: nil)
}
