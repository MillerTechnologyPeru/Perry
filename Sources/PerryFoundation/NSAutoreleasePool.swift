import PerryObjCInterop

// NSAutoreleasePool: a pool pushed when the object is made and popped when
// it is drained or released, as @autoreleasepool does. -release is not
// overridden: Perry's own references to the object come and go through it.

final class PoolStorage {
    var token: UnsafeMutableRawPointer?
    init(_ token: UnsafeMutableRawPointer?) { self.token = token }
}

enum Pools {
    nonisolated(unsafe) static var poolClass: Class!
}

@ObjCClass("NSAutoreleasePool")
public final class NSAutoreleasePool: NSObject {
    override public class func didDefineObjCClass(_ cls: ObjCClass) {
        NSObject.registerObjCCategoryStorageAllocated(cls)
        Pools.poolClass = cls.storage
    }

    @ObjCClassMethod("addObject:") static func add(_ cls: ObjCClass, _ object: ObjCObject?) { _ = ObjC.autorelease(object?.id) }

    @ObjCMethod("init")
    func initialize() -> Self {
        Storage.set(objcObject, PoolStorage(ObjC.poolPush()))
        return self
    }

    @ObjCMethod("addObject:") func add(_ object: ObjCObject?) { _ = ObjC.autorelease(object?.id) }

    /// -release frees the pool, which pops it.
    @ObjCMethod("drain") func drain() { ObjC.release(objcObject) }

    /// Pops the pool, if it is still pushed.
    @ObjCMethod("dealloc")
    func dealloc() {
        if let storage = Storage.get(objcObject, as: PoolStorage.self), let token = storage.token {
            storage.token = nil
            ObjC.poolPop(token)
        }
        Storage.set(objcObject, nil)
        ObjC.superDealloc(objcObject, from: Pools.poolClass)
    }
}
