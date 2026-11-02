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
        notificationClass = ClassDefinition(PERRY_CLASS_NSNotification, name: "NSNotification", superclass: superclass,
                                            StorageAllocation.self, NSNotificationMethods.self).cls
        centerClass = ClassDefinition(PERRY_CLASS_NSNotificationCenter, name: "NSNotificationCenter",
                                      superclass: superclass, StorageAllocation.self,
                                      NSNotificationCenterMethods.self).cls
        // The default center lives for the whole process.
        defaultCenter = Storage.allocate(UnsafeMutableRawPointer(centerClass))
        Storage.set(defaultCenter, NotificationCenterStorage())
    }
}

@ObjCImplementation
enum NSNotificationMethods {
    @ObjCClassMethod("notificationWithName:object:")
    static func notification(_ cls: id?, name: id?, object: id?) -> id? {
        ObjC.autorelease(Notifications.make(name: name, object: object, userInfo: nil, cls: cls))
    }

    @ObjCClassMethod("notificationWithName:object:userInfo:")
    static func notification(_ cls: id?, name: id?, object: id?, userInfo: id?) -> id? {
        ObjC.autorelease(Notifications.make(name: name, object: object, userInfo: userInfo, cls: cls))
    }

    @ObjCMethod("initWithName:object:userInfo:")
    static func initialize(_ notification: id?, name: id?, object: id?, userInfo: id?) -> id? {
        guard let notification else { return nil }
        Storage.set(notification, NotificationStorage(name: name, object: object, userInfo: userInfo))
        return notification
    }

    @ObjCMethod("dealloc")
    static func dealloc(_ notification: id?) {
        guard let notification else { return }
        Storage.set(notification, nil)
        ObjC.superDealloc(notification, from: Notifications.notificationClass)
    }

    @ObjCMethod("name") static func name(_ notification: id?) -> id? { Notifications.storage(notification)?.name }
    @ObjCMethod("object") static func object(_ notification: id?) -> id? { Notifications.storage(notification)?.object }
    @ObjCMethod("userInfo") static func userInfo(_ notification: id?) -> id? { Notifications.storage(notification)?.userInfo }

    @ObjCMethod("copyWithZone:")
    static func copy(_ notification: id?, zone: UnsafeMutableRawPointer?) -> id? { ObjC.retain(notification) }
}

@ObjCImplementation
enum NSNotificationCenterMethods {
    private static func observers(_ center: id?) -> NotificationCenterStorage {
        guard let storage = Notifications.center(center) else {
            foundationFatal("message sent to an uninitialized NSNotificationCenter")
        }
        return storage
    }

    @ObjCClassMethod("defaultCenter")
    static func defaultCenter(_ cls: id?) -> id? { Notifications.defaultCenter }

    @ObjCMethod("init")
    static func initialize(_ center: id?) -> id? {
        if let center { Storage.set(center, NotificationCenterStorage()) }
        return center
    }

    @ObjCMethod("dealloc")
    static func dealloc(_ center: id?) {
        guard let center else { return }
        Storage.set(center, nil)
        ObjC.superDealloc(center, from: Notifications.centerClass)
    }

    @ObjCMethod("addObserver:selector:name:object:")
    static func add(_ center: id?, observer: id?, selector: SEL?, name: id?, object: id?) {
        guard let observer, let selector else { return }
        observers(center).observers.append(.init(observer: observer, selector: selector, block: nil, token: nil,
                                                 name: Strings.value(of: name), object: object))
    }

    /// Calls `block` for each matching notification. Operation queues do not
    /// exist yet, so the block runs on the posting thread whatever `queue` is.
    @ObjCMethod("addObserverForName:object:queue:usingBlock:")
    static func add(_ center: id?, name: id?, object: id?, queue: id?, block: ObjCBlock?) -> id? {
        guard let block, let nsObject = "NSObject".withCString({ ObjC.getClass($0) }) else { return nil }
        let token = ObjC.send(UnsafeMutableRawPointer(nsObject), ObjC.selector("new"))
        observers(center).observers.append(.init(observer: nil, selector: nil, block: ObjC.retainBlock(block),
                                                 token: token, name: Strings.value(of: name), object: object))
        return token
    }

    @ObjCMethod("removeObserver:")
    static func remove(_ center: id?, _ observer: id?) {
        guard let observer else { return }
        observers(center).remove { $0.observer == observer || $0.token == observer }
    }

    @ObjCMethod("removeObserver:name:object:")
    static func remove(_ center: id?, _ observer: id?, name: id?, object: id?) {
        guard let observer else { return }
        let name = Strings.value(of: name)
        observers(center).remove {
            ($0.observer == observer || $0.token == observer)
                && (name == nil || $0.name == name) && (object == nil || $0.object == object)
        }
    }

    @ObjCMethod("postNotification:")
    static func post(_ center: id?, _ notification: id?) {
        if let notification { Notifications.post(notification, from: center) }
    }

    @ObjCMethod("postNotificationName:object:")
    static func post(_ center: id?, name: id?, object: id?) {
        post(center, name: name, object: object, userInfo: nil)
    }

    @ObjCMethod("postNotificationName:object:userInfo:")
    static func post(_ center: id?, name: id?, object: id?, userInfo: id?) {
        guard let notification = Notifications.make(name: name, object: object, userInfo: userInfo) else { return }
        Notifications.post(notification, from: center)
        ObjC.release(notification)
    }
}
