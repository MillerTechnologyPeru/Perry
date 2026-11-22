//
//  Publishers.CollectByTime.swift
//
//  Perry's own: OpenCombine has no collect(_:options:) by time.
//

extension Publisher {

    /// Collects elements by a given time-grouping strategy, and emits a
    /// single array of the collection.
    public func collect<Context: Scheduler>(
        _ strategy: Publishers.TimeGroupingStrategy<Context>,
        options: Context.SchedulerOptions? = nil
    ) -> Publishers.CollectByTime<Self, Context> {
        return .init(upstream: self, strategy: strategy, options: options)
    }
}

extension Publishers {

    /// A strategy for collecting received elements.
    public enum TimeGroupingStrategy<Context: Scheduler> {

        /// A grouping that collects and publishes elements periodically.
        case byTime(Context, Context.SchedulerTimeType.Stride)

        /// A grouping that collects and publishes elements periodically, or
        /// when a buffer reaches a maximum size.
        case byTimeOrCount(Context, Context.SchedulerTimeType.Stride, Int)
    }

    /// A publisher that buffers and periodically publishes its items.
    public struct CollectByTime<Upstream: Publisher, Context: Scheduler>: Publisher {

        public typealias Output = [Upstream.Output]

        public typealias Failure = Upstream.Failure

        public let upstream: Upstream

        public let strategy: Publishers.TimeGroupingStrategy<Context>

        public let options: Context.SchedulerOptions?

        public init(upstream: Upstream,
                    strategy: Publishers.TimeGroupingStrategy<Context>,
                    options: Context.SchedulerOptions?) {
            self.upstream = upstream
            self.strategy = strategy
            self.options = options
        }

        public func receive<Downstream: Subscriber>(subscriber: Downstream)
            where Downstream.Failure == Failure, Downstream.Input == Output
        {
            upstream.subscribe(Inner(downstream: subscriber, strategy: strategy, options: options))
        }
    }
}

extension Publishers.CollectByTime {
    private final class Inner<Downstream: Subscriber>
        : Subscriber,
          Subscription,
          CustomStringConvertible,
          CustomPlaygroundDisplayConvertible
        where Downstream.Input == [Upstream.Output],
              Downstream.Failure == Upstream.Failure
    {
        typealias Input = Upstream.Output

        typealias Failure = Upstream.Failure

        private let lock = UnfairLock.allocate()

        private let downstreamLock = UnfairRecursiveLock.allocate()

        private let downstream: Downstream

        private let scheduler: Context

        private let interval: Context.SchedulerTimeType.Stride

        /// The buffer's size at which it is published early, if any.
        private let count: Int?

        private let options: Context.SchedulerOptions?

        private var state = SubscriptionStatus.awaitingSubscription

        private var buffer: [Input] = []

        private var timer: Cancellable?

        private var demand = Subscribers.Demand.none

        /// A completion that waits for demand, the buffer not yet sent.
        private var pendingCompletion: Subscribers.Completion<Failure>?

        init(downstream: Downstream,
             strategy: Publishers.TimeGroupingStrategy<Context>,
             options: Context.SchedulerOptions?) {
            self.downstream = downstream
            self.options = options
            switch strategy {
            case let .byTime(scheduler, interval):
                self.scheduler = scheduler
                self.interval = interval
                self.count = nil
            case let .byTimeOrCount(scheduler, interval, count):
                self.scheduler = scheduler
                self.interval = interval
                self.count = count
            }
        }

        deinit {
            lock.deallocate()
            downstreamLock.deallocate()
        }

        func receive(subscription: Subscription) {
            lock.lock()
            guard case .awaitingSubscription = state else {
                lock.unlock()
                subscription.cancel()
                return
            }
            state = .subscribed(subscription)
            lock.unlock()
            let timer = scheduler.schedule(after: scheduler.now.advanced(by: interval),
                                           interval: interval,
                                           tolerance: scheduler.minimumTolerance,
                                           options: options) { [weak self] in
                self?.flush()
            }
            lock.lock()
            if case .subscribed = state {
                self.timer = timer
                lock.unlock()
            } else {
                lock.unlock()
                timer.cancel()
            }
            downstreamLock.lock()
            downstream.receive(subscription: self)
            downstreamLock.unlock()
            // The buffer bounds nothing upstream: time does.
            subscription.request(.unlimited)
        }

        func receive(_ input: Input) -> Subscribers.Demand {
            lock.lock()
            guard case .subscribed = state else {
                lock.unlock()
                return .none
            }
            buffer.append(input)
            let full = count.map { buffer.count >= $0 } ?? false
            lock.unlock()
            if full { flush() }
            return .none
        }

        func receive(completion: Subscribers.Completion<Failure>) {
            lock.lock()
            guard case .subscribed = state else {
                lock.unlock()
                return
            }
            let timer = self.timer
            self.timer = nil
            if case .finished = completion, !buffer.isEmpty, demand == .none {
                // What is left goes out with the next request.
                pendingCompletion = completion
                lock.unlock()
                timer?.cancel()
                return
            }
            state = .terminal
            let rest = buffer
            buffer = []
            lock.unlock()
            timer?.cancel()
            downstreamLock.lock()
            if case .finished = completion, !rest.isEmpty {
                _ = downstream.receive(rest)
            }
            downstream.receive(completion: completion)
            downstreamLock.unlock()
        }

        func request(_ demand: Subscribers.Demand) {
            demand.assertNonZero()
            lock.lock()
            guard case .subscribed = state else {
                lock.unlock()
                return
            }
            self.demand += demand
            guard let completion = pendingCompletion else {
                lock.unlock()
                return
            }
            pendingCompletion = nil
            state = .terminal
            let rest = buffer
            buffer = []
            lock.unlock()
            downstreamLock.lock()
            _ = downstream.receive(rest)
            downstream.receive(completion: completion)
            downstreamLock.unlock()
        }

        func cancel() {
            lock.lock()
            guard case let .subscribed(subscription) = state else {
                lock.unlock()
                return
            }
            state = .terminal
            let timer = self.timer
            self.timer = nil
            buffer = []
            lock.unlock()
            timer?.cancel()
            subscription.cancel()
        }

        /// Publishes the buffer, if it holds anything and there is demand.
        private func flush() {
            lock.lock()
            guard case .subscribed = state, !buffer.isEmpty, demand > .none else {
                lock.unlock()
                return
            }
            let elements = buffer
            buffer = []
            demand -= 1
            lock.unlock()
            downstreamLock.lock()
            let more = downstream.receive(elements)
            downstreamLock.unlock()
            guard more > .none else { return }
            lock.lock()
            demand += more
            lock.unlock()
        }

        var description: String { return "CollectByTime" }

        var playgroundDescription: Any { return description }
    }
}
