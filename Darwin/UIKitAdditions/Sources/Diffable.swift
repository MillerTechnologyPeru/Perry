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
