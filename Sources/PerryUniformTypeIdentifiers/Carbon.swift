import Glibc
import PerryObjCInterop

// Mac apps' alone: armv7 runs only iOS apps, so it has none of this.
#if !arch(arm)
// The rest of CoreServices' Carbon utilities that older Mac programs call:
// the math functions that SDKs before 10.7 bound through CoreServices (its
// vecLib), the Memory Manager's pointers and handles, the Code Fragment
// Manager's lookups (which find nothing), Launch Services' display names,
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

/// A Handle: a pointer to a master pointer, the block's address, which the
/// block's size follows. Blocks never move, so locking changes nothing;
/// temporary memory is the same memory.
private struct MasterPointer {
    var block: UnsafeMutableRawPointer?
    var size: Int
}

private func newHandle(_ size: Int, clear: Bool) -> UnsafeMutablePointer<MasterPointer>? {
    guard size >= 0, let block = clear ? calloc(1, max(size, 1)) : malloc(max(size, 1)) else {
        lastMemoryError = -108                                  // memFullErr
        return nil
    }
    let handle = UnsafeMutablePointer<MasterPointer>.allocate(capacity: 1)
    handle.initialize(to: MasterPointer(block: block, size: size))
    lastMemoryError = 0
    return handle
}

private func master(_ handle: UnsafeMutableRawPointer?) -> UnsafeMutablePointer<MasterPointer>? {
    handle?.assumingMemoryBound(to: MasterPointer.self)
}

@c(_NewHandle)
public func NewHandle(_ size: Int) -> UnsafeMutableRawPointer? { newHandle(size, clear: false).map(UnsafeMutableRawPointer.init) }

@c(_NewHandleClear)
public func NewHandleClear(_ size: Int) -> UnsafeMutableRawPointer? { newHandle(size, clear: true).map(UnsafeMutableRawPointer.init) }

/// Handle TempNewHandle(Size, OSErr *resultCode).
@c(_TempNewHandle)
public func TempNewHandle(_ size: Int, _ result: UnsafeMutablePointer<Int16>?) -> UnsafeMutableRawPointer? {
    let handle = newHandle(size, clear: false)
    result?.pointee = lastMemoryError
    return handle.map(UnsafeMutableRawPointer.init)
}

@c(_DisposeHandle)
public func DisposeHandle(_ handle: UnsafeMutableRawPointer?) {
    lastMemoryError = 0
    guard let handle = master(handle) else { return }
    free(handle.pointee.block)
    handle.deinitialize(count: 1)
    handle.deallocate()
}

@c(_TempDisposeHandle)
public func TempDisposeHandle(_ handle: UnsafeMutableRawPointer?, _ result: UnsafeMutablePointer<Int16>?) {
    DisposeHandle(handle)
    result?.pointee = 0
}

@c(_HLock) public func HLock(_ handle: UnsafeMutableRawPointer?) { lastMemoryError = handle == nil ? -109 : 0 }      // nilHandleErr
@c(_HUnlock) public func HUnlock(_ handle: UnsafeMutableRawPointer?) { lastMemoryError = handle == nil ? -109 : 0 }
@c(_HLockHi) public func HLockHi(_ handle: UnsafeMutableRawPointer?) { HLock(handle) }

@c(_TempHLock)
public func TempHLock(_ handle: UnsafeMutableRawPointer?, _ result: UnsafeMutablePointer<Int16>?) {
    HLock(handle)
    result?.pointee = lastMemoryError
}

@c(_TempHUnlock)
public func TempHUnlock(_ handle: UnsafeMutableRawPointer?, _ result: UnsafeMutablePointer<Int16>?) {
    HUnlock(handle)
    result?.pointee = lastMemoryError
}

@c(_GetHandleSize)
public func GetHandleSize(_ handle: UnsafeMutableRawPointer?) -> Int {
    guard let handle = master(handle) else {
        lastMemoryError = -109
        return 0
    }
    lastMemoryError = 0
    return handle.pointee.size
}

/// void SetHandleSize(Handle, Size): the block grown or shrunk, its master
/// pointer moved to wherever it now is.
@c(_SetHandleSize)
public func SetHandleSize(_ handle: UnsafeMutableRawPointer?, _ size: Int) {
    guard let handle = master(handle), size >= 0 else {
        lastMemoryError = handle == nil ? -109 : -50
        return
    }
    guard let block = realloc(handle.pointee.block, max(size, 1)) else {
        lastMemoryError = -108
        return
    }
    handle.pointee = MasterPointer(block: block, size: size)
    lastMemoryError = 0
}

/// Size MaxBlock(void): the largest block that could be had, for programs
/// sizing their buffers by it: 64 MB, which malloc gives as it's used.
@c(_MaxBlock) public func MaxBlock() -> Int { 64 << 20 }

// MARK: - Code Fragment Manager

/// OSErr GetSharedLibrary(ConstStr63Param, CFragArchitecture,
/// CFragLoadOptions, CFragConnectionID *, Ptr *mainAddr, Str255 errName):
/// no code fragments are found here, cfragNoLibraryErr; programs fall back
/// to what they link.
@c(_GetSharedLibrary)
public func GetSharedLibrary(_ name: UnsafeRawPointer?, _ architecture: UInt32, _ options: UInt32,
                             _ connection: UnsafeMutablePointer<UnsafeMutableRawPointer?>?,
                             _ mainAddress: UnsafeMutablePointer<UnsafeMutableRawPointer?>?,
                             _ errorName: UnsafeMutablePointer<UInt8>?) -> Int16 {
    connection?.pointee = nil
    mainAddress?.pointee = nil
    errorName?.pointee = 0
    return -2804
}

/// OSErr FindSymbol(CFragConnectionID, ConstStr255Param, Ptr *,
/// CFragSymbolClass *): cfragNoSymbolErr, there being no fragments.
@c(_FindSymbol)
public func FindSymbol(_ connection: UnsafeMutableRawPointer?, _ name: UnsafeRawPointer?,
                       _ address: UnsafeMutablePointer<UnsafeMutableRawPointer?>?, _ symbolClass: UnsafeMutablePointer<UInt8>?) -> Int16 {
    address?.pointee = nil
    return -2802
}

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

/// AbsoluteTime and Nanoseconds are both nanoseconds here.
@c(_AbsoluteToNanoseconds) public func AbsoluteToNanoseconds(_ time: UInt64) -> UInt64 { time }
@c(_NanosecondsToAbsolute) public func NanosecondsToAbsolute(_ time: UInt64) -> UInt64 { time }

@c(_AbsoluteToDuration)
public func AbsoluteToDuration(_ time: UInt64) -> Int32 {
    if time >= 1_000_000 { return Int32(clamping: time / 1_000_000) }
    return -Int32(clamping: time / 1_000)
}
#endif
