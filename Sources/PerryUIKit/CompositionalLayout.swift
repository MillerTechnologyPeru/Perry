import CPerryGeometry
import PerryObjCInterop

// UICollectionViewCompositionalLayout and the layout description classes it
// is made of: sections of groups of items, sized relative to their
// containers or absolutely or estimated, which the layout places down the
// collection view (or across it). A list is one such section: items the
// width of the section, as tall as their cells measure.
//
// The classes keep their values in states, as the other UIKit classes do;
// UIEdgeInsets stands for NSDirectionalEdgeInsets (leading is left), which
// has the same layout.

// MARK: - Dimensions

final class LayoutDimensionState: ObjectState {
    /// fractional width 0, fractional height 1, absolute 2, estimated 3.
    var kind = 0
    var value: CGFloat = 0
}

@ObjCClass("NSCollectionLayoutDimension")
open class NSCollectionLayoutDimension: NSObject {
    static let states = StateTable<LayoutDimensionState>()
    var dimension: LayoutDimensionState { NSCollectionLayoutDimension.states[objcObject] }

    static func make(_ cls: ObjCClass, kind: Int, value: CGFloat) -> NSCollectionLayoutDimension {
        let made = cls.object.newInstance().unsafeCast(to: NSCollectionLayoutDimension.self)
        made.dimension.kind = kind
        made.dimension.value = value
        return made
    }

    @ObjCClassMethod("fractionalWidthDimension:")
    static func fractionalWidth(_ cls: ObjCClass, _ fraction: CGFloat) -> NSCollectionLayoutDimension { make(cls, kind: 0, value: fraction) }
    @ObjCClassMethod("fractionalHeightDimension:")
    static func fractionalHeight(_ cls: ObjCClass, _ fraction: CGFloat) -> NSCollectionLayoutDimension { make(cls, kind: 1, value: fraction) }
    @ObjCClassMethod("absoluteDimension:")
    static func absolute(_ cls: ObjCClass, _ points: CGFloat) -> NSCollectionLayoutDimension { make(cls, kind: 2, value: points) }
    @ObjCClassMethod("estimatedDimension:")
    static func estimated(_ cls: ObjCClass, _ points: CGFloat) -> NSCollectionLayoutDimension { make(cls, kind: 3, value: points) }

    @ObjCMethod("isFractionalWidth") func isFractionalWidth() -> Bool { dimension.kind == 0 }
    @ObjCMethod("isFractionalHeight") func isFractionalHeight() -> Bool { dimension.kind == 1 }
    @ObjCMethod("isAbsolute") func isAbsolute() -> Bool { dimension.kind == 2 }
    @ObjCMethod("isEstimated") func isEstimated() -> Bool { dimension.kind == 3 }
    @ObjCMethod("dimension") func dimensionValue() -> CGFloat { dimension.value }

    @ObjCMethod("copyWithZone:")
    func copy(zone: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer { ObjCRuntime.retain(objcObject)! }

    @ObjCMethod("dealloc")
    func dealloc() {
        NSCollectionLayoutDimension.states.remove(objcObject)
        ObjCRuntime.superDealloc(objcObject, definedOn: NSCollectionLayoutDimension.objCClass.pointer)
    }
}

final class LayoutSizeState: ObjectState {
    var width: NSCollectionLayoutDimension?
    var height: NSCollectionLayoutDimension?
}

@ObjCClass("NSCollectionLayoutSize")
open class NSCollectionLayoutSize: NSObject {
    static let states = StateTable<LayoutSizeState>()
    var size: LayoutSizeState { NSCollectionLayoutSize.states[objcObject] }

    @ObjCClassMethod("sizeWithWidthDimension:heightDimension:")
    static func make(_ cls: ObjCClass, width: NSCollectionLayoutDimension?, height: NSCollectionLayoutDimension?) -> NSCollectionLayoutSize {
        let made = cls.object.newInstance().unsafeCast(to: NSCollectionLayoutSize.self)
        made.size.width = width
        made.size.height = height
        return made
    }

    @ObjCMethod("widthDimension") func widthDimension() -> NSCollectionLayoutDimension? { size.width }
    @ObjCMethod("heightDimension") func heightDimension() -> NSCollectionLayoutDimension? { size.height }

    @ObjCMethod("copyWithZone:")
    func copy(zone: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer { ObjCRuntime.retain(objcObject)! }

    @ObjCMethod("dealloc")
    func dealloc() {
        NSCollectionLayoutSize.states.remove(objcObject)
        ObjCRuntime.superDealloc(objcObject, definedOn: NSCollectionLayoutSize.objCClass.pointer)
    }
}

final class LayoutSpacingState: ObjectState {
    var points: CGFloat = 0
    var flexible = false
}

@ObjCClass("NSCollectionLayoutSpacing")
open class NSCollectionLayoutSpacing: NSObject {
    static let states = StateTable<LayoutSpacingState>()
    var spacing: LayoutSpacingState { NSCollectionLayoutSpacing.states[objcObject] }

    static func make(_ cls: ObjCClass, points: CGFloat, flexible: Bool) -> NSCollectionLayoutSpacing {
        let made = cls.object.newInstance().unsafeCast(to: NSCollectionLayoutSpacing.self)
        made.spacing.points = points
        made.spacing.flexible = flexible
        return made
    }

    @ObjCClassMethod("fixedSpacing:")
    static func fixed(_ cls: ObjCClass, _ points: CGFloat) -> NSCollectionLayoutSpacing { make(cls, points: points, flexible: false) }
    @ObjCClassMethod("flexibleSpacing:")
    static func flexible(_ cls: ObjCClass, _ points: CGFloat) -> NSCollectionLayoutSpacing { make(cls, points: points, flexible: true) }

    @ObjCMethod("spacing") func spacingValue() -> CGFloat { spacing.points }
    @ObjCMethod("isFixedSpacing") func isFixedSpacing() -> Bool { !spacing.flexible }
    @ObjCMethod("isFlexibleSpacing") func isFlexibleSpacing() -> Bool { spacing.flexible }

    @ObjCMethod("dealloc")
    func dealloc() {
        NSCollectionLayoutSpacing.states.remove(objcObject)
        ObjCRuntime.superDealloc(objcObject, definedOn: NSCollectionLayoutSpacing.objCClass.pointer)
    }
}

// MARK: - Items, groups and supplementary items

final class LayoutItemState: ObjectState {
    var size: NSCollectionLayoutSize?
    var contentInsets = UIEdgeInsets.zero
    /// Items 0, horizontal groups 1, vertical groups 2.
    var kind = 0
    var subitems: [NSCollectionLayoutItem] = []
    /// A group's repeated subitem's count, when it has one.
    var repeats = 1
    var interItemSpacing: NSCollectionLayoutSpacing?
    var supplementaryItems: [NSObject] = []
    // A boundary supplementary item's.
    var elementKind = ""
    var alignment = 1
    var offset = CGPoint.zero
    var extendsBoundary = true
    var pinToVisibleBounds = false
    var zIndex = 0
}

@ObjCClass("NSCollectionLayoutItem")
open class NSCollectionLayoutItem: NSObject {
    static let itemStates = StateTable<LayoutItemState>()
    var item: LayoutItemState { NSCollectionLayoutItem.itemStates[objcObject] }

    static func make(_ cls: ObjCClass, size: NSCollectionLayoutSize?) -> NSCollectionLayoutItem {
        let made = cls.object.newInstance().unsafeCast(to: NSCollectionLayoutItem.self)
        made.item.size = size
        return made
    }

    @ObjCClassMethod("itemWithLayoutSize:")
    static func item(_ cls: ObjCClass, size: NSCollectionLayoutSize?) -> NSCollectionLayoutItem { make(cls, size: size) }

    @ObjCClassMethod("itemWithLayoutSize:supplementaryItems:")
    static func item(_ cls: ObjCClass, size: NSCollectionLayoutSize?, supplementaryItems: NSArray?) -> NSCollectionLayoutItem {
        let made = make(cls, size: size)
        made.item.supplementaryItems = supplementaryItems?.elements ?? []
        return made
    }

    @ObjCMethod("layoutSize") func layoutSize() -> NSCollectionLayoutSize? { item.size }
    @ObjCMethod("contentInsets") func contentInsets() -> UIEdgeInsets { item.contentInsets }
    @ObjCMethod("setContentInsets:") func setContentInsets(_ insets: UIEdgeInsets) { item.contentInsets = insets }
    @ObjCMethod("edgeSpacing") func edgeSpacing() -> NSObject? { nil }
    @ObjCMethod("setEdgeSpacing:") func setEdgeSpacing(_ spacing: NSObject?) {}
    @ObjCMethod("supplementaryItems") func supplementaryItems() -> NSObject { NSMutableArray.of(item.supplementaryItems) }

    @ObjCMethod("copyWithZone:")
    func copy(zone: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer { ObjCRuntime.retain(objcObject)! }

    @ObjCMethod("dealloc")
    func dealloc() {
        NSCollectionLayoutItem.itemStates.remove(objcObject)
        ObjCRuntime.superDealloc(objcObject, definedOn: NSCollectionLayoutItem.objCClass.pointer)
    }
}

@ObjCClass("NSCollectionLayoutGroup")
open class NSCollectionLayoutGroup: NSCollectionLayoutItem {
    static func group(_ cls: ObjCClass, kind: Int, size: NSCollectionLayoutSize?, subitems: [NSCollectionLayoutItem],
                      repeats: Int = 1) -> NSCollectionLayoutGroup {
        let made = cls.object.newInstance().unsafeCast(to: NSCollectionLayoutGroup.self)
        made.item.size = size
        made.item.kind = kind
        made.item.subitems = subitems
        made.item.repeats = max(repeats, 1)
        return made
    }

    @ObjCClassMethod("horizontalGroupWithLayoutSize:subitem:count:")
    static func horizontal(_ cls: ObjCClass, size: NSCollectionLayoutSize?, subitem: NSCollectionLayoutItem?, count: Int) -> NSCollectionLayoutGroup {
        group(cls, kind: 1, size: size, subitems: subitem.map { [$0] } ?? [], repeats: count)
    }
    @ObjCClassMethod("horizontalGroupWithLayoutSize:repeatingSubitem:count:")
    static func horizontal(_ cls: ObjCClass, size: NSCollectionLayoutSize?, repeating subitem: NSCollectionLayoutItem?, count: Int) -> NSCollectionLayoutGroup {
        group(cls, kind: 1, size: size, subitems: subitem.map { [$0] } ?? [], repeats: count)
    }
    @ObjCClassMethod("horizontalGroupWithLayoutSize:subitems:")
    static func horizontal(_ cls: ObjCClass, size: NSCollectionLayoutSize?, subitems: NSArray?) -> NSCollectionLayoutGroup {
        group(cls, kind: 1, size: size, subitems: subitems?.elements.compactMap { $0.as(NSCollectionLayoutItem.self) } ?? [])
    }
    @ObjCClassMethod("verticalGroupWithLayoutSize:subitem:count:")
    static func vertical(_ cls: ObjCClass, size: NSCollectionLayoutSize?, subitem: NSCollectionLayoutItem?, count: Int) -> NSCollectionLayoutGroup {
        group(cls, kind: 2, size: size, subitems: subitem.map { [$0] } ?? [], repeats: count)
    }
    @ObjCClassMethod("verticalGroupWithLayoutSize:repeatingSubitem:count:")
    static func vertical(_ cls: ObjCClass, size: NSCollectionLayoutSize?, repeating subitem: NSCollectionLayoutItem?, count: Int) -> NSCollectionLayoutGroup {
        group(cls, kind: 2, size: size, subitems: subitem.map { [$0] } ?? [], repeats: count)
    }
    @ObjCClassMethod("verticalGroupWithLayoutSize:subitems:")
    static func vertical(_ cls: ObjCClass, size: NSCollectionLayoutSize?, subitems: NSArray?) -> NSCollectionLayoutGroup {
        group(cls, kind: 2, size: size, subitems: subitems?.elements.compactMap { $0.as(NSCollectionLayoutItem.self) } ?? [])
    }

    @ObjCMethod("subitems") func subitems() -> NSObject { NSMutableArray.of(item.subitems) }
    @ObjCMethod("interItemSpacing") func interItemSpacing() -> NSCollectionLayoutSpacing? { item.interItemSpacing }
    @ObjCMethod("setInterItemSpacing:") func setInterItemSpacing(_ spacing: NSCollectionLayoutSpacing?) { item.interItemSpacing = spacing }
}

@ObjCClass("NSCollectionLayoutSupplementaryItem")
open class NSCollectionLayoutSupplementaryItem: NSCollectionLayoutItem {
    @ObjCMethod("elementKind") func elementKind() -> String { item.elementKind }
    @ObjCMethod("zIndex") func zIndex() -> Int { item.zIndex }
    @ObjCMethod("setZIndex:") func setZIndex(_ index: Int) { item.zIndex = index }
}

@ObjCClass("NSCollectionLayoutBoundarySupplementaryItem")
open class NSCollectionLayoutBoundarySupplementaryItem: NSCollectionLayoutSupplementaryItem {
    static func boundary(_ cls: ObjCClass, size: NSCollectionLayoutSize?, kind: String, alignment: Int,
                         offset: CGPoint) -> NSCollectionLayoutBoundarySupplementaryItem {
        let made = cls.object.newInstance().unsafeCast(to: NSCollectionLayoutBoundarySupplementaryItem.self)
        made.item.size = size
        made.item.elementKind = kind
        made.item.alignment = alignment
        made.item.offset = offset
        return made
    }

    @ObjCClassMethod("boundarySupplementaryItemWithLayoutSize:elementKind:alignment:")
    static func boundary(_ cls: ObjCClass, size: NSCollectionLayoutSize?, elementKind: String, alignment: Int)
        -> NSCollectionLayoutBoundarySupplementaryItem { boundary(cls, size: size, kind: elementKind, alignment: alignment, offset: .zero) }

    @ObjCClassMethod("boundarySupplementaryItemWithLayoutSize:elementKind:alignment:absoluteOffset:")
    static func boundary(_ cls: ObjCClass, size: NSCollectionLayoutSize?, elementKind: String, alignment: Int, absoluteOffset: CGPoint)
        -> NSCollectionLayoutBoundarySupplementaryItem { boundary(cls, size: size, kind: elementKind, alignment: alignment, offset: absoluteOffset) }

    @ObjCMethod("alignment") func alignment() -> Int { item.alignment }
    @ObjCMethod("offset") func offset() -> CGPoint { item.offset }
    @ObjCMethod("extendsBoundary") func extendsBoundary() -> Bool { item.extendsBoundary }
    @ObjCMethod("setExtendsBoundary:") func setExtendsBoundary(_ extends: Bool) { item.extendsBoundary = extends }
    @ObjCMethod("pinToVisibleBounds") func pinToVisibleBounds() -> Bool { item.pinToVisibleBounds }
    @ObjCMethod("setPinToVisibleBounds:") func setPinToVisibleBounds(_ pin: Bool) { item.pinToVisibleBounds = pin }
}

// MARK: - Sections

final class LayoutSectionState: ObjectState {
    var group: NSCollectionLayoutGroup?
    var contentInsets = UIEdgeInsets.zero
    var interGroupSpacing: CGFloat = 0
    var boundarySupplementaryItems: [NSCollectionLayoutBoundarySupplementaryItem] = []
    var supplementariesFollowContentInsets = true
    var orthogonalScrollingBehavior = 0
    var contentInsetsReference = 0
}

@ObjCClass("NSCollectionLayoutSection")
open class NSCollectionLayoutSection: NSObject {
    static let sectionStates = StateTable<LayoutSectionState>()
    var section: LayoutSectionState { NSCollectionLayoutSection.sectionStates[objcObject] }

    @ObjCClassMethod("sectionWithGroup:")
    static func make(_ cls: ObjCClass, group: NSCollectionLayoutGroup?) -> NSCollectionLayoutSection {
        let made = cls.object.newInstance().unsafeCast(to: NSCollectionLayoutSection.self)
        made.section.group = group
        return made
    }

    @ObjCMethod("contentInsets") func contentInsets() -> UIEdgeInsets { section.contentInsets }
    @ObjCMethod("setContentInsets:") func setContentInsets(_ insets: UIEdgeInsets) { section.contentInsets = insets }
    @ObjCMethod("interGroupSpacing") func interGroupSpacing() -> CGFloat { section.interGroupSpacing }
    @ObjCMethod("setInterGroupSpacing:") func setInterGroupSpacing(_ spacing: CGFloat) { section.interGroupSpacing = spacing }
    @ObjCMethod("boundarySupplementaryItems") func boundarySupplementaryItems() -> NSObject {
        NSMutableArray.of(section.boundarySupplementaryItems)
    }
    @ObjCMethod("setBoundarySupplementaryItems:") func setBoundarySupplementaryItems(_ items: NSArray?) {
        section.boundarySupplementaryItems = items?.elements.compactMap { $0.as(NSCollectionLayoutBoundarySupplementaryItem.self) } ?? []
    }
    @ObjCMethod("supplementariesFollowContentInsets") func supplementariesFollowContentInsets() -> Bool {
        section.supplementariesFollowContentInsets
    }
    @ObjCMethod("setSupplementariesFollowContentInsets:") func setSupplementariesFollowContentInsets(_ follow: Bool) {
        section.supplementariesFollowContentInsets = follow
    }
    @ObjCMethod("orthogonalScrollingBehavior") func orthogonalScrollingBehavior() -> Int { section.orthogonalScrollingBehavior }
    @ObjCMethod("setOrthogonalScrollingBehavior:") func setOrthogonalScrollingBehavior(_ behavior: Int) {
        section.orthogonalScrollingBehavior = behavior
    }
    @ObjCMethod("contentInsetsReference") func contentInsetsReference() -> Int { section.contentInsetsReference }
    @ObjCMethod("setContentInsetsReference:") func setContentInsetsReference(_ reference: Int) { section.contentInsetsReference = reference }
    @ObjCMethod("visibleItemsInvalidationHandler") func visibleItemsInvalidationHandler() -> NSObject? { nil }
    @ObjCMethod("setVisibleItemsInvalidationHandler:") func setVisibleItemsInvalidationHandler(_ handler: ObjCBlock?) {}
    @ObjCMethod("decorationItems") func decorationItems() -> NSObject { NSMutableArray.empty() }
    @ObjCMethod("setDecorationItems:") func setDecorationItems(_ items: NSArray?) {}

    @ObjCMethod("dealloc")
    func dealloc() {
        NSCollectionLayoutSection.sectionStates.remove(objcObject)
        ObjCRuntime.superDealloc(objcObject, definedOn: NSCollectionLayoutSection.objCClass.pointer)
    }
}

// MARK: - The environment a section provider is given

@ObjCClass("_PerryLayoutContainer")
open class PerryLayoutContainer: NSObject {
    static let states = StateTable<ContainerState>()
    final class ContainerState: ObjectState {
        var size = CGSize.zero
        var insets = UIEdgeInsets.zero
    }
    var container: ContainerState { PerryLayoutContainer.states[objcObject] }

    @ObjCMethod("contentSize") func contentSize() -> CGSize { container.size }
    @ObjCMethod("effectiveContentSize") func effectiveContentSize() -> CGSize {
        CGSize(width: container.size.width - container.insets.left - container.insets.right,
               height: container.size.height - container.insets.top - container.insets.bottom)
    }
    @ObjCMethod("contentInsets") func contentInsets() -> UIEdgeInsets { container.insets }
    @ObjCMethod("effectiveContentInsets") func effectiveContentInsets() -> UIEdgeInsets { container.insets }

    @ObjCMethod("dealloc")
    func dealloc() {
        PerryLayoutContainer.states.remove(objcObject)
        ObjCRuntime.superDealloc(objcObject, definedOn: PerryLayoutContainer.objCClass.pointer)
    }
}

@ObjCClass("_PerryLayoutEnvironment")
open class PerryLayoutEnvironment: NSObject {
    static let states = StateTable<EnvironmentState>()
    final class EnvironmentState: ObjectState {
        var container: PerryLayoutContainer?
        var traits: NSObject?
    }
    var environment: EnvironmentState { PerryLayoutEnvironment.states[objcObject] }

    @ObjCMethod("container") func container() -> PerryLayoutContainer? { environment.container }
    @ObjCMethod("traitCollection") func traitCollection() -> NSObject? { environment.traits }

    @ObjCMethod("dealloc")
    func dealloc() {
        PerryLayoutEnvironment.states.remove(objcObject)
        ObjCRuntime.superDealloc(objcObject, definedOn: PerryLayoutEnvironment.objCClass.pointer)
    }
}

// MARK: - The layout

final class CompositionalConfigurationState: ObjectState {
    /// UICollectionViewScrollDirection: vertical 0, horizontal 1.
    var scrollDirection = 0
    var interSectionSpacing: CGFloat = 0
    var boundarySupplementaryItems: [NSCollectionLayoutBoundarySupplementaryItem] = []
    var contentInsetsReference = 0
}

@ObjCClass("UICollectionViewCompositionalLayoutConfiguration")
open class UICollectionViewCompositionalLayoutConfiguration: NSObject {
    static let states = StateTable<CompositionalConfigurationState>()
    var configuration: CompositionalConfigurationState { UICollectionViewCompositionalLayoutConfiguration.states[objcObject] }

    @ObjCMethod("scrollDirection") func scrollDirection() -> Int { configuration.scrollDirection }
    @ObjCMethod("setScrollDirection:") func setScrollDirection(_ direction: Int) { configuration.scrollDirection = direction }
    @ObjCMethod("interSectionSpacing") func interSectionSpacing() -> CGFloat { configuration.interSectionSpacing }
    @ObjCMethod("setInterSectionSpacing:") func setInterSectionSpacing(_ spacing: CGFloat) { configuration.interSectionSpacing = spacing }
    @ObjCMethod("contentInsetsReference") func contentInsetsReference() -> Int { configuration.contentInsetsReference }
    @ObjCMethod("setContentInsetsReference:") func setContentInsetsReference(_ reference: Int) { configuration.contentInsetsReference = reference }
    @ObjCMethod("boundarySupplementaryItems") func boundarySupplementaryItems() -> NSObject {
        NSMutableArray.of(configuration.boundarySupplementaryItems)
    }
    @ObjCMethod("setBoundarySupplementaryItems:") func setBoundarySupplementaryItems(_ items: NSArray?) {
        configuration.boundarySupplementaryItems = items?.elements.compactMap { $0.as(NSCollectionLayoutBoundarySupplementaryItem.self) } ?? []
    }

    @ObjCMethod("copyWithZone:")
    func copy(zone: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer {
        let copy = UICollectionViewCompositionalLayoutConfiguration.objCClass.object.newInstance()
            .unsafeCast(to: UICollectionViewCompositionalLayoutConfiguration.self)
        copy.configuration.scrollDirection = configuration.scrollDirection
        copy.configuration.interSectionSpacing = configuration.interSectionSpacing
        copy.configuration.boundarySupplementaryItems = configuration.boundarySupplementaryItems
        copy.configuration.contentInsetsReference = configuration.contentInsetsReference
        return ObjCRuntime.retain(copy.objcObject)!
    }

    @ObjCMethod("dealloc")
    func dealloc() {
        UICollectionViewCompositionalLayoutConfiguration.states.remove(objcObject)
        ObjCRuntime.superDealloc(objcObject, definedOn: UICollectionViewCompositionalLayoutConfiguration.objCClass.pointer)
    }
}

/// A section of the layout as placed.
struct CompositionalSection {
    var header: CGRect?
    var footer: CGRect?
    var items: [CGRect]
    var frame: CGRect
    var pinnedHeader = false
    var headerKind = CollectionElementKind.header
    var footerKind = CollectionElementKind.footer
    var headerZ = 0
}

final class CompositionalLayoutState: ObjectState {
    var section: NSCollectionLayoutSection?
    var provider: ObjCBlock?
    var configuration: UICollectionViewCompositionalLayoutConfiguration?
    var sections: [CompositionalSection] = []
    var contentSize = CGSize.zero
    var preparedWidth: CGFloat = -1
    /// Self-sized items' and supplementary views' heights, by place.
    var measured: [RowPath: CGFloat] = [:]
    var measuredSupplementary: [SupplementaryKey: CGFloat] = [:]
    /// Each item's estimated height dimension, which cells are measured for.
    var estimatedItems: Set<RowPath> = []
    var estimatedSupplementary: Set<SupplementaryKey> = []
}

@ObjCClass("UICollectionViewCompositionalLayout")
open class UICollectionViewCompositionalLayout: UICollectionViewLayout {
    static let compositionalStates = StateTable<CompositionalLayoutState>()
    var compositional: CompositionalLayoutState { UICollectionViewCompositionalLayout.compositionalStates[objcObject] }

    @ObjCMethod("initWithSection:")
    func initialize(section: NSCollectionLayoutSection?) -> NSObject {
        compositional.section = section
        return self
    }

    @ObjCMethod("initWithSection:configuration:")
    func initialize(section: NSCollectionLayoutSection?, configuration: UICollectionViewCompositionalLayoutConfiguration?) -> NSObject {
        compositional.section = section
        compositional.configuration = configuration
        return self
    }

    @ObjCMethod("initWithSectionProvider:")
    func initialize(sectionProvider: ObjCBlock?) -> NSObject {
        compositional.provider = sectionProvider
        return self
    }

    @ObjCMethod("initWithSectionProvider:configuration:")
    func initialize(sectionProvider: ObjCBlock?, configuration: UICollectionViewCompositionalLayoutConfiguration?) -> NSObject {
        compositional.provider = sectionProvider
        compositional.configuration = configuration
        return self
    }

    @ObjCMethod("configuration")
    func configuration() -> UICollectionViewCompositionalLayoutConfiguration {
        if let configuration = compositional.configuration { return configuration }
        let made = UICollectionViewCompositionalLayoutConfiguration.objCClass.object.newInstance()
            .unsafeCast(to: UICollectionViewCompositionalLayoutConfiguration.self)
        compositional.configuration = made
        return made
    }

    @ObjCMethod("setConfiguration:")
    func setConfiguration(_ configuration: UICollectionViewCompositionalLayoutConfiguration?) {
        compositional.configuration = configuration
        collection?.layoutInvalidated()
    }

    @ObjCMethod("dealloc")
    override func dealloc() {
        UICollectionViewCompositionalLayout.compositionalStates.remove(objcObject)
        super.dealloc()
    }

    // MARK: Sizes

    /// A dimension in points, and whether it is only an estimate: fractions
    /// are of the container the dimension is along (width or height), or of
    /// the other side for an aspect.
    private func resolve(_ dimension: NSCollectionLayoutDimension?, width: CGFloat, height: CGFloat) -> (points: CGFloat, estimated: Bool) {
        guard let dimension else { return (0, false) }
        let state = dimension.dimension
        switch state.kind {
        case 0: return (state.value * width, false)
        case 1: return (state.value * height, false)
        case 2: return (state.value, false)
        default: return (state.value, true)
        }
    }

    /// Places a section's items, header and footer from `origin`; the
    /// section's frame and the height it took.
    private func layOut(section: NSCollectionLayoutSection, index: Int, collection: UICollectionView, width: CGFloat, containerHeight: CGFloat,
                        origin: CGFloat) -> CompositionalSection {
        let values = section.section
        let insets = values.contentInsets
        let contentWidth = width - insets.left - insets.right
        var along = origin + insets.top
        var header: CGRect?, footer: CGRect?
        var result = CompositionalSection(items: [], frame: .zero)

        func boundary(_ item: NSCollectionLayoutBoundarySupplementaryItem, at y: CGFloat) -> (CGRect, kind: String) {
            let state = item.item
            let space = values.supplementariesFollowContentInsets ? contentWidth : width
            let x = values.supplementariesFollowContentInsets ? insets.left : 0
            let key = SupplementaryKey(kind: state.elementKind, path: RowPath(section: index, row: 0))
            let (w, _) = resolve(state.size?.size.width, width: space, height: containerHeight)
            var (h, estimated) = resolve(state.size?.size.height, width: space, height: containerHeight)
            if estimated {
                self.compositional.estimatedSupplementary.insert(key)
                if let measured = self.compositional.measuredSupplementary[key] { h = measured }
            }
            return (CGRect(x: x + state.offset.x, y: y + state.offset.y, width: w > 0 ? w : space, height: h), state.elementKind)
        }

        for item in values.boundarySupplementaryItems {
            let alignment = item.item.alignment
            if alignment & 1 != 0, header == nil {
                let (rect, kind) = boundary(item, at: along)
                header = rect
                result.headerKind = kind
                result.pinnedHeader = item.item.pinToVisibleBounds
                result.headerZ = item.item.zIndex
                along += rect.height
            }
        }

        // Items, group after group.
        let count = collection.numberOfItems(inSection: index)
        var frames = [CGRect](repeating: .zero, count: count)
        var next = 0
        if let group = values.group {
            var guardCount = 0
            while next < count, guardCount < count + 1 {
                guardCount += 1
                let before = next
                let size = place(group, width: contentWidth, containerHeight: containerHeight, origin: CGPoint(x: insets.left, y: along),
                                 section: index, next: &next, count: count, frames: &frames)
                if next == before { break }
                along += size.height + values.interGroupSpacing
            }
            if next > 0 { along -= values.interGroupSpacing }
        }

        for item in values.boundarySupplementaryItems where item.item.alignment & 4 != 0 && footer == nil {
            let (rect, kind) = boundary(item, at: along)
            footer = rect
            result.footerKind = kind
            along += rect.height
        }
        along += insets.bottom
        result.header = header
        result.footer = footer
        result.items = frames
        result.frame = CGRect(x: 0, y: origin, width: width, height: along - origin)
        return result
    }

    /// Places a node of a group, taking items off `next` until it is full;
    /// the size it took.
    private func place(_ node: NSCollectionLayoutItem, width: CGFloat, containerHeight: CGFloat, origin: CGPoint, section: Int,
                       next: inout Int, count: Int, frames: inout [CGRect]) -> CGSize {
        let state = node.item
        let size = state.size?.size
        let (w, _) = resolve(size?.width, width: width, height: containerHeight)
        var (h, estimated) = resolve(size?.height, width: width, height: containerHeight)
        let insets = state.contentInsets
        if state.kind == 0 {
            guard next < count else { return .zero }
            let path = RowPath(section: section, row: next)
            if estimated {
                compositional.estimatedItems.insert(path)
                h = compositional.measured[path] ?? h
            }
            let slot = CGSize(width: w > 0 ? w : width, height: h + (estimated ? insets.top + insets.bottom : 0))
            frames[next] = CGRect(x: origin.x + insets.left, y: origin.y + insets.top,
                                  width: slot.width - insets.left - insets.right, height: slot.height - insets.top - insets.bottom)
            next += 1
            return slot
        }
        // A group: its subitems, repeated, in a row or a column.
        let horizontal = state.kind == 1
        var children: [NSCollectionLayoutItem] = []
        for _ in 0..<state.repeats { children += state.subitems }
        let spacing = state.interItemSpacing?.spacing.points ?? 0
        let groupWidth = w > 0 ? w : width
        let childHeight = estimated ? containerHeight : h
        var cursor: CGFloat = 0, tallest: CGFloat = 0, used: CGFloat = 0
        var placedAny = false
        for child in children {
            guard next < count else { break }
            let at = horizontal ? CGPoint(x: origin.x + insets.left + cursor, y: origin.y + insets.top)
                                : CGPoint(x: origin.x + insets.left, y: origin.y + insets.top + cursor)
            let took = place(child, width: groupWidth - insets.left - insets.right, containerHeight: childHeight,
                             origin: at, section: section, next: &next, count: count, frames: &frames)
            placedAny = true
            if horizontal {
                cursor += took.width + spacing
                tallest = max(tallest, took.height)
            } else {
                cursor += took.height + spacing
                tallest = max(tallest, took.width)
                used = cursor - spacing
            }
        }
        guard placedAny else { return .zero }
        let height = horizontal ? (estimated ? tallest : h) : (estimated ? used : max(h, 0))
        return CGSize(width: groupWidth, height: height + insets.top + insets.bottom)
    }

    @ObjCMethod("prepareLayout")
    override func prepareLayout() {
        let state = compositional
        state.estimatedItems = []
        state.estimatedSupplementary = []
        guard let collection else {
            state.sections = []
            state.contentSize = .zero
            return
        }
        let bounds = collection.state.bounds
        let inset = collection.adjustedContentInset()
        let width = bounds.width - inset.left - inset.right
        state.preparedWidth = bounds.width

        let environment = PerryLayoutEnvironment.objCClass.object.newInstance().unsafeCast(to: PerryLayoutEnvironment.self)
        let container = PerryLayoutContainer.objCClass.object.newInstance().unsafeCast(to: PerryLayoutContainer.self)
        container.container.size = bounds.size
        container.container.insets = UIEdgeInsets(top: inset.top, left: 0, bottom: inset.bottom, right: 0)
        environment.environment.container = container

        let spacing = state.configuration?.configuration.interSectionSpacing ?? 0
        var sections: [CompositionalSection] = []
        var along: CGFloat = 0
        for index in 0..<collection.numberOfSections() {
            let section: NSCollectionLayoutSection?
            if let provider = state.provider {
                typealias Invoke = @convention(c) (UnsafeMutableRawPointer, Int, UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer?
                let made = provider.function(as: Invoke.self)(provider.object, index, environment.objcObject)
                section = made.flatMap { NSObject($0).as(NSCollectionLayoutSection.self) }
            } else {
                section = state.section
            }
            guard let section else {
                sections.append(CompositionalSection(items: [], frame: CGRect(x: 0, y: along, width: width, height: 0)))
                continue
            }
            let placed = layOut(section: section, index: index, collection: collection, width: width, containerHeight: bounds.height, origin: along)
            sections.append(placed)
            along = placed.frame.maxY + spacing
        }
        if !sections.isEmpty { along -= spacing }
        state.sections = sections
        state.contentSize = CGSize(width: width, height: max(along, 0))
    }

    @ObjCMethod("collectionViewContentSize")
    override func collectionViewContentSize() -> CGSize { compositional.contentSize }

    // MARK: Attributes

    private var attributesClass: ObjCClass { ObjCClass(ObjCRuntime.objectClass(objcObject)!).object.sendLayoutAttributesClass() }

    private func itemAttributes(_ path: RowPath) -> UICollectionViewLayoutAttributes? {
        let sections = compositional.sections
        guard sections.indices.contains(path.section), sections[path.section].items.indices.contains(path.row) else { return nil }
        let attributes = UICollectionViewLayoutAttributes.make(attributesClass, path: path.object, category: 0, kind: nil)
        attributes.attributes.frame = sections[path.section].items[path.row]
        return attributes
    }

    private func supplementaryAttributes(kind: String, section: Int) -> UICollectionViewLayoutAttributes? {
        let sections = compositional.sections
        guard sections.indices.contains(section) else { return nil }
        let placed = sections[section]
        let isHeader = kind == placed.headerKind && placed.header != nil
        guard var frame = isHeader ? placed.header : (kind == placed.footerKind ? placed.footer : nil), frame.height > 0 else { return nil }
        let attributes = UICollectionViewLayoutAttributes.make(attributesClass, path: IndexPaths.make(section: section, row: 0),
                                                               category: 1, kind: kind)
        if isHeader, placed.pinnedHeader, let collection {
            let visible = collection.state.bounds, inset = collection.adjustedContentInset()
            frame.origin.y = min(max(frame.minY, visible.minY + inset.top), placed.frame.maxY - frame.height)
            attributes.attributes.zIndex = 1024
        } else {
            attributes.attributes.zIndex = 10
        }
        attributes.attributes.frame = frame
        return attributes
    }

    @ObjCMethod("layoutAttributesForElementsInRect:")
    override func layoutAttributesForElements(in rect: CGRect) -> NSObject? {
        var found: [UICollectionViewLayoutAttributes] = []
        let sections = compositional.sections
        // The first section that ends below the rectangle's top: sections
        // are in order.
        var low = 0, high = sections.count
        while low < high {
            let middle = (low + high) / 2
            if sections[middle].frame.maxY < rect.minY { low = middle + 1 } else { high = middle }
        }
        var index = low
        while index < sections.count, sections[index].frame.minY <= rect.maxY || (sections[index].pinnedHeader && sections[index].frame.minY <= rect.maxY) {
            let placed = sections[index]
            for kind in [placed.headerKind, placed.footerKind] {
                if let attributes = supplementaryAttributes(kind: kind, section: index), attributes.attributes.frame.intersects(rect) {
                    found.append(attributes)
                }
            }
            for (item, frame) in placed.items.enumerated() where frame.intersects(rect) {
                if let attributes = itemAttributes(RowPath(section: index, row: item)) { found.append(attributes) }
            }
            index += 1
        }
        return NSMutableArray.of(found)
    }

    @ObjCMethod("layoutAttributesForItemAtIndexPath:")
    override func layoutAttributesForItem(at path: NSObject) -> NSObject? { itemAttributes(RowPath(path)) }

    @ObjCMethod("layoutAttributesForSupplementaryViewOfKind:atIndexPath:")
    override func layoutAttributesForSupplementaryView(kind: String, at path: NSObject) -> NSObject? {
        supplementaryAttributes(kind: kind, section: path.sendSection())
    }

    @ObjCMethod("shouldInvalidateLayoutForBoundsChange:")
    override func shouldInvalidateLayout(forBoundsChange bounds: CGRect) -> Bool {
        // A pinned header's frame follows the bounds when its attributes are
        // asked for, so only a change of width lays the sections out again.
        bounds.width != compositional.preparedWidth
    }

    // MARK: Self-sizing

    /// Whether the layout sizes the item by its cell.
    func isEstimated(_ path: RowPath) -> Bool { compositional.estimatedItems.contains(path) }
    func isEstimated(_ key: SupplementaryKey) -> Bool { compositional.estimatedSupplementary.contains(key) }

    /// Keeps a cell's measured height; whether it changed.
    func record(height: CGFloat, for path: RowPath) -> Bool {
        guard height > 0, compositional.measured[path] != height else { return false }
        compositional.measured[path] = height
        return true
    }

    func record(height: CGFloat, for key: SupplementaryKey) -> Bool {
        guard height > 0, compositional.measuredSupplementary[key] != height else { return false }
        compositional.measuredSupplementary[key] = height
        return true
    }
}
