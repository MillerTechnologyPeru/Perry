import CPerryFoundation
import Glibc
import PerryObjCInterop

/// A lock's pthread mutex, and the condition variable NSCondition adds.
final class LockStorage {
    let mutex = UnsafeMutablePointer<pthread_mutex_t>.allocate(capacity: 1)
    let condition = UnsafeMutablePointer<pthread_cond_t>.allocate(capacity: 1)
    var name: id?

    init(recursive: Bool) {
        var attributes = pthread_mutexattr_t()
        pthread_mutexattr_init(&attributes)
        if recursive { pthread_mutexattr_settype(&attributes, Int32(PTHREAD_MUTEX_RECURSIVE)) }
        pthread_mutex_init(mutex, &attributes)
        pthread_mutexattr_destroy(&attributes)
        pthread_cond_init(condition, nil)
    }

    deinit {
        pthread_mutex_destroy(mutex)
        pthread_cond_destroy(condition)
        mutex.deallocate()
        condition.deallocate()
        ObjC.release(name)
    }

    /// Waits for the lock until `date` (absolute time), polling as glibc
    /// has no timed lock for every mutex type.
    func lock(before date: Double) -> Bool {
        while pthread_mutex_trylock(mutex) != 0 {
            if absoluteTimeNow() >= date { return false }
            usleep(1000)
        }
        return true
    }

    /// pthread_cond_timedwait until `date` (absolute time); false on timeout.
    func wait(until date: Double) -> Bool {
        let unix = date + referenceDateOffset
        var time = timespec()
        guard unix.isFinite, unix < Double(Int32.max) else {
            pthread_cond_wait(condition, mutex)
            return true
        }
        time.tv_sec = Int(unix)
        time.tv_nsec = Int((unix - floor(unix)) * 1e9)
        return pthread_cond_timedwait(condition, mutex, &time) == 0
    }
}

enum Locks {
    static func storage(_ object: id?) -> LockStorage? {
        Storage.get(object, as: LockStorage.self)
    }
}

/// NSLock, NSRecursiveLock and NSCondition share their NSLocking methods.
@ObjCCategory("Locking", addedAtStartup: false)
extension NSObject {
    @ObjCMethod("lock") func lock() { Locks.storage(objcObject).map { pthread_mutex_lock($0.mutex) } }
    @ObjCMethod("unlock") func unlock() { Locks.storage(objcObject).map { pthread_mutex_unlock($0.mutex) } }

    @ObjCMethod("tryLock")
    func tryLock() -> Bool { Locks.storage(objcObject).map { pthread_mutex_trylock($0.mutex) == 0 } ?? false }

    @ObjCMethod("lockBeforeDate:")
    func lock(before date: ObjCObject) -> Bool {
        let limit = Dates.interval(date.id)
        return Locks.storage(objcObject)?.lock(before: limit) ?? false
    }

    @ObjCMethod("name") func lockName() -> ObjCObject? { Locks.storage(objcObject)?.name.map(ObjCObject.init) }

    @ObjCMethod("setName:")
    func setLockName(_ name: ObjCObject?) {
        guard let storage = Locks.storage(objcObject) else { return }
        let copy = name.flatMap { ObjC.send($0.id, Selectors.copyWithZone, nil) }
        ObjC.release(storage.name)
        storage.name = copy
    }
}

/// NSLock.
@ObjCClass("NSLock")
public final class NSLock: NSObject {
    override public class func didDefineObjCClass(_ cls: ObjCClass) {
        NSObject.registerObjCCategoryStorageAllocated(cls)
        NSObject.registerObjCCategoryLocking(cls)
    }

    @ObjCMethod("init")
    func initialize() -> Self {
        Storage.set(objcObject, LockStorage(recursive: false))
        return self
    }
}

/// NSRecursiveLock.
@ObjCClass("NSRecursiveLock")
public final class NSRecursiveLock: NSObject {
    override public class func didDefineObjCClass(_ cls: ObjCClass) {
        NSObject.registerObjCCategoryStorageAllocated(cls)
        NSObject.registerObjCCategoryLocking(cls)
    }

    @ObjCMethod("init")
    func initialize() -> Self {
        Storage.set(objcObject, LockStorage(recursive: true))
        return self
    }
}

/// NSCondition.
@ObjCClass("NSCondition")
public final class NSCondition: NSObject {
    override public class func didDefineObjCClass(_ cls: ObjCClass) {
        NSObject.registerObjCCategoryStorageAllocated(cls)
        NSObject.registerObjCCategoryLocking(cls)
    }

    @ObjCMethod("init")
    func initialize() -> Self {
        Storage.set(objcObject, LockStorage(recursive: false))
        return self
    }

    @ObjCMethod("wait")
    func wait() {
        guard let storage = Locks.storage(objcObject) else { return }
        pthread_cond_wait(storage.condition, storage.mutex)
    }

    @ObjCMethod("waitUntilDate:")
    func wait(until date: ObjCObject) -> Bool {
        Locks.storage(objcObject)?.wait(until: Dates.interval(date.id)) ?? false
    }

    @ObjCMethod("signal")
    func signal() { Locks.storage(objcObject).map { pthread_cond_signal($0.condition) } }

    @ObjCMethod("broadcast")
    func broadcast() { Locks.storage(objcObject).map { pthread_cond_broadcast($0.condition) } }
}
