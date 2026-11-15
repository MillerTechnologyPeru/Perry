import Glibc

/// PERRY_OBJC_PROFILE=<seconds> counts the messages sent
/// by class and selector, and prints the most frequent every <seconds>.
enum Profile {
    static let interval: Int = getenv("PERRY_OBJC_PROFILE").flatMap { Int(String(cString: $0)) } ?? 0
    static let enabled = interval > 0
    private static let lock = RecursiveLock()
    nonisolated(unsafe) private static var counts: [Key: Int] = [:]
    nonisolated(unsafe) private static var started = false
    nonisolated(unsafe) private static var mainThread: pthread_t?

    struct Key: Hashable { let cls: UInt; let selector: UInt }

    static func record(_ info: ClassInfo, _ selector: SEL) {
        lock.lock()
        defer { lock.unlock() }
        if !started {
            started = true
            mainThread = pthread_self()
            var thread = pthread_t()
            pthread_create(&thread, nil, { _ in
                while true {
                    sleep(UInt32(Profile.interval))
                    Profile.report()
                }
            }, nil)
            pthread_detach(thread)
        }
        counts[Key(cls: UInt(bitPattern: info.name), selector: UInt(bitPattern: selector)), default: 0] += 1
    }

    nonisolated(unsafe) private static var declined: Set<Key> = []

    /// A -respondsToSelector: that answered no, printed once for each class and selector.
    static func noteDeclined(_ info: ClassInfo, _ selector: SEL) {
        lock.lock()
        let isNew = declined.insert(Key(cls: UInt(bitPattern: info.name), selector: UInt(bitPattern: selector))).inserted
        lock.unlock()
        guard isNew else { return }
        let text = "perry: objc: [\(String(cString: info.name)) respondsToSelector: \(String(cString: selector))] is no\n"
        _ = text.withCString { Glibc.write(2, $0, strlen($0)) }
    }

    static func report() {
        lock.lock()
        let top = counts.sorted { $0.value > $1.value }.prefix(600)
        counts = [:]
        lock.unlock()
        var text = "perry: objc profile:\n"
        for (key, count) in top {
            let cls = UnsafePointer<CChar>(bitPattern: key.cls).map { String(cString: $0) } ?? "?"
            let selector = UnsafePointer<CChar>(bitPattern: key.selector).map { String(cString: $0) } ?? "?"
            text += "  \(count) [\(cls) \(selector)]\n"
        }
        _ = text.withCString { Glibc.write(2, $0, strlen($0)) }
    }
}
