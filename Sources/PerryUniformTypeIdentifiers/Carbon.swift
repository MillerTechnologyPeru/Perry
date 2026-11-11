import Glibc
import PerryObjCInterop

// Mac apps' alone: armv7 runs only iOS apps, so it has none of this.
#if !arch(arm)
// The rest of CoreServices' Carbon utilities that older Mac programs call:
// the math functions that SDKs before 10.7 bound through CoreServices (its
// vecLib), the Memory Manager's pointers, Launch Services' display names,
// and the Time Manager's clock.

@ObjCWrapper("NSURL")
class DisplayNameURL: NSObject {
    @ObjCMethod("path") func path() -> String?
}

// MARK: - Math

@c(_exp2) public func darwinExp2(_ x: Double) -> Double { exp2(x) }
@c(_exp2f) public func darwinExp2f(_ x: Float) -> Float { exp2f(x) }
@c(_fmax) public func darwinFmax(_ x: Double, _ y: Double) -> Double { fmax(x, y) }
@c(_fmin) public func darwinFmin(_ x: Double, _ y: Double) -> Double { fmin(x, y) }
@c(_fmaxf) public func darwinFmaxf(_ x: Float, _ y: Float) -> Float { fmaxf(x, y) }
@c(_fminf) public func darwinFminf(_ x: Float, _ y: Float) -> Float { fminf(x, y) }
@c(_nextafterf) public func darwinNextafterf(_ x: Float, _ y: Float) -> Float { nextafterf(x, y) }
@c(_nextafter) public func darwinNextafter(_ x: Double, _ y: Double) -> Double { nextafter(x, y) }

// MARK: - Memory Manager

/// Ptr NewPtr(Size), NewPtrClear and DisposePtr: blocks from malloc, which
/// MemError reports on (memFullErr when one couldn't be had).
nonisolated(unsafe) private var lastMemoryError: Int16 = 0

@c(_NewPtr)
public func NewPtr(_ size: Int) -> UnsafeMutableRawPointer? {
    let block = malloc(max(size, 1))
    lastMemoryError = block == nil ? -108 : 0
    return block
}

@c(_NewPtrClear)
public func NewPtrClear(_ size: Int) -> UnsafeMutableRawPointer? {
    let block = calloc(1, max(size, 1))
    lastMemoryError = block == nil ? -108 : 0
    return block
}

@c(_DisposePtr)
public func DisposePtr(_ block: UnsafeMutableRawPointer?) {
    free(block)
    lastMemoryError = 0
}

@c(_MemError) public func MemError() -> Int16 { lastMemoryError }

// MARK: - Bits

/// BitTst, BitSet and BitClr number bits from the high bit of the first
/// byte, as 68K's did.
@c(_BitTst)
public func BitTst(_ bytes: UnsafeRawPointer?, _ bit: Int) -> UInt8 {
    guard let bytes else { return 0 }
    return bytes.load(fromByteOffset: bit >> 3, as: UInt8.self) & (0x80 >> UInt8(bit & 7)) != 0 ? 1 : 0
}

@c(_BitSet)
public func BitSet(_ bytes: UnsafeMutableRawPointer?, _ bit: Int) {
    guard let bytes else { return }
    let byte = bytes.load(fromByteOffset: bit >> 3, as: UInt8.self)
    bytes.storeBytes(of: byte | (0x80 >> UInt8(bit & 7)), toByteOffset: bit >> 3, as: UInt8.self)
}

@c(_BitClr)
public func BitClr(_ bytes: UnsafeMutableRawPointer?, _ bit: Int) {
    guard let bytes else { return }
    let byte = bytes.load(fromByteOffset: bit >> 3, as: UInt8.self)
    bytes.storeBytes(of: byte & ~(0x80 >> UInt8(bit & 7)), toByteOffset: bit >> 3, as: UInt8.self)
}

// MARK: - Launch Services

/// OSStatus LSCopyDisplayNameForURL(CFURLRef, CFStringRef *): the item's
/// name as Finder shows it, without an app's ".app".
@c(_LSCopyDisplayNameForURL)
public func LSCopyDisplayNameForURL(_ url: UnsafeMutableRawPointer?, _ name: UnsafeMutablePointer<UnsafeMutableRawPointer?>?) -> Int32 {
    guard let url, let name else { return -50 }
    name.pointee = nil
    guard let path = DisplayNameURL(url).path() else { return -43 }
    var leaf = String(path.split(separator: "/").last ?? "/")
    if leaf.hasSuffix(".app") { leaf.removeLast(4) }
    name.pointee = NSObject.string(leaf).objCOwnedReturnValue()
    return 0
}

// MARK: - Time Manager

/// AbsoluteTime UpTime(void): nanoseconds since boot, as an UnsignedWide
/// (on Intel, low word first: a UInt64), which AbsoluteToDuration turns to milliseconds
/// (positive) or, for under one, negative microseconds.
@c(_UpTime)
public func UpTime() -> UInt64 {
    var time = timespec()
    clock_gettime(CLOCK_MONOTONIC, &time)
    return UInt64(time.tv_sec) * 1_000_000_000 + UInt64(time.tv_nsec)
}

@c(_AbsoluteToDuration)
public func AbsoluteToDuration(_ time: UInt64) -> Int32 {
    if time >= 1_000_000 { return Int32(clamping: time / 1_000_000) }
    return -Int32(clamping: time / 1_000)
}
#endif
