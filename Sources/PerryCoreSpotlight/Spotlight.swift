import Glibc
import PerryObjCInterop

// CSSearchableIndex, CSSearchableItem and CSSearchableItemAttributeSet.

/// Calls a completion handler, `void (^)(NSError *)`.
private func complete(_ handler: ObjCBlock?, error: NSObject? = nil) {
    guard let handler else { return }
    handler.function(as: (@convention(c) (UnsafeMutableRawPointer?, UnsafeMutableRawPointer?) -> Void).self)(handler.object, error?.objcObject)
}

/// CSSearchableIndex: takes items and forgets them.
@ObjCClass("CSSearchableIndex")
open class CSSearchableIndex: NSObject {
    nonisolated(unsafe) static var shared = CSSearchableIndex()
    var delegate: NSObject?

    @ObjCMethod("init")
    public required override init() { super.init() }

    @ObjCMethod("initWithName:") func initialize(name: NSObject?) -> Self { self }
    @ObjCMethod("initWithName:protectionClass:") func initialize(name: NSObject?, protectionClass: NSObject?) -> Self { self }

    @ObjCClassMethod("defaultSearchableIndex") static func defaultIndex() -> CSSearchableIndex { shared }
    @ObjCClassMethod("isIndexingAvailable") static func isIndexingAvailable() -> Bool { true }

    @ObjCMethod("indexDelegate") func indexDelegate() -> NSObject? { delegate }
    @ObjCMethod("setIndexDelegate:") func setIndexDelegate(_ delegate: NSObject?) { self.delegate = delegate }

    @ObjCMethod("indexSearchableItems:completionHandler:")
    func index(_ items: NSObject?, completionHandler: ObjCBlock?) { complete(completionHandler) }

    @ObjCMethod("deleteSearchableItemsWithIdentifiers:completionHandler:")
    func delete(identifiers: NSObject?, completionHandler: ObjCBlock?) { complete(completionHandler) }

    @ObjCMethod("deleteSearchableItemsWithDomainIdentifiers:completionHandler:")
    func delete(domainIdentifiers: NSObject?, completionHandler: ObjCBlock?) { complete(completionHandler) }

    @ObjCMethod("deleteAllSearchableItemsWithCompletionHandler:")
    func deleteAll(completionHandler: ObjCBlock?) { complete(completionHandler) }

    @ObjCMethod("beginIndexBatch") func beginIndexBatch() {}

    @ObjCMethod("endIndexBatchWithClientState:completionHandler:")
    func endIndexBatch(clientState: NSObject?, completionHandler: ObjCBlock?) { complete(completionHandler) }

    /// No client state was ever kept: nil data, no error.
    @ObjCMethod("fetchLastClientStateWithCompletionHandler:")
    func fetchLastClientState(completionHandler: ObjCBlock?) {
        guard let handler = completionHandler else { return }
        handler.function(as: (@convention(c) (UnsafeMutableRawPointer?, UnsafeMutableRawPointer?, UnsafeMutableRawPointer?) -> Void).self)(handler.object, nil, nil)
    }
}

/// CSSearchableItem: an identifier, a domain and the attributes to index.
@ObjCClass("CSSearchableItem")
open class CSSearchableItem: NSObject {
    var identifier: String = ""
    var domain: String?
    var attributes: NSObject?
    var expiration: NSObject?
    var update = false

    @ObjCMethod("init")
    public required override init() { super.init() }

    @ObjCMethod("initWithUniqueIdentifier:domainIdentifier:attributeSet:")
    func initialize(uniqueIdentifier: String?, domainIdentifier: String?, attributeSet: NSObject?) -> Self {
        identifier = uniqueIdentifier ?? ""
        domain = domainIdentifier
        attributes = attributeSet
        return self
    }

    @ObjCMethod("uniqueIdentifier") func uniqueIdentifier() -> String { identifier }
    @ObjCMethod("setUniqueIdentifier:") func setUniqueIdentifier(_ value: String?) { identifier = value ?? "" }
    @ObjCMethod("domainIdentifier") func domainIdentifier() -> String? { domain }
    @ObjCMethod("setDomainIdentifier:") func setDomainIdentifier(_ value: String?) { domain = value }
    @ObjCMethod("attributeSet") func attributeSet() -> NSObject? { attributes }
    @ObjCMethod("setAttributeSet:") func setAttributeSet(_ value: NSObject?) { attributes = value }
    @ObjCMethod("expirationDate") func expirationDate() -> NSObject? { expiration }
    @ObjCMethod("setExpirationDate:") func setExpirationDate(_ value: NSObject?) { expiration = value }
    @ObjCMethod("isUpdate") func isUpdate() -> Bool { update }
    @ObjCMethod("setIsUpdate:") func setIsUpdate(_ value: Bool) { update = value }

    /// iOS 18's link to an App Intents entity, which nothing searches for.
    @ObjCMethod("associateAppEntity:priority:") func associateAppEntity(_ entity: NSObject?, priority: Int) {}
    @ObjCMethod("associateAppEntity:") func associateAppEntity(_ entity: NSObject?) {}
}

/// The values of each attribute set's properties, by the property's name.
/// An attribute set has some hundred properties, all objects; the class
/// answers any of them from here, as messages for it arrive.
enum AttributeValues {
    nonisolated(unsafe) private static var values: [UInt: [String: UnsafeMutableRawPointer]] = [:]
    nonisolated(unsafe) private static let lock: UnsafeMutablePointer<pthread_mutex_t> = {
        let lock = UnsafeMutablePointer<pthread_mutex_t>.allocate(capacity: 1)
        pthread_mutex_init(lock, nil)
        return lock
    }()

    static func set(_ object: UnsafeMutableRawPointer, _ key: String, _ value: UnsafeMutableRawPointer?) {
        pthread_mutex_lock(lock)
        let old = values[UInt(bitPattern: object)]?[key]
        if let value {
            values[UInt(bitPattern: object), default: [:]][key] = ObjCRuntime.retain(value)
        } else {
            values[UInt(bitPattern: object)]?[key] = nil
        }
        pthread_mutex_unlock(lock)
        ObjCRuntime.release(old)
    }

    static func get(_ object: UnsafeMutableRawPointer, _ key: String) -> UnsafeMutableRawPointer? {
        pthread_mutex_lock(lock)
        defer { pthread_mutex_unlock(lock) }
        return values[UInt(bitPattern: object)]?[key]
    }

    static func removeAll(_ object: UnsafeMutableRawPointer) {
        pthread_mutex_lock(lock)
        let removed = values.removeValue(forKey: UInt(bitPattern: object))
        pthread_mutex_unlock(lock)
        for value in removed?.values ?? [:].values { ObjCRuntime.release(value) }
    }

    /// The property a getter or setter selector names: "setTitle:" and
    /// "title" are "title", "isPlayable" is "playable".
    static func property(of name: String) -> String {
        var name = name
        if name.hasSuffix(":") { name.removeLast() }
        if name.hasPrefix("set"), name.count > 3 { name = String(name.dropFirst(3)) }
        else if name.hasPrefix("is"), name.count > 2, name.dropFirst(2).first?.isUppercase == true { name = String(name.dropFirst(2)) }
        return name.prefix(1).lowercased() + name.dropFirst()
    }
}

private let attributeSetter: @convention(c) (UnsafeMutableRawPointer, UnsafeRawPointer, UnsafeMutableRawPointer?) -> Void = { object, selector, value in
    AttributeValues.set(object, AttributeValues.property(of: ObjCSelector(selector).name), value)
}

private let attributeGetter: @convention(c) (UnsafeMutableRawPointer, UnsafeRawPointer) -> UnsafeMutableRawPointer? = { object, selector in
    AttributeValues.get(object, AttributeValues.property(of: ObjCSelector(selector).name))
}

/// CSSearchableItemAttributeSet: the properties of an item, each kept as
/// set. The setter and getter of any property are added as they are asked for.
@ObjCClass("CSSearchableItemAttributeSet")
open class CSSearchableItemAttributeSet: NSObject {
    @ObjCMethod("init")
    public required override init() { super.init() }

    @ObjCMethod("initWithItemContentType:") func initialize(itemContentType: NSObject?) -> Self { self }
    @ObjCMethod("initWithContentType:") func initialize(contentType: NSObject?) -> Self { self }

    deinit { AttributeValues.removeAll(objcObject) }

    @ObjCClassMethod("resolveInstanceMethod:")
    static func resolve(_ cls: ObjCClass, selector: ObjCSelector) -> Bool {
        let name = selector.name
        let colons = name.filter { $0 == ":" }.count
        if colons == 1, name.hasPrefix("set"), name.hasSuffix(":") {
            return ObjCRuntime.functions.addMethod(cls.pointer, selector.pointer, unsafeBitCast(attributeSetter, to: UnsafeRawPointer.self), "v24@0:8@16")
        }
        if colons == 0, !name.isEmpty {
            return ObjCRuntime.functions.addMethod(cls.pointer, selector.pointer, unsafeBitCast(attributeGetter, to: UnsafeRawPointer.self), "@16@0:8")
        }
        return false
    }
}
