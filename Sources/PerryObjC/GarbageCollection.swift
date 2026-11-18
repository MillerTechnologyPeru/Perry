import CPerryObjC
import Glibc

// Objective-C garbage collection's API, from Mac OS X 10.5 to 10.7, for
// programs built to run with the collector (Xcode 3's, Interface Builder's).
// There is no collector here: the collector is off, as objc_collectingEnabled
// says, so code built for both modes manages memory by reference counts, and
// the write barriers the compiler puts in stores of object pointers are plain
// stores. Weak references don't zero.

/// Whether the collector runs: never.
@c(_objc_collectingEnabled)
public func objc_collectingEnabled() -> Bool { false }

@c(_objc_collecting_enabled)
public func objc_collecting_enabled() -> Bool { false }

/// A store of an object pointer into memory the collector would scan.
@c(_objc_assign_strongCast)
public func objc_assign_strongCast(_ value: UnsafeMutableRawPointer?, _ destination: UnsafeMutablePointer<UnsafeMutableRawPointer?>?)
    -> UnsafeMutableRawPointer? {
    destination?.pointee = value
    return value
}

/// A store of an object pointer into a global variable.
@c(_objc_assign_global)
public func objc_assign_global(_ value: UnsafeMutableRawPointer?, _ destination: UnsafeMutablePointer<UnsafeMutableRawPointer?>?)
    -> UnsafeMutableRawPointer? {
    destination?.pointee = value
    return value
}

/// A store of an object pointer into a thread-local variable.
@c(_objc_assign_threadlocal)
public func objc_assign_threadlocal(_ value: UnsafeMutableRawPointer?, _ destination: UnsafeMutablePointer<UnsafeMutableRawPointer?>?)
    -> UnsafeMutableRawPointer? {
    destination?.pointee = value
    return value
}

/// A store of an object pointer into an instance variable, at `offset` in
/// the object.
@c(_objc_assign_ivar)
public func objc_assign_ivar(_ value: UnsafeMutableRawPointer?, _ base: UnsafeMutableRawPointer?, _ offset: Int)
    -> UnsafeMutableRawPointer? {
    base?.storeBytes(of: value, toByteOffset: offset, as: UnsafeMutableRawPointer?.self)
    return value
}

/// A store into a __weak variable, which doesn't zero here.
@c(_objc_assign_weak)
public func objc_assign_weak(_ value: UnsafeMutableRawPointer?, _ destination: UnsafeMutablePointer<UnsafeMutableRawPointer?>?)
    -> UnsafeMutableRawPointer? {
    destination?.pointee = value
    return value
}

@c(_objc_read_weak)
public func objc_read_weak(_ location: UnsafeMutablePointer<UnsafeMutableRawPointer?>?) -> UnsafeMutableRawPointer? {
    location?.pointee
}

@c(_objc_memmove_collectable)
public func objc_memmove_collectable(_ destination: UnsafeMutableRawPointer?, _ source: UnsafeRawPointer?, _ size: Int)
    -> UnsafeMutableRawPointer? {
    guard let destination, let source else { return destination }
    return memmove(destination, source, size)
}

// The atomic stores with a write barrier: compare-and-swap.

private func compareAndSwap(_ expected: UnsafeMutableRawPointer?, _ replacement: UnsafeMutableRawPointer?,
                            _ location: UnsafeMutablePointer<UnsafeMutableRawPointer?>?) -> Bool {
    guard let location else { return false }
    return perry_compare_and_swap(location, expected, replacement)
}

@c(_objc_atomicCompareAndSwapPtr)
public func objc_atomicCompareAndSwapPtr(_ expected: UnsafeMutableRawPointer?, _ replacement: UnsafeMutableRawPointer?,
                                         _ location: UnsafeMutablePointer<UnsafeMutableRawPointer?>?) -> Bool {
    compareAndSwap(expected, replacement, location)
}

@c(_objc_atomicCompareAndSwapPtrBarrier)
public func objc_atomicCompareAndSwapPtrBarrier(_ expected: UnsafeMutableRawPointer?, _ replacement: UnsafeMutableRawPointer?,
                                                _ location: UnsafeMutablePointer<UnsafeMutableRawPointer?>?) -> Bool {
    compareAndSwap(expected, replacement, location)
}

@c(_objc_atomicCompareAndSwapGlobal)
public func objc_atomicCompareAndSwapGlobal(_ expected: UnsafeMutableRawPointer?, _ replacement: UnsafeMutableRawPointer?,
                                            _ location: UnsafeMutablePointer<UnsafeMutableRawPointer?>?) -> Bool {
    compareAndSwap(expected, replacement, location)
}

@c(_objc_atomicCompareAndSwapGlobalBarrier)
public func objc_atomicCompareAndSwapGlobalBarrier(_ expected: UnsafeMutableRawPointer?, _ replacement: UnsafeMutableRawPointer?,
                                                   _ location: UnsafeMutablePointer<UnsafeMutableRawPointer?>?) -> Bool {
    compareAndSwap(expected, replacement, location)
}

@c(_objc_atomicCompareAndSwapInstanceVariable)
public func objc_atomicCompareAndSwapInstanceVariable(_ expected: UnsafeMutableRawPointer?, _ replacement: UnsafeMutableRawPointer?,
                                                      _ location: UnsafeMutablePointer<UnsafeMutableRawPointer?>?) -> Bool {
    compareAndSwap(expected, replacement, location)
}

@c(_objc_atomicCompareAndSwapInstanceVariableBarrier)
public func objc_atomicCompareAndSwapInstanceVariableBarrier(_ expected: UnsafeMutableRawPointer?,
                                                             _ replacement: UnsafeMutableRawPointer?,
                                                             _ location: UnsafeMutablePointer<UnsafeMutableRawPointer?>?) -> Bool {
    compareAndSwap(expected, replacement, location)
}

// The collector's controls, which have nothing to control.

@c(_objc_clear_stack)
public func objc_clear_stack(_ options: UInt) {}

@c(_objc_collect)
public func objc_collect(_ options: UInt) {}

@c(_objc_collect_if_needed)
public func objc_collect_if_needed(_ options: UInt) {}

@c(_objc_startCollectorThread)
public func objc_startCollectorThread() {}

@c(_objc_registerThreadWithCollector)
public func objc_registerThreadWithCollector() {}

@c(_objc_unregisterThreadWithCollector)
public func objc_unregisterThreadWithCollector() {}

@c(_objc_setCollectionThreshold)
public func objc_setCollectionThreshold(_ threshold: Int) {}

@c(_objc_setCollectionRatio)
public func objc_setCollectionRatio(_ ratio: Int) {}

/// Whether the collector has finalized an object: never.
@c(_objc_is_finalized)
public func objc_is_finalized(_ pointer: UnsafeMutableRawPointer?) -> Bool { false }
