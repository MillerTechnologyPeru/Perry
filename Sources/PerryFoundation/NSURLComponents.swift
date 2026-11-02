import CPerryFoundation
import FoundationEssentials
import PerryObjCInterop

// NSURLComponents and NSURLQueryItem over swift-foundation's URLComponents
// and URLQueryItem, Darwin's own implementation, so parsing and percent
// encoding match.

final class ComponentsStorage {
    var components: URLComponents

    init(_ components: URLComponents) {
        self.components = components
    }
}

final class QueryItemStorage {
    let item: URLQueryItem

    init(_ item: URLQueryItem) {
        self.item = item
    }
}

enum URLComponentsObjects {
    nonisolated(unsafe) static var componentsClass: Class!
    nonisolated(unsafe) static var itemClass: Class!

    static func item(_ object: id?) -> URLQueryItem? { Storage.get(object, as: QueryItemStorage.self)?.item }

    static func object(_ item: URLQueryItem) -> id {
        let object = Storage.allocate(UnsafeMutableRawPointer(itemClass))!
        Storage.set(object, QueryItemStorage(item))
        return ObjC.autorelease(object)!
    }

    static func items(_ items: [URLQueryItem]?) -> UnsafeMutableRawPointer? {
        items.map { Arrays.autoreleased($0.map(object)) }
    }

    static func items(from array: ObjCObject?) -> [URLQueryItem]? {
        array.map { Arrays.elements($0.id).compactMap(item) }
    }

    /// A string index range as UTF-16 offsets.
    static func range(_ range: Range<String.Index>?, in string: String?) -> NSRange {
        guard let range, let string else { return NSRange(location: notFound, length: 0) }
        let start = string.utf16.distance(from: string.utf16.startIndex, to: range.lowerBound)
        let length = string.utf16.distance(from: range.lowerBound, to: range.upperBound)
        return NSRange(location: UInt(start), length: UInt(length))
    }
}

/// NSURLComponents.
@ObjCClass("NSURLComponents")
public final class NSURLComponents: NSObject {
    override public class func didDefineObjCClass(_ cls: ObjCClass) {
        NSObject.registerObjCCategoryStorageAllocated(cls)
        URLComponentsObjects.componentsClass = cls.storage
    }

    var storage: ComponentsStorage {
        if let storage = Storage.get(objcObject, as: ComponentsStorage.self) { return storage }
        let storage = ComponentsStorage(URLComponents())
        Storage.set(objcObject, storage)
        return storage
    }

    var components: URLComponents {
        get { storage.components }
        set { storage.components = newValue }
    }

    @ObjCMethod("dealloc")
    func dealloc() {
        Storage.set(objcObject, nil)
        ObjC.superDealloc(objcObject, from: URLComponentsObjects.componentsClass)
    }

    private static func make(_ cls: ObjCClass, _ components: URLComponents?) -> UnsafeMutableRawPointer? {
        guard let components, let object = Storage.allocate(cls.pointer) else { return nil }
        Storage.set(object, ComponentsStorage(components))
        return ObjC.autorelease(object)
    }

    @ObjCClassMethod("componentsWithString:")
    static func make(_ cls: ObjCClass, string: String) -> UnsafeMutableRawPointer? { make(cls, URLComponents(string: string)) }

    @ObjCClassMethod("componentsWithString:encodingInvalidCharacters:")
    static func make(_ cls: ObjCClass, string: String, encodingInvalidCharacters encode: Bool) -> UnsafeMutableRawPointer? {
        make(cls, URLComponents(string: string, encodingInvalidCharacters: encode))
    }

    @ObjCClassMethod("componentsWithURL:resolvingAgainstBaseURL:")
    static func make(_ cls: ObjCClass, url: NSURL, resolvingAgainstBaseURL resolve: Bool) -> UnsafeMutableRawPointer? {
        make(cls, URLComponents(url: url.url, resolvingAgainstBaseURL: resolve))
    }

    @ObjCMethod("init")
    func initialize() -> Self {
        _ = storage
        return self
    }

    @ObjCMethod("initWithString:")
    func initialize(string: String) -> UnsafeMutableRawPointer? {
        guard let components = URLComponents(string: string) else { return nil }
        Storage.set(objcObject, ComponentsStorage(components))
        return ObjC.retain(objcObject)
    }

    @ObjCMethod("initWithURL:resolvingAgainstBaseURL:")
    func initialize(url: NSURL, resolvingAgainstBaseURL resolve: Bool) -> UnsafeMutableRawPointer? {
        guard let components = URLComponents(url: url.url, resolvingAgainstBaseURL: resolve) else { return nil }
        Storage.set(objcObject, ComponentsStorage(components))
        return ObjC.retain(objcObject)
    }

    @ObjCMethod("copyWithZone:")
    func copy(zone: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer? {
        guard let object = Storage.allocate(UnsafeMutableRawPointer(URLComponentsObjects.componentsClass)) else { return nil }
        Storage.set(object, ComponentsStorage(components))
        return object
    }

    @ObjCMethod("isEqual:")
    func isEqual(_ other: ObjCObject?) -> Bool {
        Storage.get(other?.id, as: ComponentsStorage.self)?.components == components
    }

    @ObjCMethod("URL") func url() -> UnsafeMutableRawPointer? { components.url.flatMap { URLs.autoreleased($0) } }

    @ObjCMethod("URLRelativeToURL:")
    func url(relativeTo base: NSURL?) -> UnsafeMutableRawPointer? {
        components.url(relativeTo: base?.url).flatMap { URLs.autoreleased($0) }
    }

    @ObjCMethod("string") func string() -> String? { components.string }

    @ObjCMethod("scheme") func scheme() -> String? { components.scheme }
    @ObjCMethod("setScheme:") func setScheme(_ value: String?) { components.scheme = value }
    @ObjCMethod("user") func user() -> String? { components.user }
    @ObjCMethod("setUser:") func setUser(_ value: String?) { components.user = value }
    @ObjCMethod("password") func password() -> String? { components.password }
    @ObjCMethod("setPassword:") func setPassword(_ value: String?) { components.password = value }
    @ObjCMethod("host") func host() -> String? { components.host }
    @ObjCMethod("setHost:") func setHost(_ value: String?) { components.host = value }

    @ObjCMethod("port")
    func port() -> UnsafeMutableRawPointer? { components.port.flatMap { Numbers.make(nil, .signed(Int64($0))) } }

    @ObjCMethod("setPort:")
    func setPort(_ value: ObjCObject?) { components.port = value.map { Int(Numbers.storage($0.id).int64) } }

    @ObjCMethod("path") func path() -> String { components.path }
    @ObjCMethod("setPath:") func setPath(_ value: String?) { components.path = value ?? "" }
    @ObjCMethod("query") func query() -> String? { components.query }
    @ObjCMethod("setQuery:") func setQuery(_ value: String?) { components.query = value }
    @ObjCMethod("fragment") func fragment() -> String? { components.fragment }
    @ObjCMethod("setFragment:") func setFragment(_ value: String?) { components.fragment = value }

    @ObjCMethod("percentEncodedUser") func percentEncodedUser() -> String? { components.percentEncodedUser }
    @ObjCMethod("setPercentEncodedUser:") func setPercentEncodedUser(_ value: String?) { components.percentEncodedUser = value }
    @ObjCMethod("percentEncodedPassword") func percentEncodedPassword() -> String? { components.percentEncodedPassword }
    @ObjCMethod("setPercentEncodedPassword:")
    func setPercentEncodedPassword(_ value: String?) { components.percentEncodedPassword = value }
    @ObjCMethod("percentEncodedHost") func percentEncodedHost() -> String? { components.percentEncodedHost }
    @ObjCMethod("setPercentEncodedHost:") func setPercentEncodedHost(_ value: String?) { components.percentEncodedHost = value }
    @ObjCMethod("encodedHost") func encodedHost() -> String? { components.encodedHost }
    @ObjCMethod("percentEncodedPath") func percentEncodedPath() -> String { components.percentEncodedPath }
    @ObjCMethod("setPercentEncodedPath:") func setPercentEncodedPath(_ value: String?) { components.percentEncodedPath = value ?? "" }
    @ObjCMethod("percentEncodedQuery") func percentEncodedQuery() -> String? { components.percentEncodedQuery }
    @ObjCMethod("setPercentEncodedQuery:") func setPercentEncodedQuery(_ value: String?) { components.percentEncodedQuery = value }
    @ObjCMethod("percentEncodedFragment") func percentEncodedFragment() -> String? { components.percentEncodedFragment }
    @ObjCMethod("setPercentEncodedFragment:")
    func setPercentEncodedFragment(_ value: String?) { components.percentEncodedFragment = value }

    @ObjCMethod("queryItems") func queryItems() -> UnsafeMutableRawPointer? { URLComponentsObjects.items(components.queryItems) }

    @ObjCMethod("setQueryItems:")
    func setQueryItems(_ items: ObjCObject?) { components.queryItems = URLComponentsObjects.items(from: items) }

    @ObjCMethod("percentEncodedQueryItems")
    func percentEncodedQueryItems() -> UnsafeMutableRawPointer? { URLComponentsObjects.items(components.percentEncodedQueryItems) }

    @ObjCMethod("setPercentEncodedQueryItems:")
    func setPercentEncodedQueryItems(_ items: ObjCObject?) {
        components.percentEncodedQueryItems = URLComponentsObjects.items(from: items)
    }

    private func range(_ range: Range<String.Index>?) -> NSRange { URLComponentsObjects.range(range, in: components.string) }

    @ObjCMethod("rangeOfScheme") func rangeOfScheme() -> NSRange { range(components.rangeOfScheme) }
    @ObjCMethod("rangeOfUser") func rangeOfUser() -> NSRange { range(components.rangeOfUser) }
    @ObjCMethod("rangeOfPassword") func rangeOfPassword() -> NSRange { range(components.rangeOfPassword) }
    @ObjCMethod("rangeOfHost") func rangeOfHost() -> NSRange { range(components.rangeOfHost) }
    @ObjCMethod("rangeOfPort") func rangeOfPort() -> NSRange { range(components.rangeOfPort) }
    @ObjCMethod("rangeOfPath") func rangeOfPath() -> NSRange { range(components.rangeOfPath) }
    @ObjCMethod("rangeOfQuery") func rangeOfQuery() -> NSRange { range(components.rangeOfQuery) }
    @ObjCMethod("rangeOfFragment") func rangeOfFragment() -> NSRange { range(components.rangeOfFragment) }

    @ObjCMethod("description")
    func description() -> String {
        let c = components
        func show(_ value: String?) -> String { value ?? "(null)" }
        return "<NSURLComponents \(objcObject)> {scheme = \(show(c.scheme)), user = \(show(c.user)), password = \(show(c.password)), "
            + "host = \(show(c.host)), port = \(c.port.map(String.init) ?? "(null)"), path = \(c.path), query = \(show(c.query)), "
            + "fragment = \(show(c.fragment))}"
    }
}

/// NSURLQueryItem.
@ObjCClass("NSURLQueryItem")
public final class NSURLQueryItem: NSObject {
    override public class func didDefineObjCClass(_ cls: ObjCClass) {
        NSObject.registerObjCCategoryStorageAllocated(cls)
        URLComponentsObjects.itemClass = cls.storage
    }

    var item: URLQueryItem { URLComponentsObjects.item(objcObject) ?? URLQueryItem(name: "", value: nil) }

    @ObjCMethod("dealloc")
    func dealloc() {
        Storage.set(objcObject, nil)
        ObjC.superDealloc(objcObject, from: URLComponentsObjects.itemClass)
    }

    @ObjCClassMethod("queryItemWithName:value:")
    static func make(_ cls: ObjCClass, name: String, value: String?) -> UnsafeMutableRawPointer? {
        guard let object = Storage.allocate(cls.pointer) else { return nil }
        Storage.set(object, QueryItemStorage(URLQueryItem(name: name, value: value)))
        return ObjC.autorelease(object)
    }

    @ObjCMethod("initWithName:value:")
    func initialize(name: String, value: String?) -> Self {
        Storage.set(objcObject, QueryItemStorage(URLQueryItem(name: name, value: value)))
        return self
    }

    @ObjCMethod("name") func name() -> String { item.name }
    @ObjCMethod("value") func value() -> String? { item.value }
    @ObjCMethod("copyWithZone:") func copy(zone: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer { ObjC.retain(objcObject)! }
    @ObjCMethod("isEqual:") func isEqual(_ other: ObjCObject?) -> Bool { URLComponentsObjects.item(other?.id) == item }
    @ObjCMethod("hash") func hash() -> UInt { UInt(bitPattern: item.hashValue) }

    @ObjCMethod("description")
    func description() -> String { "<NSURLQueryItem \(objcObject)> {name = \(item.name), value = \(item.value ?? "(null)")}" }
}
