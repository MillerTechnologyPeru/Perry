import CPerryFoundation
import Glibc
import PerryObjCInterop

// NSNotificationQueue: notifications posted later, through a notification
// center, as the run loop of the thread that queued them turns: "as soon as
// possible" ones at the start of its next pass (and as a run of it ends),
// "when idle" ones as it is about to wait, as on Darwin. A notification
// matching one already queued (by name, by sender, or both, as its coalescing
// mask says) is coalesced: dropped if the one queued posts as soon or sooner,
// else taking its place. Every mode is the same run loop here, so the modes
// a notification is queued for don't hold it back.

/// A queue's center and its notifications, each retained, in the order
/// queued.
final class NotificationQueueStorage {
    let center: id
    var asap: [id] = []
    var idle: [id] = []
    let monitor = Monitor()

    init(center: id) {
        self.center = ObjC.retain(center)!
    }

    deinit {
        ObjC.release(center)
        for notification in asap + idle { ObjC.release(notification) }
    }

    /// Takes the notifications of one style off the queue, +1 each.
    func take(idle wanted: Bool) -> [id] {
        monitor.locked {
            defer { if wanted { idle = [] } else { asap = [] } }
            return wanted ? idle : asap
        }
    }

    /// The queued notifications of one style or both, in the order
    /// queued, retained and autoreleased: the caller sends them -object and
    /// -name with the monitor unlocked. They may be the app's subclasses,
    /// whose methods may raise, and an exception unwinds through Swift
    /// without unlocking.
    func queued(asap wantASAP: Bool = true, idle wantIdle: Bool = true) -> [id] {
        let queued: [id] = monitor.locked {
            ((wantASAP ? asap : []) + (wantIdle ? idle : [])).map { ObjC.retain($0)! }
        }
        return queued.map { ObjC.autorelease($0)! }
    }

    /// Removes the queued notifications matching `notification`, of one
    /// style or both.
    func remove(matching notification: id, mask: UInt, fromASAP: Bool = true, fromIdle: Bool = true) {
        let matching = queued(asap: fromASAP, idle: fromIdle).filter { NotificationQueues.matches($0, notification, mask: mask) }
        guard !matching.isEmpty else { return }
        let removed: [id] = monitor.locked {
            var removed: [id] = []
            if fromASAP {
                let split = asap.split { matching.contains($0) }
                asap = split.kept
                removed += split.removed
            }
            if fromIdle {
                let split = idle.split { matching.contains($0) }
                idle = split.kept
                removed += split.removed
            }
            return removed
        }
        removed.forEach { ObjC.release($0) }
    }
}

/// NSPostingStyle and NSNotificationCoalescing.
private enum PostingStyle {
    static let whenIdle: UInt = 1
    static let asap: UInt = 2
    static let now: UInt = 3
    static let onName: UInt = 1
    static let onSender: UInt = 2
}

enum NotificationQueues {
    nonisolated(unsafe) static var queueClass: Class!

    private static let lock = Monitor()
    /// Each thread's default queue, by its run loop, held as long as the
    /// thread's loop lives (threads' loops outlive their threads here).
    nonisolated(unsafe) private static var defaults: [ObjectIdentifier: id] = [:]
    /// The queues with notifications waiting for each run loop's passes,
    /// held while they wait.
    nonisolated(unsafe) private static var waiting: [ObjectIdentifier: [NotificationQueueStorage]] = [:]

    static func storage(_ object: id?) -> NotificationQueueStorage? {
        Storage.get(object, as: NotificationQueueStorage.self)
    }

    /// The calling thread's default queue, for the default center.
    static var defaultQueue: id {
        let loop = RunLoops.current
        let key = ObjectIdentifier(loop)
        return lock.locked {
            if let queue = defaults[key] { return queue }
            let queue = Storage.allocate(UnsafeMutableRawPointer(queueClass))!
            Storage.set(queue, NotificationQueueStorage(center: Notifications.defaultCenter!))
            defaults[key] = queue
            return queue
        }
    }

    /// Whether two notifications match by the mask's name and sender; a
    /// mask of neither matches nothing, as on Darwin.
    static func matches(_ first: id, _ second: id, mask: UInt) -> Bool {
        guard mask & (PostingStyle.onName | PostingStyle.onSender) != 0 else { return false }
        if mask & PostingStyle.onSender != 0,
           ObjC.send(first, ObjC.selector("object")) != ObjC.send(second, ObjC.selector("object")) { return false }
        if mask & PostingStyle.onName != 0 {
            let name = ObjC.send(first, ObjC.selector("name")), other = ObjC.send(second, ObjC.selector("name"))
            guard name == other || Strings.value(of: name) == Strings.value(of: other) else { return false }
        }
        return true
    }

    /// Has the current run loop post the queue's notifications as it turns.
    static func schedule(_ queue: NotificationQueueStorage) {
        let loop = RunLoops.current
        let key = ObjectIdentifier(loop)
        let first = lock.locked { () -> Bool in
            let isNew = waiting[key] == nil
            var queues = waiting[key] ?? []
            if !queues.contains(where: { $0 === queue }) { queues.append(queue) }
            waiting[key] = queues
            return isNew
        }
        if first { loop.setPassHook { activity in NotificationQueues.pass(key, activity) } }
    }

    /// A run loop's pass: as soon as possible notifications at its start
    /// and as a run ends, when idle ones as it is about to wait. Those
    /// queued while posting wait for the next time.
    private static func pass(_ key: ObjectIdentifier, _ activity: UInt) {
        let idle: Bool
        switch activity {
        case RunLoopActivity.beforeTimers, RunLoopActivity.exit: idle = false
        case RunLoopActivity.beforeWaiting: idle = true
        default: return
        }
        let queues = lock.locked { waiting[key] ?? [] }
        for queue in queues {
            for notification in queue.take(idle: idle) {
                Notifications.post(notification, from: queue.center)
                ObjC.release(notification)
            }
        }
        // A queue the app has let go of goes once the lock is open: its
        // center may be the app's, whose -dealloc runs as it goes.
        let finished: [NotificationQueueStorage] = lock.locked {
            guard let queues = waiting[key] else { return [] }
            let split = queues.split { queue in queue.monitor.locked { queue.asap.isEmpty && queue.idle.isEmpty } }
            waiting[key] = split.kept
            return split.removed
        }
        withExtendedLifetime(finished) {}
    }
}

/// NSNotificationQueue.
@ObjCClass("NSNotificationQueue")
public final class NSNotificationQueue: NSObject {
    override public class func didDefineObjCClass(_ cls: ObjCClass) {
        NSObject.registerObjCCategoryStorageAllocated(cls)
        NotificationQueues.queueClass = cls.storage
    }

    private var storage: NotificationQueueStorage? { NotificationQueues.storage(objcObject) }

    /// The calling thread's queue, which posts to the default center.
    @ObjCClassMethod("defaultQueue")
    static func defaultQueue() -> UnsafeMutableRawPointer? { NotificationQueues.defaultQueue }

    @ObjCMethod("initWithNotificationCenter:")
    func initialize(center: ObjCObject?) -> Self {
        Storage.set(objcObject, NotificationQueueStorage(center: center?.id ?? Notifications.defaultCenter!))
        return self
    }

    @ObjCMethod("dealloc")
    func dealloc() {
        Storage.set(objcObject, nil)
        ObjC.superDealloc(objcObject, from: NotificationQueues.queueClass)
    }

    /// Coalesced by name and sender.
    @ObjCMethod("enqueueNotification:postingStyle:")
    func enqueue(_ notification: ObjCObject?, postingStyle: UInt) {
        enqueue(notification, postingStyle: postingStyle, coalesceMask: PostingStyle.onName | PostingStyle.onSender, forModes: nil)
    }

    /// NSPostNow posts at once, taking matching notifications off the
    /// queue; NSPostASAP is dropped for a matching one queued as soon as
    /// possible and replaces one queued for when idle; NSPostWhenIdle is
    /// dropped for any matching one.
    @ObjCMethod("enqueueNotification:postingStyle:coalesceMask:forModes:")
    func enqueue(_ notification: ObjCObject?, postingStyle: UInt, coalesceMask: UInt, forModes modes: ObjCObject?) {
        guard let notification, let storage else { return }
        let object = notification.id
        switch postingStyle {
        case PostingStyle.now:
            storage.remove(matching: object, mask: coalesceMask)
            Notifications.post(object, from: storage.center)
        case PostingStyle.asap:
            let queued = storage.queued(idle: false).contains { NotificationQueues.matches($0, object, mask: coalesceMask) }
            guard !queued else { return }
            storage.remove(matching: object, mask: coalesceMask, fromASAP: false)
            storage.monitor.locked { storage.asap.append(ObjC.retain(object)!) }
            NotificationQueues.schedule(storage)
        default:
            let queued = storage.queued().contains { NotificationQueues.matches($0, object, mask: coalesceMask) }
            guard !queued else { return }
            storage.monitor.locked { storage.idle.append(ObjC.retain(object)!) }
            NotificationQueues.schedule(storage)
        }
    }

    /// Takes the queued notifications matching by the mask off the queue; a
    /// mask of neither name nor sender takes none.
    @ObjCMethod("dequeueNotificationsMatching:coalesceMask:")
    func dequeue(matching notification: ObjCObject?, coalesceMask: UInt) {
        guard let notification, let storage else { return }
        storage.remove(matching: notification.id, mask: coalesceMask)
    }
}
