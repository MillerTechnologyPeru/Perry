import CPerryGeometry
import PerryObjCInterop

// UILayoutGuide, as nibs have them for safe areas and margins: a rectangle
// in its owning view. Perry lays views out by their frames and
// autoresizing, so a guide is its owning view's bounds.

final class LayoutGuideState: ObjectState {
    /// Not retained, as Darwin's is weak.
    var owningView: UnsafeMutableRawPointer?
    var identifier = ""
}

@ObjCClass("UILayoutGuide")
open class UILayoutGuide: NSObject {
    static let states = StateTable<LayoutGuideState>()
    var guide: LayoutGuideState { UILayoutGuide.states[objcObject] }

    @ObjCMethod("dealloc")
    func dealloc() {
        UILayoutGuide.states.remove(objcObject)
        ObjCRuntime.superDealloc(objcObject, definedOn: UILayoutGuide.objCClass.pointer)
    }

    @ObjCMethod("initWithCoder:")
    func initialize(coder: NSObject) -> Self {
        let decoded = Coder(coder: coder)
        guide.identifier = decoded.string("UILayoutGuideIdentifier") ?? decoded.string("identifier") ?? ""
        guide.owningView = decoded.object("UILayoutGuideOwningView")?.objcObject
        return self
    }

    @ObjCMethod("owningView")
    func owningView() -> UIView? { guide.owningView.map { UIView(objcObject: $0, ownership: .retain) } }
    @ObjCMethod("setOwningView:") func setOwningView(_ view: UIView?) { guide.owningView = view?.objcObject }
    @ObjCMethod("identifier") func identifier() -> String { guide.identifier }
    @ObjCMethod("setIdentifier:") func setIdentifier(_ identifier: String) { guide.identifier = identifier }
    @ObjCMethod("layoutFrame") func layoutFrame() -> CGRect { owningView()?.state.bounds ?? .zero }
}

// MARK: - A view's guides

/// What a guide stands for in its owning view.
enum LayoutGuideKind: Int {
    /// The owning view's bounds: a guide the app added.
    case custom
    /// The bounds inside the safe area.
    case safeArea
    /// The bounds inside the layout margins.
    case margins
}

final class ViewGuides: ObjectState {
    var safeArea: UILayoutGuide?
    var margins: UILayoutGuide?
    var readable: UILayoutGuide?
    var added: [UILayoutGuide] = []
}

extension UILayoutGuide {
    static func make(_ kind: LayoutGuideKind, identifier: String, in view: UIView) -> UILayoutGuide {
        let guide = objCClass.object.allocated().unsafeCast(to: UILayoutGuide.self)
        guide.guide.owningView = view.objcObject
        guide.guide.identifier = identifier
        return guide
    }

    /// The kind its identifier names, as UIKit names its own guides.
    var kind: LayoutGuideKind {
        let identifier = guide.identifier
        if identifier.hasPrefix("UIViewSafeAreaLayoutGuide") { return .safeArea }
        if identifier.hasPrefix("UIViewLayoutMarginsGuide") || identifier.hasPrefix("UIViewReadableContentGuide") { return .margins }
        return .custom
    }

    /// How far inside the owning view's bounds the guide's edges are.
    var insets: UIEdgeInsets {
        guard let view = owningView() else { return .zero }
        switch kind {
        case .custom: return .zero
        case .safeArea: return view.safeAreaInsets()
        case .margins: return view.sendLayoutMargins()
        }
    }

}

@ObjCCategory("Anchors")
extension UILayoutGuide {
    @ObjCMethod("leadingAnchor") func leadingAnchor() -> NSLayoutAnchor { NSLayoutAnchor.make(.x, objcObject, .leading) }
    @ObjCMethod("trailingAnchor") func trailingAnchor() -> NSLayoutAnchor { NSLayoutAnchor.make(.x, objcObject, .trailing) }
    @ObjCMethod("leftAnchor") func leftAnchor() -> NSLayoutAnchor { NSLayoutAnchor.make(.x, objcObject, .left) }
    @ObjCMethod("rightAnchor") func rightAnchor() -> NSLayoutAnchor { NSLayoutAnchor.make(.x, objcObject, .right) }
    @ObjCMethod("topAnchor") func topAnchor() -> NSLayoutAnchor { NSLayoutAnchor.make(.y, objcObject, .top) }
    @ObjCMethod("bottomAnchor") func bottomAnchor() -> NSLayoutAnchor { NSLayoutAnchor.make(.y, objcObject, .bottom) }
    @ObjCMethod("widthAnchor") func widthAnchor() -> NSLayoutAnchor { NSLayoutAnchor.make(.dimension, objcObject, .width) }
    @ObjCMethod("heightAnchor") func heightAnchor() -> NSLayoutAnchor { NSLayoutAnchor.make(.dimension, objcObject, .height) }
    @ObjCMethod("centerXAnchor") func centerXAnchor() -> NSLayoutAnchor { NSLayoutAnchor.make(.x, objcObject, .centerX) }
    @ObjCMethod("centerYAnchor") func centerYAnchor() -> NSLayoutAnchor { NSLayoutAnchor.make(.y, objcObject, .centerY) }
}

extension UIView {
    static let guides = StateTable<ViewGuides>()
}

@ObjCCategory("LayoutGuides")
extension UIView {

    /// The bounds clear of bars and the screen's corners and housing.
    @ObjCMethod("safeAreaLayoutGuide")
    func safeAreaLayoutGuide() -> UILayoutGuide {
        let guides = UIView.guides[objcObject]
        if let guide = guides.safeArea { return guide }
        let guide = UILayoutGuide.make(.safeArea, identifier: "UIViewSafeAreaLayoutGuide", in: self)
        guides.safeArea = guide
        return guide
    }

    @ObjCMethod("layoutMarginsGuide")
    func layoutMarginsGuide() -> UILayoutGuide {
        let guides = UIView.guides[objcObject]
        if let guide = guides.margins { return guide }
        let guide = UILayoutGuide.make(.margins, identifier: "UIViewLayoutMarginsGuide", in: self)
        guides.margins = guide
        return guide
    }

    /// The margins: text here is never wider than is readable.
    @ObjCMethod("readableContentGuide")
    func readableContentGuide() -> UILayoutGuide {
        let guides = UIView.guides[objcObject]
        if let guide = guides.readable { return guide }
        let guide = UILayoutGuide.make(.margins, identifier: "UIViewReadableContentGuide", in: self)
        guides.readable = guide
        return guide
    }

    @ObjCMethod("layoutGuides") func layoutGuides() -> NSObject { NSMutableArray.of(UIView.guides[objcObject].added) }

    @ObjCMethod("addLayoutGuide:")
    func addLayoutGuide(_ guide: UILayoutGuide) {
        let guides = UIView.guides[objcObject]
        guard !guides.added.contains(where: { $0.objcObject == guide.objcObject }) else { return }
        guide.guide.owningView = objcObject
        guides.added.append(guide)
    }

    @ObjCMethod("removeLayoutGuide:")
    func removeLayoutGuide(_ guide: UILayoutGuide) {
        let guides = UIView.guides[objcObject]
        guides.added.removeAll { $0.objcObject == guide.objcObject }
        if guide.guide.owningView == objcObject { guide.guide.owningView = nil }
    }

    @ObjCMethod("leadingAnchor") func leadingAnchor() -> NSLayoutAnchor { NSLayoutAnchor.make(.x, objcObject, .leading) }
    @ObjCMethod("trailingAnchor") func trailingAnchor() -> NSLayoutAnchor { NSLayoutAnchor.make(.x, objcObject, .trailing) }
    @ObjCMethod("leftAnchor") func leftAnchor() -> NSLayoutAnchor { NSLayoutAnchor.make(.x, objcObject, .left) }
    @ObjCMethod("rightAnchor") func rightAnchor() -> NSLayoutAnchor { NSLayoutAnchor.make(.x, objcObject, .right) }
    @ObjCMethod("topAnchor") func topAnchor() -> NSLayoutAnchor { NSLayoutAnchor.make(.y, objcObject, .top) }
    @ObjCMethod("bottomAnchor") func bottomAnchor() -> NSLayoutAnchor { NSLayoutAnchor.make(.y, objcObject, .bottom) }
    @ObjCMethod("widthAnchor") func widthAnchor() -> NSLayoutAnchor { NSLayoutAnchor.make(.dimension, objcObject, .width) }
    @ObjCMethod("heightAnchor") func heightAnchor() -> NSLayoutAnchor { NSLayoutAnchor.make(.dimension, objcObject, .height) }
    @ObjCMethod("centerXAnchor") func centerXAnchor() -> NSLayoutAnchor { NSLayoutAnchor.make(.x, objcObject, .centerX) }
    @ObjCMethod("centerYAnchor") func centerYAnchor() -> NSLayoutAnchor { NSLayoutAnchor.make(.y, objcObject, .centerY) }
    @ObjCMethod("firstBaselineAnchor") func firstBaselineAnchor() -> NSLayoutAnchor { NSLayoutAnchor.make(.y, objcObject, .firstBaseline) }
    @ObjCMethod("lastBaselineAnchor") func lastBaselineAnchor() -> NSLayoutAnchor { NSLayoutAnchor.make(.y, objcObject, .lastBaseline) }
}

/// What a constraint's item is: a view, or a guide in the view that owns it.
enum LayoutItems {
    /// The view to lay out by, and for a guide its insets in that view.
    static func resolve(_ object: UnsafeMutableRawPointer) -> (view: UIView, insets: UIEdgeInsets?)? {
        let view = UIView.wrap(object)
        if view.is(UIView.self) { return (view, nil) }
        guard let guide = NSObject(object).as(UILayoutGuide.self), let owner = guide.owningView() else { return nil }
        return (owner, guide.insets)
    }
}

// MARK: - Anchors

final class LayoutAnchorState: ObjectState {
    /// Not retained, as a constraint's items are not.
    var item: UnsafeMutableRawPointer?
    var attribute = AutoLayout.Attribute.notAnAttribute
}

/// An edge, center or size of a view or guide, which makes constraints to
/// others of its kind: NSLayoutXAxisAnchor, NSLayoutYAxisAnchor and
/// NSLayoutDimension.
@ObjCClass("NSLayoutAnchor")
open class NSLayoutAnchor: NSObject {
    enum Axis { case x, y, dimension }

    static let states = StateTable<LayoutAnchorState>()
    var anchor: LayoutAnchorState { NSLayoutAnchor.states[objcObject] }

    static func make(_ axis: Axis, _ item: UnsafeMutableRawPointer, _ attribute: AutoLayout.Attribute) -> NSLayoutAnchor {
        let cls: ObjCClass
        switch axis {
        case .x: cls = NSLayoutXAxisAnchor.objCClass
        case .y: cls = NSLayoutYAxisAnchor.objCClass
        case .dimension: cls = NSLayoutDimension.objCClass
        }
        let anchor = cls.object.allocated().unsafeCast(to: NSLayoutAnchor.self)
        (anchor.anchor.item, anchor.anchor.attribute) = (item, attribute)
        return anchor
    }

    @ObjCMethod("dealloc")
    func dealloc() {
        NSLayoutAnchor.states.remove(objcObject)
        ObjCRuntime.superDealloc(objcObject, definedOn: NSLayoutAnchor.objCClass.pointer)
    }

    @ObjCMethod("item") func item() -> NSObject? { anchor.item.map { NSObject($0) } }

    /// A constraint, not yet active, of this anchor to another (or to a
    /// constant alone).
    func constraint(_ relation: Int, to other: NSLayoutAnchor?, multiplier: CGFloat = 1, constant: CGFloat = 0) -> NSLayoutConstraint {
        let constraint = NSLayoutConstraint.objCClass.object.allocated().unsafeCast(to: NSLayoutConstraint.self)
        let state = constraint.state
        (state.firstItem, state.firstAttribute, state.relation) = (anchor.item, anchor.attribute.rawValue, relation)
        (state.secondItem, state.secondAttribute) = (other?.anchor.item, other?.anchor.attribute.rawValue ?? 0)
        (state.multiplier, state.constant) = (multiplier, constant)
        return constraint
    }

    @ObjCMethod("constraintEqualToAnchor:")
    func constraint(equalTo other: NSLayoutAnchor) -> NSLayoutConstraint { constraint(0, to: other) }
    @ObjCMethod("constraintGreaterThanOrEqualToAnchor:")
    func constraint(greaterThanOrEqualTo other: NSLayoutAnchor) -> NSLayoutConstraint { constraint(1, to: other) }
    @ObjCMethod("constraintLessThanOrEqualToAnchor:")
    func constraint(lessThanOrEqualTo other: NSLayoutAnchor) -> NSLayoutConstraint { constraint(-1, to: other) }
    @ObjCMethod("constraintEqualToAnchor:constant:")
    func constraint(equalTo other: NSLayoutAnchor, constant: CGFloat) -> NSLayoutConstraint { constraint(0, to: other, constant: constant) }
    @ObjCMethod("constraintGreaterThanOrEqualToAnchor:constant:")
    func constraint(greaterThanOrEqualTo other: NSLayoutAnchor, constant: CGFloat) -> NSLayoutConstraint {
        constraint(1, to: other, constant: constant)
    }
    @ObjCMethod("constraintLessThanOrEqualToAnchor:constant:")
    func constraint(lessThanOrEqualTo other: NSLayoutAnchor, constant: CGFloat) -> NSLayoutConstraint {
        constraint(-1, to: other, constant: constant)
    }
}

/// The system's spacing between related views, in points.
private let systemSpacing: CGFloat = 8

@ObjCClass("NSLayoutXAxisAnchor")
open class NSLayoutXAxisAnchor: NSLayoutAnchor {
    @ObjCMethod("constraintEqualToSystemSpacingAfterAnchor:multiplier:")
    func constraint(equalToSystemSpacingAfter other: NSLayoutAnchor, multiplier: CGFloat) -> NSLayoutConstraint {
        constraint(0, to: other, constant: systemSpacing * multiplier)
    }
    @ObjCMethod("constraintGreaterThanOrEqualToSystemSpacingAfterAnchor:multiplier:")
    func constraint(greaterThanOrEqualToSystemSpacingAfter other: NSLayoutAnchor, multiplier: CGFloat) -> NSLayoutConstraint {
        constraint(1, to: other, constant: systemSpacing * multiplier)
    }
    @ObjCMethod("constraintLessThanOrEqualToSystemSpacingAfterAnchor:multiplier:")
    func constraint(lessThanOrEqualToSystemSpacingAfter other: NSLayoutAnchor, multiplier: CGFloat) -> NSLayoutConstraint {
        constraint(-1, to: other, constant: systemSpacing * multiplier)
    }
}

@ObjCClass("NSLayoutYAxisAnchor")
open class NSLayoutYAxisAnchor: NSLayoutAnchor {
    @ObjCMethod("constraintEqualToSystemSpacingBelowAnchor:multiplier:")
    func constraint(equalToSystemSpacingBelow other: NSLayoutAnchor, multiplier: CGFloat) -> NSLayoutConstraint {
        constraint(0, to: other, constant: systemSpacing * multiplier)
    }
    @ObjCMethod("constraintGreaterThanOrEqualToSystemSpacingBelowAnchor:multiplier:")
    func constraint(greaterThanOrEqualToSystemSpacingBelow other: NSLayoutAnchor, multiplier: CGFloat) -> NSLayoutConstraint {
        constraint(1, to: other, constant: systemSpacing * multiplier)
    }
    @ObjCMethod("constraintLessThanOrEqualToSystemSpacingBelowAnchor:multiplier:")
    func constraint(lessThanOrEqualToSystemSpacingBelow other: NSLayoutAnchor, multiplier: CGFloat) -> NSLayoutConstraint {
        constraint(-1, to: other, constant: systemSpacing * multiplier)
    }
}

@ObjCClass("NSLayoutDimension")
open class NSLayoutDimension: NSLayoutAnchor {
    @ObjCMethod("constraintEqualToConstant:")
    func constraint(equalToConstant constant: CGFloat) -> NSLayoutConstraint { constraint(0, to: nil, constant: constant) }
    @ObjCMethod("constraintGreaterThanOrEqualToConstant:")
    func constraint(greaterThanOrEqualToConstant constant: CGFloat) -> NSLayoutConstraint { constraint(1, to: nil, constant: constant) }
    @ObjCMethod("constraintLessThanOrEqualToConstant:")
    func constraint(lessThanOrEqualToConstant constant: CGFloat) -> NSLayoutConstraint { constraint(-1, to: nil, constant: constant) }

    @ObjCMethod("constraintEqualToAnchor:multiplier:")
    func constraint(equalTo other: NSLayoutAnchor, multiplier: CGFloat) -> NSLayoutConstraint { constraint(0, to: other, multiplier: multiplier) }
    @ObjCMethod("constraintGreaterThanOrEqualToAnchor:multiplier:")
    func constraint(greaterThanOrEqualTo other: NSLayoutAnchor, multiplier: CGFloat) -> NSLayoutConstraint {
        constraint(1, to: other, multiplier: multiplier)
    }
    @ObjCMethod("constraintLessThanOrEqualToAnchor:multiplier:")
    func constraint(lessThanOrEqualTo other: NSLayoutAnchor, multiplier: CGFloat) -> NSLayoutConstraint {
        constraint(-1, to: other, multiplier: multiplier)
    }
    @ObjCMethod("constraintEqualToAnchor:multiplier:constant:")
    func constraint(equalTo other: NSLayoutAnchor, multiplier: CGFloat, constant: CGFloat) -> NSLayoutConstraint {
        constraint(0, to: other, multiplier: multiplier, constant: constant)
    }
    @ObjCMethod("constraintGreaterThanOrEqualToAnchor:multiplier:constant:")
    func constraint(greaterThanOrEqualTo other: NSLayoutAnchor, multiplier: CGFloat, constant: CGFloat) -> NSLayoutConstraint {
        constraint(1, to: other, multiplier: multiplier, constant: constant)
    }
    @ObjCMethod("constraintLessThanOrEqualToAnchor:multiplier:constant:")
    func constraint(lessThanOrEqualTo other: NSLayoutAnchor, multiplier: CGFloat, constant: CGFloat) -> NSLayoutConstraint {
        constraint(-1, to: other, multiplier: multiplier, constant: constant)
    }
}
