import PerryObjCInterop
import SDL3Swift

// HIServices' Pasteboard Manager, which ApplicationServices re-exports and
// the loader finds in AppKit's provider: Carbon's calls on the pasteboards
// NSPasteboard has. The clipboard's text is SDL's clipboard, as
// NSPasteboard's is; other pasteboards, such as the find pasteboard, are
// this process's alone.

/// A pasteboard's contents, which every PasteboardRef of its name shares.
final class PasteboardContents {
    struct Flavor {
        var type: String
        /// nil for promised data, until the promise keeper puts it.
        var data: [UInt8]?
        var flags: UInt32
    }

    struct Item {
        var identifier: UnsafeMutableRawPointer?
        var flavors: [Flavor]
    }

    var items: [Item] = []
    var changeCount = 0
    /// The PasteboardRef that cleared it last, the only one that may put
    /// flavors.
    var owner: UnsafeMutableRawPointer?
    /// The owner's promise keeper and its context.
    var keeper: (function: PasteboardPromiseKeeper, context: UnsafeMutableRawPointer?, pasteboard: UnsafeMutableRawPointer)?
    /// The clipboard's text as last read from SDL or written to it.
    var clipboardText: String?

    nonisolated(unsafe) static var named: [String: PasteboardContents] = [:]
    nonisolated(unsafe) static var unnamed = 0

    static let clipboard = "com.apple.pasteboard.clipboard"
    static let utf8Text = "public.utf8-plain-text"
    static let utf16Text = "public.utf16-plain-text"

    /// The clipboard's text as an item of plain text flavors, if it has
    /// changed since the contents last had it.
    func readClipboard() {
        guard SDLSession.start() else { return }
        let text = SDL.clipboardText
        guard text != clipboardText else { return }
        clipboardText = text
        changeCount += 1
        owner = nil
        keeper = nil
        items = []
        guard !text.isEmpty else { return }
        let utf16 = text.utf16.flatMap { [UInt8(truncatingIfNeeded: $0), UInt8(truncatingIfNeeded: $0 >> 8)] }
        items = [Item(identifier: UnsafeMutableRawPointer(bitPattern: 1), flavors: [
            Flavor(type: PasteboardContents.utf8Text, data: Array(text.utf8), flags: 0),
            Flavor(type: PasteboardContents.utf16Text, data: utf16, flags: 0),
        ])]
    }

    /// Text put on the clipboard goes to SDL's, as NSPasteboard's does.
    func writeClipboard(_ type: String, _ data: [UInt8]) {
        let text: String
        switch type {
        case PasteboardContents.utf8Text: text = String(decoding: data, as: UTF8.self)
        case PasteboardContents.utf16Text:
            let units = stride(from: 0, to: data.count - 1, by: 2).map { UInt16(data[$0]) | UInt16(data[$0 + 1]) << 8 }
            text = String(decoding: units, as: UTF16.self)
        default: return
        }
        guard SDLSession.start() else { return }
        SDL.clipboardText = text
        clipboardText = text
        NSPasteboard.general?.changeCount += 1
    }
}

/// OSStatus (*PasteboardPromiseKeeperProcPtr)(PasteboardRef,
/// PasteboardItemID, CFStringRef flavorType, void *context).
public typealias PasteboardPromiseKeeper = @convention(c) (UnsafeMutableRawPointer?, UnsafeMutableRawPointer?, UnsafeMutableRawPointer?,
                                                     UnsafeMutableRawPointer?) -> Int32

/// A PasteboardRef: one client's view of a pasteboard, which sees changes
/// when it synchronizes.
@ObjCClass("PerryPasteboard")
final class Pasteboard: NSObject {
    var contents = PasteboardContents()
    var isClipboard = false
    /// The contents' change count when this client last synchronized.
    var synchronizedChangeCount = 0

    @ObjCMethod("init")
    public required override init() { super.init() }

    static func board(_ object: UnsafeMutableRawPointer?) -> Pasteboard? {
        object.flatMap { NSObject(objCArgument: $0).as(Pasteboard.self) }
    }

    func item(_ identifier: UnsafeMutableRawPointer?) -> Int? {
        contents.items.firstIndex { $0.identifier == identifier }
    }

    /// Asks the promise keeper for a promised flavor's data.
    func keepPromise(item: Int, flavor: Int) {
        guard contents.items[item].flavors[flavor].data == nil, let keeper = contents.keeper else { return }
        let identifier = contents.items[item].identifier
        _ = keeper.function(keeper.pasteboard, identifier, contents.items[item].flavors[flavor].type.objCArgument(), keeper.context)
    }
}

enum PasteboardStatus {
    static let success: Int32 = 0
    static let param: Int32 = -50
    static let badIndex: Int32 = -25131
    static let badItem: Int32 = -25132
    static let badFlavor: Int32 = -25133
    static let duplicateFlavor: Int32 = -25134
    static let notOwner: Int32 = -25135
    static let noPromiseKeeper: Int32 = -25136
}

/// OSStatus PasteboardCreate(CFStringRef name, PasteboardRef *): the named
/// pasteboard, or a new one of a unique name for NULL.
@c(_PasteboardCreate)
public func PasteboardCreate(_ name: UnsafeMutableRawPointer?, _ out: UnsafeMutablePointer<UnsafeMutableRawPointer?>?) -> Int32 {
    guard let out else { return PasteboardStatus.param }
    let key: String
    if let name {
        key = String(objCArgument: name)
    } else {
        PasteboardContents.unnamed += 1
        key = "com.apple.pasteboard.unique.\(PasteboardContents.unnamed)"
    }
    let contents = PasteboardContents.named[key] ?? PasteboardContents()
    PasteboardContents.named[key] = contents
    let board = Pasteboard()
    board.contents = contents
    board.isClipboard = key == PasteboardContents.clipboard
    if board.isClipboard { contents.readClipboard() }
    board.synchronizedChangeCount = contents.changeCount
    out.pointee = board.objCOwnedReturnValue()
    return PasteboardStatus.success
}

/// PasteboardSyncFlags PasteboardSynchronize(PasteboardRef):
/// kPasteboardModified if the contents changed since this client last
/// synchronized, and kPasteboardClientIsOwner if it cleared them last.
@c(_PasteboardSynchronize)
public func PasteboardSynchronize(_ object: UnsafeMutableRawPointer?) -> UInt32 {
    guard let board = Pasteboard.board(object) else { return 0 }
    if board.isClipboard { board.contents.readClipboard() }
    var flags: UInt32 = 0
    if board.synchronizedChangeCount != board.contents.changeCount {
        board.synchronizedChangeCount = board.contents.changeCount
        flags |= 1
    }
    if board.contents.owner == board.objcObject { flags |= 2 }
    return flags
}

/// Empties the pasteboard and makes this client its owner.
@c(_PasteboardClear)
public func PasteboardClear(_ object: UnsafeMutableRawPointer?) -> Int32 {
    guard let board = Pasteboard.board(object) else { return PasteboardStatus.param }
    let contents = board.contents
    contents.items = []
    contents.keeper = nil
    contents.changeCount += 1
    contents.owner = board.objcObject
    board.synchronizedChangeCount = contents.changeCount
    if board.isClipboard { contents.writeClipboard(PasteboardContents.utf8Text, []) }
    return PasteboardStatus.success
}

@c(_PasteboardGetItemCount)
public func PasteboardGetItemCount(_ object: UnsafeMutableRawPointer?, _ count: UnsafeMutablePointer<Int>?) -> Int32 {
    guard let board = Pasteboard.board(object), let count else { return PasteboardStatus.param }
    count.pointee = board.contents.items.count
    return PasteboardStatus.success
}

/// The identifier of the item at a 1-based index.
@c(_PasteboardGetItemIdentifier)
public func PasteboardGetItemIdentifier(_ object: UnsafeMutableRawPointer?, _ index: Int,
                                        _ identifier: UnsafeMutablePointer<UnsafeMutableRawPointer?>?) -> Int32 {
    guard let board = Pasteboard.board(object), let identifier else { return PasteboardStatus.param }
    guard index >= 1, index <= board.contents.items.count else { return PasteboardStatus.badIndex }
    identifier.pointee = board.contents.items[index - 1].identifier
    return PasteboardStatus.success
}

/// The item's flavor types, a new CFArray of CFStrings.
@c(_PasteboardCopyItemFlavors)
public func PasteboardCopyItemFlavors(_ object: UnsafeMutableRawPointer?, _ identifier: UnsafeMutableRawPointer?,
                                      _ out: UnsafeMutablePointer<UnsafeMutableRawPointer?>?) -> Int32 {
    guard let board = Pasteboard.board(object), let out else { return PasteboardStatus.param }
    guard let item = board.item(identifier) else { return PasteboardStatus.badItem }
    let types = board.contents.items[item].flavors.compactMap { $0.type.objCArgument().map(NSObject.init) }
    out.pointee = NSMutableArray.of(types).objCOwnedReturnValue()
    return PasteboardStatus.success
}

/// A flavor's data, a new CFData; a promised flavor's comes from the
/// promise keeper first.
@c(_PasteboardCopyItemFlavorData)
public func PasteboardCopyItemFlavorData(_ object: UnsafeMutableRawPointer?, _ identifier: UnsafeMutableRawPointer?,
                                         _ type: UnsafeMutableRawPointer?, _ out: UnsafeMutablePointer<UnsafeMutableRawPointer?>?) -> Int32 {
    guard let board = Pasteboard.board(object), let type, let out else { return PasteboardStatus.param }
    guard let item = board.item(identifier) else { return PasteboardStatus.badItem }
    let name = String(objCArgument: type)
    guard let flavor = board.contents.items[item].flavors.firstIndex(where: { $0.type == name }) else { return PasteboardStatus.badFlavor }
    board.keepPromise(item: item, flavor: flavor)
    // The keeper may have changed the items.
    guard let kept = board.item(identifier),
          let data = board.contents.items[kept].flavors.first(where: { $0.type == name })?.data else { return PasteboardStatus.badFlavor }
    out.pointee = data.withUnsafeBytes { NSData.make(bytes: $0.baseAddress, length: UInt($0.count)) }.objCOwnedReturnValue()
    return PasteboardStatus.success
}

/// Adds a flavor to an item, the item too if it's new; NULL data promises
/// it. Only the client that cleared the pasteboard may.
@c(_PasteboardPutItemFlavor)
public func PasteboardPutItemFlavor(_ object: UnsafeMutableRawPointer?, _ identifier: UnsafeMutableRawPointer?,
                                    _ type: UnsafeMutableRawPointer?, _ data: UnsafeMutableRawPointer?, _ flags: UInt32) -> Int32 {
    guard let board = Pasteboard.board(object), let type else { return PasteboardStatus.param }
    let contents = board.contents
    guard contents.owner == board.objcObject else { return PasteboardStatus.notOwner }
    let name = String(objCArgument: type)
    var bytes: [UInt8]?
    if let data {
        guard let value = NSObject(objCArgument: data).as(NSData.self) else { return PasteboardStatus.param }
        bytes = value.byteArray
    } else if contents.keeper == nil {
        return PasteboardStatus.noPromiseKeeper
    }
    let promised: UInt32 = 1 << 9    // kPasteboardFlavorPromised
    let flavor = PasteboardContents.Flavor(type: name, data: bytes, flags: bytes == nil ? flags | promised : flags)
    if let item = board.item(identifier) {
        // A promised flavor is put again with its data.
        if let existing = contents.items[item].flavors.firstIndex(where: { $0.type == name }) {
            guard contents.items[item].flavors[existing].data == nil, bytes != nil else { return PasteboardStatus.duplicateFlavor }
            contents.items[item].flavors[existing].data = bytes
        } else {
            contents.items[item].flavors.append(flavor)
        }
    } else {
        contents.items.append(PasteboardContents.Item(identifier: identifier, flavors: [flavor]))
    }
    if board.isClipboard, let bytes { contents.writeClipboard(name, bytes) }
    return PasteboardStatus.success
}

@c(_PasteboardSetPromiseKeeper)
public func PasteboardSetPromiseKeeper(_ object: UnsafeMutableRawPointer?, _ keeper: PasteboardPromiseKeeper?,
                                       _ context: UnsafeMutableRawPointer?) -> Int32 {
    guard let board = Pasteboard.board(object), let keeper else { return PasteboardStatus.param }
    board.contents.keeper = (keeper, context, board.objcObject)
    return PasteboardStatus.success
}

/// Has the keeper put every promised flavor's data: one pasteboard's, or
/// every pasteboard's for NULL (kPasteboardResolveAllPromises).
@c(_PasteboardResolvePromises)
public func PasteboardResolvePromises(_ object: UnsafeMutableRawPointer?) -> Int32 {
    let boards: [PasteboardContents]
    if let object {
        guard let board = Pasteboard.board(object) else { return PasteboardStatus.param }
        boards = [board.contents]
    } else {
        boards = Array(PasteboardContents.named.values)
    }
    for contents in boards {
        guard let keeper = contents.keeper else { continue }
        let promised = contents.items.flatMap { item in item.flavors.filter { $0.data == nil }.map { (item.identifier, $0.type) } }
        for (identifier, type) in promised {
            _ = keeper.function(keeper.pasteboard, identifier, type.objCArgument(), keeper.context)
        }
    }
    return PasteboardStatus.success
}
