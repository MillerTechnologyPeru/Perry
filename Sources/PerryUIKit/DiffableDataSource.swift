import CPerryGeometry
import PerryObjCInterop

// The Objective-C diffable data source and its snapshots (Swift's
// UICollectionViewDiffableDataSourceReference and
// NSDiffableDataSourceSnapshotReference). A snapshot holds its sections in
// order, each with its items, identified by objects compared with
// -isEqual:. Applying one to a data source reloads the collection view:
// differences are not animated. Swift's generic data source and snapshot
// are UIKit's Swift module's (Darwin/UIKitAdditions), not these.

final class SnapshotState: ObjectState {
    var sections: [NSObject] = []
    var items: [[NSObject]] = []
    var reloadedItems: [NSObject] = []
    var reconfiguredItems: [NSObject] = []
    var reloadedSections: [NSObject] = []

    func copy(from other: SnapshotState) {
        (sections, items) = (other.sections, other.items)
        (reloadedItems, reconfiguredItems, reloadedSections) = (other.reloadedItems, other.reconfiguredItems, other.reloadedSections)
    }

    func sectionIndex(_ identifier: NSObject?) -> Int? {
        guard let identifier else { return nil }
        return sections.firstIndex { $0.sendIsEqual(identifier) }
    }

    /// Where an item is: its section and its place in it.
    func location(_ identifier: NSObject?) -> (section: Int, item: Int)? {
        guard let identifier else { return nil }
        for (section, list) in items.enumerated() {
            if let item = list.firstIndex(where: { $0.sendIsEqual(identifier) }) { return (section, item) }
        }
        return nil
    }

    func remove(items identifiers: [NSObject]) {
        for identifier in identifiers {
            if let found = location(identifier) { items[found.section].remove(at: found.item) }
        }
    }
}

/// NSNotFound, as an index.
private let notFound = Int.max

@ObjCClass("NSDiffableDataSourceSnapshot")
open class NSDiffableDataSourceSnapshot: NSObject {
    static let states = StateTable<SnapshotState>()
    var snapshot: SnapshotState { NSDiffableDataSourceSnapshot.states[objcObject] }

    @ObjCMethod("dealloc")
    func dealloc() {
        NSDiffableDataSourceSnapshot.states.remove(objcObject)
        ObjCRuntime.superDealloc(objcObject, definedOn: NSDiffableDataSourceSnapshot.objCClass.pointer)
    }

    static func make(copying other: SnapshotState? = nil) -> NSDiffableDataSourceSnapshot {
        let made = objCClass.object.newInstance().unsafeCast(to: NSDiffableDataSourceSnapshot.self)
        if let other { made.snapshot.copy(from: other) }
        return made
    }

    @ObjCMethod("copyWithZone:")
    func copy(zone: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer {
        ObjCRuntime.retain(NSDiffableDataSourceSnapshot.make(copying: snapshot).objcObject)!
    }

    // MARK: Reading

    @ObjCMethod("numberOfItems") func numberOfItems() -> Int { snapshot.items.reduce(0) { $0 + $1.count } }
    @ObjCMethod("numberOfSections") func numberOfSections() -> Int { snapshot.sections.count }
    @ObjCMethod("sectionIdentifiers") func sectionIdentifiers() -> NSObject { NSMutableArray.of(snapshot.sections) }
    @ObjCMethod("itemIdentifiers") func itemIdentifiers() -> NSObject { NSMutableArray.of(snapshot.items.flatMap { $0 }) }
    @ObjCMethod("reloadedItemIdentifiers") func reloadedItemIdentifiers() -> NSObject { NSMutableArray.of(snapshot.reloadedItems) }
    @ObjCMethod("reconfiguredItemIdentifiers") func reconfiguredItemIdentifiers() -> NSObject { NSMutableArray.of(snapshot.reconfiguredItems) }
    @ObjCMethod("reloadedSectionIdentifiers") func reloadedSectionIdentifiers() -> NSObject { NSMutableArray.of(snapshot.reloadedSections) }

    @ObjCMethod("numberOfItemsInSection:")
    func numberOfItems(inSection identifier: NSObject?) -> Int {
        snapshot.sectionIndex(identifier).map { snapshot.items[$0].count } ?? 0
    }

    @ObjCMethod("itemIdentifiersInSectionWithIdentifier:")
    func itemIdentifiers(inSection identifier: NSObject?) -> NSObject {
        NSMutableArray.of(snapshot.sectionIndex(identifier).map { snapshot.items[$0] } ?? [])
    }

    @ObjCMethod("sectionIdentifierForSectionContainingItemIdentifier:")
    func sectionIdentifier(containingItem identifier: NSObject?) -> NSObject? {
        snapshot.location(identifier).map { snapshot.sections[$0.section] }
    }

    @ObjCMethod("indexOfItemIdentifier:")
    func index(ofItem identifier: NSObject?) -> Int {
        guard let found = snapshot.location(identifier) else { return notFound }
        return snapshot.items[..<found.section].reduce(0) { $0 + $1.count } + found.item
    }

    @ObjCMethod("indexOfSectionIdentifier:")
    func index(ofSection identifier: NSObject?) -> Int { snapshot.sectionIndex(identifier) ?? notFound }

    // MARK: Items

    private func objects(_ array: NSObject?) -> [NSObject] { array?.as(NSArray.self)?.elements ?? [] }

    @ObjCMethod("appendItemsWithIdentifiers:")
    func appendItems(_ identifiers: NSObject?) {
        guard !snapshot.sections.isEmpty else { return }
        snapshot.items[snapshot.items.count - 1] += objects(identifiers)
    }

    @ObjCMethod("appendItemsWithIdentifiers:intoSectionWithIdentifier:")
    func appendItems(_ identifiers: NSObject?, intoSection section: NSObject?) {
        guard let index = snapshot.sectionIndex(section) else { return }
        snapshot.items[index] += objects(identifiers)
    }

    @ObjCMethod("insertItemsWithIdentifiers:beforeItemWithIdentifier:")
    func insertItems(_ identifiers: NSObject?, before item: NSObject?) {
        guard let found = snapshot.location(item) else { return }
        snapshot.items[found.section].insert(contentsOf: objects(identifiers), at: found.item)
    }

    @ObjCMethod("insertItemsWithIdentifiers:afterItemWithIdentifier:")
    func insertItems(_ identifiers: NSObject?, after item: NSObject?) {
        guard let found = snapshot.location(item) else { return }
        snapshot.items[found.section].insert(contentsOf: objects(identifiers), at: found.item + 1)
    }

    @ObjCMethod("deleteItemsWithIdentifiers:")
    func deleteItems(_ identifiers: NSObject?) { snapshot.remove(items: objects(identifiers)) }

    @ObjCMethod("deleteAllItems")
    func deleteAllItems() {
        snapshot.sections = []
        snapshot.items = []
    }

    @ObjCMethod("moveItemWithIdentifier:beforeItemWithIdentifier:")
    func moveItem(_ item: NSObject?, before other: NSObject?) {
        guard let item, snapshot.location(other) != nil else { return }
        snapshot.remove(items: [item])
        if let found = snapshot.location(other) { snapshot.items[found.section].insert(item, at: found.item) }
    }

    @ObjCMethod("moveItemWithIdentifier:afterItemWithIdentifier:")
    func moveItem(_ item: NSObject?, after other: NSObject?) {
        guard let item, snapshot.location(other) != nil else { return }
        snapshot.remove(items: [item])
        if let found = snapshot.location(other) { snapshot.items[found.section].insert(item, at: found.item + 1) }
    }

    @ObjCMethod("reloadItemsWithIdentifiers:")
    func reloadItems(_ identifiers: NSObject?) { snapshot.reloadedItems += objects(identifiers) }

    @ObjCMethod("reconfigureItemsWithIdentifiers:")
    func reconfigureItems(_ identifiers: NSObject?) { snapshot.reconfiguredItems += objects(identifiers) }

    // MARK: Sections

    @ObjCMethod("appendSectionsWithIdentifiers:")
    func appendSections(_ identifiers: NSObject?) {
        for section in objects(identifiers) where snapshot.sectionIndex(section) == nil {
            snapshot.sections.append(section)
            snapshot.items.append([])
        }
    }

    @ObjCMethod("insertSectionsWithIdentifiers:beforeSectionWithIdentifier:")
    func insertSections(_ identifiers: NSObject?, before section: NSObject?) {
        guard var index = snapshot.sectionIndex(section) else { return }
        for added in objects(identifiers) where snapshot.sectionIndex(added) == nil {
            snapshot.sections.insert(added, at: index)
            snapshot.items.insert([], at: index)
            index += 1
        }
    }

    @ObjCMethod("insertSectionsWithIdentifiers:afterSectionWithIdentifier:")
    func insertSections(_ identifiers: NSObject?, after section: NSObject?) {
        guard var index = snapshot.sectionIndex(section).map({ $0 + 1 }) else { return }
        for added in objects(identifiers) where snapshot.sectionIndex(added) == nil {
            snapshot.sections.insert(added, at: index)
            snapshot.items.insert([], at: index)
            index += 1
        }
    }

    @ObjCMethod("deleteSectionsWithIdentifiers:")
    func deleteSections(_ identifiers: NSObject?) {
        for section in objects(identifiers) {
            guard let index = snapshot.sectionIndex(section) else { continue }
            snapshot.sections.remove(at: index)
            snapshot.items.remove(at: index)
        }
    }

    @ObjCMethod("reloadSectionsWithIdentifiers:")
    func reloadSections(_ identifiers: NSObject?) { snapshot.reloadedSections += objects(identifiers) }
}

final class DiffableDataSourceState: ObjectState {
    let collectionView = WeakObject()
    var cellProvider: ObjCBlock?
    var supplementaryViewProvider: ObjCBlock?
    var snapshot = SnapshotState()
}

/// A collection view's data source made from snapshots.
@ObjCClass("UICollectionViewDiffableDataSource")
open class UICollectionViewDiffableDataSource: NSObject {
    static let states = StateTable<DiffableDataSourceState>()
    var source: DiffableDataSourceState { UICollectionViewDiffableDataSource.states[objcObject] }

    @ObjCMethod("dealloc")
    func dealloc() {
        UICollectionViewDiffableDataSource.states.remove(objcObject)
        ObjCRuntime.superDealloc(objcObject, definedOn: UICollectionViewDiffableDataSource.objCClass.pointer)
    }

    /// The data source of the collection view, whose cells the block makes.
    @ObjCMethod("initWithCollectionView:cellProvider:")
    func initialize(collectionView: UICollectionView?, cellProvider: ObjCBlock?) -> UnsafeMutableRawPointer? {
        source.collectionView.object = collectionView?.objcObject
        source.cellProvider = cellProvider
        collectionView?.setDataSource(self)
        return ObjCRuntime.retain(objcObject)
    }

    @ObjCMethod("supplementaryViewProvider") func supplementaryViewProvider() -> ObjCBlock? { source.supplementaryViewProvider }
    @ObjCMethod("setSupplementaryViewProvider:")
    func setSupplementaryViewProvider(_ provider: ObjCBlock?) { source.supplementaryViewProvider = provider }

    // MARK: Snapshots

    @ObjCMethod("snapshot")
    func snapshot() -> NSObject { NSDiffableDataSourceSnapshot.make(copying: source.snapshot) }

    /// Takes the snapshot's sections and items and reloads the collection
    /// view; the completion is called after the next layout pass.
    private func apply(_ snapshot: NSObject?, completion: ObjCBlock?) {
        if let given = snapshot?.as(NSDiffableDataSourceSnapshot.self) {
            source.snapshot.copy(from: given.snapshot)
            (source.snapshot.reloadedItems, source.snapshot.reconfiguredItems, source.snapshot.reloadedSections) = ([], [], [])
        }
        source.collectionView.object.map { UICollectionView.wrap($0).sendReloadData() }
        if let completion { Updates.afterPass { Blocks.call(completion) } }
    }

    @ObjCMethod("applySnapshot:animatingDifferences:")
    func apply(_ snapshot: NSObject?, animatingDifferences: Bool) { apply(snapshot, completion: nil) }

    @ObjCMethod("applySnapshot:animatingDifferences:completion:")
    func apply(_ snapshot: NSObject?, animatingDifferences: Bool, completion: ObjCBlock?) { apply(snapshot, completion: completion) }

    @ObjCMethod("applySnapshotUsingReloadData:")
    func applyUsingReloadData(_ snapshot: NSObject?) { apply(snapshot, completion: nil) }

    @ObjCMethod("applySnapshotUsingReloadData:completion:")
    func applyUsingReloadData(_ snapshot: NSObject?, completion: ObjCBlock?) { apply(snapshot, completion: completion) }

    // MARK: Identifiers

    @ObjCMethod("itemIdentifierForIndexPath:")
    func itemIdentifier(for indexPath: NSObject?) -> NSObject? {
        guard let indexPath else { return nil }
        let path = RowPath(indexPath)
        let items = source.snapshot.items
        guard items.indices.contains(path.section), items[path.section].indices.contains(path.row) else { return nil }
        return items[path.section][path.row]
    }

    @ObjCMethod("indexPathForItemIdentifier:")
    func indexPath(forItem identifier: NSObject?) -> NSObject? {
        source.snapshot.location(identifier).map { IndexPaths.make(section: $0.section, row: $0.item) }
    }

    @ObjCMethod("sectionIdentifierForIndex:")
    func sectionIdentifier(for index: Int) -> NSObject? {
        source.snapshot.sections.indices.contains(index) ? source.snapshot.sections[index] : nil
    }

    @ObjCMethod("indexForSectionIdentifier:")
    func index(forSection identifier: NSObject?) -> Int { source.snapshot.sectionIndex(identifier) ?? notFound }

    // MARK: UICollectionViewDataSource

    @ObjCMethod("numberOfSectionsInCollectionView:")
    func numberOfSections(in collectionView: NSObject?) -> Int { source.snapshot.sections.count }

    @ObjCMethod("collectionView:numberOfItemsInSection:")
    func collectionView(_ collectionView: NSObject?, numberOfItemsInSection section: Int) -> Int {
        source.snapshot.items.indices.contains(section) ? source.snapshot.items[section].count : 0
    }

    @ObjCMethod("collectionView:cellForItemAtIndexPath:")
    func collectionView(_ collectionView: NSObject?, cellForItemAt indexPath: NSObject?) -> NSObject? {
        guard let provider = source.cellProvider, let collectionView, let indexPath,
              let item = itemIdentifier(for: indexPath) else { return nil }
        typealias Provide = @convention(c) (UnsafeMutableRawPointer, UnsafeMutableRawPointer, UnsafeMutableRawPointer,
                                            UnsafeMutableRawPointer) -> UnsafeMutableRawPointer?
        let cell = provider.function(as: Provide.self)(provider.object, collectionView.objcObject, indexPath.objcObject, item.objcObject)
        return cell.map { NSObject.objCInstance($0, ownership: .retain) }
    }

    @ObjCMethod("collectionView:viewForSupplementaryElementOfKind:atIndexPath:")
    func collectionView(_ collectionView: NSObject?, viewForSupplementaryElementOfKind kind: NSObject?, at indexPath: NSObject?) -> NSObject? {
        guard let provider = source.supplementaryViewProvider, let collectionView, let kind, let indexPath else { return nil }
        typealias Provide = @convention(c) (UnsafeMutableRawPointer, UnsafeMutableRawPointer, UnsafeMutableRawPointer,
                                            UnsafeMutableRawPointer) -> UnsafeMutableRawPointer?
        let view = provider.function(as: Provide.self)(provider.object, collectionView.objcObject, kind.objcObject, indexPath.objcObject)
        return view.map { NSObject.objCInstance($0, ownership: .retain) }
    }

    @ObjCMethod("collectionView:canMoveItemAtIndexPath:")
    func collectionView(_ collectionView: NSObject?, canMoveItemAt indexPath: NSObject?) -> Bool { false }
}

extension NSObject {
    @ObjCMethod("isEqual:") func sendIsEqual(_ other: NSObject?) -> Bool
}
