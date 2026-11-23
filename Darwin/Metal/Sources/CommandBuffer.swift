import Foundation

@available(macOS 11.0, iOS 14.0, tvOS 14.0, *)
public struct MTLLogContainer: Sequence {
    public typealias Element = MTLFunctionLog

    let logs: __MTLLogContainer

    init(_ logs: __MTLLogContainer) {
        self.logs = logs
    }

    public struct Iterator: IteratorProtocol {
        public typealias Element = MTLFunctionLog

        var base: NSFastEnumerationIterator

        public mutating func next() -> MTLFunctionLog? {
            while let object = base.next() {
                if let log = object as? MTLFunctionLog { return log }
            }
            return nil
        }
    }

    public func makeIterator() -> Iterator {
        Iterator(base: NSFastEnumerationIterator(logs))
    }
}

@available(macOS 10.11, iOS 8.0, tvOS 8.0, *)
extension MTLCommandBuffer {
    @available(macOS 11.0, iOS 14.0, tvOS 14.0, *)
    public var logs: MTLLogContainer {
        MTLLogContainer(__logs)
    }

    @available(macOS 15.0, iOS 18.0, tvOS 18.0, *)
    public func useResidencySets(_ residencySets: [MTLResidencySet]) {
        __useResidencySets(residencySets, count: residencySets.count)
    }

    /// Waits for the buffer to be scheduled. The completion handlers are
    /// the way to wait without blocking, but one can only be added before
    /// the buffer is committed, so this waits on a thread of its own.
    @available(macOS 10.15, iOS 13.0, tvOS 13.0, *)
    public func scheduled() async {
        await Self.waitOffThread(self) { $0.waitUntilScheduled() }
    }

    @available(macOS 10.15, iOS 13.0, tvOS 13.0, *)
    public func completed() async {
        await Self.waitOffThread(self) { $0.waitUntilCompleted() }
    }

    @available(macOS 10.15, iOS 13.0, tvOS 13.0, *)
    private static func waitOffThread(_ buffer: MTLCommandBuffer, _ wait: @escaping (MTLCommandBuffer) -> Void) async {
        nonisolated(unsafe) let buffer = buffer
        await withUnsafeContinuation { (continuation: UnsafeContinuation<Void, Never>) in
            Thread.detachNewThread {
                wait(buffer)
                continuation.resume()
            }
        }
    }
}

@available(macOS 10.14, iOS 12.0, tvOS 12.0, *)
extension MTLSharedEvent {
    @available(macOS 10.15, iOS 13.0, tvOS 13.0, *)
    public func valueSignaled(_ value: UInt64) async {
        await withUnsafeContinuation { (continuation: UnsafeContinuation<Void, Never>) in
            self.notify(MTLSharedEventListener(), atValue: value) { _, _ in
                continuation.resume()
            }
        }
    }
}

@available(macOS 15.0, iOS 18.0, tvOS 18.0, *)
extension MTLCommandQueue {
    @available(macOS 15.0, iOS 18.0, tvOS 18.0, *)
    public func addResidencySets(_ residencySets: [MTLResidencySet]) {
        __addResidencySets(residencySets, count: residencySets.count)
    }

    @available(macOS 15.0, iOS 18.0, tvOS 18.0, *)
    public func removeResidencySets(_ residencySets: [MTLResidencySet]) {
        __removeResidencySets(residencySets, count: residencySets.count)
    }
}

@available(macOS 15.0, iOS 18.0, tvOS 18.0, *)
extension MTLResidencySet {
    @available(macOS 15.0, iOS 18.0, tvOS 18.0, *)
    public func addAllocations(_ allocations: [MTLAllocation]) {
        __addAllocations(allocations, count: allocations.count)
    }

    @available(macOS 15.0, iOS 18.0, tvOS 18.0, *)
    public func removeAllocations(_ allocations: [MTLAllocation]) {
        __removeAllocations(allocations, count: allocations.count)
    }
}

@available(macOS 11.0, iOS 14.0, tvOS 14.0, *)
extension MTLCounterSampleBuffer {
    @available(macOS 11.0, iOS 14.0, tvOS 14.0, *)
    public func resolveCounterRange(_ range: Range<Int>) throws -> Data? {
        __resolveCounterRange(NSRange(range))
    }
}
