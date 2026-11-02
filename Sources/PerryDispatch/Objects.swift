import CPerryDispatch
import PerryObjCInterop

// Darwin's dispatch objects are Objective-C objects (OS_object and its
// subclasses), so ARC code retains and releases them with objc_retain and
// objc_release. Each Perry dispatch object is an instance with two words
// after its isa: the Linux libdispatch object it stands for, which it holds
// one reference to, and a word of state (Swift state for sources, flags
// for queue attributes). The static objects in data.c have the same layout.

public typealias Object = UnsafeMutableRawPointer

/// The work functions dispatch's _f variants take.
public typealias Function = @convention(c) (UnsafeMutableRawPointer?) -> Void

enum Objects {
    static let extraBytes = 2 * MemoryLayout<UnsafeRawPointer>.size

    /// The Linux object `object` stands for.
    @inline(__always)
    static func linux(_ object: Object?) -> Object? {
        object?.load(fromByteOffset: 8, as: Object?.self)
    }

    /// The object's state word.
    @inline(__always)
    static func word(_ object: Object?) -> UnsafeMutableRawPointer? {
        object?.load(fromByteOffset: 16, as: UnsafeMutableRawPointer?.self)
    }

    /// The object's Swift state, for the classes that keep one.
    static func state<State: AnyObject>(_ object: Object?, as type: State.Type) -> State? {
        word(object).map { Unmanaged<AnyObject>.fromOpaque($0).takeUnretainedValue() } as? State
    }

    /// A new object of `cls` (+1) taking over a reference to `linux`.
    static func make(_ cls: Object, linux: Object, state: AnyObject? = nil) -> Object {
        guard let object = Runtime.createInstance(cls, extraBytes) else { dispatchFatal("out of memory") }
        object.storeBytes(of: linux, toByteOffset: 8, as: Object?.self)
        object.storeBytes(of: state.map { Unmanaged.passRetained($0).toOpaque() }, toByteOffset: 16,
                          as: UnsafeMutableRawPointer?.self)
        return object
    }

    /// Gives a static object in data.c its class and Linux object.
    static func setUpStatic(_ object: Object, _ cls: Object, linux: Object?, flags: UInt = 0) {
        let storage = object.assumingMemoryBound(to: perry_dispatch_static_object.self)
        storage.pointee.isa = cls
        storage.pointee.linux_object = linux
        storage.pointee.state = UnsafeMutableRawPointer(bitPattern: flags)
    }

    /// From -dealloc: drops the Linux object and the state.
    static func destroy(_ object: Object, keepsState: Bool) {
        if let linux = linux(object) { linux_dispatch_release(linux) }
        if keepsState, let state = word(object) { Unmanaged<AnyObject>.fromOpaque(state).release() }
    }
}

/// The classes, looked up once.
enum Classes {
    nonisolated(unsafe) static var serialQueue: Object!
    nonisolated(unsafe) static var concurrentQueue: Object!
    nonisolated(unsafe) static var globalQueue: Object!
    nonisolated(unsafe) static var mainQueue: Object!
    nonisolated(unsafe) static var queueAttribute: Object!
    nonisolated(unsafe) static var group: Object!
    nonisolated(unsafe) static var semaphore: Object!
    nonisolated(unsafe) static var source: Object!
    nonisolated(unsafe) static var data: Object!
    nonisolated(unsafe) static var emptyData: Object!

    static func load() {
        serialQueue = OSDispatchQueueSerial.objCClass.pointer
        concurrentQueue = OSDispatchQueueConcurrent.objCClass.pointer
        globalQueue = OSDispatchQueueGlobal.objCClass.pointer
        mainQueue = OSDispatchQueueMain.objCClass.pointer
        queueAttribute = OSDispatchQueueAttr.objCClass.pointer
        group = OSDispatchGroup.objCClass.pointer
        semaphore = OSDispatchSemaphore.objCClass.pointer
        source = OSDispatchSource.objCClass.pointer
        data = OSDispatchData.objCClass.pointer
        emptyData = OSDispatchDataEmpty.objCClass.pointer
    }
}

// MARK: - Protocols

@ObjCProtocol("OS_object")
protocol OSObjectProtocol {}

@ObjCProtocol("OS_dispatch_object")
protocol OSDispatchObjectProtocol: OSObjectProtocol {}

@ObjCProtocol("OS_dispatch_queue")
protocol OSDispatchQueueProtocol: OSDispatchObjectProtocol {}

@ObjCProtocol("OS_dispatch_queue_serial")
protocol OSDispatchQueueSerialProtocol: OSDispatchQueueProtocol {}

@ObjCProtocol("OS_dispatch_queue_concurrent")
protocol OSDispatchQueueConcurrentProtocol: OSDispatchQueueProtocol {}

@ObjCProtocol("OS_dispatch_queue_global")
protocol OSDispatchQueueGlobalProtocol: OSDispatchQueueProtocol {}

@ObjCProtocol("OS_dispatch_queue_main")
protocol OSDispatchQueueMainProtocol: OSDispatchQueueSerialProtocol {}

@ObjCProtocol("OS_dispatch_queue_attr")
protocol OSDispatchQueueAttrProtocol: OSDispatchObjectProtocol {}

@ObjCProtocol("OS_dispatch_group")
protocol OSDispatchGroupProtocol: OSDispatchObjectProtocol {}

@ObjCProtocol("OS_dispatch_semaphore")
protocol OSDispatchSemaphoreProtocol: OSDispatchObjectProtocol {}

@ObjCProtocol("OS_dispatch_source")
protocol OSDispatchSourceProtocol: OSDispatchObjectProtocol {}

@ObjCProtocol("OS_dispatch_data")
protocol OSDispatchDataProtocol: OSDispatchObjectProtocol {}

// MARK: - Classes

@ObjCClass("OS_object")
open class OSObject: NSObject, OSObjectProtocol {}

@ObjCClass("OS_dispatch_object")
open class OSDispatchObject: OSObject, OSDispatchObjectProtocol {
    @ObjCMethod("dealloc")
    func dealloc() {
        Objects.destroy(objcObject, keepsState: false)
        ObjCRuntime.superDealloc(objcObject, definedOn: OSDispatchObject.objCClass.pointer)
    }
}

@ObjCClass("OS_dispatch_queue")
open class OSDispatchQueue: OSDispatchObject, OSDispatchQueueProtocol {
    /// OS_dispatch_object's -dealloc, and forgetting the Linux queue's
    /// link back; the super call skips OS_dispatch_object's.
    @ObjCMethod("dealloc")
    func deallocQueue() {
        Queues.forget(objcObject)
        Objects.destroy(objcObject, keepsState: false)
        ObjCRuntime.superDealloc(objcObject, definedOn: OSDispatchObject.objCClass.pointer)
    }
}

@ObjCClass("OS_dispatch_queue_serial")
open class OSDispatchQueueSerial: OSDispatchQueue, OSDispatchQueueSerialProtocol {}

@ObjCClass("OS_dispatch_queue_concurrent")
open class OSDispatchQueueConcurrent: OSDispatchQueue, OSDispatchQueueConcurrentProtocol {}

/// The root queues, which live as long as the process.
@ObjCClass("OS_dispatch_queue_global")
open class OSDispatchQueueGlobal: OSDispatchQueue, OSDispatchQueueGlobalProtocol {
    @ObjCMethod("retain") func retain() -> UnsafeMutableRawPointer { objcObject }
    @ObjCMethod("release", types: "Vv16@0:8") func release() {}
    @ObjCMethod("autorelease") func autorelease() -> UnsafeMutableRawPointer { objcObject }
    @ObjCMethod("retainCount") func retainCount() -> UInt { UInt.max }
}

/// The main queue, _dispatch_main_q.
@ObjCClass("OS_dispatch_queue_main")
open class OSDispatchQueueMain: OSDispatchQueueSerial, OSDispatchQueueMainProtocol {
    @ObjCMethod("retain") func retain() -> UnsafeMutableRawPointer { objcObject }
    @ObjCMethod("release", types: "Vv16@0:8") func release() {}
    @ObjCMethod("autorelease") func autorelease() -> UnsafeMutableRawPointer { objcObject }
    @ObjCMethod("retainCount") func retainCount() -> UInt { UInt.max }
}

/// Queue attributes, which, like Linux's, are never freed.
@ObjCClass("OS_dispatch_queue_attr")
open class OSDispatchQueueAttr: OSDispatchObject, OSDispatchQueueAttrProtocol {
    @ObjCMethod("retain") func retain() -> UnsafeMutableRawPointer { objcObject }
    @ObjCMethod("release", types: "Vv16@0:8") func release() {}
    @ObjCMethod("autorelease") func autorelease() -> UnsafeMutableRawPointer { objcObject }
    @ObjCMethod("retainCount") func retainCount() -> UInt { UInt.max }
}

@ObjCClass("OS_dispatch_group")
open class OSDispatchGroup: OSDispatchObject, OSDispatchGroupProtocol {}

@ObjCClass("OS_dispatch_semaphore")
open class OSDispatchSemaphore: OSDispatchObject, OSDispatchSemaphoreProtocol {}

@ObjCClass("OS_dispatch_source")
open class OSDispatchSource: OSDispatchObject, OSDispatchSourceProtocol {
    @ObjCMethod("dealloc")
    func deallocSource() {
        Objects.destroy(objcObject, keepsState: true)
        ObjCRuntime.superDealloc(objcObject, definedOn: OSDispatchObject.objCClass.pointer)
    }
}

@ObjCClass("OS_dispatch_data")
open class OSDispatchData: OSDispatchObject, OSDispatchDataProtocol {}

/// dispatch_data_empty.
@ObjCClass("OS_dispatch_data_empty")
open class OSDispatchDataEmpty: OSDispatchData {
    @ObjCMethod("retain") func retain() -> UnsafeMutableRawPointer { objcObject }
    @ObjCMethod("release", types: "Vv16@0:8") func release() {}
    @ObjCMethod("autorelease") func autorelease() -> UnsafeMutableRawPointer { objcObject }
    @ObjCMethod("retainCount") func retainCount() -> UInt { UInt.max }
}

// MARK: - Every object

@c(_dispatch_retain)
public func dispatch_retain(_ object: Object?) {
    _ = ObjCRuntime.retain(object)
}

@c(_dispatch_release)
public func dispatch_release(_ object: Object?) {
    ObjCRuntime.release(object)
}

@c(_dispatch_suspend)
public func dispatch_suspend(_ object: Object?) {
    linux_dispatch_suspend(Objects.linux(object))
}

@c(_dispatch_resume)
public func dispatch_resume(_ object: Object?) {
    linux_dispatch_resume(Objects.linux(object))
}

@c(_dispatch_activate)
public func dispatch_activate(_ object: Object?) {
    linux_dispatch_activate(Objects.linux(object))
}

/// A source's context lives in its state, as the source's own Linux
/// context leads its handlers to that state.
@c(_dispatch_set_context)
public func dispatch_set_context(_ object: Object?, _ context: UnsafeMutableRawPointer?) {
    if let source = Objects.state(object, as: SourceState.self) {
        source.context = context
    } else {
        linux_dispatch_set_context(Objects.linux(object), context)
    }
}

@c(_dispatch_get_context)
public func dispatch_get_context(_ object: Object?) -> UnsafeMutableRawPointer? {
    if let source = Objects.state(object, as: SourceState.self) { return source.context }
    return linux_dispatch_get_context(Objects.linux(object))
}

@c(_dispatch_set_finalizer_f)
public func dispatch_set_finalizer_f(_ object: Object?, _ finalizer: Function?) {
    if let source = Objects.state(object, as: SourceState.self) {
        source.finalizer = finalizer
    } else {
        linux_dispatch_set_finalizer_f(Objects.linux(object), finalizer)
    }
}

@c(_dispatch_set_target_queue)
public func dispatch_set_target_queue(_ object: Object?, _ queue: Object?) {
    linux_dispatch_set_target_queue(Objects.linux(object), Objects.linux(queue))
}
