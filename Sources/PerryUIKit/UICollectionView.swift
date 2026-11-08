import CPerryGeometry
import PerryObjCInterop

// UICollectionView, its layouts and its controller. The layout object
// places everything: the collection view asks it, by message so that apps'
// subclasses take part, for the attributes of the elements in view, then
// shows a cell from the data source for each item and a view for each
// supplementary element, keeping cells that leave the view for reuse.
// UICollectionViewFlowLayout lines items up across the scrolling direction
// and wraps them, asking the delegate for sizes, insets and spacing.

/// UICollectionElementKindSectionHeader and ...Footer.
enum CollectionElementKind {
    static let header = "UICollectionElementKindSectionHeader"
    static let footer = "UICollectionElementKindSectionFooter"
}

/// A supplementary view's place: its kind and index path.
struct SupplementaryKey: Hashable {
    var kind: String
    var path: RowPath
}

// MARK: - UICollectionViewLayoutAttributes

final class LayoutAttributesState: ObjectState {
    var frame = CGRect.zero
    var indexPath: NSObject?
    /// UICollectionElementCategory: cell 0, supplementary view 1, decoration view 2.
    var category = 0
    var kind: String?
    var alpha: CGFloat = 1
    var hidden = false
    var zIndex = 0
    var transform = CGAffineTransform(a: 1, b: 0, c: 0, d: 1, tx: 0, ty: 0)

    func copy(from other: LayoutAttributesState) {
        (frame, indexPath, category, kind) = (other.frame, other.indexPath, other.category, other.kind)
        (alpha, hidden, zIndex, transform) = (other.alpha, other.hidden, other.zIndex, other.transform)
    }
}

/// Where and how one element of a collection view is shown.
@ObjCClass("UICollectionViewLayoutAttributes")
open class UICollectionViewLayoutAttributes: NSObject {
    static let states = StateTable<LayoutAttributesState>()
    var attributes: LayoutAttributesState { UICollectionViewLayoutAttributes.states[objcObject] }

    var path: RowPath? { attributes.indexPath.map(RowPath.init) }

    /// New attributes of `cls`, which may be an app's subclass.
    static func make(_ cls: ObjCClass, path: NSObject, category: Int, kind: String?) -> UICollectionViewLayoutAttributes {
        let made = cls.object.newInstance().unsafeCast(to: UICollectionViewLayoutAttributes.self)
        made.attributes.indexPath = path
        made.attributes.category = category
        made.attributes.kind = kind
        return made
    }

    @ObjCClassMethod("layoutAttributesForCellWithIndexPath:")
    static func forCell(_ cls: ObjCClass, indexPath: NSObject) -> UICollectionViewLayoutAttributes {
        make(cls, path: indexPath, category: 0, kind: nil)
    }

    @ObjCClassMethod("layoutAttributesForSupplementaryViewOfKind:withIndexPath:")
    static func forSupplementaryView(_ cls: ObjCClass, kind: String, indexPath: NSObject) -> UICollectionViewLayoutAttributes {
        make(cls, path: indexPath, category: 1, kind: kind)
    }

    @ObjCClassMethod("layoutAttributesForDecorationViewOfKind:withIndexPath:")
    static func forDecorationView(_ cls: ObjCClass, kind: String, indexPath: NSObject) -> UICollectionViewLayoutAttributes {
        make(cls, path: indexPath, category: 2, kind: kind)
    }

    @ObjCMethod("dealloc")
    func dealloc() {
        UICollectionViewLayoutAttributes.states.remove(objcObject)
        ObjCRuntime.superDealloc(objcObject, definedOn: UICollectionViewLayoutAttributes.objCClass.pointer)
    }

    /// A copy of the same class, so subclasses' copies keep their class;
    /// their own properties are theirs to copy in an override.
    @ObjCMethod("copyWithZone:")
    func copy(zone: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer {
        let copy = ObjCClass(ObjCRuntime.objectClass(objcObject)!).object.newInstance().unsafeCast(to: UICollectionViewLayoutAttributes.self)
        copy.attributes.copy(from: attributes)
        return ObjCRuntime.retain(copy.objcObject)!
    }

    @ObjCMethod("frame") func frame() -> CGRect { attributes.frame }
    @ObjCMethod("setFrame:") func setFrame(_ frame: CGRect) { attributes.frame = frame }
    @ObjCMethod("bounds") func bounds() -> CGRect { CGRect(origin: .zero, size: attributes.frame.size) }
    @ObjCMethod("setBounds:") func setBounds(_ bounds: CGRect) { setSize(bounds.size) }
    @ObjCMethod("center") func center() -> CGPoint { CGPoint(x: attributes.frame.midX, y: attributes.frame.midY) }
    @ObjCMethod("setCenter:")
    func setCenter(_ center: CGPoint) {
        let size = attributes.frame.size
        attributes.frame.origin = CGPoint(x: center.x - size.width / 2, y: center.y - size.height / 2)
    }
    @ObjCMethod("size") func size() -> CGSize { attributes.frame.size }
    /// Keeps the center, as UIKit's.
    @ObjCMethod("setSize:")
    func setSize(_ size: CGSize) {
        let center = center()
        attributes.frame = CGRect(x: center.x - size.width / 2, y: center.y - size.height / 2, width: size.width, height: size.height)
    }
    @ObjCMethod("indexPath") func indexPath() -> NSObject? { attributes.indexPath }
    @ObjCMethod("setIndexPath:") func setIndexPath(_ path: NSObject?) { attributes.indexPath = path }
    @ObjCMethod("representedElementCategory") func representedElementCategory() -> Int { attributes.category }
    @ObjCMethod("representedElementKind") func representedElementKind() -> String? { attributes.kind }
    @ObjCMethod("alpha") func alpha() -> CGFloat { attributes.alpha }
    @ObjCMethod("setAlpha:") func setAlpha(_ alpha: CGFloat) { attributes.alpha = alpha }
    @ObjCMethod("isHidden") func isHidden() -> Bool { attributes.hidden }
    @ObjCMethod("setHidden:") func setHidden(_ hidden: Bool) { attributes.hidden = hidden }
    @ObjCMethod("zIndex") func zIndex() -> Int { attributes.zIndex }
    @ObjCMethod("setZIndex:") func setZIndex(_ index: Int) { attributes.zIndex = index }
    @ObjCMethod("transform") func transform() -> CGAffineTransform { attributes.transform }
    @ObjCMethod("setTransform:") func setTransform(_ transform: CGAffineTransform) { attributes.transform = transform }

    @ObjCMethod("isEqual:")
    func isEqual(_ other: NSObject?) -> Bool {
        guard let other = other?.as(UICollectionViewLayoutAttributes.self) else { return false }
        let a = attributes, b = other.attributes
        return a.frame == b.frame && a.category == b.category && a.kind == b.kind && a.alpha == b.alpha && a.hidden == b.hidden
            && a.zIndex == b.zIndex && other.path == path
    }
}

// MARK: - UICollectionViewLayoutInvalidationContext

final class InvalidationContextState: ObjectState {
    var everything = false
    var dataSourceCounts = false
    var flowDelegateMetrics = true
    var flowAttributes = true
    var contentOffsetAdjustment = CGPoint.zero
    var contentSizeAdjustment = CGSize.zero
}

/// What a layout is to recompute: here, always all of it.
@ObjCClass("UICollectionViewLayoutInvalidationContext")
open class UICollectionViewLayoutInvalidationContext: NSObject {
    static let states = StateTable<InvalidationContextState>()
    var context: InvalidationContextState { UICollectionViewLayoutInvalidationContext.states[objcObject] }

    @ObjCMethod("dealloc")
    func dealloc() {
        UICollectionViewLayoutInvalidationContext.states.remove(objcObject)
        ObjCRuntime.superDealloc(objcObject, definedOn: UICollectionViewLayoutInvalidationContext.objCClass.pointer)
    }

    @ObjCMethod("invalidateEverything") func invalidateEverything() -> Bool { context.everything }
    @ObjCMethod("invalidateDataSourceCounts") func invalidateDataSourceCounts() -> Bool { context.dataSourceCounts }
    @ObjCMethod("contentOffsetAdjustment") func contentOffsetAdjustment() -> CGPoint { context.contentOffsetAdjustment }
    @ObjCMethod("setContentOffsetAdjustment:") func setContentOffsetAdjustment(_ offset: CGPoint) { context.contentOffsetAdjustment = offset }
    @ObjCMethod("contentSizeAdjustment") func contentSizeAdjustment() -> CGSize { context.contentSizeAdjustment }
    @ObjCMethod("setContentSizeAdjustment:") func setContentSizeAdjustment(_ size: CGSize) { context.contentSizeAdjustment = size }
    @ObjCMethod("invalidatedItemIndexPaths") func invalidatedItemIndexPaths() -> NSObject? { nil }
    @ObjCMethod("invalidateItemsAtIndexPaths:") func invalidateItems(at paths: NSObject?) {}
    @ObjCMethod("invalidateSupplementaryElementsOfKind:atIndexPaths:") func invalidateSupplementaryElements(kind: String, at paths: NSObject?) {}
    @ObjCMethod("invalidateDecorationElementsOfKind:atIndexPaths:") func invalidateDecorationElements(kind: String, at paths: NSObject?) {}
}

@ObjCClass("UICollectionViewFlowLayoutInvalidationContext")
open class UICollectionViewFlowLayoutInvalidationContext: UICollectionViewLayoutInvalidationContext {
    @ObjCMethod("invalidateFlowLayoutDelegateMetrics") func invalidateFlowLayoutDelegateMetrics() -> Bool { context.flowDelegateMetrics }
    @ObjCMethod("setInvalidateFlowLayoutDelegateMetrics:") func setInvalidateFlowLayoutDelegateMetrics(_ value: Bool) {
        context.flowDelegateMetrics = value
    }
    @ObjCMethod("invalidateFlowLayoutAttributes") func invalidateFlowLayoutAttributes() -> Bool { context.flowAttributes }
    @ObjCMethod("setInvalidateFlowLayoutAttributes:") func setInvalidateFlowLayoutAttributes(_ value: Bool) { context.flowAttributes = value }
}

// MARK: - UICollectionViewLayout

final class CollectionLayoutState: ObjectState {
    /// The collection view using the layout; not retained.
    var collectionView: UnsafeMutableRawPointer?
}

/// The abstract layout: no elements, no size. Subclasses place them.
@ObjCClass("UICollectionViewLayout")
open class UICollectionViewLayout: NSObject {
    static let layoutStates = StateTable<CollectionLayoutState>()
    var layoutState: CollectionLayoutState { UICollectionViewLayout.layoutStates[objcObject] }

    var collection: UICollectionView? {
        layoutState.collectionView.map { UICollectionView(objcObject: $0, ownership: .retain) }
    }

    @ObjCMethod("initWithCoder:") func initialize(coder: NSObject) -> Self { self }

    @ObjCMethod("dealloc")
    func dealloc() {
        UICollectionViewLayout.layoutStates.remove(objcObject)
        ObjCRuntime.superDealloc(objcObject, definedOn: UICollectionViewLayout.objCClass.pointer)
    }

    @ObjCClassMethod("layoutAttributesClass")
    static func layoutAttributesClass() -> ObjCClass { UICollectionViewLayoutAttributes.objCClass }

    @ObjCClassMethod("invalidationContextClass")
    static func invalidationContextClass() -> ObjCClass { UICollectionViewLayoutInvalidationContext.objCClass }

    @ObjCMethod("collectionView") func collectionView() -> UICollectionView? { collection }

    @ObjCMethod("prepareLayout") func prepareLayout() {}
    @ObjCMethod("collectionViewContentSize") func collectionViewContentSize() -> CGSize { .zero }
    @ObjCMethod("layoutAttributesForElementsInRect:") func layoutAttributesForElements(in rect: CGRect) -> NSObject? { nil }
    @ObjCMethod("layoutAttributesForItemAtIndexPath:") func layoutAttributesForItem(at path: NSObject) -> NSObject? { nil }
    @ObjCMethod("layoutAttributesForSupplementaryViewOfKind:atIndexPath:")
    func layoutAttributesForSupplementaryView(kind: String, at path: NSObject) -> NSObject? { nil }
    @ObjCMethod("layoutAttributesForDecorationViewOfKind:atIndexPath:")
    func layoutAttributesForDecorationView(kind: String, at path: NSObject) -> NSObject? { nil }
    @ObjCMethod("layoutAttributesForInteractivelyMovingItemAtIndexPath:withTargetPosition:")
    func layoutAttributesForInteractivelyMovingItem(at path: NSObject, target: CGPoint) -> NSObject? {
        sendLayoutAttributesForItem(at: path)
    }

    @ObjCMethod("shouldInvalidateLayoutForBoundsChange:") func shouldInvalidateLayout(forBoundsChange bounds: CGRect) -> Bool { false }
    @ObjCMethod("invalidationContextForBoundsChange:")
    func invalidationContext(forBoundsChange bounds: CGRect) -> NSObject { newInvalidationContext() }
    @ObjCMethod("shouldInvalidateLayoutForPreferredLayoutAttributes:withOriginalAttributes:")
    func shouldInvalidateLayout(forPreferred preferred: NSObject?, original: NSObject?) -> Bool { false }

    private func newInvalidationContext() -> NSObject {
        let cls = ObjCClass(ObjCRuntime.objectClass(objcObject)!).object.sendInvalidationContextClass()
        return cls.object.newInstance()
    }

    /// The collection view lays out again from the layout's prepare.
    @ObjCMethod("invalidateLayout") func invalidateLayout() { collection?.layoutInvalidated() }
    @ObjCMethod("invalidateLayoutWithContext:") func invalidateLayout(with context: NSObject?) { sendInvalidateLayout() }

    @ObjCMethod("targetContentOffsetForProposedContentOffset:")
    func targetContentOffset(proposed: CGPoint) -> CGPoint { proposed }
    @ObjCMethod("targetContentOffsetForProposedContentOffset:withScrollingVelocity:")
    func targetContentOffset(proposed: CGPoint, velocity: CGPoint) -> CGPoint { proposed }

    @ObjCMethod("prepareForCollectionViewUpdates:") func prepareForCollectionViewUpdates(_ items: NSObject?) {}
    @ObjCMethod("finalizeCollectionViewUpdates") func finalizeCollectionViewUpdates() {}
    @ObjCMethod("prepareForAnimatedBoundsChange:") func prepareForAnimatedBoundsChange(_ bounds: CGRect) {}
    @ObjCMethod("finalizeAnimatedBoundsChange") func finalizeAnimatedBoundsChange() {}
    @ObjCMethod("prepareForTransitionToLayout:") func prepareForTransition(to layout: NSObject?) {}
    @ObjCMethod("prepareForTransitionFromLayout:") func prepareForTransition(from layout: NSObject?) {}
    @ObjCMethod("finalizeLayoutTransition") func finalizeLayoutTransition() {}
    @ObjCMethod("initialLayoutAttributesForAppearingItemAtIndexPath:")
    func initialLayoutAttributesForAppearingItem(at path: NSObject) -> NSObject? { nil }
    @ObjCMethod("finalLayoutAttributesForDisappearingItemAtIndexPath:")
    func finalLayoutAttributesForDisappearingItem(at path: NSObject) -> NSObject? { nil }
    @ObjCMethod("registerClass:forDecorationViewOfKind:") func register(_ cls: ObjCClass?, forDecorationViewOfKind kind: String) {}
    @ObjCMethod("registerNib:forDecorationViewOfKind:") func register(nib: NSObject?, forDecorationViewOfKind kind: String) {}
    @ObjCMethod("flipsHorizontallyInOppositeLayoutDirection") func flipsHorizontallyInOppositeLayoutDirection() -> Bool { false }
    @ObjCMethod("developmentLayoutDirection") func developmentLayoutDirection() -> Int { 0 }
}

// MARK: - UICollectionViewFlowLayout

/// A section of a flow layout: its header, items and footer.
struct FlowSection {
    var header: CGRect
    var items: [CGRect]
    var footer: CGRect
    /// The smallest rectangle around the header, items and footer.
    var rect: CGRect {
        let all = [header, footer] + items
        let minX = all.map(\.minX).min() ?? 0, minY = all.map(\.minY).min() ?? 0
        let maxX = all.map(\.maxX).max() ?? 0, maxY = all.map(\.maxY).max() ?? 0
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }
}

final class FlowLayoutState: ObjectState {
    var itemSize = CGSize(width: 50, height: 50)
    var estimatedItemSize = CGSize.zero
    var minimumLineSpacing: CGFloat = 10
    var minimumInteritemSpacing: CGFloat = 10
    var sectionInset = UIEdgeInsets.zero
    /// UICollectionViewScrollDirection: vertical 0, horizontal 1.
    var scrollDirection = 0
    var headerReferenceSize = CGSize.zero
    var footerReferenceSize = CGSize.zero
    var sectionHeadersPinToVisibleBounds = false
    var sectionFootersPinToVisibleBounds = false
    var sectionInsetReference = 0
    var sections: [FlowSection] = []
    var contentSize = CGSize.zero
    /// The breadth (width when vertical) the layout was prepared for.
    var preparedBreadth: CGFloat = -1
    /// Self-sized items' sizes, by index path.
    var measured: [RowPath: CGSize] = [:]
}

@ObjCClass("UICollectionViewFlowLayout")
open class UICollectionViewFlowLayout: UICollectionViewLayout {
    static let flowStates = StateTable<FlowLayoutState>()
    var flow: FlowLayoutState { UICollectionViewFlowLayout.flowStates[objcObject] }

    @ObjCMethod("initWithCoder:")
    override func initialize(coder: NSObject) -> Self {
        _ = super.initialize(coder: coder)
        let decoded = Coder(coder: coder), flow = flow
        if decoded.has("UIItemSize") { flow.itemSize = decoded.size("UIItemSize") }
        if decoded.has("UIEstimatedItemSize") { flow.estimatedItemSize = decoded.size("UIEstimatedItemSize") }
        if decoded.has("UIInteritemSpacing") { flow.minimumInteritemSpacing = decoded.double("UIInteritemSpacing") }
        if decoded.has("UILineSpacing") { flow.minimumLineSpacing = decoded.double("UILineSpacing") }
        if decoded.has("UISectionInset") { flow.sectionInset = decoded.insets("UISectionInset") }
        if decoded.has("UIHeaderReferenceSize") { flow.headerReferenceSize = decoded.size("UIHeaderReferenceSize") }
        if decoded.has("UIFooterReferenceSize") { flow.footerReferenceSize = decoded.size("UIFooterReferenceSize") }
        flow.scrollDirection = decoded.integer("UIScrollDirection")
        return self
    }

    @ObjCMethod("dealloc")
    override func dealloc() {
        UICollectionViewFlowLayout.flowStates.remove(objcObject)
        super.dealloc()
    }

    @ObjCClassMethod("invalidationContextClass")
    static func flowInvalidationContextClass() -> ObjCClass { UICollectionViewFlowLayoutInvalidationContext.objCClass }

    private func changed() { sendInvalidateLayout() }

    @ObjCMethod("itemSize") func itemSize() -> CGSize { flow.itemSize }
    @ObjCMethod("setItemSize:") func setItemSize(_ size: CGSize) { flow.itemSize = size; changed() }
    @ObjCMethod("estimatedItemSize") func estimatedItemSize() -> CGSize { flow.estimatedItemSize }
    @ObjCMethod("setEstimatedItemSize:") func setEstimatedItemSize(_ size: CGSize) { flow.estimatedItemSize = size; changed() }
    @ObjCMethod("minimumLineSpacing") func minimumLineSpacing() -> CGFloat { flow.minimumLineSpacing }
    @ObjCMethod("setMinimumLineSpacing:") func setMinimumLineSpacing(_ spacing: CGFloat) { flow.minimumLineSpacing = spacing; changed() }
    @ObjCMethod("minimumInteritemSpacing") func minimumInteritemSpacing() -> CGFloat { flow.minimumInteritemSpacing }
    @ObjCMethod("setMinimumInteritemSpacing:") func setMinimumInteritemSpacing(_ spacing: CGFloat) {
        flow.minimumInteritemSpacing = spacing
        changed()
    }
    @ObjCMethod("sectionInset") func sectionInset() -> UIEdgeInsets { flow.sectionInset }
    @ObjCMethod("setSectionInset:") func setSectionInset(_ inset: UIEdgeInsets) { flow.sectionInset = inset; changed() }
    @ObjCMethod("scrollDirection") func scrollDirection() -> Int { flow.scrollDirection }
    @ObjCMethod("setScrollDirection:") func setScrollDirection(_ direction: Int) { flow.scrollDirection = direction; changed() }
    @ObjCMethod("headerReferenceSize") func headerReferenceSize() -> CGSize { flow.headerReferenceSize }
    @ObjCMethod("setHeaderReferenceSize:") func setHeaderReferenceSize(_ size: CGSize) { flow.headerReferenceSize = size; changed() }
    @ObjCMethod("footerReferenceSize") func footerReferenceSize() -> CGSize { flow.footerReferenceSize }
    @ObjCMethod("setFooterReferenceSize:") func setFooterReferenceSize(_ size: CGSize) { flow.footerReferenceSize = size; changed() }
    @ObjCMethod("sectionHeadersPinToVisibleBounds") func sectionHeadersPinToVisibleBounds() -> Bool { flow.sectionHeadersPinToVisibleBounds }
    @ObjCMethod("setSectionHeadersPinToVisibleBounds:") func setSectionHeadersPinToVisibleBounds(_ pin: Bool) {
        flow.sectionHeadersPinToVisibleBounds = pin
        changed()
    }
    @ObjCMethod("sectionFootersPinToVisibleBounds") func sectionFootersPinToVisibleBounds() -> Bool { flow.sectionFootersPinToVisibleBounds }
    @ObjCMethod("setSectionFootersPinToVisibleBounds:") func setSectionFootersPinToVisibleBounds(_ pin: Bool) {
        flow.sectionFootersPinToVisibleBounds = pin
        changed()
    }
    @ObjCMethod("sectionInsetReference") func sectionInsetReference() -> Int { flow.sectionInsetReference }
    @ObjCMethod("setSectionInsetReference:") func setSectionInsetReference(_ reference: Int) { flow.sectionInsetReference = reference; changed() }

    // MARK: Metrics, from the delegate where it gives them

    private var vertical: Bool { flow.scrollDirection == 0 }

    private struct Metrics {
        var collection: UICollectionView
        var delegate: NSObject?
        var layout: UICollectionViewFlowLayout

        func asks(_ selector: String) -> Bool { delegate?.responds(to: selector) ?? false }

        func itemSize(_ path: RowPath) -> CGSize {
            if asks("collectionView:layout:sizeForItemAtIndexPath:") {
                return delegate!.sendCollectionView(collection, layout: layout, sizeForItemAt: path.object)
            }
            let flow = layout.flow
            if flow.estimatedItemSize != .zero {
                if let size = flow.measured[path] { return size }
                let estimate = flow.estimatedItemSize
                // UICollectionViewFlowLayoutAutomaticSize: a standard estimate.
                return estimate.width >= CGFloat.greatestFiniteMagnitude ? CGSize(width: 50, height: 50) : estimate
            }
            return flow.itemSize
        }

        func inset(_ section: Int) -> UIEdgeInsets {
            asks("collectionView:layout:insetForSectionAtIndex:")
                ? delegate!.sendCollectionView(collection, layout: layout, insetForSectionAt: section) : layout.flow.sectionInset
        }

        func lineSpacing(_ section: Int) -> CGFloat {
            asks("collectionView:layout:minimumLineSpacingForSectionAtIndex:")
                ? delegate!.sendCollectionView(collection, layout: layout, minimumLineSpacingForSectionAt: section)
                : layout.flow.minimumLineSpacing
        }

        func interitemSpacing(_ section: Int) -> CGFloat {
            asks("collectionView:layout:minimumInteritemSpacingForSectionAtIndex:")
                ? delegate!.sendCollectionView(collection, layout: layout, minimumInteritemSpacingForSectionAt: section)
                : layout.flow.minimumInteritemSpacing
        }

        func headerSize(_ section: Int) -> CGSize {
            asks("collectionView:layout:referenceSizeForHeaderInSection:")
                ? delegate!.sendCollectionView(collection, layout: layout, referenceSizeForHeaderInSection: section)
                : layout.flow.headerReferenceSize
        }

        func footerSize(_ section: Int) -> CGSize {
            asks("collectionView:layout:referenceSizeForFooterInSection:")
                ? delegate!.sendCollectionView(collection, layout: layout, referenceSizeForFooterInSection: section)
                : layout.flow.footerReferenceSize
        }
    }

    // MARK: Preparing

    /// Places every item: in lines across the scrolling direction, wrapped
    /// when the next would not fit, each line's items spread to fill it (a
    /// lone item centered) and centered within the line's depth.
    @ObjCMethod("prepareLayout")
    override func prepareLayout() {
        let flow = flow
        guard let collection else {
            flow.sections = []
            flow.contentSize = .zero
            return
        }
        let metrics = Metrics(collection: collection, delegate: collection.delegate(), layout: self)
        let bounds = collection.state.bounds
        let insets = collection.adjustedContentInset()
        let vertical = vertical
        // The room across, inside the content insets.
        let breadth = vertical ? bounds.width - insets.left - insets.right : bounds.height - insets.top - insets.bottom
        flow.preparedBreadth = vertical ? bounds.width : bounds.height
        var sections: [FlowSection] = []
        var along: CGFloat = 0
        for section in 0..<collection.numberOfSections() {
            let inset = metrics.inset(section)
            let (leading, trailing) = vertical ? (inset.left, inset.right) : (inset.top, inset.bottom)
            let (before, after) = vertical ? (inset.top, inset.bottom) : (inset.left, inset.right)
            let header = metrics.headerSize(section)
            let headerDepth = vertical ? header.height : header.width
            let headerRect = headerDepth > 0
                ? rect(across: 0, along: along, breadth: breadth, depth: headerDepth) : rect(across: 0, along: along, breadth: 0, depth: 0)
            along += max(headerDepth, 0) + before
            let lineSpacing = metrics.lineSpacing(section), interitem = metrics.interitemSpacing(section)
            let room = breadth - leading - trailing
            let count = collection.numberOfItems(inSection: section)
            var items = [CGRect](repeating: .zero, count: count)
            var line: [(index: Int, size: CGSize)] = []
            var lineBreadth: CGFloat = 0
            var firstLine = true

            func placeLine() {
                guard !line.isEmpty else { return }
                if !firstLine { along += lineSpacing }
                firstLine = false
                let depth = line.map { vertical ? $0.size.height : $0.size.width }.max() ?? 0
                let sizes = line.map { vertical ? $0.size.width : $0.size.height }
                let used = sizes.reduce(0, +)
                var position: CGFloat, gap: CGFloat
                if line.count == 1 {
                    position = leading + max(0, (room - used) / 2)
                    gap = 0
                } else {
                    position = leading
                    gap = max(interitem, (room - used) / CGFloat(line.count - 1))
                }
                for (offset, entry) in line.enumerated() {
                    let itemBreadth = sizes[offset], itemDepth = vertical ? entry.size.height : entry.size.width
                    items[entry.index] = rect(across: position, along: along + (depth - itemDepth) / 2,
                                              breadth: itemBreadth, depth: itemDepth)
                    position += itemBreadth + gap
                }
                along += depth
                line = []
                lineBreadth = 0
            }

            for index in 0..<count {
                var size = metrics.itemSize(RowPath(section: section, row: index))
                size = CGSize(width: size.width.isFinite ? max(size.width, 0) : 0, height: size.height.isFinite ? max(size.height, 0) : 0)
                let itemBreadth = vertical ? size.width : size.height
                if !line.isEmpty, lineBreadth + interitem + itemBreadth > room + 0.5 { placeLine() }
                lineBreadth += (line.isEmpty ? 0 : interitem) + itemBreadth
                line.append((index, size))
            }
            placeLine()
            along += after
            let footer = metrics.footerSize(section)
            let footerDepth = vertical ? footer.height : footer.width
            let footerRect = rect(across: 0, along: along, breadth: footerDepth > 0 ? breadth : 0, depth: max(footerDepth, 0))
            along += max(footerDepth, 0)
            sections.append(FlowSection(header: headerRect, items: items, footer: footerRect))
        }
        flow.sections = sections
        flow.contentSize = vertical ? CGSize(width: breadth, height: along) : CGSize(width: along, height: breadth)
    }

    /// A rectangle from positions across and along the scrolling direction.
    private func rect(across: CGFloat, along: CGFloat, breadth: CGFloat, depth: CGFloat) -> CGRect {
        vertical ? CGRect(x: across, y: along, width: breadth, height: depth) : CGRect(x: along, y: across, width: depth, height: breadth)
    }

    @ObjCMethod("collectionViewContentSize")
    override func collectionViewContentSize() -> CGSize { flow.contentSize }

    // MARK: Attributes

    private var attributesClass: ObjCClass { ObjCClass(ObjCRuntime.objectClass(objcObject)!).object.sendLayoutAttributesClass() }

    private func itemAttributes(_ path: RowPath) -> UICollectionViewLayoutAttributes? {
        let sections = flow.sections
        guard sections.indices.contains(path.section), sections[path.section].items.indices.contains(path.row) else { return nil }
        let attributes = UICollectionViewLayoutAttributes.make(attributesClass, path: path.object, category: 0, kind: nil)
        attributes.attributes.frame = sections[path.section].items[path.row]
        return attributes
    }

    /// A header or footer, pinned within its section's extent to the
    /// visible bounds when the layout pins them.
    private func supplementaryAttributes(kind: String, section: Int) -> UICollectionViewLayoutAttributes? {
        let sections = flow.sections
        guard sections.indices.contains(section) else { return nil }
        let geometry = sections[section]
        var frame = kind == CollectionElementKind.header ? geometry.header : geometry.footer
        guard frame.width > 0, frame.height > 0 else { return nil }
        let attributes = UICollectionViewLayoutAttributes.make(attributesClass, path: IndexPaths.make(section: section, row: 0),
                                                               category: 1, kind: kind)
        if let collection {
            let visible = collection.state.bounds, inset = collection.adjustedContentInset()
            let extent = geometry.rect
            if kind == CollectionElementKind.header, flow.sectionHeadersPinToVisibleBounds {
                if vertical {
                    frame.origin.y = min(max(frame.minY, visible.minY + inset.top), extent.maxY - frame.height)
                } else {
                    frame.origin.x = min(max(frame.minX, visible.minX + inset.left), extent.maxX - frame.width)
                }
                attributes.attributes.zIndex = 1024
            } else if kind == CollectionElementKind.footer, flow.sectionFootersPinToVisibleBounds {
                if vertical {
                    frame.origin.y = max(min(frame.minY, visible.maxY - inset.bottom - frame.height), extent.minY)
                } else {
                    frame.origin.x = max(min(frame.minX, visible.maxX - inset.right - frame.width), extent.minX)
                }
                attributes.attributes.zIndex = 1024
            } else {
                attributes.attributes.zIndex = 10
            }
        }
        attributes.attributes.frame = frame
        return attributes
    }

    @ObjCMethod("layoutAttributesForElementsInRect:")
    override func layoutAttributesForElements(in rect: CGRect) -> NSObject? {
        var found: [UICollectionViewLayoutAttributes] = []
        for (section, geometry) in flow.sections.enumerated() {
            for kind in [CollectionElementKind.header, CollectionElementKind.footer] {
                if let attributes = supplementaryAttributes(kind: kind, section: section), attributes.attributes.frame.intersects(rect) {
                    found.append(attributes)
                }
            }
            guard geometry.rect.intersects(rect) else { continue }
            for (item, frame) in geometry.items.enumerated() where frame.intersects(rect) {
                if let attributes = itemAttributes(RowPath(section: section, row: item)) { found.append(attributes) }
            }
        }
        return NSMutableArray.of(found)
    }

    @ObjCMethod("layoutAttributesForItemAtIndexPath:")
    override func layoutAttributesForItem(at path: NSObject) -> NSObject? { itemAttributes(RowPath(path)) }

    @ObjCMethod("layoutAttributesForSupplementaryViewOfKind:atIndexPath:")
    override func layoutAttributesForSupplementaryView(kind: String, at path: NSObject) -> NSObject? {
        supplementaryAttributes(kind: kind, section: path.sendSection())
    }

    /// When the breadth changes, or as it scrolls while headers or footers
    /// are pinned.
    @ObjCMethod("shouldInvalidateLayoutForBoundsChange:")
    override func shouldInvalidateLayout(forBoundsChange bounds: CGRect) -> Bool {
        let flow = flow
        if flow.sectionHeadersPinToVisibleBounds || flow.sectionFootersPinToVisibleBounds { return true }
        return (vertical ? bounds.width : bounds.height) != flow.preparedBreadth
    }

    /// A self-sizing item's measured size, which the layout keeps.
    func record(_ size: CGSize, for path: RowPath) -> Bool {
        guard flow.estimatedItemSize != .zero, flow.measured[path] != size else { return false }
        flow.measured[path] = size
        return true
    }
}

// MARK: - UICollectionView

final class CollectionViewState: ObjectState {
    var layout: UICollectionViewLayout?
    var dataSource: UnsafeMutableRawPointer?
    var cellClasses: [String: ObjCClass] = [:]
    var cellNibs: [String: UINib] = [:]
    var supplementaryClasses: [String: ObjCClass] = [:]
    var supplementaryNibs: [String: UINib] = [:]
    var reusableCells: [String: [UICollectionViewCell]] = [:]
    var reusableSupplementary: [String: [UICollectionReusableView]] = [:]
    var visibleCells: [RowPath: UICollectionViewCell] = [:]
    var visibleSupplementary: [SupplementaryKey: UICollectionReusableView] = [:]
    var selected: Set<RowPath> = []
    var allowsSelection = true
    var allowsMultipleSelection = false
    var allowsSelectionDuringEditing = false
    var allowsMultipleSelectionDuringEditing = false
    var editing = false
    var backgroundView: UIView?
    /// Items per section, asked of the data source when the layout is prepared.
    var counts: [Int]?
    /// Whether the layout has been prepared for the current data and size.
    var prepared = false
    var lastBounds: CGRect?
    var laying = false
}

@ObjCClass("UICollectionView")
open class UICollectionView: UIScrollView {
    static let collectionStates = StateTable<CollectionViewState>()
    var collection: CollectionViewState { UICollectionView.collectionStates[objcObject] }

    @ObjCMethod("initWithFrame:collectionViewLayout:")
    func initialize(frame: CGRect, collectionViewLayout layout: UICollectionViewLayout?) -> NSObject {
        let view = initializeView(frame: frame).unsafeCast(to: UICollectionView.self)
        view.setCollectionViewLayout(layout)
        return view
    }

    @ObjCMethod("initWithFrame:")
    override func initialize(frame: CGRect) -> Self {
        _ = super.initialize(frame: frame)
        setBackgroundColor(UIColor.systemBackground())
        return self
    }

    /// From a nib: the layout, and the prototype cells' nibs by reuse
    /// identifier.
    @ObjCMethod("initWithCoder:")
    override func initialize(coder: NSObject) -> Self {
        _ = super.initialize(coder: coder)
        let decoded = Coder(coder: coder)
        let layout = (decoded.object("UICollectionLayout") ?? decoded.object("UICollectionViewLayout"))?.as(UICollectionViewLayout.self)
        setCollectionViewLayout(layout ?? UICollectionViewFlowLayout.objCClass.object.newInstance().unsafeCast(to: UICollectionViewLayout.self))
        for key in ["UICollectionViewCellPrototypeNibs", "UICollectionViewCellNibDict"] {
            for (identifier, nib) in decoded.dictionary(key) {
                if let nib = nib.as(UINib.self) { collection.cellNibs[identifier] = nib }
            }
        }
        // Supplementary prototypes, named by their kind and reuse identifier
        // ("UICollectionElementKindSectionHeader/Container").
        for (name, nib) in decoded.dictionary("UICollectionViewSupplementaryViewNibDict") {
            guard let nib = nib.as(UINib.self), let slash = name.firstIndex(of: "/") else { continue }
            collection.supplementaryNibs[Self.supplementaryKey(String(name[..<slash]), String(name[name.index(after: slash)...]))] = nib
        }
        if decoded.has("UIAllowsMultipleSelection") { collection.allowsMultipleSelection = decoded.bool("UIAllowsMultipleSelection") }
        if decoded.has("UIAllowsSelection") { collection.allowsSelection = decoded.bool("UIAllowsSelection") }
        return self
    }

    @ObjCMethod("dealloc")
    override func dealloc() {
        if let layout = collection.layout, layout.layoutState.collectionView == objcObject { layout.layoutState.collectionView = nil }
        UICollectionView.collectionStates.remove(objcObject)
        super.dealloc()
    }

    // MARK: Properties

    @ObjCMethod("collectionViewLayout") func collectionViewLayout() -> UICollectionViewLayout? { collection.layout }

    @ObjCMethod("setCollectionViewLayout:")
    func setCollectionViewLayout(_ layout: UICollectionViewLayout?) {
        if let old = collection.layout, old.layoutState.collectionView == objcObject { old.layoutState.collectionView = nil }
        collection.layout = layout
        layout?.layoutState.collectionView = objcObject
        layoutInvalidated()
    }

    @ObjCMethod("setCollectionViewLayout:animated:")
    func setCollectionViewLayout(_ layout: UICollectionViewLayout?, animated: Bool) { setCollectionViewLayout(layout) }

    @ObjCMethod("setCollectionViewLayout:animated:completion:")
    func setCollectionViewLayout(_ layout: UICollectionViewLayout?, animated: Bool, completion: ObjCBlock?) {
        setCollectionViewLayout(layout)
        if let completion { Updates.afterPass { Blocks.call(completion, true) } }
    }

    @ObjCMethod("dataSource") func dataSource() -> NSObject? { collection.dataSource.map { NSObject($0) } }
    @ObjCMethod("setDataSource:") func setDataSource(_ source: NSObject?) {
        collection.dataSource = source?.objcObject
        reloadData()
    }

    @ObjCMethod("setDelegate:")
    override func setDelegate(_ delegate: NSObject?) {
        scroll.delegate.object = delegate?.objcObject
        layoutInvalidated()
    }

    @ObjCMethod("backgroundView") func backgroundView() -> UIView? { collection.backgroundView }
    /// A view behind the items, the size of the visible area.
    @ObjCMethod("setBackgroundView:")
    func setBackgroundView(_ view: UIView?) {
        if let old = collection.backgroundView, old.objcObject != view?.objcObject, old.state.superview == objcObject { old.removeFromSuperview() }
        collection.backgroundView = view
        if let view {
            if view.state.superview != objcObject { insertSubview(view, at: 0) }
            view.sendSetFrame(state.bounds)
        }
        setNeedsLayout()
    }

    @ObjCMethod("allowsSelection") func allowsSelection() -> Bool { collection.allowsSelection }
    @ObjCMethod("setAllowsSelection:") func setAllowsSelection(_ allows: Bool) { collection.allowsSelection = allows }
    @ObjCMethod("allowsMultipleSelection") func allowsMultipleSelection() -> Bool { collection.allowsMultipleSelection }
    @ObjCMethod("setAllowsMultipleSelection:") func setAllowsMultipleSelection(_ allows: Bool) { collection.allowsMultipleSelection = allows }
    @ObjCMethod("allowsSelectionDuringEditing") func allowsSelectionDuringEditing() -> Bool { collection.allowsSelectionDuringEditing }
    @ObjCMethod("setAllowsSelectionDuringEditing:") func setAllowsSelectionDuringEditing(_ allows: Bool) {
        collection.allowsSelectionDuringEditing = allows
    }
    @ObjCMethod("allowsMultipleSelectionDuringEditing") func allowsMultipleSelectionDuringEditing() -> Bool {
        collection.allowsMultipleSelectionDuringEditing
    }
    @ObjCMethod("setAllowsMultipleSelectionDuringEditing:") func setAllowsMultipleSelectionDuringEditing(_ allows: Bool) {
        collection.allowsMultipleSelectionDuringEditing = allows
    }
    @ObjCMethod("isEditing") func isEditing() -> Bool { collection.editing }
    @ObjCMethod("setEditing:") func setEditing(_ editing: Bool) { collection.editing = editing }

    /// Prefetching, drag and drop and focus, which are not offered here.
    @ObjCMethod("prefetchDataSource") func prefetchDataSource() -> NSObject? { nil }
    @ObjCMethod("setPrefetchDataSource:") func setPrefetchDataSource(_ source: NSObject?) {}
    @ObjCMethod("isPrefetchingEnabled") func isPrefetchingEnabled() -> Bool { false }
    @ObjCMethod("setPrefetchingEnabled:") func setPrefetchingEnabled(_ enabled: Bool) {}
    @ObjCMethod("dragDelegate") func dragDelegate() -> NSObject? { nil }
    @ObjCMethod("setDragDelegate:") func setDragDelegate(_ delegate: NSObject?) {}
    @ObjCMethod("dropDelegate") func dropDelegate() -> NSObject? { nil }
    @ObjCMethod("setDropDelegate:") func setDropDelegate(_ delegate: NSObject?) {}
    @ObjCMethod("dragInteractionEnabled") func dragInteractionEnabled() -> Bool { false }
    @ObjCMethod("setDragInteractionEnabled:") func setDragInteractionEnabled(_ enabled: Bool) {}
    @ObjCMethod("hasActiveDrag") func hasActiveDrag() -> Bool { false }
    @ObjCMethod("hasActiveDrop") func hasActiveDrop() -> Bool { false }
    @ObjCMethod("remembersLastFocusedIndexPath") func remembersLastFocusedIndexPath() -> Bool { false }
    @ObjCMethod("setRemembersLastFocusedIndexPath:") func setRemembersLastFocusedIndexPath(_ remembers: Bool) {}
    @ObjCMethod("reorderingCadence") func reorderingCadence() -> Int { 0 }
    @ObjCMethod("setReorderingCadence:") func setReorderingCadence(_ cadence: Int) {}

    // MARK: Registration and reuse

    private static func supplementaryKey(_ kind: String, _ identifier: String) -> String { kind + "\u{1}" + identifier }

    @ObjCMethod("registerClass:forCellWithReuseIdentifier:")
    func register(_ cls: ObjCClass?, forCellWithReuseIdentifier identifier: String) {
        collection.cellClasses[identifier] = cls
        collection.cellNibs[identifier] = nil
    }

    @ObjCMethod("registerNib:forCellWithReuseIdentifier:")
    func register(nib: NSObject?, forCellWithReuseIdentifier identifier: String) {
        collection.cellNibs[identifier] = nib?.as(UINib.self)
        if nib != nil { collection.cellClasses[identifier] = nil }
    }

    @ObjCMethod("registerClass:forSupplementaryViewOfKind:withReuseIdentifier:")
    func register(_ cls: ObjCClass?, forSupplementaryViewOfKind kind: String, withReuseIdentifier identifier: String) {
        let key = Self.supplementaryKey(kind, identifier)
        collection.supplementaryClasses[key] = cls
        collection.supplementaryNibs[key] = nil
    }

    @ObjCMethod("registerNib:forSupplementaryViewOfKind:withReuseIdentifier:")
    func register(nib: NSObject?, forSupplementaryViewOfKind kind: String, withReuseIdentifier identifier: String) {
        let key = Self.supplementaryKey(kind, identifier)
        collection.supplementaryNibs[key] = nib?.as(UINib.self)
        if nib != nil { collection.supplementaryClasses[key] = nil }
    }

    /// A reusable view of a registered class or nib, with its reuse
    /// identifier.
    private func makeReusable(cls: ObjCClass?, nib: UINib?, identifier: String) -> UICollectionReusableView? {
        var made: UICollectionReusableView?
        if let nib {
            made = nib.instantiate(owner: nil, external: [:]).first { $0.is(UICollectionReusableView.self) }?
                .unsafeCast(to: UICollectionReusableView.self)
        } else if let cls {
            made = cls.object.allocated().initializeView(frame: .zero).unsafeCast(to: UICollectionReusableView.self)
        }
        if let made, made.reusable.reuseIdentifier == nil { made.reusable.reuseIdentifier = identifier }
        return made
    }

    @ObjCMethod("dequeueReusableCellWithReuseIdentifier:forIndexPath:")
    func dequeueReusableCell(identifier: String, for indexPath: NSObject) -> UICollectionViewCell {
        if let cell = collection.reusableCells[identifier]?.popLast() {
            cell.sendPrepareForReuse()
            return cell
        }
        guard let made = makeReusable(cls: collection.cellClasses[identifier], nib: collection.cellNibs[identifier], identifier: identifier),
              made.is(UICollectionViewCell.self) else {
            uikitFatal("could not dequeue a view of kind: UICollectionElementKindCell with identifier \(identifier) - must register a nib or a class for the identifier")
        }
        return made.unsafeCast(to: UICollectionViewCell.self)
    }

    @ObjCMethod("dequeueReusableSupplementaryViewOfKind:withReuseIdentifier:forIndexPath:")
    func dequeueReusableSupplementaryView(kind: String, identifier: String, for indexPath: NSObject) -> UICollectionReusableView {
        let key = Self.supplementaryKey(kind, identifier)
        if let view = collection.reusableSupplementary[key]?.popLast() {
            view.sendPrepareForReuse()
            return view
        }
        guard let made = makeReusable(cls: collection.supplementaryClasses[key], nib: collection.supplementaryNibs[key], identifier: identifier) else {
            uikitFatal("could not dequeue a view of kind: \(kind) with identifier \(identifier) - must register a nib or a class for the identifier")
        }
        return made
    }

    // MARK: Data

    private func counts() -> [Int] {
        if let counts = collection.counts { return counts }
        var counts: [Int] = []
        if let source = dataSource() {
            let sections = source.responds(to: "numberOfSectionsInCollectionView:") ? source.sendNumberOfSections(in: self) : 1
            for section in 0..<max(sections, 0) {
                counts.append(max(source.sendCollectionView(self, numberOfItemsInSection: section), 0))
            }
        }
        collection.counts = counts
        return counts
    }

    @ObjCMethod("numberOfSections") func numberOfSections() -> Int { counts().count }

    @ObjCMethod("numberOfItemsInSection:")
    func numberOfItems(inSection section: Int) -> Int {
        let counts = counts()
        return counts.indices.contains(section) ? counts[section] : 0
    }

    private func contains(_ path: RowPath) -> Bool {
        let counts = counts()
        return counts.indices.contains(path.section) && path.row >= 0 && path.row < counts[path.section]
    }

    // MARK: Layout

    /// The layout is prepared again at the next layout pass.
    func layoutInvalidated() {
        collection.prepared = false
        setNeedsLayout()
    }

    /// Prepares the layout, if it must be, and sizes the content to it.
    private func prepareLayoutIfNeeded() {
        guard let layout = collection.layout, !collection.prepared else { return }
        collection.prepared = true
        layout.sendPrepareLayout()
        let size = layout.sendCollectionViewContentSize()
        if scroll.contentSize != size { scroll.contentSize = size }
    }

    /// The layout's attributes for an item, its frame among them.
    @ObjCMethod("layoutAttributesForItemAtIndexPath:")
    func layoutAttributesForItem(at indexPath: NSObject) -> UICollectionViewLayoutAttributes? {
        prepareLayoutIfNeeded()
        return collection.layout?.sendLayoutAttributesForItem(at: indexPath)?.as(UICollectionViewLayoutAttributes.self)
    }

    @ObjCMethod("layoutAttributesForSupplementaryElementOfKind:atIndexPath:")
    func layoutAttributesForSupplementaryElement(kind: String, at indexPath: NSObject) -> UICollectionViewLayoutAttributes? {
        prepareLayoutIfNeeded()
        return collection.layout?.sendLayoutAttributesForSupplementaryView(kind: kind, at: indexPath)?
            .as(UICollectionViewLayoutAttributes.self)
    }

    private func attributes(in rect: CGRect) -> [UICollectionViewLayoutAttributes] {
        guard let found = collection.layout?.sendLayoutAttributesForElements(in: rect)?.as(NSArray.self) else { return [] }
        return found.elements.compactMap { $0.as(UICollectionViewLayoutAttributes.self) }
    }

    /// Asks the layout, as UIKit does when the bounds change, whether it
    /// must be prepared again; then shows a cell for each item in view and
    /// a view for each header and footer, puts each where the layout says,
    /// and returns those that left the view to their pools.
    @ObjCMethod("layoutSubviews")
    override func layoutSubviews() {
        applyAdjustedInset()
        guard !collection.laying else { return }
        collection.laying = true
        defer { collection.laying = false }
        let bounds = state.bounds
        if bounds != collection.lastBounds {
            if collection.lastBounds == nil || (collection.layout?.sendShouldInvalidateLayout(forBoundsChange: bounds) ?? false) {
                collection.prepared = false
            }
            collection.lastBounds = bounds
        }
        if let background = collection.backgroundView, background.state.frame != bounds { background.sendSetFrame(bounds) }
        // Self-sizing cells may change the layout: place them again then.
        for _ in 0..<3 {
            prepareLayoutIfNeeded()
            showElements(in: state.bounds)
            if collection.prepared { break }
        }
    }

    private func showElements(in bounds: CGRect) {
        let found = attributes(in: bounds)
        let source = dataSource(), delegate = delegate()
        var wantedCells: Set<RowPath> = []
        var wantedViews: Set<SupplementaryKey> = []
        for attributes in found {
            guard let path = attributes.path else { continue }
            switch attributes.attributes.category {
            case 0:
                guard contains(path) else { continue }
                wantedCells.insert(path)
                var cell = collection.visibleCells[path]
                // A cell shown already keeps the size it measured; one
                // dequeued for the item now is measured once.
                let fresh = cell == nil
                if cell == nil {
                    guard let made = source?.sendCollectionView(self, cellForItemAt: path.object) else {
                        uikitFatal("the cell returned from -collectionView:cellForItemAtIndexPath: does not have a reuseIdentifier")
                    }
                    collection.visibleCells[path] = made
                    insert(made, behind: true)
                    if made.collectionCell.selected != collection.selected.contains(path) {
                        made.sendSetSelected(collection.selected.contains(path))
                    }
                    if let delegate, delegate.responds(to: "collectionView:willDisplayCell:forItemAtIndexPath:") {
                        delegate.sendCollectionView(self, willDisplay: made, forItemAt: path.object)
                    }
                    cell = made
                }
                apply(attributes, to: cell!, fresh: fresh)
                if fresh { measure(cell!, attributes: attributes, at: path) }
            case 1:
                guard let kind = attributes.attributes.kind else { continue }
                let key = SupplementaryKey(kind: kind, path: path)
                wantedViews.insert(key)
                var view = collection.visibleSupplementary[key]
                let fresh = view == nil
                if view == nil {
                    guard let source, source.responds(to: "collectionView:viewForSupplementaryElementOfKind:atIndexPath:"),
                          let made = source.sendCollectionView(self, viewForSupplementaryElementOfKind: kind, at: path.object) else { continue }
                    collection.visibleSupplementary[key] = made
                    insert(made, behind: false)
                    if let delegate, delegate.responds(to: "collectionView:willDisplaySupplementaryView:forElementKind:atIndexPath:") {
                        delegate.sendCollectionView(self, willDisplaySupplementaryView: made, forElementKind: kind, at: path.object)
                    }
                    view = made
                }
                apply(attributes, to: view!, fresh: fresh)
                if fresh, let layout = collection.layout?.as(UICollectionViewCompositionalLayout.self), layout.isEstimated(key) {
                    let width = attributes.attributes.frame.width
                    if let height = AutoLayout.fittingHeight(view!, width: width), layout.record(height: height, for: key) {
                        collection.prepared = false
                    }
                }
            default:
                continue
            }
        }
        for (path, cell) in collection.visibleCells where !wantedCells.contains(path) {
            collection.visibleCells[path] = nil
            enqueue(cell)
            if let delegate, delegate.responds(to: "collectionView:didEndDisplayingCell:forItemAtIndexPath:") {
                delegate.sendCollectionView(self, didEndDisplaying: cell, forItemAt: path.object)
            }
        }
        for (key, view) in collection.visibleSupplementary where !wantedViews.contains(key) {
            collection.visibleSupplementary[key] = nil
            enqueue(view, kind: key.kind)
        }
        // Higher z-indexes in front.
        let ordered = found.filter { $0.attributes.zIndex != 0 }.sorted { $0.attributes.zIndex < $1.attributes.zIndex }
        for attributes in ordered {
            guard let path = attributes.path else { continue }
            let view: UIView? = attributes.attributes.category == 0 ? collection.visibleCells[path]
                : attributes.attributes.kind.flatMap { collection.visibleSupplementary[SupplementaryKey(kind: $0, path: path)] }
            if let view { bringSubviewToFront(view) }
        }
    }

    /// Cells go behind the collection view's own subviews (such as an app's
    /// indicator bar), above its background view; headers in front.
    private func insert(_ view: UICollectionReusableView, behind: Bool) {
        if view.state.superview != objcObject {
            if behind {
                insertSubview(view, at: collection.backgroundView?.state.superview == objcObject ? 1 : 0)
            } else {
                addSubview(view)
            }
        }
        view.state.hidden = false
    }

    /// The attributes' frame, visibility and alpha; the view hears of them
    /// (-applyLayoutAttributes:) when it is new to its item or moved, not on
    /// every pass as the collection scrolls.
    private func apply(_ attributes: UICollectionViewLayoutAttributes, to view: UICollectionReusableView, fresh: Bool) {
        let values = attributes.attributes
        let moved = view.state.frame != values.frame
        if moved { view.sendSetFrame(values.frame) }
        if view.state.hidden != values.hidden { view.state.hidden = values.hidden }
        if view.state.alpha != values.alpha { view.setAlpha(values.alpha) }
        if fresh || moved { view.sendApply(attributes) }
        view.layoutIfNeeded()
    }

    /// A self-sizing item takes the size its cell prefers, its content
    /// view's constraints giving the height at the estimated width; the
    /// layout is prepared again if that changes it.
    private func measure(_ cell: UICollectionViewCell, attributes: UICollectionViewLayoutAttributes, at path: RowPath) {
        // A compositional layout's estimated item takes its cell's height at
        // the width it was given.
        if let layout = collection.layout?.as(UICollectionViewCompositionalLayout.self) {
            guard layout.isEstimated(path), let content = cell.collectionCell.contentView else { return }
            let width = attributes.attributes.frame.width
            var height = AutoLayout.fittingHeight(content, width: width)
            if height == nil {
                let candidate = attributes.copied().unsafeCast(to: UICollectionViewLayoutAttributes.self)
                let preferred = cell.sendPreferredLayoutAttributes(fitting: candidate)?.as(UICollectionViewLayoutAttributes.self)
                height = preferred?.attributes.frame.height
            }
            if let height, layout.record(height: height, for: path) { collection.prepared = false }
            return
        }
        guard let flow = collection.layout?.as(UICollectionViewFlowLayout.self), flow.flow.estimatedItemSize != .zero,
              !(delegate()?.responds(to: "collectionView:layout:sizeForItemAtIndexPath:") ?? false) else { return }
        let candidate = attributes.copied().unsafeCast(to: UICollectionViewLayoutAttributes.self)
        if let content = cell.collectionCell.contentView,
           let height = AutoLayout.fittingHeight(content, width: attributes.attributes.frame.width) {
            candidate.attributes.frame.size.height = height
        }
        let preferred = cell.sendPreferredLayoutAttributes(fitting: candidate)?.as(UICollectionViewLayoutAttributes.self) ?? candidate
        let size = preferred.attributes.frame.size
        if size.width > 0, size.height > 0, flow.record(size, for: path) { collection.prepared = false }
    }

    private func enqueue(_ cell: UICollectionViewCell) {
        cell.state.hidden = true
        guard let identifier = cell.reusable.reuseIdentifier else {
            cell.removeFromSuperview()
            return
        }
        collection.reusableCells[identifier, default: []].append(cell)
    }

    private func enqueue(_ view: UICollectionReusableView, kind: String) {
        view.state.hidden = true
        guard let identifier = view.reusable.reuseIdentifier else {
            view.removeFromSuperview()
            return
        }
        collection.reusableSupplementary[Self.supplementaryKey(kind, identifier), default: []].append(view)
    }

    // MARK: Finding items

    @ObjCMethod("cellForItemAtIndexPath:")
    func cellForItem(at indexPath: NSObject) -> UICollectionViewCell? { collection.visibleCells[RowPath(indexPath)] }

    @ObjCMethod("indexPathForCell:")
    func indexPath(for cell: UICollectionViewCell) -> NSObject? {
        collection.visibleCells.first { $0.value.objcObject == cell.objcObject }?.key.object
    }

    @ObjCMethod("indexPathForItemAtPoint:")
    func indexPathForItem(at point: CGPoint) -> NSObject? {
        prepareLayoutIfNeeded()
        let hits = attributes(in: CGRect(x: point.x - 0.5, y: point.y - 0.5, width: 1, height: 1))
        return hits.first { $0.attributes.category == 0 && $0.attributes.frame.contains(point) }?.attributes.indexPath
    }

    @ObjCMethod("visibleCells")
    func visibleCells() -> NSObject { NSMutableArray.of(collection.visibleCells.sorted { $0.key < $1.key }.map(\.value)) }

    @ObjCMethod("indexPathsForVisibleItems")
    func indexPathsForVisibleItems() -> NSObject { NSMutableArray.of(collection.visibleCells.keys.sorted().map(\.object)) }

    @ObjCMethod("supplementaryViewForElementKind:atIndexPath:")
    func supplementaryView(kind: String, at indexPath: NSObject) -> UICollectionReusableView? {
        collection.visibleSupplementary[SupplementaryKey(kind: kind, path: RowPath(indexPath))]
    }

    @ObjCMethod("visibleSupplementaryViewsOfKind:")
    func visibleSupplementaryViews(kind: String) -> NSObject {
        NSMutableArray.of(collection.visibleSupplementary.filter { $0.key.kind == kind }.sorted { $0.key.path < $1.key.path }.map(\.value))
    }

    @ObjCMethod("indexPathsForVisibleSupplementaryElementsOfKind:")
    func indexPathsForVisibleSupplementaryElements(kind: String) -> NSObject {
        NSMutableArray.of(collection.visibleSupplementary.keys.filter { $0.kind == kind }.map(\.path).sorted().map(\.object))
    }

    // MARK: Reloading and updating

    /// Every visible cell and view goes back to its pool; the data source
    /// is asked again at the next layout pass.
    @ObjCMethod("reloadData")
    func reloadData() {
        for (_, cell) in collection.visibleCells { enqueue(cell) }
        collection.visibleCells = [:]
        for (key, view) in collection.visibleSupplementary { enqueue(view, kind: key.kind) }
        collection.visibleSupplementary = [:]
        collection.counts = nil
        collection.selected = collection.selected.filter(contains)
        if let flow = collection.layout?.as(UICollectionViewFlowLayout.self) { flow.flow.measured = [:] }
        layoutInvalidated()
    }

    /// The items' cells are asked for again.
    @ObjCMethod("reloadItemsAtIndexPaths:")
    func reloadItems(at paths: NSArray) {
        for path in paths.elements.map(RowPath.init) {
            if let cell = collection.visibleCells.removeValue(forKey: path) { enqueue(cell) }
        }
        layoutInvalidated()
    }

    /// Changes to the items reload the data, without animation.
    @ObjCMethod("insertItemsAtIndexPaths:") func insertItems(at paths: NSArray) { reloadData() }
    @ObjCMethod("deleteItemsAtIndexPaths:") func deleteItems(at paths: NSArray) { reloadData() }
    @ObjCMethod("moveItemAtIndexPath:toIndexPath:") func moveItem(at from: NSObject, to destination: NSObject) { reloadData() }
    @ObjCMethod("insertSections:") func insertSections(_ sections: NSObject) { reloadData() }
    @ObjCMethod("deleteSections:") func deleteSections(_ sections: NSObject) { reloadData() }
    @ObjCMethod("reloadSections:") func reloadSections(_ sections: NSObject) { reloadData() }
    @ObjCMethod("moveSection:toSection:") func moveSection(_ section: Int, to destination: Int) { reloadData() }

    @ObjCMethod("performBatchUpdates:completion:")
    func performBatchUpdates(_ updates: ObjCBlock?, completion: ObjCBlock?) {
        updates.map(Blocks.call)
        reloadData()
        layoutIfNeeded()
        if let completion { Updates.afterPass { Blocks.call(completion, true) } }
    }

    /// Interactive moves follow the finger in UIKit; here an item is moved
    /// only by the data source when the move ends, which it is not told of.
    @ObjCMethod("beginInteractiveMovementForItemAtIndexPath:")
    func beginInteractiveMovement(at path: NSObject) -> Bool { false }
    @ObjCMethod("updateInteractiveMovementTargetPosition:") func updateInteractiveMovementTargetPosition(_ position: CGPoint) {}
    @ObjCMethod("endInteractiveMovement") func endInteractiveMovement() {}
    @ObjCMethod("cancelInteractiveMovement") func cancelInteractiveMovement() {}

    // MARK: Selection

    @ObjCMethod("indexPathsForSelectedItems")
    func indexPathsForSelectedItems() -> NSObject? { NSMutableArray.of(collection.selected.sorted().map(\.object)) }

    /// Selects without telling the delegate, as UIKit does for selection
    /// made in code.
    @ObjCMethod("selectItemAtIndexPath:animated:scrollPosition:")
    func selectItem(at indexPath: NSObject?, animated: Bool, scrollPosition: UInt) {
        guard let indexPath else {
            deselectAll()
            return
        }
        let path = RowPath(indexPath)
        if !collection.allowsMultipleSelection { deselectAll(except: path) }
        collection.selected.insert(path)
        collection.visibleCells[path]?.sendSetSelected(true)
        if scrollPosition != 0 { scrollToItem(at: indexPath, at: scrollPosition, animated: animated) }
    }

    @ObjCMethod("deselectItemAtIndexPath:animated:")
    func deselectItem(at indexPath: NSObject, animated: Bool) {
        let path = RowPath(indexPath)
        collection.selected.remove(path)
        collection.visibleCells[path]?.sendSetSelected(false)
    }

    private func deselectAll(except kept: RowPath? = nil) {
        for path in collection.selected where path != kept { collection.visibleCells[path]?.sendSetSelected(false) }
        collection.selected = collection.selected.filter { $0 == kept }
    }

    private func asks(_ delegate: NSObject?, _ selector: String) -> Bool { delegate?.responds(to: selector) ?? false }

    /// Selects or deselects an item as a tap does, asking and telling the
    /// delegate.
    func tapItem(_ path: RowPath) {
        let editing = collection.editing
        guard editing ? collection.allowsSelectionDuringEditing || collection.allowsSelection : collection.allowsSelection else { return }
        let delegate = delegate(), indexPath = path.object
        let multiple = editing ? collection.allowsMultipleSelectionDuringEditing || collection.allowsMultipleSelection
            : collection.allowsMultipleSelection
        if multiple, collection.selected.contains(path) {
            if asks(delegate, "collectionView:shouldDeselectItemAtIndexPath:"), !delegate!.sendCollectionView(self, shouldDeselectItemAt: indexPath) {
                return
            }
            deselectItem(at: indexPath, animated: false)
            if asks(delegate, "collectionView:didDeselectItemAtIndexPath:") { delegate!.sendCollectionView(self, didDeselectItemAt: indexPath) }
            return
        }
        if asks(delegate, "collectionView:shouldSelectItemAtIndexPath:"), !delegate!.sendCollectionView(self, shouldSelectItemAt: indexPath) {
            return
        }
        if !multiple {
            for previous in collection.selected.sorted() where previous != path {
                deselectItem(at: previous.object, animated: false)
                if asks(delegate, "collectionView:didDeselectItemAtIndexPath:") {
                    delegate!.sendCollectionView(self, didDeselectItemAt: previous.object)
                }
            }
        }
        collection.selected.insert(path)
        collection.visibleCells[path]?.sendSetSelected(true)
        if asks(delegate, "collectionView:didSelectItemAtIndexPath:") { delegate!.sendCollectionView(self, didSelectItemAt: indexPath) }
    }

    /// Whether the delegate lets a touch highlight the item.
    func shouldHighlight(_ path: RowPath) -> Bool {
        let delegate = delegate()
        guard asks(delegate, "collectionView:shouldHighlightItemAtIndexPath:") else { return true }
        return delegate!.sendCollectionView(self, shouldHighlightItemAt: path.object)
    }

    // MARK: Scrolling

    /// UICollectionViewScrollPosition: top 1, centered vertically 2,
    /// bottom 4, left 8, centered horizontally 16, right 32; none scrolls
    /// just enough to show the item.
    @ObjCMethod("scrollToItemAtIndexPath:atScrollPosition:animated:")
    func scrollToItem(at indexPath: NSObject, at position: UInt, animated: Bool) {
        guard let frame = layoutAttributesForItem(at: indexPath)?.attributes.frame else { return }
        let bounds = state.bounds, inset = adjustedContentInset(), size = scroll.contentSize
        var offset = bounds.origin
        if position & 1 != 0 { offset.y = frame.minY - inset.top }
        if position & 2 != 0 { offset.y = frame.midY - bounds.height / 2 }
        if position & 4 != 0 { offset.y = frame.maxY - bounds.height + inset.bottom }
        if position & 8 != 0 { offset.x = frame.minX - inset.left }
        if position & 16 != 0 { offset.x = frame.midX - bounds.width / 2 }
        if position & 32 != 0 { offset.x = frame.maxX - bounds.width + inset.right }
        if position == 0 {
            scrollRectToVisible(frame, animated: animated)
            return
        }
        offset.x = min(max(offset.x, -inset.left), max(-inset.left, size.width + inset.right - bounds.width))
        offset.y = min(max(offset.y, -inset.top), max(-inset.top, size.height + inset.bottom - bounds.height))
        setContentOffset(offset, animated: animated)
    }
}

/// UICollectionView's messages to its layout, cells, data source and delegate.
extension NSObject {
    @ObjCMethod("initWithFrame:collectionViewLayout:") func initializeCollection(frame: CGRect, layout: NSObject?) -> NSObject
    @ObjCMethod("prepareLayout") func sendPrepareLayout()
    @ObjCMethod("collectionViewContentSize") func sendCollectionViewContentSize() -> CGSize
    @ObjCMethod("layoutAttributesForElementsInRect:") func sendLayoutAttributesForElements(in rect: CGRect) -> NSObject?
    @ObjCMethod("layoutAttributesForItemAtIndexPath:") func sendLayoutAttributesForItem(at path: NSObject) -> NSObject?
    @ObjCMethod("layoutAttributesForSupplementaryViewOfKind:atIndexPath:")
    func sendLayoutAttributesForSupplementaryView(kind: String, at path: NSObject) -> NSObject?
    @ObjCMethod("shouldInvalidateLayoutForBoundsChange:") func sendShouldInvalidateLayout(forBoundsChange bounds: CGRect) -> Bool
    @ObjCMethod("invalidateLayout") func sendInvalidateLayout()
    @ObjCMethod("layoutAttributesClass") func sendLayoutAttributesClass() -> ObjCClass
    @ObjCMethod("invalidationContextClass") func sendInvalidationContextClass() -> ObjCClass
    @ObjCMethod("applyLayoutAttributes:") func sendApply(_ attributes: NSObject)
    @ObjCMethod("preferredLayoutAttributesFittingAttributes:") func sendPreferredLayoutAttributes(fitting attributes: NSObject) -> NSObject?
    @ObjCMethod("setSelected:") func sendSetSelected(_ selected: Bool)
    @ObjCMethod("setHighlighted:") func sendSetHighlighted(_ highlighted: Bool)
    @ObjCMethod("numberOfSectionsInCollectionView:") func sendNumberOfSections(in collection: UICollectionView) -> Int
    @ObjCMethod("collectionView:numberOfItemsInSection:")
    func sendCollectionView(_ collection: UICollectionView, numberOfItemsInSection section: Int) -> Int
    @ObjCMethod("collectionView:cellForItemAtIndexPath:")
    func sendCollectionView(_ collection: UICollectionView, cellForItemAt path: NSObject) -> UICollectionViewCell?
    @ObjCMethod("collectionView:viewForSupplementaryElementOfKind:atIndexPath:")
    func sendCollectionView(_ collection: UICollectionView, viewForSupplementaryElementOfKind kind: String, at path: NSObject) -> UICollectionReusableView?
    @ObjCMethod("collectionView:willDisplayCell:forItemAtIndexPath:")
    func sendCollectionView(_ collection: UICollectionView, willDisplay cell: UICollectionViewCell, forItemAt path: NSObject)
    @ObjCMethod("collectionView:didEndDisplayingCell:forItemAtIndexPath:")
    func sendCollectionView(_ collection: UICollectionView, didEndDisplaying cell: UICollectionViewCell, forItemAt path: NSObject)
    @ObjCMethod("collectionView:willDisplaySupplementaryView:forElementKind:atIndexPath:")
    func sendCollectionView(_ collection: UICollectionView, willDisplaySupplementaryView view: UICollectionReusableView,
                            forElementKind kind: String, at path: NSObject)
    @ObjCMethod("collectionView:shouldSelectItemAtIndexPath:")
    func sendCollectionView(_ collection: UICollectionView, shouldSelectItemAt path: NSObject) -> Bool
    @ObjCMethod("collectionView:shouldDeselectItemAtIndexPath:")
    func sendCollectionView(_ collection: UICollectionView, shouldDeselectItemAt path: NSObject) -> Bool
    @ObjCMethod("collectionView:shouldHighlightItemAtIndexPath:")
    func sendCollectionView(_ collection: UICollectionView, shouldHighlightItemAt path: NSObject) -> Bool
    @ObjCMethod("collectionView:didSelectItemAtIndexPath:")
    func sendCollectionView(_ collection: UICollectionView, didSelectItemAt path: NSObject)
    @ObjCMethod("collectionView:didDeselectItemAtIndexPath:")
    func sendCollectionView(_ collection: UICollectionView, didDeselectItemAt path: NSObject)
    @ObjCMethod("collectionView:layout:sizeForItemAtIndexPath:")
    func sendCollectionView(_ collection: UICollectionView, layout: UICollectionViewLayout, sizeForItemAt path: NSObject) -> CGSize
    @ObjCMethod("collectionView:layout:insetForSectionAtIndex:")
    func sendCollectionView(_ collection: UICollectionView, layout: UICollectionViewLayout, insetForSectionAt section: Int) -> UIEdgeInsets
    @ObjCMethod("collectionView:layout:minimumLineSpacingForSectionAtIndex:")
    func sendCollectionView(_ collection: UICollectionView, layout: UICollectionViewLayout, minimumLineSpacingForSectionAt section: Int) -> CGFloat
    @ObjCMethod("collectionView:layout:minimumInteritemSpacingForSectionAtIndex:")
    func sendCollectionView(_ collection: UICollectionView, layout: UICollectionViewLayout,
                            minimumInteritemSpacingForSectionAt section: Int) -> CGFloat
    @ObjCMethod("collectionView:layout:referenceSizeForHeaderInSection:")
    func sendCollectionView(_ collection: UICollectionView, layout: UICollectionViewLayout, referenceSizeForHeaderInSection section: Int) -> CGSize
    @ObjCMethod("collectionView:layout:referenceSizeForFooterInSection:")
    func sendCollectionView(_ collection: UICollectionView, layout: UICollectionViewLayout, referenceSizeForFooterInSection section: Int) -> CGSize
}

// MARK: - UICollectionViewController

final class CollectionControllerState: ObjectState {
    var layout: UICollectionViewLayout?
    var clearsSelectionOnViewWillAppear = true
    var installsStandardGestureForInteractiveMovement = true
}

@ObjCClass("UICollectionViewController")
open class UICollectionViewController: UIViewController {
    static let collectionControllerStates = StateTable<CollectionControllerState>()
    var collectionController: CollectionControllerState { UICollectionViewController.collectionControllerStates[objcObject] }

    @ObjCMethod("initWithCollectionViewLayout:")
    func initialize(collectionViewLayout layout: UICollectionViewLayout?) -> NSObject {
        // UIViewController's initializer, as a super call: a Swift
        // subclass need not have -initWithNibName:bundle: of its own.
        let controller = initialize(nibName: nil, bundle: nil).unsafeCast(to: UICollectionViewController.self)
        controller.collectionController.layout = layout
        return controller
    }

    @ObjCMethod("initWithCoder:")
    override func initialize(coder: NSObject) -> Self {
        _ = super.initialize(coder: coder)
        let decoded = Coder(coder: coder)
        collectionController.layout = (decoded.object("UICollectionViewLayout") ?? decoded.object("UICollectionLayout"))?
            .as(UICollectionViewLayout.self)
        return self
    }

    @ObjCMethod("dealloc")
    override func dealloc() {
        UICollectionViewController.collectionControllerStates.remove(objcObject)
        super.dealloc()
    }

    /// A collection view the size of the screen, following its superview's
    /// size, with the controller's layout and the controller as its data
    /// source and delegate.
    @ObjCMethod("loadView")
    override func loadView() {
        if loadViewFromNib() {
            if let collection = state.view?.as(UICollectionView.self) {
                if collection.collection.dataSource == nil { collection.setDataSource(self) }
                if collection.delegate() == nil { collection.setDelegate(self) }
            }
            return
        }
        let layout = collectionController.layout
            ?? UICollectionViewFlowLayout.objCClass.object.newInstance().unsafeCast(to: UICollectionViewLayout.self)
        let collection = UICollectionView.objCClass.object.allocated().initializeCollection(frame: Screen.bounds, layout: layout)
            .unsafeCast(to: UICollectionView.self)
        collection.setAutoresizingMask(18)
        collection.setDataSource(self)
        collection.setDelegate(self)
        setView(collection)
    }

    @ObjCMethod("collectionView") func collectionView() -> UICollectionView? { loadedView.as(UICollectionView.self) }
    @ObjCMethod("setCollectionView:") func setCollectionView(_ collection: UICollectionView?) { setView(collection) }

    @ObjCMethod("collectionViewLayout")
    func collectionViewLayout() -> UICollectionViewLayout? {
        state.view?.as(UICollectionView.self)?.collection.layout ?? collectionController.layout
    }

    @ObjCMethod("clearsSelectionOnViewWillAppear") func clearsSelectionOnViewWillAppear() -> Bool {
        collectionController.clearsSelectionOnViewWillAppear
    }
    @ObjCMethod("setClearsSelectionOnViewWillAppear:") func setClearsSelectionOnViewWillAppear(_ clears: Bool) {
        collectionController.clearsSelectionOnViewWillAppear = clears
    }
    @ObjCMethod("installsStandardGestureForInteractiveMovement") func installsStandardGestureForInteractiveMovement() -> Bool {
        collectionController.installsStandardGestureForInteractiveMovement
    }
    @ObjCMethod("setInstallsStandardGestureForInteractiveMovement:")
    func setInstallsStandardGestureForInteractiveMovement(_ installs: Bool) {
        collectionController.installsStandardGestureForInteractiveMovement = installs
    }

    @ObjCMethod("numberOfSectionsInCollectionView:") func numberOfSections(in collection: UICollectionView) -> Int { 1 }
    @ObjCMethod("collectionView:numberOfItemsInSection:")
    func collectionView(_ collection: UICollectionView, numberOfItemsInSection section: Int) -> Int { 0 }

    /// Clears the selection as the controller appears, when it should.
    @ObjCMethod("viewWillAppear:")
    override func viewWillAppear(_ animated: Bool) {
        guard collectionController.clearsSelectionOnViewWillAppear, let collection = state.view?.as(UICollectionView.self) else { return }
        for path in collection.collection.selected.sorted() { collection.deselectItem(at: path.object, animated: animated) }
    }
}
