/// Runs `body`, which may run Darwin code, in a function a Linux library
/// called: libdispatch's work functions, glibc's thread starts and key
/// destructors.
///
/// Darwin's armv7 code may change r9, which Linux's code keeps across calls.
/// Perry's code leaves r9 alone (it is built with -ffixed-r9), so keeping it
/// here keeps it for the Linux code that called. Elsewhere this runs `body`.
@inline(__always)
public func keepingLinuxRegisters<T>(_ body: () -> T) -> T {
#if arch(arm)
    var result: T?
    withoutActuallyEscaping({ result = body() }) { run in
        var run = run
        withUnsafeMutablePointer(to: &run) { perry_keep_r9(runClosure, $0) }
    }
    return result!
#else
    return body()
#endif
}

#if arch(arm)
private let runClosure: @convention(c) (UnsafeMutableRawPointer?) -> Void = { pointer in
    pointer?.assumingMemoryBound(to: (() -> Void).self).pointee()
}
#endif
