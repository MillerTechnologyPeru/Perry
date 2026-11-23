import Foundation

// Results that carry an error instead of throwing: CreateML's tables and
// columns stay values when an operation on them fails, and report the
// failure through their `error` and `isValid`. These are the helpers the
// Swift 5.0 overlay exported for it, which Perry's tables use too.

/// A value, or the error that kept it from being made.
@usableFromInline
enum _ResultType<T> {
    case success(T)
    case failure(any Error)

    /// The value, or the error thrown.
    func get() throws -> T {
        switch self {
        case .success(let value): return value
        case .failure(let error): throw error
        }
    }

    var value: T? {
        if case .success(let value) = self { return value }
        return nil
    }

    var error: (any Error)? {
        if case .failure(let error) = self { return error }
        return nil
    }
}

@usableFromInline
func nullaryDo<T>(_ body: () throws -> T) -> _ResultType<T> {
    do { return .success(try body()) } catch { return .failure(error) }
}

@usableFromInline
func nullaryDo<T>(_ body: () throws -> _ResultType<T>) -> _ResultType<T> {
    do { return try body() } catch { return .failure(error) }
}

@usableFromInline
func unaryDo<A, B>(_ a: _ResultType<A>, _ body: (A) throws -> B) -> _ResultType<B> {
    switch a {
    case .success(let a): return nullaryDo { try body(a) }
    case .failure(let error): return .failure(error)
    }
}

@usableFromInline
func unaryDo<A, B>(_ a: _ResultType<A>, _ body: (A) throws -> _ResultType<B>) -> _ResultType<B> {
    switch a {
    case .success(let a): return nullaryDo { try body(a) }
    case .failure(let error): return .failure(error)
    }
}

@usableFromInline
func unaryDo<A, B>(_ a: _ResultType<A>, defaultVal: B, _ body: (A) -> B) -> B {
    a.value.map(body) ?? defaultVal
}

@usableFromInline
func binaryDo<A, B, C>(_ a: _ResultType<A>, _ b: _ResultType<B>, _ body: (A, B) throws -> C) -> _ResultType<C> {
    switch (a, b) {
    case (.success(let a), .success(let b)): return nullaryDo { try body(a, b) }
    case (.failure(let error), _), (_, .failure(let error)): return .failure(error)
    }
}

@usableFromInline
func binaryDo<A, B, C>(_ a: _ResultType<A>, _ b: _ResultType<B>, _ body: (A, B) throws -> _ResultType<C>) -> _ResultType<C> {
    switch (a, b) {
    case (.success(let a), .success(let b)): return nullaryDo { try body(a, b) }
    case (.failure(let error), _), (_, .failure(let error)): return .failure(error)
    }
}

@usableFromInline
func binaryDo<A, B, C>(_ a: _ResultType<A>, _ b: _ResultType<B>, defaultVal: C, _ body: (A, B) -> C) -> C {
    guard let a = a.value, let b = b.value else { return defaultVal }
    return body(a, b)
}

// The Swift 5.0 overlay's bridge to the C library its tables lived in,
// which reported errors through an out pointer. Perry's tables are Swift,
// so nothing sets one; these still turn a set error into a thrown one.

/// Throws the error a C call left, if it left one.
@usableFromInline
func handle(error: OpaquePointer?) throws {
    if error != nil {
        throw MLCreateError.generic(reason: "The operation failed.")
    }
}

@usableFromInline
func handling<R>(_ body: (UnsafeMutablePointer<OpaquePointer?>) -> R) throws -> R {
    var error: OpaquePointer?
    let result = body(&error)
    try handle(error: error)
    return result
}

@usableFromInline
func handling<R, A>(_ body: (A, UnsafeMutablePointer<OpaquePointer?>) -> R, _ a: A) throws -> R {
    try handling { body(a, $0) }
}

@usableFromInline
func handling<R, A, B>(_ body: (A, B, UnsafeMutablePointer<OpaquePointer?>) -> R, _ a: A, _ b: B) throws -> R {
    try handling { body(a, b, $0) }
}

@usableFromInline
func handling<R, A, B, C>(_ body: (A, B, C, UnsafeMutablePointer<OpaquePointer?>) -> R, _ a: A, _ b: B, _ c: C) throws -> R {
    try handling { body(a, b, c, $0) }
}

@usableFromInline
func handling<R, A, B, C, D>(_ body: (A, B, C, D, UnsafeMutablePointer<OpaquePointer?>) -> R,
                             _ a: A, _ b: B, _ c: C, _ d: D) throws -> R {
    try handling { body(a, b, c, d, $0) }
}

@usableFromInline
func handling<R, A, B, C, D, E>(_ body: (A, B, C, D, E, UnsafeMutablePointer<OpaquePointer?>) -> R,
                                _ a: A, _ b: B, _ c: C, _ d: D, _ e: E) throws -> R {
    try handling { body(a, b, c, d, e, $0) }
}

@usableFromInline
func handling<R, A, B, C, D, E, F>(_ body: (A, B, C, D, E, F, UnsafeMutablePointer<OpaquePointer?>) -> R,
                                   _ a: A, _ b: B, _ c: C, _ d: D, _ e: E, _ f: F) throws -> R {
    try handling { body(a, b, c, d, e, f, $0) }
}

@usableFromInline
func handling<R, A, B, C, D, E, F, G>(_ body: (A, B, C, D, E, F, G, UnsafeMutablePointer<OpaquePointer?>) -> R,
                                      _ a: A, _ b: B, _ c: C, _ d: D, _ e: E, _ f: F, _ g: G) throws -> R {
    try handling { body(a, b, c, d, e, f, g, $0) }
}

/// Padding the Swift 5.0 overlay laid some values out with.
@usableFromInline
struct SevenBytePadding {
    var bytes: (UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8) = (0, 0, 0, 0, 0, 0, 0)

    @usableFromInline
    init() {}
}

// Errors.

public let MLCreateErrorDomain: String = "com.apple.CreateML"

public enum MLCreateError: Error, Sendable {
    case generic(reason: String)
    case type(reason: String)
    case io(reason: String)
    case cancelled
    case incompatibleParameters(parameter: String, originalValue: String, newValue: String)
    case modifiedTrainingData
}

extension MLCreateError: LocalizedError {
    public var failureReason: String? {
        switch self {
        case .generic(let reason), .type(let reason), .io(let reason):
            return reason
        case .cancelled:
            return "The operation was cancelled."
        case .incompatibleParameters(let parameter, let originalValue, let newValue):
            return "The parameter \(parameter) was \(originalValue) when the session started and is now \(newValue)."
        case .modifiedTrainingData:
            return "The training data changed since the session started."
        }
    }

    public var errorDescription: String? {
        switch self {
        case .generic: return "Generic error: \(failureReason ?? "")"
        case .type: return "Type error: \(failureReason ?? "")"
        case .io: return "IO error: \(failureReason ?? "")"
        case .cancelled: return "Cancelled"
        case .incompatibleParameters: return "Incompatible parameters: \(failureReason ?? "")"
        case .modifiedTrainingData: return "Modified training data: \(failureReason ?? "")"
        }
    }
}

extension MLCreateError: CustomNSError {
    public static var errorDomain: String { MLCreateErrorDomain }

    public var errorCode: Int {
        switch self {
        case .generic: return 0
        case .type: return 1
        case .io: return 2
        case .cancelled: return 3
        case .incompatibleParameters: return 4
        case .modifiedTrainingData: return 5
        }
    }

    public var errorUserInfo: [String: Any] {
        var userInfo: [String: Any] = [:]
        if let errorDescription { userInfo[NSLocalizedDescriptionKey] = errorDescription }
        if let failureReason { userInfo[NSLocalizedFailureReasonErrorKey] = failureReason }
        return userInfo
    }
}

extension MLCreateError: CustomStringConvertible, CustomDebugStringConvertible {
    public var description: String { errorDescription ?? "MLCreateError" }
    public var debugDescription: String { description }
}

/// The error what can't be done in Perry's CreateML throws: training and
/// running models, which Apple's CreateML does in its private engine.
func unavailable(_ what: String) -> MLCreateError {
    .generic(reason: "\(what) isn't available: Perry's CreateML has CreateML's data tables, columns and values, "
        + "but not the engine that trains and runs models.")
}

/// The error a trainer of a type throws.
func trainingUnavailable(_ type: Any.Type) -> MLCreateError {
    unavailable("Training \(type)")
}
