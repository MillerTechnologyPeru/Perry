import CPerryGeometry
import PerryObjCInterop

// UICollectionReusableView and UICollectionViewCell: a cell's content view
// fills it, in front of its background view, and the selected background
// view shows while it is selected or highlighted.

final class ReusableViewState: ObjectState {
    var reuseIdentifier: String?
}

@ObjCClass("UICollectionReusableView")
open class UICollectionReusableView: UIView {
    static let reusableStates = StateTable<ReusableViewState>()
    var reusable: ReusableViewState { UICollectionReusableView.reusableStates[objcObject] }

    @ObjCMethod("initWithCoder:")
    override func initialize(coder: NSObject) -> Self {
        _ = super.initialize(coder: coder)
        reusable.reuseIdentifier = Coder(coder: coder).string("UIReuseIdentifier")
        return self
    }

    @ObjCMethod("dealloc")
    override func dealloc() {
        UICollectionReusableView.reusableStates.remove(objcObject)
        super.dealloc()
    }

    @ObjCMethod("reuseIdentifier") func reuseIdentifier() -> String? { reusable.reuseIdentifier }
    @ObjCMethod("prepareForReuse") func prepareForReuse() {}
    @ObjCMethod("applyLayoutAttributes:") func apply(_ attributes: NSObject?) {}
    @ObjCMethod("preferredLayoutAttributesFittingAttributes:")
    func preferredLayoutAttributes(fitting attributes: NSObject?) -> NSObject? { attributes }
}

final class CollectionCellState: ObjectState {
    var contentView: UIView?
    var backgroundView: UIView?
    var selectedBackgroundView: UIView?
    var selected = false
    var highlighted = false
}

@ObjCClass("UICollectionViewCell")
open class UICollectionViewCell: UICollectionReusableView {
    static let cellStates = StateTable<CollectionCellState>()
    var collectionCell: CollectionCellState { UICollectionViewCell.cellStates[objcObject] }

    @ObjCMethod("initWithFrame:")
    override func initialize(frame: CGRect) -> Self {
        _ = super.initialize(frame: frame)
        makeContentView()
        return self
    }

    @ObjCMethod("initWithCoder:")
    override func initialize(coder: NSObject) -> Self {
        _ = super.initialize(coder: coder)
        let decoded = Coder(coder: coder)
        let cell = collectionCell
        cell.contentView = decoded.object("UIContentView")?.as(UIView.self)
        cell.backgroundView = decoded.object("UIBackgroundView")?.as(UIView.self)
        cell.selectedBackgroundView = decoded.object("UISelectedBackgroundView")?.as(UIView.self)
        if cell.contentView == nil { makeContentView() }
        return self
    }

    private func makeContentView() {
        guard collectionCell.contentView == nil else { return }
        let content = UIView.objCClass.object.allocated().initializeView(frame: state.bounds).unsafeCast(to: UIView.self)
        content.setAutoresizingMask(18)
        collectionCell.contentView = content
        addSubview(content)
    }

    @ObjCMethod("dealloc")
    override func dealloc() {
        UICollectionViewCell.cellStates.remove(objcObject)
        super.dealloc()
    }

    @ObjCMethod("contentView") func contentView() -> UIView? { collectionCell.contentView }
    @ObjCMethod("backgroundView") func backgroundView() -> UIView? { collectionCell.backgroundView }
    @ObjCMethod("setBackgroundView:")
    func setBackgroundView(_ view: UIView?) {
        collectionCell.backgroundView?.removeFromSuperview()
        collectionCell.backgroundView = view
        if let view { insertSubview(view, at: 0) }
        setNeedsLayout()
    }
    @ObjCMethod("selectedBackgroundView") func selectedBackgroundView() -> UIView? { collectionCell.selectedBackgroundView }
    @ObjCMethod("setSelectedBackgroundView:")
    func setSelectedBackgroundView(_ view: UIView?) {
        collectionCell.selectedBackgroundView?.removeFromSuperview()
        collectionCell.selectedBackgroundView = view
        showSelection()
    }
    @ObjCMethod("isSelected") func isSelected() -> Bool { collectionCell.selected }
    @ObjCMethod("setSelected:") func setSelected(_ selected: Bool) { collectionCell.selected = selected; showSelection() }
    @ObjCMethod("isHighlighted") func isHighlighted() -> Bool { collectionCell.highlighted }
    @ObjCMethod("setHighlighted:") func setHighlighted(_ highlighted: Bool) { collectionCell.highlighted = highlighted; showSelection() }

    /// The selected background view, behind the content, while selected or highlighted.
    private func showSelection() {
        guard let view = collectionCell.selectedBackgroundView else { return }
        if collectionCell.selected || collectionCell.highlighted {
            if let content = collectionCell.contentView { insertSubview(view, below: content) } else { addSubview(view) }
        } else {
            view.removeFromSuperview()
        }
        setNeedsLayout()
    }

    @ObjCMethod("layoutSubviews")
    override func layoutSubviews() {
        let bounds = state.bounds
        collectionCell.backgroundView?.sendSetFrame(bounds)
        collectionCell.selectedBackgroundView?.sendSetFrame(bounds)
        collectionCell.contentView?.sendSetFrame(bounds)
        super.layoutSubviews()
    }
}
