import FoundationEssentials
import Synchronization
import PerryObjCInterop

// NSPurgeableData: mutable data whose bytes may be thrown away while no one
// uses them (NSDiscardableContent). A new one is in use once, as Darwin's
// is; each -beginContentAccess that succeeds is one use more and each
// -endContentAccess one fewer. Its bytes are read only while it is in use:
// -length, -bytes and -mutableBytes (and copying, which reads them) raise
// outside that, as on Darwin. Nothing here runs short of memory, so the
// bytes go only when -discardContentIfPossible is sent while no one uses
// them; after that no access can begin.

/// A purgeable data's uses, and whether its bytes were thrown away.
private struct PurgeableDataUse {
    var uses = 1
    var discarded = false
}

/// Each purgeable data's use, by object; none listed is a new one's.
private let purgeableDataUses = Mutex<[UInt: PurgeableDataUse]>([:])

@ObjCClass("NSPurgeableData")
public final class NSPurgeableData: NSMutableData {
    nonisolated(unsafe) static var purgeableClass: Class!

    /// Set-up after the class is defined: NSMutableData's would take this
    /// class for its own.
    override public class func didDefineObjCClass(_ cls: ObjCClass) {
        purgeableClass = cls.storage
    }

    private var key: UInt { UInt(bitPattern: objcObject) }

    private var use: PurgeableDataUse {
        let key = self.key
        return purgeableDataUses.withLock { $0[key] ?? PurgeableDataUse() }
    }

    /// Raises unless the data is in use, as Darwin's checks do.
    private func requireAccess(_ method: String) {
        guard use.uses == 0 else { return }
        Exceptions.raise(name: "NSGenericException",
                         reason: "*** -[NSPurgeableData \(method)]: <NSPurgeableData: \(objcObject)> accessed outside successful -beginContentAccess and -endContentAccess calls.")
    }

    @ObjCMethod("dealloc")
    override func dealloc() {
        let key = self.key
        purgeableDataUses.withLock { _ = $0.removeValue(forKey: key) }
        Storage.set(objcObject, nil)
        ObjC.superDealloc(objcObject, from: DataObjects.dataClass)
    }

    // MARK: NSDiscardableContent

    /// NO once the bytes are gone.
    @ObjCMethod("beginContentAccess")
    func beginContentAccess() -> Bool {
        let key = self.key
        return purgeableDataUses.withLock { uses -> Bool in
            var use = uses[key] ?? PurgeableDataUse()
            guard !use.discarded else { return false }
            use.uses += 1
            uses[key] = use
            return true
        }
    }

    @ObjCMethod("endContentAccess")
    func endContentAccess() {
        let key = self.key
        let ended = purgeableDataUses.withLock { uses -> Bool in
            var use = uses[key] ?? PurgeableDataUse()
            guard use.uses > 0 else { return false }
            use.uses -= 1
            uses[key] = use
            return true
        }
        guard ended else {
            Exceptions.raise(name: "NSGenericException",
                             reason: "*** -[NSPurgeableData endContentAccess]: called without successful matching -beginContentAccess")
        }
    }

    /// Throws the bytes away when no one uses them.
    @ObjCMethod("discardContentIfPossible")
    func discardContentIfPossible() {
        let key = self.key
        let discard = purgeableDataUses.withLock { uses -> Bool in
            var use = uses[key] ?? PurgeableDataUse()
            guard use.uses == 0, !use.discarded else { return false }
            use.discarded = true
            uses[key] = use
            return true
        }
        if discard { Storage.set(objcObject, DataStorage(copying: nil, count: 0)) }
    }

    @ObjCMethod("isContentDiscarded")
    func isContentDiscarded() -> Bool { use.discarded }

    // MARK: Guarded access

    @ObjCMethod("length")
    override func length() -> UInt {
        requireAccess("length")
        return super.length()
    }

    @ObjCMethod("bytes")
    override func bytes() -> UnsafeRawPointer? {
        requireAccess("bytes")
        return super.bytes()
    }

    @ObjCMethod("mutableBytes")
    override func mutableBytes() -> UnsafeMutableRawPointer? {
        requireAccess("mutableBytes")
        return super.mutableBytes()
    }

    /// An immutable copy of the bytes, which are read for it.
    @ObjCMethod("copyWithZone:")
    override func copy(zone: UnsafeMutableRawPointer?) -> NSData {
        requireAccess("bytes")
        return super.copy(zone: zone)
    }

    @ObjCMethod("mutableCopyWithZone:")
    override func mutableCopy(zone: UnsafeMutableRawPointer?) -> NSData {
        requireAccess("length")
        return super.mutableCopy(zone: zone)
    }
}
