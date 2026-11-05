// CocoaError's bridging to NSError, as Darwin's Foundation declares it:
// the error protocols themselves are in Errors.swift.

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
