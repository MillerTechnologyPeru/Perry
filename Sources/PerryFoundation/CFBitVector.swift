import CPerryFoundation
import FoundationEssentials
import PerryObjCInterop

// CFBitVector: bits, numbered from the most significant bit of the first
// byte, as CoreFoundation stores them.

final class BitVectorStorage {
    var bits: [Bool] = []

    func range(_ range: CFRange) -> Range<Int> {
        let start = max(0, min(range.location, bits.count))
        return start..<max(start, min(range.location + range.length, bits.count))
    }
}

enum BitVectors {
    nonisolated(unsafe) static var vectorClass: Class!

    static func storage(_ vector: id?) -> BitVectorStorage? { Storage.get(vector, as: BitVectorStorage.self) }

    static func make(_ bits: [Bool]) -> id? {
        guard let object = Storage.allocate(UnsafeMutableRawPointer(vectorClass)) else { return nil }
        let storage = BitVectorStorage()
        storage.bits = bits
        Storage.set(object, storage)
        return object
    }
}

@ObjCClass("__NSCFBitVector")
final class NSCFBitVector: NSObject {
    override class func didDefineObjCClass(_ cls: ObjCClass) {
        NSObject.registerObjCCategoryStorageAllocated(cls)
        BitVectors.vectorClass = cls.storage
    }

    @ObjCMethod("dealloc")
    func dealloc() {
        Storage.set(objcObject, nil)
        ObjC.superDealloc(objcObject, from: BitVectors.vectorClass)
    }

    @ObjCMethod("_cfTypeID") func cfTypeID() -> UInt { 24 }

    @ObjCMethod("isEqual:")
    func isEqual(_ other: UnsafeMutableRawPointer?) -> Bool {
        guard let mine = BitVectors.storage(objcObject), let theirs = BitVectors.storage(other) else { return false }
        return mine.bits == theirs.bits
    }

    @ObjCMethod("hash") func hash() -> UInt { UInt(BitVectors.storage(objcObject)?.bits.count ?? 0) }
}

@c(_CFBitVectorGetTypeID) public func CFBitVectorGetTypeID() -> UInt { 24 }

/// A vector of `count` bits from `bytes`, the first bit the first byte's
/// most significant.
@c(_CFBitVectorCreate)
public func CFBitVectorCreate(_ allocator: UnsafeRawPointer?, _ bytes: UnsafePointer<UInt8>?, _ count: Int) -> id? {
    let bits = (0..<max(count, 0)).map { index in bytes.map { $0[index / 8] & (0x80 >> UInt8(index % 8)) != 0 } ?? false }
    return BitVectors.make(bits)
}

@c(_CFBitVectorCreateCopy)
public func CFBitVectorCreateCopy(_ allocator: UnsafeRawPointer?, _ vector: id?) -> id? {
    BitVectors.storage(vector).flatMap { BitVectors.make($0.bits) }
}

@c(_CFBitVectorCreateMutable)
public func CFBitVectorCreateMutable(_ allocator: UnsafeRawPointer?, _ capacity: Int) -> id? { BitVectors.make([]) }

@c(_CFBitVectorCreateMutableCopy)
public func CFBitVectorCreateMutableCopy(_ allocator: UnsafeRawPointer?, _ capacity: Int, _ vector: id?) -> id? {
    CFBitVectorCreateCopy(allocator, vector)
}

@c(_CFBitVectorGetCount) public func CFBitVectorGetCount(_ vector: id?) -> Int { BitVectors.storage(vector)?.bits.count ?? 0 }

@c(_CFBitVectorGetCountOfBit)
public func CFBitVectorGetCountOfBit(_ vector: id?, _ range: CFRange, _ bit: UInt32) -> Int {
    guard let storage = BitVectors.storage(vector) else { return 0 }
    return storage.bits[storage.range(range)].filter { $0 == (bit != 0) }.count
}

@c(_CFBitVectorContainsBit)
public func CFBitVectorContainsBit(_ vector: id?, _ range: CFRange, _ bit: UInt32) -> Bool {
    CFBitVectorGetCountOfBit(vector, range, bit) > 0
}

@c(_CFBitVectorGetBitAtIndex)
public func CFBitVectorGetBitAtIndex(_ vector: id?, _ index: Int) -> UInt32 {
    guard let bits = BitVectors.storage(vector)?.bits, bits.indices.contains(index) else { return 0 }
    return bits[index] ? 1 : 0
}

/// The bits in `range`, packed into `bytes` from the first byte's most
/// significant bit.
@c(_CFBitVectorGetBits)
public func CFBitVectorGetBits(_ vector: id?, _ range: CFRange, _ bytes: UnsafeMutablePointer<UInt8>?) {
    guard let bytes, let storage = BitVectors.storage(vector) else { return }
    let bits = Array(storage.bits[storage.range(range)])
    for index in 0..<(bits.count + 7) / 8 { bytes[index] = 0 }
    for (index, bit) in bits.enumerated() where bit { bytes[index / 8] |= 0x80 >> UInt8(index % 8) }
}

@c(_CFBitVectorGetFirstIndexOfBit)
public func CFBitVectorGetFirstIndexOfBit(_ vector: id?, _ range: CFRange, _ bit: UInt32) -> Int {
    guard let storage = BitVectors.storage(vector) else { return -1 }
    return storage.range(range).first { storage.bits[$0] == (bit != 0) } ?? -1
}

@c(_CFBitVectorGetLastIndexOfBit)
public func CFBitVectorGetLastIndexOfBit(_ vector: id?, _ range: CFRange, _ bit: UInt32) -> Int {
    guard let storage = BitVectors.storage(vector) else { return -1 }
    return storage.range(range).last { storage.bits[$0] == (bit != 0) } ?? -1
}

/// Grows with zero bits, or drops the last.
@c(_CFBitVectorSetCount)
public func CFBitVectorSetCount(_ vector: id?, _ count: Int) {
    guard let storage = BitVectors.storage(vector) else { return }
    let count = max(count, 0)
    if count < storage.bits.count {
        storage.bits.removeLast(storage.bits.count - count)
    } else {
        storage.bits += Array(repeating: false, count: count - storage.bits.count)
    }
}

@c(_CFBitVectorFlipBitAtIndex)
public func CFBitVectorFlipBitAtIndex(_ vector: id?, _ index: Int) {
    guard let storage = BitVectors.storage(vector), storage.bits.indices.contains(index) else { return }
    storage.bits[index].toggle()
}

@c(_CFBitVectorFlipBits)
public func CFBitVectorFlipBits(_ vector: id?, _ range: CFRange) {
    guard let storage = BitVectors.storage(vector) else { return }
    for index in storage.range(range) { storage.bits[index].toggle() }
}

@c(_CFBitVectorSetBitAtIndex)
public func CFBitVectorSetBitAtIndex(_ vector: id?, _ index: Int, _ bit: UInt32) {
    guard let storage = BitVectors.storage(vector), storage.bits.indices.contains(index) else { return }
    storage.bits[index] = bit != 0
}

@c(_CFBitVectorSetBits)
public func CFBitVectorSetBits(_ vector: id?, _ range: CFRange, _ bit: UInt32) {
    guard let storage = BitVectors.storage(vector) else { return }
    for index in storage.range(range) { storage.bits[index] = bit != 0 }
}

@c(_CFBitVectorSetAllBits)
public func CFBitVectorSetAllBits(_ vector: id?, _ bit: UInt32) {
    guard let storage = BitVectors.storage(vector) else { return }
    storage.bits = Array(repeating: bit != 0, count: storage.bits.count)
}
