import GraphiteBase
import GraphiteTasks
import PerryObjCInterop

// Driver Services' and Open Transport's clock and atomic arithmetic, and
// Multiprocessing Services' memory and delays, over Graphite's
// AbsoluteTime, AtomicMemory and MPMemory. AbsoluteTime counts nanoseconds
// of the monotonic clock here, as mach_absolute_time does on Intel Macs.

/// AbsoluteTime DurationToAbsolute(Duration): positive milliseconds,
/// negative microseconds.
@DarwinC("_DurationToAbsolute")
public func DurationToAbsolute(_ duration: Int32) -> UInt64 {
    MacDuration(rawValue: duration).nanoseconds
}

/// AbsoluteTime AddDurationToAbsolute(Duration, AbsoluteTime). Its 64-bit
/// argument is in r4 and r5 on Darwin's ppc, where Linux's would be in r5
/// and r6 (@DarwinC).
@DarwinC("_AddDurationToAbsolute")
public func AddDurationToAbsolute(_ duration: Int32, _ absolute: UInt64) -> UInt64 {
    (AbsoluteTime(nanoseconds: absolute) + MacDuration(rawValue: duration)).nanoseconds
}

/// Boolean CompareAndSwap(UInt32 old, UInt32 new, UInt32 *address).
@c(_CompareAndSwap)
public func CompareAndSwap(_ old: UInt32, _ new: UInt32, _ address: UnsafeMutablePointer<UInt32>?) -> UInt8 {
    guard let address else { return 0 }
    return AtomicMemory.compareAndSwap(old, new, at: address) ? 1 : 0
}

/// SInt32 IncrementAtomic(SInt32 *): the value before.
@c(_IncrementAtomic)
public func IncrementAtomic(_ value: UnsafeMutablePointer<Int32>?) -> Int32 {
    guard let value else { return 0 }
    return AtomicMemory.increment(value)
}

/// SInt32 DecrementAtomic(SInt32 *): the value before.
@c(_DecrementAtomic)
public func DecrementAtomic(_ value: UnsafeMutablePointer<Int32>?) -> Int32 {
    guard let value else { return 0 }
    return AtomicMemory.decrement(value)
}

/// SInt32 OTAtomicAdd32(SInt32 amount, SInt32 *): the value after.
@c(_OTAtomicAdd32)
public func OTAtomicAdd32(_ amount: Int32, _ value: UnsafeMutablePointer<Int32>?) -> Int32 {
    guard let value else { return 0 }
    return AtomicMemory.add(amount, to: value)
}

/// SInt16 OTAtomicAdd16(SInt32 amount, SInt16 *): the value after.
@c(_OTAtomicAdd16)
public func OTAtomicAdd16(_ amount: Int32, _ value: UnsafeMutablePointer<Int16>?) -> Int16 {
    guard let value else { return 0 }
    return AtomicMemory.add(Int16(truncatingIfNeeded: amount), to: value)
}

/// LogicalAddress MPAllocateAligned(ByteCount size, UInt8 alignment,
/// MPOpaqueID options): kMPAllocateClearMask (4) zeroes it.
@c(_MPAllocateAligned)
public func MPAllocateAligned(_ size: Int, _ alignment: UInt8, _ options: UInt32) -> UnsafeMutableRawPointer? {
    MPMemory.allocate(size: size, alignmentLog2: alignment, clear: options & 0x4 != 0)
}

/// void MPFree(LogicalAddress).
@c(_MPFree)
public func MPFree(_ block: UnsafeMutableRawPointer?) {
    MPMemory.free(block)
}

/// OSStatus MPDelayUntil(AbsoluteTime *expirationTime).
@c(_MPDelayUntil)
public func MPDelayUntil(_ deadline: UnsafeRawPointer?) -> Int32 {
    guard let deadline else { return MacError.parameter.status }
    delay(until: AbsoluteTime(nanoseconds: deadline.loadUnaligned(as: UInt64.self)))
    return 0
}
