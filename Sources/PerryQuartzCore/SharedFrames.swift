import CPerryGeometry
import Glibc
import PerryObjCInterop

// GL frames shared with the compositor as GPU buffers, without passing
// through the CPU. UIKit copies each presented frame, on the GPU, into one
// of a few textures it has exported as dma-bufs. Each frame comes with a
// fence the GPU signals when the copy is done. The app never draws into a
// buffer in use: the one on screen, the newest finished, or the one still
// being copied into. Cacao's engine does not import the buffers yet: it
// fails them, and the app reads its frames back instead.

/// A layer's shared buffers and which holds the newest frame. UIKit
/// publishes from the thread the app presents on; the compositor reads on
/// the main thread.
final class SharedFrames: @unchecked Sendable {
    struct Buffer {
        /// The dma-buf, owned here.
        var fd: Int32
        var width, height, stride, offset: Int32
        /// The DRM format and modifier it was exported with.
        var fourcc: UInt32
        var modifier: UInt64
    }

    /// DRM_FORMAT_MOD_INVALID: exported without a modifier.
    static let noModifier: UInt64 = 0x00ff_ffff_ffff_ffff

    let buffers: [Buffer]
    private let mutex = UnsafeMutablePointer<pthread_mutex_t>.allocate(capacity: 1)
    /// The newest finished frame's buffer, and the one on screen.
    private var latest = -1
    private var showing = -1
    /// A frame the GPU is still copying, and the fence it signals when
    /// done (owned here).
    private var pending: (slot: Int, fence: Int32)?
    private var published = 0
    private var failed = false
    private(set) var opaque = false

    /// Takes `count` records of seven 64-bit values (fd, width, height,
    /// stride, offset, fourcc, modifier), duplicating each fd.
    init(records: UnsafeRawPointer, count: Int) {
        let values = records.assumingMemoryBound(to: Int64.self)
        buffers = (0..<count).map { index in
            let v = values + index * 7
            return Buffer(fd: dup(Int32(v[0])), width: Int32(v[1]), height: Int32(v[2]), stride: Int32(v[3]), offset: Int32(v[4]),
                          fourcc: UInt32(truncatingIfNeeded: v[5]), modifier: UInt64(bitPattern: v[6]))
        }
        pthread_mutex_init(mutex, nil)
    }

    deinit {
        if let pending { close(pending.fence) }
        for buffer in buffers where buffer.fd >= 0 { close(buffer.fd) }
        pthread_mutex_destroy(mutex)
        mutex.deallocate()
    }

    private func locked<Result>(_ body: () -> Result) -> Result {
        pthread_mutex_lock(mutex)
        defer { pthread_mutex_unlock(mutex) }
        return body()
    }

    /// The app's: the buffer at `slot` is getting a new frame, finished
    /// when `fence` (a sync file, taken over here) signals, or already if
    /// there is none. A frame still being copied is passed over for it.
    func publish(_ slot: Int, opaque: Bool, fence: Int32) {
        locked {
            if let old = pending { close(old.fence) }
            pending = nil
            if fence >= 0 { pending = (slot, fence) } else { latest = slot }
            published += 1
            self.opaque = opaque
        }
    }

    /// The app's: the buffers it must not draw into, as a mask of their
    /// indexes; -1 once the compositor could not import the buffers.
    var slotsInUse: Int {
        locked {
            guard !failed else { return -1 }
            var mask = 0
            for slot in [latest, showing, pending?.slot ?? -1] where slot >= 0 { mask |= 1 << slot }
            return mask
        }
    }

    /// The compositor's: the newest finished frame's buffer, now the one
    /// on screen; how many frames were published since the last; and
    /// whether a newer frame is still being copied. Waits a few
    /// milliseconds for one that nearly is. Nil before any frame.
    func take() -> (slot: Int, frames: Int, waiting: Bool)? {
        // The fence is polled on a duplicate, as the app may pass the
        // frame over, closing it, meanwhile.
        if let (slot, fence) = locked({ pending.map { ($0.slot, dup($0.fence)) } }), fence >= 0 {
            var file = pollfd(fd: fence, events: Int16(POLLIN), revents: 0)
            let finished = poll(&file, 1, 3) > 0
            close(fence)
            if finished {
                locked {
                    guard let current = pending, current.slot == slot else { return }
                    latest = slot
                    close(current.fence)
                    pending = nil
                }
            }
        }
        return locked {
            guard !failed, latest >= 0 else { return nil }
            showing = latest
            let frames = published
            published = 0
            return (latest, frames, pending != nil)
        }
    }

    /// The compositor's: the buffers can't be imported; the app reads
    /// frames back instead.
    func fail() { locked { failed = true } }

    var hasFailed: Bool { locked { failed } }
}
