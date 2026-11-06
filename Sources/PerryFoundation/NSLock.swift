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

/// A condition lock's state: whether it is held, and the condition it was
/// left with, under a mutex of its own.
final class ConditionLockStorage {
    let lock = LockStorage(recursive: false)
    var held = false
    var condition = 0

    /// Takes the lock when it is free and, with `wanted`, when its
    /// condition is that, waiting until `date` (absolute time) if there is
    /// one; false when the date passes first, or at once when not waiting.
    func take(when wanted: Int?, until date: Double?, waiting: Bool = true) -> Bool {
        pthread_mutex_lock(lock.mutex)
        defer { pthread_mutex_unlock(lock.mutex) }
        while held || (wanted != nil && wanted != condition) {
            guard waiting else { return false }
            if let date {
                if absoluteTimeNow() >= date || !lock.wait(until: date) {
                    if held || (wanted != nil && wanted != condition) { return false }
                }
            } else {
                pthread_cond_wait(lock.condition, lock.mutex)
            }
        }
        held = true
        return true
    }

    func leave(with condition: Int?) {
        pthread_mutex_lock(lock.mutex)
        if let condition { self.condition = condition }
        held = false
        pthread_cond_broadcast(lock.condition)
        pthread_mutex_unlock(lock.mutex)
    }
}

/// NSConditionLock: a lock taken when it holds a given condition, an
/// integer its last holder left it with.
@ObjCClass("NSConditionLock")
public final class NSConditionLock: NSObject {
    override public class func didDefineObjCClass(_ cls: ObjCClass) {
        NSObject.registerObjCCategoryStorageAllocated(cls)
    }

    private var storage: ConditionLockStorage? { Storage.get(objcObject, as: ConditionLockStorage.self) }

    @ObjCMethod("init")
    func initialize() -> Self { initialize(condition: 0) }

    @ObjCMethod("initWithCondition:")
    func initialize(condition: Int) -> Self {
        let storage = ConditionLockStorage()
        storage.condition = condition
        Storage.set(objcObject, storage)
        return self
    }

    @ObjCMethod("condition") func condition() -> Int { storage?.condition ?? 0 }

    // Named apart from NSLocking's, which NSObject's category has.
    @ObjCMethod("lock") func take() { _ = storage?.take(when: nil, until: nil) }
    @ObjCMethod("lockWhenCondition:") func take(whenCondition condition: Int) { _ = storage?.take(when: condition, until: nil) }
    @ObjCMethod("tryLock") func tryTake() -> Bool { storage?.take(when: nil, until: nil, waiting: false) ?? false }
    @ObjCMethod("tryLockWhenCondition:")
    func tryTake(whenCondition condition: Int) -> Bool { storage?.take(when: condition, until: nil, waiting: false) ?? false }

    @ObjCMethod("lockBeforeDate:")
    func take(before date: ObjCObject) -> Bool { storage?.take(when: nil, until: Dates.interval(date.id)) ?? false }
    @ObjCMethod("lockWhenCondition:beforeDate:")
    func take(whenCondition condition: Int, before date: ObjCObject) -> Bool {
        storage?.take(when: condition, until: Dates.interval(date.id)) ?? false
    }

    @ObjCMethod("unlock") func leave() { storage?.leave(with: nil) }
    @ObjCMethod("unlockWithCondition:") func leave(withCondition condition: Int) { storage?.leave(with: condition) }
}
