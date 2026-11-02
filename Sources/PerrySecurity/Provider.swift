import CPerrySecurity
import FoundationEssentials
import Glibc
import PerryInterface
import PerryObjCInterop

// libPerrySecurity: the provider for Security.framework, over swift-crypto
// (CryptoKit's API with its own BoringSSL) and swift-certificates.
// PerryProviderPlugin generates its perry_provider_startup and
// perry_provider_symbol from the module's Objective-C declarations; this
// file adds the provider's own steps. Security's objects (SecKey,
// SecCertificate, SecTrust, SecPolicy) are Objective-C objects, as Darwin's
// CoreFoundation types are, so CFRetain and CFRelease work on them.

private let libobjc = "/usr/lib/libobjc.A.dylib"

func providerWillStart(_ info: perry_startup_info) -> Bool {
    guard info.version >= 2, let lookup = info.lookup_symbol else { return false }
    let loaded = ObjCRuntime.load { name in
        libobjc.withCString { library in name.withCString { lookup(library, $0) } }
    }
    guard loaded, Classes.named("NSDictionary") != nil else {
        securityFatal("Security needs libPerryobjc and libPerryFoundation, which are missing or incomplete")
    }
    Dispatch.load { name in
        "/usr/lib/libSystem.B.dylib".withCString { library in name.withCString { lookup(library, $0) } }
    }
    return true
}

func securityFatal(_ message: String) -> Never {
    let line = "perry: Security: *** \(message)\n"
    line.withCString { _ = write(2, $0, strlen($0)) }
    abort()
}

enum Classes {
    static func named(_ name: String) -> ObjCClass? {
        name.withCString { ObjCRuntime.functions.getClass($0) }.map(ObjCClass.init)
    }
}

/// libdispatch, for SecTrustEvaluateAsyncWithError.
enum Dispatch {
    typealias Function = @convention(c) (UnsafeMutableRawPointer?) -> Void
    typealias Async = @convention(c) (UnsafeMutableRawPointer?, UnsafeMutableRawPointer?, Function) -> Void
    nonisolated(unsafe) static var async: Async?

    static func load(_ lookup: (String) -> UnsafeMutableRawPointer?) {
        async = lookup("_dispatch_async_f").map { unsafeBitCast($0, to: Async.self) }
    }
}

/// A mutex.
final class Lock: @unchecked Sendable {
    private let mutex = UnsafeMutablePointer<pthread_mutex_t>.allocate(capacity: 1)

    init() {
        var attributes = pthread_mutexattr_t()
        pthread_mutexattr_init(&attributes)
        pthread_mutexattr_settype(&attributes, Int32(PTHREAD_MUTEX_RECURSIVE))
        pthread_mutex_init(mutex, &attributes)
        pthread_mutexattr_destroy(&attributes)
    }

    func withLock<T>(_ body: () throws -> T) rethrows -> T {
        pthread_mutex_lock(mutex)
        defer { pthread_mutex_unlock(mutex) }
        return try body()
    }
}

/// Swift state per Objective-C object, from creation until -dealloc.
final class StateTable<State: AnyObject>: @unchecked Sendable {
    private let lock = Lock()
    private var states: [UnsafeMutableRawPointer: State] = [:]

    subscript(object: UnsafeMutableRawPointer?) -> State? {
        guard let object else { return nil }
        return lock.withLock { states[object] }
    }

    func set(_ object: UnsafeMutableRawPointer, _ state: State) { lock.withLock { states[object] = state } }

    func remove(_ object: UnsafeMutableRawPointer) {
        let state = lock.withLock { states.removeValue(forKey: object) }
        _ = state
    }
}

/// OSStatus codes.
enum Status {
    static let success: Int32 = 0
    static let unimplemented: Int32 = -4
    static let param: Int32 = -50
    static let allocate: Int32 = -108
    static let duplicateItem: Int32 = -25299
    static let itemNotFound: Int32 = -25300
    static let interactionNotAllowed: Int32 = -25308
    static let decode: Int32 = -26275
    static let missingEntitlement: Int32 = -34018
    static let verifyFailed: Int32 = -67808
    static let notTrusted: Int32 = -67843
    static let hostNameMismatch: Int32 = -67602
    static let certificateExpired: Int32 = -67818
    static let certificateNotValidYet: Int32 = -67819
    static let unsupportedAlgorithm: Int32 = -67748
    static let invalidKey: Int32 = -67712

    static func message(_ status: Int32) -> String {
        switch status {
        case success: return "No error."
        case unimplemented: return "Function or operation not implemented."
        case param: return "One or more parameters passed to a function were not valid."
        case allocate: return "Failed to allocate memory."
        case duplicateItem: return "The specified item already exists in the keychain."
        case itemNotFound: return "The specified item could not be found in the keychain."
        case interactionNotAllowed: return "User interaction is not allowed."
        case decode: return "Unable to decode the provided data."
        case missingEntitlement: return "A required entitlement isn't present."
        case verifyFailed: return "A cryptographic verification failure has occurred."
        case notTrusted: return "The trust policy was not trusted."
        case hostNameMismatch: return "A host name mismatch has occurred."
        case certificateExpired: return "An expired certificate was detected."
        case certificateNotValidYet: return "The certificate is not yet valid."
        case unsupportedAlgorithm: return "The algorithm is not supported."
        case invalidKey: return "The key is not valid."
        default: return "OSStatus \(status)"
        }
    }

    /// A CFErrorRef (+1) in NSOSStatusErrorDomain, as Security reports.
    static func error(_ status: Int32, _ description: String? = nil) -> UnsafeMutableRawPointer? {
        let info = NSMutableDictionary.of([("NSDescription", NSObject.string(description ?? message(status)))])
        return ObjCRuntime.retain(NSError.make(domain: "NSOSStatusErrorDomain", code: Int(status), userInfo: info).objcObject)
    }

    /// Sets an out-parameter error, if the caller asked for one.
    static func report(_ out: UnsafeMutablePointer<UnsafeMutableRawPointer?>?, _ status: Int32, _ description: String? = nil) {
        out?.pointee = error(status, description)
    }
}

@c(_SecCopyErrorMessageString)
public func SecCopyErrorMessageString(_ status: Int32, _ reserved: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer? {
    ObjCRuntime.retain(NSObject.string(Status.message(status)).objcObject)
}

@c(_SecRandomCopyBytes)
public func SecRandomCopyBytes(_ generator: UnsafeRawPointer?, _ count: Int, _ bytes: UnsafeMutableRawPointer?) -> Int32 {
    guard let bytes else { return count == 0 ? 0 : Status.param }
    var random = SystemRandomNumberGenerator()
    let buffer = bytes.assumingMemoryBound(to: UInt8.self)
    for index in 0..<count { buffer[index] = UInt8.random(in: 0...255, using: &random) }
    return 0
}
