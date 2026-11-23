import Foundation

// Waiting from async code, teardown blocks, and XCTKeyPathExpectation: an
// expectation fulfilled when a key path of an object observed through KVO
// passes a filter or reaches a value.

extension XCTestCase {
    @available(macOS 10.15, iOS 13.0, tvOS 13.0, watchOS 6.0, *)
    @nonobjc @_unsafeInheritExecutor
    public func fulfillment(of expectations: [XCTestExpectation], timeout seconds: TimeInterval = .infinity,
                            enforceOrder enforceOrderOfFulfillment: Bool = false) async {
        // The waiter reports a timeout or an order broken to this test case.
        let waiter = XCTWaiter(delegate: self)
        _ = await waiter.fulfillment(of: expectations, timeout: seconds, enforceOrder: enforceOrderOfFulfillment)
    }

    @available(macOS 10.15, iOS 13.0, tvOS 13.0, watchOS 6.0, *)
    public func addTeardownBlock(_ block: @escaping @Sendable () async throws -> Void) {
        __addAsyncTeardownBlock { completion in
            Task {
                do {
                    try await block()
                    completion(nil)
                } catch {
                    completion(error)
                }
            }
        }
    }

    @available(macOS 10.15, iOS 13.0, tvOS 13.0, watchOS 6.0, *)
    @preconcurrency
    public func addTeardownBlock(_ block: @escaping @MainActor @Sendable () throws -> Void) {
        __addTeardownBlock { [weak self] in
            MainActor.assumeIsolated {
                do {
                    try block()
                } catch {
                    let issue = XCTIssue(type: .thrownError, compactDescription: "Teardown block threw error \"\(error)\"",
                                         associatedError: error)
                    self?.record(issue)
                }
            }
        }
    }
}

extension XCTWaiter {
    /// Waits on this thread, running its run loop, as wait(for:) does.
    private func waitHere(for expectations: [XCTestExpectation], timeout: TimeInterval, enforceOrder: Bool) -> Result {
        wait(for: expectations, timeout: timeout, enforceOrder: enforceOrder)
    }

    @available(macOS 10.15, iOS 13.0, tvOS 13.0, watchOS 6.0, *)
    @discardableResult
    @nonobjc @_unsafeInheritExecutor
    public func fulfillment(of expectations: [XCTestExpectation], timeout seconds: TimeInterval = .infinity,
                            enforceOrder enforceOrderOfFulfillment: Bool = false) async -> Result {
        waitHere(for: expectations, timeout: seconds, enforceOrder: enforceOrderOfFulfillment)
    }

    @available(macOS 10.15, iOS 13.0, tvOS 13.0, watchOS 6.0, *)
    @nonobjc @_unsafeInheritExecutor
    public class func fulfillment(of expectations: [XCTestExpectation], timeout seconds: TimeInterval = .infinity,
                                  enforceOrder enforceOrderOfFulfillment: Bool = false) async -> Result {
        XCTWaiter().waitHere(for: expectations, timeout: seconds, enforceOrder: enforceOrderOfFulfillment)
    }
}

/// A Sendable box for what a filter is given.
private struct Unchecked<T>: @unchecked Sendable {
    let value: T
}

@_inheritsConvenienceInitializers
@available(iOS 13.0, tvOS 13.0, *)
public final class XCTKeyPathExpectation<T, V>: XCTestExpectation, @unchecked Sendable where T: NSObject {
    @available(*, deprecated, message: "T and V must be Sendable when used with an asynchronous filtering function.")
    public typealias Predicate = @Sendable (_ observedObject: T, _ change: NSKeyValueObservedChange<V>) async -> Bool

    public final let keyPath: KeyPath<T, V>
    public final let observedObject: T
    public final let options: NSKeyValueObservingOptions

    /// The value waited for, when one is.
    private let expected: Any?
    /// The KVO observation, kept until the expectation is fulfilled.
    private var observation: NSKeyValueObservation?
    private let lock = NSLock()

    /// Observes `keyPath` on `observedObject`, fulfilling the expectation the
    /// first time `check` returns true for a change.
    private init(keyPath: KeyPath<T, V>, observedObject: T, options: NSKeyValueObservingOptions, expected: Any?,
                 check: @escaping @Sendable (T, NSKeyValueObservedChange<V>, @escaping @Sendable (Bool) -> Void) -> Void) {
        self.keyPath = keyPath
        self.observedObject = observedObject
        self.options = options
        self.expected = expected
        super.init(description: "Expect value of '\(keyPath)' of \(type(of: observedObject))")
        let observation = observedObject.observe(keyPath, options: options) { [weak self] object, change in
            check(object, change) { passed in
                if passed { self?.passed() }
            }
        }
        lock.withLock { self.observation = observation }
    }

    /// Fulfills the expectation once and stops observing.
    private func passed() {
        let observation: NSKeyValueObservation? = lock.withLock {
            defer { self.observation = nil }
            return self.observation
        }
        guard let observation else { return }
        observation.invalidate()
        fulfill()
    }

    @available(*, unavailable, message: "Use init(keyPath:observedObject:options:filter:) instead.")
    @objc public convenience dynamic init() {
        fatalError("XCTKeyPathExpectation needs a key path")
    }

    @available(*, unavailable, message: "Use init(keyPath:observedObject:options:filter:) instead.")
    @objc public override convenience dynamic init(description: String) {
        fatalError("XCTKeyPathExpectation needs a key path")
    }

    @available(*, deprecated, message: "T and V must be Sendable when used with an asynchronous filtering function.")
    @_disfavoredOverload @_semantics("keypath.mustBeValidForKVO")
    public convenience init(keyPath: KeyPath<T, V>, observedObject: T, options: NSKeyValueObservingOptions = [.initial, .new, .old],
                            predicate: Predicate? = nil) {
        self.init(keyPath: keyPath, observedObject: observedObject, options: options, expected: nil) { object, change, done in
            guard let predicate else { return done(true) }
            let arguments = Unchecked(value: (object, change))
            Task { done(await predicate(arguments.value.0, arguments.value.1)) }
        }
    }

    deinit {
        observation?.invalidate()
    }
}

@available(iOS 13.0, tvOS 13.0, *)
extension XCTKeyPathExpectation {
    public typealias SynchronousFilter = @Sendable (_ observedObject: T, _ change: NSKeyValueObservedChange<V>) -> Bool

    @_semantics("keypath.mustBeValidForKVO")
    public convenience init(keyPath: KeyPath<T, V>, observedObject: T, options: NSKeyValueObservingOptions = [.initial, .new, .old],
                            filter: SynchronousFilter? = nil) {
        self.init(keyPath: keyPath, observedObject: observedObject, options: options, expected: nil) { object, change, done in
            done(filter?(object, change) ?? true)
        }
    }
}

@available(iOS 13.0, tvOS 13.0, *)
extension XCTKeyPathExpectation where T: Sendable, V: Sendable {
    public typealias AsynchronousFilter = @Sendable (_ observedObject: T, _ change: NSKeyValueObservedChange<V>) async -> Bool

    @_semantics("keypath.mustBeValidForKVO")
    public convenience init(keyPath: KeyPath<T, V>, observedObject: T, options: NSKeyValueObservingOptions = [.initial, .new, .old],
                            filter: AsynchronousFilter? = nil) {
        self.init(keyPath: keyPath, observedObject: observedObject, options: options, expected: nil) { object, change, done in
            guard let filter else { return done(true) }
            let arguments = Unchecked(value: (object, change))
            Task { done(await filter(arguments.value.0, arguments.value.1)) }
        }
    }
}

@available(iOS 13.0, tvOS 13.0, *)
extension XCTKeyPathExpectation where V: Equatable {
    @_semantics("keypath.mustBeValidForKVO")
    public convenience init(keyPath: KeyPath<T, V>, observedObject: T, options: NSKeyValueObservingOptions = [.initial, .new, .old],
                            expectedValue: V) {
        let expected = Unchecked(value: expectedValue)
        let path = Unchecked(value: keyPath)
        self.init(keyPath: keyPath, observedObject: observedObject, options: options, expected: expectedValue) { object, change, done in
            let value = change.newValue ?? object[keyPath: path.value]
            done(value == expected.value)
        }
    }

    public final var expectedValue: V? { expected as? V }
}

extension XCTestCase {
    @available(iOS 13.0, tvOS 13.0, *)
    @_semantics("keypath.mustBeValidForKVO")
    public func expectation<T, V>(that keyPath: KeyPath<T, V>, on observedObject: T,
                                  options: NSKeyValueObservingOptions = [.initial, .new, .old],
                                  willEqual expectedValue: V) -> XCTKeyPathExpectation<T, V> where T: NSObject, V: Equatable {
        XCTKeyPathExpectation(keyPath: keyPath, observedObject: observedObject, options: options, expectedValue: expectedValue)
    }

    @available(iOS 13.0, tvOS 13.0, *)
    @available(*, deprecated, message: "T and V must be Sendable when used with an asynchronous filtering function.")
    @_disfavoredOverload @_semantics("keypath.mustBeValidForKVO")
    public func expectation<T, V>(that keyPath: KeyPath<T, V>, on observedObject: T,
                                  options: NSKeyValueObservingOptions = [.initial, .new, .old],
                                  willSatisfy predicate: XCTKeyPathExpectation<T, V>.Predicate? = nil) -> XCTKeyPathExpectation<T, V> where T: NSObject {
        XCTKeyPathExpectation(keyPath: keyPath, observedObject: observedObject, options: options, predicate: predicate)
    }

    @available(iOS 13.0, tvOS 13.0, *)
    @_semantics("keypath.mustBeValidForKVO")
    public func expectation<T, V>(that keyPath: KeyPath<T, V>, on observedObject: T,
                                  options: NSKeyValueObservingOptions = [.initial, .new, .old],
                                  willSatisfy filter: XCTKeyPathExpectation<T, V>.SynchronousFilter? = nil) -> XCTKeyPathExpectation<T, V> where T: NSObject {
        XCTKeyPathExpectation(keyPath: keyPath, observedObject: observedObject, options: options, filter: filter)
    }

    @available(iOS 13.0, tvOS 13.0, *)
    @_semantics("keypath.mustBeValidForKVO")
    public func expectation<T, V>(that keyPath: KeyPath<T, V>, on observedObject: T,
                                  options: NSKeyValueObservingOptions = [.initial, .new, .old],
                                  willSatisfy filter: XCTKeyPathExpectation<T, V>.AsynchronousFilter? = nil) -> XCTKeyPathExpectation<T, V> where T: NSObject, T: Sendable, V: Sendable {
        XCTKeyPathExpectation(keyPath: keyPath, observedObject: observedObject, options: options, filter: filter)
    }
}
