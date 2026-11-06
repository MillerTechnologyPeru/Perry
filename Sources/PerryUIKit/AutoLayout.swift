import CPerryGeometry
import PerryLayoutSolver
import PerryObjCInterop

// Auto Layout: constraints solved with the Cassowary algorithm, as
// Apple's engine does, in Kiwi's formulation. A view lays out its subviews
// from the constraints it and those subviews hold: each view a constraint
// names gets four variables, its frame in the laying-out view's space.
// Views that translate their autoresizing masks keep the frames they have;
// the laying-out view keeps its bounds. Views with an intrinsic content
// size hug it and resist compression at their priorities, and multi-line
// labels are measured again at the width they are given.

// MARK: - Laying out views

enum AutoLayout {
    /// NSLayoutAttribute.
    enum Attribute: Int {
        case notAnAttribute = 0, left, right, top, bottom, leading, trailing, width, height, centerX, centerY
        case lastBaseline, firstBaseline, leftMargin, rightMargin, topMargin, bottomMargin, leadingMargin, trailingMargin
        case centerXWithinMargins, centerYWithinMargins
    }

    /// A view's frame as variables, in the laying-out view's space.
    final class Item {
        let view: UIView
        let x = LayoutVariable(), y = LayoutVariable(), width = LayoutVariable(), height = LayoutVariable()
        /// Solved, or kept as it was.
        let solved: Bool

        init(_ view: UIView, solved: Bool) {
            self.view = view
            self.solved = solved
        }

        var frame: CGRect { CGRect(x: x.value, y: y.value, width: width.value, height: height.value) }
    }

    /// One layout: the laying-out view, its items, and the constraints.
    final class System {
        let root: UIView
        let solver = LayoutSolver()
        var items: [UnsafeMutableRawPointer: Item] = [:]
        /// Multi-line labels, and the height each was given.
        var labels: [(item: Item, height: CGFloat)] = []

        init(root: UIView) { self.root = root }

        func item(_ view: UIView) -> Item {
            if let item = items[view.objcObject] { return item }
            // Views inside the root, laid out by constraints, are solved;
            // the root and every other view keep their frames.
            let solved = view.objcObject != root.objcObject && !view.state.translatesAutoresizingMaskIntoConstraints
                && view.isDescendant(of: root)
            let item = Item(view, solved: solved)
            items[view.objcObject] = item
            if solved {
                // Where the view is now, at the lowest priority, settles
                // what the constraints leave open.
                let frame = view.convert(view.state.bounds, to: root)
                hold(item, at: frame, strength: 1)
                solver.add(LayoutExpression(item.width), .greaterOrEqual, strength: LayoutSolver.required)
                solver.add(LayoutExpression(item.height), .greaterOrEqual, strength: LayoutSolver.required)
                addIntrinsicSize(item)
            } else if view.objcObject == root.objcObject {
                let bounds = root.state.bounds
                hold(item, at: CGRect(origin: .zero, size: bounds.size), strength: LayoutSolver.required)
            } else {
                hold(item, at: view.convert(view.state.bounds, to: root), strength: LayoutSolver.required)
            }
            return item
        }

        func hold(_ item: Item, at frame: CGRect, strength: Double) {
            solver.add(LayoutExpression(item.x) + -frame.minX, .equal, strength: strength)
            solver.add(LayoutExpression(item.y) + -frame.minY, .equal, strength: strength)
            solver.add(LayoutExpression(item.width) + -frame.width, .equal, strength: strength)
            solver.add(LayoutExpression(item.height) + -frame.height, .equal, strength: strength)
        }

        /// Hugging (no larger) and compression resistance (no smaller), on
        /// each axis that has a size.
        func addIntrinsicSize(_ item: Item) {
            let view = item.view
            var size = view.sendIntrinsicContentSize()
            if let label = view.as(UILabel.self), label.label.numberOfLines != 1 {
                // As wide as its text unwrapped (or its preferred width), as
                // tall as the text wraps to at the width it has, measured
                // again once that is known: a width it was squeezed to once
                // never becomes the width it wants.
                let natural = label.sizeThatFits(.zero)
                var height = natural.height
                if label.label.preferredMaxLayoutWidth <= 0, view.state.bounds.width > 1 {
                    height = label.sizeThatFits(CGSize(width: view.state.bounds.width, height: 0)).height
                }
                size = CGSize(width: natural.width, height: height)
                labels.append((item, height))
            }
            let hugging = view.state.contentHuggingPriority, compression = view.state.compressionResistancePriority
            if size.width >= 0 {
                solver.add(LayoutExpression(item.width) + -size.width, .lessOrEqual, strength: AutoLayout.strength(hugging.width))
                solver.add(LayoutExpression(item.width) + -size.width, .greaterOrEqual, strength: AutoLayout.strength(compression.width))
            }
            if size.height >= 0 {
                solver.add(LayoutExpression(item.height) + -size.height, .lessOrEqual, strength: AutoLayout.strength(hugging.height))
                solver.add(LayoutExpression(item.height) + -size.height, .greaterOrEqual, strength: AutoLayout.strength(compression.height))
            }
        }

        /// An attribute of a view as an expression in its frame variables.
        func expression(_ view: UIView, _ attribute: Attribute) -> LayoutExpression? {
            let item = item(view)
            let x = LayoutExpression(item.x), y = LayoutExpression(item.y)
            let width = LayoutExpression(item.width), height = LayoutExpression(item.height)
            let margins = view.sendLayoutMargins()
            switch attribute {
            case .notAnAttribute: return nil
            case .left, .leading: return x
            case .right, .trailing: return x + width
            case .top: return y
            case .bottom: return y + height
            case .width: return width
            case .height: return height
            case .centerX: return x + width * 0.5
            case .centerY: return y + height * 0.5
            case .leftMargin, .leadingMargin: return x + margins.left
            case .rightMargin, .trailingMargin: return x + width + -margins.right
            case .topMargin: return y + margins.top
            case .bottomMargin: return y + height + -margins.bottom
            case .centerXWithinMargins: return x + width * 0.5 + (margins.left - margins.right) / 2
            case .centerYWithinMargins: return y + height * 0.5 + (margins.top - margins.bottom) / 2
            case .firstBaseline, .lastBaseline:
                // A label's text is centered as a block; elsewhere the
                // baseline is the bottom.
                guard let label = view.as(UILabel.self) else { return y + height }
                let font = label.font, lineHeight = Text.lineHeight(font)
                let lines = CGFloat(max(1, label.lines(width: max(view.state.bounds.width, 1)).count))
                let ascent = font.state.pointSize * 0.95
                let offset = attribute == .firstBaseline ? -lines * lineHeight / 2 + ascent : lines * lineHeight / 2 - lineHeight + ascent
                return y + height * 0.5 + offset
            }
        }

        /// An attribute of a guide, whose edges are `insets` inside its
        /// owning view's; of the view itself without insets.
        func expression(_ view: UIView, _ attribute: Attribute, insets: UIEdgeInsets?) -> LayoutExpression? {
            guard let insets else { return expression(view, attribute) }
            let item = item(view)
            let x = LayoutExpression(item.x), y = LayoutExpression(item.y)
            let width = LayoutExpression(item.width), height = LayoutExpression(item.height)
            switch attribute {
            case .notAnAttribute: return nil
            case .left, .leading, .leftMargin, .leadingMargin: return x + insets.left
            case .right, .trailing, .rightMargin, .trailingMargin: return x + width + -insets.right
            case .top, .topMargin: return y + insets.top
            case .bottom, .bottomMargin, .firstBaseline, .lastBaseline: return y + height + -insets.bottom
            case .width: return width + -(insets.left + insets.right)
            case .height: return height + -(insets.top + insets.bottom)
            case .centerX, .centerXWithinMargins: return x + width * 0.5 + (insets.left - insets.right) / 2
            case .centerY, .centerYWithinMargins: return y + height * 0.5 + (insets.top - insets.bottom) / 2
            }
        }

        /// Adds a constraint, unless it names a view outside the window
        /// or an attribute it cannot express.
        func add(_ constraint: NSLayoutConstraint) {
            let state = constraint.state
            guard let firstObject = state.firstItem, let first = layoutItem(firstObject),
                  let firstAttribute = Attribute(rawValue: state.firstAttribute),
                  let lhs = expression(first.view, firstAttribute, insets: first.insets) else { return }
            var rhs = LayoutExpression(constant: state.constant)
            if let secondObject = state.secondItem, let secondAttribute = Attribute(rawValue: state.secondAttribute),
               secondAttribute != .notAnAttribute {
                guard let second = layoutItem(secondObject),
                      let other = expression(second.view, secondAttribute, insets: second.insets) else { return }
                rhs = other * state.multiplier + state.constant
            }
            let relation: LayoutSolver.Relation = state.relation < 0 ? .lessOrEqual : state.relation > 0 ? .greaterOrEqual : .equal
            solver.add(lhs - rhs, relation, strength: AutoLayout.strength(state.priority))
        }

        /// A constraint's item: its view, or the view that owns the guide
        /// it is with the guide's insets there.
        private func layoutItem(_ object: UnsafeMutableRawPointer) -> (view: UIView, insets: UIEdgeInsets?)? {
            guard let resolved = LayoutItems.resolve(object) else { return nil }
            let view = resolved.view
            guard view.objcObject == root.objcObject || view.isDescendant(of: root) || view.windowObject != nil else { return nil }
            return resolved
        }

        /// Solves, measuring multi-line labels again at their new widths
        /// until their heights settle.
        func solve() {
            solver.updateVariables()
            for _ in 0..<3 {
                var changed = false
                for (index, entry) in labels.enumerated() {
                    guard let label = entry.item.view.as(UILabel.self) else { continue }
                    let height = label.sizeThatFits(CGSize(width: max(entry.item.width.value, 1), height: 0)).height
                    guard abs(height - entry.height) > 0.5 else { continue }
                    labels[index].height = height
                    let compression = label.state.compressionResistancePriority.height
                    solver.add(LayoutExpression(entry.item.height) + -height, .greaterOrEqual, strength: AutoLayout.strength(compression) + 1)
                    solver.add(LayoutExpression(entry.item.height) + -height, .lessOrEqual,
                               strength: AutoLayout.strength(label.state.contentHuggingPriority.height) + 1)
                    changed = true
                }
                guard changed else { break }
                solver.updateVariables()
            }
        }

        /// Sets each solved view's frame, outermost first, in its superview's space.
        func apply() {
            let solved = items.values.filter(\.solved).sorted { depth($0.view) < depth($1.view) }
            for item in solved {
                guard let superviewObject = item.view.state.superview else { continue }
                let superview = UIView.wrap(superviewObject)
                var frame = item.frame
                if let parent = items[superviewObject], parent.solved {
                    frame.origin.x -= parent.x.value
                    frame.origin.y -= parent.y.value
                } else {
                    let origin = superview.convert(CGPoint.zero, to: root)
                    frame.origin.x -= origin.x
                    frame.origin.y -= origin.y
                }
                frame = frame.roundedToScale()
                if frame != item.view.state.frame { item.view.sendSetFrame(frame) }
            }
        }

        private func depth(_ view: UIView) -> Int {
            var depth = 0
            var current = view.state.superview
            while let next = current { depth += 1; current = UIView.wrap(next).state.superview }
            return depth
        }
    }

    /// A priority's strength: 1000 is required.
    static func strength(_ priority: Float) -> Double { LayoutSolver.strength(priority) }

    /// The active constraints `view` holds, and those held by its subviews
    /// that constraints lay out, whose frames this layout sets.
    static func constraints(of view: UIView) -> [NSLayoutConstraint] {
        var found = view.state.constraints.compactMap { $0.as(NSLayoutConstraint.self) }.filter(\.state.active)
        for subview in view.state.subviews where !subview.state.translatesAutoresizingMaskIntoConstraints {
            found += constraints(of: subview)
        }
        return found
    }

    /// The stack views whose arrangements a layout of `view` solves: its
    /// own, and those of the subviews constraints lay out.
    static func stackViews(in view: UIView) -> [UIStackView] {
        var found = view.as(UIStackView.self).map { [$0] } ?? []
        for subview in view.state.subviews where !subview.state.translatesAutoresizingMaskIntoConstraints {
            found += stackViews(in: subview)
        }
        return found
    }

    /// Lays out `view`'s subviews from their constraints.
    static func layOut(_ view: UIView) {
        let constraints = constraints(of: view), stacks = stackViews(in: view)
        guard !constraints.isEmpty || !stacks.isEmpty else { return }
        let system = System(root: view)
        for constraint in constraints { system.add(constraint) }
        for stack in stacks { system.arrange(stack) }
        system.solve()
        system.apply()
    }

    /// The smallest height the constraints in `view` allow at `width`, as
    /// -systemLayoutSizeFittingSize: finds with a fixed width; nil when
    /// none bear on it.
    static func fittingHeight(_ view: UIView, width: CGFloat) -> CGFloat? {
        let constraints = constraints(of: view), stacks = stackViews(in: view)
        guard !constraints.isEmpty || !stacks.isEmpty else { return nil }
        let system = System(root: view)
        // The root's width is fixed and its height free, as small as can be.
        let root = Item(view, solved: false)
        system.items[view.objcObject] = root
        system.solver.add(LayoutExpression(root.x), .equal, strength: LayoutSolver.required)
        system.solver.add(LayoutExpression(root.y), .equal, strength: LayoutSolver.required)
        system.solver.add(LayoutExpression(root.width) + -width, .equal, strength: LayoutSolver.required)
        system.solver.add(LayoutExpression(root.height), .greaterOrEqual, strength: LayoutSolver.required)
        system.solver.add(LayoutExpression(root.height), .equal, strength: strength(50))
        for constraint in constraints { system.add(constraint) }
        for stack in stacks { system.arrange(stack) }
        system.solve()
        return root.height.value.rounded(.up)
    }
}

extension UIView {
    func isDescendant(of ancestor: UIView) -> Bool {
        var current = state.superview
        while let next = current {
            if next == ancestor.objcObject { return true }
            current = UIView.wrap(next).state.superview
        }
        return false
    }
}

extension CGRect {
    /// Aligned to the pixels drawn.
    func roundedToScale() -> CGRect {
        let scale = 1 / Screen.pixel
        func round(_ value: CGFloat) -> CGFloat { (value * scale).rounded() / scale }
        return CGRect(x: round(minX), y: round(minY), width: round(width), height: round(height))
    }
}

extension NSObject {
    @ObjCMethod("intrinsicContentSize") func sendIntrinsicContentSize() -> CGSize
    @ObjCMethod("layoutMargins") func sendLayoutMargins() -> UIEdgeInsets
}
