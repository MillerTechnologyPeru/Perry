import Glibc
import PerryObjCInterop

// Darwin heap blocks made from Swift closures, for the completion handlers
// CFNetwork hands delegates and the work it puts on operation queues. Each
// block captures a box holding the closure; Perry's blocks runtime copies
// and releases it like any other, and its dispose helper drops the box.

final class ClosureBox {
    let body: Any

    init(_ body: Any) {
        self.body = body
    }
}

enum Closures {
    /// Block_layout, its members at the word size: isa, flags and reserved
    /// (32-bit each), invoke, descriptor, then the box. 40 bytes on arm64,
    /// 24 on armv7.
    private static let word = MemoryLayout<UnsafeRawPointer>.size
    private static let invokeOffset = word + 8
    private static let descriptorOffset = invokeOffset + word
    private static let boxOffset = descriptorOffset + word
    private static let size = boxOffset + word

    private static let copyHelper: @convention(c) (UnsafeMutableRawPointer?, UnsafeRawPointer?) -> Void = { _, source in
        guard let source else { return }
        _ = Unmanaged<ClosureBox>.fromOpaque(source.load(fromByteOffset: boxOffset, as: UnsafeRawPointer.self)).retain()
    }

    private static let disposeHelper: @convention(c) (UnsafeRawPointer?) -> Void = { block in
        guard let block else { return }
        Unmanaged<ClosureBox>.fromOpaque(block.load(fromByteOffset: boxOffset, as: UnsafeRawPointer.self)).release()
    }

    nonisolated(unsafe) private static let descriptor: UnsafeMutableRawPointer = {
        // reserved, size, copy, dispose: a word each.
        let descriptor = UnsafeMutableRawPointer.allocate(byteCount: 4 * word, alignment: word)
        descriptor.storeBytes(of: 0, as: UInt.self)
        descriptor.storeBytes(of: UInt(size), toByteOffset: word, as: UInt.self)
        descriptor.storeBytes(of: unsafeBitCast(copyHelper, to: UnsafeRawPointer.self), toByteOffset: 2 * word, as: UnsafeRawPointer.self)
        descriptor.storeBytes(of: unsafeBitCast(disposeHelper, to: UnsafeRawPointer.self), toByteOffset: 3 * word, as: UnsafeRawPointer.self)
        return descriptor
    }()

    static func box(_ block: UnsafeMutableRawPointer?) -> ClosureBox? {
        block.map { Unmanaged<ClosureBox>.fromOpaque($0.load(fromByteOffset: boxOffset, as: UnsafeRawPointer.self)).takeUnretainedValue() }
    }

    /// A heap block (+1) whose invoke function is `invoke`.
    private static func make(_ body: Any, invoke: UnsafeRawPointer) -> UnsafeMutableRawPointer {
        // malloc, as Perry's _Block_release frees heap blocks with free().
        guard let block = malloc(size) else { networkFatal("out of memory") }
        block.storeBytes(of: BlocksRuntime.mallocBlockClass, as: UnsafeMutableRawPointer.self)
        // BLOCK_NEEDS_FREE | BLOCK_HAS_COPY_DISPOSE, one reference.
        block.storeBytes(of: Int32(1 << 24 | 1 << 25 | 2), toByteOffset: word, as: Int32.self)
        block.storeBytes(of: Int32(0), toByteOffset: word + 4, as: Int32.self)
        block.storeBytes(of: invoke, toByteOffset: invokeOffset, as: UnsafeRawPointer.self)
        block.storeBytes(of: UnsafeRawPointer(descriptor), toByteOffset: descriptorOffset, as: UnsafeRawPointer.self)
        block.storeBytes(of: UnsafeRawPointer(Unmanaged.passRetained(ClosureBox(body)).toOpaque()), toByteOffset: boxOffset,
                         as: UnsafeRawPointer.self)
        return block
    }

    private static let invokeVoid: @convention(c) (UnsafeMutableRawPointer?) -> Void = { block in
        (Closures.box(block)?.body as? () -> Void)?()
    }

    private static let invokeInteger: @convention(c) (UnsafeMutableRawPointer?, Int) -> Void = { block, value in
        (Closures.box(block)?.body as? (Int) -> Void)?(value)
    }

    private static let invokeObject: @convention(c) (UnsafeMutableRawPointer?, UnsafeMutableRawPointer?) -> Void = { block, object in
        (Closures.box(block)?.body as? (UnsafeMutableRawPointer?) -> Void)?(object)
    }

    private static let invokeIntegerObject: @convention(c) (UnsafeMutableRawPointer?, Int, UnsafeMutableRawPointer?) -> Void = {
        block, value, object in
        (Closures.box(block)?.body as? (Int, UnsafeMutableRawPointer?) -> Void)?(value, object)
    }

    /// void (^)(void)
    static func block(_ body: @escaping () -> Void) -> NSObject {
        NSObject(objCOwned: make(body, invoke: unsafeBitCast(invokeVoid, to: UnsafeRawPointer.self)))
    }

    /// void (^)(NSInteger)
    static func block(integer body: @escaping (Int) -> Void) -> NSObject {
        NSObject(objCOwned: make(body, invoke: unsafeBitCast(invokeInteger, to: UnsafeRawPointer.self)))
    }

    /// void (^)(NSInteger, id)
    static func block(integerObject body: @escaping (Int, UnsafeMutableRawPointer?) -> Void) -> NSObject {
        NSObject(objCOwned: make(body, invoke: unsafeBitCast(invokeIntegerObject, to: UnsafeRawPointer.self)))
    }

    /// void (^)(id)
    static func block(object body: @escaping (UnsafeMutableRawPointer?) -> Void) -> NSObject {
        NSObject(objCOwned: make(body, invoke: unsafeBitCast(invokeObject, to: UnsafeRawPointer.self)))
    }
}

/// Calls the program's blocks: the invoke function takes the block first.
enum Blocks {
    typealias Object = UnsafeMutableRawPointer?

    static func call(_ block: ObjCBlock, _ first: Object, _ second: Object, _ third: Object) {
        block.function(as: (@convention(c) (Object, Object, Object, Object) -> Void).self)(block.object, first, second, third)
    }
}

/// Runs work on an operation queue and waits for it, or at once when the
/// calling thread is already running that queue's work. Events reach a
/// delegate in order, and a download's file lives until its handler
/// returns, as on Darwin.
enum Hops {
    static func run(on queue: NSOperationQueue, _ body: @escaping () -> Void) {
        if let current = NSOperationQueue.current(), current.objcObject == queue.objcObject {
            body()
            return
        }
        let done = UnsafeMutablePointer<sem_t>.allocate(capacity: 1)
        sem_init(done, 0, 0)
        defer {
            sem_destroy(done)
            done.deallocate()
        }
        nonisolated(unsafe) let signal = done
        queue.addOperation(block: Closures.block {
            body()
            sem_post(signal)
        })
        while sem_wait(done) != 0 {}
    }
}
