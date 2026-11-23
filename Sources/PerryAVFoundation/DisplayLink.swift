import CPerryMedia
import Glibc

// CoreVideo's display links, as Mac programs pace their drawing by a
// display's refresh: SDL's OpenGL windows wait for a link's callback before
// each swap. There is no display to follow here: a link is a thread of its
// own that calls its callback 60 times a second while it runs, with the
// times of the refresh it stands for.

/// CVReturn (*CVDisplayLinkOutputCallback)(CVDisplayLinkRef, const
/// CVTimeStamp *now, const CVTimeStamp *outputTime, CVOptionFlags flagsIn,
/// CVOptionFlags *flagsOut, void *context).
public typealias CVDisplayLinkOutputCallback = @convention(c) (
    UnsafeMutableRawPointer?, UnsafePointer<CVTimeStamp>?, UnsafePointer<CVTimeStamp>?, UInt64,
    UnsafeMutablePointer<UInt64>?, UnsafeMutableRawPointer?
) -> Int32

final class DisplayLink: @unchecked Sendable {
    /// Refreshes a second, and the period's time scale.
    static let rate: Int64 = 60
    static let timeScale: Int32 = 1_000_000_000
    static var period: Int64 { Int64(timeScale) / rate }

    let lock = Lock()
    /// Held while the callback runs: stopping waits for it, as programs let
    /// go of what the callback uses right after they stop a link.
    let calling = Lock()
    var callback: CVDisplayLinkOutputCallback?
    var context: UnsafeMutableRawPointer?
    var display: UInt32 = 0
    var running = false
    /// Counts starts, so a thread a stop has ended does not carry on for
    /// the start after it.
    var generation = 0
    /// The program's references, apart from the running thread's hold on
    /// the link: the last one let go stops it.
    var references = 1

    static func link(_ pointer: UnsafeMutableRawPointer?) -> DisplayLink? {
        pointer.map { Unmanaged<DisplayLink>.fromOpaque($0).takeUnretainedValue() }
    }

    static func now() -> Int64 {
        var time = timespec()
        clock_gettime(CLOCK_MONOTONIC, &time)
        return Int64(time.tv_sec) * 1_000_000_000 + Int64(time.tv_nsec)
    }

    static func stamp(at time: Int64) -> CVTimeStamp {
        var stamp = CVTimeStamp()
        stamp.videoTimeScale = timeScale
        stamp.videoTime = time
        stamp.hostTime = UInt64(time)
        stamp.rateScalar = 1
        stamp.videoRefreshPeriod = period
        stamp.flags = 0b111                 // video time, host time and rate scalar are valid
        return stamp
    }

    func start() -> Bool {
        let generation: Int? = lock.withLock {
            guard !running else { return nil }
            running = true
            self.generation += 1
            return self.generation
        }
        guard let generation else { return false }
        Background.run { self.run(generation) }
        return true
    }

    func stop() -> Bool {
        let stopped: Bool = lock.withLock {
            guard running else { return false }
            running = false
            return true
        }
        // A recursive lock: the callback itself may stop its link.
        if stopped { calling.withLock {} }
        return stopped
    }

    private func run(_ generation: Int) {
        let reference = Unmanaged.passUnretained(self).toOpaque()
        var next = DisplayLink.now()
        while true {
            let carryOn: Bool = calling.withLock {
                let current: (CVDisplayLinkOutputCallback?, UnsafeMutableRawPointer?)? = lock.withLock {
                    running && self.generation == generation ? (callback, context) : nil
                }
                guard let current else { return false }
                if let callback = current.0 {
                    var now = DisplayLink.stamp(at: DisplayLink.now())
                    var output = DisplayLink.stamp(at: next + DisplayLink.period)
                    var flags: UInt64 = 0
                    _ = callback(reference, &now, &output, 0, &flags, current.1)
                }
                return true
            }
            guard carryOn else { return }
            next += DisplayLink.period
            let wait = next - DisplayLink.now()
            if wait > 0 {
                var time = timespec(tv_sec: Int(wait / 1_000_000_000), tv_nsec: Int(wait % 1_000_000_000))
                nanosleep(&time, nil)
            } else if wait < -DisplayLink.period * 4 {
                next = DisplayLink.now()        // far behind: start again from now
            }
        }
    }
}

private let kCVReturnSuccess: Int32 = 0
private let kCVReturnInvalidArgument: Int32 = -6661
private let kCVReturnDisplayLinkAlreadyRunning: Int32 = -6671
private let kCVReturnDisplayLinkNotRunning: Int32 = -6672

private func makeDisplayLink(_ display: UInt32, _ out: UnsafeMutablePointer<UnsafeMutableRawPointer?>?) -> Int32 {
    guard let out else { return kCVReturnInvalidArgument }
    let link = DisplayLink()
    link.display = display
    out.pointee = Unmanaged.passRetained(link).toOpaque()
    return kCVReturnSuccess
}

/// CVReturn CVDisplayLinkCreateWithActiveCGDisplays(CVDisplayLinkRef *).
@c(_CVDisplayLinkCreateWithActiveCGDisplays)
public func CVDisplayLinkCreateWithActiveCGDisplays(_ out: UnsafeMutablePointer<UnsafeMutableRawPointer?>?) -> Int32 {
    makeDisplayLink(0, out)
}

/// CVReturn CVDisplayLinkCreateWithCGDisplay(CGDirectDisplayID, CVDisplayLinkRef *).
@c(_CVDisplayLinkCreateWithCGDisplay)
public func CVDisplayLinkCreateWithCGDisplay(_ display: UInt32, _ out: UnsafeMutablePointer<UnsafeMutableRawPointer?>?) -> Int32 {
    makeDisplayLink(display, out)
}

@c(_CVDisplayLinkRetain)
public func CVDisplayLinkRetain(_ link: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer? {
    if let object = DisplayLink.link(link) { object.lock.withLock { object.references += 1 } }
    return link
}

/// The last reference let go stops a link that runs, as SDL lets its
/// OpenGL contexts' links go without stopping them.
@c(_CVDisplayLinkRelease)
public func CVDisplayLinkRelease(_ link: UnsafeMutableRawPointer?) {
    guard let link, let object = DisplayLink.link(link) else { return }
    let last: Bool = object.lock.withLock {
        object.references -= 1
        return object.references == 0
    }
    guard last else { return }
    _ = object.stop()
    Unmanaged<DisplayLink>.fromOpaque(link).release()
}

/// CVReturn CVDisplayLinkSetOutputCallback(CVDisplayLinkRef,
/// CVDisplayLinkOutputCallback, void *userInfo).
@c(_CVDisplayLinkSetOutputCallback)
public func CVDisplayLinkSetOutputCallback(_ link: UnsafeMutableRawPointer?, _ callback: CVDisplayLinkOutputCallback?,
                                           _ context: UnsafeMutableRawPointer?) -> Int32 {
    guard let link = DisplayLink.link(link) else { return kCVReturnInvalidArgument }
    link.lock.withLock {
        link.callback = callback
        link.context = context
    }
    return kCVReturnSuccess
}

@c(_CVDisplayLinkStart)
public func CVDisplayLinkStart(_ link: UnsafeMutableRawPointer?) -> Int32 {
    guard let link = DisplayLink.link(link) else { return kCVReturnInvalidArgument }
    return link.start() ? kCVReturnSuccess : kCVReturnDisplayLinkAlreadyRunning
}

@c(_CVDisplayLinkStop)
public func CVDisplayLinkStop(_ link: UnsafeMutableRawPointer?) -> Int32 {
    guard let link = DisplayLink.link(link) else { return kCVReturnInvalidArgument }
    return link.stop() ? kCVReturnSuccess : kCVReturnDisplayLinkNotRunning
}

@c(_CVDisplayLinkIsRunning)
public func CVDisplayLinkIsRunning(_ link: UnsafeMutableRawPointer?) -> UInt8 {
    guard let link = DisplayLink.link(link) else { return 0 }
    return link.lock.withLock { link.running } ? 1 : 0
}

@c(_CVDisplayLinkSetCurrentCGDisplay)
public func CVDisplayLinkSetCurrentCGDisplay(_ link: UnsafeMutableRawPointer?, _ display: UInt32) -> Int32 {
    guard let link = DisplayLink.link(link) else { return kCVReturnInvalidArgument }
    link.lock.withLock { link.display = display }
    return kCVReturnSuccess
}

/// CVReturn CVDisplayLinkSetCurrentCGDisplayFromOpenGLContext(CVDisplayLinkRef,
/// CGLContextObj, CGLPixelFormatObj): every context is on the one display.
@c(_CVDisplayLinkSetCurrentCGDisplayFromOpenGLContext)
public func CVDisplayLinkSetCurrentCGDisplayFromOpenGLContext(_ link: UnsafeMutableRawPointer?, _ context: UnsafeMutableRawPointer?,
                                                              _ format: UnsafeMutableRawPointer?) -> Int32 {
    DisplayLink.link(link) == nil ? kCVReturnInvalidArgument : kCVReturnSuccess
}

@c(_CVDisplayLinkGetCurrentCGDisplay)
public func CVDisplayLinkGetCurrentCGDisplay(_ link: UnsafeMutableRawPointer?) -> UInt32 {
    guard let link = DisplayLink.link(link) else { return 0 }
    return link.lock.withLock { link.display }
}

/// CVTime CVDisplayLinkGetNominalOutputVideoRefreshPeriod(CVDisplayLinkRef).
@c(_CVDisplayLinkGetNominalOutputVideoRefreshPeriod)
public func CVDisplayLinkGetNominalOutputVideoRefreshPeriod(_ link: UnsafeMutableRawPointer?) -> CVTime {
    guard link != nil else { return CVTime(timeValue: 0, timeScale: 0, flags: 1) }    // kCVTimeIsIndefinite
    return CVTime(timeValue: 1, timeScale: Int32(DisplayLink.rate), flags: 0)
}

/// double CVDisplayLinkGetActualOutputVideoRefreshPeriod(CVDisplayLinkRef), in seconds.
@c(_CVDisplayLinkGetActualOutputVideoRefreshPeriod)
public func CVDisplayLinkGetActualOutputVideoRefreshPeriod(_ link: UnsafeMutableRawPointer?) -> Double {
    link == nil ? 0 : 1 / Double(DisplayLink.rate)
}

/// CVTime CVDisplayLinkGetOutputVideoLatency(CVDisplayLinkRef): none.
@c(_CVDisplayLinkGetOutputVideoLatency)
public func CVDisplayLinkGetOutputVideoLatency(_ link: UnsafeMutableRawPointer?) -> CVTime {
    CVTime(timeValue: 0, timeScale: DisplayLink.timeScale, flags: 0)
}
