import CPerryFoundation
import Glibc
import PerryObjCInterop

// CFAllocator. The predefined allocators are static objects in data.c;
// kCFAllocatorNull allocates nothing, the others use malloc. Allocators
// CFAllocatorCreate makes are objects of __NSCFAllocator that call their
// context's functions.

/// CFAllocatorContext: { version, info, retain, release, copyDescription,
/// allocate, reallocate, deallocate, preferredSize }, which the C functions
/// take as a raw pointer.
struct AllocatorContext {
    typealias Allocate = @convention(c) (Int, UInt, UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer?
    typealias Reallocate = @convention(c) (UnsafeMutableRawPointer?, Int, UInt, UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer?
    typealias Deallocate = @convention(c) (UnsafeMutableRawPointer?, UnsafeMutableRawPointer?) -> Void
    typealias Retain = @convention(c) (UnsafeRawPointer?) -> UnsafeRawPointer?
    typealias Release = @convention(c) (UnsafeRawPointer?) -> Void

    var version: Int
    var info: UnsafeMutableRawPointer?
    var retain: Retain?
    var release: Release?
    var copyDescription: UnsafeRawPointer?
    var allocate: Allocate?
    var reallocate: Reallocate?
    var deallocate: Deallocate?
    var preferredSize: UnsafeRawPointer?
}

final class AllocatorStorage {
    let context: AllocatorContext

    init(_ context: AllocatorContext) {
        self.context = context
    }

    deinit {
        context.release?(context.info)
    }
}

enum Allocators {
    nonisolated(unsafe) static var allocatorClass: Class!
    nonisolated(unsafe) static var defaultAllocator: UnsafeMutableRawPointer?

    static var systemDefault: UnsafeMutableRawPointer { UnsafeMutableRawPointer(mutating: perry_foundation_cf_allocator(0)) }
    static var null: UnsafeMutableRawPointer { UnsafeMutableRawPointer(mutating: perry_foundation_cf_allocator(3)) }

    /// The allocator an argument means: NULL is the default.
    static func resolved(_ allocator: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer {
        allocator ?? defaultAllocator ?? systemDefault
    }

    static func context(_ allocator: UnsafeMutableRawPointer) -> AllocatorContext? {
        Storage.get(allocator, as: AllocatorStorage.self)?.context
    }
}

@ObjCClass("__NSCFAllocator")
final class NSCFAllocator: NSObject {
    override class func didDefineObjCClass(_ cls: ObjCClass) {
        NSObject.registerObjCCategoryStorageAllocated(cls)
        Allocators.allocatorClass = cls.storage
    }

    @ObjCMethod("dealloc")
    func dealloc() {
        Storage.set(objcObject, nil)
        ObjC.superDealloc(objcObject, from: Allocators.allocatorClass)
    }
}

@c(_CFAllocatorGetDefault)
public func CFAllocatorGetDefault() -> UnsafeMutableRawPointer? { Allocators.resolved(nil) }

@c(_CFAllocatorSetDefault)
public func CFAllocatorSetDefault(_ allocator: UnsafeMutableRawPointer?) {
    guard let allocator else { return }
    _ = ObjC.retain(allocator)
    Allocators.defaultAllocator = allocator
}

@c(_CFAllocatorCreate)
public func CFAllocatorCreate(_ allocator: UnsafeMutableRawPointer?, _ context: UnsafeRawPointer?) -> UnsafeMutableRawPointer? {
    guard var copied = context?.load(as: AllocatorContext.self), let object = Storage.allocate(UnsafeMutableRawPointer(Allocators.allocatorClass)) else {
        return nil
    }
    if let retain = copied.retain {
        copied.info = UnsafeMutableRawPointer(mutating: retain(copied.info))
    }
    Storage.set(object, AllocatorStorage(copied))
    return object
}

@c(_CFAllocatorGetContext)
public func CFAllocatorGetContext(_ allocator: UnsafeMutableRawPointer?, _ context: UnsafeMutableRawPointer?) {
    let resolved = Allocators.resolved(allocator)
    context?.storeBytes(of: Allocators.context(resolved)
        ?? AllocatorContext(version: 0, info: nil, retain: nil, release: nil, copyDescription: nil, allocate: nil,
                            reallocate: nil, deallocate: nil, preferredSize: nil), as: AllocatorContext.self)
}

@c(_CFAllocatorAllocate)
public func CFAllocatorAllocate(_ allocator: UnsafeMutableRawPointer?, _ size: Int, _ hint: UInt) -> UnsafeMutableRawPointer? {
    let resolved = Allocators.resolved(allocator)
    guard size > 0, resolved != Allocators.null else { return nil }
    if let context = Allocators.context(resolved) {
        return context.allocate?(size, hint, context.info)
    }
    return malloc(size)
}

@c(_CFAllocatorReallocate)
public func CFAllocatorReallocate(_ allocator: UnsafeMutableRawPointer?, _ pointer: UnsafeMutableRawPointer?, _ size: Int,
                                  _ hint: UInt) -> UnsafeMutableRawPointer? {
    guard let pointer else { return CFAllocatorAllocate(allocator, size, hint) }
    guard size > 0 else {
        CFAllocatorDeallocate(allocator, pointer)
        return nil
    }
    let resolved = Allocators.resolved(allocator)
    guard resolved != Allocators.null else { return nil }
    if let context = Allocators.context(resolved) {
        return context.reallocate?(pointer, size, hint, context.info)
    }
    return realloc(pointer, size)
}

@c(_CFAllocatorDeallocate)
public func CFAllocatorDeallocate(_ allocator: UnsafeMutableRawPointer?, _ pointer: UnsafeMutableRawPointer?) {
    let resolved = Allocators.resolved(allocator)
    guard let pointer, resolved != Allocators.null else { return }
    if let context = Allocators.context(resolved) {
        context.deallocate?(pointer, context.info)
        return
    }
    free(pointer)
}

@c(_CFAllocatorGetPreferredSizeForSize)
public func CFAllocatorGetPreferredSizeForSize(_ allocator: UnsafeMutableRawPointer?, _ size: Int, _ hint: UInt) -> Int { size }
