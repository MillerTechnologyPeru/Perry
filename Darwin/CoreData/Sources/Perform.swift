// Core Data's Swift API newer than the overlay Perry runs apps with:
// running blocks on a context's queue from async code. Declarations are the
// SDK interface's, for its ABI.

public import Foundation

@available(macOS 12.0, iOS 15.0, tvOS 15.0, watchOS 8.0, *)
extension NSManagedObjectContext {
  /// When a block given to perform(schedule:_:) runs: at once when the
  /// caller is on the context's queue, else enqueued; or always enqueued.
  public enum ScheduledTaskType {
    case immediate
    case enqueued
  }
}

@available(macOS 12.0, iOS 15.0, tvOS 15.0, watchOS 8.0, *)
extension NSManagedObjectContext.ScheduledTaskType : Swift.Equatable {}
@available(macOS 12.0, iOS 15.0, tvOS 15.0, watchOS 8.0, *)
extension NSManagedObjectContext.ScheduledTaskType : Swift.Hashable {}

@available(macOS 12.0, iOS 15.0, tvOS 15.0, watchOS 8.0, *)
extension NSManagedObjectContext {
  /// Runs `block` on the context's queue and returns its result. The SDK
  /// declares this rethrows, which is throws to its ABI.
  @preconcurrency nonisolated public func perform<T>(schedule: NSManagedObjectContext.ScheduledTaskType = .immediate, _ block: @escaping @Sendable () throws -> T) async throws -> T {
    let result: Result<T, any Error> = await withCheckedContinuation { continuation in
      let context = UnsafeSendable(value: self)
      context.value.perform {
        continuation.resume(returning: Result { try block() })
      }
    }
    return try result.get()
  }
}

@available(macOS 12.0, iOS 15.0, tvOS 15.0, watchOS 8.0, *)
extension NSManagedObjectContext {
  /// Runs `block` on the context's queue, waiting for it, and returns its
  /// result. The SDK declares this rethrows, which is throws to its ABI.
  @preconcurrency public func performAndWait<T>(_ block: @Sendable () throws -> T) throws -> T {
    var result: Result<T, any Error>?
    withoutActuallyEscaping(block) { block in
      let body: () -> Void = { result = Result { try block() } }
      performAndWait(body)
    }
    return try result!.get()
  }
}

/// A value carried across a Sendable boundary that the caller makes safe.
private struct UnsafeSendable<Value>: @unchecked Sendable {
  let value: Value
}
