import CPerryGeometry
import PerryLayoutSolver
import PerryObjCInterop

// Auto Layout: constraints between views, their superviews and siblings,
// each attribute (relation) multiplier × other attribute + constant at a
// priority, solved over a whole view tree at once (see Layout).
// NSLayoutAttribute: left 1, right 2, top 3, bottom 4, leading 5, trailing
// 6, width 7, height 8, center x 9, center y 10, last baseline 11, first
// baseline 12, and the margins 13 to 20.

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
        guard let format else { return NSMutableArray.empty() }
        return NSMutableArray.of(VisualFormat.constraints(format, options: options, metrics: metrics, views: views))
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

/// Lays out a window's view tree with the constraints of every view in it:
/// one Cassowary solve over the frames of all the views, in which views
/// that translate their autoresizing masks keep their frames, views placed
/// by constraints prefer their current frames weakly, and intrinsic sizes
/// count at each view's hugging and compression resistance priorities. A
/// tree is solved again only once something changed (a view needs layout).
enum Layout {
    /// Bumped whenever a view needs layout.
    nonisolated(unsafe) static var generation = 0
    nonisolated(unsafe) private static var solvedGeneration: [ObjectIdentifier: Int] = [:]
    nonisolated(unsafe) private static var solving = false

    /// A view's frame in the tree's top view's coordinates, y downwards.
    private final class Box {
        let view: NSView
        let parent: Box?
        let rect: CGRect
        let left: LayoutVariable, top: LayoutVariable, width: LayoutVariable, height: LayoutVariable

        init(_ view: NSView, parent: Box?, rect: CGRect) {
            (self.view, self.parent, self.rect) = (view, parent, rect)
            (left, top, width, height) = (LayoutVariable(), LayoutVariable(), LayoutVariable(), LayoutVariable())
        }

        var l: LayoutExpression { LayoutExpression(left) }
        var t: LayoutExpression { LayoutExpression(top) }
        var w: LayoutExpression { LayoutExpression(width) }
        var h: LayoutExpression { LayoutExpression(height) }

        /// An attribute: NSLayoutAttribute's left 1, right 2, top 3, bottom
        /// 4, leading 5, trailing 6, width 7, height 8, center x 9, center y
        /// 10, last baseline 11, first baseline 12, margins 13 to 20.
        func attribute(_ attribute: Int) -> LayoutExpression? {
            switch attribute {
            case 1, 5: return l
            case 2, 6: return l + w
            case 3, 12: return t
            case 4, 11: return t + h
            case 7: return w
            case 8: return h
            case 9: return l + w * 0.5
            case 10: return t + h * 0.5
            case 13, 17: return l + 8
            case 14, 18: return l + w + -8
            case 15: return t + 8
            case 16: return t + h + -8
            case 19: return l + w * 0.5
            case 20: return t + h * 0.5
            default: return nil
            }
        }
    }

    private static func weight(_ priority: Float) -> Double { LayoutSolver.strength(priority) }

    /// The tree's boxes, top first, each after its parent.
    private static func boxes(_ top: NSView, origin: CGRect) -> [Box] {
        var boxes: [Box] = []
        func visit(_ view: NSView, _ parent: Box?, _ rect: CGRect) {
            let box = Box(view, parent: parent, rect: rect)
            boxes.append(box)
            let flipped = view.flipped
            for subview in view.subviews {
                let frame = subview.frame
                let x = rect.minX + frame.minX - view.boundsOrigin.x
                let down = flipped ? frame.minY - view.boundsOrigin.y : view.frame.height - frame.maxY + view.boundsOrigin.y
                visit(subview, box, CGRect(x: x, y: rect.minY + down, width: frame.width, height: frame.height))
            }
        }
        visit(top, nil, origin)
        return boxes
    }

    /// Solves the tree under `top`: with its size fixed, or for fitting,
    /// as small as its constraints allow.
    private static func solve(_ top: NSView, fitting: Bool) -> [Box]? {
        let boxes = boxes(top, origin: CGRect(origin: .zero, size: top.frame.size))
        guard boxes.dropFirst().contains(where: { !$0.view.translatesAutoresizingMask }) || fitting else { return nil }
        var byView: [UnsafeMutableRawPointer: Box] = [:]
        for box in boxes { byView[box.view.objcObject] = box }
        let solver = LayoutSolver()
        var refused = 0
        func add(_ expression: LayoutExpression, _ relation: LayoutSolver.Relation, _ strength: Double) {
            if !solver.add(expression, relation, strength: strength) { refused += 1 }
        }
        let root = boxes[0]
        add(root.l, .equal, LayoutSolver.required)
        add(root.t, .equal, LayoutSolver.required)
        if fitting {
            add(root.w, .greaterOrEqual, LayoutSolver.required)
            add(root.h, .greaterOrEqual, LayoutSolver.required)
            add(root.w, .equal, weight(50))
            add(root.h, .equal, weight(50))
        } else {
            add(root.w + -Double(root.rect.width), .equal, LayoutSolver.required)
            add(root.h + -Double(root.rect.height), .equal, LayoutSolver.required)
        }
        // Frames that autoresizing places stay, relative to the superview.
        for box in boxes.dropFirst() {
            guard let parent = box.parent else { continue }
            let view = box.view
            if view.translatesAutoresizingMask {
                // The autoresizing mask as constraints: as the superview's
                // size changes from what it is, the change is shared among
                // the flexible parts (margins and size) by their sizes, as
                // -resizeWithOldSuperviewSize: shares it.
                let mask = view.autoresizingMask
                let flipped = parent.view.flipped
                func axis(_ low: LayoutExpression, _ size: LayoutExpression, _ parentLow: LayoutExpression, _ parentSize: LayoutExpression,
                          offset: CGFloat, length: CGFloat, parentLength: CGFloat, flexible: (low: Bool, size: Bool, high: Bool)) {
                    let parts = [(flexible.low, offset), (flexible.size, length), (flexible.high, parentLength - offset - length)]
                    let count = parts.filter { $0.0 }.count
                    let total = parts.filter { $0.0 }.reduce(0) { $0 + max(0, $1.1) }
                    func share(_ index: Int) -> CGFloat {
                        guard parts[index].0 else { return 0 }
                        return total > 0 ? max(0, parts[index].1) / total : 1 / CGFloat(count)
                    }
                    let delta = parentSize + -Double(parentLength)
                    add(low - parentLow - delta * Double(share(0)) + -Double(offset), .equal, LayoutSolver.required)
                    add(size - delta * Double(share(1)) + -Double(length), .equal, LayoutSolver.required)
                }
                axis(box.l, box.w, parent.l, parent.w, offset: box.rect.minX - parent.rect.minX, length: box.rect.width,
                     parentLength: parent.rect.width, flexible: (mask & 1 != 0, mask & 2 != 0, mask & 4 != 0))
                // y is downwards: the top margin is a flipped superview's
                // minimum y margin, an unflipped one's maximum.
                axis(box.t, box.h, parent.t, parent.h, offset: box.rect.minY - parent.rect.minY, length: box.rect.height,
                     parentLength: parent.rect.height,
                     flexible: (mask & (flipped ? 8 : 32) != 0, mask & 16 != 0, mask & (flipped ? 32 : 8) != 0))
                continue
            }
            add(box.w, .greaterOrEqual, LayoutSolver.required)
            add(box.h, .greaterOrEqual, LayoutSolver.required)
            let intrinsic = Send.size(view.objcObject, "intrinsicContentSize")
            if Trace.enabled { Trace.log("layout: \(view.describedByObject() ?? "?") intrinsic \(intrinsic.width)×\(intrinsic.height)") }
            if intrinsic.width >= 0 {
                add(box.w + -Double(intrinsic.width), .greaterOrEqual, weight(view.compressionResistance[0]))
                add(box.w + -Double(intrinsic.width), .lessOrEqual, weight(view.hugging[0]))
            }
            if intrinsic.height >= 0 {
                add(box.h + -Double(intrinsic.height), .greaterOrEqual, weight(view.compressionResistance[1]))
                add(box.h + -Double(intrinsic.height), .lessOrEqual, weight(view.hugging[1]))
            }
        }
        // The views' constraints.
        for box in boxes {
            for constraint in box.view.constraints {
                func expression(_ item: NSObject?, _ attribute: Int) -> LayoutExpression? {
                    guard let item else { return attribute == 0 ? LayoutExpression() : nil }
                    var target = byView[item.objcObject]
                    // A layout guide stands for its owning view.
                    if target == nil, !item.is(NSView.self), item.responds(to: "owningView"),
                       let owner = Send.object(item.objcObject, "owningView") { target = byView[owner] }
                    return target?.attribute(attribute)
                }
                guard let first = expression(constraint.firstItem, constraint.firstAttribute) else { continue }
                guard let second = constraint.secondItem == nil ? LayoutExpression()
                        : expression(constraint.secondItem, constraint.secondAttribute) else { continue }
                let relation: LayoutSolver.Relation = constraint.relation < 0 ? .lessOrEqual : constraint.relation > 0 ? .greaterOrEqual : .equal
                if Trace.enabled {
                    Trace.log("layout: \(constraint.firstItem?.describedByObject() ?? "nil").\(constraint.firstAttribute) \(constraint.relation) "
                              + "\(constraint.secondItem?.describedByObject() ?? "nil").\(constraint.secondAttribute) × \(constraint.multiplier) + \(constraint.constant) @\(constraint.priority)")
                }
                add(first - (second * Double(constraint.multiplier) + Double(constraint.constant)), relation, weight(constraint.priority))
            }
        }
        // Where nothing else decides, frames stay as they are.
        for box in boxes.dropFirst() where !box.view.translatesAutoresizingMask {
            add(box.l + -Double(box.rect.minX), .equal, 1)
            add(box.t + -Double(box.rect.minY), .equal, 1)
            add(box.w + -Double(box.rect.width), .equal, 1)
            add(box.h + -Double(box.rect.height), .equal, 1)
        }
        if refused > 0 { Trace.log("layout: \(refused) constraints of \(top.describedByObject() ?? "a view") can't be satisfied") }
        solver.updateVariables()
        return boxes
    }

    /// Lays out the tree `view` is in, unless it is laid out already.
    static func apply(_ view: NSView) {
        guard !solving else { return }
        var top = view
        while let superview = top.superview { top = superview }
        let key = ObjectIdentifier(top)
        guard solvedGeneration[key] != generation else { return }
        solving = true
        defer { solving = false }
        if let boxes = solve(top, fitting: false) {
            for box in boxes.dropFirst() where !box.view.translatesAutoresizingMask {
                guard let parent = box.parent else { continue }
                let superview = parent.view
                let x = box.left.value - parent.left.value + superview.boundsOrigin.x
                let down = box.top.value - parent.top.value
                let height = box.height.value
                let y = superview.flipped ? down + superview.boundsOrigin.y : parent.height.value - down - height + superview.boundsOrigin.y
                let frame = CGRect(x: x.rounded(), y: y.rounded(), width: max(0, box.width.value.rounded()), height: max(0, height.rounded()))
                if frame != box.view.frame { Send.void(box.view.objcObject, "setFrame:", rect: frame) }
            }
        }
        solvedGeneration[key] = generation
    }

    /// The size a view needs: its intrinsic size, or the smallest its
    /// subviews' constraints allow.
    static func fittingSize(_ view: NSView) -> CGSize {
        let intrinsic = Send.size(view.objcObject, "intrinsicContentSize")
        if intrinsic.width > 0 && intrinsic.height > 0 { return intrinsic }
        guard !solving, view.subviews.contains(where: { !$0.translatesAutoresizingMask }) else { return view.frame.size }
        solving = true
        defer { solving = false }
        guard let boxes = solve(view, fitting: true) else { return view.frame.size }
        return CGSize(width: boxes[0].width.value.rounded(.up), height: boxes[0].height.value.rounded(.up))
    }
}

extension Send {
    static func size(_ receiver: Object, _ selector: String) -> CGSize {
        typealias F = @convention(c) (Object, Selector) -> CGSize
        return unsafeBitCast(ObjCRuntime.msgSend, to: F.self)(receiver, ObjCRuntime.selector(selector))
    }
}
