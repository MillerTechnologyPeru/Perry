import CPerryFoundation
import FoundationEssentials
import PerryObjCInterop

// CFTree: a node with the program's info, retained and released by its
// context's callbacks, and children it retains, in order.

/// CFTreeContext: { version, info, retain, release, copyDescription }.
struct TreeContext {
    typealias Retain = @convention(c) (UnsafeRawPointer?) -> UnsafeRawPointer?
    typealias Release = @convention(c) (UnsafeRawPointer?) -> Void

    var info: UnsafeMutableRawPointer?
    var retain: Retain?
    var release: Release?
    var copyDescription: UnsafeRawPointer?

    init() {}

    init(_ pointer: UnsafeRawPointer?) {
        guard let pointer else { return }
        info = pointer.load(fromByteOffset: DarwinLayout.word, as: UnsafeMutableRawPointer?.self)
        retain = pointer.load(fromByteOffset: 2 * DarwinLayout.word, as: Retain?.self)
        release = pointer.load(fromByteOffset: 3 * DarwinLayout.word, as: Release?.self)
        copyDescription = pointer.load(fromByteOffset: 4 * DarwinLayout.word, as: UnsafeRawPointer?.self)
    }

    func retained() -> UnsafeMutableRawPointer? {
        guard let info, let retain else { return info }
        return retain(info).map { UnsafeMutableRawPointer(mutating: $0) }
    }

    func released() {
        if let info, let release { release(info) }
    }

    func store(to pointer: UnsafeMutableRawPointer) {
        pointer.storeBytes(of: 0, as: Int.self)
        pointer.storeBytes(of: info, toByteOffset: DarwinLayout.word, as: UnsafeMutableRawPointer?.self)
        pointer.storeBytes(of: retain, toByteOffset: 2 * DarwinLayout.word, as: Retain?.self)
        pointer.storeBytes(of: release, toByteOffset: 3 * DarwinLayout.word, as: Release?.self)
        pointer.storeBytes(of: copyDescription, toByteOffset: 4 * DarwinLayout.word, as: UnsafeRawPointer?.self)
    }
}

final class TreeStorage {
    var context = TreeContext()
    /// Not retained: the parent keeps its children.
    var parent: id?
    /// Retained.
    var children: [id] = []

    deinit {
        for child in children {
            Trees.storage(child)?.parent = nil
            ObjC.release(child)
        }
        context.released()
    }
}

enum Trees {
    nonisolated(unsafe) static var treeClass: Class!

    static func storage(_ tree: id?) -> TreeStorage? { Storage.get(tree, as: TreeStorage.self) }

    /// Puts `child`, which has no parent, among `tree`'s children at `index`.
    static func insert(_ child: id?, into tree: id?, at index: (TreeStorage) -> Int) {
        guard let child, let tree, let storage = storage(tree), let childStorage = Trees.storage(child),
              childStorage.parent == nil, child != tree else { return }
        _ = ObjC.retain(child)
        childStorage.parent = tree
        storage.children.insert(child, at: index(storage))
    }
}

@ObjCClass("__NSCFTree")
final class NSCFTree: NSObject {
    override class func didDefineObjCClass(_ cls: ObjCClass) {
        NSObject.registerObjCCategoryStorageAllocated(cls)
        Trees.treeClass = cls.storage
    }

    @ObjCMethod("dealloc")
    func dealloc() {
        Storage.set(objcObject, nil)
        ObjC.superDealloc(objcObject, from: Trees.treeClass)
    }

    @ObjCMethod("_cfTypeID") func cfTypeID() -> UInt { 28 }
}

@c(_CFTreeGetTypeID) public func CFTreeGetTypeID() -> UInt { 28 }

@c(_CFTreeCreate)
public func CFTreeCreate(_ allocator: UnsafeRawPointer?, _ context: UnsafeRawPointer?) -> id? {
    guard let object = Storage.allocate(UnsafeMutableRawPointer(Trees.treeClass)) else { return nil }
    let storage = TreeStorage()
    storage.context = TreeContext(context)
    storage.context.info = storage.context.retained()
    Storage.set(object, storage)
    return object
}

@c(_CFTreeGetContext)
public func CFTreeGetContext(_ tree: id?, _ context: UnsafeMutableRawPointer?) {
    guard let context, let storage = Trees.storage(tree) else { return }
    storage.context.store(to: context)
}

/// The new info is retained before the old is released.
@c(_CFTreeSetContext)
public func CFTreeSetContext(_ tree: id?, _ context: UnsafeRawPointer?) {
    guard let storage = Trees.storage(tree) else { return }
    var new = TreeContext(context)
    new.info = new.retained()
    let old = storage.context
    storage.context = new
    old.released()
}

@c(_CFTreeGetParent) public func CFTreeGetParent(_ tree: id?) -> id? { Trees.storage(tree)?.parent }

@c(_CFTreeGetNextSibling)
public func CFTreeGetNextSibling(_ tree: id?) -> id? {
    guard let tree, let parent = Trees.storage(tree)?.parent, let siblings = Trees.storage(parent)?.children,
          let index = siblings.firstIndex(of: tree), index + 1 < siblings.count else { return nil }
    return siblings[index + 1]
}

@c(_CFTreeGetFirstChild) public func CFTreeGetFirstChild(_ tree: id?) -> id? { Trees.storage(tree)?.children.first }

@c(_CFTreeGetChildCount) public func CFTreeGetChildCount(_ tree: id?) -> Int { Trees.storage(tree)?.children.count ?? 0 }

@c(_CFTreeGetChildAtIndex)
public func CFTreeGetChildAtIndex(_ tree: id?, _ index: Int) -> id? {
    guard let children = Trees.storage(tree)?.children, children.indices.contains(index) else { return nil }
    return children[index]
}

@c(_CFTreeGetChildren)
public func CFTreeGetChildren(_ tree: id?, _ children: UnsafeMutablePointer<id?>?) {
    guard let children, let all = Trees.storage(tree)?.children else { return }
    for (index, child) in all.enumerated() { children[index] = child }
}

@c(_CFTreeApplyFunctionToChildren)
public func CFTreeApplyFunctionToChildren(_ tree: id?, _ applier: (@convention(c) (UnsafeRawPointer?, UnsafeMutableRawPointer?) -> Void)?,
                                          _ context: UnsafeMutableRawPointer?) {
    guard let applier, let all = Trees.storage(tree)?.children else { return }
    all.forEach { applier(UnsafeRawPointer($0), context) }
}

@c(_CFTreeFindRoot)
public func CFTreeFindRoot(_ tree: id?) -> id? {
    var node = tree
    while let parent = Trees.storage(node)?.parent { node = parent }
    return node
}

@c(_CFTreeAppendChild)
public func CFTreeAppendChild(_ tree: id?, _ child: id?) { Trees.insert(child, into: tree) { $0.children.count } }

@c(_CFTreePrependChild)
public func CFTreePrependChild(_ tree: id?, _ child: id?) { Trees.insert(child, into: tree) { _ in 0 } }

/// Puts `sibling` after `tree`, under `tree`'s parent.
@c(_CFTreeInsertSibling)
public func CFTreeInsertSibling(_ tree: id?, _ sibling: id?) {
    guard let tree, let parent = Trees.storage(tree)?.parent else { return }
    Trees.insert(sibling, into: parent) { storage in (storage.children.firstIndex(of: tree) ?? storage.children.count - 1) + 1 }
}

/// Takes `tree` from its parent, which releases it.
@c(_CFTreeRemove)
public func CFTreeRemove(_ tree: id?) {
    guard let tree, let storage = Trees.storage(tree), let parent = storage.parent,
          let siblings = Trees.storage(parent), let index = siblings.children.firstIndex(of: tree) else { return }
    siblings.children.remove(at: index)
    storage.parent = nil
    ObjC.release(tree)
}

@c(_CFTreeRemoveAllChildren)
public func CFTreeRemoveAllChildren(_ tree: id?) {
    guard let storage = Trees.storage(tree) else { return }
    let children = storage.children
    storage.children = []
    for child in children {
        Trees.storage(child)?.parent = nil
        ObjC.release(child)
    }
}

/// Sorts the children, which the comparator is given, stably.
@c(_CFTreeSortChildren)
public func CFTreeSortChildren(_ tree: id?, _ comparator: (@convention(c) (UnsafeRawPointer?, UnsafeRawPointer?, UnsafeMutableRawPointer?) -> Int)?,
                               _ context: UnsafeMutableRawPointer?) {
    guard let comparator, let storage = Trees.storage(tree) else { return }
    let ordered = storage.children.enumerated().sorted { a, b in
        let result = comparator(UnsafeRawPointer(a.element), UnsafeRawPointer(b.element), context)
        return result != 0 ? result < 0 : a.offset < b.offset
    }
    storage.children = ordered.map(\.element)
}
