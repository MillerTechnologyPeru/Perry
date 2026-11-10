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

    init(_ accessor: id) { self.accessor = ObjC.retainBlock(accessor) ?? accessor }

    deinit { ObjC.release(accessor) }
}

@ObjCClass("NSFileCoordinator")
open class NSFileCoordinator: NSObject {
    @ObjCMethod("init")
    public required override init() { super.init() }

    @ObjCMethod("initWithFilePresenter:")
    func initialize(presenter: ObjCObject?) -> Self { self }

    @ObjCClassMethod("addFilePresenter:") static func addFilePresenter(_ presenter: ObjCObject?) {}
    @ObjCClassMethod("removeFilePresenter:") static func removeFilePresenter(_ presenter: ObjCObject?) {}

    @ObjCMethod("cancel") func cancel() {}

    /// Calls the accessor with no error, later on a global queue.
    @ObjCMethod("coordinateAccessWithIntents:queue:byAccessor:")
    func coordinate(intents: ObjCObject?, queue: ObjCObject?, accessor: ObjCObject?) {
        guard let accessor, let globalQueue = Dispatch.globalQueue?(0x15, 0), let async = Dispatch.async else { return }
        let context = Unmanaged.passRetained(Access(accessor.id)).toOpaque()
        async(globalQueue, context) { context in
            guard let context else { return }
            let access = Unmanaged<Access>.fromOpaque(context).takeRetainedValue()
            Blocks.invoke(access.accessor, as: (@convention(c) (id, id?) -> Void).self)(access.accessor, nil)
        }
    }

    @ObjCMethod("coordinateReadingItemAtURL:options:error:byAccessor:")
    func coordinateReading(url: ObjCObject, options: UInt, error: UnsafeMutablePointer<id?>?, accessor: ObjCObject) {
        Blocks.invoke(accessor.id, as: (@convention(c) (id, id) -> Void).self)(accessor.id, url.id)
    }

    @ObjCMethod("coordinateWritingItemAtURL:options:error:byAccessor:")
    func coordinateWriting(url: ObjCObject, options: UInt, error: UnsafeMutablePointer<id?>?, accessor: ObjCObject) {
        Blocks.invoke(accessor.id, as: (@convention(c) (id, id) -> Void).self)(accessor.id, url.id)
    }

    @ObjCMethod("coordinateReadingItemAtURL:options:writingItemAtURL:options:error:byAccessor:")
    func coordinateReading(url: ObjCObject, options: UInt, writingURL: ObjCObject, writingOptions: UInt,
                           error: UnsafeMutablePointer<id?>?, accessor: ObjCObject) {
        Blocks.invoke(accessor.id, as: (@convention(c) (id, id, id) -> Void).self)(accessor.id, url.id, writingURL.id)
    }

    @ObjCMethod("coordinateWritingItemAtURL:options:writingItemAtURL:options:error:byAccessor:")
    func coordinateWriting(url: ObjCObject, options: UInt, writingURL: ObjCObject, writingOptions: UInt,
                           error: UnsafeMutablePointer<id?>?, accessor: ObjCObject) {
        Blocks.invoke(accessor.id, as: (@convention(c) (id, id, id) -> Void).self)(accessor.id, url.id, writingURL.id)
    }
}
