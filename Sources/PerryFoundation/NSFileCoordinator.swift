import FoundationEssentials
import Synchronization
import PerryObjCInterop

// NSFileCoordinator: coordinates access to files with the other processes and
// file presenters that use them. Nothing else here reads or writes an app's
// files, so access is always granted at once: the accessor is called as the
// coordinator is asked, with the URL, and no error. The intent-based method
// calls its accessor later, on a global queue, as the real one does on its
// queue's operations. File presenters are not told of anything.

/// The file an intent is for and how it is used, kept in the object's storage.
final class IntentStorage {
    /// The file's URL, retained.
    var file: id?
    var options: UInt = 0
    var writes = false

    deinit {
        if let file { ObjC.release(file) }
    }
}

/// One file's access, to read or to write, which a coordinator grants.
@ObjCClass("NSFileAccessIntent")
public class NSFileAccessIntent: NSObject {
    nonisolated(unsafe) static var intentClass: Class!

    override public class func didDefineObjCClass(_ cls: ObjCClass) {
        NSObject.registerObjCCategoryStorageAllocated(cls)
        intentClass = cls.storage
    }

    var storage: IntentStorage? { Storage.get(objcObject, as: IntentStorage.self) }

    @ObjCMethod("dealloc")
    func dealloc() {
        Storage.set(objcObject, nil)
        ObjC.superDealloc(objcObject, from: NSFileAccessIntent.intentClass)
    }

    private static func make(_ cls: ObjCClass, _ url: ObjCObject, _ options: UInt, writes: Bool) -> UnsafeMutableRawPointer? {
        guard let object = Storage.allocate(cls.pointer) else { return nil }
        let storage = IntentStorage()
        storage.file = ObjC.retain(url.id)
        storage.options = options
        storage.writes = writes
        Storage.set(object, storage)
        return ObjC.autorelease(object)
    }

    @ObjCClassMethod("readingIntentWithURL:options:")
    static func reading(_ cls: ObjCClass, url: ObjCObject, options: UInt) -> UnsafeMutableRawPointer? {
        make(cls, url, options, writes: false)
    }

    @ObjCClassMethod("writingIntentWithURL:options:")
    static func writing(_ cls: ObjCClass, url: ObjCObject, options: UInt) -> UnsafeMutableRawPointer? {
        make(cls, url, options, writes: true)
    }

    @ObjCMethod("URL")
    func url() -> ObjCObject? { storage?.file.map { ObjCObject($0) } }
}

/// The accessor of an intent-based request, which runs on a queue.
private final class Access {
    let accessor: id
    let coordinator: UInt

    init(_ accessor: id, coordinator: UInt) {
        self.accessor = ObjC.retainBlock(accessor) ?? accessor
        self.coordinator = coordinator
    }

    deinit { ObjC.release(accessor) }
}

/// Each coordinator's purpose identifier, by coordinator, once asked for
/// or set.
private let coordinatorPurposes = Mutex<[UInt: String]>([:])

/// How many of each coordinator's accessors are running, by coordinator.
private let coordinatorAccesses = Mutex<[UInt: Int]>([:])

/// Runs an accessor of the coordinator's, counted as running meanwhile.
private func coordinatorAccess(_ coordinator: UInt, _ body: () -> Void) {
    coordinatorAccesses.withLock { $0[coordinator, default: 0] += 1 }
    body()
    coordinatorAccesses.withLock {
        let remaining = ($0[coordinator] ?? 1) - 1
        $0[coordinator] = remaining > 0 ? remaining : nil
    }
}

@ObjCClass("NSFileCoordinator")
open class NSFileCoordinator: NSObject {
    nonisolated(unsafe) static var coordinatorClass: Class!

    override open class func didDefineObjCClass(_ cls: ObjCClass) {
        coordinatorClass = cls.storage
    }

    @ObjCMethod("init")
    public required override init() {
        super.init()
        forgetPurpose()
    }

    /// A new coordinator has no purpose yet, though one that was at its
    /// address had: coordinators made with -initWithFilePresenter: have no
    /// Swift object to end with them, so the table is cleared as they start.
    private func forgetPurpose() {
        let key = UInt(bitPattern: objcObject)
        coordinatorPurposes.withLock { _ = $0.removeValue(forKey: key) }
    }

    /// None are registered with the system here, so there are none to list.
    @ObjCClassMethod("filePresenters")
    static func filePresenters() -> UnsafeMutableRawPointer? { Arrays.autoreleased([]) }

    /// What groups this coordinator's accesses with a presenter's: a new
    /// UUID's string for each coordinator, as on Darwin, until one is set.
    @ObjCMethod("purposeIdentifier")
    func purposeIdentifier() -> String {
        let key = UInt(bitPattern: objcObject)
        return coordinatorPurposes.withLock { purposes in
            if let purpose = purposes[key] { return purpose }
            let purpose = UUID().uuidString
            purposes[key] = purpose
            return purpose
        }
    }

    @ObjCMethod("setPurposeIdentifier:")
    func setPurposeIdentifier(_ purpose: String?) {
        let key = UInt(bitPattern: objcObject)
        coordinatorPurposes.withLock { $0[key] = purpose }
    }

    // Moves and iCloud changes the program announces: no presenters here
    // are told of them. A move is announced from one of the coordinator's
    // accessors, as Darwin requires; elsewhere it raises, as there.

    private func requireAccess(_ method: String) {
        let key = UInt(bitPattern: objcObject)
        guard coordinatorAccesses.withLock({ $0[key] ?? 0 }) == 0 else { return }
        Exceptions.raise(name: "NSInvalidArgumentException",
                         reason: "-[NSFileCoordinator \(method)] may only be invoked from within a block passed to a -coordinate... method.")
    }

    @ObjCMethod("itemAtURL:willMoveToURL:")
    func item(at url: ObjCObject?, willMoveTo newURL: ObjCObject?) { requireAccess("itemAtURL:willMoveToURL:") }

    @ObjCMethod("itemAtURL:didMoveToURL:")
    func item(at url: ObjCObject?, didMoveTo newURL: ObjCObject?) { requireAccess("itemAtURL:didMoveToURL:") }

    @ObjCMethod("itemAtURL:didChangeUbiquityAttributes:")
    func item(at url: ObjCObject?, didChangeUbiquityAttributes attributes: ObjCObject?) {}

    /// The batch form: the accessor is called at once, with a completion
    /// handler to call when it is done, which has nothing to release.
    @ObjCMethod("prepareForReadingItemsAtURLs:options:writingItemsAtURLs:options:error:byAccessor:")
    func prepareForReadingItems(at readingURLs: ObjCObject?, options: UInt, writingItemsAt writingURLs: ObjCObject?,
                                writingOptions: UInt, error: UnsafeMutablePointer<id?>?, accessor: ObjCObject) {
        Blocks.invoke(accessor.id, as: (@convention(c) (id, id?) -> Void).self)(accessor.id, IgnoredBlock.block)
    }

    @ObjCMethod("initWithFilePresenter:")
    func initialize(presenter: ObjCObject?) -> Self {
        forgetPurpose()
        return self
    }

    @ObjCClassMethod("addFilePresenter:") static func addFilePresenter(_ presenter: ObjCObject?) {}
    @ObjCClassMethod("removeFilePresenter:") static func removeFilePresenter(_ presenter: ObjCObject?) {}

    @ObjCMethod("cancel") func cancel() {}

    /// Calls the accessor with no error, later on a global queue.
    @ObjCMethod("coordinateAccessWithIntents:queue:byAccessor:")
    func coordinate(intents: ObjCObject?, queue: ObjCObject?, accessor: ObjCObject?) {
        guard let accessor, let globalQueue = Dispatch.globalQueue?(0x15, 0), let async = Dispatch.async else { return }
        let context = Unmanaged.passRetained(Access(accessor.id, coordinator: UInt(bitPattern: objcObject))).toOpaque()
        async(globalQueue, context) { context in
            guard let context else { return }
            let access = Unmanaged<Access>.fromOpaque(context).takeRetainedValue()
            coordinatorAccess(access.coordinator) {
                Blocks.invoke(access.accessor, as: (@convention(c) (id, id?) -> Void).self)(access.accessor, nil)
            }
        }
    }

    @ObjCMethod("coordinateReadingItemAtURL:options:error:byAccessor:")
    func coordinateReading(url: ObjCObject, options: UInt, error: UnsafeMutablePointer<id?>?, accessor: ObjCObject) {
        coordinatorAccess(UInt(bitPattern: objcObject)) {
            Blocks.invoke(accessor.id, as: (@convention(c) (id, id) -> Void).self)(accessor.id, url.id)
        }
    }

    @ObjCMethod("coordinateWritingItemAtURL:options:error:byAccessor:")
    func coordinateWriting(url: ObjCObject, options: UInt, error: UnsafeMutablePointer<id?>?, accessor: ObjCObject) {
        coordinatorAccess(UInt(bitPattern: objcObject)) {
            Blocks.invoke(accessor.id, as: (@convention(c) (id, id) -> Void).self)(accessor.id, url.id)
        }
    }

    @ObjCMethod("coordinateReadingItemAtURL:options:writingItemAtURL:options:error:byAccessor:")
    func coordinateReading(url: ObjCObject, options: UInt, writingURL: ObjCObject, writingOptions: UInt,
                           error: UnsafeMutablePointer<id?>?, accessor: ObjCObject) {
        coordinatorAccess(UInt(bitPattern: objcObject)) {
            Blocks.invoke(accessor.id, as: (@convention(c) (id, id, id) -> Void).self)(accessor.id, url.id, writingURL.id)
        }
    }

    @ObjCMethod("coordinateWritingItemAtURL:options:writingItemAtURL:options:error:byAccessor:")
    func coordinateWriting(url: ObjCObject, options: UInt, writingURL: ObjCObject, writingOptions: UInt,
                           error: UnsafeMutablePointer<id?>?, accessor: ObjCObject) {
        coordinatorAccess(UInt(bitPattern: objcObject)) {
            Blocks.invoke(accessor.id, as: (@convention(c) (id, id, id) -> Void).self)(accessor.id, url.id, writingURL.id)
        }
    }
}
