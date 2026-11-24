import CPerryFoundation
import PerryObjCInterop

/// An item an app and an extension pass in a request: a title, text and
/// attachments (item providers), all kept in its user info dictionary under
/// NSExtensionItemAttributedTitleKey, NSExtensionItemAttributedContentTextKey
/// and NSExtensionItemAttachmentsKey, as Darwin keeps them. Darwin stores
/// the attributed strings there as RTF data, to send them to the other
/// process; here they are kept as they are.
final class ExtensionItemStorage {
    /// The user info, mutable; nil once set to nil.
    var userInfo: ObjCObject?

    init(userInfo: ObjCObject?) {
        self.userInfo = userInfo
    }
}

private func itemClassNamed(_ name: String) -> id? {
    name.withCString { ObjC.getClass($0) }.map { UnsafeMutableRawPointer($0) }
}

/// A new mutable copy of a dictionary (+1), or an empty one.
private func mutableDictionary(_ dictionary: id?) -> ObjCObject? {
    if let dictionary {
        return ObjC.send(dictionary, ObjC.selector("mutableCopy")).map { ObjCObject(objCOwned: $0) }
    }
    return ObjC.send(ObjC.send(itemClassNamed("NSMutableDictionary"), ObjC.selector("alloc")), ObjC.selector("init"))
        .map { ObjCObject(objCOwned: $0) }
}

@ObjCClass("NSExtensionItem")
open class NSExtensionItem: NSObject {
    nonisolated(unsafe) static var extensionItemClass: Class!

    static let attributedTitleKey = "NSExtensionItemAttributedTitleKey"
    static let attributedContentTextKey = "NSExtensionItemAttributedContentTextKey"
    static let attachmentsKey = "NSExtensionItemAttachmentsKey"
    /// The key of the user info in an archive, Darwin's.
    static let archiveKey = "NSExtensionItemUserInfoKey"

    override public class func didDefineObjCClass(_ cls: ObjCClass) {
        NSObject.registerObjCCategoryStorageAllocated(cls)
        extensionItemClass = cls.storage
    }

    var storage: ExtensionItemStorage {
        if let storage = Storage.get(objcObject, as: ExtensionItemStorage.self) { return storage }
        let storage = ExtensionItemStorage(userInfo: mutableDictionary(nil))
        Storage.set(objcObject, storage)
        return storage
    }

    @ObjCMethod("init")
    func initialize() -> Self {
        _ = storage
        return self
    }

    private func entry(_ key: String) -> UnsafeMutableRawPointer? {
        guard let userInfo = storage.userInfo else { return nil }
        return ObjC.send(userInfo.id, Selectors.objectForKey, Strings.autoreleased(key))
    }

    /// Sets a copy of the value under the key, or removes the key for nil;
    /// the user info is made again if it was set to nil.
    private func setEntry(_ key: String, _ value: UnsafeMutableRawPointer?) {
        let storage = self.storage
        if storage.userInfo == nil {
            guard value != nil else { return }
            storage.userInfo = mutableDictionary(nil)
        }
        guard let userInfo = storage.userInfo?.id else { return }
        let keyObject = Strings.autoreleased(key)
        if let value, let copy = ObjC.send(value, Selectors.copyWithZone, nil) {
            _ = ObjC.send(userInfo, ObjC.selector("setObject:forKey:"), copy, keyObject)
            ObjC.release(copy)
        } else {
            _ = ObjC.send(userInfo, ObjC.selector("removeObjectForKey:"), keyObject)
        }
    }

    @ObjCMethod("attributedTitle") func attributedTitle() -> UnsafeMutableRawPointer? { entry(Self.attributedTitleKey) }
    @ObjCMethod("setAttributedTitle:")
    func setAttributedTitle(_ title: UnsafeMutableRawPointer?) { setEntry(Self.attributedTitleKey, title) }

    @ObjCMethod("attributedContentText") func attributedContentText() -> UnsafeMutableRawPointer? { entry(Self.attributedContentTextKey) }
    @ObjCMethod("setAttributedContentText:")
    func setAttributedContentText(_ text: UnsafeMutableRawPointer?) { setEntry(Self.attributedContentTextKey, text) }

    @ObjCMethod("attachments") func attachments() -> UnsafeMutableRawPointer? { entry(Self.attachmentsKey) }
    @ObjCMethod("setAttachments:")
    func setAttachments(_ attachments: UnsafeMutableRawPointer?) { setEntry(Self.attachmentsKey, attachments) }

    @ObjCMethod("userInfo") func userInfo() -> UnsafeMutableRawPointer? { storage.userInfo?.id }

    /// A copy of the dictionary, the title, text and attachments with it.
    @ObjCMethod("setUserInfo:")
    func setUserInfo(_ userInfo: UnsafeMutableRawPointer?) {
        storage.userInfo = userInfo.flatMap { mutableDictionary($0) }
    }

    @ObjCMethod("copyWithZone:")
    func copy(zone: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer? {
        guard let copy = Storage.allocate(ObjC.objectGetClass(objcObject).map { UnsafeMutableRawPointer($0) }) else { return nil }
        Storage.set(copy, ExtensionItemStorage(userInfo: storage.userInfo.flatMap { mutableDictionary($0.id) }))
        return copy
    }

    @ObjCClassMethod("supportsSecureCoding") static func supportsSecureCoding(_ cls: ObjCClass) -> Bool { true }

    @ObjCMethod("encodeWithCoder:")
    func encode(coder: UnsafeMutableRawPointer?) {
        _ = ObjC.send(coder, ObjC.selector("encodeObject:forKey:"), storage.userInfo?.id, Strings.autoreleased(Self.archiveKey))
    }

    @ObjCMethod("initWithCoder:")
    func initialize(coder: UnsafeMutableRawPointer?) -> Self {
        let userInfo = ObjC.send(coder, ObjC.selector("decodeObjectForKey:"), Strings.autoreleased(Self.archiveKey))
        Storage.set(objcObject, ExtensionItemStorage(userInfo: userInfo.flatMap { mutableDictionary($0) }))
        return self
    }

    @ObjCMethod("description")
    func description() -> String {
        let info = storage.userInfo.flatMap { Strings.value(of: ObjC.send($0.id, ObjC.selector("description"))) } ?? "(null)"
        return "<\(ObjC.className(objcObject)): \(objcObject)> - userInfo: \(info)"
    }

    @ObjCMethod("dealloc")
    func dealloc() {
        Storage.set(objcObject, nil)
        ObjC.superDealloc(objcObject, from: NSExtensionItem.extensionItemClass)
    }
}
