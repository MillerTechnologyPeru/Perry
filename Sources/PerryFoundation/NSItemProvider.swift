import CPerryFoundation
import FoundationEssentials
import Glibc
import PerryObjCInterop

// NSItemProvider: data an app offers in representations of several types,
// loaded on demand. On Darwin a provider crosses processes (drag and drop,
// share extensions, the pasteboard); here, with every extension in the app's
// own process, it passes data between parts of one program, which is all
// its loading needs: a representation's load handler is called on the
// loading thread, as Darwin calls it, and the consumer's completion handler
// on a background queue. Types conform through UniformTypeIdentifiers' UTType
// when the program has it, else through the common public types.
//
// NSString and NSURL are NSItemProviderReading and NSItemProviderWriting, as
// on Darwin, through a category here.

private func providerClass(_ name: String) -> id? {
    name.withCString { ObjC.getClass($0) }.map { UnsafeMutableRawPointer($0) }
}

private func isInstance(_ object: id?, of name: String) -> Bool {
    guard let object, let cls = name.withCString({ ObjC.getClass($0) }) else { return false }
    return ObjC.isKind(object, of: cls)
}

private func isSubclass(_ cls: id?, of name: String) -> Bool {
    guard let cls, let other = providerClass(name) else { return false }
    return ObjC.sendBool(cls, ObjC.selector("isSubclassOfClass:"), other)
}

private func itemProviderResponds(_ object: id?, _ selector: String) -> Bool {
    guard let object else { return false }
    return ObjC.sendBool(object, ObjC.selector("respondsToSelector:"), UnsafeMutableRawPointer(mutating: ObjC.selector(selector)))
}

private func strings(_ array: id?) -> [String] { Arrays.elements(array).compactMap { Strings.value(of: $0) } }

// MARK: - Types

/// Uniform type identifiers: UTType's, when UniformTypeIdentifiers is loaded,
/// and else the public types programs pass most.
enum ItemProviderTypes {
    /// Each common type's parents.
    static let parents: [String: [String]] = [
        "public.item": [], "public.content": [],
        "public.data": ["public.item"],
        "public.directory": ["public.item"], "public.folder": ["public.directory"],
        "public.text": ["public.data", "public.content"],
        "public.plain-text": ["public.text"],
        "public.utf8-plain-text": ["public.plain-text"],
        "public.utf16-plain-text": ["public.plain-text"],
        "public.utf16-external-plain-text": ["public.plain-text"],
        "public.rtf": ["public.text"], "public.html": ["public.text"], "public.xml": ["public.text"],
        "public.json": ["public.text"], "public.vcard": ["public.text"],
        "public.image": ["public.data", "public.content"],
        "public.png": ["public.image"], "public.jpeg": ["public.image"], "public.tiff": ["public.image"],
        "public.heic": ["public.image"], "com.compuserve.gif": ["public.image"],
        "public.composite-content": ["public.content"],
        "com.adobe.pdf": ["public.data", "public.composite-content"],
        "public.url": ["public.data"], "public.file-url": ["public.url"],
        "public.audiovisual-content": ["public.data", "public.content"],
        "public.movie": ["public.audiovisual-content"], "public.audio": ["public.audiovisual-content"],
        "public.mpeg-4": ["public.movie"], "com.apple.quicktime-movie": ["public.movie"],
    ]

    static let byExtension: [String: String] = [
        "txt": "public.plain-text", "text": "public.plain-text", "rtf": "public.rtf", "html": "public.html",
        "htm": "public.html", "xml": "public.xml", "json": "public.json", "vcf": "public.vcard",
        "png": "public.png", "jpg": "public.jpeg", "jpeg": "public.jpeg", "tif": "public.tiff", "tiff": "public.tiff",
        "heic": "public.heic", "gif": "com.compuserve.gif", "pdf": "com.adobe.pdf", "mp4": "public.mpeg-4",
        "mov": "com.apple.quicktime-movie",
    ]

    static let preferredExtension: [String: String] = [
        "public.plain-text": "txt", "public.utf8-plain-text": "txt", "public.utf16-plain-text": "txt",
        "public.utf16-external-plain-text": "txt", "public.text": "txt", "public.rtf": "rtf", "public.html": "html",
        "public.xml": "xml", "public.json": "json", "public.vcard": "vcf", "public.png": "png", "public.jpeg": "jpeg",
        "public.tiff": "tiff", "public.heic": "heic", "com.compuserve.gif": "gif", "com.adobe.pdf": "pdf",
        "public.mpeg-4": "mp4", "com.apple.quicktime-movie": "mov",
    ]

    /// The UTType of an identifier, when the program has UniformTypeIdentifiers.
    private static func utType(_ identifier: String) -> id? {
        guard let cls = providerClass("UTType") else { return nil }
        return ObjC.send(cls, ObjC.selector("typeWithIdentifier:"), Strings.autoreleased(identifier))
    }

    /// Whether `type` is `other` or one of its kinds. Every type is an item,
    /// and a type nothing here knows is taken for data.
    static func conforms(_ type: String, to other: String) -> Bool {
        if type == other || other == "public.item" { return true }
        if let own = utType(type), let target = utType(other),
           ObjC.sendBool(own, ObjC.selector("conformsToType:"), target) {
            return true
        }
        var pending = [type]
        var seen: Set<String> = []
        while let next = pending.popLast() {
            if next == other { return true }
            guard seen.insert(next).inserted else { continue }
            pending += parents[next] ?? ["public.data"]
        }
        return false
    }

    /// The type of files with an extension.
    static func type(forExtension ext: String) -> String? {
        guard !ext.isEmpty else { return nil }
        if let cls = providerClass("UTType"),
           let type = ObjC.send(cls, ObjC.selector("typeWithFilenameExtension:"), Strings.autoreleased(ext)),
           let identifier = Strings.value(of: ObjC.send(type, ObjC.selector("identifier"))), !identifier.hasPrefix("dyn.") {
            return identifier
        }
        return byExtension[ext.lowercased()]
    }

    /// The extension of a type's files, if it has one.
    static func filenameExtension(for type: String) -> String? {
        if let own = utType(type), let ext = Strings.value(of: ObjC.send(own, ObjC.selector("preferredFilenameExtension"))) {
            return ext
        }
        return preferredExtension[type]
    }
}

// MARK: - Blocks and queues

/// What a block made here calls.
private final class ItemProviderClosure {
    let body: Any

    init(_ body: Any) { self.body = body }
}

/// Darwin heap blocks made of Swift closures: the completion handlers a
/// provider gives the load handlers registered with it. Each captures a box
/// holding the closure, which its dispose helper releases.
enum ItemProviderBlocks {
    /// isa, flags and reserved (32-bit each), invoke, descriptor, then the box.
    private static let word = MemoryLayout<UnsafeRawPointer>.size
    private static let invokeOffset = word + 8
    private static let descriptorOffset = invokeOffset + word
    private static let boxOffset = descriptorOffset + word
    private static let size = boxOffset + word

    nonisolated(unsafe) private static let mallocBlockClass: UnsafeMutableRawPointer? = {
        guard let lookup = BundleLoading.lookupSymbol else { return nil }
        return "/usr/lib/libSystem.B.dylib".withCString { library in "__NSConcreteMallocBlock".withCString { lookup(library, $0) } }
    }()

    private static let copyHelper: @convention(c) (UnsafeMutableRawPointer?, UnsafeRawPointer?) -> Void = { _, source in
        guard let source else { return }
        _ = Unmanaged<ItemProviderClosure>.fromOpaque(source.load(fromByteOffset: boxOffset, as: UnsafeRawPointer.self)).retain()
    }

    private static let disposeHelper: @convention(c) (UnsafeRawPointer?) -> Void = { block in
        guard let block else { return }
        Unmanaged<ItemProviderClosure>.fromOpaque(block.load(fromByteOffset: boxOffset, as: UnsafeRawPointer.self)).release()
    }

    nonisolated(unsafe) private static let descriptor: UnsafeMutableRawPointer = {
        // reserved, size, copy, dispose: a word each.
        let descriptor = UnsafeMutableRawPointer.allocate(byteCount: 4 * word, alignment: word)
        descriptor.storeBytes(of: 0, as: UInt.self)
        descriptor.storeBytes(of: UInt(size), toByteOffset: word, as: UInt.self)
        descriptor.storeBytes(of: unsafeBitCast(copyHelper, to: UnsafeRawPointer.self), toByteOffset: 2 * word, as: UnsafeRawPointer.self)
        descriptor.storeBytes(of: unsafeBitCast(disposeHelper, to: UnsafeRawPointer.self), toByteOffset: 3 * word, as: UnsafeRawPointer.self)
        return descriptor
    }()

    private static func box(_ block: UnsafeMutableRawPointer?) -> ItemProviderClosure? {
        block.map { Unmanaged<ItemProviderClosure>.fromOpaque($0.load(fromByteOffset: boxOffset, as: UnsafeRawPointer.self)).takeUnretainedValue() }
    }

    /// A heap block (+1) whose invoke function is `invoke`: a global one,
    /// never freed, if the blocks runtime's heap block class isn't found.
    private static func make(_ body: Any, invoke: UnsafeRawPointer) -> id {
        guard let block = malloc(size) else { foundationFatal("out of memory") }
        if let mallocBlockClass {
            block.storeBytes(of: mallocBlockClass, as: UnsafeMutableRawPointer.self)
            // BLOCK_NEEDS_FREE | BLOCK_HAS_COPY_DISPOSE, one reference.
            block.storeBytes(of: Int32(1 << 24 | 1 << 25 | 2), toByteOffset: word, as: Int32.self)
        } else {
            block.storeBytes(of: Dispatch.globalBlockClass, as: UnsafeMutableRawPointer?.self)
            block.storeBytes(of: Int32(1 << 28 | 1 << 25), toByteOffset: word, as: Int32.self)   // BLOCK_IS_GLOBAL
        }
        block.storeBytes(of: Int32(0), toByteOffset: word + 4, as: Int32.self)
        block.storeBytes(of: invoke, toByteOffset: invokeOffset, as: UnsafeRawPointer.self)
        block.storeBytes(of: UnsafeRawPointer(descriptor), toByteOffset: descriptorOffset, as: UnsafeRawPointer.self)
        block.storeBytes(of: UnsafeRawPointer(Unmanaged.passRetained(ItemProviderClosure(body)).toOpaque()),
                         toByteOffset: boxOffset, as: UnsafeRawPointer.self)
        return block
    }

    private static let invokeObjects: @convention(c) (UnsafeMutableRawPointer?, UnsafeMutableRawPointer?, UnsafeMutableRawPointer?) -> Void = {
        block, first, second in
        (ItemProviderBlocks.box(block)?.body as? (id?, id?) -> Void)?(first, second)
    }

    private static let invokeObjectFlagObject: @convention(c) (UnsafeMutableRawPointer?, UnsafeMutableRawPointer?, Bool,
                                                               UnsafeMutableRawPointer?) -> Void = { block, first, flag, second in
        (ItemProviderBlocks.box(block)?.body as? (id?, Bool, id?) -> Void)?(first, flag, second)
    }

    /// void (^)(id, id), +1: a completion handler, called once.
    static func block(_ body: @escaping (id?, id?) -> Void) -> id {
        var called = false
        let once: (id?, id?) -> Void = { first, second in
            guard !called else { return }
            called = true
            body(first, second)
        }
        return make(once, invoke: unsafeBitCast(invokeObjects, to: UnsafeRawPointer.self))
    }

    /// void (^)(id, BOOL, id), +1: a completion handler, called once.
    static func block(flagged body: @escaping (id?, Bool, id?) -> Void) -> id {
        var called = false
        let once: (id?, Bool, id?) -> Void = { first, flag, second in
            guard !called else { return }
            called = true
            body(first, flag, second)
        }
        return make(once, invoke: unsafeBitCast(invokeObjectFlagObject, to: UnsafeRawPointer.self))
    }

    /// The class a block's first argument is declared as, from the block's
    /// extended signature (`v24@?0@"NSString"8@"NSError"16`): nil for id or
    /// a block without one. Darwin's providers coerce items to it.
    static func firstArgumentClass(_ block: UnsafeMutableRawPointer?) -> id? {
        guard let block else { return nil }
        let flags = block.load(fromByteOffset: word, as: Int32.self)
        guard flags & (1 << 30) != 0,
              let descriptor = block.load(fromByteOffset: DarwinLayout.blockInvoke + word, as: UnsafeRawPointer?.self) else { return nil }
        let offset = flags & (1 << 25) != 0 ? 4 * word : 2 * word
        guard let signature = descriptor.load(fromByteOffset: offset, as: UnsafePointer<CChar>?.self) else { return nil }
        let text = String(cString: signature)
        guard let blockArgument = text.range(of: "@?") else { return nil }
        let rest = text[blockArgument.upperBound...].drop { $0.isNumber }
        guard rest.hasPrefix("@\"") else { return nil }
        let name = rest.dropFirst(2).prefix { $0 != "\"" && $0 != "<" }
        return name.isEmpty ? nil : providerClass(String(name))
    }
}

private final class ItemProviderWork {
    let body: () -> Void

    init(_ body: @escaping () -> Void) { self.body = body }
}

/// Completion handlers' queue: a global one, as Darwin's providers call
/// them off the loading thread; and the main queue, where Darwin's load
/// items (and fail to).
enum ItemProviderQueue {
    static func background(_ body: @escaping () -> Void) {
        guard let dispatch = Dispatch.async, let global = Dispatch.globalQueue, let queue = global(0x15, 0) else {
            ObjC.autoreleasepool { body() }
            return
        }
        run(body, on: queue, with: dispatch)
    }

    static func onMain(_ body: @escaping () -> Void) {
        guard let dispatch = Dispatch.async, let queue = Dispatch.mainQueue else {
            ObjC.autoreleasepool { body() }
            return
        }
        run(body, on: queue, with: dispatch)
    }

    private static func run(_ body: @escaping () -> Void, on queue: UnsafeMutableRawPointer, with dispatch: Dispatch.Async) {
        let context = Unmanaged.passRetained(ItemProviderWork(body)).toOpaque()
        dispatch(queue, context) { context in
            guard let context else { return }
            let work = Unmanaged<ItemProviderWork>.fromOpaque(context).takeRetainedValue()
            ObjC.autoreleasepool { work.body() }
        }
    }

    /// Calls a void (^)(id, id) block now.
    static func call(_ block: ObjCObject?, _ first: id?, _ second: id?) {
        guard let block else { return }
        Blocks.invoke(block.id, as: (@convention(c) (id, id?, id?) -> Void).self)(block.id, first, second)
    }

    /// Calls a void (^)(id, id) block with the two objects, kept until then.
    static func deliver(_ block: ObjCObject?, _ first: id?, _ second: id?, then: (() -> Void)? = nil) {
        guard let block else { then?(); return }
        let first = first.map { ObjCObject($0) }, second = second.map { ObjCObject($0) }
        background {
            Blocks.invoke(block.id, as: (@convention(c) (id, id?, id?) -> Void).self)(block.id, first?.id, second?.id)
            then?()
        }
    }

    /// Calls a void (^)(id, BOOL, id) block.
    static func deliver(_ block: ObjCObject?, _ first: id?, _ flag: Bool, _ second: id?, then: (() -> Void)? = nil) {
        guard let block else { then?(); return }
        let first = first.map { ObjCObject($0) }, second = second.map { ObjCObject($0) }
        background {
            Blocks.invoke(block.id, as: (@convention(c) (id, id?, Bool, id?) -> Void).self)(block.id, first?.id, flag, second?.id)
            then?()
        }
    }
}

// MARK: - Errors, data and files

enum ItemProviderErrors {
    static let domain = "NSItemProviderErrorDomain"

    /// NSItemProviderItemUnavailableError.
    static func unavailable(_ description: String?) -> id? {
        Errors.autoreleased(domain: Strings.autoreleased(domain), code: -1000, description: description)
    }

    static func unavailable(type: String) -> id? { unavailable("Cannot load representation of type \(type)") }

    /// NSItemProviderUnavailableCoercionError, with the reason it failed.
    static func coercion(_ cls: id?, underlying: id? = nil) -> id? {
        let description = "Could not coerce an item to class \(ObjC.name(ofClass: cls))"
        var entries: [(String, id)] = [("NSLocalizedDescription", Strings.autoreleased(description))]
        if let underlying { entries.append(("NSUnderlyingError", underlying)) }
        return ObjC.autorelease(Errors.make(domain: Strings.autoreleased(domain), code: -1200, entries: entries))
    }
}

enum ItemProviderData {
    /// An item as data: data as it is, a file URL's contents, anything else
    /// archived, as Darwin's providers send items between processes.
    static func data(of item: id?) -> (data: id?, error: id?) {
        guard let item else { return (nil, ItemProviderErrors.unavailable(nil)) }
        if isInstance(item, of: "NSData") { return (item, nil) }
        if isInstance(item, of: "NSURL"), ObjC.sendBool(item, ObjC.selector("isFileURL"), nil) {
            if let contents = ObjC.send(providerClass("NSData"), ObjC.selector("dataWithContentsOfURL:"), item) { return (contents, nil) }
            return (nil, ItemProviderErrors.unavailable("Cannot read the file"))
        }
        typealias Archive = @convention(c) (id?, SEL, id?, Bool, UnsafeMutablePointer<id?>?) -> id?
        var error: id?
        let archived = unsafeBitCast(ObjC.msgSend, to: Archive.self)(providerClass("NSKeyedArchiver"),
                                                                       ObjC.selector("archivedDataWithRootObject:requiringSecureCoding:error:"),
                                                                       item, false, &error)
        if let archived { return (archived, nil) }
        return (nil, error ?? ItemProviderErrors.unavailable(nil))
    }

    /// An item as an instance of `cls`: itself if it is one, else read from
    /// its data by the class's NSItemProviderReading, or its data for NSData.
    static func coerce(_ item: id, to cls: id?, type: String) -> (item: id?, error: id?) {
        guard let cls else { return (item, nil) }
        if ObjC.isKind(item, of: cls.assumingMemoryBound(to: Class.Pointee.self)) { return (item, nil) }
        if isSubclass(cls, of: "NSData") {
            if let converted = Self.data(of: item).data { return (converted, nil) }
            return (nil, ItemProviderErrors.coercion(cls))
        }
        if isInstance(item, of: "NSData"), itemProviderResponds(cls, "objectWithItemProviderData:typeIdentifier:error:") {
            return read(item, as: cls, type: type)
        }
        return (nil, ItemProviderErrors.coercion(cls))
    }

    /// +[cls objectWithItemProviderData:typeIdentifier:error:].
    static func read(_ data: id, as cls: id, type: String) -> (item: id?, error: id?) {
        typealias Read = @convention(c) (id?, SEL, id?, id?, UnsafeMutablePointer<id?>?) -> id?
        var error: id?
        let object = unsafeBitCast(ObjC.msgSend, to: Read.self)(cls, ObjC.selector("objectWithItemProviderData:typeIdentifier:error:"),
                                                                 data, Strings.autoreleased(type), &error)
        if let object { return (object, nil) }
        return (nil, ItemProviderErrors.coercion(cls, underlying: error))
    }

    /// A new file of the data, named for the type, in a folder of its own.
    static func temporaryFile(_ data: id, type: String, name: String?) -> String? {
        let base = (Strings.value(of: NSTemporaryDirectory()) ?? "/tmp/") + "perry-item-provider-" + UUID().uuidString
        guard mkdir(base, 0o700) == 0 else { return nil }
        var file = name ?? "file"
        if let ext = ItemProviderTypes.filenameExtension(for: type), !file.hasSuffix("." + ext) { file += "." + ext }
        let path = base + "/" + String(file.map { $0 == "/" ? ":" : $0 })
        typealias Write = @convention(c) (id?, SEL, id?, Bool) -> Bool
        guard unsafeBitCast(ObjC.msgSend, to: Write.self)(data, ObjC.selector("writeToFile:atomically:"), Strings.autoreleased(path), true) else {
            _ = rmdir(base)
            return nil
        }
        return path
    }

    /// A copy of a file, in a folder of its own.
    static func temporaryCopy(of path: String) -> String? {
        let base = (Strings.value(of: NSTemporaryDirectory()) ?? "/tmp/") + "perry-item-provider-" + UUID().uuidString
        guard mkdir(base, 0o700) == 0 else { return nil }
        let copy = base + "/" + (path.split(separator: "/").last.map(String.init) ?? "file")
        let manager = ObjC.send(providerClass("NSFileManager"), ObjC.selector("defaultManager"))
        typealias Copy = @convention(c) (id?, SEL, id?, id?, UnsafeMutablePointer<id?>?) -> Bool
        guard unsafeBitCast(ObjC.msgSend, to: Copy.self)(manager, ObjC.selector("copyItemAtPath:toPath:error:"),
                                                        Strings.autoreleased(path), Strings.autoreleased(copy), nil) else {
            _ = rmdir(base)
            return nil
        }
        return copy
    }

    /// Removes a temporary file and its folder.
    static func removeTemporary(_ path: String) {
        let manager = ObjC.send(providerClass("NSFileManager"), ObjC.selector("defaultManager"))
        let folder = String(path[..<(path.lastIndex(of: "/") ?? path.endIndex)])
        _ = ObjC.send(manager, ObjC.selector("removeItemAtPath:error:"), Strings.autoreleased(folder), nil)
    }

    /// The types an object writes: its own, else its class's.
    static func writableTypes(_ object: id) -> [String] {
        let selector = ObjC.selector("writableTypeIdentifiersForItemProvider")
        if itemProviderResponds(object, "writableTypeIdentifiersForItemProvider") { return strings(ObjC.send(object, selector)) }
        return strings(ObjC.send(ObjC.objectGetClass(object).map { UnsafeMutableRawPointer($0) }, selector))
    }

    /// -[object loadDataWithTypeIdentifier:forItemProviderCompletionHandler:].
    static func write(_ object: id, type: String, _ completion: @escaping (id?, id?) -> Void) {
        let block = ItemProviderBlocks.block(completion)
        _ = ObjC.send(object, ObjC.selector("loadDataWithTypeIdentifier:forItemProviderCompletionHandler:"), Strings.autoreleased(type), block)
        ObjC.release(block)
    }
}

// MARK: - Representations

/// One type a provider offers, and how it is loaded.
final class ItemRepresentation {
    enum Source {
        /// NSProgress *(^)(void (^)(NSData *, NSError *)).
        case data(ObjCObject)
        /// NSProgress *(^)(void (^)(NSURL *, BOOL coordinated, NSError *)).
        case file(ObjCObject)
        /// A file's URL, from -initWithContentsOfURL:.
        case fileURL(ObjCObject)
        /// An item, from -initWithItem:typeIdentifier:.
        case item(ObjCObject)
        /// NSItemProviderLoadHandler.
        case itemLoader(ObjCObject)
        /// An NSItemProviderWriting object.
        case object(ObjCObject)
        /// NSProgress *(^)(void (^)(id<NSItemProviderWriting>, NSError *)), and its class.
        case objectLoader(ObjCObject, id)
    }

    let type: String
    let source: Source
    let fileOptions: Int

    init(type: String, source: Source, fileOptions: Int = 0) {
        self.type = type
        self.source = source
        self.fileOptions = fileOptions
    }

    /// Calls the load handler with a completion handler of the shape it takes.
    private static func callLoader(_ loader: ObjCObject, _ completion: id) {
        typealias Loader = @convention(c) (id, id) -> id?
        _ = Blocks.invoke(loader.id, as: Loader.self)(loader.id, completion)
        ObjC.release(completion)
    }

    /// The representation as data.
    func loadData(_ completion: @escaping (id?, id?) -> Void) {
        let type = self.type
        switch source {
        case .data(let loader):
            Self.callLoader(loader, ItemProviderBlocks.block(completion))
        case .file(let loader):
            Self.callLoader(loader, ItemProviderBlocks.block(flagged: { url, _, error in
                guard let url else { return completion(nil, error) }
                let (data, failure) = ItemProviderData.data(of: url)
                completion(data, failure)
            }))
        case .fileURL(let url):
            let (data, error) = ItemProviderData.data(of: url.id)
            completion(data, error)
        case .item(let item):
            let (data, error) = ItemProviderData.data(of: item.id)
            completion(data, error)
        case .itemLoader(let loader):
            let block = ItemProviderBlocks.block { item, error in
                guard let item else { return completion(nil, error) }
                let (data, failure) = ItemProviderData.data(of: item)
                completion(data, failure)
            }
            Blocks.invoke(loader.id, as: (@convention(c) (id, id, id?, id?) -> Void).self)(loader.id, block, nil, nil)
            ObjC.release(block)
        case .object(let object):
            ItemProviderData.write(object.id, type: type, completion)
        case .objectLoader(let loader, _):
            Self.callLoader(loader, ItemProviderBlocks.block { object, error in
                guard let object else { return completion(nil, error) }
                ItemProviderData.write(object, type: type, completion)
            })
        }
    }

    /// The representation's file: its own, or a copy (`copied`) of it or of
    /// its data, which goes once the consumer is done with it.
    func loadFile(name: String?, _ completion: @escaping (_ path: String?, _ copied: Bool, _ error: id?) -> Void) {
        let type = self.type
        func copy(_ url: id?, _ error: id?) {
            guard let path = URLs.url(url)?.path else { return completion(nil, false, error) }
            let copy = ItemProviderData.temporaryCopy(of: path)
            completion(copy, true, copy == nil ? ItemProviderErrors.unavailable(type: type) : nil)
        }
        switch source {
        case .file(let loader):
            Self.callLoader(loader, ItemProviderBlocks.block(flagged: { url, _, error in copy(url, error) }))
        case .fileURL(let url):
            copy(url.id, nil)
        default:
            loadData { data, error in
                guard let data else { return completion(nil, false, error) }
                let path = ItemProviderData.temporaryFile(data, type: type, name: name)
                completion(path, true, path == nil ? ItemProviderErrors.unavailable(type: type) : nil)
            }
        }
    }

    /// The representation's file where it is, if it may be opened there.
    func loadFileInPlace(name: String?, _ completion: @escaping (_ path: String?, _ inPlace: Bool, _ copied: Bool, _ error: id?) -> Void) {
        if case .file(let loader) = source, fileOptions & 1 != 0 {
            Self.callLoader(loader, ItemProviderBlocks.block(flagged: { url, _, error in
                completion(URLs.url(url)?.path, true, false, error)
            }))
            return
        }
        loadFile(name: name) { path, copied, error in completion(path, false, copied, error) }
    }

    /// The representation as an item, for a consumer expecting `expected`
    /// (nil for any class); its load handler is told of the class.
    func loadItem(expected: id?, options: id?, _ completion: @escaping (id?, id?) -> Void) {
        switch source {
        case .item(let item):
            completion(item.id, nil)
        case .itemLoader(let loader):
            let block = ItemProviderBlocks.block(completion)
            Blocks.invoke(loader.id, as: (@convention(c) (id, id, id?, id?) -> Void).self)(loader.id, block, expected, options)
            ObjC.release(block)
        case .file, .fileURL:
            if isSubclass(expected, of: "NSURL") {
                if case .fileURL(let url) = source { return completion(url.id, nil) }
                if case .file(let loader) = source {
                    Self.callLoader(loader, ItemProviderBlocks.block(flagged: { url, _, error in completion(url, error) }))
                }
                return
            }
            loadData(completion)
        case .object(let object):
            if let expected, ObjC.isKind(object.id, of: expected.assumingMemoryBound(to: Class.Pointee.self)) {
                return completion(object.id, nil)
            }
            loadData(completion)
        case .objectLoader(let loader, _):
            let type = self.type
            Self.callLoader(loader, ItemProviderBlocks.block { object, error in
                guard let object else { return completion(nil, error) }
                if let expected, ObjC.isKind(object, of: expected.assumingMemoryBound(to: Class.Pointee.self)) {
                    return completion(object, nil)
                }
                ItemProviderData.write(object, type: type, completion)
            })
        case .data:
            loadData(completion)
        }
    }
}

/// A provider's representations, in the order registered, and its metadata.
final class ItemProviderStorage {
    var representations: [ItemRepresentation] = []
    var suggestedName: String?
    var previewImageHandler: ObjCObject?

    func add(_ representation: ItemRepresentation) {
        // The first registered for a type is the one loaded.
        guard !representations.contains(where: { $0.type == representation.type }) else { return }
        representations.append(representation)
    }

    func representation(conformingTo type: String, fileOptions: Int = 0) -> ItemRepresentation? {
        representations.first {
            ($0.fileOptions & fileOptions) == fileOptions && ItemProviderTypes.conforms($0.type, to: type)
        }
    }
}

private func makeProgress() -> ObjCObject? {
    typealias Make = @convention(c) (id?, SEL, Int64) -> id?
    return unsafeBitCast(ObjC.msgSend, to: Make.self)(providerClass("NSProgress"), ObjC.selector("discreteProgressWithTotalUnitCount:"), 100)
        .map { ObjCObject($0) }
}

private func finish(_ progress: ObjCObject?) {
    typealias SetCompleted = @convention(c) (id?, SEL, Int64) -> Void
    guard let progress else { return }
    unsafeBitCast(ObjC.msgSend, to: SetCompleted.self)(progress.id, ObjC.selector("setCompletedUnitCount:"), 100)
}

private func copiedBlock(_ block: UnsafeMutableRawPointer?) -> ObjCObject? {
    block.flatMap { ObjC.retainBlock($0) }.map { ObjCObject(objCOwned: $0) }
}

@ObjCClass("NSItemProvider")
open class NSItemProvider: NSObject {
    nonisolated(unsafe) static var itemProviderClass: Class!

    override public class func didDefineObjCClass(_ cls: ObjCClass) {
        NSObject.registerObjCCategoryStorageAllocated(cls)
        itemProviderClass = cls.storage
    }

    var storage: ItemProviderStorage {
        if let storage = Storage.get(objcObject, as: ItemProviderStorage.self) { return storage }
        let storage = ItemProviderStorage()
        Storage.set(objcObject, storage)
        return storage
    }

    // MARK: Making

    @ObjCMethod("init")
    func initialize() -> Self {
        _ = storage
        return self
    }

    @ObjCMethod("initWithObject:")
    func initialize(object: UnsafeMutableRawPointer?) -> Self {
        _ = storage
        registerObject(object, visibility: 0)
        return self
    }

    /// The item under the type, if both are given.
    @ObjCMethod("initWithItem:typeIdentifier:")
    func initialize(item: UnsafeMutableRawPointer?, typeIdentifier: String?) -> Self {
        let storage = self.storage
        if let item, let typeIdentifier {
            storage.add(ItemRepresentation(type: typeIdentifier, source: .item(ObjCObject(item))))
        }
        return self
    }

    /// The file under its type, then its URL as an NSURL writes it; made
    /// even for a file that isn't there, as Darwin's is.
    @ObjCMethod("initWithContentsOfURL:")
    func initialize(contentsOfURL url: UnsafeMutableRawPointer?) -> Self? {
        guard let url, let path = URLs.url(url)?.path else { return nil }
        let storage = self.storage
        let name = path.split(separator: "/").last.map(String.init) ?? ""
        let ext = name.lastIndex(of: ".").map { String(name[name.index(after: $0)...]) } ?? ""
        storage.add(ItemRepresentation(type: ItemProviderTypes.type(forExtension: ext) ?? "public.data", source: .fileURL(ObjCObject(url))))
        registerObject(url, visibility: 0)
        return self
    }

    @ObjCMethod("copyWithZone:")
    func copy(zone: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer? {
        guard let copy = Storage.allocate(ObjC.objectGetClass(objcObject).map { UnsafeMutableRawPointer($0) }) else { return nil }
        let source = self.storage, copied = ItemProviderStorage()
        copied.representations = source.representations
        copied.suggestedName = source.suggestedName
        copied.previewImageHandler = source.previewImageHandler
        Storage.set(copy, copied)
        return copy
    }

    // MARK: Registering

    @ObjCMethod("registerDataRepresentationForTypeIdentifier:visibility:loadHandler:")
    func registerDataRepresentation(forTypeIdentifier type: String, visibility: Int, loadHandler: UnsafeMutableRawPointer?) {
        guard let loader = copiedBlock(loadHandler) else { return }
        storage.add(ItemRepresentation(type: type, source: .data(loader)))
    }

    @ObjCMethod("registerFileRepresentationForTypeIdentifier:fileOptions:visibility:loadHandler:")
    func registerFileRepresentation(forTypeIdentifier type: String, fileOptions: Int, visibility: Int, loadHandler: UnsafeMutableRawPointer?) {
        guard let loader = copiedBlock(loadHandler) else { return }
        storage.add(ItemRepresentation(type: type, source: .file(loader), fileOptions: fileOptions))
    }

    @ObjCMethod("registerItemForTypeIdentifier:loadHandler:")
    func registerItem(forTypeIdentifier type: String, loadHandler: UnsafeMutableRawPointer?) {
        guard let loader = copiedBlock(loadHandler) else { return }
        storage.add(ItemRepresentation(type: type, source: .itemLoader(loader)))
    }

    /// A representation for each type the object writes.
    @ObjCMethod("registerObject:visibility:")
    func registerObject(_ object: UnsafeMutableRawPointer?, visibility: Int) {
        guard let object else { return }
        let held = ObjCObject(object)
        for type in ItemProviderData.writableTypes(object) {
            storage.add(ItemRepresentation(type: type, source: .object(held)))
        }
    }

    @ObjCMethod("registerObjectOfClass:visibility:loadHandler:")
    func registerObject(ofClass cls: UnsafeMutableRawPointer?, visibility: Int, loadHandler: UnsafeMutableRawPointer?) {
        guard let cls, let loader = copiedBlock(loadHandler) else { return }
        for type in strings(ObjC.send(cls, ObjC.selector("writableTypeIdentifiersForItemProvider"))) {
            storage.add(ItemRepresentation(type: type, source: .objectLoader(loader, cls)))
        }
    }

    // MARK: Asking

    @ObjCMethod("registeredTypeIdentifiers")
    func registeredTypeIdentifiers() -> UnsafeMutableRawPointer? {
        Arrays.autoreleased(storage.representations.map { Strings.autoreleased($0.type) })
    }

    /// The types registered with the options: those opened in place, for
    /// NSItemProviderFileOptionOpenInPlace.
    @ObjCMethod("registeredTypeIdentifiersWithFileOptions:")
    func registeredTypeIdentifiers(fileOptions: Int) -> UnsafeMutableRawPointer? {
        Arrays.autoreleased(storage.representations.filter { $0.fileOptions & fileOptions == fileOptions }
            .map { Strings.autoreleased($0.type) })
    }

    @ObjCMethod("hasItemConformingToTypeIdentifier:")
    func hasItem(conformingToTypeIdentifier type: String) -> Bool { storage.representation(conformingTo: type) != nil }

    @ObjCMethod("hasRepresentationConformingToTypeIdentifier:fileOptions:")
    func hasRepresentation(conformingToTypeIdentifier type: String, fileOptions: Int) -> Bool {
        storage.representation(conformingTo: type, fileOptions: fileOptions) != nil
    }

    /// The first representation a class reads, and the type it is read as.
    private func readable(by cls: id?) -> ItemRepresentation? {
        guard let cls, itemProviderResponds(cls, "readableTypeIdentifiersForItemProvider") else { return nil }
        let types = strings(ObjC.send(cls, ObjC.selector("readableTypeIdentifiersForItemProvider")))
        return storage.representations.first { representation in
            types.contains { ItemProviderTypes.conforms(representation.type, to: $0) }
        }
    }

    @ObjCMethod("canLoadObjectOfClass:")
    func canLoadObject(ofClass cls: UnsafeMutableRawPointer?) -> Bool { readable(by: cls) != nil }

    // MARK: Loading

    @ObjCMethod("loadDataRepresentationForTypeIdentifier:completionHandler:")
    func loadDataRepresentation(forTypeIdentifier type: String, completionHandler: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer? {
        let progress = makeProgress()
        let completion = copiedBlock(completionHandler)
        guard let representation = storage.representation(conformingTo: type) else {
            finish(progress)
            ItemProviderQueue.deliver(completion, nil, ItemProviderErrors.unavailable(type: type))
            return progress?.id
        }
        representation.loadData { data, error in
            if data != nil { finish(progress) }
            ItemProviderQueue.deliver(completion, data, data == nil ? (error ?? ItemProviderErrors.unavailable(type: type)) : nil)
        }
        return progress?.id
    }

    /// A copy of the file, which is removed once the completion handler returns.
    @ObjCMethod("loadFileRepresentationForTypeIdentifier:completionHandler:")
    func loadFileRepresentation(forTypeIdentifier type: String, completionHandler: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer? {
        let progress = makeProgress()
        let completion = copiedBlock(completionHandler)
        guard let representation = storage.representation(conformingTo: type) else {
            finish(progress)
            ItemProviderQueue.deliver(completion, nil, ItemProviderErrors.unavailable(type: type))
            return progress?.id
        }
        representation.loadFile(name: storage.suggestedName) { path, copied, error in
            guard let path else {
                return ItemProviderQueue.deliver(completion, nil, error ?? ItemProviderErrors.unavailable(type: type))
            }
            finish(progress)
            ItemProviderQueue.deliver(completion, URLs.autoreleased(URLs.fileURL(path, isDirectory: false)), nil) {
                if copied { ItemProviderData.removeTemporary(path) }
            }
        }
        return progress?.id
    }

    /// The file itself, if it was registered to be opened in place; else a copy.
    @ObjCMethod("loadInPlaceFileRepresentationForTypeIdentifier:completionHandler:")
    func loadInPlaceFileRepresentation(forTypeIdentifier type: String, completionHandler: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer? {
        let progress = makeProgress()
        let completion = copiedBlock(completionHandler)
        guard let representation = storage.representation(conformingTo: type) else {
            finish(progress)
            ItemProviderQueue.deliver(completion, nil, false, ItemProviderErrors.unavailable(type: type))
            return progress?.id
        }
        representation.loadFileInPlace(name: storage.suggestedName) { path, inPlace, copied, error in
            guard let path else {
                return ItemProviderQueue.deliver(completion, nil, false, error ?? ItemProviderErrors.unavailable(type: type))
            }
            finish(progress)
            ItemProviderQueue.deliver(completion, URLs.autoreleased(URLs.fileURL(path, isDirectory: false)), inPlace, nil) {
                if copied { ItemProviderData.removeTemporary(path) }
            }
        }
        return progress?.id
    }

    /// The item, coerced to the class the completion handler's first
    /// argument is declared as, as Darwin's provider does. As there, the
    /// item is loaded on the main queue, from whatever thread it is asked
    /// for, and a type the provider lacks is reported there.
    @ObjCMethod("loadItemForTypeIdentifier:options:completionHandler:")
    func loadItem(forTypeIdentifier type: String, options: UnsafeMutableRawPointer?, completionHandler: UnsafeMutableRawPointer?) {
        let expected = ItemProviderBlocks.firstArgumentClass(completionHandler)
        let completion = copiedBlock(completionHandler)
        let options = options.map { ObjCObject($0) }
        let storage = self.storage
        let provider = ObjCObject(objcObject)
        ItemProviderQueue.onMain {
            _ = provider
            guard let representation = storage.representation(conformingTo: type) else {
                return ItemProviderQueue.call(completion, nil, ItemProviderErrors.unavailable(type: type))
            }
            representation.loadItem(expected: expected, options: options?.id) { item, error in
                guard let item else {
                    return ItemProviderQueue.deliver(completion, nil, error ?? ItemProviderErrors.unavailable(type: type))
                }
                let (coerced, failure) = ItemProviderData.coerce(item, to: expected, type: representation.type)
                ItemProviderQueue.deliver(completion, coerced, failure)
            }
        }
    }

    /// An instance of the class, read from the first representation it reads.
    @ObjCMethod("loadObjectOfClass:completionHandler:")
    func loadObject(ofClass cls: UnsafeMutableRawPointer?, completionHandler: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer? {
        let progress = makeProgress()
        let completion = copiedBlock(completionHandler)
        guard let cls, let representation = readable(by: cls) else {
            finish(progress)
            ItemProviderQueue.deliver(completion, nil, ItemProviderErrors.unavailable("Cannot load an object of class \(ObjC.name(ofClass: cls))"))
            return progress?.id
        }
        let wanted = cls.assumingMemoryBound(to: Class.Pointee.self)
        // Objects registered as themselves are given as they are.
        if case .object(let object) = representation.source, ObjC.isKind(object.id, of: wanted) {
            finish(progress)
            ItemProviderQueue.deliver(completion, object.id, nil)
            return progress?.id
        }
        let type = representation.type
        // An object, or the data the class reads one from.
        let reading: (id?, id?) -> Void = { loaded, error in
            guard let loaded else {
                return ItemProviderQueue.deliver(completion, nil, error ?? ItemProviderErrors.unavailable(type: type))
            }
            if ObjC.isKind(loaded, of: wanted) {
                finish(progress)
                return ItemProviderQueue.deliver(completion, loaded, nil)
            }
            let (object, failure) = ItemProviderData.read(loaded, as: cls, type: type)
            if object != nil { finish(progress) }
            ItemProviderQueue.deliver(completion, object, failure)
        }
        if case .objectLoader = representation.source {
            representation.loadItem(expected: cls, options: nil, reading)
        } else {
            representation.loadData(reading)
        }
        return progress?.id
    }

    // MARK: Metadata

    @ObjCMethod("suggestedName") func suggestedName() -> String? { storage.suggestedName }
    @ObjCMethod("setSuggestedName:") func setSuggestedName(_ name: String?) { storage.suggestedName = name }

    @ObjCMethod("previewImageHandler")
    func previewImageHandler() -> UnsafeMutableRawPointer? { storage.previewImageHandler?.id }

    @ObjCMethod("setPreviewImageHandler:")
    func setPreviewImageHandler(_ handler: UnsafeMutableRawPointer?) { storage.previewImageHandler = copiedBlock(handler) }

    /// The preview image handler's image, loaded on the main queue as an
    /// item is; NSItemProviderItemUnavailableError there without one.
    @ObjCMethod("loadPreviewImageWithOptions:completionHandler:")
    func loadPreviewImage(options: UnsafeMutableRawPointer?, completionHandler: UnsafeMutableRawPointer?) {
        let completion = copiedBlock(completionHandler)
        let expected = ItemProviderBlocks.firstArgumentClass(completionHandler)
        let options = options.map { ObjCObject($0) }
        let handler = storage.previewImageHandler
        ItemProviderQueue.onMain {
            guard let handler else { return ItemProviderQueue.call(completion, nil, ItemProviderErrors.unavailable(nil)) }
            let block = ItemProviderBlocks.block { image, error in
                guard let image else { return ItemProviderQueue.deliver(completion, nil, error ?? ItemProviderErrors.unavailable(nil)) }
                let (coerced, failure) = ItemProviderData.coerce(image, to: expected, type: "public.image")
                ItemProviderQueue.deliver(completion, coerced, failure)
            }
            Blocks.invoke(handler.id, as: (@convention(c) (id, id, id?, id?) -> Void).self)(handler.id, block, expected, options?.id)
            ObjC.release(block)
        }
    }

    @ObjCMethod("description")
    func description() -> String {
        let types = registeredTypeIdentifiers()
        let listed = Strings.value(of: ObjC.send(types, ObjC.selector("description"))) ?? "()"
        return "<\(ObjC.className(objcObject)): \(objcObject)> {types = \(listed)}"
    }

    @ObjCMethod("dealloc")
    func dealloc() {
        Storage.set(objcObject, nil)
        ObjC.superDealloc(objcObject, from: NSItemProvider.itemProviderClass)
    }
}

// MARK: - Strings and URLs as items

/// NSString's NSItemProviderReading and NSItemProviderWriting: UTF-8 text
/// written, any plain text or a URL's string read.
@ObjCCategory("ItemProviderReadingWriting")
extension NSString {
    @ObjCClassMethod("writableTypeIdentifiersForItemProvider")
    static func itemProviderWritableTypes(_ cls: ObjCClass) -> UnsafeMutableRawPointer? {
        Arrays.autoreleased([Strings.autoreleased("public.utf8-plain-text")])
    }

    @ObjCMethod("writableTypeIdentifiersForItemProvider")
    func itemProviderInstanceWritableTypes() -> UnsafeMutableRawPointer? {
        Arrays.autoreleased([Strings.autoreleased("public.utf8-plain-text")])
    }

    @ObjCClassMethod("readableTypeIdentifiersForItemProvider")
    static func itemProviderReadableTypes(_ cls: ObjCClass) -> UnsafeMutableRawPointer? {
        Arrays.autoreleased(["public.utf8-plain-text", "public.utf16-external-plain-text", "public.utf16-plain-text",
                             "public.plain-text", "public.url"].map { Strings.autoreleased($0) })
    }

    @ObjCMethod("loadDataWithTypeIdentifier:forItemProviderCompletionHandler:")
    func itemProviderLoadData(typeIdentifier: String?, completionHandler: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer? {
        let data = DataObjects.autoreleased(Data((Strings.value(of: objcObject) ?? "").utf8))
        if let completionHandler {
            Blocks.invoke(completionHandler, as: (@convention(c) (id, id?, id?) -> Void).self)(completionHandler, data, nil)
        }
        return nil
    }

    /// UTF-16 for the UTF-16 types, else UTF-8.
    @ObjCClassMethod("objectWithItemProviderData:typeIdentifier:error:")
    static func itemProviderObject(_ cls: ObjCClass, data: UnsafeMutableRawPointer?, typeIdentifier: String?,
                                   error: UnsafeMutablePointer<id?>?) -> UnsafeMutableRawPointer? {
        let utf16 = typeIdentifier.map { $0 == "public.utf16-plain-text" || $0 == "public.utf16-external-plain-text" } ?? false
        typealias Make = @convention(c) (id?, SEL, id?, UInt) -> id?
        let made = unsafeBitCast(ObjC.msgSend, to: Make.self)(ObjC.send(cls.pointer, ObjC.selector("alloc")),
                                                              ObjC.selector("initWithData:encoding:"), data, utf16 ? 10 : 4)
        guard let made else {
            error?.pointee = ObjC.autorelease(Errors.make(domain: Errors.cocoaDomain, code: 4864, entries: [
                ("NSDebugDescription", Strings.autoreleased("A string could not be instantiated because of an unknown error.")),
            ]))
            return nil
        }
        return ObjC.autorelease(made)
    }
}

/// NSURL's: a URL written and read as its string; a file URL is also a
/// public.file-url.
@ObjCCategory("ItemProviderReadingWriting")
extension NSURL {
    @ObjCClassMethod("writableTypeIdentifiersForItemProvider")
    static func itemProviderWritableTypes(_ cls: ObjCClass) -> UnsafeMutableRawPointer? {
        Arrays.autoreleased([Strings.autoreleased("public.url")])
    }

    @ObjCMethod("writableTypeIdentifiersForItemProvider")
    func itemProviderInstanceWritableTypes() -> UnsafeMutableRawPointer? {
        let types = url.isFileURL ? ["public.file-url", "public.url"] : ["public.url"]
        return Arrays.autoreleased(types.map { Strings.autoreleased($0) })
    }

    @ObjCClassMethod("readableTypeIdentifiersForItemProvider")
    static func itemProviderReadableTypes(_ cls: ObjCClass) -> UnsafeMutableRawPointer? {
        Arrays.autoreleased([Strings.autoreleased("public.url")])
    }

    @ObjCMethod("loadDataWithTypeIdentifier:forItemProviderCompletionHandler:")
    func itemProviderLoadData(typeIdentifier: String?, completionHandler: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer? {
        let data = DataObjects.autoreleased(Data(url.absoluteString.utf8))
        if let completionHandler {
            Blocks.invoke(completionHandler, as: (@convention(c) (id, id?, id?) -> Void).self)(completionHandler, data, nil)
        }
        return nil
    }

    @ObjCClassMethod("objectWithItemProviderData:typeIdentifier:error:")
    static func itemProviderObject(_ cls: ObjCClass, data: UnsafeMutableRawPointer?, typeIdentifier: String?,
                                   error: UnsafeMutablePointer<id?>?) -> UnsafeMutableRawPointer? {
        let text = data.flatMap { String(validating: DataObjects.data($0), as: UTF8.self) }
        guard let text, let made = ObjC.send(cls.pointer, ObjC.selector("URLWithString:"), Strings.autoreleased(text)) else {
            error?.pointee = ObjC.autorelease(Errors.make(domain: Errors.cocoaDomain, code: 4864, entries: [
                ("NSDebugDescription", Strings.autoreleased("A URL could not be instantiated from the data.")),
            ]))
            return nil
        }
        return made
    }
}
