import CPerryGeometry
import PerryObjCInterop

// UIStackView: a view that lines up its arranged subviews along an axis.
// As in UIKit, the arrangement is constraints, which the layout that
// solves the stack view's frame solves with the rest (AutoLayout). Hidden
// arranged subviews take no room. Where the constraints leave sizes open,
// as when views hug at the same priority, the frames a nib was laid out
// with settle them.

final class StackState: ObjectState {
    var arrangedSubviews: [UIView] = []
    /// UILayoutConstraintAxis: horizontal 0, vertical 1.
    var axis = 0
    /// UIStackViewDistribution: fill 0, fill equally 1, fill proportionally
    /// 2, equal spacing 3, equal centering 4.
    var distribution = 0
    /// UIStackViewAlignment: fill 0, leading or top 1, first baseline 2,
    /// center 3, trailing or bottom 4, last baseline 5.
    var alignment = 0
    var spacing: CGFloat = 0
    var customSpacing: [UnsafeMutableRawPointer: CGFloat] = [:]
    var baselineRelative = false
    var layoutMarginsRelative = false
}

@ObjCClass("UIStackView")
open class UIStackView: UIView {
    static let stackStates = StateTable<StackState>()
    var stack: StackState { UIStackView.stackStates[objcObject] }

    /// UIStackViewSpacingUseDefault and UIStackViewSpacingUseSystem.
    static let useDefaultSpacing = CGFloat(Float.greatestFiniteMagnitude)
    static let useSystemSpacing = CGFloat(-Float.greatestFiniteMagnitude)

    @ObjCMethod("dealloc")
    override func dealloc() {
        UIStackView.stackStates.remove(objcObject)
        super.dealloc()
    }

    @ObjCMethod("initWithArrangedSubviews:")
    func initialize(arrangedSubviews views: NSArray) -> Self {
        _ = initializeView(frame: .zero)
        for view in views.elements { addArrangedSubview(view.unsafeCast(to: UIView.self)) }
        return self
    }

    @ObjCMethod("initWithCoder:")
    override func initialize(coder: NSObject) -> Self {
        _ = super.initialize(coder: coder)
        let decoded = Coder(coder: coder)
        let stack = stack
        stack.arrangedSubviews = decoded.array("UIStackViewArrangedSubviews").compactMap { $0.as(UIView.self) }
        for view in stack.arrangedSubviews { view.state.translatesAutoresizingMaskIntoConstraints = false }
        stack.axis = decoded.integer("UIStackViewAxis")
        stack.distribution = decoded.integer("UIStackViewDistribution")
        stack.alignment = decoded.integer("UIStackViewAlignment")
        stack.spacing = decoded.double("UIStackViewSpacing")
        stack.baselineRelative = decoded.bool("UIStackViewBaselineRelative")
        stack.layoutMarginsRelative = decoded.bool("UIStackViewLayoutMarginsRelative")
        return self
    }

    // MARK: Arranged subviews

    /// Those still subviews: a view removed from the stack view leaves the
    /// arrangement too.
    var arranged: [UIView] { stack.arrangedSubviews.filter { $0.state.superview == objcObject } }

    @ObjCMethod("arrangedSubviews") func arrangedSubviews() -> NSObject { NSMutableArray.of(arranged) }

    @ObjCMethod("addArrangedSubview:")
    func addArrangedSubview(_ view: UIView) { insertArrangedSubview(view, at: UInt(arranged.count)) }

    /// Adds the view as a subview too, laid out by constraints.
    @ObjCMethod("insertArrangedSubview:atIndex:")
    func insertArrangedSubview(_ view: UIView, at index: UInt) {
        stack.arrangedSubviews = arranged.filter { $0.objcObject != view.objcObject }
        stack.arrangedSubviews.insert(view, at: min(Int(index), stack.arrangedSubviews.count))
        view.state.translatesAutoresizingMaskIntoConstraints = false
        if view.state.superview != objcObject { addSubview(view) }
        arrangementChanged()
    }

    /// Leaves the view a subview, as UIKit does.
    @ObjCMethod("removeArrangedSubview:")
    func removeArrangedSubview(_ view: UIView) {
        stack.arrangedSubviews.removeAll { $0.objcObject == view.objcObject }
        stack.customSpacing[view.objcObject] = nil
        arrangementChanged()
    }

    // MARK: Arrangement

    @ObjCMethod("axis") func axis() -> Int { stack.axis }
    @ObjCMethod("setAxis:") func setAxis(_ axis: Int) { stack.axis = axis; arrangementChanged() }
    @ObjCMethod("distribution") func distribution() -> Int { stack.distribution }
    @ObjCMethod("setDistribution:") func setDistribution(_ distribution: Int) { stack.distribution = distribution; arrangementChanged() }
    @ObjCMethod("alignment") func alignment() -> Int { stack.alignment }
    @ObjCMethod("setAlignment:") func setAlignment(_ alignment: Int) { stack.alignment = alignment; arrangementChanged() }
    @ObjCMethod("spacing") func spacing() -> CGFloat { stack.spacing }
    @ObjCMethod("setSpacing:") func setSpacing(_ spacing: CGFloat) { stack.spacing = spacing; arrangementChanged() }

    @ObjCMethod("setCustomSpacing:afterView:")
    func setCustomSpacing(_ spacing: CGFloat, after view: UIView) {
        stack.customSpacing[view.objcObject] = spacing == UIStackView.useDefaultSpacing ? nil : spacing
        arrangementChanged()
    }

    @ObjCMethod("customSpacingAfterView:")
    func customSpacing(after view: UIView) -> CGFloat { stack.customSpacing[view.objcObject] ?? UIStackView.useDefaultSpacing }

    @ObjCMethod("isBaselineRelativeArrangement") func isBaselineRelativeArrangement() -> Bool { stack.baselineRelative }
    @ObjCMethod("setBaselineRelativeArrangement:")
    func setBaselineRelativeArrangement(_ relative: Bool) { stack.baselineRelative = relative; arrangementChanged() }
    @ObjCMethod("isLayoutMarginsRelativeArrangement") func isLayoutMarginsRelativeArrangement() -> Bool { stack.layoutMarginsRelative }
    @ObjCMethod("setLayoutMarginsRelativeArrangement:")
    func setLayoutMarginsRelativeArrangement(_ relative: Bool) { stack.layoutMarginsRelative = relative; arrangementChanged() }

    /// The space after an arranged subview: its custom spacing, or the
    /// stack view's; the system spacing is 8 points.
    func spacing(after view: UIView) -> CGFloat {
        let spacing = stack.customSpacing[view.objcObject] ?? stack.spacing
        return spacing == UIStackView.useSystemSpacing ? 8 : spacing
    }

    /// The stack view and the layout its frame is solved in run again.
    func arrangementChanged() {
        setNeedsLayout()
        superviewNeedsLayout()
    }
}

extension AutoLayout.System {
    /// The constraints that line up a stack view's visible arranged
    /// subviews, at UIKit's priorities.
    func arrange(_ stackView: UIStackView) {
        let stack = stackView.stack
        let views = stackView.arranged.filter { !$0.state.hidden }
        guard let first = views.first, let last = views.last else { return }
        typealias Attribute = AutoLayout.Attribute
        let horizontal = stack.axis == 0
        let (leading, trailing, length): (Attribute, Attribute, Attribute) = horizontal ? (.leading, .trailing, .width) : (.top, .bottom, .height)
        let (top, bottom, middle, thickness): (Attribute, Attribute, Attribute, Attribute) =
            horizontal ? (.top, .bottom, .centerY, .height) : (.leading, .trailing, .centerX, .width)

        /// The stack view's own edges, inside its margins when it arranges
        /// within them.
        func edge(_ attribute: Attribute) -> LayoutExpression? {
            guard stack.layoutMarginsRelative else { return expression(stackView, attribute) }
            let inside: [Attribute: Attribute] = [.leading: .leadingMargin, .trailing: .trailingMargin, .top: .topMargin,
                                                  .bottom: .bottomMargin, .centerX: .centerXWithinMargins, .centerY: .centerYWithinMargins]
            return expression(stackView, inside[attribute] ?? attribute)
        }
        func constrain(_ lhs: LayoutExpression?, _ relation: LayoutSolver.Relation, _ rhs: LayoutExpression?, _ constant: CGFloat = 0,
                       priority: Float = 1000) {
            guard let lhs, let rhs else { return }
            solver.add(lhs - (rhs + constant), relation, strength: AutoLayout.strength(priority))
        }
        func gap(_ before: UIView, _ after: UIView) -> LayoutExpression? {
            guard let start = expression(after, leading), let end = expression(before, trailing) else { return nil }
            return start - end
        }

        // Along the axis: end to end, from edge to edge.
        constrain(expression(first, leading), .equal, edge(leading))
        constrain(expression(last, trailing), .equal, edge(trailing))
        let pairs = Array(zip(views, views.dropFirst()))
        for (before, after) in pairs {
            let spacing = stackView.spacing(after: before)
            let relation: LayoutSolver.Relation = stack.distribution >= 3 ? .greaterOrEqual : .equal
            constrain(expression(after, leading), relation, expression(before, trailing), spacing)
        }
        switch stack.distribution {
        case 1:
            for view in views.dropFirst() { constrain(expression(view, length), .equal, expression(first, length)) }
        case 2:
            // In proportion to their intrinsic lengths.
            let lengths = views.map { view -> CGFloat in
                let size = view.sendIntrinsicContentSize()
                return horizontal ? size.width : size.height
            }
            guard let reference = lengths.firstIndex(where: { $0 > 0 }) else { break }
            for (view, size) in zip(views, lengths) where size > 0 && view.objcObject != views[reference].objcObject {
                guard let mine = expression(view, length), let theirs = expression(views[reference], length) else { continue }
                solver.add(mine * lengths[reference] - theirs * size, .equal, strength: AutoLayout.strength(999))
            }
        case 3 where views.count > 2:
            guard let firstGap = gap(first, views[1]) else { break }
            for (before, after) in pairs.dropFirst() { constrain(gap(before, after), .equal, firstGap, priority: 999) }
        case 4 where views.count > 2:
            let along: Attribute = horizontal ? .centerX : .centerY
            guard let start = expression(first, along), let next = expression(views[1], along) else { break }
            for (before, after) in pairs.dropFirst() {
                guard let from = expression(before, along), let to = expression(after, along) else { continue }
                constrain(to - from, .equal, next - start, priority: 999)
            }
        default:
            break
        }

        // Across it: as aligned, inside the stack view, which is as thick as
        // the thickest view where alignment leaves it free.
        let alignment = !horizontal && (stack.alignment == 2 || stack.alignment == 5) ? 1 : stack.alignment
        for view in views {
            switch alignment {
            case 0:
                constrain(expression(view, top), .equal, edge(top))
                constrain(expression(view, bottom), .equal, edge(bottom))
            case 1:
                constrain(expression(view, top), .equal, edge(top))
                constrain(expression(view, bottom), .lessOrEqual, edge(bottom))
            case 4:
                constrain(expression(view, top), .greaterOrEqual, edge(top))
                constrain(expression(view, bottom), .equal, edge(bottom))
            case 3:
                constrain(expression(view, middle), .equal, edge(middle))
                constrain(expression(view, top), .greaterOrEqual, edge(top))
                constrain(expression(view, bottom), .lessOrEqual, edge(bottom))
            default:
                let baseline: Attribute = alignment == 2 ? .firstBaseline : .lastBaseline
                if view.objcObject != first.objcObject { constrain(expression(view, baseline), .equal, expression(first, baseline)) }
                constrain(expression(view, top), .greaterOrEqual, edge(top))
                constrain(expression(view, bottom), .lessOrEqual, edge(bottom))
            }
            if alignment != 0, let near = edge(top), let far = edge(bottom) {
                constrain(far - near, .equal, expression(view, thickness), priority: 49)
            }
        }
    }
}
