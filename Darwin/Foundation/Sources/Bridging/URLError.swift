// URLError, an NSError of the URL loading domain kept as one, as Darwin's
// Foundation declares it, with its codes: NSURLError.h's values.

@available(macOS 10.10, iOS 8.0, watchOS 2.0, tvOS 9.0, *)
public struct URLError: _BridgedStoredNSError {
    public let _nsError: NSError

    public init(_nsError error: NSError) {
        precondition(error.domain == NSURLErrorDomain)
        _nsError = error
    }

    public static var errorDomain: String { NSURLErrorDomain }

    public var hashValue: Int { _nsError.hashValue }

    /// The error code in the URL loading domain.
    public struct Code: RawRepresentable, Hashable, _ErrorCodeProtocol, Sendable {
        public typealias _ErrorType = URLError

        public let rawValue: Int

        public init(rawValue: Int) {
            self.rawValue = rawValue
        }
    }
}

@available(macOS 10.10, iOS 8.0, watchOS 2.0, tvOS 9.0, *)
extension URLError.Code {
    public static var unknown: URLError.Code { URLError.Code(rawValue: NSURLErrorUnknown) }
    public static var cancelled: URLError.Code { URLError.Code(rawValue: NSURLErrorCancelled) }
    public static var badURL: URLError.Code { URLError.Code(rawValue: NSURLErrorBadURL) }
    public static var timedOut: URLError.Code { URLError.Code(rawValue: NSURLErrorTimedOut) }
    public static var unsupportedURL: URLError.Code { URLError.Code(rawValue: NSURLErrorUnsupportedURL) }
    public static var cannotFindHost: URLError.Code { URLError.Code(rawValue: NSURLErrorCannotFindHost) }
    public static var cannotConnectToHost: URLError.Code { URLError.Code(rawValue: NSURLErrorCannotConnectToHost) }
    public static var networkConnectionLost: URLError.Code { URLError.Code(rawValue: NSURLErrorNetworkConnectionLost) }
    public static var dnsLookupFailed: URLError.Code { URLError.Code(rawValue: NSURLErrorDNSLookupFailed) }
    public static var httpTooManyRedirects: URLError.Code { URLError.Code(rawValue: NSURLErrorHTTPTooManyRedirects) }
    public static var resourceUnavailable: URLError.Code { URLError.Code(rawValue: NSURLErrorResourceUnavailable) }
    public static var notConnectedToInternet: URLError.Code { URLError.Code(rawValue: NSURLErrorNotConnectedToInternet) }
    public static var redirectToNonExistentLocation: URLError.Code { URLError.Code(rawValue: NSURLErrorRedirectToNonExistentLocation) }
    public static var badServerResponse: URLError.Code { URLError.Code(rawValue: NSURLErrorBadServerResponse) }
    public static var userCancelledAuthentication: URLError.Code { URLError.Code(rawValue: NSURLErrorUserCancelledAuthentication) }
    public static var userAuthenticationRequired: URLError.Code { URLError.Code(rawValue: NSURLErrorUserAuthenticationRequired) }
    public static var zeroByteResource: URLError.Code { URLError.Code(rawValue: NSURLErrorZeroByteResource) }
    public static var cannotDecodeRawData: URLError.Code { URLError.Code(rawValue: NSURLErrorCannotDecodeRawData) }
    public static var cannotDecodeContentData: URLError.Code { URLError.Code(rawValue: NSURLErrorCannotDecodeContentData) }
    public static var cannotParseResponse: URLError.Code { URLError.Code(rawValue: NSURLErrorCannotParseResponse) }
    public static var appTransportSecurityRequiresSecureConnection: URLError.Code { URLError.Code(rawValue: NSURLErrorAppTransportSecurityRequiresSecureConnection) }
    public static var fileDoesNotExist: URLError.Code { URLError.Code(rawValue: NSURLErrorFileDoesNotExist) }
    public static var fileIsDirectory: URLError.Code { URLError.Code(rawValue: NSURLErrorFileIsDirectory) }
    public static var noPermissionsToReadFile: URLError.Code { URLError.Code(rawValue: NSURLErrorNoPermissionsToReadFile) }
    public static var dataLengthExceedsMaximum: URLError.Code { URLError.Code(rawValue: NSURLErrorDataLengthExceedsMaximum) }
    public static var secureConnectionFailed: URLError.Code { URLError.Code(rawValue: NSURLErrorSecureConnectionFailed) }
    public static var serverCertificateHasBadDate: URLError.Code { URLError.Code(rawValue: NSURLErrorServerCertificateHasBadDate) }
    public static var serverCertificateUntrusted: URLError.Code { URLError.Code(rawValue: NSURLErrorServerCertificateUntrusted) }
    public static var serverCertificateHasUnknownRoot: URLError.Code { URLError.Code(rawValue: NSURLErrorServerCertificateHasUnknownRoot) }
    public static var serverCertificateNotYetValid: URLError.Code { URLError.Code(rawValue: NSURLErrorServerCertificateNotYetValid) }
    public static var clientCertificateRejected: URLError.Code { URLError.Code(rawValue: NSURLErrorClientCertificateRejected) }
    public static var clientCertificateRequired: URLError.Code { URLError.Code(rawValue: NSURLErrorClientCertificateRequired) }
    public static var cannotLoadFromNetwork: URLError.Code { URLError.Code(rawValue: NSURLErrorCannotLoadFromNetwork) }
    public static var cannotCreateFile: URLError.Code { URLError.Code(rawValue: NSURLErrorCannotCreateFile) }
    public static var cannotOpenFile: URLError.Code { URLError.Code(rawValue: NSURLErrorCannotOpenFile) }
    public static var cannotCloseFile: URLError.Code { URLError.Code(rawValue: NSURLErrorCannotCloseFile) }
    public static var cannotWriteToFile: URLError.Code { URLError.Code(rawValue: NSURLErrorCannotWriteToFile) }
    public static var cannotRemoveFile: URLError.Code { URLError.Code(rawValue: NSURLErrorCannotRemoveFile) }
    public static var cannotMoveFile: URLError.Code { URLError.Code(rawValue: NSURLErrorCannotMoveFile) }
    public static var downloadDecodingFailedMidStream: URLError.Code { URLError.Code(rawValue: NSURLErrorDownloadDecodingFailedMidStream) }
    public static var downloadDecodingFailedToComplete: URLError.Code { URLError.Code(rawValue: NSURLErrorDownloadDecodingFailedToComplete) }
    public static var internationalRoamingOff: URLError.Code { URLError.Code(rawValue: NSURLErrorInternationalRoamingOff) }
    public static var callIsActive: URLError.Code { URLError.Code(rawValue: NSURLErrorCallIsActive) }
    public static var dataNotAllowed: URLError.Code { URLError.Code(rawValue: NSURLErrorDataNotAllowed) }
    public static var requestBodyStreamExhausted: URLError.Code { URLError.Code(rawValue: NSURLErrorRequestBodyStreamExhausted) }
    public static var backgroundSessionRequiresSharedContainer: URLError.Code { URLError.Code(rawValue: NSURLErrorBackgroundSessionRequiresSharedContainer) }
    public static var backgroundSessionInUseByAnotherProcess: URLError.Code { URLError.Code(rawValue: NSURLErrorBackgroundSessionInUseByAnotherProcess) }
    public static var backgroundSessionWasDisconnected: URLError.Code { URLError.Code(rawValue: NSURLErrorBackgroundSessionWasDisconnected) }
}

@available(macOS 10.10, iOS 8.0, watchOS 2.0, tvOS 9.0, *)
extension URLError {
    public static var unknown: URLError.Code { .unknown }
    public static var cancelled: URLError.Code { .cancelled }
    public static var badURL: URLError.Code { .badURL }
    public static var timedOut: URLError.Code { .timedOut }
    public static var unsupportedURL: URLError.Code { .unsupportedURL }
    public static var cannotFindHost: URLError.Code { .cannotFindHost }
    public static var cannotConnectToHost: URLError.Code { .cannotConnectToHost }
    public static var networkConnectionLost: URLError.Code { .networkConnectionLost }
    public static var dnsLookupFailed: URLError.Code { .dnsLookupFailed }
    public static var httpTooManyRedirects: URLError.Code { .httpTooManyRedirects }
    public static var resourceUnavailable: URLError.Code { .resourceUnavailable }
    public static var notConnectedToInternet: URLError.Code { .notConnectedToInternet }
    public static var redirectToNonExistentLocation: URLError.Code { .redirectToNonExistentLocation }
    public static var badServerResponse: URLError.Code { .badServerResponse }
    public static var userCancelledAuthentication: URLError.Code { .userCancelledAuthentication }
    public static var userAuthenticationRequired: URLError.Code { .userAuthenticationRequired }
    public static var zeroByteResource: URLError.Code { .zeroByteResource }
    public static var cannotDecodeRawData: URLError.Code { .cannotDecodeRawData }
    public static var cannotDecodeContentData: URLError.Code { .cannotDecodeContentData }
    public static var cannotParseResponse: URLError.Code { .cannotParseResponse }
    public static var appTransportSecurityRequiresSecureConnection: URLError.Code { .appTransportSecurityRequiresSecureConnection }
    public static var fileDoesNotExist: URLError.Code { .fileDoesNotExist }
    public static var fileIsDirectory: URLError.Code { .fileIsDirectory }
    public static var noPermissionsToReadFile: URLError.Code { .noPermissionsToReadFile }
    public static var dataLengthExceedsMaximum: URLError.Code { .dataLengthExceedsMaximum }
    public static var secureConnectionFailed: URLError.Code { .secureConnectionFailed }
    public static var serverCertificateHasBadDate: URLError.Code { .serverCertificateHasBadDate }
    public static var serverCertificateUntrusted: URLError.Code { .serverCertificateUntrusted }
    public static var serverCertificateHasUnknownRoot: URLError.Code { .serverCertificateHasUnknownRoot }
    public static var serverCertificateNotYetValid: URLError.Code { .serverCertificateNotYetValid }
    public static var clientCertificateRejected: URLError.Code { .clientCertificateRejected }
    public static var clientCertificateRequired: URLError.Code { .clientCertificateRequired }
    public static var cannotLoadFromNetwork: URLError.Code { .cannotLoadFromNetwork }
    public static var cannotCreateFile: URLError.Code { .cannotCreateFile }
    public static var cannotOpenFile: URLError.Code { .cannotOpenFile }
    public static var cannotCloseFile: URLError.Code { .cannotCloseFile }
    public static var cannotWriteToFile: URLError.Code { .cannotWriteToFile }
    public static var cannotRemoveFile: URLError.Code { .cannotRemoveFile }
    public static var cannotMoveFile: URLError.Code { .cannotMoveFile }
    public static var downloadDecodingFailedMidStream: URLError.Code { .downloadDecodingFailedMidStream }
    public static var downloadDecodingFailedToComplete: URLError.Code { .downloadDecodingFailedToComplete }
    public static var internationalRoamingOff: URLError.Code { .internationalRoamingOff }
    public static var callIsActive: URLError.Code { .callIsActive }
    public static var dataNotAllowed: URLError.Code { .dataNotAllowed }
    public static var requestBodyStreamExhausted: URLError.Code { .requestBodyStreamExhausted }
    public static var backgroundSessionRequiresSharedContainer: URLError.Code { .backgroundSessionRequiresSharedContainer }
    public static var backgroundSessionInUseByAnotherProcess: URLError.Code { .backgroundSessionInUseByAnotherProcess }
    public static var backgroundSessionWasDisconnected: URLError.Code { .backgroundSessionWasDisconnected }
}

@available(macOS 10.10, iOS 8.0, watchOS 2.0, tvOS 9.0, *)
extension URLError {
    /// Why a background task was cancelled.
    public enum BackgroundTaskCancelledReason: Int, Sendable {
        case userForceQuitApplication
        case backgroundUpdatesDisabled
        case insufficientSystemResources
    }

    /// Why the network was unavailable.
    public enum NetworkUnavailableReason: Int, Sendable {
        case cellular
        case expensive
        case constrained
        case ultraConstrained
    }

    private var info: [AnyHashable: Any] { _nsError.userInfo }

    /// The URL which caused a load to fail.
    public var failingURL: URL? {
        (info[NSURLErrorFailingURLErrorKey] as? NSURL).flatMap { URL._bridging($0) }
    }

    /// The string for the URL which caused a load to fail.
    public var failureURLString: String? {
        info[NSURLErrorFailingURLStringErrorKey] as? String
    }

    /// Why a background task was cancelled.
    public var backgroundTaskCancelledReason: BackgroundTaskCancelledReason? {
        (info[NSURLErrorBackgroundTaskCancelledReasonKey] as? NSNumber).flatMap { BackgroundTaskCancelledReason(rawValue: $0.intValue) }
    }

    /// Why the network was unavailable.
    public var networkUnavailableReason: NetworkUnavailableReason? {
        (info[NSURLErrorNetworkUnavailableReasonKey] as? NSNumber).flatMap { NetworkUnavailableReason(rawValue: $0.intValue) }
    }

    /// Data to resume a failed download with.
    public var downloadTaskResumeData: Data? {
        (info[NSURLSessionDownloadTaskResumeData] as? NSData).map { Data(_bridging: $0) }
    }
}
