import Glibc
import PerryObjCInterop

// Mac apps' alone: armv7 runs only iOS apps, so it has none of this.
#if !arch(arm)
// Launch Services' shared file lists: the recent documents, applications
// and servers, favorites and login items that macOS keeps for the Finder
// and the Apple menu. Nothing reads them here, so each list is the
// process's own and keeps only its items' URLs.

/// The lists' names and properties, and the two positions an item is
/// inserted at. Those are LSSharedFileListItemRefs on macOS that apps only
/// pass back; here they're string objects, which retain and release safely.
@ObjCConstants
enum SharedFileListConstants {
    static let kLSSharedFileListFavoriteVolumes = "com.apple.LSSharedFileList.FavoriteVolumes"
    static let kLSSharedFileListFavoriteItems = "com.apple.LSSharedFileList.FavoriteItems"
    static let kLSSharedFileListRecentApplicationItems = "com.apple.LSSharedFileList.RecentApplications"
    static let kLSSharedFileListRecentDocumentItems = "com.apple.LSSharedFileList.RecentDocuments"
    static let kLSSharedFileListRecentServerItems = "com.apple.LSSharedFileList.RecentServers"
    static let kLSSharedFileListSessionLoginItems = "com.apple.LSSharedFileList.SessionLoginItems"
    static let kLSSharedFileListGlobalLoginItems = "com.apple.LSSharedFileList.GlobalLoginItems"
    static let kLSSharedFileListRecentItemsMaxAmount = "com.apple.LSSharedFileList.RecentItemsMaxAmount"
    static let kLSSharedFileListVolumesComputerVisible = "com.apple.LSSharedFileList.VolumesComputerVisible"
    static let kLSSharedFileListVolumesIDiskVisible = "com.apple.LSSharedFileList.VolumesIDiskVisible"
    static let kLSSharedFileListVolumesNetworkVisible = "com.apple.LSSharedFileList.VolumesNetworkVisible"
    static let kLSSharedFileListItemHidden = "com.apple.LSSharedFileList.ItemIsHidden"
    static let kLSSharedFileListLoginItemHidden = "com.apple.loginitem.HideOnLaunch"
    static let kLSSharedFileListItemBeforeFirst = "kLSSharedFileListItemBeforeFirst"
    static let kLSSharedFileListItemLast = "kLSSharedFileListItemLast"
}

final class SharedFileListState {
    let name: String
    var urls: [NSObject] = []
    init(name: String) { self.name = name }
}

/// An LSSharedFileListRef.
@ObjCClass("PerryLSSharedFileList")
public final class SharedFileList: NSObject {
    static let states = StateTable<SharedFileListState>()

    @ObjCMethod("dealloc")
    func dealloc() {
        SharedFileList.states.remove(objcObject)
        ObjCRuntime.superDealloc(objcObject, definedOn: SharedFileList.objCClass.pointer)
    }

    static func state(_ list: UnsafeMutableRawPointer?) -> SharedFileListState? { states[list] }
}

/// An LSSharedFileListItemRef: an item's URL.
@ObjCClass("PerryLSSharedFileListItem")
public final class SharedFileListItem: NSObject {
    static let urls = StateTable<NSObject>()

    @ObjCMethod("dealloc")
    func dealloc() {
        SharedFileListItem.urls.remove(objcObject)
        ObjCRuntime.superDealloc(objcObject, definedOn: SharedFileListItem.objCClass.pointer)
    }
}

@ObjCWrapper("NSNumber")
class SharedFileListNumber: NSObject {
    @ObjCClassMethod("numberWithInt:") static func make(_ value: Int32) -> SharedFileListNumber
}

/// LSSharedFileListRef LSSharedFileListCreate(CFAllocatorRef, CFStringRef listType,
/// CFTypeRef listOptions): a new list (+1).
@c(_LSSharedFileListCreate)
public func LSSharedFileListCreate(_ allocator: UnsafeRawPointer?, _ type: UnsafeMutableRawPointer?, _ options: UnsafeRawPointer?) -> UnsafeMutableRawPointer? {
    guard let type else { return nil }
    let list = SharedFileList.objCClass.ownedInstance()
    SharedFileList.states.set(list, SharedFileListState(name: String(objCArgument: type)))
    return list
}

/// CFTypeRef LSSharedFileListCopyProperty(LSSharedFileListRef, CFStringRef):
/// the recent lists' size, macOS's default of 10; nothing else is set.
@c(_LSSharedFileListCopyProperty)
public func LSSharedFileListCopyProperty(_ list: UnsafeMutableRawPointer?, _ name: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer? {
    guard SharedFileList.state(list) != nil, let name,
          String(objCArgument: name) == SharedFileListConstants.kLSSharedFileListRecentItemsMaxAmount else { return nil }
    return ObjCRuntime.retain(SharedFileListNumber.make(10).objcObject)
}

@c(_LSSharedFileListSetProperty)
public func LSSharedFileListSetProperty(_ list: UnsafeMutableRawPointer?, _ name: UnsafeRawPointer?, _ value: UnsafeRawPointer?) -> Int32 {
    SharedFileList.state(list) == nil ? -50 : 0
}

/// LSSharedFileListItemRef LSSharedFileListInsertItemURL(LSSharedFileListRef,
/// LSSharedFileListItemRef insertAfter, CFStringRef displayName, IconRef,
/// CFURLRef, CFDictionaryRef propertiesToSet, CFArrayRef propertiesToClear):
/// the new item (+1), first or last as asked. An item already there for
/// the URL moves.
@c(_LSSharedFileListInsertItemURL)
public func LSSharedFileListInsertItemURL(_ list: UnsafeMutableRawPointer?, _ after: UnsafeMutableRawPointer?, _ name: UnsafeRawPointer?,
                                          _ icon: UnsafeRawPointer?, _ url: UnsafeMutableRawPointer?, _ set: UnsafeRawPointer?,
                                          _ clear: UnsafeRawPointer?) -> UnsafeMutableRawPointer? {
    guard let state = SharedFileList.state(list), let url else { return nil }
    let object = NSObject(url)
    let path = object.as(DisplayNameURL.self)?.path()
    state.urls.removeAll { $0.as(DisplayNameURL.self)?.path() == path }
    let first = after.map { String(objCArgument: $0) == SharedFileListConstants.kLSSharedFileListItemBeforeFirst } ?? false
    if first { state.urls.insert(object, at: 0) } else { state.urls.append(object) }
    let item = SharedFileListItem.objCClass.ownedInstance()
    SharedFileListItem.urls.set(item, object)
    return item
}

@c(_LSSharedFileListRemoveAllItems)
public func LSSharedFileListRemoveAllItems(_ list: UnsafeMutableRawPointer?) -> Int32 {
    guard let state = SharedFileList.state(list) else { return -50 }
    state.urls = []
    return 0
}

/// OSStatus LSSharedFileListItemRemove(LSSharedFileListRef, LSSharedFileListItemRef).
@c(_LSSharedFileListItemRemove)
public func LSSharedFileListItemRemove(_ list: UnsafeMutableRawPointer?, _ item: UnsafeMutableRawPointer?) -> Int32 {
    guard let state = SharedFileList.state(list), let url = SharedFileListItem.urls[item] else { return -50 }
    state.urls.removeAll { $0.objcObject == url.objcObject }
    return 0
}

/// CFURLRef LSSharedFileListItemCopyResolvedURL(LSSharedFileListItemRef,
/// LSSharedFileListResolutionFlags, CFErrorRef *): the item's URL (+1).
@c(_LSSharedFileListItemCopyResolvedURL)
public func LSSharedFileListItemCopyResolvedURL(_ item: UnsafeMutableRawPointer?, _ flags: UInt32,
                                                _ error: UnsafeMutablePointer<UnsafeMutableRawPointer?>?) -> UnsafeMutableRawPointer? {
    error?.pointee = nil
    return SharedFileListItem.urls[item].flatMap { ObjCRuntime.retain($0.objcObject) }
}
#endif
