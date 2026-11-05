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

    /// Empty, with a buffer of `capacity` bytes (16 at least) already
    /// there: CFDataCreateMutable's caller may write up to its capacity
    /// through CFDataGetMutableBytePtr before setting the length.
    init(reserving capacity: Int) {
        count = 0
        self.capacity = max(capacity, 16)
        freeWhenDone = true
        bytes = malloc(self.capacity)
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
        guard let object else { return Data() }
        // Another library's subclass, such as Swift's bridged Data, keeps its
        // own bytes, even when it was made with NSData's -init.
        let foreign = ObjC.overrides(object, Selectors.length, of: dataClass)
            && ObjC.overrides(object, Selectors.length, of: mutableClass)
        if !foreign { return storage(object)?.data ?? Data() }
        let length = Int(ObjC.sendUInt(object, Selectors.length))
        guard length > 0, let bytes = ObjC.sendPointer(object, Selectors.bytes) else { return Data() }
        return Data(bytes: bytes, count: length)
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
    /// What the Swift runtime asks to tell Foundation's classes apart.
    @ObjCMethod("isNSData__") func isNSData__() -> Bool { true }

    /// Set-up after the class is defined.
    override public class func didDefineObjCClass(_ cls: ObjCClass) {
        NSObject.registerObjCCategoryStorageAllocated(cls)
        DataObjects.dataClass = cls.storage
    }

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

    /// Nil makes empty data, as on Darwin.
    @ObjCClassMethod("dataWithData:")
    static func data(_ cls: ObjCClass, data other: NSData?) -> NSData { DataObjects.owned(DataStorage(other?.data ?? Data()), cls: cls) }

    @ObjCClassMethod("dataWithContentsOfFile:")
    static func data(_ cls: ObjCClass, contentsOfFile path: String?) -> NSData? {
        guard let path else { return nil }
        return (try? Data(contentsOf: URL(filePath: path))).map { DataObjects.owned(DataStorage($0), cls: cls) }
    }

    @ObjCClassMethod("dataWithContentsOfURL:")
    static func data(_ cls: ObjCClass, contentsOfURL url: NSURL?) -> NSData? {
        url.flatMap(contents).map { DataObjects.owned(DataStorage($0), cls: cls) }
    }

    /// NSDataReadingOptions only tune how the file is read (mapped,
    /// uncached), so they are ignored; a failure is NSFileReadNoSuchFileError
    /// (260) or NSFileReadUnknownError (256).
    @ObjCClassMethod("dataWithContentsOfFile:options:error:")
    static func data(_ cls: ObjCClass, contentsOfFile path: String?, options: UInt,
                     error: UnsafeMutablePointer<UnsafeMutableRawPointer?>?) -> NSData? {
        guard let path, let bytes = try? Data(contentsOf: URL(filePath: path)) else {
            error?.pointee = readError(path.map { access($0, F_OK) == 0 } ?? false)
            return nil
        }
        return DataObjects.owned(DataStorage(bytes), cls: cls)
    }

    @ObjCClassMethod("dataWithContentsOfURL:options:error:")
    static func data(_ cls: ObjCClass, contentsOfURL url: NSURL?, options: UInt,
                     error: UnsafeMutablePointer<UnsafeMutableRawPointer?>?) -> NSData? {
        guard let url, let bytes = contents(of: url) else {
            error?.pointee = readError(url.map { $0.url.isFileURL && access($0.url.path, F_OK) == 0 } ?? false)
            return nil
        }
        return DataObjects.owned(DataStorage(bytes), cls: cls)
    }

    static func readError(_ exists: Bool) -> UnsafeMutableRawPointer? {
        Errors.autoreleased(domain: Errors.cocoaDomain, code: exists ? 256 : 260, description: "The file couldn’t be opened.")
    }

    /// URLs read from local files instead, as an old app's servers are
    /// gone: PERRY_URL_MAP's URL=path pairs, separated by "|", each split
    /// at its last "=" (a URL's query can have them; a path seldom does).
    nonisolated(unsafe) static let urlMap: [String: String] = {
        guard let setting = getenv("PERRY_URL_MAP") else { return [:] }
        var map: [String: String] = [:]
        for entry in String(cString: setting).split(separator: "|") {
            guard let equals = entry.lastIndex(of: "=") else { continue }
            map[String(entry[..<equals])] = String(entry[entry.index(after: equals)...])
        }
        return map
    }()

    /// A file's bytes, or what NSURLConnection loads for other schemes,
    /// waiting for it as Darwin does; nil when CFNetwork is not loaded. A
    /// URL PERRY_URL_MAP maps is its file's bytes.
    static func contents(of url: NSURL) -> Data? {
        if let path = urlMap[url.url.absoluteString] {
            return try? Data(contentsOf: path.hasPrefix("file:") ? URL(string: path) ?? URL(filePath: path) : URL(filePath: path))
        }
        if url.url.isFileURL { return try? Data(contentsOf: url.url) }
        let requestClass = ObjC.getClass("NSURLRequest").map(UnsafeMutableRawPointer.init)
        let connectionClass = ObjC.getClass("NSURLConnection").map(UnsafeMutableRawPointer.init)
        guard let requestClass, let connectionClass,
              let request = ObjC.send(requestClass, ObjC.selector("requestWithURL:"), url.objcObject) else { return nil }
        // Without a response or error to return.
        typealias Send = @convention(c) (id?, SEL, id?, UnsafeMutableRawPointer?, UnsafeMutableRawPointer?) -> id?
        let selector = ObjC.selector("sendSynchronousRequest:returningResponse:error:")
        let result = ObjC.autoreleasepool {
            unsafeBitCast(ObjC.msgSend, to: Send.self)(connectionClass, selector, request, nil, nil).map(DataObjects.data)
        }
        return result
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
    func initialize(data other: NSData?) -> Self { setStorage(DataStorage(other?.data ?? Data())) }

    @ObjCMethod("initWithContentsOfFile:")
    func initialize(contentsOfFile path: String?) -> Self? {
        guard let path else { return nil }
        return (try? Data(contentsOf: URL(filePath: path))).map { setStorage(DataStorage($0)) }
    }

    @ObjCMethod("initWithContentsOfURL:")
    func initialize(contentsOfURL url: NSURL?) -> Self? { url.flatMap(NSData.contents).map { setStorage(DataStorage($0)) } }

    @ObjCMethod("initWithContentsOfFile:options:error:")
    func initialize(contentsOfFile path: String?, options: UInt, error: UnsafeMutablePointer<UnsafeMutableRawPointer?>?) -> Self? {
        guard let path, let bytes = try? Data(contentsOf: URL(filePath: path)) else {
            error?.pointee = NSData.readError(path.map { access($0, F_OK) == 0 } ?? false)
            return nil
        }
        return setStorage(DataStorage(bytes))
    }

    @ObjCMethod("initWithContentsOfURL:options:error:")
    func initialize(contentsOfURL url: NSURL?, options: UInt, error: UnsafeMutablePointer<UnsafeMutableRawPointer?>?) -> Self? {
        guard let url, let bytes = NSData.contents(of: url) else {
            error?.pointee = NSData.readError(url.map { $0.url.isFileURL && access($0.url.path, F_OK) == 0 } ?? false)
            return nil
        }
        return setStorage(DataStorage(bytes))
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

    /// All the bytes; deprecated, as the buffer's size can't be checked.
    @ObjCMethod("getBytes:")
    func getBytes(_ buffer: UnsafeMutableRawPointer) {
        guard let storage, let bytes = storage.bytes else { return }
        memcpy(buffer, bytes, storage.count)
    }

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

    /// NSDataSearchBackwards is 1, NSDataSearchAnchored 2; not found is
    /// {NSNotFound, 0}.
    @ObjCMethod("rangeOfData:options:range:")
    func range(of other: NSData, options: UInt, range: NSRange) -> NSRange {
        let data = data, needle = [UInt8](other.data)
        let start = Int(range.location), end = Int(range.location + range.length)
        guard end <= data.count else {
            foundationFatal("-[NSData rangeOfData:options:range:]: range {\(range.location), \(range.length)} exceeds data length \(data.count)")
        }
        let notFound = NSRange(location: Int.max, length: 0)
        guard !needle.isEmpty, needle.count <= end - start else { return notFound }
        let backwards = options & 1 != 0, anchored = options & 2 != 0
        let bytes = [UInt8](data[data.startIndex + start ..< data.startIndex + end])
        var candidates = Array(0...(bytes.count - needle.count))
        if backwards { candidates.reverse() }
        if anchored { candidates = candidates.first.map { [$0] } ?? [] }
        for offset in candidates where bytes[offset ..< offset + needle.count].elementsEqual(needle) {
            return NSRange(location: start + offset, length: needle.count)
        }
        return notFound
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

    /// The bytes as one range, as they are contiguous here.
    @ObjCMethod("enumerateByteRangesUsingBlock:")
    func enumerateByteRanges(_ block: ObjCBlock) {
        // The block takes the bytes, an NSRange (two words, in two
        // registers) and a stop flag.
        typealias Invoke = @convention(c) (id, UnsafeRawPointer?, UInt, UInt, UnsafeMutablePointer<Bool>) -> Void
        guard let storage, storage.count > 0 else { return }
        var stop = false
        block.function(as: Invoke.self)(block.object, UnsafeRawPointer(storage.bytes), 0, UInt(storage.count), &stop)
    }

    /// The deprecated name, without line breaks.
    @ObjCMethod("base64Encoding") func base64Encoding() -> String { base64(data, options: 0) }

    @ObjCMethod("base64EncodedStringWithOptions:")
    func base64String(options: UInt) -> String { base64(data, options: options) }

    @ObjCMethod("base64EncodedDataWithOptions:")
    func base64Data(options: UInt) -> NSData { DataObjects.owned(DataStorage(Data(base64(data, options: options).utf8))) }

    // MARK: Writing

    @ObjCMethod("writeToFile:atomically:")
    func write(toFile path: String, atomically: Bool) -> Bool {
        (try? data.write(to: URL(filePath: path), options: atomically ? .atomic : [])) != nil
    }

    /// NSDataWritingOptions: atomic 1, without overwriting 2; the file
    /// protection classes are only recorded by the system, so ignored.
    @ObjCMethod("writeToFile:options:error:")
    func write(toFile path: String, options: UInt, error: UnsafeMutablePointer<UnsafeMutableRawPointer?>?) -> Bool {
        write(to: URL(filePath: path), options: options, error: error)
    }

    @ObjCMethod("writeToURL:options:error:")
    func write(toURL url: NSURL, options: UInt, error: UnsafeMutablePointer<UnsafeMutableRawPointer?>?) -> Bool {
        guard url.url.isFileURL else {
            error?.pointee = Errors.autoreleased(domain: Errors.cocoaDomain, code: 518, description: "The file couldn’t be saved.")
            return false
        }
        return write(to: url.url, options: options, error: error)
    }

    private func write(to url: URL, options: UInt, error out: UnsafeMutablePointer<UnsafeMutableRawPointer?>?) -> Bool {
        var writing: Data.WritingOptions = []
        if options & 1 != 0 { writing.insert(.atomic) }
        if options & 2 != 0 { writing.insert(.withoutOverwriting) }
        do {
            try data.write(to: url, options: writing)
            return true
        } catch {
            // NSFileWriteFileExistsError 516, NSFileWriteUnknownError 512.
            let exists = options & 2 != 0 && access(url.path, F_OK) == 0
            out?.pointee = Errors.autoreleased(domain: Errors.cocoaDomain, code: exists ? 516 : 512,
                                                 description: "The file couldn’t be saved.")
            return false
        }
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
    /// Set-up after the class is defined.
    override public class func didDefineObjCClass(_ cls: ObjCClass) {
        DataObjects.mutableClass = cls.storage
    }

    private var storage: DataStorage {
        guard let storage = DataObjects.storage(objcObject) else {
            foundationFatal("mutating method sent to an uninitialized NSMutableData")
        }
        return storage
    }

    @ObjCClassMethod("dataWithCapacity:")
    static func data(_ cls: ObjCClass, capacity: UInt) -> NSData { DataObjects.owned(DataStorage(reserving: Int(capacity)), cls: cls) }

    @ObjCClassMethod("dataWithLength:")
    static func data(_ cls: ObjCClass, length: UInt) -> NSData {
        DataObjects.owned(DataStorage(Data(count: Int(length))), cls: cls)
    }

    @ObjCMethod("initWithCapacity:")
    func initialize(capacity: UInt) -> Self {
        Storage.set(objcObject, DataStorage(reserving: Int(capacity)))
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
}

/// CoreFoundation's name for the NSNull instance.
@ObjCConstants
enum NullConstants {
    nonisolated(unsafe) static let kCFNull: UnsafeMutableRawPointer? = Nulls.null
}

/// NSNull.
@ObjCClass("NSNull")
public final class NSNull: NSObject {
    /// Set-up after the class is defined.
    override public class func didDefineObjCClass(_ cls: ObjCClass) {
        NSObject.registerObjCCategoryImmortal(cls)
        Nulls.null = ObjC.createInstance(cls.markingStatic().storage, 0)
    }

    @ObjCClassMethod("null") static func null() -> UnsafeMutableRawPointer? { Nulls.null }
    @ObjCClassMethod("alloc") static func alloc() -> UnsafeMutableRawPointer? { Nulls.null }
    @ObjCMethod("init") func initialize() -> Self { self }
    @ObjCMethod("description") func description() -> String { "<null>" }
    @ObjCMethod("copyWithZone:") func copy(zone: UnsafeMutableRawPointer?) -> NSNull { self }
}
