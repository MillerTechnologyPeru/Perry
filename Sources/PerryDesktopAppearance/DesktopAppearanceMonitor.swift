public import CacaoDBus
import Glibc

/// The settings portal's appearance for code that can't wait on a task:
/// AppKit, whose colors are asked for on the main thread as it draws.
///
/// `start` connects and reads in the background at once; `current` waits,
/// for at most the time it's given, for that first read, and from then on
/// answers at once with the latest the portal said. Each change is handed
/// to the monitor's handler, and so is a first read that came after
/// `current` stopped waiting for it, as the change from what was shown.
public final class DesktopAppearanceMonitor: @unchecked Sendable {

    // Allocated, as a lock must stay at one address.
    private let mutex = UnsafeMutablePointer<pthread_mutex_t>.allocate(capacity: 1)
    private let condition = UnsafeMutablePointer<pthread_cond_t>.allocate(capacity: 1)
    /// Whether the first read finished: an answer, or no bus.
    private var finished = false
    /// Whether `current` stopped waiting for the first read.
    private var waitedOut = false
    /// Whether a change came in before the first read was kept.
    private var changed = false
    private var latest: PortalAppearance?
    private var observer: PortalAppearanceObserver?
    private let onChange: @Sendable (PortalAppearance) -> Void

    private init(onChange: @escaping @Sendable (PortalAppearance) -> Void) {
        self.onChange = onChange
        pthread_mutex_init(mutex, nil)
        pthread_cond_init(condition, nil)
    }

    /// Starts reading the appearance from the session bus, or the bus at
    /// `address`, and hearing its changes. `onChange` runs on a task of its
    /// own, not the caller's thread.
    public static func start(address: String? = nil, timeout: Duration = .seconds(2),
                             onChange: @escaping @Sendable (PortalAppearance) -> Void) -> DesktopAppearanceMonitor {
        let monitor = DesktopAppearanceMonitor(onChange: onChange)
        Task.detached {
            let started = await PortalAppearanceObserver.start(address: address, timeout: timeout) { [weak monitor] appearance in
                monitor?.heard(appearance)
            }
            monitor.read(started)
        }
        return monitor
    }

    /// The portal's appearance, waiting up to `seconds` for the first read
    /// if it hasn't finished. `nil` when there's no bus, or no answer yet.
    public func current(waitingAtMost seconds: Double) -> PortalAppearance? {
        pthread_mutex_lock(mutex)
        defer { pthread_mutex_unlock(mutex) }
        if !finished && !waitedOut {
            var deadline = timespec()
            clock_gettime(CLOCK_REALTIME, &deadline)
            // In 64 bits: a second's nanoseconds don't fit the Int of a
            // 32-bit program, which trapped here as it launched.
            let nanoseconds = Int64(deadline.tv_nsec) + Int64(seconds * 1_000_000_000)
            deadline.tv_sec += Int(nanoseconds / 1_000_000_000)
            deadline.tv_nsec = Int(nanoseconds % 1_000_000_000)
            while !finished, pthread_cond_timedwait(condition, mutex, &deadline) != ETIMEDOUT {}
            if !finished { waitedOut = true }
        }
        return latest
    }

    /// Whether the first read has finished.
    public var isReady: Bool {
        pthread_mutex_lock(mutex)
        defer { pthread_mutex_unlock(mutex) }
        return finished
    }

    /// Stops hearing changes.
    public func stop() async {
        pthread_mutex_lock(mutex)
        let observer = self.observer
        self.observer = nil
        pthread_mutex_unlock(mutex)
        await observer?.stop()
    }

    private func heard(_ appearance: PortalAppearance) {
        pthread_mutex_lock(mutex)
        latest = appearance
        changed = true
        pthread_mutex_unlock(mutex)
        onChange(appearance)
    }

    private func read(_ started: (observer: PortalAppearanceObserver, appearance: PortalAppearance)?) {
        pthread_mutex_lock(mutex)
        observer = started?.observer
        // A change heard meanwhile is newer than the first read.
        if !changed { latest = started?.appearance }
        let late = waitedOut && !changed ? started?.appearance : nil
        finished = true
        pthread_cond_broadcast(condition)
        pthread_mutex_unlock(mutex)
        if let late { onChange(late) }
    }

    deinit {
        pthread_cond_destroy(condition)
        pthread_mutex_destroy(mutex)
        condition.deallocate()
        mutex.deallocate()
    }
}
