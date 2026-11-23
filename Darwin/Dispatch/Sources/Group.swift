import Darwin

// DispatchGroup and DispatchSemaphore's Swift API, and dispatchPrecondition.

extension DispatchGroup {
    public func notify(qos: DispatchQoS = .unspecified, flags: DispatchWorkItemFlags = [], queue: DispatchQueue,
                       execute work: @escaping @convention(block) () -> Void) {
        let block = qos == .unspecified && flags.isEmpty ? work : makeBlock(qos: qos, flags: flags, work)
        __dispatch_group_notify(self, queue, block)
    }

    @available(macOS 10.10, iOS 8.0, *)
    public func notify(queue: DispatchQueue, work: DispatchWorkItem) {
        __dispatch_group_notify(self, queue, work._block)
    }

    @_unavailableFromAsync(message: "Use a TaskGroup instead")
    public func wait() {
        _ = __dispatch_group_wait(self, dispatchTimeForever)
    }

    @_unavailableFromAsync(message: "Use a TaskGroup instead")
    public func wait(timeout: DispatchTime) -> DispatchTimeoutResult {
        __dispatch_group_wait(self, timeout.rawValue) == 0 ? .success : .timedOut
    }

    @_unavailableFromAsync(message: "Use a TaskGroup instead")
    public func wait(wallTimeout timeout: DispatchWallTime) -> DispatchTimeoutResult {
        __dispatch_group_wait(self, timeout.rawValue) == 0 ? .success : .timedOut
    }
}

extension DispatchSemaphore {
    @discardableResult
    public func signal() -> Int {
        __dispatch_semaphore_signal(self)
    }

    @_unavailableFromAsync(message: "Await a Task handle instead")
    public func wait() {
        _ = __dispatch_semaphore_wait(self, dispatchTimeForever)
    }

    @_unavailableFromAsync(message: "Await a Task handle instead")
    public func wait(timeout: DispatchTime) -> DispatchTimeoutResult {
        __dispatch_semaphore_wait(self, timeout.rawValue) == 0 ? .success : .timedOut
    }

    @_unavailableFromAsync(message: "Await a Task handle instead")
    public func wait(wallTimeout: DispatchWallTime) -> DispatchTimeoutResult {
        __dispatch_semaphore_wait(self, wallTimeout.rawValue) == 0 ? .success : .timedOut
    }
}

@available(macOS 10.12, iOS 10.0, tvOS 10.0, watchOS 3.0, *)
public enum DispatchPredicate: Sendable {
    case onQueue(DispatchQueue)
    case onQueueAsBarrier(DispatchQueue)
    case notOnQueue(DispatchQueue)
}

/// Whether the predicate holds; dispatch's assertions stop the program
/// when it doesn't, with their own message.
@available(macOS 10.12, iOS 10.0, tvOS 10.0, watchOS 3.0, *)
public func _dispatchPreconditionTest(_ condition: DispatchPredicate) -> Bool {
    switch condition {
    case .onQueue(let queue): __dispatch_assert_queue(queue)
    case .onQueueAsBarrier(let queue): __dispatch_assert_queue_barrier(queue)
    case .notOnQueue(let queue): __dispatch_assert_queue_not(queue)
    }
    return true
}

@available(macOS 10.12, iOS 10.0, tvOS 10.0, watchOS 3.0, *)
@_transparent
public func dispatchPrecondition(condition: @autoclosure () -> DispatchPredicate) {
    precondition(_dispatchPreconditionTest(condition()), "dispatchPrecondition failure")
}
