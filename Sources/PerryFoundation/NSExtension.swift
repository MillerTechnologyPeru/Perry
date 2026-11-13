import CPerryFoundation
import FoundationEssentials
import Glibc
import PerryObjCInterop

// App extensions and the XPC connections an app talks to them over, in one
// process. Darwin runs each extension (an .appex in the app's PlugIns) as a
// process of its own and connects the app's NSExtensionContext to the
// extension's with an NSXPCConnection pair. Perry has no second Mach-O
// process to start, so the extension's executable is loaded into the app as
// a bundle, its context and request handler classes are made here, and the
// two contexts' connections point at each other: a message sent to one's
// remoteObjectProxy is delivered, as it stands, to the other's exported
// object. Arguments are not encoded and copied as XPC does, and a call
// returns once the exported object has handled it.

/// A mutex around some state.
private final class Lock: @unchecked Sendable {
    private let mutex = UnsafeMutablePointer<pthread_mutex_t>.allocate(capacity: 1)

    init() { pthread_mutex_init(mutex, nil) }

    func with<Result>(_ body: () -> Result) -> Result {
        pthread_mutex_lock(mutex)
        defer { pthread_mutex_unlock(mutex) }
        return body()
    }
}

private func send(_ receiver: id?, _ name: String) -> id? { ObjC.send(receiver, ObjC.selector(name)) }

private func send(_ receiver: id?, _ name: String, _ argument: id?) -> id? {
    ObjC.send(receiver, ObjC.selector(name), argument)
}

private func classNamed(_ name: String) -> id? {
    name.withCString { ObjC.getClass($0) }.map { UnsafeMutableRawPointer($0) }
}

/// The object an Info.plist dictionary has for a key.
private func entry(_ dictionary: id?, _ key: String) -> id? {
    guard let dictionary else { return nil }
    let key = Strings.make(key)
    defer { ObjC.release(key) }
    return send(dictionary, "objectForKey:", key)
}

// MARK: - Interfaces

/// What an NSXPCInterface was made for. Nothing is encoded here, so the
/// classes arguments may be are not kept.
final class InterfaceStorage {
    var proto: id?
}

@ObjCClass("NSXPCInterface")
public class NSXPCInterface: NSObject {
    nonisolated(unsafe) static var interfaceClass: Class!

    override public class func didDefineObjCClass(_ cls: ObjCClass) {
        NSObject.registerObjCCategoryStorageAllocated(cls)
        interfaceClass = cls.storage
    }

    @ObjCClassMethod("interfaceWithProtocol:")
    static func make(_ cls: ObjCClass, proto: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer? {
        guard let object = Storage.allocate(cls.pointer) else { return nil }
        let storage = InterfaceStorage()
        storage.proto = proto
        Storage.set(object, storage)
        return ObjC.autorelease(object)
    }

    @ObjCMethod("protocol")
    func interfaceProtocol() -> UnsafeMutableRawPointer? {
        Storage.get(objcObject, as: InterfaceStorage.self)?.proto
    }

    @ObjCMethod("setProtocol:")
    func setProtocol(_ proto: UnsafeMutableRawPointer?) {
        Storage.get(objcObject, as: InterfaceStorage.self)?.proto = proto
    }

    @ObjCMethod("setClasses:forSelector:argumentIndex:ofReply:")
    func setClasses(_ classes: UnsafeMutableRawPointer?, selector: UnsafeRawPointer?, argument: UInt, ofReply: Bool) {}

    @ObjCMethod("classesForSelector:argumentIndex:ofReply:")
    func classes(selector: UnsafeRawPointer?, argument: UInt, ofReply: Bool) -> UnsafeMutableRawPointer? { nil }

    @ObjCMethod("setInterface:forSelector:argumentIndex:ofReply:")
    func setInterface(_ interface: UnsafeMutableRawPointer?, selector: UnsafeRawPointer?, argument: UInt, ofReply: Bool) {}

    @ObjCMethod("interfaceForSelector:argumentIndex:ofReply:")
    func interface(selector: UnsafeRawPointer?, argument: UInt, ofReply: Bool) -> UnsafeMutableRawPointer? { nil }

    @ObjCMethod("dealloc")
    func dealloc() {
        Storage.set(objcObject, nil)
        ObjC.superDealloc(objcObject, from: NSXPCInterface.interfaceClass)
    }
}

// MARK: - Connections

/// A connection's two ends meet: each holds the other, and the proxy of one
/// sends to the exported object of the other.
final class ConnectionStorage {
    var remoteInterface: id?
    var exportedInterface: id?
    var exportedObject: id?
    var peer: ConnectionStorage?
    var interruptionHandler: id?
    var invalidationHandler: id?
    var invalidated = false

    func replace(_ old: inout id?, with new: id?) {
        _ = ObjC.retain(new)
        if let old { ObjC.release(old) }
        old = new
    }
}

/// What a remoteObjectProxy stands for: the connection it was asked of.
final class ProxyStorage {
    let connection: ConnectionStorage

    init(_ connection: ConnectionStorage) { self.connection = connection }
}

/// The object remoteObjectProxy answers: whatever it is sent, the peer's
/// exported object is given.
@ObjCClass("PerryXPCProxy")
public class PerryXPCProxy: NSObject {
    nonisolated(unsafe) static var proxyClass: Class!

    override public class func didDefineObjCClass(_ cls: ObjCClass) {
        NSObject.registerObjCCategoryStorageAllocated(cls)
        proxyClass = cls.storage
    }

    static func make(for connection: ConnectionStorage) -> id? {
        guard let object = Storage.allocate(UnsafeMutableRawPointer(proxyClass)) else { return nil }
        Storage.set(object, ProxyStorage(connection))
        return ObjC.autorelease(object)
    }

    private var target: id? {
        Storage.get(objcObject, as: ProxyStorage.self)?.connection.peer?.exportedObject
    }

    @ObjCMethod("forwardingTargetForSelector:")
    func forwardingTarget(_ selector: UnsafeRawPointer?) -> UnsafeMutableRawPointer? { target }

    @ObjCMethod("respondsToSelector:")
    func responds(_ selector: UnsafeRawPointer?) -> Bool {
        guard let target, let selector else { return false }
        return ObjC.sendBool(target, ObjC.selector("respondsToSelector:"), UnsafeMutableRawPointer(mutating: selector))
    }

    /// A proxy conforms to the protocol of the interface it stands for, as
    /// Darwin's, which is made to adopt it, does: Swift casts it to that
    /// protocol.
    @ObjCMethod("conformsToProtocol:")
    func conforms(_ proto: UnsafeMutableRawPointer?) -> Bool {
        guard let proto else { return false }
        if let connection = Storage.get(objcObject, as: ProxyStorage.self)?.connection,
           let interface = connection.remoteInterface,
           let own = Storage.get(interface, as: InterfaceStorage.self)?.proto,
           own == proto || ObjC.sendBool(own, ObjC.selector("conformsToProtocol:"), proto) {
            return true
        }
        guard let target else { return false }
        return ObjC.sendBool(target, ObjC.selector("conformsToProtocol:"), proto)
    }

    @ObjCMethod("dealloc")
    func dealloc() {
        Storage.set(objcObject, nil)
        ObjC.superDealloc(objcObject, from: PerryXPCProxy.proxyClass)
    }
}

@ObjCClass("NSXPCConnection")
public class NSXPCConnection: NSObject {
    nonisolated(unsafe) static var connectionClass: Class!

    override public class func didDefineObjCClass(_ cls: ObjCClass) {
        NSObject.registerObjCCategoryStorageAllocated(cls)
        connectionClass = cls.storage
    }

    var storage: ConnectionStorage? { Storage.get(objcObject, as: ConnectionStorage.self) }

    /// A connection with no peer, +1.
    static func create() -> id? {
        guard let object = Storage.allocate(UnsafeMutableRawPointer(connectionClass)) else { return nil }
        Storage.set(object, ConnectionStorage())
        return object
    }

    private func ensureStorage() -> UnsafeMutableRawPointer {
        if storage == nil { Storage.set(objcObject, ConnectionStorage()) }
        return objcObject
    }

    @ObjCMethod("init") func initialize() -> UnsafeMutableRawPointer { ensureStorage() }
    @ObjCMethod("initWithServiceName:") func initialize(serviceName: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer { ensureStorage() }
    @ObjCMethod("initWithListenerEndpoint:") func initialize(endpoint: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer { ensureStorage() }
    @ObjCMethod("initWithMachServiceName:options:")
    func initialize(machService: UnsafeMutableRawPointer?, options: UInt) -> UnsafeMutableRawPointer { ensureStorage() }

    @ObjCMethod("remoteObjectInterface")
    func remoteObjectInterface() -> UnsafeMutableRawPointer? { storage?.remoteInterface }

    @ObjCMethod("setRemoteObjectInterface:")
    func setRemoteObjectInterface(_ interface: UnsafeMutableRawPointer?) {
        guard let storage else { return }
        storage.replace(&storage.remoteInterface, with: interface)
    }

    @ObjCMethod("exportedInterface")
    func exportedInterface() -> UnsafeMutableRawPointer? { storage?.exportedInterface }

    @ObjCMethod("setExportedInterface:")
    func setExportedInterface(_ interface: UnsafeMutableRawPointer?) {
        guard let storage else { return }
        storage.replace(&storage.exportedInterface, with: interface)
    }

    @ObjCMethod("exportedObject")
    func exportedObject() -> UnsafeMutableRawPointer? { storage?.exportedObject }

    @ObjCMethod("setExportedObject:")
    func setExportedObject(_ object: UnsafeMutableRawPointer?) {
        guard let storage else { return }
        storage.replace(&storage.exportedObject, with: object)
    }

    @ObjCMethod("interruptionHandler")
    func interruptionHandler() -> UnsafeMutableRawPointer? { storage?.interruptionHandler }

    @ObjCMethod("setInterruptionHandler:")
    func setInterruptionHandler(_ handler: UnsafeMutableRawPointer?) {
        guard let storage else { return }
        storage.replace(&storage.interruptionHandler, with: handler.flatMap { ObjC.retainBlock($0) })
    }

    @ObjCMethod("invalidationHandler")
    func invalidationHandler() -> UnsafeMutableRawPointer? { storage?.invalidationHandler }

    @ObjCMethod("setInvalidationHandler:")
    func setInvalidationHandler(_ handler: UnsafeMutableRawPointer?) {
        guard let storage else { return }
        storage.replace(&storage.invalidationHandler, with: handler.flatMap { ObjC.retainBlock($0) })
    }

    @ObjCMethod("remoteObjectProxy")
    func remoteObjectProxy() -> UnsafeMutableRawPointer? {
        storage.flatMap { PerryXPCProxy.make(for: $0) }
    }

    @ObjCMethod("remoteObjectProxyWithErrorHandler:")
    func remoteObjectProxy(errorHandler: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer? { remoteObjectProxy() }

    @ObjCMethod("synchronousRemoteObjectProxyWithErrorHandler:")
    func synchronousRemoteObjectProxy(errorHandler: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer? { remoteObjectProxy() }

    @ObjCMethod("resume") func resume() {}
    @ObjCMethod("suspend") func suspend() {}
    @ObjCMethod("auditToken") func auditToken() -> Int { 0 }
    @ObjCMethod("processIdentifier") func processIdentifier() -> Int32 { getpid() }
    @ObjCMethod("effectiveUserIdentifier") func effectiveUserIdentifier() -> UInt32 { geteuid() }
    @ObjCMethod("effectiveGroupIdentifier") func effectiveGroupIdentifier() -> UInt32 { getegid() }

    @ObjCMethod("invalidate")
    func invalidate() {
        guard let storage, !storage.invalidated else { return }
        storage.invalidated = true
        if let handler = storage.invalidationHandler {
            Blocks.invoke(handler, as: (@convention(c) (id) -> Void).self)(handler)
        }
    }

    @ObjCMethod("dealloc")
    func dealloc() {
        if let storage {
            storage.peer?.peer = nil
            storage.peer = nil
            for old in [storage.remoteInterface, storage.exportedInterface, storage.exportedObject,
                        storage.interruptionHandler, storage.invalidationHandler] {
                if let old { ObjC.release(old) }
            }
        }
        Storage.set(objcObject, nil)
        ObjC.superDealloc(objcObject, from: NSXPCConnection.connectionClass)
    }
}

/// An NSXPCListener: nothing is ever connected to one, as connections are
/// made by the extension host; it accepts no work and starts no service.
@ObjCClass("NSXPCListener")
public class NSXPCListener: NSObject {
    nonisolated(unsafe) static var listenerClass: Class!

    override public class func didDefineObjCClass(_ cls: ObjCClass) {
        NSObject.registerObjCCategoryStorageAllocated(cls)
        listenerClass = cls.storage
    }

    private static func make(_ cls: ObjCClass) -> UnsafeMutableRawPointer? {
        Storage.allocate(cls.pointer).flatMap { ObjC.autorelease($0) }
    }

    @ObjCClassMethod("anonymousListener")
    static func anonymous(_ cls: ObjCClass) -> UnsafeMutableRawPointer? { make(cls) }

    @ObjCClassMethod("serviceListener")
    static func service(_ cls: ObjCClass) -> UnsafeMutableRawPointer? { make(cls) }

    @ObjCMethod("init") func initialize() -> UnsafeMutableRawPointer { objcObject }
    @ObjCMethod("initWithMachServiceName:") func initialize(name: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer { objcObject }

    @ObjCMethod("delegate") func delegate() -> UnsafeMutableRawPointer? { nil }
    @ObjCMethod("setDelegate:") func setDelegate(_ delegate: UnsafeMutableRawPointer?) {}
    @ObjCMethod("resume") func resume() {}
    @ObjCMethod("suspend") func suspend() {}
    @ObjCMethod("invalidate") func invalidate() {}
}

// MARK: - Extension contexts

private let contextLock = Lock()
nonisolated(unsafe) private var contextConnections: [UInt: id] = [:]

/// What an extension and the app that hosts it share, one on each side:
/// the context gives the connection to the other.
@ObjCClass("NSExtensionContext")
open class NSExtensionContext: NSObject {
    nonisolated(unsafe) static var contextClass: Class!

    override public class func didDefineObjCClass(_ cls: ObjCClass) {
        contextClass = cls.storage
    }

    static func setConnection(_ connection: id?, of context: id) {
        contextLock.with {
            if let old = contextConnections[UInt(bitPattern: context)] { ObjC.release(old) }
            contextConnections[UInt(bitPattern: context)] = connection.flatMap { ObjC.retain($0) }
        }
    }

    @ObjCMethod("_auxiliaryConnection")
    func auxiliaryConnection() -> UnsafeMutableRawPointer? {
        contextLock.with { contextConnections[UInt(bitPattern: objcObject)] }
    }

    @ObjCClassMethod("_extensionAuxiliaryHostProtocol")
    static func auxiliaryHostProtocol(_ cls: ObjCClass) -> UnsafeMutableRawPointer? { nil }

    @ObjCClassMethod("_extensionAuxiliaryVendorProtocol")
    static func auxiliaryVendorProtocol(_ cls: ObjCClass) -> UnsafeMutableRawPointer? { nil }

    @ObjCMethod("inputItems")
    func inputItems() -> UnsafeMutableRawPointer? {
        send(classNamed("NSArray"), "array")
    }

    @ObjCMethod("completeRequestReturningItems:completionHandler:")
    func completeRequest(items: UnsafeMutableRawPointer?, completion: UnsafeMutableRawPointer?) {
        guard let completion else { return }
        Blocks.invoke(completion, as: (@convention(c) (id, Bool) -> Void).self)(completion, true)
    }

    @ObjCMethod("cancelRequestWithError:")
    func cancelRequest(error: UnsafeMutableRawPointer?) {}

    @ObjCMethod("dealloc")
    func dealloc() {
        NSExtensionContext.setConnection(nil, of: objcObject)
        contextLock.with { _ = contextConnections.removeValue(forKey: UInt(bitPattern: objcObject)) }
        ObjC.superDealloc(objcObject, from: NSExtensionContext.contextClass)
    }
}

// MARK: - Extensions

/// The extension a bundle in the app's PlugIns is.
final class ExtensionStorage {
    var identifier: String
    /// The NSBundle, retained.
    var bundle: id
    /// The bundle's NSExtension Info.plist entry, retained.
    var attributes: id?
    /// The contexts the app's side of each request holds, by request.
    var requests: [String: id] = [:]
    var blocks: [String: id] = [:]

    init(identifier: String, bundle: id, attributes: id?) {
        self.identifier = identifier
        self.bundle = bundle
        self.attributes = attributes
    }

    deinit {
        ObjC.release(bundle)
        if let attributes { ObjC.release(attributes) }
        for context in requests.values { ObjC.release(context) }
        for block in blocks.values { ObjC.release(block) }
    }
}

/// A request's completion, given to the main queue.
private final class RequestCompletion {
    let block: id
    let identifier: id

    init(_ block: id, _ identifier: id) {
        self.block = ObjC.retainBlock(block) ?? block
        self.identifier = ObjC.retain(identifier) ?? identifier
    }

    deinit {
        ObjC.release(block)
        ObjC.release(identifier)
    }
}

@ObjCClass("NSExtension")
public class NSExtension: NSObject {
    nonisolated(unsafe) static var extensionClass: Class!

    override public class func didDefineObjCClass(_ cls: ObjCClass) {
        NSObject.registerObjCCategoryStorageAllocated(cls)
        extensionClass = cls.storage
    }

    var storage: ExtensionStorage? { Storage.get(objcObject, as: ExtensionStorage.self) }

    /// The extension that an app bundle at `path` is, if it names one.
    private static func make(path: String) -> id? {
        let pathString = Strings.make(path)
        defer { ObjC.release(pathString) }
        guard let bundle = send(classNamed("NSBundle"), "bundleWithPath:", pathString) else { return nil }
        guard let info = send(bundle, "infoDictionary"), let attributes = entry(info, "NSExtension") else { return nil }
        let identifier = send(bundle, "bundleIdentifier").flatMap { Strings.value(of: $0) } ?? path
        guard let object = Storage.allocate(UnsafeMutableRawPointer(extensionClass)) else { return nil }
        Storage.set(object, ExtensionStorage(identifier: identifier, bundle: ObjC.retain(bundle) ?? bundle,
                                             attributes: ObjC.retain(attributes)))
        return object
    }

    /// The bundles of the app's PlugIns folder.
    private static func plugInPaths() -> [String] {
        guard let main = send(classNamed("NSBundle"), "mainBundle"),
              let folder = send(main, "builtInPlugInsPath").flatMap({ Strings.value(of: $0) }),
              let names = try? FileManager.default.contentsOfDirectory(atPath: folder) else { return [] }
        return names.sorted().filter { $0.hasSuffix(".appex") }.map { folder + "/" + $0 }
    }

    @ObjCClassMethod("extensionWithIdentifier:error:")
    static func extensionWith(_ cls: ObjCClass, identifier: String, error: UnsafeMutablePointer<id?>?) -> UnsafeMutableRawPointer? {
        for path in plugInPaths() {
            guard let object = make(path: path) else { continue }
            if (Storage.get(object, as: ExtensionStorage.self)?.identifier) == identifier { return ObjC.autorelease(object) }
            ObjC.release(object)
        }
        error?.pointee = Errors.autoreleased(domain: Strings.autoreleased("NSCocoaErrorDomain"), code: 4,
                                              description: "The extension \(identifier) could not be found.")
        return nil
    }

    /// Calls the completion with the extension, or an error, as the real
    /// one does once it has looked.
    @ObjCClassMethod("extensionWithURL:completion:")
    static func extensionWith(_ cls: ObjCClass, url: UnsafeMutableRawPointer, completion: UnsafeMutableRawPointer) {
        let path = send(url, "path").flatMap { Strings.value(of: $0) } ?? ""
        let object = make(path: path)
        typealias Completion = @convention(c) (id, id?, id?) -> Void
        let error = object == nil
            ? Errors.autoreleased(domain: Strings.autoreleased("NSCocoaErrorDomain"), code: 4,
                                  description: "There is no extension at \(path).")
            : nil
        Blocks.invoke(completion, as: Completion.self)(completion, object.flatMap { ObjC.autorelease($0) }, error)
    }

    @ObjCMethod("identifier") func identifier() -> String? { storage?.identifier }

    @ObjCMethod("_extensionBundle")
    func extensionBundle() -> UnsafeMutableRawPointer? { storage.map { $0.bundle } }

    @ObjCMethod("_plugIn") func plugIn() -> UnsafeMutableRawPointer? { nil }

    @ObjCMethod("setRequestCompletionBlock:") func setRequestCompletionBlock(_ block: UnsafeMutableRawPointer?) {}
    @ObjCMethod("setRequestCancellationBlock:") func setRequestCancellationBlock(_ block: UnsafeMutableRawPointer?) {}
    @ObjCMethod("setRequestInterruptionBlock:") func setRequestInterruptionBlock(_ block: UnsafeMutableRawPointer?) {}
    @ObjCMethod("cancelExtensionRequestWithIdentifier:") func cancelExtensionRequest(_ identifier: UnsafeMutableRawPointer?) {}
    @ObjCMethod("_kill:") func kill(_ signal: Int32) {}

    private func contextClass(_ key: String) -> id? {
        guard let storage, let name = entry(storage.attributes, key).flatMap({ Strings.value(of: $0) }) else { return nil }
        return classNamed(name)
    }

    /// Starts a request: loads the extension, makes its context and the
    /// app's, joins their connections and hands the extension's context to
    /// its request handler. The app learns of the request's identifier on
    /// the main queue.
    @ObjCMethod("beginExtensionRequestWithOptions:inputItems:completion:")
    func beginExtensionRequest(options: Int, inputItems: UnsafeMutableRawPointer?, completion: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer? {
        beginRequest(completion: completion)
    }

    @ObjCMethod("beginExtensionRequestWithInputItems:completion:")
    func beginExtensionRequest(inputItems: UnsafeMutableRawPointer?, completion: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer? {
        beginRequest(completion: completion)
    }

    private func beginRequest(completion: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer? {
        guard let storage else { return nil }
        _ = send(storage.bundle, "load")
        let base = classNamed("NSExtensionContext")
        let vendorClass = contextClass("NSExtensionContextClass") ?? base
        let hostClass = contextClass("NSExtensionContextHostClass") ?? base
        guard let vendorContext = send(send(vendorClass, "alloc"), "init"),
              let hostContext = send(send(hostClass, "alloc"), "init"),
              let hostConnection = NSXPCConnection.create(), let vendorConnection = NSXPCConnection.create(),
              let host = Storage.get(hostConnection, as: ConnectionStorage.self),
              let vendor = Storage.get(vendorConnection, as: ConnectionStorage.self) else { return nil }

        // The app's end speaks the extension's protocol and serves its own.
        host.replace(&host.remoteInterface, with: send(vendorClass, "_extensionAuxiliaryVendorProtocol"))
        host.replace(&host.exportedInterface, with: send(hostClass, "_extensionAuxiliaryHostProtocol"))
        host.replace(&host.exportedObject, with: hostContext)
        vendor.replace(&vendor.remoteInterface, with: send(hostClass, "_extensionAuxiliaryHostProtocol"))
        vendor.replace(&vendor.exportedInterface, with: send(vendorClass, "_extensionAuxiliaryVendorProtocol"))
        vendor.replace(&vendor.exportedObject, with: vendorContext)
        host.peer = vendor
        vendor.peer = host
        NSExtensionContext.setConnection(hostConnection, of: hostContext)
        NSExtensionContext.setConnection(vendorConnection, of: vendorContext)

        let identifier = send(classNamed("NSUUID"), "UUID")
        let key = identifier.flatMap { send($0, "UUIDString") }.flatMap { Strings.value(of: $0) } ?? UUID().uuidString
        storage.requests[key] = hostContext

        // The extension's request handler is told, as its process would be.
        if let handlerClass = contextClass("NSExtensionPrincipalClass") ?? send(storage.bundle, "principalClass"),
           let handler = send(send(handlerClass, "alloc"), "init") {
            _ = send(handler, "beginRequestWithExtensionContext:", vendorContext)
            storage.blocks[key] = handler
        }

        if let completion, let identifier, let queue = Dispatch.mainQueue, let async = Dispatch.async {
            let context = Unmanaged.passRetained(RequestCompletion(completion, identifier)).toOpaque()
            async(queue, context) { context in
                guard let context else { return }
                let request = Unmanaged<RequestCompletion>.fromOpaque(context).takeRetainedValue()
                Blocks.invoke(request.block, as: (@convention(c) (id, id, id?) -> Void).self)(request.block, request.identifier, nil)
            }
        }
        return identifier
    }

    @ObjCMethod("_extensionContextForUUID:")
    func extensionContext(forUUID uuid: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer? {
        guard let storage, let uuid,
              let key = send(uuid, "UUIDString").flatMap({ Strings.value(of: $0) }),
              let context = storage.requests[key] else { return nil }
        return context
    }

    @ObjCMethod("dealloc")
    func dealloc() {
        Storage.set(objcObject, nil)
        ObjC.superDealloc(objcObject, from: NSExtension.extensionClass)
    }
}
