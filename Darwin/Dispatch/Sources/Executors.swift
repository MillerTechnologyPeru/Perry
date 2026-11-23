import Darwin

// Queues as Swift concurrency executors: a serial queue runs an actor's
// jobs, any queue a task's.

@available(macOS 14.0, iOS 17.0, tvOS 17.0, watchOS 10.0, *)
extension _DispatchSerialExecutorQueue: SerialExecutor {
    public func enqueue(_ job: consuming ExecutorJob) {
        let job = UnownedJob(job)
        let executor = asUnownedSerialExecutor()
        __dispatch_async(self) { job.runSynchronously(on: executor) }
    }

    public func asUnownedSerialExecutor() -> UnownedSerialExecutor {
        UnownedSerialExecutor(ordinary: self)
    }

    @_alwaysEmitIntoClient
    public func checkIsolated() {
        dispatchPrecondition(condition: .onQueue(self))
    }

    /// Whether the current thread runs this queue's work: the queue's
    /// assertion, without stopping the program, isn't available, so this
    /// answers that it can't tell.
    @available(macOS 26.0, iOS 26.0, tvOS 26.0, watchOS 26.0, visionOS 26.0, *)
    public func isIsolatingCurrentContext() -> Bool? {
        nil
    }
}

@available(macOS 15.4, iOS 18.4, tvOS 18.4, watchOS 11.4, *)
extension DispatchQueue: TaskExecutor {
    public func enqueue(_ job: UnownedJob) {
        let executor = asUnownedTaskExecutor()
        __dispatch_async(self) { job.runSynchronously(on: executor) }
    }

    public func asUnownedTaskExecutor() -> UnownedTaskExecutor {
        UnownedTaskExecutor(ordinary: self)
    }
}
