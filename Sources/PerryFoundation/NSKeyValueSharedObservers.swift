import CPerryFoundation
import PerryObjCInterop

// Key-value observers shared by many objects of one class (iOS 18): an
// NSKeyValueSharedObservers collects observers and the keys they observe,
// and a snapshot of it, given to an object's -setSharedObservers:, has the
// object observed by all of them at once (KeyValueObserving.swift). Darwin
// does it to save registering each observer with each object; here each
// object gets the registrations -addObserver:forKeyPath:… would make.

/// What a shared observers object, or a snapshot of one, holds.
final class SharedObserversStorage {
    let observableClass: Class?
    var registrations: [KeyValueObserving.SharedRegistration]

    init(observableClass: Class?, registrations: [KeyValueObserving.SharedRegistration] = []) {
        self.observableClass = observableClass
        self.registrations = registrations
    }
}

@ObjCClass("NSKeyValueSharedObservers")
public class NSKeyValueSharedObservers: NSObject {
    nonisolated(unsafe) static var observersClass: Class!

    override public class func didDefineObjCClass(_ cls: ObjCClass) {
        NSObject.registerObjCCategoryStorageAllocated(cls)
        observersClass = cls.storage
    }

    private var storage: SharedObserversStorage? { Storage.get(objcObject, as: SharedObserversStorage.self) }

    @ObjCMethod("initWithObservableClass:")
    func initialize(observableClass: UnsafeMutableRawPointer?) -> Self {
        Storage.set(objcObject, SharedObserversStorage(observableClass: observableClass?.assumingMemoryBound(to: Class.Pointee.self)))
        return self
    }

    /// Kept for the snapshots made from now on; the observer isn't retained.
    @ObjCMethod("addSharedObserver:forKey:options:context:")
    func addSharedObserver(_ observer: UnsafeMutableRawPointer?, forKey key: String, options: UInt, context: UnsafeMutableRawPointer?) {
        guard let observer else { return }
        if storage == nil { Storage.set(objcObject, SharedObserversStorage(observableClass: nil)) }
        storage?.registrations.append(.init(observer: observer, key: key, options: options, context: context))
    }

    @ObjCMethod("snapshot")
    func snapshot() -> UnsafeMutableRawPointer? {
        guard let object = Storage.allocate(UnsafeMutableRawPointer(NSKeyValueSharedObserversSnapshot.snapshotClass)) else { return nil }
        Storage.set(object, SharedObserversStorage(observableClass: storage?.observableClass,
                                                   registrations: storage?.registrations ?? []))
        return ObjC.autorelease(object)
    }

    @ObjCMethod("dealloc")
    func dealloc() {
        Storage.set(objcObject, nil)
        ObjC.superDealloc(objcObject, from: NSKeyValueSharedObservers.observersClass)
    }
}

/// The observers as they were when the snapshot was taken.
@ObjCClass("NSKeyValueSharedObserversSnapshot")
public class NSKeyValueSharedObserversSnapshot: NSObject {
    nonisolated(unsafe) static var snapshotClass: Class!

    override public class func didDefineObjCClass(_ cls: ObjCClass) {
        NSObject.registerObjCCategoryStorageAllocated(cls)
        snapshotClass = cls.storage
    }

    @ObjCMethod("dealloc")
    func dealloc() {
        Storage.set(objcObject, nil)
        ObjC.superDealloc(objcObject, from: NSKeyValueSharedObserversSnapshot.snapshotClass)
    }
}
