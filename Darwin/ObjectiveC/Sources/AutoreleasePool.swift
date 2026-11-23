// Autorelease pools: the runtime's push and pop, which the SDK's own
// autoreleasepool(invoking:) is compiled into callers over, and the
// function of the Swift 5 overlay that programs built then call.

@_silgen_name("_objc_autoreleasePoolPush")
public func _autoreleasePoolPush() -> UnsafeMutableRawPointer

@_silgen_name("_objc_autoreleasePoolPop")
public func _autoreleasePoolPop(_: UnsafeMutableRawPointer)

/// Runs `body` in a pool of its own, draining it after, whether `body`
/// returns or throws.
public func autoreleasepool<Result>(invoking body: () throws -> Result) rethrows -> Result {
    let pool = _autoreleasePoolPush()
    defer { _autoreleasePoolPop(pool) }
    return try body()
}
