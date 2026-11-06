import CPerryGeometry
import PerryObjCInterop

// Auto Layout, as far as Interface Builder's layouts use it: constraints
// between a view and its superview, its siblings or a constant, each
// attribute = multiplier × other attribute + constant. When a view lays
// out, each subview that doesn't translate its autoresizing mask gets its
// frame from the equalities that place it, with its intrinsic size (or
// its current one) where they leave a size open; inequalities then bound
// its width and height. Attributes are measured with y downwards, as
// Auto Layout's top and bottom are, whether or not the superview is
// flipped. NSLayoutAttribute: left 1, right 2, top 3, bottom 4, leading
// 5, trailing 6, width 7, height 8, center x 9, center y 10, last
// baseline 11, first baseline 12, and the margins 13 to 20.

@ObjCClass("NSLayoutConstraint")
open class NSLayoutConstraint: NSObject {
    var firstItem: NSObject?
    var firstAttribute = 0
    /// NSLayoutRelation: less than or equal -1, equal 0, greater 1.
    var relation = 0
    var secondItem: NSObject?
    var secondAttribute = 0
    var multiplier: CGFloat = 1
    var constant: CGFloat = 0
    var priority: Float = 1000
    var active = false
    var identifier: String?
    var shouldBeArchived = false

    @ObjCMethod("init")
    public required override init() { super.init() }

    init(item: NSObject?, attribute: Int, relation: Int, to other: NSObject?, attribute otherAttribute: Int, multiplier: CGFloat, constant: CGFloat) {
        super.init()
        (firstItem, firstAttribute, self.relation) = (item, attribute, relation)
        (secondItem, secondAttribute, self.multiplier, self.constant) = (other, otherAttribute, multiplier, constant)
    }

    @ObjCMethod("initWithCoder:")
    public required init(coder: NSObject?) {
        super.init()
        guard let coder else { return }
        let decoded = Coder(coder: coder)
        firstItem = decoded.object("NSFirstItem")
        firstAttribute = decoded.has("NSFirstAttributeV2") ? decoded.integer("NSFirstAttributeV2") : decoded.integer("NSFirstAttribute")
        secondItem = decoded.object("NSSecondItem")
        secondAttribute = decoded.has("NSSecondAttributeV2") ? decoded.integer("NSSecondAttributeV2") : decoded.integer("NSSecondAttribute")
        relation = decoded.integer("NSRelation")
        if decoded.has("NSMultiplier") { multiplier = decoded.double("NSMultiplier") }
        constant = decoded.has("NSConstantV2") ? decoded.double("NSConstantV2") : decoded.double("NSConstant")
        if decoded.has("NSPriority") { priority = Float(decoded.integer("NSPriority")) }
        identifier = decoded.string("NSLayoutIdentifier")
        shouldBeArchived = decoded.bool("NSShouldBeArchived")
        active = true
    }

    @ObjCClassMethod("constraintWithItem:attribute:relatedBy:toItem:attribute:multiplier:constant:")
    static func constraint(item: NSObject?, attribute: Int, relatedBy relation: Int, toItem other: NSObject?, attribute otherAttribute: Int,
                           multiplier: CGFloat, constant: CGFloat) -> NSLayoutConstraint {
        NSLayoutConstraint(item: item, attribute: attribute, relation: relation, to: other, attribute: otherAttribute, multiplier: multiplier,
                           constant: constant)
    }

    @ObjCClassMethod("constraintsWithVisualFormat:options:metrics:views:")
    static func constraints(visualFormat format: String?, options: UInt, metrics: NSObject?, views: NSObject?) -> NSObject {
        Trace.log("layout: visual format \(format ?? "") isn't laid out")
        return NSMutableArray.empty()
    }

    @ObjCClassMethod("activateConstraints:")
    static func activate(_ constraints: NSObject?) {
        for item in constraints?.as(NSArray.self)?.elements ?? [] { item.as(NSLayoutConstraint.self)?.setActive(true) }
    }

    @ObjCClassMethod("deactivateConstraints:")
    static func deactivate(_ constraints: NSObject?) {
        for item in constraints?.as(NSArray.self)?.elements ?? [] { item.as(NSLayoutConstraint.self)?.setActive(false) }
    }

    /// The view that holds the constraint: the nearest common ancestor of
    /// its items.
    var holder: NSView? {
        let first = firstItem?.as(NSView.self), second = secondItem?.as(NSView.self)
        guard let first else { return second }
        guard let second else { return first }
        return first.ancestorShared(with: second)
    }

    @ObjCMethod("isActive") func isActive() -> Bool { active }
    @ObjCMethod("setActive:")
    func setActive(_ value: Bool) {
        guard value != active else { return }
        active = value
        guard let holder else { return }
        if value { holder.addConstraint(self) } else { holder.removeConstraint(self) }
    }

    @ObjCMethod("firstItem") func constraintFirstItem() -> NSObject? { firstItem }
    @ObjCMethod("secondItem") func constraintSecondItem() -> NSObject? { secondItem }
    @ObjCMethod("firstAttribute") func constraintFirstAttribute() -> Int { firstAttribute }
    @ObjCMethod("secondAttribute") func constraintSecondAttribute() -> Int { secondAttribute }
    @ObjCMethod("relation") func constraintRelation() -> Int { relation }
    @ObjCMethod("multiplier") func constraintMultiplier() -> CGFloat { multiplier }
    @ObjCMethod("constant") func constraintConstant() -> CGFloat { constant }
    @ObjCMethod("setConstant:")
    func setConstant(_ value: CGFloat) {
        constant = value
        holder?.setNeedsLayout(true)
        (firstItem?.as(NSView.self))?.superview?.setNeedsLayout(true)
    }
    @ObjCMethod("priority") func constraintPriority() -> Float { priority }
    @ObjCMethod("setPriority:") func setPriority(_ value: Float) { priority = value }
    @ObjCMethod("identifier") func constraintIdentifier() -> String? { identifier }
    @ObjCMethod("setIdentifier:") func setIdentifier(_ value: String?) { identifier = value }
    @ObjCMethod("shouldBeArchived") func constraintShouldBeArchived() -> Bool { shouldBeArchived }
    @ObjCMethod("setShouldBeArchived:") func setShouldBeArchived(_ value: Bool) { shouldBeArchived = value }
    @ObjCMethod("firstAnchor") func firstAnchor() -> NSLayoutAnchor? { firstItem.map { NSLayoutAnchor.make($0, firstAttribute) } }
    @ObjCMethod("secondAnchor") func secondAnchor() -> NSLayoutAnchor? { secondItem.map { NSLayoutAnchor.make($0, secondAttribute) } }
}

/// A view's edge, center or size, which makes constraints to another's.
@ObjCClass("NSLayoutAnchor")
open class NSLayoutAnchor: NSObject {
    var item: NSObject?
    var attribute = 0

    @ObjCMethod("init")
    public required override init() { super.init() }

    static func make(_ item: NSObject, _ attribute: Int) -> NSLayoutAnchor {
        let anchor: NSLayoutAnchor
        switch attribute {
        case 7, 8: anchor = NSLayoutDimension()
        case 3, 4, 10, 11, 12, 15, 16, 20: anchor = NSLayoutYAxisAnchor()
        default: anchor = NSLayoutXAxisAnchor()
        }
        (anchor.item, anchor.attribute) = (item, attribute)
        return anchor
    }

    private func constraint(_ relation: Int, _ other: NSLayoutAnchor?, multiplier: CGFloat = 1, constant: CGFloat = 0) -> NSLayoutConstraint {
        NSLayoutConstraint(item: item, attribute: attribute, relation: relation, to: other?.item, attribute: other?.attribute ?? 0,
                           multiplier: multiplier, constant: constant)
    }

    @ObjCMethod("item") func anchorItem() -> NSObject? { item }
    @ObjCMethod("constraintEqualToAnchor:") func equal(to other: NSLayoutAnchor?) -> NSLayoutConstraint { constraint(0, other) }
    @ObjCMethod("constraintEqualToAnchor:constant:")
    func equal(to other: NSLayoutAnchor?, constant: CGFloat) -> NSLayoutConstraint { constraint(0, other, constant: constant) }
    @ObjCMethod("constraintGreaterThanOrEqualToAnchor:") func greater(than other: NSLayoutAnchor?) -> NSLayoutConstraint { constraint(1, other) }
    @ObjCMethod("constraintGreaterThanOrEqualToAnchor:constant:")
    func greater(than other: NSLayoutAnchor?, constant: CGFloat) -> NSLayoutConstraint { constraint(1, other, constant: constant) }
    @ObjCMethod("constraintLessThanOrEqualToAnchor:") func less(than other: NSLayoutAnchor?) -> NSLayoutConstraint { constraint(-1, other) }
    @ObjCMethod("constraintLessThanOrEqualToAnchor:constant:")
    func less(than other: NSLayoutAnchor?, constant: CGFloat) -> NSLayoutConstraint { constraint(-1, other, constant: constant) }
    @ObjCMethod("constraintEqualToConstant:") func equal(toConstant constant: CGFloat) -> NSLayoutConstraint { constraint(0, nil, constant: constant) }
    @ObjCMethod("constraintGreaterThanOrEqualToConstant:")
    func greater(thanConstant constant: CGFloat) -> NSLayoutConstraint { constraint(1, nil, constant: constant) }
    @ObjCMethod("constraintLessThanOrEqualToConstant:")
    func less(thanConstant constant: CGFloat) -> NSLayoutConstraint { constraint(-1, nil, constant: constant) }
    @ObjCMethod("constraintEqualToAnchor:multiplier:")
    func equal(to other: NSLayoutAnchor?, multiplier: CGFloat) -> NSLayoutConstraint { constraint(0, other, multiplier: multiplier) }
    @ObjCMethod("constraintEqualToAnchor:multiplier:constant:")
    func equal(to other: NSLayoutAnchor?, multiplier: CGFloat, constant: CGFloat) -> NSLayoutConstraint {
        constraint(0, other, multiplier: multiplier, constant: constant)
    }
}

@ObjCClass("NSLayoutXAxisAnchor")
open class NSLayoutXAxisAnchor: NSLayoutAnchor {}

@ObjCClass("NSLayoutYAxisAnchor")
open class NSLayoutYAxisAnchor: NSLayoutAnchor {}

@ObjCClass("NSLayoutDimension")
open class NSLayoutDimension: NSLayoutAnchor {}

enum Layout {
    private enum Axis { case horizontal, vertical }

    /// An attribute's axis, and what it measures: the minimum edge 0, the
    /// maximum 1, the size 2, the center 3; with the margin it adds.
    private static func role(_ attribute: Int) -> (axis: Axis, part: Int, margin: CGFloat)? {
        switch attribute {
        case 1, 5: return (.horizontal, 0, 0)
        case 2, 6: return (.horizontal, 1, 0)
        case 3, 12: return (.vertical, 0, 0)
        case 4, 11: return (.vertical, 1, 0)
        case 7: return (.horizontal, 2, 0)
        case 8: return (.vertical, 2, 0)
        case 9: return (.horizontal, 3, 0)
        case 10: return (.vertical, 3, 0)
        case 13, 17: return (.horizontal, 0, 8)
        case 14, 18: return (.horizontal, 1, -8)
        case 15: return (.vertical, 0, 8)
        case 16: return (.vertical, 1, -8)
        case 19: return (.horizontal, 3, 0)
        case 20: return (.vertical, 3, 0)
        default: return nil
        }
    }

    /// An attribute of a rectangle with y downwards.
    private static func value(_ rect: CGRect, _ attribute: Int) -> CGFloat? {
        guard let (axis, part, margin) = role(attribute) else { return nil }
        let (low, size) = axis == .horizontal ? (rect.minX, rect.width) : (rect.minY, rect.height)
        switch part {
        case 0: return low + margin
        case 1: return low + size + margin
        case 2: return size
        default: return low + size / 2
        }
    }

    /// A subview's frame with y downwards in `view`.
    private static func downward(_ subview: NSView, in view: NSView) -> CGRect {
        var rect = subview.frame
        if !view.flipped { rect.origin.y = view.frame.height - rect.maxY }
        return rect
    }

    /// Places the subviews of `view` that its constraints place.
    static func apply(_ view: NSView) {
        let placed = view.subviews.filter { !$0.translatesAutoresizingMask }
        guard !placed.isEmpty else { return }
        var all = view.constraints
        for subview in placed { all += subview.constraints }
        let container = CGRect(origin: .zero, size: view.frame.size)
        var frames: [ObjectIdentifier: CGRect] = [:]
        for subview in view.subviews { frames[ObjectIdentifier(subview)] = downward(subview, in: view) }
        func rect(of item: NSObject?) -> CGRect? {
            guard let item else { return nil }
            if item.objcObject == view.objcObject { return container }
            guard let other = item.as(NSView.self), other.superviewObject == view.objcObject else {
                // A layout guide, or a view elsewhere: the container.
                return item.is(NSView.self) ? nil : container
            }
            return frames[ObjectIdentifier(other)]
        }
        // Siblings placed by each other settle over a few passes.
        for _ in 0..<3 {
            for subview in placed {
                frames[ObjectIdentifier(subview)] = solve(subview, all, current: frames[ObjectIdentifier(subview)] ?? subview.frame, rect: rect)
            }
        }
        for subview in placed {
            guard var frame = frames[ObjectIdentifier(subview)] else { continue }
            if !view.flipped { frame.origin.y = view.frame.height - frame.maxY }
            frame = CGRect(x: frame.minX.rounded(), y: frame.minY.rounded(), width: max(0, frame.width.rounded()), height: max(0, frame.height.rounded()))
            if frame != subview.frame { Send.void(subview.objcObject, "setFrame:", rect: frame) }
        }
    }

    /// The frame, y downwards, that the constraints give `subview`.
    private static func solve(_ subview: NSView, _ constraints: [NSLayoutConstraint], current: CGRect,
                              rect: (NSObject?) -> CGRect?) -> CGRect {
        // What is known of each axis: minimum, maximum, size, center.
        var known: [Axis: [Int: CGFloat]] = [.horizontal: [:], .vertical: [:]]
        var bounds: [Axis: (low: CGFloat?, high: CGFloat?)] = [.horizontal: (nil, nil), .vertical: (nil, nil)]
        let me = subview.objcObject
        for constraint in constraints {
            let first = constraint.firstItem?.objcObject, second = constraint.secondItem?.objcObject
            let mine: Int, other: Int, otherItem: NSObject?
            var solved: CGFloat
            if first == me && second != me {
                (mine, other, otherItem) = (constraint.firstAttribute, constraint.secondAttribute, constraint.secondItem)
                let base: CGFloat
                if otherItem == nil { base = 0 } else {
                    guard let r = rect(otherItem), let v = value(r, other) else { continue }
                    base = v
                }
                solved = constraint.multiplier * base + constraint.constant
            } else if second == me && first != me {
                (mine, other, otherItem) = (constraint.secondAttribute, constraint.firstAttribute, constraint.firstItem)
                guard let r = rect(otherItem), let v = value(r, other), constraint.multiplier != 0 else { continue }
                solved = (v - constraint.constant) / constraint.multiplier
            } else {
                continue
            }
            guard let (axis, part, margin) = role(mine) else { continue }
            solved -= part <= 1 ? margin : 0
            // A relation's direction flips when the subview is the second item.
            var relation = constraint.relation
            if second == me { relation = -relation }
            if relation == 0 {
                if constraint.priority >= 250 || known[axis]![part] == nil { known[axis]![part] = solved }
            } else if part == 2 {
                var range = bounds[axis]!
                if relation > 0 { range.low = max(range.low ?? solved, solved) } else { range.high = min(range.high ?? solved, solved) }
                bounds[axis] = range
            }
        }
        let intrinsic = Send.size(subview.objcObject, "intrinsicContentSize")
        func resolve(_ axis: Axis, low currentLow: CGFloat, size currentSize: CGFloat, intrinsic: CGFloat) -> (CGFloat, CGFloat) {
            let facts = known[axis]!
            var size = facts[2] ?? (intrinsic > 0 ? intrinsic : currentSize)
            var low = currentLow
            if let a = facts[0], let b = facts[1] {
                low = a
                size = b - a
            } else if let a = facts[0] {
                low = a
                if let c = facts[3], facts[2] == nil { size = 2 * (c - a) }
            } else if let b = facts[1] {
                if let c = facts[3], facts[2] == nil { size = 2 * (b - c) }
                low = b - size
            } else if let c = facts[3] {
                low = c - size / 2
            }
            if let range = bounds[axis] {
                if let floor = range.low, size < floor { size = floor }
                if let ceiling = range.high, size > ceiling { size = ceiling }
            }
            return (low, max(0, size))
        }
        let (x, width) = resolve(.horizontal, low: current.minX, size: current.width, intrinsic: intrinsic.width)
        let (y, height) = resolve(.vertical, low: current.minY, size: current.height, intrinsic: intrinsic.height)
        return CGRect(x: x, y: y, width: width, height: height)
    }

    /// The size a view needs: its frame, or for a view whose subviews its
    /// constraints place, what they span.
    static func fittingSize(_ view: NSView) -> CGSize {
        let intrinsic = Send.size(view.objcObject, "intrinsicContentSize")
        if intrinsic.width > 0 && intrinsic.height > 0 { return intrinsic }
        return view.frame.size
    }
}

extension Send {
    static func size(_ receiver: Object, _ selector: String) -> CGSize {
        typealias F = @convention(c) (Object, Selector) -> CGSize
        return unsafeBitCast(ObjCRuntime.msgSend, to: F.self)(receiver, ObjCRuntime.selector(selector))
    }
}
