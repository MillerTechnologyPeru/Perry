import CPerryGeometry
import CPerryMetal
import Glibc
import PerryObjCInterop

// The Foundation and libdispatch calls Metal makes, metal2vulkan's library,
// and Metal's errors.

@ObjCWrapper("NSDictionary")
class NSDictionary: NSObject {
    @ObjCClassMethod("dictionaryWithObject:forKey:") static func make(object: NSObject, key: String) -> NSDictionary
}

@ObjCWrapper("NSError")
class NSError: NSObject {
    @ObjCClassMethod("errorWithDomain:code:userInfo:")
    static func make(domain: String, code: Int, userInfo: NSObject?) -> NSError
}

@ObjCWrapper("NSBundle")
class NSBundle: NSObject {
    @ObjCClassMethod("mainBundle") static func main() -> NSBundle
    @ObjCMethod("pathForResource:ofType:") func path(forResource name: String, ofType type: String) -> String?
}

@ObjCWrapper("NSURL")
class NSURL: NSObject {
    @ObjCMethod("path") func path() -> String?
}

extension PerryRange: ObjCScalar {
    public static var objCTypeEncoding: String { "{_NSRange=QQ}" }
}

/// Metal's error domains.
@ObjCConstants
enum MetalConstants {
    static let MTLLibraryErrorDomain = "MTLLibraryErrorDomain"
    static let MTLCommandBufferErrorDomain = "MTLCommandBufferErrorDomain"
    static let MTLCommandBufferEncoderInfoErrorKey = "MTLCommandBufferEncoderInfoErrorKey"
}

/// MTLLibraryError's codes.
enum LibraryError {
    static let unsupported = 1
    static let compileFailure = 3
    static let functionNotFound = 5
    static let fileNotFound = 6
}

enum Errors {
    /// An NSError with `message` as its localized description.
    static func make(_ domain: String, _ code: Int, _ message: String) -> NSError {
        NSError.make(domain: domain, code: code,
                     userInfo: NSDictionary.make(object: NSObject.string(message), key: "NSLocalizedDescription"))
    }

    /// Stores an autoreleased error for an `error:` argument, when there is one.
    static func store(_ pointer: UnsafeMutablePointer<UnsafeMutableRawPointer?>?, _ domain: String, _ code: Int,
                      _ message: String) {
        guard let pointer else { return }
        pointer.pointee = make(domain, code, message).objCReturnValue()
    }
}

extension NSObject {
    static func string(_ value: String) -> NSObject { NSObject(objCReturnValue: value.objCArgument()) }

    /// A new NSArray of `objects`, autoreleased.
    static func array(_ objects: [NSObject]) -> NSObject {
        typealias Make = @convention(c) (UnsafeMutableRawPointer?, UnsafeRawPointer?,
                                         UnsafePointer<UnsafeMutableRawPointer?>?, UInt) -> UnsafeMutableRawPointer?
        let pointers: [UnsafeMutableRawPointer?] = objects.map { $0.objcObject }
        let array = pointers.withUnsafeBufferPointer {
            unsafeBitCast(ObjCRuntime.msgSend, to: Make.self)(ObjCRuntime.classObject("NSArray"),
                                                            ObjCRuntime.selector("arrayWithObjects:count:"),
                                                            $0.baseAddress, UInt($0.count))
        }
        return NSObject(objCReturnValue: array)
    }
}

/// metal2vulkan's functions; only reached once a device exists.
enum M2V {
    static var api: perry_m2v { perry_metal2vulkan()!.pointee }

    /// Calls a function that can fail: its result and its error message.
    static func call<Result>(_ body: (perry_m2v_error) -> Result) -> (Result, String?) {
        var message: UnsafeMutablePointer<CChar>?
        let result = withUnsafeMutablePointer(to: &message) { body($0) }
        guard let message else { return (result, nil) }
        defer { api.string_free(message) }
        return (result, String(cString: message))
    }
}

/// libdispatch's data, which newLibraryWithData: takes.
enum DispatchData {
    typealias CreateMap = @convention(c) (UnsafeMutableRawPointer?, UnsafeMutablePointer<UnsafeRawPointer?>?,
                                          UnsafeMutablePointer<Int>?) -> UnsafeMutableRawPointer?
    nonisolated(unsafe) static var createMap: CreateMap?

    /// The bytes of a dispatch_data_t.
    static func bytes(_ data: UnsafeMutableRawPointer?) -> [UInt8]? {
        guard let data, let createMap else { return nil }
        var buffer: UnsafeRawPointer?
        var size = 0
        guard let map = createMap(data, &buffer, &size) else { return nil }
        defer { ObjCRuntime.release(map) }
        guard let buffer else { return [] }
        return Array(UnsafeRawBufferPointer(start: buffer, count: size))
    }
}

/// A file's bytes.
func readFile(_ path: String) -> [UInt8]? {
    guard let file = fopen(path, "rb") else { return nil }
    defer { fclose(file) }
    var bytes: [UInt8] = []
    var chunk = [UInt8](repeating: 0, count: 65536)
    while true {
        let count = fread(&chunk, 1, chunk.count, file)
        if count == 0 { break }
        bytes += chunk.prefix(count)
    }
    return ferror(file) == 0 ? bytes : nil
}

/// A mutex, for state metal2vulkan's threads reach.
final class Lock: @unchecked Sendable {
    private let mutex = UnsafeMutablePointer<pthread_mutex_t>.allocate(capacity: 1)

    init() { pthread_mutex_init(mutex, nil) }

    deinit {
        pthread_mutex_destroy(mutex)
        mutex.deallocate()
    }

    func withLock<Result>(_ body: () throws -> Result) rethrows -> Result {
        pthread_mutex_lock(mutex)
        defer { pthread_mutex_unlock(mutex) }
        return try body()
    }
}
