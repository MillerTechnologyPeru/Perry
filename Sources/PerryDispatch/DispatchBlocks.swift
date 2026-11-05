import CPerryDispatch
import Glibc
import PerryObjCInterop

// dispatch_block_create's blocks: Darwin heap blocks, which Perry's blocks
// runtime copies and releases like any other, whose invoke function runs
// the wrapped block unless it was cancelled and then marks it done. A Linux
// group, entered when the block is made and left when it first finishes,
// gives dispatch_block_wait and dispatch_block_notify.

final class DispatchBlockState {
    let body: UnsafeMutableRawPointer
    let flags: UInt
    let group: Object
    private let lock = Lock()
    private var cancelled = false
    private var finished = false

    init(body: UnsafeMutableRawPointer, flags: UInt) {
        self.body = body
        self.flags = flags
        group = linux_dispatch_group_create()!
        linux_dispatch_group_enter(group)
    }

    deinit {
        // A group released while entered is a client error to libdispatch.
        if !finished { linux_dispatch_group_leave(group) }
        linux_dispatch_release(group)
        Runtime.blockRelease(body)
    }

    var isCancelled: Bool {
        get { lock.withLock { cancelled } }
        set { lock.withLock { cancelled = newValue } }
    }

    func run() {
        if !isCancelled { Blocks.invoke(body) }
        let first = lock.withLock {
            defer { finished = true }
            return !finished
        }
        if first { linux_dispatch_group_leave(group) }
    }
}

enum DispatchBlocks {
    static let barrier: UInt = 0x1

    /// Block_layout, with the state captured after the descriptor.
    private static let size = 48

    private static let invoke: @convention(c) (UnsafeMutableRawPointer?) -> Void = { block in
        DispatchBlocks.state(block)?.run()
    }

    /// The copy helper, for a copy of a stack block (these are never on the
    /// stack), and the dispose helper, when the last reference goes.
    private static let copyHelper: @convention(c) (UnsafeMutableRawPointer?, UnsafeRawPointer?) -> Void = { _, source in
        guard let source else { return }
        let state = source.load(fromByteOffset: 32, as: UnsafeMutableRawPointer.self)
        _ = Unmanaged<DispatchBlockState>.fromOpaque(state).retain()
    }

    private static let disposeHelper: @convention(c) (UnsafeRawPointer?) -> Void = { block in
        guard let block else { return }
        Unmanaged<DispatchBlockState>.fromOpaque(block.load(fromByteOffset: 32, as: UnsafeMutableRawPointer.self))
            .release()
    }

    /// Block_descriptor with copy and dispose helpers.
    nonisolated(unsafe) private static let descriptor: UnsafeMutableRawPointer = {
        let descriptor = UnsafeMutableRawPointer.allocate(byteCount: 32, alignment: 8)
        descriptor.storeBytes(of: 0, as: UInt.self)
        descriptor.storeBytes(of: UInt(size), toByteOffset: 8, as: UInt.self)
        descriptor.storeBytes(of: unsafeBitCast(copyHelper, to: UnsafeRawPointer.self), toByteOffset: 16,
                              as: UnsafeRawPointer.self)
        descriptor.storeBytes(of: unsafeBitCast(disposeHelper, to: UnsafeRawPointer.self), toByteOffset: 24,
                              as: UnsafeRawPointer.self)
        return descriptor
    }()

    static func make(flags: UInt, body: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer {
        let state = DispatchBlockState(body: Blocks.copy(body), flags: flags)
        // malloc, as Perry's _Block_release frees heap blocks with free().
        guard let block = malloc(size) else { dispatchFatal("out of memory") }
        block.storeBytes(of: Runtime.mallocBlockClass, as: UnsafeMutableRawPointer.self)
        // BLOCK_NEEDS_FREE | BLOCK_HAS_COPY_DISPOSE, one reference.
        block.storeBytes(of: Int32(1 << 24 | 1 << 25 | 2), toByteOffset: 8, as: Int32.self)
        block.storeBytes(of: Int32(0), toByteOffset: 12, as: Int32.self)
        block.storeBytes(of: unsafeBitCast(invoke, to: UnsafeRawPointer.self), toByteOffset: 16, as: UnsafeRawPointer.self)
        block.storeBytes(of: UnsafeRawPointer(descriptor), toByteOffset: 24, as: UnsafeRawPointer.self)
        block.storeBytes(of: Unmanaged.passRetained(state).toOpaque(), toByteOffset: 32, as: UnsafeMutableRawPointer.self)
        return block
    }

    /// The state of a block dispatch_block_create made; nil for others.
    static func state(_ block: UnsafeMutableRawPointer?) -> DispatchBlockState? {
        guard let block, block.load(fromByteOffset: 16, as: UnsafeRawPointer.self)
                == unsafeBitCast(invoke, to: UnsafeRawPointer.self) else { return nil }
        return Unmanaged<DispatchBlockState>.fromOpaque(block.load(fromByteOffset: 32, as: UnsafeMutableRawPointer.self))
            .takeUnretainedValue()
    }

    static func isBarrier(_ block: UnsafeMutableRawPointer) -> Bool {
        guard let state = state(block) else { return false }
        return state.flags & barrier != 0
    }

    static func required(_ block: UnsafeMutableRawPointer?, _ function: String) -> DispatchBlockState {
        guard let state = state(block) else {
            dispatchFatal("\(function) called on a block not made by dispatch_block_create")
        }
        return state
    }
}

@c(_dispatch_block_create)
public func dispatch_block_create(_ flags: UInt, _ block: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer? {
    DispatchBlocks.make(flags: flags, body: block)
}

/// The QoS class is not kept: Linux's threads run every block alike.
@c(_dispatch_block_create_with_qos_class)
public func dispatch_block_create_with_qos_class(_ flags: UInt, _ qos: UInt32, _ priority: Int32,
                                                 _ block: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer? {
    DispatchBlocks.make(flags: flags, body: block)
}

@c(_dispatch_block_perform)
public func dispatch_block_perform(_ flags: UInt, _ block: UnsafeMutableRawPointer?) {
    guard let block else { return }
    Blocks.invoke(block)
}

@c(_dispatch_block_wait)
public func dispatch_block_wait(_ block: UnsafeMutableRawPointer?, _ timeout: UInt64.ObjCType) -> Int {
    linux_dispatch_group_wait(DispatchBlocks.required(block, "dispatch_block_wait").group,
                              DarwinTime.linux(UInt64(objCArgument: timeout)))
}

@c(_dispatch_block_notify)
public func dispatch_block_notify(_ block: UnsafeMutableRawPointer?, _ queue: Object?,
                                  _ notification: UnsafeMutableRawPointer?) {
    linux_dispatch_group_notify_f(DispatchBlocks.required(block, "dispatch_block_notify").group,
                                  Objects.linux(queue), Blocks.copy(notification), Blocks.runOnce)
}

@c(_dispatch_block_cancel)
public func dispatch_block_cancel(_ block: UnsafeMutableRawPointer?) {
    DispatchBlocks.required(block, "dispatch_block_cancel").isCancelled = true
}

@c(_dispatch_block_testcancel)
public func dispatch_block_testcancel(_ block: UnsafeMutableRawPointer?) -> Int {
    DispatchBlocks.required(block, "dispatch_block_testcancel").isCancelled ? 1 : 0
}
