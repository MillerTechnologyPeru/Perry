import CPerryFoundation
import Glibc
import PerryObjCInterop

// NSXPCCoder, the coder XPC connections encode messages with, and
// NSXPCListenerEndpoint, a listener's address, which one process hands
// another to connect to it. Messages here go to the exported object as they
// are sent (NSExtension.swift), so nothing makes coders; an endpoint names
// its listener in this process, and an archive of it names the same one.

/// The listener an endpoint stands for, while it lives.
private final class EndpointListenerBox {
    weak var listener: ListenerStorage?

    init(_ listener: ListenerStorage?) { self.listener = listener }
}

/// Each endpoint's listener, by the endpoint's number, for decoding.
private enum EndpointRegistry {
    nonisolated(unsafe) static var next = 1
    nonisolated(unsafe) static var listeners: [Int: EndpointListenerBox] = [:]
    nonisolated(unsafe) static let mutex: UnsafeMutablePointer<pthread_mutex_t> = {
        let mutex = UnsafeMutablePointer<pthread_mutex_t>.allocate(capacity: 1)
        pthread_mutex_init(mutex, nil)
        return mutex
    }()

    static func locked<Result>(_ body: () -> Result) -> Result {
        pthread_mutex_lock(mutex)
        defer { pthread_mutex_unlock(mutex) }
        return body()
    }
}

final class ListenerEndpointStorage {
    /// Each endpoint's own number: endpoints are equal when it is.
    let serial: Int
    let listener: ListenerStorage?

    init(serial: Int, listener: ListenerStorage?) {
        self.serial = serial
        self.listener = listener
    }
}

@ObjCClass("NSXPCListenerEndpoint")
public class NSXPCListenerEndpoint: NSObject {
    nonisolated(unsafe) static var endpointClass: Class!

    override public class func didDefineObjCClass(_ cls: ObjCClass) {
        NSObject.registerObjCCategoryStorageAllocated(cls)
        endpointClass = cls.storage
    }

    var storage: ListenerEndpointStorage? { Storage.get(objcObject, as: ListenerEndpointStorage.self) }

    /// A new endpoint of the listener, autoreleased.
    static func make(for listener: ListenerStorage) -> id? {
        guard let object = Storage.allocate(UnsafeMutableRawPointer(endpointClass)) else { return nil }
        let serial = EndpointRegistry.locked { () -> Int in
            let serial = EndpointRegistry.next
            EndpointRegistry.next += 1
            EndpointRegistry.listeners = EndpointRegistry.listeners.filter { $0.value.listener != nil }
            EndpointRegistry.listeners[serial] = EndpointListenerBox(listener)
            return serial
        }
        Storage.set(object, ListenerEndpointStorage(serial: serial, listener: listener))
        return ObjC.autorelease(object)
    }

    /// The listener an endpoint stands for.
    static func listener(of endpoint: id?) -> ListenerStorage? {
        Storage.get(endpoint, as: ListenerEndpointStorage.self)?.listener
    }

    @ObjCMethod("isEqual:")
    func isEqual(_ other: UnsafeMutableRawPointer?) -> Bool {
        guard let other else { return false }
        return other == objcObject || (storage != nil && Storage.get(other, as: ListenerEndpointStorage.self)?.serial == storage?.serial)
    }

    @ObjCMethod("hash") func hash() -> UInt { UInt(storage?.serial ?? 0) }

    @ObjCClassMethod("supportsSecureCoding") static func supportsSecureCoding(_ cls: ObjCClass) -> Bool { true }

    @ObjCMethod("encodeWithCoder:")
    func encode(coder: UnsafeMutableRawPointer?) {
        typealias Encode = @convention(c) (id?, SEL, Int, id?) -> Void
        unsafeBitCast(ObjC.msgSend, to: Encode.self)(coder, ObjC.selector("encodeInteger:forKey:"), storage?.serial ?? 0,
                                                     Strings.autoreleased("NS.endpoint"))
    }

    /// The same endpoint again, while its listener lives.
    @ObjCMethod("initWithCoder:")
    func initialize(coder: UnsafeMutableRawPointer?) -> Self {
        let serial = ObjC.sendInt(coder, ObjC.selector("decodeIntegerForKey:"), Strings.autoreleased("NS.endpoint"))
        let listener = EndpointRegistry.locked { EndpointRegistry.listeners[serial]?.listener }
        Storage.set(objcObject, ListenerEndpointStorage(serial: serial, listener: listener))
        return self
    }

    @ObjCMethod("dealloc")
    func dealloc() {
        Storage.set(objcObject, nil)
        ObjC.superDealloc(objcObject, from: NSXPCListenerEndpoint.endpointClass)
    }
}

/// What an XPC coder holds: its user info, its connection and the XPC
/// objects encoded with it, unretained, as libxpc's objects need not be
/// Objective-C objects here.
final class XPCCoderStorage {
    var userInfo: ObjCObject?
    var connection: ObjCObject?
    var objects: [String: UnsafeMutableRawPointer] = [:]
}

@ObjCClass("NSXPCCoder")
public class NSXPCCoder: NSCoder {
    nonisolated(unsafe) static var coderClass: Class!

    override public class func didDefineObjCClass(_ cls: ObjCClass) {
        NSObject.registerObjCCategoryStorageAllocated(cls)
        coderClass = cls.storage
    }

    var storage: XPCCoderStorage {
        if let storage = Storage.get(objcObject, as: XPCCoderStorage.self) { return storage }
        let storage = XPCCoderStorage()
        Storage.set(objcObject, storage)
        return storage
    }

    @ObjCMethod("userInfo") func userInfo() -> UnsafeMutableRawPointer? { storage.userInfo?.id }
    @ObjCMethod("setUserInfo:") func setUserInfo(_ userInfo: UnsafeMutableRawPointer?) { storage.userInfo = userInfo.map { ObjCObject($0) } }

    /// The connection the coder encodes a message for: none, as messages
    /// here aren't encoded.
    @ObjCMethod("connection") func connection() -> UnsafeMutableRawPointer? { storage.connection?.id }

    @ObjCMethod("encodeXPCObject:forKey:")
    func encodeXPCObject(_ object: UnsafeMutableRawPointer?, forKey key: String?) {
        guard let key else { return }
        storage.objects[key] = object
    }

    @ObjCMethod("decodeXPCObjectOfType:forKey:")
    func decodeXPCObject(ofType type: UnsafeMutableRawPointer?, forKey key: String?) -> UnsafeMutableRawPointer? {
        key.flatMap { storage.objects[$0] }
    }

    @ObjCMethod("dealloc")
    func dealloc() {
        Storage.set(objcObject, nil)
        ObjC.superDealloc(objcObject, from: NSXPCCoder.coderClass)
    }
}
