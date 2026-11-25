import Glibc
import PerryObjCInterop

// Mac apps' alone: armv7 runs only iOS apps, so it has none of this.
#if !arch(arm)
// Spotlight's Metadata framework. There is no index here: an item's
// attributes are read from the file system (its path, name, content type,
// size and dates), and a query finds nothing, finishing at once as an
// empty search would, so apps waiting for its notification go on.

@ObjCConstants
enum MetadataConstants {
    static let kMDItemPath = "kMDItemPath"
    static let kMDItemFSName = "kMDItemFSName"
    static let kMDItemDisplayName = "kMDItemDisplayName"
    static let kMDItemContentType = "kMDItemContentType"
    static let kMDItemKind = "kMDItemKind"
    static let kMDItemFSSize = "kMDItemFSSize"
    static let kMDItemFSCreationDate = "kMDItemFSCreationDate"
    static let kMDItemFSContentChangeDate = "kMDItemFSContentChangeDate"
    static let kMDItemContentModificationDate = "kMDItemContentModificationDate"
    static let kMDQueryDidFinishNotification = "kMDQueryDidFinishNotification"
    static let kMDQueryDidUpdateNotification = "kMDQueryDidUpdateNotification"
    static let kMDQueryProgressNotification = "kMDQueryProgressNotification"
    static let kMDQueryUpdateAddedItems = "kMDQueryUpdateAddedItems"
    static let kMDQueryUpdateChangedItems = "kMDQueryUpdateChangedItems"
    static let kMDQueryUpdateRemovedItems = "kMDQueryUpdateRemovedItems"
    static let kMDQueryResultContentRelevance = "kMDQueryResultContentRelevance"
}

/// MDItemRef's and MDQueryRef's CFTypeIDs: ones no CoreFoundation type has.
private let itemTypeID: UInt = 0x4D44_4974   // 'MDIt'
private let queryTypeID: UInt = 0x4D44_5175   // 'MDQu'

@ObjCWrapper("NSNumber")
class MetadataNumber: NSObject {
    @ObjCClassMethod("numberWithLongLong:") static func make(_ value: Int64) -> MetadataNumber
}

@ObjCWrapper("NSDate")
class MetadataDate: NSObject {
    @ObjCClassMethod("dateWithTimeIntervalSince1970:") static func make(_ seconds: Double) -> MetadataDate
}

/// An MDItemRef: a file, by path.
@ObjCClass("PerryMDItem")
public final class MetadataItem: NSObject {
    static let paths = StateTable<NSObject>()

    @ObjCMethod("dealloc")
    func dealloc() {
        MetadataItem.paths.remove(objcObject)
        ObjCRuntime.superDealloc(objcObject, definedOn: MetadataItem.objCClass.pointer)
    }

    @ObjCMethod("_cfTypeID") func cfTypeID() -> UInt { itemTypeID }

    /// The item's attributes there are values for, by name.
    static func attributes(_ item: UnsafeMutableRawPointer?) -> [(String, NSObject)] {
        guard let pathObject = paths[item] else { return [] }
        let path = String(objCArgument: pathObject.objcObject)
        let leaf = String(path.split(separator: "/").last ?? "/")
        var info = stat()
        guard stat(path, &info) == 0 else { return [] }
        let folder = info.st_mode & 0o170000 == 0o040000
        let dot = leaf.lastIndex(of: ".").flatMap { $0 == leaf.startIndex ? nil : $0 }
        let pathExtension = dot.map { String(leaf[leaf.index(after: $0)...]) } ?? ""
        let type = folder && pathExtension.isEmpty ? "public.folder"
            : Database.preferred(tag: pathExtension, tagClass: TagClass.filenameExtension, conformingTo: nil).identifier
        let modified = Double(info.st_mtim.tv_sec) + Double(info.st_mtim.tv_nsec) / 1e9
        let changed = Double(info.st_ctim.tv_sec) + Double(info.st_ctim.tv_nsec) / 1e9
        return [
            (MetadataConstants.kMDItemPath, NSObject.string(path)),
            (MetadataConstants.kMDItemFSName, NSObject.string(leaf)),
            (MetadataConstants.kMDItemDisplayName, NSObject.string(leaf)),
            (MetadataConstants.kMDItemContentType, NSObject.string(type)),
            (MetadataConstants.kMDItemFSSize, MetadataNumber.make(Int64(info.st_size))),
            (MetadataConstants.kMDItemFSCreationDate, MetadataDate.make(min(modified, changed))),
            (MetadataConstants.kMDItemFSContentChangeDate, MetadataDate.make(modified)),
            (MetadataConstants.kMDItemContentModificationDate, MetadataDate.make(modified)),
        ]
    }
}

/// An MDQueryRef: it gathers nothing.
@ObjCClass("PerryMDQuery")
public final class MetadataQuery: NSObject {
    @ObjCMethod("_cfTypeID") func cfTypeID() -> UInt { queryTypeID }
}

@c(_MDItemGetTypeID) public func MDItemGetTypeID() -> UInt { itemTypeID }
@c(_MDQueryGetTypeID) public func MDQueryGetTypeID() -> UInt { queryTypeID }

@ObjCWrapper("NSURL")
class MetadataURL: NSObject {
    @ObjCMethod("path") func path() -> String?
}

/// MDItemRef MDItemCreateWithURL(CFAllocatorRef, CFURLRef): an item for a
/// file that exists (+1), else NULL.
@c(_MDItemCreateWithURL)
public func MDItemCreateWithURL(_ allocator: UnsafeRawPointer?, _ url: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer? {
    guard let url, let path = MetadataURL(url).path(), access(path, F_OK) == 0 else { return nil }
    let item = MetadataItem.objCClass.ownedInstance()
    MetadataItem.paths.set(item, NSObject.string(path))
    return item
}

@c(_MDItemCreate)
public func MDItemCreate(_ allocator: UnsafeRawPointer?, _ path: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer? {
    guard let path else { return nil }
    let text = String(objCArgument: path)
    guard access(text, F_OK) == 0 else { return nil }
    let item = MetadataItem.objCClass.ownedInstance()
    MetadataItem.paths.set(item, NSObject.string(text))
    return item
}

/// CFTypeRef MDItemCopyAttribute(MDItemRef, CFStringRef): +1, or NULL.
@c(_MDItemCopyAttribute)
public func MDItemCopyAttribute(_ item: UnsafeMutableRawPointer?, _ name: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer? {
    guard let name else { return nil }
    let key = String(objCArgument: name)
    return MetadataItem.attributes(item).first { $0.0 == key }.flatMap { ObjCRuntime.retain($0.1.objcObject) }
}

/// CFDictionaryRef MDItemCopyAttributes(MDItemRef, CFArrayRef names): +1.
@c(_MDItemCopyAttributes)
public func MDItemCopyAttributes(_ item: UnsafeMutableRawPointer?, _ names: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer? {
    guard MetadataItem.paths[item] != nil else { return nil }
    let wanted = Set(names.map { NSArray($0).elements.map { String(objCArgument: $0.objcObject) } } ?? [])
    let dictionary = NSMutableDictionary.of(MetadataItem.attributes(item).filter { names == nil || wanted.contains($0.0) })
    return ObjCRuntime.retain(dictionary.objcObject)
}

@c(_MDItemCopyAttributeNames)
public func MDItemCopyAttributeNames(_ item: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer? {
    guard MetadataItem.paths[item] != nil else { return nil }
    let array = NSMutableArray.empty()
    for (name, _) in MetadataItem.attributes(item) { array.add(NSObject.string(name)) }
    return ObjCRuntime.retain(array.objcObject)
}

/// MDQueryRef MDQueryCreate(CFAllocatorRef, CFStringRef query, CFArrayRef
/// valueListAttrs, CFArrayRef sortingAttrs): +1.
@c(_MDQueryCreate)
public func MDQueryCreate(_ allocator: UnsafeRawPointer?, _ query: UnsafeRawPointer?, _ values: UnsafeRawPointer?,
                          _ sorting: UnsafeRawPointer?) -> UnsafeMutableRawPointer? {
    query == nil ? nil : MetadataQuery.objCClass.ownedInstance()
}

@c(_MDQuerySetSearchScope)
public func MDQuerySetSearchScope(_ query: UnsafeRawPointer?, _ scopes: UnsafeRawPointer?, _ options: UInt32) {}

@c(_MDQuerySetSortComparator)
public func MDQuerySetSortComparator(_ query: UnsafeRawPointer?, _ comparator: UnsafeRawPointer?, _ context: UnsafeRawPointer?) {}

/// void MDQuerySetBatchingParameters(MDQueryRef, MDQueryBatchingParams): the
/// parameters, six size_t values passed in memory, change nothing.
@c(_MDQuerySetBatchingParameters)
public func MDQuerySetBatchingParameters(_ query: UnsafeRawPointer?) {}

/// MDQueryBatchingParams MDQueryGetBatchingParameters(MDQueryRef): the
/// 48-byte struct comes back through the hidden result pointer. These are
/// Spotlight's defaults.
@c(_MDQueryGetBatchingParameters)
public func MDQueryGetBatchingParameters(_ result: UnsafeMutableRawPointer?, _ query: UnsafeRawPointer?) -> UnsafeMutableRawPointer? {
    guard let result else { return nil }
    let defaults: [Int] = [1000, 1000, 1000, 1000, 1000, 1000]
    for (index, value) in defaults.enumerated() { result.storeBytes(of: value, toByteOffset: index * 8, as: Int.self) }
    return result
}

@c(_MDQueryDisableUpdates) public func MDQueryDisableUpdates(_ query: UnsafeRawPointer?) {}
@c(_MDQueryEnableUpdates) public func MDQueryEnableUpdates(_ query: UnsafeRawPointer?) {}
@c(_MDQueryStop) public func MDQueryStop(_ query: UnsafeRawPointer?) {}
@c(_MDQueryGetResultCount) public func MDQueryGetResultCount(_ query: UnsafeRawPointer?) -> Int { 0 }
@c(_MDQueryGetResultAtIndex) public func MDQueryGetResultAtIndex(_ query: UnsafeRawPointer?, _ index: Int) -> UnsafeRawPointer? { nil }
@c(_MDQueryIsGatheringComplete) public func MDQueryIsGatheringComplete(_ query: UnsafeRawPointer?) -> UInt8 { 1 }

/// Boolean MDQueryExecute(MDQueryRef, CFOptionFlags): starts the search,
/// which finds nothing: kMDQueryDidFinishNotification is posted to the
/// local center from the main queue, after the caller has returned.
@c(_MDQueryExecute)
public func MDQueryExecute(_ query: UnsafeMutableRawPointer?, _ options: UInt) -> UInt8 {
    guard let query else { return 0 }
    typealias Async = @convention(c) (UnsafeMutableRawPointer?, UnsafeMutableRawPointer?, @convention(c) (UnsafeMutableRawPointer?) -> Void) -> Void
    let dispatch = "/usr/lib/system/libdispatch.dylib"
    guard let lookup = providerSymbolLookup,
          let async = dispatch.withCString({ library in lookup(library, "_dispatch_async_f") }),
          let mainQueue = dispatch.withCString({ library in lookup(library, "__dispatch_main_q") }) else { return 1 }
    _ = ObjCRuntime.retain(query)
    unsafeBitCast(async, to: Async.self)(mainQueue, query) { query in
        typealias Center = @convention(c) () -> UnsafeMutableRawPointer?
        typealias Post = @convention(c) (UnsafeMutableRawPointer?, UnsafeMutableRawPointer?, UnsafeRawPointer?, UnsafeRawPointer?, UInt8) -> Void
        let foundation = "/System/Library/Frameworks/CoreFoundation.framework/CoreFoundation"
        if let lookup = providerSymbolLookup,
           let center = foundation.withCString({ library in lookup(library, "_CFNotificationCenterGetLocalCenter") }),
           let post = foundation.withCString({ library in lookup(library, "_CFNotificationCenterPostNotification") }) {
            let name = NSObject.string(MetadataConstants.kMDQueryDidFinishNotification)
            unsafeBitCast(post, to: Post.self)(unsafeBitCast(center, to: Center.self)(), name.objcObject, query, nil, 1)
        }
        ObjCRuntime.release(query)
    }
    return 1
}
#endif
