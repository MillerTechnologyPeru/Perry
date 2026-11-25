import CPerryFoundation
import Glibc
import PerryObjCInterop

// NSPointerFunctions: the options of an NSHashTable, NSMapTable or
// NSPointerArray, and the callout functions they stand for. Darwin's
// collections copy these on the way in and out; here they keep the options,
// which say how they hold and compare their members, and a function set as
// a property is kept for the program to read back but not called by them.

/// NSPointerFunctionsOptions and the function pointers, each a C function
/// as the header declares it.
final class PointerFunctionsStorage {
    var options: UInt
    var hash: UnsafeMutableRawPointer?
    var isEqual: UnsafeMutableRawPointer?
    var size: UnsafeMutableRawPointer?
    var description: UnsafeMutableRawPointer?
    var relinquish: UnsafeMutableRawPointer?
    var acquire: UnsafeMutableRawPointer?
    var usesStrongWriteBarrier = false
    var usesWeakReadAndWriteBarriers: Bool

    /// The functions the options give, as Darwin fills them in: hashing,
    /// equality and description by personality; for strong objects retain
    /// and release (or a copy in with NSPointerFunctionsCopyIn), for malloc
    /// memory (and strong non-objects) free, nothing for opaque or weak
    /// memory. No size function.
    init(options: UInt) {
        self.options = options
        let memory = options & 0xff, personality = options & 0xff00, copyIn = options & 0x10000 != 0
        let objects = personality == 0 || personality == 0x200
        switch personality {
        case 0:
            hash = PointerFunctionDefaults.pointer(PointerFunctionDefaults.objectHash)
            isEqual = PointerFunctionDefaults.pointer(PointerFunctionDefaults.objectEqual)
            description = PointerFunctionDefaults.pointer(PointerFunctionDefaults.objectDescription)
        case 0x300:
            hash = PointerFunctionDefaults.pointer(PointerFunctionDefaults.cStringHash)
            isEqual = PointerFunctionDefaults.pointer(PointerFunctionDefaults.cStringEqual)
            description = PointerFunctionDefaults.pointer(PointerFunctionDefaults.cStringDescription)
        case 0x400:
            hash = PointerFunctionDefaults.pointer(PointerFunctionDefaults.structHash)
            isEqual = PointerFunctionDefaults.pointer(PointerFunctionDefaults.structEqual)
            description = PointerFunctionDefaults.pointer(PointerFunctionDefaults.pointerDescription)
        case 0x500:
            hash = PointerFunctionDefaults.pointer(PointerFunctionDefaults.integerHash)
            isEqual = PointerFunctionDefaults.pointer(PointerFunctionDefaults.pointerEqual)
            description = PointerFunctionDefaults.pointer(PointerFunctionDefaults.integerDescription)
        default:
            // Opaque (1 << 8) and object pointer (2 << 8): the pointer itself.
            hash = PointerFunctionDefaults.pointer(PointerFunctionDefaults.shiftedHash)
            isEqual = PointerFunctionDefaults.pointer(PointerFunctionDefaults.pointerEqual)
            description = PointerFunctionDefaults.pointer(personality == 0x200 ? PointerFunctionDefaults.objectDescription
                                                                                : PointerFunctionDefaults.pointerDescription)
        }
        if memory == 0 && objects {
            relinquish = PointerFunctionDefaults.pointer(PointerFunctionDefaults.release)
            acquire = PointerFunctionDefaults.pointer(copyIn ? PointerFunctionDefaults.copyObject : PointerFunctionDefaults.retain)
        } else if memory == 0 || memory == 3 {
            relinquish = PointerFunctionDefaults.pointer(PointerFunctionDefaults.free)
            acquire = PointerFunctionDefaults.pointer(PointerFunctionDefaults.copyBytes)
        }
        usesWeakReadAndWriteBarriers = memory == 1 || memory == 5
    }

    func copy() -> PointerFunctionsStorage {
        let copy = PointerFunctionsStorage(options: options)
        (copy.hash, copy.isEqual, copy.size, copy.description) = (hash, isEqual, size, description)
        (copy.relinquish, copy.acquire) = (relinquish, acquire)
        (copy.usesStrongWriteBarrier, copy.usesWeakReadAndWriteBarriers) = (usesStrongWriteBarrier, usesWeakReadAndWriteBarriers)
        return copy
    }
}

/// The default callout functions, as C functions the program may call.
enum PointerFunctionDefaults {
    typealias Hash = @convention(c) (UnsafeRawPointer?, UnsafeRawPointer?) -> UInt
    typealias Equal = @convention(c) (UnsafeRawPointer?, UnsafeRawPointer?, UnsafeRawPointer?) -> Bool
    typealias Describer = @convention(c) (UnsafeRawPointer?) -> UnsafeMutableRawPointer?
    typealias Relinquish = @convention(c) (UnsafeRawPointer?, UnsafeRawPointer?) -> Void
    typealias Acquire = @convention(c) (UnsafeRawPointer?, UnsafeRawPointer?, Bool) -> UnsafeMutableRawPointer?
    typealias Size = @convention(c) (UnsafeRawPointer?) -> UInt

    static func pointer<Function>(_ function: Function) -> UnsafeMutableRawPointer {
        unsafeBitCast(function, to: UnsafeMutableRawPointer.self)
    }

    /// The size the program's size function gives an item, 0 without one.
    private static func size(_ item: UnsafeRawPointer?, _ function: UnsafeRawPointer?) -> Int {
        guard let function else { return 0 }
        return Int(darwinCallable(unsafeBitCast(function, to: Size.self))(item))
    }

    private static func object(_ item: UnsafeRawPointer?) -> id? { item.map { UnsafeMutableRawPointer(mutating: $0) } }

    nonisolated(unsafe) static let objectHash: Hash = { item, _ in
        guard let object = PointerFunctionDefaults.object(item) else { return 0 }
        return ObjC.sendUInt(object, Selectors.hash)
    }

    nonisolated(unsafe) static let objectEqual: Equal = { a, b, _ in
        guard let a = PointerFunctionDefaults.object(a), let b = PointerFunctionDefaults.object(b) else { return a == b }
        return a == b || ObjC.sendBool(a, Selectors.isEqual, b)
    }

    nonisolated(unsafe) static let objectDescription: Describer = { item in
        guard let object = PointerFunctionDefaults.object(item) else { return nil }
        return ObjC.send(object, ObjC.selector("description"))
    }

    nonisolated(unsafe) static let shiftedHash: Hash = { item, _ in UInt(bitPattern: item) >> 2 }
    nonisolated(unsafe) static let integerHash: Hash = { item, _ in UInt(bitPattern: item) }
    nonisolated(unsafe) static let pointerEqual: Equal = { a, b, _ in a == b }

    nonisolated(unsafe) static let pointerDescription: Describer = { item in
        Strings.autoreleased("0x" + String(UInt(bitPattern: item), radix: 16))
    }

    nonisolated(unsafe) static let integerDescription: Describer = { item in
        Strings.autoreleased(String(Int(bitPattern: UInt(bitPattern: item))))
    }

    nonisolated(unsafe) static let cStringHash: Hash = { item, _ in
        guard let item else { return 0 }
        // FNV-1a over the bytes, in 64 bits, which a 32-bit UInt keeps
        // the low half of.
        var hash: UInt64 = 0xcbf29ce484222325
        var cursor = item.assumingMemoryBound(to: UInt8.self)
        while cursor.pointee != 0 {
            hash = (hash ^ UInt64(cursor.pointee)) &* 0x100000001b3
            cursor += 1
        }
        return UInt(truncatingIfNeeded: hash)
    }

    nonisolated(unsafe) static let cStringEqual: Equal = { a, b, _ in
        guard let a, let b else { return a == b }
        return strcmp(a.assumingMemoryBound(to: CChar.self), b.assumingMemoryBound(to: CChar.self)) == 0
    }

    nonisolated(unsafe) static let cStringDescription: Describer = { item in
        guard let item else { return nil }
        return Strings.autoreleased(String(cString: item.assumingMemoryBound(to: CChar.self)))
    }

    nonisolated(unsafe) static let structHash: Hash = { item, function in
        guard let item else { return 0 }
        var hash: UInt64 = 0xcbf29ce484222325
        let bytes = item.assumingMemoryBound(to: UInt8.self)
        for offset in 0..<PointerFunctionDefaults.size(item, function) { hash = (hash ^ UInt64(bytes[offset])) &* 0x100000001b3 }
        return UInt(truncatingIfNeeded: hash)
    }

    nonisolated(unsafe) static let structEqual: Equal = { a, b, function in
        guard let a, let b else { return a == b }
        let count = PointerFunctionDefaults.size(a, function)
        return count == PointerFunctionDefaults.size(b, function) && memcmp(a, b, count) == 0
    }

    nonisolated(unsafe) static let retain: Acquire = { item, _, _ in ObjC.retain(PointerFunctionDefaults.object(item)) }

    nonisolated(unsafe) static let copyObject: Acquire = { item, _, _ in
        guard let object = PointerFunctionDefaults.object(item) else { return nil }
        return ObjC.send(object, Selectors.copyWithZone, nil)
    }

    nonisolated(unsafe) static let release: Relinquish = { item, _ in ObjC.release(PointerFunctionDefaults.object(item)) }

    /// A copy of the item's bytes (by the size function) when asked to
    /// copy, else the item itself.
    nonisolated(unsafe) static let copyBytes: Acquire = { item, function, shouldCopy in
        guard let item else { return nil }
        guard shouldCopy else { return UnsafeMutableRawPointer(mutating: item) }
        let count = PointerFunctionDefaults.size(item, function)
        guard let copy = calloc(1, max(count, 1)) else { return nil }
        memcpy(copy, item, count)
        return copy
    }

    nonisolated(unsafe) static let free: Relinquish = { item, _ in Glibc.free(UnsafeMutableRawPointer(mutating: item)) }
}

enum PointerFunctionsObjects {
    nonisolated(unsafe) static var functionsClass: Class!

    static func storage(_ object: id?) -> PointerFunctionsStorage? { Storage.get(object, as: PointerFunctionsStorage.self) }

    /// The options an NSPointerFunctions holds; strong objects (0) for nil.
    static func options(_ object: id?) -> UInt { storage(object)?.options ?? 0 }

    /// A new NSPointerFunctions, autoreleased.
    static func make(_ storage: PointerFunctionsStorage, cls: UnsafeMutableRawPointer? = nil) -> id {
        let object = Storage.allocate(cls ?? UnsafeMutableRawPointer(functionsClass))!
        Storage.set(object, storage)
        return ObjC.autorelease(object)!
    }

    static func make(options: UInt) -> id { make(PointerFunctionsStorage(options: options)) }
}

/// NSPointerFunctions.
@ObjCClass("NSPointerFunctions")
public final class NSPointerFunctions: NSObject {
    override public class func didDefineObjCClass(_ cls: ObjCClass) {
        NSObject.registerObjCCategoryStorageAllocated(cls)
        PointerFunctionsObjects.functionsClass = cls.storage
    }

    private var state: PointerFunctionsStorage {
        if let state = PointerFunctionsObjects.storage(objcObject) { return state }
        let state = PointerFunctionsStorage(options: 0)
        Storage.set(objcObject, state)
        return state
    }

    @ObjCClassMethod("pointerFunctionsWithOptions:")
    static func make(_ cls: ObjCClass, options: UInt) -> UnsafeMutableRawPointer {
        PointerFunctionsObjects.make(PointerFunctionsStorage(options: options), cls: cls.pointer)
    }

    @ObjCMethod("initWithOptions:")
    func initialize(options: UInt) -> Self {
        Storage.set(objcObject, PointerFunctionsStorage(options: options))
        return self
    }

    @ObjCMethod("init") func initialize() -> Self { initialize(options: 0) }

    @ObjCMethod("dealloc")
    func dealloc() {
        Storage.set(objcObject, nil)
        ObjC.superDealloc(objcObject, from: PointerFunctionsObjects.functionsClass)
    }

    @ObjCMethod("copyWithZone:")
    func copy(zone: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer? {
        ObjC.retain(PointerFunctionsObjects.make(state.copy()))
    }

    @ObjCMethod("hashFunction") func hashFunction() -> UnsafeMutableRawPointer? { state.hash }
    @ObjCMethod("setHashFunction:") func setHashFunction(_ function: UnsafeMutableRawPointer?) { state.hash = function }
    @ObjCMethod("isEqualFunction") func isEqualFunction() -> UnsafeMutableRawPointer? { state.isEqual }
    @ObjCMethod("setIsEqualFunction:") func setIsEqualFunction(_ function: UnsafeMutableRawPointer?) { state.isEqual = function }
    @ObjCMethod("sizeFunction") func sizeFunction() -> UnsafeMutableRawPointer? { state.size }
    @ObjCMethod("setSizeFunction:") func setSizeFunction(_ function: UnsafeMutableRawPointer?) { state.size = function }
    @ObjCMethod("descriptionFunction") func descriptionFunction() -> UnsafeMutableRawPointer? { state.description }
    @ObjCMethod("setDescriptionFunction:") func setDescriptionFunction(_ function: UnsafeMutableRawPointer?) { state.description = function }
    @ObjCMethod("relinquishFunction") func relinquishFunction() -> UnsafeMutableRawPointer? { state.relinquish }
    @ObjCMethod("setRelinquishFunction:") func setRelinquishFunction(_ function: UnsafeMutableRawPointer?) { state.relinquish = function }
    @ObjCMethod("acquireFunction") func acquireFunction() -> UnsafeMutableRawPointer? { state.acquire }
    @ObjCMethod("setAcquireFunction:") func setAcquireFunction(_ function: UnsafeMutableRawPointer?) { state.acquire = function }

    /// Garbage collection's barriers, which mean nothing without it: kept
    /// as set. Weak memory uses the weak ones, as on Darwin.
    @ObjCMethod("usesStrongWriteBarrier") func usesStrongWriteBarrier() -> Bool { state.usesStrongWriteBarrier }
    @ObjCMethod("setUsesStrongWriteBarrier:") func setUsesStrongWriteBarrier(_ value: Bool) { state.usesStrongWriteBarrier = value }
    @ObjCMethod("usesWeakReadAndWriteBarriers") func usesWeakReadAndWriteBarriers() -> Bool { state.usesWeakReadAndWriteBarriers }
    @ObjCMethod("setUsesWeakReadAndWriteBarriers:")
    func setUsesWeakReadAndWriteBarriers(_ value: Bool) { state.usesWeakReadAndWriteBarriers = value }
}
