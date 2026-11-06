import FoundationEssentials
import PerryObjCInterop

// NSProgress: units of work done out of a total, which apps show in bars
// and observe for their fraction. A child's progress counts for the units
// its parent gave it; cancellation and pausing reach the children too.

final class ProgressStorage {
    var total: Int64 = 0
    var completed: Int64 = 0
    var cancellable = true
    var pausable = false
    var cancelled = false
    var paused = false
    var localizedDescription: String?
    var localizedAdditionalDescription: String?
    var kind: String?
    var userInfo: [String: id] = [:]
    /// The parent, which keeps this progress; not retained.
    var parent: id?
    /// Retained children, with the parent's units each stands for.
    var children: [(progress: id, units: Int64)] = []
    var cancellationHandler: BlockReference?
    var pausingHandler: BlockReference?
    var resumingHandler: BlockReference?

    deinit {
        for child in children { ObjC.release(child.progress) }
        for value in userInfo.values { ObjC.release(value) }
    }
}

enum Progresses {
    nonisolated(unsafe) static var progressClass: Class!
    /// Each thread's current progress, which new progresses become children
    /// of, with the units the next child stands for.
    nonisolated(unsafe) static var current: [(progress: id, units: Int64)] = []

    static func storage(_ object: id?) -> ProgressStorage? {
        object.flatMap { Storage.get($0, as: ProgressStorage.self) }
    }

    /// A new progress for `total` units, +1, made a child of the current
    /// progress if there is one.
    static func make(total: Int64, parent: id?, cls: Class? = nil) -> id {
        let object = Storage.allocate(UnsafeMutableRawPointer(cls ?? progressClass))!
        let storage = ProgressStorage()
        storage.total = total
        Storage.set(object, storage)
        if let parent, let current = current.last, current.progress == parent {
            addChild(object, to: parent, units: current.units)
        }
        return object
    }

    static func addChild(_ child: id, to parent: id, units: Int64) {
        guard let parentStorage = storage(parent), let childStorage = storage(child) else { return }
        parentStorage.children.append((ObjC.retain(child)!, units))
        childStorage.parent = parent
    }

    /// The fraction done: the units completed, and children's fractions of
    /// the units they stand for.
    static func fraction(_ object: id) -> Double {
        guard let storage = storage(object) else { return 0 }
        guard storage.total > 0 else { return 0 }
        var done = Double(min(storage.completed, storage.total))
        for child in storage.children where !isFinished(child.progress) {
            done += Double(child.units) * fraction(child.progress)
        }
        return min(done / Double(storage.total), 1)
    }

    static func isFinished(_ object: id) -> Bool {
        guard let storage = storage(object) else { return false }
        return storage.total > 0 && storage.completed >= storage.total
    }

    static func cancel(_ object: id) {
        guard let storage = storage(object), !storage.cancelled else { return }
        KeyValueObserving.willChange(object, "cancelled", kind: 1, indexes: nil)
        storage.cancelled = true
        KeyValueObserving.didChange(object, "cancelled")
        storage.cancellationHandler.map { Blocks.invoke($0.block, as: (@convention(c) (id) -> Void).self)($0.block) }
        for child in storage.children { cancel(child.progress) }
    }

    static func setPaused(_ object: id, _ paused: Bool) {
        guard let storage = storage(object), storage.paused != paused else { return }
        KeyValueObserving.willChange(object, "paused", kind: 1, indexes: nil)
        storage.paused = paused
        KeyValueObserving.didChange(object, "paused")
        let handler = paused ? storage.pausingHandler : storage.resumingHandler
        handler.map { Blocks.invoke($0.block, as: (@convention(c) (id) -> Void).self)($0.block) }
        for child in storage.children { setPaused(child.progress, paused) }
    }

    /// Tells observers of the fraction, here and in the parents, that it
    /// changed.
    static func fractionChanged(_ object: id, _ change: () -> Void) {
        var chain: [id] = []
        var next: id? = object
        while let progress = next {
            chain.append(progress)
            next = storage(progress)?.parent
        }
        for progress in chain { KeyValueObserving.willChange(progress, "fractionCompleted", kind: 1, indexes: nil) }
        change()
        for progress in chain.reversed() { KeyValueObserving.didChange(progress, "fractionCompleted") }
    }
}

@ObjCClass("NSProgress")
public class NSProgress: NSObject {
    override public class func didDefineObjCClass(_ cls: ObjCClass) {
        NSObject.registerObjCCategoryStorageAllocated(cls)
        Progresses.progressClass = cls.storage
    }

    private var storage: ProgressStorage {
        if let storage = Progresses.storage(objcObject) { return storage }
        let storage = ProgressStorage()
        Storage.set(objcObject, storage)
        return storage
    }

    // MARK: Creating

    @ObjCClassMethod("progressWithTotalUnitCount:")
    static func progress(_ cls: ObjCClass, totalUnitCount: Int64) -> ObjCObject {
        ObjCObject(ObjC.autorelease(Progresses.make(total: totalUnitCount, parent: Progresses.current.last?.progress, cls: cls.storage))!)
    }

    /// A progress that is no one's child.
    @ObjCClassMethod("discreteProgressWithTotalUnitCount:")
    static func discreteProgress(_ cls: ObjCClass, totalUnitCount: Int64) -> ObjCObject {
        ObjCObject(ObjC.autorelease(Progresses.make(total: totalUnitCount, parent: nil, cls: cls.storage))!)
    }

    @ObjCClassMethod("progressWithTotalUnitCount:parent:pendingUnitCount:")
    static func progress(_ cls: ObjCClass, totalUnitCount: Int64, parent: ObjCObject?, pendingUnitCount: Int64) -> ObjCObject {
        let progress = Progresses.make(total: totalUnitCount, parent: nil, cls: cls.storage)
        if let parent { Progresses.addChild(progress, to: parent.id, units: pendingUnitCount) }
        return ObjCObject(ObjC.autorelease(progress)!)
    }

    @ObjCClassMethod("currentProgress")
    static func currentProgress() -> ObjCObject? { Progresses.current.last.map { ObjCObject($0.progress) } }

    @ObjCMethod("init")
    func initialize() -> Self {
        _ = storage
        return self
    }

    /// A progress made a child of the current one, if any, as
    /// +progressWithTotalUnitCount: makes them.
    @ObjCMethod("initWithParent:userInfo:")
    func initialize(parent: ObjCObject?, userInfo: ObjCObject?) -> Self {
        _ = storage
        if let parent, let current = Progresses.current.last, current.progress == parent.id {
            Progresses.addChild(objcObject, to: parent.id, units: current.units)
        }
        for entry in Dictionaries.entries(userInfo?.id) {
            storage.userInfo[String(objCArgument: entry.key)] = ObjC.retain(entry.value)
        }
        return self
    }

    // MARK: Children

    @ObjCMethod("addChild:withPendingUnitCount:")
    func addChild(_ child: ObjCObject, pendingUnitCount: Int64) {
        Progresses.fractionChanged(objcObject) { Progresses.addChild(child.id, to: objcObject, units: pendingUnitCount) }
    }

    @ObjCMethod("becomeCurrentWithPendingUnitCount:")
    func becomeCurrent(pendingUnitCount: Int64) {
        Progresses.current.append((ObjC.retain(objcObject)!, pendingUnitCount))
    }

    @ObjCMethod("resignCurrent")
    func resignCurrent() {
        guard let index = Progresses.current.lastIndex(where: { $0.progress == objcObject }) else { return }
        let current = Progresses.current.remove(at: index)
        ObjC.release(current.progress)
    }

    @ObjCMethod("performAsCurrentWithPendingUnitCount:usingBlock:")
    func performAsCurrent(pendingUnitCount: Int64, block: ObjCBlock) {
        becomeCurrent(pendingUnitCount: pendingUnitCount)
        block.function(as: (@convention(c) (id) -> Void).self)(block.object)
        resignCurrent()
    }

    // MARK: Counts

    @ObjCMethod("totalUnitCount") func totalUnitCount() -> Int64 { storage.total }
    @ObjCMethod("setTotalUnitCount:")
    func setTotalUnitCount(_ count: Int64) {
        Progresses.fractionChanged(objcObject) { storage.total = count }
    }

    @ObjCMethod("completedUnitCount") func completedUnitCount() -> Int64 { storage.completed }
    @ObjCMethod("setCompletedUnitCount:")
    func setCompletedUnitCount(_ count: Int64) {
        Progresses.fractionChanged(objcObject) { storage.completed = count }
    }

    @ObjCMethod("fractionCompleted") func fractionCompleted() -> Double { Progresses.fraction(objcObject) }
    @ObjCMethod("isFinished") func isFinished() -> Bool { Progresses.isFinished(objcObject) }
    /// Indeterminate while there is no total.
    @ObjCMethod("isIndeterminate") func isIndeterminate() -> Bool { storage.total <= 0 }

    // MARK: Descriptions

    @ObjCMethod("localizedDescription")
    func localizedDescription() -> String {
        storage.localizedDescription ?? "\(Int((Progresses.fraction(objcObject) * 100).rounded()))% completed"
    }
    @ObjCMethod("setLocalizedDescription:") func setLocalizedDescription(_ text: String?) { storage.localizedDescription = text }

    @ObjCMethod("localizedAdditionalDescription")
    func localizedAdditionalDescription() -> String {
        storage.localizedAdditionalDescription ?? "\(storage.completed) of \(storage.total)"
    }
    @ObjCMethod("setLocalizedAdditionalDescription:")
    func setLocalizedAdditionalDescription(_ text: String?) { storage.localizedAdditionalDescription = text }

    @ObjCMethod("kind") func kind() -> String? { storage.kind }
    @ObjCMethod("setKind:") func setKind(_ kind: String?) { storage.kind = kind }

    @ObjCMethod("userInfo")
    func userInfo() -> ObjCObject {
        ObjCObject(Dictionaries.autoreleased(storage.userInfo.map { (key: Strings.autoreleased($0.key), value: $0.value) }))
    }

    @ObjCMethod("setUserInfoObject:forKey:")
    func setUserInfoObject(_ value: ObjCObject?, forKey key: String) {
        if let old = storage.userInfo.removeValue(forKey: key) { ObjC.release(old) }
        if let value { storage.userInfo[key] = ObjC.retain(value.id) }
    }

    // MARK: Cancelling and pausing

    @ObjCMethod("isCancellable") func isCancellable() -> Bool { storage.cancellable }
    @ObjCMethod("setCancellable:") func setCancellable(_ cancellable: Bool) { storage.cancellable = cancellable }
    @ObjCMethod("isCancelled") func isCancelled() -> Bool { storage.cancelled || Progresses.storage(storage.parent).map { $0.cancelled } == true }
    @ObjCMethod("cancel") func cancel() { Progresses.cancel(objcObject) }

    @ObjCMethod("isPausable") func isPausable() -> Bool { storage.pausable }
    @ObjCMethod("setPausable:") func setPausable(_ pausable: Bool) { storage.pausable = pausable }
    @ObjCMethod("isPaused") func isPaused() -> Bool { storage.paused }
    @ObjCMethod("pause") func pause() { Progresses.setPaused(objcObject, true) }
    @ObjCMethod("resume") func resume() { Progresses.setPaused(objcObject, false) }

    @ObjCMethod("cancellationHandler") func cancellationHandler() -> ObjCObject? { storage.cancellationHandler.map { ObjCObject($0.block) } }
    @ObjCMethod("setCancellationHandler:")
    func setCancellationHandler(_ handler: ObjCObject?) { storage.cancellationHandler = BlockReference(handler?.id) }
    @ObjCMethod("setPausingHandler:")
    func setPausingHandler(_ handler: ObjCObject?) { storage.pausingHandler = BlockReference(handler?.id) }
    @ObjCMethod("setResumingHandler:")
    func setResumingHandler(_ handler: ObjCObject?) { storage.resumingHandler = BlockReference(handler?.id) }

    @ObjCMethod("description")
    func description() -> String {
        "<NSProgress: \(String(UInt(bitPattern: objcObject), radix: 16))> : Fraction completed: \(Progresses.fraction(objcObject)) / Completed: \(storage.completed) of \(storage.total)"
    }
}
