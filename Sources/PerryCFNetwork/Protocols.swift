import FoundationEssentials
import PerryObjCInterop
import PerryURLLoading

// NSURLProtocol: the program's subclasses load requests for sessions and
// connections. corelibs asks the bridge in PerryURLLoading, which asks the
// session configuration's classes, then the registered ones (newest first),
// with +canInitWithRequest:, and runs the one that can: an instance made
// with -initWithRequest:cachedResponse:client: gets -startLoading, and its
// client passes what it is told back to corelibs.

final class ProtocolState: @unchecked Sendable {
    let request: NSObject
    let cachedResponse: NSObject?
    let client: NSObject?
    let task: NSObject?

    init(request: NSObject, cachedResponse: NSObject?, client: NSObject?, task: NSObject?) {
        self.request = request
        self.cachedResponse = cachedResponse
        self.client = client
        self.task = task
    }
}

/// A protocol property's value, retained while a request holds it.
final class PropertyValue: @unchecked Sendable {
    let object: UnsafeMutableRawPointer

    init(_ object: UnsafeMutableRawPointer) {
        self.object = ObjCRuntime.retain(object)!
    }

    deinit {
        ObjCRuntime.release(object)
    }
}

enum URLProtocols {
    typealias Object = UnsafeMutableRawPointer?
    static let states = StateTable<ProtocolState>()
    static let lock = Lock()
    /// Registered classes, newest first.
    nonisolated(unsafe) static var registered: [UnsafeMutableRawPointer] = []

    static func send<Function>(_ type: Function.Type) -> Function { unsafeBitCast(ObjCRuntime.msgSend, to: type) }

    static func canInit(_ cls: UnsafeMutableRawPointer, _ request: NSObject) -> Bool {
        send((@convention(c) (Object, UnsafeRawPointer, Object) -> Bool).self)(
            cls, ObjCRuntime.selector("canInitWithRequest:"), request.objcObject)
    }
}

/// The program's protocols, for the bridge.
final class ProtocolLoading: ProtocolLoader, @unchecked Sendable {
    final class Load {
        let instance: UnsafeMutableRawPointer

        init(_ instance: UnsafeMutableRawPointer) {
            self.instance = instance
        }
    }

    func protocolClass(for request: Request, classes: [UnsafeMutableRawPointer]) -> UnsafeMutableRawPointer? {
        let registered = URLProtocols.lock.withLock { URLProtocols.registered }
        return ObjCRuntime.autoreleasepool {
            let object = Requests.object(request)
            return (classes + registered).first { URLProtocols.canInit($0, object) }
        }
    }

    func start(_ cls: UnsafeMutableRawPointer, request: Request, client: ProtocolClient) -> AnyObject {
        typealias Object = UnsafeMutableRawPointer?
        return ObjCRuntime.autoreleasepool {
            let canonical = URLProtocols.send((@convention(c) (Object, UnsafeRawPointer, Object) -> Object).self)(
                cls, ObjCRuntime.selector("canonicalRequestForRequest:"), Requests.object(request).objcObject)
            let clientObject = ProtocolClients.object(client)
            let allocated = URLProtocols.send((@convention(c) (Object, UnsafeRawPointer) -> Object).self)(cls, ObjCRuntime.selector("alloc"))
            let instance = URLProtocols.send((@convention(c) (Object, UnsafeRawPointer, Object, Object, Object) -> Object).self)(
                allocated, ObjCRuntime.selector("initWithRequest:cachedResponse:client:"), canonical, nil, clientObject.objcObject)!
            URLProtocols.send((@convention(c) (Object, UnsafeRawPointer) -> Void).self)(instance, ObjCRuntime.selector("startLoading"))
            return Load(instance)
        }
    }

    func stop(_ load: AnyObject) {
        guard let load = load as? Load else { return }
        ObjCRuntime.autoreleasepool {
            URLProtocols.send((@convention(c) (UnsafeMutableRawPointer?, UnsafeRawPointer) -> Void).self)(
                load.instance, ObjCRuntime.selector("stopLoading"))
        }
        ObjCRuntime.release(load.instance)
    }
}

/// NSURLProtocol.
@ObjCClass("NSURLProtocol")
open class NSURLProtocol: NSObject {
    override public class func didDefineObjCClass(_ cls: ObjCClass) {
        Protocols.loader = ProtocolLoading()
    }

    var state: ProtocolState? { URLProtocols.states.get(objcObject) }

    @ObjCMethod("dealloc")
    func dealloc() {
        URLProtocols.states.remove(objcObject)
        ObjCRuntime.superDealloc(objcObject, definedOn: NSURLProtocol.objCClass.pointer)
    }

    @ObjCMethod("initWithRequest:cachedResponse:client:")
    func initialize(request: NSObject, cachedResponse: NSObject?, client: NSObject?) -> Self {
        URLProtocols.states.set(objcObject, ProtocolState(request: request, cachedResponse: cachedResponse, client: client, task: nil))
        return self
    }

    @ObjCMethod("initWithTask:cachedResponse:client:")
    func initialize(task: NSObject, cachedResponse: NSObject?, client: NSObject?) -> Self {
        let request = URLProtocols.send((@convention(c) (UnsafeMutableRawPointer?, UnsafeRawPointer) -> UnsafeMutableRawPointer?).self)(
            task.objcObject, ObjCRuntime.selector("currentRequest"))
        URLProtocols.states.set(objcObject, ProtocolState(request: NSObject(request!), cachedResponse: cachedResponse,
                                                          client: client, task: task))
        return self
    }

    @ObjCMethod("request") func request() -> NSObject? { state?.request }
    @ObjCMethod("cachedResponse") func cachedResponse() -> NSObject? { state?.cachedResponse }
    @ObjCMethod("client") func client() -> NSObject? { state?.client }
    @ObjCMethod("task") func task() -> NSObject? { state?.task }
    @ObjCMethod("startLoading") func startLoading() {}
    @ObjCMethod("stopLoading") func stopLoading() {}

    @ObjCClassMethod("canInitWithRequest:") static func canInit(_ cls: ObjCClass, request: NSObject?) -> Bool { false }

    @ObjCClassMethod("canInitWithTask:")
    static func canInit(_ cls: ObjCClass, task: NSObject?) -> Bool {
        let request = URLProtocols.send((@convention(c) (UnsafeMutableRawPointer?, UnsafeRawPointer) -> UnsafeMutableRawPointer?).self)(
            task?.objcObject, ObjCRuntime.selector("currentRequest"))
        return request.map { URLProtocols.canInit(cls.pointer, NSObject($0)) } ?? false
    }

    @ObjCClassMethod("canonicalRequestForRequest:")
    static func canonicalRequest(_ cls: ObjCClass, for request: NSObject) -> NSObject { request }

    @ObjCClassMethod("requestIsCacheEquivalent:toRequest:")
    static func requestIsCacheEquivalent(_ cls: ObjCClass, _ first: NSObject?, to second: NSObject?) -> Bool {
        guard let first = first.flatMap({ Requests.states.get($0.objcObject) }),
              let second = second.flatMap({ Requests.states.get($0.objcObject) }) else { return false }
        return first.isEqual(to: second)
    }

    @ObjCClassMethod("registerClass:")
    static func register(_ cls: ObjCClass, protocolClass: UnsafeMutableRawPointer?) -> Bool {
        guard let protocolClass else { return false }
        URLProtocols.lock.withLock {
            URLProtocols.registered.removeAll { $0 == protocolClass }
            URLProtocols.registered.insert(protocolClass, at: 0)
        }
        return true
    }

    @ObjCClassMethod("unregisterClass:")
    static func unregister(_ cls: ObjCClass, protocolClass: UnsafeMutableRawPointer?) {
        URLProtocols.lock.withLock { URLProtocols.registered.removeAll { $0 == protocolClass } }
    }

    @ObjCClassMethod("propertyForKey:inRequest:")
    static func property(_ cls: ObjCClass, forKey key: String, in request: NSObject?) -> UnsafeMutableRawPointer? {
        guard let request = request.flatMap({ Requests.states.get($0.objcObject) }) else { return nil }
        return (request.property(forKey: key) as? PropertyValue)?.object
    }

    @ObjCClassMethod("setProperty:forKey:inRequest:")
    static func setProperty(_ cls: ObjCClass, _ value: UnsafeMutableRawPointer?, forKey key: String, in request: NSObject?) {
        guard let request = request.flatMap({ Requests.states.get($0.objcObject) }) else { return }
        request.setProperty(value.map(PropertyValue.init), forKey: key)
    }

    @ObjCClassMethod("removePropertyForKey:inRequest:")
    static func removeProperty(_ cls: ObjCClass, forKey key: String, in request: NSObject?) {
        request.flatMap { Requests.states.get($0.objcObject) }?.setProperty(nil, forKey: key)
    }
}

// MARK: - Clients

enum ProtocolClients {
    static let states = StateTable<ProtocolClient>()

    static func object(_ client: ProtocolClient) -> NSObject {
        let object = NSURLProtocolClientObject.objCClass.autoreleasedInstance()
        states.set(object.objcObject, client)
        return object
    }
}

/// The client a protocol tells how its load goes (NSURLProtocolClient).
@ObjCClass("_NSURLProtocolClient")
open class NSURLProtocolClientObject: NSObject {
    var client: ProtocolClient? { ProtocolClients.states.get(objcObject) }

    @ObjCMethod("dealloc")
    func dealloc() {
        ProtocolClients.states.remove(objcObject)
        ObjCRuntime.superDealloc(objcObject, definedOn: NSURLProtocolClientObject.objCClass.pointer)
    }

    @ObjCMethod("URLProtocol:didReceiveResponse:cacheStoragePolicy:")
    func didReceive(_ urlProtocol: NSObject?, response: NSObject?, cacheStoragePolicy policy: UInt) {
        guard let response = response.flatMap({ Responses.response($0.objcObject) }) else { return }
        client?.receive(response, cachePolicy: Int(policy))
    }

    @ObjCMethod("URLProtocol:didLoadData:")
    func didLoad(_ urlProtocol: NSObject?, data: NSData?) { client?.load(data?.data ?? Data()) }

    @ObjCMethod("URLProtocolDidFinishLoading:")
    func didFinishLoading(_ urlProtocol: NSObject?) { client?.finish() }

    @ObjCMethod("URLProtocol:didFailWithError:")
    func didFail(_ urlProtocol: NSObject?, error: NSError?) {
        client?.fail(domain: error?.domain() ?? "NSURLErrorDomain", code: error?.code() ?? -1, description: error?.localizedDescription())
    }

    @ObjCMethod("URLProtocol:wasRedirectedToRequest:redirectResponse:")
    func wasRedirected(_ urlProtocol: NSObject?, to request: NSObject?, redirectResponse response: NSObject?) {
        guard let request = request.flatMap({ Requests.states.get($0.objcObject) }),
              let response = response.flatMap({ Responses.response($0.objcObject) }) else { return }
        client?.redirect(to: request, response: response)
    }

    @ObjCMethod("URLProtocol:cachedResponseIsValid:")
    func cachedResponseIsValid(_ urlProtocol: NSObject?, _ response: NSObject?) {}

    @ObjCMethod("URLProtocol:didReceiveAuthenticationChallenge:")
    func didReceiveChallenge(_ urlProtocol: NSObject?, _ challenge: NSObject?) {}

    @ObjCMethod("URLProtocol:didCancelAuthenticationChallenge:")
    func didCancelChallenge(_ urlProtocol: NSObject?, _ challenge: NSObject?) {}
}
