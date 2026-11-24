public import CacaoDBusMenu
import DBus
import Glibc

/// Serves a Mac app's main menu to the desktop's menu bar, for AppKit,
/// whose menus are read and chosen on its main thread.
///
/// `start` connects to the session bus in the background, puts the menu
/// the app publishes at `/MenuBar` and owns the bus name made from the
/// app's `app_id`, as `AppMenuDiscovery` names it, so a menu bar that knows
/// only the focused window's `app_id` finds it. Before a menu opens, the
/// bar's `AboutToShow` hands the menu's identifier to `validate`, so the app
/// can validate its items and publish the menu again, and the bar is
/// answered once what the app published is served; a click is handed to
/// `onClick`. A menu bar shows that it is there by owning
/// `com.canonical.AppMenu.Registrar`: `onPresence` hears when that changes.
///
/// Nothing here is needed: with no session bus the menu is not served, and
/// `menuBarIsPresent` says no menu bar is there.
public final class DesktopMenuService: @unchecked Sendable {
    /// Validates the items of the submenu with an identifier, as before it
    /// opens in the app, and publishes the menu if that changed it.
    public typealias Validator = @Sendable (_ id: Int32) async -> Void

    /// Where the menu is served: the connection's unique name and the path,
    /// as the appmenu protocol ties windows to it.
    public struct Address: Hashable, Sendable {
        public var service: String
        public var path: String
    }

    private let lock = Lock()
    /// Whether the first look at the menu bar's presence finished: an
    /// answer, or no bus.
    private var presenceRead = false
    private var present = false
    private var servedAddress: Address?
    private var connection: DBusConnection?
    private var exporter: DBusMenuExporter?
    private var following: Task<Void, Never>?
    private var stopped = false
    private let publisher = Publisher()

    private let validate: Validator
    private let onClick: @Sendable (Int32) -> Void
    private let onPresence: @Sendable (Bool) -> Void
    private let onServed: @Sendable (Address) -> Void

    private init(validate: @escaping Validator, onClick: @escaping @Sendable (Int32) -> Void,
                 onPresence: @escaping @Sendable (Bool) -> Void, onServed: @escaping @Sendable (Address) -> Void) {
        self.validate = validate
        self.onClick = onClick
        self.onPresence = onPresence
        self.onServed = onServed
    }

    /// Starts serving the menu on the session bus, or the bus at `address`.
    /// The handlers run on tasks of their own, not the caller's thread:
    /// `onServed` once the menu is on the bus, `onPresence` with the first
    /// look at whether a menu bar is there and each time that changes.
    public static func start(appID: String?, address: String? = nil, validate: @escaping Validator,
                             onClick: @escaping @Sendable (Int32) -> Void,
                             onPresence: @escaping @Sendable (Bool) -> Void = { _ in },
                             onServed: @escaping @Sendable (Address) -> Void = { _ in }) -> DesktopMenuService {
        let service = DesktopMenuService(validate: validate, onClick: onClick, onPresence: onPresence, onServed: onServed)
        Task.detached { await service.run(appID: appID, address: address) }
        return service
    }

    /// Whether a menu bar shows apps' menus, waiting up to `seconds` for
    /// the first look if it hasn't finished. False with no bus, or while
    /// the menu isn't served.
    public func menuBarIsPresent(waitingAtMost seconds: Double) -> Bool {
        lock.locked {
            lock.wait(seconds: seconds) { presenceRead }
            return present
        }
    }

    /// Where the menu is served, once it is.
    public var address: Address? {
        locked { servedAddress }
    }

    /// Serves a newer menu: the bar hears what changed. Menus are served in
    /// the order they are published; the latest one published before the
    /// menu is on the bus is served once it is.
    public func publish(_ menu: DBusMenuItem) {
        publisher.publish(menu)
    }

    /// Takes the menu off the bus and closes the connection, waiting up to
    /// `seconds` so replies already sent, such as the one to a Quit item's
    /// click, leave before the app does.
    public func stop(waitingAtMost seconds: Double = 1) {
        let (connection, exporter, following) = locked { () -> (DBusConnection?, DBusMenuExporter?, Task<Void, Never>?) in
            stopped = true
            defer { self.connection = nil; self.exporter = nil; self.following = nil; servedAddress = nil }
            return (self.connection, self.exporter, self.following)
        }
        following?.cancel()
        publisher.close()
        guard let connection else { return }
        let done = Semaphore()
        Task.detached {
            await exporter?.unexport()
            // Answered after the messages sent before it are written.
            _ = try? await connection.getBusID()
            await connection.close()
            done.signal()
        }
        done.wait(seconds: seconds)
    }

    // MARK: Serving

    private func run(appID: String?, address: String?) async {
        let connection: DBusConnection
        do {
            if let address {
                connection = try await DBusConnection.connect(to: address)
            } else {
                connection = try await DBusConnection.connect(to: .session)
            }
        } catch {
            readPresence(false)
            return
        }
        // Empty until the app's latest menu is served, below: asking the app
        // for one here would wait on its main thread, which may be waiting
        // for the first look at the menu bar.
        let exporter = DBusMenuExporter(connection: connection, menu: .root([])) { [weak self] event in
            guard event.kind == .clicked else { return }
            self?.onClick(event.id)
        } onAboutToShow: { [weak self] id in
            await self?.refresh(validating: id)
        }
        await exporter.export()
        let unique = await connection.uniqueName
        let served = unique.map { Address(service: $0.rawValue, path: AppMenuDiscovery.path.rawValue) }
        let keep = locked { () -> Bool in
            guard !stopped else { return false }
            self.connection = connection
            self.exporter = exporter
            servedAddress = served
            return true
        }
        guard keep else {
            await exporter.unexport()
            await connection.close()
            readPresence(false)
            return
        }
        publisher.attach(exporter)
        // Whether a menu bar is there first, which a window waits for to
        // decide whether to show its own; then the name it finds the menu by.
        let presence = try? await AppMenuDiscovery.menuBarPresence(on: connection)
        if presence == nil { readPresence(false) }
        let task = presence.map { presence in
            Task { [weak self] in
                for await isPresent in presence {
                    guard let self else { return }
                    self.readPresence(isPresent)
                    self.onPresence(isPresent)
                }
            }
        }
        locked { following = task }
        if let appID, !appID.isEmpty {
            _ = try? await AppMenuDiscovery.claimName(forAppID: appID, on: connection)
        }
        if let served { onServed(served) }
    }

    /// Records the menu bar's presence.
    private func readPresence(_ isPresent: Bool) {
        locked {
            present = isPresent
            presenceRead = true
            lock.broadcast()
        }
    }

    /// The bar is about to open a submenu: the app validates its items,
    /// and the bar is answered once what it then publishes is served.
    private func refresh(validating id: Int32) async {
        await validate(id)
        await publisher.waitUntilServed()
    }

    private func locked<T>(_ body: () -> T) -> T { lock.locked(body) }

    deinit { following?.cancel() }
}

public extension DesktopMenuService {
    /// Runs `body` where `schedule` puts it, such as an app's main queue,
    /// and waits up to `seconds` for its result: nil if it didn't come in
    /// time, as when that thread is busy in a modal loop.
    static func result<T: Sendable>(within seconds: Double, scheduling schedule: (@escaping @Sendable () -> Void) -> Void,
                                    _ body: @escaping @Sendable () -> T) async -> T? {
        let once = Once<T?>()
        return await withCheckedContinuation { continuation in
            once.set(continuation)
            schedule { once.resume(body()) }
            Task {
                try? await Task.sleep(for: .seconds(seconds))
                once.resume(nil)
            }
        }
    }
}

/// Resumes a continuation once, with the first value given.
private final class Once<T: Sendable>: @unchecked Sendable {
    private let lock = Lock()
    private var continuation: CheckedContinuation<T, Never>?
    private var done = false

    func set(_ continuation: CheckedContinuation<T, Never>) {
        lock.locked { self.continuation = continuation }
    }

    func resume(_ value: T) {
        let continuation = lock.locked { () -> CheckedContinuation<T, Never>? in
            guard !done else { return nil }
            done = true
            defer { self.continuation = nil }
            return self.continuation
        }
        continuation?.resume(returning: value)
    }
}

/// Puts menus on the bus in the order they were published, one at a time.
private final class Publisher: @unchecked Sendable {
    private let lock = Lock()
    private var issued = 0
    private var served = 0
    private var closed = false
    /// The latest menu published before there was an exporter to serve it.
    private var pending: (menu: DBusMenuItem, ticket: Int)?
    private var queue: AsyncStream<(DBusMenuItem, Int)>.Continuation?
    private var consumer: Task<Void, Never>?
    private var waiters: [(ticket: Int, continuation: CheckedContinuation<Void, Never>)] = []

    func publish(_ menu: DBusMenuItem) {
        lock.locked {
            guard !closed else { return }
            issued += 1
            if let queue {
                queue.yield((menu, issued))
            } else {
                pending = (menu, issued)
            }
        }
    }

    /// Serves menus with `exporter` from now on, the pending one first.
    func attach(_ exporter: DBusMenuExporter) {
        let (stream, continuation) = AsyncStream<(DBusMenuItem, Int)>.makeStream()
        let consumer = Task { [weak self] in
            for await (menu, ticket) in stream {
                await exporter.update(menu)
                self?.finished(ticket)
            }
        }
        lock.locked {
            guard !closed else { return }
            queue = continuation
            self.consumer = consumer
            if let pending { continuation.yield(pending) }
            pending = nil
        }
    }

    /// Waits until every menu published so far is served.
    func waitUntilServed() async {
        await withCheckedContinuation { continuation in
            let ready = lock.locked { () -> Bool in
                guard !closed, queue != nil, served < issued else { return true }
                waiters.append((issued, continuation))
                return false
            }
            if ready { continuation.resume() }
        }
    }

    func close() {
        let waiting = lock.locked { () -> [CheckedContinuation<Void, Never>] in
            closed = true
            queue?.finish()
            consumer?.cancel()
            defer { waiters = [] }
            return waiters.map(\.continuation)
        }
        waiting.forEach { $0.resume() }
    }

    private func finished(_ ticket: Int) {
        let ready = lock.locked { () -> [CheckedContinuation<Void, Never>] in
            served = ticket
            let ready = waiters.filter { $0.ticket <= ticket }.map(\.continuation)
            waiters.removeAll { $0.ticket <= ticket }
            return ready
        }
        ready.forEach { $0.resume() }
    }
}

/// A semaphore with a bounded wait, for a synchronous caller.
private final class Semaphore: @unchecked Sendable {
    private let lock = Lock()
    private var signaled = false

    func signal() {
        lock.locked {
            signaled = true
            lock.broadcast()
        }
    }

    func wait(seconds: Double) {
        lock.locked {
            lock.wait(seconds: seconds) { signaled }
        }
    }
}

/// A mutex with a condition, allocated, as a lock must stay at one address.
final class Lock: @unchecked Sendable {
    private let mutex = UnsafeMutablePointer<pthread_mutex_t>.allocate(capacity: 1)
    private let condition = UnsafeMutablePointer<pthread_cond_t>.allocate(capacity: 1)

    init() {
        pthread_mutex_init(mutex, nil)
        pthread_cond_init(condition, nil)
    }

    deinit {
        pthread_cond_destroy(condition)
        pthread_mutex_destroy(mutex)
        condition.deallocate()
        mutex.deallocate()
    }

    func locked<T>(_ body: () throws -> T) rethrows -> T {
        pthread_mutex_lock(mutex)
        defer { pthread_mutex_unlock(mutex) }
        return try body()
    }

    /// Wakes the waiters; with the lock held.
    func broadcast() { pthread_cond_broadcast(condition) }

    /// Waits, with the lock held, until `done` or `seconds` have passed.
    func wait(seconds: Double, until done: () -> Bool) {
        var deadline = timespec()
        clock_gettime(CLOCK_REALTIME, &deadline)
        // In 64 bits: a second's nanoseconds don't fit a 32-bit Int.
        let nanoseconds = Int64(deadline.tv_nsec) + Int64(seconds * 1_000_000_000)
        deadline.tv_sec += Int(nanoseconds / 1_000_000_000)
        deadline.tv_nsec = Int(nanoseconds % 1_000_000_000)
        while !done(), pthread_cond_timedwait(condition, mutex, &deadline) != ETIMEDOUT {}
    }
}
