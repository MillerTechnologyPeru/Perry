import CPerryDispatch
import Glibc
import PerryObjCInterop

// dispatch_data. A Darwin destructor block is never handed to Linux: the
// bytes are copied, and the block runs on its queue at once, as the buffer
// is no longer needed. DISPATCH_DATA_DESTRUCTOR_FREE and _MUNMAP map to
// Linux's own, which take over the buffer.

enum DataObjects {
    static func wrap(_ linux: Object?) -> Object? {
        guard let linux else { return nil }
        if linux == perry_linux_data_empty() {
            linux_dispatch_release(linux)
            return perry_data_empty()
        }
        return Objects.make(Classes.data, linux: linux)
    }
}

@c(_dispatch_data_create)
public func dispatch_data_create(_ buffer: UnsafeRawPointer?, _ size: Int, _ queue: Object?,
                                 _ destructor: UnsafeMutableRawPointer?) -> Object? {
    if size == 0 {
        if let destructor, destructor != UnsafeMutableRawPointer(mutating: perry_data_destructor_free()),
           destructor != UnsafeMutableRawPointer(mutating: perry_data_destructor_munmap()) {
            linux_dispatch_async_f(Objects.linux(queue) ?? linux_dispatch_get_global_queue(0, 0),
                                   Blocks.copy(destructor), Blocks.runOnce)
        }
        return perry_data_empty()
    }
    let linuxDestructor: UnsafeMutableRawPointer?
    switch destructor.map(UnsafeRawPointer.init) {
    case perry_data_destructor_free(): linuxDestructor = perry_linux_data_destructor_free()
    case perry_data_destructor_munmap(): linuxDestructor = perry_linux_data_destructor_munmap()
    default: linuxDestructor = nil
    }
    let data = DataObjects.wrap(linux_dispatch_data_create(buffer, size, Objects.linux(queue), linuxDestructor))
    if linuxDestructor == nil, let destructor {
        linux_dispatch_async_f(Objects.linux(queue) ?? linux_dispatch_get_global_queue(0, 0),
                               Blocks.copy(destructor), Blocks.runOnce)
    }
    return data
}

@c(_dispatch_data_get_size)
public func dispatch_data_get_size(_ data: Object?) -> Int {
    linux_dispatch_data_get_size(Objects.linux(data))
}

@c(_dispatch_data_create_map)
public func dispatch_data_create_map(_ data: Object?, _ buffer: UnsafeMutablePointer<UnsafeRawPointer?>?,
                                     _ size: UnsafeMutablePointer<Int>?) -> Object? {
    DataObjects.wrap(linux_dispatch_data_create_map(Objects.linux(data), buffer, size))
}

@c(_dispatch_data_create_concat)
public func dispatch_data_create_concat(_ first: Object?, _ second: Object?) -> Object? {
    DataObjects.wrap(linux_dispatch_data_create_concat(Objects.linux(first), Objects.linux(second)))
}

@c(_dispatch_data_create_subrange)
public func dispatch_data_create_subrange(_ data: Object?, _ offset: Int, _ length: Int) -> Object? {
    DataObjects.wrap(linux_dispatch_data_create_subrange(Objects.linux(data), offset, length))
}

/// The region is returned +0, as Darwin's is: it lives as long as `data`.
@c(_dispatch_data_copy_region)
public func dispatch_data_copy_region(_ data: Object?, _ location: Int, _ offset: UnsafeMutablePointer<Int>?) -> Object? {
    ObjCRuntime.autorelease(DataObjects.wrap(linux_dispatch_data_copy_region(Objects.linux(data), location, offset)))
}

/// bool (^)(dispatch_data_t region, size_t offset, const void *buffer, size_t size)
private let applyRegion: @convention(c) (UnsafeMutableRawPointer?, UnsafeMutableRawPointer?, Int, UnsafeRawPointer?,
                                         Int) -> Bool = { block, region, offset, buffer, size in
    typealias Invoke = @convention(c) (UnsafeMutableRawPointer, Object?, Int, UnsafeRawPointer?, Int) -> Bool
    guard let block else { return false }
    // Linux lends the region; the Darwin one holds its own reference.
    if let region { linux_dispatch_retain(region) }
    let darwin = DataObjects.wrap(region)
    return keepingLinuxRegisters {
        defer { ObjCRuntime.release(darwin) }
        return unsafeBitCast(block.load(fromByteOffset: DarwinLayout.blockInvoke, as: UnsafeRawPointer.self), to: Invoke.self)(
            block, darwin, offset, buffer, size)
    }
}

@c(_dispatch_data_apply)
public func dispatch_data_apply(_ data: Object?, _ block: UnsafeMutableRawPointer?) -> Bool {
    linux_dispatch_data_apply_f(Objects.linux(data), block, applyRegion)
}
