import CPerryObjC
import Glibc
import PerryObjCInterop

/// The block classes, built inside libSystem's _NSConcrete*Block storage
/// so blocks can be messaged: retained, released and copied.
public enum BlockClasses {
    typealias BlockCopy = @convention(c) (UnsafeRawPointer?) -> UnsafeMutableRawPointer?
    typealias BlockRelease = @convention(c) (UnsafeRawPointer?) -> Void

    nonisolated(unsafe) static var blockCopy: BlockCopy?
    nonisolated(unsafe) static var blockRelease: BlockRelease?

    /// _Block_copy, or the block itself when libSystem has no blocks runtime.
    public static func copy(_ block: UnsafeRawPointer?) -> UnsafeMutableRawPointer? {
        blockCopy.map { $0(block) } ?? UnsafeMutableRawPointer(mutating: block)
    }

    public static func release(_ block: UnsafeRawPointer?) {
        blockRelease?(block)
    }

    /// Storage for each class: libSystem's symbol, class in words 0-15 and
    /// metaclass in words 16-31.
    public struct Storage {
        public var stack, malloc, global, auto, finalizing, weakVariable: UnsafeMutableRawPointer?
        public init(stack: UnsafeMutableRawPointer?, malloc: UnsafeMutableRawPointer?, global: UnsafeMutableRawPointer?,
                    auto: UnsafeMutableRawPointer?, finalizing: UnsafeMutableRawPointer?,
                    weakVariable: UnsafeMutableRawPointer?) {
            self.stack = stack
            self.malloc = malloc
            self.global = global
            self.auto = auto
            self.finalizing = finalizing
            self.weakVariable = weakVariable
        }
    }

    public static func install(_ storage: Storage, copy: UnsafeMutableRawPointer?, release: UnsafeMutableRawPointer?) {
        blockCopy = copy.map { unsafeBitCast($0, to: BlockCopy.self) }
        blockRelease = release.map { unsafeBitCast($0, to: BlockRelease.self) }

        let base = UnsafeMutablePointer<perry_objc_class>.allocate(capacity: 2)
        base.initialize(repeating: perry_objc_class(), count: 2)
        let block = Runtime.makeClass(base, metaclass: base + 1, superclass: RootClasses.nsObject,
                                      name: permanentCString("NSBlock"), instanceSize: 8, registerName: true)
        _ = MethodTable(block, NSBlock.registerObjCMethods)

        func make(_ name: String, _ storage: UnsafeMutableRawPointer?, _ registrations: ObjCMethodRegistration...) {
            guard let storage else { return }
            let info = Runtime.makeClass(storage.assumingMemoryBound(to: perry_objc_class.self),
                                         metaclass: (storage + 128).assumingMemoryBound(to: perry_objc_class.self),
                                         superclass: block.cls, name: permanentCString(name),
                                         instanceSize: 8, registerName: true)
            _ = MethodTable(info, registrations)
        }
        // Heap blocks are reference counted by the blocks runtime; stack and
        // global blocks are not, and copying a stack block moves it to the heap.
        make("__NSMallocBlock__", storage.malloc, HeapBlock.registerObjCMethods)
        make("__NSAutoBlock__", storage.auto, HeapBlock.registerObjCMethods)
        make("__NSFinalizingBlock__", storage.finalizing, HeapBlock.registerObjCMethods)
        make("__NSStackBlock__", storage.stack, NSObject.registerObjCCategoryImmortal)
        make("__NSGlobalBlock__", storage.global, NSObject.registerObjCCategoryImmortal)
        make("__NSBlockVariable__", storage.weakVariable, NSObject.registerObjCCategoryImmortal)
    }
}

/// Blocks, whose classes are built in libSystem's storage.
@ObjCClass("NSBlock")
class NSBlock: NSObject {
    @ObjCMethod("copy") func copyBlock() -> UnsafeMutableRawPointer? { BlockClasses.copy(objcObject) }

    @ObjCMethod("copyWithZone:")
    func copyBlock(zone: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer? { BlockClasses.copy(objcObject) }

    /// Calls a block that takes no arguments.
    @ObjCMethod("invoke")
    func invokeBlock() {
        typealias Invoke = @convention(c) (ObjectPointer) -> Void
        unsafeBitCast(objcObject.load(fromByteOffset: 16, as: UnsafeRawPointer.self), to: Invoke.self)(objcObject)
    }
}

/// Heap blocks, reference counted by the blocks runtime.
@ObjCClass("__NSMallocBlock__")
final class HeapBlock: NSBlock {
    @ObjCMethod("retain") func retainBlock() -> UnsafeMutableRawPointer? { BlockClasses.copy(objcObject) }
    @ObjCMethod("release", types: "Vv16@0:8") func releaseBlock() { BlockClasses.release(objcObject) }

    @ObjCMethod("autorelease")
    func autoreleaseBlock() -> UnsafeMutableRawPointer {
        AutoreleasePool.add(objcObject)
        return objcObject
    }

    @ObjCMethod("retainCount") func blockRetainCount() -> UInt { 1 }
}
