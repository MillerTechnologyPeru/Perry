import CPerryGeometry
import PerryObjCInterop

// What a collection view list section (UICollectionLayoutListConfiguration)
// draws on its rows: an inset grouped section's rounded card, its first and
// last cells' outer corners, and the separators its configuration asks for,
// at the top and bottom of the cells, inside their insets.

/// Where a cell was when a list section last styled it.
struct ListCellPlace: Equatable {
    var section: Int
    var row: Int
    var count: Int
    var size: CGSize
}

enum ListMetrics {
    /// As iOS's cards have them for apps built with the iOS 26 SDK and before.
    static var cornerRadius: CGFloat { ProgramSDK.iOS26Design ? 26 : 10 }
    static var separatorHeight: CGFloat { ProgramSDK.iOS26Design ? 1 : Screen.pixel }
}

extension UICollectionView {
    /// Styles the cell for its place in a list section, when that has
    /// changed.
    func applyListStyle(to cell: UICollectionViewCell, at path: RowPath) {
        guard let layout = collection.layout?.as(UICollectionViewCompositionalLayout.self),
              layout.compositional.sections.indices.contains(path.section),
              let list = layout.compositional.sections[path.section].list else { return }
        let count = numberOfItems(inSection: path.section)
        let place = ListCellPlace(section: path.section, row: path.row, count: count, size: cell.state.bounds.size)
        guard cell.collectionCell.listPlace != place else { return }
        cell.collectionCell.listPlace = place

        if list.listRounded {
            // CACornerMask: the top two, 3, and the bottom two, 12.
            let corners: UInt = (path.row == 0 ? 3 : 0) | (path.row == count - 1 ? 12 : 0)
            cell.state.layer.setCornerRadius(corners == 0 ? 0 : ListMetrics.cornerRadius)
            cell.state.layer.setMaskedCorners(corners)
            cell.state.layer.setMasksToBounds(true)
        }
        guard let block = list.listSeparators else { return }
        typealias Invoke = @convention(c) (UnsafeMutableRawPointer, Int, Int, Int) -> UIEdgeInsets
        // Top leading and trailing as top and left, bottom's as bottom and
        // right; a leading inset below 0 is no separator.
        let insets = block.function(as: Invoke.self)(block.object, path.section, path.row, count)
        let size = place.size, height = ListMetrics.separatorHeight
        cell.collectionCell.topSeparator = separator(
            cell.collectionCell.topSeparator, in: cell, leading: insets.top, trailing: insets.left, y: 0, size: size)
        cell.collectionCell.bottomSeparator = separator(
            cell.collectionCell.bottomSeparator, in: cell, leading: insets.bottom, trailing: insets.right, y: size.height - height, size: size)
    }

    private func separator(_ existing: UIView?, in cell: UICollectionViewCell, leading: CGFloat, trailing: CGFloat, y: CGFloat, size: CGSize) -> UIView? {
        guard leading >= 0 else {
            existing?.setHidden(true)
            return existing
        }
        let line = existing ?? {
            let made = UIView.objCClass.object.allocated().initializeView(frame: .zero).unsafeCast(to: UIView.self)
            made.setBackgroundColor(UIColor.separator())
            made.setUserInteractionEnabled(false)
            cell.addSubview(made)
            return made
        }()
        line.setHidden(false)
        line.sendSetFrame(CGRect(x: leading, y: y, width: max(size.width - leading - trailing, 0), height: ListMetrics.separatorHeight))
        return line
    }
}
