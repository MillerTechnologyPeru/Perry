import Foundation

// Fetching from a context with a fetch request's result type, as the
// Swift 5.0 overlay had it.

extension NSManagedObjectContext {
    public func fetch<T>(_ request: NSFetchRequest<T>) throws -> [T] where T: NSFetchRequestResult {
        // The request's type parameter is Swift's alone: the Objective-C
        // request returns objects of its result type, which T names.
        let results = try __execute(request as! NSFetchRequest<NSFetchRequestResult>)
        return results as! [T]
    }

    /// The framework's untyped fetch, newer than the overlay.
    @available(macOS 12.0, iOS 15.0, tvOS 15.0, watchOS 8.0, *)
    @_disfavoredOverload
    public func fetch(_ request: NSFetchRequest<any NSFetchRequestResult>) throws -> [Any] {
        try __execute(request)
    }

    public func count<T>(for request: NSFetchRequest<T>) throws -> Int where T: NSFetchRequestResult {
        try count(for: request as! NSFetchRequest<NSFetchRequestResult>)
    }
}
