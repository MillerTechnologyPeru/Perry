import CPerryDispatch
import Glibc
import PerryObjCInterop

// dispatch_io channels, and whole reads and writes of a descriptor, on
// Linux's. Darwin's handler blocks are copied and called from the _f
// variants' functions, with the data as Darwin data objects and errors in
// Darwin's numbering.

enum IO {
    /// What a handler is called with: the copied block, released when the
    /// handler is done with.
    static func context(_ block: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer? {
        block.map(Blocks.copy)
    }

    static func darwinError(_ error: Int32) -> Int32 {
        error == 0 ? 0 : Runtime.darwinErrno?(error) ?? error
    }

    /// The data, as a Darwin object held for the handler's call.
    static func withData<T>(_ linux: Object?, _ body: (Object?) -> T) -> T {
        guard let linux else { return body(nil) }
        linux_dispatch_retain(linux)
        let data = DataObjects.wrap(linux)
        defer { if let data { ObjCRuntime.release(data) } }
        return body(data)
    }

    /// cleanup_handler(int error), called once.
    static let cleanup: linux_dispatch_io_cleanup = { context, error in
        guard let block = context else { return }
        keepingLinuxRegisters {
            ObjCRuntime.autoreleasepool {
                typealias Handler = @convention(c) (UnsafeMutableRawPointer, Int32) -> Void
                unsafeBitCast(block.load(fromByteOffset: DarwinLayout.blockInvoke, as: UnsafeRawPointer.self), to: Handler.self)(
                    block, IO.darwinError(error))
            }
            Runtime.blockRelease(block)
        }
    }

    /// io_handler(bool done, dispatch_data_t data, int error), called until done.
    static let handler: linux_dispatch_io_handler = { context, done, data, error in
        guard let block = context else { return }
        keepingLinuxRegisters {
            IO.withData(data) { data in
                ObjCRuntime.autoreleasepool {
                    typealias Handler = @convention(c) (UnsafeMutableRawPointer, Bool, Object?, Int32) -> Void
                    unsafeBitCast(block.load(fromByteOffset: DarwinLayout.blockInvoke, as: UnsafeRawPointer.self), to: Handler.self)(
                        block, done, data, IO.darwinError(error))
                }
            }
            if done { Runtime.blockRelease(block) }
        }
    }

    /// dispatch_read and dispatch_write's handler(dispatch_data_t data, int error).
    static let dataHandler: linux_dispatch_data_handler = { context, data, error in
        guard let block = context else { return }
        keepingLinuxRegisters {
            IO.withData(data) { data in
                ObjCRuntime.autoreleasepool {
                    typealias Handler = @convention(c) (UnsafeMutableRawPointer, Object?, Int32) -> Void
                    unsafeBitCast(block.load(fromByteOffset: DarwinLayout.blockInvoke, as: UnsafeRawPointer.self), to: Handler.self)(
                        block, data, IO.darwinError(error))
                }
            }
            Runtime.blockRelease(block)
        }
    }

    static func wrap(_ linux: Object?) -> Object? {
        linux.map { Objects.make(Classes.io, linux: $0) }
    }

    /// Darwin's open flags as Linux's.
    static func linuxFlags(_ flags: Int32) -> Int32 {
        var linux = flags & O_ACCMODE
        let pairs: [(Int32, Int32)] = [
            (0x4, O_NONBLOCK), (0x8, O_APPEND), (0x200, O_CREAT), (0x400, O_TRUNC), (0x800, O_EXCL),
            (0x20000, O_NOCTTY), (0x100000, O_DIRECTORY), (0x200000, O_NOFOLLOW), (0x1000000, O_CLOEXEC),
        ]
        for (darwin, value) in pairs where flags & darwin != 0 { linux |= value }
        return linux
    }
}

// MARK: - Channels

@c(_dispatch_io_create)
public func dispatch_io_create(_ type: UInt, _ fd: Int32, _ queue: Object?, _ cleanup: UnsafeMutableRawPointer?) -> Object? {
    IO.wrap(linux_dispatch_io_create_f(type, fd, Objects.linux(queue), IO.context(cleanup), IO.cleanup))
}

@c(_dispatch_io_create_with_path)
public func dispatch_io_create_with_path(_ type: UInt, _ path: UnsafePointer<CChar>?, _ flags: Int32, _ mode: UInt16,
                                         _ queue: Object?, _ cleanup: UnsafeMutableRawPointer?) -> Object? {
    IO.wrap(linux_dispatch_io_create_with_path_f(type, path, IO.linuxFlags(flags), UInt32(mode), Objects.linux(queue),
                                                 IO.context(cleanup), IO.cleanup))
}

@c(_dispatch_io_create_with_io)
public func dispatch_io_create_with_io(_ type: UInt, _ io: Object?, _ queue: Object?,
                                       _ cleanup: UnsafeMutableRawPointer?) -> Object? {
    IO.wrap(linux_dispatch_io_create_with_io_f(type, Objects.linux(io), Objects.linux(queue), IO.context(cleanup),
                                               IO.cleanup))
}

@c(_dispatch_io_read)
public func dispatch_io_read(_ channel: Object?, _ offset: Int64.ObjCType, _ length: Int, _ queue: Object?,
                             _ handler: UnsafeMutableRawPointer?) {
    linux_dispatch_io_read_f(Objects.linux(channel), Int64(objCArgument: offset), length, Objects.linux(queue), IO.context(handler), IO.handler)
}

@c(_dispatch_io_write)
public func dispatch_io_write(_ channel: Object?, _ offset: Int64.ObjCType, _ data: Object?, _ queue: Object?,
                              _ handler: UnsafeMutableRawPointer?) {
    linux_dispatch_io_write_f(Objects.linux(channel), Int64(objCArgument: offset), Objects.linux(data), Objects.linux(queue),
                              IO.context(handler), IO.handler)
}

@c(_dispatch_io_close)
public func dispatch_io_close(_ channel: Object?, _ flags: UInt) {
    linux_dispatch_io_close(Objects.linux(channel), flags)
}

@c(_dispatch_io_barrier)
public func dispatch_io_barrier(_ channel: Object?, _ barrier: UnsafeMutableRawPointer?) {
    linux_dispatch_io_barrier_f(Objects.linux(channel), Blocks.copy(barrier), Blocks.runOnce)
}

@c(_dispatch_io_barrier_f)
public func dispatch_io_barrier_f(_ channel: Object?, _ context: UnsafeMutableRawPointer?, _ work: Function?) {
    guard let work else { dispatchFatal("dispatch_io_barrier_f called with a NULL function") }
    let (call, run) = Blocks.pooled(context, work)
    linux_dispatch_io_barrier_f(Objects.linux(channel), call, run)
}

@c(_dispatch_io_get_descriptor)
public func dispatch_io_get_descriptor(_ channel: Object?) -> Int32 {
    linux_dispatch_io_get_descriptor(Objects.linux(channel))
}

@c(_dispatch_io_set_high_water)
public func dispatch_io_set_high_water(_ channel: Object?, _ highWater: Int) {
    linux_dispatch_io_set_high_water(Objects.linux(channel), highWater)
}

@c(_dispatch_io_set_low_water)
public func dispatch_io_set_low_water(_ channel: Object?, _ lowWater: Int) {
    linux_dispatch_io_set_low_water(Objects.linux(channel), lowWater)
}

@c(_dispatch_io_set_interval)
public func dispatch_io_set_interval(_ channel: Object?, _ interval: UInt64.ObjCType, _ flags: UInt) {
    linux_dispatch_io_set_interval(Objects.linux(channel), UInt64(objCArgument: interval), flags)
}

// MARK: - Whole reads and writes

@c(_dispatch_read)
public func dispatch_read(_ fd: Int32, _ length: Int, _ queue: Object?, _ handler: UnsafeMutableRawPointer?) {
    linux_dispatch_read_f(fd, length, Objects.linux(queue), IO.context(handler), IO.dataHandler)
}

@c(_dispatch_write)
public func dispatch_write(_ fd: Int32, _ data: Object?, _ queue: Object?, _ handler: UnsafeMutableRawPointer?) {
    linux_dispatch_write_f(fd, Objects.linux(data), Objects.linux(queue), IO.context(handler), IO.dataHandler)
}
