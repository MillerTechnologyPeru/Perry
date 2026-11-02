import CPerryFoundation
import Glibc
import PerryObjCInterop

/// An NSNotification's name, object and user info, each retained.
final class NotificationStorage {
    let name: id?
    let object: id?
    let userInfo: id?

    init(name: id?, object: id?, userInfo: id?) {
        self.name = ObjC.send(name, Selectors.copyWithZone, nil)
        self.object = ObjC.retain(object)
        self.userInfo = ObjC.retain(userInfo)
    }

    deinit {
        for value in [name, object, userInfo] { ObjC.release(value) }
    }
}

/// A notification center's observers, in the order they were added.
final class NotificationCenterStorage {
    struct Observer {
        /// Not retained, as Foundation does not retain observers.
        let observer: id?
        let selector: SEL?
        /// Block observers: the block and the token returned for removing it, both retained.
        let block: id?
        let token: id?
        let name: String?
        let object: id?
    }

    var observers: [Observer] = []

    deinit {
        for observer in observers {
            ObjC.release(observer.block)
            ObjC.release(observer.token)
        }
    }

    func remove(where matches: (Observer) -> Bool) {
        let removed = observers.filter(matches)
        observers.removeAll(where: matches)
        for observer in removed {
            ObjC.release(observer.block)
            ObjC.release(observer.token)
        }
    }
}

enum Notifications {
    nonisolated(unsafe) static var notificationClass: Class!
    nonisolated(unsafe) static var centerClass: Class!
    nonisolated(unsafe) static var defaultCenter: id!

    static func storage(_ notification: id?) -> NotificationStorage? {
        Storage.get(notification, as: NotificationStorage.self)
    }

    static func center(_ object: id?) -> NotificationCenterStorage? {
        Storage.get(object, as: NotificationCenterStorage.self)
    }

    static func make(name: id?, object: id?, userInfo: id?, cls: id? = nil) -> id? {
        guard let notification = Storage.allocate(cls ?? UnsafeMutableRawPointer(notificationClass)) else { return nil }
        Storage.set(notification, NotificationStorage(name: name, object: object, userInfo: userInfo))
        return notification
    }

    /// Delivers to every matching observer, in the order they were added.
    /// Observers added or removed while posting take effect next time.
    static func post(_ notification: id, from center: id?) {
        guard let center = Notifications.center(center), let storage = storage(notification) else { return }
        let name = Strings.value(of: storage.name)
        let matching = center.observers.filter { observer in
            (observer.name == nil || observer.name == name)
                && (observer.object == nil || observer.object == storage.object)
        }
        for observer in matching {
            if let block = observer.block {
                Blocks.invoke(block, as: (@convention(c) (id, id?) -> Void).self)(block, notification)
            } else if let selector = observer.selector {
                _ = ObjC.send(observer.observer, selector, notification)
            }
        }
    }

    static func install(superclass: Class) {
        notificationClass = NSNotification.defineObjCClass(NSObject.registerObjCCategoryStorageAllocated).storage
        centerClass = NSNotificationCenter.defineObjCClass(NSObject.registerObjCCategoryStorageAllocated).storage
        // The default center lives for the whole process.
        defaultCenter = Storage.allocate(UnsafeMutableRawPointer(centerClass))
        Storage.set(defaultCenter, NotificationCenterStorage())
    }
}

/// NSNotification.
@ObjCClass("NSNotification")
public final class NSNotification: NSObject {
    private var storage: NotificationStorage? { Notifications.storage(objcObject) }

    @ObjCClassMethod("notificationWithName:object:")
    static func notification(_ cls: ObjCClass, name: ObjCObject, object: ObjCObject?) -> NSNotification? {
        Notifications.make(name: name.id, object: object?.id, userInfo: nil, cls: cls.pointer).map { NSNotification(objCOwned: $0) }
    }

    @ObjCClassMethod("notificationWithName:object:userInfo:")
    static func notification(_ cls: ObjCClass, name: ObjCObject, object: ObjCObject?, userInfo: ObjCObject?) -> NSNotification? {
        Notifications.make(name: name.id, object: object?.id, userInfo: userInfo?.id, cls: cls.pointer)
            .map { NSNotification(objCOwned: $0) }
    }

    @ObjCMethod("initWithName:object:userInfo:")
    func initialize(name: ObjCObject, object: ObjCObject?, userInfo: ObjCObject?) -> Self {
        Storage.set(objcObject, NotificationStorage(name: name.id, object: object?.id, userInfo: userInfo?.id))
        return self
    }

    @ObjCMethod("dealloc")
    func dealloc() {
        Storage.set(objcObject, nil)
        ObjC.superDealloc(objcObject, from: Notifications.notificationClass)
    }

    @ObjCMethod("name") func name() -> ObjCObject? { storage?.name.map(ObjCObject.init) }
    @ObjCMethod("object") func object() -> ObjCObject? { storage?.object.map(ObjCObject.init) }
    @ObjCMethod("userInfo") func userInfo() -> ObjCObject? { storage?.userInfo.map(ObjCObject.init) }

    @ObjCMethod("copyWithZone:")
    func copy(zone: UnsafeMutableRawPointer?) -> NSNotification { self }
}

/// NSNotificationCenter.
@ObjCClass("NSNotificationCenter")
public final class NSNotificationCenter: NSObject {
    private var observers: NotificationCenterStorage {
        guard let storage = Notifications.center(objcObject) else {
            foundationFatal("message sent to an uninitialized NSNotificationCenter")
        }
        return storage
    }

    @ObjCClassMethod("defaultCenter")
    static func defaultCenter() -> NSNotificationCenter { NSNotificationCenter(objCArgument: Notifications.defaultCenter) }

    @ObjCMethod("init")
    func initialize() -> Self {
        Storage.set(objcObject, NotificationCenterStorage())
        return self
    }

    @ObjCMethod("dealloc")
    func dealloc() {
        Storage.set(objcObject, nil)
        ObjC.superDealloc(objcObject, from: Notifications.centerClass)
    }

    @ObjCMethod("addObserver:selector:name:object:")
    func add(observer: ObjCObject, selector: ObjCSelector, name: String?, object: ObjCObject?) {
        observers.observers.append(.init(observer: observer.id, selector: selector.pointer.assumingMemoryBound(to: CChar.self),
                                         block: nil, token: nil, name: name, object: object?.id))
    }

    /// Calls `block` for each matching notification. Operation queues do not
    /// exist yet, so the block runs on the posting thread whatever `queue` is.
    @ObjCMethod("addObserverForName:object:queue:usingBlock:")
    func add(name: String?, object: ObjCObject?, queue: ObjCObject?, block: ObjCBlock) -> ObjCObject {
        let token = ObjCObject(objCOwned: ObjC.send(ObjCClass(named: "NSObject").pointer, ObjC.selector("new")))
        observers.observers.append(.init(observer: nil, selector: nil, block: ObjC.retain(block.object),
                                         token: ObjC.retain(token.id), name: name, object: object?.id))
        return token
    }

    @ObjCMethod("removeObserver:")
    func remove(_ observer: ObjCObject) {
        observers.remove { $0.observer == observer.id || $0.token == observer.id }
    }

    @ObjCMethod("removeObserver:name:object:")
    func remove(_ observer: ObjCObject, name: String?, object: ObjCObject?) {
        observers.remove {
            ($0.observer == observer.id || $0.token == observer.id)
                && (name == nil || $0.name == name) && (object == nil || $0.object == object?.id)
        }
    }

    @ObjCMethod("postNotification:")
    func post(_ notification: NSNotification) { Notifications.post(notification.id, from: objcObject) }

    @ObjCMethod("postNotificationName:object:")
    func post(name: ObjCObject, object: ObjCObject?) { post(name: name, object: object, userInfo: nil) }

    @ObjCMethod("postNotificationName:object:userInfo:")
    func post(name: ObjCObject, object: ObjCObject?, userInfo: ObjCObject?) {
        guard let notification = Notifications.make(name: name.id, object: object?.id, userInfo: userInfo?.id) else { return }
        Notifications.post(notification, from: objcObject)
        ObjC.release(notification)
    }
}
