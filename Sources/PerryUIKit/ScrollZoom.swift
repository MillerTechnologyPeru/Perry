import CPerryGeometry
import Glibc
import PerryObjCInterop

// UIScrollView's zooming: the delegate's -viewForZoomingInScrollView: is
// scaled by its transform to the zoom scale, its frame's origin at the
// content's, and the content size follows its frame. A pinch with two
// fingers zooms about their midpoint, the content under it staying under
// it, a little past the minimum and maximum scales when the scroll view
// bounces zoom, springing back when the fingers lift. The delegate hears
// that zooming will begin, that the scroll view zoomed with each change,
// and that zooming ended, at what scale.

extension UIScrollView {
    /// The delegate's view to zoom, when the scales allow zooming.
    func zoomingView() -> UIView? {
        guard let delegate = delegate(), delegate.responds(to: "viewForZoomingInScrollView:") else { return nil }
        return delegate.sendViewForZooming(in: self)
    }

    var canZoom: Bool { scroll.maximumZoomScale > scroll.minimumZoomScale && zoomingView() != nil }

    /// Scales the zooming view to `scale`, keeping the point of the content
    /// at `anchor` in the view's bounds (the visible part) where it is; the
    /// delegate hears the scroll view zoomed. Without an anchor, the offset
    /// stays as it is.
    func applyZoom(_ scale: CGFloat, keeping anchor: CGPoint? = nil) {
        let scroll = scroll
        guard scale > 0, let view = zoomingView() else {
            scroll.zoomScale = scale
            return
        }
        let old = scroll.zoomScale, offset = state.bounds.origin
        scroll.zoomScale = scale
        view.setTransform(CGAffineTransform(a: scale, b: 0, c: 0, d: scale, tx: 0, ty: 0))
        let size = CGSize(width: view.state.bounds.width * scale, height: view.state.bounds.height * scale)
        view.setCenter(CGPoint(x: size.width / 2, y: size.height / 2))
        scroll.contentSize = size
        if let anchor, old > 0 {
            // The content point under the anchor, before and after.
            let content = CGPoint(x: (offset.x + anchor.x) / old, y: (offset.y + anchor.y) / old)
            sendSetContentOffset(CGPoint(x: content.x * scale - anchor.x, y: content.y * scale - anchor.y))
        }
        if let delegate = delegate(), delegate.responds(to: "scrollViewDidZoom:") { delegate.sendScrollViewDidZoom(self) }
        layOutIndicators()
        Updates.schedule()
    }

    /// The scale within the minimum and maximum.
    func clampedZoom(_ scale: CGFloat) -> CGFloat { min(max(scale, scroll.minimumZoomScale), scroll.maximumZoomScale) }

    /// A pinch's scale: past the limits only a little, and only when zoom
    /// bounces.
    func bandedZoom(_ scale: CGFloat) -> CGFloat {
        let low = scroll.minimumZoomScale, high = scroll.maximumZoomScale
        guard scroll.bouncesZoom else { return clampedZoom(scale) }
        if scale < low { return low * pow(scale / low, 0.3) }
        if scale > high { return high * pow(scale / high, 0.3) }
        return scale
    }

    func willBeginZooming() {
        scroll.zooming = true
        guard let delegate = delegate(), delegate.responds(to: "scrollViewWillBeginZooming:withView:") else { return }
        delegate.sendScrollViewWillBeginZooming(self, with: zoomingView())
    }

    func didEndZooming() {
        scroll.zooming = false
        guard let delegate = delegate(), delegate.responds(to: "scrollViewDidEndZooming:withView:atScale:") else { return }
        delegate.sendScrollViewDidEndZooming(self, with: zoomingView(), atScale: scroll.zoomScale)
    }

    /// From `from` to `to` over a quarter second about `anchor`, then the
    /// offset back within the content; at once without a live view.
    func animateZoom(to scale: CGFloat, keeping anchor: CGPoint?, completion: @escaping () -> Void = {}) {
        let from = scroll.zoomScale
        guard Animations.live, from != scale else {
            applyZoom(scale, keeping: anchor)
            clampOffset()
            return completion()
        }
        let object = objcObject
        Animations.run(duration: 0.25, { progress in
            let view = UIScrollView(objcObject: object, ownership: .retain)
            view.applyZoom(from + (scale - from) * progress, keeping: anchor)
        }, completion: {
            let view = UIScrollView(objcObject: object, ownership: .retain)
            view.clampOffset()
            completion()
        })
    }

    /// The offset within the content, as after a zoom.
    func clampOffset() {
        let bounds = state.bounds, inset = adjustedContentInset(), size = scroll.contentSize
        let maxX = max(-inset.left, size.width + inset.right - bounds.width)
        let maxY = max(-inset.top, size.height + inset.bottom - bounds.height)
        let offset = CGPoint(x: min(max(bounds.minX, -inset.left), maxX), y: min(max(bounds.minY, -inset.top), maxY))
        if offset != bounds.origin { sendSetContentOffset(offset) }
    }

    /// Zooms so `rect`, in the zooming view's coordinates, fills the view
    /// as far as the scales allow, and shows it.
    @ObjCMethod("zoomToRect:animated:")
    func zoom(to rect: CGRect, animated: Bool) {
        guard rect.width > 0, rect.height > 0, zoomingView() != nil else { return }
        let bounds = state.bounds
        let scale = clampedZoom(min(bounds.width / rect.width, bounds.height / rect.height))
        let object = objcObject
        let finish = {
            let view = UIScrollView(objcObject: object, ownership: .retain)
            let target = CGPoint(x: rect.midX * scale - bounds.width / 2, y: rect.midY * scale - bounds.height / 2)
            view.sendSetContentOffset(target)
            view.clampOffset()
        }
        willBeginZooming()
        if animated {
            animateZoom(to: scale, keeping: nil) {
                finish()
                UIScrollView(objcObject: object, ownership: .retain).didEndZooming()
            }
        } else {
            applyZoom(scale)
            finish()
            didEndZooming()
        }
    }
}

/// The scroll view delegate's zooming messages.
extension NSObject {
    @ObjCMethod("viewForZoomingInScrollView:") func sendViewForZooming(in scrollView: UIScrollView) -> UIView?
    @ObjCMethod("scrollViewDidZoom:") func sendScrollViewDidZoom(_ scrollView: UIScrollView)
    @ObjCMethod("scrollViewWillBeginZooming:withView:") func sendScrollViewWillBeginZooming(_ scrollView: UIScrollView, with view: UIView?)
    @ObjCMethod("scrollViewDidEndZooming:withView:atScale:")
    func sendScrollViewDidEndZooming(_ scrollView: UIScrollView, with view: UIView?, atScale scale: CGFloat)
}
