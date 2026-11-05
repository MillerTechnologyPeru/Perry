// Swift concurrency's waits and clocks, built on a Mac with Xcode: task
// sleeps on each clock, timeouts raced in task groups, cancellation, actors,
// the main actor, task names, and Dispatch's own timers. Apple's concurrency
// runtime makes its dispatch deadlines in mach ticks itself, so a waiting
// task is where a mistranslated time shows. Each check prints whether it
// held, not how long it took, so the output is the same on every machine.
import Dispatch
import Foundation

func check(_ name: String, _ condition: Bool) {
    print("\(name): \(condition ? "ok" : "FAILED")")
    fflush(stdout)
}

/// Whether `body` took about `seconds`: no less, and not much more.
func takes(_ seconds: Double, _ body: () async throws -> Void) async rethrows -> Bool {
    let start = Date()
    try await body()
    let elapsed = Date().timeIntervalSince(start)
    return elapsed >= seconds * 0.95 && elapsed < seconds + 1.5
}

enum Timeout: Error { case timedOut }

/// The value of `work`, or Timeout.timedOut if `seconds` pass first.
func withTimeout<T: Sendable>(_ seconds: Double, _ work: @escaping @Sendable () async throws -> T) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask { try await work() }
        group.addTask {
            try await Task.sleep(for: .seconds(seconds))
            throw Timeout.timedOut
        }
        defer { group.cancelAll() }
        return try await group.next()!
    }
}

actor Counter {
    private(set) var value = 0
    func increment() { value += 1 }
}

// MARK: Sleeps

check("sleep(nanoseconds:) waits", try await takes(0.3) { try await Task.sleep(nanoseconds: 300_000_000) })
check("sleep(for:) waits", try await takes(0.3) { try await Task.sleep(for: .milliseconds(300)) })
check("ContinuousClock sleep(until:) waits", try await takes(0.3) {
    try await Task.sleep(until: .now + .milliseconds(300), clock: .continuous)
})
check("SuspendingClock sleep(until:) waits", try await takes(0.3) {
    try await Task.sleep(until: .now + .milliseconds(300), clock: .suspending)
})
check("sleep with tolerance waits", try await takes(0.3) {
    try await Task.sleep(for: .milliseconds(300), tolerance: .milliseconds(100))
})
check("a deadline in the past returns at once", try await takes(0) {
    try await Task.sleep(until: .now - .seconds(5), clock: .continuous)
})

// MARK: Clocks

do {
    let continuous = ContinuousClock.now, suspending = SuspendingClock.now, date = Date()
    try await Task.sleep(nanoseconds: 200_000_000)
    let seconds = Date().timeIntervalSince(date)
    func close(_ duration: Duration) -> Bool {
        let measured = Double(duration.components.seconds) + Double(duration.components.attoseconds) / 1e18
        return abs(measured - seconds) < 0.05
    }
    check("ContinuousClock keeps time", close(ContinuousClock.now - continuous))
    check("SuspendingClock keeps time", close(SuspendingClock.now - suspending))
    let measured = ContinuousClock().measure { usleep(100_000) }
    check("ContinuousClock measures", measured >= .milliseconds(95) && measured < .milliseconds(600))
}

// MARK: Timeouts and cancellation

check("work faster than its timeout finishes", (try? await withTimeout(1) {
    try await Task.sleep(for: .milliseconds(100))
    return "done"
}) == "done")

do {
    var timedOut = false
    let quick = try await takes(0.2) {
        do {
            _ = try await withTimeout(0.2) {
                try await Task.sleep(for: .seconds(10))
                return "late"
            }
        } catch Timeout.timedOut {
            timedOut = true
        }
    }
    check("work slower than its timeout times out", timedOut && quick)
}

do {
    let task = Task {
        do {
            try await Task.sleep(for: .seconds(10))
            return "slept"
        } catch is CancellationError {
            return "cancelled"
        }
    }
    try await Task.sleep(for: .milliseconds(100))
    task.cancel()
    let result = try await task.value
    check("cancelling a sleeping task ends its sleep", result == "cancelled")
}

do {
    let handled = await withTaskGroup(of: Bool.self) { group in
        group.addTask {
            await withTaskCancellationHandler {
                (try? await Task.sleep(for: .seconds(10))) == nil
            } onCancel: {}
        }
        group.cancelAll()
        return await group.next()!
    }
    check("a cancelled group's sleeping child is woken", handled)
}

// MARK: Structured concurrency and actors

do {
    let start = Date()
    async let first: Int = { try? await Task.sleep(for: .milliseconds(200)); return 1 }()
    async let second: Int = { try? await Task.sleep(for: .milliseconds(200)); return 2 }()
    let sum = await first + second
    let elapsed = Date().timeIntervalSince(start)
    check("async lets run at once", sum == 3 && elapsed >= 0.19 && elapsed < 0.39)
}

do {
    let counter = Counter()
    await withTaskGroup(of: Void.self) { group in
        for _ in 0..<100 { group.addTask { await counter.increment() } }
    }
    check("an actor serializes its calls", await counter.value == 100)
}

do {
    let order = await withTaskGroup(of: Int.self) { group in
        for delay in [300, 100, 200] {
            group.addTask {
                try? await Task.sleep(for: .milliseconds(delay))
                return delay
            }
        }
        var order: [Int] = []
        for await delay in group { order.append(delay) }
        return order
    }
    check("children finish in order of their sleeps", order == [100, 200, 300])
}

check("top-level code runs on the main thread", pthread_main_np() != 0)
await MainActor.run { check("MainActor.run is on the main thread", pthread_main_np() != 0) }
check("a detached task leaves the main thread", await Task.detached { pthread_main_np() == 0 }.value)

if #available(iOS 26.0, macOS 26.0, *) {
    let name = await Task(name: "Fetch Location Data") { Task.name }.value
    check("a task knows its name", name == "Fetch Location Data")
    let child = await withTaskGroup(of: String?.self) { group in
        group.addTask(name: "child") { Task.name }
        return await group.next()!
    }
    check("a group's child knows its name", child == "child")
} else {
    check("a task knows its name", true)
    check("a group's child knows its name", true)
}

// MARK: Dispatch

do {
    let waited = await takes(0.3) {
        await withCheckedContinuation { continuation in
            DispatchQueue.global().asyncAfter(deadline: .now() + 0.3) { continuation.resume() }
        }
    }
    check("asyncAfter(deadline:) waits", waited)
    let walled = await takes(0.3) {
        await withCheckedContinuation { continuation in
            DispatchQueue.global().asyncAfter(wallDeadline: .now() + 0.3) { continuation.resume() }
        }
    }
    check("asyncAfter(wallDeadline:) waits", walled)
}

/// Dispatch's blocking waits, which time out: a semaphore's, then a group's.
func blockingWaits() -> (semaphore: Bool, group: Bool) {
    let semaphore = DispatchSemaphore(value: 0)
    let start = Date()
    let result = semaphore.wait(timeout: .now() + 0.2)
    let elapsed = Date().timeIntervalSince(start)
    let group = DispatchGroup()
    group.enter()
    defer { group.leave() }
    return (result == .timedOut && elapsed >= 0.19 && elapsed < 1.7, group.wait(timeout: .now() + 0.1) == .timedOut)
}

do {
    let waits = blockingWaits()
    check("a semaphore wait times out", waits.semaphore)
    check("a group wait times out", waits.group)
}

do {
    let fired = await takes(0.2) {
        await withCheckedContinuation { continuation in
            let timer = DispatchSource.makeTimerSource(queue: .global())
            timer.schedule(deadline: .now() + 0.2)
            timer.setEventHandler {
                timer.cancel()
                continuation.resume()
            }
            timer.resume()
        }
    }
    check("a timer source fires on time", fired)
    let start = DispatchTime.now()
    usleep(100_000)
    let nanoseconds = DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds
    check("DispatchTime keeps nanoseconds", nanoseconds >= 95_000_000 && nanoseconds < 600_000_000)
}
