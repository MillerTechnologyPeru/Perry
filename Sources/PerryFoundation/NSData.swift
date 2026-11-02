import CPerryFoundation
import FoundationEssentials
import Glibc
import PerryObjCInterop

/// An NSData's bytes. They live in a malloc'd buffer so -bytes and
/// -mutableBytes stay valid until the object changes length or is freed;
/// swift-foundation's Data is used for conversions.
final class DataStorage {
    private(set) var bytes: UnsafeMutableRawPointer?
    private(set) var count: Int
    private var capacity: Int
    /// dataWithBytesNoCopy: buffers the caller still owns.
    private let freeWhenDone: Bool

    init(copying source: UnsafeRawPointer?, count: Int) {
        self.count = count
        capacity = count
        freeWhenDone = true
        bytes = count > 0 ? malloc(count) : nil
        if let bytes, let source { memcpy(bytes, source, count) }
    }

    init(adopting buffer: UnsafeMutableRawPointer?, count: Int, freeWhenDone: Bool) {
        bytes = buffer
        self.count = count
        capacity = count
        self.freeWhenDone = freeWhenDone
    }

    convenience init(_ data: Data) {
        self.init(copying: nil, count: data.count)
        if let bytes { data.copyBytes(to: bytes.assumingMemoryBound(to: UInt8.self), count: data.count) }
    }

    deinit {
        if freeWhenDone { free(bytes) }
    }

    var data: Data {
        bytes.map { Data(bytes: $0, count: count) } ?? Data()
    }

    /// Resizes, zero-filling new bytes. Moves borrowed bytes into a buffer
    /// of its own first.
    func setCount(_ newCount: Int) {
        if newCount > capacity || !freeWhenDone {
            let newCapacity = max(newCount, capacity * 2, 16)
            let grown = malloc(newCapacity)!
            if let bytes { memcpy(grown, bytes, min(count, newCount)) }
            if freeWhenDone { free(bytes) }
            bytes = grown
            capacity = newCapacity
        }
        if newCount > count, let bytes {
            memset(bytes + count, 0, newCount - count)
        }
        count = newCount
    }

    func replace(location: Int, length: Int, with source: UnsafeRawPointer?, count replacementCount: Int) {
        let tail = count - location - length
        let oldCount = count
        if replacementCount > length { setCount(oldCount + replacementCount - length) }
        if let bytes {
            memmove(bytes + location + replacementCount, bytes + location + length, tail)
            if let source, replacementCount > 0 {
                memcpy(bytes + location, source, replacementCount)
            } else if replacementCount > 0 {
                memset(bytes + location, 0, replacementCount)
            }
        }
        if replacementCount < length { setCount(oldCount + replacementCount - length) }
    }
}

enum DataObjects {
    nonisolated(unsafe) static var dataClass: Class!
    nonisolated(unsafe) static var mutableClass: Class!

    static func storage(_ object: id?) -> DataStorage? {
        Storage.get(object, as: DataStorage.self)
    }

    static func data(_ object: id?) -> Data {
        storage(object)?.data ?? Data()
    }

    static func make(_ storage: DataStorage, cls: id? = nil) -> id? {
        guard let object = Storage.allocate(cls ?? UnsafeMutableRawPointer(dataClass)) else { return nil }
        Storage.set(object, storage)
        return object
    }

    static func autoreleased(_ data: Data, cls: id? = nil) -> id? {
        ObjC.autorelease(make(DataStorage(data), cls: cls))
    }

    static func initialize(_ object: id?, _ storage: DataStorage) -> id? {
        if let object { Storage.set(object, storage) }
        return object
    }

    /// Foundation's description: {length = 2, bytes = 0x6869}. Data over
    /// 24 bytes shows its first 16 and last 8 bytes in groups of four:
    /// {length = 40, bytes = 0x00010203 … 0c0d0e0f ... 20212223 24252627 }.
    static func description(_ data: Data) -> String {
        let bytes = Array(data)
        func hex(_ slice: ArraySlice<UInt8>) -> String {
            slice.map { byte in
                let digits = String(byte, radix: 16)
                return (digits.count == 1 ? "0" : "") + digits
            }.joined()
        }
        func grouped(_ slice: ArraySlice<UInt8>) -> String {
            stride(from: slice.startIndex, to: slice.endIndex, by: 4)
                .map { hex(slice[$0..<min($0 + 4, slice.endIndex)]) }
                .joined(separator: " ")
        }
        let shown = bytes.count > 24
            ? grouped(bytes[0..<16]) + " ... " + grouped(bytes[(bytes.count - 8)...]) + " "
            : hex(bytes[...])
        return "{length = \(bytes.count), bytes = 0x\(shown)}"
    }

    static func install(superclass: Class) {
        dataClass = NSData.defineObjCClass(NSObject.registerObjCCategoryStorageAllocated).storage
        mutableClass = NSMutableData.defineObjCClass().storage
    }

    /// A new NSData wrapped for returning, +1.
    static func owned(_ storage: DataStorage, cls: ObjCClass? = nil) -> NSData {
        NSData(objCOwned: make(storage, cls: cls?.pointer))
    }
}

/// NSDataBase64EncodingOptions: line length and line ending flags.
private func base64(_ data: Data, options: UInt) -> String {
    var swiftOptions: Data.Base64EncodingOptions = []
    if options & 1 != 0 { swiftOptions.insert(.lineLength64Characters) }
    if options & 2 != 0 { swiftOptions.insert(.lineLength76Characters) }
    if options & 16 != 0 { swiftOptions.insert(.endLineWithCarriageReturn) }
    if options & 32 != 0 { swiftOptions.insert(.endLineWithLineFeed) }
    return data.base64EncodedString(options: swiftOptions)
}

/// NSData.
@ObjCClass("NSData")
public class NSData: NSObject {
    var data: Data { DataObjects.data(objcObject) }
    private var storage: DataStorage? { DataObjects.storage(objcObject) }

    private func setStorage(_ storage: DataStorage) -> Self {
        Storage.set(objcObject, storage)
        return self
    }

    // MARK: Creating

    @ObjCClassMethod("data")
    static func empty(_ cls: ObjCClass) -> NSData { DataObjects.owned(DataStorage(Data()), cls: cls) }

    @ObjCClassMethod("dataWithBytes:length:")
    static func data(_ cls: ObjCClass, bytes: UnsafeRawPointer?, length: UInt) -> NSData {
        DataObjects.owned(DataStorage(copying: bytes, count: Int(length)), cls: cls)
    }

    @ObjCClassMethod("dataWithBytesNoCopy:length:")
    static func data(_ cls: ObjCClass, noCopy bytes: UnsafeMutableRawPointer?, length: UInt) -> NSData {
        DataObjects.owned(DataStorage(adopting: bytes, count: Int(length), freeWhenDone: true), cls: cls)
    }

    @ObjCClassMethod("dataWithBytesNoCopy:length:freeWhenDone:")
    static func data(_ cls: ObjCClass, noCopy bytes: UnsafeMutableRawPointer?, length: UInt, freeWhenDone: Bool) -> NSData {
        DataObjects.owned(DataStorage(adopting: bytes, count: Int(length), freeWhenDone: freeWhenDone), cls: cls)
    }

    @ObjCClassMethod("dataWithData:")
    static func data(_ cls: ObjCClass, data other: NSData) -> NSData { DataObjects.owned(DataStorage(other.data), cls: cls) }

    @ObjCClassMethod("dataWithContentsOfFile:")
    static func data(_ cls: ObjCClass, contentsOfFile path: String) -> NSData? {
        (try? Data(contentsOf: URL(filePath: path))).map { DataObjects.owned(DataStorage($0), cls: cls) }
    }

    @ObjCClassMethod("dataWithContentsOfURL:")
    static func data(_ cls: ObjCClass, contentsOfURL url: NSURL) -> NSData? {
        guard url.url.isFileURL else { return nil }
        return (try? Data(contentsOf: url.url)).map { DataObjects.owned(DataStorage($0), cls: cls) }
    }

    @ObjCMethod("init")
    func initialize() -> Self { setStorage(DataStorage(copying: nil, count: 0)) }

    @ObjCMethod("initWithBytes:length:")
    func initialize(bytes: UnsafeRawPointer?, length: UInt) -> Self {
        setStorage(DataStorage(copying: bytes, count: Int(length)))
    }

    @ObjCMethod("initWithBytesNoCopy:length:freeWhenDone:")
    func initialize(noCopy bytes: UnsafeMutableRawPointer?, length: UInt, freeWhenDone: Bool) -> Self {
        setStorage(DataStorage(adopting: bytes, count: Int(length), freeWhenDone: freeWhenDone))
    }

    @ObjCMethod("initWithData:")
    func initialize(data other: NSData) -> Self { setStorage(DataStorage(other.data)) }

    @ObjCMethod("initWithContentsOfFile:")
    func initialize(contentsOfFile path: String) -> Self? {
        (try? Data(contentsOf: URL(filePath: path))).map { setStorage(DataStorage($0)) }
    }

    /// NSDataBase64DecodingOptions: 1 ignores unknown characters.
    @ObjCMethod("initWithBase64EncodedString:options:")
    func initialize(base64 string: String, options: UInt) -> Self? {
        Data(base64Encoded: string, options: options & 1 != 0 ? .ignoreUnknownCharacters : [])
            .map { setStorage(DataStorage($0)) }
    }

    @ObjCMethod("dealloc")
    func dealloc() {
        Storage.set(objcObject, nil)
        ObjC.superDealloc(objcObject, from: DataObjects.dataClass)
    }

    // MARK: Contents

    @ObjCMethod("length")
    func length() -> UInt { UInt(storage?.count ?? 0) }

    @ObjCMethod("bytes")
    func bytes() -> UnsafeRawPointer? { UnsafeRawPointer(storage?.bytes) }

    @ObjCMethod("getBytes:length:")
    func getBytes(_ buffer: UnsafeMutableRawPointer, length: UInt) {
        guard let storage, let bytes = storage.bytes else { return }
        memcpy(buffer, bytes, min(Int(length), storage.count))
    }

    @ObjCMethod("getBytes:range:")
    func getBytes(_ buffer: UnsafeMutableRawPointer, range: NSRange) {
        guard let storage, let bytes = storage.bytes else { return }
        guard Int(range.location + range.length) <= storage.count else {
            foundationFatal("-[NSData getBytes:range:]: range {\(range.location), \(range.length)} exceeds data length \(storage.count)")
        }
        memcpy(buffer, bytes + Int(range.location), Int(range.length))
    }

    @ObjCMethod("subdataWithRange:")
    func subdata(range: NSRange) -> NSData {
        let data = data
        guard Int(range.location + range.length) <= data.count else {
            foundationFatal("-[NSData subdataWithRange:]: range {\(range.location), \(range.length)} exceeds data length \(data.count)")
        }
        return DataObjects.owned(DataStorage(data.subdata(in: Int(range.location)..<Int(range.location + range.length))))
    }

    @ObjCMethod("isEqualToData:")
    func isEqual(toData other: NSData?) -> Bool { other?.data == data }

    @ObjCMethod("isEqual:")
    func isEqual(_ other: ObjCObject?) -> Bool {
        guard let other else { return false }
        return other.id == objcObject || (other.is(NSData.self) && isEqual(toData: other.unsafeCast(to: NSData.self)))
    }

    @ObjCMethod("hash")
    func hash() -> UInt { UInt(bitPattern: data.hashValue) }

    @ObjCMethod("description")
    func description() -> String { DataObjects.description(data) }

    @ObjCMethod("base64EncodedStringWithOptions:")
    func base64String(options: UInt) -> String { base64(data, options: options) }

    @ObjCMethod("base64EncodedDataWithOptions:")
    func base64Data(options: UInt) -> NSData { DataObjects.owned(DataStorage(Data(base64(data, options: options).utf8))) }

    // MARK: Writing

    @ObjCMethod("writeToFile:atomically:")
    func write(toFile path: String, atomically: Bool) -> Bool {
        (try? data.write(to: URL(filePath: path), options: atomically ? .atomic : [])) != nil
    }

    @ObjCMethod("writeToURL:atomically:")
    func write(toURL url: NSURL, atomically: Bool) -> Bool {
        url.url.isFileURL && (try? data.write(to: url.url, options: atomically ? .atomic : [])) != nil
    }

    // MARK: Copying

    @ObjCMethod("copyWithZone:")
    func copy(zone: UnsafeMutableRawPointer?) -> NSData { self }

    @ObjCMethod("mutableCopyWithZone:")
    func mutableCopy(zone: UnsafeMutableRawPointer?) -> NSData {
        DataObjects.owned(DataStorage(data), cls: ObjCClass(UnsafeMutableRawPointer(DataObjects.mutableClass)))
    }
}

/// NSMutableData.
@ObjCClass("NSMutableData")
public class NSMutableData: NSData {
    private var storage: DataStorage {
        guard let storage = DataObjects.storage(objcObject) else {
            foundationFatal("mutating method sent to an uninitialized NSMutableData")
        }
        return storage
    }

    @ObjCClassMethod("dataWithCapacity:")
    static func data(_ cls: ObjCClass, capacity: UInt) -> NSData { DataObjects.owned(DataStorage(Data()), cls: cls) }

    @ObjCClassMethod("dataWithLength:")
    static func data(_ cls: ObjCClass, length: UInt) -> NSData {
        DataObjects.owned(DataStorage(Data(count: Int(length))), cls: cls)
    }

    @ObjCMethod("initWithCapacity:")
    func initialize(capacity: UInt) -> Self {
        Storage.set(objcObject, DataStorage(copying: nil, count: 0))
        return self
    }

    @ObjCMethod("initWithLength:")
    func initialize(length: UInt) -> Self {
        Storage.set(objcObject, DataStorage(Data(count: Int(length))))
        return self
    }

    @ObjCMethod("copyWithZone:")
    override func copy(zone: UnsafeMutableRawPointer?) -> NSData { DataObjects.owned(DataStorage(storage.data)) }

    @ObjCMethod("mutableBytes")
    func mutableBytes() -> UnsafeMutableRawPointer? { storage.bytes }

    @ObjCMethod("setLength:")
    func setLength(_ length: UInt) { storage.setCount(Int(length)) }

    @ObjCMethod("increaseLengthBy:")
    func increaseLength(by extra: UInt) { storage.setCount(storage.count + Int(extra)) }

    @ObjCMethod("appendBytes:length:")
    func append(bytes: UnsafeRawPointer?, length: UInt) {
        storage.replace(location: storage.count, length: 0, with: bytes, count: Int(length))
    }

    @ObjCMethod("appendData:")
    func append(data other: NSData) {
        other.data.withUnsafeBytes { append(bytes: $0.baseAddress, length: UInt($0.count)) }
    }

    @ObjCMethod("replaceBytesInRange:withBytes:")
    func replace(range: NSRange, with bytes: UnsafeRawPointer?) {
        replace(range: range, with: bytes, length: range.length)
    }

    @ObjCMethod("replaceBytesInRange:withBytes:length:")
    func replace(range: NSRange, with bytes: UnsafeRawPointer?, length: UInt) {
        guard Int(range.location + range.length) <= storage.count else {
            foundationFatal("-[NSMutableData replaceBytesInRange:withBytes:]: range {\(range.location), \(range.length)} exceeds data length \(storage.count)")
        }
        storage.replace(location: Int(range.location), length: Int(range.length), with: bytes, count: Int(length))
    }

    @ObjCMethod("setData:")
    func set(data other: NSData) {
        other.data.withUnsafeBytes {
            storage.replace(location: 0, length: storage.count, with: $0.baseAddress, count: $0.count)
        }
    }
}

/// NSNull: one immortal instance, also exported as kCFNull.
enum Nulls {
    nonisolated(unsafe) static var null: id!

    static func install(superclass: Class) {
        let cls = NSNull.defineObjCClass(NSObject.registerObjCCategoryImmortal).markingStatic().storage
        null = ObjC.createInstance(cls, 0)
        perry_foundation_constant(PERRY_CONSTANT_kCFNull).pointee = null
    }
}

/// NSNull.
@ObjCClass("NSNull")
public final class NSNull: NSObject {
    @ObjCClassMethod("null") static func null() -> UnsafeMutableRawPointer? { Nulls.null }
    @ObjCClassMethod("alloc") static func alloc() -> UnsafeMutableRawPointer? { Nulls.null }
    @ObjCMethod("init") func initialize() -> Self { self }
    @ObjCMethod("description") func description() -> String { "<null>" }
    @ObjCMethod("copyWithZone:") func copy(zone: UnsafeMutableRawPointer?) -> NSNull { self }
}
