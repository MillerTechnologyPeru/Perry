import CPerryFoundation
import Glibc
import PerryObjCInterop

// NSException. Raising one goes to libobjc's objc_exception_throw. Perry
// cannot unwind Mach-O frames to a @catch, so every exception is uncaught:
// Foundation reports it as Darwin does, calls the handler the program set
// with NSSetUncaughtExceptionHandler, and the process ends.

/// An exception's name, reason and user info.
final class ExceptionStorage {
    let name: id?
    let reason: id?
    let userInfo: id?

    init(name: id?, reason: id?, userInfo: id?) {
        self.name = ObjC.send(name, Selectors.copyWithZone, nil)
        self.reason = ObjC.send(reason, Selectors.copyWithZone, nil)
        self.userInfo = ObjC.retain(userInfo)
    }

    deinit {
        ObjC.release(name)
        ObjC.release(reason)
        ObjC.release(userInfo)
    }
}

/// Exception names.
@ObjCConstants
enum ExceptionConstants {
    static let NSGenericException = "NSGenericException"
    static let NSRangeException = "NSRangeException"
    static let NSInvalidArgumentException = "NSInvalidArgumentException"
    static let NSInvalidArchiveOperationException = "NSInvalidArchiveOperationException"
    static let NSInternalInconsistencyException = "NSInternalInconsistencyException"
    static let NSMallocException = "NSMallocException"
    static let NSObjectInaccessibleException = "NSObjectInaccessibleException"
    static let NSObjectNotAvailableException = "NSObjectNotAvailableException"
    static let NSDestinationInvalidException = "NSDestinationInvalidException"
    static let NSPortTimeoutException = "NSPortTimeoutException"
    static let NSInvalidSendPortException = "NSInvalidSendPortException"
    static let NSInvalidReceivePortException = "NSInvalidReceivePortException"
    static let NSPortSendException = "NSPortSendException"
    static let NSPortReceiveException = "NSPortReceiveException"
    static let NSCharacterConversionException = "NSCharacterConversionException"
    static let NSFileHandleOperationException = "NSFileHandleOperationException"
    static let NSFileHandleNotificationDataItem = "NSFileHandleNotificationDataItem"
    static let NSFileHandleReadToEndOfFileCompletionNotification = "NSFileHandleReadToEndOfFileCompletionNotification"
    static let NSUndefinedKeyException = "NSUnknownKeyException"
}

enum Exceptions {
    nonisolated(unsafe) static var exceptionClass: Class!
    typealias Handler = @convention(c) (id?) -> Void
    /// NSSetUncaughtExceptionHandler's.
    nonisolated(unsafe) static var handler: Handler?

    static func storage(_ object: id?) -> ExceptionStorage? { Storage.get(object, as: ExceptionStorage.self) }

    /// Reports an exception no @catch handled, as CoreFoundation does,
    /// then calls the program's handler.
    static let uncaught: Handler = { exception in
        let storage = Exceptions.storage(exception)
        let name = Strings.value(of: storage?.name) ?? "NSException"
        let reason = Strings.value(of: storage?.reason) ?? ""
        log("*** Terminating app due to uncaught exception '\(name)', reason: '\(reason)'")
        if let setting = getenv("PERRY_CRASH_REPORT"), setting.pointee != 0, String(cString: setting) != "0" { Exceptions.reportFrames() }
        Exceptions.handler?(exception)
    }

    /// The frames that threw, with PERRY_CRASH_REPORT set: by symbol where
    /// the address is in a library dladdr knows, else the bare address (an
    /// app's Mach-O images).
    static func reportFrames() {
        var addresses = [UInt](repeating: 0, count: 64)
        let count = perry_frame_return_addresses(&addresses, addresses.count)
        var line = [CChar](repeating: 0, count: 512)
        for (index, address) in addresses.prefix(count).enumerated() {
            perry_describe_address(address, &line, line.count)
            log("  #\(index) " + String(cString: line))
        }
    }

    typealias Throw = @convention(c) (id?) -> Void
    nonisolated(unsafe) static var throwException: Throw?

    /// Binds objc_exception_throw and installs the report with libobjc,
    /// through `lookup`.
    static func load(_ lookup: (String) -> UnsafeMutableRawPointer?) {
        typealias SetHandler = @convention(c) (Handler?) -> Handler?
        throwException = lookup("_objc_exception_throw").map { unsafeBitCast($0, to: Throw.self) }
        guard let set = lookup("_objc_setUncaughtExceptionHandler") else { return }
        _ = unsafeBitCast(set, to: SetHandler.self)(uncaught)
    }

    /// Raises a new exception by name with a reason, as Foundation's own
    /// checks do.
    static func raise(name: String, reason: String) -> Never {
        guard let cls = "NSException".withCString({ ObjC.getClass($0) }),
              let exception = Storage.allocate(UnsafeMutableRawPointer(cls)) else { foundationFatal(reason) }
        Storage.set(exception, ExceptionStorage(name: Strings.autoreleased(name), reason: Strings.autoreleased(reason), userInfo: nil))
        raise(ObjC.autorelease(exception))
    }

    static func raise(_ exception: id?) -> Never {
        throwException?(exception)
        uncaught(exception)
        foundationFatal("terminating with uncaught exception of type NSException")
    }
}

@c(_NSSetUncaughtExceptionHandler)
public func NSSetUncaughtExceptionHandler(_ handler: (@convention(c) (UnsafeMutableRawPointer?) -> Void)?) {
    Exceptions.handler = handler
}

@c(_NSGetUncaughtExceptionHandler)
public func NSGetUncaughtExceptionHandler() -> (@convention(c) (UnsafeMutableRawPointer?) -> Void)? { Exceptions.handler }

/// +raise:format:, with the format's arguments as a Darwin va_list.
@c
public func perry_foundation_raiseFormat(_ cls: id?, _ cmd: SEL?, _ name: id?, _ format: id?,
                                         _ arguments: UnsafeRawPointer?) {
    var reason = Strings.value(of: format) ?? ""
    if let arguments {
        var darwin = DarwinArguments(arguments)
        reason = Format.string(reason, &darwin)
    }
    guard let cls, let exception = Storage.allocate(cls) else { foundationFatal(reason) }
    Storage.set(exception, ExceptionStorage(name: name, reason: Strings.autoreleased(reason), userInfo: nil))
    Exceptions.raise(ObjC.autorelease(exception))
}

/// NSException.
@ObjCClass("NSException")
public class NSException: NSObject {
    override public class func didDefineObjCClass(_ cls: ObjCClass) {
        NSObject.registerObjCCategoryStorageAllocated(cls)
        Exceptions.exceptionClass = cls.storage
        cls.addMethod("raise:format:", types: "v32@0:8@16@24",
                      implementation: variadicEntry(perry_imp_raiseFormat), isClassMethod: true)
    }

    private var storage: ExceptionStorage? { Exceptions.storage(objcObject) }

    @ObjCClassMethod("exceptionWithName:reason:userInfo:")
    static func exception(_ cls: ObjCClass, name: ObjCObject?, reason: ObjCObject?, userInfo: ObjCObject?) -> NSException? {
        guard let exception = Storage.allocate(cls.pointer) else { return nil }
        Storage.set(exception, ExceptionStorage(name: name?.id, reason: reason?.id, userInfo: userInfo?.id))
        return NSException(objCOwned: exception)
    }

    @ObjCClassMethod("raise:format:arguments:")
    static func raise(_ cls: ObjCClass, name: ObjCObject?, format: ObjCObject?, arguments: UnsafeRawPointer?) {
        perry_foundation_raiseFormat(cls.pointer, nil, name?.id, format?.id, arguments)
    }

    @ObjCMethod("initWithName:reason:userInfo:")
    func initialize(name: ObjCObject?, reason: ObjCObject?, userInfo: ObjCObject?) -> Self {
        Storage.set(objcObject, ExceptionStorage(name: name?.id, reason: reason?.id, userInfo: userInfo?.id))
        return self
    }

    @ObjCMethod("dealloc")
    func dealloc() {
        Storage.set(objcObject, nil)
        ObjC.superDealloc(objcObject, from: Exceptions.exceptionClass)
    }

    @ObjCMethod("name") func name() -> ObjCObject? { storage?.name.map(ObjCObject.init) }
    @ObjCMethod("reason") func reason() -> ObjCObject? { storage?.reason.map(ObjCObject.init) }
    @ObjCMethod("userInfo") func userInfo() -> ObjCObject? { storage?.userInfo.map(ObjCObject.init) }
    @ObjCMethod("callStackSymbols") func callStackSymbols() -> ObjCObject { ObjCObject(Arrays.autoreleased([])) }
    @ObjCMethod("callStackReturnAddresses") func callStackReturnAddresses() -> ObjCObject { ObjCObject(Arrays.autoreleased([])) }
    @ObjCMethod("raise") func raise() { Exceptions.raise(objcObject) }

    @ObjCMethod("description")
    func description() -> String { Strings.value(of: storage?.reason) ?? Strings.value(of: storage?.name) ?? "" }

    @ObjCMethod("copyWithZone:") func copy(zone: UnsafeMutableRawPointer?) -> NSException { self }
}
