import FoundationEssentials
import Glibc
import PerryObjCInterop

// NSFileWrapper: a file, a directory of file wrappers, or a symbolic link,
// read from disk or made in memory, and written back to disk. Reading is
// immediate: a wrapper made from a URL holds the bytes of every file under
// it.

/// Reports a failure as an NSError in the Cocoa domain.
private func fail(_ error: UnsafeMutablePointer<id?>?, _ code: Int, _ description: String) {
    error?.pointee = Errors.autoreleased(domain: Errors.cocoaDomain, code: code, description: description)
}

private func send(_ receiver: id?, _ name: String) -> id? { ObjC.send(receiver, ObjC.selector(name)) }

private func classNamed(_ name: String) -> id? {
    name.withCString { ObjC.getClass($0) }.map { UnsafeMutableRawPointer($0) }
}

final class FileWrapperStorage {
    enum Kind { case regular, directory, symbolicLink }

    var kind: Kind
    var preferredFilename: String?
    var filename: String?
    var contents: id?
    var destination: URL?
    var children: [(key: String, wrapper: id)] = []
    var attributes: id?

    init(kind: Kind) { self.kind = kind }

    deinit {
        if let contents { ObjC.release(contents) }
        if let attributes { ObjC.release(attributes) }
        for child in children { ObjC.release(child.wrapper) }
    }
}

@ObjCClass("NSFileWrapper")
public class NSFileWrapper: NSObject {
    nonisolated(unsafe) static var wrapperClass: Class!

    override public class func didDefineObjCClass(_ cls: ObjCClass) {
        NSObject.registerObjCCategoryStorageAllocated(cls)
        wrapperClass = cls.storage
    }

    private var storage: FileWrapperStorage {
        if let existing = Storage.get(objcObject, as: FileWrapperStorage.self) { return existing }
        let made = FileWrapperStorage(kind: .regular)
        Storage.set(objcObject, made)
        return made
    }

    private func become(_ storage: FileWrapperStorage) -> Self {
        Storage.set(objcObject, storage)
        return self
    }

    private static func storage(of object: id?) -> FileWrapperStorage? {
        Storage.get(object, as: FileWrapperStorage.self)
    }

    /// A wrapper (+1) for the file, directory or link at `path`.
    private static func read(path: String, url: URL, error: UnsafeMutablePointer<id?>?) -> id? {
        var info = stat()
        guard lstat(path, &info) == 0 else {
            fail(error, 260, "The file “\(url.lastPathComponent)” couldn’t be opened because there is no such file.")
            return nil
        }
        let name = url.lastPathComponent
        let type = info.st_mode & S_IFMT
        let storage: FileWrapperStorage
        if type == S_IFLNK {
            storage = FileWrapperStorage(kind: .symbolicLink)
            var buffer = [CChar](repeating: 0, count: Int(PATH_MAX) + 1)
            let length = readlink(path, &buffer, Int(PATH_MAX))
            let target = length > 0 ? String(decoding: buffer.prefix(length).map { UInt8(bitPattern: $0) }, as: UTF8.self) : ""
            storage.destination = URL(fileURLWithPath: target)
        } else if type == S_IFDIR {
            storage = FileWrapperStorage(kind: .directory)
            let names = ((try? FileManager.default.contentsOfDirectory(atPath: path)) ?? []).sorted()
            for child in names {
                let childPath = path + (path.hasSuffix("/") ? "" : "/") + child
                guard let wrapper = read(path: childPath, url: URL(fileURLWithPath: childPath), error: error) else { continue }
                if let childStorage = Self.storage(of: wrapper) {
                    childStorage.filename = child
                    childStorage.preferredFilename = child
                }
                storage.children.append((child, wrapper))
            }
        } else {
            storage = FileWrapperStorage(kind: .regular)
            guard let bytes = FileManager.default.contents(atPath: path) else {
                fail(error, 257, "The file “\(name)” couldn’t be opened because you don’t have permission to view it.")
                return nil
            }
            storage.contents = ObjC.retain(DataObjects.autoreleased(bytes))
        }
        storage.preferredFilename = name
        storage.filename = name
        guard let object = Storage.allocate(UnsafeMutableRawPointer(wrapperClass)) else { return nil }
        Storage.set(object, storage)
        return object
    }

    @ObjCMethod("initWithURL:options:error:")
    func initialize(url: UnsafeMutableRawPointer?, options: UInt, error: UnsafeMutablePointer<id?>?) -> Self? {
        guard let url = URLs.url(url), let made = Self.read(path: FileManagers.path(url), url: url, error: error),
              let source = Self.storage(of: made) else {
            return nil
        }
        Storage.set(objcObject, source)
        ObjC.release(made)
        return self
    }

    @ObjCMethod("initDirectoryWithFileWrappers:")
    func initialize(directoryWith wrappers: UnsafeMutableRawPointer?) -> Self {
        let storage = FileWrapperStorage(kind: .directory)
        for (key, wrapper) in Dictionaries.entries(wrappers) {
            guard let name = Strings.value(of: key), let retained = ObjC.retain(wrapper) else { continue }
            if let child = Self.storage(of: wrapper), child.preferredFilename == nil { child.preferredFilename = name }
            Self.storage(of: wrapper)?.filename = name
            storage.children.append((name, retained))
        }
        return become(storage)
    }

    @ObjCMethod("initRegularFileWithContents:")
    func initialize(regularFileWith contents: UnsafeMutableRawPointer?) -> Self {
        let storage = FileWrapperStorage(kind: .regular)
        storage.contents = contents.flatMap { ObjC.retain($0) }
        return become(storage)
    }

    @ObjCMethod("initSymbolicLinkWithDestinationURL:")
    func initialize(symbolicLinkWith url: UnsafeMutableRawPointer?) -> Self {
        let storage = FileWrapperStorage(kind: .symbolicLink)
        storage.destination = URLs.url(url)
        return become(storage)
    }

    @ObjCMethod("init") func initialize() -> Self { become(FileWrapperStorage(kind: .regular)) }

    @ObjCMethod("dealloc")
    func dealloc() {
        Storage.set(objcObject, nil)
        ObjC.superDealloc(objcObject, from: NSFileWrapper.wrapperClass)
    }

    @ObjCMethod("isDirectory") func isDirectory() -> Bool { storage.kind == .directory }
    @ObjCMethod("isRegularFile") func isRegularFile() -> Bool { storage.kind == .regular }
    @ObjCMethod("isSymbolicLink") func isSymbolicLink() -> Bool { storage.kind == .symbolicLink }

    @ObjCMethod("preferredFilename") func preferredFilename() -> UnsafeMutableRawPointer? {
        storage.preferredFilename.map { Strings.autoreleased($0) }
    }
    @ObjCMethod("setPreferredFilename:") func setPreferredFilename(_ name: UnsafeMutableRawPointer?) {
        storage.preferredFilename = Strings.value(of: name)
    }
    @ObjCMethod("filename") func filename() -> UnsafeMutableRawPointer? {
        storage.filename.map { Strings.autoreleased($0) }
    }
    @ObjCMethod("setFilename:") func setFilename(_ name: UnsafeMutableRawPointer?) {
        storage.filename = Strings.value(of: name)
    }

    @ObjCMethod("fileAttributes") func fileAttributes() -> UnsafeMutableRawPointer? {
        storage.attributes ?? ObjC.send(classNamed("NSDictionary"), ObjC.selector("dictionary"))
    }
    @ObjCMethod("setFileAttributes:") func setFileAttributes(_ attributes: UnsafeMutableRawPointer?) {
        if let old = storage.attributes { ObjC.release(old) }
        storage.attributes = attributes.flatMap { ObjC.retain($0) }
    }

    @ObjCMethod("fileWrappers") func fileWrappers() -> UnsafeMutableRawPointer? {
        guard storage.kind == .directory else { return nil }
        let dictionary = ObjC.send(classNamed("NSMutableDictionary"), ObjC.selector("dictionary"))
        for child in storage.children {
            let key = Strings.autoreleased(child.key)
            _ = ObjC.send(dictionary, ObjC.selector("setObject:forKey:"), child.wrapper, key)
        }
        return dictionary
    }

    @ObjCMethod("regularFileContents") func regularFileContents() -> UnsafeMutableRawPointer? {
        storage.kind == .regular ? storage.contents : nil
    }

    @ObjCMethod("symbolicLinkDestinationURL") func symbolicLinkDestinationURL() -> UnsafeMutableRawPointer? {
        storage.kind == .symbolicLink ? URLs.autoreleased(storage.destination) : nil
    }

    private func uniqueKey(for wrapper: id, preferred: String?) -> String {
        let base = preferred ?? "File"
        guard storage.children.contains(where: { $0.key == base }) else { return base }
        var number = 2
        while storage.children.contains(where: { $0.key == "\(base) \(number)" }) { number += 1 }
        return "\(base) \(number)"
    }

    @ObjCMethod("addFileWrapper:")
    func add(_ wrapper: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer? {
        guard storage.kind == .directory, let wrapper, let retained = ObjC.retain(wrapper) else { return nil }
        let child = Self.storage(of: wrapper)
        let key = uniqueKey(for: wrapper, preferred: child?.filename ?? child?.preferredFilename)
        child?.filename = key
        storage.children.append((key, retained))
        return Strings.autoreleased(key)
    }

    @ObjCMethod("addRegularFileWithContents:preferredFilename:")
    func addRegularFile(contents: UnsafeMutableRawPointer?, preferredFilename: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer? {
        guard let wrapper = ObjC.send(ObjC.send(classNamed("NSFileWrapper"), ObjC.selector("alloc")),
                                      ObjC.selector("initRegularFileWithContents:"), contents) else { return nil }
        Self.storage(of: wrapper)?.preferredFilename = Strings.value(of: preferredFilename)
        defer { ObjC.release(wrapper) }
        return add(wrapper)
    }

    @ObjCMethod("removeFileWrapper:")
    func remove(_ wrapper: UnsafeMutableRawPointer?) {
        guard let index = storage.children.firstIndex(where: { $0.wrapper == wrapper }) else { return }
        ObjC.release(storage.children.remove(at: index).wrapper)
    }

    @ObjCMethod("keyForFileWrapper:")
    func key(for wrapper: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer? {
        storage.children.first(where: { $0.wrapper == wrapper }).map { Strings.autoreleased($0.key) }
    }

    @ObjCMethod("matchesContentsOfURL:") func matches(url: UnsafeMutableRawPointer?) -> Bool { false }

    @ObjCMethod("readFromURL:options:error:")
    func read(url: UnsafeMutableRawPointer?, options: UInt, error: UnsafeMutablePointer<id?>?) -> Bool {
        guard let url = URLs.url(url), let made = Self.read(path: FileManagers.path(url), url: url, error: error),
              let source = Self.storage(of: made) else { return false }
        Storage.set(objcObject, source)
        ObjC.release(made)
        return true
    }

    private static func write(_ storage: FileWrapperStorage, path: String, error: UnsafeMutablePointer<id?>?) -> Bool {
        switch storage.kind {
        case .directory:
            if mkdir(path, 0o755) != 0 && errno != EEXIST {
                fail(error, 512, "The folder “\(URL(fileURLWithPath: path).lastPathComponent)” couldn’t be saved.")
                return false
            }
            for child in storage.children {
                guard let childStorage = Self.storage(of: child.wrapper) else { continue }
                guard write(childStorage, path: path + "/" + child.key, error: error) else { return false }
            }
            return true
        case .symbolicLink:
            unlink(path)
            return symlink(storage.destination?.path ?? "", path) == 0
        case .regular:
            let data = DataObjects.data(storage.contents)
            guard FileManager.default.createFile(atPath: path, contents: data) else {
                fail(error, 512, "The file “\(URL(fileURLWithPath: path).lastPathComponent)” couldn’t be saved.")
                return false
            }
            return true
        }
    }

    @ObjCMethod("writeToURL:options:originalContentsURL:error:")
    func write(url: UnsafeMutableRawPointer?, options: UInt, originalContentsURL: UnsafeMutableRawPointer?,
               error: UnsafeMutablePointer<id?>?) -> Bool {
        guard let url = URLs.url(url) else { return false }
        return Self.write(storage, path: FileManagers.path(url), error: error)
    }

    /// The wrapper in the NeXT RTFD pasteboard format, as Darwin
    /// serializes one (see FileWrapperArchive).
    @ObjCMethod("serializedRepresentation")
    func serializedRepresentation() -> UnsafeMutableRawPointer? {
        DataObjects.autoreleased(Data(FileWrapperArchive.serialized(storage)))
    }

    /// A wrapper from -serializedRepresentation's bytes; nil for others.
    @ObjCMethod("initWithSerializedRepresentation:")
    func initialize(serializedRepresentation data: UnsafeMutableRawPointer?) -> Self? {
        guard let made = FileWrapperArchive.wrapper(serialized: [UInt8](DataObjects.data(data))) else { return nil }
        return become(made)
    }
}

/// NSFileWrapper's serialized form, the NeXT RTFD pasteboard format: "rtfd",
/// a zero word, then the item. An item is a version word (3) and a table
/// of named entries: the count, each name (length, then bytes), each
/// entry's length, then the entries; every number a 32-bit little-endian
/// word. A file's or link's entry is a list (a count, then each chunk's
/// length and bytes) of its contents or destination path; a directory's is
/// an item of its own. Each table's "." entry is a list of one table that
/// gives each entry's 16 bytes of attributes: modification time,
/// permissions, kind (1 a directory, 4 a link, 2 the item itself), and 1
/// for the item itself. A lone file or link is an item whose ".." entry is
/// its contents, with __@PreferredName@__ and __@UTF8PreferredName@__ for
/// its preferred name.
private enum FileWrapperArchive {
    static let magic: [UInt8] = Array("rtfd".utf8)

    private static func word(_ value: Int) -> [UInt8] {
        withUnsafeBytes(of: UInt32(truncatingIfNeeded: value).littleEndian) { Array($0) }
    }

    private static func list(_ chunks: [[UInt8]]) -> [UInt8] {
        chunks.reduce(word(chunks.count)) { $0 + word($1.count) + $1 }
    }

    private static func table(_ entries: [(name: String, data: [UInt8])]) -> [UInt8] {
        var bytes = word(entries.count)
        for entry in entries { bytes += word(entry.name.utf8.count) + Array(entry.name.utf8) }
        for entry in entries { bytes += word(entry.data.count) }
        for entry in entries { bytes += entry.data }
        return bytes
    }

    private static func attributes(_ entries: [(name: String, permissions: Int, kind: Int, own: Int)]) -> [UInt8] {
        list([table(entries.map { (name: $0.name, data: word(0) + word($0.permissions) + word($0.kind) + word($0.own)) })])
    }

    private static func contents(_ storage: FileWrapperStorage) -> [UInt8] {
        storage.kind == .symbolicLink ? Array((storage.destination.map { FileManagers.path($0) } ?? "").utf8)
            : [UInt8](DataObjects.data(storage.contents))
    }

    /// A directory's item.
    private static func item(_ storage: FileWrapperStorage) -> [UInt8] {
        var entries: [(name: String, data: [UInt8])] = []
        var kinds: [(name: String, permissions: Int, kind: Int, own: Int)] = []
        for child in storage.children.sorted(by: { $0.key < $1.key }) {
            guard let childStorage = Storage.get(child.wrapper, as: FileWrapperStorage.self) else { continue }
            switch childStorage.kind {
            case .directory:
                entries.append((child.key, item(childStorage)))
                kinds.append((child.key, 0o777, 1, 0))
            case .symbolicLink:
                entries.append((child.key, list([contents(childStorage)])))
                kinds.append((child.key, 0o666, 4, 0))
            case .regular:
                entries.append((child.key, list([contents(childStorage)])))
                kinds.append((child.key, 0o666, 0, 0))
            }
        }
        entries.append((".", attributes(kinds)))
        return word(3) + table(entries)
    }

    static func serialized(_ storage: FileWrapperStorage) -> [UInt8] {
        guard storage.kind != .directory else { return magic + word(0) + item(storage) }
        var entries: [(name: String, data: [UInt8])] = [("..", list([contents(storage)]))]
        if let name = storage.preferredFilename {
            entries.append(("__@PreferredName@__", list([Array(name.utf8)])))
            entries.append(("__@UTF8PreferredName@__", list([Array(name.utf8)])))
        }
        entries.append((".", attributes([("..", 0o666, storage.kind == .symbolicLink ? 6 : 2, 1)])))
        return magic + word(0) + word(3) + table(entries)
    }

    // MARK: Reading

    private struct Reader {
        let bytes: [UInt8]
        var offset = 0

        init(_ bytes: [UInt8]) { self.bytes = bytes }

        mutating func word() -> Int? {
            guard offset + 4 <= bytes.count else { return nil }
            defer { offset += 4 }
            return (0..<4).reduce(0) { $0 | Int(bytes[offset + $1]) << (8 * $1) }
        }

        mutating func chunk(_ count: Int) -> [UInt8]? {
            guard count >= 0, offset + count <= bytes.count else { return nil }
            defer { offset += count }
            return Array(bytes[offset..<offset + count])
        }
    }

    private static func readList(_ bytes: [UInt8]) -> [[UInt8]]? {
        var reader = Reader(bytes)
        guard let count = reader.word(), count < 1 << 20 else { return nil }
        var chunks: [[UInt8]] = []
        for _ in 0..<count {
            guard let length = reader.word(), let chunk = reader.chunk(length) else { return nil }
            chunks.append(chunk)
        }
        return chunks
    }

    private static func readTable(_ reader: inout Reader) -> [String: [UInt8]]? {
        guard let count = reader.word(), count < 1 << 20 else { return nil }
        var names: [String] = [], lengths: [Int] = []
        for _ in 0..<count {
            guard let length = reader.word(), let name = reader.chunk(length) else { return nil }
            names.append(String(decoding: name, as: UTF8.self))
        }
        for _ in 0..<count {
            guard let length = reader.word() else { return nil }
            lengths.append(length)
        }
        var entries: [String: [UInt8]] = [:]
        for (name, length) in zip(names, lengths) {
            guard let data = reader.chunk(length) else { return nil }
            entries[name] = data
        }
        return entries
    }

    /// An item's table, after its version word.
    private static func readItem(_ bytes: [UInt8]) -> [String: [UInt8]]? {
        var reader = Reader(bytes)
        guard reader.word() != nil else { return nil }
        return readTable(&reader)
    }

    /// Each entry's kind word, from the "." entry's table.
    private static func kinds(_ entries: [String: [UInt8]]) -> [String: Int] {
        guard let dot = entries["."], let first = readList(dot)?.first else { return [:] }
        var reader = Reader(first)
        guard let table = readTable(&reader) else { return [:] }
        return table.compactMapValues { attributes -> Int? in
            var fields = Reader(attributes)
            _ = fields.word()
            _ = fields.word()
            return fields.word()
        }
    }

    /// A wrapper (+1) of a stored kind and contents.
    private static func object(_ storage: FileWrapperStorage) -> id? {
        guard let object = Storage.allocate(UnsafeMutableRawPointer(NSFileWrapper.wrapperClass)) else { return nil }
        Storage.set(object, storage)
        return object
    }

    private static func leaf(_ data: [UInt8], kind: Int) -> FileWrapperStorage? {
        guard let chunks = readList(data) else { return nil }
        let bytes = chunks.reduce([], +)
        if kind & 4 != 0 {
            let storage = FileWrapperStorage(kind: .symbolicLink)
            storage.destination = URL(filePath: String(decoding: bytes, as: UTF8.self))
            return storage
        }
        let storage = FileWrapperStorage(kind: .regular)
        storage.contents = ObjC.retain(DataObjects.autoreleased(Data(bytes)))
        return storage
    }

    private static func directory(_ entries: [String: [UInt8]]) -> FileWrapperStorage? {
        let storage = FileWrapperStorage(kind: .directory)
        let entryKinds = Self.kinds(entries)
        for (name, data) in entries.sorted(by: { $0.key < $1.key }) where name != "." {
            let kind = entryKinds[name] ?? 0
            let child: FileWrapperStorage?
            if kind & 1 != 0 {
                child = readItem(data).flatMap(directory)
            } else {
                child = leaf(data, kind: kind)
            }
            guard let child, let wrapper = object(child) else { return nil }
            child.filename = name
            child.preferredFilename = name
            storage.children.append((name, wrapper))
        }
        return storage
    }

    static func wrapper(serialized bytes: [UInt8]) -> FileWrapperStorage? {
        guard bytes.count >= 12, Array(bytes[0..<4]) == magic, let entries = readItem(Array(bytes[8...])) else { return nil }
        guard let own = entries[".."] else { return directory(entries) }
        guard let storage = leaf(own, kind: kinds(entries)[".."] ?? 2) else { return nil }
        let name = (entries["__@UTF8PreferredName@__"] ?? entries["__@PreferredName@__"]).flatMap(readList)?.first
        storage.preferredFilename = name.map { String(decoding: $0, as: UTF8.self) }
        return storage
    }
}
