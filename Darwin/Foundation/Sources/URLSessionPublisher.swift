// URLSession's Combine publisher, which runs a data task for each
// subscriber that asks for a value. Declarations are the SDK interface's.

import Combine

@available(macOS 10.15, iOS 13.0, tvOS 13.0, watchOS 6.0, *)
extension URLSession {
    public func dataTaskPublisher(for url: URL) -> URLSession.DataTaskPublisher {
        DataTaskPublisher(request: URLRequest(url: url), session: self)
    }

    public func dataTaskPublisher(for request: URLRequest) -> URLSession.DataTaskPublisher {
        DataTaskPublisher(request: request, session: self)
    }

    public struct DataTaskPublisher: Publisher, Sendable {
        public typealias Output = (data: Data, response: URLResponse)
        public typealias Failure = URLError

        public let request: URLRequest
        public let session: URLSession

        public init(request: URLRequest, session: URLSession) {
            self.request = request
            self.session = session
        }

        public func receive<S>(subscriber: S) where S: Subscriber, S.Failure == URLError, S.Input == (data: Data, response: URLResponse) {
            subscriber.receive(subscription: DataTaskSubscription(publisher: self, subscriber: AnySubscriber(subscriber)))
        }
    }
}

/// One subscriber's data task: started on its first demand, cancelled
/// with the subscription.
@available(macOS 10.15, iOS 13.0, tvOS 13.0, watchOS 6.0, *)
private final class DataTaskSubscription: Subscription, @unchecked Sendable {
    typealias Output = URLSession.DataTaskPublisher.Output

    private let lock = NSLock()
    private let publisher: URLSession.DataTaskPublisher
    private var subscriber: AnySubscriber<Output, URLError>?
    private var task: URLSessionDataTask?

    init(publisher: URLSession.DataTaskPublisher, subscriber: AnySubscriber<Output, URLError>) {
        self.publisher = publisher
        self.subscriber = subscriber
    }

    func request(_ demand: Subscribers.Demand) {
        guard demand > 0 else { return }
        lock.lock()
        guard subscriber != nil, task == nil else { lock.unlock(); return }
        let task = publisher.session.dataTask(with: publisher.request) { [weak self] data, response, error in
            self?.finish(data: data, response: response, error: error)
        }
        self.task = task
        lock.unlock()
        task.resume()
    }

    private func finish(data: Data?, response: URLResponse?, error: Error?) {
        lock.lock()
        guard let subscriber else { lock.unlock(); return }
        self.subscriber = nil
        task = nil
        lock.unlock()
        if let response, error == nil {
            _ = subscriber.receive((data: data ?? Data(), response: response))
            subscriber.receive(completion: .finished)
        } else {
            let failure = (error as? URLError) ?? URLError(.unknown)
            subscriber.receive(completion: .failure(failure))
        }
    }

    func cancel() {
        lock.lock()
        let task = task
        self.task = nil
        subscriber = nil
        lock.unlock()
        task?.cancel()
    }
}
