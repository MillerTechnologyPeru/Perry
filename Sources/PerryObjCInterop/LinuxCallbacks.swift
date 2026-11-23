import Glibc

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

/// What Linux code calls for `function`, Darwin code whose arguments are
/// words (a block's invoke, a work function or callback a program passed).
///
/// On ppc a Darwin function saves its return address in its caller's frame,
/// at 8(r1), where Linux code keeps its own registers, and may change r2,
/// Linux's thread pointer: so the loader gives a stub that calls it from a
/// frame laid out as a Darwin caller's, keeping r2. Linux code, and every
/// function elsewhere, is returned as it is.
@inline(__always)
public func darwinCallable<Function>(_ function: Function) -> Function {
#if arch(powerpc)
    guard let callable = PPCCallables.callable else { return function }
    return unsafeBitCast(callable(unsafeBitCast(function, to: UnsafeMutableRawPointer.self)), to: Function.self)
#else
    return function
#endif
}

#if arch(powerpc)
private enum PPCCallables {
    // The loader's, which perry exports: RTLD_DEFAULT finds it.
    nonisolated(unsafe) static let callable = dlsym(nil, "perry_ppc_linux_callable").map {
        unsafeBitCast($0, to: (@convention(c) (UnsafeMutableRawPointer) -> UnsafeMutableRawPointer).self)
    }
}
#endif
