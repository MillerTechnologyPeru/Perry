// Diffable data sources: a collection view's data given as snapshots of
// its sections and items by identifier, which iOS keeps in UIKit's Swift
// module over private Objective-C classes. Here a snapshot is a Swift
// value of the sections in order, each with its items, and applying one
// reloads the collection view: differences aren't animated. Declarations
// are the SDK interface's, for its ABI. An index path is a section and an
// item, its two indexes: their names are in UIKit's overlay.

public import Foundation

@available(iOS 13.0, tvOS 13.0, *)
@preconcurrency public struct NSDiffableDataSourceSnapshot<SectionIdentifierType, ItemIdentifierType> : @unchecked Swift.Sendable where SectionIdentifierType : Swift.Hashable, SectionIdentifierType : Swift.Sendable, ItemIdentifierType : Swift.Hashable, ItemIdentifierType : Swift.Sendable {
  var sections: [SectionIdentifierType] = []
  var items: [[ItemIdentifierType]] = []
  var reloadedSections: [SectionIdentifierType] = []
  var reloadedItems: [ItemIdentifierType] = []
  var reconfiguredItems: [ItemIdentifierType] = []

  public init() {}

  public var numberOfItems: Swift.Int { items.reduce(0) { $0 + $1.count } }
  public var numberOfSections: Swift.Int { sections.count }
  public var sectionIdentifiers: [SectionIdentifierType] { sections }
  public var itemIdentifiers: [ItemIdentifierType] { items.flatMap { $0 } }
  public var reloadedSectionIdentifiers: [SectionIdentifierType] { reloadedSections }
  public var reloadedItemIdentifiers: [ItemIdentifierType] { reloadedItems }
  public var reconfiguredItemIdentifiers: [ItemIdentifierType] { reconfiguredItems }

  public func numberOfItems(inSection identifier: SectionIdentifierType) -> Swift.Int {
    sections.firstIndex(of: identifier).map { items[$0].count } ?? 0
  }
  public func itemIdentifiers(inSection identifier: SectionIdentifierType) -> [ItemIdentifierType] {
    sections.firstIndex(of: identifier).map { items[$0] } ?? []
  }
  public func sectionIdentifier(containingItem identifier: ItemIdentifierType) -> SectionIdentifierType? {
    location(of: identifier).map { sections[$0.section] }
  }
  public func indexOfItem(_ identifier: ItemIdentifierType) -> Swift.Int? { itemIdentifiers.firstIndex(of: identifier) }
  public func indexOfSection(_ identifier: SectionIdentifierType) -> Swift.Int? { sections.firstIndex(of: identifier) }

  /// Where an item is: its section and its index there.
  func location(of identifier: ItemIdentifierType) -> (section: Int, item: Int)? {
    for (section, sectionItems) in items.enumerated() {
      if let item = sectionItems.firstIndex(of: identifier) { return (section, item) }
    }
    return nil
  }

  public mutating func appendItems(_ identifiers: [ItemIdentifierType], toSection sectionIdentifier: SectionIdentifierType? = nil) {
    let section = sectionIdentifier.flatMap { sections.firstIndex(of: $0) } ?? (sections.isEmpty ? nil : sections.count - 1)
    guard let section else { return }
    items[section].append(contentsOf: identifiers)
  }
  public mutating func insertItems(_ identifiers: [ItemIdentifierType], beforeItem beforeIdentifier: ItemIdentifierType) {
    guard let at = location(of: beforeIdentifier) else { return }
    items[at.section].insert(contentsOf: identifiers, at: at.item)
  }
  public mutating func insertItems(_ identifiers: [ItemIdentifierType], afterItem afterIdentifier: ItemIdentifierType) {
    guard let at = location(of: afterIdentifier) else { return }
    items[at.section].insert(contentsOf: identifiers, at: at.item + 1)
  }
  public mutating func deleteItems(_ identifiers: [ItemIdentifierType]) {
    let deleted = Set(identifiers)
    for section in items.indices { items[section].removeAll { deleted.contains($0) } }
  }
  public mutating func deleteAllItems() {
    sections = []
    items = []
  }
  public mutating func moveItem(_ identifier: ItemIdentifierType, beforeItem toIdentifier: ItemIdentifierType) {
    deleteItems([identifier])
    insertItems([identifier], beforeItem: toIdentifier)
  }
  public mutating func moveItem(_ identifier: ItemIdentifierType, afterItem toIdentifier: ItemIdentifierType) {
    deleteItems([identifier])
    insertItems([identifier], afterItem: toIdentifier)
  }
  public mutating func reloadItems(_ identifiers: [ItemIdentifierType]) { reloadedItems.append(contentsOf: identifiers) }
  public mutating func reconfigureItems(_ identifiers: [ItemIdentifierType]) { reconfiguredItems.append(contentsOf: identifiers) }
  public mutating func appendSections(_ identifiers: [SectionIdentifierType]) {
    sections.append(contentsOf: identifiers)
    items.append(contentsOf: identifiers.map { _ in [] })
  }
  public mutating func insertSections(_ identifiers: [SectionIdentifierType], beforeSection toIdentifier: SectionIdentifierType) {
    guard let at = sections.firstIndex(of: toIdentifier) else { return }
    sections.insert(contentsOf: identifiers, at: at)
    items.insert(contentsOf: identifiers.map { _ in [] }, at: at)
  }
  public mutating func insertSections(_ identifiers: [SectionIdentifierType], afterSection toIdentifier: SectionIdentifierType) {
    guard let at = sections.firstIndex(of: toIdentifier) else { return }
    sections.insert(contentsOf: identifiers, at: at + 1)
    items.insert(contentsOf: identifiers.map { _ in [] }, at: at + 1)
  }
  public mutating func deleteSections(_ identifiers: [SectionIdentifierType]) {
    for identifier in identifiers {
      guard let at = sections.firstIndex(of: identifier) else { continue }
      sections.remove(at: at)
      items.remove(at: at)
    }
  }
  public mutating func moveSection(_ identifier: SectionIdentifierType, beforeSection toIdentifier: SectionIdentifierType) {
    guard let from = sections.firstIndex(of: identifier) else { return }
    let moved = items[from]
    deleteSections([identifier])
    insertSections([identifier], beforeSection: toIdentifier)
    if let at = sections.firstIndex(of: identifier) { items[at] = moved }
  }
  public mutating func moveSection(_ identifier: SectionIdentifierType, afterSection toIdentifier: SectionIdentifierType) {
    guard let from = sections.firstIndex(of: identifier) else { return }
    let moved = items[from]
    deleteSections([identifier])
    insertSections([identifier], afterSection: toIdentifier)
    if let at = sections.firstIndex(of: identifier) { items[at] = moved }
  }
  public mutating func reloadSections(_ identifiers: [SectionIdentifierType]) { reloadedSections.append(contentsOf: identifiers) }
}

@available(iOS 13.0, tvOS 13.0, *)
@preconcurrency @_Concurrency.MainActor open class UICollectionViewDiffableDataSource<SectionIdentifierType, ItemIdentifierType> : ObjectiveC.NSObject, UICollectionViewDataSource where SectionIdentifierType : Swift.Hashable, SectionIdentifierType : Swift.Sendable, ItemIdentifierType : Swift.Hashable, ItemIdentifierType : Swift.Sendable {
  public typealias CellProvider = (_ collectionView: UICollectionView, _ indexPath: Foundation.IndexPath, _ itemIdentifier: ItemIdentifierType) -> UICollectionViewCell?
  public typealias SupplementaryViewProvider = (_ collectionView: UICollectionView, _ elementKind: Swift.String, _ indexPath: Foundation.IndexPath) -> UICollectionReusableView?

  private weak var collectionView: UICollectionView?
  private let cellProvider: CellProvider
  private var current = NSDiffableDataSourceSnapshot<SectionIdentifierType, ItemIdentifierType>()
  /// The section snapshots applied, by section (their item type is the data source's).
  var sectionSnapshots: [SectionIdentifierType: Any] = [:]

  @_Concurrency.MainActor @preconcurrency public var supplementaryViewProvider: UIKit.UICollectionViewDiffableDataSource<SectionIdentifierType, ItemIdentifierType>.SupplementaryViewProvider?

  @_Concurrency.MainActor @preconcurrency public init(collectionView: UICollectionView, cellProvider: @escaping UIKit.UICollectionViewDiffableDataSource<SectionIdentifierType, ItemIdentifierType>.CellProvider) {
    self.collectionView = collectionView
    self.cellProvider = cellProvider
    super.init()
    collectionView.dataSource = self
  }

  @_Concurrency.MainActor @preconcurrency open func apply(_ snapshot: UIKit.NSDiffableDataSourceSnapshot<SectionIdentifierType, ItemIdentifierType>, animatingDifferences: Swift.Bool = true, completion: (() -> Swift.Void)? = nil) {
    applySnapshotUsingReloadData(snapshot, completion: completion)
  }
  @_Concurrency.MainActor @preconcurrency open func apply(_ snapshot: UIKit.NSDiffableDataSourceSnapshot<SectionIdentifierType, ItemIdentifierType>, animatingDifferences: Swift.Bool = true) async {
    applySnapshotUsingReloadData(snapshot, completion: nil)
  }
  @_Concurrency.MainActor @preconcurrency open func applySnapshotUsingReloadData(_ snapshot: UIKit.NSDiffableDataSourceSnapshot<SectionIdentifierType, ItemIdentifierType>, completion: (() -> Swift.Void)? = nil) {
    var applied = snapshot
    applied.reloadedSections = []
    applied.reloadedItems = []
    applied.reconfiguredItems = []
    current = applied
    collectionView?.reloadData()
    completion?()
  }
  @_Concurrency.MainActor @preconcurrency open func applySnapshotUsingReloadData(_ snapshot: UIKit.NSDiffableDataSourceSnapshot<SectionIdentifierType, ItemIdentifierType>) async {
    applySnapshotUsingReloadData(snapshot, completion: nil)
  }
  @_Concurrency.MainActor @preconcurrency open func snapshot() -> UIKit.NSDiffableDataSourceSnapshot<SectionIdentifierType, ItemIdentifierType> { current }
  @_Concurrency.MainActor @preconcurrency open func sectionIdentifier(for index: Swift.Int) -> SectionIdentifierType? {
    current.sections.indices.contains(index) ? current.sections[index] : nil
  }
  @_Concurrency.MainActor @preconcurrency open func index(for sectionIdentifier: SectionIdentifierType) -> Swift.Int? {
    current.sections.firstIndex(of: sectionIdentifier)
  }
  @_Concurrency.MainActor @preconcurrency open func itemIdentifier(for indexPath: Foundation.IndexPath) -> ItemIdentifierType? {
    guard indexPath.count == 2, current.items.indices.contains(indexPath[0]), current.items[indexPath[0]].indices.contains(indexPath[1]) else {
      return nil
    }
    return current.items[indexPath[0]][indexPath[1]]
  }
  @_Concurrency.MainActor @preconcurrency open func indexPath(for itemIdentifier: ItemIdentifierType) -> Foundation.IndexPath? {
    current.location(of: itemIdentifier).map { IndexPath(indexes: [$0.section, $0.item]) }
  }

  @_Concurrency.MainActor @preconcurrency @objc open func numberOfSections(in collectionView: UICollectionView) -> Swift.Int { current.sections.count }
  @_Concurrency.MainActor @preconcurrency @objc open func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Swift.Int) -> Swift.Int {
    current.items.indices.contains(section) ? current.items[section].count : 0
  }
  @_Concurrency.MainActor @preconcurrency @objc open func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: Foundation.IndexPath) -> UICollectionViewCell {
    guard let item = itemIdentifier(for: indexPath), let cell = cellProvider(collectionView, indexPath, item) else {
      fatalError("UICollectionViewDiffableDataSource: the cell provider gave no cell for \(indexPath)")
    }
    return cell
  }
  @_Concurrency.MainActor @preconcurrency @objc open func collectionView(_ collectionView: UICollectionView, viewForSupplementaryElementOfKind kind: Swift.String, at indexPath: Foundation.IndexPath) -> UICollectionReusableView {
    guard let view = supplementaryViewProvider?(collectionView, kind, indexPath) else {
      fatalError("UICollectionViewDiffableDataSource: no supplementary view of kind \(kind) for \(indexPath)")
    }
    return view
  }
  @_Concurrency.MainActor @preconcurrency @objc open func collectionView(_ collectionView: UICollectionView, canMoveItemAt indexPath: Foundation.IndexPath) -> Swift.Bool { false }
  @_Concurrency.MainActor @preconcurrency @objc open func collectionView(_ collectionView: UICollectionView, moveItemAt sourceIndexPath: Foundation.IndexPath, to destinationIndexPath: Foundation.IndexPath) {}
  @_Concurrency.MainActor @preconcurrency @objc open func indexTitles(for collectionView: UICollectionView) -> [Swift.String]? { nil }
  @_Concurrency.MainActor @preconcurrency @objc open func collectionView(_ collectionView: UICollectionView, indexPathForIndexTitle title: Swift.String, at index: Swift.Int) -> Foundation.IndexPath {
    IndexPath(indexes: [index, 0])
  }
  @_Concurrency.MainActor @preconcurrency public func description() -> Swift.String { "UICollectionViewDiffableDataSource" }
}

// MARK: - Table views

/// A table view's diffable data source: as the collection view's, applying
/// a snapshot reloads the table view, whatever the row animation.
@available(iOS 13.0, tvOS 13.0, *)
@preconcurrency @_Concurrency.MainActor open class UITableViewDiffableDataSource<SectionIdentifierType, ItemIdentifierType> : ObjectiveC.NSObject, UITableViewDataSource where SectionIdentifierType : Swift.Hashable, SectionIdentifierType : Swift.Sendable, ItemIdentifierType : Swift.Hashable, ItemIdentifierType : Swift.Sendable {
  public typealias CellProvider = (_ tableView: UITableView, _ indexPath: Foundation.IndexPath, _ itemIdentifier: ItemIdentifierType) -> UITableViewCell?

  private weak var tableView: UITableView?
  private let cellProvider: CellProvider
  private var current = NSDiffableDataSourceSnapshot<SectionIdentifierType, ItemIdentifierType>()

  @_Concurrency.MainActor @preconcurrency public init(tableView: UITableView, cellProvider: @escaping UIKit.UITableViewDiffableDataSource<SectionIdentifierType, ItemIdentifierType>.CellProvider) {
    self.tableView = tableView
    self.cellProvider = cellProvider
    super.init()
    tableView.dataSource = self
  }

  @_Concurrency.MainActor @preconcurrency open func apply(_ snapshot: UIKit.NSDiffableDataSourceSnapshot<SectionIdentifierType, ItemIdentifierType>, animatingDifferences: Swift.Bool = true, completion: (() -> Swift.Void)? = nil) {
    applySnapshotUsingReloadData(snapshot, completion: completion)
  }
  @available(iOS 15.0, tvOS 15.0, *)
  @_Concurrency.MainActor @preconcurrency open func apply(_ snapshot: UIKit.NSDiffableDataSourceSnapshot<SectionIdentifierType, ItemIdentifierType>, animatingDifferences: Swift.Bool = true) async {
    applySnapshotUsingReloadData(snapshot, completion: nil)
  }
  @available(iOS 15.0, tvOS 15.0, *)
  @_Concurrency.MainActor @preconcurrency open func applySnapshotUsingReloadData(_ snapshot: UIKit.NSDiffableDataSourceSnapshot<SectionIdentifierType, ItemIdentifierType>, completion: (() -> Swift.Void)? = nil) {
    var applied = snapshot
    applied.reloadedSections = []
    applied.reloadedItems = []
    applied.reconfiguredItems = []
    current = applied
    tableView?.reloadData()
    completion?()
  }
  @available(iOS 15.0, tvOS 15.0, *)
  @_Concurrency.MainActor @preconcurrency open func applySnapshotUsingReloadData(_ snapshot: UIKit.NSDiffableDataSourceSnapshot<SectionIdentifierType, ItemIdentifierType>) async {
    applySnapshotUsingReloadData(snapshot, completion: nil)
  }
  @_Concurrency.MainActor @preconcurrency open func snapshot() -> UIKit.NSDiffableDataSourceSnapshot<SectionIdentifierType, ItemIdentifierType> { current }
  @available(iOS 15.0, tvOS 15.0, *)
  @_Concurrency.MainActor @preconcurrency open func sectionIdentifier(for index: Swift.Int) -> SectionIdentifierType? {
    current.sections.indices.contains(index) ? current.sections[index] : nil
  }
  @available(iOS 15.0, tvOS 15.0, *)
  @_Concurrency.MainActor @preconcurrency open func index(for sectionIdentifier: SectionIdentifierType) -> Swift.Int? {
    current.sections.firstIndex(of: sectionIdentifier)
  }
  @_Concurrency.MainActor @preconcurrency open func itemIdentifier(for indexPath: Foundation.IndexPath) -> ItemIdentifierType? {
    guard indexPath.count == 2, current.items.indices.contains(indexPath[0]), current.items[indexPath[0]].indices.contains(indexPath[1]) else {
      return nil
    }
    return current.items[indexPath[0]][indexPath[1]]
  }
  @_Concurrency.MainActor @preconcurrency open func indexPath(for itemIdentifier: ItemIdentifierType) -> Foundation.IndexPath? {
    current.location(of: itemIdentifier).map { IndexPath(indexes: [$0.section, $0.item]) }
  }
  /// Kept for the ABI: rows aren't animated.
  @_Concurrency.MainActor @preconcurrency public var defaultRowAnimation: UITableView.RowAnimation = .automatic

  @_Concurrency.MainActor @preconcurrency @objc open func numberOfSections(in tableView: UITableView) -> Swift.Int { current.sections.count }
  @_Concurrency.MainActor @preconcurrency @objc open func tableView(_ tableView: UITableView, numberOfRowsInSection section: Swift.Int) -> Swift.Int {
    current.items.indices.contains(section) ? current.items[section].count : 0
  }
  @_Concurrency.MainActor @preconcurrency @objc open func tableView(_ tableView: UITableView, cellForRowAt indexPath: Foundation.IndexPath) -> UITableViewCell {
    guard let item = itemIdentifier(for: indexPath), let cell = cellProvider(tableView, indexPath, item) else {
      fatalError("UITableViewDiffableDataSource: the cell provider gave no cell for \(indexPath)")
    }
    return cell
  }
  @_Concurrency.MainActor @preconcurrency @objc open func tableView(_ tableView: UITableView, titleForHeaderInSection section: Swift.Int) -> Swift.String? { nil }
  @_Concurrency.MainActor @preconcurrency @objc open func tableView(_ tableView: UITableView, titleForFooterInSection section: Swift.Int) -> Swift.String? { nil }
  /// Rows aren't editable unless a subclass says so, as on iOS.
  @_Concurrency.MainActor @preconcurrency @objc open func tableView(_ tableView: UITableView, canEditRowAt indexPath: Foundation.IndexPath) -> Swift.Bool { false }
  @_Concurrency.MainActor @preconcurrency @objc open func tableView(_ tableView: UITableView, commit editingStyle: UITableViewCell.EditingStyle, forRowAt indexPath: Foundation.IndexPath) {}
  @_Concurrency.MainActor @preconcurrency @objc open func tableView(_ tableView: UITableView, canMoveRowAt indexPath: Foundation.IndexPath) -> Swift.Bool { false }
  /// A row the table view moved moves in the snapshot too.
  @_Concurrency.MainActor @preconcurrency @objc open func tableView(_ tableView: UITableView, moveRowAt sourceIndexPath: Foundation.IndexPath, to destinationIndexPath: Foundation.IndexPath) {
    guard let item = itemIdentifier(for: sourceIndexPath), destinationIndexPath.count == 2 else { return }
    let section = destinationIndexPath[0], row = destinationIndexPath[1]
    guard current.items.indices.contains(section) else { return }
    current.deleteItems([item])
    current.items[section].insert(item, at: min(max(row, 0), current.items[section].count))
  }
  @_Concurrency.MainActor @preconcurrency @objc open func sectionIndexTitles(for tableView: UITableView) -> [Swift.String]? { nil }
  @_Concurrency.MainActor @preconcurrency @objc open func tableView(_ tableView: UITableView, sectionForSectionIndexTitle title: Swift.String, at index: Swift.Int) -> Swift.Int { index }
  @_Concurrency.MainActor @preconcurrency public func description() -> Swift.String { "UITableViewDiffableDataSource" }
}

@available(iOS 13.0, tvOS 13.0, *)
extension UIKit.UITableViewDiffableDataSource : Swift.Sendable {}

// MARK: - Section snapshots

/// One section's items as a tree: items at the root, each with its
/// children in order, and which of them are expanded.
@available(iOS 14.0, tvOS 14.0, *)
@preconcurrency public struct NSDiffableDataSourceSectionSnapshot<ItemIdentifierType> : @unchecked Swift.Sendable where ItemIdentifierType : Swift.Hashable, ItemIdentifierType : Swift.Sendable {
  var roots: [ItemIdentifierType] = []
  var children: [ItemIdentifierType: [ItemIdentifierType]] = [:]
  /// Every item's parent: nil for a root item.
  var parents: [ItemIdentifierType: ItemIdentifierType?] = [:]
  var expanded: Set<ItemIdentifierType> = []

  public init() {}
  public init(_ snapshot: UIKit.NSDiffableDataSourceSectionSnapshot<ItemIdentifierType>) { self = snapshot }

  /// The children of a parent, or the root items for none.
  private func siblings(of parent: ItemIdentifierType?) -> [ItemIdentifierType] {
    parent.map { children[$0] ?? [] } ?? roots
  }
  private mutating func setSiblings(_ items: [ItemIdentifierType], of parent: ItemIdentifierType?) {
    if let parent { children[parent] = items.isEmpty ? nil : items } else { roots = items }
  }
  /// An item and its descendants, depth first; only into expanded items when visible.
  private func flattened(_ items: [ItemIdentifierType], visible: Swift.Bool = false, into list: inout [ItemIdentifierType]) {
    for item in items {
      list.append(item)
      if !visible || expanded.contains(item), let below = children[item] {
        flattened(below, visible: visible, into: &list)
      }
    }
  }
  /// Places another snapshot's items (its roots under a parent, or at a place among siblings).
  private mutating func graft(_ snapshot: UIKit.NSDiffableDataSourceSectionSnapshot<ItemIdentifierType>, under parent: ItemIdentifierType?, at index: Swift.Int) {
    var list = siblings(of: parent)
    list.insert(contentsOf: snapshot.roots, at: min(max(index, 0), list.count))
    setSiblings(list, of: parent)
    for (item, below) in snapshot.children { children[item] = below }
    for (item, above) in snapshot.parents { parents[item] = .some(above) }
    for root in snapshot.roots { parents[root] = .some(parent) }
    expanded.formUnion(snapshot.expanded)
  }

  public mutating func append(_ items: [ItemIdentifierType], to parent: ItemIdentifierType? = nil) {
    setSiblings(siblings(of: parent) + items, of: parent)
    for item in items { parents[item] = .some(parent) }
  }
  public mutating func insert(_ items: [ItemIdentifierType], before item: ItemIdentifierType) {
    guard contains(item) else { return }
    let parent = parents[item] ?? nil
    var list = siblings(of: parent)
    guard let at = list.firstIndex(of: item) else { return }
    list.insert(contentsOf: items, at: at)
    setSiblings(list, of: parent)
    for inserted in items { parents[inserted] = .some(parent) }
  }
  public mutating func insert(_ items: [ItemIdentifierType], after item: ItemIdentifierType) {
    guard contains(item) else { return }
    let parent = parents[item] ?? nil
    var list = siblings(of: parent)
    guard let at = list.firstIndex(of: item) else { return }
    list.insert(contentsOf: items, at: at + 1)
    setSiblings(list, of: parent)
    for inserted in items { parents[inserted] = .some(parent) }
  }
  public mutating func delete(_ items: [ItemIdentifierType]) {
    for item in items where contains(item) {
      var gone: [ItemIdentifierType] = []
      flattened([item], into: &gone)
      let parent = parents[item] ?? nil
      setSiblings(siblings(of: parent).filter { $0 != item }, of: parent)
      for removed in gone {
        children[removed] = nil
        parents[removed] = nil
        expanded.remove(removed)
      }
    }
  }
  public mutating func deleteAll() { self = NSDiffableDataSourceSectionSnapshot() }
  public mutating func expand(_ items: [ItemIdentifierType]) {
    for item in items where contains(item) { expanded.insert(item) }
  }
  public mutating func collapse(_ items: [ItemIdentifierType]) {
    for item in items { expanded.remove(item) }
  }
  public mutating func replace(childrenOf parent: ItemIdentifierType, using snapshot: UIKit.NSDiffableDataSourceSectionSnapshot<ItemIdentifierType>) {
    guard contains(parent) else { return }
    delete(children[parent] ?? [])
    graft(snapshot, under: parent, at: 0)
  }
  public mutating func insert(_ snapshot: UIKit.NSDiffableDataSourceSectionSnapshot<ItemIdentifierType>, before item: ItemIdentifierType) {
    guard contains(item) else { return }
    let parent = parents[item] ?? nil
    graft(snapshot, under: parent, at: siblings(of: parent).firstIndex(of: item) ?? 0)
  }
  public mutating func insert(_ snapshot: UIKit.NSDiffableDataSourceSectionSnapshot<ItemIdentifierType>, after item: ItemIdentifierType) {
    guard contains(item) else { return }
    let parent = parents[item] ?? nil
    graft(snapshot, under: parent, at: (siblings(of: parent).firstIndex(of: item) ?? -1) + 1)
  }

  public func isExpanded(_ item: ItemIdentifierType) -> Swift.Bool { expanded.contains(item) }
  /// Whether every item above this one is expanded.
  public func isVisible(_ item: ItemIdentifierType) -> Swift.Bool {
    guard contains(item) else { return false }
    var above = parents[item] ?? nil
    while let parent = above {
      if !expanded.contains(parent) { return false }
      above = parents[parent] ?? nil
    }
    return true
  }
  public func contains(_ item: ItemIdentifierType) -> Swift.Bool { parents.keys.contains(item) }
  /// How deep an item is: 0 at the root.
  public func level(of item: ItemIdentifierType) -> Swift.Int {
    var level = 0
    var above = parents[item] ?? nil
    while let parent = above {
      level += 1
      above = parents[parent] ?? nil
    }
    return level
  }
  public func index(of item: ItemIdentifierType) -> Swift.Int? { items.firstIndex(of: item) }
  public func parent(of child: ItemIdentifierType) -> ItemIdentifierType? { parents[child] ?? nil }
  public func snapshot(of parent: ItemIdentifierType, includingParent: Swift.Bool = false) -> UIKit.NSDiffableDataSourceSectionSnapshot<ItemIdentifierType> {
    var snapshot = NSDiffableDataSourceSectionSnapshot()
    guard contains(parent) else { return snapshot }
    var subtree: [ItemIdentifierType] = []
    flattened([parent], into: &subtree)
    snapshot.roots = includingParent ? [parent] : (children[parent] ?? [])
    for item in subtree {
      if item == parent {
        if includingParent { snapshot.parents[item] = .some(nil) }
      } else {
        let above = parents[item] ?? nil
        let root = above == parent && !includingParent
        snapshot.parents[item] = .some(root ? nil : above)
      }
      if item != parent || includingParent {
        snapshot.children[item] = children[item]
        if expanded.contains(item) { snapshot.expanded.insert(item) }
      }
    }
    return snapshot
  }

  public var items: [ItemIdentifierType] {
    var list: [ItemIdentifierType] = []
    flattened(roots, into: &list)
    return list
  }
  public var rootItems: [ItemIdentifierType] { roots }
  public var visibleItems: [ItemIdentifierType] {
    var list: [ItemIdentifierType] = []
    flattened(roots, visible: true, into: &list)
    return list
  }
  @available(iOS 18.1, tvOS 18.1, visionOS 2.1, *)
  public var expandedItems: [ItemIdentifierType] { items.filter { expanded.contains($0) } }
  /// The tree, an item a line, indented by level.
  public func visualDescription() -> Swift.String {
    items.map { item in
      String(repeating: "  ", count: level(of: item)) + (children[item] == nil ? "- " : (expanded.contains(item) ? "v " : "> ")) + "\(item)"
    }.joined(separator: "\n")
  }
}

/// A section snapshot applied to a collection view's section gives the
/// section its visible items, in order.
@available(iOS 14.0, tvOS 14.0, *)
extension UIKit.UICollectionViewDiffableDataSource {
  @_Concurrency.MainActor @preconcurrency public func apply(_ snapshot: UIKit.NSDiffableDataSourceSectionSnapshot<ItemIdentifierType>, to section: SectionIdentifierType, animatingDifferences: Swift.Bool = true, completion: (() -> Swift.Void)? = nil) {
    var whole = self.snapshot()
    if whole.indexOfSection(section) == nil { whole.appendSections([section]) }
    if let at = whole.indexOfSection(section) { whole.items[at] = snapshot.visibleItems }
    sectionSnapshots[section] = snapshot
    applySnapshotUsingReloadData(whole, completion: completion)
  }
  @available(iOS 15.0, tvOS 15.0, *)
  @_Concurrency.MainActor @preconcurrency public func apply(_ snapshot: UIKit.NSDiffableDataSourceSectionSnapshot<ItemIdentifierType>, to section: SectionIdentifierType, animatingDifferences: Swift.Bool = true) async {
    apply(snapshot, to: section, animatingDifferences: animatingDifferences, completion: nil)
  }
  /// The section snapshot last applied to the section, or the section's items as root items.
  @_Concurrency.MainActor @preconcurrency public func snapshot(for section: SectionIdentifierType) -> UIKit.NSDiffableDataSourceSectionSnapshot<ItemIdentifierType> {
    let items = self.snapshot().itemIdentifiers(inSection: section)
    if let kept = sectionSnapshots[section] as? NSDiffableDataSourceSectionSnapshot<ItemIdentifierType>, kept.visibleItems == items {
      return kept
    }
    var snapshot = NSDiffableDataSourceSectionSnapshot<ItemIdentifierType>()
    snapshot.append(items)
    return snapshot
  }
}
