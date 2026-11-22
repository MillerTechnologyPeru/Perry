import CacaoRender
import Glibc
import Synchronization

// GL frames shared with the compositor as GPU buffers, without passing
// through the CPU. UIKit copies each presented frame, on the GPU, into one
// of a few textures it has exported as dma-bufs. Each frame comes with a
// fence the GPU signals when the copy is done. The app never draws into a
// buffer in use: the one on screen, the newest finished, or the one still
// being copied into. The buffers are a Cacao external surface's, which
// Cacao's engine imports once each and draws the newest finished of; where
// it can't import them, the app reads its frames back instead.

/// A layer's shared buffers, as the external surface they are published
/// to. UIKit publishes from the thread the app presents on; the compositor
/// takes frames on the main thread.
final class SharedFrames: Sendable {
    let surface: ExternalSurface
    /// Frames published since the compositor last counted them.
    private let published = Mutex(0)

    /// Takes `count` records of seven 64-bit values (fd, width, height,
    /// stride, offset, fourcc, modifier); the surface duplicates each fd.
    init(records: UnsafeRawPointer, count: Int) {
        let values = records.assumingMemoryBound(to: Int64.self)
        let buffers = (0..<count).map { index in
            let v = values + index * 7
            return ExternalSurface.Buffer(fileDescriptor: Int32(v[0]), width: Int32(v[1]), height: Int32(v[2]), stride: Int32(v[3]),
                                          offset: Int32(v[4]), fourCC: UInt32(truncatingIfNeeded: v[5]), modifier: UInt64(bitPattern: v[6]))
        }
        // GL's rows are bottom first.
        surface = ExternalSurface(buffers: buffers, rowOrder: .bottomFirst)
    }

    /// The app's: the buffer at `slot` is getting a new frame, finished
    /// when `fence` (a sync file, taken over here) signals, or already if
    /// there is none. A frame still being copied is passed over for it.
    func publish(_ slot: Int, opaque: Bool, fence: Int32) {
        surface.publish(buffer: slot, isOpaque: opaque, fence: fence)
        published.withLock { $0 += 1 }
    }

    /// The compositor's, for the frame rate: the frames published since
    /// it last asked.
    func takePublished() -> Int {
        published.withLock { count in
            defer { count = 0 }
            return count
        }
    }

    /// The app's: the buffers it must not draw into, as a mask of their
    /// indexes; -1 once the compositor could not import the buffers.
    var slotsInUse: Int { surface.buffersInUse ?? -1 }

    /// Whether the compositor could not import the buffers.
    var hasFailed: Bool { !surface.usesBuffers }
}
